import 'dart:async';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/screens/secure_content_viewer_screen.dart';
import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/services/biometric_verification.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:aperture/widgets/viewing_status_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/biometric_fake.dart';
import 'support/viewing_test_fakes.dart';

// Host integration: real routes, shared controller and service implementations.
// Native channel events, identity and policy decisions are TEST FIXTURES ONLY.
// A satisfied provider is not evidence of real account/backend authorization.
final _protected = find.byKey(
  const ValueKey('protected-render-placeholder'),
  skipOffstage: false,
);

class _SecurityFlow {
  _SecurityFlow(this.tester, {NativeCaptureFake? native})
    : native = native ?? NativeCaptureFake();

  final WidgetTester tester;
  final NativeCaptureFake native;
  final biometric = BiometricFake();
  final conditions = ConditionsFake(
    requiredConditions: {
      ViewingCondition.device,
      ViewingCondition.location,
      ViewingCondition.presence,
    },
  );
  final navigator = GlobalKey<NavigatorState>();
  late ViewingStateController controller;

  Future<void> mount({bool check = true, bool open = true}) async {
    conditions.snapshot.putIfAbsent(
      ViewingCondition.device,
      () => ViewingConditionResult.satisfied,
    );
    native.install();
    addTearDown(conditions.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await flushViewing(tester);
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: AppTheme.theme,
        home: SecureViewerScreen(
          contentTitle: 'Task 10.3 test-only placeholder',
          conditionProvider: conditions,
          biometricAuthenticator: biometric,
          captureProtection: ScreenCaptureProtection.forTesting(),
          cameraDetection: native.camera.service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller = tester
        .widget<ViewingStatusPanel>(find.byType(ViewingStatusPanel).first)
        .controller;
    if (check) {
      await tap('Check Conditions');
      await flushViewing(tester);
    }
    if (open && controller.state == ViewingState.allowed) {
      await tap('Open Secure Content');
      await settle();
    }
  }

  Future<void> tap(String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await frame();
  }

  Future<void> frame() async {
    // Drain channel delivery before the next rendered Flutter frame.
    await tester.idle();
    await tester.pump();
  }

  Future<void> settle() async {
    await flushViewing(tester);
    await tester.pumpAndSettle();
  }

  Future<void> top() async {
    await settle();
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
  }

  Future<void> locked(String warning, {required bool ended}) async {
    expect(_protected, findsNothing);
    expect(controller.state, isNot(ViewingState.allowed));
    expect(controller.sessionEnded, ended);
    if (ended) {
      expect(controller.canRecheck, isFalse);
      expect(controller.biometrics.approved, isFalse);
    }
    await top();
    expect(find.text(warning), findsWidgets);
    expect(tester.takeException(), isNull);
    debugPrint(
      '[IntegratedSecurity] warning="$warning" '
      'state=${controller.state.name} ended=${controller.sessionEnded} '
      'identity=${controller.biometrics.state.name} '
      'capture=${controller.captureState.name} '
      'protected_widgets=${_protected.evaluate().length} '
      'can_recheck=${controller.canRecheck}',
    );
  }

  Future<void> retryIdentity() async {
    unawaited(controller.verifyIdentity());
    await settle();
  }

  Future<void> recheck() async {
    unawaited(controller.revalidate());
    await settle();
  }
}

void main() {
  testWidgets('S01 biometric + all gates permit only the monitored subtree', (
    tester,
  ) async {
    final f = _SecurityFlow(tester);
    await f.mount();
    expect(f.controller.biometrics.approved, isTrue);
    expect(f.controller.state, ViewingState.allowed);
    expect(f.controller.sessionEnded, isFalse);
    expect(_protected, findsOneWidget);
    expect(find.text('Checks passed'), findsOneWidget);
    f.native.camera.event();
    await f.frame();
    expect(_protected, findsOneWidget);
  });

  testWidgets('S02 camera violation wins after biometric success', (
    tester,
  ) async {
    final f = _SecurityFlow(tester);
    await f.mount();
    expect(f.controller.biometrics.approved, isTrue);
    f.native.camera.event(phone: true);
    await f.frame();
    expect(_protected, findsNothing);
    await f.locked('Phone detected', ended: true);
    f.native.camera.event();
    await f.retryIdentity();
    await f.locked('Phone detected', ended: true);
  });

  for (final pair in [
    (3, ViewingCondition.device, 'Device security failed'),
    (4, ViewingCondition.location, 'Approved location failed'),
  ]) {
    testWidgets('S0${pair.$1} biometric success cannot override ${pair.$2}', (
      tester,
    ) async {
      final f = _SecurityFlow(tester);
      await f.mount();
      f.conditions.update({pair.$2: ViewingConditionResult.failed});
      await f.frame();
      expect(_protected, findsNothing);
      await f.retryIdentity();
      expect(f.controller.biometrics.approved, isTrue);
      await f.locked(pair.$3, ended: false);
      f.native.camera.event();
      await f.frame();
      await f.locked(pair.$3, ended: false);
    });
  }

  testWidgets('S05 screenshot ends an already authorized local fixture', (
    tester,
  ) async {
    final f = _SecurityFlow(tester);
    await f.mount();
    expect(_protected, findsOneWidget);
    f.native.events!.success({'type': 'screenshot'});
    await f.frame();
    expect(_protected, findsNothing);
    await f.locked('Screenshot detected', ended: true);
    f.native.setCapture(false);
    await f.retryIdentity();
    await f.recheck();
    await f.locked('Screenshot detected', ended: true);
  });

  testWidgets(
    'S06 recording cannot be overridden by identity or clear camera',
    (tester) async {
      final f = _SecurityFlow(tester);
      await f.mount();
      f.native.setCapture(true);
      await f.frame();
      expect(_protected, findsNothing);
      f.native.camera.event();
      await f.retryIdentity();
      await f.locked('Screen capture detected', ended: false);
      expect(f.controller.biometrics.approved, isTrue);
    },
  );

  testWidgets('S07 camera still terminates while a device gate is failed', (
    tester,
  ) async {
    final f = _SecurityFlow(tester);
    await f.mount();
    f.conditions.update({
      ViewingCondition.device: ViewingConditionResult.failed,
    });
    await f.frame();
    await f.locked('Device security failed', ended: false);
    f.native.camera.event(phone: true);
    await f.frame();
    await f.locked('Phone detected', ended: true);
    f.conditions.update({
      ViewingCondition.device: ViewingConditionResult.satisfied,
    });
    await f.recheck();
    await f.locked('Phone detected', ended: true);
  });

  for (final screenshotFirst in [true, false]) {
    testWidgets(
      'S08 simultaneous phone/screenshot, screenshotFirst=$screenshotFirst',
      (tester) async {
        final f = _SecurityFlow(tester);
        await f.mount();
        void screenshot() => f.native.events!.success({'type': 'screenshot'});
        void phone() => f.native.camera.event(phone: true);
        (screenshotFirst ? screenshot : phone)();
        (screenshotFirst ? phone : screenshot)();
        await f.frame();
        expect(_protected, findsNothing);
        final reason = f.controller.violationReason;
        expect(
          reason,
          anyOf(ViewingIssueKind.screenshot, ViewingIssueKind.phoneDetected),
        );
        final title = reason == ViewingIssueKind.screenshot
            ? 'Screenshot detected'
            : 'Phone detected';
        await f.locked(title, ended: true);
        f.native.camera.event();
        f.native.setCapture(false);
        await f.retryIdentity();
        expect(f.controller.violationReason, reason);
        await f.locked(title, ended: true);
      },
    );
  }

  testWidgets('S09 restored capture/device cannot bypass a failed location', (
    tester,
  ) async {
    final f = _SecurityFlow(tester);
    await f.mount();
    f.native.setCapture(true);
    f.conditions.update({
      ViewingCondition.device: ViewingConditionResult.failed,
      ViewingCondition.location: ViewingConditionResult.failed,
    });
    await f.frame();
    expect(_protected, findsNothing);
    f.native.setCapture(false);
    f.conditions.update({
      ViewingCondition.device: ViewingConditionResult.satisfied,
    });
    await f.recheck();
    await f.locked('Approved location failed', ended: false);
    f.conditions.update({
      ViewingCondition.location: ViewingConditionResult.satisfied,
    });
    await f.frame();
    expect(_protected, findsNothing);
    await f.recheck();
    expect(f.controller.state, ViewingState.allowed);
    expect(f.controller.sessionEnded, isFalse);
    expect(_protected, findsOneWidget);
    expect(find.text('Checks passed'), findsOneWidget);
  });

  testWidgets('S10 permanent termination refuses another successful verifier', (
    tester,
  ) async {
    final f = _SecurityFlow(tester);
    await f.mount();
    f.conditions.update({
      ViewingCondition.device: ViewingConditionResult.denied,
    });
    await f.frame();
    final prompts = f.biometric.starts;
    await f.retryIdentity();
    expect(f.biometric.starts, prompts);
    expect(f.controller.biometrics.state, BiometricState.ended);
    f.conditions.update({
      ViewingCondition.device: ViewingConditionResult.satisfied,
    });
    f.native.camera.event();
    await f.recheck();
    await f.locked('Device security denied', ended: true);
  });

  testWidgets('S11 termination invalidates pending biometric success', (
    tester,
  ) async {
    final f = _SecurityFlow(tester);
    f.biometric.pending = Completer<BiometricState>();
    await f.mount(open: false);
    expect(f.controller.biometrics.state, BiometricState.verifying);
    f.native.events!.success({'type': 'screenshot'});
    await f.frame();
    f.biometric.pending!.complete(BiometricState.verified);
    await f.settle();
    expect(f.native.camera.starts, 0);
    expect(f.controller.biometrics.state, BiometricState.ended);
    await f.locked('Screenshot detected', ended: true);
  });

  testWidgets('S12 background hides and requires new identity and camera run', (
    tester,
  ) async {
    final f = _SecurityFlow(tester);
    await f.mount();
    final oldRun = f.native.camera.token;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await f.frame();
    expect(_protected, findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await f.settle();
    await f.locked('App inactive', ended: false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await f.settle();
    expect(f.controller.biometrics.approved, isFalse);
    expect(_protected, findsNothing);
    f.native.camera.sendInitial = false;
    await f.retryIdentity();
    f.native.camera.event(sessionId: oldRun);
    await f.frame();
    expect(_protected, findsNothing);
    f.native.camera.event();
    await f.frame();
    expect(_protected, findsOneWidget);
    expect(f.controller.sessionEnded, isFalse);
  });

  testWidgets('S13 foreground cannot recover a permanently violated session', (
    tester,
  ) async {
    final f = _SecurityFlow(tester);
    await f.mount();
    f.native.camera.event(phone: true);
    await f.frame();
    await f.settle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await f.frame();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await f.settle();
    await f.retryIdentity();
    await f.locked('Phone detected', ended: true);
  });

  testWidgets(
    'S14 late access and capture callbacks cannot rewrite termination',
    (tester) async {
      final f = _SecurityFlow(tester);
      await f.mount();
      final old = Map.of(f.conditions.snapshot);
      f.conditions.checking = Completer<Map<String, ViewingConditionResult>>();
      unawaited(f.controller.revalidate());
      await f.settle();
      f.native.events!.success({'type': 'screenshot'});
      await f.frame();
      final terminal = f.controller.results;
      f.conditions.checking!.complete(old);
      f.conditions.update({
        ViewingCondition.device: ViewingConditionResult.satisfied,
      });
      f.native.camera.event();
      f.native.setCapture(false);
      await f.settle();
      expect(f.controller.results, terminal);
      await f.locked('Screenshot detected', ended: true);
    },
  );

  testWidgets(
    'S15 replaced session cannot inherit pending identity or access',
    (tester) async {
      final first = _SecurityFlow(tester);
      first.conditions.checking =
          Completer<Map<String, ViewingConditionResult>>();
      first.biometric.pending = Completer<BiometricState>();
      await first.mount(open: false);
      unawaited(first.controller.verifyIdentity());
      await first.settle();
      await tester.pumpWidget(const SizedBox());
      await first.settle();
      final second = _SecurityFlow(tester, native: first.native);
      second.biometric.pending = Completer<BiometricState>();
      await second.mount(open: false);
      expect(second.controller.biometrics.state, BiometricState.verifying);
      first.conditions.checking!.complete(first.conditions.snapshot);
      first.biometric.pending!.complete(BiometricState.verified);
      await second.settle();
      expect(_protected, findsNothing);
      expect(second.controller.biometrics.approved, isFalse);
      expect(second.native.camera.starts, 0);
      await second.top();
      expect(find.text('Verification in progress'), findsWidgets);
      second.biometric.pending!.complete(BiometricState.verified);
      await second.settle();
      await second.tap('Open Secure Content');
      await second.settle();
      expect(second.controller.sessionEnded, isFalse);
      expect(second.controller.state, ViewingState.allowed);
      expect(_protected, findsOneWidget);
    },
  );

  testWidgets(
    'S16 authentication cancellation defeats a pending access check',
    (tester) async {
      final f = _SecurityFlow(tester);
      f.conditions.checking = Completer<Map<String, ViewingConditionResult>>();
      f.biometric.pending = Completer<BiometricState>();
      await f.mount(open: false);
      unawaited(f.controller.verifyIdentity());
      await f.settle();
      f.biometric.pending!.complete(BiometricState.cancelled);
      await f.settle();
      expect(_protected, findsNothing);
      f.conditions.checking!.complete(f.conditions.snapshot);
      await f.settle();
      expect(f.controller.biometrics.state, BiometricState.cancelled);
      expect(f.native.camera.starts, 0);
      await f.locked('Verification cancelled', ended: false);
      f.native.camera.event();
      await f.frame();
      expect(_protected, findsNothing);
    },
  );

  testWidgets('S17 unavailable mandatory state defeats all local successes', (
    tester,
  ) async {
    final f = _SecurityFlow(tester);
    f.conditions.snapshot[ViewingCondition.device] =
        ViewingConditionResult.unknown;
    await f.mount(open: false);
    await f.retryIdentity();
    expect(f.controller.biometrics.approved, isTrue);
    expect(f.native.camera.starts, 0);
    await f.locked('Device security not confirmed', ended: false);
    f.native.camera.event();
    await f.recheck();
    await f.locked('Device security not confirmed', ended: false);
  });

  testWidgets('S18 provider authorization denial overrides local success', (
    tester,
  ) async {
    final f = _SecurityFlow(tester);
    await f.mount();
    expect(_protected, findsOneWidget);
    // Supported mobile provider boundary, NOT a real backend HTTP response.
    f.conditions.update({
      ViewingCondition.authorization: ViewingConditionResult.denied,
    });
    await f.frame();
    expect(_protected, findsNothing);
    f.native.camera.event();
    f.native.setCapture(false);
    f.conditions.update({
      ViewingCondition.authorization: ViewingConditionResult.satisfied,
    });
    await f.retryIdentity();
    await f.recheck();
    await f.locked('Authorization denied', ended: true);
  });

  testWidgets('S19 event bursts do not clear capture latch or repeat exit', (
    tester,
  ) async {
    final f = _SecurityFlow(tester);
    await f.mount();
    for (var i = 0; i < 10; i++) {
      f.native.setCapture(true);
      f.native.camera.event();
    }
    await f.frame();
    await f.locked('Screen capture detected', ended: false);
    for (var i = 0; i < 10; i++) {
      f.native.setCapture(false);
    }
    await f.frame();
    expect(_protected, findsNothing);
    for (var i = 0; i < 10; i++) {
      f.native.camera.event(phone: true);
    }
    await f.frame();
    for (var i = 0; i < 10; i++) {
      f.native.camera.event();
      f.native.events!.success({'type': 'screenshot'});
    }
    await f.settle();
    await f.locked('Phone detected', ended: true);
    expect(f.native.camera.stops, 1);
    expect(find.byType(SecureViewerScreen), findsOneWidget);
    expect(find.byType(SecureContentViewerScreen), findsNothing);
    await f.retryIdentity();
    await f.locked('Phone detected', ended: true);
  });

  testWidgets('S20 ended navigation cannot construct content on direct entry', (
    tester,
  ) async {
    final f = _SecurityFlow(tester);
    await f.mount();
    f.native.camera.event(phone: true);
    await f.frame();
    await f.locked('Phone detected', ended: true);
    await tester.scrollUntilVisible(
      find.text('Open Secure Content'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Open Secure Content'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Open Demo Preview'), findsNothing);
    unawaited(
      f.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => SecureContentViewerScreen(
            contentTitle: 'Forced entry into the same ended session',
            restrictions: ContentRestrictions.demoDefaults,
            viewingController: f.controller,
            cameraDetection: f.native.camera.service,
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await f.frame();
      expect(_protected, findsNothing);
    }
    await f.settle();
    await f.locked('Phone detected', ended: true);
  });
}
