import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../controllers/viewing_state_controller.dart';
import '../services/camera_detection.dart';
import '../services/access_status.dart';
import '../services/biometric_verification.dart';
import '../widgets/biometric_status_panel.dart';
import '../services/screen_capture_protection.dart';
import '../services/viewing_conditions.dart';
import '../theme/app_theme.dart';
import '../widgets/content_restrictions_section.dart';
import '../widgets/content_restrictions_summary.dart';
import '../widgets/section_header.dart';
import '../widgets/viewing_status_panel.dart';
import 'secure_content_viewer_screen.dart';

class SecureViewerScreen extends StatefulWidget {
  final String contentTitle;
  final String ownerName;
  final ContentRestrictions restrictions;
  final ViewingConditionProvider? conditionProvider;
  final ScreenCaptureProtection? captureProtection;
  final CameraDetectionService? cameraDetection;
  final BiometricAuthenticator? biometricAuthenticator;
  final ViewingStateController? viewingController;
  final ValueChanged<AccessStatusKind?>? onCameraStatus;
  final bool showPolicySummary;
  final bool allowDemoPreview;
  final Widget? recipientDetails;
  final Widget? recipientAuthorization;
  final Widget? recipientDeviceChecks;
  final bool recipientChecksUnavailable;

  const SecureViewerScreen({
    super.key,
    this.contentTitle = 'Project Document',
    this.ownerName = 'Alex Morgan',
    this.restrictions = ContentRestrictions.demoDefaults,
    this.conditionProvider,
    this.captureProtection,
    this.cameraDetection,
    this.biometricAuthenticator,
    this.viewingController,
    this.onCameraStatus,
    this.showPolicySummary = true,
    this.allowDemoPreview = true,
    this.recipientDetails,
    this.recipientAuthorization,
    this.recipientDeviceChecks,
    this.recipientChecksUnavailable = false,
  });

  @override
  State<SecureViewerScreen> createState() => _SecureViewerScreenState();
}

class _SecureViewerScreenState extends State<SecureViewerScreen>
    with WidgetsBindingObserver {
  late final ViewingStateController _controller;
  late final bool _ownsController;
  bool _opening = false;
  bool _violationAnnounced = false;
  bool _rebuildScheduled = false;
  bool _cleanupScheduled = false;
  bool get _recipientRoute => widget.recipientAuthorization != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Preflight starts unverified. The Check Conditions action begins evaluation;
    // no native session or successful check is fabricated by visiting this page.
    _ownsController = widget.viewingController == null;
    _controller =
        (widget.viewingController ??
        ViewingStateController(
          restrictions: widget.restrictions,
          biometricAuthenticator: widget.biometricAuthenticator,
          conditions: widget.conditionProvider ?? UnverifiedViewingConditions(),
          protection:
              widget.captureProtection ?? ScreenCaptureProtection.instance,
        ));
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _controller.suspend();
    }
    _controller.addListener(_stateChanged);
  }

  void _stateChanged() {
    if (!mounted) return;
    if (_controller.sessionEnded && !_cleanupScheduled) {
      _cleanupScheduled = true;
      unawaited(_releaseCaptureAfterLockFrame());
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_rebuildScheduled) return;
      _rebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rebuildScheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _releaseCaptureAfterLockFrame() async {
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) _controller.releaseEndedCapture();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The current content route handles lifecycle for the same shared controller.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (state != AppLifecycleState.resumed) {
      _controller.suspend(backgrounded: state != AppLifecycleState.inactive);
    } else {
      unawaited(_controller.resume(recheck: _controller.hasStarted));
    }
  }

  Future<void> _openSecureContent({bool demoPreview = false}) async {
    if (_opening ||
        widget.recipientChecksUnavailable ||
        _controller.sessionEnded ||
        (demoPreview && (!kDebugMode || !widget.allowDemoPreview))) {
      return;
    }
    if (demoPreview
        ? _controller.hasStarted
        : _controller.state != ViewingState.allowed) {
      return;
    }
    setState(() => _opening = true);
    if (!demoPreview) unawaited(_controller.revalidate());
    final exitReason = await Navigator.push<SecureContentViewerExitReason>(
      context,
      MaterialPageRoute(
        builder: (context) => demoPreview
            ? SecureContentViewerScreen.demo(
                contentTitle: widget.contentTitle,
                restrictions: widget.restrictions,
                captureProtection: widget.captureProtection,
                biometricAuthenticator: widget.biometricAuthenticator,
                cameraDetection: widget.cameraDetection,
                onSecurityViolation: (reason) =>
                    _controller.endForSecurityViolation(reason: reason),
              )
            : SecureContentViewerScreen(
                contentTitle: widget.contentTitle,
                restrictions: widget.restrictions,
                viewingController: _controller,
                cameraDetection: widget.cameraDetection,
                onCameraStatus: widget.onCameraStatus,
                recipientAuthorization: widget.recipientAuthorization,
              ),
      ),
    );
    if (!mounted) return;
    setState(() => _opening = false);
    if (exitReason == SecureContentViewerExitReason.securityViolation &&
        !_violationAnnounced) {
      _violationAnnounced = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (_controller.violationReason) {
            ViewingIssueKind.screenshot =>
              'Screenshot detected. This viewing session has ended.',
            ViewingIssueKind.phoneDetected =>
              'Phone detected. This viewing session has ended.',
            _ => 'Demo security violation. This viewing session has ended.',
          }),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_stateChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      backgroundColor: AppTheme.background,
      foregroundColor: AppTheme.textPrimary,
      elevation: 0,
      title: Text(_recipientRoute ? 'Recipient access' : 'Secure Viewer'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.contentTitle,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Shared by ${widget.ownerName}',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          if (_recipientRoute) ...[
            const SizedBox(height: 8),
            ?widget.recipientDetails,
            const SizedBox(height: 16),
            const ProtectedDisplayNotice(),
            const SizedBox(height: 16),
            widget.recipientAuthorization!,
            const SizedBox(height: 16),
            ?widget.recipientDeviceChecks,
          ],
          if (!widget.recipientChecksUnavailable) ...[
            const SizedBox(height: 24),
            BiometricStatusPanel(controller: _controller),
            const SizedBox(height: 16),
            ViewingStatusPanel(
              controller: _controller,
              combinedServerChecks: _recipientRoute,
              onRecheck: () => unawaited(_controller.revalidate()),
            ),
            const SizedBox(height: 16),
            ViewingActionButton(
              label: _recipientRoute
                  ? 'Open security checks'
                  : 'Open Secure Content',
              icon: Icons.open_in_full_outlined,
              onPressed: !_opening && _controller.state == ViewingState.allowed
                  ? () => _openSecureContent()
                  : null,
            ),
          ],
          if (kDebugMode &&
              widget.allowDemoPreview &&
              !_controller.hasStarted &&
              !_controller.sessionEnded) ...[
            const SizedBox(height: 12),
            const Text(
              'Demo preview shows a placeholder only. It does not verify access to real content.',
              style: TextStyle(height: 1.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            ViewingActionButton(
              label: 'Open Demo Preview',
              icon: Icons.science_outlined,
              secondary: true,
              onPressed: _opening
                  ? null
                  : () => _openSecureContent(demoPreview: true),
            ),
          ],
          if (widget.showPolicySummary) ...[
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Security Policy',
              icon: Icons.shield_outlined,
            ),
            const SizedBox(height: 14),
            ContentRestrictionsSummary(restrictions: widget.restrictions),
          ],
          if (!widget.recipientChecksUnavailable) ...[
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Condition Checks',
              icon: Icons.verified_outlined,
            ),
            const SizedBox(height: 14),
            ViewingConditionList(
              controller: _controller,
              combinedServerChecks: _recipientRoute,
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Go back'),
          ),
        ],
      ),
    ),
  );
}
