import 'dart:async';
import 'dart:convert';

import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_session.dart';

// Source-shaped synthetic fixtures only. No sockets or real credentials.
class ApiCall {
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
  const ApiCall(this.method, this.uri, this.headers, this.body);
  dynamic get json => body == null ? null : jsonDecode(body!);
}

ApiReply jsonReply(Object value, [int status = 200]) =>
    ApiReply(status, jsonEncode(value));

Map<String, Object?> contentJson({
  int id = 7,
  bool mine = false,
  String title = 'Synthetic metadata',
  String status = 'Active',
  String policy = 'Active',
}) => {
  'Id': id,
  'Title': title,
  'Owner': 'synthetic-owner',
  'Mine': mine,
  'CreatedAt': '2026-11-05T12:00:00Z',
  'Status': status,
  'PolicyStatus': policy,
  if (mine) 'Recipient': 'synthetic-recipient',
};

Map<String, Object?> accessJson({
  bool granted = true,
  bool suspended = false,
  bool ended = false,
  int id = 41,
}) => {
  'SessionId': id,
  'AccessGranted': granted,
  'Suspended': suspended,
  'SessionEnded': ended,
  'DeviceVerified': false,
  'LocationVerified': true,
  'CameraRestrictions': {
    'Enabled': false,
    'BlockPhones': false,
    'BlockMultiplePeople': false,
    'RequireViewer': false,
  },
  if (granted) 'Body': 'SYNTHETIC PAYLOAD MUST NOT RENDER',
  if (granted) 'FileType': 'text/plain',
};

class ApiFake implements ApiTransport {
  final calls = <ApiCall>[];
  final routes = <String, FutureOr<ApiReply> Function(ApiCall)>{};
  List<Map<String, Object?>> contents = [];
  int userId = 1;
  String username = 'synthetic-user';
  String token = 'synthetic-opaque-token';
  DateTime expiresAt = DateTime.utc(2026, 11, 5, 8);
  bool closed = false;

  ApiService service({Duration timeout = const Duration(seconds: 4)}) =>
      ApiService(
        baseUri: Uri.parse('https://fixture.invalid/'),
        transport: this,
        timeout: timeout,
      );
  ApiSession session({
    String? deviceKey = '11111111-1111-4111-8111-111111111111',
    Duration timeout = const Duration(seconds: 4),
  }) => ApiSession(
    service(timeout: timeout),
    deviceKey: deviceKey,
    now: () => DateTime.utc(2026, 11, 5),
  );

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final call = ApiCall(method, uri, Map.of(headers), body);
    calls.add(call);
    final route = routes[uri.path];
    if (route != null) return route(call);
    switch (uri.path) {
      case '/api/auth/login':
        return jsonReply({
          'Success': true,
          'Token': token,
          'ExpiresAt': expiresAt.toIso8601String(),
          'User': {'Id': userId, 'Username': username},
        });
      case '/api/user/me':
        return jsonReply({
          'success': true,
          'user': {'id': userId, 'username': username},
        });
      case '/api/auth/logout':
        return jsonReply({'success': true});
      case '/api/content':
        return jsonReply(contents);
    }
    if (uri.path.endsWith('/policy')) {
      return jsonReply({'status': call.json['Status']});
    }
    if (uri.path.endsWith('/revoke') || uri.path.endsWith('/end')) {
      return jsonReply({'success': true});
    }
    if (uri.path.endsWith('/sessions') || uri.path.endsWith('/check')) {
      return jsonReply(accessJson());
    }
    throw StateError('Unexpected fixture request: $method ${uri.path}');
  }

  @override
  void close() => closed = true;
}
