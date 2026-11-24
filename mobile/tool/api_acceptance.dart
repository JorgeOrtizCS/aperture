#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:aperture/models/api_models.dart';
import 'package:aperture/models/content_create_request.dart';
import 'package:aperture/services/api_service.dart';

import 'flutter_png_fixture_spec.dart';
import 'temporary_png_demo_fixture.dart';

part 'classroom_session_acceptance.dart';
part 'classroom_revocation_acceptance.dart';
part 'classroom_png_acceptance.dart';

enum AcceptanceMode {
  smoke,
  existingShare,
  disposable,
  classroomSession,
  classroomRevocation,
  classroomPng,
  classroomFlutterPngSetup;

  bool get isClassroomWrite =>
      this == classroomSession ||
      this == classroomRevocation ||
      this == classroomPng ||
      this == classroomFlutterPngSetup;
}

const _localConfigPath = 'config/local/api.acceptance.json';

class AcceptanceConfig {
  final Uri base;
  final bool usesClassroomHttp;
  final ClassroomAccounts classroomAccounts;
  final Set<int> archivedPngIds;
  final String? deviceKey;
  final int? existingShareId;
  final ({String username, String password}) sender, recipient;

  AcceptanceConfig._(
    this.base,
    this.usesClassroomHttp,
    this.classroomAccounts,
    this.archivedPngIds,
    this.deviceKey,
    this.existingShareId,
    this.sender,
    this.recipient,
  );

  factory AcceptanceConfig.fromJson(
    Object? input, {
    bool protectedLoopback = false,
    bool classroomHttp = false,
  }) {
    final json = apiObject(input);
    if (json['APERTURE_ACCEPTANCE_ENVIRONMENT'] != 'approved-non-production') {
      throw const ApiException(ApiFailure.configuration);
    }

    ({String username, String password}) account(String key) {
      final entry = apiObject(json[key]);
      return (
        username: apiString(entry['username']).trim(),
        password: apiString(entry['password']),
      );
    }

    final sender = account('sender');
    final recipient = account('recipient');
    if (sender.username.toLowerCase() == recipient.username.toLowerCase()) {
      throw const ApiException(ApiFailure.configuration);
    }
    final key = json['APERTURE_DEVICE_KEY'];
    if (protectedLoopback && classroomHttp) {
      throw const ApiException(ApiFailure.configuration);
    }
    final baseUrl = apiString(json['APERTURE_API_BASE_URL']);
    final base = classroomHttp
        ? ApiService.parseApprovedClassroomBaseUrl(
            baseUrl,
            apiString(json['APERTURE_CLASSROOM_APPROVED_ORIGIN']),
          )
        : ApiService.parseBaseUrl(baseUrl, schoolDemo: protectedLoopback);
    if (protectedLoopback && !{'127.0.0.1', '::1'}.contains(base.host)) {
      throw const ApiException(ApiFailure.configuration);
    }
    final approvedAccounts = classroomHttp
        ? (
            sender: apiString(json['APERTURE_CLASSROOM_SENDER']).trim(),
            recipient: apiString(json['APERTURE_CLASSROOM_RECIPIENT']).trim(),
          )
        : defaultClassroomAccounts;
    final allowlist = {approvedAccounts.sender, approvedAccounts.recipient};
    if (classroomHttp &&
        (base.port != 80 ||
            base.path != '/' ||
            allowlist.length != 2 ||
            !allowlist.containsAll([sender.username, recipient.username]))) {
      throw const ApiException(ApiFailure.configuration);
    }
    final archive = json['APERTURE_CLASSROOM_ARCHIVED_PNG_IDS'];
    final archivedPngIds = classroomHttp && archive != null && archive != ''
        ? parseArchivedPngIds(apiString(archive))
        : const <int>{};
    final shareId = json['APERTURE_ACCEPTANCE_CONTENT_ID'];
    return AcceptanceConfig._(
      base,
      classroomHttp,
      approvedAccounts,
      archivedPngIds,
      key == null || key == '' ? null : apiString(key),
      shareId == null ? null : apiId(shareId),
      sender,
      recipient,
    );
  }

  bool get usesLoopbackHttp => !usesClassroomHttp && base.scheme == 'http';
}

class AcceptanceFailure implements Exception {
  final String step;
  const AcceptanceFailure(this.step);
}

void _require(bool condition) {
  if (!condition) throw const FormatException('Unexpected contract result.');
}

String _nonce() {
  final random = Random.secure();
  return List.generate(
    12,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

Future<void> runAcceptance(
  AcceptanceConfig config,
  AcceptanceMode mode, {
  required bool approvedDisposableWrites,
  required void Function(String) progress,
  ApiTransport? transport,
  File? classroomSessionJournal,
}) async {
  if (mode.isClassroomWrite) {
    if (!approvedDisposableWrites ||
        !config.usesClassroomHttp ||
        config.sender.username != config.classroomAccounts.sender ||
        config.recipient.username != config.classroomAccounts.recipient ||
        (mode == AcceptanceMode.classroomFlutterPngSetup &&
            config.archivedPngIds.isEmpty) ||
        config.existingShareId != null ||
        config.deviceKey != null ||
        classroomSessionJournal == null) {
      throw const AcceptanceFailure(
        'Classroom session requires exact approved scope and a private journal',
      );
    }
    final revocation = mode == AcceptanceMode.classroomRevocation;
    final target =
        transport ??
        _ClassroomSessionTransport(
          config,
          allowSenderChanges: revocation,
          allowViewingSessions: mode != AcceptanceMode.classroomFlutterPngSetup,
        );
    final runner = switch (mode) {
      AcceptanceMode.classroomRevocation => _ClassroomRevocation(
        config,
        target,
        progress,
        classroomSessionJournal,
      ),
      AcceptanceMode.classroomPng => _ClassroomPng(
        config,
        target,
        progress,
        classroomSessionJournal,
      ),
      AcceptanceMode.classroomFlutterPngSetup => _ClassroomFlutterPngSetup(
        config,
        target,
        progress,
        classroomSessionJournal,
      ),
      _ => _ClassroomSession(config, target, progress, classroomSessionJournal),
    };
    await runner.run();
    return;
  }
  if (config.usesClassroomHttp && mode != AcceptanceMode.smoke) {
    throw const AcceptanceFailure('Classroom HTTP supports smoke only');
  }
  final key = config.deviceKey;
  if (mode == AcceptanceMode.disposable &&
      (!approvedDisposableWrites || config.usesLoopbackHttp)) {
    throw const AcceptanceFailure(
      'Disposable writes require approval and HTTPS',
    );
  }
  if (mode == AcceptanceMode.existingShare && config.existingShareId == null) {
    throw const AcceptanceFailure(
      'An approved synthetic content ID is required',
    );
  }
  if (mode != AcceptanceMode.smoke &&
      (key == null ||
          !RegExp(
            r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
          ).hasMatch(key) ||
          key.replaceAll('-', '').replaceAll('0', '').isEmpty)) {
    throw const AcceptanceFailure('A nonzero test device GUID is required');
  }
  final target =
      transport ??
      (config.usesClassroomHttp
          ? NativeApiTransport.classroomHttp(config.base)
          : config.usesLoopbackHttp
          ? NativeApiTransport.schoolDemo(config.base)
          : NativeApiTransport());
  final runner = _Acceptance(config, target, progress);
  await runner.run(mode);
}

class _Acceptance {
  final AcceptanceConfig config;
  final ApiTransport transport;
  final void Function(String) progress;
  final ApiService api;
  final _tokens = <String>{};
  final _sessions = <int, String>{};
  final _content = <int, String>{};

  _Acceptance(this.config, this.transport, this.progress)
    : api = ApiService(
        baseUri: config.base,
        transport: transport,
        schoolDemo: config.usesLoopbackHttp,
        classroomHttp: config.usesClassroomHttp,
        classroomAccounts: config.classroomAccounts,
        timeout: config.usesClassroomHttp
            ? NativeApiTransport.classroomTimeout
            : NativeApiTransport.timeout,
      );

  Future<T> _step<T>(String label, Future<T> Function() operation) async {
    try {
      final result = await operation();
      progress('PASS: $label');
      return result;
    } on ApiException catch (e) {
      throw AcceptanceFailure('$label (${e.kind.name})');
    } catch (_) {
      throw AcceptanceFailure(label);
    }
  }

  Future<ApiReply> _request(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
  }) => transport.send(method, config.base.resolve(path), {
    'Accept': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
    if (body != null) 'Content-Type': 'application/json',
  }, body == null ? null : jsonEncode(body));

  Future<ApiCredentials> _login(
    ({String username, String password}) account,
  ) async {
    final auth = await api.login(account.username, account.password);
    _tokens.add(auth.token);
    _require(auth.expiresAt.isAfter(DateTime.now().toUtc()));
    final me = await api.currentUser(auth.token);
    _require(me.id == auth.user.id && me.username == auth.user.username);
    _require(me.username == account.username);
    return auth;
  }

  Future<void> _logout(String token) async {
    // Use a raw request: acceptance requires a positive server acknowledgement
    // for a known-valid token, followed by proof it no longer authorizes GET.
    final response = await _request('POST', 'api/auth/logout', token: token);
    _require(response.status == 200);
    _require(apiObject(jsonDecode(response.body))['success'] == true);
    _require(
      (await _request('GET', 'api/user/me', token: token)).status == 401,
    );
    _tokens.remove(token);
  }

  void _compareLists(
    ApiUser owner,
    ApiUser recipient,
    List<ApiContent> owned,
    List<ApiContent> received,
  ) {
    for (final item in owned.where((item) => item.mine)) {
      _require(item.owner == owner.username);
    }
    final sent = owned
        .where((item) => item.mine && item.recipient == recipient.username)
        .map((item) => item.id)
        .toSet();
    final inbound = received
        .where((item) => !item.mine && item.owner == owner.username)
        .map((item) => item.id)
        .toSet();
    _require(sent.containsAll(inbound) && inbound.containsAll(sent));
  }

  Future<void> _isolation(
    ApiCredentials a,
    ApiCredentials b, {
    int? id,
    String status = 'Active',
    String policyStatus = 'Active',
  }) async {
    final first = await api.list(a.token);
    final second = await api.list(b.token);

    _compareLists(a.user, b.user, first, second);
    _compareLists(b.user, a.user, second, first);
    if (id != null) {
      final sent = first.where((item) => item.id == id).single;
      final received = second.where((item) => item.id == id).single;
      _require(sent.mine && sent.recipient == b.user.username);
      _require(!received.mine && received.owner == a.user.username);
      for (final item in [sent, received]) {
        _require(item.status == status && item.policyStatus == policyStatus);
      }
    }
  }

  Future<int> _create(
    String token,
    String recipient,
    String title, {
    bool camera = false,
    bool screenshot = false,
  }) async {
    final response = await _request(
      'POST',
      'api/content',
      token: token,
      body: {
        'Title': title,
        'Body': 'Disposable synthetic API acceptance fixture.',
        'Recipient': recipient,
        'ScreenshotRestriction': screenshot,
        if (camera)
          'CameraRestrictions': {'Enabled': true, 'BlockPhones': true},
      },
    );
    _require(response.status == 200);
    final id = apiId(apiObject(jsonDecode(response.body))['id']);
    _content[id] = token;
    return id;
  }

  Future<int?> _open(
    String token,
    int content, {
    int expected = 200,
    bool? deviceTrusted,
  }) async {
    final response = await _request(
      'POST',
      'api/content/$content/sessions',
      token: token,
      body: {
        'DeviceKey': config.deviceKey,
        'CameraPolicyVersion': ApiService.cameraPolicyVersion,
      },
    );
    // 404 may have an empty body. Any positive ID in an open result must be
    // cleaned up even when later assertions fail.
    final raw = response.body.trim().isEmpty || response.status == 404
        ? null
        : apiObject(jsonDecode(response.body));
    final id = raw?['SessionId'];
    if (id is int && id > 0) _sessions[id] = token;
    _require(response.status == expected);
    if (expected == 404) return null;
    final decision = ApiAccessDecision.fromJson(raw);
    if (expected == 200) {
      _require(decision.granted && !decision.ended && !decision.suspended);
      if (deviceTrusted != null) {
        _require(decision.deviceVerified == deviceTrusted);
      }
      return apiId(decision.sessionId);
    }
    _require(raw!['AccessGranted'] == false && (id == null || id == 0));
    _require(raw['Body'] == null && raw['FileDataBase64'] == null);
    return null;
  }

  Future<void> _check(String token, int id, {int expected = 200}) async {
    final response = await _request(
      'POST',
      'api/content/sessions/$id/check',
      token: token,
      body: const {},
    );
    _require(response.status == expected);
    if (expected == 200) {
      final result = ApiAccessDecision.fromJson(jsonDecode(response.body));
      _require(result.granted && result.sessionId == id);
    } else if (expected == 403) {
      final result = apiObject(jsonDecode(response.body));
      _require(
        result['AccessGranted'] == false && result['SessionEnded'] == true,
      );
      _require(result['Body'] == null && result['FileDataBase64'] == null);
    }
  }

  Future<void> _revoke(String token, int id) async {
    await api.revoke(token, id);
    _content.remove(id);
  }

  Future<void> _verifyRecipientSession(
    ApiCredentials sender,
    ApiCredentials recipient,
    int content, {
    bool? deviceTrusted,
  }) async {
    final id = (await _open(
      recipient.token,
      content,
      deviceTrusted: deviceTrusted,
    ))!;
    await _check(recipient.token, id);
    await _check(sender.token, id, expected: 404);
    await api.end(recipient.token, id);
    _sessions.remove(id);
    await _check(recipient.token, id, expected: 403);
  }

  Future<void> _disposable(
    ApiCredentials sender,
    ApiCredentials recipient,
  ) async {
    final a = sender.token, b = recipient.token;
    final deviceTrusted = await _step(
      'Register the recipient test device',
      () => api.registerDevice(
        b,
        config.deviceKey!,
        'Aperture acceptance device',
      ),
    );
    final run = 'aperture-acceptance-${_nonce()}';
    progress('Disposable fixture title prefix: $run');
    final content = await _step(
      'Create disposable sender-to-recipient fixture',
      () => _create(a, recipient.user.username, '$run-basic'),
    );
    await _step('Verify sender and recipient see only their roles', () async {
      await _isolation(sender, recipient, id: content);
      await _open(a, content, expected: 404);
      final reply = await _request(
        'POST',
        'api/content/$content/policy',
        token: b,
        body: {'Status': 'Paused'},
      );
      _require(reply.status == 404);
    });
    await _step(
      'Open, check and end a recipient session',
      () => _verifyRecipientSession(
        sender,
        recipient,
        content,
        deviceTrusted: deviceTrusted,
      ),
    );
    final resumed = await _step(
      'Pause ends access and resume allows a fresh session',
      () async {
        final id = (await _open(b, content, deviceTrusted: deviceTrusted))!;
        await api.policy(a, content, 'Paused');
        await _isolation(
          sender,
          recipient,
          id: content,
          policyStatus: 'Paused',
        );
        await _check(b, id, expected: 404);
        await _open(b, content, expected: 403);
        await api.policy(a, content, 'Active');
        await _isolation(sender, recipient, id: content);
        await _check(b, id, expected: 404);
        _sessions.remove(id);
        final fresh = (await _open(b, content, deviceTrusted: deviceTrusted))!;
        _require(fresh != id);
        await _check(b, fresh);
        return fresh;
      },
    );
    await _step(
      'Revocation ends a fresh session and prevents reopening',
      () async {
        await api.revoke(a, content);
        await _isolation(sender, recipient, id: content, status: 'Revoked');
        _content.remove(content);
        await _check(b, resumed, expected: 404);
        _sessions.remove(resumed);
        await _open(b, content, expected: 404);
      },
    );
    await _step(
      'Camera and screenshot policies deny unsupported sessions',
      () async {
        final camera = await _create(
          a,
          recipient.user.username,
          '$run-camera',
          camera: true,
        );
        await _open(b, camera, expected: 403);
        final screenshot = await _create(
          a,
          recipient.user.username,
          '$run-screenshot',
          screenshot: true,
        );
        await _open(b, screenshot, expected: 403);
      },
    );
  }

  Future<void> run(AcceptanceMode mode) async {
    if (config.usesClassroomHttp) {
      try {
        await _runClassroomSmoke();
      } finally {
        api.close();
      }
      return;
    }
    try {
      final connection = config.usesLoopbackHttp ? 'Loopback HTTP' : 'HTTPS';
      await _step('$connection connectivity and anonymous rejection', () async {
        if (config.usesLoopbackHttp) {
          await api.checkAnonymousAccess();
        } else {
          _require((await _request('GET', 'api/content')).status == 401);
        }
      });
      await _step('Invalid login rejected', () async {
        final reply = await _request(
          'POST',
          'api/auth/login',
          body: {
            // Probe a random nonexistent account; avoid lockouts on real logins.
            'Username': 'aperture-invalid-${_nonce()}',
            'Password': _nonce(),
          },
        );
        if (reply.status == 200) {
          final token = apiObject(jsonDecode(reply.body))['Token'];
          if (token is String && RegExp(r'^[\w-]+$').hasMatch(token)) {
            _tokens.add(token);
          }
        }
        _require(reply.status == 401);
      });
      final sender = await _step(
        'Sender login and current-user identity',
        () => _login(config.sender),
      );
      final recipient = await _step(
        'Recipient login and current-user identity',
        () => _login(config.recipient),
      );
      await _step(
        'Account lists, isolation and server camera version',
        () async {
          _require(sender.user.id != recipient.user.id);
          _require(sender.token != recipient.token);
          await _isolation(
            sender,
            recipient,
            id: mode == AcceptanceMode.existingShare
                ? config.existingShareId
                : null,
          );
          _require(await api.serverCameraPolicyVersion(recipient.token) == 1);
        },
      );
      if (mode == AcceptanceMode.existingShare) {
        final content = config.existingShareId!;
        await _step(
          'Sender denied viewing the approved synthetic share',
          () => _open(sender.token, content, expected: 404),
        );
        await _step(
          'Open, check and end a recipient session',
          () => _verifyRecipientSession(sender, recipient, content),
        );
      }
      if (mode == AcceptanceMode.disposable) {
        await _disposable(sender, recipient);
        await _step(
          'End remaining sessions and revoke disposable content',
          _cleanupRecords,
        );
      }
      await _step('Logout invalidates both bearer tokens', () async {
        await _logout(recipient.token);
        await _logout(sender.token);
      });
    } finally {
      var cleanupFailed = false;
      try {
        await _cleanupRecords();
      } catch (_) {
        cleanupFailed = true;
      }
      for (final token in _tokens) {
        try {
          await api.logout(token);
        } catch (_) {
          cleanupFailed = true;
        }
      }
      api.close();
      if (cleanupFailed) {
        progress(
          'WARNING: Cleanup could not be confirmed. Check the test environment.',
        );
      }
    }
  }

  Future<void> _runClassroomSmoke() async {
    progress('Insecure HTTP — Classroom Test: ${config.base.origin}');
    await _step('Anonymous content access rejected', () async {
      final reply = await _request('GET', 'api/content');
      progress('GET /api/content (anonymous): HTTP ${reply.status}');
      _require(reply.status == 401);
    });

    final results = <(ApiUser, List<ApiContent>)>[];
    var failed = false;
    for (final (label, account) in [
      ('Sender', config.sender),
      ('Recipient', config.recipient),
    ]) {
      try {
        results.add(await _classroomAccount(label, account));
      } on AcceptanceFailure catch (e) {
        failed = true;
        progress('FAIL: ${e.step}');
      }
    }
    if (failed) throw const AcceptanceFailure('Classroom smoke incomplete');
    await _step(
      'Distinct accounts and consistent sender/recipient lists',
      () async {
        final (sender, sent) = results[0];
        final (recipient, received) = results[1];
        _require(sender.id != recipient.id);
        _compareLists(sender, recipient, sent, received);
        _compareLists(recipient, sender, received, sent);
      },
    );
  }

  Future<(ApiUser, List<ApiContent>)> _classroomAccount(
    String label,
    ({String username, String password}) account,
  ) async {
    final api = ApiService(
      baseUri: config.base,
      transport: _ClassroomStatusTransport(transport, label, progress),
      classroomHttp: true,
      classroomAccounts: config.classroomAccounts,
      timeout: NativeApiTransport.classroomTimeout,
    );
    final auth = await _step('$label login and token structure', () async {
      final auth = await api.login(account.username, account.password);
      return auth;
    });
    var verified = false;
    try {
      final me = await _step(
        '$label current-user identity and expiry',
        () async {
          _require(auth.expiresAt.isAfter(DateTime.now().toUtc()));
          final me = await api.currentUser(auth.token);
          _require(me.id == auth.user.id && me.username == auth.user.username);
          _require(me.username == account.username);
          return me;
        },
      );
      final items = await _step(
        '$label listing metadata validated',
        () => api.list(auth.token),
      );
      final owned = items.where((item) => item.mine).length;
      progress(
        '$label: ${me.username}, account ID ${me.id}, '
        '${items.length} metadata rows ($owned owned, ${items.length - owned} received)',
      );
      verified = true;
      return (me, items);
    } finally {
      try {
        await _step(
          '$label logout acknowledgement and token invalidation',
          () async {
            final reply = await _request(
              'POST',
              'api/auth/logout',
              token: auth.token,
            );
            progress('$label POST /api/auth/logout: HTTP ${reply.status}');
            _require(reply.status == 200);
            _require(apiObject(jsonDecode(reply.body))['success'] == true);
            final after = await _request(
              'GET',
              'api/user/me',
              token: auth.token,
            );
            progress(
              '$label GET /api/user/me after logout: HTTP ${after.status}',
            );
            _require(after.status == 401);
          },
        );
      } on AcceptanceFailure catch (e) {
        if (verified) rethrow;
        progress('FAIL: ${e.step}');
      }
    }
  }

  Future<void> _cleanupRecords() async {
    var failed = false;
    for (final entry in _sessions.entries.toList()) {
      try {
        await api.end(entry.value, entry.key);
        _sessions.remove(entry.key);
      } on ApiException catch (e) {
        if (e.kind == ApiFailure.notFound) {
          _sessions.remove(entry.key);
        } else {
          failed = true;
        }
      }
    }
    for (final entry in _content.entries.toList()) {
      try {
        await _revoke(entry.value, entry.key);
      } on ApiException {
        failed = true;
      }
    }
    _require(!failed);
  }
}

/// Reports status and a fixed vocabulary of response shapes. Response strings,
/// dynamic keys, headers and request bodies never reach the output callback.
class _ClassroomStatusTransport implements ApiTransport {
  final ApiTransport transport;
  final String label;
  final void Function(String) progress;

  _ClassroomStatusTransport(this.transport, this.label, this.progress);

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final reply = await transport.send(method, uri, headers, body);
    final shape = _shape(reply.body);
    progress('$label $method ${uri.path}: HTTP ${reply.status} ($shape)');
    return reply;
  }

  static String _shape(String body) {
    try {
      final value = jsonDecode(body);
      if (value is List) {
        if (value.isEmpty) return 'empty JSON array';
        return value.every((row) => row is Map<String, dynamic>)
            ? 'JSON array of objects'
            : 'JSON array with non-object rows';
      }
      if (value is Map<String, dynamic>) {
        if (value['Success'] == false || value['success'] == false) {
          return 'JSON rejection';
        }
        final fields = [
          for (final field in [
            'Success',
            'Token',
            'ExpiresAt',
            'User',
            'success',
            'user',
          ])
            if (value.containsKey(field)) field,
        ];
        return fields.isEmpty
            ? 'JSON object'
            : 'JSON object with ${fields.join(', ')}';
      }
      return 'JSON scalar';
    } on FormatException {
      return body.isEmpty ? 'empty body' : 'non-JSON body';
    }
  }

  @override
  void close() => transport.close();
}

Future<void> main(List<String> args) async {
  final mode = switch (args) {
    ['smoke', _] ||
    ['smoke', _, '--protected-loopback'] ||
    [
      'smoke',
      _localConfigPath,
      '--classroom-http-integration',
    ] => AcceptanceMode.smoke,
    ['existing-share', _] || ['existing-share', _, '--protected-loopback'] =>
      AcceptanceMode.existingShare,
    [
      'classroom-http-session',
      _localConfigPath,
      '--approve-one-synthetic-share',
    ] =>
      AcceptanceMode.classroomSession,
    [
      'classroom-http-revocation',
      _localConfigPath,
      '--approve-one-revocation-fixture',
    ] =>
      AcceptanceMode.classroomRevocation,
    ['classroom-http-png', _localConfigPath, _pngApprovalFlag] =>
      AcceptanceMode.classroomPng,
    [
      'classroom-http-flutter-png-setup',
      _localConfigPath,
      _flutterPngApprovalFlag,
    ] =>
      AcceptanceMode.classroomFlutterPngSetup,
    ['disposable', _, '--approve-disposable-writes'] =>
      AcceptanceMode.disposable,
    _ => null,
  };
  if (mode == null) {
    stderr.writeln(
      'Usage: tool/api_acceptance.dart smoke <local.json> [--protected-loopback]\n'
      '   or: tool/api_acceptance.dart smoke $_localConfigPath --classroom-http-integration\n'
      '   or: tool/api_acceptance.dart existing-share <local.json> [--protected-loopback]\n'
      '   or: tool/api_acceptance.dart disposable <local.json> --approve-disposable-writes\n'
      '   or: tool/api_acceptance.dart classroom-http-session $_localConfigPath --approve-one-synthetic-share\n'
      '   or: tool/api_acceptance.dart classroom-http-revocation $_localConfigPath --approve-one-revocation-fixture\n'
      '   or: tool/api_acceptance.dart classroom-http-png $_localConfigPath $_pngApprovalFlag\n'
      '   or: tool/api_acceptance.dart classroom-http-flutter-png-setup $_localConfigPath $_flutterPngApprovalFlag',
    );
    exitCode = 64;
    return;
  }
  final AcceptanceConfig config;
  try {
    final file = File(args[1]);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size > 65536 ||
        (!Platform.isWindows && stat.mode & 0x3f != 0)) {
      throw const ApiException(ApiFailure.configuration);
    }
    if (mode.isClassroomWrite &&
        await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw const ApiException(ApiFailure.configuration);
    }
    config = AcceptanceConfig.fromJson(
      jsonDecode(await file.readAsString()),
      protectedLoopback:
          args.length == 3 && args.last == '--protected-loopback',
      classroomHttp:
          mode.isClassroomWrite ||
          (args.length == 3 && args.last == '--$classroomHttpMode'),
    );
  } catch (_) {
    stderr.writeln(
      'Invalid local config. Use the sample schema and a private file (chmod 600 on macOS/Linux).',
    );
    exitCode = 78;
    return;
  }
  try {
    await runAcceptance(
      config,
      mode,
      approvedDisposableWrites:
          mode == AcceptanceMode.disposable || mode.isClassroomWrite,
      progress: stdout.writeln,
      classroomSessionJournal: switch (mode) {
        AcceptanceMode.classroomSession => File(
          'config/local/first-viewing-session.jsonl',
        ),
        AcceptanceMode.classroomRevocation => File(
          'config/local/revocation-acceptance.jsonl',
        ),
        AcceptanceMode.classroomPng => File(_pngJournalPath),
        AcceptanceMode.classroomFlutterPngSetup => File(_flutterPngJournalPath),
        _ => null,
      },
    );
  } on AcceptanceFailure catch (e) {
    stderr.writeln('FAIL: ${e.step}');
    exitCode = 1;
  } catch (_) {
    stderr.writeln('FAIL: Acceptance stopped before completion.');
    exitCode = 1;
  }
}
