import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/viewing_state_controller.dart';
import '../services/biometric_verification.dart';
import '../theme/app_theme.dart';
import 'security_notice.dart';
import 'viewing_status_panel.dart';

({String title, String message}) biometricMessage(
  BiometricState state,
) => switch (state) {
  BiometricState.required => (
    title: 'Verification required',
    message: 'Verify with Face ID, Touch ID, or a supported Android biometric for this session. PIN and passcode cannot authorize viewing.',
  ),
  BiometricState.verifying => (
    title: 'Verification in progress',
    message:
        'Complete the system biometric prompt. Protected content stays hidden.',
  ),
  BiometricState.verified => (
    title: 'Verification successful',
    message: 'Device user verified for this session only. Sender authorization, capture protection, and camera checks must also pass; no backend access is implied.',
  ),
  BiometricState.cancelled => (
    title: 'Verification cancelled',
    message: 'No biometric approval was granted. Content stays hidden. You may retry.',
  ),
  BiometricState.failed => (
    title: 'Verification failed',
    message: 'Your identity could not be verified with biometrics. Content stays hidden. You may retry with biometrics only.',
  ),
  BiometricState.unavailable => (
    title: 'Biometrics unavailable',
    message: 'Biometric hardware or the system authentication service is unavailable. Content stays hidden. Check device settings and retry when available.',
  ),
  BiometricState.notEnrolled => (
    title: 'Biometrics not enrolled',
    message: 'No enrolled biometric is available to Aperture. Enroll a biometric or enable biometric permission in device settings, then retry. A PIN or passcode cannot authorize viewing.',
  ),
  BiometricState.temporaryLockout => (
    title: 'Biometric lockout',
    message: 'Biometrics are temporarily locked after unsuccessful attempts. Wait for the system lockout to clear, then retry. Content stays hidden.',
  ),
  BiometricState.permanentLockout => (
    title: 'Biometric lockout',
    message: 'Biometrics are locked by the operating system. Resolve the lockout in device settings or by unlocking your device, then retry biometrics. Device unlock alone never grants Aperture access.',
  ),
  BiometricState.busy => (
    title: 'Verification unavailable',
    message: 'Another system verification is finishing. Content stays hidden. Wait, then retry.',
  ),
  BiometricState.ended => (
    title: 'Viewing session ended',
    message: 'Biometric approval has been revoked. Verification cannot restore a permanently ended viewing session.',
  ),
};

class BiometricStatusPanel extends StatelessWidget {
  const BiometricStatusPanel({super.key, required this.controller});
  final ViewingStateController controller;

  @override
  Widget build(BuildContext context) {
    final identity = controller.biometrics;
    final state = controller.sessionEnded
        ? BiometricState.ended
        : identity.state;
    final message = biometricMessage(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state == BiometricState.verified ||
            state == BiometricState.verifying)
          Semantics(
            container: true,
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      message.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: state == BiometricState.verified
                            ? AppTheme.success
                            : AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(message.message),
                ],
              ),
            ),
          )
        else
          SecurityNotice(
            title: message.title,
            message: message.message,
            icon: Icons.fingerprint,
            urgent: state == BiometricState.ended,
          ),
        if (!controller.sessionEnded && !identity.approved)
          ViewingActionButton(
            label: identity.busy
                ? 'Verification in progress'
                : 'Verify identity',
            icon: Icons.fingerprint,
            onPressed: identity.canVerify
                ? () => unawaited(controller.verifyIdentity())
                : null,
          ),
      ],
    );
  }
}
