import 'dart:async';

import '../widgets/content_restrictions_section.dart';

enum ViewingConditionResult { satisfied, failed, denied, unknown }

abstract final class ViewingCondition {
  static const authorization = 'authorization';
  static const expiration = 'expiration';
  static const viewLimit = 'viewLimit';
  // Mobile provider identifiers, not claims that native/backend adapters exist.
  static const device = 'device';
  static const location = 'location';
  static const presence = 'presence';
}

/// A provider must report every required check, both initially and on change.
/// Missing/unknown results never authorize viewing. Declare mandatory conditions
/// before checking and keep the producer scoped to its viewing session. A
/// controller retains every declared requirement for that session, even if a
/// producer later omits it. Restoration is advisory until a fresh check passes.
/// Location/device identifiers alone do not provide sensor or server evidence.
abstract interface class ViewingConditionProvider {
  Set<String> get requiredConditions;
  Stream<Map<String, ViewingConditionResult>> get changes;
  Future<Map<String, ViewingConditionResult>> check(
    ContentRestrictions restrictions,
  );
}

/// Optional lifecycle for providers that own polls, sensors or remote sessions.
abstract interface class ViewingConditionLifecycle {
  void invalidateLocalChecks();
  void endSession();
}

/// No backend authorization, expiration timestamp or view usage is available yet.
class UnverifiedViewingConditions implements ViewingConditionProvider {
  @override
  Set<String> get requiredConditions => const {};

  @override
  Stream<Map<String, ViewingConditionResult>> get changes =>
      const Stream.empty();

  @override
  Future<Map<String, ViewingConditionResult>> check(
    ContentRestrictions restrictions,
  ) async => const {};
}

/// Drives ONLY the explicitly labeled, non-sensitive placeholder demo.
/// It does not simulate a backend authorization or invent policy timestamps.
class DemoViewingConditions implements ViewingConditionProvider {
  static const condition = 'demoCondition';
  final _changes =
      StreamController<Map<String, ViewingConditionResult>>.broadcast(
        sync: true,
      );
  bool _satisfied = true;

  bool get satisfied => _satisfied;

  @override
  Set<String> get requiredConditions => const {condition};

  @override
  Stream<Map<String, ViewingConditionResult>> get changes => _changes.stream;

  Map<String, ViewingConditionResult> get _snapshot => {
    condition: _satisfied
        ? ViewingConditionResult.satisfied
        : ViewingConditionResult.failed,
  };

  @override
  Future<Map<String, ViewingConditionResult>> check(
    ContentRestrictions restrictions,
  ) async => _snapshot;

  void toggle() {
    _satisfied = !_satisfied;
    _changes.add(_snapshot);
  }

  void dispose() => unawaited(_changes.close());
}
