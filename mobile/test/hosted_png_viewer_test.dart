import 'dart:async';
import 'dart:convert';

import 'package:aperture/models/api_models.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/biometric_verification.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/widgets/recipient_png_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/hosted_png_viewer.dart';
import '../tool/hosted_png_viewer_transport.dart';
import '../tool/flutter_png_fixture_spec.dart';
import '../tool/temporary_png_demo_fixture.dart';
import 'support/biometric_fake.dart';
import 'support/hosted_png_fixture_api.dart';
import 'support/viewing_test_fakes.dart';

void main() {
  const open = ('POST', '/api/content/$hostedPngContentId/sessions');
  const sid = HostedPngFixtureApi.session;
  const check = ('POST', '/api/content/sessions/$sid/check');
  const end = ('POST', '/api/content/sessions/$sid/end');
  const logout = ('POST', '/api/auth/logout');
  const credential = 'Bearer ${HostedPngFixtureApi.token}';
  const openLabel = 'Verify identity and open PNG';
  final renderer = find.byType(RecipientPngRenderer);
  final pixels = find.byType(RawImage);
  late HostedPngFixtureApi server;
  late NativeCaptureFake capture;
  late HostedPngTransport transport;
  late BiometricFake biometrics;
  late GlobalKey<NavigatorState> navigator;

  setUp(() {
    server = HostedPngFixtureApi();
    transport = HostedPngTransport(server);
    capture = NativeCaptureFake()..install();
    biometrics = BiometricFake();
    navigator = GlobalKey<NavigatorState>();
  });

  test(
    'fresh live pin refuses archived IDs and verifies exact title and limit',
    () async {
      for (final id in [0, ...flutterPngFixtureArchivedIds]) {
        expect(
          () => HostedPngTransport.forFlutterAcceptance(server, id),
          throwsA(isA<ApiException>()),
        );
      }
      const nextId = 72;
      expect(
        () => HostedPngTransport.forFlutterAcceptance(
          server,
          nextId,
          archivedIds: {nextId},
        ),
        throwsA(isA<ApiException>()),
      );
      expect(server.routes, isEmpty);
      final fresh = HostedPngFixtureApi(
        contentId: nextId,
        title: flutterPngFixtureTitle,
        maxViews: flutterPngFixtureMaxViews,
      );
      final pinned = HostedPngTransport.forFlutterAcceptance(fresh, nextId);
      final api = ApiService.fixture(transport: pinned);
      addTearDown(api.close);
      final auth = await api.login(hostedPngRecipient, 'fixture');
      await api.currentUser(auth.token);
      for (final (key, value) in [
        ('Id', 73),
        ('Title', hostedPngTitle),
        ('MaxViews', 2),
        ('RemainingViews', 0),
      ]) {
        fresh.metadataOverrides[key] = value;
        expect(await api.list(auth.token), isEmpty);
        expect(pinned.begin(1, () async => true), isFalse);
        fresh.metadataOverrides.clear();
      }
      expect((await api.list(auth.token)).single.id, nextId);
      expect(pinned.begin(1, () async => true), isTrue);
      await expectLater(
        api.open(
          auth.token,
          hostedPngContentId,
          '11111111-1111-4111-8111-111111111111',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        fresh.routes.where((route) => route.$2.endsWith('/sessions')),
        isEmpty,
      );
    },
  );

  Future<void> mount(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: HostedPngViewer(
          transport: transport,
          biometricAuthenticator: biometrics,
          captureProtection: ScreenCaptureProtection.forTesting(),
        ),
      ),
    );
    expect(find.text(hostedPngLabel), findsOneWidget);
    // Dispose the route and allow its cleanup and optional logout to complete.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.enterText(find.byType(TextField), 'fixture only');
    await tester.tap(find.text('Sign in as approved recipient'));
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.text(openLabel));
    await tester.pumpAndSettle();
  }

  Future<void> paint(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (pixels.evaluate().any(
        (el) => (el.widget as RawImage).image != null,
      )) {
        return;
      }
    }
  }

  test(
    'live factory needs opt-in and transport rejects unapproved routes',
    () async {
      expect(
        () => HostedPngTransport.live('http://classroom.fixture.invalid/'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => HostedPngTransport.live('http://example.test/'),
        throwsA(isA<ApiException>()),
      );
      final api = ApiService.fixture(transport: transport);
      await expectLater(
        api.login(classroomFixtureSender, 'unused'),
        throwsA(isA<ApiException>()),
      );
      expect(server.routes, isEmpty);

      final auth = await api.login(hostedPngRecipient, 'fixture');
      await api.currentUser(auth.token);
      await api.list(auth.token);
      expect(transport.begin(1, () async => true), isTrue);
      for (final path in [
        '/api/content',
        '/api/content/13/sessions',
        '/api/content/$hostedPngContentId/policy',
        '/api/content/sessions/$sid/check',
        '/api/content/sessions/$sid/end',
      ]) {
        await expectLater(
          transport.send('POST', Uri(path: path), {
            'Authorization': credential,
          }, null),
          throwsA(isA<ApiException>()),
        );
      }
      expect(server.routes.map((route) => route.$1), ['POST', 'GET', 'GET']);
      api.close();
    },
  );

  testWidgets(
    'valid grant renders delivered bytes only after both native gates',
    (tester) async {
      capture.enabling = Completer<bool>();
      biometrics.pending = Completer<BiometricState>();
      await mount(tester);
      await tester.tap(find.text(openLabel));
      await tester.pump();
      expect(server.routes, isNot(contains(open)));
      expect(renderer, findsNothing);

      biometrics.pending!.complete(BiometricState.verified);
      await tester.pump();
      expect(capture.enables, 1);
      expect(server.routes, isNot(contains(open)));
      capture.enabling!.complete(false);
      await tester.pumpAndSettle();
      await paint(tester);
      expect(server.routes.where((route) => route == open), hasLength(1));
      expect(tester.widget<RawImage>(pixels).image?.width, 320);
      expect(tester.widget<RawImage>(pixels).image?.height, 180);
      expect(
        () => transport.take(1, sid),
        throwsA(isA<ApiException>()),
        reason: 'The renderer took ownership of the single available buffer.',
      );
      await tester.tap(find.text('End viewing'));
      await tester.pumpAndSettle();
      expect(renderer, findsNothing);
      expect(server.cleanupCredentials, [credential]);
      expect(find.text(openLabel), findsNothing);
    },
  );

  for (final (name, alter) in <(String, void Function(HostedPngFixtureApi))>[
    ('wrong identity', (s) => s.username = classroomFixtureSender),
    ('expired credential', (s) => s.expired = true),
    ('wrong content ID', (s) => s.metadataOverrides['Id'] = 13),
    ('consumed view limit', (s) => s.metadataOverrides['RemainingViews'] = 0),
    ('revoked access', (s) => s.metadataOverrides['Status'] = 'Revoked'),
    (
      'required location',
      (s) => s.metadataOverrides['AllowedCity'] = 'Classroom',
    ),
    (
      'required device',
      (s) => s.metadataOverrides['RequireTrustedDevice'] = true,
    ),
  ]) {
    testWidgets('$name prevents a session from opening', (tester) async {
      alter(server);
      await mount(tester);
      expect(find.text(openLabel), findsNothing);
      expect(server.routes, isNot(contains(open)));
      expect(renderer, findsNothing);
      expect(biometrics.starts, 0);
    });
  }

  for (final (key, value) in <(String, Object?)>[
    (
      'FileDataBase64',
      '${classroomSyntheticPng.substring(0, 6)}E${classroomSyntheticPng.substring(7)}',
    ),
    ('FileType', 'image/jpeg'),
    ('ContentId', 13),
    ('SessionId', 0),
    ('SessionEnded', true),
    ('AccessGranted', null),
    ('ExpiresAt', '2000-01-01T00:00:00Z'),
    ('LocationVerified', false),
    ('CameraRestrictions', const {'Enabled': true}),
  ]) {
    testWidgets('rejects conflicting grant field $key', (tester) async {
      server.grantOverrides[key] = value;
      await mount(tester);
      await start(tester);
      expect(renderer, findsNothing);
      expect(server.routes.where((route) => route == open), hasLength(1));
      expect(find.text(openLabel), findsNothing);
      expect(
        server.cleanupCredentials,
        const {'SessionId', 'ContentId'}.contains(key) ? isEmpty : [credential],
      );
    });
  }

  testWidgets('biometric cancellation prevents the server open', (
    tester,
  ) async {
    biometrics.result = BiometricState.cancelled;
    await mount(tester);
    await start(tester);
    expect(server.routes, isNot(contains(open)));
    expect(renderer, findsNothing);
  });

  testWidgets('capture protection failure prevents the server open', (
    tester,
  ) async {
    capture.nullResult = true;
    await mount(tester);
    await start(tester);
    expect(server.routes, isNot(contains(open)));
    expect(renderer, findsNothing);
  });

  for (final event in [
    'pause',
    'revoke',
    'capture',
    'screenshot',
    'background',
    'route',
    'logout',
    'end',
  ]) {
    testWidgets('$event withdraws a zoomed PNG and retires the session', (
      tester,
    ) async {
      await mount(tester);
      await start(tester);
      await paint(tester);
      expect(renderer, findsOneWidget);
      final image = tester.widget<RawImage>(pixels).image!;
      final viewport = find.byType(InteractiveViewer);
      final transform = tester
          .widget<InteractiveViewer>(viewport)
          .transformationController!;
      await tester.tap(viewport);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(viewport);
      await tester.pump();
      expect(transform.value.getMaxScaleOnAxis(), closeTo(2.5, 0.001));
      final drag = await tester.startGesture(tester.getCenter(viewport));
      await drag.moveBy(const Offset(36, 20));
      await drag.moveBy(const Offset(18, 10));
      await tester.pump();
      switch (event) {
        case 'pause':
          server.checkReply = const ApiReply(404, '');
        case 'revoke':
          server.checkReply = ApiReply(
            403,
            jsonEncode({'AccessGranted': false, 'SessionEnded': true}),
          );
        case 'capture':
          capture.setCapture(true);
        case 'screenshot':
          capture.events!.success({'type': 'screenshot'});
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          expect(server.routes, contains(end));
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        case 'route':
          unawaited(
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other route')),
              ),
            ),
          );
        case 'logout':
          await tester.tap(find.text('Sign out'));
        case 'end':
          await tester.tap(find.text('End viewing'));
      }
      if (event == 'pause' || event == 'revoke') {
        await tester.pump(const Duration(seconds: 3));
        expect(server.routes, contains(check));
      }
      // Deliver pending platform events before checking the withdrawal frame.
      await tester.idle();
      await tester.pump();
      expect(find.byType(RawImage, skipOffstage: false), findsNothing);
      expect(viewport, findsNothing);
      expect(image.debugDisposed, isTrue);
      expect(image.debugGetOpenHandleStackTraces(), isEmpty);
      await drag.moveBy(const Offset(-18, -24));
      await drag.up();
      await tester.pump();
      expect(server.routes, contains(end));
      expect(server.cleanupCredentials, [credential]);
      if (event == 'route') navigator.currentState!.pop();
      if (event == 'logout') {
        await tester.enterText(find.byType(TextField), 'fixture only');
        await tester.tap(find.text('Sign in as approved recipient'));
      }
      await tester.pumpAndSettle();
      expect(renderer, findsNothing);
      expect(server.routes.where((route) => route == open), hasLength(1));
    });
  }

  testWidgets(
    'late open after logout is ended before the issuing credential is retired',
    (tester) async {
      final delay = server.delayOpen = Completer<void>();
      await mount(tester);
      await tester.tap(find.text(openLabel));
      await tester.pump();
      expect(server.routes, contains(open));
      await tester.tap(find.text('Sign out'));
      await tester.pump();
      expect(server.routes, isNot(contains(logout)));
      delay.complete();
      await tester.pumpAndSettle();
      expect(
        server.routes.indexOf(end),
        lessThan(server.routes.indexOf(logout)),
      );
      expect(server.cleanupCredentials, [credential]);
      expect(renderer, findsNothing);
    },
  );

  testWidgets('stale check grant cannot restore an ended session', (
    tester,
  ) async {
    final delay = server.delayCheck = Completer<void>();
    await mount(tester);
    await start(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(server.routes, contains(check));
    await tester.tap(find.text('End viewing'));
    await tester.pumpAndSettle();
    delay.complete();
    await tester.pumpAndSettle();
    expect(renderer, findsNothing);
    expect(server.cleanupCredentials, [credential]);
  });
}
