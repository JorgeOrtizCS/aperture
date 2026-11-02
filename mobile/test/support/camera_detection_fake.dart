import 'dart:async';

import 'package:aperture/services/camera_detection.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class NativeCameraFake {
  final service = CameraDetectionService();
  int? token;
  int starts = 0;
  int stops = 0;
  bool sendInitial = true;
  bool? startResult = true;
  PlatformException? startError;
  PlatformException? stopError;
  Completer<bool>? starting;
  final calls = <String>[];

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('aperture/camera_detection/events'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('aperture/camera_detection'),
      (call) async {
        calls.add(call.method);
        if (call.method == 'start') {
          token = (call.arguments as Map)['session_id'] as int;
          starts++;
          if (startError != null) throw startError!;
          if (sendInitial) scheduleMicrotask(() => event());
          return starting?.future ?? startResult;
        }
        if (call.method == 'stop') {
          stops++;
          if (stopError != null) throw stopError!;
          return null;
        }
        throw MissingPluginException();
      },
    );
  }

  Map<String, Object?> payload({bool phone = false, int? sessionId}) => {
    'session_id': sessionId ?? token,
    'phone_detected': phone,
    'phone_confidence': phone ? 0.31 : 0.0,
    'person_count': 1,
    'latency_ms': 17.4,
    'timestamp': '2026-10-19T12:30:15.512Z',
  };

  void event({bool phone = false, int? sessionId, Object? data}) => send(
    const StandardMethodCodec().encodeSuccessEnvelope(
      data ?? payload(phone: phone, sessionId: sessionId),
    ),
  );
  void error(String code) =>
      send(const StandardMethodCodec().encodeErrorEnvelope(code: code));
  void end() => send(null);
  void send(ByteData? data) => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .handlePlatformMessage('aperture/camera_detection/events', data, null);
}
