import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/share_file_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/temporary_png_demo.dart';
import '../tool/temporary_png_demo_backend.dart';
import '../tool/temporary_png_demo_fixture.dart';
import '../tool/temporary_png_demo_transport.dart';
import 'support/biometric_fake.dart';
import 'support/png_fixture.dart';
import 'support/viewing_test_fakes.dart';

class _Picker implements ShareFilePicker {
  _Picker(this.bytes);

  final Uint8List bytes;

  @override
  Future<bool> pick(int requestId) async => true;

  @override
  Future<PickedShareFile> read(int requestId, int maxBytes) async =>
      PickedShareFile('Aperture-Demo.png', bytes, mimeType: 'image/png');

  @override
  Future<void> discard(int requestId) async {}
}

class _SocketTestOverrides extends HttpOverrides {}

class _Backend implements ApiTransport {
  final fixture = PngDemoFixtureBackend();
  final calls = <(String, String)>[];
  Completer<ApiReply>? createResponse;
  Completer<ApiReply>? delayedOpen;
  bool badGrant = false;
  bool paused = false;
  bool opening = false;
  Map<String, dynamic>? upload;

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    calls.add((method, uri.path));
    if ((method, uri.path) == ('POST', '/api/content')) {
      upload = jsonDecode(body!) as Map<String, dynamic>;
      if (createResponse != null) return createResponse!.future;
    }
    final reply = await fixture.send(method, uri, headers, body);
    if (uri.path == '/api/content/1/sessions' && reply.status == 200) {
      opening = true;
      if (delayedOpen != null) await delayedOpen!.future;
      if (badGrant) {
        final j = jsonDecode(reply.body) as Map<String, dynamic>;
        j['FileDataBase64'] = base64Encode(pngFixture());
        return ApiReply(200, jsonEncode(j));
      }
    }
    if (paused && uri.path.endsWith('/check')) return const ApiReply(404, '');
    return reply;
  }

  @override
  void close() => fixture.close();
}

void main() {
  const signIn = 'Sign in as fixture sender and recipient';
  const select = 'Select Aperture-Demo.png';
  const create = 'Create unencrypted synthetic share';
  const view = 'Verify identity and open synthetic PNG';
  const signOut = 'Sign out both accounts';
  late _Backend backend;
  late NativeCaptureFake capture;

  setUp(() {
    backend = _Backend();
    capture = NativeCaptureFake()..install();
  });

  Future<void> settleImage(WidgetTester tester) async {
    for (var frame = 0; frame < 20; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 3)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
  }

  Future<void> mount(
    WidgetTester tester, {
    Uint8List? bytes,
    Duration? timeout,
  }) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: TemporaryPngDemo(
          backend: backend,
          picker: _Picker(bytes ?? base64Decode(classroomSyntheticPng)),
          captureProtection: ScreenCaptureProtection.forTesting(),
          biometricAuthenticator: BiometricFake(),
          timeout: timeout ?? const Duration(seconds: 4),
          pollInterval: const Duration(seconds: 2),
        ),
      ),
    );
    await tap(tester, signIn);
  }

  Future<void> upload(WidgetTester tester) async {
    await tap(tester, select);
    await settleImage(tester);
    expect(find.text('Synthetic sample verified · 320 × 180'), findsOneWidget);
    await tap(tester, create);
    expect(
      find.text('Both accounts confirmed the synthetic PNG share.'),
      findsOneWidget,
    );
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  test('sample matches the checked-in fixture and public HTTP is rejected', () {
    expect(
      base64Decode(classroomSyntheticPng),
      File('docs/week11/task11-3/Aperture-Demo.png').readAsBytesSync(),
    );
    expect(
      () => PngDemoLoopback('http://classroom.fixture.invalid/'),
      throwsException,
    );
    expect(() => PngDemoLoopback('http://localhost:8080/'), throwsException);
    expect(PngDemoLoopback('http://127.0.0.1:8080/').base.port, 8080);
  });

  test(
    'literal loopback makes a real HTTP request and refuses redirects',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        request.response
          ..statusCode = 307
          ..headers.set(HttpHeaders.locationHeader, '/api/redirected');
        await request.response.close();
      });
      final demo = PngDemoLoopback('http://127.0.0.1:${server.port}/');
      final reply = await HttpOverrides.runWithHttpOverrides(
        () => demo.send('GET', Uri(path: '/api/content'), {}, null),
        _SocketTestOverrides(),
      );
      expect(reply.status, 307);
      expect(paths, ['/api/content']);
    },
  );

  testWidgets('a rejected create offers no viewer and cannot be resubmitted', (
    tester,
  ) async {
    backend.createResponse = Completer<ApiReply>()
      ..complete(const ApiReply(400, ''));
    await mount(tester);
    await tap(tester, select);
    await settleImage(tester);
    await tap(tester, create);
    expect(find.textContaining('invalidRequest'), findsOneWidget);
    expect(find.text(create), findsNothing);
    expect(find.text(view), findsNothing);
    expect(
      backend.calls.where((call) => call == ('POST', '/api/content')),
      hasLength(1),
    );
    await dispose(tester);
  });

  testWidgets(
    'creates, renders, withdraws on pause and revoke, then signs out',
    (tester) async {
      await mount(tester);
      await upload(tester);
      expect(backend.upload!['FileType'], 'image/png');
      expect(backend.upload!['FileDataBase64'], classroomSyntheticPng);
      expect(backend.upload!['Recipient'], pngDemoRecipient);
      expect(backend.upload!['MaxViews'], 2);
      expect(backend.upload!['ScreenshotRestriction'], false);
      expect(find.byType(RawImage), findsNothing);
      await tap(tester, view);
      await settleImage(tester);
      expect(find.byType(RawImage), findsOneWidget);
      expect(capture.enables, 1);
      await tap(tester, 'Pause test share');
      expect(find.byType(RawImage), findsNothing);
      expect(
        find.text('Recipient access: Active · Policy: Paused'),
        findsOneWidget,
      );
      await tap(tester, 'Resume test share');
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      await tap(tester, view);
      await settleImage(tester);
      expect(find.byType(RawImage), findsOneWidget);
      await tap(tester, 'Revoke test share');
      expect(find.byType(RawImage), findsNothing);
      expect(
        find.text('Recipient access: Revoked · Policy: Active'),
        findsOneWidget,
      );
      await tap(tester, signOut);
      expect(
        backend.calls.where((call) => call.$2 == '/api/auth/logout'),
        hasLength(2),
      );
      expect(
        backend.calls.where((call) => call.$2.endsWith('/end')),
        hasLength(2),
      );
      expect(find.byType(RawImage), findsNothing);
      await dispose(tester);
    },
  );

  testWidgets(
    'polling withdraws a displayed image when the API denies its session',
    (tester) async {
      await mount(tester);
      await upload(tester);
      await tap(tester, view);
      await settleImage(tester);
      expect(find.byType(RawImage), findsOneWidget);
      backend.paused = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(
        backend.calls.where((call) => call.$2.endsWith('/check')),
        hasLength(1),
      );
      await dispose(tester);
    },
  );

  testWidgets(
    'rejects a different PNG and a timed-out upload cannot be retried',
    (tester) async {
      final other = pngFixture();
      await mount(tester, bytes: other);
      await tap(tester, select);
      expect(other.every((byte) => byte == 0), isTrue);
      expect(
        find.text('Select the original synthetic Aperture-Demo.png.'),
        findsOneWidget,
      );
      expect(backend.upload, isNull);
      await dispose(tester);

      backend = _Backend()..createResponse = Completer<ApiReply>();
      await mount(tester, timeout: const Duration(milliseconds: 150));
      await tap(tester, select);
      await settleImage(tester);
      await tap(tester, create);
      await tester.pump(const Duration(milliseconds: 151));
      expect(find.textContaining('outcome is unknown'), findsOneWidget);
      expect(find.text(create), findsNothing);
      expect(
        backend.calls.where((call) => call == ('POST', '/api/content')),
        hasLength(1),
      );
      backend.createResponse!.complete(const ApiReply(200, '{"id":1}'));
      await tester.pump();
      expect(find.text(view), findsNothing);
      await dispose(tester);
    },
  );

  testWidgets('a late grant after logout and account switch never renders', (
    tester,
  ) async {
    backend.delayedOpen = Completer<ApiReply>();
    await mount(tester);
    await upload(tester);
    await tap(tester, view);
    await tester.pump();
    expect(backend.opening, isTrue);
    await tap(tester, signOut);
    expect(find.byType(RawImage), findsNothing);
    backend.delayedOpen!.complete(const ApiReply(200, ''));
    await tester.pump();
    await tester.pump();
    expect(
      backend.calls.where((call) => call.$2.endsWith('/end')),
      hasLength(1),
    );
    await tap(tester, signIn);
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    await dispose(tester);
  });

  testWidgets(
    'an authorized response containing an unrelated PNG fails closed',
    (tester) async {
      backend.badGrant = true;
      await mount(tester);
      await upload(tester);
      await tap(tester, view);
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(
        backend.calls.where((call) => call.$2.endsWith('/end')),
        hasLength(1),
      );
      await dispose(tester);
    },
  );

  testWidgets(
    'capture failure keeps pixels hidden after server authorization',
    (tester) async {
      capture.capture = true;
      await mount(tester);
      await upload(tester);
      await tap(tester, view);
      await settleImage(tester);
      expect(find.byType(RawImage), findsNothing);
      expect(capture.enables, 1);
      await tap(tester, 'End viewing');
      await tester.pump();
      expect(
        backend.calls.where((call) => call.$2.endsWith('/end')),
        hasLength(1),
      );
      await dispose(tester);
    },
  );
}
