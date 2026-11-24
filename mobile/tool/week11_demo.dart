import 'dart:async';
import 'dart:convert';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/main.dart';
import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_session.dart';
import 'package:aperture/services/camera_detection.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/material.dart';

void main() => runApp(const Week11DemoApp());

const demoSender = 'fixture-sender';
const demoRecipient = 'fixture-recipient';
const demoOwnerItem = 'Owner-managed sample';
const demoLocationItem = 'Location-restricted sample';

/// A separate entry point for the presentation. The application and its
/// native services are reused, while sample API responses stay in this file.
class Week11DemoApp extends StatefulWidget {
  const Week11DemoApp({super.key});

  @override
  State<Week11DemoApp> createState() => _Week11DemoAppState();
}

class _Week11DemoAppState extends State<Week11DemoApp> {
  late final _account = ApiSession(
    ApiService.fixture(
      transport: Week11DemoTransport(),
      canOpenContentRoutes: true,
    ),
    deviceKey: '11111111-1111-4111-8111-111111111111',
  );

  @override
  void dispose() {
    _account.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.theme,
    debugShowCheckedModeBanner: false,
    home: Builder(builder: _buildHome),
  );

  Widget _buildHome(BuildContext context) {
    final compactBanner =
        MediaQuery.orientationOf(context) == Orientation.landscape &&
        MediaQuery.viewInsetsOf(context).bottom > 0;
    return Material(
      child: SafeArea(
        bottom: false,
        child: Flex(
          direction: compactBanner ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: AppTheme.primarySoft,
              child: Padding(
                padding: compactBanner
                    ? const EdgeInsets.all(12)
                    : const EdgeInsets.only(left: 12),
                child: compactBanner
                    ? const Text(
                        'Offline\ndemo',
                        semanticsLabel: 'Offline demo',
                      )
                    : Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Offline demo · Sample accounts and data',
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => const _SessionDemonstration(),
                              ),
                            ),
                            child: const Text('Session demo'),
                          ),
                        ],
                      ),
              ),
            ),
            // The nested navigator's modal barriers must not hide the
            // persistent demo controls from accessibility services.
            Expanded(
              child: Semantics(
                container: true,
                child: ApiApplication(session: _account),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionDemonstration extends StatefulWidget {
  const _SessionDemonstration();

  @override
  State<_SessionDemonstration> createState() => _SessionDemonstrationState();
}

class _SessionDemonstrationState extends State<_SessionDemonstration> {
  final _controller = ViewingStateController(
    restrictions: ContentRestrictions.demoDefaults,
    conditions: UnverifiedViewingConditions(),
    protection: ScreenCaptureProtection.instance,
  );
  late final _cameraPermission = CameraDetectionService.instance
      .readPermission();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Simulated session · Check the locked preflight, then simulate ending it.',
            ),
          ),
          FutureBuilder(
            future: _cameraPermission,
            builder: (context, snapshot) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(switch (snapshot.data) {
                CameraPermissionState.granted => 'Camera permission available',
                CameraPermissionState.denied ||
                CameraPermissionState.permanentlyDenied =>
                  'Camera permission denied',
                CameraPermissionState.notDetermined =>
                  'Camera permission has not been requested',
                _ => 'Camera permission status unavailable',
              }, textAlign: TextAlign.center),
            ),
          ),
          const Text('Camera monitoring starts only after access checks pass.'),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => TextButton(
              onPressed: !_controller.hasStarted || _controller.sessionEnded
                  ? null
                  : _controller.endForSecurityViolation,
              child: const Text('Simulate session end'),
            ),
          ),
          Expanded(
            child: SecureViewerScreen(
              contentTitle: 'Locked sample session',
              ownerName: 'Offline demo',
              viewingController: _controller,
              showPolicySummary: false,
              allowDemoPreview: false,
            ),
          ),
        ],
      ),
    ),
  );
}

/// In-process sample API, with no network path, upload endpoint or grant.
class Week11DemoTransport implements ApiTransport {
  static const _ownerId = 1;
  static const _policyId = 2;
  final _accounts = <String, String>{};
  int _sequence = 0;
  bool _revoked = false;
  String _policy = 'Active';

  int _userId(String name) => name == demoSender ? 1 : 2;

  ApiReply _reply(Object payload, {int status = 200}) =>
      ApiReply(status, jsonEncode(payload));

  ApiReply _denied([int status = 403]) =>
      _reply({'success': false}, status: status);

  Map<String, Object> _ownerItem({required bool mine}) => {
    'Id': _ownerId,
    'Title': demoOwnerItem,
    'Owner': demoSender,
    'Mine': mine,
    if (mine) 'Recipient': demoRecipient,
    'CreatedAt': '2026-11-01T12:00:00Z',
    'Status': _revoked ? 'Revoked' : 'Active',
    'PolicyStatus': _policy,
  };

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    if (uri.hasAuthority || uri.hasScheme) return _denied();
    if (method == 'POST' && uri.path == '/api/auth/login') {
      final data = jsonDecode(body ?? '{}') as Map<String, dynamic>;
      final username = data['Username'];
      final password = data['Password'];
      if ((username != demoSender && username != demoRecipient) ||
          password is! String ||
          password.trim().isEmpty) {
        return _denied(401);
      }
      final name = username as String;
      final token = 'demo-account-${++_sequence}';
      _accounts[token] = name;
      return _reply({
        'Success': true,
        'Token': token,
        'ExpiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        'User': {'Id': _userId(name), 'Username': name},
      });
    }

    final bearer = headers['Authorization'];
    final token = bearer != null && bearer.startsWith('Bearer ')
        ? bearer.substring(7)
        : null;
    final name = _accounts[token];
    if (name == null) return _denied(401);

    switch ((method, uri.path)) {
      case ('POST', '/api/auth/logout'):
        _accounts.remove(token);
        return _reply({'success': true});
      case ('GET', '/api/user/me'):
        return _reply({
          'success': true,
          'user': {'id': _userId(name), 'username': name},
        });
      case ('GET', '/api/content'):
        return _reply([
          _ownerItem(mine: name == demoSender),
          if (name == demoRecipient)
            {
              'Id': _policyId,
              'Title': demoLocationItem,
              'Owner': 'fixture-policy-owner',
              'Mine': false,
              'CreatedAt': '2026-11-01T12:00:00Z',
              'Status': 'Active',
              'PolicyStatus': 'Active',
              'Latitude': 26.37,
              'Longitude': -80.1,
              'RadiusMeters': 500,
              'RequireTrustedDevice': true,
            },
        ]);
      case ('POST', '/api/content/1/policy')
          when name == demoSender && !_revoked:
        final status = (jsonDecode(body ?? '{}') as Map)['Status'];
        if (status != 'Paused' && status != 'Active') return _denied();
        _policy = status as String;
        return _reply({'status': _policy});
      case ('POST', '/api/content/1/revoke') when name == demoSender:
        _revoked = true;
        return _reply({'success': true});
      default:
        return _denied();
    }
  }

  @override
  void close() => _accounts.clear();
}
