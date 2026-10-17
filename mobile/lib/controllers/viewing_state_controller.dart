import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/screen_capture_protection.dart';
import '../services/viewing_conditions.dart';
import '../widgets/content_restrictions_section.dart';

enum ViewingIssueKind {
  screenshot,
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
    this.demoPreview = false,
    this.checkTimeout = const Duration(seconds: 5),
  });

  final ContentRestrictions restrictions;
  final ViewingConditionProvider conditions;

  /// Only the viewer's non-sensitive placeholder demo may omit real policy checks.
  final bool demoPreview;
  final Duration checkTimeout;
  final ScreenCaptureProtection protection;
  ScreenCaptureSession? _session;
  final Map<String, ViewingConditionResult> _deniedResults = {};
  final Map<String, ViewingConditionResult> _results = {};
  final Map<String, int> _revisions = {};
  StreamSubscription<Map<String, ViewingConditionResult>>? _subscription;
  bool _checking = true;
  // Live recovery signals are advisory: only a complete fresh evaluation can
  // release a lock. A failure during an evaluation invalidates its snapshot.
  bool _needsRevalidation = true;
  int _failureRevision = 0;
  bool _active = true;
  bool _closed = false;
  bool _conditionStreamFailed = false;
  ViewingIssueKind? _violationReason;
  int _evaluations = 0;
  int _generation = 0;

  Set<String> get requiredConditions => {
    ...conditions.requiredConditions,
    if (!demoPreview) ...{
      ViewingCondition.authorization,
      // A duration alone is insufficient: the provider needs a real timestamp.
      ViewingCondition.expiration,
      if (restrictions.viewLimit != null) ViewingCondition.viewLimit,
    },
  };

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
  }

  ViewingState get state {
    if (sessionEnded) return ViewingState.accessDenied;
    if (_closed || !_active) return ViewingState.temporarilyLocked;
    if (captureState == CaptureProtectionState.unavailable) {
      return ViewingState.protectionUnavailable;
    }
    if (_checking || captureState == CaptureProtectionState.checking) {
      return ViewingState.checking;
    }
    if (requiredConditions.any(
      (id) => _results[id] == ViewingConditionResult.denied,
    )) {
      return ViewingState.accessDenied;
    }
    if (_needsRevalidation ||
        _conditionStreamFailed ||
        requiredConditions.any(
          (id) => _results[id] != ViewingConditionResult.satisfied,
        ) ||
        captureState == CaptureProtectionState.captureActive) {
      return ViewingState.temporarilyLocked;
    }
    return ViewingState.allowed;
  }

  void _invalidateEvaluation() {
    _needsRevalidation = true;
    _failureRevision++;
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

  Future<void> revalidate() async {
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
    void monitoringFailed() {
      if (_closed || generation != _generation) return;
      _conditionStreamFailed = true;
      _invalidateEvaluation();
      _results.clear();
      notifyListeners();
    }

    _session ??= protection.createSession()..addListener(_protectionChanged);
    final protectionReady = _session!.revalidate();
    try {
      await _subscription?.cancel().timeout(checkTimeout);
      if (_closed || generation != _generation) return;
      _subscription = conditions.changes.listen(
        (updates) {
          if (_closed || generation != _generation || _conditionStreamFailed) {
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
        if (!_closed && generation == _generation && !_conditionStreamFailed) {
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
      }
    }
  }

  void suspend() {
    if (_closed) return;
    ++_generation; // Discard any in-flight check from the previous foreground run.
    _active = false;
    _needsRevalidation = true;
    _results.clear();
    notifyListeners();
  }

  Future<void> resume({bool recheck = true}) {
    if (_closed) return Future.value();
    _active = true;
    if (!recheck) {
      notifyListeners();
      return Future.value();
    }
    return revalidate();
  }

  void endForSecurityViolation({
    ViewingIssueKind reason = ViewingIssueKind.simulatedViolation,
  }) {
    if (_closed || securityViolation) return;
    assert(
      reason == ViewingIssueKind.screenshot ||
          reason == ViewingIssueKind.simulatedViolation,
    );
    _violationReason = reason;
    ++_generation;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    ++_generation;
    _session?.removeListener(_protectionChanged);
    unawaited(
      _subscription?.cancel().catchError((Object error) {
        debugPrint('Viewing-condition cleanup failed: $error');
      }),
    );
    _session?.dispose();
    super.dispose();
  }
}
