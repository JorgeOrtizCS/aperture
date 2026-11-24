import 'dart:convert';

import 'package:aperture/models/api_models.dart';
import 'package:aperture/services/api_service.dart';

import 'temporary_png_demo_transport.dart';

/// Implements the Web API wire contract in memory for the standalone demo.
class PngDemoFixtureBackend implements ApiTransport {
  final _tokens = <String, String>{};
  var _next = 0;
  var _views = 0;
  var _policy = 'Active';
  var _revoked = false;
  Map<String, dynamic>? _share;
  (int, String)? _session;

  ApiReply _json(Object value, [int status = 200]) =>
      ApiReply(status, jsonEncode(value));

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final input = body == null ? null : apiObject(jsonDecode(body));
    final path = uri.path;
    if ((method, path) == ('POST', '/api/auth/login')) {
      final user = input!['Username'];
      if (!{pngDemoSender, pngDemoRecipient}.contains(user) ||
          input['Password'] != 'offline-fixture') {
        return const ApiReply(401, '');
      }
      final token = 'memory-session-${++_next}';
      _tokens['Bearer $token'] = user as String;
      return _json({
        'Success': true,
        'User': {'Id': user == pngDemoSender ? 1 : 2, 'Username': user},
        'Token': token,
        'ExpiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      });
    }
    final token = headers['Authorization'];
    final user = _tokens[token];
    if (user == null) return const ApiReply(401, '');
    switch ((method, path)) {
      case ('GET', '/api/user/me'):
        return _json({
          'success': true,
          'user': {'id': user == pngDemoSender ? 1 : 2, 'username': user},
        });
      case ('POST', '/api/auth/logout'):
        _tokens.remove(token);
        if (_session?.$2 == token) _session = null;
        return _json({'success': true});
      case ('POST', '/api/content'):
        if (user != pngDemoSender || _share != null || input == null) {
          return const ApiReply(400, '');
        }
        _share = input;
        return _json({'id': 1});
      case ('GET', '/api/content'):
        final share = _share;
        final mine = user == pngDemoSender;
        return _json([
          if (share != null)
            {
              'Id': 1,
              'Title': share['Title'],
              'Owner': pngDemoSender,
              'Mine': mine,
              if (mine) 'Recipient': pngDemoRecipient,
              'CreatedAt': DateTime.now().toUtc().toIso8601String(),
              'ExpiresAt': share['ExpiresAt'],
              'MaxViews': share['MaxViews'],
              'ScreenshotRestriction': share['ScreenshotRestriction'],
              'RequireTrustedDevice': share['RequireTrustedDevice'],
              'Status': _revoked ? 'Revoked' : 'Active',
              'PolicyStatus': _policy,
            },
        ]);
    }
    final share = _share;
    if (share == null || method != 'POST') return const ApiReply(404, '');
    if (user == pngDemoSender && path == '/api/content/1/policy') {
      final status = input?['Status'];
      if (status != 'Active' && status != 'Paused') {
        return const ApiReply(400, '');
      }
      _policy = status as String;
      if (status == 'Paused') _session = null;
      return _json({'status': status});
    }
    if (user == pngDemoSender && path == '/api/content/1/revoke') {
      _revoked = true;
      _session = null;
      return _json({'success': true});
    }
    if (user != pngDemoRecipient) return const ApiReply(404, '');
    if (path == '/api/content/1/sessions') {
      if (_revoked) return const ApiReply(404, '');
      if (_policy != 'Active' ||
          _views >= (share['MaxViews'] as int) ||
          !DateTime.parse(share['ExpiresAt'] as String)
              .isAfter(DateTime.now().toUtc())) {
        return const ApiReply(403, '');
      }
      _views++;
      _session = (++_next, token!);
    } else {
      final session = _session;
      if (session == null || session.$2 != token) {
        return const ApiReply(404, '');
      }
      if (path == '/api/content/sessions/${session.$1}/end') {
        _session = null;
        return _json({'success': true});
      }
      if (path != '/api/content/sessions/${session.$1}/check') {
        return const ApiReply(404, '');
      }
    }
    return _json({
      'SessionId': _session!.$1,
      'AccessGranted': true,
      'Suspended': false,
      'SessionEnded': false,
      'DeviceVerified': false,
      'LocationVerified': true,
      'CameraRestrictions': {
        'Enabled': false,
        'BlockPhones': false,
        'BlockMultiplePeople': false,
        'RequireViewer': false,
      },
      'FileType': share['FileType'],
      'FileDataBase64': share['FileDataBase64'],
    });
  }

  @override
  void close() {
    _tokens.clear();
    _share = null;
    _session = null;
  }
}
