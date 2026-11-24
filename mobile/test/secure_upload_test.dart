import 'dart:async';
import 'dart:convert';

import 'package:aperture/main.dart';
import 'package:aperture/models/api_models.dart';
import 'package:aperture/models/content_create_request.dart';
import 'package:aperture/models/location_radius_policy.dart';
import 'package:aperture/screens/share_content_screen.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_session.dart';
import 'package:aperture/services/share_file_selection.dart';
import 'package:aperture/services/share_upload_draft.dart';
import 'package:aperture/widgets/api_scope.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:aperture/widgets/content_restrictions_summary.dart';
import 'package:aperture/widgets/restriction_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';
import 'support/png_fixture.dart';

final now = DateTime.utc(2026, 11, 5);

class UploadFixture extends ApiFake implements CancellableApiTransport {
  final cancellations = <ApiRequestCancellation>[];

  Iterable<ApiCall> get submissions => calls.where(
    (call) => call.method == 'POST' && call.uri.path == '/api/content',
  );

  ApiSession uploadSession({Duration timeout = const Duration(seconds: 4)}) =>
      ApiSession(
        ApiService.uploadFixture(transport: this, timeout: timeout),
        now: () => now,
      );

  @override
  Future<ApiReply> sendCancellable(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
    ApiRequestCancellation cancellation,
  ) {
    cancellations.add(cancellation);
    // Keep the injected exchange outstanding after cancellation to exercise
    // stale responses even when a transport cannot undo a dispatched write.
    return send(method, uri, headers, body);
  }
}

class DelayedUploadSession extends ApiSession {
  DelayedUploadSession(UploadFixture fixture)
    : super(ApiService.uploadFixture(transport: fixture), now: () => now);

  final readyToDispatch = Completer<void>();

  @override
  Future<int> createContent(
    ContentCreateRequest request,
    Uint8List? png, {
    required int maxBytes,
    required ApiRequestCancellation cancellation,
  }) async {
    await readyToDispatch.future;
    return super.createContent(
      request,
      png,
      maxBytes: maxBytes,
      cancellation: cancellation,
    );
  }
}

Matcher apiFailure(ApiFailure kind) =>
    isA<ApiException>().having((error) => error.kind, 'kind', kind);
Matcher draftProblem(ContentDraftProblem kind) => isA<ContentDraftException>()
    .having((error) => error.problem, 'problem', kind);

ContentCreateRequest request({
  String recipient = 'synthetic-recipient',
  String sender = 'synthetic-user',
  ContentRestrictions restrictions = ContentRestrictions.demoDefaults,
}) => buildShareUploadDraft(
  title: '  Synthetic share  ',
  recipient: recipient,
  sender: sender,
  restrictions: restrictions,
  now: now,
);

Future<int> submit(
  ApiSession account, {
  Uint8List? bytes,
  ApiRequestCancellation? cancellation,
}) => account.createContent(
  request(),
  bytes ?? pngFixture(),
  maxBytes: ContentCreateRequest.maxPngBytes,
  cancellation: cancellation ?? ApiRequestCancellation(),
);

Future<void> login(ApiSession account, [String username = 'synthetic-user']) =>
    account.login(username, 'fixture-only');

class TestPicker implements ShareFilePicker {
  final bytes = pngFixture();
  bool discarded = false;
  @override
  Future<bool> pick(int requestId) async => true;
  @override
  Future<PickedShareFile> read(int requestId, int maxBytes) async =>
      PickedShareFile('synthetic.png', bytes);
  @override
  Future<void> discard(int requestId) async {
    discarded = true;
  }
}

Finder draftField(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);

Future<void> mountDraft(
  WidgetTester tester,
  ApiSession account,
  TestPicker picker,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(480, 1600);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ApiScope(
      session: account,
      child: MaterialApp(home: ShareContentScreen(filePicker: picker)),
    ),
  );
  for (final (key, value) in [
    ('share-title', 'Synthetic title'),
    ('share-description', 'Local note only'),
    ('share-recipient', 'synthetic-recipient'),
  ]) {
    await tester.enterText(draftField(key), value);
  }
  await tester.tap(find.byKey(const ValueKey('share-select-png')));
  for (var i = 0; i < 200 && !picker.discarded; i++) {
    await tester.pump();
    if (!picker.discarded) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }
  expect(picker.discarded, isTrue);
  await tester.pumpAndSettle();
  final button = find.text('Share Securely');
  if (button.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'wire request encodes the original PNG and preserves supported policies',
    () {
      final bytes = pngFixture();
      final data = request(
        recipient: '  synthetic-recipient  ',
        restrictions: ContentRestrictions.demoDefaults.copyWith(
          accessDuration: AccessDuration.oneWeek,
          viewLimit: 5,
          viewingStartsAt: DateTime.parse('2026-11-05T01:30:00-05:00'),
          locationArea: const SenderLocationDraft(
            enabled: true,
            latitude: '26',
            longitude: '-80',
          ),
        ),
      ).encode(bytes, maxBytes: bytes.length);
      expect(data, {
        'Title': 'Synthetic share',
        'Recipient': 'synthetic-recipient',
        'FileType': 'image/png',
        'FileDataBase64': base64Encode(bytes),
        'ScreenshotRestriction': true,
        'RequireTrustedDevice': false,
        'StartTime': '2026-11-05T06:30:00.000Z',
        'ExpiresAt': '2026-11-12T00:00:00.000Z',
        'MaxViews': 5,
        'Latitude': 26.0,
        'Longitude': -80.0,
        'RadiusMeters': 100.0,
      });
      expect(base64Decode(data['FileDataBase64']! as String), bytes);
    },
  );

  test('optional time, trusted device and unlimited views map without invented fields', () {
    final bytes = pngFixture();
    final draft = ContentCreateRequest.validate(
      title: 'Example',
      recipient: 'recipient',
      sender: 'sender',
      now: now,
      startTime: now.add(const Duration(hours: 1)),
      expiresAt: now.add(const Duration(hours: 12)),
      screenshotRestriction: false,
      requireTrustedDevice: true,
    );
    final wire = draft.encode(bytes, maxBytes: 1000);
    expect(wire['RequireTrustedDevice'], isTrue);
    expect(wire['ScreenshotRestriction'], isFalse);
    expect(wire['StartTime'], '2026-11-05T01:00:00.000Z');
    expect(wire.containsKey('MaxViews'), isFalse);
    expect(wire.containsKey('Body'), isFalse);
    expect(wire.containsKey('Latitude'), isFalse);
    expect(draft.toString(), isNot(contains('recipient')));
  });

  test('sender draft rejects a start at its calculated expiry', () {
    expect(
      () => request(
        restrictions: ContentRestrictions.demoDefaults.copyWith(
          viewingStartsAt: now.add(const Duration(days: 2)),
        ),
      ),
      throwsA(isA<ContentDraftException>()),
    );
  });

  test(
    'network location uses only the source fields and cannot mix with GPS',
    () {
      final bytes = pngFixture();
      final policy = ContentRestrictions.demoDefaults.copyWith(
        networkLocation: const NetworkLocation(
          country: ' US ',
          city: 'Example City',
        ),
      );
      final data = request(restrictions: policy)
          .encode(bytes, maxBytes: bytes.length);
      expect(data['AllowedCountry'], 'US');
      expect(data['AllowedCity'], 'Example City');
      expect(
        data.keys.toSet().intersection({
          'Latitude',
          'Longitude',
          'RadiusMeters',
        }),
        isEmpty,
      );
      expect(data.containsKey('AllowedRegion'), isFalse);
      expect(
        () => request(
          restrictions: policy.copyWith(
            locationArea: const SenderLocationDraft(
              enabled: true,
              latitude: '26',
              longitude: '-80',
            ),
          ),
        ),
        throwsA(draftProblem(ContentDraftProblem.policy)),
      );
    },
  );

  for (final value in ['', ' SYNTHETIC-USER ', 'bad\nname', 'x' * 101]) {
    test('rejects an invalid recipient candidate [${value.length}]', () {
      expect(
        () => request(recipient: value),
        throwsA(draftProblem(ContentDraftProblem.recipient)),
      );
    });
  }

  for (final (policy, kind) in [
    (
      ContentRestrictions.demoDefaults.copyWith(viewLimit: 0),
      ContentDraftProblem.policy,
    ),
    (
      ContentRestrictions.demoDefaults.copyWith(
        locationArea: const SenderLocationDraft(enabled: true),
      ),
      ContentDraftProblem.policy,
    ),
    (
      ContentRestrictions.demoDefaults.copyWith(allowDownload: true),
      ContentDraftProblem.unsupportedPolicy,
    ),
    (
      ContentRestrictions.demoDefaults.copyWith(allowResharing: true),
      ContentDraftProblem.unsupportedPolicy,
    ),
  ]) {
    test(
      'rejects invalid or unmappable policy ${kind.name} ${policy.allowDownload} ${policy.allowResharing} ${policy.viewLimit}',
      () {
        expect(
          () => request(restrictions: policy),
          throwsA(draftProblem(kind)),
        );
      },
    );
  }

  test('rejects a time window that would already be expired', () {
    expect(
      () => ContentCreateRequest.validate(
        title: 'Example',
        recipient: 'recipient',
        sender: 'sender',
        now: now,
        expiresAt: now,
        screenshotRestriction: true,
      ),
      throwsA(draftProblem(ContentDraftProblem.policy)),
    );
  });

  for (final (label, bytes, limit, kind)
      in <(String, Uint8List?, int, ContentDraftProblem)>[
        ('missing', null, 1024, ContentDraftProblem.missingFile),
        ('empty', Uint8List(0), 1024, ContentDraftProblem.missingFile),
        (
          'unsupported',
          Uint8List.fromList(List.filled(64, 71)),
          1024,
          ContentDraftProblem.unsupportedImage,
        ),
        (
          'over configured limit',
          pngFixture(),
          30,
          ContentDraftProblem.tooLarge,
        ),
        (
          'over backend limit',
          Uint8List(ContentCreateRequest.maxPngBytes + 1),
          99999999,
          ContentDraftProblem.tooLarge,
        ),
      ]) {
    test('$label image is rejected and wiped before dispatch', () async {
      final fake = UploadFixture();
      final account = fake.uploadSession();
      addTearDown(account.dispose);
      await login(account);
      await expectLater(
        account.createContent(
          request(),
          bytes,
          maxBytes: limit,
          cancellation: ApiRequestCancellation(),
        ),
        throwsA(draftProblem(kind)),
      );
      expect(fake.submissions, isEmpty);
      expect(account.uploadNeedsReconciliation, isFalse);
      expect(bytes?.every((byte) => byte == 0) ?? true, isTrue);
    });
  }

  test('original file is staged only by explicit opt-in and wiped on preview disposal', () async {
    final plain = pngFixture();
    final preview = await PngFileValidator.validate(
      PickedShareFile('image.png', plain),
      maxBytes: 1024,
    );
    expect(preview.takeUploadBytes(), isNull);
    expect(plain, everyElement(0));
    preview.dispose();
    final staged = pngFixture();
    final testPreview = await PngFileValidator.validate(
      PickedShareFile('image.png', staged),
      maxBytes: 1024,
      stageForUpload: true,
    );
    expect(testPreview.hasUploadBytes, isTrue);
    testPreview.dispose();
    expect(staged, everyElement(0));
  });

  test(
    'live and normal offline transports reject create without dispatch',
    () async {
      final fake = UploadFixture();
      for (final api in [fake.service(), ApiService.fixture(transport: fake)]) {
        final bytes = pngFixture();
        await expectLater(
          api.createContent(
            'fixture-token',
            request(),
            bytes,
            maxBytes: 1024,
            cancellation: ApiRequestCancellation(),
            onDispatch: () => fail('Unexpected dispatch'),
          ),
          throwsA(apiFailure(ApiFailure.uploadUnverified)),
        );
        expect(bytes, everyElement(0));
      }
      expect(fake.calls, isEmpty);
    },
  );

  test(
    'missing authentication does not dispatch and wipes the selected buffer',
    () async {
      final fake = UploadFixture();
      final account = fake.uploadSession();
      addTearDown(account.dispose);
      final bytes = pngFixture();
      await expectLater(
        submit(account, bytes: bytes),
        throwsA(apiFailure(ApiFailure.credentials)),
      );
      expect(fake.calls, isEmpty);
      expect(bytes, everyElement(0));
    },
  );

  test(
    'only a positive integer id acknowledges one authenticated dispatch',
    () async {
      final fake = UploadFixture();
      final account = fake.uploadSession();
      addTearDown(account.dispose);
      await login(account);
      final bytes = pngFixture();
      final original = Uint8List.fromList(bytes);
      final reply = Completer<ApiReply>();
      fake.routes['/api/content'] = (_) => reply.future;
      final result = submit(account, bytes: bytes);
      expect(account.uploadPending, isTrue);
      final call = fake.submissions.single;
      expect(call.uri.hasAuthority, isFalse);
      expect(call.headers['Authorization'], 'Bearer ${fake.token}');
      expect(call.headers['Content-Type'], 'application/json');
      expect(base64Decode(call.json['FileDataBase64'] as String), original);
      expect(bytes, everyElement(0));
      await expectLater(
        submit(account),
        throwsA(apiFailure(ApiFailure.pending)),
      );
      reply.complete(jsonReply({'id': 41}));
      expect(await result, 41);
      expect(account.uploadPending, isFalse);
      expect(account.items, isEmpty);
      expect(fake.submissions, hasLength(1));
    },
  );

  test(
    'pre-dispatch cancellation allows a later explicit submission',
    () async {
      final fake = UploadFixture();
      final account = fake.uploadSession();
      addTearDown(account.dispose);
      await login(account);
      final bytes = pngFixture();
      final cancellation = ApiRequestCancellation()..cancel();
      await expectLater(
        submit(account, bytes: bytes, cancellation: cancellation),
        throwsA(apiFailure(ApiFailure.cancelled)),
      );
      expect(fake.submissions, isEmpty);
      expect(bytes, everyElement(0));
      expect(account.uploadNeedsReconciliation, isFalse);
      fake.routes['/api/content'] = (_) => jsonReply({'id': 42});
      expect(await submit(account), 42);
    },
  );

  test('cancellation after dispatch signals transport and ignores a late acknowledgement', () async {
    final fake = UploadFixture();
    final account = fake.uploadSession();
    addTearDown(account.dispose);
    await login(account);
    final reply = Completer<ApiReply>();
    fake.routes['/api/content'] = (_) => reply.future;
    final cancellation = ApiRequestCancellation();
    final result = submit(account, cancellation: cancellation);
    final rejected = expectLater(
      result,
      throwsA(apiFailure(ApiFailure.cancelled)),
    );
    cancellation.cancel();
    await rejected;
    expect(fake.cancellations.single.isCancelled, isTrue);
    expect(account.uploadNeedsReconciliation, isTrue);
    reply.complete(jsonReply({'id': 41}));
    await expectLater(
      submit(account),
      throwsA(apiFailure(ApiFailure.uploadUnconfirmed)),
    );
    expect(fake.submissions, hasLength(1));
  });

  for (final (label, handler, kind)
      in <(String, FutureOr<ApiReply> Function(ApiCall), ApiFailure)>[
        (
          'network error',
          (_) => throw StateError('private response details'),
          ApiFailure.network,
        ),
        (
          'server error',
          (_) => const ApiReply(500, 'private response details'),
          ApiFailure.server,
        ),
        (
          'malformed acknowledgement',
          (_) => jsonReply({'id': '41'}),
          ApiFailure.malformed,
        ),
        (
          'missing acknowledgement',
          (_) => jsonReply({'success': true}),
          ApiFailure.malformed,
        ),
      ]) {
    test(
      '$label does not confirm a share or allow a duplicate retry',
      () async {
        final fake = UploadFixture();
        final account = fake.uploadSession();
        addTearDown(account.dispose);
        await login(account);
        fake.routes['/api/content'] = handler;
        await expectLater(submit(account), throwsA(apiFailure(kind)));
        expect(account.uploadNeedsReconciliation, isTrue);
        await expectLater(
          submit(account),
          throwsA(apiFailure(ApiFailure.uploadUnconfirmed)),
        );
        expect(fake.submissions, hasLength(1));
      },
    );
  }

  test(
    'timeout aborts the wait and blocks retry even if a late success arrives',
    () async {
      final fake = UploadFixture();
      final account = fake.uploadSession(
        timeout: const Duration(milliseconds: 15),
      );
      addTearDown(account.dispose);
      await login(account);
      final reply = Completer<ApiReply>();
      fake.routes['/api/content'] = (_) => reply.future;
      await expectLater(
        submit(account),
        throwsA(apiFailure(ApiFailure.timeout)),
      );
      expect(fake.cancellations.single.isCancelled, isTrue);
      reply.complete(jsonReply({'id': 41}));
      await expectLater(
        submit(account),
        throwsA(apiFailure(ApiFailure.uploadUnconfirmed)),
      );
      expect(fake.submissions, hasLength(1));
    },
  );

  test('explicit 400 permits a corrected new submit and never retries automatically', () async {
    final fake = UploadFixture();
    final account = fake.uploadSession();
    addTearDown(account.dispose);
    await login(account);
    fake.routes['/api/content'] = (_) =>
        const ApiReply(400, 'fixture rejection');
    await expectLater(
      submit(account),
      throwsA(apiFailure(ApiFailure.invalidRequest)),
    );
    expect(fake.submissions, hasLength(1));
    expect(account.uploadNeedsReconciliation, isFalse);
    fake.routes['/api/content'] = (_) => jsonReply({'id': 42});
    expect(await submit(account), 42);
    expect(fake.submissions, hasLength(2));
  });

  test(
    '401 clears the active identity and never marks content shared',
    () async {
      final fake = UploadFixture();
      final account = fake.uploadSession();
      addTearDown(account.dispose);
      await login(account);
      fake.routes['/api/content'] = (_) =>
          const ApiReply(401, 'fixture unauthorized');
      await expectLater(
        submit(account),
        throwsA(apiFailure(ApiFailure.credentials)),
      );
      expect(account.authenticated, isFalse);
      expect(account.items, isEmpty);
      expect(fake.submissions, hasLength(1));
    },
  );

  test(
    '403 denies the operation without signing out a valid account',
    () async {
      final fake = UploadFixture();
      final account = fake.uploadSession();
      addTearDown(account.dispose);
      await login(account);
      fake.routes['/api/content'] = (_) =>
          const ApiReply(403, 'fixture denial');
      await expectLater(
        submit(account),
        throwsA(apiFailure(ApiFailure.denied)),
      );
      expect(account.authenticated, isTrue);
      expect(account.uploadNeedsReconciliation, isFalse);
      expect(fake.submissions, hasLength(1));
    },
  );

  for (final status in [200, 401]) {
    test(
      'logout during upload ignores stale $status and preserves the same-account retry lock',
      () async {
        final fake = UploadFixture();
        final account = fake.uploadSession();
        addTearDown(account.dispose);
        await login(account);
        final reply = Completer<ApiReply>();
        fake.routes['/api/content'] = (_) => reply.future;
        final result = submit(account);
        final rejected = expectLater(
          result,
          throwsA(apiFailure(ApiFailure.stale)),
        );
        await account.logout();
        await rejected;
        expect(fake.cancellations.single.isCancelled, isTrue);
        fake.userId = 2;
        fake.username = 'replacement';
        fake.token = 'replacement-fixture-token';
        await login(account, 'replacement');
        reply.complete(jsonReply({'id': 41}, status));
        await Future<void>.delayed(Duration.zero);
        expect(account.user?.id, 2);
        expect(account.uploadNeedsReconciliation, isFalse);
        fake.userId = 1;
        fake.username = 'synthetic-user';
        await login(account);
        await expectLater(
          submit(account),
          throwsA(apiFailure(ApiFailure.uploadUnconfirmed)),
        );
        expect(fake.submissions, hasLength(1));
      },
    );
  }

  testWidgets(
    'authenticated dashboard draft reviews local settings and never uploads',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1200);
      addTearDown(tester.view.reset);
      final fake = UploadFixture();
      final account = fake.session();
      await login(account);
      Future<void> tap(String label) async {
        final target = find.text(label);
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(ApiApplication(session: account));
        await tester.pumpAndSettle();
        await tap('Prepare PNG');
        final recipient = draftField('share-recipient');
        await tester.enterText(recipient, ' SYNTHETIC-USER ');
        await tester.pump();
        expect(
          find.text(
            'Enter a different account’s username (up to 100 characters).',
          ),
          findsOneWidget,
        );
        await tester.enterText(recipient, 'synthetic-recipient');
        await tap('Edit Policy');
        expect(
          find.textContaining('Save keeps these settings in this draft'),
          findsOneWidget,
        );
        final maximum = find.byType(DropdownButtonFormField<String>);
        await tester.ensureVisible(maximum);
        await tester.tap(maximum);
        await tester.pumpAndSettle();
        await tester.tap(find.text('1 view').last);
        await tester.pumpAndSettle();
        await tap('Save');
        expect(find.text('Maximum views: 1'), findsOneWidget);
        expect(
          tester.widget<TextField>(recipient).controller!.text,
          'synthetic-recipient',
        );
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Share Securely'),
              )
              .onPressed,
          isNull,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tap('Prepare PNG');
        expect(tester.widget<TextField>(recipient).controller!.text, isEmpty);
        expect(find.text('Maximum views: 3'), findsOneWidget);
        expect(fake.submissions, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        account.dispose();
      }
    },
  );

  testWidgets(
    'local preview keeps Share disabled and wipes its source on removal',
    (tester) async {
      final fake = UploadFixture();
      final account = fake.session();
      await login(account);
      final picker = TestPicker();
      try {
        await mountDraft(tester, account, picker);
        expect(picker.bytes, isNot(everyElement(0)));
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Share Securely'),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.text(
            'Encrypted upload is unavailable. Your draft has not been shared.',
          ),
          findsOneWidget,
        );
        expect(fake.submissions, isEmpty);
        final remove = find.text('Remove file');
        await tester.scrollUntilVisible(
          remove,
          150,
          scrollable: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );
        await tester.tap(remove);
        await tester.pump();
        expect(picker.bytes, everyElement(0));
        expect(fake.submissions, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        account.dispose();
      }
    },
  );

  for (final cancel in [false, true]) {
    testWidgets(
      'fixture UI waits for acknowledgement and handles ${cancel ? 'cancel' : 'success'}',
      (tester) async {
        final fake = UploadFixture();
        final account = fake.uploadSession();
        await login(account);
        final reply = Completer<ApiReply>();
        fake.routes['/api/content'] = (_) => reply.future;
        final picker = TestPicker();
        try {
          await mountDraft(tester, account, picker);
          final preview = tester
              .widget<RawImage>(find.byKey(const ValueKey('share-png-preview')))
              .image!;
          final submit = find.widgetWithText(ElevatedButton, 'Share Securely');
          final edit = find.widgetWithText(ElevatedButton, 'Edit Policy');
          if (!cancel) {
            await tester.ensureVisible(edit);
            await tester.tap(edit);
            await tester.pumpAndSettle();
            final policy = tester.widget<ContentRestrictionsSection>(
              find.byType(ContentRestrictionsSection),
            );
            policy.onChanged(policy.restrictions.copyWith(viewLimit: 5));
            await tester.pumpAndSettle();
            final start = find.widgetWithText(
              TextFormField,
              'Viewing start (optional)',
            );
            await tester.ensureVisible(start);
            await tester.enterText(start, '2026-11-05T01:00:00Z');
            final trust = find.widgetWithText(
              RestrictionTile,
              'Require a service-approved device',
            );
            await tester.ensureVisible(trust);
            await tester.tap(
              find.descendant(of: trust, matching: find.byType(Switch)),
            );
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('Save'));
            await tester.tap(find.text('Save'));
            await tester.pumpAndSettle();
          }
          final editBeforeDispatch = tester.widget<ElevatedButton>(edit);
          if (submit.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              submit,
              200,
              scrollable: find.byType(Scrollable).first,
            );
          }
          await Scrollable.ensureVisible(
            tester.element(submit),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Share Securely'));
          // Exercise a second tap on the old frame before the button rebuilds.
          await tester.tap(submit);
          await tester.pump();
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(find.textContaining('acknowledged content'), findsNothing);
          expect(
            tester
                .widget<ElevatedButton>(
                  find.widgetWithText(ElevatedButton, 'Submitting…'),
                )
                .onPressed,
            isNull,
          );
          for (final (key, value) in [
            ('share-title', 'Synthetic title'),
            ('share-description', 'Local note only'),
            ('share-recipient', 'synthetic-recipient'),
          ]) {
            final field = tester.widget<TextField>(draftField(key));
            expect(field.readOnly, isTrue);
            expect(field.controller!.text, value);
          }
          expect(tester.widget<ElevatedButton>(edit).onPressed, isNull);
          final frozenPolicy = tester
              .widget<ContentRestrictionsSummary>(
                find.byType(ContentRestrictionsSummary),
              )
              .restrictions;
          expect(frozenPolicy.viewLimit, cancel ? 3 : 5);
          expect(frozenPolicy.restrictScreenshots, isTrue);
          editBeforeDispatch.onPressed!();
          await tester.pump();
          expect(find.text('Viewing Requirements'), findsNothing);
          final pickerAction = find.byKey(const ValueKey('share-select-png'));
          expect(tester.widget<InkWell>(pickerAction).onTap, isNull);
          for (final label in ['Remove file', 'Enlarge preview']) {
            expect(
              tester
                  .widget<TextButton>(find.widgetWithText(TextButton, label))
                  .onPressed,
              isNull,
            );
          }
          expect(picker.bytes, everyElement(0));
          expect(preview.debugDisposed, isFalse);
          final body = fake.submissions.single.json as Map<String, dynamic>;
          expect(body['Title'], 'Synthetic title');
          expect(body['Recipient'], 'synthetic-recipient');
          expect(body['MaxViews'], cancel ? 3 : 5);
          expect(body['StartTime'], cancel ? null : '2026-11-05T01:00:00.000Z');
          expect(body['RequireTrustedDevice'], !cancel);
          expect(body['ScreenshotRestriction'], isTrue);
          expect(body.containsKey('Body'), isFalse);
          if (cancel) {
            final button = find.text('Cancel submission');
            await tester.ensureVisible(button);
            await tester.tap(button);
            await tester.pump();
            await tester.pump();
            reply.complete(jsonReply({'id': 41}));
            await tester.pumpAndSettle();
            expect(
              find.textContaining('server outcome is unknown'),
              findsOneWidget,
            );
            expect(find.textContaining('acknowledged content'), findsNothing);
          } else {
            reply.complete(jsonReply({'id': 41}));
            await tester.pumpAndSettle();
            expect(
              find.text('Test fixture acknowledged content #41.'),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('share-png-preview')),
              findsNothing,
            );
          }
          expect(preview.debugDisposed, isTrue);
          expect(
            tester.widget<TextField>(draftField('share-title')).readOnly,
            isFalse,
          );
          expect(fake.submissions, hasLength(1));
        } finally {
          await tester.pumpWidget(const SizedBox());
          account.dispose();
        }
      },
    );
  }

  testWidgets('local rejection keeps the draft available to correct', (
    tester,
  ) async {
    final fake = UploadFixture();
    final account = fake.uploadSession();
    await login(account);
    try {
      await mountDraft(tester, account, TestPicker());
      await tester.enterText(draftField('share-title'), '');
      await tester.ensureVisible(find.text('Share Securely'));
      await tester.tap(find.text('Share Securely'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Submission was not sent. Enter a title of at most 160 characters.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('share-png-preview')), findsOneWidget);
      expect(
        tester.widget<TextField>(draftField('share-title')).readOnly,
        isFalse,
      );
      expect(fake.submissions, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox());
      account.dispose();
    }
  });

  testWidgets('cancel before dispatch reports cancellation and wipes bytes', (
    tester,
  ) async {
    final fake = UploadFixture();
    final account = DelayedUploadSession(fake);
    await login(account);
    final picker = TestPicker();
    try {
      await mountDraft(tester, account, picker);
      await tester.tap(find.text('Share Securely'));
      await tester.pump();
      final cancel = find.text('Cancel submission');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      account.readyToDispatch.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('Submission cancelled before dispatch.'),
        findsOneWidget,
      );
      expect(fake.submissions, isEmpty);
      expect(account.uploadNeedsReconciliation, isFalse);
      expect(picker.bytes, everyElement(0));
      expect(find.byKey(const ValueKey('share-png-preview')), findsNothing);
    } finally {
      if (!account.readyToDispatch.isCompleted) {
        account.readyToDispatch.complete();
      }
      await tester.pumpWidget(const SizedBox());
      account.dispose();
    }
  });

  for (final (label, response, message, unknown) in [
    (
      'confirmed rejection',
      const ApiReply(400, 'private response details'),
      'Test fixture rejected the submission before writing.',
      false,
    ),
    (
      'confirmed denial',
      const ApiReply(403, 'private response details'),
      'Test fixture denied the submission before writing.',
      false,
    ),
    ('malformed acknowledgement', jsonReply({'id': '41'}), null, true),
    ('timed-out acknowledgement', null, null, true),
  ]) {
    testWidgets('fixture UI reports $label accurately', (tester) async {
      final fake = UploadFixture();
      final account = fake.uploadSession();
      await login(account);
      final reply = Completer<ApiReply>();
      fake.routes['/api/content'] = (_) => reply.future;
      try {
        await mountDraft(tester, account, TestPicker());
        await tester.tap(find.text('Share Securely'));
        await tester.pump();
        if (response == null) {
          await tester.pump(const Duration(seconds: 4));
          reply.complete(jsonReply({'id': 41}));
        } else {
          reply.complete(response);
        }
        await tester.pumpAndSettle();
        expect(
          find.text(
            message ?? const ApiException(ApiFailure.uploadUnconfirmed).message,
          ),
          findsOneWidget,
        );
        expect(find.textContaining('acknowledged content'), findsNothing);
        expect(find.textContaining('private response details'), findsNothing);
        expect(account.uploadNeedsReconciliation, unknown);
        expect(fake.submissions, hasLength(1));
      } finally {
        await tester.pumpWidget(const SizedBox());
        account.dispose();
      }
    });
  }

  testWidgets('an old acknowledgement cannot update a replacement account', (
    tester,
  ) async {
    final fake = UploadFixture();
    final account = fake.uploadSession();
    await login(account);
    final reply = Completer<ApiReply>();
    fake.routes['/api/content'] = (_) => reply.future;
    try {
      await mountDraft(tester, account, TestPicker());
      await tester.tap(find.text('Share Securely'));
      await tester.pump();
      await account.logout();
      fake.userId = 2;
      fake.username = 'replacement';
      fake.token = 'replacement-fixture-token';
      await login(account, 'replacement');
      reply.complete(jsonReply({'id': 41}));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('share-upload-status')), findsNothing);
      expect(find.byKey(const ValueKey('share-png-preview')), findsNothing);
      expect(account.user?.id, 2);
      expect(account.uploadNeedsReconciliation, isFalse);
      expect(fake.submissions, hasLength(1));
    } finally {
      await tester.pumpWidget(const SizedBox());
      account.dispose();
    }
  });
}
