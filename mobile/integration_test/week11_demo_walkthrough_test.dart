import 'dart:convert';
import 'dart:io';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/main.dart';
import 'package:aperture/screens/api_content_screens.dart';
import 'package:aperture/screens/login_screen.dart';
import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/screens/share_content_screen.dart';
import 'package:aperture/screens/welcome_screen.dart';
import 'package:aperture/services/api_configuration.dart';
import 'package:aperture/services/api_session.dart';
import 'package:aperture/services/biometric_verification.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/share_file_selection.dart';
import 'package:aperture/widgets/biometric_status_panel.dart';
import 'package:aperture/widgets/content_restrictions_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../tool/week11_demo.dart';

void _mark(String step) => debugPrint('[Task113Demo] $step');

class _Walkthrough {
  _Walkthrough(this.tester);
  final WidgetTester tester;

  Future<void> until(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (!ready() && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 32));
      await Future<void>.delayed(const Duration(milliseconds: 32));
    }
    expect(ready(), isTrue);
  }

  Future<void> show(Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scroll = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(scroll).position;
      position.jumpTo(0);
      await tester.pumpAndSettle();
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(finder, 180, scrollable: scroll);
      }
    }
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> tap(Finder finder) async {
    await show(finder);
    expect(finder.hitTestable(), findsOneWidget);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> text(String value) => tap(find.text(value));

  Future<void> enter(String key, String value) async {
    final container = find.byKey(ValueKey(key));
    await show(container);
    await tester.enterText(
      find.descendant(of: container, matching: find.byType(TextField)),
      value,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  Future<void> login(String name, {String password = 'demo'}) async {
    await text('Get Started');
    expect(find.byType(LoginScreen), findsOneWidget);
    await enter('login-username', name);
    await enter('login-password', password);
    await text('Sign In');
  }

  Future<void> backFrom(Finder screen) async {
    await Navigator.of(tester.element(screen)).maybePop();
    await tester.pumpAndSettle();
  }

  Future<void> expectLocked() async {
    final open = find.widgetWithText(ElevatedButton, 'Open Secure Content');
    await show(open);
    expect(tester.widget<ElevatedButton>(open).onPressed, isNull);
    expect(
      find.byKey(
        const ValueKey('protected-render-placeholder'),
        skipOffstage: false,
      ),
      findsNothing,
    );
  }

  BiometricStatusPanel get biometrics =>
      tester.widget(find.byType(BiometricStatusPanel).first);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('standard navigation without an API environment stays at login', (
    tester,
  ) async {
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    final account = ApiSession(configuredApi(mode: 'live', baseUrl: ''));
    try {
      final flow = _Walkthrough(tester);
      await tester.pumpWidget(ApiApplication(session: account));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(
        find.text('Offline demo · Sample accounts and data'),
        findsNothing,
      );
      await flow.login('fixture-sender');
      await flow.until(
        () => find
            .textContaining('approved HTTPS API environment')
            .evaluate()
            .isNotEmpty,
      );
      expect(account.authenticated, isFalse);
      expect(find.byType(ApiDashboardScreen), findsNothing);
      expect(find.text('Session demo'), findsNothing);
      await binding.takeScreenshot('01-standard-login');
      _mark('STANDARD_LOGIN_LOCKED');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      account.dispose();
    }
  });

  testWidgets('offline walkthrough exercises the app with labeled fixtures', (
    tester,
  ) async {
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    final flow = _Walkthrough(tester);
    final lifecycle = AppLifecycleListener(onPause: () => _mark('PAUSED'));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    if (Platform.isIOS) {
      // Drive the real Dart picker adapter and decoder with the same PNG as
      // the Android file. The simulator's system Files UI is a manual step.
      const encoded = String.fromEnvironment('TASK113_IOS_PNG_BASE64');
      expect(encoded, isNotEmpty);
      messenger.setMockMethodCallHandler(NativeShareFilePicker.channel, (
        call,
      ) async {
        switch (call.method) {
          case 'pick':
            return true;
          case 'read':
            return {
              'name': 'Aperture-Demo.png',
              'mimeType': 'image/png',
              'bytes': base64Decode(encoded),
            };
          case 'discard':
            return null;
          default:
            throw MissingPluginException();
        }
      });
    }
    try {
      await tester.pumpWidget(const Week11DemoApp());
      await tester.pumpAndSettle();
      expect(
        find.text('Offline demo · Sample accounts and data'),
        findsOneWidget,
      );
      await flow.login(demoSender);
      await flow.until(() => find.text(demoOwnerItem).evaluate().isNotEmpty);
      expect(find.text('Signed in as $demoSender'), findsOneWidget);
      _mark('SENDER_DASHBOARD');

      await flow.text('Prepare PNG');
      final select = find.byKey(const ValueKey('share-select-png'));
      await flow.show(select);
      _mark(
        Platform.isAndroid ? 'ANDROID_FILE_PICKER' : 'IOS_PNG_ADAPTER_FIXTURE',
      );
      await tester.tap(select);
      final preview = find.byKey(const ValueKey('share-png-preview'));
      await flow.until(() => preview.evaluate().isNotEmpty);
      await flow.show(preview);
      expect(find.text('Local preview · Not shared'), findsOneWidget);
      await binding.takeScreenshot('02-local-png-preview');
      _mark('LOCAL_PNG_PREVIEW');

      await flow.text('Edit Policy');
      final limit = find.byType(DropdownButtonFormField<String>);
      await flow.tap(limit);
      await flow.text('5 views');
      await flow.text('Save');
      final summary = find.byType(ContentRestrictionsSummary);
      await flow.show(summary);
      expect(
        tester
            .widget<ContentRestrictionsSummary>(summary)
            .restrictions
            .viewLimit,
        5,
      );
      final upload = find.widgetWithText(ElevatedButton, 'Share Securely');
      await flow.show(upload);
      expect(tester.widget<ElevatedButton>(upload).onPressed, isNull);
      await binding.takeScreenshot('03-sender-policy-upload-disabled');
      await flow.backFrom(find.byType(ShareContentScreen));
      expect(preview, findsNothing);

      await flow.text(demoOwnerItem);
      await flow.text('Pause policy');
      await flow.until(() => find.text('Policy: Paused').evaluate().isNotEmpty);
      await binding.takeScreenshot('04-owner-pause');
      await flow.text('Resume policy');
      await flow.until(() => find.text('Policy: Active').evaluate().isNotEmpty);
      await flow.text('Revoke access');
      await flow.text('Confirm revocation');
      await flow.until(
        () => find.text('Sample revocation applied.').evaluate().isNotEmpty,
      );
      expect(find.text('Recipient access: Revoked'), findsOneWidget);
      _mark('OWNER_PAUSE_RESUME_REVOKE');
      await flow.backFrom(find.byType(ApiContentStatusScreen));
      await flow.text('Sign out');
      expect(find.byType(WelcomeScreen), findsOneWidget);
      await flow.login(demoRecipient);
      await flow.until(() => find.text(demoLocationItem).evaluate().isNotEmpty);
      expect(find.text('Signed in as $demoRecipient'), findsOneWidget);
      expect(find.text('Shared With Me'), findsOneWidget);
      await binding.takeScreenshot('05-recipient-list');
      _mark('RECIPIENT_LIST');

      await flow.text(demoLocationItem);
      await flow.until(
        () => find.byType(SecureViewerScreen).evaluate().isNotEmpty,
      );
      await flow.expectLocked();
      await flow.show(find.text('Verify identity'));
      final viewing = flow.biometrics.controller;
      _mark('BIOMETRIC_READY');
      await tester.tap(find.text('Verify identity'));
      await flow.until(
        () =>
            !viewing.biometrics.busy &&
            viewing.biometrics.state != BiometricState.required,
      );
      _mark('BIOMETRIC_RESULT ${viewing.biometrics.state.name}');
      await flow.expectLocked();

      if (Platform.isAndroid) {
        final allow = find.text('Allow location for viewing');
        await flow.show(allow);
        _mark('ANDROID_LOCATION_PROMPT');
        await tester.tap(allow);
      } else {
        _mark('IOS_LOCATION_SETTINGS');
      }
      final denied = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data?.contains('Location permission denied.') == true ||
                widget.data?.contains(
                      'Location permission is blocked in system settings.',
                    ) ==
                    true),
      );
      await flow.until(() => denied.evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('06-recipient-preflight-denial');
      _mark('RECIPIENT_LOCATION_DENIED');
      await flow.backFrom(find.byType(ApiRecipientScreen));

      await flow.tap(find.byTooltip('Notifications'));
      expect(find.text('Access revoked'), findsOneWidget);
      expect(find.textContaining('Sample content listing'), findsOneWidget);
      expect(find.textContaining('Device status'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              const {
                'Location permission blocked',
                'Location permission denied',
              }.contains(widget.data),
        ),
        findsOneWidget,
      );
      expect(find.text(demoOwnerItem), findsNothing);
      expect(find.byType(RawImage), findsNothing);
      await binding.takeScreenshot('07-notifications');
      await flow.backFrom(find.text('Notifications'));
      _mark('SAMPLE_NOTICES_PRIVATE');

      await flow.text('Session demo');
      await flow.text('Check Conditions');
      await flow.show(find.byType(BiometricStatusPanel));
      final simulated = flow.biometrics.controller;
      await flow.until(
        () => simulated.captureState == CaptureProtectionState.ready,
      );
      expect(simulated.state, isNot(ViewingState.allowed));
      _mark('CAPTURE_READY_LOCKED');
      // Allow host tools to record the Android window flag before release.
      await Future<void>.delayed(const Duration(seconds: 3));
      await flow.text('Simulate session end');
      expect(simulated.sessionEnded, isTrue);
      expect(simulated.canRecheck, isFalse);
      expect(simulated.biometrics.approved, isFalse);
      await flow.show(find.text('Demo security violation').first);
      await binding.takeScreenshot('08-simulated-session-ended');
      await flow.backFrom(find.byType(SecureViewerScreen));
      _mark('SIMULATED_END_AND_BACK');
      await flow.text('Sign out');
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(
        find.byType(ApiDashboardScreen, skipOffstage: false),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      _mark('LOGOUT_COMPLETE');
    } finally {
      lifecycle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      if (Platform.isIOS) {
        messenger.setMockMethodCallHandler(NativeShareFilePicker.channel, null);
      }
    }
  });
}
