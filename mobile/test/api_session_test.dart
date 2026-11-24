import 'dart:async';

import 'package:aperture/models/api_models.dart';
import 'package:aperture/models/location_radius_policy.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';

Matcher apiError(ApiFailure kind) =>
    isA<ApiException>().having((e) => e.kind, 'kind', kind);

void main() {
  late ApiFake fake;
  late ApiSession account;
  setUp(() {
    fake = ApiFake();
    account = fake.session();
  });
  tearDown(() => account.dispose());
  Future<void> login() =>
      account.login('synthetic-user', 'not-a-real-password');

  test(
    'login verifies current-user identity and endpoint-specific casing',
    () async {
      await login();
      expect(account.authenticated, isTrue);
      expect(account.user!.id, 1);
      expect(fake.calls.map((c) => c.uri.path), [
        '/api/auth/login',
        '/api/user/me',
      ]);
      expect(fake.calls.first.json, {
        'Username': 'synthetic-user',
        'Password': 'not-a-real-password',
      });
      expect(fake.calls.first.headers.containsKey('Authorization'), isFalse);
      expect(
        fake.calls.last.headers['Authorization'],
        'Bearer synthetic-opaque-token',
      );
    },
  );

  test(
    'authentication denial never installs account or loads content',
    () async {
      fake.routes['/api/auth/login'] = (_) => const ApiReply(401, 'rejected');
      await expectLater(login(), throwsA(apiError(ApiFailure.credentials)));
      expect(account.authenticated, isFalse);
      expect(account.items, isEmpty);
      expect(fake.calls.length, 1);
    },
  );

  test('HTTP 200 Success false is still authentication denial', () async {
    fake.routes['/api/auth/login'] = (_) => jsonReply({'Success': false});
    await expectLater(login(), throwsA(apiError(ApiFailure.credentials)));
    expect(account.authenticated, isFalse);
  });

  test('missing credentials are rejected without any request', () async {
    await expectLater(
      account.login(' ', ''),
      throwsA(apiError(ApiFailure.invalidRequest)),
    );
    await expectLater(
      account.refresh(),
      throwsA(apiError(ApiFailure.credentials)),
    );
    expect(fake.calls, isEmpty);
  });

  test('expired login response does not establish account', () async {
    fake.expiresAt = DateTime.utc(2020);
    await expectLater(login(), throwsA(apiError(ApiFailure.credentials)));
    expect(account.authenticated, isFalse);
    expect(fake.calls.where((c) => c.uri.path == '/api/user/me'), isEmpty);
  });

  test('current-user mismatch rejects cross-user identity', () async {
    fake.routes['/api/user/me'] = (_) => jsonReply({
      'success': true,
      'user': {'id': 2, 'username': 'different-user'},
    });
    await expectLater(login(), throwsA(apiError(ApiFailure.malformed)));
    expect(account.authenticated, isFalse);
  });

  for (final body in [
    'not-json',
    '{}',
    '{"Success":true}',
    '{"Success":"true"}',
    '{"Success":true,"Token":""}',
  ]) {
    test('malformed login response fails closed: $body', () async {
      fake.routes['/api/auth/login'] = (_) => ApiReply(200, body);
      await expectLater(login(), throwsA(apiError(ApiFailure.malformed)));
      expect(account.authenticated, isFalse);
    });
  }

  test('invalid token header and unzoned expiry are rejected', () async {
    fake.token = 'bad\r\ntoken';
    await expectLater(login(), throwsA(apiError(ApiFailure.malformed)));
    fake.routes['/api/auth/login'] = (_) => jsonReply({
      'Success': true,
      'Token': 'safe',
      'ExpiresAt': '2030-01-01T00:00:00',
      'User': {'Id': 1, 'Username': 'x'},
    });
    await expectLater(login(), throwsA(apiError(ApiFailure.malformed)));
  });

  test(
    'network failure produces safe error without credential echoes',
    () async {
      fake.routes['/api/auth/login'] = (_) =>
          throw StateError('sensitive transport diagnostics');
      await expectLater(login(), throwsA(apiError(ApiFailure.network)));
      expect(account.error!.message, isNot(contains('sensitive')));
      expect(account.authenticated, isFalse);
    },
  );

  test('timeout cannot install credentials from a late response', () async {
    account.dispose();
    account = fake.session(timeout: const Duration(milliseconds: 5));
    final pending = Completer<ApiReply>();
    fake.routes['/api/auth/login'] = (_) => pending.future;
    await expectLater(login(), throwsA(apiError(ApiFailure.timeout)));
    pending.complete(
      jsonReply({
        'Success': true,
        'Token': 'late',
        'ExpiresAt': '2030-01-01T00:00:00Z',
        'User': {'Id': 1, 'Username': 'synthetic-user'},
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(account.authenticated, isFalse);
  });

  test('logout during pending login discards late success', () async {
    final pending = Completer<ApiReply>();
    fake.routes['/api/user/me'] = (_) => pending.future;
    final signingIn = login();
    await Future<void>.delayed(Duration.zero);
    await account.logout();
    pending.complete(
      jsonReply({
        'success': true,
        'user': {'id': 1, 'username': 'synthetic-user'},
      }),
    );
    await expectLater(signingIn, throwsA(apiError(ApiFailure.stale)));
    expect(account.authenticated, isFalse);
  });

  test('pending old-user list cannot populate another account', () async {
    await login();
    final pending = Completer<ApiReply>();
    fake.routes['/api/content'] = (_) => pending.future;
    final first = account.refresh();
    await account.logout();
    fake.userId = 2;
    fake.username = 'second-user';
    fake.token = 'second-token';
    await account.login('second-user', 'synthetic-only');
    expect(account.hasContentListing, isFalse);
    expect(account.contentListingError, isNull);
    fake.routes.remove('/api/content');
    fake.contents = [contentJson(title: 'SECOND ACCOUNT ONLY')];
    await account.refresh();
    pending.complete(jsonReply([contentJson(title: 'FIRST ACCOUNT ONLY')]));
    await expectLater(first, throwsA(apiError(ApiFailure.stale)));
    expect(account.user!.id, 2);
    expect(account.items.single.title, 'SECOND ACCOUNT ONLY');
    expect(account.hasContentListing, isTrue);
    expect(account.contentListingError, isNull);
  });

  test('old-user unauthorized response cannot log out new user', () async {
    await login();
    final pending = Completer<ApiReply>();
    fake.routes['/api/content'] = (_) => pending.future;
    final first = account.refresh();
    await account.logout();
    fake.userId = 2;
    fake.username = 'second';
    await account.login('second', 'synthetic-only');
    pending.complete(const ApiReply(401, 'expired old token'));
    await expectLater(first, throwsA(apiError(ApiFailure.stale)));
    expect(account.authenticated, isTrue);
    expect(account.user!.id, 2);
  });

  test('current 401 clears identity and cached content', () async {
    await login();
    fake.contents = [contentJson()];
    await account.refresh();
    fake.routes['/api/content'] = (_) => const ApiReply(401, 'expired');
    await expectLater(
      account.refresh(),
      throwsA(apiError(ApiFailure.credentials)),
    );
    expect(account.authenticated, isFalse);
    expect(account.items, isEmpty);
    expect(account.hasContentListing, isFalse);
    expect(account.contentListingError, isNull);
  });

  test('a failed refresh retains the last known empty listing', () async {
    await login();
    expect(account.hasContentListing, isFalse);
    await account.refresh();
    expect(account.hasContentListing, isTrue);
    expect(account.items, isEmpty);
    fake.routes['/api/content'] = (_) => const ApiReply(500, 'private detail');
    await expectLater(account.refresh(), throwsA(apiError(ApiFailure.server)));
    expect(account.hasContentListing, isTrue);
    expect(account.contentListingError?.kind, ApiFailure.server);
    expect(account.items, isEmpty);

    fake.routes.remove('/api/content');
    fake.contents = [contentJson()];
    await account.refresh();
    expect(account.contentListingError, isNull);
    expect(account.items, hasLength(1));
  });

  for (final value in [
    null,
    {},
    [
      {'Id': '7'},
    ],
    [contentJson()..['Mine'] = 'true'],
    [contentJson()..['Status'] = 'Unrecognized'],
  ]) {
    test('unexpected content-list shape fails closed: $value', () async {
      await login();
      fake.routes['/api/content'] = (_) => jsonReply(value ?? 'null');
      await expectLater(
        account.refresh(),
        throwsA(apiError(ApiFailure.malformed)),
      );
      expect(account.items, isEmpty);
    });
  }

  test('owner pause/resume is separate from recipient revocation', () async {
    await login();
    fake.contents = [contentJson(mine: true)];
    await account.refresh();
    await account.setPolicy(7, 'Paused');
    expect(account.items.single.policyStatus, 'Paused');
    expect(account.items.single.status, 'Active');
    await account.setPolicy(7, 'Active');
    expect(account.items.single.policyStatus, 'Active');
    final writes = fake.calls
        .where((c) => c.uri.path.endsWith('/policy'))
        .toList();
    expect(writes.map((c) => c.json), [
      {'Status': 'Paused'},
      {'Status': 'Active'},
    ]);
  });

  test(
    'revoke remains Active while pending and changes only after true ack',
    () async {
      await login();
      fake.contents = [contentJson(mine: true)];
      await account.refresh();
      final pending = Completer<ApiReply>();
      fake.routes['/api/content/7/revoke'] = (_) => pending.future;
      final operation = account.revoke(7);
      expect(account.pending(7), isTrue);
      expect(account.items.single.status, 'Active');
      await expectLater(
        account.revoke(7),
        throwsA(apiError(ApiFailure.pending)),
      );
      pending.complete(jsonReply({'success': true}));
      await operation;
      expect(account.items.single.status, 'Revoked');
      expect(account.pending(7), isFalse);
      await account.refresh(); // Even a later stale server list cannot regrant.
      expect(account.items.single.status, 'Revoked');
      await expectLater(
        account.setPolicy(7, 'Active'),
        throwsA(apiError(ApiFailure.denied)),
      );
    },
  );

  for (final reply in [
    const ApiReply(500, 'server'),
    jsonReply({'success': false}),
    jsonReply({'Success': true}),
    const ApiReply(302, 'redirect'),
  ]) {
    test(
      'failed/unexpected revocation never claims success: ${reply.body}',
      () async {
        await login();
        fake.contents = [contentJson(mine: true)];
        await account.refresh();
        fake.routes['/api/content/7/revoke'] = (_) => reply;
        await expectLater(account.revoke(7), throwsA(isA<ApiException>()));
        expect(account.items.single.status, 'Active');
        expect(account.pending(7), isFalse);
      },
    );
  }

  test('permission endpoint mismatched acknowledgement is rejected', () async {
    await login();
    fake.contents = [contentJson(mine: true)];
    await account.refresh();
    fake.routes['/api/content/7/policy'] = (_) =>
        jsonReply({'status': 'Active'});
    await expectLater(
      account.setPolicy(7, 'Paused'),
      throwsA(apiError(ApiFailure.malformed)),
    );
    expect(account.items.single.policyStatus, 'Active');
  });

  test(
    'matching and mismatching listings cannot settle an unknown owner action',
    () async {
      await login();
      fake.contents = [contentJson(mine: true), contentJson(id: 8, mine: true)];
      await account.refresh();
      fake.routes['/api/content/7/policy'] = (_) =>
          jsonReply({'status': 'Active'});
      await expectLater(
        account.setPolicy(7, 'Paused'),
        throwsA(apiError(ApiFailure.malformed)),
      );

      for (final policy in ['Paused', 'Active']) {
        fake.contents[0] = contentJson(mine: true, policy: policy);
        await account.refresh();
        expect(account.items.first.policyStatus, policy);
        await expectLater(
          account.revoke(7),
          throwsA(apiError(ApiFailure.ownerControlUnconfirmed)),
        );
        expect(account.ownerControl(7), (
          OwnerControlAction.pause,
          OwnerControlPhase.unconfirmed,
        ));
      }
      await expectLater(
        account.setLocation(
          7,
          const LocationZone(26, -80, 100),
          isCurrent: () => true,
        ),
        throwsA(apiError(ApiFailure.ownerControlUnconfirmed)),
      );
      await account.setPolicy(8, 'Paused');
      expect(account.items.last.policyStatus, 'Paused');
      expect(
        fake.calls.where(
          (call) =>
              call.method == 'POST' &&
              call.uri.path.startsWith('/api/content/7/'),
        ),
        hasLength(1),
      );
    },
  );

  for (final (initial, target, action) in [
    ('Active', 'Paused', OwnerControlAction.pause),
    ('Paused', 'Active', OwnerControlAction.resume),
    ('Active', null, OwnerControlAction.revoke),
  ]) {
    test(
      '${action.name} blocks duplicate and conflicting requests for its item only',
      () async {
        await login();
        fake.contents = [
          contentJson(mine: true, policy: initial),
          contentJson(id: 8, mine: true),
        ];
        await account.refresh();
        final reply = Completer<ApiReply>();
        final path = target == null
            ? '/api/content/7/revoke'
            : '/api/content/7/policy';
        fake.routes[path] = (_) => reply.future;
        Future<void> change() =>
            target == null ? account.revoke(7) : account.setPolicy(7, target);
        final attempt = change();
        expect(account.ownerControl(7), (action, OwnerControlPhase.pending));
        await expectLater(change(), throwsA(apiError(ApiFailure.pending)));
        await expectLater(
          target == null ? account.setPolicy(7, 'Paused') : account.revoke(7),
          throwsA(apiError(ApiFailure.pending)),
        );
        await account.setPolicy(8, 'Paused');
        expect(account.items.last.policyStatus, 'Paused');
        reply.complete(
          jsonReply(target == null ? {'success': true} : {'status': target}),
        );
        await attempt;
        expect(account.ownerControl(7), (action, OwnerControlPhase.confirmed));
        expect(fake.calls.where((call) => call.uri.path == path), hasLength(1));
      },
    );
  }

  test('pre-write owner rejection leaves the item manageable', () async {
    await login();
    fake.contents = [contentJson(mine: true)];
    await account.refresh();
    const policy = '/api/content/7/policy';
    fake.routes[policy] = (_) => const ApiReply(400, 'invalid policy');
    await expectLater(
      account.setPolicy(7, 'Paused'),
      throwsA(apiError(ApiFailure.invalidRequest)),
    );
    expect(account.ownerControl(7), (
      OwnerControlAction.pause,
      OwnerControlPhase.rejected,
    ));
    const revoke = '/api/content/7/revoke';
    fake.routes[revoke] = (_) => const ApiReply(404, 'owner match not found');
    await expectLater(
      account.revoke(7),
      throwsA(apiError(ApiFailure.notFound)),
    );
    expect(account.ownerControl(7), (
      OwnerControlAction.revoke,
      OwnerControlPhase.rejected,
    ));
    fake.routes.remove(policy);
    await account.setPolicy(7, 'Paused');
    expect(account.ownerControl(7), (
      OwnerControlAction.pause,
      OwnerControlPhase.confirmed,
    ));
  });

  test(
    'late owner completion remains scoped across sign-out and item ID reuse',
    () async {
      await login();
      fake.contents = [contentJson(mine: true)];
      await account.refresh();
      final old = Completer<ApiReply>();
      const policy = '/api/content/7/policy';
      fake.routes[policy] = (_) => old.future;
      final stale = expectLater(
        account.setPolicy(7, 'Paused'),
        throwsA(apiError(ApiFailure.stale)),
      );
      await account.logout();
      expect(account.ownerControl(7), isNull);
      fake.userId = 2;
      fake.username = 'second';
      await account.login('second', 'synthetic-only');
      await account.refresh();
      expect(account.ownerControl(7), isNull);
      fake.routes.remove(policy);
      await account.setPolicy(7, 'Paused');
      old.complete(jsonReply({'status': 'Paused'}));
      await stale;
      expect(account.ownerControl(7), (
        OwnerControlAction.pause,
        OwnerControlPhase.confirmed,
      ));
      expect(account.items.single.policyStatus, 'Paused');
      fake.userId = 1;
      fake.username = 'synthetic-user';
      await login();
      await account.refresh();
      expect(account.ownerControl(7), (
        OwnerControlAction.pause,
        OwnerControlPhase.unconfirmed,
      ));
      await expectLater(
        account.revoke(7),
        throwsA(apiError(ApiFailure.ownerControlUnconfirmed)),
      );
    },
  );

  test(
    'signing back in cannot bypass an owner action still in flight',
    () async {
      await login();
      fake.contents = [contentJson(mine: true)];
      await account.refresh();
      final pending = Completer<ApiReply>();
      fake.routes['/api/content/7/revoke'] = (_) => pending.future;
      final old = expectLater(
        account.revoke(7),
        throwsA(apiError(ApiFailure.stale)),
      );
      await account.logout();
      await login();
      await account.refresh();
      expect(account.pending(7), isTrue);
      await expectLater(
        account.setPolicy(7, 'Paused'),
        throwsA(apiError(ApiFailure.pending)),
      );
      pending.complete(jsonReply({'success': true}));
      await old;
      expect(account.pending(7), isFalse);
      expect(account.items.single.status, 'Active');
      expect(account.ownerControlUnconfirmed(7), isTrue);
      await expectLater(
        account.revoke(7),
        throwsA(apiError(ApiFailure.ownerControlUnconfirmed)),
      );
      expect(
        fake.calls.where((call) => call.uri.path.endsWith('/7/revoke')),
        hasLength(1),
      );
    },
  );

  test('a pending area edit stays with its account and item through reauthentication', () async {
    await login();
    fake.contents = [contentJson(mine: true), contentJson(id: 8, mine: true)];
    await account.refresh();
    const areaPath = '/api/situational/content/7/location';
    final areaReply = Completer<ApiReply>();
    fake.routes[areaPath] = (_) => areaReply.future;
    Future<void> editArea() => account.setLocation(
      7,
      const LocationZone(26, -80, 100),
      isCurrent: () => true,
    );
    final old = expectLater(editArea(), throwsA(apiError(ApiFailure.stale)));
    expect(account.ownerControl(7), (
      OwnerControlAction.editViewingArea,
      OwnerControlPhase.pending,
    ));
    await account.setPolicy(8, 'Paused');
    expect(account.items.last.policyStatus, 'Paused');

    await account.logout();
    await login();
    await account.refresh();
    expect(account.pending(7), isTrue);
    await expectLater(editArea(), throwsA(apiError(ApiFailure.pending)));

    await account.logout();
    fake.userId = 2;
    fake.username = 'second';
    fake.token = 'second-token';
    await account.login('second', 'synthetic-only');
    await account.refresh();
    expect(account.ownerControl(7), isNull);
    await account.revoke(7);
    areaReply.complete(jsonReply({'success': true}));
    await old;
    await account.refresh(); // A later listing still returns Active.
    expect(account.items.first.status, 'Revoked');
    expect(account.items.first.locationZone, isNull);
    expect(account.ownerControl(7), (
      OwnerControlAction.revoke,
      OwnerControlPhase.confirmed,
    ));

    fake.userId = 1;
    fake.username = 'synthetic-user';
    fake.token = 'synthetic-opaque-token';
    await login();
    await account.refresh();
    expect(account.ownerControl(7), (
      OwnerControlAction.editViewingArea,
      OwnerControlPhase.unconfirmed,
    ));
    for (final change in [
      editArea,
      () => account.setPolicy(7, 'Paused'),
      () => account.setPolicy(7, 'Active'),
      () => account.revoke(7),
    ]) {
      await expectLater(
        change(),
        throwsA(apiError(ApiFailure.ownerControlUnconfirmed)),
      );
    }
    await account.setPolicy(8, 'Paused');
    expect(account.items.last.policyStatus, 'Paused');
    expect(fake.calls.where((call) => call.uri.path == areaPath), hasLength(1));
  });

  test(
    'an area acknowledgement supersedes a read started during the write',
    () async {
      await login();
      fake.contents = [contentJson(mine: true)];
      await account.refresh();
      final areaReply = Completer<ApiReply>();
      fake.routes['/api/situational/content/7/location'] = (_) =>
          areaReply.future;
      const area = LocationZone(26, -80, 100);
      final edit = account.setLocation(7, area, isCurrent: () => true);
      final listed = Completer<ApiReply>();
      fake.routes['/api/content'] = (_) => listed.future;
      final refresh = account.refresh();
      expect(account.loading, isTrue);
      areaReply.complete(jsonReply({'success': true}));
      await edit;
      listed.complete(jsonReply(fake.contents));
      await refresh;
      expect(account.loading, isFalse);
      expect(account.items.single.locationZone, area);
      expect(account.ownerControl(7), (
        OwnerControlAction.editViewingArea,
        OwnerControlPhase.confirmed,
      ));
    },
  );

  test(
    'recipient cannot invoke sender operations at the mobile boundary',
    () async {
      await login();
      fake.contents = [contentJson(mine: false)];
      await account.refresh();
      final count = fake.calls.length;
      await expectLater(
        account.revoke(7),
        throwsA(apiError(ApiFailure.denied)),
      );
      expect(
        fake.calls.length,
        count,
      ); // Real owner enforcement remains server-owned.
    },
  );

  test('late list cannot overwrite a confirmed revocation', () async {
    await login();
    fake.contents = [contentJson(mine: true)];
    await account.refresh();
    final pending = Completer<ApiReply>();
    fake.routes['/api/content'] = (_) => pending.future;
    final oldList = account.refresh();
    await account.revoke(7);
    pending.complete(jsonReply([contentJson(mine: true)]));
    await oldList;
    expect(account.items.single.status, 'Revoked');
  });

  test('late mutation after logout cannot affect replacement user', () async {
    await login();
    fake.contents = [contentJson(mine: true)];
    await account.refresh();
    final pending = Completer<ApiReply>();
    fake.routes['/api/content/7/revoke'] = (_) => pending.future;
    final revoke = account.revoke(7);
    await account.logout();
    fake.userId = 2;
    fake.username = 'second';
    await account.login('second', 'synthetic-only');
    pending.complete(jsonReply({'success': true}));
    await expectLater(revoke, throwsA(apiError(ApiFailure.stale)));
    expect(account.items, isEmpty);
    expect(account.user!.id, 2);
  });

  const sessionEnd = '/api/content/sessions/41/end';
  const authLogout = '/api/auth/logout';

  for (final logoutWhilePending in [false, true]) {
    test(
      'logout retries a failed viewing end '
      '${logoutWhilePending ? 'while the issuing account is retiring' : 'after it has settled'}',
      () async {
        await login();
        final oldToken = fake.token;
        final viewing = await account.openViewing(7, account.deviceKey!);
        final pending = Completer<ApiReply>();
        var attempts = 0;
        fake.routes[sessionEnd] = (_) =>
            ++attempts == 1 ? pending.future : jsonReply({'success': true});
        final failedEnd = expectLater(
          account.endViewing(viewing.sessionId!),
          throwsA(apiError(ApiFailure.server)),
        );
        Future<void>? logout;
        if (logoutWhilePending) {
          logout = account.logout();
          expect(account.authenticated, isFalse);
          expect(attempts, 1);
          fake.userId = 2;
          fake.username = 'replacement';
          fake.token = 'replacement-token';
          await account.login('replacement', 'synthetic-only');
        }

        pending.complete(const ApiReply(500, 'synthetic end failure'));
        await failedEnd;
        await (logout ?? account.logout());

        final cleanup = fake.calls.where(
          (call) => {sessionEnd, authLogout}.contains(call.uri.path),
        );
        expect(cleanup.map((call) => call.uri.path), [
          sessionEnd,
          sessionEnd,
          authLogout,
        ]);
        expect(
          cleanup.map((call) => call.headers['Authorization']),
          everyElement('Bearer $oldToken'),
        );
        expect(account.user?.id, logoutWhilePending ? 2 : null);
      },
    );
  }

  test('an already closed viewing session needs no logout retry', () async {
    await login();
    final viewing = await account.openViewing(7, account.deviceKey!);
    fake.routes[sessionEnd] = (_) => const ApiReply(404, '');
    await account.endViewing(viewing.sessionId!);
    await account.logout();
    expect(
      fake.calls.where((call) => call.uri.path == sessionEnd),
      hasLength(1),
    );
  });

  test('disposal lets an already dispatched viewing end finish', () async {
    final transport = ApiFake();
    final session = transport.session();
    await session.login('synthetic-user', 'fixture-password');
    final decision = await session.openViewing(7, session.deviceKey!);
    final pending = Completer<ApiReply>();
    transport.routes['/api/content/sessions/41/end'] = (_) => pending.future;
    final ending = session.endViewing(decision.sessionId!);
    session.dispose();
    expect(session.authenticated, isFalse);
    expect(transport.closed, isFalse);
    expect(
      transport.calls.where((call) => call.uri.path.endsWith('/41/end')),
      hasLength(1),
    );
    pending.complete(jsonReply({'success': true}));
    await ending;
    await Future<void>.delayed(Duration.zero);
    expect(transport.closed, isTrue);
  });

  for (final malformed in [false, true]) {
    test(
      'disposal ends a late ${malformed ? 'malformed' : 'valid'} open',
      () async {
        final transport = ApiFake();
        final session = transport.session();
        await session.login('synthetic-user', 'fixture-password');
        final opening = Completer<ApiReply>();
        final endStarted = Completer<ApiCall>();
        final ending = Completer<ApiReply>();
        transport.routes['/api/content/7/sessions'] = (_) => opening.future;
        transport.routes['/api/content/sessions/41/end'] = (call) {
          endStarted.complete(call);
          return ending.future;
        };

        final result = session.openViewing(7, session.deviceKey!);
        final rejected = expectLater(
          result,
          throwsA(apiError(ApiFailure.stale)),
        );
        session.dispose();
        expect(session.authenticated, isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(transport.closed, isFalse);

        opening.complete(
          jsonReply({
            ...accessJson(),
            if (malformed) 'AccessGranted': 'not a boolean',
          }),
        );
        final end = await endStarted.future;
        expect(end.headers['Authorization'], 'Bearer ${transport.token}');
        await Future<void>.delayed(Duration.zero);
        expect(transport.closed, isFalse);
        ending.complete(const ApiReply(500, 'fixture cleanup failed'));
        await rejected;
        await Future<void>.delayed(Duration.zero);
        expect(transport.closed, isTrue);
        expect(
          transport.calls.where((c) => c.uri.path.endsWith('/41/end')),
          hasLength(1),
        );
      },
    );
  }

  test('no configured API performs no request or prototype fallback', () async {
    account.dispose();
    account = ApiSession(ApiService(baseUri: null, transport: fake));
    await expectLater(login(), throwsA(apiError(ApiFailure.configuration)));
    expect(fake.calls, isEmpty);
    expect(account.authenticated, isFalse);
  });

  test('HTTPS root and safe redirect policy are mandatory configuration', () {
    for (final url in [
      'http://fixture.invalid/',
      'https://user:pass@fixture.invalid/',
      'https://fixture.invalid/?token=x',
      'https://fixture.invalid/#fragment',
    ]) {
      expect(
        () => ApiService(baseUri: Uri.parse(url), transport: fake),
        throwsA(apiError(ApiFailure.configuration)),
      );
    }
  });
  test('logout revokes local account before pending server logout and reports failure', () async {
    await login();
    fake.contents = [contentJson()];
    await account.refresh();
    final pending = Completer<ApiReply>();
    fake.routes['/api/auth/logout'] = (_) => pending.future;
    final ending = account.logout();
    expect(account.authenticated, isFalse);
    expect(account.items, isEmpty);
    expect(account.hasContentListing, isFalse);
    final signedOutIdentity = account.identityVersion;
    await account.logout();
    expect(account.identityVersion, signedOutIdentity);
    pending.complete(const ApiReply(500, 'fixture failure'));
    await ending;
    expect(account.authenticated, isFalse);
    expect(account.logoutWarning, contains('could not be confirmed'));
    expect(
      fake.calls.where((call) => call.uri.path == '/api/auth/logout'),
      hasLength(1),
    );
  });

  test('a late logout failure cannot warn a replacement account', () async {
    await login();
    final pending = Completer<ApiReply>();
    fake.routes['/api/auth/logout'] = (_) => pending.future;
    final ending = account.logout();
    fake.userId = 2;
    fake.token = 'replacement-token';
    await login();
    pending.complete(const ApiReply(500, 'old account private failure'));
    await ending;
    expect(account.user?.id, 2);
    expect(account.logoutWarning, isNull);
  });
  test('invalid calendar/timezone dates are not silently normalized', () {
    for (final value in [
      '2030-02-30T00:00:00Z',
      '2030-13-01T00:00:00Z',
      '2030-01-01T24:00:00Z',
      '2030-01-01T00:00:00+00:99',
    ]) {
      expect(() => apiUtc(value), throwsA(apiError(ApiFailure.malformed)));
    }
  });
}
