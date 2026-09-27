import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final dir = Directory('../docs/demo-walkthrough');
      await dir.create(recursive: true);
      final file = File('${dir.path}/$name.png');
      await file.writeAsBytes(bytes, flush: true);
      stdout.writeln('WROTE ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
