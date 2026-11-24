import 'dart:io';

import 'package:aperture/screens/share_content_screen.dart';
import 'package:aperture/services/share_file_selection.dart';
import 'package:aperture/widgets/png_document_view.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/synthetic_contract_png.dart';

const _nativeBackground = bool.fromEnvironment(
  'APERTURE_SENDER_PREVIEW_OS_ROUND_TRIP',
);

class _SyntheticPicker implements ShareFilePicker {
  late PickedShareFile file;

  @override
  Future<bool> pick(int requestId) async => true;

  @override
  Future<PickedShareFile> read(int requestId, int maxBytes) async => file;

  @override
  Future<void> discard(int requestId) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reads local sender contracts at original resolution', (
    tester,
  ) async {
    final picker = _SyntheticPicker();
    final navigator = GlobalKey<NavigatorState>();
    final states = <AppLifecycleState>[];
    final lifecycle = AppLifecycleListener(onStateChange: states.add);
    addTearDown(lifecycle.dispose);
    final select = find.byKey(const ValueKey('share-select-png'));
    final thumbnail = find.byKey(const ValueKey('share-png-preview'));
    final enlarge = find.text('Enlarge preview');
    final viewport = find.byType(InteractiveViewer);
    final pixels = find.byType(RawImage);
    final fit = find.text('Fit to screen');
    final close = find.byTooltip('Close preview');
    final formScroll = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    final cache = PaintingBinding.instance.imageCache;
    (int, int, int) cacheState() =>
        (cache.currentSize, cache.liveImageCount, cache.pendingImageCount);
    final initialCache = cacheState();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        home: ShareContentScreen(filePicker: picker),
      ),
    );
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
    }

    Future<void> waitUntil(
      bool Function() ready, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(ready(), isTrue);
    }

    Future<void> reveal(Finder target, double delta) async {
      await tester.scrollUntilVisible(target, delta, scrollable: formScroll);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(tester.element(target), alignment: .35);
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
    }

    Future<void> selectPng({required bool landscape}) async {
      picker.file = PickedShareFile(
        landscape ? 'Fictional-Rate-Card.png' : 'Fictional-Agreement.png',
        await syntheticContractPng(landscape: landscape),
        mimeType: 'image/png',
      );
      await reveal(select, -150);
      await tester.tap(select);
      await tester.pump();
      await waitUntil(() => thumbnail.evaluate().isNotEmpty);
      await tester.ensureVisible(thumbnail);
      await tester.pumpAndSettle();
    }

    double zoom() => tester
        .widget<InteractiveViewer>(viewport)
        .transformationController!
        .value
        .getMaxScaleOnAxis();

    Future<void> open() async {
      await reveal(enlarge, 150);
      await tester.tap(enlarge);
      await waitUntil(() => viewport.evaluate().isNotEmpty);
      expect(zoom(), 1);
      expect(find.byType(BackButton), findsOneWidget);
      expect(close, findsOneWidget);
      final image = tester.widget<RawImage>(pixels).image!;
      final page = tester.getRect(pixels);
      final screen = tester.getRect(viewport);
      expect(
        page.width / page.height,
        closeTo(image.width / image.height, .001),
      );
      expect((page.center - screen.center).distance, lessThan(.01));
      expect(page.width, lessThanOrEqualTo(screen.width + .01));
      expect(page.height, lessThanOrEqualTo(screen.height + .01));
    }

    Future<void> pinchOut() async {
      final rect = tester.getRect(viewport);
      final left = await tester.startGesture(rect.center - const Offset(18, 0));
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
      expect(zoom(), closeTo(5, .001));
    }

    Future<void> showSmallPrint() async {
      await pinchOut();
      final size = tester.getSize(viewport);
      for (var i = 0; i < 7; i++) {
        await tester.drag(viewport, Offset(size.width * .4, size.height * .4));
        await tester.pumpAndSettle();
      }
      expect(
        (tester.getTopLeft(pixels) - tester.getTopLeft(viewport)).distance,
        lessThan(.01),
      );
      // Move the small first-clause print near the center of the viewport.
      final drag = await tester.startGesture(tester.getCenter(viewport));
      await drag.moveBy(const Offset(0, -22));
      await drag.moveBy(Offset(0, -size.height * .56));
      await tester.pump(const Duration(milliseconds: 180));
      await drag.up();
      await tester.pumpAndSettle();
    }

    await selectPng(landscape: false);
    final portraitBytes = picker.file.bytes;
    final small = tester.widget<RawImage>(thumbnail).image!;
    expect((small.width, small.height), (264, 512));
    await binding.takeScreenshot('01-sender-thumbnail');

    await open();
    final portrait = tester.widget<RawImage>(pixels).image!;
    expect((portrait.width, portrait.height), (1280, 2480));
    await binding.takeScreenshot('02-portrait-full-resolution-fit');
    await pinchOut();
    final start = tester.getTopLeft(pixels);
    await tester.drag(viewport, const Offset(-95, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(pixels).dx, lessThan(start.dx - 25));
    await tester.drag(viewport, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(pixels).dy, lessThan(start.dy - 30));
    await tester.tap(fit);
    await tester.pumpAndSettle();
    expect(zoom(), 1);
    await showSmallPrint();
    await binding.takeScreenshot('03-portrait-full-resolution-zoom');
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(portrait.debugDisposed, isTrue);
    expect(portrait.debugGetOpenHandleStackTraces(), isEmpty);
    await tester.scrollUntilVisible(thumbnail, -150, scrollable: formScroll);
    expect(tester.widget<RawImage>(thumbnail).image, same(small));
    expect(viewport, findsNothing);
    await binding.takeScreenshot('04-preview-closed');

    // Reproduce the previous implementation with the selected file's real
    // thumbnail, the same viewport, and the same zoom and pan.
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Local PNG preview')),
          body: SafeArea(
            child: PngDocumentView(
              image: small,
              semanticLabel: '512-pixel comparison',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await showSmallPrint();
    await binding.takeScreenshot('05-portrait-512-comparison');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    await open();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(viewport, findsNothing);
    await selectPng(landscape: true);
    expect(small.debugDisposed, isTrue);
    expect(portraitBytes.every((byte) => byte == 0), isTrue);
    final wideThumbnail = tester.widget<RawImage>(thumbnail).image!;
    expect((wideThumbnail.width, wideThumbnail.height), (512, 279));
    await open();
    final wide = tester.widget<RawImage>(pixels).image!;
    expect((wide.width, wide.height), (2200, 1200));
    await tester.tap(viewport);
    await tester.pump(const Duration(milliseconds: 45));
    await tester.tap(viewport);
    await tester.pumpAndSettle();
    expect(zoom(), closeTo(2.5, .001));
    await binding.takeScreenshot('06-landscape-full-resolution-zoom');

    if (_nativeBackground) {
      states.clear();
      debugPrintSynchronously('[SenderPreviewNative] BACKGROUND_READY');
      await waitUntil(
        () =>
            states.contains(AppLifecycleState.paused) &&
            states.last == AppLifecycleState.resumed,
        timeout: const Duration(seconds: 50),
      );
      debugPrintSynchronously(
        '[SenderPreviewNative] ${states.map((state) => state.name).join(",")}',
      );
    } else {
      await tester.tap(close);
      await tester.pumpAndSettle();
      final remove = find.text('Remove file');
      await reveal(remove, 150);
      await tester.tap(remove);
    }
    await tester.pumpAndSettle();
    expect(find.byType(RawImage, skipOffstage: false), findsNothing);
    expect(wide.debugDisposed, isTrue);
    expect(wide.debugGetOpenHandleStackTraces(), isEmpty);
    expect(wideThumbnail.debugDisposed, isTrue);
    expect(wideThumbnail.debugGetOpenHandleStackTraces(), isEmpty);
    expect(picker.file.bytes.every((byte) => byte == 0), isTrue);
    expect(cacheState(), initialCache);
  });
}
