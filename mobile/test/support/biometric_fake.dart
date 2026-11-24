import 'dart:async';

import 'package:aperture/services/biometric_verification.dart';

/// Test-only authenticator; no successful fake exists in lib/ or native code.
class BiometricFake implements BiometricAuthenticator {
  BiometricState result = BiometricState.verified;
  Completer<BiometricState>? pending;
  Object? error;
  int starts = 0;
  int cancels = 0;

  @override
  Future<BiometricState> authenticate() async {
    starts++;
    if (error != null) throw error!;
    return pending?.future ?? result;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}
