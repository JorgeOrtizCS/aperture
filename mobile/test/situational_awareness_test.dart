import 'dart:async';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/screens/secure_content_viewer_screen.dart';
import 'package:aperture/services/biometric_verification.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/biometric_fake.dart';
import 'support/viewing_test_fakes.dart';

// Deterministic host fixtures only. Device/location results and all native
// channels here are simulated; these tests make no backend or hardware claim.
void main() {
  late NativeCaptureFake native;
  late ConditionsFake conditions;
  late BiometricFake biometric;
  late ViewingStateController controller;
  final protected = find.byKey(
    const ValueKey('protected-render-placeholder'),
    skipOffstage: false,
  );

  setUp(() {
    native = NativeCaptureFake()..install();
    biometric = BiometricFake();
    conditions = ConditionsFake(
      requiredConditions: {'device', 'location', 'presence'},
    );
    conditions.snapshot['device'] = ViewingConditionResult.satisfied;
    controller = ViewingStateController(
      restrictions: ContentRestrictions.demoDefaults,
      conditions: conditions,
      protection: ScreenCaptureProtection.forTesting(),
      biometricAuthenticator: biometric,
    );
  });

  tearDown(() {
    controller.dispose();
    conditions.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await flushViewing(tester);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: SecureContentViewerScreen(
          contentTitle: 'Simulated security fixture',
          restrictions: ContentRestrictions.demoDefaults,
          viewingController: controller,
          cameraDetection: native.camera.service,
        ),
      ),
    );
    unawaited(controller.revalidate());
    await flushViewing(tester);
  }

  Future<void> recheck(WidgetTester tester) async {
    unawaited(controller.revalidate());
    await flushViewing(tester);
  }

  testWidgets('all independent checks precede the protected subtree', (
    tester,
  ) async {
    native.camera.sendInitial = false;
    await mount(tester);
    expect(controller.biometrics.approved, isTrue);
    expect(protected, findsNothing);
    native.camera.event();
    await tester.idle();
    await tester.pump();
    expect(protected, findsOneWidget);
  });

  testWidgets('phone event hides next frame and permanently ends the flow', (
    tester,
  ) async {
    await mount(tester);
    expect(protected, findsOneWidget);
    native.camera.event(phone: true);
    await tester.idle();
    await tester.pump();
    expect(protected, findsNothing);
    expect(controller.violationReason, ViewingIssueKind.phoneDetected);
    expect(find.text('Phone detected'), findsOneWidget);
    native.camera.event();
    await recheck(tester);
    expect(controller.sessionEnded, isTrue);
    expect(protected, findsNothing);
  });

  testWidgets('screenshot ends session before late clear/capture events', (
    tester,
  ) async {
    await mount(tester);
    native.events!.success({'type': 'screenshot'});
    await tester.idle();
    await tester.pump();
    expect(protected, findsNothing);
    expect(find.text('Screenshot detected'), findsOneWidget);
    native.setCapture(false);
    native.camera.event();
    await recheck(tester);
    expect(controller.violationReason, ViewingIssueKind.screenshot);
    expect(controller.biometrics.approved, isFalse);
    expect(protected, findsNothing);
  });

  testWidgets('recording stops viewing and stopping needs explicit recheck', (
    tester,
  ) async {
    await mount(tester);
    native.setCapture(true);
    await tester.idle();
    await tester.pump();
    expect(protected, findsNothing);
    expect(find.text('Screen capture detected'), findsOneWidget);
    native.setCapture(false);
    await tester.idle();
    await tester.pump();
    expect(protected, findsNothing);
    expect(controller.sessionEnded, isFalse);
    await recheck(tester);
    expect(protected, findsOneWidget);
  });

  for (final condition in ['device', 'location', 'presence']) {
    testWidgets('$condition failure is a separate mandatory gate', (
      tester,
    ) async {
      await mount(tester);
      conditions.update({condition: ViewingConditionResult.failed});
      await tester.idle();
      await tester.pump();
      expect(protected, findsNothing);
      expect(controller.sessionEnded, isFalse);
      final label = switch (condition) {
        'device' => 'Device security',
        'location' => 'Approved location',
        _ => 'Viewer presence',
      };
      expect(find.text('$label failed'), findsOneWidget);
      native.camera.event();
      await tester.idle();
      await tester.pump();
      expect(protected, findsNothing);
      conditions.update({condition: ViewingConditionResult.satisfied});
      await tester.idle();
      await tester.pump();
      expect(protected, findsNothing);
      await recheck(tester);
      expect(protected, findsOneWidget);
    });
  }

  testWidgets('simultaneous failures retain every independent warning', (
    tester,
  ) async {
    await mount(tester);
    conditions.update({
      'device': ViewingConditionResult.failed,
      'location': ViewingConditionResult.failed,
    });
    native.setCapture(true);
    await tester.idle();
    await tester.pump();
    expect(protected, findsNothing);
    expect(find.text('Device security failed'), findsOneWidget);
    expect(find.text('Approved location failed'), findsOneWidget);
    expect(find.text('Screen capture detected'), findsOneWidget);
    conditions.update({'device': ViewingConditionResult.satisfied});
    native.setCapture(false);
    await recheck(tester);
    expect(protected, findsNothing);
    expect(find.text('Approved location failed'), findsOneWidget);
    conditions.update({'location': ViewingConditionResult.satisfied});
    await recheck(tester);
    expect(protected, findsOneWidget);
  });

  testWidgets('explicit device denial remains permanent after restoration', (
    tester,
  ) async {
    await mount(tester);
    conditions.update({'device': ViewingConditionResult.denied});
    await tester.idle();
    await tester.pump();
    expect(find.text('Device security denied'), findsOneWidget);
    conditions.update({'device': ViewingConditionResult.satisfied});
    await recheck(tester);
    expect(controller.state, ViewingState.accessDenied);
    expect(controller.results['device'], ViewingConditionResult.denied);
    expect(controller.canRecheck, isFalse);
    expect(protected, findsNothing);
  });

  testWidgets('background return waits for identity and a new camera run', (
    tester,
  ) async {
    await mount(tester);
    final oldToken = native.camera.token;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.idle();
    await tester.pump();
    expect(protected, findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await flushViewing(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flushViewing(tester);
    expect(controller.biometrics.approved, isFalse);
    expect(protected, findsNothing);
    native.camera.event(sessionId: oldToken);
    await tester.idle();
    await tester.pump();
    expect(protected, findsNothing);
    native.camera.sendInitial = false;
    unawaited(controller.verifyIdentity());
    await flushViewing(tester);
    expect(protected, findsNothing);
    native.camera.event(sessionId: oldToken);
    await tester.idle();
    await tester.pump();
    expect(protected, findsNothing);
    native.camera.event();
    await tester.idle();
    await tester.pump();
    expect(protected, findsOneWidget);
  });

  testWidgets('late provider events cannot rewrite a terminated snapshot', (
    tester,
  ) async {
    await mount(tester);
    controller.endForSecurityViolation(reason: ViewingIssueKind.phoneDetected);
    final ended = controller.results;
    conditions.update({'device': ViewingConditionResult.unknown});
    await tester.idle();
    await tester.pump();
    expect(controller.results, ended);
    expect(controller.state, ViewingState.accessDenied);
    expect(protected, findsNothing);
  });

  testWidgets('biometric success cannot release a device failure', (
    tester,
  ) async {
    biometric.pending = Completer<BiometricState>();
    await mount(tester);
    conditions.update({'device': ViewingConditionResult.failed});
    biometric.pending!.complete(BiometricState.verified);
    await flushViewing(tester);
    expect(controller.biometrics.approved, isTrue);
    expect(controller.state, ViewingState.temporarilyLocked);
    expect(protected, findsNothing);
    expect(native.camera.starts, 0);
  });

  for (final condition in ['device', 'location', 'unknownMandatorySignal']) {
    testWidgets('missing $condition result fails closed', (tester) async {
      conditions.requiredConditions.add(condition);
      conditions.snapshot.remove(condition);
      await mount(tester);
      expect(controller.state, ViewingState.temporarilyLocked);
      expect(protected, findsNothing);
      expect(native.camera.starts, 0);
    });
  }

  testWidgets('unavailable provider stream hides and cannot self-restore', (
    tester,
  ) async {
    await mount(tester);
    conditions.stream.addError(StateError('simulated producer failure'));
    await tester.idle();
    await tester.pump();
    expect(protected, findsNothing);
    expect(find.text('Condition monitoring unavailable'), findsOneWidget);
    conditions.update({'device': ViewingConditionResult.satisfied});
    await tester.idle();
    await tester.pump();
    expect(protected, findsNothing);
  });

  testWidgets('ended provider stream fails closed', (tester) async {
    await mount(tester);
    unawaited(conditions.stream.close());
    await tester.idle();
    await tester.pump();
    expect(protected, findsNothing);
    expect(controller.state, ViewingState.temporarilyLocked);
  });

  testWidgets('provider cannot drop an already failed required condition', (
    tester,
  ) async {
    await mount(tester);
    conditions.update({'device': ViewingConditionResult.failed});
    await tester.idle();
    await tester.pump();
    conditions.requiredConditions.remove('device');
    conditions.snapshot.remove('device');
    await recheck(tester);
    expect(controller.requiredConditions, contains('device'));
    expect(controller.state, ViewingState.temporarilyLocked);
    expect(protected, findsNothing);
  });

  testWidgets('requirements are retained from controller creation', (
    tester,
  ) async {
    conditions.requiredConditions.remove('device');
    conditions.snapshot.remove('device');
    await mount(tester);
    expect(controller.requiredConditions, contains('device'));
    expect(protected, findsNothing);
  });

  testWidgets('newly declared requirements cannot later disappear', (
    tester,
  ) async {
    await mount(tester);
    conditions.requiredConditions.add('newMandatorySignal');
    conditions.update({'newMandatorySignal': ViewingConditionResult.failed});
    await tester.idle();
    await tester.pump();
    expect(protected, findsNothing);
    conditions.requiredConditions.remove('newMandatorySignal');
    conditions.snapshot.remove('newMandatorySignal');
    await recheck(tester);
    expect(controller.requiredConditions, contains('newMandatorySignal'));
    expect(protected, findsNothing);
  });

  test('callers cannot mutate the controller required set', () {
    expect(() => controller.requiredConditions.clear(), throwsUnsupportedError);
  });

  testWidgets('pending checks cannot rewrite an explicit terminal denial', (
    tester,
  ) async {
    await mount(tester);
    conditions.checking = Completer<Map<String, ViewingConditionResult>>();
    unawaited(controller.revalidate());
    await flushViewing(tester);
    conditions.update({'device': ViewingConditionResult.denied});
    final ended = controller.results;
    conditions.checking!.complete({
      ...conditions.snapshot,
      'location': ViewingConditionResult.failed,
    });
    await flushViewing(tester);
    expect(controller.results, ended);
    expect(controller.state, ViewingState.accessDenied);
    expect(protected, findsNothing);
  });

  testWidgets('unmount and old run events never restore outgoing content', (
    tester,
  ) async {
    await mount(tester);
    final oldToken = native.camera.token;
    await tester.pumpWidget(const MaterialApp(home: Text('Viewer closed')));
    conditions.update({'device': ViewingConditionResult.satisfied});
    native.camera.event(sessionId: oldToken);
    await flushViewing(tester);
    expect(protected, findsNothing);
    expect(controller.biometrics.approved, isFalse);
    expect(find.text('Viewer closed'), findsOneWidget);
  });
}
