import 'dart:async';

import 'package:flutter/material.dart';

import '../services/screen_capture_protection.dart';
import '../theme/app_theme.dart';

enum SecureContentViewerExitReason { securityViolation }

class SecureContentViewerScreen extends StatefulWidget {
  final String contentTitle;

  const SecureContentViewerScreen({super.key, required this.contentTitle});

  @override
  State<SecureContentViewerScreen> createState() =>
      _SecureContentViewerScreenState();
}

class _SecureContentViewerScreenState extends State<SecureContentViewerScreen> {
  final ScreenCaptureProtection _screenCaptureProtection =
      ScreenCaptureProtection.instance;
  StreamSubscription<bool>? _captureStateSubscription;
  bool _captureDetected = false;
  bool _viewingConditionInvalid = false;
  bool _protectionDisabled = false;

  @override
  void initState() {
    super.initState();

    _captureDetected = _screenCaptureProtection.isCaptureActive;
    _captureStateSubscription = _screenCaptureProtection.captureStateChanges
        .listen(_handleCaptureStateChanged);
    _enableScreenCaptureProtection();
  }

  Future<void> _enableScreenCaptureProtection() async {
    final captureDetected = await _screenCaptureProtection.enableProtection();
    if (!mounted) {
      return;
    }

    setState(() {
      _captureDetected = captureDetected;
    });
  }

  void _handleCaptureStateChanged(bool captureDetected) {
    if (!mounted) {
      return;
    }

    setState(() {
      _captureDetected = captureDetected;
    });
  }

  Future<void> _simulateSecurityViolation() async {
    if (_viewingConditionInvalid) {
      return;
    }

    setState(() {
      _viewingConditionInvalid = true;
    });

    await _disableScreenCaptureProtection();
    if (!mounted) {
      return;
    }

    Navigator.pop(context, SecureContentViewerExitReason.securityViolation);
  }

  Future<void> _disableScreenCaptureProtection() async {
    if (_protectionDisabled) {
      return;
    }

    _protectionDisabled = true;
    await _captureStateSubscription?.cancel();
    _captureStateSubscription = null;
    await _screenCaptureProtection.disableProtection();
  }

  @override
  void dispose() {
    unawaited(_disableScreenCaptureProtection());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: Text(widget.contentTitle),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: _SecureIndicator(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _viewingConditionInvalid
                        ? const _ViewingConditionInvalidState()
                        : _captureDetected
                        ? const _CaptureBlockedState()
                        : const _ProtectedRenderPlaceholder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _captureDetected
                    ? 'Protected content will reappear automatically when screen capture stops.'
                    : 'Decrypted PDFs, images, and text content will render in the protected area when the secure content service is connected.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _viewingConditionInvalid
                    ? null
                    : _simulateSecurityViolation,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.warning,
                  side: const BorderSide(color: Color(0xFFFCD34D)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.warning_amber_outlined),
                label: const Text(
                  'Demo: Simulate Security Violation',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewingConditionInvalidState extends StatelessWidget {
  const _ViewingConditionInvalidState();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('viewing-condition-invalid'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.lock_clock_outlined,
                color: AppTheme.warning,
                size: 38,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Viewing Ended',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'A required security condition is no longer satisfied. Protected content is being hidden and access will return to the secure viewer.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureBlockedState extends StatelessWidget {
  const _CaptureBlockedState();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('capture-blocked'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.visibility_off_outlined,
                color: AppTheme.warning,
                size: 38,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Content Hidden',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Screen recording or screen sharing was detected. Aperture has temporarily hidden this protected content. Stop screen capture to continue viewing.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecureIndicator extends StatelessWidget {
  const _SecureIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, color: AppTheme.primary, size: 16),
          SizedBox(width: 6),
          Text(
            'Secure',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProtectedRenderPlaceholder extends StatelessWidget {
  const _ProtectedRenderPlaceholder();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            Expanded(
              child: Center(
                key: const ValueKey('protected-render-placeholder'),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: AppTheme.primarySoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.insert_drive_file_outlined,
                          color: AppTheme.primary,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Protected content viewer',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'This area is reserved for the decrypted document, image, or message body.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (constraints.maxHeight > 420) ...[
              const Divider(color: AppTheme.border),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Renderer placeholder sized for future PDF, image, or text modules.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
