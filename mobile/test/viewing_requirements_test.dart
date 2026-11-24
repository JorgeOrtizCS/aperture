import 'package:aperture/screens/content_status_screen.dart';
import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/screens/share_content_screen.dart';
import 'package:aperture/screens/viewing_requirements_screen.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:aperture/widgets/content_restrictions_summary.dart';
import 'package:aperture/widgets/location_area_editor.dart';
import 'package:aperture/widgets/restriction_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const initialPolicy = ContentRestrictions(
  allowDownload: true,
  allowResharing: true,
  restrictScreenshots: false,
  accessDuration: AccessDuration.oneWeek,
  viewLimit: 1,
);

Future<void> revealInList(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
}

Future<void> tapInList(WidgetTester tester, String label) async {
  final target = find.text(label);
  await revealInList(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> scrollToTop(WidgetTester tester) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
}

Future<void> selectDuration(WidgetTester tester, String label) async {
  final dropdown = find.byType(DropdownButtonFormField<AccessDuration>);
  await Scrollable.ensureVisible(tester.element(dropdown), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> selectViewLimit(WidgetTester tester, String label) async {
  final dropdown = find.byType(DropdownButtonFormField<String>);
  await Scrollable.ensureVisible(tester.element(dropdown), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> toggle(WidgetTester tester, String title) async {
  final tile = find.widgetWithText(RestrictionTile, title);
  final control = find.descendant(of: tile, matching: find.byType(Switch));
  await Scrollable.ensureVisible(tester.element(control), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

void expectPolicy(ContentRestrictions actual, ContentRestrictions expected) {
  expect(actual.allowDownload, expected.allowDownload);
  expect(actual.allowResharing, expected.allowResharing);
  expect(actual.restrictScreenshots, expected.restrictScreenshots);
  expect(actual.accessDuration, expected.accessDuration);
  expect(actual.viewLimit, expected.viewLimit);
}

Future<void> openEditor(
  WidgetTester tester,
  ValueChanged<ContentRestrictions?> onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.theme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              onResult(
                await Navigator.push<ContentRestrictions>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ViewingRequirementsScreen(
                      initialRestrictions: initialPolicy,
                    ),
                  ),
                ),
              );
            },
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Save returns all edited settings and keeps input immutable', (
    tester,
  ) async {
    ContentRestrictions? result;
    await openEditor(tester, (value) => result = value);

    expect(
      tester
          .widget<ContentRestrictionsSection>(
            find.byType(ContentRestrictionsSection),
          )
          .restrictions,
      same(initialPolicy),
    );
    expect(tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value), [
      false, // Location is opt-in; no center is invented for an existing draft.
      true,
      true,
      false,
    ]);
    expect(find.text('7 days'), findsOneWidget);
    expect(find.text('1 view'), findsOneWidget);

    await toggle(tester, 'Allow Download');
    await toggle(tester, 'Allow Resharing');
    await toggle(tester, 'Screenshot Protection');
    await selectDuration(tester, '12 hours');
    await selectViewLimit(tester, '5 views');
    await tapInList(tester, 'Save');

    expect(find.byType(ViewingRequirementsScreen), findsNothing);
    expectPolicy(
      result!,
      const ContentRestrictions(
        allowDownload: false,
        allowResharing: false,
        restrictScreenshots: true,
        accessDuration: AccessDuration.twelveHours,
        viewLimit: 5,
      ),
    );
    expect(initialPolicy.allowDownload, isTrue);
    expect(initialPolicy.viewLimit, 1);
  });

  for (final cancelWithBack in [false, true]) {
    testWidgets(
      '${cancelWithBack ? 'Back' : 'Cancel'} discards draft changes',
      (tester) async {
        var returned = false;
        ContentRestrictions? result = initialPolicy;
        await openEditor(tester, (value) {
          returned = true;
          result = value;
        });
        await toggle(tester, 'Allow Download');
        await selectDuration(tester, '24 hours');
        await selectViewLimit(tester, 'Unlimited');
        if (cancelWithBack) {
          await tester.pageBack();
          await tester.pumpAndSettle();
        } else {
          await tapInList(tester, 'Cancel');
        }
        expect(returned, isTrue);
        expect(result, isNull);

        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();
        expectPolicy(
          tester
              .widget<ContentRestrictionsSection>(
                find.byType(ContentRestrictionsSection),
              )
              .restrictions,
          initialPolicy,
        );
      },
    );
  }

  testWidgets('Unlimited can be changed back to a finite maximum before Save', (
    tester,
  ) async {
    ContentRestrictions? result;
    await openEditor(tester, (value) => result = value);
    await selectViewLimit(tester, 'Unlimited');
    expect(
      tester
          .widget<ContentRestrictionsSection>(
            find.byType(ContentRestrictionsSection),
          )
          .restrictions
          .viewLimit,
      isNull,
    );
    await selectViewLimit(tester, '3 views');
    await tapInList(tester, 'Save');
    expect(result!.viewLimit, 3);
  });

  testWidgets('Editor and policy summary fit a narrow phone screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.theme, home: const ShareContentScreen()),
    );
    await tapInList(tester, 'Edit Policy');
    await tapInList(tester, 'Save');
    await scrollToTop(tester);
    await tester.scrollUntilVisible(
      find.byType(ContentRestrictionsSummary),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sender reviews saved area and retains it after Back', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.theme, home: const ShareContentScreen()),
    );
    final noArea = find.text('Viewing area: No area selected');
    await revealInList(tester, noArea);
    expect(noArea, findsOneWidget);
    await tapInList(tester, 'Edit Policy');
    await tapInList(tester, 'Require a viewing area');
    final latitude = find.byKey(const ValueKey('location-center-latitude'));
    final longitude = find.byKey(const ValueKey('location-center-longitude'));
    await tester.enterText(latitude, '1.25');
    await tester.enterText(longitude, '-2.5');
    await tapInList(tester, 'Save');

    expect(find.text('Viewing area: 100.0 m radius'), findsOneWidget);
    expect(find.text('Review the center in Edit Policy.'), findsOneWidget);
    await tapInList(tester, 'Edit Policy');
    final saved = tester
        .widget<LocationAreaEditor>(find.byType(LocationAreaEditor))
        .draft;
    expect(saved.latitude, '1.25');
    expect(saved.longitude, '-2.5');
    await tester.enterText(latitude, '4.5');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapInList(tester, 'Edit Policy');
    expect(
      tester.widget<LocationAreaEditor>(find.byType(LocationAreaEditor)).draft,
      same(saved),
    );
  });

  for (final viewLimit in <int?>[1, 3, 5, null]) {
    testWidgets(
      'Draft policy persists and the standalone status/viewer use it: $viewLimit',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.theme, home: const ShareContentScreen()),
        );
        final summaryTitle = find.text('Saved draft policy');
        await revealInList(tester, summaryTitle);
        expect(summaryTitle, findsOneWidget);
        expect(
          find.text('Screenshot restriction: Requested in draft'),
          findsOneWidget,
        );
        await tapInList(tester, 'Edit Policy');
        expect(find.text('Allow Download'), findsNothing);
        expect(find.text('Allow Resharing'), findsNothing);
        expect(
          find.text('Download and resharing permissions are unavailable.'),
          findsOneWidget,
        );
        await toggle(tester, 'Screenshot restriction preference');
        await selectDuration(tester, '7 days');
        await selectViewLimit(
          tester,
          viewLimit == null
              ? 'Unlimited'
              : '$viewLimit ${viewLimit == 1 ? 'view' : 'views'}',
        );
        await tapInList(tester, 'Save');

        final saved = tester
            .widget<ContentRestrictionsSummary>(
              find.byType(ContentRestrictionsSummary),
            )
            .restrictions;
        expectPolicy(
          saved,
          ContentRestrictions.demoDefaults.copyWith(
            restrictScreenshots: false,
            accessDuration: AccessDuration.oneWeek,
            viewLimit: viewLimit,
            clearViewLimit: viewLimit == null,
          ),
        );
        expect(find.text('Expiration duration: 7 days'), findsOneWidget);
        expect(
          find.text('Screenshot restriction: No preference selected'),
          findsOneWidget,
        );
        expect(
          find.text('Maximum views: ${viewLimit ?? 'Unlimited'}'),
          findsOneWidget,
        );

        // Reopen with the saved configuration; a canceled edit must not replace it.
        await tapInList(tester, 'Edit Policy');
        expectPolicy(
          tester
              .widget<ContentRestrictionsSection>(
                find.byType(ContentRestrictionsSection),
              )
              .restrictions,
          saved,
        );
        expect(
          tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value),
          [false, false],
        );
        await toggle(tester, 'Screenshot restriction preference');
        await selectViewLimit(
          tester,
          viewLimit == null ? '1 view' : 'Unlimited',
        );
        await tapInList(tester, 'Cancel');
        expect(
          tester
              .widget<ContentRestrictionsSummary>(
                find.byType(ContentRestrictionsSummary),
              )
              .restrictions,
          same(saved),
        );

        final share = find.widgetWithText(ElevatedButton, 'Share Securely');
        await tester.scrollUntilVisible(
          share,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.widget<ElevatedButton>(share).onPressed, isNull);
        expect(find.byType(ContentStatusScreen), findsNothing);

        // The status/viewer remain separate prototype fixtures. The sender
        // draft must never navigate to them as if an upload had succeeded.
        await tester.pumpWidget(
          MaterialApp(
            key: const ValueKey('standalone-status-fixture'),
            theme: AppTheme.theme,
            home: ContentStatusScreen(
              contentTitle: 'Standalone policy fixture',
              restrictions: saved,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ContentStatusScreen>(find.byType(ContentStatusScreen))
              .restrictions,
          same(saved),
        );
        await tester.scrollUntilVisible(
          find.byType(ContentRestrictionsSummary),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Configured expiration: 7 days'), findsOneWidget);
        expect(
          find.text('Maximum views: ${viewLimit ?? 'Unlimited'}'),
          findsOneWidget,
        );
        expect(find.text('Downloads: disallowed by policy'), findsOneWidget);
        expect(find.text('Resharing: disallowed by policy'), findsOneWidget);
        expect(
          find.text('Screenshot restriction: not requested'),
          findsOneWidget,
        );
        await tapInList(tester, 'Preview Policy');
        final viewer = tester.widget<SecureViewerScreen>(
          find.byType(SecureViewerScreen),
        );
        expect(viewer.restrictions, same(saved));
        expect(viewer.contentTitle, 'Standalone policy fixture');
        await tester.scrollUntilVisible(
          find.byType(ContentRestrictionsSummary),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester
              .widget<ContentRestrictionsSummary>(
                find.byType(ContentRestrictionsSummary),
              )
              .restrictions,
          same(saved),
        );
        expect(find.text('Configured expiration: 7 days'), findsOneWidget);
        expect(
          find.text('Maximum views: ${viewLimit ?? 'Unlimited'}'),
          findsOneWidget,
        );
        expect(find.text('Downloads: disallowed by policy'), findsOneWidget);
        expect(find.text('Resharing: disallowed by policy'), findsOneWidget);
        expect(
          find.text('Screenshot restriction: not requested'),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ContentStatusScreen>(find.byType(ContentStatusScreen))
              .restrictions,
          same(saved),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
