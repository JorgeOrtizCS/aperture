import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/models/api_models.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_session.dart';
import 'package:aperture/services/api_viewing_conditions.dart';
import 'package:aperture/services/biometric_verification.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/share_file_selection.dart';
import 'package:aperture/services/share_upload_draft.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:aperture/widgets/recipient_png_renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'temporary_png_demo_backend.dart';
import 'temporary_png_demo_fixture.dart';
import 'temporary_png_demo_transport.dart';

void main() {
  const enabled = bool.fromEnvironment('APERTURE_SYNTHETIC_PNG_DEMO');
  const url = String.fromEnvironment('APERTURE_SYNTHETIC_PNG_LOOPBACK');
  if (!kDebugMode || !enabled) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Synthetic PNG demo is disabled.')),
        ),
      ),
    );
    return;
  }
  try {
    runApp(
      MaterialApp(
        home: TemporaryPngDemo(
          backend: url.isEmpty ? PngDemoFixtureBackend() : PngDemoLoopback(url),
          offline: url.isEmpty,
        ),
      ),
    );
  } on ApiException {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Use a literal HTTP loopback test API.')),
        ),
      ),
    );
  }
}

const _policy = ContentRestrictions(
  allowDownload: false,
  allowResharing: false,
  restrictScreenshots: false,
  accessDuration: AccessDuration.twelveHours,
  viewLimit: 2,
);

String _title() {
  final random = Random.secure();
  final nonce = List.generate(
    12,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'Aperture synthetic PNG - $nonce';
}

class TemporaryPngDemo extends StatefulWidget {
  const TemporaryPngDemo({
    super.key,
    required this.backend,
    this.offline = true,
    this.picker = const NativeShareFilePicker(),
    this.captureProtection,
    this.biometricAuthenticator,
    this.timeout = const Duration(seconds: 4),
    this.pollInterval = const Duration(seconds: 3),
  });
  final ApiTransport backend;
  final bool offline;
  final ShareFilePicker picker;
  final ScreenCaptureProtection? captureProtection;
  final BiometricAuthenticator? biometricAuthenticator;
  final Duration timeout;
  final Duration pollInterval;

  @override
  State<TemporaryPngDemo> createState() => _TemporaryPngDemoState();
}

class _TemporaryPngDemoState extends State<TemporaryPngDemo>
    with WidgetsBindingObserver {
  final _passwords = (TextEditingController(), TextEditingController());
  final _image = ValueNotifier<RecipientPngRequest?>(null);
  late final _transport = PngDemoTransport(widget.backend);
  // Both account sessions share the fixture isolation transport. The hosting
  // widget owns it until their asynchronous retirement completes.
  late final _sender = ApiSession(
    ApiService.uploadFixture(
      transport: _transport.accountTransport(),
      timeout: widget.timeout,
    ),
  );
  late final _recipient = ApiSession(
    ApiService.fixture(transport: _transport.accountTransport()),
    deviceKey: pngDemoDevice,
  );

  ApiViewingConditions? _conditions;
  ViewingStateController? _viewer;
  ApiRequestCancellation? _upload;
  PngDraftPreview? _draft;
  int? _pick;
  var _sequence = 0;
  var _reading = false;
  var _busy = false;
  var _signingOut = false;
  var _retiringView = false;
  var _disposed = false;
  var _viewOffered = false;
  var _notice = '';
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  Completer<void>? _foregroundWait;

  bool get _foreground => _lifecycle == AppLifecycleState.resumed;
  bool get _signedIn =>
      _sender.authenticated &&
      _recipient.authenticated &&
      _sender.user?.username == pngDemoSender &&
      _recipient.user?.username == pngDemoRecipient;

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) return;
    _lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _sender.addListener(_accountChanged);
    _recipient.addListener(_accountChanged);
  }

  void _rebuild() {
    if (mounted && !_disposed) setState(() {});
  }

  void _accountChanged() {
    if (!_signedIn) {
      _clearDraft();
      _stopViewing();
    }
    _rebuild();
  }

  Future<void> _action(Future<void> Function() run) async {
    if (_busy || !_foreground) return;
    _busy = true;
    _notice = '';
    _rebuild();
    try {
      await run();
    } on ApiException catch (error) {
      _notice = switch (error.kind) {
        ApiFailure.cancelled when _transport.submitted =>
          'The upload may have reached the API. No upload will be retried.',
        ApiFailure.timeout || ApiFailure.uploadUnconfirmed =>
          'The request outcome is unknown. No upload will be retried.',
        _ => 'The test API did not confirm the request (${error.kind.name}).',
      };
    } on PngFileException {
      _notice = 'Select the original synthetic Aperture-Demo.png.';
    } catch (_) {
      _notice = 'The test step could not be completed.';
    } finally {
      _busy = false;
      _rebuild();
    }
  }

  Future<void> _signIn() async {
    final (senderPassword, recipientPassword) = widget.offline
        ? ('offline-fixture', 'offline-fixture')
        : (_passwords.$1.text, _passwords.$2.text);
    _passwords.$1.clear();
    _passwords.$2.clear();
    try {
      await _sender.login(pngDemoSender, senderPassword);
      if (_disposed || !_foreground) throw const ApiException(ApiFailure.stale);
      await _recipient.login(pngDemoRecipient, recipientPassword);
      if (_disposed ||
          !_foreground ||
          !_signedIn ||
          _sender.user!.id == _recipient.user!.id) {
        throw const ApiException(ApiFailure.stale);
      }
      await _refresh();
    } catch (_) {
      if (!_disposed) await _signOut();
      rethrow;
    }
  }

  Future<void> _refresh() async {
    try {
      await Future.wait([_sender.refresh(), _recipient.refresh()]);
    } catch (_) {
      _stopViewing();
      rethrow;
    }
  }

  void _clearDraft() {
    _upload?.cancel();
    _draft?.dispose();
    _draft = null;
    final pick = _pick;
    _pick = null;
    _reading = false;
    if (pick != null) {
      unawaited(widget.picker.discard(pick).catchError((Object _) {}));
    }
    _foregroundWait?.complete();
    _foregroundWait = null;
  }

  Future<void> _select() async {
    _clearDraft();
    final id = _pick = ++_sequence;
    bool current() => !_disposed && _signedIn && _pick == id;
    try {
      if (!await widget.picker.pick(id) || !current()) return;
      if (!_foreground) await (_foregroundWait ??= Completer<void>()).future;
      if (!current() || !_foreground) return;
      _reading = true;
      final file = await widget.picker
          .read(id, PngFileValidator.backendMaxBytes)
          .then((file) {
            if (!current() || !_foreground) file.clear();
            return file;
          })
          .timeout(const Duration(seconds: 15));
      if (!current() || !_foreground) return;
      if (file.bytes.length != 986 ||
          base64Encode(file.bytes) != classroomSyntheticPng) {
        file.clear();
        throw const PngFileException(PngFileProblem.unsupported);
      }
      final draft = await PngFileValidator.validate(
        file,
        maxBytes: PngFileValidator.backendMaxBytes,
        stageForUpload: true,
      );
      if (!current() || !_foreground) {
        draft.dispose();
        return;
      }
      _draft = draft;
    } finally {
      if (_pick == id) {
        _pick = null;
        _reading = false;
        await widget.picker.discard(id).catchError((Object _) {});
      }
    }
  }

  Future<void> _submit() async {
    if (!_signedIn || _transport.submitted) return;
    final request = buildShareUploadDraft(
      title: _title(),
      recipient: pngDemoRecipient,
      sender: pngDemoSender,
      restrictions: _policy,
      now: _sender.now(),
    );
    final bytes = _draft?.takeUploadBytes();
    _clearDraft();
    final cancellation = _upload = ApiRequestCancellation();
    try {
      final id = await _sender.createContent(
        request,
        bytes,
        maxBytes: PngFileValidator.backendMaxBytes,
        cancellation: cancellation,
      );
      if (_disposed || !_foreground || !_signedIn || cancellation.isCancelled) {
        return;
      }
      await _refresh();
      if (!_sender.items.any((item) => item.id == id && item.mine) ||
          !_recipient.items.any((item) => item.id == id && !item.mine)) {
        throw const ApiException(ApiFailure.malformed);
      }
      _notice = 'Both accounts confirmed the synthetic PNG share.';
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      _upload = null;
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    _signingOut = true;
    _clearDraft();
    _stopViewing();
    try {
      await Future.wait([_sender.logout(), _recipient.logout()]);
      if (_sender.logoutWarning != null || _recipient.logoutWarning != null) {
        _notice = 'Signed out locally. The API did not confirm both logouts.';
      }
    } finally {
      _signingOut = false;
    }
  }

  void _stopViewing() {
    final viewer = _viewer;
    if (viewer == null) return;
    final conditions = _conditions!;
    _image.value = null;
    _viewer = null;
    _conditions = null;
    _viewOffered = false;
    viewer.removeListener(_viewChanged);
    viewer.suspend();
    conditions.endSession();
    _retiringView = true;
    // Paint the withdrawn frame before releasing native capture protection.
    unawaited(
      WidgetsBinding.instance.endOfFrame.then((_) {
        viewer.dispose();
        conditions.dispose();
        _retiringView = false;
        _rebuild();
      }),
    );
  }

  void _viewChanged() {
    final viewer = _viewer;
    if (viewer == null) return;
    if (viewer.sessionEnded ||
        (_viewOffered && viewer.state != ViewingState.allowed)) {
      _stopViewing();
      _notice = 'Viewing ended. The image has been withdrawn.';
    } else if (!_viewOffered &&
        _signedIn &&
        _foreground &&
        viewer.state == ViewingState.allowed &&
        _transport.hasAuthorizedSample) {
      _viewOffered = true;
      // Materialize only the byte-for-byte known synthetic image, after the
      // transport has matched the authorized grant payload to that sample.
      _image.value = RecipientPngRequest(
        () async => RecipientPngPayload(
          contentType: 'image/png',
          bytes: base64Decode(classroomSyntheticPng),
        ),
      );
    }
    _rebuild();
  }

  Future<void> _view(int id) async {
    if (_viewer != null || _retiringView || !_signedIn) return;
    final senderEpoch = _sender.identityVersion;
    final recipientEpoch = _recipient.identityVersion;
    await _refresh();
    if (_disposed ||
        !_foreground ||
        !_signedIn ||
        senderEpoch != _sender.identityVersion ||
        recipientEpoch != _recipient.identityVersion ||
        !_sender.items.any(
          (item) =>
              item.id == id &&
              item.mine &&
              item.status == 'Active' &&
              item.policyStatus == 'Active',
        ) ||
        !_recipient.items.any(
          (item) =>
              item.id == id &&
              !item.mine &&
              item.status == 'Active' &&
              item.policyStatus == 'Active',
        )) {
      return;
    }

    late final ViewingStateController viewer;
    final conditions = ApiViewingConditions(
      _recipient,
      id,
      identityReady: () => viewer.biometrics.approved,
      pollInterval: widget.pollInterval,
    );
    viewer = ViewingStateController(
      restrictions: _policy,
      conditions: conditions,
      protection: widget.captureProtection ?? ScreenCaptureProtection.instance,
      biometricAuthenticator: widget.biometricAuthenticator,
    )..addListener(_viewChanged);
    _viewer = viewer;
    _conditions = conditions;
    await viewer.verifyIdentity();
  }

  Future<void> _change(ApiContent row, {String? policy}) async {
    _stopViewing();
    if (policy == null) {
      await _sender.revoke(row.id);
    } else {
      await _sender.setPolicy(row.id, policy);
    }
    await _refresh();
  }

  void _cancelAndSignOut() {
    if (_foreground) unawaited(_signOut().whenComplete(_rebuild));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (_foreground) {
      _foregroundWait?.complete();
      _foregroundWait = null;
      final viewer = _viewer;
      if (viewer != null) {
        // Native authentication can finish during the prompt's inactivity.
        // Revalidate after resume also when this was the first verification.
        unawaited(() async {
          await viewer.resume(recheck: false);
          if (identical(_viewer, viewer) && viewer.biometrics.approved) {
            await viewer.revalidate(verifyIdentity: false);
          }
        }());
      }
    } else {
      if (_draft != null ||
          _reading ||
          _upload != null ||
          state == AppLifecycleState.detached) {
        _clearDraft();
      }
      // Transient biometric prompt inactivity may precede native approval.
      // A session that has delivered pixels is terminal on foreground loss.
      if (_viewOffered || state != AppLifecycleState.inactive) {
        _stopViewing();
      } else {
        _viewer?.suspend(backgrounded: false);
      }
    }
    _rebuild();
  }

  @override
  void dispose() {
    _disposed = true;
    if (kDebugMode) {
      WidgetsBinding.instance.removeObserver(this);
      _sender.removeListener(_accountChanged);
      _recipient.removeListener(_accountChanged);
      _clearDraft();
      // The entire harness is leaving, so remove the renderer before the
      // next frame and let ApiSession retire opens with the original token.
      final viewer = _viewer;
      viewer?.removeListener(_viewChanged);
      viewer?.dispose();
      _conditions?.dispose();
      unawaited(
        Future.wait([_sender.logout(), _recipient.logout()]).whenComplete(() {
          _sender.dispose();
          _recipient.dispose();
          _transport.close();
        }),
      );
    }
    _passwords.$1.dispose();
    _passwords.$2.dispose();
    _image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final owner = _sender.items.firstOrNull;
    final received = _recipient.items.firstOrNull;
    final ready = !_busy && !_signingOut && _foreground;
    final canView =
        owner != null &&
        received?.id == owner.id &&
        received?.status == 'Active' &&
        received?.policyStatus == 'Active' &&
        owner.status == 'Active' &&
        owner.policyStatus == 'Active';
    final viewer = _viewer;
    final warning = widget.offline
        ? 'Offline fixture API. Shares and sessions exist only in memory.'
        : 'Loopback test API. PNG data is sent and stored without file encryption.';
    if (_image.value != null && owner != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Unencrypted PNG test harness')),
        body: SafeArea(
          child: Column(
            children: [
              Text(warning, textAlign: TextAlign.center),
              Expanded(child: RecipientPngRenderer(input: _image)),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: _stopViewingAndRefresh,
                    child: const Text('End viewing'),
                  ),
                  if (owner.status == 'Active') ...[
                    TextButton(
                      onPressed: ready
                          ? () =>
                                _action(() => _change(owner, policy: 'Paused'))
                          : null,
                      child: const Text('Pause test share'),
                    ),
                    TextButton(
                      onPressed: ready
                          ? () => _action(() => _change(owner))
                          : null,
                      child: const Text('Revoke test share'),
                    ),
                  ],
                  TextButton(
                    onPressed: ready ? () => _action(_refresh) : null,
                    child: const Text('Refresh test listings'),
                  ),
                  TextButton(
                    onPressed: _cancelAndSignOut,
                    child: const Text('Sign out both accounts'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Unencrypted PNG test harness')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Insecure test · Synthetic PNG only',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(warning),
            if (!_signedIn) ...[
              if (!widget.offline) ...[
                for (final (name, controller) in [
                  (pngDemoSender, _passwords.$1),
                  (pngDemoRecipient, _passwords.$2),
                ])
                  TextField(
                    controller: controller,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: '$name disposable password',
                    ),
                  ),
              ],
              FilledButton(
                onPressed: ready ? () => _action(_signIn) : null,
                child: const Text('Sign in as fixture sender and recipient'),
              ),
            ] else ...[
              const Text(
                'Sender: $pngDemoSender · Recipient: $pngDemoRecipient',
              ),
              if (!_transport.submitted) ...[
                OutlinedButton(
                  onPressed: ready ? () => _action(_select) : null,
                  child: const Text('Select Aperture-Demo.png'),
                ),
                if (_draft case final draft?)
                  Text(
                    'Synthetic sample verified · ${draft.width} × ${draft.height}',
                  ),
                FilledButton(
                  onPressed: ready && _draft != null
                      ? () => _action(_submit)
                      : null,
                  child: const Text('Create unencrypted synthetic share'),
                ),
              ],
              if (owner != null) ...[
                Text(
                  'Sender access: ${owner.status} · Policy: ${owner.policyStatus}',
                ),
                if (owner.status == 'Active') ...[
                  OutlinedButton(
                    onPressed: ready
                        ? () => _action(
                            () => _change(
                              owner,
                              policy: owner.policyStatus == 'Paused'
                                  ? 'Active'
                                  : 'Paused',
                            ),
                          )
                        : null,
                    child: Text(
                      owner.policyStatus == 'Paused'
                          ? 'Resume test share'
                          : 'Pause test share',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: ready
                        ? () => _action(() => _change(owner))
                        : null,
                    child: const Text('Revoke test share'),
                  ),
                ],
              ],
              if (received != null)
                Text(
                  'Recipient access: ${received.status} · Policy: ${received.policyStatus}',
                ),
              if (canView && viewer == null)
                FilledButton(
                  onPressed: ready && !_retiringView
                      ? () => _action(() => _view(owner.id))
                      : null,
                  child: const Text('Verify identity and open synthetic PNG'),
                ),
              if (viewer != null) ...[
                Text(
                  viewer.state == ViewingState.allowed
                      ? 'Authorized synthetic image'
                      : 'Image hidden · ${viewer.biometrics.state.name} / ${viewer.state.name}',
                ),
                OutlinedButton(
                  onPressed: _stopViewingAndRefresh,
                  child: const Text('End viewing'),
                ),
              ],
              TextButton(
                onPressed: ready ? () => _action(_refresh) : null,
                child: const Text('Refresh test listings'),
              ),
              TextButton(
                onPressed: _cancelAndSignOut,
                child: const Text('Sign out both accounts'),
              ),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_notice.isNotEmpty) Text(_notice),
          ],
        ),
      ),
    );
  }

  void _stopViewingAndRefresh() {
    _stopViewing();
    _rebuild();
  }
}
