import 'dart:async';

import 'package:aperture/services/biometric_verification.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

import 'support/biometric_fake.dart';

class AuthenticationSpy extends LocalAuthentication {
  bool hardware = true;
  List<BiometricType> enrolled = [BiometricType.fingerprint];
  bool result = true;
  LocalAuthExceptionCode? error;
  Completer<bool>? pending;
  Completer<bool>? checking;
  int calls = 0, stops = 0;
  bool? biometricOnlySeen, persistentSeen, sensitiveSeen;
  @override
  Future<bool> get canCheckBiometrics async => checking?.future ?? hardware;
  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => enrolled;
  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<dynamic> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    calls++;
    biometricOnlySeen = biometricOnly;
    persistentSeen = persistAcrossBackgrounding;
    sensitiveSeen = sensitiveTransaction;
    if (error != null) throw LocalAuthException(code: error!);
    return pending?.future ?? result;
  }

  @override
  Future<bool> stopAuthentication() async {
    stops++;
    return true;
  }
}

Future<void> ticks() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'adapter requires biometrics only and disables background persistence',
    () async {
      final api = AuthenticationSpy();
      final adapter = LocalBiometricAuthenticator(authentication: api);
      expect(await adapter.authenticate(), BiometricState.verified);
      expect(api.biometricOnlySeen, isTrue);
      expect(api.persistentSeen, isFalse);
      expect(api.sensitiveSeen, isTrue);
    },
  );
  test('recognition false fails closed', () async {
    final api = AuthenticationSpy()..result = false;
    expect(
      await LocalBiometricAuthenticator(authentication: api).authenticate(),
      BiometricState.failed,
    );
  });
  test('native no-hardware failure denies access without fallback', () async {
    final api = AuthenticationSpy()
      ..error = LocalAuthExceptionCode.noBiometricHardware;
    expect(
      await LocalBiometricAuthenticator(authentication: api).authenticate(),
      BiometricState.unavailable,
    );
    expect(api.calls, 1);
  });
  test('native no-enrollment failure denies access without fallback', () async {
    final api = AuthenticationSpy()
      ..error = LocalAuthExceptionCode.noBiometricsEnrolled;
    expect(
      await LocalBiometricAuthenticator(authentication: api).authenticate(),
      BiometricState.notEnrolled,
    );
    expect(api.calls, 1);
  });
  for (final code in LocalAuthExceptionCode.values) {
    test(
      'platform ${code.name} is handled without credential fallback',
      () async {
        final api = AuthenticationSpy()..error = code;
        final expected = switch (code) {
          LocalAuthExceptionCode.userCanceled ||
          LocalAuthExceptionCode.systemCanceled ||
          LocalAuthExceptionCode.timeout => BiometricState.cancelled,
          LocalAuthExceptionCode.noBiometricsEnrolled ||
          LocalAuthExceptionCode.noCredentialsSet => BiometricState.notEnrolled,
          LocalAuthExceptionCode.noBiometricHardware ||
          LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
          LocalAuthExceptionCode.uiUnavailable => BiometricState.unavailable,
          LocalAuthExceptionCode.temporaryLockout =>
            BiometricState.temporaryLockout,
          LocalAuthExceptionCode.biometricLockout =>
            BiometricState.permanentLockout,
          LocalAuthExceptionCode.authInProgress => BiometricState.busy,
          _ => BiometricState.failed,
        };
        expect(
          await LocalBiometricAuthenticator(authentication: api).authenticate(),
          expected,
        );
        expect(api.calls, 1);
        expect(api.biometricOnlySeen, isTrue);
      },
    );
  }
  test(
    'native prompts serialize across sessions without sharing results',
    () async {
      final one = AuthenticationSpy()..pending = Completer<bool>();
      final two = AuthenticationSpy();
      final a = LocalBiometricAuthenticator(authentication: one),
          b = LocalBiometricAuthenticator(authentication: two);
      final first = a.authenticate();
      await ticks();
      expect(await b.authenticate(), BiometricState.busy);
      expect(two.calls, 0);
      await a.cancel();
      one.pending!.complete(true);
      expect(await first, BiometricState.cancelled);
      expect(await b.authenticate(), BiometricState.verified);
      expect(two.calls, 1);
    },
  );
  test('old adapter cancellation cannot cancel a newer native owner', () async {
    final a = LocalBiometricAuthenticator(authentication: AuthenticationSpy());
    await a.authenticate();
    final api = AuthenticationSpy()..pending = Completer<bool>();
    final b = LocalBiometricAuthenticator(authentication: api);
    final next = b.authenticate();
    await ticks();
    await a.cancel();
    expect(api.stops, 0);
    api.pending!.complete(true);
    expect(await next, BiometricState.verified);
  });
  test(
    'lockout is not masked by false capability or enrollment helpers',
    () async {
      final api = AuthenticationSpy()
        ..hardware = false
        ..enrolled = []
        ..error = LocalAuthExceptionCode.biometricLockout;
      expect(
        await LocalBiometricAuthenticator(authentication: api).authenticate(),
        BiometricState.permanentLockout,
      );
      expect(api.calls, 1);
    },
  );

  for (final outcome in [
    BiometricState.verified,
    BiometricState.cancelled,
    BiometricState.failed,
    BiometricState.unavailable,
    BiometricState.notEnrolled,
    BiometricState.temporaryLockout,
    BiometricState.permanentLockout,
    BiometricState.busy,
  ]) {
    test('session presents ${outcome.name} and grants only verified', () async {
      final fake = BiometricFake()..result = outcome;
      final session = BiometricVerification(authenticator: fake);
      expect(session.approved, isFalse);
      await session.verify();
      expect(session.state, outcome);
      expect(session.approved, outcome == BiometricState.verified);
      session.dispose();
    });
  }
  test(
    'repeated verification requests share one prompt in the same session',
    () async {
      final fake = BiometricFake()..pending = Completer<BiometricState>();
      final session = BiometricVerification(authenticator: fake);
      final a = session.verify(), b = session.verify(), c = session.verify();
      expect(identical(a, b), isTrue);
      expect(identical(b, c), isTrue);
      await ticks();
      expect(fake.starts, 1);
      fake.pending!.complete(BiometricState.verified);
      await a;
      session.dispose();
    },
  );
  test('approval is never cached in another session', () async {
    final fake = BiometricFake();
    final a = BiometricVerification(authenticator: fake);
    await a.verify();
    a.dispose();
    final b = BiometricVerification(authenticator: fake);
    expect(b.approved, isFalse);
    await b.verify();
    expect(fake.starts, 2);
    b.dispose();
  });
  test('background cancels and discards stale success; returning requires a new attempt', () async {
    final fake = BiometricFake()..pending = Completer<BiometricState>();
    final session = BiometricVerification(authenticator: fake);
    final first = session.verify();
    await ticks();
    session.suspend(backgrounded: true);
    fake.pending!.complete(BiometricState.verified);
    await first;
    session.resume();
    expect(session.approved, isFalse);
    expect(session.state, BiometricState.required);
    expect(fake.cancels, greaterThan(0));
    fake.pending = null;
    await session.verify();
    expect(session.approved, isTrue);
    expect(fake.starts, 2);
    session.dispose();
  });
  test(
    'system prompt inactivity keeps approval hidden until foreground',
    () async {
      final fake = BiometricFake()..pending = Completer<BiometricState>();
      final session = BiometricVerification(authenticator: fake);
      final op = session.verify();
      await ticks();
      session.suspend(backgrounded: false);
      fake.pending!.complete(BiometricState.verified);
      await op;
      expect(session.approved, isFalse);
      expect(session.canVerify, isFalse);
      session.resume();
      expect(session.approved, isTrue);
      session.dispose();
    },
  );
  test('real background after a pending inactive success revokes it', () async {
    final fake = BiometricFake()..pending = Completer<BiometricState>();
    final session = BiometricVerification(authenticator: fake);
    final op = session.verify();
    await ticks();
    session.suspend(backgrounded: false);
    fake.pending!.complete(BiometricState.verified);
    await op;
    session.suspend(backgrounded: true);
    session.resume();
    expect(session.approved, isFalse);
    session.dispose();
  });
  for (final ended in [false, true]) {
    test(
      'revoke ended=$ended rejects late authentication completion',
      () async {
        final fake = BiometricFake()..pending = Completer<BiometricState>();
        final session = BiometricVerification(authenticator: fake);
        final op = session.verify();
        await ticks();
        session.revoke(ended: ended);
        fake.pending!.complete(BiometricState.verified);
        await op;
        expect(session.approved, isFalse);
        expect(
          session.state,
          ended ? BiometricState.ended : BiometricState.required,
        );
        session.dispose();
      },
    );
  }
  test(
    'disposal discards completion and emits no later notifications',
    () async {
      final fake = BiometricFake()..pending = Completer<BiometricState>();
      final session = BiometricVerification(authenticator: fake);
      var notifications = 0;
      session.addListener(() => notifications++);
      final op = session.verify();
      await ticks();
      session.dispose();
      final count = notifications;
      fake.pending!.complete(BiometricState.verified);
      await op;
      expect(session.approved, isFalse);
      expect(notifications, count);
    },
  );
  test('revoke before scheduled start prevents any native attempt', () async {
    final fake = BiometricFake();
    final session = BiometricVerification(authenticator: fake);
    final op = session.verify();
    session.revoke(ended: true);
    await op;
    expect(fake.starts, 0);
    expect(session.approved, isFalse);
    session.dispose();
  });
  testWidgets(
    'timeout and a newer verification cannot consume an older success',
    (tester) async {
      final old = Completer<BiometricState>();
      final fake = BiometricFake()..pending = old;
      final session = BiometricVerification(
        authenticator: fake,
        timeout: const Duration(milliseconds: 20),
      );
      unawaited(session.verify());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(session.state, BiometricState.unavailable);
      expect(session.approved, isFalse);
      final next = Completer<BiometricState>();
      fake.pending = next;
      unawaited(session.verify());
      await tester.pump();
      old.complete(BiometricState.verified);
      await tester.pump();
      expect(session.approved, isFalse);
      next.complete(BiometricState.cancelled);
      await tester.pump();
      expect(session.state, BiometricState.cancelled);
      session.dispose();
    },
  );
  test('unexpected adapter outcome and exception fail closed', () async {
    final fake = BiometricFake()..result = BiometricState.required;
    final session = BiometricVerification(authenticator: fake);
    await session.verify();
    expect(session.state, BiometricState.failed);
    fake.error = StateError('unavailable');
    await session.verify();
    expect(session.state, BiometricState.unavailable);
    expect(session.approved, isFalse);
    session.dispose();
  });
}
