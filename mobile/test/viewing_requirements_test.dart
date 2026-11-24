import 'package:aperture/screens/content_status_screen.dart';
import 'package:aperture/screens/secure_viewer_screen.dart';
import 'package:aperture/screens/share_content_screen.dart';
import 'package:aperture/screens/viewing_requirements_screen.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/widgets/content_restrictions_section.dart';
import 'package:aperture/widgets/content_restrictions_summary.dart';
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

Future<void> tapInList(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
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

  for (final viewLimit in <int?>[1, 3, 5, null]) {
    testWidgets(
      'Saved policy flows through share, status and viewer: $viewLimit',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.theme, home: const ShareContentScreen()),
        );
        await tapInList(tester, 'Edit Policy');
        await toggle(tester, 'Allow Download');
        await toggle(tester, 'Allow Resharing');
        await toggle(tester, 'Screenshot Protection');
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
          initialPolicy.copyWith(
            viewLimit: viewLimit,
            clearViewLimit: viewLimit == null,
          ),
        );
        expect(find.text('Configured expiration: 7 days'), findsOneWidget);
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
          [true, true, false],
        );
        await toggle(tester, 'Allow Download');
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

        await scrollToTop(tester);
        await tapInList(tester, 'Select content');
        await tester.enterText(
          find.byType(TextField).last,
          'viewer@example.com',
        );
        await tapInList(tester, 'Share Securely');
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
        expect(find.text('Downloads: allowed by policy'), findsOneWidget);
        expect(find.text('Resharing: allowed by policy'), findsOneWidget);
        expect(
          find.text('Screenshot restriction: not requested'),
          findsOneWidget,
        );
        await tapInList(tester, 'Preview Policy');
        final viewer = tester.widget<SecureViewerScreen>(
          find.byType(SecureViewerScreen),
        );
        expect(viewer.restrictions, same(saved));
        expect(viewer.contentTitle, 'Project Document.pdf');
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
        expect(find.text('Downloads: allowed by policy'), findsOneWidget);
        expect(find.text('Resharing: allowed by policy'), findsOneWidget);
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
