import 'dart:async';
import 'dart:math' as math;

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/models/api_models.dart';
import 'package:aperture/models/location_radius_policy.dart';
import 'package:aperture/screens/api_content_screens.dart';
import 'package:aperture/screens/viewing_requirements_screen.dart';
import 'package:aperture/services/api_session.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_viewing_conditions.dart';
import 'package:aperture/services/device_location.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/services/viewing_conditions.dart';
import 'package:aperture/widgets/biometric_status_panel.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:aperture/widgets/location_area_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';
import 'support/biometric_fake.dart';
import 'support/viewing_test_fakes.dart';

// Synthetic policy centers, measurements, identity, camera/capture and HTTP.
// No native acceptance, real location or real protected content is claimed.
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
  final clock = DateTime.utc(2026, 11, 6);
  const zone = LocationZone(0, 0, 100);
  LocationFix fix({
    double distance = 0,
    double? accuracy = 3,
    DateTime? time,
  }) => LocationFix(
    distance / LocationRadiusPolicy.earthRadiusMeters * 180 / math.pi,
    0,
    time ?? clock,
    horizontalAccuracyMeters: accuracy,
  );
  Map<String, Object?> row({
    double radius = 100,
    double latitude = 0,
    bool device = false,
  }) => {
    ...contentJson(),
    'Latitude': latitude,
    'Longitude': 0,
    'RadiusMeters': radius,
    'RequireTrustedDevice': device,
  };

  for (final preset in LocationRadiusPreset.values.where(
    (p) => p.meters != null,
  )) {
    test(
      'preset ${preset.meters} meters is valid and accepts a precise center fix',
      () {
        final draft = SenderLocationDraft(
          enabled: true,
          latitude: '0',
          longitude: '0',
          preset: preset,
        );
        expect(draft.valid, true);
        expect(draft.zone!.radiusMeters, preset.meters);
        expect(
          LocationRadiusPolicy.evaluate(
            draft.zone,
            fix(),
            clock,
            clock,
            const Duration(seconds: 5),
          ),
          LocationZoneResult.accepted,
        );
      },
    );
  }
  test('sender default is 100 meters with location initially off and no invented center', () {
    const draft = SenderLocationDraft();
    expect(draft.preset, LocationRadiusPreset.building);
    expect(draft.radiusMeters, 100);
    expect(draft.enabled, false);
    expect(draft.zone, null);
  });
  for (final input in [
    '',
    '9.999',
    '10000.001',
    '-10',
    'NaN',
    'Infinity',
    '1e309',
    'abc',
  ]) {
    test('custom radius rejects $input', () {
      final draft = SenderLocationDraft(
        enabled: true,
        latitude: '0',
        longitude: '0',
        preset: LocationRadiusPreset.custom,
        customRadius: input,
      );
      expect(draft.valid, false);
      expect(draft.zone, null);
    });
  }
  for (final input in ['10', '10.5', '100', '10000']) {
    test('custom radius accepts $input', () {
      expect(
        SenderLocationDraft(
          enabled: true,
          latitude: '0',
          longitude: '0',
          preset: LocationRadiusPreset.custom,
          customRadius: input,
        ).valid,
        true,
      );
    });
  }
  for (final lat in ['', '91', 'NaN', 'Infinity']) {
    test('invalid center $lat cannot be saved', () {
      expect(
        SenderLocationDraft(enabled: true, latitude: lat, longitude: '0').valid,
        false,
      );
    });
  }
  for (final sample in <(double, double?, double, bool)>[
    (20, 5, 100, true),
    (90, 10, 100, true),
    (90.0001, 10, 100, false),
    (0, 100, 100, true),
    (0, 100.001, 1000, false),
    (5, 6, 10, false),
    (0, 11, 10, false),
    (100, 0, 100, true),
    (101, 0, 100, false),
    (0, null, 100, false),
    (0, -1, 100, false),
    (0, double.nan, 100, false),
    (0, double.infinity, 100, false),
    (double.nan, 3, 100, false),
    (-1, 3, 100, false),
    (0, 3, double.infinity, false),
  ]) {
    test(
      'boundary distance=${sample.$1} uncertainty=${sample.$2} radius=${sample.$3}',
      () {
        expect(
          LocationRadiusPolicy.acceptsDistance(sample.$1, sample.$2, sample.$3),
          sample.$4,
        );
      },
    );
  }
  test('geodesic near-boundary fixes include their uncertainty without a tolerance', () {
    expect(
      LocationRadiusPolicy.evaluate(
        zone,
        fix(distance: 89.9, accuracy: 10),
        clock,
        clock,
        const Duration(seconds: 5),
      ),
      LocationZoneResult.accepted,
    );
    expect(
      LocationRadiusPolicy.evaluate(
        zone,
        fix(distance: 90.1, accuracy: 10),
        clock,
        clock,
        const Duration(seconds: 5),
      ),
      LocationZoneResult.outside,
    );
  });
  test('great-circle calculation handles the antimeridian', () {
    const area = LocationZone(0, 179.999, 500);
    final sample = LocationFix(0, -179.999, clock, horizontalAccuracyMeters: 3);
    expect(
      LocationRadiusPolicy.distanceMeters(area, sample),
      closeTo(222.39, .1),
    );
  });
  test('confirmed list status changes retain the server zone without logging its center', () {
    final item = ApiContent.fromJson(row(radius: 500));
    expect(
      item.confirmed(policyStatus: 'Paused').locationZone,
      const LocationZone(0, 0, 500),
    );
    expect(item.locationZone.toString(), 'LocationZone(redacted)');
  });
  test('stale and future measurements cannot satisfy the circle', () {
    for (final offset in [-1, 1]) {
      expect(
        LocationRadiusPolicy.evaluate(
          zone,
          fix(time: clock.add(Duration(seconds: offset))),
          clock,
          clock,
          const Duration(seconds: 5),
        ),
        LocationZoneResult.stale,
      );
    }
    expect(
      LocationRadiusPolicy.evaluate(
        zone,
        fix(),
        clock,
        clock.add(const Duration(seconds: 5)),
        const Duration(seconds: 5),
      ),
      LocationZoneResult.stale,
    );
  });

  group('real authorization provider with synthetic inputs', () {
    late ApiFake api;
    late ApiSession account;
    late ApiViewingConditions provider;
    late _Location location;
    bool identity = true;
    setUp(() async {
      api = ApiFake()..contents = [row()];
      account = api.session();
      await account.login('synthetic-user', 'fixture-password');
      await account.refresh();
      identity = true;
      location = _Location(
        () async => LocationReading(LocationStatus.granted, fix()),
      );
      provider = ApiViewingConditions(
        account,
        7,
        locationSource: location,
        identityReady: () => identity,
        now: () => clock,
      );
    });
    tearDown(() {
      provider.dispose();
      account.dispose();
    });
    Future<Map<String, ViewingConditionResult>> check() =>
        provider.check(ContentRestrictions.demoDefaults);
    Iterable<ApiCall> opens() =>
        api.calls.where((c) => c.uri.path.endsWith('/sessions'));

    test('inside reading still requires a separate server grant and sends only existing headers', () async {
      expect(
        (await check()).values.every(
          (v) => v == ViewingConditionResult.satisfied,
        ),
        true,
      );
      expect(opens().single.headers['X-Client-Latitude'], '0.0');
      expect(
        opens().single.headers.keys.where((h) => h.contains('Accuracy')),
        isEmpty,
      );
    });
    for (final accuracy in [null, -1.0, double.nan, double.infinity, 100.001]) {
      test(
        'provider rejects untrusted accuracy $accuracy before API open',
        () async {
          location.reply = () async =>
              LocationReading(LocationStatus.granted, fix(accuracy: accuracy));
          expect(
            (await check())[ViewingCondition.location],
            ViewingConditionResult.failed,
          );
          expect(opens(), isEmpty);
        },
      );
    }
    test(
      'provider rejects uncertainty crossing the circle before API open',
      () async {
        location.reply = () async => LocationReading(
          LocationStatus.granted,
          fix(distance: 95, accuracy: 10),
        );
        expect(
          (await check())[ViewingCondition.location],
          ViewingConditionResult.failed,
        );
        expect(opens(), isEmpty);
      },
    );
    for (final status in [
      LocationStatus.denied,
      LocationStatus.permanentlyDenied,
      LocationStatus.stale,
    ]) {
      test('provider preserves $status failure', () async {
        location.reply = () async => LocationReading(status);
        expect(
          (await check())[ViewingCondition.location],
          ViewingConditionResult.failed,
        );
        expect(opens(), isEmpty);
      });
    }
    test('successful local check cannot override backend denial', () async {
      api.routes['/api/content/7/sessions'] = (_) =>
          jsonReply(accessJson(granted: false, ended: true));
      expect(
        (await check())[ViewingCondition.authorization],
        ViewingConditionResult.denied,
      );
      api.routes.clear();
      expect(
        (await check())[ViewingCondition.authorization],
        ViewingConditionResult.denied,
      );
      expect(opens().length, 1);
    });
    test(
      'successful local check cannot override missing device approval',
      () async {
        api.contents = [row(device: true)];
        await account.refresh();
        expect(
          (await check())[ViewingCondition.device],
          ViewingConditionResult.denied,
        );
      },
    );
    test('unverified identity does not acquire a reading', () async {
      identity = false;
      await check();
      expect(location.calls, 0);
      expect(opens(), isEmpty);
    });
    for (final radius in [9.0, 10001.0]) {
      test(
        'unsupported prototype radius $radius cannot collect or open',
        () async {
          api.contents = [row(radius: radius)];
          await account.refresh();
          expect(
            (await check())[ViewingCondition.location],
            ViewingConditionResult.failed,
          );
          expect(location.calls, 0);
          expect(opens(), isEmpty);
        },
      );
    }
    test(
      'conflicting server zones cannot silently choose an easier area',
      () async {
        api.contents = [row(), row(latitude: 1)];
        await account.refresh();
        expect(
          (await check())[ViewingCondition.location],
          ViewingConditionResult.failed,
        );
        expect(location.calls, 0);
        expect(opens(), isEmpty);
      },
    );
    test('changed policy invalidates an in-flight grant and closes its orphan session', () async {
      final pending = Completer<ApiReply>();
      api.routes['/api/content/7/sessions'] = (_) => pending.future;
      final result = check();
      await Future<void>.delayed(Duration.zero);
      expect(opens().length, 1);
      api.contents = [row(latitude: 1)];
      await account.refresh();
      pending.complete(jsonReply(accessJson()));
      expect(
        (await result)[ViewingCondition.authorization],
        ViewingConditionResult.denied,
      );
      await Future<void>.delayed(Duration.zero);
      expect(api.calls.any((c) => c.uri.path.endsWith('/41/end')), true);
      api.routes.clear();
      expect(
        (await check())[ViewingCondition.location],
        ViewingConditionResult.failed,
      );
    });
    test('removed zone remains mandatory and fails closed without collecting again', () async {
      await check();
      final before = location.calls;
      api.contents = [contentJson()];
      await account.refresh();
      expect(
        (await check())[ViewingCondition.location],
        ViewingConditionResult.failed,
      );
      expect(provider.requiredConditions, contains(ViewingCondition.location));
      expect(location.calls, before);
    });
    test('termination rejects a delayed location result', () async {
      final pending = Completer<LocationReading>();
      location.reply = () => pending.future;
      final result = check();
      provider.endSession();
      pending.complete(LocationReading(LocationStatus.granted, fix()));
      expect(
        (await result)[ViewingCondition.authorization],
        ViewingConditionResult.denied,
      );
      expect(opens(), isEmpty);
    });
  });

  testWidgets(
    'sender editor shows default, small-area warning and custom validation',
    (tester) async {
      var draft = const SenderLocationDraft(
        enabled: true,
        latitude: '0',
        longitude: '0',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (_, set) => LocationAreaEditor(
                  draft: draft,
                  onChanged: (value) => set(() => draft = value),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Selected radius: 100.0 m'), findsOneWidget);
      expect(
        find.textContaining('Small areas can be difficult'),
        findsOneWidget,
      );
      final picker = find.byKey(const ValueKey('location-radius-preset'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom radius: 10–10,000 m').last);
      await tester.pumpAndSettle();
      final custom = find.byKey(const ValueKey('location-custom-radius'));
      await tester.enterText(custom, '9');
      await tester.pump();
      expect(draft.valid, false);
      await tester.enterText(custom, '10000');
      await tester.pump();
      expect(draft.valid, true);
      expect(find.text('Selected radius: 10000.0 m'), findsOneWidget);
    },
  );
  testWidgets('incomplete enabled area disables saving the sender draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ViewingRequirementsScreen(
          initialRestrictions: ContentRestrictions(
            allowDownload: false,
            allowResharing: false,
            restrictScreenshots: true,
            accessDuration: AccessDuration.twoDays,
            locationArea: SenderLocationDraft(enabled: true),
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Save'))
          .onPressed,
      null,
    );
  });

  for (final violation in ['none', 'camera', 'capture']) {
    testWidgets(
      'actual recipient route keeps $violation independent of a passed radius',
      (tester) async {
        final native = NativeCaptureFake()..install();
        final biometric = BiometricFake();
        final api = ApiFake()..contents = [row()];
        final account = api.session();
        await account.login('synthetic-user', 'fixture-password');
        await account.refresh();
        final location = _Location(
          () async => LocationReading(
            LocationStatus.granted,
            LocationFix(0, 0, DateTime.now(), horizontalAccuracyMeters: 3),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ApiRecipientScreen(
              account: account,
              contentId: 7,
              biometricAuthenticator: biometric,
              cameraDetection: native.camera.service,
              captureProtection: ScreenCaptureProtection.forTesting(),
              locationSource: location,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final controller = tester
            .widget<BiometricStatusPanel>(find.byType(BiometricStatusPanel))
            .controller;
        unawaited(controller.verifyIdentity());
        await flushViewing(tester);
        expect(controller.state, ViewingState.allowed);
        final open = find.text('Open security checks');
        await tester.scrollUntilVisible(
          open,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(open);
        await tester.tap(open);
        await flushViewing(tester);
        expect(
          find.byKey(
            const ValueKey('protected-render-placeholder'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        if (violation == 'camera') {
          native.camera.event(phone: true);
        }
        if (violation == 'capture') {
          native.setCapture(true);
        }
        await flushViewing(tester);
        if (violation != 'none') {
          expect(controller.state, isNot(ViewingState.allowed));
          unawaited(controller.verifyIdentity());
          await flushViewing(tester);
          expect(controller.state, isNot(ViewingState.allowed));
        }
        expect(
          find.byKey(
            const ValueKey('protected-render-placeholder'),
            skipOffstage: false,
          ),
          violation == 'none' ? findsOneWidget : findsNothing,
        );
        expect(find.text('SYNTHETIC PAYLOAD MUST NOT RENDER'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await flushViewing(tester);
        account.dispose();
      },
    );
  }
}
