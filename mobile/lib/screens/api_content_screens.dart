import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/viewing_state_controller.dart';
import '../models/api_models.dart';
import '../models/location_radius_policy.dart';
import '../services/access_status.dart';
import '../services/api_session.dart';
import '../services/api_viewing_conditions.dart';
import '../services/biometric_verification.dart';
import '../services/camera_detection.dart';
import '../services/device_location.dart';
import '../services/native_device_location.dart';
import '../services/device_registration.dart';
import '../services/screen_capture_protection.dart';
import '../widgets/aperture_button.dart';
import '../widgets/content_restrictions_section.dart';
import 'notifications_screen.dart';
import 'secure_viewer_screen.dart';
import 'api_location_edit_screen.dart';
import 'share_content_screen.dart';

class ApiDashboardScreen extends StatefulWidget {
  final ApiSession account;
  const ApiDashboardScreen({super.key, required this.account});

  @override
  State<ApiDashboardScreen> createState() => _ApiDashboardScreenState();
}

class _ApiDashboardScreenState extends State<ApiDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    try {
      await widget.account.refresh();
    } on ApiException {
      /* Account owns error UI. */
    }
  }

  void _openDetails(ApiSession account, ApiContent item, int identity) {
    if (!item.mine &&
        !account.api.usesClassroomHttp &&
        (!mounted ||
            !identical(widget.account, account) ||
            !account.authenticated ||
            account.identityVersion != identity ||
            !account.items.any(
              (current) => current.id == item.id && !current.mine,
            ))) {
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) {
          if (account.api.usesClassroomHttp) {
            return ApiContentStatusScreen._classroom(
              account,
              item.id,
              item.mine,
            );
          }
          return item.mine
              ? ApiContentStatusScreen(account: account, contentId: item.id)
              : ApiRecipientScreen(account: account, contentId: item.id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.account,
    builder: (context, _) {
      final account = widget.account;
      final identity = account.identityVersion;
      final listingError = account.contentListingError;
      final hasListing = account.hasContentListing;
      final listingStatus = switch ((
        account.loading,
        listingError != null,
        hasListing,
      )) {
        (true, _, true) =>
          'Refreshing content. Showing the last known listing.',
        (true, _, false) => 'Loading content…',
        (_, true, true) => 'Refresh failed. Showing the last known listing.',
        (_, true, false) => 'Content listing could not be loaded.',
        (_, false, true) => 'Content listing refreshed.',
        _ => 'Content listing has not loaded yet.',
      };
      final canOpenDetails =
          account.api.usesClassroomHttp || account.api.canOpenContentRoutes;
      final signOut = account.authenticated
          ? () {
              if (mounted &&
                  identical(widget.account, account) &&
                  account.identityVersion == identity) {
                unawaited(account.logout());
              }
            }
          : null;
      final largeActionText = MediaQuery.textScalerOf(context).scale(14) > 28;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Aperture'),
          actions: [
            IconButton(
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: !account.authenticated
                  ? null
                  : () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NotificationsScreen(account: account),
                      ),
                    ),
            ),
            if (largeActionText)
              IconButton(
                tooltip: 'Sign out',
                onPressed: signOut,
                icon: const Icon(Icons.logout),
              )
            else
              TextButton(onPressed: signOut, child: const Text('Sign out')),
          ],
        ),
        body: !account.authenticated
            ? const Center(child: Text('Sign in to access this account.'))
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'Signed in as ${account.user!.username}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      account.api.isFixture
                          ? 'Fixture mode · sample accounts and content.'
                          : 'Last confirmed server metadata. A listed item does not grant viewing access.',
                    ),
                    if (!account.api.usesClassroomHttp)
                      TextButton.icon(
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ShareContentScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Prepare PNG'),
                      ),
                    Semantics(liveRegion: true, child: Text(listingStatus)),
                    if (account.loading)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Loading content listing',
                      ),
                    if (!account.loading && listingError != null)
                      Text(
                        listingError.kind == ApiFailure.timeout
                            ? 'The listing request timed out. Use Refresh content to try again.'
                            : listingError.message,
                        key: const ValueKey('api-list-error'),
                      ),
                    TextButton(
                      onPressed: account.loading ? null : _refresh,
                      child: const Text('Refresh content'),
                    ),
                    if (hasListing && account.items.isEmpty)
                      Text(
                        account.loading || listingError != null
                            ? 'The last known listing was empty.'
                            : 'No shared content is available.',
                      ),
                    for (final mine in [false, true]) ...[
                      const SizedBox(height: 20),
                      Text(
                        mine ? 'My Shared Content' : 'Shared With Me',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final item in account.items.where(
                        (item) => item.mine == mine,
                      ))
                        ListTile(
                          title: Text(item.title),
                          subtitle: Text(
                            mine
                                ? 'Recipient: ${item.recipient} · Access: ${item.status} · Policy: ${item.policyStatus}'
                                : account.api.usesClassroomHttp
                                ? 'Owner: ${item.owner} · Access: ${item.status} · Policy: ${item.policyStatus}'
                                : 'Owner: ${item.owner} · Listed access: ${item.status} · Listed policy: ${item.policyStatus}',
                          ),
                          trailing: canOpenDetails
                              ? const Icon(Icons.chevron_right)
                              : null,
                          onTap: canOpenDetails
                              ? () => _openDetails(account, item, identity)
                              : null,
                        ),
                    ],
                  ],
                ),
              ),
      );
    },
  );
}

class ApiContentStatusScreen extends StatefulWidget {
  final ApiSession account;
  final int contentId;
  final bool _mine;
  const ApiContentStatusScreen({
    super.key,
    required this.account,
    required this.contentId,
  }) : _mine = true;

  const ApiContentStatusScreen._classroom(
    this.account,
    this.contentId,
    this._mine,
  );

  @override
  State<ApiContentStatusScreen> createState() => _ApiContentStatusScreenState();
}

typedef _ContentStatusScope = ({
  ApiSession account,
  int identity,
  int contentId,
  bool mine,
});

class _ApiContentStatusScreenState extends State<ApiContentStatusScreen> {
  late int _identity;
  ApiException? _refreshError;
  bool _readbackFailed = false;
  bool _confirmingRevoke = false;

  bool get _canManage =>
      widget._mine && widget.account.api.canOpenContentRoutes;

  _ContentStatusScope get _scope => (
    account: widget.account,
    identity: _identity,
    contentId: widget.contentId,
    mine: widget._mine,
  );

  bool _current(_ContentStatusScope scope) =>
      mounted &&
      _scope == scope &&
      scope.account.authenticated &&
      scope.account.identityVersion == scope.identity;

  @override
  void initState() {
    super.initState();
    _identity = widget.account.identityVersion;
  }

  @override
  void didUpdateWidget(ApiContentStatusScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.account, widget.account) ||
        oldWidget.contentId != widget.contentId ||
        oldWidget._mine != widget._mine) {
      _identity = widget.account.identityVersion;
      _refreshError = null;
      _readbackFailed = false;
      _confirmingRevoke = false;
    }
  }

  Future<void> _refresh(
    _ContentStatusScope scope, {
    bool afterWrite = false,
  }) async {
    if (!_current(scope) || (!afterWrite && scope.account.loading)) return;
    setState(() {
      _refreshError = null;
      _readbackFailed = false;
    });
    try {
      await scope.account.refresh();
    } on ApiException catch (error) {
      if (!_current(scope) || error.kind == ApiFailure.stale) return;
      setState(() {
        if (afterWrite) {
          _readbackFailed = true;
        } else {
          _refreshError = error;
        }
      });
    }
  }

  bool _canManageItem(_ContentStatusScope scope) =>
      _current(scope) &&
      _canManage &&
      !_confirmingRevoke &&
      scope.account.items.any(
        (item) =>
            item.id == scope.contentId && item.mine && item.status != 'Revoked',
      );

  bool _canChange(_ContentStatusScope scope) =>
      _canManageItem(scope) &&
      !scope.account.pending(scope.contentId) &&
      !scope.account.ownerControlUnconfirmed(scope.contentId);

  Future<bool> _confirmRevoke(ApiSession account) async {
    var answered = false;
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            void answer(bool confirmed) {
              if (answered) return;
              answered = true;
              Navigator.pop(context, confirmed);
            }

            return AlertDialog(
              title: const Text('Revoke recipient access?'),
              content: Text(
                account.api.isFixture
                    ? 'This marks the sample item as revoked for the rest of this demo run.'
                    : 'The server will be asked to revoke access for every recipient of this content and end active sessions. This app cannot restore revoked recipient access.',
              ),
              actions: [
                TextButton(
                  onPressed: () => answer(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => answer(true),
                  child: const Text('Confirm revocation'),
                ),
              ],
            );
          },
        ) ==
        true;
  }

  Future<void> _change(
    _ContentStatusScope scope,
    OwnerControlAction action,
  ) async {
    if (!_canChange(scope)) return;
    final account = scope.account;
    final id = scope.contentId;
    if (action == OwnerControlAction.revoke) {
      _confirmingRevoke = true;
      final confirmed = await _confirmRevoke(account);
      if (!_current(scope)) return;
      _confirmingRevoke = false;
      if (!confirmed || !_canChange(scope)) return;
    }
    setState(() {
      _refreshError = null;
      _readbackFailed = false;
    });
    try {
      await switch (action) {
        OwnerControlAction.pause => account.setPolicy(id, 'Paused'),
        OwnerControlAction.resume => account.setPolicy(id, 'Active'),
        OwnerControlAction.revoke => account.revoke(id),
        OwnerControlAction.editViewingArea => throw StateError(
          'Viewing areas are saved through the area editor.',
        ),
      };
      await _refresh(scope, afterWrite: true);
    } on ApiException {
      // The account session owns the outcome even when this route is closed.
    }
  }

  String _confirmation(OwnerControlAction action, bool fixture) {
    if (action == OwnerControlAction.editViewingArea) {
      return 'Viewing area update acknowledged by the server.';
    }
    final status = action == OwnerControlAction.pause ? 'Paused' : 'Active';
    if (action == OwnerControlAction.revoke) {
      return fixture
          ? 'Sample revocation applied.'
          : 'Revocation confirmed by the server.';
    }
    return fixture
        ? 'Sample policy set to $status.'
        : 'Policy $status confirmed by the server.';
  }

  Widget _ownerOutcome(
    ApiSession account,
    OwnerControlAction action,
    OwnerControlPhase phase,
  ) {
    final verb = action == OwnerControlAction.editViewingArea
        ? 'viewing-area update'
        : action.name;
    final (message, key) = switch (phase) {
      OwnerControlPhase.pending => (
        'Request pending… Waiting for the $verb acknowledgement.',
        'api-write-pending',
      ),
      OwnerControlPhase.confirmed => (
        '${_confirmation(action, account.api.isFixture)}'
            '${_readbackFailed ? ' Status refresh is unavailable. Showing the last observed listing separately.' : ''}',
        'api-write-confirmation',
      ),
      OwnerControlPhase.notDispatched => (
        'The $verb request was not sent.',
        'api-write-error',
      ),
      OwnerControlPhase.rejected => (
        'The $verb request was rejected before a change was applied.',
        'api-write-error',
      ),
      OwnerControlPhase.unconfirmed => (
        'The $verb request’s server outcome is unknown. Refresh status to see '
            'the latest listing. Authoritative reconciliation is required '
            'before another change.',
        'api-write-unconfirmed',
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Text(message, key: ValueKey(key)),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.account,
    builder: (context, _) {
      final scope = _scope;
      final (:account, identity: _, contentId: id, :mine) = scope;
      final matching = account.items
          .where((item) => item.id == id && item.mine == mine)
          .toList();
      final item = matching.isEmpty ? null : matching.first;
      final ownerControl = _canManage ? account.ownerControl(id) : null;
      final pending = account.pending(id);
      final locked = pending || account.ownerControlUnconfirmed(id);
      final areaPending =
          ownerControl ==
          (OwnerControlAction.editViewingArea, OwnerControlPhase.pending);
      final areaUnconfirmed =
          ownerControl ==
          (OwnerControlAction.editViewingArea, OwnerControlPhase.unconfirmed);
      final reviewArea = areaPending || areaUnconfirmed;
      final listed = ownerControl == null
          ? const <ApiContent>[]
          : account.listedOwnerItems(id);
      return Scaffold(
        appBar: AppBar(title: const Text('Content Status')),
        body: !_current(scope) || (item == null && ownerControl == null)
            ? const Center(child: Text('Content unavailable to this account.'))
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (item == null)
                    const Text('Content unavailable to this account.')
                  else ...[
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (!mine) Text('Owner: ${item.owner}'),
                    for (var i = 0; i < matching.length; i++) ...[
                      if (mine) Text('Recipient: ${matching[i].recipient}'),
                      Text(
                        'Recipient access: ${matching[i].status}',
                        key: ValueKey('api-recipient-status-$i'),
                      ),
                    ],
                    Text('Policy: ${item.policyStatus}'),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    account.api.usesClassroomHttp
                        ? 'Classroom Test · Read-only content status.'
                        : account.api.isFixture
                        ? 'Sample content status. These controls change the local demo data.'
                        : 'Displayed status uses the last listing and any acknowledged owner action. Recipient enforcement is checked separately by each viewing session.',
                  ),
                  if (_canManage)
                    const Text(
                      'Pause, resume and revoke apply to all recipients of this content.',
                    ),
                  if (pending || account.loading)
                    const LinearProgressIndicator(),
                  if (ownerControl != null) ...[
                    _ownerOutcome(account, ownerControl.$1, ownerControl.$2),
                    if (reviewArea)
                      Text(
                        areaUnconfirmed
                            ? 'Revoke is temporarily unavailable because the previous viewing-area update remains unconfirmed. Recipient access may still be active.'
                            : 'Revoke is temporarily unavailable while the viewing-area update is pending.',
                      ),
                    const Text('Latest observed listing'),
                    if (listed.isEmpty)
                      const Text('No matching listed item is available.'),
                    for (final row in listed)
                      Text(
                        '${row.recipient ?? 'Recipient'} · Access: ${row.status} · Policy: ${row.policyStatus}',
                      ),
                  ],
                  if (_refreshError != null)
                    Text(
                      'Status refresh failed. ${_refreshError!.message}',
                      key: const ValueKey('api-status-refresh-error'),
                    ),
                  TextButton(
                    onPressed: (pending && !areaPending) || account.loading
                        ? null
                        : () => _refresh(scope),
                    child: const Text('Refresh status'),
                  ),
                  if (_canManage &&
                      item != null &&
                      matching.any((item) => item.status != 'Revoked')) ...[
                    ApertureButton(
                      label: reviewArea
                          ? 'Review viewing area'
                          : 'Edit viewing area',
                      isSecondary: true,
                      onPressed: (locked && !reviewArea) || account.loading
                          ? null
                          : () {
                              if (reviewArea
                                  ? !_canManageItem(scope)
                                  : !_canChange(scope)) {
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => ApiLocationEditScreen(
                                    account: account,
                                    contentId: id,
                                  ),
                                ),
                              );
                            },
                    ),
                    const SizedBox(height: 12),
                    ApertureButton(
                      label: item.policyStatus == 'Paused'
                          ? 'Resume policy'
                          : 'Pause policy',
                      onPressed: locked
                          ? null
                          : () => _change(
                              scope,
                              item.policyStatus == 'Paused'
                                  ? OwnerControlAction.resume
                                  : OwnerControlAction.pause,
                            ),
                    ),
                    const SizedBox(height: 12),
                    ApertureButton(
                      label: pending && !areaPending
                          ? 'Request pending…'
                          : 'Revoke access',
                      onPressed: locked
                          ? null
                          : () => _change(scope, OwnerControlAction.revoke),
                    ),
                  ] else if (_canManage && item != null)
                    const Text(
                      'Revoked recipient access cannot be restored here.',
                    ),
                ],
              ),
      );
    },
  );
}

class ApiRecipientScreen extends StatelessWidget {
  final ApiSession account;
  final int contentId;
  final BiometricAuthenticator? biometricAuthenticator;
  final CameraDetectionService? cameraDetection;
  final ScreenCaptureProtection? captureProtection;
  final DeviceLocationSource? locationSource;
  const ApiRecipientScreen({
    super.key,
    required this.account,
    required this.contentId,
    this.biometricAuthenticator,
    this.cameraDetection,
    this.captureProtection,
    this.locationSource,
  });

  @override
  Widget build(BuildContext context) =>
      _RecipientAccess(key: ValueKey((account, contentId)), screen: this);
}

class _RecipientAccess extends StatefulWidget {
  final ApiRecipientScreen screen;

  const _RecipientAccess({required super.key, required this.screen});

  @override
  State<_RecipientAccess> createState() => _ApiRecipientScreenState();
}

class _ApiRecipientScreenState extends State<_RecipientAccess>
    with WidgetsBindingObserver {
  late final int _identity;
  late final AccessStatusReporter _statuses;
  late final ApiViewingConditions _conditions;
  late final ViewingStateController _viewing;
  late final DeviceRegistration _registration;

  ApiRecipientScreen get _screen => widget.screen;
  ApiSession get _account => _screen.account;
  bool get _currentAccount =>
      mounted &&
      _account.authenticated &&
      _account.identityVersion == _identity;
  Iterable<ApiContent> get _incoming => _currentAccount
      ? _account.items.where(
          (item) => item.id == _screen.contentId && !item.mine,
        )
      : const [];

  @override
  void initState() {
    super.initState();
    _identity = _account.identityVersion;
    _statuses = _account.accessStatuses.beginViewing(_screen.contentId);
    WidgetsBinding.instance.addObserver(this);
    _conditions = ApiViewingConditions(
      _account,
      _screen.contentId,
      statuses: _statuses,
      identityReady: () => _viewing.biometrics.approved,
      locationSource:
          _screen.locationSource ??
          NativeDeviceLocation(
            approvedAccuracyLimitMeters:
                LocationRadiusPolicy.maximumUncertaintyMeters,
          ),
    );
    _viewing = ViewingStateController(
      restrictions: ContentRestrictions.demoDefaults,
      conditions: _conditions,
      protection: _screen.captureProtection ?? ScreenCaptureProtection.instance,
      biometricAuthenticator: _screen.biometricAuthenticator,
    )..addListener(_changed);
    _registration = DeviceRegistration(
      _account,
      sessionEnded: () => _viewing.sessionEnded || _conditions.sessionEnded,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_conditions.refreshLocationPermission());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The native location adapter also receives this lifecycle event.
      // Read after all observers have updated their foreground state.
      scheduleMicrotask(() {
        if (mounted &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          unawaited(_conditions.refreshLocationPermission());
        }
      });
    } else if (state != AppLifecycleState.inactive) {
      // Transient inactivity can belong to the permission prompt itself.
      _conditions.invalidateLocationPermissionObservation();
    }
  }

  void _changed() {
    if (_viewing.sessionEnded) _registration.cancel();
    switch (_viewing.biometrics.state) {
      case BiometricState.cancelled:
        _statuses.record(
          AccessStatusTopic.biometric,
          AccessStatusKind.biometricCancelled,
        );
      case BiometricState.unavailable:
      case BiometricState.notEnrolled:
      case BiometricState.temporaryLockout:
      case BiometricState.permanentLockout:
      case BiometricState.busy:
        _statuses.record(
          AccessStatusTopic.biometric,
          AccessStatusKind.biometricUnavailable,
        );
      case BiometricState.verified:
        _statuses.record(AccessStatusTopic.biometric, null);
      default:
        break;
    }
    if (_viewing.securityViolation) {
      _statuses.record(AccessStatusTopic.server, null);
      _statuses.record(
        AccessStatusTopic.security,
        AccessStatusKind.sessionEnded,
      );
    } else {
      final unavailable = _viewing.issues.any(
        (issue) => const {
          ViewingIssueKind.protectionUnavailable,
          ViewingIssueKind.monitoringUnavailable,
          ViewingIssueKind.captureDetected,
        }.contains(issue.kind),
      );
      _statuses.record(
        AccessStatusTopic.security,
        unavailable ? AccessStatusKind.securityUnavailable : null,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statuses.close();
    _viewing.removeListener(_changed);
    _registration.dispose();
    _viewing.dispose();
    _conditions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _account,
    builder: (context, _) => _body(context),
  );

  Widget _body(BuildContext context) {
    final items = _incoming;
    if (items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Recipient access')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('Content unavailable to this account.'),
              const SizedBox(height: 12),
              Text(
                _currentAccount
                    ? 'This item is missing from your current listing. Go back and refresh Shared With Me.'
                    : 'The original sign-in is no longer active. Go back to the account screen and sign in again if needed.',
              ),
            ],
          ),
        ),
      );
    }
    final item = items.first;
    final localExpiry = item.expiresAt?.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final listingLabel =
        _account.loading || _account.contentListingError != null
        ? 'Last known Shared With Me listing'
        : 'Shared With Me listing';
    return SecureViewerScreen(
      contentTitle: item.title,
      ownerName: item.owner,
      viewingController: _viewing,
      cameraDetection: _screen.cameraDetection,
      onCameraStatus: (kind) =>
          _statuses.record(AccessStatusTopic.camera, kind),
      showPolicySummary: false,
      allowDemoPreview: false,
      recipientChecksUnavailable:
          _conditions.sessionEnded && !_viewing.hasStarted,
      recipientDetails: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_account.api.isFixture) const Text('Sample API status'),
          Text('Signed in as ${_account.user!.username}'),
          Text(
            '$listingLabel · Access: ${item.status} · Policy: ${item.policyStatus}',
          ),
          if (localExpiry != null)
            Text(
              'Listed viewing deadline: ${localizations.formatMediumDate(localExpiry)} '
              '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(localExpiry))}',
            ),
        ],
      ),
      recipientAuthorization: _authorizationStatus(),
      recipientDeviceChecks: _deviceChecks(),
    );
  }

  Widget _authorizationStatus() => ListenableBuilder(
    listenable: Listenable.merge([_account, _conditions, _viewing]),
    builder: (context, _) {
      final items = _incoming;
      final message = switch ((
        items.isEmpty,
        items.any((item) => item.status == 'Revoked'),
        items.any((item) => item.policyStatus == 'Paused'),
        _viewing.securityViolation,
      )) {
        (true, _, _, _) => 'Content unavailable to this account.',
        (_, true, _, _) => 'The listing reports revoked access. Contact the sender if you expected access.',
        (_, _, true, _) => 'The listing reports a sender pause. Return to Shared With Me and reopen the item after the sender resumes access.',
        (_, _, _, true) => 'A local security event ended this session.',
        _ => _conditions.message,
      };
      return Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Server authorization',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(message, key: const ValueKey('recipient-server-status')),
          ],
        ),
      );
    },
  );

  Widget _deviceChecks() => ListenableBuilder(
    listenable: Listenable.merge([_conditions, _registration, _viewing]),
    builder: (context, _) {
      if (_conditions.sessionEnded || _viewing.sessionEnded) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_conditions.requiresPreciseLocation) ...[
            const Text(
              'Aperture uses precise foreground location to check the required viewing area. Location permission alone does not authorize access.',
            ),
            if (_conditions.locationPermissionGuidance case final guidance?)
              Text(guidance),
            if (_conditions.canRequestLocationPermission)
              TextButton(
                onPressed: _conditions.locationPermissionPending
                    ? null
                    : () => unawaited(_conditions.requestLocationPermission()),
                child: Text(
                  _conditions.locationPermissionPending
                      ? 'Waiting for location permission…'
                      : 'Allow location for viewing',
                ),
              ),
          ],
          Text(
            _registration.message,
            key: const ValueKey('device-registration-status'),
          ),
          TextButton(
            onPressed: _registration.pending
                ? null
                : () => unawaited(
                    _registration.register('Aperture mobile device'),
                  ),
            child: Text(
              _registration.pending
                  ? 'Registering device…'
                  : 'Register this device',
            ),
          ),
          if (_registration.pending)
            TextButton(
              onPressed: _registration.cancel,
              child: const Text('Cancel registration wait'),
            ),
        ],
      );
    },
  );
}
