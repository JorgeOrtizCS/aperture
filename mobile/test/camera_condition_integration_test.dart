import 'dart:async';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/screens/secure_content_viewer_screen.dart';
import 'package:aperture/screens/api_content_screens.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';
import 'support/biometric_fake.dart';
import 'support/viewing_test_fakes.dart';

// Real Flutter routes/controller/channel adapters, synthetic sensor/API inputs.
// None of these cases establish native detector, GPS or server acceptance.
void main() {
  late NativeCaptureFake native;
  late ConditionsFake conditions;
  late ViewingStateController controller;
  final protected = find.byKey(
    const ValueKey('protected-render-placeholder'),
    skipOffstage: false,
  );

  setUp(() {
    native = NativeCaptureFake()..install();
    conditions = ConditionsFake();
    controller = ViewingStateController(
      restrictions: ContentRestrictions.demoDefaults,
      conditions: conditions,
      protection: ScreenCaptureProtection.forTesting(),
      biometricAuthenticator: BiometricFake(),
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
        home: SecureContentViewerScreen(
          contentTitle: 'Synthetic protected viewing',
          restrictions: ContentRestrictions.demoDefaults,
          viewingController: controller,
          cameraDetection: native.camera.service,
        ),
      ),
    );
    unawaited(controller.revalidate());
    await flushViewing(tester);
    expect(protected, findsOneWidget);
  }

  Future<void> people(WidgetTester tester, int count) async {
    native.camera.event(
      data: {...native.camera.payload(), 'person_count': count},
    );
    await tester.idle();
    await tester.pump();
  }

  Future<void> recheck(WidgetTester tester) async {
    unawaited(controller.revalidate());
    await flushViewing(tester);
  }

  for (final count in [0, 2, 3]) {
    testWidgets(
      'person count $count hides immediately and needs fresh revalidation',
      (tester) async {
        await mount(tester);
        await people(tester, count);
        expect(protected, findsNothing);
        expect(controller.sessionEnded, false);
        expect(
          find.text(
            count == 0 ? 'Required viewer missing' : 'Multiple people detected',
          ),
          findsOneWidget,
        );
        await recheck(tester);
        expect(protected, findsNothing);
        await people(tester, 1);
        expect(protected, findsNothing);
        await recheck(tester);
        expect(protected, findsOneWidget);
      },
    );
  }

  testWidgets('successful identity cannot override a failed person condition', (
    tester,
  ) async {
    await mount(tester);
    await people(tester, 2);
    unawaited(controller.verifyIdentity());
    await flushViewing(tester);
    expect(controller.biometrics.approved, true);
    expect(protected, findsNothing);
  });

  testWidgets('camera restoration cannot override another required condition', (
    tester,
  ) async {
    await mount(tester);
    await people(tester, 2);
    conditions.update({'location': ViewingConditionResult.failed});
    await people(tester, 1);
    await recheck(tester);
    expect(controller.sessionEnded, false);
    expect(protected, findsNothing);
  });

  testWidgets('person and recording failures both require restoration', (
    tester,
  ) async {
    await mount(tester);
    native.setCapture(true);
    await people(tester, 0);
    await people(tester, 1);
    await recheck(tester);
    expect(protected, findsNothing);
    native.setCapture(false);
    await tester.pump();
    expect(protected, findsNothing);
    await recheck(tester);
    expect(protected, findsOneWidget);
  });

  for (final code in [
    'permission_denied',
    'inference_failed',
    'camera_interrupted',
  ]) {
    testWidgets('camera $code cannot be cleared by a late successful frame', (
      tester,
    ) async {
      await mount(tester);
      native.camera.error(code);
      await tester.pump();
      native.camera.event();
      await tester.pump();
      expect(protected, findsNothing);
      expect(
        find.text(
          code == 'permission_denied'
              ? 'Camera permission denied'
              : 'Camera protection unavailable',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('phone termination wins over multiple people and clear frames', (
    tester,
  ) async {
    await mount(tester);
    await people(tester, 2);
    native.camera.event(phone: true);
    await tester.pump();
    await people(tester, 1);
    await recheck(tester);
    expect(controller.sessionEnded, true);
    expect(controller.violationReason, ViewingIssueKind.phoneDetected);
    expect(protected, findsNothing);
  });

  testWidgets('screenshot termination cannot be undone by viewer return', (
    tester,
  ) async {
    await mount(tester);
    await people(tester, 0);
    native.events!.success({'type': 'screenshot'});
    await tester.pump();
    await people(tester, 1);
    expect(controller.sessionEnded, true);
    expect(controller.violationReason, ViewingIssueKind.screenshot);
    expect(protected, findsNothing);
  });

  testWidgets(
    'person failure followed by background needs fresh camera and identity',
    (tester) async {
      await mount(tester);
      await people(tester, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await flushViewing(tester);
      expect(protected, findsNothing);
      expect(controller.biometrics.approved, false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flushViewing(tester);
      unawaited(controller.verifyIdentity());
      await flushViewing(tester);
      expect(native.camera.starts, 2);
      expect(protected, findsOneWidget);
    },
  );

  testWidgets(
    'device registration UI reports untrusted and never grants viewing',
    (tester) async {
      final fake = ApiFake()..contents = [contentJson()];
      fake.routes['/api/devices'] = (_) => jsonReply({'trusted': false});
      final account = fake.session();
      await account.login('synthetic-user', 'fixture-password');
      await account.refresh();
      await tester.pumpWidget(
        MaterialApp(home: ApiRecipientScreen(account: account, contentId: 7)),
      );
      await tester.tap(find.text('Register this device'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not approved'), findsOneWidget);
      expect(protected, findsNothing);
      expect(
        fake.calls.where((c) => c.uri.path.endsWith('/sessions')),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await flushViewing(tester);
      account.dispose();
    },
  );
}
