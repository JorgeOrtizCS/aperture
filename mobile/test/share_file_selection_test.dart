import 'dart:async';

import 'package:aperture/main.dart';
import 'package:aperture/screens/content_status_screen.dart';
import 'package:aperture/screens/share_content_screen.dart';
import 'package:aperture/services/share_file_selection.dart';
import 'package:aperture/widgets/content_restrictions_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';
import 'support/png_fixture.dart';

Matcher problem(PngFileProblem kind) =>
    isA<PngFileException>().having((e) => e.problem, 'problem', kind);

class DraftPicker implements ShareFilePicker {
  FutureOr<bool> Function() choice = () => true;
  FutureOr<PickedShareFile> Function() document = () =>
      PickedShareFile('diagram.PNG', pngFixture(), mimeType: 'image/png');
  final picks = <int>[];
  final reads = <(int, int)>[];
  final discarded = <int>[];
  Completer<void> completed = Completer<void>();

  @override
  Future<bool> pick(int requestId) async {
    picks.add(requestId);
    return choice();
  }

  @override
  Future<PickedShareFile> read(int requestId, int maxBytes) async {
    reads.add((requestId, maxBytes));
    return document();
  }

  @override
  Future<void> discard(int requestId) async {
    discarded.add(requestId);
    if (!completed.isCompleted) completed.complete();
  }
}

const _selectKey = ValueKey('share-select-png');
const _previewKey = ValueKey('share-png-preview');
const _statusKey = ValueKey('share-file-status');
final _enlarge = find.text('Enlarge preview');
final _viewport = find.byType(InteractiveViewer);
final _loadingPreview = find.text('Preparing full-resolution preview…');
final _closePreview = find.byTooltip('Close preview');

Uint8List _page({int width = 768, int height = 1536}) => pngFixture(
  width: width,
  height: height,
  scanlines: Uint8List(height * (1 + 3 * width)),
);

Future<void> draft(
  WidgetTester tester,
  DraftPicker picker, {
  int? maxBytes,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(480, 1450);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: ShareContentScreen(filePicker: picker, maxBytes: maxBytes),
    ),
  );
}

Future<void> selectAndComplete(WidgetTester tester, DraftPicker picker) async {
  picker.completed = Completer<void>();
  await tester.tap(find.byKey(_selectKey));
  await finishSelection(tester, () => picker.completed.isCompleted);
}

Future<void> finishSelection(
  WidgetTester tester,
  bool Function() complete,
) async {
  // Allow engine decode callbacks to finish outside fake time, then deliver
  // their Dart continuations on the widget test binding.
  for (var attempt = 0; !complete() && attempt < 200; attempt++) {
    await tester.pump();
    if (!complete()) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }
  expect(complete(), isTrue, reason: 'The picker request should complete');
  await tester.pumpAndSettle();
}

void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void pause(WidgetTester tester) => lifecycle(tester, const [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
]);

void resume(WidgetTester tester) => lifecycle(tester, const [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
]);

Finder field(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);

String input(WidgetTester tester, String key) =>
    tester.widget<TextField>(field(key)).controller!.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodes an actual PNG and wipes the encoded bytes', () async {
    final bytes = pngFixture();
    final originalLength = bytes.length;
    final preview = await PngFileValidator.validate(
      PickedShareFile(
        'provider/folder/diagram.PNG',
        bytes,
        mimeType: 'image/png',
      ),
      maxBytes: PngFileValidator.backendMaxBytes,
    );
    expect(preview.name, 'diagram.PNG');
    expect(
      (preview.width, preview.height, preview.byteCount),
      (2, 1, originalLength),
    );
    expect(preview.image.width, 2);
    expect(bytes, everyElement(0));
    preview.dispose();
  });

  final badFiles = <(String, PickedShareFile Function(), int, PngFileProblem)>[
    (
      'extension',
      () => PickedShareFile('renamed.jpg', pngFixture()),
      512,
      PngFileProblem.unsupported,
    ),
    (
      'MIME',
      () =>
          PickedShareFile('diagram.png', pngFixture(), mimeType: 'image/jpeg'),
      512,
      PngFileProblem.unsupported,
    ),
    (
      'signature',
      () => PickedShareFile(
        'renamed.png',
        Uint8List.fromList(List.filled(60, 42)),
      ),
      512,
      PngFileProblem.malformed,
    ),
    (
      'truncated chunks',
      () => PickedShareFile(
        'truncated.png',
        pngFixture().sublist(0, pngFixture().length - 6),
      ),
      512,
      PngFileProblem.malformed,
    ),
    (
      'invalid CRC',
      () => PickedShareFile('bad-crc.png', pngFixture()..[25] ^= 1),
      512,
      PngFileProblem.malformed,
    ),
    (
      'malformed compressed image',
      () => PickedShareFile('bad-raster.png', pngFixture(scanlines: [0, 1])),
      512,
      PngFileProblem.malformed,
    ),
    (
      'trailing content',
      () => PickedShareFile(
        'extra.png',
        Uint8List.fromList([...pngFixture(), 1]),
      ),
      512,
      PngFileProblem.malformed,
    ),
    (
      'empty',
      () => PickedShareFile('empty.png', Uint8List(0)),
      512,
      PngFileProblem.empty,
    ),
    (
      'oversize',
      () => PickedShareFile('large.png', pngFixture()),
      40,
      PngFileProblem.tooLarge,
    ),
    (
      'oversize canvas',
      () => PickedShareFile('large-canvas.png', pngFixture(width: 9000)),
      512,
      PngFileProblem.dimensions,
    ),
    (
      'animation',
      () => PickedShareFile('animated.png', pngFixture(animated: true)),
      512,
      PngFileProblem.unsupported,
    ),
  ];
  for (final (name, file, limit, kind) in badFiles) {
    test('rejects $name and wipes the encoded bytes', () async {
      final selection = file();
      await expectLater(
        PngFileValidator.validate(selection, maxBytes: limit),
        throwsA(problem(kind)),
      );
      expect(selection.bytes.every((byte) => byte == 0), isTrue);
    });
  }

  test('deployment limit cannot exceed the API ceiling', () {
    expect(PngFileValidator.boundedLimit(100), 100);
    expect(PngFileValidator.boundedLimit(99999999), 5 * 1024 * 1024);
    expect(PngFileValidator.boundedLimit(0), 5 * 1024 * 1024);
  });

  testWidgets('validates a PNG, replaces it and removes its preview', (
    tester,
  ) async {
    final picker = DraftPicker();
    await draft(tester, picker);
    await selectAndComplete(tester, picker);
    expect(find.text('diagram.PNG'), findsOneWidget);
    expect(find.text('Local preview · Not shared'), findsOneWidget);
    final first = tester.widget<RawImage>(find.byKey(_previewKey)).image!;
    picker.document = () => PickedShareFile('replacement.png', pngFixture());
    await selectAndComplete(tester, picker);
    expect(find.text('diagram.PNG'), findsNothing);
    expect(find.text('replacement.png'), findsOneWidget);
    expect(first.debugDisposed, isTrue);
    final replacement = tester.widget<RawImage>(find.byKey(_previewKey)).image!;
    await tester.tap(find.text('Remove file'));
    await tester.pump();
    expect(replacement.debugDisposed, isTrue);
    expect(find.byKey(_previewKey), findsNothing);
    expect(picker.picks.toSet(), hasLength(2));
    expect(picker.discarded, picker.picks);
  });

  testWidgets(
    'enlargement uses the original pixels, disposes on close, and refits on reopen',
    (tester) async {
      final bytes = _page();
      final picker = DraftPicker()
        ..document = () => PickedShareFile('portrait.png', bytes);
      await draft(tester, picker);
      await selectAndComplete(tester, picker);
      final cache = PaintingBinding.instance.imageCache;
      (int, int, int) cached() =>
          (cache.currentSize, cache.liveImageCount, cache.pendingImageCount);
      final baseline = cached();
      final thumbnail = tester.widget<RawImage>(find.byKey(_previewKey)).image!;
      expect((thumbnail.width, thumbnail.height), (256, 512));
      await tester.tap(_enlarge);
      await tester.pump();
      expect(_loadingPreview, findsOneWidget);
      await finishSelection(tester, () => _viewport.evaluate().isNotEmpty);
      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect((image.width, image.height), (768, 1536));
      expect(image, isNot(same(thumbnail)));
      await tester.tap(_viewport);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(_viewport);
      await tester.pump();
      double zoom() => tester
          .widget<InteractiveViewer>(_viewport)
          .transformationController!
          .value
          .getMaxScaleOnAxis();
      expect(zoom(), closeTo(2.5, 0.001));
      await tester.tap(_closePreview);
      await tester.pumpAndSettle();
      expect(image.debugDisposed, isTrue);
      expect(image.debugGetOpenHandleStackTraces(), isEmpty);
      expect(tester.widget<RawImage>(find.byKey(_previewKey)).image, thumbnail);
      expect(bytes, isNot(everyElement(0)));
      await tester.tap(_enlarge);
      await finishSelection(tester, () => _viewport.evaluate().isNotEmpty);
      final reopened = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect(zoom(), 1);
      expect(reopened, isNot(same(image)));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(_viewport, findsNothing);
      expect(find.byType(RawImage, skipOffstage: false), findsNothing);
      expect(reopened.debugDisposed, isTrue);
      expect(reopened.debugGetOpenHandleStackTraces(), isEmpty);
      expect(thumbnail.debugDisposed, isTrue);
      expect(bytes, everyElement(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(_enlarge, findsNothing);
      expect(cached(), baseline);
    },
  );

  for (final event in ['remove', 'replace', 'background', 'navigate']) {
    testWidgets('$event during preparation prevents a stale enlargement', (
      tester,
    ) async {
      final original = _page();
      final picker = DraftPicker()
        ..document = () => PickedShareFile('portrait.png', original);
      await draft(tester, picker);
      await selectAndComplete(tester, picker);
      final thumbnail = tester.widget<RawImage>(find.byKey(_previewKey)).image!;
      await tester.tap(_enlarge);
      await tester.pump();
      expect(_loadingPreview, findsOneWidget);
      switch (event) {
        case 'remove':
          await tester.tap(_closePreview);
          await tester.pump();
          await tester.tap(find.text('Remove file'));
        case 'replace':
          await tester.binding.handlePopRoute();
          await tester.pump();
          picker.document = () =>
              PickedShareFile('landscape.png', _page(width: 1200, height: 600));
          await selectAndComplete(tester, picker);
          await tester.tap(_enlarge);
          await finishSelection(tester, () => _viewport.evaluate().isNotEmpty);
          final replacement = tester
              .widget<RawImage>(find.byType(RawImage))
              .image!;
          expect((replacement.width, replacement.height), (1200, 600));
          await tester.tap(_closePreview);
        case 'background':
          pause(tester);
          await tester.pump();
          resume(tester);
        case 'navigate':
          final navigator = tester.state<NavigatorState>(
            find.byType(Navigator),
          );
          unawaited(
            navigator.push<void>(
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Other route')),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byType(InteractiveViewer, skipOffstage: false),
            findsNothing,
          );
          navigator.pop();
          await tester.pumpAndSettle();
          expect(_enlarge, findsOneWidget);
          // The still-current local draft can be removed on return.
          await tester.tap(find.text('Remove file'));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(_viewport, findsNothing);
      expect(_loadingPreview, findsNothing);
      expect(thumbnail.debugDisposed, isTrue);
      expect(original, everyElement(0));
    });
  }

  testWidgets('an enlargement decode error leaves Back and Close available', (
    tester,
  ) async {
    final bytes = _page();
    final picker = DraftPicker()
      ..document = () => PickedShareFile('portrait.png', bytes);
    await draft(tester, picker);
    await selectAndComplete(tester, picker);
    // Corrupt the synthetic source after thumbnail validation to force the
    // full-resolution decoder's error path.
    bytes[0] = 0;
    await tester.tap(_enlarge);
    final error = find.text(
      'Could not enlarge this PNG. Close the preview and try again.',
    );
    await finishSelection(tester, () => error.evaluate().isNotEmpty);
    expect(_viewport, findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(_closePreview);
    await tester.pumpAndSettle();
    expect(find.byKey(_previewKey), findsOneWidget);
  });

  testWidgets(
    'cancellation clears the old preview and preserves the draft form',
    (tester) async {
      final picker = DraftPicker();
      await draft(tester, picker);
      await tester.enterText(field('share-title'), 'My draft');
      await tester.enterText(field('share-description'), 'Local note');
      await tester.enterText(field('share-recipient'), 'fixture-recipient');
      final before = tester
          .widget<ContentRestrictionsSummary>(
            find.byType(ContentRestrictionsSummary),
          )
          .restrictions;
      await selectAndComplete(tester, picker);
      final image = tester.widget<RawImage>(find.byKey(_previewKey)).image!;
      picker.choice = () => false;
      await selectAndComplete(tester, picker);
      expect(find.text('No file selected.'), findsOneWidget);
      expect(image.debugDisposed, isTrue);
      expect(picker.reads, hasLength(1));
      expect(input(tester, 'share-title'), 'My draft');
      expect(input(tester, 'share-description'), 'Local note');
      expect(input(tester, 'share-recipient'), 'fixture-recipient');
      expect(
        tester
            .widget<ContentRestrictionsSummary>(
              find.byType(ContentRestrictionsSummary),
            )
            .restrictions,
        same(before),
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Share Securely'),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(ContentStatusScreen), findsNothing);
    },
  );

  testWidgets('size limit reaches the reader and failure leaves no preview', (
    tester,
  ) async {
    final picker = DraftPicker();
    await draft(tester, picker, maxBytes: 50);
    await selectAndComplete(tester, picker);
    expect(picker.reads.single.$2, 50);
    expect(find.text('This file exceeds the 50 bytes limit.'), findsOneWidget);
    expect(find.byKey(_previewKey), findsNothing);
    expect(input(tester, 'share-title'), isEmpty);
  });

  testWidgets('unreadable file reports a safe error and allows retry', (
    tester,
  ) async {
    final picker = DraftPicker()
      ..document = () => throw StateError('file:///private/source.png');
    await draft(tester, picker);
    await selectAndComplete(tester, picker);
    expect(
      find.text('Could not read this file. Try another PNG.'),
      findsOneWidget,
    );
    expect(find.textContaining('/private/'), findsNothing);
    picker.choice = () => false;
    await selectAndComplete(tester, picker);
    expect(find.text('No file selected.'), findsOneWidget);
    expect(
      find.text('Could not read this file. Try another PNG.'),
      findsNothing,
    );
  });

  testWidgets(
    'duplicate taps do not reopen the picker; read waits for resume',
    (tester) async {
      final choice = Completer<bool>();
      final picker = DraftPicker()..choice = () => choice.future;
      picker.document = () =>
          throw const PngFileException(PngFileProblem.empty);
      await draft(tester, picker);
      await tester.tap(find.byKey(_selectKey));
      await tester.pump();
      await tester.tap(find.byKey(_selectKey));
      expect(picker.picks, hasLength(1));
      pause(tester);
      choice.complete(true);
      await tester.pump();
      expect(picker.reads, isEmpty);
      resume(tester);
      await tester.pumpAndSettle();
      expect(picker.reads, hasLength(1));
      expect(
        find.text('This file is empty. Choose another PNG.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'backgrounding releases a displayed preview without clearing fields',
    (tester) async {
      final bytes = pngFixture();
      final picker = DraftPicker()
        ..document = () => PickedShareFile('diagram.PNG', bytes);
      await draft(tester, picker);
      await tester.enterText(field('share-title'), 'Draft to keep');
      await selectAndComplete(tester, picker);
      final image = tester.widget<RawImage>(find.byKey(_previewKey)).image!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(image.debugDisposed, isTrue);
      expect(bytes, everyElement(0));
      expect(find.byKey(_previewKey), findsNothing);
      expect(find.byKey(_statusKey), findsOneWidget);
      expect(input(tester, 'share-title'), 'Draft to keep');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byKey(_previewKey), findsNothing);
      expect(tester.widget<TextField>(field('share-title')).readOnly, isFalse);
    },
  );

  testWidgets(
    'backgrounding during a read discards and wipes its late result',
    (tester) async {
      final pending = Completer<PickedShareFile>();
      final picker = DraftPicker()..document = () => pending.future;
      await draft(tester, picker);
      await tester.tap(find.byKey(_selectKey));
      await tester.pump();
      expect(picker.reads, hasLength(1));
      pause(tester);
      await tester.pump();
      expect(picker.discarded, picker.picks);
      final stale = pngFixture();
      pending.complete(PickedShareFile('stale.png', stale));
      resume(tester);
      await tester.pumpAndSettle();
      expect(stale, everyElement(0));
      expect(find.text('stale.png'), findsNothing);
      expect(find.byKey(_previewKey), findsNothing);
    },
  );

  testWidgets(
    'navigating back discards the request before a late picker callback',
    (tester) async {
      final choice = Completer<bool>();
      final picker = DraftPicker()..choice = () => choice.future;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ShareContentScreen(filePicker: picker),
                ),
              ),
              child: const Text('Open draft'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open draft'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_selectKey));
      await tester.tap(find.byKey(_selectKey));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(picker.discarded, picker.picks);
      choice.complete(true);
      await tester.pump();
      expect(picker.reads, isEmpty);
      expect(find.byType(ShareContentScreen), findsNothing);
    },
  );

  testWidgets(
    'account dashboard opens a local draft and logout releases preview without upload',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 1450);
      addTearDown(tester.view.reset);
      final fake = ApiFake();
      final account = fake.session();
      await account.login('synthetic-user', 'sample');
      final channelCalls = <String>[];
      final finished = Completer<void>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final channel = NativeShareFilePicker.channel.name;
      const codec = StandardMethodCodec();
      messenger.setMockMessageHandler(channel, (message) async {
        final call = codec.decodeMethodCall(message!);
        channelCalls.add(call.method);
        if (call.method == 'discard') finished.complete();
        final result = switch (call.method) {
          'pick' => true,
          'read' => {
            'name': 'account.png',
            'mimeType': 'image/png',
            'bytes': pngFixture(),
          },
          _ => null,
        };
        // PlatformDispatcher delivers a read-only platform message on device.
        return codec.encodeSuccessEnvelope(result).asUnmodifiableView();
      });
      addTearDown(() => messenger.setMockMessageHandler(channel, null));
      try {
        await tester.pumpWidget(ApiApplication(session: account));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Prepare PNG'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_selectKey));
        await finishSelection(tester, () => finished.isCompleted);
        final image = tester.widget<RawImage>(find.byKey(_previewKey)).image!;
        await tester.tap(_enlarge);
        await tester.pump();
        expect(_loadingPreview, findsOneWidget);
        await finishSelection(tester, () => _viewport.evaluate().isNotEmpty);
        final enlarged = tester.widget<RawImage>(find.byType(RawImage)).image!;
        expect(channelCalls, ['pick', 'read', 'discard']);
        await account.logout();
        await tester.pumpAndSettle();
        expect(image.debugDisposed, isTrue);
        expect(enlarged.debugDisposed, isTrue);
        expect(enlarged.debugGetOpenHandleStackTraces(), isEmpty);
        expect(find.byType(ShareContentScreen), findsNothing);
        expect(
          fake.calls
              .where((call) => call.method == 'POST')
              .map((call) => call.uri.path),
          ['/api/auth/login', '/api/auth/logout'],
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        account.dispose();
      }
    },
  );
}
