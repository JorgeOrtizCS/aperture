import 'dart:async';

import 'package:aperture/models/api_models.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_session.dart';
import 'package:aperture/services/api_viewing_conditions.dart';
import 'package:aperture/services/device_location.dart';
import 'package:aperture/services/device_registration.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';

// Synthetic location/device/HTTP fixtures. No GPS permissions or sockets used.
class _Location implements DeviceLocationSource {
  Future<LocationReading> Function() reply;
  int calls = 0;
  _Location(this.reply);
  @override
  Future<LocationReading> locate() {
    calls++;
    return reply();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiFake fake;
  late ApiSession account;
  late ApiViewingConditions conditions;
  late DeviceRegistration registration;
  late _Location location;
  late DateTime clock;
  bool ended = false;
  bool identity = true;

  Map<String, Object?> row({bool gps = true, bool device = false}) => {
    ...contentJson(),
    if (gps) ...{'Latitude': 26.37, 'Longitude': -80.1, 'RadiusMeters': 500},
    'RequireTrustedDevice': device,
  };
  LocationReading fresh() => LocationReading(
    LocationStatus.granted,
    LocationFix(26.37, -80.1, clock, horizontalAccuracyMeters: 3),
  );
  Future<void> prepare({bool gps = true, bool device = false}) async {
    fake.contents = [row(gps: gps, device: device)];
    await account.refresh();
    conditions = ApiViewingConditions(
      account,
      7,
      identityReady: () => identity,
      locationSource: location,
      now: () => clock,
    );
  }

  Future<Map<String, ViewingConditionResult>> check() =>
      conditions.check(ContentRestrictions.demoDefaults);
  Iterable<ApiCall> viewingCalls() => fake.calls.where(
    (c) => c.uri.path.endsWith('/sessions') || c.uri.path.endsWith('/check'),
  );

  setUp(() async {
    clock = DateTime.utc(2026, 11, 5);
    ended = false;
    identity = true;
    fake = ApiFake();
    account = fake.session();
    await account.login('synthetic-user', 'fixture-password');
    location = _Location(() async => fresh());
    await prepare();
    registration = DeviceRegistration(account, sessionEnded: () => ended);
  });
  tearDown(() {
    registration.dispose();
    conditions.dispose();
    account.dispose();
  });

  test(
    'fresh policy-required fixes use exact GPS headers on open and check',
    () async {
      expect(
        (await check()).values.every(
          (v) => v == ViewingConditionResult.satisfied,
        ),
        true,
      );
      clock = clock.add(const Duration(seconds: 1));
      await check();
      expect(location.calls, 2);
      expect(viewingCalls().length, 2);
      for (final call in viewingCalls()) {
        expect(call.headers['X-Client-Latitude'], '26.37');
        expect(call.headers['X-Client-Longitude'], '-80.1');
      }
      expect(viewingCalls().first.json['CameraPolicyVersion'], 0);
    },
  );

  test(
    'location-free policy never accesses location or sends coordinates',
    () async {
      conditions.dispose();
      await prepare(gps: false);
      await check();
      expect(location.calls, 0);
      expect(
        viewingCalls().single.headers.keys.where(
          (k) => k.startsWith('X-Client'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'unverified biometrics never request location or authorization',
    () async {
      identity = false;
      await check();
      expect(location.calls, 0);
      expect(viewingCalls(), isEmpty);
    },
  );

  for (final status in [
    LocationStatus.denied,
    LocationStatus.permanentlyDenied,
    LocationStatus.unavailable,
    LocationStatus.stale,
  ]) {
    test('location $status fails closed without an API open', () async {
      location.reply = () async => LocationReading(status);
      final result = await check();
      expect(result[ViewingCondition.location], ViewingConditionResult.failed);
      expect(
        result[ViewingCondition.authorization],
        ViewingConditionResult.unknown,
      );
      expect(conditions.message, contains('hidden'));
      expect(viewingCalls(), isEmpty);
    });
  }

  for (final sample in ['missing', 'old', 'future', 'nan', 'range']) {
    test('rejects $sample location without sending it', () async {
      location.reply = () async =>
          LocationReading(LocationStatus.granted, switch (sample) {
            'missing' => null,
            'old' => LocationFix(
              26.37,
              -80.1,
              clock.subtract(const Duration(seconds: 1)),
            ),
            'future' => LocationFix(
              26.37,
              -80.1,
              clock.add(const Duration(seconds: 1)),
            ),
            'nan' => LocationFix(double.nan, -80.1, clock),
            _ => LocationFix(91, -80.1, clock),
          });
      expect(
        (await check())[ViewingCondition.location],
        ViewingConditionResult.failed,
      );
      expect(viewingCalls(), isEmpty);
    });
  }

  test(
    'previous successful coordinates cannot satisfy the next check',
    () async {
      final previous = fresh();
      await check();
      clock = clock.add(const Duration(seconds: 1));
      location.reply = () async => previous;
      expect(
        (await check())[ViewingCondition.location],
        ViewingConditionResult.failed,
      );
      expect(viewingCalls().length, 1);
    },
  );

  test(
    'location exceptions are unavailable, not a successful permission',
    () async {
      location.reply = () async => throw StateError('synthetic failure');
      expect(
        (await check())[ViewingCondition.location],
        ViewingConditionResult.failed,
      );
      expect(conditions.message, contains('unavailable'));
    },
  );

  test('default production location source is unavailable', () async {
    conditions.dispose();
    conditions = ApiViewingConditions(account, 7, identityReady: () => true);
    expect(
      (await check())[ViewingCondition.location],
      ViewingConditionResult.failed,
    );
    expect(viewingCalls(), isEmpty);
  });

  test('permission restoration still needs a fresh server check', () async {
    location.reply = () async => const LocationReading(LocationStatus.denied);
    await check();
    location.reply = () async => fresh();
    expect(
      (await check())[ViewingCondition.authorization],
      ViewingConditionResult.satisfied,
    );
    expect(viewingCalls().length, 1);
  });

  test(
    'termination while location is pending prevents a network open',
    () async {
      final pending = Completer<LocationReading>();
      location.reply = () => pending.future;
      final request = check();
      conditions.endSession();
      pending.complete(fresh());
      expect(
        (await request).values,
        everyElement(ViewingConditionResult.denied),
      );
      expect(viewingCalls(), isEmpty);
    },
  );

  test(
    'biometric revocation during location acquisition prevents an open',
    () async {
      final pending = Completer<LocationReading>();
      location.reply = () => pending.future;
      final request = check();
      identity = false;
      pending.complete(fresh());
      await request;
      expect(viewingCalls(), isEmpty);
    },
  );

  test(
    'location expires during a pending API response and cannot grant',
    () async {
      fake.routes['/api/content/7/sessions'] = (_) async {
        clock = clock.add(const Duration(seconds: 6));
        return jsonReply(accessJson());
      };
      final result = await check();
      expect(result[ViewingCondition.location], ViewingConditionResult.failed);
      expect(
        result[ViewingCondition.authorization],
        ViewingConditionResult.unknown,
      );
    },
  );

  test(
    'late API success after termination is discarded and cleaned up',
    () async {
      final pending = Completer<ApiReply>();
      fake.routes['/api/content/7/sessions'] = (_) => pending.future;
      final request = check();
      await Future<void>.delayed(Duration.zero);
      conditions.endSession();
      pending.complete(jsonReply(accessJson()));
      expect(
        (await request).values,
        everyElement(ViewingConditionResult.denied),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fake.calls.any((c) => c.uri.path.endsWith('/end')), true);
      expect(
        (await check()).values,
        everyElement(ViewingConditionResult.denied),
      );
    },
  );

  test(
    'required device approval cannot be replaced by a server grant flag',
    () async {
      conditions.dispose();
      await prepare(gps: false, device: true);
      expect(
        (await check())[ViewingCondition.device],
        ViewingConditionResult.denied,
      );
      fake.routes['/api/content/7/sessions'] = (_) =>
          jsonReply({...accessJson(), 'DeviceVerified': true});
      expect(
        (await check())[ViewingCondition.authorization],
        ViewingConditionResult.denied,
      );
    },
  );

  test('required device approval is checked in the session response', () async {
    conditions.dispose();
    await prepare(gps: false, device: true);
    fake.routes['/api/content/7/sessions'] = (_) =>
        jsonReply({...accessJson(), 'DeviceVerified': true});
    expect(
      (await check())[ViewingCondition.device],
      ViewingConditionResult.satisfied,
    );
  });

  test(
    'policy metadata cannot remove an already-required location gate',
    () async {
      fake.contents = [row(gps: false)];
      await account.refresh();
      expect(
        conditions.requiredConditions,
        contains(ViewingCondition.location),
      );
    },
  );

  for (final value in [null, 'invalid', double.nan]) {
    test('partial or invalid precise policy is rejected: $value', () {
      expect(
        () => ApiContent.fromJson({
          ...contentJson(),
          'Latitude': value,
          'Longitude': -80.1,
        }),
        throwsA(isA<ApiException>()),
      );
    });
  }

  for (final trusted in [false, true]) {
    test(
      'registration uses documented fields and server trusted=$trusted',
      () async {
        fake.routes['/api/devices'] = (_) => jsonReply({'trusted': trusted});
        await registration.register('  Synthetic phone  ');
        final call = fake.calls.singleWhere(
          (c) => c.uri.path == '/api/devices',
        );
        expect(call.method, 'POST');
        expect(call.json, {
          'DeviceKey': account.deviceKey,
          'DeviceName': 'Synthetic phone',
        });
        expect(registration.trusted, trusted);
        expect(registration.pending, false);
        expect(viewingCalls(), isEmpty);
      },
    );
  }

  for (final code in [400, 401, 403, 404, 500]) {
    test('registration HTTP $code never establishes trust', () async {
      fake.routes['/api/devices'] = (_) => ApiReply(code, '{}');
      await registration.register('Synthetic phone');
      expect(registration.trusted, isNull);
      expect(registration.pending, false);
      expect(account.authenticated, code != 401);
    });
  }

  for (final body in [
    'not-json',
    '{}',
    '{"trusted":"true"}',
    '{"trusted":null}',
  ]) {
    test(
      'malformed registration acknowledgement fails closed: $body',
      () async {
        fake.routes['/api/devices'] = (_) => ApiReply(200, body);
        await registration.register('Synthetic phone');
        expect(registration.trusted, isNull);
        expect(registration.message, contains('unexpected'));
      },
    );
  }

  test('registration network failure is reported without trust', () async {
    fake.routes['/api/devices'] = (_) =>
        throw const ApiException(ApiFailure.network);
    await registration.register('Synthetic phone');
    expect(registration.message, contains('could not be reached'));
    expect(registration.trusted, isNull);
  });

  test(
    'invalid device name is rejected without a registration request',
    () async {
      await registration.register(' ');
      expect(fake.calls.where((c) => c.uri.path == '/api/devices'), isEmpty);
      expect(registration.trusted, isNull);
    },
  );

  test('concurrent registration is deduplicated; cancellation ignores late approval', () async {
    final pending = Completer<ApiReply>();
    fake.routes['/api/devices'] = (_) => pending.future;
    final first = registration.register('Synthetic phone');
    await registration.register('Synthetic phone');
    expect(fake.calls.where((c) => c.uri.path == '/api/devices').length, 1);
    registration.cancel();
    pending.complete(jsonReply({'trusted': true}));
    await first;
    expect(registration.trusted, isNull);
    expect(registration.message, contains('unconfirmed'));
  });

  test(
    'cancelled registration cannot overwrite a replacement request',
    () async {
      final pending = Completer<ApiReply>();
      fake.routes['/api/devices'] = (_) => pending.future;
      final first = registration.register('Old synthetic phone');
      registration.cancel();
      fake.routes['/api/devices'] = (_) => jsonReply({'trusted': false});
      await registration.register('New synthetic phone');
      pending.complete(jsonReply({'trusted': true}));
      await first;
      expect(registration.trusted, false);
    },
  );

  test('logout during registration discards late approval', () async {
    final pending = Completer<ApiReply>();
    fake.routes['/api/devices'] = (_) => pending.future;
    final first = registration.register('Synthetic phone');
    await account.logout();
    pending.complete(jsonReply({'trusted': true}));
    await first;
    expect(registration.trusted, isNull);
    expect(account.authenticated, false);
  });

  test('ended viewing session ignores pending device approval', () async {
    final pending = Completer<ApiReply>();
    fake.routes['/api/devices'] = (_) => pending.future;
    final first = registration.register('Synthetic phone');
    ended = true;
    pending.complete(jsonReply({'trusted': true}));
    await first;
    expect(registration.trusted, isNull);
    expect(viewingCalls(), isEmpty);
  });

  test(
    'new local evaluation cannot reuse a pending old location request',
    () async {
      final old = Completer<LocationReading>();
      location.reply = () => old.future;
      final previous = check();
      conditions.invalidateLocalChecks();
      clock = clock.add(const Duration(seconds: 1));
      location.reply = () async => fresh();
      expect(
        (await check())[ViewingCondition.authorization],
        ViewingConditionResult.satisfied,
      );
      old.complete(fresh());
      expect(
        (await previous).values,
        everyElement(ViewingConditionResult.denied),
      );
      expect(location.calls, 2);
      expect(viewingCalls().length, 1);
    },
  );

  test(
    'old open response cannot replace a new evaluation or close its session',
    () async {
      final old = Completer<ApiReply>();
      fake.routes['/api/content/7/sessions'] = (_) => old.future;
      final previous = check();
      await Future<void>.delayed(Duration.zero);
      conditions.invalidateLocalChecks();
      clock = clock.add(const Duration(seconds: 1));
      fake.routes['/api/content/7/sessions'] = (_) =>
          jsonReply(accessJson(id: 42));
      expect(
        (await check())[ViewingCondition.authorization],
        ViewingConditionResult.satisfied,
      );
      old.complete(jsonReply(accessJson(id: 41)));
      expect(
        (await previous).values,
        everyElement(ViewingConditionResult.denied),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        fake.calls.any((c) => c.uri.path == '/api/content/sessions/41/end'),
        true,
      );
      expect(
        fake.calls.any((c) => c.uri.path == '/api/content/sessions/42/end'),
        false,
      );
      fake.routes['/api/content/sessions/42/check'] = (_) =>
          jsonReply(accessJson(id: 42));
      expect(
        (await check())[ViewingCondition.authorization],
        ViewingConditionResult.satisfied,
      );
    },
  );

  test(
    'superseded polling completion cannot publish into a new evaluation',
    () async {
      conditions.dispose();
      final timers = <_ManualTimer>[];
      conditions = ApiViewingConditions(
        account,
        7,
        identityReady: () => true,
        locationSource: location,
        now: () => clock,
        schedule: (duration, callback) {
          final timer = _ManualTimer(duration, callback);
          timers.add(timer);
          return timer;
        },
      );
      await check();
      final changes = <Map<String, ViewingConditionResult>>[];
      final sub = conditions.changes.listen(changes.add);
      final old = Completer<ApiReply>();
      fake.routes['/api/content/sessions/41/check'] = (_) => old.future;
      timers
          .singleWhere((t) => t.duration == const Duration(seconds: 3))
          .fire();
      await Future<void>.delayed(Duration.zero);
      conditions.invalidateLocalChecks();
      fake.routes['/api/content/sessions/41/check'] = (_) =>
          jsonReply(accessJson());
      expect(
        (await check())[ViewingCondition.authorization],
        ViewingConditionResult.satisfied,
      );
      old.complete(jsonReply(accessJson()));
      await Future<void>.delayed(Duration.zero);
      expect(changes, isEmpty);
      expect(fake.calls.where((c) => c.uri.path.endsWith('/end')), isEmpty);
      await sub.cancel();
    },
  );

  test('location expiry publishes a mandatory unknown state', () async {
    conditions.dispose();
    final timers = <_ManualTimer>[];
    conditions = ApiViewingConditions(
      account,
      7,
      identityReady: () => true,
      locationSource: location,
      now: () => clock,
      schedule: (duration, callback) {
        final timer = _ManualTimer(duration, callback);
        timers.add(timer);
        return timer;
      },
    );
    final changes = <Map<String, ViewingConditionResult>>[];
    final sub = conditions.changes.listen(changes.add);
    await check();
    timers.singleWhere((t) => t.duration == const Duration(seconds: 5)).fire();
    expect(
      changes.last[ViewingCondition.location],
      ViewingConditionResult.unknown,
    );
    await sub.cancel();
  });

  test('restored location cannot reopen a server-terminated session', () async {
    fake.routes['/api/content/7/sessions'] = (_) =>
        jsonReply(accessJson(granted: false, ended: true));
    await check();
    final calls = location.calls;
    fake.routes['/api/content/7/sessions'] = (_) => jsonReply(accessJson());
    expect((await check()).values, everyElement(ViewingConditionResult.denied));
    expect(location.calls, calls);
  });

  test('registration timeout never confirms device approval', () async {
    registration.dispose();
    conditions.dispose();
    account.dispose();
    account = fake.session(timeout: const Duration(milliseconds: 5));
    await account.login('synthetic-user', 'fixture-password');
    await prepare();
    registration = DeviceRegistration(account, sessionEnded: () => ended);
    final pending = Completer<ApiReply>();
    fake.routes['/api/devices'] = (_) => pending.future;
    await registration.register('Synthetic phone');
    expect(registration.message, contains('timed out'));
    expect(registration.trusted, isNull);
    pending.complete(jsonReply({'trusted': true}));
    await Future<void>.delayed(Duration.zero);
    expect(registration.trusted, isNull);
  });
}

class _ManualTimer implements Timer {
  final Duration duration;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  _ManualTimer(this.duration, this.callback);
  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }

  @override
  void cancel() => isActive = false;
}
