import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/api_models.dart';
import 'api_service.dart';

ApiService configuredApi({
  String mode = const String.fromEnvironment(
    'APERTURE_API_MODE',
    defaultValue: 'live',
  ),
  String baseUrl = const String.fromEnvironment('APERTURE_API_BASE_URL'),
  String classroomOrigin = approvedClassroomOrigin,
}) {
  if (mode == 'fixture' && kDebugMode && baseUrl.isEmpty) {
    return ApiService.fixture(transport: _FixtureTransport());
  }
  final schoolDemo = mode == 'school-demo-http' && kDebugMode;
  final classroomHttp = mode == classroomHttpMode && kDebugMode;
  if (mode == 'live' || schoolDemo || classroomHttp) {
    try {
      final base = classroomHttp
          ? ApiService.parseApprovedClassroomBaseUrl(baseUrl, classroomOrigin)
          : ApiService.parseBaseUrl(baseUrl, schoolDemo: schoolDemo);
      return ApiService(
        baseUri: base,
        transport: classroomHttp
            ? NativeApiTransport.classroomHttp(base)
            : schoolDemo
            ? NativeApiTransport.schoolDemo(base)
            : NativeApiTransport(),
        schoolDemo: schoolDemo,
        classroomHttp: classroomHttp,
        timeout: classroomHttp
            ? NativeApiTransport.classroomTimeout
            : NativeApiTransport.timeout,
      );
    } on ApiException {
      // The sign-in UI reports a missing or invalid API configuration.
    }
  }
  return ApiService(baseUri: null, transport: NativeApiTransport());
}

/// Exercises the API sign-in/list/logout flow without sockets. Reserved
/// fixture names are selectors; no real authentication is attempted.
class _FixtureTransport implements ApiTransport {
  static const _sender = 'fixture-sender';
  static const _recipient = 'fixture-recipient';
  final _users = <String, String>{};
  var _sequence = 0;

  ApiReply _json(int status, Object value) =>
      ApiReply(status, jsonEncode(value));

  int _id(String username) => username == _sender ? 1 : 2;

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    if (uri.hasAuthority || uri.hasScheme) {
      throw const ApiException(ApiFailure.configuration);
    }
    if (method == 'POST' && uri.path == '/api/auth/login') {
      final input = apiObject(jsonDecode(body!));
      final username = input['Username'];
      final password = input['Password'];
      if ((username != _sender && username != _recipient) ||
          password is! String ||
          password.trim().isEmpty) {
        return _json(401, {'Success': false});
      }
      final name = username as String;
      final token = 'fixture-session-${++_sequence}';
      _users[token] = name;
      return _json(200, {
        'Success': true,
        'Token': token,
        'ExpiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 8))
            .toIso8601String(),
        'User': {'Id': _id(name), 'Username': name},
      });
    }
    final bearer = headers['Authorization'];
    final token = bearer != null && bearer.startsWith('Bearer ')
        ? bearer.substring(7)
        : null;
    final user = _users[token];
    if (user == null) return _json(401, {'success': false});

    return switch ((method, uri.path)) {
      ('GET', '/api/user/me') => _json(200, {
        'success': true,
        'user': {'id': _id(user), 'username': user},
      }),
      ('POST', '/api/auth/logout') => _json(200, {
        'success': _users.remove(token) != null,
      }),
      ('GET', '/api/content') => _json(200, [
        {
          'Id': 1,
          'Title': 'Sample shared content',
          'Owner': _sender,
          'Mine': user == _sender,
          if (user == _sender) 'Recipient': _recipient,
          'CreatedAt': '2026-01-01T00:00:00Z',
          'Status': 'Active',
          'PolicyStatus': 'Active',
          'RequireTrustedDevice': false,
          'ScreenshotRestriction': false,
        },
      ]),
      ('GET', '/api/content/capabilities') => _json(200, {
        'CameraPolicyVersion': 1,
      }),
      _ => _json(403, {'success': false}),
    };
  }

  @override
  void close() => _users.clear();
}
