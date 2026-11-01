import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final dir = Directory('/tmp/do-my-chore-goal-wallet');
  await dir.create(recursive: true);
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('${dir.path}/$name.png');
      await file.writeAsBytes(bytes, flush: true);
      stdout.writeln('WROTE ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
