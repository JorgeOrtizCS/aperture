import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_session.dart';
import 'package:aperture/services/api_viewing_conditions.dart';
import 'package:aperture/services/camera_detection.dart';
import 'package:aperture/services/device_location.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:aperture/widgets/recipient_png_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';
import 'support/biometric_fake.dart';
import 'support/png_fixture.dart';
import 'support/viewing_test_fakes.dart';

final _pixels = find.byType(RawImage, skipOffstage: false);
const _checkPath = '/api/content/sessions/41/check';
const _loading = 'Loading image…';

ApiReply _grant() => jsonReply({
  ...accessJson()
    ..remove('Body')
    ..remove('FileType'),
  'DeviceVerified': true,
});

RecipientPngPayload _payload(Uint8List bytes) =>
    RecipientPngPayload(contentType: 'image/png', bytes: bytes);

class _LocationFixture implements ForegroundDeviceLocationSource {
  _LocationFixture(this.now);
  final DateTime Function() now;
  bool inside = true;
  int closes = 0;

  @override
  Future<LocationReading> locate() async => LocationReading(
    LocationStatus.granted,
    LocationFix(
      inside ? 26.37 : 26.39,
      -80.1,
      now().toUtc(),
      horizontalAccuracyMeters: 8,
    ),
  );

  @override
  Future<void> cancelAcquisition() async {}

  @override
  Future<void> close() async => closes++;

  @override
  Future<LocationPermissionState> requestPermission() async =>
      LocationPermissionState.granted;
}

/// Test-only delivery owner. Real account, API condition and controller logic
/// consume socket-free HTTP, identity and native-channel fixtures. The test
/// explicitly offers generated PNGs; the authorization DTO never supplies bytes.
class _SyntheticSession {
  _SyntheticSession(this.tester);
  final WidgetTester tester;
  final api = ApiFake();
  final native = NativeCaptureFake();
  final input = ValueNotifier<RecipientPngRequest?>(null);
  late final ApiSession account;
  late final int owner;
  late final ApiViewingConditions conditions;
  late final ViewingStateController controller;
  late final CameraDetectionSession camera;
  late final _LocationFixture location;
  bool _mounted = false;

  DateTime now() => tester.binding.clock.now();

  bool get canOffer =>
      account.authenticated &&
      account.identityVersion == owner &&
      controller.state == ViewingState.allowed &&
      controller.biometrics.approved &&
      camera.state == CameraDetectionState.monitoring;

  Future<void> mount({bool needsLocation = false}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    native.install();
    api.contents = [
      {
        ...contentJson(),
        'RequireTrustedDevice': true,
        if (needsLocation) ...{
          'Latitude': 26.37,
          'Longitude': -80.1,
          'RadiusMeters': 500,
        },
      },
    ];
    api.routes['/api/content/7/sessions'] = (_) => _grant();
    api.routes[_checkPath] = (_) => _grant();
    account = api.session();
    await account.login('synthetic-user', 'fixture-password');
    await account.refresh();
    owner = account.identityVersion;
    location = _LocationFixture(now);
    conditions = ApiViewingConditions(
      account,
      7,
      identityReady: () => controller.biometrics.approved,
      locationSource: location,
      now: now,
    );
    controller = ViewingStateController(
      restrictions: ContentRestrictions.demoDefaults,
      conditions: conditions,
      protection: ScreenCaptureProtection.forTesting(),
      biometricAuthenticator: BiometricFake(),
    )..addListener(_withdrawIfDenied);
    camera = native.camera.service.createSession()..addListener(_cameraChanged);
    account.addListener(_withdrawIfDenied);
    _mounted = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Synthetic lifecycle test only')),
          body: RecipientPngRenderer(input: input),
        ),
      ),
    );
    await verify();
    unawaited(camera.start());
    await flushViewing(tester);
    expect(canOffer, isTrue);
    expect(_pixels, findsNothing); // An eligible session cannot load by itself.
  }

  Future<void> close() async {
    if (!_mounted) return;
    await tester.pumpWidget(const SizedBox.shrink());
    account.removeListener(_withdrawIfDenied);
    camera.dispose();
    controller.dispose();
    conditions.dispose();
    input.dispose();
    await flushViewing(tester);
    account.dispose();
  }

  Future<void> verify() async {
    unawaited(controller.verifyIdentity());
    await flushViewing(tester);
  }

  Future<void> recheck() async {
    unawaited(controller.revalidate(verifyIdentity: false));
    await flushViewing(tester);
  }

  void _withdrawIfDenied() {
    if (!canOffer) input.value = null;
  }

  void _cameraChanged() {
    if (camera.state == CameraDetectionState.phoneDetected) {
      controller.endForSecurityViolation(
        reason: ViewingIssueKind.phoneDetected,
      );
    }
    _withdrawIfDenied();
  }

  void offer(Future<RecipientPngPayload> Function() load) {
    expect(canOffer, isTrue);
    input.value = RecipientPngRequest(load);
  }

  Future<ui.Image> render() async {
    final bytes = pngFixture();
    offer(() async => _payload(bytes));
    await until(() => _pixels.evaluate().isNotEmpty);
    expect(bytes, everyElement(0));
    return tester.widget<RawImage>(_pixels).image!;
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200; i++) {
      await tester.pump();
      if (done()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(done(), isTrue);
  }

  Future<void> expectWithdrawn(ui.Image image, {required bool ended}) async {
    await tester.idle();
    await tester.pump();
    expect(input.value, isNull);
    expect(_pixels, findsNothing);
    expect(find.bySemanticsLabel('Shared PNG image'), findsNothing);
    expect(image.debugDisposed, isTrue);
    expect(image.debugGetOpenHandleStackTraces(), isEmpty);
    expect(controller.state, isNot(ViewingState.allowed));
    expect(controller.sessionEnded, ended);
  }
}

void _lifecycleTest(
  String name,
  Future<void> Function(WidgetTester, _SyntheticSession) test,
) {
  testWidgets(name, (tester) async {
    final h = _SyntheticSession(tester);
    try {
      await test(tester, h);
    } finally {
      await h.close();
    }
  });
}

void main() {
  _lifecycleTest('phone violation removes decoded pixels and latches the end', (
    tester,
    h,
  ) async {
    await h.mount();
    final image = await h.render();
    h.native.camera.event(phone: true);
    await h.expectWithdrawn(image, ended: true);
    expect(h.controller.violationReason, ViewingIssueKind.phoneDetected);
    expect(h.controller.biometrics.approved, isFalse);
    await h.verify();
    expect(h.canOffer, isFalse);
  });

  _lifecycleTest(
    'required location failure removes pixels despite verified identity',
    (tester, h) async {
      await h.mount(needsLocation: true);
      final image = await h.render();
      h.location.inside = false;
      await tester.pump(const Duration(seconds: 3));
      await h.expectWithdrawn(image, ended: false);
      expect(h.controller.biometrics.approved, isTrue);
      expect(h.conditions.message, contains('fit inside'));
      expect(h.api.calls.where((call) => call.uri.path == _checkPath), isEmpty);
      h.location.inside = true;
      await h.recheck();
      expect(h.canOffer, isTrue);
      expect(_pixels, findsNothing); // A fresh source is still required.
      await h.render();
    },
  );

  _lifecycleTest(
    'biometric revocation withdraws pixels without a camera failure',
    (tester, h) async {
      await h.mount();
      final image = await h.render();
      h.controller.revokeIdentity();
      await h.expectWithdrawn(image, ended: false);
      expect(h.camera.state, CameraDetectionState.monitoring);
      expect(h.controller.captureState, CaptureProtectionState.ready);
      await h.verify();
      expect(h.canOffer, isTrue);
      expect(_pixels, findsNothing);
    },
  );

  _lifecycleTest(
    'active capture withdraws pixels; capture stop alone cannot restore',
    (tester, h) async {
      await h.mount();
      final image = await h.render();
      h.native.setCapture(true);
      await h.expectWithdrawn(image, ended: false);
      expect(h.controller.captureState, CaptureProtectionState.captureActive);
      h.native.setCapture(false);
      await tester.pump();
      expect(h.canOffer, isFalse);
      expect(_pixels, findsNothing);
      await h.recheck();
      expect(h.canOffer, isTrue);
      expect(_pixels, findsNothing);
    },
  );

  _lifecycleTest(
    'screenshot termination wipes a pending payload before any decode',
    (tester, h) async {
      await h.mount();
      final pending = Completer<RecipientPngPayload>();
      h.offer(() => pending.future);
      await tester.pump();
      expect(find.text(_loading), findsOneWidget);
      h.native.events!.success({'type': 'screenshot'});
      await tester.idle();
      expect(h.controller.sessionEnded, isTrue);
      expect(h.controller.violationReason, ViewingIssueKind.screenshot);
      expect(h.input.value, isNull);
      final late = pngFixture();
      pending.complete(_payload(late));
      await tester.pump();
      expect(find.text(_loading), findsNothing);
      expect(late, everyElement(0));
      expect(_pixels, findsNothing);
      expect(h.location.closes, 1);
      expect(
        h.api.calls.where((c) => c.uri.path.endsWith('/41/end')),
        hasLength(1),
      );
    },
  );

  _lifecycleTest(
    'account replacement withdraws old pixels before new sign-in',
    (tester, h) async {
      await h.mount();
      final image = await h.render();
      h.api.userId = 2;
      h.api.username = 'replacement';
      h.api.token = 'replacement-token';
      final signingIn = h.account.login('replacement', 'fixture-password');
      expect(h.input.value, isNull);
      expect(image.debugDisposed, isTrue);
      await signingIn;
      await h.expectWithdrawn(image, ended: true);
      expect(h.account.user!.id, 2);
      expect(h.account.identityVersion, isNot(h.owner));
      expect(h.canOffer, isFalse);
      final end = h.api.calls.singleWhere(
        (c) => c.uri.path.endsWith('/41/end'),
      );
      expect(end.headers['Authorization'], 'Bearer synthetic-opaque-token');
    },
  );

  _lifecycleTest(
    'server expiry withdraws pixels and cannot be rechecked into access',
    (tester, h) async {
      await h.mount();
      final image = await h.render();
      final expiry = h.now().add(const Duration(seconds: 1));
      h.api.routes[_checkPath] = (_) => h.now().isBefore(expiry)
          ? _grant()
          : jsonReply(accessJson(granted: false, ended: true));
      await tester.pump(const Duration(seconds: 3));
      await h.expectWithdrawn(image, ended: true);
      h.api.routes[_checkPath] = (_) => _grant();
      final calls = h.api.calls.length;
      await h.controller.revalidate();
      expect(h.api.calls, hasLength(calls));
      expect(h.canOffer, isFalse);
    },
  );

  _lifecycleTest(
    'poll timeout withdraws pixels and late success cannot restore them',
    (tester, h) async {
      await h.mount();
      final image = await h.render();
      final late = Completer<ApiReply>();
      h.api.routes[_checkPath] = (_) => late.future;
      await tester.pump(const Duration(seconds: 3)); // Dispatch poll.
      h.native.camera.event(); // Keep the camera healthy independently.
      await tester.idle();
      await tester.pump(const Duration(seconds: 4)); // Request timeout.
      await h.expectWithdrawn(image, ended: false);
      expect(h.conditions.message, contains('timed out'));
      expect(h.camera.state, CameraDetectionState.monitoring);
      late.complete(_grant());
      await tester.pump();
      expect(h.canOffer, isFalse);
      expect(_pixels, findsNothing);
      h.api.routes[_checkPath] = (_) => _grant();
      await h.recheck();
      final next = await h.render();
      h.api.routes[_checkPath] = (_) => const ApiReply(403, '');
      h.native.camera.event();
      await tester.idle();
      await tester.pump(const Duration(seconds: 3));
      await h.expectWithdrawn(next, ended: true);
    },
  );

  _lifecycleTest(
    'withdrawal at engine decode completion disposes the stale frame',
    (tester, h) async {
      await h.mount();
      final bytes = pngFixture();
      ui.Image? decoded;
      final original = ui.Image.onCreate;
      try {
        ui.Image.onCreate = (image) {
          original?.call(image);
          if (decoded == null && image.width == 2 && image.height == 1) {
            decoded = image;
            h.controller.revokeIdentity();
          }
        };
        h.offer(() async => _payload(bytes));
        await h.until(() => decoded?.debugDisposed == true);
      } finally {
        ui.Image.onCreate = original;
      }
      expect(h.input.value, isNull);
      expect(_pixels, findsNothing);
      expect(decoded!.debugGetOpenHandleStackTraces(), isEmpty);
      expect(bytes, everyElement(0));
    },
  );
}
