import 'dart:async';
import 'dart:convert';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/screens/secure_content_viewer_screen.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/biometric_fake.dart';
import 'support/viewing_test_fakes.dart';

// Deterministic rebuild/first-frame regressions. All native/identity/policy
// inputs here are test fixtures, not native acceptance or device benchmarks.
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

  Future<void> frame(WidgetTester tester) async {
    await tester.idle();
    await tester.pump();
  }

  Future<void> mount(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await flushViewing(tester);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: SecureContentViewerScreen(
          contentTitle: 'Synthetic rebuild fixture',
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

  testWidgets('clear telemetry rebuilds diagnostics without rebuilding gates', (
    tester,
  ) async {
    await mount(tester);
    final counts = <String, int>{};
    final previous = debugOnRebuildDirtyWidget;
    final checks = conditions.checks;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      final name = element.widget.runtimeType.toString();
      if (name == 'SecureContentViewerScreen' ||
          name == 'BiometricStatusPanel') {
        counts[name] = (counts[name] ?? 0) + 1;
      }
      final widget = element.widget;
      if (widget is Text && widget.data?.startsWith('People:') == true) {
        counts['telemetry_text'] = (counts['telemetry_text'] ?? 0) + 1;
      }
    };
    try {
      for (var i = 0; i < 30; i++) {
        native.camera.event(
          data: {...native.camera.payload(), 'latency_ms': 10.0 + i},
        );
        await frame(tester);
      }
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
    debugPrint('[ViewerRebuildProbe] ${jsonEncode(counts)}');
    expect(counts['SecureContentViewerScreen'] ?? 0, 0);
    expect(counts['BiometricStatusPanel'] ?? 0, 0);
    expect(counts['telemetry_text'], 30);
    expect(find.textContaining('Inference: 39.0 ms'), findsOneWidget);
    expect(conditions.checks, checks);
    expect(controller.biometrics.approved, isTrue);
    expect(protected, findsOneWidget);
  });

  testWidgets('camera failure still hides in the next frame after telemetry', (
    tester,
  ) async {
    await mount(tester);
    native.camera.event();
    await frame(tester);
    native.camera.error('camera_interrupted');
    await frame(tester);
    expect(protected, findsNothing);
    expect(find.text('Camera protection unavailable'), findsOneWidget);
    native.camera.event();
    await flushViewing(tester);
    expect(protected, findsNothing);
  });

  testWidgets('phone transition is immediate and cannot be optimized away', (
    tester,
  ) async {
    await mount(tester);
    for (var i = 0; i < 5; i++) {
      native.camera.event();
      await frame(tester);
    }
    native.camera.event(phone: true);
    await frame(tester);
    expect(protected, findsNothing);
    expect(controller.violationReason, ViewingIssueKind.phoneDetected);
    expect(controller.sessionEnded, isTrue);
    native.camera.event();
    await controller.verifyIdentity();
    await controller.revalidate();
    await flushViewing(tester);
    expect(protected, findsNothing);
    expect(controller.biometrics.approved, isFalse);
  });

  testWidgets(
    'telemetry cannot rebuild content across an independent capture lock',
    (tester) async {
      await mount(tester);
      native.setCapture(true);
      await frame(tester);
      expect(protected, findsNothing);
      for (var i = 0; i < 10; i++) {
        native.camera.event();
        await frame(tester);
        expect(protected, findsNothing);
      }
      expect(find.text('Screen capture detected'), findsOneWidget);
      native.setCapture(false);
      await frame(tester);
      expect(protected, findsNothing);
      unawaited(controller.revalidate());
      await flushViewing(tester);
      expect(protected, findsOneWidget);
    },
  );
}
