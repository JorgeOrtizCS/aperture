import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/screens/secure_content_viewer_screen.dart';
import 'package:aperture/screens/security_settings_screen.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/security_settings.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:aperture/widgets/security_notice.dart';
import 'package:aperture/widgets/viewing_status_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/viewing_test_fakes.dart';

void main() {
  testWidgets(
    'settings expose only two presentation switches with accessible labels',
    (tester) async {
      final settings = SecuritySettings();
      addTearDown(settings.dispose);
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(home: SecuritySettingsScreen(settings: settings)),
      );
      expect(find.byType(Switch), findsNWidgets(2));
      expect(find.bySemanticsLabel('Warning haptics'), findsOneWidget);
      expect(find.bySemanticsLabel('Show warning details'), findsOneWidget);
      await tester.tap(find.byType(Switch).first);
      expect(settings.warningHaptics, isTrue);
      await tester.ensureVisible(find.byType(Switch).last);
      await tester.tap(find.byType(Switch).last);
      expect(settings.showWarningDetails, isFalse);
      final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
      list.position.jumpTo(list.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Biometric identity verification'), findsOneWidget);
      expect(
        find.textContaining('Biometric-only verification is required'),
        findsOneWidget,
      );
      expect(
        find.byType(Switch),
        findsNothing,
      ); // No mandatory-protection controls.
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets(
    'details preference never removes warning reason or recovery instructions',
    (tester) async {
      final settings = SecuritySettings();
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityNotice(
              title: 'Camera protection unavailable',
              message: 'Content stays hidden. Retry camera protection.',
              details: 'Camera status: permission_denied',
              settings: settings,
            ),
          ),
        ),
      );
      expect(find.textContaining('permission_denied'), findsOneWidget);
      settings.setShowWarningDetails(false);
      await tester.pump();
      expect(find.textContaining('permission_denied'), findsNothing);
      expect(find.text('Camera protection unavailable'), findsOneWidget);
      expect(
        find.text('Content stays hidden. Retry camera protection.'),
        findsOneWidget,
      );
      final notices = tester.widgetList<Semantics>(find.byType(Semantics));
      expect(notices.any((s) => s.properties.liveRegion == true), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'haptics are opt-in, emitted on new warnings, and do not repeat on preference rebuilds',
    (tester) async {
      final settings = SecuritySettings();
      addTearDown(settings.dispose);
      final calls = <MethodCall>[];
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      Future<void> notice(String title) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SecurityNotice(
                title: title,
                message: 'Content stays hidden.',
                settings: settings,
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await notice('Camera unavailable');
      expect(calls.where((c) => c.method == 'HapticFeedback.vibrate'), isEmpty);
      settings.setWarningHaptics(true);
      await tester.pump();
      await notice('Screen capture detected');
      expect(
        calls.where((c) => c.method == 'HapticFeedback.vibrate'),
        hasLength(1),
      );
      settings.setShowWarningDetails(false);
      await tester.pump();
      expect(
        calls.where((c) => c.method == 'HapticFeedback.vibrate'),
        hasLength(1),
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            throw PlatformException(code: 'unsupported');
          }
          return null;
        },
      );
      await notice('Viewing ended');
      expect(find.text('Viewing ended'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'camera warning details can be hidden without restoring content',
    (tester) async {
      final native = NativeCaptureFake();
      native.camera.startError = PlatformException(code: 'permission_denied');
      native.install();
      final conditions = ConditionsFake();
      addTearDown(conditions.dispose);
      final settings = SecuritySettings.instance;
      addTearDown(() {
        settings.setShowWarningDetails(true);
        settings.setWarningHaptics(false);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SecureContentViewerScreen(
            contentTitle: 'Test placeholder',
            restrictions: ContentRestrictions.demoDefaults,
            conditionProvider: conditions,
            captureProtection: ScreenCaptureProtection.forTesting(),
            cameraDetection: native.camera.service,
          ),
        ),
      );
      await flushViewing(tester);
      expect(find.text('Camera permission denied'), findsOneWidget);
      expect(
        find.textContaining('Camera status: permission_denied'),
        findsOneWidget,
      );
      settings.setShowWarningDetails(false);
      await tester.pump();
      expect(
        find.textContaining('Camera status: permission_denied'),
        findsNothing,
      );
      expect(find.text('Camera permission denied'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('protected-render-placeholder')),
        findsNothing,
      );
      expect(find.text('Checks passed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await flushViewing(tester);
    },
  );

  for (final kind in [
    ViewingIssueKind.phoneDetected,
    ViewingIssueKind.screenshot,
  ]) {
    testWidgets(
      'presentation preferences cannot clear permanent ${kind.name} lockout',
      (tester) async {
        NativeCaptureFake().install();
        final conditions = ConditionsFake();
        final controller = ViewingStateController(
          restrictions: ContentRestrictions.demoDefaults,
          conditions: conditions,
          protection: ScreenCaptureProtection.forTesting(),
        );
        controller.revalidate();
        await flushViewing(tester);
        controller.endForSecurityViolation(reason: kind);
        final settings = SecuritySettings.instance;
        settings.setWarningHaptics(true);
        settings.setShowWarningDetails(false);
        await controller.revalidate();
        expect(controller.sessionEnded, isTrue);
        expect(controller.state, ViewingState.accessDenied);
        expect(controller.canRecheck, isFalse);
        settings.setWarningHaptics(false);
        settings.setShowWarningDetails(true);
        controller.dispose();
        await flushViewing(tester);
        conditions.dispose();
      },
    );
  }

  test('biometrics never replace unverified recipient authorization', () {
    final message = viewingIssueMessage(
      const ViewingIssue(
        ViewingIssueKind.unknownCondition,
        condition: 'authorization',
      ),
    );
    expect(message.message, contains('Authentication required'));
    expect(
      message.message,
      contains('Device biometrics alone cannot grant recipient access'),
    );
  });
}
