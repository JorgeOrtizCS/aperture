import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/static_png_decoder.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:aperture/widgets/recipient_png_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';
import 'support/png_fixture.dart';

final _pixels = find.byType(RawImage, skipOffstage: false);
const _loading = 'Loading image…';
const _invalid = 'This PNG is invalid or incomplete.';
const _unsupported = 'Only still PNG images are supported.';

RecipientPngPayload _payload(Uint8List bytes, {String type = 'image/png'}) =>
    RecipientPngPayload(contentType: type, bytes: bytes);

RecipientPngRequest _request(Uint8List bytes, {String type = 'image/png'}) =>
    RecipientPngRequest(() async => _payload(bytes, type: type));

class _RendererHarness {
  final input = ValueNotifier<RecipientPngRequest?>(null);
  final navigator = GlobalKey<NavigatorState>();

  Future<void> mount(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(input.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Synthetic harness home')),
      ),
    );
    open();
    await tester.pumpAndSettle();
  }

  void open() => unawaited(
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 160,
              child: Center(child: RecipientPngRenderer(input: input)),
            ),
          ),
        ),
      ),
    ),
  );

  Future<ui.Image> render(WidgetTester tester) async {
    final bytes = pngFixture();
    input.value = _request(bytes);
    await _finish(tester, _pixels);
    expect(bytes, everyElement(0));
    return tester.widget<RawImage>(_pixels).image!;
  }
}

Future<void> _finish(WidgetTester tester, Finder target) async {
  // The real engine codec completes outside widget test fake time.
  for (var i = 0; i < 200; i++) {
    await tester.pump();
    if (target.evaluate().isNotEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(target, findsOneWidget);
}

Finder _liveRegion(String message) => find.ancestor(
  of: find.text(message),
  matching: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.liveRegion == true,
  ),
);

void main() {
  testWidgets('loads a real PNG, preserves aspect ratio and skips cache', (
    tester,
  ) async {
    final h = _RendererHarness();
    await h.mount(tester);
    final cache = PaintingBinding.instance.imageCache;
    final before = (
      cache.currentSize,
      cache.liveImageCount,
      cache.pendingImageCount,
    );
    final result = Completer<RecipientPngPayload>();
    h.input.value = RecipientPngRequest(() => result.future);
    await tester.pump();
    expect(_pixels, findsNothing);
    expect(_liveRegion(_loading), findsOneWidget);
    final bytes = pngFixture();
    result.complete(_payload(bytes));
    await _finish(tester, _pixels);
    final raw = tester.widget<RawImage>(_pixels);
    expect((raw.image!.width, raw.image!.height), (2, 1));
    expect(tester.getSize(_pixels), const Size(224, 112));
    expect(raw.fit, BoxFit.contain);
    expect(find.bySemanticsLabel('Shared PNG image'), findsOneWidget);
    expect(find.text(_loading), findsNothing);
    expect(bytes, everyElement(0));
    expect((
      cache.currentSize,
      cache.liveImageCount,
      cache.pendingImageCount,
    ), before);
  });

  testWidgets('fit resets a zoomed image at the edge of the viewport', (
    tester,
  ) async {
    final h = _RendererHarness();
    await h.mount(tester);
    await h.render(tester);
    final viewport = find.byType(InteractiveViewer);
    final original = tester.getRect(_pixels);
    await tester.tap(viewport);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(viewport);
    await tester.pump();
    expect(tester.getRect(_pixels).width, closeTo(original.width * 2.5, .001));
    await tester.tap(find.text('Fit to screen'));
    await tester.pumpAndSettle();
    expect(tester.getRect(_pixels), original);
  });

  for (final (name, type, buildBytes, message) in [
    ('corrupt bytes', 'image/png', () => Uint8List(64), _invalid),
    (
      'truncated PNG',
      'image/png',
      () => Uint8List.fromList(pngFixture().sublist(0, 50)),
      _invalid,
    ),
    (
      'bad compressed data with valid PNG framing',
      'image/png',
      () => pngFixture(scanlines: [0]),
      _invalid,
    ),
    (
      'truncated zlib stream with valid chunk CRC',
      'image/png',
      () => pngFixture(
        transformCompressed: (zlib) => zlib.sublist(0, zlib.length - 4),
      ),
      _invalid,
    ),
    ('unsupported MIME', 'image/jpeg', () => pngFixture(), _unsupported),
    (
      'animated PNG',
      'image/png',
      () => pngFixture(animated: true),
      _unsupported,
    ),
    (
      'oversized dimensions',
      'image/png',
      () => pngFixture(width: 4097),
      'This PNG exceeds the supported size.',
    ),
    (
      'oversized encoded bytes',
      'image/png',
      () => Uint8List(5 * 1024 * 1024 + 1)..[0] = 255,
      'This PNG exceeds the supported size.',
    ),
  ]) {
    testWidgets('rejects $name with an accessible error and wipes bytes', (
      tester,
    ) async {
      final h = _RendererHarness();
      await h.mount(tester);
      final bytes = buildBytes();
      h.input.value = _request(bytes, type: type);
      await _finish(tester, find.text(message));
      expect(_liveRegion(message), findsOneWidget);
      expect(_pixels, findsNothing);
      expect(bytes, everyElement(0));
    });
  }

  testWidgets('load failure shows a generic message and permits a new input', (
    tester,
  ) async {
    final h = _RendererHarness();
    await h.mount(tester);
    h.input.value = RecipientPngRequest(
      () async => throw StateError('internal delivery detail'),
    );
    await _finish(tester, find.text('Unable to load the image.'));
    expect(_liveRegion('Unable to load the image.'), findsOneWidget);
    expect(find.textContaining('internal delivery detail'), findsNothing);
    await h.render(tester);
    expect(find.text('Unable to load the image.'), findsNothing);
  });

  testWidgets('denial disposes both image handles and clears the next frame', (
    tester,
  ) async {
    final h = _RendererHarness();
    await h.mount(tester);
    final owned = await h.render(tester);
    expect(owned.debugGetOpenHandleStackTraces(), hasLength(2));
    final oldRequest = h.input.value;
    h.input.value = null;
    expect(owned.debugDisposed, isTrue);
    await tester.pump();
    expect(_pixels, findsNothing);
    expect(owned.debugGetOpenHandleStackTraces(), isEmpty);
    h.input.value = oldRequest;
    await tester.pump();
    expect(_pixels, findsNothing);
  });

  testWidgets(
    'denial and replacement before the same frame remove old pixels',
    (tester) async {
      final h = _RendererHarness();
      await h.mount(tester);
      final old = await h.render(tester);
      h.input.value = null;
      final next = Completer<RecipientPngPayload>();
      h.input.value = RecipientPngRequest(() => next.future);
      await tester.pump();
      expect(_pixels, findsNothing);
      expect(find.text(_loading), findsOneWidget);
      expect(old.debugDisposed, isTrue);
      next.complete(_payload(pngFixture()));
      await _finish(tester, _pixels);
      expect(tester.widget<RawImage>(_pixels).image, isNot(same(old)));
    },
  );

  testWidgets('background hides the image; resume requires a fresh request', (
    tester,
  ) async {
    final h = _RendererHarness();
    await h.mount(tester);
    final image = await h.render(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(_pixels, findsNothing);
    expect(image.debugDisposed, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    var loads = 0;
    h.input.value = RecipientPngRequest(() async {
      loads++;
      return _payload(pngFixture());
    });
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(loads, 0);
    expect(_pixels, findsNothing);
    await h.render(tester);
  });

  testWidgets('covering or popping the route drops pixels without replay', (
    tester,
  ) async {
    final h = _RendererHarness();
    await h.mount(tester);
    final image = await h.render(tester);
    unawaited(
      h.navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Cover'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(_pixels, findsNothing);
    expect(image.debugDisposed, isTrue);
    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_pixels, findsNothing);
    for (var i = 0; i < 3; i++) {
      final current = await h.render(tester);
      h.navigator.currentState!.pop();
      await tester.pump();
      expect(_pixels, findsNothing);
      await tester.pumpAndSettle();
      expect(current.debugGetOpenHandleStackTraces(), isEmpty);
      h.open();
      await tester.pumpAndSettle();
      expect(_pixels, findsNothing);
    }
  });

  testWidgets('covering a route prevents delivery before the next frame', (
    tester,
  ) async {
    final h = _RendererHarness();
    await h.mount(tester);
    unawaited(
      h.navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Cover'))),
      ),
    );
    var loads = 0;
    h.input.value = RecipientPngRequest(() async {
      loads++;
      return _payload(pngFixture());
    });
    // A pushed route is already current even before Flutter rebuilds the
    // covered route's inherited status or paints the transition.
    await tester.idle();
    expect(loads, 0);
    await tester.pumpAndSettle();
    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(loads, 0);
    expect(_pixels, findsNothing);
    await h.render(tester);
  });

  testWidgets('late payload cannot replace a newer result and is wiped', (
    tester,
  ) async {
    final h = _RendererHarness();
    await h.mount(tester);
    final pending = Completer<RecipientPngPayload>();
    h.input.value = RecipientPngRequest(() => pending.future);
    await tester.pump();
    expect(find.text(_loading), findsOneWidget);
    final next = await h.render(tester);
    final late = pngFixture();
    pending.complete(_payload(late));
    await tester.pumpAndSettle();
    expect(tester.widget<RawImage>(_pixels).image, same(next));
    expect(late, everyElement(0));
  });

  testWidgets('disposal wipes a later payload and ignores a later failure', (
    tester,
  ) async {
    final h = _RendererHarness();
    await h.mount(tester);
    final first = Completer<RecipientPngPayload>();
    final second = Completer<RecipientPngPayload>();
    h.input.value = RecipientPngRequest(() => first.future);
    await tester.pump();
    h.input.value = RecipientPngRequest(() => second.future);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    final late = pngFixture();
    first.complete(_payload(late));
    second.completeError(StateError('late delivery failure'));
    await tester.pump();
    expect(late, everyElement(0));
    expect(_pixels, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('test adapter withdraws display on controller termination', (
    tester,
  ) async {
    final h = _RendererHarness();
    await h.mount(tester);
    // Observes a real termination event; the preceding render is synthetic
    // and does not derive permission from this controller.
    final controller = ViewingStateController(
      restrictions: ContentRestrictions.demoDefaults,
      conditions: UnverifiedViewingConditions(),
      protection: ScreenCaptureProtection.forTesting(),
    );
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.sessionEnded) h.input.value = null;
    });
    final image = await h.render(tester);
    controller.endForSecurityViolation();
    await tester.pump();
    expect(image.debugDisposed, isTrue);
    expect(_pixels, findsNothing);
  });

  testWidgets('test adapter withdraws display before server logout completes', (
    tester,
  ) async {
    final h = _RendererHarness();
    await h.mount(tester);
    final fake = ApiFake();
    final serverLogout = Completer<ApiReply>();
    fake.routes['/api/auth/logout'] = (_) => serverLogout.future;
    final account = fake.session();
    addTearDown(account.dispose);
    await account.login('synthetic-user', 'fixture-password');
    expect(account.authenticated, isTrue);
    account.addListener(() {
      if (!account.authenticated) h.input.value = null;
    });
    final image = await h.render(tester);
    final logout = account.logout();
    await tester.pump();
    expect(serverLogout.isCompleted, isFalse);
    expect(account.authenticated, isFalse);
    expect(image.debugDisposed, isTrue);
    expect(_pixels, findsNothing);
    serverLogout.complete(jsonReply({'success': true}));
    await logout;
  });

  test('decode cancellation still clears the owned encoded buffer', () async {
    final bytes = pngFixture();
    var checks = 0;
    final result = await StaticPngDecoder.decode(
      bytes,
      maxBytes: 1000,
      isCurrent: () => ++checks < 2,
    );
    expect(checks, 2);
    expect(result, isNull);
    expect(bytes, everyElement(0));
  });
}
