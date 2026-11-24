import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/screens/secure_content_viewer_screen.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/aperture_button.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:aperture/widgets/viewing_status_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/viewing_test_fakes.dart';

void main() {
  for (final scale in [2.0, 3.0]) {
    for (final withIcon in [false, true]) {
      testWidgets(
        'button label fits and remains tappable at 320px, ${scale}x text, icon=$withIcon',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var presses = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    ApertureButton(
                      label: 'Share New Content',
                      icon: withIcon ? Icons.add : null,
                      onPressed: () => presses++,
                    ),
                  ],
                ),
              ),
            ),
          );
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text('Share New Content'),
          );
          final painter = TextPainter(
            text: paragraph.text,
            textDirection: TextDirection.ltr,
            textScaler: paragraph.textScaler,
            maxLines: paragraph.maxLines,
          )..layout(maxWidth: paragraph.size.width);
          expect(
            paragraph.size.height,
            greaterThanOrEqualTo(painter.height),
            reason: 'Every line of the enlarged label must fit',
          );
          painter.dispose();
          final button = find.byType(ElevatedButton);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(56));
          expect(tester.takeException(), isNull);
          await tester.tap(button);
          expect(presses, 1);
        },
      );
    }
  }

  for (final demo in [false, true]) {
    testWidgets(
      'violation simulation is ${demo ? 'available in the explicit demo' : 'absent from a normal route'}',
      (tester) async {
        final native = NativeCaptureFake()..install();
        final conditions = ConditionsFake();
        addTearDown(conditions.dispose);
        final protection = ScreenCaptureProtection.forTesting();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.theme,
            home: demo
                ? SecureContentViewerScreen.demo(
                    contentTitle: 'Demo',
                    restrictions: ContentRestrictions.demoDefaults,
                    captureProtection: protection,
                    cameraDetection: native.camera.service,
                  )
                : SecureContentViewerScreen(
                    contentTitle: 'Normal route',
                    restrictions: ContentRestrictions.demoDefaults,
                    conditionProvider: conditions,
                    captureProtection: protection,
                    cameraDetection: native.camera.service,
                  ),
          ),
        );
        await flushViewing(tester);
        expect(
          find.byKey(const ValueKey('protected-render-placeholder')),
          findsOneWidget,
        );
        final action = find.text('Demo: Simulate Security Violation');
        if (demo) {
          await tester.scrollUntilVisible(
            action,
            200,
            scrollable: find.byType(Scrollable).first,
          );
        }
        expect(action, demo ? findsOneWidget : findsNothing);
        if (demo) {
          await tester.ensureVisible(action);
          await tester.tap(action);
          await tester.pump();
          expect(
            find.byKey(
              const ValueKey('protected-render-placeholder'),
              skipOffstage: false,
            ),
            findsNothing,
          );
          expect(find.text('Demo security violation'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        await flushViewing(tester);
      },
    );
  }

  for (final reason in [
    ViewingIssueKind.phoneDetected,
    ViewingIssueKind.screenshot,
    null,
  ]) {
    testWidgets(
      'ended-session rows cannot imply authorization after ${reason?.name ?? 'policy denial'}',
      (tester) async {
        NativeCaptureFake().install();
        final conditions = ConditionsFake();
        final controller = ViewingStateController(
          restrictions: ContentRestrictions.demoDefaults,
          conditions: conditions,
          protection: ScreenCaptureProtection.forTesting(),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.theme,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: controller,
                builder: (_, _) => ListView(
                  children: [
                    ViewingStatusPanel(
                      controller: controller,
                      onRecheck: controller.revalidate,
                    ),
                    ViewingConditionList(controller: controller),
                  ],
                ),
              ),
            ),
          ),
        );
        controller.revalidate();
        await flushViewing(tester);
        expect(controller.state, ViewingState.allowed);
        if (reason != null) {
          controller.endForSecurityViolation(reason: reason);
        } else {
          conditions.update({
            ViewingCondition.authorization: ViewingConditionResult.denied,
          });
        }
        await tester.pump();
        expect(controller.state, ViewingState.accessDenied);
        expect(find.text('Met'), findsNothing);
        expect(find.text('Available for this session'), findsNothing);
        expect(
          find.text(
            'Session ended. Previous checks no longer authorize access.',
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(ViewingConditionList),
            matching: find.byIcon(Icons.check_circle_outline),
          ),
          findsNothing,
        );
        if (reason == null) expect(find.text('Denied'), findsOneWidget);
        final checks = conditions.checks;
        conditions.update(
          Map.fromEntries(
            controller.requiredConditions.map(
              (id) => MapEntry(id, ViewingConditionResult.satisfied),
            ),
          ),
        );
        await controller.revalidate();
        await flushViewing(tester);
        expect(controller.state, ViewingState.accessDenied);
        expect(conditions.checks, checks);
        expect(find.text('Recheck Conditions'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await flushViewing(tester);
        conditions.dispose();
      },
    );
  }
}
