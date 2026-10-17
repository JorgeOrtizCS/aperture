import 'dart:async';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/screens/secure_content_viewer_screen.dart';
import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/viewing_test_fakes.dart';

final protectedContent = find.byKey(
  const ValueKey('protected-render-placeholder'),
  skipOffstage: false,
);

Future<void> tapLabel(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.scrollUntilVisible(
    target,
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await flushViewing(tester);
}

bool actionEnabled(WidgetTester tester, String label) =>
    tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, label))
        .onPressed !=
    null;

void main() {
  late NativeCaptureFake native;
  late ConditionsFake conditions;
  late ScreenCaptureProtection protection;

  setUp(() {
    native = NativeCaptureFake();
    conditions = ConditionsFake();
    protection = ScreenCaptureProtection.forTesting();
  });
  tearDown(() => conditions.dispose());

  Future<void> showViewer(
    WidgetTester tester, {
    bool preflight = false,
    double scale = 1,
    bool demo = false,
  }) async {
    native.install();
    final screen = preflight
        ? SecureViewerScreen(
            restrictions: ContentRestrictions.demoDefaults,
            conditionProvider: conditions,
            captureProtection: protection,
          )
        : demo
        ? SecureContentViewerScreen.demo(
            contentTitle: 'Demo',
            restrictions: ContentRestrictions.demoDefaults,
            captureProtection: protection,
          )
        : SecureContentViewerScreen(
            contentTitle: 'Document',
            restrictions: ContentRestrictions.demoDefaults,
            conditionProvider: conditions,
            captureProtection: protection,
          );
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
    await flushViewing(tester);
  }

  testWidgets(
    'checking explains why content is hidden and offers no premature retry',
    (tester) async {
      conditions.checking = Completer<Map<String, ViewingConditionResult>>();
      await showViewer(tester);
      expect(find.text('Checking conditions'), findsOneWidget);
      expect(
        find.textContaining('Security checks in progress.'),
        findsOneWidget,
      );
      expect(find.text('Recheck Conditions'), findsNothing);
      expect(protectedContent, findsNothing);
      conditions.checking!.complete(conditions.snapshot);
      await flushViewing(tester);
      expect(find.text('Checks passed'), findsOneWidget);
      expect(protectedContent, findsOneWidget);
    },
  );

  testWidgets(
    'preflight starts unverified and only enables Open after real evaluation',
    (tester) async {
      await showViewer(tester, preflight: true);
      expect(find.text('Check before viewing'), findsOneWidget);
      expect(actionEnabled(tester, 'Open Secure Content'), isFalse);
      expect(find.text('Met'), findsNothing);
      expect(native.enables, 0);
      await tapLabel(tester, 'Check Conditions');
      expect(find.text('Ready to view'), findsOneWidget);
      expect(actionEnabled(tester, 'Open Secure Content'), isTrue);
      expect(native.enables, 1);
    },
  );

  testWidgets('recording or mirroring gives the correct recoverable warning', (
    tester,
  ) async {
    native.capture = true;
    await showViewer(tester);
    expect(find.text('Content Hidden'), findsOneWidget);
    expect(find.text('Screen capture detected'), findsOneWidget);
    expect(
      find.textContaining('Screen recording or mirroring is active.'),
      findsOneWidget,
    );
    expect(find.text('Recheck Conditions'), findsOneWidget);
    expect(protectedContent, findsNothing);
  });

  testWidgets('simultaneous warnings retain each true failure reason', (
    tester,
  ) async {
    await showViewer(tester);
    conditions.update({
      'presence': ViewingConditionResult.failed,
      'location': ViewingConditionResult.failed,
    });
    native.setCapture(true);
    await flushViewing(tester);
    expect(find.text('Viewer presence failed'), findsOneWidget);
    expect(find.text('Approved location failed'), findsOneWidget);
    expect(find.text('Screen capture detected'), findsOneWidget);
    conditions.update({'presence': ViewingConditionResult.satisfied});
    await tester.pump();
    expect(protectedContent, findsNothing);
    expect(find.text('Viewer presence failed'), findsOneWidget);
    expect(find.text('Approved location failed'), findsOneWidget);
    await tapLabel(tester, 'Recheck Conditions');
    expect(protectedContent, findsNothing);
    expect(find.text('Viewer presence failed'), findsNothing);
    expect(find.text('Approved location failed'), findsOneWidget);
  });

  for (final denial in [
    (
      ViewingCondition.authorization,
      ViewingConditionResult.denied,
      'Authorization denied',
    ),
    (
      ViewingCondition.expiration,
      ViewingConditionResult.failed,
      'Content expired',
    ),
    (
      ViewingCondition.viewLimit,
      ViewingConditionResult.failed,
      'View limit reached',
    ),
    ('presence', ViewingConditionResult.denied, 'Viewer presence denied'),
  ]) {
    testWidgets('${denial.$3} has no retry or demo bypass', (tester) async {
      conditions.snapshot[denial.$1] = denial.$2;
      await showViewer(tester, preflight: true);
      await tapLabel(tester, 'Check Conditions');
      expect(find.text('Access denied'), findsOneWidget);
      expect(find.text(denial.$3), findsOneWidget);
      expect(find.text('Recheck Conditions'), findsNothing);
      expect(find.text('Open Demo Preview'), findsNothing);
      expect(find.text('Simulate Conditions Restored'), findsNothing);
      expect(actionEnabled(tester, 'Open Secure Content'), isFalse);
      conditions.update({denial.$1: ViewingConditionResult.satisfied});
      await flushViewing(tester);
      expect(find.text('Access denied'), findsOneWidget);
      expect(actionEnabled(tester, 'Open Secure Content'), isFalse);
      expect(protectedContent, findsNothing);
    });
  }

  testWidgets(
    'Recheck evaluates again and cannot force a failed condition to pass',
    (tester) async {
      conditions.snapshot['presence'] = ViewingConditionResult.failed;
      await showViewer(tester);
      final firstChecks = conditions.checks;
      conditions.checking = Completer<Map<String, ViewingConditionResult>>();
      await tapLabel(tester, 'Recheck Conditions');
      expect(conditions.checks, firstChecks + 1);
      expect(
        find.textContaining('Security recheck in progress.'),
        findsOneWidget,
      );
      expect(find.text('Recheck Conditions'), findsNothing);
      expect(protectedContent, findsNothing);
      conditions.checking!.complete(conditions.snapshot);
      await flushViewing(tester);
      expect(find.text('Viewer presence failed'), findsOneWidget);
      expect(protectedContent, findsNothing);
    },
  );

  testWidgets(
    'unknown authorization is never presented as expired, denied or passed',
    (tester) async {
      conditions.snapshot.remove(ViewingCondition.authorization);
      await showViewer(tester, preflight: true);
      await tapLabel(tester, 'Check Conditions');
      expect(
        find.text('Recipient authorization not confirmed'),
        findsOneWidget,
      );
      expect(find.text('Authorization denied'), findsNothing);
      expect(find.text('Content expired'), findsNothing);
      expect(actionEnabled(tester, 'Open Secure Content'), isFalse);
      expect(protectedContent, findsNothing);
    },
  );

  testWidgets(
    'native monitoring error has no ineffective retry or Open action',
    (tester) async {
      await showViewer(tester, preflight: true);
      await tapLabel(tester, 'Check Conditions');
      native.events!.error(code: 'monitor_failed');
      await flushViewing(tester);
      expect(find.text('Protection unavailable'), findsOneWidget);
      expect(find.text('Capture protection unavailable'), findsOneWidget);
      expect(find.text('Recheck Conditions'), findsNothing);
      expect(actionEnabled(tester, 'Open Secure Content'), isFalse);
      expect(protectedContent, findsNothing);
    },
  );

  testWidgets(
    'recoverable initialization failure can recheck without force-unlocking',
    (tester) async {
      native.enableError = PlatformException(code: 'temporary_failure');
      await showViewer(tester);
      expect(find.text('Protection unavailable'), findsOneWidget);
      expect(find.text('Recheck Conditions'), findsOneWidget);
      native.enableError = null;
      conditions.checking = Completer<Map<String, ViewingConditionResult>>();
      await tapLabel(tester, 'Recheck Conditions');
      expect(native.enables, 2);
      expect(protectedContent, findsNothing);
      conditions.checking!.complete(conditions.snapshot);
      await flushViewing(tester);
      expect(protectedContent, findsOneWidget);
    },
  );

  testWidgets(
    'shared controller preserves screenshot reason through one exit and notice',
    (tester) async {
      await showViewer(tester, preflight: true);
      await tapLabel(tester, 'Check Conditions');
      await tapLabel(tester, 'Open Secure Content');
      expect(protectedContent, findsOneWidget);
      native.events!.success({'type': 'screenshot'});
      native.events!.success({'type': 'screenshot'});
      await tester.pump();
      expect(protectedContent, findsNothing);
      await tester.pumpAndSettle();
      await flushViewing(tester);
      expect(find.byType(SecureContentViewerScreen), findsNothing);
      expect(find.text('Viewing ended'), findsOneWidget);
      expect(find.text('Screenshot detected'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text('Screenshot detected. This viewing session has ended.'),
        findsOneWidget,
      );
      expect(find.text('Approved location failed'), findsNothing);
      expect(find.text('Demo security violation'), findsNothing);
      expect(find.text('Recheck Conditions'), findsNothing);
      expect(find.text('Open Demo Preview'), findsNothing);
      expect(actionEnabled(tester, 'Open Secure Content'), isFalse);
      native.events!.success({'type': 'screenshot'});
      await flushViewing(tester);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(SecureViewerScreen), findsOneWidget);
    },
  );

  testWidgets(
    'shared preflight follows live denial and capture states after content closes',
    (tester) async {
      await showViewer(tester, preflight: true);
      await tapLabel(tester, 'Check Conditions');
      await tapLabel(tester, 'Open Secure Content');
      native.setCapture(true);
      await flushViewing(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Screen capture detected'), findsOneWidget);
      expect(actionEnabled(tester, 'Open Secure Content'), isFalse);
      native.setCapture(false);
      await flushViewing(tester);
      expect(actionEnabled(tester, 'Open Secure Content'), isFalse);
      await tapLabel(tester, 'Recheck Conditions');
      expect(actionEnabled(tester, 'Open Secure Content'), isTrue);
      conditions.update({
        ViewingCondition.authorization: ViewingConditionResult.denied,
      });
      await flushViewing(tester);
      expect(find.text('Authorization denied'), findsOneWidget);
      expect(actionEnabled(tester, 'Open Secure Content'), isFalse);
    },
  );

  testWidgets(
    'preflight can check after backgrounding before its first evaluation',
    (tester) async {
      await showViewer(tester, preflight: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flushViewing(tester);
      await tapLabel(tester, 'Check Conditions');
      expect(actionEnabled(tester, 'Open Secure Content'), isTrue);
    },
  );

  for (final issue in [
    'unknown',
    'capture',
    'denied',
    'unavailable',
    'checking',
    'demo',
  ]) {
    testWidgets('$issue warning is usable at 320px and 2x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (issue == 'unknown') conditions.snapshot.clear();
      if (issue == 'capture') native.capture = true;
      if (issue == 'denied') {
        conditions.snapshot[ViewingCondition.authorization] =
            ViewingConditionResult.denied;
      }
      if (issue == 'unavailable') native.enableError = MissingPluginException();
      if (issue == 'checking') {
        conditions.checking = Completer<Map<String, ViewingConditionResult>>();
      }
      await showViewer(tester, scale: 2, demo: issue == 'demo');
      expect(tester.takeException(), isNull);
      await tapLabel(tester, 'Close viewer');
      expect(tester.takeException(), isNull);
      if (issue == 'checking') {
        conditions.checking!.complete(conditions.snapshot);
        await flushViewing(tester);
      }
    });
  }

  testWidgets(
    'controller itself rejects rechecks after screenshot or explicit denial',
    (tester) async {
      native.install();
      final controller = ViewingStateController(
        restrictions: ContentRestrictions.demoDefaults,
        conditions: conditions,
        protection: protection,
      );
      addTearDown(controller.dispose);
      unawaited(controller.revalidate());
      await flushViewing(tester);
      conditions.update({
        ViewingCondition.expiration: ViewingConditionResult.failed,
      });
      final checks = conditions.checks;
      await controller.revalidate();
      expect(conditions.checks, checks);
      expect(controller.canRecheck, isFalse);
      expect(controller.state, ViewingState.accessDenied);
      controller.endForSecurityViolation(reason: ViewingIssueKind.screenshot);
      await controller.revalidate();
      expect(controller.violationReason, ViewingIssueKind.screenshot);
      expect(conditions.checks, checks);
    },
  );

  testWidgets(
    'preflight denial, policy and condition rows support large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      conditions.snapshot[ViewingCondition.authorization] =
          ViewingConditionResult.denied;
      await showViewer(tester, preflight: true, scale: 2);
      await tapLabel(tester, 'Check Conditions');
      expect(find.text('Authorization denied'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Native capture protection'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tapLabel(tester, 'Go back');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'demo exit preserves a real screenshot reason and labels simulated violations',
    (tester) async {
      await showViewer(tester, preflight: true);
      await tapLabel(tester, 'Open Demo Preview');
      native.events!.success({'type': 'screenshot'});
      await tester.pumpAndSettle();
      await flushViewing(tester);
      expect(find.text('Screenshot detected'), findsOneWidget);
      expect(find.text('Demo security violation'), findsNothing);
      expect(find.text('Recheck Conditions'), findsNothing);
      expect(actionEnabled(tester, 'Open Secure Content'), isFalse);
    },
  );

  testWidgets(
    'a shared session already ended before navigation still exits safely',
    (tester) async {
      native.install();
      final controller = ViewingStateController(
        restrictions: ContentRestrictions.demoDefaults,
        conditions: conditions,
        protection: protection,
      );
      addTearDown(controller.dispose);
      controller.endForSecurityViolation(reason: ViewingIssueKind.screenshot);
      var exits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SecureContentViewerScreen(
                        contentTitle: 'Document',
                        restrictions: ContentRestrictions.demoDefaults,
                        viewingController: controller,
                      ),
                    ),
                  );
                  exits++;
                },
                child: const Text('Enter'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Enter'));
      await tester.pumpAndSettle();
      expect(exits, 1);
      expect(protectedContent, findsNothing);
      expect(controller.violationReason, ViewingIssueKind.screenshot);
    },
  );
}
