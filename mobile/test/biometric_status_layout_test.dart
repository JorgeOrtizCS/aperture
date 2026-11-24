import 'dart:async';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/services/biometric_verification.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/widgets/biometric_status_panel.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/biometric_fake.dart';
import 'support/viewing_test_fakes.dart';

void main() {
  for (final state in BiometricState.values) {
    testWidgets('${state.name} is accessible and wraps at 320px with 3x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final native = NativeCaptureFake()..install();
      final conditions = ConditionsFake();
      final fake = BiometricFake()..result = state;
      if (state == BiometricState.verifying) {
        fake.pending = Completer<BiometricState>();
      }
      final controller = ViewingStateController(
        restrictions: ContentRestrictions.demoDefaults,
        conditions: conditions,
        protection: ScreenCaptureProtection.forTesting(),
        biometricAuthenticator: fake,
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(3)),
            child: child!,
          ),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [BiometricStatusPanel(controller: controller)],
              ),
            ),
          ),
        ),
      );
      if (state == BiometricState.ended) {
        controller.endForSecurityViolation(
          reason: ViewingIssueKind.phoneDetected,
        );
      } else if (state != BiometricState.required) {
        unawaited(controller.verifyIdentity());
      }
      await flushViewing(tester);
      final message = biometricMessage(state);
      expect(
        find.text(message.title),
        state == BiometricState.verifying ? findsNWidgets(2) : findsOneWidget,
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(message.message),
      );
      final painter = TextPainter(
        text: paragraph.text,
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout(maxWidth: paragraph.size.width);
      expect(paragraph.size.height, greaterThanOrEqualTo(painter.height));
      painter.dispose();
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .any((s) => s.properties.liveRegion == true),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      if (state != BiometricState.verified && state != BiometricState.ended) {
        final action = find.byType(ElevatedButton);
        await tester.ensureVisible(action);
        await tester.pump();
        expect(action.hitTestable(), findsOneWidget);
        expect(
          tester.widget<ElevatedButton>(action).onPressed != null,
          state != BiometricState.verifying,
        );
      } else {
        expect(find.byType(ElevatedButton), findsNothing);
      }
      expect(native.camera.starts, 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await flushViewing(tester);
      conditions.dispose();
      semantics.dispose();
    });
  }
}
