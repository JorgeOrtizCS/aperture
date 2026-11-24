import 'dart:async';
import 'dart:io';

import 'package:aperture/screens/api_content_screens.dart';
import 'package:aperture/screens/notifications_screen.dart';
import 'package:aperture/services/camera_detection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/api_fake.dart';

// The host drives OS permission prompts and settings on disposable targets.
// The API transport is an in-process fixture. No protected content is loaded.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native permission denial and restoration remain locked', (
    tester,
  ) async {
    final fake = ApiFake()
      ..contents = [
        {
          ...contentJson(title: 'Private native fixture.png'),
          'Latitude': 26.37,
          'Longitude': -80.1,
          'RadiusMeters': 500,
        },
        contentJson(id: 8, policy: 'Paused'),
      ];
    final account = fake.session();
    final navigator = GlobalKey<NavigatorState>();
    final service = CameraDetectionService();
    final camera = service.createSession();
    void mark(String step) => debugPrint('[Task114Native] $step');
    final lifecycle = AppLifecycleListener(onPause: () => mark('PAUSED'));

    Future<void> waitFor(Finder finder) async {
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 33));
        await Future<void>.delayed(const Duration(milliseconds: 33));
      }
      expect(finder, findsOneWidget);
      await tester.pumpAndSettle();
    }

    try {
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      await account.login('synthetic-user', 'fixture-password');
      await account.refresh();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: ApiRecipientScreen(account: account, contentId: 7),
        ),
      );

      if (Platform.isAndroid) {
        expect(
          await service.readPermission(),
          CameraPermissionState.notDetermined,
        );
        // Exercise the Android OS denial dialog on a standalone camera run.
        // The host denies the request before any detector can start.
        mark('CAMERA_PROMPT');
        unawaited(camera.start());
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        CameraPermissionState permission;
        do {
          await tester.pump(const Duration(milliseconds: 80));
          await Future<void>.delayed(const Duration(milliseconds: 80));
          permission = await service.readPermission();
        } while ((binding.lifecycleState != AppLifecycleState.resumed ||
                permission != CameraPermissionState.denied) &&
            DateTime.now().isBefore(deadline));
        expect(permission, CameraPermissionState.denied);
        await camera.stop();
        mark('CAMERA_DENIED');
        final allow = find.text('Allow location for viewing');
        await waitFor(allow);
        mark('LOCATION_PROMPT');
        await tester.tap(allow);
      } else {
        expect(
          await service.readPermission(),
          isNot(CameraPermissionState.unavailable),
        );
        mark('INITIAL_LOCATION_DENIAL');
      }

      await waitFor(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data?.contains('Location permission denied.') == true ||
                  widget.data?.contains(
                        'Location permission is blocked in system settings.',
                      ) ==
                      true),
        ),
      );
      final blocked = find
          .textContaining('Location permission is blocked in system settings.')
          .evaluate()
          .isNotEmpty;
      mark('LOCATION_DENIED blocked=$blocked');

      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => NotificationsScreen(account: account),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          blocked
              ? 'Location permission blocked'
              : 'Location permission denied',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Device status'), findsOneWidget);
      expect(find.text('Content paused'), findsOneWidget);
      expect(find.textContaining('Content listing'), findsOneWidget);
      expect(find.text('Private native fixture.png'), findsNothing);
      expect(find.byType(RawImage), findsNothing);
      await binding.takeScreenshot('01-notifications-location-denied');
      navigator.currentState!.pop();
      await tester.pumpAndSettle();

      mark('RESTORE_READY');
      await waitFor(find.textContaining('Location permission is available.'));
      expect(find.text('Allow location for viewing'), findsNothing);
      if (Platform.isAndroid) {
        expect(await service.readPermission(), CameraPermissionState.granted);
      }
      expect(
        fake.calls.where((call) => call.uri.path.endsWith('/sessions')),
        isEmpty,
      );
      expect(
        find.byKey(const ValueKey('protected-render-placeholder')),
        findsNothing,
      );
      await binding.takeScreenshot('02-permission-restored-viewing-locked');
      mark('RESTORED_VIEWING_LOCKED');
    } finally {
      lifecycle.dispose();
      await camera.close();
      camera.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      account.dispose();
    }
  });
}
