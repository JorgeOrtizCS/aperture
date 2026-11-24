import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (data) async {
      final label = Platform.environment['APERTURE_PERF_LABEL'] ?? 'unlabeled';
      final result = data?['aperture_workload'];
      if (result == null) throw StateError('No completed performance workload');
      final output = File('docs/week10/task10-2/$label.json');
      await output.parent.create(recursive: true);
      await output.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
