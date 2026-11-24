import 'dart:async';
import 'dart:io';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/services/biometric_verification.dart';
import 'package:aperture/services/camera_detection.dart';
import 'package:aperture/services/native_device_location.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/widgets/biometric_status_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// An external driver switches apps, changes simulator permissions, and on
// Android drives the emulator fingerprint sensor and the system Back button.
// No API environment, protected item, fake gate, or injected lifecycle state.
class _LifecycleProbe with WidgetsBindingObserver {
  final events = <AppLifecycleState>[];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => events.add(state);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native locked-view lifecycle and permission cleanup', (
    tester,
  ) async {
    final probe = _LifecycleProbe();
    tester.binding.addObserver(probe);
    addTearDown(() => tester.binding.removeObserver(probe));
    final location = NativeDeviceLocation(approvedAccuracyLimitMeters: 100);
    addTearDown(location.close);
    final camera = CameraDetectionService.instance.createSession();
    addTearDown(camera.dispose);
    final protected = find.byKey(
      const ValueKey('protected-render-placeholder'),
      skipOffstage: false,
    );
    void mark(String value) => debugPrint('[Week11Native] $value');
    Future<void> waitFor(bool Function() condition, String name) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!condition() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(protected, findsNothing);
      }
      expect(condition(), isTrue, reason: name);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const SecureViewerScreen(allowDemoPreview: false),
                ),
              ),
              child: const Text('Enter locked preflight'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Enter locked preflight'));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<BiometricStatusPanel>(find.byType(BiometricStatusPanel))
        .controller;
    unawaited(controller.revalidate(verifyIdentity: false));
    await waitFor(
      () => controller.captureState == CaptureProtectionState.ready,
      'native capture bridge readiness',
    );
    expect(controller.state, isNot(ViewingState.allowed));
    mark('CAPTURE_READY');

    if (Platform.isAndroid) {
      unawaited(controller.verifyIdentity());
      await waitFor(() => controller.biometrics.busy, 'native prompt started');
      mark('BIOMETRIC_CANCEL');
      await waitFor(
        () => controller.biometrics.state == BiometricState.cancelled,
        'actual OS biometric cancellation',
      );
      expect(controller.biometrics.approved, isFalse);
      mark('BIOMETRIC_CANCELLED');
      await waitFor(
        () =>
            tester.binding.lifecycleState == AppLifecycleState.resumed &&
            controller.biometrics.canVerify,
        'native prompt dismissed and foreground recovered',
      );
      unawaited(controller.verifyIdentity());
      await waitFor(() => controller.biometrics.busy, 'retry started');
      mark('BIOMETRIC_MATCH');
      await waitFor(() => controller.biometrics.approved, 'emulator match');
      expect(controller.state, isNot(ViewingState.allowed));
      mark('BIOMETRIC_VERIFIED_BUT_UNAUTHORIZED');
    } else {
      await controller.verifyIdentity();
      expect(controller.biometrics.approved, isFalse);
      expect(controller.state, isNot(ViewingState.allowed));
      mark('BIOMETRIC_RESULT ${controller.biometrics.state.name}');
    }

    const locationChannel = NativeDeviceLocation.channel;
    final initial = await locationChannel.invokeMethod<String>('permission');
    expect(initial, anyOf('notDetermined', 'denied', 'permanentlyDenied'));
    expect((await location.locate()).fix, isNull);
    mark('GRANT_LOCATION initial=$initial');
    final grantDeadline = DateTime.now().add(const Duration(seconds: 20));
    String? permission;
    do {
      permission = await locationChannel.invokeMethod<String>('permission');
      if (permission == 'granted') break;
      await tester.pump(const Duration(milliseconds: 150));
    } while (DateTime.now().isBefore(grantDeadline));
    expect(permission, 'granted');
    if (Platform.isIOS) {
      // Clear an explicit simulated point after a fresh reading, so Core
      // Location doesn't immediately fulfill the next request from its default.
      mark('SYNTHETIC_SAMPLE_NOW');
      final sample = await locationChannel.invokeMapMethod<String, Object?>(
        'locate',
        {'owner_id': 1105, 'request_id': 1, 'timeout_ms': 4000},
      );
      expect(sample?['status'], 'granted');
      expect(sample?['latitude'], closeTo(26.37, 0.0001));
      expect(sample?['longitude'], closeTo(-80.1, 0.0001));
      mark('CLEAR_LOCATION');
      await tester.pump(const Duration(seconds: 2));
    }

    probe.events.clear();
    Map<String, Object?>? acquisition;
    unawaited(
      locationChannel
          .invokeMapMethod<String, Object?>('locate', {
            'owner_id': 1105,
            'request_id': 2,
            'timeout_ms': 4000,
          })
          .then((value) => acquisition = value),
    );
    // With simulator location cleared, establish a genuinely pending read.
    await tester.pump(const Duration(milliseconds: 150));
    expect(acquisition, isNull);
    mark('BACKGROUND_NOW');
    await waitFor(
      () =>
          probe.events.contains(AppLifecycleState.paused) &&
          probe.events.last == AppLifecycleState.resumed,
      'OS app switch and return',
    );
    expect(acquisition?['status'], 'cancelled');
    expect(controller.biometrics.approved, isFalse);
    expect(controller.state, isNot(ViewingState.allowed));
    mark(
      'RESUMED events=${probe.events.map((e) => e.name).join(",")} '
      'location=${acquisition?['status']} identity=${controller.biometrics.state.name}',
    );

    if (Platform.isAndroid) {
      await waitFor(() => controller.biometrics.canVerify, 'fresh check ready');
      unawaited(controller.verifyIdentity());
      await waitFor(() => controller.biometrics.busy, 'fresh native prompt');
      mark('BIOMETRIC_AFTER_RESUME');
      await waitFor(
        () => controller.biometrics.approved,
        'fresh OS biometric match after resume',
      );
      expect(controller.state, isNot(ViewingState.allowed));
      probe.events.clear();
      mark('LOCK_NOW');
      await waitFor(
        () =>
            probe.events.contains(AppLifecycleState.paused) &&
            probe.events.last == AppLifecycleState.resumed,
        'OS screen lock and unlock',
      );
      expect(controller.biometrics.approved, isFalse);
      expect(controller.state, isNot(ViewingState.allowed));
      mark('UNLOCKED events=${probe.events.map((e) => e.name).join(",")}');
    }

    // Explicit simulated terminal input; native lifecycle/permission events
    // above come from the OS. No protected content was eligible for display.
    controller.endForSecurityViolation();
    await tester.pumpAndSettle();
    expect(controller.sessionEnded, isTrue);
    expect(controller.canRecheck, isFalse);
    expect(controller.state, ViewingState.accessDenied);
    await controller.verifyIdentity();
    await controller.revalidate();
    expect(protected, findsNothing);
    mark('SIMULATED_TERMINATION_LOCKED');
    await tester.pump(const Duration(seconds: 1)); // Allow device evidence.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Enter locked preflight'), findsOneWidget);
    mark('NAVIGATION_BACK_PASS');

    // Exercise the actual camera permission boundary without starting
    // inference. iOS camera access is pre-denied by the simulator driver.
    probe.events.clear();
    unawaited(camera.start());
    mark('CAMERA_PERMISSION_CHECK');
    await waitFor(
      () => camera.state == CameraDetectionState.unavailable,
      'camera remains unavailable after permission denial',
    );
    final cameraError = camera.errorCode;
    if (Platform.isAndroid && cameraError == 'app_inactive') {
      // Android can open its permission activity even for a fixed denial.
      // The native pause tears down startup before the reply is delivered.
      await waitFor(
        () => probe.events.contains(AppLifecycleState.inactive),
        'OS permission activity interrupted startup',
      );
    } else {
      expect(cameraError, 'permission_denied');
    }
    await camera.close();
    expect(protected, findsNothing);
    mark('CAMERA_UNAVAILABLE_AND_CLOSED error=$cameraError');
    mark('COMPLETE');
  });
}
