import 'dart:async';

import 'package:aperture/screens/api_content_screens.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/biometric_status_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/api_fake.dart';
import '../test/support/biometric_fake.dart';

// Runs on the emulator. Only the recipient case uses a native capture bridge.
// HTTP and identity are fixtures. Neither case displays protected content.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> tap(
    WidgetTester tester,
    String label, {
    bool settle = true,
  }) async {
    final target = find.text(label);
    await tester.scrollUntilVisible(
      target,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(target);
    await tester.pump();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets('native capture readiness cannot override recipient denial', (
    tester,
  ) async {
    final fake = ApiFake()..contents = [contentJson()];
    final response = Completer<ApiReply>();
    fake.routes['/api/content/7/sessions'] = (_) => response.future;
    final account = fake.session();
    final biometric = BiometricFake();
    final protected = find.byKey(
      const ValueKey('protected-render-placeholder'),
      skipOffstage: false,
    );
    try {
      await account.login('synthetic-user', 'fixture-password');
      await account.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: ApiRecipientScreen(
            account: account,
            contentId: 7,
            biometricAuthenticator: biometric,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller = tester
          .widget<BiometricStatusPanel>(find.byType(BiometricStatusPanel))
          .controller;
      await tap(tester, 'Verify identity', settle: false);
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      bool requested() =>
          fake.calls.any((call) => call.uri.path == '/api/content/7/sessions');
      while ((!requested() ||
              controller.captureState != CaptureProtectionState.ready) &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(protected, findsNothing);
      }
      expect(requested(), isTrue);
      expect(controller.biometrics.approved, isTrue);
      expect(controller.captureState, CaptureProtectionState.ready);
      expect(protected, findsNothing);

      response.complete(const ApiReply(403, 'synthetic authorization denial'));
      await tester.pumpAndSettle();
      expect(controller.sessionEnded, isTrue);
      expect(controller.biometrics.approved, isFalse);
      final denied = find.text('Access denied');
      await tester.scrollUntilVisible(
        denied,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(denied, findsOneWidget);
      expect(protected, findsNothing);

      await controller.verifyIdentity();
      await controller.revalidate();
      await tester.pumpAndSettle();
      expect(biometric.starts, 1);
      expect(controller.sessionEnded, isTrue);
      expect(protected, findsNothing);
      final open = find.widgetWithText(ElevatedButton, 'Open Secure Content');
      await tester.scrollUntilVisible(
        open,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<ElevatedButton>(open).onPressed, isNull);
      expect(find.text('Open Demo Preview'), findsNothing);
      expect(find.text('Edit viewing area'), findsNothing);
      expect(find.text('Revoke access'), findsNothing);
      debugPrint(
        '[Week10Acceptance] native capture ready; fixture denial ended and kept viewer hidden',
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      account.dispose();
    }
  });

  testWidgets('owner status waits for fixture acknowledgements on device', (
    tester,
  ) async {
    const title = 'Owned synthetic item';
    final fake = ApiFake()..contents = [contentJson(mine: true, title: title)];
    final account = fake.session();
    const notice = ValueKey('api-write-confirmation');
    try {
      await account.login('synthetic-user', 'fixture-password');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: ApiDashboardScreen(account: account),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, title);
      expect(find.byType(ApiContentStatusScreen), findsOneWidget);
      expect(find.text('Recipient access: Active'), findsOneWidget);

      fake.routes['/api/content/7/policy'] = (call) {
        final status = call.json['Status'] as String;
        fake.contents = [contentJson(mine: true, title: title, policy: status)];
        return jsonReply({'status': status});
      };
      await tap(tester, 'Pause policy');
      expect(account.items.single.policyStatus, 'Paused');
      expect(
        find.text('Policy Paused confirmed by the server.'),
        findsOneWidget,
      );
      await tap(tester, 'Resume policy');
      expect(account.items.single.policyStatus, 'Active');

      fake.routes['/api/content/7/revoke'] = (_) =>
          const ApiReply(403, 'synthetic owner rejection');
      await tap(tester, 'Revoke access');
      await tap(tester, 'Confirm revocation');
      expect(find.byKey(const ValueKey('api-write-error')), findsOneWidget);
      expect(find.byKey(notice), findsNothing);
      expect(account.items.single.status, 'Active');

      final response = Completer<ApiReply>();
      fake.routes['/api/content/7/revoke'] = (_) => response.future;
      await tap(tester, 'Revoke access');
      await tap(tester, 'Confirm revocation', settle: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(account.pending(7), isTrue);
      expect(account.items.single.status, 'Active');
      expect(find.byKey(notice), findsNothing);
      fake.contents = [
        contentJson(mine: true, title: title, status: 'Revoked'),
      ];
      response.complete(jsonReply({'success': true}));
      await tester.pumpAndSettle();
      expect(find.text('Recipient access: Revoked'), findsOneWidget);
      expect(find.text('Revocation confirmed by the server.'), findsOneWidget);
      expect(find.text('Revoke access'), findsNothing);
      debugPrint(
        '[Week10Acceptance] owner pause/resume and rejected/pending/confirmed fixture revocation',
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      account.dispose();
    }
  });
}
