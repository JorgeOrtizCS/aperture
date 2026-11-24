import 'dart:async';
import 'dart:convert';

import 'package:aperture/services/api_service.dart';

import '../../tool/hosted_png_viewer_transport.dart';
import '../../tool/temporary_png_demo_fixture.dart';

class HostedPngFixtureApi implements ApiTransport {
  HostedPngFixtureApi({
    this.contentId = hostedPngContentId,
    this.title = hostedPngTitle,
    this.maxViews = 2,
  });

  final int contentId, maxViews;
  final String title;
  static const token = 'fixture-recipient-token';
  static const session = 724;
  final routes = <(String, String)>[];
  final cleanupCredentials = <String?>[];
  final metadataOverrides = <String, Object?>{};
  final grantOverrides = <String, Object?>{};
  ApiReply? checkReply;
  Completer<void>? delayOpen;
  Completer<void>? delayCheck;
  String username = hostedPngRecipient;
  bool expired = false;
  bool closed = false;

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final route = (method, uri.path);
    routes.add(route);
    if (route == ('POST', '/api/auth/login')) {
      return _reply({
        'Success': true,
        'User': {'Id': 8, 'Username': username},
        'Token': token,
        'ExpiresAt': (expired ? DateTime.utc(2000) : DateTime.utc(2099))
            .toIso8601String(),
      });
    }
    if (headers['Authorization'] != 'Bearer $token') {
      return const ApiReply(401, '');
    }
    if (route == ('POST', '/api/content/$contentId/sessions')) return _open();
    return switch (route) {
      ('GET', '/api/user/me') => _reply({
        'success': true,
        'user': {'id': 8, 'username': username},
      }),
      ('GET', '/api/content') => _reply([
        {
          'Id': contentId,
          'Title': title,
          'Owner': classroomFixtureSender,
          'Mine': false,
          'Status': 'Active',
          'PolicyStatus': 'Active',
          'CreatedAt': '2026-11-14T21:00:00Z',
          'MaxViews': maxViews,
          'RequireTrustedDevice': false,
          'ScreenshotRestriction': false,
          ...metadataOverrides,
        },
      ]),
      ('POST', '/api/content/sessions/$session/check') => _check(),
      ('POST', '/api/content/sessions/$session/end') => _end(headers),
      ('POST', '/api/auth/logout') => _reply({'success': true}),
      _ => throw StateError('Test app requested a route outside the fixture.'),
    };
  }

  Future<ApiReply> _open() async {
    await delayOpen?.future;
    return _grant();
  }

  Future<ApiReply> _check() async {
    await delayCheck?.future;
    return checkReply ?? _grant();
  }

  ApiReply _end(Map<String, String> headers) {
    cleanupCredentials.add(headers['Authorization']);
    return _reply({'success': true});
  }

  ApiReply _grant() => _reply({
    'Title': title,
    'SessionId': session,
    'AccessGranted': true,
    'Suspended': false,
    'SessionEnded': false,
    'DeviceVerified': false,
    'LocationVerified': true,
    'CameraRestrictions': const {
      'Enabled': false,
      'BlockPhones': false,
      'BlockMultiplePeople': false,
      'RequireViewer': false,
    },
    'FileType': hostedPngMime,
    'Body': null,
    'FileDataBase64': classroomSyntheticPng,
    ...grantOverrides,
  });

  static ApiReply _reply(Object data) => ApiReply(200, jsonEncode(data));

  @override
  void close() => closed = true;
}
