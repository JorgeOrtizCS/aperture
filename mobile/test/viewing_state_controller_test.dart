import 'dart:async';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/viewing_test_fakes.dart';

void main() {
  late NativeCaptureFake native;
  late ConditionsFake conditions;
  late ScreenCaptureProtection protection;
  final controllers = <ViewingStateController>[];

  setUp(() {
    native = NativeCaptureFake();
    conditions = ConditionsFake();
    protection = ScreenCaptureProtection.forTesting();
    controllers.clear();
  });

  tearDown(() {
    for (final controller in controllers) {
      controller.dispose();
    }
    conditions.dispose();
  });

  ViewingStateController create({ContentRestrictions? policy}) {
    native.install();
    final controller = ViewingStateController(
      restrictions: policy ?? ContentRestrictions.demoDefaults,
      conditions: conditions,
      protection: protection,
    );
    controllers.add(controller);
    return controller;
  }

  testWidgets('starts checking and waits for native AND condition checks', (
    tester,
  ) async {
    native.enabling = Completer<bool>();
    conditions.checking = Completer<Map<String, ViewingConditionResult>>();
    final controller = create();
    expect(controller.state, ViewingState.checking);
    unawaited(controller.revalidate());
    await flushViewing(tester);
    expect(controller.state, ViewingState.checking);
    native.enabling!.complete(false);
    await flushViewing(tester);
    expect(controller.state, ViewingState.checking);
    conditions.checking!.complete(conditions.snapshot);
    await flushViewing(tester);
    expect(controller.state, ViewingState.allowed);
    expect(conditions.lastPolicy, same(ContentRestrictions.demoDefaults));
  });

  testWidgets(
    'live failures remain independent of capture and other conditions',
    (tester) async {
      final controller = create();
      unawaited(controller.revalidate());
      await flushViewing(tester);
      expect(controller.state, ViewingState.allowed);
      conditions.update({
        'presence': ViewingConditionResult.failed,
        'location': ViewingConditionResult.failed,
      });
      expect(controller.state, ViewingState.temporarilyLocked);
      native.setCapture(true);
      await flushViewing(tester);
      conditions.update({'presence': ViewingConditionResult.satisfied});
      expect(controller.state, ViewingState.temporarilyLocked);
      native.setCapture(false);
      await flushViewing(tester);
      expect(controller.state, ViewingState.temporarilyLocked);
      conditions.update({'location': ViewingConditionResult.satisfied});
      expect(controller.state, ViewingState.temporarilyLocked);
      expect(conditions.checks, 1);
      expect(native.enables, 1);
      unawaited(controller.revalidate());
      await flushViewing(tester);
      expect(controller.state, ViewingState.allowed);
      expect(conditions.checks, 2);
      expect(native.enables, 2);
    },
  );

  testWidgets('explicit denial never authorizes content', (tester) async {
    conditions.snapshot[ViewingCondition.authorization] =
        ViewingConditionResult.denied;
    final controller = create();
    unawaited(controller.revalidate());
    await flushViewing(tester);
    expect(controller.state, ViewingState.accessDenied);
  });

  testWidgets(
    'missing authorization, expiration or finite usage fails closed',
    (tester) async {
      final controller = create();
      for (final check in [
        ViewingCondition.authorization,
        ViewingCondition.expiration,
        ViewingCondition.viewLimit,
      ]) {
        final known = Map.of(conditions.snapshot);
        conditions.snapshot.remove(check);
        unawaited(controller.revalidate());
        await flushViewing(tester);
        expect(controller.state, ViewingState.temporarilyLocked, reason: check);
        conditions.snapshot = known;
      }
    },
  );

  testWidgets('unlimited policy does not require an invented usage counter', (
    tester,
  ) async {
    conditions.snapshot.remove(ViewingCondition.viewLimit);
    final controller = create(
      policy: ContentRestrictions.demoDefaults.copyWith(clearViewLimit: true),
    );
    unawaited(controller.revalidate());
    await flushViewing(tester);
    expect(controller.state, ViewingState.allowed);
  });

  for (final error in [
    MissingPluginException(),
    PlatformException(code: 'unavailable'),
  ]) {
    testWidgets(
      'native initialization failure is unavailable: ${error.runtimeType}',
      (tester) async {
        native.enableError = error;
        final controller = create();
        unawaited(controller.revalidate());
        await flushViewing(tester);
        expect(controller.state, ViewingState.protectionUnavailable);
      },
    );
  }

  testWidgets('missing initialization response is unavailable', (tester) async {
    native.nullResult = true;
    final controller = create();
    unawaited(controller.revalidate());
    await flushViewing(tester);
    expect(controller.state, ViewingState.protectionUnavailable);
  });

  testWidgets(
    'event error during initialization cannot be cleared by method success',
    (tester) async {
      native.enabling = Completer<bool>();
      final controller = create();
      unawaited(controller.revalidate());
      await flushViewing(tester);
      native.events!.error(code: 'monitor_failed');
      await flushViewing(tester);
      native.enabling!.complete(false);
      await flushViewing(tester);
      expect(controller.state, ViewingState.protectionUnavailable);
      native.setCapture(false);
      await flushViewing(tester);
      expect(controller.state, ViewingState.protectionUnavailable);
    },
  );

  testWidgets(
    'native event errors and stream closure fail closed after viewing',
    (tester) async {
      final controller = create();
      unawaited(controller.revalidate());
      await flushViewing(tester);
      expect(controller.state, ViewingState.allowed);
      native.events!.error(code: 'monitor_failed');
      await flushViewing(tester);
      expect(controller.state, ViewingState.protectionUnavailable);
      native.events!.endOfStream();
      await flushViewing(tester);
      expect(controller.state, ViewingState.protectionUnavailable);
    },
  );

  testWidgets('native handshake and initialization timeout fail closed', (
    tester,
  ) async {
    native.sendInitialEvent = false;
    final controller = create();
    unawaited(controller.revalidate());
    await flushViewing(tester);
    expect(controller.state, ViewingState.checking);
    await tester.pump(const Duration(seconds: 6));
    await flushViewing(tester);
    expect(controller.state, ViewingState.protectionUnavailable);
  });

  testWidgets('malformed native events fail closed', (tester) async {
    final controller = create();
    unawaited(controller.revalidate());
    await flushViewing(tester);
    native.events!.success({'type': 'capture', 'active': 'false'});
    await flushViewing(tester);
    expect(controller.state, ViewingState.protectionUnavailable);
  });

  testWidgets('condition monitoring error cannot be cleared by a stale check', (
    tester,
  ) async {
    conditions.checking = Completer<Map<String, ViewingConditionResult>>();
    final controller = create();
    unawaited(controller.revalidate());
    await flushViewing(tester);
    conditions.stream.addError(StateError('monitor unavailable'));
    conditions.checking!.complete(conditions.snapshot);
    await flushViewing(tester);
    expect(controller.state, ViewingState.temporarilyLocked);
  });

  testWidgets('live failure wins over an older successful check snapshot', (
    tester,
  ) async {
    conditions.checking = Completer<Map<String, ViewingConditionResult>>();
    final stale = Map.of(conditions.snapshot);
    final controller = create();
    unawaited(controller.revalidate());
    await flushViewing(tester);
    conditions.update({'presence': ViewingConditionResult.failed});
    conditions.checking!.complete(stale);
    await flushViewing(tester);
    expect(controller.state, ViewingState.temporarilyLocked);
  });

  testWidgets(
    'background invalidates pending results and resume rechecks both sources',
    (tester) async {
      final controller = create();
      unawaited(controller.revalidate());
      await flushViewing(tester);
      controller.suspend();
      expect(controller.state, ViewingState.temporarilyLocked);
      conditions.checking = Completer<Map<String, ViewingConditionResult>>();
      unawaited(controller.resume());
      await flushViewing(tester);
      expect(controller.state, ViewingState.checking);
      expect(native.enables, 2);
      expect(conditions.checks, 2);
      conditions.checking!.complete(conditions.snapshot);
      await flushViewing(tester);
      expect(controller.state, ViewingState.allowed);
    },
  );

  testWidgets(
    'old cleanup cannot disable a newer session and repeated close is safe',
    (tester) async {
      native.enabling = Completer<bool>();
      native.install();
      final first = protection.createSession();
      unawaited(first.revalidate());
      await flushViewing(tester);
      final close1 = first.close();
      final close2 = first.close();
      expect(close1, same(close2));
      final second = protection.createSession();
      unawaited(second.revalidate());
      native.enabling!.complete(false);
      await flushViewing(tester);
      expect(second.state, CaptureProtectionState.ready);
      expect(native.calls, [
        'enableProtection',
        'disableProtection',
        'enableProtection',
      ]);
      await first.close();
      expect(native.disables, 1);
      first.dispose();
      unawaited(second.close());
      await flushViewing(tester);
      expect(native.disables, 2);
      second.dispose();
    },
  );

  testWidgets('cleanup failure cannot authorize a replacement session', (
    tester,
  ) async {
    native.install();
    final first = protection.createSession();
    unawaited(first.revalidate());
    await flushViewing(tester);
    native.disableError = PlatformException(code: 'cleanup_failed');
    unawaited(first.close());
    await flushViewing(tester);
    final second = protection.createSession();
    unawaited(second.revalidate());
    await flushViewing(tester);
    expect(second.state, CaptureProtectionState.unavailable);
    first.dispose();
    second.dispose();
  });

  testWidgets('a stalled native enable becomes unavailable', (tester) async {
    native.enabling = Completer<bool>();
    final controller = create();
    unawaited(controller.revalidate());
    await flushViewing(tester);
    await tester.pump(const Duration(seconds: 6));
    await flushViewing(tester);
    expect(controller.state, ViewingState.protectionUnavailable);
    native.enabling!.complete(false);
    await flushViewing(tester);
    expect(controller.state, ViewingState.protectionUnavailable);
  });

  testWidgets('condition check failure and timeout do not authorize viewing', (
    tester,
  ) async {
    conditions.checkError = StateError('verification failed');
    final controller = create();
    unawaited(controller.revalidate());
    await flushViewing(tester);
    expect(controller.state, ViewingState.temporarilyLocked);
    conditions.checkError = null;
    conditions.checking = Completer<Map<String, ViewingConditionResult>>();
    unawaited(controller.revalidate());
    await flushViewing(tester);
    await tester.pump(const Duration(seconds: 6));
    await flushViewing(tester);
    expect(controller.state, ViewingState.temporarilyLocked);
    conditions.checking!.complete(conditions.snapshot);
    await flushViewing(tester);
    expect(controller.state, ViewingState.temporarilyLocked);
  });

  testWidgets(
    'background discards a successful result from an earlier foreground check',
    (tester) async {
      final oldCheck = Completer<Map<String, ViewingConditionResult>>();
      conditions.checking = oldCheck;
      final controller = create();
      unawaited(controller.revalidate());
      await flushViewing(tester);
      controller.suspend();
      conditions.checking = Completer<Map<String, ViewingConditionResult>>();
      unawaited(controller.resume());
      await flushViewing(tester);
      oldCheck.complete(conditions.snapshot);
      await flushViewing(tester);
      expect(controller.state, ViewingState.checking);
      conditions.checking!.complete({
        ...conditions.snapshot,
        'presence': ViewingConditionResult.failed,
      });
      await flushViewing(tester);
      expect(controller.state, ViewingState.temporarilyLocked);
    },
  );

  testWidgets('an initially active recording locks without exposing content', (
    tester,
  ) async {
    native.capture = true;
    final controller = create();
    unawaited(controller.revalidate());
    await flushViewing(tester);
    expect(controller.state, ViewingState.temporarilyLocked);
    native.setCapture(false);
    await flushViewing(tester);
    expect(controller.state, ViewingState.temporarilyLocked);
    unawaited(controller.revalidate());
    await flushViewing(tester);
    expect(controller.state, ViewingState.allowed);
  });
}
