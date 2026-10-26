import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum CaptureProtectionState { checking, ready, captureActive, unavailable }

/// A lease prevents an old route's asynchronous cleanup disabling a newer viewer.
class ScreenCaptureSession extends ChangeNotifier {
  ScreenCaptureSession._(this._service);

  final ScreenCaptureProtection _service;
  CaptureProtectionState _state = CaptureProtectionState.checking;
  bool _screenshotViolation = false;
  bool _closed = false;
  Future<void>? _closing;

  CaptureProtectionState get state => _state;
  bool get screenshotViolation => _screenshotViolation;
  bool get canRevalidate =>
      !_closed &&
      _service._owner == this &&
      !_service._cleanupFailed &&
      !_service._streamBroken;

  Future<void> revalidate() {
    if (_closed) return Future.value();
    _setState(CaptureProtectionState.checking);
    return _service._initialize(this);
  }

  void _setState(CaptureProtectionState value) {
    if (_closed || _state == value) return;
    _state = value;
    notifyListeners();
  }

  void _reportScreenshot() {
    if (_closed || _screenshotViolation) return;
    _screenshotViolation = true;
    notifyListeners();
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    return _closing = _service._release(this);
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

class ScreenCaptureProtection {
  ScreenCaptureProtection._() : timeout = const Duration(seconds: 5);

  @visibleForTesting
  ScreenCaptureProtection.forTesting({
    this.timeout = const Duration(seconds: 5),
  });

  static final ScreenCaptureProtection instance = ScreenCaptureProtection._();
  final Duration timeout;

  static const MethodChannel _methodChannel = MethodChannel(
    'aperture/screen_capture_protection',
  );
  static const EventChannel _eventChannel = EventChannel(
    'aperture/screen_capture_protection/events',
  );

  ScreenCaptureSession? _owner;
  ScreenCaptureSession? _nativeSession;
  StreamSubscription<dynamic>? _nativeCaptureSubscription;
  Future<void>? _pending;
  int _generation = 0;
  bool _cleanupFailed = false;
  bool _streamBroken = false;
  bool? _lastCapture;
  void Function(dynamic)? _onNativeEvent;
  void Function()? _onNativeError;

  ScreenCaptureSession createSession() {
    _owner?._setState(CaptureProtectionState.unavailable);
    return _owner = ScreenCaptureSession._(this);
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = (_pending ?? Future<void>.value()).then((_) => operation());
    // Keep the operation queue usable even if platform cleanup fails.
    _pending = next.catchError((Object error) {
      debugPrint('[ApertureCapture] operation failed: $error');
    });
    return _pending!;
  }

  Future<void> _initialize(ScreenCaptureSession session) => _enqueue(() async {
    if (session._closed || _owner != session) return;
    if (_nativeSession != null && _nativeSession != session) {
      await _stopNative();
    }
    if (_cleanupFailed || _streamBroken) {
      session._setState(CaptureProtectionState.unavailable);
      return;
    }
    _nativeSession = session;
    final generation = ++_generation;
    var failed = false;
    var initialized = false;
    bool? latestCapture = _lastCapture;
    final firstCapture = Completer<bool>();
    if (latestCapture != null) firstCapture.complete(latestCapture);

    bool current() =>
        generation == _generation && _owner == session && !session._closed;
    void unavailable() {
      if (!current()) return;
      failed = true;
      session._setState(CaptureProtectionState.unavailable);
      if (!firstCapture.isCompleted) firstCapture.complete(false);
    }

    try {
      _onNativeError = () {
        _streamBroken = true;
        unavailable();
      };
      _onNativeEvent = (dynamic event) {
        if (!current()) return;
        bool? capture;
        if (event is bool) {
          capture = event; // Android's FLAG_SECURE acknowledgement.
        } else if (event is Map &&
            event['type'] == 'capture' &&
            event['active'] is bool) {
          capture = event['active'] as bool;
        } else if (event is Map && event['type'] == 'screenshot') {
          debugPrint('[ApertureCapture] Flutter received screenshot violation');
          session._reportScreenshot();
          return;
        } else {
          _onNativeError?.call();
          return;
        }
        _lastCapture = latestCapture = capture;
        debugPrint(
          '[ApertureCapture] Flutter received capture active=$capture',
        );
        if (!firstCapture.isCompleted) firstCapture.complete(capture);
        if (initialized && !failed) {
          session._setState(
            capture
                ? CaptureProtectionState.captureActive
                : CaptureProtectionState.ready,
          );
        }
      };
      // Keep this listener for the session, including background/resume checks.
      // EventChannel's asynchronous onCancel must not race a fresh onListen.
      _nativeCaptureSubscription ??= _eventChannel
          .receiveBroadcastStream()
          .listen(
            (event) => _onNativeEvent?.call(event),
            onError: (Object error) => _onNativeError?.call(),
            onDone: () => _onNativeError?.call(),
          );
      final capture = await _methodChannel
          .invokeMethod<bool>('enableProtection')
          .timeout(timeout);
      if (capture == null) {
        unavailable();
        return;
      }
      await firstCapture.future.timeout(timeout);
      if (!current() || failed) return;
      initialized = true;
      // A capture seen during initialization cannot be cleared by a stale method
      // response. Prefer locking until another live update/revalidation arrives.
      session._setState(
        capture || latestCapture == true
            ? CaptureProtectionState.captureActive
            : CaptureProtectionState.ready,
      );
    } catch (error) {
      debugPrint('[ApertureCapture] initialization unavailable: $error');
      unavailable();
    }
  });

  Future<void> _release(ScreenCaptureSession session) => _enqueue(() async {
    if (_owner == session && _nativeSession == session) {
      await _stopNative();
    }
    if (_owner == session) _owner = null;
  });

  Future<void> _stopNative() async {
    ++_generation;
    try {
      await _nativeCaptureSubscription?.cancel().timeout(timeout);
      await _methodChannel
          .invokeMethod<void>('disableProtection')
          .timeout(timeout);
    } catch (error) {
      // Cleanup with an unknown outcome could finish late and clear a new secure
      // window. Refuse further sessions until the service/app is restarted.
      _cleanupFailed = true;
      debugPrint('[ApertureCapture] cleanup unavailable: $error');
    } finally {
      _nativeCaptureSubscription = null;
      _nativeSession = null;
      _onNativeEvent = null;
      _onNativeError = null;
      _lastCapture = null;
      _streamBroken = false;
    }
  }
}
