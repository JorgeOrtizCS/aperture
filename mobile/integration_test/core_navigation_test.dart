import 'package:aperture/main.dart';
import 'package:aperture/screens/dashboard_screen.dart';
import 'package:aperture/screens/login_screen.dart';
import 'package:aperture/screens/notifications_screen.dart';
import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/screens/share_content_screen.dart';
import 'package:aperture/screens/security_settings_screen.dart';
import 'package:aperture/screens/viewing_requirements_screen.dart';
import 'package:aperture/screens/welcome_screen.dart';
import 'package:aperture/widgets/content_restrictions_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Real app/routes on device. No mock channels, successful policy provider, demo
// viewer, or camera-start action. Uses prototype sign-in and a local draft.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'core navigation and local sender policy flow without inference',
    (tester) async {
      final visited = <String>[];
      Future<void> page(Type type, String name) async {
        await tester.pumpAndSettle();
        expect(find.byType(type), findsOneWidget);
        expect(tester.takeException(), isNull);
        visited.add(name);
        debugPrint('[ApertureNavigation] PASS $name');
      }

      Future<void> tapText(String text) async {
        final target = find.text(text);
        if (target.evaluate().isEmpty) {
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            target,
            250,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
        await tester.pumpAndSettle();
        expect(
          target.hitTestable(),
          findsOneWidget,
          reason: '$text must be reachable',
        );
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> enter(String key, String value) async {
        final container = find.byKey(ValueKey(key));
        if (container.evaluate().isEmpty) {
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            container,
            200,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await Scrollable.ensureVisible(
          tester.element(container),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(of: container, matching: find.byType(TextField)),
          value,
        );
      }

      Future<void> back() async {
        Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(const ApertureApp());
      await page(WelcomeScreen, 'Welcome');
      await tapText('Get Started');
      await page(LoginScreen, 'Login');
      await tapText('Sign In');
      expect(
        find.text('Please enter your username and password.'),
        findsOneWidget,
      );
      await enter('login-username', 'navigation-demo');
      await enter('login-password', 'not-a-real-credential');
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tapText('Sign In');
      await page(DashboardScreen, 'Dashboard');
      await tapText('Security Settings');
      await page(SecuritySettingsScreen, 'Security Settings');
      final detailSwitch = find.byType(Switch).last;
      await tester.ensureVisible(detailSwitch);
      await tester.tap(detailSwitch);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(detailSwitch).value, isFalse);
      await back();
      await tapText('Security Settings');
      await tester.ensureVisible(find.byType(Switch).last);
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
      await tester.tap(find.byType(Switch).last);
      await back();
      await tester.tap(find.byIcon(Icons.notifications_outlined).first);
      await page(NotificationsScreen, 'Notifications');
      await back();
      await tapText('Share New Content');
      await page(ShareContentScreen, 'Share Content');
      await enter('share-title', 'Navigation sample');
      await enter('share-description', 'Local-only description');
      await enter('share-recipient', 'recipient-demo@example.invalid');
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tapText('Edit Policy');
      await page(ViewingRequirementsScreen, 'Policy editor');
      final download = find.byType(Switch).first;
      await tester.ensureVisible(download);
      await tester.tap(download);
      await tapText('Cancel');
      await tapText('Edit Policy');
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 views').last);
      await tester.pumpAndSettle();
      await tapText('Save');
      await tester.ensureVisible(find.byType(ContentRestrictionsSummary));
      expect(
        tester
            .widget<ContentRestrictionsSummary>(
              find.byType(ContentRestrictionsSummary),
            )
            .restrictions
            .viewLimit,
        5,
      );
      final share = find.widgetWithText(ElevatedButton, 'Share Securely');
      await tester.scrollUntilVisible(
        share,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<ElevatedButton>(share).onPressed, isNull);
      await back();
      await page(DashboardScreen, 'Dashboard return');
      await tapText('Project Document');
      await page(SecureViewerScreen, 'Recipient preflight');
      await tapText('Check Conditions');
      expect(
        find.text('Recipient authorization not confirmed'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Open Secure Content'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Open Secure Content'),
            )
            .onPressed,
        isNull,
      );
      debugPrint(
        '[ApertureNavigation] PASS real unverified policy remains locked',
      );
      expect(
        find.byKey(
          const ValueKey('protected-render-placeholder'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      await back();
      binding.reportData = {
        'navigation': {
          'visited': visited,
          'camera_inference_requested': false,
          'backend_authentication': 'prototype only',
          'upload': 'disabled',
        },
      };
    },
  );
}
