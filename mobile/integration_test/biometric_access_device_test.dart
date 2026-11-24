import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/widgets/biometric_status_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Real local_auth plugin + platform dialogs, no fake policy/authenticator or
// native channels. Simulator matches must be supplied through OS test controls.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const mode = String.fromEnvironment(
    'APERTURE_BIOMETRIC_ACCEPTANCE',
    defaultValue: 'unenrolled',
  );
  testWidgets('native biometric secure preflight: $mode', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SecureViewerScreen()));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('protected-render-placeholder'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    await tester.ensureVisible(find.text('Verify identity'));
    await tester.tap(find.text('Verify identity'));
    await tester.pump();
    debugPrint(
      '[BiometricDevice] WAITING mode=$mode platform=${Theme.of(tester.element(find.byType(Scaffold))).platform.name}',
    );
    final deadline = DateTime.now().add(const Duration(seconds: 50));
    const terminals = [
      'Verification successful',
      'Verification cancelled',
      'Verification failed',
      'Biometrics unavailable',
      'Biometrics not enrolled',
      'Biometric lockout',
      'Verification required',
    ];
    String? outcome;
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(
          const ValueKey('protected-render-placeholder'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      if (scroll.position.pixels != 0) {
        scroll.position.jumpTo(0);
        await tester.pump();
      }
      for (final text in terminals) {
        if (find
            .descendant(
              of: find.byType(BiometricStatusPanel),
              matching: find.text(text),
            )
            .evaluate()
            .isNotEmpty) {
          outcome = text;
          break;
        }
      }
      if (outcome != null) break;
    }
    debugPrint('[BiometricDevice] RESULT mode=$mode outcome=$outcome');
    switch (mode) {
      case 'success':
        expect(outcome, 'Verification successful');
      case 'cancel':
        expect(outcome, anyOf('Verification cancelled', 'Verification failed'));
      case 'background':
        expect(
          outcome,
          anyOf('Verification required', 'Verification cancelled'),
        );
      case 'unenrolled':
        expect(
          outcome,
          anyOf('Biometrics unavailable', 'Biometrics not enrolled'),
        );
      default:
        fail('Unknown test mode $mode');
    }
    if (mode == 'success') {
      final actualController = tester
          .widget<BiometricStatusPanel>(find.byType(BiometricStatusPanel))
          .controller;
      expect(actualController.biometrics.approved, isTrue);
      expect(actualController.state.name, isNot('allowed'));
      debugPrint(
        '[BiometricDevice] backend remains unverified state=${actualController.state.name}',
      );
    }
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
    expect(
      find.byKey(
        const ValueKey('protected-render-placeholder'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    binding.reportData = {
      'biometric_device': {
        'mode': mode,
        'outcome': outcome,
        'backend_authorization': 'unverified',
        'protected_subtree': 'absent',
        'native_camera_requested': false,
      },
    };
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
