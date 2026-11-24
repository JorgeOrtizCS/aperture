import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/viewing_state_controller.dart';
import '../services/camera_detection.dart';
import '../services/screen_capture_protection.dart';
import '../services/viewing_conditions.dart';
import '../widgets/content_restrictions_section.dart';
import '../theme/app_theme.dart';
import '../widgets/viewing_status_panel.dart';

enum SecureContentViewerExitReason { securityViolation }

class SecureContentViewerScreen extends StatefulWidget {
  final String contentTitle;
  final ContentRestrictions restrictions;
  final ViewingConditionProvider? conditionProvider;
  final ScreenCaptureProtection? captureProtection;
  final CameraDetectionService? cameraDetection;
  final bool demoPreview;
  final ViewingStateController? viewingController;
  final ValueChanged<ViewingIssueKind>? onSecurityViolation;

  const SecureContentViewerScreen({
    super.key,
    required this.contentTitle,
    required this.restrictions,
    this.conditionProvider,
    this.captureProtection,
    this.cameraDetection,
    this.viewingController,
  }) : demoPreview = false,
       onSecurityViolation = null;

  /// This route can display only the existing non-sensitive placeholder.
  const SecureContentViewerScreen.demo({
    super.key,
    required this.contentTitle,
    required this.restrictions,
    this.captureProtection,
    this.cameraDetection,
    this.onSecurityViolation,
  }) : conditionProvider = null,
       viewingController = null,
       demoPreview = true;

  @override
  State<SecureContentViewerScreen> createState() =>
      _SecureContentViewerScreenState();
}

class _SecureContentViewerScreenState extends State<SecureContentViewerScreen>
    with WidgetsBindingObserver {
  late final ViewingStateController _controller;
  late final CameraDetectionSession _camera;
  DemoViewingConditions? _demoConditions;
  late final bool _ownsController;
  bool _exitScheduled = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _demoConditions = widget.demoPreview ? DemoViewingConditions() : null;
    _ownsController = widget.viewingController == null;
    _controller =
        widget.viewingController ??
        ViewingStateController(
          restrictions: widget.restrictions,
          conditions:
              _demoConditions ??
              widget.conditionProvider ??
              UnverifiedViewingConditions(),
          protection:
              widget.captureProtection ?? ScreenCaptureProtection.instance,
          demoPreview: widget.demoPreview,
        );
    _controller.addListener(_stateChanged);
    _camera =
        (widget.cameraDetection ?? CameraDetectionService.instance)
            .createSession()
          ..addListener(_cameraChanged);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _controller.suspend();
    } else if (_ownsController) {
      unawaited(_controller.revalidate());
    }
    if ((lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        !_controller.sessionEnded) {
      unawaited(_camera.start());
    }
    if (_controller.securityViolation) {
      // A shared session may have ended between preflight and route creation.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _stateChanged();
      });
    }
  }

  void _cameraChanged() {
    if (!mounted || _leaving) return;
    if (_camera.state == CameraDetectionState.phoneDetected) {
      _controller.endForSecurityViolation(
        reason: ViewingIssueKind.phoneDetected,
      );
    }
    setState(() {});
  }

  void _stateChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.securityViolation && !_exitScheduled && !_leaving) {
      _exitScheduled = true;
      unawaited(_exitAfterContentIsHidden());
    }
  }

  Future<void> _exitAfterContentIsHidden() async {
    // Paint the opaque replacement before popping or releasing native protection.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _leaving) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _leaving = true;
    widget.onSecurityViolation?.call(_controller.violationReason!);
    Navigator.pop(context, SecureContentViewerExitReason.securityViolation);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_leaving) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.resume());
      if (!_controller.sessionEnded) unawaited(_camera.start());
    } else {
      _controller.suspend();
      unawaited(_camera.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_stateChanged);
    _camera.removeListener(_cameraChanged);
    _camera.dispose();
    if (_ownsController) _controller.dispose();
    _demoConditions?.dispose();
    super.dispose();
  }

  Widget _viewingArea() {
    if (!_leaving &&
        _controller.state == ViewingState.allowed &&
        _camera.state == CameraDetectionState.monitoring) {
      return const _ProtectedRenderPlaceholder();
    }
    if (!_leaving && _controller.state == ViewingState.allowed) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Protected content is hidden until camera protection is confirmed.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ViewingStatusPanel(
      controller: _controller,
      onRecheck: () => unawaited(_controller.revalidate()),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) {
        _leaving = true;
        unawaited(_camera.stop());
        if (_ownsController) {
          _controller.suspend();
        } else {
          setState(
            () {},
          ); // Hide the outgoing content without changing preflight state.
        }
      }
    },
    child: Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: Text(
          widget.contentTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            // No transition retains the outgoing protected subtree or semantics.
            _viewingArea(),
            const SizedBox(height: 12),
            _cameraStatus(),
            const SizedBox(height: 16),
            if (_controller.state == ViewingState.allowed &&
                _camera.state == CameraDetectionState.monitoring)
              Text(
                widget.demoPreview ? 'Demo checks only' : 'Checks passed',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.success,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              widget.demoPreview
                  ? 'Demo preview: placeholder only. Authorization, expiration, and view-count checks are not evaluated.'
                  : 'Content stays hidden until capture protection and all required checks are confirmed.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            if (_demoConditions != null && !_controller.sessionEnded) ...[
              ViewingActionButton(
                label: _demoConditions!.satisfied
                    ? 'Demo: Fail Viewing Condition'
                    : 'Demo: Restore Viewing Condition',
                secondary: true,
                icon: Icons.science_outlined,
                onPressed: _demoConditions!.toggle,
              ),
              const SizedBox(height: 8),
            ],
            if (!_controller.sessionEnded)
              ViewingActionButton(
                label: 'Demo: Simulate Security Violation',
                secondary: true,
                icon: Icons.science_outlined,
                onPressed: () => _controller.endForSecurityViolation(),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Close viewer'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _cameraStatus() {
    final state = _camera.state;
    final latest = _camera.latest;
    final title = switch (state) {
      CameraDetectionState.stopped => 'Camera monitoring paused',
      CameraDetectionState.checking => 'Checking camera protection',
      CameraDetectionState.monitoring => 'Camera protection active',
      CameraDetectionState.phoneDetected => 'Phone detected — content hidden',
      CameraDetectionState.unavailable =>
        _camera.errorCode == 'permission_denied'
            ? 'Camera permission denied'
            : 'Camera protection unavailable',
    };
    return Column(
      children: [
        Text(
          title,
          key: const ValueKey('camera-detection-status'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: state == CameraDetectionState.monitoring
                ? AppTheme.success
                : AppTheme.textPrimary,
          ),
        ),
        if (latest != null)
          Text(
            'People: ${latest.personCount} · Phone confidence: ${latest.phoneConfidence.toStringAsFixed(2)} · Inference: ${latest.latencyMs.toStringAsFixed(1)} ms',
            textAlign: TextAlign.center,
          ),
        if (state == CameraDetectionState.unavailable) ...[
          const Text(
            'Camera checks failed. Content stays hidden. If permission was denied, allow Camera in system settings.',
            textAlign: TextAlign.center,
          ),
          if (!_controller.sessionEnded)
            TextButton(
              onPressed: () {
                unawaited(_controller.revalidate());
                unawaited(_camera.start());
              },
              child: const Text('Retry camera protection'),
            ),
        ],
      ],
    );
  }
}

class _ProtectedRenderPlaceholder extends StatelessWidget {
  const _ProtectedRenderPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('protected-render-placeholder'),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.border),
    ),
    child: const Column(
      children: [
        ExcludeSemantics(
          child: Icon(
            Icons.insert_drive_file_outlined,
            size: 48,
            color: AppTheme.primary,
          ),
        ),
        SizedBox(height: 20),
        Text(
          'Protected content viewer',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        SizedBox(height: 12),
        Text(
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
  );
}
