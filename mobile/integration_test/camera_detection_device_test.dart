import 'dart:async';

import 'package:aperture/screens/secure_content_viewer_screen.dart';
import 'package:aperture/services/camera_detection.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Device run: grant Camera before starting this test. Uses real platform
/// channels, native camera frames and the bundled model; no mock responses.
/// For camera-unavailable iOS Simulator validation, define
/// APERTURE_EXPECT_NO_CAMERA=true to skip the two live-camera tests.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final liveCameraSupported =
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      !const bool.fromEnvironment('APERTURE_EXPECT_NO_CAMERA');

  testWidgets(
    'iOS simulator camera failure keeps demo content hidden',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Device test home')),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => SecureContentViewerScreen.demo(
              contentTitle: 'Unavailable camera validation',
              restrictions: ContentRestrictions.demoDefaults,
              cameraDetection: CameraDetectionService(),
            ),
          ),
        ),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (find.text('Camera protection unavailable').evaluate().isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Camera protection unavailable'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('protected-render-placeholder'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Device test home'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    skip:
        defaultTargetPlatform != TargetPlatform.iOS ||
        !const bool.fromEnvironment('APERTURE_EXPECT_NO_CAMERA'),
  );

  testWidgets('native camera delivers fresh events and releases resources', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();
    final samples = <double>[];
    final session = CameraDetectionService().createSession();
    final collected = Completer<void>();
    session.addListener(() {
      if (session.state == CameraDetectionState.unavailable &&
          !collected.isCompleted) {
        collected.completeError(
          StateError('Native detector: ${session.errorCode}'),
        );
      }
      if (session.state == CameraDetectionState.phoneDetected &&
          !collected.isCompleted) {
        collected.completeError(
          StateError('Phone detected in test camera input'),
        );
      }
      final event = session.latest;
      if (session.state == CameraDetectionState.monitoring && event != null) {
        samples.add(event.latencyMs);
        expect(event.phoneConfidence, inInclusiveRange(0.0, 1.0));
        expect(event.personCount, greaterThanOrEqualTo(0));
        if (samples.length >= 10 && !collected.isCompleted) {
          collected.complete();
        }
      }
    });
    try {
      await Future.wait<void>([
        session.start(),
        collected.future.timeout(const Duration(seconds: 30)),
      ]);
      await session.stop();
      expect(session.state, CameraDetectionState.stopped);
      final count = samples.length;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(
        samples.length,
        count,
        reason: 'No events after native stop acknowledgement',
      );
      final summary = <String, Object>{
        'platform': defaultTargetPlatform.name,
        'input': 'live_camera',
        'count': samples.length,
        'average_ms': samples.reduce((a, b) => a + b) / samples.length,
        'minimum_ms': samples.reduce((a, b) => a < b ? a : b),
        'maximum_ms': samples.reduce((a, b) => a > b ? a : b),
      };
      binding.reportData = {'camera_latency': summary};
      debugPrint('[ApertureDeviceTest] $summary');
    } finally {
      await session.close();
      session.dispose();
    }
  }, skip: !liveCameraSupported);

  testWidgets('real camera gates demo viewer and stops on route exit', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Device test home')),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => SecureContentViewerScreen.demo(
            contentTitle: 'Native camera validation',
            restrictions: ContentRestrictions.demoDefaults,
            cameraDetection: CameraDetectionService(),
          ),
        ),
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (find.text('Camera protection active').evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Camera protection active'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('protected-render-placeholder')),
      findsOneWidget,
    );
    navigator.currentState!.pop();
    await tester.pump();
    expect(
      find.byKey(
        const ValueKey('protected-render-placeholder'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(find.text('Device test home'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, skip: !liveCameraSupported);
}
