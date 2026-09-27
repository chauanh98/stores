import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/file_saver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      return Directory.systemTemp.path;
    },
  );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/share'),
    (MethodCall methodCall) async {
      return null;
    },
  );

  test('saveExcelFile executes on native platform without error', () async {
    final bytes = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]); // PK zip header
    const fileName = 'test_export.xlsx';

    await expectLater(saveExcelFile(bytes, fileName), completes);

    final savedFile = File('${Directory.systemTemp.path}/$fileName');
    expect(await savedFile.exists(), isTrue);
    expect(await savedFile.readAsBytes(), equals(bytes));
  });
}
