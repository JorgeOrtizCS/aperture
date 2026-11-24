import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [_]) async {
      if (name != '01-synthetic-png-rendered' &&
          name != '02-synthetic-png-withdrawn' &&
          name != '03-synthetic-png-after-resume') {
        return false;
      }
      final directory = Directory(
        Platform.environment['APERTURE_RECIPIENT_EVIDENCE'] ??
            'build/recipient-png-evidence',
      );
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: null,
  );
}
