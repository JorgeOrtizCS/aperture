import 'dart:async';

import 'package:aperture/screens/api_content_screens.dart';
import 'package:aperture/screens/content_status_screen.dart';
import 'package:aperture/screens/dashboard_screen.dart';
import 'package:aperture/screens/login_screen.dart';
import 'package:aperture/screens/notifications_screen.dart';
import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/screens/share_content_screen.dart';
import 'package:aperture/screens/security_settings_screen.dart';
import 'package:aperture/widgets/security_notice.dart';
import 'package:aperture/screens/viewing_requirements_screen.dart';
import 'package:aperture/screens/welcome_screen.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:aperture/widgets/api_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';
import 'support/biometric_fake.dart';
import 'support/viewing_test_fakes.dart';

void main() {
  const sizes = [
    Size(320, 640),
    Size(360, 780),
    Size(390, 844),
    Size(430, 932),
    Size(768, 1024),
    Size(1024, 1366),
  ];
  for (final portrait in sizes) {
    for (final landscape in [false, true]) {
      final size = landscape ? Size(portrait.height, portrait.width) : portrait;
      for (final scale in [1.0, 2.0, 3.0]) {
        testWidgets(
          '${size.width}x${size.height} text ${scale}x all core screens',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final screens = <Widget>[
              const WelcomeScreen(),
              const LoginScreen(),
              const DashboardScreen(),
              const ShareContentScreen(),
              const ContentStatusScreen(),
              const SecuritySettingsScreen(),
              const Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: SecurityNotice(
                      title: "Camera protection unavailable",
                      message: "Content stays hidden. Allow Camera in system settings, then retry. Retrying never overrides the sender’s required checks.",
                      details: "Camera status: permission_denied",
                    ),
                  ),
                ),
              ),
              const NotificationsScreen(),
              const ViewingRequirementsScreen(
                initialRestrictions: ContentRestrictions.demoDefaults,
                senderDraft: true,
              ),
              const SecureViewerScreen(),
            ];
            for (final screen in screens) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: AppTheme.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: screen,
                ),
              );
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '${screen.runtimeType} at $size / $scale',
              );
              // Lay out every lazy-list child, including bottom actions.
              final scrolls = tester
                  .stateList<ScrollableState>(find.byType(Scrollable))
                  .toList();
              for (final scroll in scrolls) {
                if (scroll.position.axis != Axis.vertical) continue;
                for (var step = 0; step < 80; step++) {
                  final position = scroll.position;
                  if (position.pixels >= position.maxScrollExtent) break;
                  position.jumpTo(
                    (position.pixels + size.height / 2).clamp(
                      0,
                      position.maxScrollExtent,
                    ),
                  );
                  await tester.pumpAndSettle();
                  final error = tester.takeException();
                  if (error != null) debugPrint('$error');
                  expect(
                    error,
                    isNull,
                    reason: '${screen.runtimeType} scrolling at $size / $scale',
                  );
                }
              }
              await tester.pumpWidget(const SizedBox());
              await tester.pumpAndSettle();
            }
          },
        );
      }
    }
  }
  for (final portrait in sizes) {
    for (final landscape in [false, true]) {
      final size = landscape ? Size(portrait.height, portrait.width) : portrait;
      testWidgets('$size keyboard and long editor input at 2x text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = FakeViewPadding(bottom: size.height * 0.45);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        for (final screen in <Widget>[
          const LoginScreen(),
          const ShareContentScreen(),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: screen,
            ),
          );
          await tester.pumpAndSettle();
          final container = find.byKey(
            ValueKey(screen is LoginScreen ? 'login-username' : 'share-title'),
          );
          await tester.scrollUntilVisible(
            container,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          final field = find.descendant(
            of: container,
            matching: find.byType(TextField),
          );
          expect(tester.widget<TextField>(field).readOnly, isFalse);
          await tester.enterText(
            field,
            'Long local-only input for responsive keyboard testing',
          );
          await tester.pumpAndSettle();
          final action = find.text(
            screen is LoginScreen ? 'Sign In' : 'Share Securely',
          );
          await tester.scrollUntilVisible(
            action,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await Scrollable.ensureVisible(
            tester.element(action),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          expect(action.hitTestable(), findsOneWidget);
          if (screen is ShareContentScreen) {
            expect(
              tester
                  .widget<ElevatedButton>(
                    find.widgetWithText(ElevatedButton, 'Share Securely'),
                  )
                  .onPressed,
              isNull,
            );
            expect(find.text('Cancel submission'), findsNothing);
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.runtimeType} with keyboard at $size',
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      });
    }
  }
  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    testWidgets('Account recovery notices stay readable at $size and 3x text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = ApiFake()..contents = [contentJson()];
      final account = fake.session();
      await account.login('synthetic-user', 'fixture-only');

      Widget screen(Widget home) => ApiScope(
        session: account,
        child: MaterialApp(
          key: ValueKey(home.runtimeType),
          theme: AppTheme.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          home: home,
        ),
      );

      try {
        await tester.pumpWidget(screen(ApiDashboardScreen(account: account)));
        await tester.pumpAndSettle();
        fake.routes['/api/content'] = (_) => const ApiReply(500, 'offline');
        final refresh = find.text('Refresh content');
        await tester.scrollUntilVisible(refresh, size.height / 3);
        await Scrollable.ensureVisible(tester.element(refresh), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        final stale = find.text(
          'Refresh failed. Showing the last known listing.',
        );
        expect(stale, findsOneWidget);
        expect(tester.takeException(), isNull);

        fake.routes['/api/auth/logout'] = (_) => const ApiReply(500, 'offline');
        final signOut = find.byTooltip('Sign out');
        expect(signOut.hitTestable(), findsOneWidget);
        await tester.tap(signOut);
        await tester.pumpAndSettle();
        await tester.pumpWidget(screen(const WelcomeScreen()));
        await tester.pumpAndSettle();
        expect(
          find
              .textContaining('Server sign-out could not be confirmed')
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        account.dispose();
      }
    });

    testWidgets('Locked recipient access scrolls at $size and 3x text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = ApiFake()
        ..contents = [
          contentJson(title: 'A longer incoming shared document title'),
        ];
      final native = NativeCaptureFake()..install();
      final account = fake.session();
      await account.login('synthetic-user', 'fixture-only');
      await account.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          home: ApiRecipientScreen(
            account: account,
            contentId: 7,
            biometricAuthenticator: BiometricFake(),
            cameraDetection: native.camera.service,
            captureProtection: ScreenCaptureProtection.forTesting(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Protected display unavailable',
        'Server authorization',
        'Register this device',
        'Open security checks',
        'Go back',
      ]) {
        final target = find.text(label);
        await tester.scrollUntilVisible(target, size.height / 3);
        await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(
        fake.calls.where((call) => call.uri.path.endsWith('/sessions')),
        isEmpty,
      );
      final controller = tester
          .widget<SecureViewerScreen>(find.byType(SecureViewerScreen))
          .viewingController!;
      unawaited(controller.verifyIdentity());
      await flushViewing(tester);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      final open = find.text('Open security checks');
      await tester.scrollUntilVisible(open, size.height / 3);
      await Scrollable.ensureVisible(tester.element(open), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(open);
      await flushViewing(tester);
      await tester.pumpAndSettle();
      expect(find.text('Protected display unavailable'), findsOneWidget);
      final close = find.text('Close viewer');
      await tester.scrollUntilVisible(close, size.height / 3);
      await Scrollable.ensureVisible(tester.element(close), alignment: 0.5);
      await tester.pumpAndSettle();
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(close);
      await flushViewing(tester);
      await tester.pumpAndSettle();
      expect(native.camera.stops, 1);
      await tester.pumpWidget(const SizedBox());
      account.dispose();
    });

    testWidgets('Sender policy review is usable at $size and 3x text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          home: const ShareContentScreen(),
        ),
      );
      await tester.pumpAndSettle();

      Future<Finder> reveal(String label) async {
        final target = find.text(label);
        await tester.scrollUntilVisible(
          target,
          size.height / 3,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
        await tester.pumpAndSettle();
        return target;
      }

      final edit = await reveal('Edit Policy');
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(
        await reveal('Download and resharing permissions are unavailable.'),
        findsOneWidget,
      );
      final save = await reveal('Save');
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final share = await reveal('Share Securely');
      expect(share.hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Share Securely'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
