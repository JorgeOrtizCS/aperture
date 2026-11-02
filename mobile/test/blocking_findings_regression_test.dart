import 'dart:async';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/screens/viewing_requirements_screen.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/viewing_test_fakes.dart';

Future<ViewingStateController> allowedController(
  WidgetTester tester,
  NativeCaptureFake native,
  ConditionsFake conditions,
) async {
  native.install();
  final controller = ViewingStateController(
    restrictions: ContentRestrictions.demoDefaults,
    conditions: conditions,
    protection: ScreenCaptureProtection.forTesting(),
  );
  addTearDown(() {
    controller.dispose();
    conditions.dispose();
  });
  unawaited(controller.revalidate());
  await flushViewing(tester);
  expect(controller.state, ViewingState.allowed);
  return controller;
}

Future<void> showEditor(WidgetTester tester, {bool large = false}) async {
  if (large) {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
        child: child!,
      ),
      home: const ViewingRequirementsScreen(
        initialRestrictions: ContentRestrictions.demoDefaults,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<SemanticsNode> semanticsNodes(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return nodes;
}

void main() {
  testWidgets(
    'a newly required unknown check cannot be satisfied by a live event alone',
    (tester) async {
      final native = NativeCaptureFake();
      final required = <String>{'presence'};
      final conditions = ConditionsFake(requiredConditions: required);
      final controller = await allowedController(tester, native, conditions);
      required.add('additionalRequirement');
      expect(controller.state, ViewingState.temporarilyLocked);
      conditions.update({
        'additionalRequirement': ViewingConditionResult.satisfied,
      });
      expect(controller.state, ViewingState.temporarilyLocked);
      expect(conditions.checks, 1);
      unawaited(controller.revalidate());
      await flushViewing(tester);
      expect(controller.state, ViewingState.allowed);
      expect(conditions.checks, 2);
    },
  );

  testWidgets(
    'restoration requires a complete fresh provider check AND native revalidation',
    (tester) async {
      final native = NativeCaptureFake();
      final conditions = ConditionsFake();
      final controller = await allowedController(tester, native, conditions);
      conditions.update({'presence': ViewingConditionResult.failed});
      expect(controller.state, ViewingState.temporarilyLocked);
      conditions.update({'presence': ViewingConditionResult.satisfied});
      expect(controller.state, ViewingState.temporarilyLocked);
      expect(conditions.checks, 1);
      expect(native.enables, 1);
      native.enabling = Completer<bool>();
      conditions.checking = Completer<Map<String, ViewingConditionResult>>();
      unawaited(controller.revalidate());
      await flushViewing(tester);
      expect(conditions.checks, 2);
      expect(native.enables, 2);
      expect(controller.state, ViewingState.checking);
      conditions.checking!.complete(conditions.snapshot);
      await flushViewing(tester);
      expect(controller.state, ViewingState.checking);
      native.enabling!.complete(false);
      await flushViewing(tester);
      expect(controller.state, ViewingState.allowed);
    },
  );

  for (final missingOrFailed in ['missing', 'unknown', 'failed']) {
    testWidgets(
      '$missingOrFailed fresh result cannot be replaced by a satisfied live event',
      (tester) async {
        final native = NativeCaptureFake();
        final conditions = ConditionsFake();
        final controller = await allowedController(tester, native, conditions);
        conditions.update({'presence': ViewingConditionResult.failed});
        conditions.update({'presence': ViewingConditionResult.satisfied});
        conditions.checking = Completer<Map<String, ViewingConditionResult>>();
        unawaited(controller.revalidate());
        await flushViewing(tester);
        conditions.update({'presence': ViewingConditionResult.satisfied});
        final snapshot = Map.of(conditions.snapshot);
        if (missingOrFailed == 'missing') {
          snapshot.remove('presence');
        } else {
          snapshot['presence'] = missingOrFailed == 'unknown'
              ? ViewingConditionResult.unknown
              : ViewingConditionResult.failed;
        }
        conditions.checking!.complete(snapshot);
        await flushViewing(tester);
        expect(controller.state, ViewingState.temporarilyLocked);
        conditions.update({'presence': ViewingConditionResult.satisfied});
        await flushViewing(tester);
        expect(controller.state, ViewingState.temporarilyLocked);
        conditions.checking = null;
        unawaited(controller.revalidate());
        await flushViewing(tester);
        expect(controller.state, ViewingState.allowed);
      },
    );
  }

  testWidgets(
    'failure then satisfaction while native revalidation is pending invalidates the earlier snapshot',
    (tester) async {
      final native = NativeCaptureFake();
      final conditions = ConditionsFake();
      final controller = await allowedController(tester, native, conditions);
      native.enabling = Completer<bool>();
      unawaited(controller.revalidate());
      await flushViewing(
        tester,
      ); // Provider snapshot has passed; native check is still pending.
      conditions.update({'presence': ViewingConditionResult.failed});
      conditions.update({'presence': ViewingConditionResult.satisfied});
      native.enabling!.complete(false);
      await flushViewing(tester);
      expect(controller.state, ViewingState.temporarilyLocked);
      unawaited(controller.revalidate());
      await flushViewing(tester);
      expect(controller.state, ViewingState.allowed);
    },
  );

  testWidgets(
    'rechecking one restored condition cannot clear another simultaneous failure',
    (tester) async {
      final native = NativeCaptureFake();
      final conditions = ConditionsFake();
      final controller = await allowedController(tester, native, conditions);
      conditions.update({
        'presence': ViewingConditionResult.failed,
        'location': ViewingConditionResult.failed,
      });
      conditions.update({'presence': ViewingConditionResult.satisfied});
      unawaited(controller.revalidate());
      await flushViewing(tester);
      expect(controller.state, ViewingState.temporarilyLocked);
      conditions.update({'location': ViewingConditionResult.satisfied});
      expect(controller.state, ViewingState.temporarilyLocked);
      unawaited(controller.revalidate());
      await flushViewing(tester);
      expect(controller.state, ViewingState.allowed);
    },
  );

  for (final label in [
    'Allow Download',
    'Allow Resharing',
    'Screenshot Protection',
  ]) {
    testWidgets(
      '$label has one labeled switch node with an accurate toggled state',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await showEditor(tester);
          final matches = semanticsNodes(tester)
              .where((node) => node.label.contains(label))
              .toList();
          expect(
            matches,
            hasLength(1),
            reason:
                'The title must not be announced separately from the switch.',
          );
          final node = matches.single;
          expect(node.label, label);
          expect(
            node.getSemanticsData().flagsCollection.isToggled.toBoolOrNull(),
            isNotNull,
          );
          final initial = label == 'Screenshot Protection';
          expect(
            node.getSemanticsData().flagsCollection.isToggled.toBoolOrNull(),
            initial,
          );
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(node.id, SemanticsAction.tap);
          await tester.pumpAndSettle();
          final updated = semanticsNodes(tester)
              .where((node) => node.label == label)
              .single;
          expect(
            updated.getSemanticsData().flagsCollection.isToggled.toBoolOrNull(),
            !initial,
          );
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'Expiration dropdown preserves all options and selections at 320x640 with 2x text',
    (tester) async {
      await showEditor(tester, large: true);
      final dropdown = find.byType(DropdownButtonFormField<AccessDuration>);
      for (final duration in AccessDuration.values) {
        await tester.scrollUntilVisible(
          dropdown,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(dropdown),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        for (final option in AccessDuration.values) {
          expect(find.text(option.label, skipOffstage: false), findsWidgets);
        }
        final target = find.text(duration.label).last;
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ContentRestrictionsSection>(
                find.byType(ContentRestrictionsSection),
              )
              .restrictions
              .accessDuration,
          duration,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'View Limit dropdown preserves unlimited and finite options at 320x640 with 2x text',
    (tester) async {
      await showEditor(tester, large: true);
      final dropdown = find.byType(DropdownButtonFormField<String>);
      final options = <String, int?>{
        'Unlimited': null,
        '1 view': 1,
        '3 views': 3,
        '5 views': 5,
      };
      for (final option in options.entries) {
        await tester.scrollUntilVisible(
          dropdown,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(dropdown),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        for (final label in options.keys) {
          expect(find.text(label, skipOffstage: false), findsWidgets);
        }
        final target = find.text(option.key).last;
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ContentRestrictionsSection>(
                find.byType(ContentRestrictionsSection),
              )
              .restrictions
              .viewLimit,
          option.value,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
