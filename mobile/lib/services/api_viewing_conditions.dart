import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/api_models.dart';
import '../models/location_radius_policy.dart';
import '../widgets/content_restrictions_section.dart';
import 'access_status.dart';
import 'api_session.dart';
import 'device_location.dart';
import 'viewing_conditions.dart';

/// Server authorization at the existing condition boundary. No content bytes
/// retained, no fabricated device/GPS facts, no advertised camera protocol v1.
class ApiViewingConditions extends ChangeNotifier
    implements ViewingConditionProvider, ViewingConditionLifecycle {
  final ApiSession account;
  final AccessStatusReporter? statuses;
  final int contentId;
  final Duration pollInterval;
  final bool Function() identityReady;
  final DeviceLocationSource locationSource;
  final DateTime Function() now;
  final Duration locationMaxAge, locationTimeout;
  final Timer Function(Duration, void Function()) schedule;
  late final int _accountIdentity;
  ApiViewingConditions(
    this.account,
    this.contentId, {
    this.statuses,
    this.pollInterval = const Duration(seconds: 3),
    bool Function()? identityReady,
    this.locationSource = const UnavailableDeviceLocation(),
    DateTime Function()? now,
    this.locationMaxAge = const Duration(seconds: 5),
    this.locationTimeout = const Duration(seconds: 4),
    Timer Function(Duration, void Function())? schedule,
  }) : identityReady = identityReady ?? _unverifiedIdentity,
       now = now ?? DateTime.now,
       schedule = schedule ?? Timer.new {
    _accountIdentity = account.identityVersion;
    account.addListener(_accountChanged);
    _accountChanged();
  }

  static bool _unverifiedIdentity() => false;

  final _changes =
      StreamController<Map<String, ViewingConditionResult>>.broadcast(
        sync: true,
      );
  Timer? _timer;
  Timer? _locationExpiry;
  Future<Map<String, ViewingConditionResult>>? _pending;
  int? _sessionId;
  int _generation = 0;
  bool _ended = false, _disposed = false;
  bool _requiresLocation = false, _requiresDevice = false;
  LocationZone? _locationZone;
  bool locationPermissionPending = false;
  LocationPermissionState? locationPermission;
  int? get sessionId => _sessionId;
  bool get sessionEnded => _ended;
  int _permissionGeneration = 0;
  bool get requiresPreciseLocation => _requiresLocation;
  bool get _canObserveLocation =>
      _requiresLocation &&
      !_ended &&
      !_disposed &&
      account.authenticated &&
      account.identityVersion == _accountIdentity;

  bool get canRequestLocationPermission =>
      _canObserveLocation &&
      locationSource is ForegroundDeviceLocationSource &&
      locationPermission != LocationPermissionState.granted &&
      locationPermission != LocationPermissionState.permanentlyDenied;

  String? get locationPermissionGuidance => switch (locationPermission) {
    LocationPermissionState.granted => 'Location permission is available. Verify identity and recheck every viewing condition.',
    LocationPermissionState.denied => 'Location permission denied. Try again or allow precise location in system settings.',
    LocationPermissionState.permanentlyDenied => 'Location permission is blocked in system settings. Enable precise location for Aperture, then return and recheck.',
    LocationPermissionState.approximate => 'Only approximate location is available. Enable precise location in system settings, then recheck.',
    LocationPermissionState.unavailable => 'Location permission could not be checked. Check Location Services and try again.',
    _ => null,
  };

  void _recordPermission(LocationPermissionState permission) {
    locationPermission = permission;
    statuses?.record(AccessStatusTopic.location, switch (permission) {
      LocationPermissionState.denied => AccessStatusKind.locationDenied,
      LocationPermissionState.permanentlyDenied =>
        AccessStatusKind.locationBlocked,
      LocationPermissionState.approximate =>
        AccessStatusKind.locationApproximate,
      LocationPermissionState.unavailable =>
        AccessStatusKind.locationUnavailable,
      _ => null,
    });
  }

  /// Reads OS status on foreground without prompting or collecting a fix.
  Future<void> refreshLocationPermission() async {
    final source = locationSource;
    if (!_canObserveLocation ||
        locationPermissionPending ||
        source is! DeviceLocationPermissionStatus) {
      return;
    }
    final generation = ++_permissionGeneration;
    LocationPermissionState permission;
    try {
      permission = await (source as DeviceLocationPermissionStatus)
          .readPermission();
    } catch (_) {
      permission = LocationPermissionState.unavailable;
    }
    if (!_canObserveLocation || generation != _permissionGeneration) return;
    _recordPermission(permission);
    notifyListeners();
  }

  void invalidateLocationPermissionObservation() {
    ++_permissionGeneration;
    if (!locationPermissionPending) return;
    locationPermissionPending = false;
    if (!_ended && !_disposed) notifyListeners();
  }

  void _cancelLocation({bool close = false}) {
    final source = locationSource;
    if (source is ForegroundDeviceLocationSource) {
      unawaited(
        (close ? source.close() : source.cancelAcquisition()).catchError(
          (Object _) {},
        ),
      );
    }
  }

  Future<void> requestLocationPermission() async {
    if (!canRequestLocationPermission || locationPermissionPending) return;
    final generation = ++_permissionGeneration;
    locationPermissionPending = true;
    notifyListeners();
    LocationPermissionState permission;
    try {
      permission = await (locationSource as ForegroundDeviceLocationSource)
          .requestPermission();
    } catch (_) {
      permission = LocationPermissionState.unavailable;
    }
    if (!_canObserveLocation || generation != _permissionGeneration) return;
    locationPermissionPending = false;
    _recordPermission(permission);
    notifyListeners();
  }

  void _recordServerStatus(AccessStatusKind? kind) => statuses?.record(
    AccessStatusTopic.server,
    kind,
    source: AccessStatusSource.serverResponse,
  );

  String message =
      'Server authorization has not been checked. Content remains hidden.';

  @override
  Set<String> get requiredConditions => {
    ViewingCondition.authorization,
    ViewingCondition.expiration,
    ViewingCondition.viewLimit,
    if (_requiresLocation) ViewingCondition.location,
    if (_requiresDevice) ViewingCondition.device,
  };
  @override
  Stream<Map<String, ViewingConditionResult>> get changes => _changes.stream;

  Map<String, ViewingConditionResult> _result(ViewingConditionResult result) =>
      {for (final key in requiredConditions) key: result};

  void _publish(Map<String, ViewingConditionResult> result) {
    if (!_disposed) {
      _changes.add(result);
      notifyListeners();
    }
  }

  void _accountChanged() {
    if (_ended || _disposed) return;
    final items = account.items.where(
      (item) => item.id == contentId && !item.mine,
    );
    final identityChanged =
        !account.authenticated || account.identityVersion != _accountIdentity;
    final revoked = items.any((item) => item.status == 'Revoked');
    final paused = items.any((item) => item.policyStatus == 'Paused');
    if (identityChanged || revoked || paused || items.isEmpty) {
      message = switch ((identityChanged, revoked, paused)) {
        (true, _, _) =>
          'Account verification ended. This viewing session cannot resume.',
        (_, true, _) => 'The server reports revoked recipient access. This session cannot resume.',
        (_, _, true) => 'The sender paused access. Open the item again after the policy resumes.',
        _ => 'This item is no longer listed for this recipient. This session cannot resume.',
      };
      if (revoked && !identityChanged) {
        statuses?.record(
          AccessStatusTopic.server,
          AccessStatusKind.contentRevoked,
          source: AccessStatusSource.serverMetadata,
        );
      } else {
        _recordServerStatus(null);
      }
      endSession();
      _publish(_result(ViewingConditionResult.denied));
      return;
    }
    final locationRequired = items.any((item) => item.requiresPreciseLocation);
    final deviceRequired = items.any((item) => item.requiresTrustedDevice);
    final zones = items
        .where((item) => item.requiresPreciseLocation)
        .map((item) => item.locationZone)
        .toSet();
    final zone = zones.length == 1 ? zones.single : null;
    if ((locationRequired && !_requiresLocation) ||
        (deviceRequired && !_requiresDevice) ||
        zone != _locationZone) {
      // Requirements can expand; a later list cannot silently remove a gate.
      _requiresLocation |= locationRequired;
      _requiresDevice |= deviceRequired;
      _locationZone = zone;
      ++_generation;
      _pending = null;
      _timer?.cancel();
      _locationExpiry?.cancel();
      _cancelLocation();
      message = 'Server authorization must be checked against the current requirements.';
      _publish(_result(ViewingConditionResult.unknown));
    }
  }

  @override
  Future<Map<String, ViewingConditionResult>> check(
    ContentRestrictions restrictions,
  ) {
    if (_ended || _disposed) {
      return Future.value(_result(ViewingConditionResult.denied));
    }
    if (_pending != null) return _pending!;
    late final Future<Map<String, ViewingConditionResult>> pending;
    pending = _check().whenComplete(() {
      if (identical(_pending, pending)) _pending = null;
    });
    return _pending = pending;
  }

  /// A new foreground/biometric evaluation must not share the previous fix or
  /// pending exchange. The controller already hides content on this boundary.
  @override
  void invalidateLocalChecks() {
    if (_ended ||
        _disposed ||
        (_pending == null && _timer == null && _locationExpiry == null)) {
      return;
    }
    ++_generation;
    _pending = null;
    _timer?.cancel();
    _timer = null;
    _locationExpiry?.cancel();
    _locationExpiry = null;
    _cancelLocation();
    message = 'A fresh server access check is required.';
  }

  Future<Map<String, ViewingConditionResult>> _check() async {
    final generation = _generation;
    _timer?.cancel();
    var result = _result(ViewingConditionResult.unknown);
    var terminal = false;
    try {
      if (!identityReady()) {
        message =
            'Verify device identity before requesting server viewing access.';
        if (!_disposed) notifyListeners();
        return result;
      }
      final key = account.deviceKey;
      if (key == null || key.isEmpty) {
        throw const ApiException(ApiFailure.configuration);
      }
      LocationFix? fix;
      if (_requiresLocation) {
        if (_locationZone == null || !_locationZone!.valid) {
          message = 'The required viewing area is missing or invalid. Content stays hidden.';
          result[ViewingCondition.location] = ViewingConditionResult.failed;
          _recordServerStatus(null);
          statuses?.record(
            AccessStatusTopic.policy,
            AccessStatusKind.securityUnavailable,
          );
          return result;
        }
        // Permission/native access is requested only for an applicable policy,
        // after identity verification, and never for location-free content.
        final started = now().toUtc();
        LocationReading reading;
        try {
          reading = await locationSource.locate().timeout(locationTimeout);
        } catch (_) {
          if (!_ended && !_disposed && generation == _generation) {
            _cancelLocation();
          }
          reading = const LocationReading(LocationStatus.unavailable);
        }
        if (_disposed || _ended || generation != _generation) {
          return _result(ViewingConditionResult.denied);
        }
        if (!identityReady()) return result;
        switch (reading.status) {
          case LocationStatus.denied:
            _recordPermission(LocationPermissionState.denied);
          case LocationStatus.permanentlyDenied:
            _recordPermission(LocationPermissionState.permanentlyDenied);
          case LocationStatus.permissionRequired:
            _recordPermission(LocationPermissionState.notDetermined);
          case LocationStatus.granted:
            _recordPermission(LocationPermissionState.granted);
          case LocationStatus.unavailable:
            statuses?.record(
              AccessStatusTopic.location,
              AccessStatusKind.locationUnavailable,
            );
          default:
            break;
        }
        fix = reading.fix;
        if (reading.status != LocationStatus.granted ||
            fix == null ||
            !fix.freshFor(started, now().toUtc(), locationMaxAge)) {
          message = switch (reading.status) {
            LocationStatus.denied =>
              'Location permission denied. Content stays hidden.',
            LocationStatus.permanentlyDenied => 'Location permission is blocked in system settings. Content stays hidden.',
            LocationStatus.unavailable =>
              'Required device location is unavailable. Content stays hidden.',
            LocationStatus.permissionRequired => 'Allow location for this viewing policy, then verify identity and recheck all conditions.',
            LocationStatus.accuracyUnconfirmed => 'The location accuracy requirement has not been approved. Content stays hidden.',
            LocationStatus.insufficientAccuracy => 'Location is not accurate enough for this viewing policy. Content stays hidden.',
            _ => 'A fresh valid location is required for every access check. Content stays hidden.',
          };
          result[ViewingCondition.location] = ViewingConditionResult.failed;
          _recordServerStatus(null);
          statuses?.record(
            AccessStatusTopic.policy,
            AccessStatusKind.securityUnavailable,
          );
          return result;
        }
        final zoneResult = LocationRadiusPolicy.evaluate(
          _locationZone,
          fix,
          started,
          now().toUtc(),
          locationMaxAge,
        );
        if (zoneResult != LocationZoneResult.accepted) {
          message = zoneResult == LocationZoneResult.uncertainty
              ? 'Location accuracy is missing, invalid or exceeds 100 meters. Content stays hidden.'
              : 'Your location and its uncertainty must fit inside the viewing area. Content stays hidden.';
          result[ViewingCondition.location] = ViewingConditionResult.failed;
          _recordServerStatus(null);
          statuses?.record(
            AccessStatusTopic.policy,
            AccessStatusKind.securityUnavailable,
          );
          return result;
        }
      }
      final opening = _sessionId == null;
      message = 'Waiting for the server access decision.';
      notifyListeners();
      final decision = opening
          ? await account.openViewing(contentId, key, location: fix)
          : await account.checkViewing(_sessionId!, location: fix);
      if (_disposed || _ended || generation != _generation) {
        if (opening &&
            decision.sessionId != null &&
            decision.sessionId != _sessionId &&
            account.identityVersion == _accountIdentity) {
          unawaited(
            account.endViewing(decision.sessionId!).catchError((Object _) {}),
          );
        }
        return _result(ViewingConditionResult.denied);
      }
      if (decision.sessionId != null) {
        if (_sessionId != null && _sessionId != decision.sessionId) {
          throw const ApiException(ApiFailure.malformed);
        }
        _sessionId = decision.sessionId;
      }
      statuses?.record(AccessStatusTopic.connection, null);
      statuses?.record(AccessStatusTopic.policy, null);
      if (decision.granted) {
        if (_requiresDevice && !decision.deviceVerified) {
          terminal = true;
          result = _result(ViewingConditionResult.denied);
          message = 'The required device approval was not confirmed. This session has ended.';
          _recordServerStatus(null);
          statuses?.record(
            AccessStatusTopic.policy,
            AccessStatusKind.securityUnavailable,
          );
        } else if (fix != null &&
            !fix.freshFor(fix.measuredAt, now().toUtc(), locationMaxAge)) {
          result[ViewingCondition.location] = ViewingConditionResult.failed;
          message = 'Location expired while access was pending. Recheck all conditions.';
          _recordServerStatus(null);
          statuses?.record(
            AccessStatusTopic.policy,
            AccessStatusKind.securityUnavailable,
          );
        } else if (identityReady()) {
          result = _result(ViewingConditionResult.satisfied);
          _recordServerStatus(AccessStatusKind.accessGranted);
          message = 'The server granted access for this check. Local security requirements still apply.';
          if (fix != null) {
            _locationExpiry?.cancel();
            final remaining =
                locationMaxAge - now().toUtc().difference(fix.measuredAt);
            _locationExpiry = schedule(remaining, () {
              if (_disposed || _ended || generation != _generation) return;
              message = 'Location is no longer fresh. Recheck all conditions.';
              _recordServerStatus(null);
              statuses?.record(
                AccessStatusTopic.policy,
                AccessStatusKind.securityUnavailable,
              );
              _publish({
                ViewingCondition.location: ViewingConditionResult.unknown,
              });
            });
          }
        } else {
          message = 'Device identity changed while authorization was pending. Reverify and recheck.';
          _recordServerStatus(null);
        }
      } else if (decision.suspended && !decision.ended && _sessionId != null) {
        // Do not relax existing permanent mobile authorization/expiry latches
        // to imitate desktop grace/recovery semantics without team agreement.
        terminal = true;
        result = _result(ViewingConditionResult.denied);
        message = 'The server suspended access. This mobile viewing session has ended. Return to Shared With Me and reopen the item when access is restored.';
        _recordServerStatus(AccessStatusKind.sessionSuspended);
      } else {
        terminal = true;
        result = _result(ViewingConditionResult.denied);
        if (decision.ended && !decision.refusedByHttp) {
          message = 'The server ended this viewing session. Return to Shared With Me and reopen the item if access is still available.';
          _recordServerStatus(AccessStatusKind.sessionEnded);
        } else {
          message = switch ((decision.suspended, opening)) {
            (true, _) => 'The server suspended access. Return to Shared With Me and reopen the item when access is restored.',
            (_, false) => 'The server denied this access check. The session may have expired or access may have changed. Reopen the item from Shared With Me if access is still available.',
            _ => 'The server denied this access check. If you expected access, reopen the item from Shared With Me or contact the sender.',
          };
          _recordServerStatus(
            decision.suspended
                ? AccessStatusKind.sessionSuspended
                : AccessStatusKind.accessDenied,
          );
        }
      }
    } on ApiException catch (e) {
      if (_ended || _disposed || generation != _generation) {
        return _result(ViewingConditionResult.denied);
      }
      if ({
        ApiFailure.credentials,
        ApiFailure.denied,
        ApiFailure.notFound,
        ApiFailure.unsupportedViewingPolicy,
      }.contains(e.kind)) {
        terminal = true;
        result = _result(ViewingConditionResult.denied);
      }
      final network =
          e.kind == ApiFailure.network || e.kind == ApiFailure.timeout;
      statuses?.record(
        AccessStatusTopic.connection,
        network ? AccessStatusKind.networkInterrupted : null,
      );
      _recordServerStatus(
        e.kind == ApiFailure.denied ? AccessStatusKind.accessDenied : null,
      );
      statuses?.record(AccessStatusTopic.policy, switch (e.kind) {
        ApiFailure.denied ||
        ApiFailure.network ||
        ApiFailure.timeout ||
        ApiFailure.credentials ||
        ApiFailure.stale => null,
        _ => AccessStatusKind.securityUnavailable,
      });
      message = switch (e.kind) {
        ApiFailure.configuration => 'An approved API environment and test device key are required. Content remains hidden.',
        ApiFailure.denied => 'The server denied this access check. If you expected access, reopen the item from Shared With Me or contact the sender.',
        ApiFailure.network => 'The server access check could not be reached. Check your connection, then recheck conditions.',
        ApiFailure.notFound when _sessionId != null => 'This viewing session is no longer available. Return to Shared With Me and reopen the item if access is still available.',
        ApiFailure.notFound => 'This item is unavailable to your account. Return to Shared With Me and refresh the listing.',
        ApiFailure.unsupportedViewingPolicy => 'This app cannot verify a required viewing policy. The session ended. Contact the sender or use an approved app version that supports the policy.',
        _ => e.message,
      };
    } finally {
      if (!terminal && !_disposed && !_ended && generation == _generation) {
        notifyListeners();
      }
    }
    if (!_ended && !_disposed && generation == _generation) {
      if (terminal) {
        endSession();
        _publish(result);
        return result;
      }
      _timer = schedule(pollInterval, () async {
        if (_disposed || _ended || generation != _generation) return;
        final next = await check(ContentRestrictions.demoDefaults);
        if (!_disposed && !_ended && generation == _generation) {
          _publish(next);
        }
      });
    }
    return result;
  }

  @override
  void endSession() {
    if (_disposed || _ended) return;
    _ended = true;
    account.removeListener(_accountChanged);
    ++_generation;
    _pending = null;
    _timer?.cancel();
    _timer = null;
    _locationExpiry?.cancel();
    _locationExpiry = null;
    ++_permissionGeneration;
    locationPermissionPending = false;
    _cancelLocation(close: true);
    final sid = _sessionId;
    _sessionId = null;
    if (sid != null && account.identityVersion == _accountIdentity) {
      unawaited(account.endViewing(sid).catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    endSession();
    _disposed = true;
    unawaited(_changes.close());
    super.dispose();
  }
}
