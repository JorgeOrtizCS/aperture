import 'dart:async';
import 'dart:convert';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/models/api_models.dart';
import 'package:aperture/screens/api_content_screens.dart';
import 'package:aperture/services/access_status.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_session.dart';
import 'package:aperture/services/api_viewing_conditions.dart';
import 'package:aperture/services/biometric_verification.dart';
import 'package:aperture/services/device_location.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:aperture/widgets/biometric_status_panel.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:aperture/widgets/recipient_png_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';
import 'support/biometric_fake.dart';
import 'support/png_fixture.dart';
import 'support/viewing_test_fakes.dart';

// Actual API recipient/preflight/content widgets and security services.
// HTTP/native/identity inputs are deterministic fixtures, NOT live acceptance.
final _protected = find.byKey(
  const ValueKey('protected-render-placeholder'),
  skipOffstage: false,
);

class _PendingLocation implements ForegroundDeviceLocationSource {
  final reading = Completer<LocationReading>();
  int acquisitions = 0, cancellations = 0, closes = 0;

  @override
  Future<LocationReading> locate() {
    acquisitions++;
    return reading.future;
  }

  @override
  Future<void> cancelAcquisition() async => cancellations++;

  @override
  Future<void> close() async => closes++;

  @override
  Future<LocationPermissionState> requestPermission() async =>
      LocationPermissionState.granted;
}

class _ApiFlow {
  final WidgetTester tester;
  _ApiFlow(this.tester) {
    all.add(this);
  }
  static final all = <_ApiFlow>[];
  bool _hasAccount = false;
  final fake = ApiFake();
  final native = NativeCaptureFake();
  final biometric = BiometricFake();
  late ApiSession account;
  late ViewingStateController controller;
  ApiViewingConditions get conditions =>
      controller.conditions as ApiViewingConditions;

  Future<void> mount({
    bool verify = true,
    bool open = false,
    bool deviceKey = true,
    DeviceLocationSource? location,
    Map<String, Object?> metadata = const {},
  }) async {
    native.install();
    fake.contents = [
      {
        ...contentJson(),
        ...metadata,
        if (location != null) ...{
          'Latitude': 26.37,
          'Longitude': -80.1,
          'RadiusMeters': 500,
        },
      },
    ];
    account = deviceKey ? fake.session() : fake.session(deviceKey: null);
    _hasAccount = true;
    await account.login('synthetic-user', 'fixture-password');
    await account.refresh();
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
    final panel = find.byType(BiometricStatusPanel);
    if (panel.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        panel,
        140,
        scrollable: find.byType(Scrollable).first,
      );
    }
    controller = tester.widget<BiometricStatusPanel>(panel).controller;
    expect(_protected, findsNothing);
    expect(find.text('Open Demo Preview'), findsNothing);
    if (verify) {
      unawaited(controller.verifyIdentity());
      await flushViewing(tester);
    }
    if (open) {
      expect(controller.state, ViewingState.allowed);
      await tap('Open security checks');
      await flushViewing(tester);
      expect(_protected, findsOneWidget);
    }
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await flushViewing(tester);
    if (_hasAccount) account.dispose();
  }

  Future<void> tap(String text) async {
    final target = find.text(text);
    if (target.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(
        target,
        160,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }
}

void apiWidgets(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      while (_ApiFlow.all.isNotEmpty) {
        await _ApiFlow.all.removeLast().close();
      }
    }
  });
}

void main() {
  apiWidgets(
    'API grant still requires identity/capture/camera; payload never renders',
    (tester) async {
      final f = _ApiFlow(tester);
      final legacyPngGrant = jsonReply({
        ...accessJson(),
        'FileType': 'image/png',
        'FileDataBase64': base64Encode(pngFixture()),
      });
      f.fake.routes['/api/content/7/sessions'] = (_) => legacyPngGrant;
      f.fake.routes['/api/content/sessions/41/check'] = (_) => legacyPngGrant;
      await f.mount(open: true);
      expect(find.byType(RawImage, skipOffstage: false), findsNothing);
      expect(
        find.byType(RecipientPngRenderer, skipOffstage: false),
        findsNothing,
      );
      expect(find.text('Protected display unavailable'), findsOneWidget);
      expect(
        find.textContaining('server granted access for this check'),
        findsOneWidget,
      );
      expect(f.controller.biometrics.approved, isTrue);
      expect(f.controller.captureState, CaptureProtectionState.ready);
      expect(f.native.camera.starts, 1);
      expect(find.text('SYNTHETIC PAYLOAD MUST NOT RENDER'), findsNothing);
      final opens = f.fake.calls
          .where((c) => c.uri.path.endsWith('/sessions'))
          .toList();
      expect(opens.length, 1);
      expect(opens.single.json['CameraPolicyVersion'], 0);
      expect(f.fake.calls.any((c) => c.uri.path.endsWith('/check')), isTrue);
      expect(f.fake.calls.map((c) => c.uri.path).toSet(), {
        '/api/auth/login',
        '/api/user/me',
        '/api/content',
        '/api/content/7/sessions',
        '/api/content/sessions/41/check',
      });
    },
  );

  apiWidgets('unverified local identity prevents server open', (tester) async {
    final f = _ApiFlow(tester);
    await f.mount(verify: false);
    unawaited(f.controller.revalidate());
    await flushViewing(tester);
    expect(
      f.fake.calls.where((c) => c.uri.path.endsWith('/sessions')),
      isEmpty,
    );
    expect(f.controller.state, isNot(ViewingState.allowed));
    expect(_protected, findsNothing);
  });

  apiWidgets('missing device requirement fails closed without an open', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    await f.mount(deviceKey: false);
    expect(f.controller.biometrics.approved, isTrue);
    expect(f.controller.state, isNot(ViewingState.allowed));
    expect(
      f.fake.calls.where((c) => c.uri.path.endsWith('/sessions')),
      isEmpty,
    );
    expect(f.conditions.message, contains('test device key'));
    expect(_protected, findsNothing);
  });

  apiWidgets('HTTP 403 and 200 denial both permanently block server access', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    f.fake.routes['/api/content/7/sessions'] = (_) =>
        const ApiReply(403, 'denied');
    await f.mount();
    expect(f.controller.sessionEnded, isTrue);
    expect(f.controller.biometrics.approved, isFalse);
    expect(_protected, findsNothing);
    expect(
      find.textContaining('The server denied this access check.'),
      findsOneWidget,
    );
    expect(find.text('Content expired'), findsNothing);
    expect(find.text('View limit reached'), findsNothing);
    f.fake.routes['/api/content/7/sessions'] = (_) => jsonReply(accessJson());
    await f.controller.verifyIdentity();
    await f.controller.revalidate();
    await flushViewing(tester);
    expect(f.controller.sessionEnded, isTrue);
    expect(_protected, findsNothing);
  });

  apiWidgets('source policy refusal explains the unopened viewing window', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    f.fake.routes['/api/content/7/sessions'] = (_) => jsonReply({
      ...accessJson(granted: false, id: 0),
      'Message': 'Access has not begun.',
      'FileDataBase64': 'synthetic refusal payload',
    }, 403);
    await f.mount();
    expect(f.controller.sessionEnded, isTrue);
    expect(f.controller.biometrics.approved, isFalse);
    expect(
      find.textContaining('viewing window has not opened'),
      findsOneWidget,
    );
    expect(find.textContaining('synthetic refusal payload'), findsNothing);
    expect(_protected, findsNothing);
  });

  apiWidgets(
    'recipient can review listed policy and gets a typed network location refusal',
    (tester) async {
      final f = _ApiFlow(tester);
      await f.mount(
        verify: false,
        metadata: {
          'StartTime': '2026-11-05T12:00:00Z',
          'ExpiresAt': '2026-11-06T12:00:00Z',
          'MaxViews': 3,
          'RequireTrustedDevice': true,
          'ScreenshotRestriction': true,
          'AllowedCountry': 'US',
          'AllowedRegion': 'Example Region',
        },
      );
      await f.tap('Review listed viewing policy');
      expect(find.textContaining('Listed viewing start'), findsOneWidget);
      expect(find.text('Listed maximum views: 3'), findsOneWidget);
      expect(
        find.textContaining('Service-approved device required'),
        findsOneWidget,
      );
      expect(
        find.text('Listed screenshot restriction: Required'),
        findsOneWidget,
      );
      expect(
        find.text('Listed network location: US, Example Region'),
        findsOneWidget,
      );
      expect(
        f.fake.calls.where((call) => call.uri.path.endsWith('/sessions')),
        isEmpty,
      );
      f.fake.routes['/api/content/7/sessions'] = (_) => jsonReply({
        ...accessJson(granted: false, id: 0),
        'Message': 'State/region restriction was not satisfied.',
      }, 403);
      unawaited(f.controller.verifyIdentity());
      await flushViewing(tester);
      expect(f.controller.sessionEnded, isTrue);
      expect(f.conditions.message, contains('network location did not meet'));
      expect(
        f.fake.calls
            .singleWhere((call) => call.uri.path.endsWith('/sessions'))
            .headers
            .containsKey('X-Client-Latitude'),
        isFalse,
      );
      expect(_protected, findsNothing);
    },
  );

  apiWidgets(
    'a listed policy change invalidates a pending open and ends its late session',
    (tester) async {
      final f = _ApiFlow(tester);
      await f.mount(verify: false, metadata: {'MaxViews': 5});
      final pending = Completer<ApiReply>();
      f.fake.routes['/api/content/7/sessions'] = (_) => pending.future;
      unawaited(f.controller.verifyIdentity());
      await flushViewing(tester);
      f.fake.contents = [
        {...contentJson(), 'MaxViews': 2},
      ];
      await f.account.refresh();
      await flushViewing(tester);
      pending.complete(jsonReply(accessJson()));
      await flushViewing(tester);
      expect(f.controller.state, isNot(ViewingState.allowed));
      expect(f.conditions.sessionId, isNull);
      expect(
        f.fake.calls.where(
          (call) => call.uri.path == '/api/content/sessions/41/end',
        ),
        hasLength(1),
      );
      expect(_protected, findsNothing);
      await f.tap('Review listed viewing policy');
      expect(find.text('Listed maximum views: 2'), findsOneWidget);
    },
  );

  apiWidgets('source 403 expiry ends the session and requires reopening', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    await f.mount(open: true);
    f.fake.routes['/api/content/sessions/41/check'] = (_) => jsonReply({
      ...accessJson(granted: false, ended: true, id: 0),
      'Message': 'Session expired; open the content again.',
    }, 403);
    await tester.pump(const Duration(seconds: 3));
    await flushViewing(tester);
    expect(f.controller.sessionEnded, isTrue);
    expect(
      find.textContaining(
        'The server reported that this viewing session expired.',
      ),
      findsOneWidget,
    );
    expect(find.text('Recheck Conditions'), findsNothing);
    expect(find.byType(RecipientPngRenderer), findsNothing);
  });

  apiWidgets('server session missing gives recovery without guessing expiry', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    await f.mount(open: true);
    f.fake.routes['/api/content/sessions/41/check'] = (_) =>
        const ApiReply(404, 'opaque expiry or access detail');
    await tester.pump(const Duration(seconds: 3));
    await flushViewing(tester);
    expect(f.controller.sessionEnded, isTrue);
    expect(
      find.textContaining(
        'The session may have expired or access may have changed.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('opaque expiry'), findsNothing);
    expect(find.text('Content expired'), findsNothing);
    expect(find.text('Recheck Conditions'), findsNothing);
    expect(find.text('Protected display unavailable'), findsOneWidget);
  });

  apiWidgets('a pending open cannot publish access to a replacement account', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    await f.mount(verify: false);
    final pending = Completer<ApiReply>();
    f.fake.routes['/api/content/7/sessions'] = (_) => pending.future;
    unawaited(f.controller.verifyIdentity());
    await flushViewing(tester);
    expect(
      find.text('Waiting for the server access decision.'),
      findsOneWidget,
    );
    final logout = f.account.logout();
    f.fake.userId = 2;
    f.fake.username = 'replacement-user';
    f.fake.token = 'replacement-token';
    f.fake.contents = [contentJson(title: 'Replacement account share')];
    await f.account.login('replacement-user', 'fixture-only');
    await f.account.refresh();
    pending.complete(jsonReply(accessJson()));
    await logout;
    await flushViewing(tester);
    expect(find.text('Content unavailable to this account.'), findsOneWidget);
    expect(find.text('Replacement account share'), findsNothing);
    expect(find.textContaining('server granted access'), findsNothing);
    expect(_protected, findsNothing);
    final end = f.fake.calls.singleWhere((c) => c.uri.path.endsWith('/41/end'));
    expect(end.headers['Authorization'], 'Bearer synthetic-opaque-token');
  });

  apiWidgets('server revocation on poll hides an already authorized fixture', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    await f.mount(open: true);
    f.fake.routes['/api/content/sessions/41/check'] = (_) =>
        jsonReply(accessJson(granted: false, ended: true));
    await tester.pump(const Duration(seconds: 3));
    await flushViewing(tester);
    expect(_protected, findsNothing);
    expect(f.controller.sessionEnded, isTrue);
    expect(f.controller.biometrics.approved, isFalse);
    expect(f.fake.calls.any((c) => c.uri.path.endsWith('/end')), isTrue);
  });

  apiWidgets('terminal policy denial releases camera and capture before Back', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    await f.mount(open: true);
    f.fake.routes['/api/content/sessions/41/check'] = (_) =>
        const ApiReply(403, '');
    await tester.pump(const Duration(seconds: 3));
    await flushViewing(tester);
    expect(_protected, findsNothing);
    expect(f.controller.sessionEnded, isTrue);
    expect(f.native.camera.stops, 1);
    expect(f.native.disables, 1);
    expect(
      f.fake.calls.where((c) => c.uri.path.endsWith('/41/end')),
      hasLength(1),
    );
  });

  apiWidgets('logout ends an established session with its original account', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    await f.mount(open: true);
    final pending = Completer<ApiReply>();
    f.fake.routes['/api/content/sessions/41/check'] = (_) => pending.future;
    final check = f.conditions.check(ContentRestrictions.demoDefaults);
    await f.account.logout();
    pending.complete(jsonReply(accessJson()));
    await check;
    await flushViewing(tester);
    expect(_protected, findsNothing);
    expect(f.controller.sessionEnded, isTrue);
    final end = f.fake.calls.singleWhere((c) => c.uri.path.endsWith('/41/end'));
    expect(end.headers['Authorization'], 'Bearer synthetic-opaque-token');
    expect(f.native.camera.stops, 1);
  });

  apiWidgets('network loss hides content until an explicit fresh recheck', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    await f.mount(open: true);
    f.fake.routes['/api/content/sessions/41/check'] = (_) =>
        throw const ApiException(ApiFailure.network);
    await tester.pump(const Duration(seconds: 3));
    await flushViewing(tester);
    expect(_protected, findsNothing);
    expect(f.controller.sessionEnded, isFalse);
    expect(f.controller.canRecheck, isTrue);
    expect(find.textContaining('Check your connection'), findsOneWidget);
    f.fake.routes.remove('/api/content/sessions/41/check');
    f.native.camera.event(); // Keep the independent camera watchdog healthy.
    await tester.pump(const Duration(seconds: 3));
    await flushViewing(tester);
    expect(_protected, findsNothing);
    unawaited(f.controller.revalidate());
    await flushViewing(tester);
    expect(_protected, findsOneWidget);
  });

  apiWidgets('Back releases the camera and pauses policy polling', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    await f.mount(open: true);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await flushViewing(tester);
    expect(_protected, findsNothing);
    expect(f.native.camera.stops, 1);
    expect(f.native.disables, 1);
    expect(f.controller.biometrics.approved, isFalse);
    final requests = f.fake.calls.length;
    await tester.pump(const Duration(seconds: 10));
    expect(f.fake.calls, hasLength(requests));
  });

  apiWidgets(
    'server suspension does not relax existing permanent mobile denials',
    (tester) async {
      final f = _ApiFlow(tester);
      await f.mount(open: true);
      f.fake.routes['/api/content/sessions/41/check'] = (_) =>
          jsonReply(accessJson(granted: false, suspended: true));
      await tester.pump(const Duration(seconds: 3));
      await flushViewing(tester);
      expect(_protected, findsNothing);
      expect(f.controller.sessionEnded, isTrue);
      expect(
        f.conditions.message,
        contains('mobile viewing session has ended'),
      );
      f.fake.routes['/api/content/sessions/41/check'] = (_) =>
          jsonReply(accessJson());
      await f.controller.revalidate();
      expect(f.controller.sessionEnded, isTrue);
    },
  );

  apiWidgets(
    'camera-required unexpected grant is rejected rather than advertising support',
    (tester) async {
      final f = _ApiFlow(tester);
      f.fake.routes['/api/content/7/sessions'] = (_) {
        final j = accessJson();
        (j['CameraRestrictions'] as Map)['Enabled'] = true;
        return jsonReply(j);
      };
      await f.mount();
      expect(f.controller.sessionEnded, isTrue);
      expect(f.native.camera.starts, 0);
      expect(_protected, findsNothing);
      expect(
        find.textContaining(
          'This app cannot verify a required viewing policy.',
        ),
        findsOneWidget,
      );
    },
  );

  apiWidgets('malformed mandatory access fields never authorize content', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    f.fake.routes['/api/content/7/sessions'] = (_) =>
        jsonReply({'AccessGranted': true, 'SessionId': 41});
    await f.mount();
    expect(f.controller.state, isNot(ViewingState.allowed));
    expect(_protected, findsNothing);
    expect(f.conditions.message, contains('unexpected response'));
  });

  apiWidgets(
    'network failure hides and later success cannot override capture latch',
    (tester) async {
      final f = _ApiFlow(tester);
      await f.mount(open: true);
      f.fake.routes['/api/content/sessions/41/check'] = (_) =>
          throw StateError('synthetic network failure');
      await tester.pump(const Duration(seconds: 3));
      await flushViewing(tester);
      expect(_protected, findsNothing);
      expect(f.controller.sessionEnded, isFalse);
      f.native.setCapture(true);
      await flushViewing(tester);
      f.fake.routes['/api/content/sessions/41/check'] = (_) =>
          jsonReply(accessJson());
      await f.conditions.check(ContentRestrictions.demoDefaults);
      await f.controller.verifyIdentity();
      await flushViewing(tester);
      expect(f.controller.captureState, CaptureProtectionState.captureActive);
      expect(_protected, findsNothing);
    },
  );

  apiWidgets(
    'phone violation wins over a simultaneous pending successful response',
    (tester) async {
      final f = _ApiFlow(tester);
      await f.mount(open: true);
      final pending = Completer<ApiReply>();
      f.fake.routes['/api/content/sessions/41/check'] = (_) => pending.future;
      final checking = f.conditions.check(ContentRestrictions.demoDefaults);
      f.native.camera.event(phone: true);
      await tester.idle();
      await tester.pump();
      expect(_protected, findsNothing);
      expect(f.controller.sessionEnded, isTrue);
      pending.complete(jsonReply(accessJson()));
      await checking;
      await flushViewing(tester);
      expect(_protected, findsNothing);
      expect(f.controller.violationReason, ViewingIssueKind.phoneDetected);
      expect(f.controller.biometrics.approved, isFalse);
    },
  );

  apiWidgets(
    'termination during pending open rejects late success and attempts session cleanup',
    (tester) async {
      final f = _ApiFlow(tester);
      final pending = Completer<ApiReply>();
      f.fake.routes['/api/content/7/sessions'] = (_) => pending.future;
      await f.mount();
      expect(f.controller.state, ViewingState.checking);
      f.controller.endForSecurityViolation(reason: ViewingIssueKind.screenshot);
      pending.complete(jsonReply(accessJson()));
      await flushViewing(tester);
      expect(_protected, findsNothing);
      expect(f.controller.sessionEnded, isTrue);
      expect(f.native.camera.starts, 0);
      expect(f.fake.calls.any((c) => c.uri.path.endsWith('/41/end')), isTrue);
    },
  );

  apiWidgets(
    'background during pending authorization requires fresh identity',
    (tester) async {
      final f = _ApiFlow(tester);
      final pending = Completer<ApiReply>();
      f.fake.routes['/api/content/7/sessions'] = (_) => pending.future;
      await f.mount();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete(jsonReply(accessJson()));
      await flushViewing(tester);
      expect(_protected, findsNothing);
      expect(f.controller.biometrics.approved, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flushViewing(tester);
      expect(f.controller.state, isNot(ViewingState.allowed));
      expect(_protected, findsNothing);
    },
  );

  apiWidgets('background cancels location and disposal closes it once', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    final location = _PendingLocation();
    await f.mount(location: location);
    expect(location.acquisitions, 1);
    final previous = location.cancellations;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(location.cancellations, previous + 1);
    location.reading.complete(
      LocationReading(
        LocationStatus.granted,
        LocationFix(
          26.37,
          -80.1,
          DateTime.now().toUtc(),
          horizontalAccuracyMeters: 3,
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flushViewing(tester);
    expect(
      f.fake.calls.where((c) => c.uri.path.endsWith('/sessions')),
      isEmpty,
    );
    expect(f.controller.biometrics.approved, isFalse);
    expect(_protected, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await flushViewing(tester);
    expect(location.closes, 1);
  });

  apiWidgets('cancelled pending biometric request never issues server open', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    f.biometric.pending = Completer<BiometricState>();
    await f.mount();
    expect(f.controller.biometrics.state, BiometricState.verifying);
    f.biometric.pending!.complete(BiometricState.cancelled);
    await flushViewing(tester);
    expect(_protected, findsNothing);
    expect(
      f.fake.calls.where((c) => c.uri.path.endsWith('/sessions')),
      isEmpty,
    );
  });

  apiWidgets(
    'logout during open discards old-user grant and closes orphan session',
    (tester) async {
      final f = _ApiFlow(tester);
      final pending = Completer<ApiReply>();
      f.fake.routes['/api/content/7/sessions'] = (_) => pending.future;
      await f.mount();
      final logout = f.account.logout();
      expect(f.account.authenticated, isFalse);
      f.fake.userId = 2;
      f.fake.username = 'replacement';
      f.fake.token = 'replacement-token';
      await f.account.login('replacement', 'synthetic-only');
      pending.complete(jsonReply(accessJson()));
      await flushViewing(tester);
      await logout;
      expect(f.controller.sessionEnded, isTrue);
      expect(_protected, findsNothing);
      expect(f.account.items, isEmpty);
      expect(f.account.user!.id, 2);
      final end = f.fake.calls
          .where((c) => c.uri.path.endsWith('/41/end'))
          .single;
      expect(end.headers['Authorization'], 'Bearer synthetic-opaque-token');
    },
  );
  apiWidgets(
    'content request timeout hides and late success cannot authorize',
    (tester) async {
      final f = _ApiFlow(tester);
      final pending = Completer<ApiReply>();
      f.fake.routes['/api/content/7/sessions'] = (_) => pending.future;
      await f.mount();
      await tester.pump(const Duration(seconds: 4));
      await flushViewing(tester);
      expect(f.controller.state, isNot(ViewingState.allowed));
      expect(_protected, findsNothing);
      expect(f.conditions.message, contains('timed out'));
      pending.complete(jsonReply(accessJson()));
      await flushViewing(tester);
      expect(_protected, findsNothing);
      expect(f.native.camera.starts, 0);
    },
  );

  apiWidgets('revoked listing wins over an older successful check', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    await f.mount(open: true);
    final pending = Completer<ApiReply>();
    f.fake.routes['/api/content/sessions/41/check'] = (_) => pending.future;
    final old = f.conditions.check(ContentRestrictions.demoDefaults);
    f.fake.contents = [contentJson(status: 'Revoked')];
    await f.account.refresh();
    await flushViewing(tester);
    expect(_protected, findsNothing);
    expect(f.controller.sessionEnded, isTrue);
    pending.complete(jsonReply(accessJson()));
    await old;
    await flushViewing(tester);
    expect(_protected, findsNothing);
    expect(f.controller.sessionEnded, isTrue);
  });

  for (final (change, contents) in [
    ('drops the item', <Map<String, Object?>>[]),
    ('becomes owner-only', [contentJson(mine: true)]),
    ('confirms a sender pause', [contentJson(policy: 'Paused')]),
  ]) {
    apiWidgets('recipient listing $change while the secure viewer is open', (
      tester,
    ) async {
      final f = _ApiFlow(tester);
      await f.mount(open: true);
      final pending = Completer<ApiReply>();
      f.fake.routes['/api/content/sessions/41/check'] = (_) => pending.future;
      final old = f.conditions.check(ContentRestrictions.demoDefaults);

      f.fake.contents = contents;
      await f.account.refresh();
      await flushViewing(tester);
      expect(_protected, findsNothing);
      expect(f.controller.sessionEnded, isTrue);
      expect(f.controller.biometrics.approved, isFalse);
      expect(f.native.camera.stops, 1);
      expect(f.native.disables, 1);
      expect(
        f.account.accessStatuses.entries.map((status) => status.kind),
        isNot(contains(AccessStatusKind.accessGranted)),
      );
      expect(
        f.fake.calls.where((c) => c.uri.path.endsWith('/41/end')),
        hasLength(1),
      );

      pending.complete(jsonReply(accessJson()));
      await old;
      f.fake.contents = [contentJson()];
      await f.account.refresh();
      await flushViewing(tester);
      expect(_protected, findsNothing);
      expect(f.controller.sessionEnded, isTrue);
    });
  }

  apiWidgets('mismatched server session ID fails closed', (tester) async {
    final f = _ApiFlow(tester);
    await f.mount(open: true);
    f.fake.routes['/api/content/sessions/41/check'] = (_) =>
        jsonReply(accessJson(id: 42));
    await tester.pump(const Duration(seconds: 3));
    await flushViewing(tester);
    expect(_protected, findsNothing);
    expect(f.conditions.message, contains('unexpected response'));
    expect(
      f.fake.calls.where((c) => c.uri.path.endsWith('/sessions')).length,
      1,
    );
  });
  apiWidgets('a contradictory unverified location grant remains locked', (
    tester,
  ) async {
    final f = _ApiFlow(tester);
    f.fake.routes['/api/content/7/sessions'] = (_) =>
        jsonReply(accessJson()..['LocationVerified'] = false);
    await f.mount();
    expect(f.controller.state, isNot(ViewingState.allowed));
    expect(_protected, findsNothing);
    expect(f.native.camera.starts, 0);
    expect(f.fake.calls.any((c) => c.uri.path.endsWith('/41/end')), isTrue);
  });
  for (final flag in ['SessionEnded', 'Suspended']) {
    apiWidgets(
      'terminal server flag $flag dominates contradictory grant fields',
      (tester) async {
        final f = _ApiFlow(tester);
        await f.mount(open: true);
        f.fake.routes['/api/content/sessions/41/check'] = (_) =>
            jsonReply(accessJson()..[flag] = true);
        await tester.pump(const Duration(seconds: 3));
        await flushViewing(tester);
        expect(_protected, findsNothing);
        expect(f.controller.sessionEnded, isTrue);
        f.fake.routes['/api/content/sessions/41/check'] = (_) =>
            jsonReply(accessJson());
        await f.controller.revalidate();
        await flushViewing(tester);
        expect(f.controller.sessionEnded, isTrue);
        expect(_protected, findsNothing);
      },
    );
  }
}
