import 'dart:async';

import 'package:aperture/services/camera_detection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/camera_detection_fake.dart';
import 'support/viewing_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final data = NativeCameraFake().payload();

  test('parses Jorge contract and native UTC events', () {
    final event = DetectionEvent.parse(data);
    expect(event.phoneDetected, false);
    expect(event.phoneConfidence, 0);
    expect(event.personCount, 1);
    expect(event.latencyMs, 17.4);
    expect(event.timestamp.isUtc, true);
    expect(
      DetectionEvent.parse({...data, 'timestamp': '2026-10-16T01:30:12.512'})
          .timestamp
          .isUtc,
      false,
    );
    expect(
      DetectionEvent.parse({
        ...data,
        'phone_detected': true,
        'phone_confidence': 0.15,
      }).phoneDetected,
      true,
    );
    expect(DetectionEvent.parse({...data, 'latency_ms': 17}).latencyMs, 17.0);
  });

  for (final key in [
    'phone_detected',
    'phone_confidence',
    'person_count',
    'latency_ms',
    'timestamp',
  ]) {
    test('rejects missing $key', () {
      expect(
        () => DetectionEvent.parse(Map.of(data)..remove(key)),
        throwsFormatException,
      );
    });
  }
  for (final pair in <(String, Object?)>[
    ('phone_detected', 'false'),
    ('phone_detected', null),
    ('phone_confidence', -0.01),
    ('phone_confidence', 1.01),
    ('phone_confidence', double.nan),
    ('phone_confidence', double.infinity),
    ('phone_confidence', '0.3'),
    ('phone_confidence', 0.2),
    ('phone_detected', true),
    ('person_count', -1),
    ('person_count', 1.0),
    ('latency_ms', -1),
    ('latency_ms', double.infinity),
    ('timestamp', 1234),
    ('timestamp', 'bad'),
    ('timestamp', '2026-10-19'),
    ('timestamp', '2026-02-31T12:30:15Z'),
    ('timestamp', '2026-10-19T25:30:15Z'),
    ('timestamp', '2026-10-19T12:30:15+99:99'),
  ]) {
    test('rejects invalid ${pair.$1}=${pair.$2}', () {
      expect(
        () => DetectionEvent.parse({...data, pair.$1: pair.$2}),
        throwsFormatException,
      );
    });
  }
  test('rejects non-map payload', () {
    expect(() => DetectionEvent.parse(null), throwsFormatException);
    expect(() => DetectionEvent.parse('clear'), throwsFormatException);
  });

  late NativeCameraFake native;
  late CameraDetectionService service;
  late CameraDetectionSession session;
  setUp(() {
    native = NativeCameraFake()..install();
    service = CameraDetectionService();
    session = service.createSession();
  });
  tearDown(() {
    session.dispose();
  });
  void cameraTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        final closing = session.close();
        await flushViewing(tester);
        await closing;
      }
    });
  }

  cameraTest('startup requires acknowledgement and fresh event', (
    tester,
  ) async {
    native.sendInitial = false;
    native.starting = Completer<bool>();
    unawaited(session.start());
    await flushViewing(tester);
    expect(session.state, CameraDetectionState.checking);
    native.event();
    await tester.pump();
    expect(session.state, CameraDetectionState.checking);
    native.starting!.complete(true);
    await flushViewing(tester);
    expect(session.state, CameraDetectionState.monitoring);
    expect(session.latest!.personCount, 1);
  });

  cameraTest('phone latches and clear frames cannot restore session', (
    tester,
  ) async {
    unawaited(session.start());
    await flushViewing(tester);
    native.event(phone: true);
    native.event();
    await flushViewing(tester);
    expect(session.state, CameraDetectionState.phoneDetected);
    await session.start();
    expect(native.starts, 1);
    expect(native.stops, 1);
  });

  for (final acknowledgement in [false, null]) {
    cameraTest(
      'startup acknowledgement $acknowledgement rejects clear frames',
      (tester) async {
        native.startResult = acknowledgement;
        unawaited(session.start());
        await flushViewing(tester);
        expect(session.state, CameraDetectionState.unavailable);
        expect(session.errorCode, 'startup_failed');
        expect(native.stops, 1);
        native.event();
        await tester.pump();
        expect(session.state, CameraDetectionState.unavailable);
      },
    );
  }

  cameraTest(
    'startup timeout rejects a late acknowledgement and clear frames',
    (tester) async {
      native.starting = Completer<bool>();
      unawaited(session.start());
      await flushViewing(tester);
      await tester.pump(const Duration(seconds: 6));
      await flushViewing(tester);
      expect(session.state, CameraDetectionState.unavailable);
      expect(session.errorCode, 'startup_failed');
      expect(native.stops, 1);
      native.starting!.complete(true);
      native.event();
      await flushViewing(tester);
      expect(session.state, CameraDetectionState.unavailable);
    },
  );

  cameraTest('stop and restart reject frames from previous run', (
    tester,
  ) async {
    unawaited(session.start());
    await flushViewing(tester);
    final old = native.token;
    unawaited(session.stop());
    expect(session.state, CameraDetectionState.stopped);
    await flushViewing(tester);
    native.sendInitial = false;
    unawaited(session.start());
    await flushViewing(tester);
    native.event(sessionId: old);
    await tester.pump();
    expect(session.state, CameraDetectionState.checking);
    native.event();
    await tester.pump();
    expect(session.state, CameraDetectionState.monitoring);
  });

  for (final code in [
    'permission_denied',
    'camera_unavailable',
    'inference_failed',
  ]) {
    cameraTest('$code keeps session unavailable and cleans native resources', (
      tester,
    ) async {
      native.startError = PlatformException(code: code);
      unawaited(session.start());
      await flushViewing(tester);
      expect(session.state, CameraDetectionState.unavailable);
      expect(session.errorCode, code);
      expect(native.stops, 1);
      native.event();
      await tester.pump();
      expect(session.state, CameraDetectionState.unavailable);
    });
  }

  for (final failure in [
    'invalid',
    'stream_error',
    'stream_end',
    'frame_timeout',
  ]) {
    cameraTest('$failure hides content and stops camera', (tester) async {
      unawaited(session.start());
      await flushViewing(tester);
      if (failure == 'invalid') {
        native.event(data: {'session_id': native.token});
      }
      if (failure == 'stream_error') native.error('detector_failed');
      if (failure == 'stream_end') native.end();
      if (failure == 'frame_timeout') {
        await tester.pump(const Duration(seconds: 6));
      }
      await flushViewing(tester);
      expect(session.state, CameraDetectionState.unavailable);
      expect(native.stops, 1);
    });
  }

  cameraTest('close during startup cannot resurrect camera session', (
    tester,
  ) async {
    native.starting = Completer<bool>();
    unawaited(session.start());
    await flushViewing(tester);
    final closing = session.close();
    native.starting!.complete(true);
    await flushViewing(tester);
    await closing;
    expect(native.stops, 1);
    await session.start();
    expect(native.starts, 1);
  });

  cameraTest('old route cleanup cannot stop newer owner', (tester) async {
    unawaited(session.start());
    await flushViewing(tester);
    final next = service.createSession();
    unawaited(next.start());
    await flushViewing(tester);
    await session.close();
    expect(next.state, CameraDetectionState.monitoring);
    expect(native.calls, ['start', 'stop', 'start']);
    await next.close();
    next.dispose();
  });

  cameraTest('unknown cleanup outcome poisons subsequent runs', (tester) async {
    unawaited(session.start());
    await flushViewing(tester);
    native.stopError = PlatformException(code: 'stop_failed');
    unawaited(session.stop());
    await flushViewing(tester);
    unawaited(session.start());
    await flushViewing(tester);
    expect(session.state, CameraDetectionState.unavailable);
    expect(session.errorCode, 'cleanup_failed');
    expect(native.starts, 1);
  });
}
