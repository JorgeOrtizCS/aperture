part of 'api_acceptance.dart';

const _fixtureTitle = 'Aperture synthetic acceptance - first viewing session';
const _cameraDisabled = {
  'Enabled': false,
  'BlockPhones': false,
  'BlockMultiplePeople': false,
  'RequireViewer': false,
};
const _fixtureBody = {
  'Title': _fixtureTitle,
  'Body': 'Synthetic test text for Aperture viewing-session authorization and cleanup.',
  'MaxViews': 1,
  'RequireTrustedDevice': false,
  'ScreenshotRestriction': false,
  'CameraRestrictions': _cameraDisabled,
};

String _deviceGuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Separate from the app transport. Only the acceptance state machine below
/// can drive the additional routes.
class _ClassroomSessionTransport implements ApiTransport {
  final Uri base;
  final bool allowSenderChanges;
  final bool allowViewingSessions;
  final _client = HttpClient()..findProxy = (_) => 'DIRECT';
  static final _sessionRoute = RegExp(
    r'^api/content/(?:[1-9][0-9]*/sessions|sessions/[1-9][0-9]*/(?:check|end))$',
  );
  static final _senderChangeRoute = RegExp(
    r'^api/content/[1-9][0-9]*/(?:policy|revoke)$',
  );

  _ClassroomSessionTransport(
    AcceptanceConfig config, {
    this.allowSenderChanges = false,
    this.allowViewingSessions = true,
  }) : base = config.base {
    if (!config.usesClassroomHttp) {
      throw const ApiException(ApiFailure.configuration);
    }
  }

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final path = uri.path.substring(1);
    final allowed = switch ((method, path)) {
      ('GET', 'api/user/me' || 'api/content') => true,
      ('POST', 'api/auth/login' || 'api/auth/logout' || 'api/content') => true,
      ('POST', _) =>
        (allowViewingSessions && _sessionRoute.hasMatch(path)) ||
            (allowSenderChanges && _senderChangeRoute.hasMatch(path)),
      _ => false,
    };
    if (!allowed || uri != base.resolve(path)) {
      throw const ApiException(ApiFailure.configuration);
    }
    HttpClientRequest? request;
    var expired = false;
    try {
      return await (() async {
        HttpClient.enableTimelineLogging = false;
        request = await _client.openUrl(method, uri);
        if (expired) {
          request!.abort();
          throw const ApiException(ApiFailure.timeout);
        }
        request!
          ..followRedirects = false
          ..persistentConnection = false;
        headers.forEach(request!.headers.set);
        if (body != null) request!.add(utf8.encode(body));
        final response = await request!.close();
        final bytes = <int>[];
        await for (final part in response) {
          if (part.length > NativeApiTransport.maxBytes - bytes.length) {
            request!.abort();
            throw const ApiException(ApiFailure.malformed);
          }
          bytes.addAll(part);
        }
        return ApiReply(response.statusCode, utf8.decode(bytes));
      })().timeout(NativeApiTransport.classroomTimeout);
    } on TimeoutException {
      expired = true;
      request?.abort();
      throw const ApiException(ApiFailure.timeout);
    } on FormatException {
      throw const ApiException(ApiFailure.malformed);
    } on ApiException {
      rethrow;
    } on Object {
      throw const ApiException(ApiFailure.network);
    }
  }

  @override
  void close() => _client.close(force: true);
}

class _ClassroomSession {
  final AcceptanceConfig config;
  final ApiTransport transport;
  final void Function(String) progress;
  final File journal;
  final _tokens = <String, String>{};
  final _deviceKey = _deviceGuid();
  final _preexistingIds = <int>{};
  ({String token, int id})? _knownSession;

  _ClassroomSession(this.config, this.transport, this.progress, this.journal);

  Map<String, Object> get fixture => {
    ..._fixtureBody,
    'Recipient': config.recipient.username,
  };

  Future<void> _record(Map<String, Object> event) => journal.writeAsString(
    '${jsonEncode(event)}\n',
    mode: FileMode.append,
    flush: true,
  );

  Future<void> _reserveCreate() async {
    await journal.create(exclusive: true);
    if (!Platform.isWindows) {
      final chmod = await Process.run('chmod', ['600', journal.path]);
      _require(chmod.exitCode == 0 && (await journal.stat()).mode & 0x3f == 0);
    }
    await _record({'event': 'createAttempt', 'deviceGuid': _deviceKey});
  }

  Future<T> _step<T>(String label, Future<T> Function() action) async {
    try {
      final result = await action();
      progress('PASS: $label');
      return result;
    } on ApiException catch (e) {
      throw AcceptanceFailure('$label (${e.kind.name})');
    } on AcceptanceFailure {
      rethrow;
    } catch (_) {
      throw AcceptanceFailure(label);
    }
  }

  Future<ApiReply> _exchange(
    String label,
    String method,
    String path,
    String token, [
    Map<String, Object?>? body,
  ]) async {
    final reply = await transport.send(method, config.base.resolve(path), {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    }, body == null ? null : jsonEncode(body));
    progress(
      '$label: HTTP ${reply.status} (${_ClassroomStatusTransport._shape(reply.body)})',
    );
    return reply;
  }

  Future<ApiCredentials> _login(
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
    final auth = await api.login(account.username, account.password);
    _tokens[auth.token] = label;
    final me = await api.currentUser(auth.token);
    _require(auth.expiresAt.isAfter(DateTime.now().toUtc()));
    _require(me.id == auth.user.id && me.username == auth.user.username);
    _require(me.username == account.username);
    return auth;
  }

  Future<List<Map<String, dynamic>>> _fixtureRows(
    String label,
    String token, {
    bool baseline = false,
  }) async {
    final reply = await _exchange(label, 'GET', 'api/content', token);
    _require(reply.status == 200);
    final rows = (jsonDecode(reply.body) as List).map(apiObject);
    if (baseline) _preexistingIds.addAll(rows.map((row) => apiId(row['Id'])));
    return rows.where((row) => row['Title'] == fixture['Title']).toList();
  }

  void _verifyRow(
    Map<String, dynamic> row,
    int contentId, {
    required bool mine,
    required String status,
    required String policy,
  }) {
    _require(
      row['Id'] == contentId &&
          row['Mine'] == mine &&
          row['Owner'] == config.sender.username,
    );
    _require(row['Recipient'] == (mine ? config.recipient.username : null));
    _require(row['Status'] == status && row['PolicyStatus'] == policy);
    _require(
      row['MaxViews'] == fixture['MaxViews'] &&
          row['RequireTrustedDevice'] == false &&
          row['ScreenshotRestriction'] == false,
    );
    _require(
      [
        'StartTime',
        'ExpiresAt',
        'Latitude',
        'Longitude',
        'RadiusMeters',
        'RequiredLocation',
        'AllowedCountry',
        'AllowedRegion',
        'AllowedCity',
        'Body',
        'FileDataBase64',
      ].every((field) => row[field] == null),
    );
    if (row['CameraRestrictions'] != null) {
      final camera = apiObject(row['CameraRestrictions']);
      _require(_cameraDisabled.keys.every((field) => camera[field] == false));
    }
  }

  Future<void> _verifyListings(
    String sender,
    String recipient,
    int contentId, {
    String status = 'Active',
    String policy = 'Active',
  }) async {
    final sent = await _fixtureRows('Sender fixture list', sender);
    final received = await _fixtureRows('Recipient fixture list', recipient);
    _verifyRow(
      sent.single,
      contentId,
      mine: true,
      status: status,
      policy: policy,
    );
    _verifyRow(
      received.single,
      contentId,
      mine: false,
      status: status,
      policy: policy,
    );
  }

  Future<void> _reconcileCreate(String sender, String recipient) async {
    for (final (label, token) in [
      ('Sender', sender),
      ('Recipient', recipient),
    ]) {
      try {
        final rows = await _fixtureRows('$label create reconciliation', token);
        progress(
          '$label create reconciliation: ${rows.length} exact-title matches',
        );
      } catch (_) {
        progress('$label create reconciliation could not be completed');
      }
    }
  }

  Future<int> _create(String sender, String recipient) async {
    await _reserveCreate();
    int contentId;
    try {
      final reply = await _exchange(
        'Create synthetic share',
        'POST',
        'api/content',
        sender,
        fixture,
      );
      _require(reply.status == 200);
      contentId = apiId(apiObject(jsonDecode(reply.body))['id']);
      _require(!_preexistingIds.contains(contentId));
    } catch (_) {
      await _reconcileCreate(sender, recipient);
      rethrow;
    }
    await _record({'event': 'shareCreated', 'contentId': contentId});
    progress('Share ID recorded in the private journal');
    return contentId;
  }

  Future<ApiReply> _open(String label, String token, int contentId) async {
    final reply = await _exchange(
      label,
      'POST',
      'api/content/$contentId/sessions',
      token,
      {
        'DeviceKey': _deviceKey,
        'CameraPolicyVersion': ApiService.cameraPolicyVersion,
      },
    );
    if (reply.body.trim().isNotEmpty) {
      // A malformed or denied open can still disclose a session needing cleanup.
      // Only a positive ID returned by this fixture's open is tracked.
      final Object? value;
      try {
        value = jsonDecode(reply.body);
      } on FormatException {
        return reply;
      }
      final id =
          value is Map<String, dynamic> &&
              (reply.status == 200 || value['AccessGranted'] == true)
          ? value['SessionId']
          : null;
      if (id is int && id > 0) _knownSession = (token: token, id: id);
    }
    return reply;
  }

  Future<int> _openRecipient(String label, String token, int contentId) async {
    await _record({'event': 'recipientOpenAttempt'});
    final reply = await _open(label, token, contentId);
    final session = _knownSession;
    if (session != null) {
      await _record({'event': 'sessionObserved', 'sessionId': session.id});
    }
    return apiId(_grant(reply).sessionId);
  }

  ApiAccessDecision _grant(ApiReply reply) {
    _require(reply.status == 200);
    final json = apiObject(jsonDecode(reply.body));
    final decision = ApiAccessDecision.fromJson(json);
    _require(
      decision.granted &&
          !decision.suspended &&
          !decision.ended &&
          !decision.deviceVerified &&
          json['FileDataBase64'] == null,
    );
    if (json['FileType'] != null) _require(json['FileType'] == 'text/plain');
    return decision;
  }

  Future<void> _endKnownSession(String label, {bool cleanup = false}) async {
    final session = _knownSession!;
    // Dispatch at most once, including when acknowledgement is ambiguous.
    _knownSession = null;
    final reply = await _exchange(
      label,
      'POST',
      'api/content/sessions/${session.id}/end',
      session.token,
    );
    if (cleanup && reply.status == 404) {
      await _record({'event': 'sessionUnavailableAtCleanup'});
    } else {
      _require(
        reply.status == 200 &&
            apiObject(jsonDecode(reply.body))['success'] == true,
      );
      await _record({'event': 'sessionEnded'});
    }
  }

  Future<void> _run() async {
    if (await FileSystemEntity.type(journal.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const AcceptanceFailure(
        'Private journal already exists. Reconcile the previous attempt before another run',
      );
    }
    await _step('Private journal directory is available', () async {
      final parent = await journal.parent.stat();
      _require(parent.type == FileSystemEntityType.directory);
      _require(Platform.isWindows || parent.mode & 0x3f == 0);
    });

    final sender = await _step(
      'Verify sender identity',
      () => _login('Sender', config.sender),
    );
    final recipient = await _step(
      'Verify recipient identity',
      () => _login('Recipient', config.recipient),
    );
    _require(
      sender.user.id != recipient.user.id && sender.token != recipient.token,
    );
    await _step('Fixture is absent before the create', () async {
      final sent = await _fixtureRows(
        'Sender baseline list',
        sender.token,
        baseline: true,
      );
      final received = await _fixtureRows(
        'Recipient baseline list',
        recipient.token,
        baseline: true,
      );
      _require(sent.isEmpty && received.isEmpty);
    });
    final contentId = await _step(
      'Create exactly one fixture',
      () => _create(sender.token, recipient.token),
    );
    await _step(
      'Both accounts list the newly created active fixture',
      () => _verifyListings(sender.token, recipient.token, contentId),
    );
    await _exercise(sender.token, recipient.token, contentId);
  }

  Future<void> _exercise(String sender, String recipient, int contentId) async {
    await _step('Sender open denied', () async {
      final reply = await _open('Sender open', sender, contentId);
      _require(reply.status == 404);
    });
    final sessionId = await _step(
      'Recipient granted one session',
      () => _openRecipient('Recipient open', recipient, contentId),
    );
    final check = 'api/content/sessions/$sessionId/check';
    await _step('Recipient authorized on the same session', () async {
      final reply = await _exchange(
        'Recipient check',
        'POST',
        check,
        recipient,
        {},
      );
      _require(_grant(reply).sessionId == sessionId);
    });
    await _step(
      'Recipient session ended',
      () => _endKnownSession('Recipient end'),
    );
    await _step('Ended session cannot be reused', () async {
      final reply = await _exchange(
        'Recipient post-end check',
        'POST',
        check,
        recipient,
        {},
      );
      _require(reply.status == 403);
      final json = apiObject(jsonDecode(reply.body));
      _require(
        json['AccessGranted'] == false &&
            json['SessionEnded'] == true &&
            json['Body'] == null &&
            json['FileDataBase64'] == null,
      );
      await _record({'event': 'endedSessionRejected'});
    });
  }

  Future<void> run() async {
    progress('Insecure HTTP — Synthetic Classroom Acceptance');
    var cleanupFailed = false;
    try {
      await _step('One-share classroom session test', _run);
    } finally {
      try {
        if (_knownSession != null) {
          try {
            await _endKnownSession('Bounded session cleanup', cleanup: true);
          } catch (_) {
            cleanupFailed = true;
            progress('WARNING: Session cleanup could not be confirmed');
          }
        }
        for (final entry in _tokens.entries) {
          try {
            final reply = await _exchange(
              '${entry.value} logout',
              'POST',
              'api/auth/logout',
              entry.key,
            );
            _require(
              reply.status == 200 &&
                  apiObject(jsonDecode(reply.body))['success'] == true,
            );
          } catch (_) {
            cleanupFailed = true;
            progress('WARNING: ${entry.value} logout could not be confirmed');
          }
        }
      } finally {
        transport.close();
      }
    }
    if (cleanupFailed) {
      throw const AcceptanceFailure('Cleanup could not be confirmed');
    }
  }
}
