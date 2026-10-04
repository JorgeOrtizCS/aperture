import 'dart:async';

import 'package:flutter/services.dart';

class ScreenCaptureProtection {
  ScreenCaptureProtection._();

  static final ScreenCaptureProtection instance = ScreenCaptureProtection._();

  static const MethodChannel _methodChannel = MethodChannel(
    'aperture/screen_capture_protection',
  );
  static const EventChannel _eventChannel = EventChannel(
    'aperture/screen_capture_protection/events',
  );

  final StreamController<bool> _captureStateController =
      StreamController<bool>.broadcast();

  StreamSubscription<dynamic>? _nativeCaptureSubscription;
  bool _isCaptureActive = false;

  bool get isCaptureActive => _isCaptureActive;

  Stream<bool> get captureStateChanges => _captureStateController.stream;

  Future<bool> enableProtection() async {
    _startNativeCaptureListener();

    try {
      final isCaptureActive = await _methodChannel.invokeMethod<bool>(
        'enableProtection',
      );
      _setCaptureActive(isCaptureActive ?? false);
    } on MissingPluginException {
      _setCaptureActive(false);
    } on PlatformException {
      _setCaptureActive(true);
    }

    return _isCaptureActive;
  }

  Future<void> disableProtection() async {
    try {
      await _methodChannel.invokeMethod<void>('disableProtection');
    } on MissingPluginException {
      // Desktop/web builds do not provide the native secure window prototype.
    } finally {
      await _nativeCaptureSubscription?.cancel();
      _nativeCaptureSubscription = null;
      _setCaptureActive(false);
    }
  }

  void _startNativeCaptureListener() {
    if (_nativeCaptureSubscription != null) {
      return;
    }

    _nativeCaptureSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) => _setCaptureActive(event == true),
      onError: (_) => _setCaptureActive(false),
    );
  }

  void _setCaptureActive(bool isCaptureActive) {
    if (_isCaptureActive == isCaptureActive) {
      return;
    }

    _isCaptureActive = isCaptureActive;
    if (!_captureStateController.isClosed) {
      _captureStateController.add(isCaptureActive);
    }
  }
}
