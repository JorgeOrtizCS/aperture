import 'package:aperture/models/api_models.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/week11_demo.dart';

const _device = '11111111-1111-4111-8111-111111111111';
final _denied = isA<ApiException>().having(
  (error) => error.kind,
  'kind',
  ApiFailure.denied,
);

void main() {
  testWidgets('offline demo controls are available to accessibility services', (
    tester,
  ) async {
    await tester.pumpWidget(const Week11DemoApp());
    await tester.pumpAndSettle();

    final banner = find.semantics.byLabel(
      'Offline demo · Sample accounts and data',
    );
    final sessionDemo = find.semantics.byLabel('Session demo');
    expect(banner, findsOne);
    expect(sessionDemo, findsOne);
    tester.semantics.tap(sessionDemo);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(banner, findsNothing);
    expect(find.text('Locked sample session'), findsOneWidget);
  });

  testWidgets(
    'large text stays visible after rotating with the keyboard open',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 914);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const Week11DemoApp());

      final start = find.text('Get Started');
      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pumpAndSettle();
      final username = find.byType(EditableText).first;
      await tester.ensureVisible(username);
      await tester.enterText(username, demoSender);

      tester.platformDispatcher.textScaleFactorTestValue = 1.75;
      tester.view.physicalSize = const Size(571, 320);
      tester.view.padding = const FakeViewPadding(top: 28, left: 32, right: 48);
      tester.view.viewInsets = const FakeViewPadding(bottom: 184);
      await tester.pumpAndSettle();
      await tester.ensureVisible(username);
      await tester.pumpAndSettle();

      final editable = tester.getRect(username);
      final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
      expect(editable.top, greaterThanOrEqualTo(viewport.top));
      expect(editable.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(find.semantics.byLabel('Offline demo'), findsOne);

      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(find.text('Session demo'), findsOneWidget);
      expect(tester.widget<EditableText>(username).controller.text, demoSender);
    },
  );

  late ApiService api;
  setUp(() {
    api = ApiService.fixture(
      transport: Week11DemoTransport(),
      canOpenContentRoutes: true,
    );
  });

  test('sender can pause, resume and revoke only the managed sample', () async {
    final owner = ApiSession(api);
    try {
      await owner.login(demoSender, 'demo');
      await owner.refresh();
      expect(owner.items.single.title, demoOwnerItem);
      await owner.setPolicy(1, 'Paused');
      expect(owner.items.single.policyStatus, 'Paused');
      await owner.refresh();
      expect(owner.items.single.policyStatus, 'Paused');
      await owner.setPolicy(1, 'Active');
      expect(owner.items.single.policyStatus, 'Active');
      await owner.revoke(1);
      expect(owner.items.single.status, 'Revoked');
      await expectLater(owner.setPolicy(1, 'Active'), throwsA(_denied));
    } finally {
      owner.dispose();
    }
  });

  test('recipient sees the same revocation but cannot change it', () async {
    try {
      final sender = await api.login(demoSender, 'demo');
      final recipient = await api.login(demoRecipient, 'demo');
      await expectLater(
        api.policy(recipient.token, 1, 'Paused'),
        throwsA(_denied),
      );
      await expectLater(api.revoke(recipient.token, 1), throwsA(_denied));
      await api.revoke(sender.token, 1);
      final items = await api.list(recipient.token);
      expect(items.first.status, 'Revoked');
      expect(items.last.title, demoLocationItem);
      expect(items.last.requiresPreciseLocation, isTrue);
      expect(items.last.requiresTrustedDevice, isTrue);
      await api.logout(sender.token);
      await expectLater(
        api.list(sender.token),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailure.credentials,
          ),
        ),
      );
    } finally {
      api.close();
    }
  });

  test(
    'demo transport never grants viewing, upload or an absolute URL',
    () async {
      try {
        expect(api.baseUri, isNull);
        expect(api.canCreateContent, isFalse);
        final sender = await api.login(demoSender, 'demo');
        final recipient = await api.login(demoRecipient, 'demo');
        for (final account in [sender, recipient]) {
          for (final id in [1, 2]) {
            final decision = await api.open(account.token, id, _device);
            expect(decision.granted, isFalse);
            expect(decision.ended, isTrue);
            expect(decision.sessionId, isNull);
          }
          expect((await api.check(account.token, 1)).granted, isFalse);
        }
        expect(
          (await api.transport.send('POST', Uri(path: '/api/content'), {
            'Authorization': 'Bearer ${sender.token}',
          }, '{}')).status,
          403,
        );
        expect(
          (await api.transport.send(
            'POST',
            Uri.parse('https://example.invalid/api/auth/login'),
            {},
            '{}',
          )).status,
          403,
        );
      } finally {
        api.close();
      }
    },
  );
}
