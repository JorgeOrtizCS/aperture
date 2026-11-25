import 'dart:async';

import 'package:aperture/main.dart';
import 'package:aperture/models/api_models.dart';
import 'package:aperture/models/location_radius_policy.dart';
import 'package:aperture/screens/api_content_screens.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';

void main() {
  late ApiFake fake;
  late ApiSession account;
  setUp(() {
    fake = ApiFake();
    account = fake.session();
  });

  Future<void> frame(WidgetTester tester) async {
    await tester.idle();
    await tester.pump();
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frame(tester);
  }

  void apiWidgets(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await cleanup(tester);
        account.dispose();
      }
    });
  }

  Future<void> tap(
    WidgetTester tester,
    String text, {
    bool settle = true,
  }) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await frame(tester);
    }
  }

  Future<void> loginForm(
    WidgetTester tester, {
    String username = 'synthetic-user',
  }) async {
    await tester.pumpWidget(ApiApplication(session: account));
    await tap(tester, 'Get Started');
    for (final entry in {
      'login-username': username,
      'login-password': 'synthetic-only',
    }.entries) {
      final field = find.descendant(
        of: find.byKey(ValueKey(entry.key)),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }

  Future<void> status(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);
    fake.contents = [contentJson(mine: true, title: 'Owned synthetic item')];
    await account.login('synthetic-user', 'synthetic-only');
    await account.refresh();
    await tester.pumpWidget(
      MaterialApp(home: ApiContentStatusScreen(account: account, contentId: 7)),
    );
    await tester.pumpAndSettle();
  }

  apiWidgets(
    'dashboard device registration can recheck approval without opening a view',
    (tester) async {
      var trusted = false;
      fake.routes['/api/devices'] = (_) => jsonReply({'trusted': trusted});
      await account.login('synthetic-user', 'synthetic-only');
      await tester.pumpWidget(ApiApplication(session: account));
      await tester.pumpAndSettle();
      await tap(tester, 'Device approval');
      await tap(tester, 'Register this device');
      expect(
        find.textContaining('Backend approval is required'),
        findsOneWidget,
      );
      trusted = true;
      await tap(tester, 'Check device approval again');
      expect(
        find.textContaining('server confirms device approval'),
        findsOneWidget,
      );
      final writes = fake.calls.where((call) => call.method == 'POST').toList();
      expect(writes.map((call) => call.uri.path), [
        '/api/auth/login',
        '/api/devices',
        '/api/devices',
      ]);
      expect(writes.last.json, {
        'DeviceKey': account.deviceKey,
        'DeviceName': 'Aperture mobile device',
      });
    },
  );

  apiWidgets(
    'a stale sender-list callback cannot open a different account’s item',
    (tester) async {
      fake.contents = [contentJson(mine: true, title: 'First sender item')];
      await account.login('synthetic-user', 'synthetic-only');
      await tester.pumpWidget(
        MaterialApp(home: ApiDashboardScreen(account: account)),
      );
      await tester.pumpAndSettle();
      final stale = tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'First sender item'))
          .onTap!;
      await account.logout();
      fake.userId = 2;
      fake.username = 'other-user';
      fake.contents = [contentJson(mine: true, title: 'Other account item')];
      await account.login('other-user', 'synthetic-only');
      await account.refresh();
      await tester.pumpAndSettle();
      stale();
      await tester.pumpAndSettle();
      expect(find.text('Other account item'), findsOneWidget);
      expect(find.text('Content Status'), findsNothing);
    },
  );

  apiWidgets('public HTTP shows the warning and never exposes protected data', (
    tester,
  ) async {
    account.dispose();
    account = ApiSession(
      ApiService(
        baseUri: Uri.parse('http://fixture.invalid/site/'),
        transport: fake,
        schoolDemo: true,
      ),
    );
    fake.routes['/site/api/content/capabilities'] = (_) => jsonReply({
      'success': false,
      'message': 'Authentication required.',
    }, 401);

    await tester.pumpWidget(ApiApplication(session: account));
    final banner = find.text('School demo · Insecure HTTP');
    expect(banner, findsOneWidget);
    expect(fake.calls, isEmpty);
    await tap(tester, 'Get Started');
    expect(banner, findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tap(tester, 'Check API anonymously');
    expect(find.textContaining('expected anonymous 401'), findsOneWidget);
    expect(fake.calls.single.headers, {'Accept': 'application/json'});

    fake.routes['/site/api/content/capabilities'] = (_) => jsonReply([
      {
        'Title': 'SYNTHETIC PROTECTED METADATA',
        'Body': 'SYNTHETIC PRIVATE BODY',
      },
    ]);
    await tap(tester, 'Check API anonymously');
    expect(find.textContaining('unexpected response'), findsOneWidget);
    expect(find.textContaining('SYNTHETIC'), findsNothing);
    expect(find.byType(ApiDashboardScreen), findsNothing);
    expect(account.authenticated, isFalse);
  });

  apiWidgets('password visibility has an accessible action in both states', (
    tester,
  ) async {
    await loginForm(tester);
    final password = find.descendant(
      of: find.byKey(const ValueKey('login-password')),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(password).obscureText, isTrue);

    final show = find.semantics.byLabel('Show password');
    final hide = find.semantics.byLabel('Hide password');
    expect(show, findsOne);
    tester.semantics.tap(show);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(password).obscureText, isFalse);
    expect(show, findsNothing);
    expect(hide, findsOne);

    tester.semantics.tap(hide);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    expect(hide, findsNothing);
    expect(show, findsOne);
  });

  apiWidgets(
    'new account form validates and returns to sign-in after acknowledgement',
    (tester) async {
      await loginForm(tester);
      fake.routes['/api/register'] = (_) => jsonReply({'success': true});
      await tap(tester, 'Create an account');
      await tap(tester, 'Create account');
      expect(
        find.text('Enter a password with at least 8 characters.'),
        findsOneWidget,
      );
      expect(fake.calls, isEmpty);
      for (final (label, text) in [
        ('First name', 'Synthetic'),
        ('Last name', 'Example'),
        ('Username', 'new-user'),
        ('Password', 'test-password'),
      ]) {
        final field = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(field);
        await tester.enterText(field, text);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tap(tester, 'Create account');
      expect(
        find.text('Account created. Sign in with your new credentials.'),
        findsOneWidget,
      );
      final username = find.descendant(
        of: find.byKey(const ValueKey('login-username')),
        matching: find.byType(TextField),
      );
      final password = find.descendant(
        of: find.byKey(const ValueKey('login-password')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(username).controller!.text, 'new-user');
      expect(tester.widget<TextField>(password).controller!.text, isEmpty);
      expect(fake.calls.single.uri.path, '/api/register');
      expect(account.authenticated, isFalse);
    },
  );

  apiWidgets(
    'classroom status is read-only and scoped to the signed-in account',
    (tester) async {
      account.dispose();
      account = ApiSession(
        ApiService(
          baseUri: Uri.parse('http://fixture.invalid/'),
          transport: fake,
          classroomHttp: true,
        ),
        now: () => DateTime.utc(2026, 11, 5),
      );
      fake.username = classroomFixtureSender;
      fake.contents = [
        contentJson(mine: true, title: 'First synthetic account row'),
      ];

      await loginForm(tester, username: classroomFixtureSender);
      final banner = find.text('Insecure HTTP — Classroom Test');
      expect(banner, findsOneWidget);
      expect(find.byTooltip('Show password'), findsNothing);
      await tap(tester, 'Sign In');
      expect(banner, findsOneWidget);
      expect(find.text('Signed in as $classroomFixtureSender'), findsOneWidget);
      expect(find.text('First synthetic account row'), findsOneWidget);
      expect(find.text('Prepare PNG'), findsNothing);
      await tap(tester, 'First synthetic account row');
      expect(find.text('Content Status'), findsOneWidget);
      expect(banner, findsOneWidget);
      expect(find.text('Recipient: synthetic-recipient'), findsOneWidget);
      expect(
        find.text('Classroom Test · Read-only content status.'),
        findsOneWidget,
      );
      expect(find.text('Pause policy'), findsNothing);
      expect(find.text('Resume policy'), findsNothing);
      expect(find.text('Revoke access'), findsNothing);
      expect(find.text('Edit viewing area'), findsNothing);
      fake.contents = [
        contentJson(
          mine: true,
          title: 'First synthetic account row',
          policy: 'Paused',
        ),
      ];
      await tap(tester, 'Refresh status');
      expect(find.text('Policy: Paused'), findsOneWidget);
      expect(find.text('Resume policy'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ApiDashboardScreen), findsOneWidget);
      await tap(tester, 'Sign out');
      expect(find.text('First synthetic account row'), findsNothing);

      fake.username = classroomFixtureRecipient;
      fake.userId = 2;
      fake.contents = [
        {
          ...contentJson(title: 'Second synthetic account row'),
          'Body': 'SYNTHETIC PRIVATE BODY',
          'FileDataBase64': 'SYNTHETIC PRIVATE PNG',
        },
      ];
      await loginForm(tester, username: classroomFixtureRecipient);
      await tap(tester, 'Sign In');
      expect(banner, findsOneWidget);
      expect(
        find.text('Signed in as $classroomFixtureRecipient'),
        findsOneWidget,
      );
      expect(find.text('Second synthetic account row'), findsOneWidget);
      expect(find.text('First synthetic account row'), findsNothing);
      await tap(tester, 'Second synthetic account row');
      expect(find.text('Content Status'), findsOneWidget);
      expect(banner, findsOneWidget);
      expect(find.text('Owner: synthetic-owner'), findsOneWidget);
      expect(find.text('Recipient access: Active'), findsOneWidget);
      expect(find.byType(ApiRecipientScreen), findsNothing);
      expect(find.textContaining('SYNTHETIC PRIVATE'), findsNothing);

      fake.routes['/api/content'] = (_) =>
          jsonReply({'Message': 'server-private-response'}, 401);
      await tap(tester, 'Refresh status');
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Content Status'), findsNothing);
      expect(find.text('Second synthetic account row'), findsNothing);
      expect(find.text('server-private-response'), findsNothing);
      expect(account.authenticated, isFalse);
      expect(fake.calls.map((call) => (call.method, call.uri.path)).toSet(), {
        ('POST', '/api/auth/login'),
        ('GET', '/api/user/me'),
        ('GET', '/api/content'),
        ('POST', '/api/auth/logout'),
      });
    },
  );

  apiWidgets(
    'back cancels pending sign-in and cannot navigate on late success',
    (tester) async {
      final pending = Completer<ApiReply>();
      fake.routes['/api/user/me'] = (_) => pending.future;
      await loginForm(tester);
      await tap(tester, 'Sign In', settle: false);
      expect(account.signingIn, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(account.signingIn, isFalse);
      pending.complete(
        jsonReply({
          'success': true,
          'user': {'id': 1, 'username': 'synthetic-user'},
        }),
      );
      await tester.pumpAndSettle();
      expect(account.authenticated, isFalse);
      expect(find.byType(ApiDashboardScreen), findsNothing);
      expect(find.text('Get Started'), findsOneWidget);
      expect(
        fake.calls.where((c) => c.uri.path.endsWith('/logout')),
        hasLength(1),
      );
    },
  );

  apiWidgets('list error does not also claim an empty successful listing', (
    tester,
  ) async {
    fake.routes['/api/content'] = (_) => const ApiReply(403, '');
    await loginForm(tester);
    await tap(tester, 'Sign In');
    expect(find.byKey(const ValueKey('api-list-error')), findsOneWidget);
    expect(find.text('No shared content is available.'), findsNothing);
    expect(account.authenticated, isTrue);
    fake.routes.remove('/api/content');
    await tap(tester, 'Refresh content');
    expect(find.byKey(const ValueKey('api-list-error')), findsNothing);
    expect(find.text('No shared content is available.'), findsOneWidget);
  });

  apiWidgets('refresh distinguishes loading, last known and refreshed rows', (
    tester,
  ) async {
    fake.contents = [contentJson(title: 'Earlier confirmed share')];
    final initial = Completer<ApiReply>();
    fake.routes['/api/content'] = (_) => initial.future;
    await loginForm(tester);
    await tap(tester, 'Sign In', settle: false);
    await frame(tester);
    expect(find.text('Loading content…'), findsOneWidget);
    expect(find.text('No shared content is available.'), findsNothing);
    initial.complete(jsonReply(fake.contents));
    await tester.pumpAndSettle();
    expect(find.text('Content listing refreshed.'), findsOneWidget);
    expect(find.text('Earlier confirmed share'), findsOneWidget);

    final refresh = Completer<ApiReply>();
    fake.routes['/api/content'] = (_) => refresh.future;
    await tap(tester, 'Refresh content', settle: false);
    expect(
      find.text('Refreshing content. Showing the last known listing.'),
      findsOneWidget,
    );
    expect(find.text('Earlier confirmed share'), findsOneWidget);
    refresh.complete(const ApiReply(200, 'opaque invalid listing'));
    await tester.pumpAndSettle();
    expect(
      find.text('Refresh failed. Showing the last known listing.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('api-list-error')), findsOneWidget);
    expect(find.text('Earlier confirmed share'), findsOneWidget);
    expect(find.text('No shared content is available.'), findsNothing);
    expect(find.textContaining('opaque invalid listing'), findsNothing);
    await tap(tester, 'Earlier confirmed share');
    expect(
      find.textContaining('Last known Shared With Me listing'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    final timedOut = Completer<ApiReply>();
    fake.routes['/api/content'] = (_) => timedOut.future;
    await tap(tester, 'Refresh content', settle: false);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(
      find.text('Refresh failed. Showing the last known listing.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('The listing request timed out'),
      findsOneWidget,
    );
    expect(find.text('Earlier confirmed share'), findsOneWidget);
    timedOut.complete(jsonReply([contentJson(title: 'Late timed-out result')]));
    await tester.pumpAndSettle();
    expect(find.text('Late timed-out result'), findsNothing);

    fake.contents = [];
    fake.routes.remove('/api/content');
    await tap(tester, 'Refresh content');
    expect(find.text('Content listing refreshed.'), findsOneWidget);
    expect(find.text('No shared content is available.'), findsOneWidget);
    expect(find.text('Earlier confirmed share'), findsNothing);
    expect(find.byKey(const ValueKey('api-list-error')), findsNothing);
    expect(fake.calls.map((call) => (call.method, call.uri.path)).toSet(), {
      ('POST', '/api/auth/login'),
      ('GET', '/api/user/me'),
      ('GET', '/api/content'),
    });
    expect(
      fake.calls.where((call) => call.uri.path == '/api/content'),
      hasLength(4),
    );
  });

  apiWidgets('configured login opens only API dashboard metadata', (
    tester,
  ) async {
    fake.contents = [contentJson(title: 'Server fixture item')];
    await loginForm(tester);
    await tap(tester, 'Sign In');
    expect(find.byType(ApiDashboardScreen), findsOneWidget);
    expect(find.text('Server fixture item'), findsOneWidget);
    expect(find.text('Project Document'), findsNothing);
    expect(find.textContaining('Local prototype sign-in'), findsNothing);
  });

  apiWidgets('authentication rejection has error and no sample fallback', (
    tester,
  ) async {
    fake.routes['/api/auth/login'] = (_) =>
        const ApiReply(401, 'synthetic rejection');
    await loginForm(tester);
    await tap(tester, 'Sign In');
    expect(find.textContaining('Sign-in was rejected'), findsOneWidget);
    expect(find.byType(ApiDashboardScreen), findsNothing);
    final password = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('login-password')),
        matching: find.byType(TextField),
      ),
    );
    expect(password.controller!.text, isEmpty);
  });

  apiWidgets('missing configuration keeps real entry locked without requests', (
    tester,
  ) async {
    account.dispose();
    account = ApiSession(ApiService(baseUri: null, transport: fake));
    await loginForm(tester);
    await tap(tester, 'Sign In');
    expect(
      find.textContaining('approved HTTPS API environment'),
      findsOneWidget,
    );
    expect(fake.calls, isEmpty);
    expect(find.byType(ApiDashboardScreen), findsNothing);
  });

  apiWidgets('pending login disables duplicate submit and waits for me', (
    tester,
  ) async {
    final pending = Completer<ApiReply>();
    fake.routes['/api/user/me'] = (_) => pending.future;
    await loginForm(tester);
    await tap(tester, 'Sign In', settle: false);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Signing in…'),
          )
          .onPressed,
      isNull,
    );
    expect(account.authenticated, isFalse);
    pending.complete(
      jsonReply({
        'success': true,
        'user': {'id': 1, 'username': 'synthetic-user'},
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ApiDashboardScreen), findsOneWidget);
  });

  apiWidgets(
    'dashboard network failure shows retry rather than fabricated content',
    (tester) async {
      fake.routes['/api/content'] = (_) => throw StateError('fixture offline');
      await loginForm(tester);
      await tap(tester, 'Sign In');
      expect(find.byKey(const ValueKey('api-list-error')), findsOneWidget);
      expect(find.text('Project Document'), findsNothing);
      fake.routes.remove('/api/content');
      fake.contents = [contentJson(title: 'Retried fixture')];
      await tap(tester, 'Refresh content');
      expect(find.text('Retried fixture'), findsOneWidget);
    },
  );

  apiWidgets(
    'logout removes navigator stack and late list cannot return private metadata',
    (tester) async {
      final pending = Completer<ApiReply>();
      fake.routes['/api/content'] = (_) => pending.future;
      await loginForm(tester);
      await tap(tester, 'Sign In', settle: false);
      await frame(tester);
      await account.logout();
      await tester.pumpAndSettle();
      expect(find.text('Get Started'), findsOneWidget);
      pending.complete(
        jsonReply([contentJson(title: 'OLD USER PRIVATE METADATA')]),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('OLD USER PRIVATE METADATA', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byType(ApiDashboardScreen, skipOffstage: false),
        findsNothing,
      );
    },
  );

  apiWidgets('unconfirmed server sign-out warns on Welcome and Sign In', (
    tester,
  ) async {
    final pending = Completer<ApiReply>();
    fake.contents = [contentJson(title: 'Private signed-out metadata')];
    fake.routes['/api/auth/logout'] = (_) => pending.future;
    await loginForm(tester);
    await tap(tester, 'Sign In');
    expect(find.text('Private signed-out metadata'), findsOneWidget);
    await tap(tester, 'Sign out', settle: false);
    final warning = find.text(
      'Signed out locally. Server sign-out could not be confirmed.',
    );
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.byType(ApiDashboardScreen, skipOffstage: false), findsNothing);
    expect(
      find.text('Private signed-out metadata', skipOffstage: false),
      findsNothing,
    );
    expect(account.authenticated, isFalse);
    expect(account.items, isEmpty);
    expect(warning, findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(warning, findsOneWidget);
    await tap(tester, 'Get Started');
    expect(warning, findsOneWidget);
    expect(
      fake.calls.where((call) => call.uri.path == '/api/auth/logout'),
      hasLength(1),
    );
    pending.complete(jsonReply({'success': true}));
    await tester.pumpAndSettle();
    expect(warning, findsOneWidget);
  });

  apiWidgets('credential expiry removes an authenticated navigation stack', (
    tester,
  ) async {
    fake.expiresAt = DateTime.utc(2026, 11, 5).add(const Duration(minutes: 1));
    await loginForm(tester);
    await tap(tester, 'Sign In');
    expect(find.byType(ApiDashboardScreen), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.byType(ApiDashboardScreen, skipOffstage: false), findsNothing);
    expect(account.items, isEmpty);
  });

  for (final expiresWhileAway in [true, false]) {
    apiWidgets('foreground reconciles absolute expiry ($expiresWhileAway)', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var wallClock = DateTime.utc(2026, 11, 5);
      account.dispose();
      account = ApiSession(fake.service(), now: () => wallClock);
      fake.expiresAt = wallClock.add(const Duration(hours: 1));
      fake.contents = [contentJson(title: 'Account metadata')];
      await loginForm(tester);
      await tap(tester, 'Sign In');
      await tap(tester, 'Prepare PNG');
      expect(find.text('Prepare a local draft'), findsOneWidget);
      final identity = account.identityVersion;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }

      // Move wall time without advancing the test timer scheduled at sign-in.
      wallClock = wallClock.add(Duration(minutes: expiresWhileAway ? 61 : 59));
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      if (expiresWhileAway) {
        expect(find.text('Get Started'), findsOneWidget);
        expect(
          find.text('Prepare a local draft', skipOffstage: false),
          findsNothing,
        );
        expect(account.identityVersion, greaterThan(identity));
        expect(account.items, isEmpty);
      } else {
        expect(find.text('Prepare a local draft'), findsOneWidget);
        expect(account.authenticated, isTrue);
        expect(account.identityVersion, identity);
      }
      expect(
        fake.calls.where((call) => call.uri.path == '/api/auth/logout'),
        isEmpty,
      );
    });
  }

  apiWidgets('an old absolute expiry cannot sign out a newer account', (
    tester,
  ) async {
    fake.expiresAt = DateTime.utc(2026, 11, 5).add(const Duration(minutes: 1));
    await loginForm(tester);
    await tap(tester, 'Sign In');
    await account.logout();
    fake.userId = 2;
    fake.username = 'newer-user';
    fake.token = 'newer-token';
    fake.expiresAt = DateTime.utc(2026, 11, 5, 8);
    await account.login('newer-user', 'synthetic-only');
    await tester.pumpAndSettle();
    final identity = account.identityVersion;
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(account.user?.id, 2);
    expect(account.identityVersion, identity);
    expect(find.text('Signed in as newer-user'), findsOneWidget);
  });

  apiWidgets('revocation confirmation can be cancelled without request', (
    tester,
  ) async {
    await status(tester);
    await tap(tester, 'Revoke access');
    await tap(tester, 'Cancel');
    expect(fake.calls.where((c) => c.uri.path.endsWith('/revoke')), isEmpty);
    expect(find.text('Recipient access: Active'), findsOneWidget);
  });

  apiWidgets(
    'sender revocation shows pending, then confirmed revoked with no restore',
    (tester) async {
      await status(tester);
      final pending = Completer<ApiReply>();
      fake.routes['/api/content/7/revoke'] = (_) => pending.future;
      await tap(tester, 'Revoke access');
      await tap(tester, 'Confirm revocation', settle: false);
      expect(find.text('Recipient access: Active'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('api-write-confirmation')),
        findsNothing,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Request pending…'),
            )
            .onPressed,
        isNull,
      );
      pending.complete(jsonReply({'success': true}));
      await tester.pumpAndSettle();
      expect(find.text('Recipient access: Revoked'), findsOneWidget);
      expect(find.text('Revocation confirmed by the server.'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Restore Access'),
        findsNothing,
      );
      expect(find.text('Revoke access'), findsNothing);
    },
  );

  apiWidgets('unconfirmed revocation permits only a read-only status refresh', (
    tester,
  ) async {
    await status(tester);
    fake.routes['/api/content/7/revoke'] = (_) =>
        const ApiReply(500, 'synthetic server failure');
    await tap(tester, 'Revoke access');
    await tap(tester, 'Confirm revocation');
    expect(find.text('Recipient access: Active'), findsOneWidget);
    expect(find.byKey(const ValueKey('api-write-unconfirmed')), findsOneWidget);
    expect(find.byKey(const ValueKey('api-write-confirmation')), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Revoke access'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Pause policy'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Edit viewing area'),
          )
          .onPressed,
      isNull,
    );

    final readError = find.byKey(const ValueKey('api-status-refresh-error'));
    fake.routes['/api/content'] = (_) => const ApiReply(500, 'private details');
    await tap(tester, 'Refresh status');
    expect(readError, findsOneWidget);
    expect(find.byKey(const ValueKey('api-write-unconfirmed')), findsOneWidget);
    fake.routes.remove('/api/content');
    final before = fake.calls.length;
    fake.contents = [contentJson(mine: true, status: 'Revoked')];
    await tap(tester, 'Refresh status');
    expect(fake.calls.skip(before).single.method, 'GET');
    expect(find.text('Recipient access: Revoked'), findsOneWidget);
    expect(
      find.text('synthetic-recipient · Access: Revoked · Policy: Active'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('api-write-unconfirmed')), findsOneWidget);
    expect(find.byKey(const ValueKey('api-write-confirmation')), findsNothing);
    expect(readError, findsNothing);
    expect(
      fake.calls.where((call) => call.uri.path.endsWith('/revoke')),
      hasLength(1),
    );
  });

  apiWidgets('owner time editor saves and reads back the stored window', (
    tester,
  ) async {
    const path = '/api/situational/content/7/time';
    const start = '2026-11-06T14:00:00.000Z';
    String? storedStart;
    String? storedExpiry = '2026-11-07T12:00:00.000Z';
    await status(tester);
    fake.routes[path] = (call) {
      if (call.method == 'POST') {
        final body = call.json as Map<String, dynamic>;
        expect(body, {'StartTime': start, 'ExpiresAt': null});
        storedStart = body['StartTime'] as String?;
        storedExpiry = body['ExpiresAt'] as String?;
        fake.contents.single
          ..['StartTime'] = storedStart
          ..['ExpiresAt'] = storedExpiry;
        return jsonReply({'success': true});
      }
      return jsonReply({
        'passed': storedStart == null,
        'reason': storedStart == null ? null : 'Access has not begun.',
        'startTime': storedStart,
        'expiresAt': storedExpiry,
      });
    };
    await tap(tester, 'Edit viewing time');
    final startField = find.widgetWithText(TextField, 'Viewing start');
    final expiryField = find.widgetWithText(TextField, 'Viewing expiration');
    final save = find.widgetWithText(ElevatedButton, 'Save viewing time');
    expect(
      tester.widget<TextField>(expiryField).controller!.text,
      storedExpiry,
    );
    expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
    await tester.enterText(startField, '2026-11-06T14:00:00');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
    await tester.enterText(startField, '2026-11-06T09:00:00-05:00');
    await tester.enterText(expiryField, '');
    await tester.pump();
    await tap(tester, 'Save viewing time');
    expect(find.text('Viewing time confirmed by the server.'), findsOneWidget);
    expect(tester.widget<TextField>(startField).controller!.text, start);
    expect(tester.widget<TextField>(expiryField).controller!.text, isEmpty);
    expect(
      fake.calls
          .where((call) => call.uri.path == path)
          .map((call) => call.method),
      ['GET', 'POST', 'GET'],
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Listed viewing start: $start'), findsOneWidget);
    expect(
      find.text('Viewing time update acknowledged by the server.'),
      findsOneWidget,
    );
  });

  apiWidgets(
    'leaving a pending time edit keeps owner actions blocked on return',
    (tester) async {
      const path = '/api/situational/content/7/time';
      final pending = Completer<ApiReply>();
      await status(tester);
      fake.routes[path] = (call) => call.method == 'POST'
          ? pending.future
          : jsonReply({
              'passed': true,
              'reason': null,
              'startTime': null,
              'expiresAt': null,
            });
      await tap(tester, 'Edit viewing time');
      await tester.enterText(
        find.widgetWithText(TextField, 'Viewing start'),
        '2026-11-06T14:00:00Z',
      );
      await tester.pump();
      await tap(tester, 'Save viewing time', settle: false);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(account.pending(7), isTrue);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Refresh status'),
            )
            .onPressed,
        isNotNull,
      );
      for (final label in [
        'Pause policy',
        'Revoke access',
        'Edit viewing area',
      ]) {
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, label),
              )
              .onPressed,
          isNull,
        );
      }
      pending.complete(jsonReply({'success': true}));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('previous viewing-time update remains unconfirmed'),
        findsOneWidget,
      );
      await tap(tester, 'Refresh status');
      await tap(tester, 'Review viewing time');
      expect(
        find.textContaining('Authoritative reconciliation is required'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Save viewing time'),
            )
            .onPressed,
        isNull,
      );
      expect(
        fake.calls.where(
          (call) => call.uri.path == path && call.method == 'POST',
        ),
        hasLength(1),
      );
    },
  );

  apiWidgets(
    'an acknowledged time edit with different read-back requires refresh',
    (tester) async {
      const path = '/api/situational/content/7/time';
      await status(tester);
      fake.routes[path] = (call) => call.method == 'POST'
          ? jsonReply({'success': true})
          : jsonReply({
              'passed': true,
              'reason': null,
              'startTime': null,
              'expiresAt': null,
            });
      await tap(tester, 'Edit viewing time');
      await tester.enterText(
        find.widgetWithText(TextField, 'Viewing start'),
        '2026-11-06T14:00:00Z',
      );
      await tester.pump();
      await tap(tester, 'Save viewing time');
      expect(
        find.textContaining(
          'acknowledged the update, but returned a different window',
        ),
        findsOneWidget,
      );
      expect(account.ownerControl(7)?.$2, OwnerControlPhase.confirmed);
      final save = find.widgetWithText(ElevatedButton, 'Save viewing time');
      expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
      await tap(tester, 'Refresh viewing time');
      expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
      expect(
        fake.calls.where(
          (call) => call.uri.path == path && call.method == 'POST',
        ),
        hasLength(1),
      );
    },
  );

  apiWidgets('pause/resume UI waits for backend acknowledgement and refresh', (
    tester,
  ) async {
    await status(tester);
    final pending = Completer<ApiReply>();
    fake.routes['/api/content/7/policy'] = (_) => pending.future;
    await tap(tester, 'Pause policy', settle: false);
    expect(find.text('Policy: Active'), findsOneWidget);
    fake.contents = [
      contentJson(mine: true, title: 'Owned synthetic item', policy: 'Paused'),
    ];
    pending.complete(jsonReply({'status': 'Paused'}));
    await tester.pumpAndSettle();
    expect(find.text('Policy: Paused'), findsOneWidget);
    expect(find.text('Policy Paused confirmed by the server.'), findsOneWidget);
    expect(find.text('Resume policy'), findsOneWidget);
    expect(find.text('Recipient access: Active'), findsOneWidget);
    fake.routes.remove('/api/content/7/policy');
    fake.contents = [contentJson(mine: true, title: 'Owned synthetic item')];
    await tap(tester, 'Resume policy');
    expect(find.text('Policy: Active'), findsOneWidget);
    expect(find.text('Policy Active confirmed by the server.'), findsOneWidget);
  });

  apiWidgets('definitive rejection explains that it did not apply a change', (
    tester,
  ) async {
    await status(tester);
    fake.routes['/api/content/7/policy'] = (_) =>
        const ApiReply(404, 'owner match not found');
    await tap(tester, 'Pause policy');
    expect(
      find.text('The pause request was rejected before a change was applied.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('api-write-unconfirmed')), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Pause policy'),
          )
          .onPressed,
      isNotNull,
    );
  });

  apiWidgets('unconfirmed owner state survives route exit and re-entry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);
    fake.contents = [contentJson(mine: true, title: 'Owned synthetic item')];
    await account.login('synthetic-user', 'synthetic-only');
    await tester.pumpWidget(ApiApplication(session: account));
    await tester.pumpAndSettle();
    await tap(tester, 'Owned synthetic item');
    fake.routes['/api/content/7/policy'] = (_) =>
        throw StateError('transport interrupted');
    await tap(tester, 'Pause policy');
    expect(find.byKey(const ValueKey('api-write-unconfirmed')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, 'Owned synthetic item');
    expect(find.byKey(const ValueKey('api-write-unconfirmed')), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Pause policy'),
          )
          .onPressed,
      isNull,
    );
    expect(
      fake.calls.where((call) => call.uri.path.endsWith('/policy')),
      hasLength(1),
    );
    fake.contents = [];
    await tap(tester, 'Refresh status');
    expect(find.text('No matching listed item is available.'), findsOneWidget);
    expect(find.byKey(const ValueKey('api-write-unconfirmed')), findsOneWidget);
    expect(find.text('Refresh status'), findsOneWidget);
  });

  apiWidgets('status re-entry and every listing refresh retain the area hold', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);
    const areaPath = '/api/situational/content/7/location';
    const requested = LocationZone(26, -80, 100);
    const earlier = LocationZone(25, -81, 500);
    Map<String, Object?> row(LocationZone zone, {String policy = 'Active'}) => {
      ...contentJson(mine: true, title: 'Owned synthetic item', policy: policy),
      'Latitude': zone.latitude,
      'Longitude': zone.longitude,
      'RadiusMeters': zone.radiusMeters,
    };
    fake.contents = [row(earlier)];
    fake.routes[areaPath] = (_) => const ApiReply(200, '{}');
    await account.login('synthetic-user', 'synthetic-only');
    await tester.pumpWidget(ApiApplication(session: account));
    await tester.pumpAndSettle();
    await tap(tester, 'Owned synthetic item');
    await expectLater(
      account.setLocation(7, requested, isCurrent: () => true),
      throwsA(isA<ApiException>()),
    );
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, 'Owned synthetic item');

    final unknown = find.byKey(const ValueKey('api-write-unconfirmed'));
    final refreshError = find.byKey(const ValueKey('api-status-refresh-error'));
    void expectLocked(String policyAction) {
      expect(unknown, findsOneWidget);
      expect(
        find.textContaining('previous viewing-area update remains unconfirmed'),
        findsOneWidget,
      );
      expect(find.text('Recipient access: Active'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('api-write-confirmation')),
        findsNothing,
      );
      for (final label in [policyAction, 'Revoke access']) {
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, label),
              )
              .onPressed,
          isNull,
        );
      }
    }

    Future<void> refresh() async {
      final before = fake.calls.length;
      await tap(tester, 'Refresh status');
      final request = fake.calls.skip(before).single;
      expect(request.method, 'GET');
      expect(request.uri.path, '/api/content');
    }

    expectLocked('Pause policy');
    fake.routes['/api/content'] = (_) => const ApiReply(500, 'not available');
    await refresh();
    expect(refreshError, findsOneWidget);
    expectLocked('Pause policy');
    fake.routes.remove('/api/content');
    fake.contents = [row(requested)];
    await refresh();
    expect(refreshError, findsNothing);
    expect(account.items.single.locationZone, requested);
    expectLocked('Pause policy');
    fake.contents = [row(earlier, policy: 'Paused')];
    await refresh();
    expect(account.items.single.locationZone, earlier);
    expectLocked('Resume policy');
    expect(fake.calls.where((call) => call.uri.path == areaPath), hasLength(1));
  });

  apiWidgets(
    'late acknowledgement and stale callbacks stay with the original item',
    (tester) async {
      await status(tester);
      fake.contents.add(
        contentJson(id: 8, mine: true, title: 'Other owned item'),
      );
      await account.refresh();
      final pending = Completer<ApiReply>();
      fake.routes['/api/content/7/policy'] = (_) => pending.future;
      final oldPause = tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Pause policy'),
          )
          .onPressed!;
      oldPause();
      oldPause();
      await frame(tester);
      expect(
        find.textContaining('Waiting for the pause acknowledgement'),
        findsOneWidget,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ApiContentStatusScreen(account: account, contentId: 8),
        ),
      );
      oldPause();
      final count = fake.calls.length;
      pending.complete(jsonReply({'status': 'Paused'}));
      await tester.pumpAndSettle();
      expect(fake.calls.length, count);
      expect(find.text('Other owned item'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('api-write-confirmation')),
        findsNothing,
      );
      expect(find.text('Policy: Active'), findsOneWidget);
      expect(account.items.first.policyStatus, 'Paused');
      await tap(tester, 'Pause policy');
      expect(
        fake.calls.where((call) => call.uri.path == '/api/content/8/policy'),
        hasLength(1),
      );
    },
  );

  apiWidgets('confirmed revoke is retained when follow-up refresh fails', (
    tester,
  ) async {
    await status(tester);
    fake.routes['/api/content'] = (_) =>
        throw StateError('synthetic offline after acknowledgement');
    await tap(tester, 'Revoke access');
    await tap(tester, 'Confirm revocation');
    expect(find.text('Recipient access: Revoked'), findsOneWidget);
    expect(
      find.textContaining(
        'Revocation confirmed by the server. Status refresh is unavailable',
      ),
      findsOneWidget,
    );
    fake.routes.remove('/api/content');
    await tap(tester, 'Refresh status');
    expect(find.text('Recipient access: Revoked'), findsOneWidget);
    expect(
      find.text('synthetic-recipient · Access: Active · Policy: Active'),
      findsOneWidget,
    );
    expect(find.text('Revoke access'), findsNothing);
    expect(find.byKey(const ValueKey('api-write-unconfirmed')), findsNothing);
  });

  apiWidgets('sender status does not expose another account after logout', (
    tester,
  ) async {
    await status(tester);
    await account.logout();
    await tester.pumpAndSettle();
    expect(
      find.text('Owned synthetic item', skipOffstage: false),
      findsNothing,
    );
    expect(find.text('Content unavailable to this account.'), findsOneWidget);
  });

  apiWidgets('incoming route rebases on the current recipient listing', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1100);
    addTearDown(tester.view.reset);
    fake.contents = [
      {
        ...contentJson(title: 'First incoming'),
        'ExpiresAt': '2026-11-06T08:00:00Z',
      },
      contentJson(id: 8, title: 'Another incoming'),
      contentJson(id: 9, mine: true, title: 'Sender item'),
    ];
    await account.login('synthetic-user', 'synthetic-only');
    await tester.pumpWidget(ApiApplication(session: account));
    await tester.pumpAndSettle();
    expect(find.text('Shared With Me'), findsOneWidget);
    final staleTap = tester
        .widget<ListTile>(find.widgetWithText(ListTile, 'First incoming'))
        .onTap!;
    await tap(tester, 'First incoming');
    expect(find.text('Recipient access'), findsOneWidget);
    expect(find.text('Shared by synthetic-owner'), findsOneWidget);
    expect(find.text('Protected display unavailable'), findsOneWidget);
    expect(find.textContaining('Listed viewing deadline'), findsOneWidget);
    expect(find.textContaining('precise foreground location'), findsNothing);
    expect(
      find.textContaining('Server authorization has not been checked'),
      findsOneWidget,
    );
    expect(find.text('Another incoming'), findsNothing);
    expect(find.text('Sender item'), findsNothing);
    expect(find.text('Open Demo Preview'), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Open security checks'),
          )
          .onPressed,
      isNull,
    );
    fake.contents = [contentJson(id: 8, title: 'Another incoming')];
    await account.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Content unavailable to this account.'), findsOneWidget);
    expect(find.text('First incoming', skipOffstage: false), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    staleTap();
    await tester.pumpAndSettle();
    expect(find.byType(ApiRecipientScreen), findsNothing);
    await tap(tester, 'Another incoming');
    expect(find.text('Another incoming'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, 'Another incoming');
    expect(
      find.textContaining('Server authorization has not been checked'),
      findsOneWidget,
    );
    expect(
      fake.calls.where((call) => call.uri.path.endsWith('/sessions')),
      isEmpty,
    );
  });

  for (final (status, policy, guidance) in [
    ('Revoked', 'Active', 'The listing reports revoked access.'),
    ('Denied', 'Active', 'The listing reports denied access.'),
    ('Active', 'Paused', 'The listing reports a sender pause.'),
  ]) {
    apiWidgets('recipient listing $status/$policy remains locked', (
      tester,
    ) async {
      fake.contents = [
        contentJson(title: 'Locked share', status: status, policy: policy),
      ];
      await account.login('synthetic-user', 'synthetic-only');
      await account.refresh();
      await tester.pumpWidget(
        MaterialApp(home: ApiRecipientScreen(account: account, contentId: 7)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(guidance), findsOneWidget);
      expect(find.text('Protected display unavailable'), findsOneWidget);
      expect(find.text('Open security checks'), findsNothing);
      expect(find.text('Check Conditions'), findsNothing);
      expect(find.text('Register this device'), findsNothing);
      expect(
        fake.calls.where((call) => call.uri.path.endsWith('/sessions')),
        isEmpty,
      );
    });
  }

  apiWidgets(
    'stale incoming navigation follows the denied listing and leaves owner status read-only',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1100);
      addTearDown(tester.view.reset);
      fake.contents = [
        contentJson(title: 'Incoming synthetic item'),
        contentJson(
          id: 8,
          mine: true,
          title: 'Owned denied item',
          status: 'Denied',
        ),
        contentJson(id: 9, mine: true, title: 'Owned active item'),
      ];
      await account.login('synthetic-user', 'synthetic-only');
      await tester.pumpWidget(ApiApplication(session: account));
      await tester.pumpAndSettle();
      final incoming = find.widgetWithText(ListTile, 'Incoming synthetic item');
      final staleTap = tester.widget<ListTile>(incoming).onTap!;
      fake.contents.first['Status'] = 'Denied';
      await account.refresh();
      await tester.pumpAndSettle();
      staleTap();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The listing reports denied access.'),
        findsOneWidget,
      );
      expect(find.text('Open security checks'), findsNothing);
      expect(find.text('Check Conditions'), findsNothing);
      expect(find.text('Edit viewing time'), findsNothing);
      expect(find.text('Revoke access'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, 'Owned denied item');
      expect(find.text('Recipient access: Denied'), findsOneWidget);
      expect(find.text('Pause policy'), findsNothing);
      expect(find.text('Edit viewing area'), findsNothing);
      expect(find.text('Edit viewing time'), findsNothing);
      expect(find.text('Revoke access'), findsNothing);
      expect(find.text('Refresh status'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, 'Owned active item');
      expect(find.text('Recipient access: Active'), findsOneWidget);
      expect(find.text('Pause policy'), findsOneWidget);
      expect(
        fake.calls.where((call) => call.uri.path.contains('/api/content/')),
        isEmpty,
      );
    },
  );

  apiWidgets('revocation timeout shows unknown outcome without false success', (
    tester,
  ) async {
    await status(tester);
    final pending = Completer<ApiReply>();
    fake.routes['/api/content/7/revoke'] = (_) => pending.future;
    await tap(tester, 'Revoke access');
    await tap(tester, 'Confirm revocation', settle: false);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Recipient access: Active'), findsOneWidget);
    expect(find.textContaining('server outcome is unknown'), findsOneWidget);
    expect(find.byKey(const ValueKey('api-write-confirmation')), findsNothing);
    pending.complete(jsonReply({'success': true}));
    await frame(tester);
    expect(find.text('Recipient access: Active'), findsOneWidget);
  });
  apiWidgets(
    'content-wide revoke shows every recipient and revokes all only after ack',
    (tester) async {
      fake.contents = [
        contentJson(mine: true, status: 'Revoked')
          ..['Recipient'] = 'first-recipient',
        contentJson(mine: true)..['Recipient'] = 'second-recipient',
      ];
      await account.login('synthetic-user', 'fixture-only');
      await account.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: ApiContentStatusScreen(account: account, contentId: 7),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recipient: first-recipient'), findsOneWidget);
      expect(find.text('Recipient: second-recipient'), findsOneWidget);
      expect(find.text('Recipient access: Active'), findsOneWidget);
      await tap(tester, 'Revoke access');
      expect(find.textContaining('every recipient'), findsOneWidget);
      await tap(tester, 'Confirm revocation');
      expect(account.items.every((item) => item.status == 'Revoked'), isTrue);
      expect(
        fake.calls.where((c) => c.uri.path.endsWith('/7/revoke')).length,
        1,
      );
    },
  );
}
