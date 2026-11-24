import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aperture/widgets/recipient_png_renderer.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/png_fixture.dart';

// Native rendering fixture only. This entry point is never imported by the
// app. No account, policy provider, API, or secure viewer is instantiated.
Uint8List _colorBars() {
  const width = 320;
  const height = 180;
  const palette = [
    [20, 90, 112],
    [25, 136, 150],
    [55, 180, 175],
    [237, 197, 93],
    [236, 138, 66],
    [193, 82, 102],
    [106, 76, 140],
    [53, 54, 104],
  ];
  final rows = [
    for (var y = 0; y < height; y++) ...[
      0,
      for (var x = 0; x < width; x++)
        ...palette[(x ~/ 40 + (y ~/ 45) * 2) % palette.length],
    ],
  ];
  return pngFixture(width: width, height: height, scanlines: rows);
}

// The optional round trip is driven by the host OS tools, never by injected
// Flutter lifecycle callbacks. Keep the original renderer-only run portable.
const _osRoundTrip = bool.fromEnvironment('APERTURE_TEST_OS_ROUND_TRIP');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native PNG display and withdrawal, synthetic pixels only', (
    tester,
  ) async {
    final input = ValueNotifier<RecipientPngRequest?>(null);
    addTearDown(input.dispose);
    final lifecycle = <AppLifecycleState>[];
    final returned = ValueNotifier(false);
    addTearDown(returned.dispose);
    final listener = AppLifecycleListener(
      onStateChange: (state) {
        lifecycle.add(state);
        if (_osRoundTrip && state == AppLifecycleState.paused) {
          debugPrintSynchronously('[RecipientLifecycleNative] PAUSED');
        }
      },
    );
    addTearDown(listener.dispose);
    final pixels = find.byType(RawImage, skipOffstage: false);
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFF198896)),
        home: Scaffold(
          appBar: AppBar(title: const Text('Synthetic PNG test harness')),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Fixture pixels only. No server authorization or protected content.',
                  ),
                  if (_osRoundTrip)
                    ValueListenableBuilder(
                      valueListenable: returned,
                      builder: (_, value, _) => value
                          ? const Text(
                              'Returned from background. No image replayed.',
                            )
                          : const SizedBox.shrink(),
                    ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F1F3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: ValueListenableBuilder(
                            valueListenable: input,
                            builder: (_, request, _) => Stack(
                              alignment: Alignment.center,
                              children: [
                                RecipientPngRenderer(input: input),
                                if (request == null)
                                  const Text('Fixture withdrawn. No image.'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => input.value = null,
                    child: const Text('Withdraw fixture'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> waitUntil(
      bool Function() ready, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      expect(ready(), isTrue);
    }

    Future<void> waitFor(Finder target) async {
      await waitUntil(() => target.evaluate().isNotEmpty);
      expect(target, findsOneWidget);
      await tester.pumpAndSettle();
    }

    final bytes = _colorBars();
    final delivery = Completer<RecipientPngPayload>();
    input.value = RecipientPngRequest(() => delivery.future);
    await waitFor(find.text('Loading image…'));
    expect(pixels, findsNothing);
    delivery.complete(
      RecipientPngPayload(contentType: 'image/png', bytes: bytes),
    );
    await waitFor(pixels);
    var image = tester.widget<RawImage>(pixels).image!;
    expect((image.width, image.height), (320, 180));
    final size = tester.getSize(pixels);
    expect(size.width / size.height, closeTo(320 / 180, 0.01));
    expect(bytes, everyElement(0));
    await binding.takeScreenshot('01-synthetic-png-rendered');

    if (_osRoundTrip) {
      lifecycle.clear();
      final originalRequest = input.value;
      debugPrintSynchronously('[RecipientLifecycleNative] BACKGROUND_READY');
      await waitUntil(
        () =>
            lifecycle.contains(AppLifecycleState.paused) &&
            lifecycle.last == AppLifecycleState.resumed,
        timeout: const Duration(seconds: 40),
      );
      returned.value = true;
      await tester.pumpAndSettle();
      expect(input.value, same(originalRequest));
      expect(pixels, findsNothing);
      expect(image.debugDisposed, isTrue);
      expect(image.debugGetOpenHandleStackTraces(), isEmpty);
      await binding.takeScreenshot('03-synthetic-png-after-resume');
      final states = lifecycle.map((state) => state.name).join(',');
      debugPrintSynchronously(
        '[RecipientLifecycleNative] RESUMED events=$states image=absent',
      );

      final fresh = _colorBars();
      input.value = RecipientPngRequest(
        () async => RecipientPngPayload(contentType: 'image/png', bytes: fresh),
      );
      await waitFor(pixels);
      image = tester.widget<RawImage>(pixels).image!;
      expect(fresh, everyElement(0));
      returned.value = false;
      debugPrintSynchronously(
        '[RecipientLifecycleNative] FRESH_FIXTURE_RENDERED',
      );
    }

    await tester.tap(find.text('Withdraw fixture'));
    await tester.pumpAndSettle();
    expect(pixels, findsNothing);
    expect(image.debugDisposed, isTrue);
    expect(find.text('Fixture withdrawn. No image.'), findsOneWidget);
    await binding.takeScreenshot('02-synthetic-png-withdrawn');

    final invalid = Uint8List.fromList([137, 80, 78, 71]);
    input.value = RecipientPngRequest(
      () async => RecipientPngPayload(contentType: 'image/png', bytes: invalid),
    );
    await waitFor(find.text('This PNG is invalid or incomplete.'));
    expect(pixels, findsNothing);
    expect(invalid, everyElement(0));

    final lateDelivery = Completer<RecipientPngPayload>();
    input.value = RecipientPngRequest(() => lateDelivery.future);
    await waitFor(find.text('Loading image…'));
    input.value = null;
    await tester.pumpWidget(const SizedBox.shrink());
    final late = _colorBars();
    lateDelivery.complete(
      RecipientPngPayload(contentType: 'image/png', bytes: late),
    );
    await tester.pumpAndSettle();
    expect(pixels, findsNothing);
    expect(late, everyElement(0));
  });
}
