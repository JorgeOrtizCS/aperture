import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/services/biometric_verification.dart';
import 'package:aperture/widgets/biometric_status_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Real Android plugin and OS lifecycle only. An enrolled disposable emulator
// supplies fingerprint events and Home/foreground actions externally via ADB.
// No authenticator, policy, capture or camera service is replaced here.
class _LifecycleProbe with WidgetsBindingObserver {
  final events = <AppLifecycleState>[];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => events.add(state);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native repeated requests, background revocation and fresh sessions',
    (tester) async {
      final probe = _LifecycleProbe();
      WidgetsBinding.instance.addObserver(probe);
      addTearDown(() => WidgetsBinding.instance.removeObserver(probe));
      final protected = find.byKey(
        const ValueKey('protected-render-placeholder'),
        skipOffstage: false,
      );

      Future<void> waitFor(bool Function() predicate) async {
        final deadline = DateTime.now().add(const Duration(seconds: 55));
        while (!predicate() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 200));
          expect(protected, findsNothing);
        }
        expect(
          predicate(),
          isTrue,
          reason: 'Native action must actually finish',
        );
      }

      Future<ViewingStateController> mount() async {
        await tester.pumpWidget(
          MaterialApp(home: SecureViewerScreen(key: UniqueKey())),
        );
        await tester.pumpAndSettle();
        final controller = tester
            .widget<BiometricStatusPanel>(find.byType(BiometricStatusPanel))
            .controller;
        expect(controller.biometrics.state, BiometricState.required);
        expect(controller.biometrics.approved, isFalse);
        expect(protected, findsNothing);
        return controller;
      }

      Future<void> verifiedButDenied(ViewingStateController controller) async {
        await waitFor(() => controller.biometrics.approved);
        await tester.pumpAndSettle();
        expect(controller.state, isNot(ViewingState.allowed));
        await tester.scrollUntilVisible(
          find.text('Open Secure Content'),
          150,
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
        expect(protected, findsNothing);
      }

      final first = await mount();
      final verify = find.widgetWithText(ElevatedButton, 'Verify identity');
      await tester.ensureVisible(verify);
      // Dispatch three rapid UI requests before rebuilding the disabled button.
      await tester.tap(verify);
      await tester.tap(verify);
      await tester.tap(verify);
      await tester.pump();
      expect(first.biometrics.state, BiometricState.verifying);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Verification in progress'),
            )
            .onPressed,
        isNull,
      );
      debugPrint('[NativeSession] WAITING first');
      await verifiedButDenied(first);

      probe.events.clear();
      debugPrint('[NativeSession] BACKGROUND_NOW');
      await waitFor(
        () =>
            probe.events.contains(AppLifecycleState.paused) &&
            probe.events.last == AppLifecycleState.resumed,
      );
      expect(first.biometrics.approved, isFalse);
      expect(first.biometrics.state, BiometricState.required);
      debugPrint(
        '[NativeSession] LIFECYCLE ${probe.events.map((e) => e.name)}',
      );
      // Lifecycle delivery precedes the frame rebuilding the retry action.
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Verify identity'));
      await tester.tap(find.text('Verify identity'));
      await tester.pump();
      debugPrint('[NativeSession] WAITING resumed');
      await verifiedButDenied(first);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(first.biometrics.approved, isFalse);
      final second = await mount();
      expect(identical(first, second), isFalse);
      await tester.ensureVisible(find.text('Verify identity'));
      await tester.tap(find.text('Verify identity'));
      await tester.pump();
      debugPrint('[NativeSession] WAITING fresh');
      await verifiedButDenied(second);
      binding.reportData = {
        'native_android_sessions': {
          'rapid_verify_taps': 3,
          'successful_native_prompts': 3,
          'background_events': probe.events.map((e) => e.name).toList(),
          'approval_revoked_on_background_and_disposal': true,
          'fresh_controller_requires_verification': true,
          'backend_authorization': 'unverified',
          'open': 'disabled',
          'protected_subtree': 'absent',
          'native_camera_requested': false,
        },
      };
      debugPrint('[NativeSession] PASS all real native session checks');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    skip: defaultTargetPlatform != TargetPlatform.android,
  );
}
