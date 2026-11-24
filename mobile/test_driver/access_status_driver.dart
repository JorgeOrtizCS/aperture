import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [_]) async {
    if (name != '01-notifications-location-denied' &&
        name != '02-permission-restored-viewing-locked') {
      return false;
    }
    final directory = Directory(
      Platform.environment['APERTURE_ACCESS_STATUS_EVIDENCE'] ??
          'build/access-status-evidence',
    );
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
    return true;
  },
  responseDataCallback: null,
);
