import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Real simulator routes and native capture/biometric bridges. No mocked
// channels, successful policy provider or test authenticator. The second scene
// deliberately uses the app's labeled debug simulation, not a real violation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unverified access and explicit demo termination stay hidden', (
    tester,
  ) async {
    final protected = find.byKey(
      const ValueKey('protected-render-placeholder'),
      skipOffstage: false,
    );

    Future<void> tapLabel(String label) async {
      await tester.scrollUntilVisible(
        find.text(label),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> evidence(String scene) async {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      debugPrint('[Task10.1Evidence] $scene-ready');
      const hold = int.fromEnvironment('APERTURE_EVIDENCE_HOLD_SECONDS');
      if (hold > 0) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: hold)),
        );
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: const SecureViewerScreen(
          key: ValueKey('unverified-native-flow'),
          contentTitle: 'Unverified access — no backend connected',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapLabel('Check Conditions');
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (find.text('Checking conditions').evaluate().isNotEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Checking conditions'), findsNothing);
    expect(protected, findsNothing);
    await tester.scrollUntilVisible(
      find.text('Open Secure Content'),
      180,
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
    await evidence('unverified-warning');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: const SecureViewerScreen(
          key: ValueKey('explicit-demo-flow'),
          contentTitle: 'Demo simulation only — no real detection',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapLabel('Open Demo Preview');
    // No identity success is injected. On an unenrolled simulator the native
    // plugin denies verification; the explicit demo simulation is still usable.
    expect(protected, findsNothing);
    await tapLabel('Demo: Simulate Security Violation');
    await tester.pumpAndSettle();
    // Returning from the demo retains preflight's scroll position. Bring its
    // status panel back into the lazy list before inspecting the ended state.
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Viewing ended'), findsOneWidget);
    expect(find.text('Demo security violation'), findsOneWidget);
    expect(protected, findsNothing);
    expect(find.text('Open Demo Preview'), findsNothing);
    await evidence('demo-terminated');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
