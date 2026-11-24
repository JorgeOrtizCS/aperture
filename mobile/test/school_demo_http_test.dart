import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aperture/models/api_models.dart';
import 'package:aperture/models/content_create_request.dart';
import 'package:aperture/services/api_configuration.dart';
import 'package:aperture/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';

const _publicDemo = 'http://fixture.invalid/site';
const _deviceKey = '11111111-1111-4111-8111-111111111111';
const _anonymousDenial = {
  'success': false,
  'message': 'Authentication required.',
};

Matcher _failure(ApiFailure kind) =>
    isA<ApiException>().having((error) => error.kind, 'kind', kind);

ApiService _publicDemoWith(ApiTransport transport) => ApiService(
  baseUri: ApiService.parseBaseUrl(_publicDemo, schoolDemo: true),
  schoolDemo: true,
  transport: transport,
);

void main() {
  test('classroom HTTP requires an explicit mode and API origin', () {
    for (final (mode, url) in [
      ('live', _publicDemo),
      (classroomHttpMode, ''),
      (classroomHttpMode, 'https://fixture.invalid/'),
      (classroomHttpMode, 'http://user@fixture.invalid/'),
    ]) {
      final api = configuredApi(mode: mode, baseUrl: url);
      addTearDown(api.close);
      expect(api.configured, isFalse);
    }
    for (final origin in ['', 'http://other.fixture.invalid/']) {
      final mismatched = configuredApi(
        mode: classroomHttpMode,
        baseUrl: _publicDemo,
        classroomOrigin: origin,
      );
      addTearDown(mismatched.close);
      expect(mismatched.configured, isFalse);
    }
    final classroom = configuredApi(
      mode: classroomHttpMode,
      baseUrl: _publicDemo,
      classroomOrigin: _publicDemo,
    );
    addTearDown(classroom.close);
    expect(classroom.usesClassroomHttp, isTrue);
    expect(classroom.anonymousOnly, isFalse);
    expect(classroom.canOpenContentRoutes, isFalse);
    expect(classroom.canCreateContent, isFalse);
  });

  test('classroom native transport pins the origin and blocks writes and redirects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <String>[];
    final profileEnabledOnRequest = <bool>[];
    server.listen((request) async {
      requests.add(request.uri.path);
      profileEnabledOnRequest.add(HttpClient.enableTimelineLogging);
      await request.drain<void>();
      request.response
        ..statusCode = 307
        ..headers.set('Location', '/other');
      await request.response.close();
    });
    final base = Uri.parse('http://127.0.0.1:${server.port}/');
    final transport = NativeApiTransport.classroomHttp(base);
    addTearDown(transport.close);
    for (final (method, uri) in [
      ('POST', base.resolve('api/content')),
      ('POST', base.resolve('api/content/1/sessions')),
      ('GET', base.resolve('api/user/me').replace(host: 'fixture.invalid')),
      ('GET', base.resolve('api/user/me?extra=1')),
    ]) {
      await expectLater(
        transport.send(method, uri, {}, null),
        throwsA(_failure(ApiFailure.configuration)),
      );
    }
    final profiling = HttpClient.enableTimelineLogging;
    addTearDown(() => HttpClient.enableTimelineLogging = profiling);
    HttpClient.enableTimelineLogging = true;
    final reply = await transport.send(
      'POST',
      base.resolve('api/auth/login'),
      {'Content-Type': 'application/json'},
      jsonEncode({
        'Username': classroomFixtureSender,
        'Password': 'synthetic-only',
      }),
    );
    expect(reply.status, 307);
    expect(requests, ['/api/auth/login']);
    expect(profileEnabledOnRequest, [false]);
  });

  test('only explicit school demo opts into HTTP', () {
    final demo = configuredApi(mode: 'school-demo-http', baseUrl: _publicDemo);
    final live = configuredApi(baseUrl: 'https://fixture.invalid/site');
    addTearDown(demo.close);
    addTearDown(live.close);
    expect(demo.baseUri.toString(), 'http://fixture.invalid/site/');
    expect(demo.usesSchoolDemoHttp, isTrue);
    expect(demo.anonymousOnly, isTrue);
    expect(demo.canCreateContent, isFalse);
    expect(live.baseUri.toString(), 'https://fixture.invalid/site/');
    expect(live.usesSchoolDemoHttp, isFalse);
    expect(live.anonymousOnly, isFalse);
    expect(
      () => ApiService(baseUri: demo.baseUri, transport: ApiFake()),
      throwsA(_failure(ApiFailure.configuration)),
    );
  });

  test('mixed modes and unsafe base URLs stay unavailable', () {
    for (final (mode, url) in [
      ('live', _publicDemo),
      ('school-demo-http', ''),
      ('school-demo-http', 'https://fixture.invalid/'),
      ('school-demo-http', 'ftp://fixture.invalid/'),
      ('school-demo-http', 'http://@fixture.invalid/'),
      ('school-demo-http', 'HTTP://@fixture.invalid/'),
      ('school-demo-http', 'http://user:sample@fixture.invalid/'),
      ('school-demo-http', 'http://fixture.invalid:0/'),
      ('school-demo-http', 'http://fixture.invalid:65536/'),
      ('school-demo-http', 'http://fixture.invalid/?a=b'),
      ('school-demo-http', 'http://fixture.invalid/#fragment'),
      ('school-demo-http', 'http://fixture.invalid/bad path'),
      ('school-demo-http', 'http://fixture.invalid\\ambiguous'),
    ]) {
      final api = configuredApi(mode: mode, baseUrl: url);
      expect(api.configured, isFalse, reason: '$mode with $url');
      api.close();
    }
  });

  test(
    'public HTTP sends only the explicit anonymous contract probe',
    () async {
      final fake = ApiFake()
        ..routes['/site/api/content/capabilities'] = (_) =>
            jsonReply(_anonymousDenial, 401);
      final api = _publicDemoWith(fake);
      addTearDown(api.close);

      await expectLater(
        api.login('disposable', 'synthetic-only'),
        throwsA(_failure(ApiFailure.httpDemoAnonymousOnly)),
      );
      await expectLater(
        api.currentUser('synthetic-token'),
        throwsA(_failure(ApiFailure.httpDemoAnonymousOnly)),
      );
      await expectLater(
        api.list('synthetic-token'),
        throwsA(_failure(ApiFailure.httpDemoAnonymousOnly)),
      );
      await expectLater(
        api.open('synthetic-token', 7, _deviceKey),
        throwsA(_failure(ApiFailure.httpDemoAnonymousOnly)),
      );
      expect(fake.calls, isEmpty);

      await api.checkAnonymousAccess();
      final call = fake.calls.single;
      expect(call.method, 'GET');
      expect(
        call.uri.toString(),
        'http://fixture.invalid/site/api/content/capabilities',
      );
      expect(call.headers, {'Accept': 'application/json'});
      expect(call.body, isNull);
    },
  );

  test(
    'public native transport rejects credential headers before I/O',
    () async {
      final base = ApiService.parseBaseUrl(_publicDemo, schoolDemo: true);
      final transport = NativeApiTransport.schoolDemo(base);
      addTearDown(transport.close);
      final uri = base.resolve('api/content/capabilities');
      await expectLater(
        transport.send('GET', uri, {
          'Accept': 'application/json',
          'authorization': 'Bearer synthetic-token',
        }, null),
        throwsA(_failure(ApiFailure.httpDemoAnonymousOnly)),
      );
      await expectLater(
        transport.send('GET', uri.replace(host: 'other.invalid'), {
          'Accept': 'application/json',
        }, null),
        throwsA(_failure(ApiFailure.configuration)),
      );
    },
  );

  test('placeholder, wrong route and proxy 401 fail the probe', () async {
    final fake = ApiFake();
    final api = _publicDemoWith(fake);
    addTearDown(api.close);
    for (final (reply, kind) in [
      (
        const ApiReply(200, '<title>Your site is ready...</title>'),
        ApiFailure.malformed,
      ),
      (const ApiReply(404, ''), ApiFailure.notFound),
      (const ApiReply(401, '<title>Proxy login</title>'), ApiFailure.malformed),
      (jsonReply({'success': false}, 401), ApiFailure.malformed),
    ]) {
      fake.routes['/site/api/content/capabilities'] = (_) => reply;
      await expectLater(api.checkAnonymousAccess(), throwsA(_failure(kind)));
    }
  });

  test(
    'loopback exercises real HTTP login, identity, lists and session models',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = 'http://127.0.0.1:${server.port}/aperture/';
      final api = configuredApi(mode: 'school-demo-http', baseUrl: base);
      addTearDown(() => server.close(force: true));
      addTearDown(api.close);
      final requests = <ApiCall>[];
      final tokens = <String, String>{};
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final authorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        final token = authorization?.substring('Bearer '.length);
        final user = tokens[token];
        final path = request.uri.path.substring('/aperture/'.length);
        final call = ApiCall(request.method, request.uri, {
          'Authorization': ?authorization,
        }, body.isEmpty ? null : body);
        requests.add(call);
        final ApiReply reply;
        if (path == 'api/auth/login' &&
            call.json['Password'] == 'disposable-only') {
          final name = call.json['Username'] as String;
          final token = 'synthetic-$name';
          tokens[token] = name;
          reply = jsonReply({
            'Success': true,
            'Token': token,
            'ExpiresAt': '2030-01-01T00:00:00Z',
            'User': {
              'Id': name == 'disposable-sender' ? 1 : 2,
              'Username': name,
            },
          });
        } else if (user == null) {
          reply = jsonReply(_anonymousDenial, 401);
        } else {
          reply = switch (path) {
            'api/user/me' => jsonReply({
              'success': true,
              'user': {
                'id': user == 'disposable-sender' ? 1 : 2,
                'username': user,
              },
            }),
            'api/content' => jsonReply([
              {
                ...contentJson(mine: user == 'disposable-sender'),
                'Owner': 'disposable-sender',
                if (user == 'disposable-sender')
                  'Recipient': 'disposable-recipient',
              },
            ]),
            'api/content/7/sessions' => jsonReply(accessJson()),
            'api/content/sessions/41/check' => jsonReply(
              accessJson(suspended: true),
            ),
            'api/content/sessions/41/end' => jsonReply({'success': true}),
            'api/auth/logout' => jsonReply({
              'success': tokens.remove(token) != null,
            }),
            _ => const ApiReply(404, ''),
          };
        }
        request.response
          ..statusCode = reply.status
          ..headers.contentType = ContentType.json
          ..write(reply.body);
        await request.response.close();
      });

      expect(api.anonymousOnly, isFalse);
      await api.checkAnonymousAccess();
      expect(requests.single.headers, isEmpty);
      await expectLater(
        api.login('disposable-sender', 'rejected-sample'),
        throwsA(_failure(ApiFailure.credentials)),
      );
      final sender = await api.login('disposable-sender', 'disposable-only');
      final recipient = await api.login(
        'disposable-recipient',
        'disposable-only',
      );
      expect((await api.currentUser(sender.token)).id, sender.user.id);
      expect((await api.currentUser(recipient.token)).id, recipient.user.id);
      final sent = (await api.list(sender.token)).single;
      final received = (await api.list(recipient.token)).single;
      expect(sent.mine, isTrue);
      expect(sent.recipient, recipient.user.username);
      expect(received.mine, isFalse);
      expect(received.id, sent.id);
      final open = await api.open(recipient.token, 7, _deviceKey);
      expect(open.sessionId, 41);
      expect(open.granted, isTrue);
      final check = await api.check(recipient.token, 41);
      expect(check.suspended, isTrue);
      expect(check.granted, isFalse);
      await api.end(recipient.token, 41);
      await api.logout(sender.token);
      await api.logout(recipient.token);
      await expectLater(
        api.currentUser(recipient.token),
        throwsA(_failure(ApiFailure.credentials)),
      );
      expect(requests[2].json, {
        'Username': 'disposable-sender',
        'Password': 'disposable-only',
      });
      final openRequest = requests.singleWhere(
        (r) => r.uri.path.endsWith('/7/sessions'),
      );
      expect(openRequest.method, 'POST');
      expect(openRequest.json, {
        'DeviceKey': _deviceKey,
        'CameraPolicyVersion': 0,
      });
      expect(openRequest.headers['Authorization'], 'Bearer ${recipient.token}');

      final upload = ContentCreateRequest.validate(
        title: 'Disposable fixture',
        recipient: 'disposable-recipient',
        sender: 'disposable-sender',
        now: DateTime.utc(2026),
        screenshotRestriction: true,
      );
      final bytes = Uint8List.fromList([1, 2, 3]);
      final requestCount = requests.length;
      await expectLater(
        api.createContent(
          'synthetic-token',
          upload,
          bytes,
          maxBytes: 100,
          cancellation: ApiRequestCancellation(),
          onDispatch: () => fail('Upload reached dispatch'),
        ),
        throwsA(_failure(ApiFailure.uploadUnverified)),
      );
      expect(bytes, everyElement(0));
      expect(requests, hasLength(requestCount));
    },
  );

  test(
    'native transport follows no redirect and cannot downgrade HTTPS',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final root = Uri.parse('http://127.0.0.1:${server.port}/');
      final requests = <String>[];
      server.listen((request) {
        requests.add(request.uri.path);
        request.response
          ..statusCode = 302
          ..headers.set(HttpHeaders.locationHeader, root.resolve('target'));
        request.response.close();
      });
      final live = NativeApiTransport();
      final demo = NativeApiTransport.schoolDemo(root);
      addTearDown(() => server.close(force: true));
      addTearDown(live.close);
      addTearDown(demo.close);

      await expectLater(
        live.send('GET', root, {}, null),
        throwsA(_failure(ApiFailure.configuration)),
      );
      await expectLater(
        live.send('GET', root.replace(scheme: 'https'), {}, null),
        throwsA(_failure(ApiFailure.network)),
      );
      await expectLater(
        demo.send('POST', root.resolve('api/content'), {}, '{"Body":"sample"}'),
        throwsA(_failure(ApiFailure.uploadUnverified)),
      );
      expect(requests, isEmpty);
      expect((await demo.send('GET', root, {}, null)).status, 302);
      expect(requests, ['/']);
    },
  );

  test('unreachable loopback produces a network failure', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}/';
    await server.close(force: true);
    final api = configuredApi(mode: 'school-demo-http', baseUrl: base);
    addTearDown(api.close);
    await expectLater(
      api.checkAnonymousAccess(),
      throwsA(_failure(ApiFailure.network)),
    );
  });
}
