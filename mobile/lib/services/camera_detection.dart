import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class DetectionEvent {
  const DetectionEvent._({
    required this.phoneDetected,
    required this.phoneConfidence,
    required this.personCount,
    required this.latencyMs,
    required this.timestamp,
  });

  final bool phoneDetected;
  final double phoneConfidence;
  final int personCount;
  final double latencyMs;
  final DateTime timestamp;

  factory DetectionEvent.parse(Object? value) {
    if (value is! Map) throw const FormatException('Expected detection map');
    final phone = value['phone_detected'];
    final confidence = value['phone_confidence'];
    final persons = value['person_count'];
    final latency = value['latency_ms'];
    final time = value['timestamp'];
    // Require a complete ISO timestamp; DateTime.parse alone accepts dates and
    // normalizes invalid calendar dates. Jorge's local ISO timestamps are valid.
    final timestamp = time is String ? DateTime.tryParse(time) : null;
    final iso =
        time is String &&
        RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})?$',
        ).hasMatch(time);
    if (phone is! bool ||
        confidence is! num ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1 ||
        persons is! int ||
        persons < 0 ||
        latency is! num ||
        !latency.isFinite ||
        latency < 0 ||
        timestamp == null ||
        !iso) {
      throw const FormatException('Invalid detection fields');
    }
    final calendar = DateTime.tryParse(time.substring(0, 19));
    final zone = RegExp(r'([+-])(\d{2}):(\d{2})$').firstMatch(time);
    if (zone != null &&
        (int.parse(zone.group(2)!) > 23 || int.parse(zone.group(3)!) > 59)) {
      throw const FormatException('Invalid detection timezone');
    }
    if (calendar == null ||
        calendar.toIso8601String().substring(0, 19) != time.substring(0, 19)) {
      throw const FormatException('Invalid detection timestamp');
    }
    // Native implementations retain full score precision. A contradictory
    // contract is a detector failure, never a clear result.
    if (phone != (confidence >= CameraDetectionService.phoneThreshold)) {
      throw const FormatException('Inconsistent phone detection');
    }
    return DetectionEvent._(
      phoneDetected: phone,
      phoneConfidence: confidence.toDouble(),
      personCount: persons,
      latencyMs: latency.toDouble(),
      timestamp: timestamp,
    );
  }
}

enum CameraDetectionState {
  stopped,
  checking,
  monitoring,
  phoneDetected,
  unavailable,
}

class CameraDetectionSession extends ChangeNotifier {
  CameraDetectionSession._(this._service);
  final CameraDetectionService _service;
  CameraDetectionState _state = CameraDetectionState.stopped;
  DetectionEvent? _latest;
  String? _errorCode;
  int _token = 0;
  bool _closed = false;
  bool _failed = false;
  Timer? _watchdog;
  Future<void>? _closing;

  CameraDetectionState get state => _state;
  DetectionEvent? get latest => _latest;
  String? get errorCode => _errorCode;

  void _change(CameraDetectionState state) {
    if (_closed) return;
    _state = state;
    notifyListeners();
  }

  Future<void> start() {
    if (_closed || _state == CameraDetectionState.phoneDetected) {
      return Future.value();
    }
    _watchdog?.cancel();
    _token = ++_service._sequence;
    _latest = null;
    _failed = false;
    _errorCode = null;
    _change(CameraDetectionState.checking);
    return _service._start(this, _token);
  }

  Future<void> stop() {
    _watchdog?.cancel();
    ++_token; // Reject events synchronously, before asynchronous native cleanup.
    if (_state != CameraDetectionState.phoneDetected &&
        _state != CameraDetectionState.unavailable) {
      _change(CameraDetectionState.stopped);
    }
    return _service._stop(this);
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(
      _service.frameTimeout,
      () => _service._fail(this, 'detector_timeout'),
    );
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _watchdog?.cancel();
    ++_token;
    return _closing = _service._stop(this);
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

/// Serializes camera ownership across routes. Each native run carries a token,
/// so late permission replies, frames and cleanup cannot authorize a new run.
class CameraDetectionService {
  CameraDetectionService({this.frameTimeout = const Duration(seconds: 5)});
  static final instance = CameraDetectionService();
  static const phoneThreshold = 0.15;
  static const personThreshold = 0.5;
  static const _methods = MethodChannel('aperture/camera_detection');
  static const _events = EventChannel('aperture/camera_detection/events');
  final Duration frameTimeout;
  CameraDetectionSession? _owner;
  CameraDetectionSession? _nativeOwner;
  int? _nativeToken;
  int _sequence = 0;
  bool _cleanupFailed = false;
  StreamSubscription<dynamic>? _subscription;
  Future<void> _pending = Future.value();

  CameraDetectionSession createSession() {
    final previous = _owner;
    if (previous != null) {
      previous._watchdog?.cancel();
      previous._errorCode = 'session_replaced';
      previous._change(CameraDetectionState.unavailable);
    }
    return _owner = CameraDetectionSession._(this);
  }

  Future<void> _enqueue(Future<void> Function() action) {
    return _pending = _pending.then((_) => action()).catchError((Object _) {
      _cleanupFailed = true;
      final owner = _owner;
      if (owner != null) _fail(owner, 'native_error');
    });
  }

  bool _current(CameraDetectionSession session, int token) =>
      _owner == session &&
      !session._closed &&
      session._token == token &&
      !session._failed;

  Future<void> _start(CameraDetectionSession session, int token) =>
      _enqueue(() async {
        if (!_current(session, token)) return;
        await _stopNative();
        if (!_current(session, token)) return;
        if (_cleanupFailed) {
          _fail(session, 'cleanup_failed');
          return;
        }
        _nativeOwner = session;
        _nativeToken = token;
        var acknowledged = false;
        void accept() {
          if (acknowledged &&
              session._latest != null &&
              session.state != CameraDetectionState.phoneDetected) {
            session._change(CameraDetectionState.monitoring);
          }
        }

        _subscription = _events.receiveBroadcastStream().listen(
          (dynamic payload) {
            if (!_current(session, token)) return;
            if (session.state == CameraDetectionState.phoneDetected) return;
            if (payload is! Map || payload['session_id'] is! int) {
              _fail(session, 'invalid_event');
              return;
            }
            if (payload['session_id'] != token) return;
            try {
              final event = DetectionEvent.parse(payload);
              session._latest = event;
              session._armWatchdog();
              if (event.phoneDetected) {
                session._watchdog?.cancel();
                session._change(CameraDetectionState.phoneDetected);
                unawaited(_stop(session));
              } else if (session.state != CameraDetectionState.phoneDetected) {
                accept();
              }
            } on FormatException {
              _fail(session, 'invalid_event');
            }
          },
          onError: (Object error) {
            if (_current(session, token)) {
              _fail(
                session,
                error is PlatformException ? error.code : 'native_error',
              );
            }
          },
          onDone: () {
            if (_current(session, token)) _fail(session, 'stream_closed');
          },
        );
        try {
          final started = await _methods
              .invokeMethod<bool>('start', {'session_id': token})
              .timeout(frameTimeout);
          if (!_current(session, token)) return;
          if (started != true) {
            _fail(session, 'startup_failed');
            return;
          }
          acknowledged = true;
          if (session.state != CameraDetectionState.phoneDetected) {
            session._armWatchdog();
          }
          accept();
        } catch (error) {
          if (_current(session, token)) {
            _fail(
              session,
              error is PlatformException ? error.code : 'startup_failed',
            );
          }
        }
      });

  void _fail(CameraDetectionSession session, String code) {
    if (_owner != session ||
        session._closed ||
        session.state == CameraDetectionState.phoneDetected ||
        session._failed) {
      return;
    }
    session._failed = true;
    session._watchdog?.cancel();
    session._errorCode = code;
    session._change(CameraDetectionState.unavailable);
    unawaited(_stop(session));
  }

  Future<void> _stop(CameraDetectionSession session) => _enqueue(() async {
    if (_nativeOwner == session) await _stopNative();
    if (_owner == session && session._closed) _owner = null;
  });

  Future<void> _stopNative() async {
    final token = _nativeToken;
    _nativeToken = null;
    _nativeOwner = null;
    final subscription = _subscription;
    _subscription = null;
    try {
      // Stop first: even failed stream cancellation must release the camera.
      if (token != null) {
        await _methods
            .invokeMethod<void>('stop', {'session_id': token})
            .timeout(frameTimeout);
      }
    } catch (_) {
      _cleanupFailed = true;
    } finally {
      try {
        await subscription?.cancel().timeout(frameTimeout);
      } catch (_) {
        _cleanupFailed = true;
      }
    }
  }
}
