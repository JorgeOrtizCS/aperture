import 'dart:async';
import 'dart:convert';

import 'package:aperture/screens/debug_camera_trials_screen.dart';
import 'package:aperture/screens/secure_content_viewer_screen.dart';
import 'package:aperture/services/camera_detection.dart';
import 'package:aperture/services/debug_camera_trial.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/camera_detection_fake.dart';
import 'support/viewing_test_fakes.dart';

void main() {
  test('large detection metadata produces complete bounded log records', () {
    final payload = NativeCameraFake().payload();
    payload['debug_detections'] = List.generate(
      20,
      (_) => {
        'category_name': 'cell phone',
        'category_index': -1,
        'score': 0.31,
        'box_x': 100,
        'box_y': 200,
        'box_width': 80,
        'box_height': 160,
      },
    );
    final lines = DebugCameraTrial.cameraLogLines(payload);
    expect(lines, hasLength(21));
    expect(lines.every((line) => line.length < 900), true);
    final core = jsonDecode(lines.first.split(' event ').last) as Map;
    expect(core['debug_candidate_count'], 20);
    expect(core['phone_confidence'], payload['phone_confidence']);
    for (final line in lines.skip(1)) {
      final box = jsonDecode(line.split('[ApertureCameraBox] ').last) as Map;
      expect(box['debug_event_id'], core['debug_event_id']);
      expect((box['candidate'] as Map)['score'], 0.31);
    }
    expect(payload['debug_detections'] as List, hasLength(20));
  });

  testWidgets('biometric prompt inactivity keeps the camera trial open', (
    tester,
  ) async {
    final native = NativeCaptureFake()..install();
    final authenticate = Completer<bool>();
    final freshCapture = Completer<bool>();
    final startAcknowledgement = Completer<bool>();
    final stopAcknowledgement = Completer<void>();
    native.camera
      ..sendInitial = false
      ..starting = startAcknowledgement;
    var prompts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/local_auth'),
          (call) async {
            if (call.method != 'authenticate') return true;
            prompts++;
            return authenticate.future;
          },
        );

    final content = find.byKey(
      const ValueKey('protected-render-placeholder'),
      skipOffstage: false,
    );
    final viewer = find.byType(SecureContentViewerScreen);
    final binding = tester.binding;
    try {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        const MaterialApp(home: DebugCameraTrialsScreen()),
      );
      await tester.tap(find.text('Start trial A'));
      await tester.pumpAndSettle();
      await flushViewing(tester);
      final trial = DebugCameraTrial.current!;
      expect(prompts, 1);
      expect(content, findsNothing);
      expect(native.camera.calls, isEmpty);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      // Let the diagnostics wrapper's 100 ms auto-exit timer run.
      await tester.pump(const Duration(milliseconds: 150));
      expect(trial.ended, isFalse);
      expect(viewer, findsOneWidget);
      expect(content, findsNothing);
      expect(native.camera.calls, isEmpty);

      authenticate.complete(true);
      await flushViewing(tester);
      expect(content, findsNothing);
      expect(native.camera.calls, isEmpty);

      native.enabling = freshCapture;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flushViewing(tester);
      expect(native.enables, greaterThan(1));
      expect(content, findsNothing);
      expect(native.camera.calls, isEmpty);

      freshCapture.complete(false); // Native protection ready, no capture.
      await flushViewing(tester);
      expect(native.camera.calls, ['start']);
      expect(content, findsNothing);
      startAcknowledgement.complete(true);
      await flushViewing(tester);
      expect(content, findsNothing);
      native.camera.event();
      await flushViewing(tester);
      expect(content, findsOneWidget);
      expect(trial.frames, 1);

      native.camera.event(
        data: {...native.camera.payload(), 'person_count': 0},
      );
      await flushViewing(tester);
      expect(content, findsNothing);
      expect(native.camera.calls, ['start']);
      expect(trial.ended, isFalse);
      native.camera.event();
      await flushViewing(tester);
      expect(content, findsNothing);
      await tester.ensureVisible(find.text('Recheck Conditions'));
      await tester.tap(find.text('Recheck Conditions'));
      await flushViewing(tester);
      expect(content, findsOneWidget);

      native.camera.stopping = stopAcknowledgement;
      native.camera.event(phone: true);
      await tester.pump();
      expect(content, findsNothing);
      await flushViewing(tester);
      expect(trial.reason, 'security_violation:phoneDetected');
      expect(trial.phoneFrames, 1);
      expect(native.camera.calls, ['start', 'stop']);
      final frames = trial.frames;
      native.camera.event();
      await flushViewing(tester);
      expect(content, findsNothing);
      expect(trial.frames, frames);
      stopAcknowledgement.complete();
      await tester.pumpAndSettle();
      await flushViewing(tester);
      expect(viewer, findsNothing);
      expect(find.text('Start trial A'), findsOneWidget);
      expect(native.camera.calls, ['start', 'stop']);
      expect(trial.reason, 'security_violation:phoneDetected');
    } finally {
      if (!authenticate.isCompleted) authenticate.complete(false);
      if (!freshCapture.isCompleted) freshCapture.complete(false);
      if (!startAcknowledgement.isCompleted) {
        startAcknowledgement.complete(true);
      }
      if (!stopAcknowledgement.isCompleted) stopAcknowledgement.complete();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await flushViewing(tester);
    }
  });

  testWidgets('trial tagging preserves first-positive latch and native stop', (
    tester,
  ) async {
    final native = NativeCameraFake()..install();
    final trial = DebugCameraTrial.begin('B', 'glasses; no second phone');
    final session = native.service.createSession();
    try {
      unawaited(session.start());
      await flushViewing(tester);
      expect(session.state, CameraDetectionState.monitoring);
      expect(trial.frames, 1);
      native.event(phone: true);
      await flushViewing(tester);
      expect(session.state, CameraDetectionState.phoneDetected);
      expect(native.stops, 1);
      expect(trial.phoneFrames, 1);
      expect(trial.maxPhoneConfidence, 0.31);
      native.event();
      await session.start();
      await flushViewing(tester);
      expect(session.state, CameraDetectionState.phoneDetected);
      expect(native.starts, 1);
      expect(trial.frames, 2);
    } finally {
      await session.close();
      session.dispose();
      DebugCameraTrial.current = null;
      trial.dispose();
    }
  });
}
