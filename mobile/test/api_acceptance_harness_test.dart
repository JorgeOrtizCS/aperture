import 'dart:convert';
import 'dart:io';

import 'package:aperture/models/api_models.dart';
import 'package:aperture/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/api_acceptance.dart';
import '../tool/flutter_png_fixture_spec.dart';
import 'support/api_fake.dart';

const _sender = classroomFixtureSender;
const _recipient = classroomFixtureRecipient;
const _classroomBase = 'http://classroom.fixture.invalid/';
const _deviceKey = '11111111-1111-4111-8111-111111111111';
const _sharedItemId = 7;
const _pngPath = 'docs/week11/task11-3/Aperture-Demo.png';

/// A socket-free, stateful source-contract server. It independently maintains
/// tokens, ownership and session lifetime to exercise the acceptance workflow.
class ContractServer implements ApiTransport {
  final calls = <ApiCall>[];
  final tokens = <String, String>{};
  final contents = <int, Map<String, Object?>>{};
  final sessions = <int, int>{};
  final terminatedSessions = <int>{};
  final devices = <(String, String), bool>{};
  final policies = <int, String>{};
  final revoked = <int>{};
  var sequence = 0;
  bool closed = false, rejectCheck = false, acceptUnsupported = false;
  bool badAnonymousResponse = false;
  bool misreportDeviceTrust = false, resumeRestoresSessions = false;

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final call = ApiCall(method, uri, headers, body);
    calls.add(call);
    final input = body == null ? <String, dynamic>{} : jsonDecode(body);
    if (uri.path == '/api/auth/login') {
      final username = input['Username'];
      if (username != _sender && username != _recipient) {
        return jsonReply({'Success': false}, 401);
      }
      final token = 'synthetic-${++sequence}';
      tokens[token] = username;
      return jsonReply({
        'Success': true,
        'Token': token,
        'ExpiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        'User': {'Id': username == _sender ? 1 : 2, 'Username': username},
      });
    }
    final token = headers['Authorization']?.substring(7);
    final user = tokens[token];
    if (user == null) {
      return jsonReply(
        badAnonymousResponse
            ? {}
            : {'success': false, 'message': 'Authentication required.'},
        401,
      );
    }
    if (uri.path == '/api/auth/logout') {
      tokens.remove(token);
      return jsonReply({'success': true});
    }
    if (uri.path == '/api/user/me') {
      return jsonReply({
        'success': true,
        'user': {'id': user == _sender ? 1 : 2, 'username': user},
      });
    }
    if (uri.path == '/api/content/capabilities') {
      return jsonReply({'CameraPolicyVersion': 1});
    }
    if (uri.path == '/api/devices' && method == 'POST') {
      final key = input['DeviceKey'];
      final name = input['DeviceName'];
      if (key != _deviceKey || name is! String || name.trim().isEmpty) {
        return const ApiReply(400, '');
      }
      return jsonReply({
        'trusted': devices.putIfAbsent((user, _deviceKey), () => false),
      });
    }
    if (uri.path == '/api/content') {
      if (method == 'GET') {
        return jsonReply([
          for (final entry in contents.entries)
            if (entry.value['Recipient'] == user || user == _sender)
              {
                ...contentJson(
                  id: entry.key,
                  mine: user == _sender,
                  title:
                      entry.value['Title'] as String? ?? 'Synthetic metadata',
                ),
                'Owner': _sender,
                'Recipient': user == _sender ? entry.value['Recipient'] : null,
                'Status': revoked.contains(entry.key) ? 'Revoked' : 'Active',
                'PolicyStatus': policies[entry.key] ?? 'Active',
                if (entry.value['MaxViews'] != null) ...{
                  'MaxViews': entry.value['MaxViews'],
                  'RequireTrustedDevice': entry.value['RequireTrustedDevice'],
                  'ScreenshotRestriction': entry.value['ScreenshotRestriction'],
                },
              },
        ]);
      }
      final id = ++sequence;
      contents[id] = Map<String, Object?>.from(input);
      return jsonReply({'id': id});
    }
    final path = uri.path.split('/');
    if (path[3] == 'sessions') {
      final id = int.parse(path[4]);
      if (user != _recipient) return const ApiReply(404, '');
      final content = sessions[id];
      if (content == null) {
        return jsonReply(accessJson(granted: false, ended: true), 403);
      }
      if (terminatedSessions.contains(id)) {
        return const ApiReply(404, '');
      }
      if (path.last == 'end') {
        sessions.remove(id);
        return jsonReply({'success': true});
      }
      if (rejectCheck) return jsonReply({}, 500);
      return _grant(content, id, user);
    }
    final id = int.parse(path[3]);
    if (!contents.containsKey(id)) return const ApiReply(404, '');
    if (path.last == 'sessions') {
      if (user != _recipient || revoked.contains(id)) {
        return const ApiReply(404, '');
      }
      final device = input['DeviceKey'];
      final classroom = contents[id]!['MaxViews'] != null;
      final validDevice = classroom
          ? device is String &&
                RegExp(
                  r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
                ).hasMatch(device)
          : device == _deviceKey;
      if (!validDevice || input['CameraPolicyVersion'] != 0) {
        return const ApiReply(400, '');
      }
      final content = contents[id]!;
      if (policies[id] == 'Paused' ||
          (!acceptUnsupported &&
              (content['ScreenshotRestriction'] == true ||
                  (content['CameraRestrictions'] as Map?)?['Enabled'] ==
                      true))) {
        return jsonReply({
          'AccessGranted': false,
          'SessionId': 0,
          'Suspended': false,
          'SessionEnded': false,
        }, 403);
      }
      final sid = ++sequence;
      sessions[sid] = id;
      return _grant(id, sid, user);
    }
    if (user != _sender) return const ApiReply(404, '');
    if (path.last == 'policy') {
      policies[id] = input['Status'];
      if (policies[id] == 'Paused') {
        _terminateSessions(id);
      } else if (resumeRestoresSessions) {
        terminatedSessions.removeWhere((session) => sessions[session] == id);
      }
      return jsonReply({'status': input['Status']});
    }
    if (path.last == 'revoke') {
      revoked.add(id);
      _terminateSessions(id);
      return jsonReply({'success': true});
    }
    throw StateError('Unknown synthetic route.');
  }

  void _terminateSessions(int content) {
    terminatedSessions.addAll(
      sessions.entries
          .where((entry) => entry.value == content)
          .map((entry) => entry.key),
    );
  }

  ApiReply _grant(int content, int session, String recipient) {
    final decision = accessJson(id: session)
      ..['DeviceVerified'] =
          misreportDeviceTrust || devices[(recipient, _deviceKey)] == true;
    final png = contents[content]?['FileDataBase64'];
    if (png != null) {
      decision.remove('Body');
      decision['Title'] = contents[content]!['Title'];
      decision['FileType'] = 'image/png';
      decision['FileDataBase64'] = png;
    }
    return jsonReply(decision);
  }

  @override
  void close() => closed = true;
}

AcceptanceConfig configuration({
  String base = 'https://fixture.invalid/',
  bool protectedLoopback = false,
  bool classroomHttp = false,
  int? existingShareId,
  String? deviceKey = _deviceKey,
}) => AcceptanceConfig.fromJson(
  {
    'APERTURE_ACCEPTANCE_ENVIRONMENT': 'approved-non-production',
    'APERTURE_API_BASE_URL': base,
    'APERTURE_DEVICE_KEY': deviceKey,
    'APERTURE_ACCEPTANCE_CONTENT_ID': existingShareId,
    if (classroomHttp) ...{
      'APERTURE_CLASSROOM_APPROVED_ORIGIN': _classroomBase,
      'APERTURE_CLASSROOM_SENDER': _sender,
      'APERTURE_CLASSROOM_RECIPIENT': _recipient,
      'APERTURE_CLASSROOM_ARCHIVED_PNG_IDS': '900010,900011,900012',
    },
    'sender': {'username': _sender, 'password': 'sample'},
    'recipient': {'username': _recipient, 'password': 'sample'},
  },
  protectedLoopback: protectedLoopback,
  classroomHttp: classroomHttp,
);

void main() {
  const classroomBase = _classroomBase;

  test(
    'classroom smoke requires opt-in, the approved origin and test accounts',
    () {
      expect(
        configuration(
          base: classroomBase,
          classroomHttp: true,
        ).usesClassroomHttp,
        isTrue,
      );
      expect(
        () => configuration(base: classroomBase),
        throwsA(isA<ApiException>()),
      );
      for (final base in [
        'https://classroom.fixture.invalid/',
        'http://classroom.fixture.invalid.other.invalid/',
        'http://classroom.fixture.invalid:8080/',
        'http://classroom.fixture.invalid/other/',
        'http://127.0.0.1/',
      ]) {
        expect(
          () => configuration(base: base, classroomHttp: true),
          throwsA(isA<ApiException>()),
        );
      }
      for (final override in [
        {'APERTURE_ACCEPTANCE_ENVIRONMENT': 'production'},
        {'APERTURE_CLASSROOM_APPROVED_ORIGIN': ''},
        {'APERTURE_CLASSROOM_ARCHIVED_PNG_IDS': 'invalid'},
        {
          'recipient': {'username': 'third-account', 'password': 'sample'},
        },
      ]) {
        expect(
          () => AcceptanceConfig.fromJson({
            'APERTURE_ACCEPTANCE_ENVIRONMENT': 'approved-non-production',
            'APERTURE_API_BASE_URL': classroomBase,
            'APERTURE_CLASSROOM_APPROVED_ORIGIN': classroomBase,
            'APERTURE_CLASSROOM_SENDER': _sender,
            'APERTURE_CLASSROOM_RECIPIENT': _recipient,
            'sender': {'username': _sender, 'password': 'sample'},
            'recipient': {'username': _recipient, 'password': 'sample'},
            ...override,
          }, classroomHttp: true),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );

  test(
    'classroom smoke uses independent sessions and reports redacted statuses',
    () async {
      final server = ContractServer();
      final output = <String>[];
      await runAcceptance(
        configuration(base: classroomBase, classroomHttp: true),
        AcceptanceMode.smoke,
        approvedDisposableWrites: false,
        progress: output.add,
        transport: server,
      );
      expect(server.calls.map((call) => '${call.method} ${call.uri.path}'), [
        'GET /api/content',
        for (var account = 0; account < 2; account++) ...[
          'POST /api/auth/login',
          'GET /api/user/me',
          'GET /api/content',
          'POST /api/auth/logout',
          'GET /api/user/me',
        ],
      ]);
      expect(output.join('\n'), contains('after logout: HTTP 401'));
      expect(output.join('\n'), contains('empty JSON array'));
      expect(output.join('\n'), isNot(contains('sample')));
      expect(output.join('\n'), isNot(contains('synthetic-1')));
      expect(output.join('\n'), isNot(contains('synthetic-2')));
      expect(server.tokens, isEmpty);
      expect(server.closed, isTrue);
    },
  );

  test('classroom smoke rejects unauthorized login and never repeats a failed logout', () async {
    final server = _RejectedClassroomServer();
    final output = <String>[];
    await expectLater(
      runAcceptance(
        configuration(base: classroomBase, classroomHttp: true),
        AcceptanceMode.smoke,
        approvedDisposableWrites: false,
        progress: output.add,
        transport: server,
      ),
      throwsA(isA<AcceptanceFailure>()),
    );
    expect(
      server.calls.where((call) => call.uri.path == '/api/auth/login'),
      hasLength(2),
    );
    expect(
      server.calls.where((call) => call.uri.path == '/api/auth/logout'),
      hasLength(1),
    );
    final log = output.join('\n');
    expect(
      log,
      contains('Sender POST /api/auth/login: HTTP 401 (JSON rejection)'),
    );
    expect(log, contains('Recipient POST /api/auth/logout: HTTP 503'));
    expect(log, isNot(contains('secret-response-marker')));
  });

  test('classroom rejects sharing workflows before any request', () async {
    for (final mode in [
      AcceptanceMode.existingShare,
      AcceptanceMode.disposable,
    ]) {
      final server = ContractServer();
      await expectLater(
        runAcceptance(
          configuration(base: classroomBase, classroomHttp: true),
          mode,
          approvedDisposableWrites: true,
          progress: (_) {},
          transport: server,
        ),
        throwsA(isA<AcceptanceFailure>()),
      );
      expect(server.calls, isEmpty);
    }
  });

  group('isolated classroom session', () {
    late File journal;
    final config = configuration(
      base: classroomBase,
      classroomHttp: true,
      deviceKey: null,
    );
    final output = <String>[];

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp(
        'classroom-session-test-',
      );
      if (!Platform.isWindows) {
        final mode = await Process.run('chmod', ['700', dir.path]);
        expect(mode.exitCode, 0);
      }
      addTearDown(() => dir.delete(recursive: true));
      journal = File('${dir.path}/journal.jsonl');
      output.clear();
    });

    Future<void> run(
      ContractServer server, {
      bool approved = true,
      AcceptanceConfig? scope,
    }) => runAcceptance(
      scope ?? config,
      AcceptanceMode.classroomSession,
      approvedDisposableWrites: approved,
      progress: output.add,
      transport: server,
      classroomSessionJournal: journal,
    );

    test(
      'rejects missing opt-in or a configured existing share before network',
      () async {
        final server = ContractServer();
        await expectLater(
          run(server, approved: false),
          throwsA(isA<AcceptanceFailure>()),
        );
        await expectLater(
          run(
            server,
            scope: configuration(
              base: classroomBase,
              classroomHttp: true,
              existingShareId: 7,
              deviceKey: null,
            ),
          ),
          throwsA(isA<AcceptanceFailure>()),
        );
        expect(server.calls, isEmpty);
        expect(await journal.exists(), isFalse);
      },
    );

    test(
      'creates one exact fixture, ends one session and prevents reruns',
      () async {
        final server = ContractServer();
        await run(server);
        expect(server.contents, hasLength(1));
        expect(server.devices, isEmpty);
        expect(server.revoked, isEmpty);
        expect(server.sessions, isEmpty);
        expect(server.tokens, isEmpty);
        final fixture = server.contents.values.single;
        expect(fixture, {
          'Title': 'Aperture synthetic acceptance - first viewing session',
          'Body': 'Synthetic test text for Aperture viewing-session authorization and cleanup.',
          'Recipient': _recipient,
          'MaxViews': 1,
          'RequireTrustedDevice': false,
          'ScreenshotRestriction': false,
          'CameraRestrictions': {
            'Enabled': false,
            'BlockPhones': false,
            'BlockMultiplePeople': false,
            'RequireViewer': false,
          },
        });
        final paths = server.calls.map((call) => call.uri.path);
        expect(paths.where((p) => p.endsWith('/sessions')), hasLength(2));
        expect(paths.where((p) => p.endsWith('/check')), hasLength(2));
        expect(paths.where((p) => p.endsWith('/end')), hasLength(1));
        final evidence = await journal.readAsString();
        expect(evidence, contains('endedSessionRejected'));
        expect(
          evidence,
          contains('"contentId":${server.contents.keys.single}'),
        );
        expect(evidence, isNot(contains('synthetic-')));
        if (!Platform.isWindows) expect((await journal.stat()).mode & 0x3f, 0);
        final log = output.join('\n');
        expect(log, contains('Recipient post-end check: HTTP 403'));
        expect(log, isNot(contains(fixture['Body'] as String)));
        expect(log, isNot(contains('/sessions/')));
        expect(log, isNot(contains('synthetic-')));
        final rerun = ContractServer();
        await expectLater(run(rerun), throwsA(isA<AcceptanceFailure>()));
        expect(rerun.calls, isEmpty);
      },
    );

    test(
      'reconciles a lost create acknowledgement without another POST',
      () async {
        final server = _UnconfirmedClassroomCreate();
        await expectLater(run(server), throwsA(isA<AcceptanceFailure>()));
        expect(server.contents, hasLength(1));
        expect(
          server.calls.where(
            (call) => call.method == 'POST' && call.uri.path == '/api/content',
          ),
          hasLength(1),
        );
        expect(
          server.calls.where((call) => call.uri.path.endsWith('/sessions')),
          isEmpty,
        );
        expect(
          output.join('\n'),
          contains('Sender create reconciliation: 1 exact-title matches'),
        );
        expect(
          output.join('\n'),
          contains('Recipient create reconciliation: 1 exact-title matches'),
        );
        expect(await journal.readAsString(), isNot(contains('shareCreated')));
        expect(server.tokens, isEmpty);
      },
    );

    test('ends a known session once when its check fails', () async {
      final server = ContractServer()..rejectCheck = true;
      await expectLater(run(server), throwsA(isA<AcceptanceFailure>()));
      expect(server.sessions, isEmpty);
      expect(
        server.calls.where((call) => call.uri.path.endsWith('/end')),
        hasLength(1),
      );
      expect(output.join('\n'), contains('Bounded session cleanup: HTTP 200'));
      expect(output.join('\n'), isNot(contains('Recipient post-end check')));
    });
  });

  group('isolated classroom hosted PNG acceptance', () {
    late File journal;
    final output = <String>[];
    final config = configuration(
      base: classroomBase,
      classroomHttp: true,
      deviceKey: null,
    );

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('classroom-png-test-');
      addTearDown(() => dir.delete(recursive: true));
      journal = File('${dir.path}/png.jsonl');
      output.clear();
    });

    Future<void> run(
      ContractServer server, {
      bool approved = true,
      AcceptanceMode mode = AcceptanceMode.classroomPng,
    }) => runAcceptance(
      config,
      mode,
      approvedDisposableWrites: approved,
      progress: output.add,
      transport: server,
      classroomSessionJournal: journal,
    );

    test('Flutter setup leaves the only view unused', () async {
      const mode = AcceptanceMode.classroomFlutterPngSetup;
      final server = ContractServer()
        ..contents[900012] = {'Title': 'previous PNG', 'Recipient': _recipient};
      await expectLater(
        run(server, mode: mode, approved: false),
        throwsA(isA<AcceptanceFailure>()),
      );
      expect(server.calls, isEmpty);
      await run(server, mode: mode);
      final id = server.contents.keys.singleWhere((id) => id != 900012);
      final fixture = server.contents[id]!;
      expect(fixture['Title'], flutterPngFixtureTitle);
      expect(fixture['MaxViews'], 1);
      expect(fixture['FileType'], 'image/png');
      expect(fixture['Recipient'], _recipient);
      expect(
        fixture['FileDataBase64'],
        base64Encode(await File(_pngPath).readAsBytes()),
      );
      expect(server.contents[900012], {
        'Title': 'previous PNG',
        'Recipient': _recipient,
      });
      expect(server.sessions, isEmpty);
      expect(
        server.calls
            .where((call) => call.method == 'POST')
            .map((call) => call.uri.path),
        [
          '/api/auth/login',
          '/api/auth/login',
          '/api/content',
          '/api/auth/logout',
          '/api/auth/logout',
        ],
      );
      final rows = (await journal.readAsLines()).map(
        (line) => apiObject(jsonDecode(line)),
      );
      expect(
        rows.singleWhere((row) => row['event'] == 'fixtureReadyForFlutter'),
        {
          'event': 'fixtureReadyForFlutter',
          'contentId': id,
          'title': flutterPngFixtureTitle,
          'maxViews': 1,
        },
      );
      final calls = server.calls.length;
      await expectLater(
        run(server, mode: mode),
        throwsA(isA<AcceptanceFailure>()),
      );
      expect(server.calls, hasLength(calls));
    });

    test('one exact PNG, one session, and both kinds of denial', () async {
      final server = ContractServer()
        ..contents[900] = {'Title': 'prior fixture', 'Recipient': _recipient};
      await expectLater(
        run(server, approved: false),
        throwsA(isA<AcceptanceFailure>()),
      );
      expect(server.calls, isEmpty);
      await run(server);

      final id = server.contents.keys.singleWhere((id) => id != 900);
      final png = base64Encode(await File(_pngPath).readAsBytes());
      expect(server.contents[id], {
        'Title': 'Aperture synthetic classroom acceptance PNG',
        'Recipient': _recipient,
        'FileType': 'image/png',
        'FileDataBase64': png,
        'MaxViews': 2,
        'RequireTrustedDevice': false,
        'ScreenshotRestriction': false,
        'CameraRestrictions': {
          'Enabled': false,
          'BlockPhones': false,
          'BlockMultiplePeople': false,
          'RequireViewer': false,
        },
      });
      expect(server.contents[900], {
        'Title': 'prior fixture',
        'Recipient': _recipient,
      });
      final evidence = await journal.readAsString();
      final events = const LineSplitter()
          .convert(evidence)
          .map((line) => apiObject(jsonDecode(line)));
      final session = events.singleWhere(
        (entry) => entry['event'] == 'sessionObserved',
      )['sessionId'];
      expect(
        server.calls
            .where(
              (call) =>
                  call.uri.path.startsWith('/api/content/') ||
                  (call.method == 'POST' && call.uri.path == '/api/content'),
            )
            .map((call) => call.uri.path),
        [
          '/api/content',
          '/api/content/$id/sessions',
          '/api/content/$id/sessions',
          '/api/content/sessions/$session/check',
          '/api/content/sessions/$session/end',
          '/api/content/sessions/$session/check',
        ],
      );
      expect(events.singleWhere((entry) => entry['event'] == 'pngVerified'), {
        'event': 'pngVerified',
        'status': 200,
        'mime': 'image/png',
        'byteSize': 986,
        'sha256':
            '4afc448186f1260fc52d84be9f7273e6b4243ac3d32b541ad5921cddd1eb524f',
      });
      expect('$evidence\n${output.join('\n')}', isNot(contains(png)));
      expect(server.sessions, isEmpty);
      expect(server.tokens, isEmpty);
      final calls = server.calls.length;
      await expectLater(run(server), throwsA(isA<AcceptanceFailure>()));
      expect(server.calls, hasLength(calls));
    });

    for (final defect in ['checksum', 'mime', 'content ID', 'denial payload']) {
      test(
        'rejects $defect, closes known session and never creates again',
        () async {
          final server = _WrongPngGrant(defect);
          await expectLater(run(server), throwsA(isA<AcceptanceFailure>()));
          expect(server.contents, hasLength(1));
          expect(server.sessions, isEmpty);
          expect(server.tokens, isEmpty);
          expect(
            output.join('\n'),
            contains('Bounded session cleanup: HTTP 200'),
          );
          expect(
            output.join('\n'),
            isNot(contains('Recipient post-end check')),
          );
          final calls = server.calls.length;
          await expectLater(run(server), throwsA(isA<AcceptanceFailure>()));
          expect(server.calls, hasLength(calls));
        },
      );
    }

    test('ambiguous create reconciles with lists and stops', () async {
      final server = _UnconfirmedClassroomCreate();
      await expectLater(run(server), throwsA(isA<AcceptanceFailure>()));
      expect(server.contents, hasLength(1));
      expect(server.sessions, isEmpty);
      expect(output.join('\n'), contains('Sender create reconciliation'));
      expect(output.join('\n'), contains('Recipient create reconciliation'));
      final calls = server.calls.length;
      await expectLater(run(server), throwsA(isA<AcceptanceFailure>()));
      expect(server.calls, hasLength(calls));
    });
  });

  group('isolated classroom revocation', () {
    late File journal;
    final output = <String>[];
    final scope = configuration(
      base: classroomBase,
      classroomHttp: true,
      deviceKey: null,
    );

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('revocation-test-');
      addTearDown(() => dir.delete(recursive: true));
      journal = File('${dir.path}/revocation.jsonl');
      output.clear();
    });

    Future<void> run(ContractServer server, {bool approved = true}) =>
        runAcceptance(
          scope,
          AcceptanceMode.classroomRevocation,
          approvedDisposableWrites: approved,
          progress: output.add,
          transport: server,
          classroomSessionJournal: journal,
        );

    test(
      'requires opt-in and refuses any existing journal before I/O',
      () async {
        final server = ContractServer();
        await expectLater(
          run(server, approved: false),
          throwsA(isA<AcceptanceFailure>()),
        );
        expect(await journal.exists(), isFalse);
        await journal.create();
        await expectLater(run(server), throwsA(isA<AcceptanceFailure>()));
        expect(server.calls, isEmpty);
      },
    );

    test(
      'targets only the new fixture, with two distinct sessions in order',
      () async {
        final server = ContractServer()
          ..contents[900] = {'Title': 'prior fixture', 'Recipient': _recipient};
        await run(server);
        final id = server.revoked.single;
        final fixture = server.contents[id]!;
        final (first, second) = (
          server.sessions.keys.first,
          server.sessions.keys.last,
        );
        expect(first, isNot(second));
        expect(server.terminatedSessions, {first, second});
        expect(server.policies[900], isNull);
        expect(server.devices, isEmpty);
        expect(server.tokens, isEmpty);
        expect(fixture, {
          'Title': 'Aperture synthetic acceptance - pause resume revoke',
          'Body': 'Synthetic text for pause, resume, session replacement, and revocation acceptance.',
          'Recipient': _recipient,
          'MaxViews': 2,
          'RequireTrustedDevice': false,
          'ScreenshotRestriction': false,
          'CameraRestrictions': {
            'Enabled': false,
            'BlockPhones': false,
            'BlockMultiplePeople': false,
            'RequireViewer': false,
          },
        });
        expect(
          server.calls
              .where(
                (call) =>
                    call.method == 'POST' &&
                    call.uri.path.startsWith('/api/content'),
              )
              .map((call) => (call.uri.path, (call.json as Map?)?['Status'])),
          [
            ('/api/content', null),
            ('/api/content/$id/sessions', null),
            ('/api/content/$id/policy', 'Paused'),
            ('/api/content/sessions/$first/check', null),
            ('/api/content/$id/policy', 'Active'),
            ('/api/content/sessions/$first/check', null),
            ('/api/content/$id/sessions', null),
            ('/api/content/$id/revoke', null),
            ('/api/content/sessions/$second/check', null),
            ('/api/content/$id/sessions', null),
          ],
        );
        final log = output.join('\n');
        expect(log, contains('Both listings confirm revoked access'));
        for (final secret in [
          fixture['Body'],
          'SYNTHETIC PAYLOAD',
          'synthetic-1',
          'sample',
          '/sessions/',
        ]) {
          expect(log, isNot(contains(secret as String)));
        }
        final evidence = await journal.readAsString();
        expect(evidence, contains('revokedListingsVerified'));
        expect(evidence, isNot(contains(fixture['Body'] as String)));
      },
    );

    test(
      'refuses restored sessions and ends the known active session once',
      () async {
        final server = ContractServer()..resumeRestoresSessions = true;
        await expectLater(run(server), throwsA(isA<AcceptanceFailure>()));
        expect(server.revoked, isEmpty);
        expect(server.sessions, isEmpty);
        expect(server.tokens, isEmpty);
        expect(
          server.calls.where((call) => call.uri.path.endsWith('/end')),
          hasLength(1),
        );
        expect(output.join('\n'), isNot(contains('Second recipient open')));
      },
    );

    test('rejects payload-bearing denials and skips resume', () async {
      final server = _RevocationContractServer(denialPayload: true);
      await expectLater(run(server), throwsA(isA<AcceptanceFailure>()));
      expect(server.policies.values, ['Paused']);
      expect(server.revoked, isEmpty);
      expect(
        server.calls.where((call) => call.uri.path.endsWith('/end')),
        hasLength(1),
      );
      expect(output.join('\n'), isNot(contains('private denial payload')));
    });

    for (final lost in ['create', 'pause', 'resume', 'revoke']) {
      test(
        'reconciles ambiguous $lost without retry or dependent writes',
        () async {
          final server = _RevocationContractServer(lost: lost);
          await expectLater(run(server), throwsA(isA<AcceptanceFailure>()));
          expect(server.contents, hasLength(1));
          expect(server.tokens, isEmpty);
          final writes = server.calls
              .where(
                (call) =>
                    call.method == 'POST' &&
                    call.uri.path.startsWith('/api/content'),
              )
              .map((call) => call.uri.path.split('/').last)
              .toList();
          expect(writes, [
            'content',
            if (lost != 'create') ...['sessions', 'policy'],
            if (lost == 'resume' || lost == 'revoke') 'check',
            if (lost == 'resume' || lost == 'revoke') 'policy',
            if (lost == 'revoke') ...['check', 'sessions', 'revoke'],
            if (lost == 'pause' || lost == 'revoke') 'end',
          ]);
          expect(output.join('\n'), contains('reconciliation'));
        },
      );
    }
  });

  test(
    'disposable mode requires explicit approval before even authentication',
    () async {
      final server = ContractServer();
      await expectLater(
        runAcceptance(
          configuration(),
          AcceptanceMode.disposable,
          approvedDisposableWrites: false,
          progress: (_) {},
          transport: server,
        ),
        throwsA(isA<AcceptanceFailure>()),
      );
      expect(server.calls, isEmpty);
    },
  );

  test(
    'config rejects HTTP, duplicate accounts and an unapproved environment',
    () {
      for (final entry in [
        {'APERTURE_API_BASE_URL': 'http://fixture.invalid/'},
        {'APERTURE_ACCEPTANCE_ENVIRONMENT': 'production'},
        {
          'recipient': {
            'username': _sender.toUpperCase(),
            'password': 'sample',
          },
        },
      ]) {
        expect(
          () => AcceptanceConfig.fromJson({
            'APERTURE_ACCEPTANCE_ENVIRONMENT': 'approved-non-production',
            'APERTURE_API_BASE_URL': 'https://fixture.invalid/',
            'sender': {'username': _sender, 'password': 'sample'},
            'recipient': {'username': _recipient, 'password': 'sample'},
            ...entry,
          }),
          throwsA(anything),
        );
      }
    },
  );

  test('protected loopback is explicit and limited to literal loopback', () {
    for (final url in [
      'http://localhost:8787/',
      'http://10.0.2.2:8787/',
      'http://192.168.1.2:8787/',
      'http://fixture.invalid/',
      'https://127.0.0.1:8787/',
    ]) {
      expect(
        () => configuration(base: url, protectedLoopback: true),
        throwsA(isA<ApiException>()),
      );
    }
    expect(
      () => configuration(base: 'http://127.0.0.1:8787/'),
      throwsA(isA<ApiException>()),
    );
    for (final host in ['127.0.0.1', '[::1]']) {
      expect(
        configuration(
          base: 'http://$host:8787/',
          protectedLoopback: true,
        ).usesLoopbackHttp,
        isTrue,
      );
    }
  });

  test('loopback refuses disposable writes before authentication', () async {
    final server = ContractServer();
    await expectLater(
      runAcceptance(
        configuration(base: 'http://127.0.0.1:8787/', protectedLoopback: true),
        AcceptanceMode.disposable,
        approvedDisposableWrites: true,
        progress: (_) {},
        transport: server,
      ),
      throwsA(isA<AcceptanceFailure>()),
    );
    expect(server.calls, isEmpty);
  });

  test(
    'existing share requires a content ID and nonzero device GUID',
    () async {
      for (final config in [
        configuration(),
        configuration(existingShareId: 7, deviceKey: null),
        configuration(
          existingShareId: 7,
          deviceKey: '00000000-0000-0000-0000-000000000000',
        ),
      ]) {
        final server = ContractServer();
        await expectLater(
          runAcceptance(
            config,
            AcceptanceMode.existingShare,
            approvedDisposableWrites: false,
            progress: (_) {},
            transport: server,
          ),
          throwsA(isA<AcceptanceFailure>()),
        );
        expect(server.calls, isEmpty);
      }
    },
  );

  test('loopback verifies a seeded share over real local HTTP', () async {
    final png = base64Encode(await File(_pngPath).readAsBytes());
    final seededShare = {
      'Recipient': _recipient,
      'Title': 'Aperture acceptance PNG',
      'FileType': 'image/png',
      'FileDataBase64': png,
    };
    final fixture = ContractServer()
      ..contents[_sharedItemId] = seededShare
      ..contents[8] = {'Recipient': 'unrelated-user'};
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => http.close(force: true));
    const prefix = '/aperture/';
    http.listen((request) async {
      expect(request.uri.path, startsWith(prefix));
      final body = await utf8.decoder.bind(request).join();
      final token = request.headers.value(HttpHeaders.authorizationHeader);
      final reply = await fixture.send(
        request.method,
        request.uri.replace(
          path: request.uri.path.substring(prefix.length - 1),
        ),
        {'Authorization': ?token},
        body.isEmpty ? null : body,
      );
      request.response
        ..statusCode = reply.status
        ..write(reply.body);
      await request.response.close();
    });
    final config = configuration(
      base: 'http://127.0.0.1:${http.port}$prefix',
      protectedLoopback: true,
      existingShareId: _sharedItemId,
    );
    final output = <String>[];
    Future<void> run() => runAcceptance(
      config,
      AcceptanceMode.existingShare,
      approvedDisposableWrites: false,
      progress: output.add,
    );

    fixture.badAnonymousResponse = true;
    await expectLater(run(), throwsA(isA<AcceptanceFailure>()));
    expect(fixture.calls.single.uri.path, '/api/content/capabilities');
    expect(fixture.calls.single.headers, isEmpty);
    expect(fixture.calls.single.body, isNull);
    fixture.badAnonymousResponse = false;
    fixture.calls.clear();

    await run();
    expect(output, hasLength(8));
    expect(output.join(), isNot(contains('synthetic-')));
    expect(output.join(), isNot(contains(png)));
    expect(fixture.sessions, isEmpty);
    expect(fixture.tokens, isEmpty);
    expect(fixture.contents, {
      _sharedItemId: seededShare,
      8: {'Recipient': 'unrelated-user'},
    });
    expect(fixture.revoked, isEmpty);
    expect(fixture.policies, isEmpty);
    expect(
      fixture.calls
          .where((call) => call.method == 'POST')
          .map((call) => call.uri.path),
      everyElement(
        matches(
          r'^/api/(auth/(login|logout)|content/(7/sessions|sessions/\d+/(check|end)))$',
        ),
      ),
    );
  });

  test('existing share failure cleans only the session it opened', () async {
    final server = ContractServer()
      ..contents[7] = {'Recipient': _recipient}
      ..sessions[100] = 7
      ..rejectCheck = true;
    await expectLater(
      runAcceptance(
        configuration(existingShareId: 7),
        AcceptanceMode.existingShare,
        approvedDisposableWrites: false,
        progress: (_) {},
        transport: server,
      ),
      throwsA(isA<AcceptanceFailure>()),
    );
    expect(server.sessions, {100: 7});
    expect(server.contents, {
      7: {'Recipient': _recipient},
    });
    expect(server.revoked, isEmpty);
    expect(server.tokens, isEmpty);
  });

  test('smoke authenticates both identities and invalidates tokens without content writes', () async {
    final server = ContractServer();
    final output = <String>[];
    await runAcceptance(
      configuration(),
      AcceptanceMode.smoke,
      approvedDisposableWrites: false,
      progress: output.add,
      transport: server,
    );
    expect(server.tokens, isEmpty);
    expect(server.contents, isEmpty);
    expect(server.sessions, isEmpty);
    expect(server.closed, isTrue);
    expect(
      server.calls.where(
        (call) =>
            call.method == 'POST' && !call.uri.path.startsWith('/api/auth/'),
      ),
      isEmpty,
    );
    expect(output, hasLength(6));
    expect(output.join(), isNot(contains('sample')));
    expect(output.join(), isNot(contains('synthetic-')));
  });

  test('disposable workflow verifies isolation, authorization, pause, resume and revoke', () async {
    final server = ContractServer();
    final output = <String>[];
    await runAcceptance(
      configuration(),
      AcceptanceMode.disposable,
      approvedDisposableWrites: true,
      progress: output.add,
      transport: server,
    );
    expect(server.contents, hasLength(3));
    expect(server.revoked, containsAll(server.contents.keys));
    expect(server.devices, {(_recipient, _deviceKey): false});
    final registration = server.calls.singleWhere(
      (call) => call.uri.path == '/api/devices',
    );
    expect(registration.method, 'POST');
    expect(registration.json, {
      'DeviceKey': _deviceKey,
      'DeviceName': 'Aperture acceptance device',
    });
    expect(server.tokens, isEmpty);
    expect(server.sessions.values.every(server.revoked.contains), isTrue);
    expect(server.terminatedSessions, containsAll(server.sessions.keys));
    expect(output.where((line) => line.startsWith('PASS:')), hasLength(14));
    expect(output.join(), isNot(contains('sample')));
  });

  for (final (step, fixture) in [
    (
      'Open, check and end a recipient session',
      ContractServer()..misreportDeviceTrust = true,
    ),
    (
      'Pause ends access and resume allows a fresh session',
      ContractServer()..resumeRestoresSessions = true,
    ),
  ]) {
    test('disposable acceptance detects a contract failure at $step', () async {
      await expectLater(
        runAcceptance(
          configuration(),
          AcceptanceMode.disposable,
          approvedDisposableWrites: true,
          progress: (_) {},
          transport: fixture,
        ),
        throwsA(
          isA<AcceptanceFailure>().having((error) => error.step, 'step', step),
        ),
      );
      expect(fixture.revoked, containsAll(fixture.contents.keys));
      expect(fixture.tokens, isEmpty);
      expect(fixture.closed, isTrue);
    });
  }

  test('failure after session creation ends it and revokes only newly created content', () async {
    final server = ContractServer()..rejectCheck = true;
    server.contents[999] = {'Recipient': 'unrelated-user'};
    await expectLater(
      runAcceptance(
        configuration(),
        AcceptanceMode.disposable,
        approvedDisposableWrites: true,
        progress: (_) {},
        transport: server,
      ),
      throwsA(isA<AcceptanceFailure>()),
    );
    expect(server.sessions, isEmpty);
    expect(server.revoked, hasLength(1));
    expect(server.revoked, isNot(contains(999)));
    expect(server.tokens, isEmpty);
    final end = server.calls.indexWhere(
      (call) => call.uri.path.endsWith('/end'),
    );
    final logout = server.calls.indexWhere(
      (call) => call.uri.path.endsWith('/logout'),
    );
    expect(end, greaterThan(0));
    expect(logout, greaterThan(end));
  });

  test(
    'unexpected unsupported grant fails acceptance and cleans its new session',
    () async {
      final server = ContractServer()..acceptUnsupported = true;
      await expectLater(
        runAcceptance(
          configuration(),
          AcceptanceMode.disposable,
          approvedDisposableWrites: true,
          progress: (_) {},
          transport: server,
        ),
        throwsA(isA<AcceptanceFailure>()),
      );
      expect(server.revoked, containsAll(server.contents.keys));
      expect(server.tokens, isEmpty);
      expect(server.sessions.values.every(server.revoked.contains), isTrue);
      expect(server.closed, isTrue);
    },
  );
}

class _RevocationContractServer extends ContractServer {
  final String? lost;
  final bool denialPayload;

  _RevocationContractServer({this.lost, this.denialPayload = false});

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final reply = await super.send(method, uri, headers, body);
    if (method == 'POST') {
      final action = switch (uri.path.split('/').last) {
        'content' => 'create',
        'policy' =>
          jsonDecode(body!)['Status'] == 'Paused' ? 'pause' : 'resume',
        'revoke' => 'revoke',
        _ => null,
      };
      if (action != null && action == lost) {
        throw const ApiException(ApiFailure.timeout);
      }
    }
    if (denialPayload && uri.path.endsWith('/check') && reply.status == 404) {
      return jsonReply({
        'AccessGranted': false,
        'Body': 'private denial payload',
      }, 404);
    }
    return reply;
  }
}

class _WrongPngGrant extends ContractServer {
  final String defect;
  _WrongPngGrant(this.defect);

  @override
  ApiReply _grant(int content, int session, String recipient) {
    final reply = super._grant(content, session, recipient);
    final json = apiObject(jsonDecode(reply.body));
    switch (defect) {
      case 'checksum':
        final bytes = base64Decode(json['FileDataBase64'] as String);
        bytes[bytes.length - 1] ^= 1;
        json['FileDataBase64'] = base64Encode(bytes);
      case 'mime':
        json['FileType'] = 'image/jpeg';
      case 'content ID':
        json['ContentId'] = content + 1;
    }
    return jsonReply(json);
  }

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final reply = await super.send(method, uri, headers, body);
    if (defect == 'denial payload' &&
        uri.path.endsWith('/check') &&
        reply.status == 404) {
      return jsonReply({
        'FileDataBase64': contents.values.single['FileDataBase64'],
      }, 404);
    }
    return reply;
  }
}

class _UnconfirmedClassroomCreate extends ContractServer {
  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final response = await super.send(method, uri, headers, body);
    if (method == 'POST' && uri.path == '/api/content') {
      throw const ApiException(ApiFailure.timeout);
    }
    return response;
  }
}

class _RejectedClassroomServer extends ContractServer {
  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    if (uri.path == '/api/auth/login' &&
        jsonDecode(body!)['Username'] == _sender) {
      calls.add(ApiCall(method, uri, headers, body));
      return jsonReply({
        'Success': false,
        'Message': 'secret-response-marker',
      }, 401);
    }
    if (uri.path == '/api/auth/logout') {
      calls.add(ApiCall(method, uri, headers, body));
      return const ApiReply(503, 'secret-response-marker');
    }
    return super.send(method, uri, headers, body);
  }
}
