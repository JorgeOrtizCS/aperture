import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/screen_capture_protection.dart';
import '../services/biometric_verification.dart';
import '../services/viewing_conditions.dart';
import '../widgets/content_restrictions_section.dart';

enum ViewingIssueKind {
  screenshot,
  phoneDetected,
  multiplePeople,
  viewerMissing,
  simulatedViolation,
  expired,
  viewLimitReached,
  authorizationDenied,
  conditionDenied,
  conditionFailed,
  unknownCondition,
  captureDetected,
  protectionUnavailable,
  monitoringUnavailable,
  inactive,
}

@immutable
class ViewingIssue {
  final ViewingIssueKind kind;
  final String? condition;

  const ViewingIssue(this.kind, {this.condition});
}

enum ViewingState {
  checking,
  allowed,
  temporarilyLocked,
  accessDenied,
  protectionUnavailable,
}

class ViewingStateController extends ChangeNotifier {
  ViewingStateController({
    required this.restrictions,
    required this.conditions,
    required this.protection,
    bool demoPreview = false,
    this.checkTimeout = const Duration(seconds: 5),
    BiometricAuthenticator? biometricAuthenticator,
  }) : demoPreview = demoPreview && kDebugMode,
       _requiredConditions = Set.of(conditions.requiredConditions),
       biometrics = BiometricVerification(
         authenticator: biometricAuthenticator,
       ) {
    if (!this.demoPreview) {
      _requiredConditions.addAll({
        ViewingCondition.authorization,
        ViewingCondition.expiration,
        if (restrictions.viewLimit != null) ViewingCondition.viewLimit,
      });
    }
    biometrics.addListener(_biometricChanged);
  }

  final BiometricVerification biometrics;

  void _biometricChanged() {
    if (!_closed) notifyListeners();
  }

  Future<void> verifyIdentity() async {
    if (_closed || !_active || sessionEnded || !biometrics.canVerify) return;
    // A successful biometric notification must never release a pre-prompt
    // policy snapshot, even for a frame before the fresh checks begin.
    _invalidateEvaluation();
    await biometrics.verify();
    if (!_closed && _active && !sessionEnded && biometrics.approved) {
      await revalidate(verifyIdentity: false);
    }
  }

  void revokeIdentity() {
    if (_closed || sessionEnded) return;
    ++_generation;
    _checking = false;
    _invalidateEvaluation();
    _pauseMonitoring();
    biometrics.revoke();
  }

  final ContentRestrictions restrictions;
  final ViewingConditionProvider conditions;
  final Set<String> _requiredConditions;

  /// Only the viewer's non-sensitive placeholder demo may omit real policy checks.
  final bool demoPreview;
  final Duration checkTimeout;
  final ScreenCaptureProtection protection;
  ScreenCaptureSession? _session;
  final Map<String, ViewingConditionResult> _deniedResults = {};
  final Map<String, ViewingConditionResult> _results = {};
  final Map<String, int> _revisions = {};
  StreamSubscription<Map<String, ViewingConditionResult>>? _subscription;
  Future<void>? _conditionCleanup;
  bool _checking = true;
  // Live recovery signals are advisory: only a complete fresh evaluation can
  // release a lock. A failure during an evaluation invalidates its snapshot.
  bool _needsRevalidation = true;
  int _failureRevision = 0;
  bool _active = true;
  bool _closed = false;
  bool _conditionStreamFailed = false;
  ViewingIssueKind? _violationReason;
  ViewingIssueKind? _cameraIssue;
  int _evaluations = 0;
  int _generation = 0;

  Set<String> get requiredConditions {
    // A producer disappearing must not silently remove a mandatory gate.
    // Requirements may expand, but removal needs a separately authorized flow.
    if (!_closed && !sessionEnded) {
      _requiredConditions.addAll(conditions.requiredConditions);
    }
    return Set.unmodifiable(_requiredConditions);
  }

  bool get securityViolation => _violationReason != null;
  ViewingIssueKind? get violationReason => _violationReason;
  bool get hasStarted => _evaluations > 0;
  bool get isRechecking => state == ViewingState.checking && _evaluations > 1;
  bool get sessionEnded => securityViolation || _deniedResults.isNotEmpty;
  CaptureProtectionState get captureState =>
      _session?.state ?? CaptureProtectionState.checking;
  Map<String, ViewingConditionResult> get results =>
      Map.unmodifiable({..._results, ..._deniedResults});

  bool get canRecheck =>
      hasStarted &&
      !_closed &&
      _active &&
      !sessionEnded &&
      !_checking &&
      (state == ViewingState.temporarilyLocked ||
          (state == ViewingState.protectionUnavailable &&
              (_session?.canRevalidate ?? false)));

  List<ViewingIssue> get issues {
    if (securityViolation) return [ViewingIssue(_violationReason!)];
    final failures = <ViewingIssue>[];
    if (_cameraIssue != null) failures.add(ViewingIssue(_cameraIssue!));
    for (final id in requiredConditions) {
      final result = results[id] ?? ViewingConditionResult.unknown;
      if (result == ViewingConditionResult.satisfied) continue;
      final knownFailure =
          result == ViewingConditionResult.failed ||
          result == ViewingConditionResult.denied;
      final kind = !knownFailure
          ? ViewingIssueKind.unknownCondition
          : switch (id) {
              ViewingCondition.authorization =>
                ViewingIssueKind.authorizationDenied,
              ViewingCondition.expiration => ViewingIssueKind.expired,
              ViewingCondition.viewLimit => ViewingIssueKind.viewLimitReached,
              _ =>
                result == ViewingConditionResult.denied
                    ? ViewingIssueKind.conditionDenied
                    : ViewingIssueKind.conditionFailed,
            };
      failures.add(ViewingIssue(kind, condition: id));
    }
    if (captureState == CaptureProtectionState.unavailable) {
      failures.insert(
        0,
        const ViewingIssue(ViewingIssueKind.protectionUnavailable),
      );
    } else if (captureState == CaptureProtectionState.captureActive) {
      failures.insert(0, const ViewingIssue(ViewingIssueKind.captureDetected));
    }
    if (_conditionStreamFailed) {
      failures.add(const ViewingIssue(ViewingIssueKind.monitoringUnavailable));
    }
    if (!_active) {
      failures.insert(0, const ViewingIssue(ViewingIssueKind.inactive));
    }
    if (!biometrics.approved && !sessionEnded) {
      failures.add(
        const ViewingIssue(
          ViewingIssueKind.unknownCondition,
          condition: 'biometric',
        ),
      );
    }
    if (failures.isEmpty && _needsRevalidation && hasStarted && !_checking) {
      failures.add(const ViewingIssue(ViewingIssueKind.unknownCondition));
    }
    return List.unmodifiable(failures);
  }

  void _rememberDenials() {
    for (final id in requiredConditions) {
      final result = _results[id];
      if (result == ViewingConditionResult.denied ||
          (result == ViewingConditionResult.failed &&
              const {
                ViewingCondition.authorization,
                ViewingCondition.expiration,
                ViewingCondition.viewLimit,
              }.contains(id))) {
        _deniedResults[id] = result!;
      }
    }
    if (sessionEnded) _endMonitoring();
  }

  ViewingState get state {
    if (sessionEnded) return ViewingState.accessDenied;
    if (_closed || !_active) return ViewingState.temporarilyLocked;
    if (captureState == CaptureProtectionState.unavailable) {
      return ViewingState.protectionUnavailable;
    }
    if (_checking ||
        (_session != null && captureState == CaptureProtectionState.checking)) {
      return ViewingState.checking;
    }
    if (requiredConditions.any(
      (id) => _results[id] == ViewingConditionResult.denied,
    )) {
      return ViewingState.accessDenied;
    }
    if (_needsRevalidation ||
        _cameraIssue != null ||
        _conditionStreamFailed ||
        requiredConditions.any(
          (id) => _results[id] != ViewingConditionResult.satisfied,
        ) ||
        captureState == CaptureProtectionState.captureActive) {
      return ViewingState.temporarilyLocked;
    }
    if (!biometrics.approved) return ViewingState.temporarilyLocked;
    return ViewingState.allowed;
  }

  void _invalidateEvaluation() {
    _needsRevalidation = true;
    _failureRevision++;
  }

  Future<void> _cancelConditionSubscription() async {
    final subscription = _subscription;
    if (subscription != null) {
      _subscription = null;
      _conditionCleanup = subscription.cancel();
    }
    await _conditionCleanup;
  }

  void _stopListening() {
    unawaited(_cancelConditionSubscription().catchError((Object _) {}));
  }

  void _pauseMonitoring() {
    _stopListening();
    final provider = conditions;
    if (provider is ViewingConditionLifecycle) {
      (provider as ViewingConditionLifecycle).invalidateLocalChecks();
    }
  }

  void _endMonitoring() {
    ++_generation;
    _stopListening();
    final provider = conditions;
    if (provider is ViewingConditionLifecycle) {
      (provider as ViewingConditionLifecycle).endSession();
    }
    biometrics.revoke(ended: true);
  }

  /// A visible route calls this after painting the lock screen. Never drop
  /// native protection while the last protected frame may still be on screen.
  void releaseEndedCapture() {
    if (!_closed && sessionEnded) unawaited(_session?.close());
  }

  /// The outgoing content route is gone. Keep the preflight flow reusable,
  /// but only release its lease if a new check hasn't already started.
  void releaseIdleCapture() {
    if (_closed || sessionEnded || _checking || _subscription != null) return;
    final session = _session;
    _session = null;
    session?.removeListener(_protectionChanged);
    session?.dispose();
  }

  /// Person counts are a viewing condition, never identity verification.
  /// Recovery only removes this failure; a fresh complete recheck is required.
  void cameraConditionChanged(ViewingIssueKind? issue) {
    assert(
      issue == null ||
          issue == ViewingIssueKind.multiplePeople ||
          issue == ViewingIssueKind.viewerMissing,
    );
    if (_closed || sessionEnded || _cameraIssue == issue) return;
    _cameraIssue = issue;
    _invalidateEvaluation();
    notifyListeners();
  }

  void _protectionChanged() {
    if (_closed) return;
    if (_session?.screenshotViolation == true) {
      endForSecurityViolation(reason: ViewingIssueKind.screenshot);
    } else {
      if (captureState == CaptureProtectionState.captureActive ||
          captureState == CaptureProtectionState.unavailable) {
        _invalidateEvaluation();
      }
      notifyListeners();
    }
  }

  Future<void> revalidate({bool verifyIdentity = true}) async {
    if (_closed || sessionEnded || !_active) return;
    _evaluations++;
    final generation = ++_generation;
    final failureRevisionAtStart = _failureRevision;
    var completeSnapshotPassed = false;
    _needsRevalidation = true;
    _checking = true;
    _conditionStreamFailed = false;
    _results.clear();
    _revisions.clear();
    notifyListeners();
    if (_closed || sessionEnded || generation != _generation) return;
    void monitoringFailed() {
      if (_closed || sessionEnded || generation != _generation) return;
      _conditionStreamFailed = true;
      _invalidateEvaluation();
      _results.clear();
      notifyListeners();
    }

    _session ??= protection.createSession()..addListener(_protectionChanged);
    final protectionReady = _session!.revalidate();
    try {
      await _cancelConditionSubscription().timeout(checkTimeout);
      if (_closed || sessionEnded || generation != _generation) return;
      _subscription = conditions.changes.listen(
        (updates) {
          if (_closed ||
              sessionEnded ||
              generation != _generation ||
              _conditionStreamFailed) {
            return;
          }
          for (final entry in updates.entries) {
            final required = requiredConditions.contains(entry.key);
            if (required &&
                entry.value == ViewingConditionResult.satisfied &&
                (_needsRevalidation ||
                    _results[entry.key] != ViewingConditionResult.satisfied)) {
              if (!_needsRevalidation) _invalidateEvaluation();
              continue; // Preserve the last unverified failure until recheck.
            }
            if (required && entry.value != ViewingConditionResult.satisfied) {
              _invalidateEvaluation();
            }
            _results[entry.key] = entry.value;
            _revisions[entry.key] = (_revisions[entry.key] ?? 0) + 1;
          }
          _rememberDenials();
          notifyListeners();
        },
        onError: (Object error) => monitoringFailed(),
        onDone: monitoringFailed,
      );
      // A live failure during check() wins over an older successful snapshot.
      final revisionsAtCheck = Map<String, int>.of(_revisions);
      try {
        final checked = await conditions
            .check(restrictions)
            .timeout(checkTimeout);
        if (!_closed &&
            !sessionEnded &&
            generation == _generation &&
            !_conditionStreamFailed) {
          for (final entry in checked.entries) {
            if (_revisions[entry.key] == revisionsAtCheck[entry.key]) {
              _results[entry.key] = entry.value;
            }
          }
          // Missing required snapshot entries cannot be filled by live events.
          for (final id in requiredConditions) {
            _results.putIfAbsent(id, () => ViewingConditionResult.unknown);
          }
          completeSnapshotPassed = requiredConditions.every(
            (id) => checked[id] == ViewingConditionResult.satisfied,
          );
          _rememberDenials();
        }
      } catch (_) {
        monitoringFailed();
      }
    } catch (_) {
      monitoringFailed();
    } finally {
      await protectionReady;
      if (!_closed && generation == _generation) {
        if (completeSnapshotPassed &&
            _cameraIssue == null &&
            !_conditionStreamFailed &&
            _failureRevision == failureRevisionAtStart &&
            _active &&
            !sessionEnded &&
            captureState == CaptureProtectionState.ready &&
            requiredConditions.every(
              (id) => _results[id] == ViewingConditionResult.satisfied,
            )) {
          _needsRevalidation = false;
        }
        _checking = false;
        notifyListeners();
        if (verifyIdentity &&
            !biometrics.approved &&
            !_needsRevalidation &&
            !sessionEnded &&
            _active) {
          // The system prompt can outlast expiry or another sender requirement.
          // Refresh policy/capture after success before allowing camera startup.
          await this.verifyIdentity();
        }
      }
    }
  }

  void suspend({bool backgrounded = true}) {
    if (_closed || sessionEnded) return;
    ++_generation; // Discard any in-flight check from the previous foreground run.
    _active = false;
    _pauseMonitoring();
    _needsRevalidation = true;
    _results.clear();
    biometrics.suspend(backgrounded: backgrounded);
  }

  Future<void> resume({bool recheck = true}) {
    if (_closed || sessionEnded) return Future.value();
    _active = true;
    biometrics.resume();
    if (!recheck) {
      notifyListeners();
      return Future.value();
    }
    return revalidate(verifyIdentity: false);
  }

  void endForSecurityViolation({
    ViewingIssueKind reason = ViewingIssueKind.simulatedViolation,
  }) {
    if (_closed || securityViolation) return;
    assert(
      reason == ViewingIssueKind.screenshot ||
          reason == ViewingIssueKind.phoneDetected ||
          reason == ViewingIssueKind.simulatedViolation,
    );
    _violationReason = reason;
    _endMonitoring();
    if (kDebugMode) {
      debugPrintSynchronously(
        '[ApertureSecurity] timestamp=${DateTime.now().toUtc().toIso8601String()} '
        'controller_id=${identityHashCode(this)} reason=${reason.name} '
        'session_ended=$sessionEnded state=${state.name}',
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    biometrics.removeListener(_biometricChanged);
    biometrics.dispose();
    ++_generation;
    _session?.removeListener(_protectionChanged);
    _stopListening();
    final provider = conditions;
    if (provider is ViewingConditionLifecycle) {
      (provider as ViewingConditionLifecycle).endSession();
    }
    _session?.dispose();
    super.dispose();
  }
}
