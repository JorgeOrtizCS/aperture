import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/biometric_fake.dart';
import '../test/support/hosted_png_fixture_api.dart';
import '../tool/flutter_png_fixture_spec.dart';
import '../tool/hosted_png_viewer.dart';
import '../tool/hosted_png_viewer_transport.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'fixture delivery renders and withdraws with the native capture bridge',
    (tester) async {
      const syntheticId = 72;
      final backend = HostedPngFixtureApi(
        contentId: syntheticId,
        title: flutterPngFixtureTitle,
        maxViews: flutterPngFixtureMaxViews,
      );
      final biometrics = BiometricFake();
      await tester.pumpWidget(
        MaterialApp(
          home: HostedPngViewer(
            transport: HostedPngTransport.forFlutterAcceptance(
              backend,
              syntheticId,
            ),
            biometricAuthenticator: biometrics,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(hostedPngLabel), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'offline fixture');
      await tester.tap(find.text('Sign in as approved recipient'));
      await tester.pumpAndSettle();
      expect(find.text(flutterPngFixtureTitle), findsOneWidget);
      expect(
        backend.routes.where((route) => route.$2.endsWith('/sessions')),
        isEmpty,
      );
      await tester.tap(find.text('Verify identity and open PNG'));
      await tester.pumpAndSettle();
      final picture = find.byType(RawImage);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (picture.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(biometrics.starts, 1);
      final image = tester.widget<RawImage>(picture).image!;
      expect((image.width, image.height), (320, 180));
      expect(backend.routes.where((route) => route.$2.endsWith('/sessions')), [
        ('POST', '/api/content/$syntheticId/sessions'),
      ]);
      await tester.tap(find.text('End viewing'));
      await tester.pumpAndSettle();
      expect(picture, findsNothing);
      expect(backend.cleanupCredentials, [
        'Bearer ${HostedPngFixtureApi.token}',
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
