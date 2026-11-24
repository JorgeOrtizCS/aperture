import 'dart:async';

import 'package:aperture/models/api_models.dart';
import 'package:aperture/models/location_radius_policy.dart';
import 'package:aperture/screens/api_content_screens.dart';
import 'package:aperture/screens/api_location_edit_screen.dart';
import 'package:aperture/screens/viewing_requirements_screen.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/services/api_session.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_fake.dart';

// Synthetic coordinates/accounts/HTTP only. No live writes or native GPS.
const _endpoint = '/api/situational/content/7/location';
const _old = LocationZone(26.37, -80.1, 100);
const _next = LocationZone(26.38, -80.11, 500);
Map<String, Object?> _row({
  bool mine = true,
  LocationZone? zone = _old,
  String status = 'Active',
  String policy = 'Active',
}) => {
  ...contentJson(mine: mine, status: status, policy: policy),
  if (zone != null) ...{
    'Latitude': zone.latitude,
    'Longitude': zone.longitude,
    'RadiusMeters': zone.radiusMeters,
  },
};
Matcher _error(ApiFailure kind) =>
    isA<ApiException>().having((e) => e.kind, 'kind', kind);
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('owner location contract and account boundary', () {
    late ApiFake api;
    late ApiSession account;
    bool current = true;
    setUp(() async {
      api = ApiFake()..contents = [_row()];
      api.routes[_endpoint] = (_) => jsonReply({'success': true});
      account = api.session();
      current = true;
      await account.login('synthetic-user', 'fixture-password');
      await account.refresh();
    });
    tearDown(() => account.dispose());
    Future<void> save([LocationZone zone = _next]) =>
        account.setLocation(7, zone, isCurrent: () => current);
    Iterable<ApiCall> writes() =>
        api.calls.where((c) => c.uri.path == _endpoint);

    test(
      'exact authenticated POST uses three policy fields and no sensor headers',
      () async {
        await save();
        final call = writes().single;
        expect(call.method, 'POST');
        expect(call.headers['Authorization'], 'Bearer synthetic-opaque-token');
        expect(call.headers['Content-Type'], 'application/json');
        expect(call.json, {
          'Latitude': 26.38,
          'Longitude': -80.11,
          'RadiusMeters': 500.0,
        });
        expect(
          call.headers.keys.where((k) => k.startsWith('X-Client')),
          isEmpty,
        );
        expect(account.items.single.locationZone, _next);
      },
    );
    for (final radius in [10.0, 30.0, 100.0, 500.0, 1000.0, 10000.0, 10.5]) {
      test(
        'supported radius $radius preserves numeric center and radius',
        () async {
          final zone = LocationZone(_old.latitude, _old.longitude, radius);
          await save(zone);
          expect(writes().single.json['RadiusMeters'], radius);
          expect(account.items.single.locationZone, zone);
        },
      );
    }
    for (final entry in [
      const LocationZone(91, 0, 100),
      const LocationZone(0, -181, 100),
      const LocationZone(double.nan, 0, 100),
      const LocationZone(0, double.infinity, 100),
      const LocationZone(0, 0, 9),
      const LocationZone(0, 0, 10001),
      const LocationZone(0, 0, double.nan),
      const LocationZone(0, 0, double.infinity),
    ].indexed) {
      final zone = entry.$2;
      test('invalid policy ${entry.$1} sends no write', () async {
        await expectLater(
          save(zone),
          throwsA(_error(ApiFailure.invalidRequest)),
        );
        expect(writes(), isEmpty);
        expect(account.ownerControl(7), (
          OwnerControlAction.editViewingArea,
          OwnerControlPhase.notDispatched,
        ));
        expect(account.items.single.locationZone, _old);
      });
    }
    for (final body in [
      'not-json',
      '[]',
      '{}',
      '{"Success":true}',
      '{"success":"true"}',
      '{"success":false}',
    ]) {
      test('malformed acknowledgement $body cannot confirm an area', () async {
        api.routes[_endpoint] = (_) => ApiReply(200, body);
        await expectLater(save(), throwsA(_error(ApiFailure.malformed)));
        expect(account.items.single.locationZone, _old);
      });
    }
    test(
      'a lost area acknowledgement blocks writes after a matching refresh',
      () async {
        api.routes[_endpoint] = (_) => const ApiReply(200, '{}');
        await expectLater(save(), throwsA(_error(ApiFailure.malformed)));
        api.contents = [_row(zone: _next)];
        await account.refresh();
        expect(account.items.single.locationZone, _next);
        expect(account.ownerControlUnconfirmed(7), isTrue);
        await expectLater(
          save(),
          throwsA(_error(ApiFailure.ownerControlUnconfirmed)),
        );
        expect(writes(), hasLength(1));
      },
    );
    for (final row in [
      (400, ApiFailure.invalidRequest),
      (401, ApiFailure.credentials),
      (403, ApiFailure.denied),
      (404, ApiFailure.notFound),
      (500, ApiFailure.server),
      (302, ApiFailure.server),
    ]) {
      test('HTTP ${row.$1} cannot confirm an area', () async {
        api.routes[_endpoint] = (_) => ApiReply(row.$1, 'synthetic failure');
        await expectLater(save(), throwsA(_error(row.$2)));
        expect(account.authenticated, row.$1 != 401);
        if (account.authenticated) {
          expect(account.items.single.locationZone, _old);
          expect(account.ownerControl(7), (
            OwnerControlAction.editViewingArea,
            row.$1 == 400 || row.$1 == 404
                ? OwnerControlPhase.rejected
                : OwnerControlPhase.unconfirmed,
          ));
        } else {
          await account.login('synthetic-user', 'fixture-password');
          expect(account.ownerControl(7), isNull);
        }
      });
    }
    test(
      'pending request retains old metadata; acknowledgement precedes change',
      () async {
        final pending = Completer<ApiReply>();
        api.routes[_endpoint] = (_) => pending.future;
        final result = save();
        await _tick();
        expect(account.pending(7), true);
        expect(account.items.single.locationZone, _old);
        pending.complete(jsonReply({'success': true}));
        await result;
        expect(account.pending(7), false);
        expect(account.items.single.locationZone, _next);
      },
    );
    test('location writes serialize with duplicate, pause, resume and revoke actions', () async {
      final pending = Completer<ApiReply>();
      api.routes[_endpoint] = (_) => pending.future;
      final result = save();
      await _tick();
      for (final action in [
        save,
        () => account.setPolicy(7, 'Paused'),
        () => account.setPolicy(7, 'Active'),
        () => account.revoke(7),
      ]) {
        await expectLater(action(), throwsA(_error(ApiFailure.pending)));
      }
      expect(writes().length, 1);
      pending.complete(jsonReply({'success': true}));
      await result;
    });
    for (final kind in ['recipient', 'revoked', 'missing']) {
      test('$kind cannot invoke the owner mutation', () async {
        api.contents = kind == 'missing'
            ? []
            : [
                _row(
                  mine: kind != 'recipient',
                  status: kind == 'revoked' ? 'Revoked' : 'Active',
                ),
              ];
        await account.refresh();
        await expectLater(save(), throwsA(_error(ApiFailure.denied)));
        expect(writes(), isEmpty);
      });
    }
    test('missing credentials and ended caller prevent requests', () async {
      current = false;
      await expectLater(save(), throwsA(_error(ApiFailure.stale)));
      current = true;
      await account.logout();
      await expectLater(save(), throwsA(_error(ApiFailure.credentials)));
      expect(writes(), isEmpty);
    });
    test(
      'caller invalidated before dispatch can retry from a fresh route',
      () async {
        void invalidate() {
          if (account.pending(7)) current = false;
        }

        account.addListener(invalidate);
        await expectLater(save(), throwsA(_error(ApiFailure.stale)));
        account.removeListener(invalidate);
        expect(writes(), isEmpty);
        expect(account.ownerControl(7), (
          OwnerControlAction.editViewingArea,
          OwnerControlPhase.notDispatched,
        ));
        current = true;
        await save();
        expect(writes(), hasLength(1));
        expect(account.items.single.locationZone, _next);
      },
    );
    for (final response in [200, 401, 500]) {
      test(
        'caller termination rejects late $response without account mutation',
        () async {
          final pending = Completer<ApiReply>();
          api.routes[_endpoint] = (_) => pending.future;
          final result = expectLater(save(), throwsA(_error(ApiFailure.stale)));
          await _tick();
          current = false;
          pending.complete(
            response == 200
                ? jsonReply({'success': true})
                : ApiReply(response, 'synthetic failure'),
          );
          await result;
          expect(account.authenticated, true);
          expect(account.items.single.locationZone, _old);
          expect(account.error, null);
          expect(account.pending(7), false);
          expect(account.ownerControlUnconfirmed(7), isTrue);
        },
      );
    }
    for (final response in [200, 401]) {
      test(
        'replacement account ignores old $response and preserves its pending state',
        () async {
          final pending = Completer<ApiReply>();
          api.routes[_endpoint] = (_) => pending.future;
          final result = expectLater(save(), throwsA(_error(ApiFailure.stale)));
          await _tick();
          await account.logout();
          api.userId = 2;
          api.username = 'synthetic-other';
          api.contents = [_row(zone: const LocationZone(1, 2, 30))];
          await account.login('synthetic-other', 'fixture-password');
          await account.refresh();
          pending.complete(
            response == 200
                ? jsonReply({'success': true})
                : const ApiReply(401, 'old denial'),
          );
          await result;
          expect(account.authenticated, true);
          expect(account.user!.id, 2);
          expect(
            account.items.single.locationZone,
            const LocationZone(1, 2, 30),
          );
        },
      );
    }
    test('logout alone rejects a late acknowledgement', () async {
      final pending = Completer<ApiReply>();
      api.routes[_endpoint] = (_) => pending.future;
      final result = expectLater(save(), throwsA(_error(ApiFailure.stale)));
      await _tick();
      await account.logout();
      pending.complete(jsonReply({'success': true}));
      await result;
      expect(account.authenticated, false);
      expect(account.items, isEmpty);
    });
    test(
      'older listing cannot overwrite an acknowledged policy change',
      () async {
        final pending = Completer<ApiReply>();
        api.routes['/api/content'] = (_) => pending.future;
        final listing = account.refresh();
        await _tick();
        await save();
        pending.complete(jsonReply([_row()]));
        await listing;
        expect(account.items.single.locationZone, _next);
      },
    );
    test('route-scoped superseded refresh reports stale rather than claiming read-back', () async {
      final old = Completer<ApiReply>();
      api.routes['/api/content'] = (_) => old.future;
      final oldResult = expectLater(
        account.refresh(isCurrent: () => current),
        throwsA(_error(ApiFailure.stale)),
      );
      await _tick();
      api.routes.remove('/api/content');
      await account.refresh();
      old.complete(jsonReply([_row(zone: _next)]));
      await oldResult;
      expect(account.items.single.locationZone, _old);
    });
    test(
      'inactive route refresh cannot replace metadata or process a late 401',
      () async {
        final pending = Completer<ApiReply>();
        api.routes['/api/content'] = (_) => pending.future;
        final result = expectLater(
          account.refresh(isCurrent: () => current),
          throwsA(_error(ApiFailure.stale)),
        );
        await _tick();
        current = false;
        pending.complete(const ApiReply(401, 'old denial'));
        await result;
        expect(account.authenticated, true);
        expect(account.error, null);
      },
    );
    test('transport exception fails without modifying the area', () async {
      api.routes[_endpoint] = (_) => throw StateError('fixture offline');
      await expectLater(save(), throwsA(_error(ApiFailure.network)));
      expect(account.items.single.locationZone, _old);
    });
    test(
      'timeout discards late acknowledgement and cannot imply no server effect',
      () async {
        account.dispose();
        account = api.session(timeout: const Duration(milliseconds: 2));
        await account.login('synthetic-user', 'fixture-password');
        await account.refresh();
        final pending = Completer<ApiReply>();
        api.routes[_endpoint] = (_) => pending.future;
        await expectLater(save(), throwsA(_error(ApiFailure.timeout)));
        pending.complete(jsonReply({'success': true}));
        await _tick();
        expect(account.items.single.locationZone, _old);
        expect(account.pending(7), false);
        expect(account.ownerControl(7), (
          OwnerControlAction.editViewingArea,
          OwnerControlPhase.unconfirmed,
        ));
        await expectLater(
          save(),
          throwsA(_error(ApiFailure.ownerControlUnconfirmed)),
        );
        expect(writes(), hasLength(1));
        expect(
          const ApiException(ApiFailure.timeout).message,
          contains('unknown'),
        );
      },
    );
    test(
      'all owned rows retain independent status/trust while area changes',
      () async {
        api.contents = [
          _row(policy: 'Paused'),
          {
            ..._row(status: 'Revoked', policy: 'Paused'),
            'Recipient': 'synthetic-second',
            'RequireTrustedDevice': true,
          },
        ];
        await account.refresh();
        await save();
        expect(
          account.items.every(
            (i) => i.locationZone == _next && i.requiresPreciseLocation,
          ),
          true,
        );
        expect(account.items.map((i) => i.status), ['Active', 'Revoked']);
        expect(account.items.every((i) => i.policyStatus == 'Paused'), true);
        expect(account.items.last.requiresTrustedDevice, true);
      },
    );
    test('existing-content draft preserves custom coordinates/radius and no-area is blank', () {
      final draft = SenderLocationDraft.forExistingArea(
        const LocationZone(1.234, -2.345, 123.5),
      );
      expect(draft.zone, const LocationZone(1.234, -2.345, 123.5));
      expect(draft.preset, LocationRadiusPreset.custom);
      final blank = SenderLocationDraft.forExistingArea(null);
      expect(blank.enabled, true);
      expect(blank.zone, null);
      expect(blank.latitude, isEmpty);
    });
  });

  Future<void> show(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump();
    }
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  Future<void> tap(
    WidgetTester tester,
    String text, {
    bool settle = true,
  }) async {
    final finder = find.text(text);
    await show(tester, finder);
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.idle();
      await tester.pump();
    }
  }

  Future<void> enter(WidgetTester tester, String key, String value) async {
    final finder = find.byKey(ValueKey(key));
    await show(tester, finder);
    await tester.enterText(finder, value);
    await tester.pump();
  }

  Future<void> edit(WidgetTester tester) async {
    await enter(tester, 'location-center-latitude', _next.latitude.toString());
    await enter(
      tester,
      'location-center-longitude',
      _next.longitude.toString(),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final picker = find.byKey(const ValueKey('location-radius-preset'));
    await show(tester, picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Campus / large property: 500 m').last);
    await tester.pumpAndSettle();
  }

  Future<void> confirmText(WidgetTester tester, String text) async {
    await show(tester, find.textContaining(text));
    expect(find.textContaining(text), findsOneWidget);
  }

  void flowTest(
    String name,
    Future<void> Function(WidgetTester, _OwnerFlow) body,
  ) {
    testWidgets(name, (tester) async {
      final flow = _OwnerFlow();
      try {
        await body(tester, flow);
      } finally {
        await tester.pumpWidget(const SizedBox());
        flow.releasePending();
        await tester.idle();
        await tester.pump();
        flow.close();
      }
    });
  }

  flowTest(
    'owner status enters prefilled existing editor without a clear-location toggle',
    (tester, f) async {
      await f.mount(tester);
      await tap(tester, 'Edit viewing area');
      expect(find.byType(ApiLocationEditScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('location-area-enabled')), findsNothing);
      await show(
        tester,
        find.byKey(const ValueKey('location-center-latitude')),
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('location-center-latitude')),
            )
            .initialValue,
        '26.37',
      );
      await confirmText(tester, 'Selected radius: 100.0 m');
      expect(f.writes, isEmpty);
    },
  );
  flowTest(
    'existing editor sends chosen center/radius and confirms only after acknowledgement and list',
    (tester, f) async {
      await f.mount(tester, editor: true);
      await edit(tester);
      await tap(tester, 'Save viewing area');
      await confirmText(
        tester,
        'Viewing area update confirmed in the server listing.',
      );
      expect(f.writes.single.json, {
        'Latitude': _next.latitude,
        'Longitude': _next.longitude,
        'RadiusMeters': 500.0,
      });
      expect(f.account!.items.single.locationZone, _next);
      expect(
        f.api.calls.where((c) => c.uri.path.endsWith('/sessions')),
        isEmpty,
      );
      expect(
        find.byKey(
          const ValueKey('protected-render-placeholder'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      await confirmText(tester, 'The server currently checks distance only.');
    },
  );
  flowTest(
    'pending area write retains old metadata and disables another save',
    (tester, f) async {
      await f.mount(tester, editor: true);
      final pending = f.hold();
      f.api.routes[_endpoint] = (_) => pending.future;
      await edit(tester);
      await tap(tester, 'Save viewing area', settle: false);
      expect(f.account!.items.single.locationZone, _old);
      expect(find.textContaining('update confirmed'), findsNothing);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Save viewing area'),
            )
            .onPressed,
        null,
      );
      f.api.contents = [_row(zone: _next)];
      pending.complete(jsonReply({'success': true}));
      await tester.pumpAndSettle();
      await confirmText(tester, 'update confirmed in the server listing');
      expect(f.writes.length, 1);
    },
  );
  for (final failure in [
    (403, 'The server denied this action.'),
    (404, 'This content or session is unavailable to this account.'),
    (400, 'The server rejected this request.'),
  ]) {
    flowTest('owner UI displays HTTP ${failure.$1} without saved state', (
      tester,
      f,
    ) async {
      await f.mount(tester, editor: true);
      f.api.routes[_endpoint] = (_) => ApiReply(failure.$1, 'synthetic denial');
      await edit(tester);
      await tap(tester, 'Save viewing area');
      await confirmText(tester, failure.$2);
      expect(f.account!.items.single.locationZone, _old);
      expect(find.textContaining('update confirmed'), findsNothing);
    });
  }
  flowTest('401 ends the authentication session and removes owner controls', (
    tester,
    f,
  ) async {
    await f.mount(tester, editor: true);
    f.api.routes[_endpoint] = (_) => const ApiReply(401, 'expired');
    await tap(tester, 'Save viewing area');
    expect(f.account!.authenticated, false);
    expect(find.text('Save viewing area'), findsNothing);
    expect(find.textContaining('no longer editable'), findsOneWidget);
  });
  flowTest('unknown write stays locked and never confirms the draft', (
    tester,
    f,
  ) async {
    await f.mount(tester, editor: true);
    f.api.routes[_endpoint] = (_) =>
        const ApiReply(500, 'synthetic server failure');
    await edit(tester);
    await tap(tester, 'Save viewing area');
    await confirmText(tester, 'The API could not complete the request.');
    await confirmText(
      tester,
      'The viewing-area update’s server outcome is unknown.',
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Save viewing area'),
          )
          .onPressed,
      null,
    );
    expect(f.account!.items.single.locationZone, _old);
  });
  flowTest(
    'acknowledged write with failed refresh reports both facts without a false listing confirmation',
    (tester, f) async {
      await f.mount(tester, editor: true);
      f.api.routes[_endpoint] = (_) {
        f.api.routes['/api/content'] = (_) =>
            const ApiReply(500, 'fixture unavailable');
        return jsonReply({'success': true});
      };
      await edit(tester);
      await tap(tester, 'Save viewing area');
      await confirmText(tester, 'update acknowledged. Status refresh failed');
      expect(f.account!.items.single.locationZone, _next);
      expect(f.account!.ownerControl(7), (
        OwnerControlAction.editViewingArea,
        OwnerControlPhase.confirmed,
      ));
      expect(
        find.textContaining('confirmed in the server listing'),
        findsNothing,
      );
    },
  );
  flowTest(
    'acknowledged write with different listed policy requires refresh before another edit',
    (tester, f) async {
      await f.mount(tester, editor: true);
      f.api.routes[_endpoint] = (_) => jsonReply({'success': true});
      await edit(tester);
      await tap(tester, 'Save viewing area');
      await confirmText(tester, 'its listed area differs');
      expect(f.account!.items.single.locationZone, _old);
      expect(f.account!.ownerControl(7), (
        OwnerControlAction.editViewingArea,
        OwnerControlPhase.confirmed,
      ));
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Save viewing area'),
            )
            .onPressed,
        null,
      );
    },
  );
  flowTest(
    'refresh resets visible edited text even when the server area is unchanged',
    (tester, f) async {
      await f.mount(tester, editor: true);
      await enter(tester, 'location-center-latitude', '12.345');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tap(tester, 'Refresh listed area');
      await show(
        tester,
        find.byKey(const ValueKey('location-center-latitude')),
      );
      final field = find.descendant(
        of: find.byKey(const ValueKey('location-center-latitude')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(field).controller!.text, '26.37');
      expect(f.writes, isEmpty);
    },
  );
  flowTest(
    'existing content without a precise area needs an explicit center before saving',
    (tester, f) async {
      await f.mount(tester, editor: true, zone: null);
      await show(tester, find.text('Save viewing area'));
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Save viewing area'),
            )
            .onPressed,
        null,
      );
      await enter(tester, 'location-center-latitude', '26.37');
      await enter(tester, 'location-center-longitude', '-80.1');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tap(tester, 'Save viewing area');
      expect(f.writes.length, 1);
    },
  );
  flowTest(
    'recipients have neither status-page editing nor forced editor access',
    (tester, f) async {
      await f.mount(tester, mine: false);
      expect(find.text('Edit viewing area'), findsNothing);
      unawaited(
        f.navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ApiLocationEditScreen(account: f.account!, contentId: 7),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save viewing area'), findsNothing);
      expect(find.textContaining('no longer editable'), findsOneWidget);
      expect(f.writes, isEmpty);
    },
  );
  flowTest('revoked owner content exposes no location editing', (
    tester,
    f,
  ) async {
    await f.mount(tester, status: 'Revoked');
    expect(find.text('Edit viewing area'), findsNothing);
    expect(f.writes, isEmpty);
  });
  flowTest(
    'popping during a pending save retains the hold through editor re-entry',
    (tester, f) async {
      await f.mount(tester, editor: true);
      final pending = f.hold();
      f.api.routes[_endpoint] = (_) => pending.future;
      await edit(tester);
      await tap(tester, 'Save viewing area', settle: false);
      f.navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(f.account!.pending(7), isTrue);
      final before = f.api.calls.length;
      await tap(tester, 'Refresh status', settle: false);
      expect(f.api.calls.skip(before).single.method, 'GET');
      expect(f.account!.pending(7), isTrue);
      pending.complete(jsonReply({'success': true}));
      await tester.pumpAndSettle();
      expect(f.account!.items.single.locationZone, _old);
      expect(f.account!.error, null);
      expect(find.textContaining('update confirmed'), findsNothing);
      await confirmText(
        tester,
        'The viewing-area update request’s server outcome is unknown.',
      );
      await tap(tester, 'Review viewing area');
      await confirmText(
        tester,
        'The viewing-area update’s server outcome is unknown.',
      );
      f.api.contents = [_row(zone: _next)];
      await tap(tester, 'Refresh listed area');
      await confirmText(tester, 'Listed viewing area refreshed.');
      await confirmText(
        tester,
        'The viewing-area update’s server outcome is unknown.',
      );
      expect(f.account!.items.single.locationZone, _next);
      await show(tester, find.text('Save viewing area'));
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Save viewing area'),
            )
            .onPressed,
        isNull,
      );
      expect(f.writes, hasLength(1));
    },
  );
  flowTest(
    'covering and returning to an editor cannot revive its old request',
    (tester, f) async {
      await f.mount(tester, editor: true);
      final pending = f.hold();
      f.api.routes[_endpoint] = (_) => pending.future;
      await edit(tester);
      await tap(tester, 'Save viewing area', settle: false);
      unawaited(
        f.navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Other page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      f.navigator.currentState!.pop();
      await tester.pump();
      pending.complete(jsonReply({'success': true}));
      await tester.pumpAndSettle();
      expect(f.account!.items.single.locationZone, _old);
      await confirmText(tester, 'A pending server change may still finish');
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Save viewing area'),
            )
            .onPressed,
        null,
      );
    },
  );
  flowTest('logout and replacement discard a pending owner response', (
    tester,
    f,
  ) async {
    await f.mount(tester, editor: true);
    final pending = f.hold();
    f.api.routes[_endpoint] = (_) => pending.future;
    await edit(tester);
    await tap(tester, 'Save viewing area', settle: false);
    await f.account!.logout();
    f.api.userId = 2;
    f.api.username = 'synthetic-other';
    f.api.contents = [_row(zone: const LocationZone(1, 2, 30))];
    await f.account!.login('synthetic-other', 'fixture-password');
    await f.account!.refresh();
    pending.complete(jsonReply({'success': true}));
    await tester.pumpAndSettle();
    expect(f.account!.items.single.locationZone, const LocationZone(1, 2, 30));
    expect(find.text('Save viewing area'), findsNothing);
    expect(f.account!.user!.id, 2);
  });
  flowTest(
    'late read-back denial after navigation cannot sign out the current account',
    (tester, f) async {
      await f.mount(tester, editor: true);
      final listing = f.hold();
      f.api.routes[_endpoint] = (_) {
        f.api.routes['/api/content'] = (_) => listing.future;
        return jsonReply({'success': true});
      };
      await edit(tester);
      await tap(tester, 'Save viewing area', settle: false);
      expect(f.account!.items.single.locationZone, _next);
      f.navigator.currentState!.pop();
      await tester.pump();
      listing.complete(const ApiReply(401, 'stale read-back denial'));
      await tester.pumpAndSettle();
      expect(f.account!.authenticated, true);
      expect(f.account!.items.single.locationZone, _next);
      expect(f.account!.error, null);
    },
  );
  for (final boundary in ['content', 'account']) {
    flowTest('a reused editor state cannot acknowledge an old $boundary', (
      tester,
      f,
    ) async {
      await f.mount(tester);
      f.api.contents = [
        _row(),
        {..._row(zone: const LocationZone(1, 2, 30)), 'Id': 8},
      ];
      await f.account!.refresh();
      final replacement = boundary == 'account' ? f.api.session() : f.account!;
      if (boundary == 'account') {
        f.extraAccounts.add(replacement);
        await replacement.login('synthetic-user', 'fixture-password');
        await replacement.refresh();
      }
      const key = ValueKey('reused-owner-editor');
      await tester.pumpWidget(
        MaterialApp(
          home: ApiLocationEditScreen(
            key: key,
            account: f.account!,
            contentId: 7,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(ApiLocationEditScreen));
      final pending = f.hold();
      f.api.routes[_endpoint] = (_) => pending.future;
      await edit(tester);
      await tap(tester, 'Save viewing area', settle: false);
      await tester.pumpWidget(
        MaterialApp(
          home: ApiLocationEditScreen(
            key: key,
            account: replacement,
            contentId: boundary == 'content' ? 8 : 7,
          ),
        ),
      );
      await tester.pump();
      expect(tester.state(find.byType(ApiLocationEditScreen)), same(state));
      expect(find.text('Save viewing area'), findsNothing);
      pending.complete(jsonReply({'success': true}));
      await tester.pumpAndSettle();
      expect(f.account!.items.firstWhere((i) => i.id == 7).locationZone, _old);
      expect(find.textContaining('update confirmed'), findsNothing);
    });
  }
  flowTest('unsent sender policy remains an explicitly local preview', (
    tester,
    f,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ViewingRequirementsScreen(
          initialRestrictions: ContentRestrictions.demoDefaults,
        ),
      ),
    );
    expect(
      find.text(
        'Local policy preview. No location is uploaded or access granted.',
      ),
      findsOneWidget,
    );
    expect(find.text('Edit shared viewing area'), findsNothing);
    expect(f.api.calls, isEmpty);
  });
}

class _OwnerFlow {
  final api = ApiFake();
  final extraAccounts = <ApiSession>[];
  final pending = <Completer<ApiReply>>[];
  Completer<ApiReply> hold() {
    final value = Completer<ApiReply>();
    pending.add(value);
    return value;
  }

  void releasePending() {
    for (final value in pending) {
      if (!value.isCompleted) value.complete(jsonReply({'success': false}));
    }
  }

  final navigator = GlobalKey<NavigatorState>();
  ApiSession? account;
  Iterable<ApiCall> get writes =>
      api.calls.where((c) => c.uri.path == _endpoint);
  Future<void> mount(
    WidgetTester tester, {
    bool editor = false,
    bool mine = true,
    LocationZone? zone = _old,
    String status = 'Active',
  }) async {
    api.contents = [_row(mine: mine, zone: zone, status: status)];
    api.routes[_endpoint] = (call) {
      api.contents = [
        for (final item in api.contents)
          {...item, ...Map<String, Object?>.from(call.json as Map)},
      ];
      return jsonReply({'success': true});
    };
    account = api.session();
    await account!.login('synthetic-user', 'fixture-password');
    await account!.refresh();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: ApiContentStatusScreen(account: account!, contentId: 7),
      ),
    );
    await tester.pumpAndSettle();
    if (editor) {
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ApiLocationEditScreen(account: account!, contentId: 7),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
  }

  void close() {
    account?.dispose();
    for (final other in extraAccounts) {
      other.dispose();
    }
  }
}
