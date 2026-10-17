import 'dart:async';

import '../widgets/content_restrictions_section.dart';

enum ViewingConditionResult { satisfied, failed, denied, unknown }

abstract final class ViewingCondition {
  static const authorization = 'authorization';
  static const expiration = 'expiration';
  static const viewLimit = 'viewLimit';
}

/// A provider must report every required check, both initially and on change.
/// Missing/unknown results never authorize viewing. Future location/presence
/// adapters can add identifiers without changing the viewer or native bridge.
abstract interface class ViewingConditionProvider {
  Set<String> get requiredConditions;
  Stream<Map<String, ViewingConditionResult>> get changes;
  Future<Map<String, ViewingConditionResult>> check(
    ContentRestrictions restrictions,
  );
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
