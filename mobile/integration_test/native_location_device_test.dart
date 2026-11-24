import 'dart:async';
import 'dart:io';

import 'package:aperture/services/device_location.dart';
import 'package:aperture/services/native_device_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Real OS bridge/permissions, explicit test-driver location only. No API calls,
// no mock platform channel, no approved viewing-location policy or real content.
// Driver sets exactly 26.37,-80.1 after SAMPLE_PENDING and controls permissions.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native foreground location, accuracy metadata and cancellation',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Synthetic native location acceptance')),
        ),
      );
      await tester.pumpAndSettle();
      const channel = NativeDeviceLocation.channel;
      final source = NativeDeviceLocation();
      Future<T> wait<T>(
        Future<T> future, {
        Duration timeout = const Duration(seconds: 40),
      }) async {
        T? value;
        Object? error;
        bool done = false;
        unawaited(
          future.then(
            (v) {
              value = v;
              done = true;
            },
            onError: (Object e) {
              error = e;
              done = true;
            },
          ),
        );
        final deadline = DateTime.now().add(timeout);
        while (!done && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(done, true, reason: 'Native operation did not complete');
        if (error != null) throw error!;
        return value as T;
      }

      Future<void> foreground() async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (tester.binding.lifecycleState != AppLifecycleState.resumed &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.binding.lifecycleState, AppLifecycleState.resumed);
      }

      await foreground();
      debugPrint('[NativeLocation] PERMISSION_REQUEST');
      final initial = await wait(
        source.requestPermission(),
        timeout: const Duration(minutes: 2),
      );
      expect(
        initial,
        anyOf(
          LocationPermissionState.denied,
          LocationPermissionState.permanentlyDenied,
        ),
      );
      await foreground();
      if (Platform.isAndroid && initial == LocationPermissionState.denied) {
        debugPrint('[NativeLocation] PERMISSION_REQUEST_AGAIN');
        expect(
          await wait(
            source.requestPermission(),
            timeout: const Duration(minutes: 2),
          ),
          LocationPermissionState.permanentlyDenied,
        );
      }
      debugPrint('[NativeLocation] GRANT_SETTINGS');
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      Object? permission;
      do {
        permission = await wait(channel.invokeMethod<Object?>('permission'));
        if (permission == 'granted') break;
        await tester.pump(const Duration(milliseconds: 200));
      } while (DateTime.now().isBefore(deadline));
      expect(permission, 'granted');
      await foreground();
      final started = DateTime.now().millisecondsSinceEpoch;
      debugPrint('[NativeLocation] SAMPLE_PENDING');
      final sample = await wait(
        channel.invokeMapMethod<String, Object?>('locate', {
          'owner_id': 9001,
          'request_id': 1,
          'timeout_ms': 4000,
        }),
      );
      expect(sample?['status'], 'granted');
      expect((sample!['latitude'] as num).toDouble(), closeTo(26.37, 0.00001));
      expect((sample['longitude'] as num).toDouble(), closeTo(-80.1, 0.00001));
      final accuracy = (sample['accuracy_m'] as num).toDouble();
      expect(accuracy.isFinite && accuracy >= 0, true);
      expect(sample['timestamp_ms'] as int, greaterThanOrEqualTo(started));
      debugPrint(
        '[NativeLocation] SAMPLE_PASS (measurement only, not viewing approval)',
      );
      expect(
        (await source.locate()).status,
        LocationStatus.accuracyUnconfirmed,
      );

      debugPrint('[NativeLocation] CLEAR_LOCATION');
      await tester.pump(const Duration(seconds: 2));
      debugPrint('[NativeLocation] CANCEL_PENDING');
      final cancelled = channel.invokeMapMethod<String, Object?>('locate', {
        'owner_id': 9002,
        'request_id': 2,
        'timeout_ms': 4000,
      });
      await wait(channel.invokeMethod<void>('close', {'owner_id': 9001}));
      await wait(
        channel.invokeMethod<void>('cancelAcquisition', {'owner_id': 9002}),
      );
      expect((await wait(cancelled))?['status'], 'cancelled');
      debugPrint('[NativeLocation] CANCEL_PASS');

      final timeout = await wait(
        channel.invokeMapMethod<String, Object?>('locate', {
          'owner_id': 9003,
          'request_id': 3,
          'timeout_ms': 100,
        }),
      );
      expect(timeout?['status'], 'unavailable');
      debugPrint('[NativeLocation] TIMEOUT_PASS');
      debugPrint('[NativeLocation] BACKGROUND_PENDING');
      final background = channel.invokeMapMethod<String, Object?>('locate', {
        'owner_id': 9004,
        'request_id': 4,
        'timeout_ms': 4000,
      });
      expect((await wait(background))?['status'], 'cancelled');
      final foregroundDeadline = DateTime.now().add(
        const Duration(seconds: 30),
      );
      while (tester.binding.lifecycleState != AppLifecycleState.resumed &&
          DateTime.now().isBefore(foregroundDeadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.binding.lifecycleState, AppLifecycleState.resumed);
      debugPrint('[NativeLocation] LIFECYCLE_PASS');
      await wait(source.close());
      expect(
        find.byKey(
          const ValueKey('protected-render-placeholder'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      debugPrint('[NativeLocation] COMPLETE');
    },
  );
}
