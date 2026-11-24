import 'dart:io';
import 'dart:ui' as ui;

import 'package:aperture/widgets/recipient_png_renderer.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/synthetic_contract_png.dart';

const _nativeBackground = bool.fromEnvironment('APERTURE_ZOOM_OS_ROUND_TRIP');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'reads synthetic contracts and discards them at end or background',
    (tester) async {
      final input = ValueNotifier<RecipientPngRequest?>(null);
      addTearDown(input.dispose);
      final states = <AppLifecycleState>[];
      final listener = AppLifecycleListener(onStateChange: states.add);
      addTearDown(listener.dispose);
      final pixels = find.byType(RawImage, skipOffstage: false);
      final viewer = find.byType(InteractiveViewer);
      final fit = find.text('Fit to screen');
      const endLabel = 'End viewing';

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: const Color(0xFF156966)),
          home: Scaffold(
            appBar: AppBar(title: const Text('Synthetic document test')),
            body: SafeArea(child: RecipientPngRenderer(input: input)),
            bottomNavigationBar: SafeArea(
              child: Center(
                heightFactor: 1,
                child: FilledButton(
                  onPressed: () => input.value = null,
                  child: const Text(endLabel),
                ),
              ),
            ),
          ),
        ),
      );
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
      }

      Future<void> waitUntil(
        bool Function() condition,
        Duration timeout,
      ) async {
        final deadline = DateTime.now().add(timeout);
        while (!condition() && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(condition(), isTrue);
      }

      double zoom() => tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!
          .value
          .getMaxScaleOnAxis();

      Future<ui.Image> open({required bool landscape}) async {
        final bytes = await syntheticContractPng(landscape: landscape);
        input.value = RecipientPngRequest(
          () async =>
              RecipientPngPayload(contentType: 'image/png', bytes: bytes),
        );
        await waitUntil(
          () => pixels.evaluate().isNotEmpty,
          const Duration(seconds: 8),
        );
        expect(bytes.every((byte) => byte == 0), isTrue);
        final image = tester.widget<RawImage>(pixels).image!;
        final page = tester.getRect(pixels);
        final viewport = tester.getRect(viewer);
        expect(
          page.width / page.height,
          closeTo(image.width / image.height, 0.001),
        );
        expect((page.center - viewport.center).distance, lessThan(.001));
        expect(page.width, lessThanOrEqualTo(viewport.width + .001));
        expect(page.height, lessThanOrEqualTo(viewport.height + .001));
        expect(zoom(), 1);
        return image;
      }

      Future<void> doubleTap(Offset point) async {
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 45));
        await tester.tapAt(point);
        await tester.pumpAndSettle();
      }

      Future<void> pinchOut() async {
        final rect = tester.getRect(viewer);
        final left = await tester.startGesture(
          rect.center - const Offset(18, 0),
        );
        final right = await tester.startGesture(
          rect.center + const Offset(18, 0),
        );
        for (var i = 0; i < 8; i++) {
          await left.moveBy(Offset(-rect.width / 20, 0));
          await right.moveBy(Offset(rect.width / 20, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 160));
        await left.up();
        await right.up();
        await tester.pumpAndSettle();
        expect(zoom(), closeTo(5, 0.001));
      }

      void expectGone(ui.Image image) {
        expect(pixels, findsNothing);
        expect(viewer, findsNothing);
        expect(image.debugDisposed, isTrue);
        expect(image.debugGetOpenHandleStackTraces(), isEmpty);
      }

      final cache = PaintingBinding.instance.imageCache;
      (int, int, int) cacheState() =>
          (cache.currentSize, cache.liveImageCount, cache.pendingImageCount);
      final initialCache = cacheState();
      final tall = await open(landscape: false);
      await binding.takeScreenshot('01-portrait-fit');
      await pinchOut();
      final midpoint = tester.getTopLeft(pixels);
      final viewSize = tester.getSize(viewer);
      await tester.drag(viewer, Offset(0, -viewSize.height * .34));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(pixels).dy, lessThan(midpoint.dy - 40));
      await tester.drag(viewer, Offset(-viewSize.width * .35, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(pixels).dx, lessThan(midpoint.dx - 20));
      await tester.tap(fit);
      await tester.pumpAndSettle();
      expect(zoom(), 1);
      await pinchOut();
      for (var i = 0; i < 7; i++) {
        await tester.drag(
          viewer,
          Offset(viewSize.width * .40, viewSize.height * .4),
        );
        await tester.pumpAndSettle();
      }
      expect(
        tester.getTopLeft(pixels).dx,
        closeTo(tester.getTopLeft(viewer).dx, .01),
      );
      expect(
        tester.getTopLeft(pixels).dy,
        closeTo(tester.getTopLeft(viewer).dy, .01),
      );
      await binding.takeScreenshot('02-portrait-zoom-5x');
      final drag = await tester.startGesture(tester.getCenter(viewer));
      await drag.moveBy(const Offset(-55, -65));
      await tester.pump();
      await tester.tap(find.text(endLabel));
      await tester.pump();
      expectGone(tall);
      await drag.moveBy(const Offset(-11, -13));
      await drag.up();

      final wide = await open(landscape: true);
      final wideRect = tester.getRect(pixels);
      final focus = Offset(
        wideRect.left + wideRect.width * .30,
        wideRect.center.dy,
      );
      await doubleTap(focus);
      expect(zoom(), closeTo(2.5, .001));
      await doubleTap(focus);
      expect(zoom(), 1);
      await doubleTap(focus);
      await binding.takeScreenshot('03-landscape-zoom');

      if (_nativeBackground) {
        states.clear();
        debugPrintSynchronously('[DocumentZoomNative] BACKGROUND_READY');
        await waitUntil(
          () =>
              states.contains(AppLifecycleState.paused) &&
              states.last == AppLifecycleState.resumed,
          const Duration(seconds: 50),
        );
        await tester.pumpAndSettle();
        expectGone(wide);
        debugPrintSynchronously(
          '[DocumentZoomNative] ${states.map((state) => state.name).join(",")} image=absent',
        );
      } else {
        await tester.tap(find.text(endLabel));
        await tester.pumpAndSettle();
        expectGone(wide);
      }
      await binding.takeScreenshot('04-after-withdrawal');
      expect(cacheState(), initialCache);
    },
  );
}
