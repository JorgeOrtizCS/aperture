import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory(
    Platform.environment['APERTURE_DOCUMENT_ZOOM_EVIDENCE'] ??
        'build/document-viewer-zoom-evidence',
  );
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [_]) async {
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
