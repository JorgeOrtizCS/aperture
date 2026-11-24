import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aperture/models/api_models.dart';
import 'package:aperture/services/api_service.dart';
import 'package:flutter/foundation.dart';

import 'temporary_png_demo_fixture.dart';

const pngDemoSender = 'fixture-png-sender';
const pngDemoRecipient = 'fixture-png-recipient';
const pngDemoDevice = '11111111-1111-4111-8111-111111111111';

/// Reuses the normal API client with relative routes. The alternate entry point
/// owns the sole exception for transmitting and receiving the known sample.
class PngDemoTransport implements CancellableApiTransport {
  PngDemoTransport(this._backend) {
    if (!kDebugMode) throw const ApiException(ApiFailure.configuration);
  }

  final ApiTransport _backend;
  final _accounts = <String, String>{};
  final _priorIds = <int>{};
  final _listed = <String>{};
  final _sessions = <int, String>{};
  final _delivered = <int>{};
  bool _submitted = false;
  int? contentId;
  String? _title;
  DateTime? _expiry;

  bool get submitted => _submitted;

  bool get hasAuthorizedSample => _delivered.isNotEmpty;

  CancellableApiTransport accountTransport() => _PngDemoAccountTransport(this);

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) => _send(method, uri, headers, body);

  @override
  Future<ApiReply> sendCancellable(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
    ApiRequestCancellation cancellation,
  ) => _send(method, uri, headers, body, cancellation);

  Future<ApiReply> _send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body, [
    ApiRequestCancellation? cancellation,
  ]) async {
    if (uri.hasAuthority || uri.hasScheme || uri.hasQuery || uri.hasFragment) {
      throw const ApiException(ApiFailure.configuration);
    }
    final path = uri.path;
    final token = headers['Authorization'];
    final account = _accounts[token];
    final input = body == null ? null : apiObject(jsonDecode(body));
    final backend = _backend;
    Future<ApiReply> forward() {
      if (cancellation?.isCancelled == true) {
        throw const ApiException(ApiFailure.cancelled);
      }
      return backend is CancellableApiTransport && cancellation != null
          ? backend.sendCancellable(method, uri, headers, body, cancellation)
          : backend.send(method, uri, headers, body);
    }

    if ((method, path) == ('POST', '/api/auth/login')) {
      final username = input?['Username'];
      if (username != pngDemoSender && username != pngDemoRecipient) {
        return const ApiReply(401, '');
      }
      final reply = await forward();
      if (reply.status == 200) {
        final j = apiObject(jsonDecode(reply.body));
        final bearer = j['Token'];
        if (j['Success'] == true && bearer is String) {
          _accounts['Bearer $bearer'] = username as String;
        }
      }
      return reply;
    }
    if (account == null) return const ApiReply(401, '');
    switch ((method, path)) {
      case ('GET', '/api/user/me'):
        return forward();
      case ('POST', '/api/auth/logout'):
        _accounts.remove(token);
        _listed.remove(account);
        _sessions.removeWhere((id, owner) {
          if (owner != token) return false;
          _delivered.remove(id);
          return true;
        });
        return forward();
      case ('GET', '/api/content'):
        final reply = await forward();
        if (reply.status != 200) return reply;
        final rows = jsonDecode(reply.body) as List;
        final items = rows.map(apiObject);
        if (contentId == null) {
          _priorIds.addAll(items.map((row) => apiId(row['Id'])));
        }
        final matching = items.where((row) => row['Id'] == contentId).toList();
        if (matching.isNotEmpty && !_fixtureRow(matching.single, account)) {
          throw const ApiException(ApiFailure.denied);
        }
        _listed.add(account);
        return ApiReply(200, jsonEncode(matching));
      case ('POST', '/api/content'):
        if (_submitted ||
            account != pngDemoSender ||
            !_listed.containsAll({pngDemoSender, pngDemoRecipient}) ||
            input == null ||
            !_approvedUpload(input)) {
          throw const ApiException(ApiFailure.denied);
        }
        _submitted =
            true; // Includes ambiguous acknowledgement and cancellation.
        _title = input['Title'] as String;
        _expiry = apiUtc(input['ExpiresAt']);
        final reply = await forward();
        if (reply.status == 200) {
          final id = apiId(apiObject(jsonDecode(reply.body))['id']);
          if (_priorIds.contains(id)) {
            throw const ApiException(ApiFailure.malformed);
          }
          contentId = id;
        }
        return reply;
    }
    final id = contentId;
    if (method != 'POST' || id == null) {
      throw const ApiException(ApiFailure.denied);
    }
    if (account == pngDemoSender &&
        (path == '/api/content/$id/policy' ||
            path == '/api/content/$id/revoke')) {
      return forward();
    }
    if (account != pngDemoRecipient) {
      throw const ApiException(ApiFailure.denied);
    }
    if (path == '/api/content/$id/sessions') {
      return _view(await forward(), token!, opening: true);
    }
    final match = RegExp(r'^/api/content/sessions/([1-9][0-9]*)/(check|end)$')
        .firstMatch(path);
    final session = match == null ? null : int.tryParse(match[1]!);
    if (session == null || _sessions[session] != token) {
      throw const ApiException(ApiFailure.denied);
    }
    if (match![2] == 'check') {
      final reply = await forward();
      if (_sessions[session] != token) return const ApiReply(404, '');
      return _view(reply, token!, expectedId: session);
    }
    _delivered.remove(session);
    final reply = await forward();
    if (reply.status == 200 || reply.status == 404) _sessions.remove(session);
    return reply;
  }

  bool _approvedUpload(Map<String, dynamic> body) {
    const keys = {
      'Title',
      'Recipient',
      'FileType',
      'FileDataBase64',
      'RequireTrustedDevice',
      'ScreenshotRestriction',
      'MaxViews',
      'ExpiresAt',
    };
    final title = body['Title'];
    final expires = DateTime.tryParse(body['ExpiresAt']?.toString() ?? '');
    final now = DateTime.now().toUtc();
    return body.length == keys.length &&
        keys.containsAll(body.keys) &&
        title is String &&
        RegExp(r'^Aperture synthetic PNG - [a-f0-9]{24}$').hasMatch(title) &&
        body['Recipient'] == pngDemoRecipient &&
        body['FileType'] == 'image/png' &&
        body['FileDataBase64'] == classroomSyntheticPng &&
        body['RequireTrustedDevice'] == false &&
        body['ScreenshotRestriction'] == false &&
        body['MaxViews'] == 2 &&
        expires != null &&
        expires.isAfter(now) &&
        !expires.isAfter(now.add(const Duration(hours: 12)));
  }

  bool _fixtureRow(Map<String, dynamic> row, String account) {
    final mine = account == pngDemoSender;
    final item = ApiContent.fromJson(row);
    return item.mine == mine &&
        item.title == _title &&
        item.owner == pngDemoSender &&
        item.recipient == (mine ? pngDemoRecipient : null) &&
        !item.requiresTrustedDevice &&
        !item.requiresPreciseLocation &&
        row['RequireTrustedDevice'] == false &&
        row['ScreenshotRestriction'] == false &&
        row['MaxViews'] == 2 &&
        item.expiresAt == _expiry &&
        const [
          'AllowedCountry',
          'AllowedRegion',
          'AllowedCity',
          'RequiredLocation',
          'StartTime',
          'FileDataBase64',
          'Body',
        ].every((key) => row[key] == null) &&
        (row['CameraRestrictions'] == null ||
            apiObject(row['CameraRestrictions']).values
                .every((value) => value == false));
  }

  ApiReply _view(
    ApiReply reply,
    String token, {
    bool opening = false,
    int? expectedId,
  }) {
    if (reply.status != 200) {
      _delivered.remove(expectedId);
      return ApiReply(reply.status, '');
    }
    final json = apiObject(jsonDecode(reply.body));
    final session = json['SessionId'];
    // Preserve the ID in a sanitized envelope if the normal client needs to
    // end a malformed open. A check never adds a cleanup target.
    if (opening && session is int && session > 0) _sessions[session] = token;
    final png = json.remove('FileDataBase64');
    final fileType = json.remove('FileType');
    final text = json.remove('Body');
    json.remove('Title');
    json.remove('Message');
    final grant =
        json['AccessGranted'] == true &&
        json['SessionEnded'] == false &&
        json['Suspended'] == false;
    if (grant &&
        session is int &&
        session > 0 &&
        (opening || session == expectedId) &&
        json['DeviceVerified'] == false &&
        text == null &&
        png == classroomSyntheticPng &&
        fileType == 'image/png') {
      _delivered.add(session);
    } else {
      _delivered.remove(expectedId ?? session);
      if (grant) json['AccessGranted'] = false;
    }
    return ApiReply(200, jsonEncode(json));
  }

  @override
  void close() {
    _accounts.clear();
    _sessions.clear();
    _delivered.clear();
    _backend.close();
  }
}

class _PngDemoAccountTransport implements CancellableApiTransport {
  _PngDemoAccountTransport(this.transport);

  final PngDemoTransport transport;

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) => transport.send(method, uri, headers, body);

  @override
  Future<ApiReply> sendCancellable(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
    ApiRequestCancellation cancellation,
  ) => transport.sendCancellable(method, uri, headers, body, cancellation);

  @override
  void close() {} // The harness closes the shared transport after both logouts.
}

/// A developer can route the same contract to an isolated API on device
/// loopback. An arbitrary public origin cannot be selected from this tool.
class PngDemoLoopback implements CancellableApiTransport {
  PngDemoLoopback(String url)
    : base = ApiService.parseBaseUrl(url, schoolDemo: true) {
    if (!kDebugMode || !{'127.0.0.1', '::1'}.contains(base.host)) {
      throw const ApiException(ApiFailure.configuration);
    }
  }

  final Uri base;

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) => _send(method, uri, headers, body);

  @override
  Future<ApiReply> sendCancellable(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
    ApiRequestCancellation cancellation,
  ) => _send(method, uri, headers, body, cancellation);

  Future<ApiReply> _send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body, [
    ApiRequestCancellation? cancellation,
  ]) async {
    if (!uri.path.startsWith('/api/') ||
        uri.hasAuthority ||
        uri.hasScheme ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ApiException(ApiFailure.configuration);
    }
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    HttpClient.enableTimelineLogging = false;
    final connectionClosed = Completer<void>();
    if (cancellation != null) {
      unawaited(
        Future.any([cancellation.whenCancelled, connectionClosed.future])
            .then((_) {
              if (cancellation.isCancelled) client.close(force: true);
            }),
      );
    }
    try {
      return await (() async {
        final request = await client.openUrl(
          method,
          base.resolve(uri.path.substring(1)),
        );
        request
          ..followRedirects = false
          ..persistentConnection = false;
        headers.forEach(request.headers.set);
        if (body != null) request.add(utf8.encode(body));
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > NativeApiTransport.maxBytes) {
            throw const ApiException(ApiFailure.malformed);
          }
          bytes.addAll(chunk);
        }
        return ApiReply(response.statusCode, utf8.decode(bytes));
      })().timeout(const Duration(seconds: 4));
    } on TimeoutException {
      throw const ApiException(ApiFailure.timeout);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(ApiFailure.network);
    } finally {
      client.close(force: true);
      connectionClosed.complete();
    }
  }

  @override
  void close() {}
}
