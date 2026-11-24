import 'dart:async';
import 'dart:math';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/models/api_models.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_session.dart';
import 'package:aperture/services/api_viewing_conditions.dart';
import 'package:aperture/services/biometric_verification.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:aperture/widgets/recipient_png_renderer.dart';
import 'package:flutter/material.dart';

import 'hosted_png_viewer_transport.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('APERTURE_API_BASE_URL');
  try {
    runApp(
      MaterialApp(
        home: HostedPngViewer(transport: HostedPngTransport.live(url)),
      ),
    );
  } on ApiException {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Classroom PNG viewing is disabled.')),
        ),
      ),
    );
  }
}

String _newDeviceKey() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class HostedPngViewer extends StatefulWidget {
  const HostedPngViewer({
    super.key,
    required this.transport,
    this.biometricAuthenticator,
    this.captureProtection,
    this.pollInterval = const Duration(seconds: 3),
  });

  final HostedPngTransport transport;
  final BiometricAuthenticator? biometricAuthenticator;
  final ScreenCaptureProtection? captureProtection;
  final Duration pollInterval;

  @override
  State<HostedPngViewer> createState() => _HostedPngViewerState();
}

class _HostedPngViewerState extends State<HostedPngViewer>
    with WidgetsBindingObserver {
  // The capture gate and the transport each have their own shorter bound.
  // Leave time for ApiSession to observe and retire a known open response.
  static const _apiDeadline = Duration(seconds: 30);
  static const _captureDeadline = Duration(seconds: 10);
  final _password = TextEditingController();
  final _image = ValueNotifier<RecipientPngRequest?>(null);
  late final ApiSession _account;
  ViewingStateController? _viewer;
  ApiViewingConditions? _conditions;
  Completer<void>? _captureWait;
  ModalRoute<dynamic>? _route;
  int? _viewIdentity;
  bool _foreground = false, _disposed = false, _busy = false, _retiring = false;
  String? _notice;

  bool get _onScreen =>
      !_disposed && _foreground && (_route?.isCurrent ?? true);
  bool get _matchesAccount => _account.user?.username == hostedPngRecipient;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    _foreground = binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
    _account = ApiSession(
      ApiService.fixture(transport: widget.transport, timeout: _apiDeadline),
      deviceKey: _newDeviceKey(),
    )..addListener(_accountChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (_route?.isCurrent == false) {
      // The renderer also watches the route. Stop the producer after this build.
      scheduleMicrotask(() {
        if (!_disposed && _route?.isCurrent == false) _stop();
      });
    }
  }

  void _rebuild() {
    if (!_disposed) setState(() {});
  }

  void _accountChanged() {
    if (_viewer != null &&
        (!_matchesAccount || _viewIdentity != _account.identityVersion)) {
      _stop();
    }
    _rebuild();
  }

  Future<void> _action(Future<void> Function() run) async {
    if (!_onScreen || _busy || _retiring) return;
    _busy = true;
    _notice = null;
    _rebuild();
    try {
      await run();
    } on ApiException catch (e) {
      _notice = e.message;
    } finally {
      _busy = false;
      _rebuild();
    }
  }

  Future<void> _login() async {
    final password = _password.text;
    _password.clear();
    await _account.login(hostedPngRecipient, password);
    if (!_disposed && _matchesAccount) await _account.refresh();
  }

  Future<bool> _captureReady(ViewingStateController viewer) async {
    if (!_onScreen || !identical(_viewer, viewer)) return false;
    if (viewer.captureState == CaptureProtectionState.checking) {
      final wait = Completer<void>();
      _captureWait = wait;
      await wait.future.timeout(_captureDeadline, onTimeout: () {});
    }
    return _eligible(viewer) &&
        viewer.captureState == CaptureProtectionState.ready;
  }

  bool _eligible(ViewingStateController viewer) =>
      _onScreen &&
      identical(_viewer, viewer) &&
      _matchesAccount &&
      _viewIdentity == _account.identityVersion &&
      viewer.biometrics.approved &&
      !viewer.sessionEnded;

  Future<void> _open() async {
    if (!_matchesAccount ||
        _viewer != null ||
        widget.transport.openDispatched) {
      return;
    }
    final identity = _account.identityVersion;
    await _account.refresh(isCurrent: () => _onScreen);
    if (!_onScreen ||
        !_matchesAccount ||
        _account.identityVersion != identity ||
        _account.items.singleOrNull?.id != widget.transport.contentId) {
      return;
    }

    late final ViewingStateController viewer;
    if (!widget.transport.begin(identity, () => _captureReady(viewer))) return;
    final conditions = ApiViewingConditions(
      _account,
      widget.transport.contentId,
      identityReady: () => _eligible(viewer),
      pollInterval: widget.pollInterval,
    );
    viewer = ViewingStateController(
      restrictions: ContentRestrictions(
        allowDownload: false,
        allowResharing: false,
        restrictScreenshots: false,
        accessDuration: AccessDuration.twelveHours,
        viewLimit: widget.transport.maxViews,
      ),
      conditions: conditions,
      protection: widget.captureProtection ?? ScreenCaptureProtection.instance,
      checkTimeout: const Duration(seconds: 32),
      biometricAuthenticator: widget.biometricAuthenticator,
    )..addListener(_viewChanged);
    _viewer = viewer;
    _conditions = conditions;
    _viewIdentity = identity;
    await viewer.verifyIdentity();
    _finishVerification(viewer);
  }

  void _finishVerification(ViewingStateController viewer) {
    if (!_onScreen || !identical(_viewer, viewer)) return;
    if (!viewer.biometrics.approved &&
        viewer.biometrics.state != BiometricState.verifying) {
      _stop('Identity could not be verified.');
    } else if (widget.transport.openDispatched &&
        viewer.state != ViewingState.allowed) {
      _stop('The viewing session could not be authorized.');
    }
  }

  void _viewChanged() {
    final viewer = _viewer;
    if (viewer == null) return;
    if (viewer.captureState != CaptureProtectionState.checking) {
      _releaseCaptureWait();
    }
    if (viewer.sessionEnded ||
        const {
          CaptureProtectionState.captureActive,
          CaptureProtectionState.unavailable,
        }.contains(viewer.captureState) ||
        (_image.value != null && viewer.state != ViewingState.allowed)) {
      _stop('Viewing ended. The image is hidden.');
      return;
    }
    final session = _conditions!.sessionId;
    if (_image.value == null &&
        session != null &&
        _eligible(viewer) &&
        viewer.state == ViewingState.allowed &&
        viewer.captureState == CaptureProtectionState.ready) {
      final identity = _viewIdentity!;
      _image.value = RecipientPngRequest(() async {
        if (!_eligible(viewer) ||
            viewer.state != ViewingState.allowed ||
            viewer.captureState != CaptureProtectionState.ready ||
            _conditions?.sessionId != session) {
          throw const ApiException(ApiFailure.stale);
        }
        return widget.transport.take(identity, session);
      });
    }
    _rebuild();
  }

  void _releaseCaptureWait() {
    _captureWait?.complete();
    _captureWait = null;
  }

  void _stop([String? notice]) {
    final viewer = _viewer;
    if (viewer == null) return;
    final conditions = _conditions!;
    _viewer = null;
    _conditions = null;
    _viewIdentity = null;
    _notice = notice ?? _notice;
    widget.transport.retire();
    _releaseCaptureWait();
    if (!_disposed) _image.value = null;
    viewer.removeListener(_viewChanged);
    viewer.suspend();
    conditions.endSession();
    _retiring = true;
    // Keep the native lease until Flutter paints the frame without the image.
    unawaited(
      WidgetsBinding.instance.endOfFrame.then((_) {
        viewer.dispose();
        conditions.dispose();
        _retiring = false;
        _rebuild();
      }),
    );
    _rebuild();
  }

  Future<void> _logout() async {
    _stop();
    await _account.logout();
    if (_account.logoutWarning != null) _notice = _account.logoutWarning;
    _rebuild();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    final viewer = _viewer;
    if (viewer != null) {
      if (_foreground) {
        unawaited(() async {
          await viewer.resume(recheck: false);
          if (_eligible(viewer) && !viewer.hasStarted) {
            await viewer.revalidate(verifyIdentity: false);
          }
          _finishVerification(viewer);
        }());
      } else if (state == AppLifecycleState.inactive && !viewer.hasStarted) {
        // Native authentication can briefly obscure the app.
        viewer.suspend(backgrounded: false);
      } else {
        _stop('Viewing ended when Aperture left the foreground.');
      }
    }
    _rebuild();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    _account.removeListener(_accountChanged);
    unawaited(_account.logout().whenComplete(_account.dispose));
    _password.dispose();
    _image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eligible =
        _account.items.singleOrNull?.id == widget.transport.contentId;
    if (_image.value != null) {
      return Scaffold(
        appBar: AppBar(title: const Text(hostedPngLabel)),
        body: SafeArea(
          child: Column(
            children: [
              const Text('Synthetic PNG only. Classroom HTTP is unencrypted.'),
              Expanded(child: RecipientPngRenderer(input: _image)),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        _stop('Viewing ended. The image is hidden.'),
                    child: const Text('End viewing'),
                  ),
                  TextButton(onPressed: _logout, child: const Text('Sign out')),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text(hostedPngLabel)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Synthetic PNG only. Classroom HTTP is unencrypted.'),
            if (!_matchesAccount) ...[
              TextField(
                controller: _password,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Disposable recipient password',
                ),
              ),
              FilledButton(
                onPressed: _busy ? null : () => _action(_login),
                child: const Text('Sign in as approved recipient'),
              ),
            ] else ...[
              if (eligible) Text(widget.transport.title),
              if (!eligible) const Text('The approved share is unavailable.'),
              if (eligible &&
                  _viewer == null &&
                  !widget.transport.openDispatched)
                FilledButton(
                  onPressed: _busy || _retiring ? null : () => _action(_open),
                  child: const Text('Verify identity and open PNG'),
                ),
              if (_viewer != null)
                OutlinedButton(
                  onPressed: () => _stop('Viewing ended. The image is hidden.'),
                  child: const Text('End viewing'),
                ),
              TextButton(onPressed: _logout, child: const Text('Sign out')),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_notice case final notice?) Text(notice),
          ],
        ),
      ),
    );
  }
}
