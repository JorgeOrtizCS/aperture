import 'dart:async';

import 'package:aperture/models/api_models.dart';
import 'package:aperture/services/api_configuration.dart';
import 'package:aperture/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';

Matcher failure(ApiFailure kind) =>
    isA<ApiException>().having((e) => e.kind, 'kind', kind);

void main() {
  test(
    'explicit fixture mode signs in, switches roles and invalidates logout',
    () async {
      final api = configuredApi(mode: 'fixture', baseUrl: '');
      expect(api.isFixture, isTrue);
      expect(api.canOpenContentRoutes, isFalse);
      expect(api.baseUri, isNull);
      final sender = await api.login('fixture-sender', 'sample');
      expect((await api.currentUser(sender.token)).id, sender.user.id);
      final sent = (await api.list(sender.token)).single;
      expect(sent.mine, isTrue);
      final recipient = await api.login('fixture-recipient', 'sample');
      final received = (await api.list(recipient.token)).single;
      expect(received.id, sent.id);
      expect(received.mine, isFalse);
      expect(await api.serverCameraPolicyVersion(recipient.token), 1);
      await api.logout(sender.token);
      await expectLater(
        api.currentUser(sender.token),
        throwsA(failure(ApiFailure.credentials)),
      );
      // Fixture mode cannot grant viewing or mutate a server.
      expect(
        (await api.open(
          recipient.token,
          received.id,
          '11111111-1111-4111-8111-111111111111',
        )).granted,
        isFalse,
      );
      api.close();
    },
  );

  test('fixture login failure never establishes a live environment', () async {
    final api = configuredApi(mode: 'fixture', baseUrl: '');
    await expectLater(
      api.login('unknown-fixture', 'sample'),
      throwsA(failure(ApiFailure.credentials)),
    );
    expect(api.baseUri, isNull);
    api.close();
  });

  for (final setup in [
    ('fixture', 'https://fixture.invalid/'),
    ('unknown', ''),
    ('live', ''),
    ('live', 'http://fixture.invalid/'),
    ('live', 'https://fixture.invalid/?query'),
  ]) {
    test('invalid or mixed configuration stays unavailable: $setup', () {
      final api = configuredApi(mode: setup.$1, baseUrl: setup.$2);
      expect(api.configured, isFalse);
      expect(api.isFixture, isFalse);
      api.close();
    });
  }

  test('HTTPS virtual directory remains part of each API route', () async {
    final fake = ApiFake();
    final api = ApiService(
      baseUri: ApiService.parseBaseUrl('https://fixture.invalid/aperture'),
      transport: fake,
    );
    fake.routes['/aperture/api/content'] = (_) => jsonReply([]);
    await api.list('synthetic');
    expect(fake.calls.single.uri.path, '/aperture/api/content');
    for (final url in [
      'https://fixture.invalid:0/',
      'https://fixture.invalid:65536/',
      'https://fixture.invalid/ space',
      'https://@fixture.invalid/',
    ]) {
      expect(
        () => ApiService.parseBaseUrl(url),
        throwsA(failure(ApiFailure.configuration)),
      );
    }
  });

  test(
    'native transport refuses cleartext before opening a connection',
    () async {
      final transport = NativeApiTransport();
      await expectLater(
        transport.send('GET', Uri.parse('http://fixture.invalid/'), {}, null),
        throwsA(failure(ApiFailure.configuration)),
      );
      transport.close();
    },
  );

  test(
    'already invalidated logout is confirmed, other failures remain visible',
    () async {
      final fake = ApiFake();
      final api = fake.service();
      fake.routes['/api/auth/logout'] = (_) => const ApiReply(401, '');
      await api.logout('synthetic');
      fake.routes['/api/auth/logout'] = (_) => const ApiReply(403, '');
      await expectLater(
        api.logout('synthetic'),
        throwsA(failure(ApiFailure.denied)),
      );
    },
  );

  test('server capabilities never upgrade the mobile camera claim', () async {
    final fake = ApiFake();
    fake.routes['/api/content/capabilities'] = (_) =>
        jsonReply({'CameraPolicyVersion': 1});
    final api = fake.service();
    expect(await api.serverCameraPolicyVersion('synthetic'), 1);
    await api.open('synthetic', 7, '11111111-1111-4111-8111-111111111111');
    expect(fake.calls.last.json['CameraPolicyVersion'], 0);
    fake.routes['/api/content/capabilities'] = (_) =>
        jsonReply({'CameraPolicyVersion': '1'});
    await expectLater(
      api.serverCameraPolicyVersion('synthetic'),
      throwsA(failure(ApiFailure.malformed)),
    );
  });

  test('direct account replacement retires the previous token', () async {
    final fake = ApiFake();
    final account = fake.session();
    await account.login('synthetic-user', 'sample');
    fake.userId = 2;
    fake.username = 'replacement';
    fake.token = 'replacement-token';
    await account.login('replacement', 'sample');
    await Future<void>.delayed(Duration.zero);
    expect(account.user!.id, 2);
    final logouts = fake.calls.where((c) => c.uri.path.endsWith('/logout'));
    expect(
      logouts.single.headers['Authorization'],
      'Bearer synthetic-opaque-token',
    );
    account.dispose();
  });

  test(
    'cancelling pending login discards success and revokes its candidate token',
    () async {
      final fake = ApiFake();
      final account = fake.session();
      final me = Completer<ApiReply>();
      fake.routes['/api/user/me'] = (_) => me.future;
      final pending = account.login('synthetic-user', 'sample');
      final rejected = expectLater(pending, throwsA(failure(ApiFailure.stale)));
      await Future<void>.delayed(Duration.zero);
      account.cancelLogin();
      expect(account.signingIn, isFalse);
      me.complete(
        jsonReply({
          'success': true,
          'user': {'id': 1, 'username': 'synthetic-user'},
        }),
      );
      await rejected;
      await Future<void>.delayed(Duration.zero);
      expect(account.authenticated, isFalse);
      expect(
        fake.calls.where((c) => c.uri.path.endsWith('/logout')),
        hasLength(1),
      );
      account.dispose();
    },
  );

  for (final malformed in [false, true]) {
    test(
      'logout waits for late ${malformed ? 'malformed' : 'valid'} open cleanup before token revocation',
      () async {
        final fake = ApiFake();
        final account = fake.session();
        await account.login('synthetic-user', 'sample');
        final open = Completer<ApiReply>();
        final end = Completer<ApiReply>();
        fake.routes['/api/content/7/sessions'] = (_) => open.future;
        fake.routes['/api/content/sessions/41/end'] = (_) => end.future;
        final pending = account.openViewing(7, account.deviceKey!);
        final rejected = expectLater(
          pending,
          throwsA(failure(ApiFailure.stale)),
        );
        final logout = account.logout();
        expect(account.authenticated, isFalse);
        open.complete(
          jsonReply({
            ...accessJson(),
            if (malformed) 'AccessGranted': 'invalid',
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(fake.calls.last.uri.path, '/api/content/sessions/41/end');
        expect(
          fake.calls.where((c) => c.uri.path.endsWith('/logout')),
          isEmpty,
        );
        end.complete(jsonReply({'success': true}));
        await rejected;
        await logout;
        expect(fake.calls.last.uri.path, '/api/auth/logout');
        account.dispose();
      },
    );
  }

  test(
    'dispose preserves transport until pending login token can be retired',
    () async {
      final fake = ApiFake();
      final account = fake.session();
      final me = Completer<ApiReply>();
      final logout = Completer<ApiReply>();
      fake.routes['/api/user/me'] = (_) => me.future;
      fake.routes['/api/auth/logout'] = (_) => logout.future;
      final login = account.login('synthetic-user', 'sample');
      final rejected = expectLater(login, throwsA(failure(ApiFailure.stale)));
      await Future<void>.delayed(Duration.zero);
      account.dispose();
      expect(fake.closed, isFalse);
      me.complete(
        jsonReply({
          'success': true,
          'user': {'id': 1, 'username': 'synthetic-user'},
        }),
      );
      await rejected;
      expect(fake.closed, isFalse);
      logout.complete(jsonReply({'success': true}));
      await Future<void>.delayed(Duration.zero);
      expect(fake.closed, isTrue);
    },
  );

  test(
    'late same-account list failure cannot replace a newer refresh',
    () async {
      final fake = ApiFake();
      final account = fake.session();
      await account.login('synthetic-user', 'sample');
      final old = Completer<ApiReply>();
      fake.routes['/api/content'] = (_) => old.future;
      final first = account.refresh();
      fake.routes.remove('/api/content');
      fake.contents = [contentJson(title: 'New confirmed metadata')];
      await account.refresh();
      old.complete(const ApiReply(500, ''));
      await first;
      expect(account.error, isNull);
      expect(account.contentListingError, isNull);
      expect(account.hasContentListing, isTrue);
      expect(account.items.single.title, 'New confirmed metadata');
      account.dispose();
    },
  );
}
