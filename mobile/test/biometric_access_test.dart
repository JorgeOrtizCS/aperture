import 'dart:async';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/screens/secure_content_viewer_screen.dart';
import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/services/biometric_verification.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/biometric_fake.dart';
import 'support/viewing_test_fakes.dart';

final protected = find.byKey(
  const ValueKey('protected-render-placeholder'),
  skipOffstage: false,
);

void main() {
  late NativeCaptureFake native;
  late BiometricFake biometric;
  late ConditionsFake conditions;
  ViewingStateController? controller;
  setUp(() {
    native = NativeCaptureFake();
    biometric = BiometricFake();
    conditions = ConditionsFake();
    controller = null;
  });
  tearDown(() {
    controller?.dispose();
    conditions.dispose();
  });

  Future<void> mount(WidgetTester tester, {bool capture = false}) async {
    native.capture = capture;
    native.install();
    controller = ViewingStateController(
      restrictions: ContentRestrictions.demoDefaults,
      conditions: conditions,
      protection: ScreenCaptureProtection.forTesting(),
      biometricAuthenticator: biometric,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: SecureContentViewerScreen(
          contentTitle: 'Test-only placeholder',
          restrictions: ContentRestrictions.demoDefaults,
          viewingController: controller,
          cameraDetection: native.camera.service,
        ),
      ),
    );
    unawaited(controller!.revalidate());
    await flushViewing(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await flushViewing(tester);
  }

  testWidgets(
    'success requires biometrics before camera startup and protected rendering',
    (tester) async {
      biometric.pending = Completer<BiometricState>();
      await mount(tester);
      expect(find.text('Verification in progress'), findsNWidgets(2));
      expect(protected, findsNothing);
      expect(native.camera.starts, 0);
      expect(controller!.state, ViewingState.temporarilyLocked);
      biometric.pending!.complete(BiometricState.verified);
      await flushViewing(tester);
      expect(controller!.state, ViewingState.allowed);
      expect(native.camera.starts, 1);
      expect(protected, findsOneWidget);
      expect(find.text('Verification successful'), findsOneWidget);
      await unmount(tester);
      expect(controller!.biometrics.approved, isFalse);
    },
  );
  testWidgets(
    'expiry during the biometric prompt requires a fresh policy check',
    (tester) async {
      biometric.pending = Completer<BiometricState>();
      await mount(tester);
      expect(conditions.checks, 1);
      // Time-based expiry need not emit a live event while the OS prompt is open.
      conditions.snapshot[ViewingCondition.expiration] =
          ViewingConditionResult.denied;
      biometric.pending!.complete(BiometricState.verified);
      await flushViewing(tester);
      expect(conditions.checks, 2);
      expect(controller!.sessionEnded, isTrue);
      expect(controller!.biometrics.approved, isFalse);
      expect(protected, findsNothing);
      expect(native.camera.starts, 0);
      await unmount(tester);
    },
  );
  for (final outcome in [
    BiometricState.cancelled,
    BiometricState.failed,
    BiometricState.unavailable,
    BiometricState.notEnrolled,
    BiometricState.temporaryLockout,
    BiometricState.permanentLockout,
  ]) {
    testWidgets(
      '${outcome.name} keeps direct viewer hidden and supports biometric-only retry',
      (tester) async {
        biometric.result = outcome;
        await mount(tester);
        expect(protected, findsNothing);
        expect(native.camera.starts, 0);
        expect(controller!.biometrics.state, outcome);
        expect(find.text('Verify identity'), findsOneWidget);
        biometric.result = BiometricState.verified;
        await tester.ensureVisible(find.text('Verify identity'));
        await tester.tap(find.text('Verify identity'));
        await flushViewing(tester);
        expect(protected, findsOneWidget);
        expect(biometric.starts, 2);
        await unmount(tester);
      },
    );
  }
  testWidgets('repeated Verify presses cannot open multiple prompts', (
    tester,
  ) async {
    native.install();
    biometric.pending = Completer<BiometricState>();
    await tester.pumpWidget(
      MaterialApp(
        home: SecureViewerScreen(
          conditionProvider: conditions,
          captureProtection: ScreenCaptureProtection.forTesting(),
          biometricAuthenticator: biometric,
        ),
      ),
    );
    final verify = find.widgetWithText(ElevatedButton, 'Verify identity');
    await tester.ensureVisible(verify);
    await tester.tap(verify);
    await tester.pump();
    final busy = find.widgetWithText(
      ElevatedButton,
      'Verification in progress',
    );
    expect(tester.widget<ElevatedButton>(busy).onPressed, isNull);
    await tester.tap(busy);
    await tester.tap(busy);
    await flushViewing(tester);
    expect(biometric.starts, 1);
    biometric.pending!.complete(BiometricState.cancelled);
    await flushViewing(tester);
    expect(protected, findsNothing);
    await unmount(tester);
  });
  testWidgets(
    'direct-route production default cannot reveal content without biometrics',
    (tester) async {
      native.install();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/local_auth'),
        (call) async =>
            throw MissingPluginException('Native biometrics unavailable'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SecureContentViewerScreen(
            contentTitle: 'Direct route',
            restrictions: ContentRestrictions.demoDefaults,
            conditionProvider: conditions,
            captureProtection: ScreenCaptureProtection.forTesting(),
            cameraDetection: native.camera.service,
          ),
        ),
      );
      await flushViewing(tester);
      expect(protected, findsNothing);
      expect(find.text('Biometrics unavailable'), findsOneWidget);
      expect(native.camera.starts, 0);
      await unmount(tester);
    },
  );
  testWidgets(
    'successful device biometrics cannot invent backend authorization',
    (tester) async {
      native.install();
      await tester.pumpWidget(
        MaterialApp(
          home: SecureViewerScreen(
            biometricAuthenticator: biometric,
            captureProtection: ScreenCaptureProtection.forTesting(),
            cameraDetection: native.camera.service,
          ),
        ),
      );
      await tester.ensureVisible(find.text('Verify identity'));
      await tester.tap(find.text('Verify identity'));
      await flushViewing(tester);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump();
      expect(find.text('Verification successful'), findsOneWidget);
      expect(
        find.text('Recipient authorization not confirmed'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Open Secure Content'),
        200,
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
      expect(protected, findsNothing);
      expect(native.camera.starts, 0);
      await unmount(tester);
    },
  );
  for (final condition in [
    ViewingCondition.authorization,
    ViewingCondition.expiration,
    ViewingCondition.viewLimit,
    'location',
    'presence',
  ]) {
    testWidgets('biometrics cannot override denied $condition', (tester) async {
      conditions.snapshot[condition] = ViewingConditionResult.denied;
      await mount(tester);
      expect(controller!.sessionEnded, isTrue);
      expect(controller!.biometrics.state, BiometricState.ended);
      await controller!.verifyIdentity();
      expect(biometric.starts, 0);
      expect(protected, findsNothing);
      expect(native.camera.starts, 0);
      expect(find.text('Viewing session ended'), findsOneWidget);
      await unmount(tester);
    });
  }
  testWidgets('capture active remains locked after successful biometrics', (
    tester,
  ) async {
    await mount(tester, capture: true);
    unawaited(controller!.verifyIdentity());
    await flushViewing(tester);
    expect(controller!.biometrics.approved, isTrue);
    expect(controller!.state, ViewingState.temporarilyLocked);
    expect(protected, findsNothing);
    expect(find.text('Screen capture detected'), findsOneWidget);
    expect(native.camera.starts, 0);
    await unmount(tester);
  });
  testWidgets(
    'capture becoming active during authentication wins over success',
    (tester) async {
      biometric.pending = Completer<BiometricState>();
      await mount(tester);
      native.setCapture(true);
      await flushViewing(tester);
      biometric.pending!.complete(BiometricState.verified);
      await flushViewing(tester);
      expect(protected, findsNothing);
      expect(controller!.state, ViewingState.temporarilyLocked);
      expect(native.camera.starts, 0);
      await unmount(tester);
    },
  );
  testWidgets('unavailable native capture never authorizes via biometrics', (
    tester,
  ) async {
    native.enableError = PlatformException(code: 'unavailable');
    await mount(tester);
    unawaited(controller!.verifyIdentity());
    await flushViewing(tester);
    expect(controller!.biometrics.approved, isTrue);
    expect(controller!.state, ViewingState.protectionUnavailable);
    expect(protected, findsNothing);
    expect(native.camera.starts, 0);
    await unmount(tester);
  });
  testWidgets(
    'camera unavailable after biometric success keeps subtree absent',
    (tester) async {
      native.camera.startError = PlatformException(code: 'permission_denied');
      await mount(tester);
      expect(controller!.biometrics.approved, isTrue);
      expect(protected, findsNothing);
      expect(find.text('Camera permission denied'), findsOneWidget);
      await unmount(tester);
    },
  );
  testWidgets(
    'background revokes approval and requires fresh identity and camera',
    (tester) async {
      await mount(tester);
      expect(protected, findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(protected, findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await flushViewing(tester);
      expect(controller!.biometrics.approved, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flushViewing(tester);
      expect(protected, findsNothing);
      expect(native.camera.starts, 1);
      await tester.ensureVisible(find.text('Verify identity'));
      await tester.tap(find.text('Verify identity'));
      await flushViewing(tester);
      expect(protected, findsOneWidget);
      expect(native.camera.starts, 2);
      expect(biometric.starts, 2);
      await unmount(tester);
    },
  );
  testWidgets('background rejects pending success and does not start camera', (
    tester,
  ) async {
    biometric.pending = Completer<BiometricState>();
    await mount(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await flushViewing(tester);
    biometric.pending!.complete(BiometricState.verified);
    await flushViewing(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flushViewing(tester);
    expect(controller!.biometrics.approved, isFalse);
    expect(protected, findsNothing);
    expect(native.camera.starts, 0);
    await unmount(tester);
  });
  testWidgets(
    'widget disposal rejects in-flight success, including shared controllers',
    (tester) async {
      biometric.pending = Completer<BiometricState>();
      await mount(tester);
      await unmount(tester);
      biometric.pending!.complete(BiometricState.verified);
      await flushViewing(tester);
      expect(controller!.biometrics.approved, isFalse);
      expect(native.camera.starts, 0);
      expect(protected, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final reason in [
    ViewingIssueKind.phoneDetected,
    ViewingIssueKind.screenshot,
  ]) {
    testWidgets(
      '${reason.name} permanent lock beats a late successful reauthentication',
      (tester) async {
        await mount(tester);
        expect(protected, findsOneWidget);
        controller!.revokeIdentity();
        biometric.pending = Completer<BiometricState>();
        unawaited(controller!.verifyIdentity());
        await flushViewing(tester);
        if (reason == ViewingIssueKind.phoneDetected) {
          native.camera.event(phone: true);
        } else {
          native.events!.success({'type': 'screenshot'});
        }
        await tester.pump();
        expect(protected, findsNothing);
        biometric.pending!.complete(BiometricState.verified);
        await flushViewing(tester);
        expect(controller!.sessionEnded, isTrue);
        expect(controller!.biometrics.state, BiometricState.ended);
        await controller!.verifyIdentity();
        await controller!.revalidate();
        expect(controller!.state, ViewingState.accessDenied);
        expect(protected, findsNothing);
        await unmount(tester);
      },
    );
  }
  testWidgets(
    'preflight and content share approval only until the content route closes',
    (tester) async {
      native.install();
      await tester.pumpWidget(
        MaterialApp(
          home: SecureViewerScreen(
            conditionProvider: conditions,
            biometricAuthenticator: biometric,
            captureProtection: ScreenCaptureProtection.forTesting(),
            cameraDetection: native.camera.service,
          ),
        ),
      );
      await tester.ensureVisible(find.text('Verify identity'));
      await tester.tap(find.text('Verify identity'));
      await flushViewing(tester);
      await tester.scrollUntilVisible(
        find.text('Open Secure Content'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Open Secure Content'));
      await tester.pumpAndSettle();
      await flushViewing(tester);
      expect(protected, findsOneWidget);
      expect(biometric.starts, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await flushViewing(tester);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump();
      expect(find.text('Verification successful'), findsNothing);
      expect(find.text('Verification required'), findsOneWidget);
      expect(protected, findsNothing);
      await unmount(tester);
    },
  );
}
