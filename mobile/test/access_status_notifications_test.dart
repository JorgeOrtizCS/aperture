import 'dart:async';

import 'package:aperture/controllers/viewing_state_controller.dart';
import 'package:aperture/screens/api_content_screens.dart';
import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/screens/notifications_screen.dart';
import 'package:aperture/services/access_status.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_session.dart';
import 'package:aperture/services/biometric_verification.dart';
import 'package:aperture/services/device_location.dart';
import 'package:aperture/services/native_device_location.dart';
import 'package:aperture/services/screen_capture_protection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';
import 'support/biometric_fake.dart';
import 'support/viewing_test_fakes.dart';

const _check = '/api/content/sessions/41/check';
const _open = '/api/content/7/sessions';
const _allowLocation = 'Allow location for viewing';

class _Location
    implements ForegroundDeviceLocationSource, DeviceLocationPermissionStatus {
  LocationPermissionState status = LocationPermissionState.notDetermined;
  Completer<LocationPermissionState>? pending;
  int prompts = 0, fixes = 0;

  @override
  Future<LocationPermissionState> readPermission() async => status;

  @override
  Future<LocationPermissionState> requestPermission() async {
    prompts++;
    return pending?.future ?? status;
  }

  @override
  Future<LocationReading> locate() async {
    fixes++;
    return const LocationReading(LocationStatus.unavailable);
  }

  @override
  Future<void> cancelAcquisition() async {}

  @override
  Future<void> close() async {}
}

class _Flow {
  _Flow(this.tester);
  final WidgetTester tester;
  final fake = ApiFake();
  final native = NativeCaptureFake();
  final biometric = BiometricFake();
  final navigator = GlobalKey<NavigatorState>();
  late final ApiSession account = fake.session();
  late final ViewingStateController controller;

  Set<AccessStatusKind> get kinds =>
      account.accessStatuses.entries.map((notice) => notice.kind).toSet();

  Future<void> login() => account.login('synthetic-user', 'synthetic-only');

  Future<void> mountRecipient({
    _Location? location,
    bool nativeLocation = false,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    native.install();
    fake.contents = [
      {
        ...contentJson(title: 'Private fixture filename.png'),
        if (location != null || nativeLocation) ...{
          'Latitude': 26.37,
          'Longitude': -80.1,
          'RadiusMeters': 500,
        },
      },
    ];
    await login();
    await account.refresh();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
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
    await flushViewing(tester);
    controller = tester
        .widget<SecureViewerScreen>(find.byType(SecureViewerScreen))
        .viewingController!;
  }

  Future<void> verify() async {
    unawaited(controller.verifyIdentity());
    await flushViewing(tester);
  }

  Future<void> tap(String text) async {
    final target = find.text(text);
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        140,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(target);
    await tester.tap(target);
    await flushViewing(tester);
    await tester.pumpAndSettle();
  }

  Future<void> notices() async {
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => NotificationsScreen(account: account),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void lifecycle(AppLifecycleState state) =>
      tester.binding.handleAppLifecycleStateChanged(state);

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await flushViewing(tester);
    account.dispose();
    lifecycle(AppLifecycleState.resumed);
  }
}

void _test(String name, Future<void> Function(_Flow) body) {
  testWidgets(name, (tester) async {
    final flow = _Flow(tester);
    try {
      await body(flow);
    } finally {
      await flow.close();
    }
  });
}

void main() {
  _test(
    'dashboard notifications reflect confirmed listings without preview data',
    (f) async {
      final tester = f.tester;
      f.fake.contents = [
        contentJson(
          id: 7,
          mine: true,
          policy: 'Paused',
          title: 'private-title.png',
        ),
        contentJson(id: 8, status: 'Revoked', policy: 'Paused'),
        contentJson(id: 9, mine: true, policy: 'Paused'),
        {
          ...contentJson(id: 10),
          'ExpiresAt': '2026-11-05T00:00:00Z',
          'FileDataBase64': 'secret-png-preview',
        },
        {...contentJson(id: 11), 'ExpiresAt': 'unknown'},
        {...contentJson(id: 12), 'ExpiresAt': '2026-11-06T00:00:00Z'},
      ];
      await f.login();
      await tester.pumpWidget(
        MaterialApp(home: ApiDashboardScreen(account: f.account)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(find.text('Content paused'), findsOneWidget);
      expect(find.text('Access revoked'), findsOneWidget);
      expect(find.text('Viewing window expired'), findsOneWidget);
      expect(find.textContaining('Content listing'), findsNWidgets(3));
      expect(find.text('Access granted'), findsNothing);
      for (final private in [
        'private-title.png',
        'secret-png-preview',
        'synthetic-recipient',
        'synthetic-owner',
        'synthetic-opaque-token',
      ]) {
        expect(find.textContaining(private), findsNothing);
      }
      expect(find.byType(RawImage), findsNothing);
      await f.account.setPolicy(7, 'Active');
      await f.account.setPolicy(9, 'Active');
      await tester.pump();
      expect(find.text('Content paused'), findsNothing);
    },
  );

  _test(
    'active view observes grant, connection loss, recovery and server denial',
    (f) async {
      await f.mountRecipient();
      await f.verify();
      expect(f.kinds, contains(AccessStatusKind.accessGranted));
      await f.tap('Open security checks');
      f.fake.routes[_check] = (_) => throw StateError('private network detail');
      await f.tester.pump(const Duration(seconds: 3));
      await flushViewing(f.tester);
      expect(f.kinds, {AccessStatusKind.networkInterrupted});
      final controller = f.controller;
      expect(controller.state, isNot(ViewingState.allowed));
      f.fake.routes[_check] = (_) => jsonReply(accessJson());
      unawaited(controller.revalidate());
      await flushViewing(f.tester);
      expect(f.kinds, {AccessStatusKind.accessGranted});
      f.fake.routes[_check] = (_) =>
          const ApiReply(403, 'untrusted private detail');
      f.native.camera.event();
      await f.tester.idle();
      await f.tester.pump(const Duration(seconds: 3));
      await flushViewing(f.tester);
      expect(controller.sessionEnded, isTrue);
      await f.notices();
      expect(find.text('Access denied'), findsOneWidget);
      expect(find.textContaining('Server response'), findsOneWidget);
      expect(find.textContaining('private detail'), findsNothing);
      expect(find.text('Access granted'), findsNothing);
    },
  );

  for (final (flag, expected) in [
    ('SessionEnded', 'Viewing session ended'),
    ('Suspended', 'Viewing suspended'),
  ]) {
    _test('$flag is server status without a guessed expiry reason', (f) async {
      await f.mountRecipient();
      await f.verify();
      f.fake.routes[_check] = (_) => jsonReply({
        ...accessJson(granted: false),
        flag: true,
        'Message': 'expired PRIVATE_SESSION_BODY',
      });
      await f.tester.pump(const Duration(seconds: 3));
      await flushViewing(f.tester);
      expect(f.controller.sessionEnded, isTrue);
      await f.notices();
      expect(find.text(expected), findsOneWidget);
      expect(find.textContaining('Server response'), findsOneWidget);
      expect(find.textContaining('expired'), findsNothing);
      expect(find.textContaining('PRIVATE_SESSION_BODY'), findsNothing);
    });
  }

  _test('revocation replaces a grant and repeated listings show one notice', (
    f,
  ) async {
    await f.mountRecipient();
    await f.verify();
    f.fake.contents = [contentJson(status: 'Revoked')];
    await f.account.refresh();
    await f.account.refresh();
    await flushViewing(f.tester);
    expect(f.controller.sessionEnded, isTrue);
    await f.notices();
    expect(find.text('Access revoked'), findsOneWidget);
    expect(find.textContaining('Content listing'), findsOneWidget);
    expect(find.text('Access granted'), findsNothing);
  });

  _test(
    'logout and account replacement reject a late old grant and clear status',
    (f) async {
      await f.mountRecipient();
      f.biometric.result = BiometricState.cancelled;
      await f.verify();
      expect(f.kinds, contains(AccessStatusKind.biometricCancelled));
      final response = Completer<ApiReply>();
      f.fake.routes[_open] = (_) => response.future;
      f.biometric.result = BiometricState.verified;
      await f.verify();
      expect(f.fake.calls.any((call) => call.uri.path == _open), isTrue);
      await f.notices();
      final oldReporter = f.account.accessStatuses.beginViewing(99);
      oldReporter.record(
        AccessStatusTopic.security,
        AccessStatusKind.securityUnavailable,
      );
      final logout = f.account.logout();
      await f.tester.pump();
      expect(find.text('Sign in to see access status.'), findsOneWidget);
      f.fake.userId = 2;
      f.fake.username = 'replacement';
      f.fake.token = 'replacement-token';
      await f.account.login('replacement', 'synthetic-only');
      oldReporter.record(
        AccessStatusTopic.server,
        AccessStatusKind.accessGranted,
      );
      response.complete(jsonReply(accessJson()));
      await logout;
      await flushViewing(f.tester);
      expect(f.account.user!.id, 2);
      expect(f.kinds, isEmpty);
      expect(find.text('No access updates yet.'), findsOneWidget);
    },
  );

  _test('biometric cancellation and unavailable are local and deduplicated', (
    f,
  ) async {
    await f.mountRecipient();
    f.biometric.result = BiometricState.cancelled;
    await f.verify();
    expect(f.kinds, {AccessStatusKind.biometricCancelled});
    f.biometric.result = BiometricState.notEnrolled;
    await f.verify();
    await f.verify();
    expect(f.fake.calls.where((c) => c.uri.path == _open), isEmpty);
    await f.notices();
    expect(find.text('Biometrics unavailable'), findsOneWidget);
    expect(find.textContaining('Device status'), findsOneWidget);
    expect(find.text('Biometric verification cancelled'), findsNothing);
  });

  _test('unsupported mandatory policy is device status and remains terminal', (
    f,
  ) async {
    await f.mountRecipient();
    f.fake.routes[_open] = (_) {
      final grant = accessJson();
      (grant['CameraRestrictions'] as Map)['Enabled'] = true;
      return jsonReply(grant);
    };
    await f.verify();
    expect(f.controller.sessionEnded, isTrue);
    await f.notices();
    expect(find.text('Required security checks unavailable'), findsOneWidget);
    expect(find.textContaining('Device status'), findsOneWidget);
    expect(find.text('Access denied'), findsNothing);
  });

  _test(
    'location denial, blocked settings and restoration never open a session',
    (f) async {
      final location = _Location();
      await f.mountRecipient(location: location);
      location.status = LocationPermissionState.denied;
      await f.tap(_allowLocation);
      expect(f.kinds, {AccessStatusKind.locationDenied});
      expect(
        find.textContaining('Try again or allow precise location'),
        findsOneWidget,
      );
      location.status = LocationPermissionState.permanentlyDenied;
      await f.tap(_allowLocation);
      expect(f.kinds, {AccessStatusKind.locationBlocked});
      expect(find.text(_allowLocation), findsNothing);
      f.lifecycle(AppLifecycleState.paused);
      location.status = LocationPermissionState.approximate;
      f.lifecycle(AppLifecycleState.resumed);
      await flushViewing(f.tester);
      expect(f.kinds, {AccessStatusKind.locationApproximate});
      f.lifecycle(AppLifecycleState.paused);
      location.status = LocationPermissionState.granted;
      f.lifecycle(AppLifecycleState.resumed);
      await flushViewing(f.tester);
      expect(f.kinds, isEmpty);
      expect(
        find.textContaining('Location permission is available'),
        findsOneWidget,
      );
      expect(find.text(_allowLocation), findsNothing);
      expect(location.prompts, 2);
      expect(location.fixes, 0);
      expect(f.fake.calls.where((c) => c.uri.path == _open), isEmpty);
      expect(f.controller.state, isNot(ViewingState.allowed));
    },
  );

  _test('foreground observes native location after its lifecycle callback', (
    f,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var permission = 'permanentlyDenied';
    final calls = <String>[];
    messenger.setMockMethodCallHandler(NativeDeviceLocation.channel, (
      call,
    ) async {
      calls.add(call.method);
      return call.method == 'permission' ? permission : null;
    });
    await f.mountRecipient(nativeLocation: true);
    expect(f.kinds, {AccessStatusKind.locationBlocked});
    expect(find.textContaining('precise foreground location'), findsOneWidget);
    expect(
      find.textContaining('permission alone does not authorize access'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Enable precise location for Aperture'),
      findsOneWidget,
    );
    f.lifecycle(AppLifecycleState.paused);
    permission = 'granted';
    f.lifecycle(AppLifecycleState.resumed);
    await flushViewing(f.tester);
    expect(f.kinds, isEmpty);
    expect(calls.where((call) => call == 'permission'), hasLength(2));
    expect(calls, isNot(contains('locate')));
    expect(f.fake.calls.where((c) => c.uri.path == _open), isEmpty);
  });

  _test(
    'background cancels the location UI wait and ignores its stale answer',
    (f) async {
      final location = _Location();
      await f.mountRecipient(location: location);
      final pending = Completer<LocationPermissionState>();
      location.pending = pending;
      await f.tap(_allowLocation);
      expect(find.text('Waiting for location permission…'), findsOneWidget);
      f.lifecycle(AppLifecycleState.inactive);
      await f.tester.pump();
      expect(find.text('Waiting for location permission…'), findsOneWidget);
      f.lifecycle(AppLifecycleState.paused);
      location.status = LocationPermissionState.permanentlyDenied;
      f.lifecycle(AppLifecycleState.resumed);
      pending.complete(LocationPermissionState.granted);
      await flushViewing(f.tester);
      expect(f.kinds, {AccessStatusKind.locationBlocked});
      expect(find.text('Waiting for location permission…'), findsNothing);
      expect(f.fake.calls.where((c) => c.uri.path == _open), isEmpty);
    },
  );

  _test(
    'restored camera permission clears an old denial but still needs checks',
    (f) async {
      await f.mountRecipient();
      var permission = 'denied';
      f.native.camera.permission = () => permission;
      f.native.camera.startError = PlatformException(code: 'permission_denied');
      await f.verify();
      await f.tap('Open security checks');
      expect(f.kinds, contains(AccessStatusKind.cameraDenied));
      f.lifecycle(AppLifecycleState.paused);
      permission = 'permanentlyDenied';
      f.lifecycle(AppLifecycleState.resumed);
      await flushViewing(f.tester);
      expect(f.kinds, contains(AccessStatusKind.cameraBlocked));
      await f.tester.scrollUntilVisible(
        find.text('Camera permission blocked'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Camera permission blocked'), findsOneWidget);
      expect(find.text('Retry camera protection'), findsNothing);
      f.lifecycle(AppLifecycleState.paused);
      permission = 'granted';
      f.lifecycle(AppLifecycleState.resumed);
      await flushViewing(f.tester);
      expect(f.kinds, isNot(contains(AccessStatusKind.cameraDenied)));
      expect(f.kinds, isNot(contains(AccessStatusKind.cameraBlocked)));
      expect(f.controller.biometrics.approved, isFalse);
      expect(
        find.byKey(const ValueKey('protected-render-placeholder')),
        findsNothing,
      );
    },
  );

  test(
    'duplicate notices and stale reporters cannot mutate current status',
    () {
      final feed = AccessStatusFeed();
      var changes = 0;
      feed.addListener(() => changes++);
      final first = feed.beginViewing(7);
      first.record(AccessStatusTopic.location, AccessStatusKind.locationDenied);
      first.record(AccessStatusTopic.location, AccessStatusKind.locationDenied);
      expect(changes, 1);
      final second = feed.beginViewing(7);
      first.record(
        AccessStatusTopic.location,
        AccessStatusKind.locationBlocked,
      );
      expect(feed.entries, isEmpty);
      second.record(
        AccessStatusTopic.location,
        AccessStatusKind.locationUnavailable,
      );
      second.close();
      second.record(AccessStatusTopic.location, null);
      expect(feed.entries.single.kind, AccessStatusKind.locationUnavailable);
      feed.clear();
      expect(feed.entries, isEmpty);
      feed.dispose();
    },
  );
}
