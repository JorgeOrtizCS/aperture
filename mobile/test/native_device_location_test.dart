import 'dart:async';

import 'package:aperture/services/device_location.dart';
import 'package:aperture/services/native_device_location.dart';
import 'package:aperture/services/api_viewing_conditions.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';

// Synthetic measurements/accuracy limits. No production accuracy rule is set.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NativeDeviceLocation source;
  late DateTime clock;
  late List<MethodCall> calls;
  String permission = 'granted';
  Completer<Object?>? permissionReply;
  Future<Object?> Function()? reply;
  Map<String, Object?> sample() => {
    'status': 'granted',
    'latitude': 26.37,
    'longitude': -80.1,
    'accuracy_m': 3.0,
    'timestamp_ms': clock.millisecondsSinceEpoch,
  };
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  setUp(() {
    clock = DateTime.utc(2026, 11, 6);
    permission = 'granted';
    calls = [];
    reply = null;
    permissionReply = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeDeviceLocation.channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'permission':
              return permission;
            case 'requestPermission':
              return permissionReply?.future ?? permission;
            case 'locate':
              return reply == null ? sample() : reply!();
            case 'cancelAcquisition':
            case 'close':
              return null;
          }
          throw MissingPluginException();
        });
    source = NativeDeviceLocation(
      approvedAccuracyLimitMeters: 10,
      now: () => clock,
    );
  });
  tearDown(() async {
    await source.close();
  });
  test(
    'unused native source closes without platform calls or cleanup timers',
    () async {
      await source.close();
      expect(calls, isEmpty);
    },
  );
  test('fresh OS measurement retains reported accuracy, never fabricated precision', () async {
    final result = await source.locate();
    expect(result.status, LocationStatus.granted);
    expect(result.fix!.horizontalAccuracyMeters, 3);
    expect(result.fix!.latitude, 26.37);
    expect(result.fix.toString(), 'LocationFix(redacted)');
    expect(calls.map((c) => c.method), ['permission', 'locate']);
    expect(calls.last.arguments['max_accuracy_m'], 10.0);
    expect(calls.last.arguments['timeout_ms'], 4000);
  });
  test('native accuracy rejection passes no fix to the caller', () async {
    reply = () async => {'status': 'insufficientAccuracy'};
    final result = await source.locate();
    expect(result.status, LocationStatus.insufficientAccuracy);
    expect(result.fix, isNull);
  });
  test(
    'permission loss after a fresh fix does not reuse or acquire a fix',
    () async {
      expect((await source.locate()).status, LocationStatus.granted);
      calls.clear();
      permission = 'denied';
      final result = await source.locate();
      expect(result.status, LocationStatus.denied);
      expect(result.fix, isNull);
      expect(calls.map((c) => c.method), ['permission']);
    },
  );
  for (final limit in [null, -1.0, 0.0, double.nan, double.infinity]) {
    test('unknown or invalid accuracy rule $limit collects nothing', () async {
      await source.close();
      calls.clear();
      source = NativeDeviceLocation(approvedAccuracyLimitMeters: limit);
      expect(
        (await source.locate()).status,
        LocationStatus.accuracyUnconfirmed,
      );
      expect(calls, isEmpty);
    });
  }
  for (final row in [
    ('notDetermined', LocationStatus.permissionRequired),
    ('denied', LocationStatus.denied),
    ('permanentlyDenied', LocationStatus.permanentlyDenied),
    ('approximate', LocationStatus.insufficientAccuracy),
    ('unavailable', LocationStatus.unavailable),
    ('unexpected', LocationStatus.unavailable),
  ]) {
    test(
      'permission ${row.$1} never samples or prompts automatically',
      () async {
        permission = row.$1;
        expect((await source.locate()).status, row.$2);
        expect(calls.map((c) => c.method), ['permission']);
      },
    );
  }
  for (final row in <(String, Object?)>[
    ('accuracy_m', null),
    ('accuracy_m', -1),
    ('accuracy_m', double.nan),
    ('accuracy_m', double.infinity),
    ('accuracy_m', '3'),
    ('latitude', double.nan),
    ('latitude', 91),
    ('longitude', -181),
    ('timestamp_ms', null),
    ('timestamp_ms', -1),
    ('timestamp_ms', 'time'),
  ]) {
    test('invalid ${row.$1}=${row.$2} fails closed', () async {
      reply = () async => {...sample(), row.$1: row.$2};
      expect((await source.locate()).status, isNot(LocationStatus.granted));
    });
  }
  for (final offset in [-1, 1]) {
    test('timestamp offset $offset is not a newly acquired fix', () async {
      reply = () async => {
        ...sample(),
        'timestamp_ms': clock
            .add(Duration(seconds: offset))
            .millisecondsSinceEpoch,
      };
      expect((await source.locate()).status, LocationStatus.stale);
    });
  }
  test('insufficient accuracy drops the coordinates', () async {
    reply = () async => {...sample(), 'accuracy_m': 100.0};
    final r = await source.locate();
    expect(r.status, LocationStatus.insufficientAccuracy);
    expect(r.fix, isNull);
  });
  for (final status in [
    'cancelled',
    'unavailable',
    'stale',
    'denied',
    'permanentlyDenied',
  ]) {
    test('native $status cannot produce a fix', () async {
      reply = () async => {'status': status};
      expect((await source.locate()).status, isNot(LocationStatus.granted));
    });
  }
  test(
    'permission interaction is separate and duplicate actions share one wait',
    () async {
      permissionReply = Completer<Object?>();
      final first = source.requestPermission();
      final second = source.requestPermission();
      expect(identical(first, second), true);
      await tick();
      expect(calls.map((c) => c.method), ['requestPermission']);
      permissionReply!.complete('granted');
      expect(await first, LocationPermissionState.granted);
      expect(calls.where((c) => c.method == 'locate'), isEmpty);
    },
  );
  test('cancellation rejects late acquisition success', () async {
    final pending = Completer<Object?>();
    reply = () => pending.future;
    final first = source.locate();
    await tick();
    await source.cancelAcquisition();
    pending.complete(sample());
    expect((await first).status, LocationStatus.cancelled);
  });
  test('old request error cannot cancel replacement acquisition', () async {
    final old = Completer<Object?>();
    reply = () => old.future;
    final first = source.locate();
    await tick();
    await source.cancelAcquisition();
    final current = Completer<Object?>();
    reply = () => current.future;
    final second = source.locate();
    await tick();
    old.completeError(PlatformException(code: 'old_request'));
    expect((await first).status, isNot(LocationStatus.granted));
    expect(calls.where((c) => c.method == 'cancelAcquisition').length, 1);
    current.complete(sample());
    expect((await second).status, LocationStatus.granted);
  });
  test(
    'close rejects pending permission and never reopens the source',
    () async {
      permissionReply = Completer<Object?>();
      final wait = source.requestPermission();
      await tick();
      await source.close();
      permissionReply!.complete('granted');
      expect(await wait, LocationPermissionState.unavailable);
      expect((await source.locate()).status, LocationStatus.unavailable);
    },
  );
  test('background cancels permission ownership', () async {
    permissionReply = Completer<Object?>();
    final wait = source.requestPermission();
    await tick();
    source.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tick();
    permissionReply!.complete('granted');
    expect(await wait, LocationPermissionState.unavailable);
    expect((await source.locate()).status, LocationStatus.unavailable);
  });
  test(
    'inactive permission prompt does not authorize a location fix',
    () async {
      permissionReply = Completer<Object?>();
      final wait = source.requestPermission();
      await tick();
      source.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tick();
      permissionReply!.complete('granted');
      expect(await wait, LocationPermissionState.granted);
      expect((await source.locate()).status, LocationStatus.unavailable);
      source.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect((await source.locate()).status, LocationStatus.granted);
    },
  );
  test('Dart timeout releases native sensor ownership', () async {
    await source.close();
    calls.clear();
    source = NativeDeviceLocation(
      approvedAccuracyLimitMeters: 10,
      now: () => clock,
      acquisitionTimeout: const Duration(milliseconds: 1),
    );
    final pending = Completer<Object?>();
    reply = () => pending.future;
    expect((await source.locate()).status, LocationStatus.unavailable);
    expect(calls.any((c) => c.method == 'cancelAcquisition'), true);
    pending.complete(sample());
  });
  test('route sources have distinct native owners', () async {
    await source.requestPermission();
    final other = NativeDeviceLocation();
    await other.requestPermission();
    expect(
      calls
          .where((c) => c.method == 'requestPermission')
          .map((c) => (c.arguments as Map)['owner_id'])
          .toSet()
          .length,
      2,
    );
    await other.close();
  });
  for (final required in [false, true]) {
    test(
      'policy location-required=$required controls permission interaction',
      () async {
        final api = ApiFake()
          ..contents = [
            {
              ...contentJson(),
              if (required) ...{
                'Latitude': 26.37,
                'Longitude': -80.1,
                'RadiusMeters': 500,
              },
            },
          ];
        final account = api.session();
        await account.login('synthetic-user', 'fixture-password');
        await account.refresh();
        final provider = ApiViewingConditions(
          account,
          7,
          locationSource: source,
        );
        await provider.requestLocationPermission();
        expect(calls.any((c) => c.method == 'requestPermission'), required);
        expect(
          api.calls.where((c) => c.uri.path.endsWith('/sessions')),
          isEmpty,
        );
        provider.dispose();
        account.dispose();
      },
    );
  }
  test(
    'missing production accuracy rule prevents collection and API open',
    () async {
      await source.close();
      calls.clear();
      source = NativeDeviceLocation();
      final api = ApiFake()
        ..contents = [
          {
            ...contentJson(),
            'Latitude': 26.37,
            'Longitude': -80.1,
            'RadiusMeters': 500,
          },
        ];
      final account = api.session();
      await account.login('synthetic-user', 'fixture-password');
      await account.refresh();
      final provider = ApiViewingConditions(
        account,
        7,
        identityReady: () => true,
        locationSource: source,
      );
      final result = await provider.check(ContentRestrictions.demoDefaults);
      expect(result[ViewingCondition.location], ViewingConditionResult.failed);
      expect(
        provider.message,
        contains('accuracy requirement has not been approved'),
      );
      expect(
        calls.where(
          (c) => c.method == 'locate' || c.method == 'requestPermission',
        ),
        isEmpty,
      );
      expect(api.calls.where((c) => c.uri.path.endsWith('/sessions')), isEmpty);
      provider.dispose();
      account.dispose();
    },
  );
  test(
    'ended session closes pending permission and drops late grant',
    () async {
      final api = ApiFake()
        ..contents = [
          {
            ...contentJson(),
            'Latitude': 26.37,
            'Longitude': -80.1,
            'RadiusMeters': 500,
          },
        ];
      final account = api.session();
      await account.login('synthetic-user', 'fixture-password');
      await account.refresh();
      final provider = ApiViewingConditions(account, 7, locationSource: source);
      permissionReply = Completer<Object?>();
      final wait = provider.requestLocationPermission();
      await tick();
      provider.endSession();
      await tick();
      permissionReply!.complete('granted');
      await wait;
      expect(provider.locationPermissionPending, false);
      expect(provider.canRequestLocationPermission, false);
      expect(calls.any((c) => c.method == 'close'), true);
      provider.dispose();
      account.dispose();
    },
  );
}
