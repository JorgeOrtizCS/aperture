import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/main.dart';
import 'package:aperture/screens/dashboard_screen.dart';
import 'package:aperture/screens/secure_content_viewer_screen.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/biometric_fake.dart';
import '../test/support/viewing_test_fakes.dart';

// UI diagnostic workload only: synthetic policy/identity/native-channel inputs,
// the existing non-sensitive placeholder, and no real account/content/inference.
// Keep this workload/configuration identical for before and after measurements.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('repeatable UI and secure-viewer performance workload', (
    tester,
  ) async {
    final native = NativeCaptureFake()..install();
    final protected = find.byKey(
      const ValueKey('protected-render-placeholder'),
      skipOffstage: false,
    );
    final stages = <Map<String, Object?>>[];
    final report = <String, Object?>{
      'label': const String.fromEnvironment(
        'APERTURE_PERF_LABEL',
        defaultValue: 'unlabeled',
      ),
      'mode': kDebugMode
          ? 'debug'
          : kProfileMode
          ? 'profile'
          : 'release',
      'platform': Platform.operatingSystem,
      'runtime': Platform.version,
      'display_refresh_rates_hz': ui.PlatformDispatcher.instance.displays
          .map((display) => display.refreshRate)
          .toList(),
      'physical_size': {
        'width': tester.view.physicalSize.width,
        'height': tester.view.physicalSize.height,
        'pixel_ratio': tester.view.devicePixelRatio,
      },
      'configuration': {
        'debug_rebuild_hook_available': kDebugMode,
        'steady_trials': 3,
        'steady_duration_ms': 6000,
        'synthetic_camera_interval_ms': 200,
        'frame_policy': 'fullyLive',
        'sdk_frame_budget_ms': 16,
        'boundary_inputs': 'test-only synthetic policy, biometrics and camera/capture channels',
        'login_fixture': 'controller-seeded synthetic prototype credentials; native IME entry is outside this navigation benchmark',
        'navigation_elapsed_scope':
            'test action through pumpAndSettle; includes test polling',
        'hide_elapsed_scope': 'injected event through first test-observed absent subtree; no sensor/native detection claim',
        'process_rss_scope': 'whole simulator app process, not Dart heap or protected-content size',
      },
      'stages': stages,
    };

    Future<void> measure(String name, Future<void> Function() action) async {
      debugPrint('[AperturePerfStage] $name start');
      final counts = <String, int>{};
      final previous = debugOnRebuildDirtyWidget;
      final elapsed = Stopwatch();
      int? rssBefore;
      int? rssAfter;
      await binding
          .watchPerformance(() async {
            debugOnRebuildDirtyWidget = (element, builtOnce) {
              previous?.call(element, builtOnce);
              // Count callbacks directly. Flutter's builtOnce flag is maintained by
              // debugPrintRebuildDirtyWidgets, which is deliberately disabled here.
              final name = element.widget.runtimeType.toString();
              if (const {
                'SecureContentViewerScreen',
                'BiometricStatusPanel',
                'ViewingStatusPanel',
                '_ProtectedRenderPlaceholder',
              }.contains(name)) {
                counts[name] = (counts[name] ?? 0) + 1;
              }
              final widget = element.widget;
              if (widget is Text &&
                  widget.data?.startsWith('People:') == true) {
                counts['telemetry_text'] = (counts['telemetry_text'] ?? 0) + 1;
              }
            };
            rssBefore = ProcessInfo.currentRss;
            elapsed.start();
            try {
              await action();
            } finally {
              elapsed.stop();
              rssAfter = ProcessInfo.currentRss;
              debugOnRebuildDirtyWidget = previous;
            }
          }, reportKey: name)
          .timeout(const Duration(seconds: 90));
      final timing = Map<String, dynamic>.from(
        binding.reportData![name] as Map,
      );
      stages.add({
        'name': name,
        'action_elapsed_us': elapsed.elapsedMicroseconds,
        'process_rss_before_bytes': rssBefore,
        'process_rss_after_bytes': rssAfter,
        'rebuilds_during_action': counts,
        'flutter_frame_timing': timing,
      });
      expect(tester.takeException(), isNull);
      debugPrint(
        '[AperturePerfStage] $name end frames=${timing['frame_count']} rebuilds=$counts',
      );
    }

    Future<void> tap(String label) async {
      final target = find.text(label);
      if (target.evaluate().isEmpty) {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          target,
          180,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await tester.pumpAndSettle();
    }

    await measure('in_process_app_first_mount', () async {
      await tester.pumpWidget(const ApertureApp());
      await tester.pumpAndSettle();
      expect(find.text('Get Started'), findsOneWidget);
    });
    await measure('welcome_to_login', () => tap('Get Started'));
    // Seed synthetic form inputs outside timing. Tester.enterText's debug
    // client is not reliable in profile mode. Sign In still executes the real
    // existing validation/navigation callback; no successful API is injected.
    for (final entry in {
      'login-username': 'performance-synthetic-user',
      'login-password': 'not-a-real-credential',
    }.entries) {
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(ValueKey(entry.key)),
          matching: find.byType(TextField),
        ),
      );
      field.controller!.text = entry.value;
      expect(field.controller!.text, entry.value);
    }
    await tester.pumpAndSettle();
    await measure('prototype_login_to_dashboard', () async {
      await tap('Sign In');
      expect(find.byType(DashboardScreen), findsOneWidget);
    });
    await measure('dashboard_notifications_roundtrip', () async {
      await tester.tap(find.byIcon(Icons.notifications_outlined).first);
      await tester.pumpAndSettle();
      await back();
    });
    await measure('sender_share_policy_roundtrip', () async {
      await tap('Share New Content');
      await tap('Edit Policy');
      await tap('Cancel');
      await back();
    });
    await measure('content_status_roundtrip', () async {
      await tap('Confidential File');
      await back();
    });
    await measure('unverified_secure_preflight', () async {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tap('Project Document');
      await tap('Check Conditions');
      expect(protected, findsNothing);
      await back();
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    final conditions = ConditionsFake();
    final controller = ViewingStateController(
      restrictions: ContentRestrictions.demoDefaults,
      conditions: conditions,
      protection: ScreenCaptureProtection.forTesting(),
      biometricAuthenticator: BiometricFake(),
    );
    Timer? heartbeat;
    var ticks = 0;
    try {
      await measure('synthetic_secure_viewer_initialization', () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.theme,
            home: SecureContentViewerScreen(
              contentTitle: 'Synthetic performance fixture — placeholder only',
              restrictions: ContentRestrictions.demoDefaults,
              viewingController: controller,
              cameraDetection: native.camera.service,
            ),
          ),
        );
        unawaited(controller.revalidate());
        await tester.pumpAndSettle();
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (protected.evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(protected, findsOneWidget);
        heartbeat = Timer.periodic(const Duration(milliseconds: 200), (_) {
          ticks++;
          native.camera.event(
            data: {
              ...native.camera.payload(),
              'latency_ms': 10 + (ticks % 20) / 10,
            },
          );
        });
      });
      for (var trial = 1; trial <= 3; trial++) {
        final checks = conditions.checks;
        final before = ticks;
        await measure('steady_telemetry_$trial', () async {
          await Future<void>.delayed(const Duration(milliseconds: 6000));
          expect(protected, findsOneWidget);
          expect(controller.state, ViewingState.allowed);
          expect(conditions.checks, checks);
        });
        stages.last['synthetic_ticks_including_sdk_flush'] = ticks - before;
      }
      final hideObservations = <String, int>{};
      await measure('condition_violation_warning', () async {
        final clock = Stopwatch()..start();
        conditions.update({
          ViewingCondition.location: ViewingConditionResult.failed,
        });
        await tester.pump();
        expect(protected, findsNothing);
        clock.stop();
        hideObservations['location_event_to_observed_hide_us'] =
            clock.elapsedMicroseconds;
        expect(find.text('Approved location failed'), findsOneWidget);
      });
      conditions.update({
        ViewingCondition.location: ViewingConditionResult.satisfied,
      });
      await tester.pump();
      expect(protected, findsNothing);
      await controller.revalidate();
      await tester.pumpAndSettle();
      expect(protected, findsOneWidget);
      await measure('capture_violation_warning', () async {
        final clock = Stopwatch()..start();
        native.setCapture(true);
        await tester.idle();
        await tester.pump();
        expect(protected, findsNothing);
        clock.stop();
        hideObservations['capture_event_to_observed_hide_us'] =
            clock.elapsedMicroseconds;
        expect(find.text('Screen capture detected'), findsOneWidget);
      });
      native.setCapture(false);
      await tester.pump();
      expect(protected, findsNothing);
      await controller.revalidate();
      await tester.pumpAndSettle();
      expect(protected, findsOneWidget);
      await measure('phone_termination', () async {
        final clock = Stopwatch()..start();
        native.camera.event(phone: true);
        await tester.idle();
        await tester.pump();
        expect(protected, findsNothing);
        clock.stop();
        hideObservations['phone_event_to_observed_hide_us'] =
            clock.elapsedMicroseconds;
        expect(controller.violationReason, ViewingIssueKind.phoneDetected);
        expect(controller.sessionEnded, isTrue);
        await tester.pumpAndSettle();
        native.camera.event();
        await controller.revalidate();
        await controller.verifyIdentity();
        expect(protected, findsNothing);
        expect(controller.sessionEnded, isTrue);
      });
      report['event_to_observed_hide_us'] = hideObservations;
      report['synthetic_camera_ticks_total'] = ticks;
    } finally {
      heartbeat?.cancel();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      controller.dispose();
      conditions.dispose();
    }
    binding.reportData!['aperture_workload'] = report;
    final encoded = base64Encode(utf8.encode(jsonEncode(report)));
    const chunkSize = 2000;
    final total = (encoded.length / chunkSize).ceil();
    for (var i = 0; i < total; i++) {
      final end = ((i + 1) * chunkSize).clamp(0, encoded.length);
      debugPrintSynchronously(
        '[AperturePerfChunk] ${i + 1}/$total ${encoded.substring(i * chunkSize, end)}',
      );
    }
    debugPrint(
      '[AperturePerfComplete] ${report['label']} stages=${stages.length}',
    );
  });
}
