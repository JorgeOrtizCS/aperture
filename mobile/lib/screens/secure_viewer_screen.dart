import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/viewing_state_controller.dart';
import '../services/camera_detection.dart';
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

  const SecureViewerScreen({
    super.key,
    this.contentTitle = 'Project Document',
    this.ownerName = 'Alex Morgan',
    this.restrictions = ContentRestrictions.demoDefaults,
    this.conditionProvider,
    this.captureProtection,
    this.cameraDetection,
  });

  @override
  State<SecureViewerScreen> createState() => _SecureViewerScreenState();
}

class _SecureViewerScreenState extends State<SecureViewerScreen>
    with WidgetsBindingObserver {
  late final ViewingStateController _controller;
  bool _opening = false;
  bool _violationAnnounced = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Preflight starts unverified. The Check Conditions action begins evaluation;
    // no native session or successful check is fabricated by visiting this page.
    _controller = ViewingStateController(
      restrictions: widget.restrictions,
      conditions: widget.conditionProvider ?? UnverifiedViewingConditions(),
      protection: widget.captureProtection ?? ScreenCaptureProtection.instance,
    )..addListener(_stateChanged);
  }

  void _stateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The current content route handles lifecycle for the same shared controller.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (state != AppLifecycleState.resumed) {
      _controller.suspend();
    } else {
      unawaited(_controller.resume(recheck: _controller.hasStarted));
    }
  }

  Future<void> _openSecureContent({bool demoPreview = false}) async {
    if (_opening || _controller.sessionEnded) return;
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
                cameraDetection: widget.cameraDetection,
                onSecurityViolation: (reason) =>
                    _controller.endForSecurityViolation(reason: reason),
              )
            : SecureContentViewerScreen(
                contentTitle: widget.contentTitle,
                restrictions: widget.restrictions,
                viewingController: _controller,
                cameraDetection: widget.cameraDetection,
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      backgroundColor: AppTheme.background,
      foregroundColor: AppTheme.textPrimary,
      elevation: 0,
      title: const Text('Secure Viewer'),
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
          const SizedBox(height: 24),
          ViewingStatusPanel(
            controller: _controller,
            onRecheck: () => unawaited(_controller.revalidate()),
          ),
          const SizedBox(height: 16),
          ViewingActionButton(
            label: 'Open Secure Content',
            icon: Icons.open_in_full_outlined,
            onPressed: !_opening && _controller.state == ViewingState.allowed
                ? () => _openSecureContent()
                : null,
          ),
          if (!_controller.hasStarted && !_controller.sessionEnded) ...[
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
          const SizedBox(height: 28),
          const SectionHeader(
            title: 'Security Policy',
            icon: Icons.shield_outlined,
          ),
          const SizedBox(height: 14),
          ContentRestrictionsSummary(restrictions: widget.restrictions),
          const SizedBox(height: 28),
          const SectionHeader(
            title: 'Condition Checks',
            icon: Icons.verified_outlined,
          ),
          const SizedBox(height: 14),
          ViewingConditionList(controller: _controller),
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
