import 'dart:async';

import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class NativeCaptureFake {
  NativeEventsFake? events;
  Completer<bool>? enabling;
  Completer<void>? disabling;
  Object? enableError;
  Object? disableError;
  bool capture = false;
  bool sendInitialEvent = true;
  bool nullResult = false;
  int enables = 0;
  int disables = 0;
  final calls = <String>[];

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('aperture/screen_capture_protection'),
      (call) async {
        calls.add(call.method);
        if (call.method == 'enableProtection') {
          enables++;
          if (enableError != null) throw enableError!;
          if (nullResult) return null;
          return enabling?.future ?? capture;
        }
        if (call.method == 'disableProtection') {
          disables++;
          if (disabling != null) await disabling!.future;
          if (disableError != null) throw disableError!;
          return null;
        }
        throw MissingPluginException();
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('aperture/screen_capture_protection/events'),
      (call) async {
        if (call.method == 'listen') {
          events = NativeEventsFake();
          if (sendInitialEvent) {
            scheduleMicrotask(() => events!.success(capture));
          }
        }
        return null;
      },
    );
  }

  void setCapture(bool value) {
    capture = value;
    events!.success({'type': 'capture', 'active': value});
  }
}

class ConditionsFake implements ViewingConditionProvider {
  ConditionsFake({this.requiredConditions = const {'presence', 'location'}});

  @override
  final Set<String> requiredConditions;
  StreamController<Map<String, ViewingConditionResult>>? _stream;
  StreamController<Map<String, ViewingConditionResult>> get stream =>
      _stream ??=
          StreamController<Map<String, ViewingConditionResult>>.broadcast(
            sync: true,
          );
  Map<String, ViewingConditionResult> snapshot = {
    ViewingCondition.authorization: ViewingConditionResult.satisfied,
    ViewingCondition.expiration: ViewingConditionResult.satisfied,
    ViewingCondition.viewLimit: ViewingConditionResult.satisfied,
    'presence': ViewingConditionResult.satisfied,
    'location': ViewingConditionResult.satisfied,
  };
  Completer<Map<String, ViewingConditionResult>>? checking;
  Object? checkError;
  int checks = 0;
  ContentRestrictions? lastPolicy;

  @override
  Stream<Map<String, ViewingConditionResult>> get changes => stream.stream;

  @override
  Future<Map<String, ViewingConditionResult>> check(
    ContentRestrictions restrictions,
  ) async {
    checks++;
    lastPolicy = restrictions;
    if (checkError != null) throw checkError!;
    return checking?.future ?? Map.of(snapshot);
  }

  void update(Map<String, ViewingConditionResult> changes) {
    snapshot.addAll(changes);
    stream.add(changes);
  }

  void dispose() => unawaited(_stream?.close());
}

Future<void> flushViewing(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    // Platform-channel cancellation can finish outside the widget fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

class NativeEventsFake {
  static const codec = StandardMethodCodec();
  static const channel = 'aperture/screen_capture_protection/events';

  void success(Object? value) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel,
          codec.encodeSuccessEnvelope(value),
          null,
        );
  }

  void error({required String code}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel,
          codec.encodeErrorEnvelope(code: code),
          null,
        );
  }

  void endOfStream() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel, null, null);
  }
}
