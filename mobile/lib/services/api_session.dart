import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/api_models.dart';
import '../models/content_create_request.dart';
import '../models/location_radius_policy.dart';
import 'access_status.dart';
import 'api_service.dart';
import 'device_location.dart';

enum OwnerControlAction {
  pause,
  resume,
  revoke,
  editViewingArea,
  editViewingTime,
}

enum OwnerControlPhase {
  pending,
  confirmed,
  notDispatched,
  rejected,
  unconfirmed,
}

/// Account-scoped memory only. No passwords, bearer tokens or content payloads
/// are persisted. Epochs apply to success AND failure completions.
class ApiSession extends ChangeNotifier {
  final ApiService api;
  final DateTime Function() now;
  final String? deviceKey;
  final accessStatuses = AccessStatusFeed();
  ApiSession(this.api, {DateTime Function()? now, this.deviceKey})
    : now = now ?? DateTime.now;

  ApiCredentials? _credentials;
  Timer? _expiry;
  bool _disposed = false;
  int _epoch = 0, _identityVersion = 0, _listEpoch = 0;
  bool signingIn = false, loading = false;
  bool _registeringAccount = false;
  ApiException? error;
  String? logoutWarning;
  bool _hasContentListing = false;
  ApiException? _contentListingError;
  List<ApiContent> _items = const [];
  List<ApiContent> _listedItems = const [];
  final Set<int> _confirmedRevoked = {};
  // A route exit or reauthentication cannot resolve a possibly dispatched
  // mutation. Only the issuing account can see its pending or unknown state.
  final _ownerControls =
      <(int, int), (OwnerControlAction, OwnerControlPhase)>{};
  static const _unconfirmedEndFailures = {
    ApiFailure.network,
    ApiFailure.timeout,
    ApiFailure.server,
    ApiFailure.malformed,
  };
  final Set<int> _viewingSessions = {};
  final Set<Future<ApiAccessDecision>> _viewingOpens = {};
  final _viewingCleanup = <(String, int), Future<void>>{};
  final Set<Future<void>> _logins = {}, _retiring = {};
  final _uploads = <int, ApiRequestCancellation>{};
  // Keep only the account ID until this session object is disposed. Signing
  // out and back in is not evidence that an unacknowledged write failed.
  final _unconfirmedUploads = <int>{};

  bool get authenticated =>
      !_disposed &&
      _credentials != null &&
      _credentials!.expiresAt.isAfter(now().toUtc());
  ApiUser? get user => authenticated ? _credentials!.user : null;
  int get identityVersion => _identityVersion;
  List<ApiContent> get items => _items;
  bool get hasContentListing => _hasContentListing;
  bool get registeringAccount => _registeringAccount;
  ApiException? get contentListingError => _contentListingError;
  (OwnerControlAction, OwnerControlPhase)? ownerControl(int id) =>
      _ownerControls[(user?.id, id)];
  bool ownerControlUnconfirmed(int id) =>
      ownerControl(id)?.$2 == OwnerControlPhase.unconfirmed;
  bool pending(int id) => ownerControl(id)?.$2 == OwnerControlPhase.pending;
  Iterable<ApiContent> listedOwnerItems(int id) => authenticated
      ? _listedItems.where((item) => item.id == id && item.mine)
      : const [];
  bool get uploadPending => _uploads.containsKey(user?.id);
  bool get uploadNeedsReconciliation => _unconfirmedUploads.contains(user?.id);

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _clear() {
    final old = _credentials;
    if (old != null) _uploads[old.user.id]?.cancel();
    ++_epoch;
    ++_identityVersion;
    ++_listEpoch;
    _expiry?.cancel();
    _credentials = null;
    _items = const [];
    _listedItems = const [];
    _hasContentListing = false;
    _contentListingError = null;
    accessStatuses.clear();
    _confirmedRevoked.clear();
    _ownerControls.removeWhere(
      (_, state) =>
          state.$2 == OwnerControlPhase.confirmed ||
          state.$2 == OwnerControlPhase.notDispatched ||
          state.$2 == OwnerControlPhase.rejected,
    );
    signingIn = loading = false;
    error = null;
    final ending = _endKnownViewing(old);
    _emit();
    return ending;
  }

  Future<void> _endKnownViewing(ApiCredentials? owner) async {
    final sessions = _viewingSessions.toList();
    _viewingSessions.clear();
    if (owner == null) return;
    await Future.wait([
      for (final id in sessions) _endBeforeRetiring(owner.token, id),
    ]);
  }

  Future<void> _endBeforeRetiring(String token, int id) async {
    // If the route has already started cleanup, wait for it before trying
    // once more on an unconfirmed result.
    final pending = _viewingCleanup[(token, id)];
    if (pending != null) {
      try {
        await pending;
        return;
      } on ApiException catch (error) {
        if (!_unconfirmedEndFailures.contains(error.kind)) return;
      }
    }
    await _settled(_endWithToken(token, id));
  }

  Future<void> _endWithToken(String token, int id) {
    final key = (token, id);
    return _viewingCleanup.putIfAbsent(key, () async {
      try {
        await api.end(token, id);
      } on ApiException catch (error) {
        // End returns 404 when the issuing account has no such active session.
        if (error.kind != ApiFailure.notFound) rethrow;
      } finally {
        _viewingCleanup.remove(key);
      }
    });
  }

  bool _current(int ticket) => !_disposed && ticket == _epoch;

  /// Reconcile the existing absolute deadline if the timer is delayed.
  void expireCredentialsIfNeeded() {
    if (!_disposed && _credentials != null && !authenticated) {
      unawaited(_clear());
    }
  }

  Future<void> _track(Future<void> work, Set<Future<void>> pending) {
    late final Future<void> tracked;
    tracked = work.whenComplete(() => pending.remove(tracked));
    pending.add(tracked);
    return tracked;
  }

  static Future<void> _settled<T>(Future<T> work) =>
      work.then<void>((_) {}, onError: (Object _) {});

  Future<void> login(String username, String password) =>
      _track(_login(username, password), _logins);

  Future<void> registerAccount({
    required String firstName,
    required String lastName,
    required String username,
    required String password,
  }) async {
    if (_disposed || authenticated || signingIn) {
      throw const ApiException(ApiFailure.stale);
    }
    if (_registeringAccount) throw const ApiException(ApiFailure.pending);
    final ticket = _epoch;
    _registeringAccount = true;
    _emit();
    try {
      await api.registerAccount(
        firstName: firstName,
        lastName: lastName,
        username: username,
        password: password,
      );
      if (!_current(ticket)) throw const ApiException(ApiFailure.stale);
    } finally {
      _registeringAccount = false;
      _emit();
    }
  }

  Future<void> _login(String username, String password) async {
    if (_disposed) throw const ApiException(ApiFailure.stale);
    if (signingIn) throw const ApiException(ApiFailure.pending);
    if (username.trim().isEmpty || password.trim().isEmpty) {
      throw const ApiException(ApiFailure.invalidRequest);
    }
    // A new sign-in is an account boundary even when used directly by a caller.
    if (_credentials != null) unawaited(logout());
    final ticket = ++_epoch;
    signingIn = true;
    error = null;
    logoutWarning = null;
    _emit();
    ApiCredentials? candidate;
    try {
      candidate = await api.login(username.trim(), password);
      if (!_current(ticket)) throw const ApiException(ApiFailure.stale);
      if (!candidate.expiresAt.isAfter(now().toUtc())) {
        throw const ApiException(ApiFailure.credentials);
      }
      final me = await api.currentUser(candidate.token);
      if (!_current(ticket)) throw const ApiException(ApiFailure.stale);
      if (me.id != candidate.user.id ||
          me.username != candidate.user.username ||
          (api.usesClassroomHttp && me.username != username.trim())) {
        throw const ApiException(ApiFailure.malformed);
      }
      // Verify expiry again: current-user lookup may have outlasted the token.
      if (!candidate.expiresAt.isAfter(now().toUtc())) {
        throw const ApiException(ApiFailure.credentials);
      }
      _credentials = candidate;
      ++_identityVersion;
      _expiry = Timer(candidate.expiresAt.difference(now().toUtc()), () {
        if (_current(ticket)) unawaited(_clear());
      });
    } on ApiException catch (e) {
      if (candidate != null) {
        unawaited(_track(_settled(api.logout(candidate.token)), _retiring));
      }
      if (!_current(ticket)) throw const ApiException(ApiFailure.stale);
      error = e;
      rethrow;
    } finally {
      if (_current(ticket)) {
        signingIn = false;
        _emit();
      }
    }
  }

  void cancelLogin() {
    if (!signingIn || _disposed) return;
    ++_epoch;
    signingIn = false;
    error = null;
    _emit();
  }

  Future<void> logout() => _track(_logout(), _retiring);

  Future<void> _logout() async {
    if (_disposed || (_credentials == null && !signingIn)) return;
    final old = _credentials;
    final opens = _viewingOpens.toList();
    final cleanup = _viewingCleanup.values.toList();
    // Revoke local identity, data and routes before network completion.
    final ending = _clear();
    final ticket = _epoch;
    if (old == null) return;
    try {
      // A late open may still have created a session. Give its cleanup the
      // issuing token before invalidating that token on the server.
      await Future.wait([
        ending,
        for (final open in opens) _settled(open),
        for (final end in cleanup) _settled(end),
      ]);
      await api.logout(old.token);
    } on ApiException {
      if (_current(ticket)) {
        logoutWarning =
            'Signed out locally. Server sign-out could not be confirmed.';
        _emit();
      }
    }
  }

  Future<T> _authorized<T>(
    Future<T> Function(String) action, {
    void Function(T result)? accept,
    Future<void> Function(T result, String oldToken)? discard,
    bool Function()? isCurrent,
  }) async {
    if (isCurrent?.call() == false) throw const ApiException(ApiFailure.stale);
    if (!authenticated) {
      if (_credentials != null) unawaited(_clear());
      throw const ApiException(ApiFailure.credentials);
    }
    final ticket = _epoch;
    final token = _credentials!.token;
    try {
      final result = await action(token);
      if (!_current(ticket) || !authenticated || isCurrent?.call() == false) {
        if (_current(ticket) && isCurrent?.call() != false && !authenticated) {
          unawaited(_clear());
        }
        if (discard != null) await discard(result, token);
        throw const ApiException(ApiFailure.stale);
      }
      accept?.call(result);
      return result;
    } on ApiException catch (e) {
      if (!_current(ticket) || isCurrent?.call() == false) {
        throw const ApiException(ApiFailure.stale);
      }
      if (e.kind == ApiFailure.credentials) unawaited(_clear());
      rethrow;
    }
  }

  /// A create is never retried automatically. Without server idempotency,
  /// cancellation or a lost acknowledgement after dispatch blocks new writes
  /// for this account until a separate reconciliation mechanism exists.
  Future<int> createContent(
    ContentCreateRequest request,
    Uint8List? png, {
    required int maxBytes,
    required ApiRequestCancellation cancellation,
  }) async {
    try {
      if (!api.canCreateContent) {
        throw const ApiException(ApiFailure.uploadUnverified);
      }
      final owner = user;
      if (owner == null) throw const ApiException(ApiFailure.credentials);
      if (_uploads.containsKey(owner.id)) {
        throw const ApiException(ApiFailure.pending);
      }
      if (_unconfirmedUploads.contains(owner.id)) {
        throw const ApiException(ApiFailure.uploadUnconfirmed);
      }
      if (request.recipient.toLowerCase() ==
          owner.username.trim().toLowerCase()) {
        throw const ContentDraftException(ContentDraftProblem.recipient);
      }
      if (request.expiresAt?.isAfter(now().toUtc()) == false) {
        throw const ContentDraftException(ContentDraftProblem.policy);
      }
      if (cancellation.isCancelled) {
        throw const ApiException(ApiFailure.cancelled);
      }
      var dispatched = false;
      _uploads[owner.id] = cancellation;
      _emit();
      try {
        final id = await _authorized(
          (token) => api.createContent(
            token,
            request,
            png,
            maxBytes: maxBytes,
            cancellation: cancellation,
            onDispatch: () => dispatched = true,
          ),
        );
        if (cancellation.isCancelled) {
          throw const ApiException(ApiFailure.cancelled);
        }
        return id;
      } on ApiException catch (e) {
        if (dispatched &&
            !{
              ApiFailure.invalidRequest,
              ApiFailure.credentials,
              ApiFailure.denied,
            }.contains(e.kind)) {
          _unconfirmedUploads.add(owner.id);
        }
        rethrow;
      } finally {
        _uploads.remove(owner.id);
        _emit();
      }
    } finally {
      png?.fillRange(0, png.length, 0);
    }
  }

  Future<void> refresh({bool Function()? isCurrent}) async {
    if (isCurrent?.call() == false) throw const ApiException(ApiFailure.stale);
    final listTicket = ++_listEpoch;
    final ticket = _epoch;
    loading = true;
    error = null;
    _emit();
    try {
      final contents = await _authorized(api.list, isCurrent: isCurrent);
      if (!_current(ticket) || listTicket != _listEpoch) {
        if (isCurrent != null) throw const ApiException(ApiFailure.stale);
        return;
      }
      _listedItems = contents;
      _hasContentListing = true;
      _contentListingError = null;
      _items = List.unmodifiable(
        contents.map(
          (item) => _confirmedRevoked.contains(item.id)
              ? item.confirmed(status: 'Revoked')
              : item,
        ),
      );
    } on ApiException catch (e) {
      if (_current(ticket) &&
          (listTicket != _listEpoch || isCurrent?.call() == false)) {
        if (isCurrent != null) throw const ApiException(ApiFailure.stale);
        return;
      }
      if (_current(ticket) &&
          listTicket == _listEpoch &&
          isCurrent?.call() != false) {
        if (authenticated) _contentListingError = e;
        error = e;
      }
      rethrow;
    } finally {
      if (_current(ticket) && listTicket == _listEpoch) {
        loading = false;
        _emit();
      }
    }
  }

  Future<void> _change(
    int id, {
    String? policy,
    bool revoke = false,
    LocationZone? location,
    ApiTimeWindow? window,
    bool Function()? isCurrent,
  }) async {
    if (isCurrent?.call() == false) throw const ApiException(ApiFailure.stale);
    final owner = user;
    if (owner == null) throw const ApiException(ApiFailure.credentials);
    if (ownerControlUnconfirmed(id)) {
      throw const ApiException(ApiFailure.ownerControlUnconfirmed);
    }
    if (!_items.any(
      (item) => item.id == id && item.mine && item.status != 'Revoked',
    )) {
      throw const ApiException(ApiFailure.denied);
    }
    if (pending(id)) throw const ApiException(ApiFailure.pending);
    final action = switch ((location != null, window != null, revoke, policy)) {
      (true, _, _, _) => OwnerControlAction.editViewingArea,
      (_, true, _, _) => OwnerControlAction.editViewingTime,
      (_, _, true, _) => OwnerControlAction.revoke,
      (_, _, false, 'Paused') => OwnerControlAction.pause,
      (_, _, false, 'Active') => OwnerControlAction.resume,
      _ => throw const ApiException(ApiFailure.invalidRequest),
    };
    final editorAction = location != null || window != null;
    final key = (owner.id, id);
    final ticket = _epoch;
    ++_listEpoch; // Older list snapshots cannot undo a confirmed write.
    loading = false;
    _ownerControls[key] = (action, OwnerControlPhase.pending);
    error = null;
    _emit();
    var attempted = false;
    try {
      if (!_current(ticket)) throw const ApiException(ApiFailure.stale);
      await _authorized((token) {
        if (location != null) {
          return api.setLocation(
            token,
            id,
            location,
            onDispatch: () => attempted = true,
          );
        }
        if (window != null) {
          return api.setTimeWindow(
            token,
            id,
            window,
            onDispatch: () => attempted = true,
          );
        }
        attempted = true;
        return revoke ? api.revoke(token, id) : api.policy(token, id, policy!);
      }, isCurrent: isCurrent);
      if (!_current(ticket) || isCurrent?.call() == false) {
        throw const ApiException(ApiFailure.stale);
      }
      ++_listEpoch;
      loading = false;
      if (revoke) _confirmedRevoked.add(id);
      _ownerControls[key] = (action, OwnerControlPhase.confirmed);
      _items = List.unmodifiable(
        _items.map(
          (item) => item.id == id && item.mine
              ? item.confirmed(
                  status: revoke ? 'Revoked' : null,
                  policyStatus: policy,
                  zone: location,
                )
              : item,
        ),
      );
    } on ApiException catch (e) {
      if (editorAction && _current(ticket) && isCurrent?.call() != false) {
        error = e;
      }
      if (!attempted || _ownerControlRejected(action, e.kind)) {
        if (_current(ticket)) {
          _ownerControls[key] = (
            action,
            !attempted && editorAction
                ? OwnerControlPhase.notDispatched
                : OwnerControlPhase.rejected,
          );
        } else {
          _ownerControls.remove(key);
        }
      }
      rethrow;
    } finally {
      if (_ownerControls[key]?.$2 == OwnerControlPhase.pending) {
        // A later listing can show the resource state but cannot settle this
        // request. The current API has no operation outcome lookup.
        _ownerControls[key] = (action, OwnerControlPhase.unconfirmed);
      }
      if (_current(ticket) || user?.id == owner.id) _emit();
    }
  }

  static bool _ownerControlRejected(
    OwnerControlAction action,
    ApiFailure kind,
  ) => switch (kind) {
    // Authentication rejects before the handler. Owner-scoped mutations return
    // NotFound without a write, including the area update with no owner match.
    ApiFailure.credentials || ApiFailure.notFound => true,
    // Status, location and time validation precede the write. Revoke has no
    // request body and its contract does not define a 400 rejection.
    ApiFailure.invalidRequest => action != OwnerControlAction.revoke,
    ApiFailure.configuration || ApiFailure.httpDemoAnonymousOnly =>
      action != OwnerControlAction.editViewingArea &&
          action != OwnerControlAction.editViewingTime,
    _ => false,
  };

  Future<void> setPolicy(int id, String status) => _change(id, policy: status);
  Future<void> revoke(int id) => _change(id, revoke: true);
  Future<void> setLocation(
    int id,
    LocationZone zone, {
    required bool Function() isCurrent,
  }) => _change(id, location: zone, isCurrent: isCurrent);

  Future<ApiTimeWindow> timeWindow(
    int id, {
    required bool Function() isCurrent,
  }) => _authorized((token) => api.timeWindow(token, id), isCurrent: isCurrent);

  Future<void> setTimeWindow(
    int id,
    ApiTimeWindow window, {
    required bool Function() isCurrent,
  }) async {
    final expiry = window.expiresAt;
    final start = window.startTime;
    if (expiry != null &&
        (!expiry.isAfter(now().toUtc()) ||
            (start != null && !expiry.isAfter(start)))) {
      throw const ApiException(ApiFailure.invalidRequest);
    }
    await _change(id, window: window, isCurrent: isCurrent);
  }

  Future<bool> registerDevice(String name) => _authorized((token) {
    final key = deviceKey;
    if (key == null) throw const ApiException(ApiFailure.configuration);
    return api.registerDevice(token, key, name);
  });

  Future<ApiAccessDecision> openViewing(
    int id,
    String key, {
    LocationFix? location,
  }) {
    late final Future<ApiAccessDecision> opening;
    opening = _authorized(
      (token) => api.open(token, id, key, location: location),
      accept: (result) {
        final sid = result.sessionId;
        if (sid != null) _viewingSessions.add(sid);
      },
      discard: (result, oldToken) async {
        final sid = result.sessionId;
        if (sid != null) {
          await _endWithToken(oldToken, sid).catchError((Object _) {});
        }
      },
    ).whenComplete(() => _viewingOpens.remove(opening));
    _viewingOpens.add(opening);
    return opening;
  }

  Future<ApiAccessDecision> checkViewing(int id, {LocationFix? location}) =>
      _authorized((token) => api.check(token, id, location: location));
  Future<void> endViewing(int id) async {
    final owner = _credentials;
    if (owner == null || !_viewingSessions.contains(id)) return;
    var unconfirmed = false;
    try {
      await _endWithToken(owner.token, id);
    } on ApiException catch (error) {
      unconfirmed = _unconfirmedEndFailures.contains(error.kind);
      rethrow;
    } finally {
      // Retain uncertain ends for retirement under the issuing credential.
      if (!unconfirmed && identical(_credentials, owner)) {
        _viewingSessions.remove(id);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    accessStatuses.dispose();
    for (final cancellation in _uploads.values) {
      cancellation.cancel();
    }
    ++_epoch;
    _expiry?.cancel();
    final ending = _endKnownViewing(_credentials);
    _credentials = null;
    _items = const [];
    _listedItems = const [];
    _hasContentListing = false;
    _contentListingError = null;
    _ownerControls.clear();
    // An open already in flight can still reveal a server session ID. Keep
    // the transport until its bounded response and any cleanup complete.
    final opening = _viewingOpens.toList();
    final pending = _viewingCleanup.values.toList();
    final logins = _logins.toList();
    unawaited(
      Future.wait([
        ending,
        for (final open in opening) _settled(open),
        for (final cleanup in pending) _settled(cleanup),
        for (final login in logins) _settled(login),
      ]).then<void>((_) async {
        if (_retiring.isNotEmpty) await Future.wait(_retiring.toList());
        api.close();
      }),
    );
    super.dispose();
  }
}
