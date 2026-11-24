import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [_]) async {
    if (!RegExp(r'^0[1-8]-[a-z-]+$').hasMatch(name)) return false;
    final directory = Directory(
      Platform.environment['APERTURE_TASK113_EVIDENCE'] ??
          'build/week11/task11-3',
    );
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
    return true;
  },
  responseDataCallback: null,
);
