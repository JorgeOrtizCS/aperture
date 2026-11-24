import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricState {
  required,
  verifying,
  verified,
  cancelled,
  failed,
  unavailable,
  notEnrolled,
  temporaryLockout,
  permanentLockout,
  busy,
  ended,
}

abstract interface class BiometricAuthenticator {
  Future<BiometricState> authenticate();
  Future<void> cancel();
}

/// Owns one native attempt. The process-wide lease serializes prompts, never
/// shares a successful result, and prevents old cleanup cancelling a new prompt.
class LocalBiometricAuthenticator implements BiometricAuthenticator {
  LocalBiometricAuthenticator({LocalAuthentication? authentication})
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;
  static LocalBiometricAuthenticator? _owner;
  bool _cancelled = false;
  Future<void>? _cancelling;

  @override
  Future<BiometricState> authenticate() async {
    if (_owner != null) return BiometricState.busy;
    _owner = this;
    _cancelled = false;
    _cancelling = null;
    try {
      // authenticate() performs the OS capability/enrollment checks and reports
      // typed failures. Boolean capability helpers are not authoritative here:
      // iOS may report no available templates during biometric lockout.
      final success = await _authentication.authenticate(
        localizedReason:
            'Verify your identity to start this Aperture viewing session.',
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: false,
      );
      return _cancelled
          ? BiometricState.cancelled
          : success
          ? BiometricState.verified
          : BiometricState.failed;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout => BiometricState.cancelled,
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noCredentialsSet => BiometricState.notEnrolled,
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
        LocalAuthExceptionCode.uiUnavailable => BiometricState.unavailable,
        LocalAuthExceptionCode.temporaryLockout =>
          BiometricState.temporaryLockout,
        LocalAuthExceptionCode.biometricLockout =>
          BiometricState.permanentLockout,
        LocalAuthExceptionCode.authInProgress => BiometricState.busy,
        _ => BiometricState.failed,
      };
    } catch (_) {
      return BiometricState.unavailable;
    } finally {
      // A timed-out stop with an unknown native outcome must not release the
      // lease: a later cancellation could otherwise interrupt another session.
      await _cancelling;
      if (identical(_owner, this)) _owner = null;
    }
  }

  @override
  Future<void> cancel() {
    _cancelled = true;
    if (!identical(_owner, this)) return Future.value();
    return _cancelling ??= _stop();
  }

  Future<void> _stop() async {
    try {
      await _authentication.stopAuthentication();
    } catch (_) {
      // The still-outstanding authenticate future retains ownership. No success
      // may be consumed by the invalidated session even if the native stop fails.
    }
  }
}

/// A fresh instance belongs to exactly one viewing controller, never an account
/// preference or app singleton. Foreground approval is additionally required.
class BiometricVerification extends ChangeNotifier {
  BiometricVerification({
    BiometricAuthenticator? authenticator,
    this.timeout = const Duration(seconds: 60),
  }) : _authenticator = authenticator ?? LocalBiometricAuthenticator();

  final BiometricAuthenticator _authenticator;
  final Duration timeout;
  BiometricState _state = BiometricState.required;
  bool _foreground = true;
  bool _closed = false;
  bool _pendingSuccess = false;
  int _generation = 0;
  Future<void>? _inFlight;
  Completer<BiometricState>? _invalidation;

  BiometricState get state => !_foreground && _state == BiometricState.verified
      ? BiometricState.required
      : _state;
  bool get approved =>
      !_closed && _foreground && _state == BiometricState.verified;
  bool get busy => _inFlight != null || _pendingSuccess;
  bool get canVerify =>
      !_closed &&
      _foreground &&
      !busy &&
      _state != BiometricState.ended &&
      !approved;

  Future<void> verify() {
    if (_inFlight != null) return _inFlight!;
    if (!canVerify) return Future.value();
    final generation = ++_generation;
    _state = BiometricState.verifying;
    _invalidation = Completer<BiometricState>();
    // Schedule first so reentrant listeners see the same pending operation.
    final operation = Future<void>.microtask(() => _verify(generation));
    _inFlight = operation;
    notifyListeners();
    return operation;
  }

  Future<void> _verify(int generation) async {
    try {
      if (_closed ||
          generation != _generation ||
          _state == BiometricState.ended) {
        return;
      }
      final result = await Future.any<BiometricState>([
        _authenticator.authenticate(),
        _invalidation!.future,
      ]).timeout(timeout);
      if (_closed ||
          generation != _generation ||
          _state == BiometricState.ended) {
        return;
      }
      // Unknown future adapter results must also fail closed.
      final terminal = const {
        BiometricState.verified,
        BiometricState.cancelled,
        BiometricState.failed,
        BiometricState.unavailable,
        BiometricState.notEnrolled,
        BiometricState.temporaryLockout,
        BiometricState.permanentLockout,
        BiometricState.busy,
      };
      if (result == BiometricState.verified && !_foreground) {
        _pendingSuccess = true; // Transient system-prompt inactivity only.
      } else {
        _state = terminal.contains(result) ? result : BiometricState.failed;
      }
    } catch (_) {
      if (!_closed && generation == _generation) {
        _state = BiometricState.unavailable;
        unawaited(_cancel());
      }
    } finally {
      _inFlight = null;
      if (!_closed) notifyListeners();
    }
  }

  void _invalidateAttempt() {
    final cancellation = _invalidation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete(BiometricState.cancelled);
    }
  }

  Future<void> _cancel() async {
    try {
      await _authenticator.cancel();
    } catch (_) {}
  }

  void suspend({required bool backgrounded}) {
    if (_closed || _state == BiometricState.ended) return;
    _foreground = false;
    if (backgrounded || _state == BiometricState.verified) {
      ++_generation;
      _invalidateAttempt();
      _pendingSuccess = false;
      _state = BiometricState.required;
      unawaited(_cancel());
    }
    notifyListeners();
  }

  void resume() {
    if (_closed || _state == BiometricState.ended) return;
    _foreground = true;
    if (_pendingSuccess) {
      _pendingSuccess = false;
      _state = BiometricState.verified;
    }
    notifyListeners();
  }

  void revoke({bool ended = false}) {
    if (_closed || _state == BiometricState.ended) return;
    ++_generation;
    _invalidateAttempt();
    _pendingSuccess = false;
    _state = ended ? BiometricState.ended : BiometricState.required;
    unawaited(_cancel());
    notifyListeners();
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    ++_generation;
    _invalidateAttempt();
    _pendingSuccess = false;
    _state = BiometricState.ended;
    unawaited(_cancel());
    super.dispose();
  }
}
