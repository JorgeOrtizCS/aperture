import 'dart:async';

import 'package:aperture/screens/secure_content_viewer_screen.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/viewing_test_fakes.dart';

final content = find.byKey(
  const ValueKey('protected-render-placeholder'),
  skipOffstage: false,
);

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

  Future<void> open(
    WidgetTester tester, {
    bool demo = false,
    bool unverified = false,
    ValueChanged<SecureContentViewerExitReason?>? onExit,
  }) async {
    native.install();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result =
                    await Navigator.push<SecureContentViewerExitReason>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => demo
                            ? SecureContentViewerScreen.demo(
                                contentTitle: 'Demo',
                                restrictions: ContentRestrictions.demoDefaults,
                                captureProtection: protection,
                              )
                            : SecureContentViewerScreen(
                                contentTitle: 'Test document',
                                restrictions: ContentRestrictions.demoDefaults,
                                conditionProvider: unverified
                                    ? null
                                    : conditions,
                                captureProtection: protection,
                              ),
                      ),
                    );
                onExit?.call(result);
              },
              child: const Text('Open viewer'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open viewer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await flushViewing(tester);
  }

  testWidgets(
    'never builds content while initialization or checks are pending',
    (tester) async {
      native.enabling = Completer<bool>();
      conditions.checking = Completer<Map<String, ViewingConditionResult>>();
      await open(tester);
      expect(find.text('Checking conditions'), findsOneWidget);
      expect(content, findsNothing);
      native.enabling!.complete(false);
      await flushViewing(tester);
      expect(content, findsNothing);
      conditions.checking!.complete(conditions.snapshot);
      await flushViewing(tester);
      expect(content, findsOneWidget);
    },
  );

  testWidgets(
    'first failure frame removes content with no fade or retained semantics',
    (tester) async {
      await open(tester);
      expect(content, findsOneWidget);
      conditions.update({'presence': ViewingConditionResult.failed});
      await tester.pump();
      expect(content, findsNothing);
      expect(find.text('Content Hidden'), findsOneWidget);
      expect(
        find.text('Protected content viewer', skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(AnimatedSwitcher), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(content, findsNothing);
      conditions.update({'presence': ViewingConditionResult.satisfied});
      await tester.pump();
      expect(content, findsNothing);
      await tester.ensureVisible(find.text('Recheck Conditions'));
      await tester.tap(find.text('Recheck Conditions'));
      await flushViewing(tester);
      expect(content, findsOneWidget);
    },
  );

  testWidgets('unknown real policy requirements keep the normal route locked', (
    tester,
  ) async {
    await open(tester, unverified: true);
    expect(content, findsNothing);
    expect(find.text('Content Hidden'), findsOneWidget);
  });

  testWidgets('native stream error immediately replaces visible content', (
    tester,
  ) async {
    await open(tester);
    expect(content, findsOneWidget);
    native.events!.error(code: 'monitor_failed');
    await tester.pump();
    expect(content, findsNothing);
    expect(find.text('Protection unavailable'), findsOneWidget);
  });

  testWidgets('background hides content and resume waits for fresh checks', (
    tester,
  ) async {
    await open(tester);
    expect(content, findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(content, findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(content, findsNothing);
    conditions.checking = Completer<Map<String, ViewingConditionResult>>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flushViewing(tester);
    expect(content, findsNothing);
    expect(find.text('Checking conditions'), findsOneWidget);
    conditions.checking!.complete(conditions.snapshot);
    await flushViewing(tester);
    expect(content, findsOneWidget);
    expect(native.enables, 2);
    expect(conditions.checks, 2);
  });

  testWidgets('repeated screenshots exit once with existing violation result', (
    tester,
  ) async {
    var exits = 0;
    SecureContentViewerExitReason? reason;
    await open(
      tester,
      onExit: (value) {
        exits++;
        reason = value;
      },
    );
    native.events!.success({'type': 'screenshot'});
    native.events!.success({'type': 'screenshot'});
    await tester.pump();
    expect(content, findsNothing);
    await tester.pumpAndSettle();
    await flushViewing(tester);
    expect(exits, 1);
    expect(reason, SecureContentViewerExitReason.securityViolation);
    expect(find.text('Open viewer'), findsOneWidget);
    expect(native.disables, 1);
  });

  testWidgets('rapid Back and reopen discards old initialization safely', (
    tester,
  ) async {
    native.enabling = Completer<bool>();
    await open(tester);
    expect(content, findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open viewer'));
    await tester.pumpAndSettle();
    native.enabling!.complete(false);
    await flushViewing(tester);
    expect(content, findsOneWidget);
    expect(native.calls, [
      'enableProtection',
      'disableProtection',
      'enableProtection',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'demo is labeled and can fail and restore only its placeholder condition',
    (tester) async {
      await open(tester, demo: true);
      expect(content, findsOneWidget);
      expect(
        find.textContaining(
          'Authorization, expiration, and view-count checks are not evaluated',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Demo: Fail Viewing Condition'));
      await tester.pump();
      expect(content, findsNothing);
      await tester.tap(find.text('Demo: Restore Viewing Condition'));
      await tester.pump();
      expect(content, findsNothing);
      await tester.ensureVisible(find.text('Recheck Conditions'));
      await tester.tap(find.text('Recheck Conditions'));
      await flushViewing(tester);
      expect(content, findsOneWidget);
    },
  );

  testWidgets('normal Back removes content before the outgoing route fades', (
    tester,
  ) async {
    await open(tester);
    expect(content, findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    expect(content, findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Open viewer'), findsOneWidget);
  });
}
