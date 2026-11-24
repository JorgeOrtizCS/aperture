import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/viewing_state_controller.dart';
import '../services/camera_detection.dart';
import '../services/access_status.dart';
import '../services/biometric_verification.dart';
import '../widgets/biometric_status_panel.dart';
import '../services/screen_capture_protection.dart';
import '../services/viewing_conditions.dart';
import '../services/security_settings.dart';
import '../widgets/content_restrictions_section.dart';
import '../theme/app_theme.dart';
import '../widgets/viewing_status_panel.dart';
import '../widgets/security_notice.dart';

enum SecureContentViewerExitReason { securityViolation }

class SecureContentViewerScreen extends StatefulWidget {
  final String contentTitle;
  final ContentRestrictions restrictions;
  final ViewingConditionProvider? conditionProvider;
  final ScreenCaptureProtection? captureProtection;
  final CameraDetectionService? cameraDetection;
  final BiometricAuthenticator? biometricAuthenticator;
  final bool demoPreview;
  final ViewingStateController? viewingController;
  final ValueChanged<ViewingIssueKind>? onSecurityViolation;
  final ValueChanged<AccessStatusKind?>? onCameraStatus;
  final Widget? recipientAuthorization;

  const SecureContentViewerScreen({
    super.key,
    required this.contentTitle,
    required this.restrictions,
    this.conditionProvider,
    this.captureProtection,
    this.cameraDetection,
    this.biometricAuthenticator,
    this.viewingController,
    this.onCameraStatus,
    this.recipientAuthorization,
  }) : demoPreview = false,
       onSecurityViolation = null;

  /// This route can display only the existing non-sensitive placeholder.
  const SecureContentViewerScreen.demo({
    super.key,
    required this.contentTitle,
    required this.restrictions,
    this.captureProtection,
    this.cameraDetection,
    this.biometricAuthenticator,
    this.onSecurityViolation,
  }) : conditionProvider = null,
       viewingController = null,
       demoPreview = true,
       onCameraStatus = null,
       recipientAuthorization = null;

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
  bool _cleanupScheduled = false;
  bool _leaving = false;
  bool _foreground = true;
  int _permissionGeneration = 0;
  CameraPermissionState _cameraPermission = CameraPermissionState.unavailable;
  CameraDetectionState _lastCameraState = CameraDetectionState.stopped;
  bool get _recipientRoute => widget.recipientAuthorization != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _demoConditions = widget.demoPreview && kDebugMode
        ? DemoViewingConditions()
        : null;
    _ownsController = widget.viewingController == null;
    _controller =
        widget.viewingController ??
        ViewingStateController(
          restrictions: widget.restrictions,
          biometricAuthenticator: widget.biometricAuthenticator,
          conditions:
              _demoConditions ??
              widget.conditionProvider ??
              UnverifiedViewingConditions(),
          protection:
              widget.captureProtection ?? ScreenCaptureProtection.instance,
          demoPreview: widget.demoPreview && kDebugMode,
        );
    _controller.addListener(_stateChanged);
    _camera =
        (widget.cameraDetection ?? CameraDetectionService.instance)
            .createSession()
          ..addListener(_cameraChanged);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (!_foreground) {
      _controller.suspend();
    } else if (_ownsController) {
      unawaited(_controller.revalidate());
    }
    _maybeStartCamera();
    unawaited(_refreshCameraPermission());
    if (_controller.securityViolation) {
      // A shared session may have ended between preflight and route creation.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _stateChanged();
      });
    }
  }

  void _maybeStartCamera() {
    if (!_leaving &&
        mounted &&
        _controller.state == ViewingState.allowed &&
        _controller.biometrics.approved &&
        _camera.state == CameraDetectionState.stopped) {
      unawaited(_camera.start());
    }
  }

  AccessStatusKind? get _cameraNotice => switch (_cameraPermission) {
    CameraPermissionState.permanentlyDenied => AccessStatusKind.cameraBlocked,
    CameraPermissionState.denied => AccessStatusKind.cameraDenied,
    _ when _camera.state == CameraDetectionState.unavailable =>
      _camera.errorCode == 'permission_denied' &&
              _cameraPermission != CameraPermissionState.granted
          ? AccessStatusKind.cameraDenied
          : AccessStatusKind.cameraUnavailable,
    _ => null,
  };

  Future<void> _refreshCameraPermission() async {
    if (!_foreground || _leaving || _controller.sessionEnded) return;
    final generation = ++_permissionGeneration;
    final permission = await _camera.readPermission();
    if (!mounted ||
        !_foreground ||
        _leaving ||
        _controller.sessionEnded ||
        generation != _permissionGeneration) {
      return;
    }
    if (_cameraPermission != permission) {
      setState(() => _cameraPermission = permission);
    }
    widget.onCameraStatus?.call(_cameraNotice);
  }

  void _cameraChanged() {
    if (!mounted || _leaving) return;
    if (_camera.state == CameraDetectionState.phoneDetected) {
      _controller.endForSecurityViolation(
        reason: ViewingIssueKind.phoneDetected,
      );
    } else if (_camera.state == CameraDetectionState.multiplePeople) {
      _controller.cameraConditionChanged(ViewingIssueKind.multiplePeople);
    } else if (_camera.state == CameraDetectionState.viewerMissing) {
      _controller.cameraConditionChanged(ViewingIssueKind.viewerMissing);
    } else {
      // Stopped/unavailable runs have their own render gate. Discard the old
      // person observation so a fresh run can be checked after navigation.
      _controller.cameraConditionChanged(null);
    }
    if (_foreground && !_controller.sessionEnded) {
      if (_camera.state == CameraDetectionState.monitoring &&
          _lastCameraState != CameraDetectionState.monitoring) {
        ++_permissionGeneration;
        _cameraPermission = CameraPermissionState.granted;
        widget.onCameraStatus?.call(null);
      } else if (_camera.state == CameraDetectionState.unavailable) {
        widget.onCameraStatus?.call(_cameraNotice);
        unawaited(_refreshCameraPermission());
      }
    }
    // Every security transition still updates the route immediately. Clear
    // telemetry in an unchanged state only needs the diagnostics listener below.
    if (_lastCameraState != _camera.state) {
      _lastCameraState = _camera.state;
      setState(() {});
    }
  }

  void _stateChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.sessionEnded) {
      if (!_cleanupScheduled) {
        _cleanupScheduled = true;
        unawaited(_camera.stop());
        unawaited(_releaseCaptureAfterLockFrame());
      }
    } else {
      _maybeStartCamera();
    }
    if (_controller.securityViolation && !_exitScheduled && !_leaving) {
      _exitScheduled = true;
      unawaited(_exitAfterContentIsHidden());
    }
  }

  Future<void> _releaseCaptureAfterLockFrame() async {
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) _controller.releaseEndedCapture();
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
    if (kDebugMode) {
      debugPrintSynchronously(
        '[ApertureViewerLifecycle] timestamp=${DateTime.now().toUtc().toIso8601String()} '
        'controller_id=${identityHashCode(_controller)} lifecycle=${state.name} '
        'camera=${_camera.state.name} viewer=${_controller.state.name} '
        'reason=${_controller.violationReason?.name ?? "none"}',
      );
    }
    if (_leaving) return;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(_refreshCameraPermission());
      unawaited(_controller.resume());
      _maybeStartCamera();
    } else {
      ++_permissionGeneration;
      _controller.suspend(backgrounded: state != AppLifecycleState.inactive);
      unawaited(_camera.stop());
    }
  }

  @override
  void dispose() {
    if (kDebugMode) {
      debugPrintSynchronously(
        '[ApertureViewerLifecycle] timestamp=${DateTime.now().toUtc().toIso8601String()} '
        'controller_id=${identityHashCode(_controller)} action=dispose '
        'camera=${_camera.state.name} viewer=${_controller.state.name} '
        'reason=${_controller.violationReason?.name ?? "none"}',
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_stateChanged);
    if (!_leaving) _controller.revokeIdentity();
    _camera.removeListener(_cameraChanged);
    _camera.dispose();
    if (_ownsController) {
      _controller.dispose();
    } else {
      _controller.releaseIdleCapture();
    }
    _demoConditions?.dispose();
    super.dispose();
  }

  Widget _viewingArea() {
    if (!_leaving &&
        _controller.state == ViewingState.allowed &&
        _controller.biometrics.approved &&
        _camera.state == CameraDetectionState.monitoring) {
      return _ProtectedRenderPlaceholder(recipientRoute: _recipientRoute);
    }
    if (!_leaving && _controller.state == ViewingState.allowed) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _recipientRoute
              ? 'Camera protection is not confirmed for this session.'
              : 'Protected content is hidden until camera protection is confirmed.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ViewingStatusPanel(
      controller: _controller,
      combinedServerChecks: _recipientRoute,
      onRecheck: () => unawaited(_controller.revalidate()),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) {
        _leaving = true;
        _controller.revokeIdentity();
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
          _recipientRoute ? 'Security checks' : widget.contentTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            if (_recipientRoute) ...[
              const ProtectedDisplayNotice(),
              const SizedBox(height: 12),
              widget.recipientAuthorization!,
              const SizedBox(height: 16),
            ],
            // No transition retains the outgoing protected subtree or semantics.
            BiometricStatusPanel(controller: _controller),
            const SizedBox(height: 12),
            _viewingArea(),
            const SizedBox(height: 12),
            _cameraStatus(),
            const SizedBox(height: 16),
            if (!_recipientRoute &&
                _controller.state == ViewingState.allowed &&
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
            if (!_recipientRoute)
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
            if (kDebugMode && widget.demoPreview && !_controller.sessionEnded)
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

  Widget _cameraStatus() => ListenableBuilder(
    listenable: Listenable.merge([_camera, SecuritySettings.instance]),
    builder: (context, _) => _cameraStatusContent(),
  );

  Widget _cameraStatusContent() {
    if (_controller.sessionEnded) {
      return const Text(
        'Camera monitoring ended. This session cannot resume.',
        textAlign: TextAlign.center,
      );
    }
    final state = _camera.state;
    final latest = _camera.latest;
    final notice = _cameraNotice;
    final title = switch (notice) {
      AccessStatusKind.cameraDenied => 'Camera permission denied',
      AccessStatusKind.cameraBlocked => 'Camera permission blocked',
      AccessStatusKind.cameraUnavailable => 'Camera protection unavailable',
      _ => switch (state) {
        CameraDetectionState.stopped => 'Camera monitoring paused',
        CameraDetectionState.checking => 'Checking camera protection',
        CameraDetectionState.monitoring => 'Camera protection active',
        CameraDetectionState.phoneDetected => 'Phone detected — content hidden',
        CameraDetectionState.multiplePeople =>
          'Multiple people detected — content hidden',
        CameraDetectionState.viewerMissing =>
          'Required viewer missing — content hidden',
        CameraDetectionState.unavailable => 'Camera protection unavailable',
      },
    };
    return Column(
      children: [
        if (notice == null)
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
        if (latest != null &&
            state == CameraDetectionState.monitoring &&
            SecuritySettings.instance.showWarningDetails)
          Text(
            'People: ${latest.personCount} · Phone confidence: ${latest.phoneConfidence.toStringAsFixed(2)} · Inference: ${latest.latencyMs.toStringAsFixed(1)} ms',
            textAlign: TextAlign.center,
          ),
        if (notice != null) ...[
          SecurityNotice(
            title: title,
            message: switch (notice) {
              AccessStatusKind.cameraBlocked => 'Allow Camera for Aperture in system settings and check any device restrictions. Return and recheck viewing conditions.',
              AccessStatusKind.cameraDenied => 'Retry the camera check or allow Camera for Aperture in system settings. Content stays hidden.',
              _ => 'Camera checks failed. Make sure the camera is available, then retry. Content stays hidden.',
            },
            icon: Icons.videocam_off_outlined,
            details:
                'Camera status: ${_camera.errorCode ?? "unavailable"}. Retrying never overrides authorization, capture protection, or an ended session.',
          ),
          if (notice != AccessStatusKind.cameraBlocked)
            TextButton(
              onPressed: () async {
                await _controller.revalidate();
                if (mounted &&
                    !_leaving &&
                    _controller.state == ViewingState.allowed &&
                    _controller.biometrics.approved) {
                  unawaited(_camera.start());
                }
              },
              child: const Text('Retry camera protection'),
            ),
        ],
      ],
    );
  }
}

class _ProtectedRenderPlaceholder extends StatelessWidget {
  final bool recipientRoute;
  const _ProtectedRenderPlaceholder({required this.recipientRoute});
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('protected-render-placeholder'),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.border),
    ),
    child: Column(
      children: [
        const ExcludeSemantics(
          child: Icon(
            Icons.insert_drive_file_outlined,
            size: 48,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          recipientRoute ? 'No content displayed' : 'Protected content viewer',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        if (!recipientRoute) ...[
          const SizedBox(height: 12),
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
      ],
    ),
  );
}
