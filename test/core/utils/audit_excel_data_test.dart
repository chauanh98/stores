// ignore_for_file: avoid_print, unused_local_variable

import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/excel_helper.dart';

void main() {
  final suppFile = File('DanhSachNhaCungCap_KV21092026-131848-781.xlsx');
  final importFile = File('DanhSachChiTietNhapHang_KV21092026-132019-161.xlsx');
  final hasFiles = suppFile.existsSync() && importFile.existsSync();

  test('Cross-reference Suppliers and Import Receipts', () {
    final suppBytes = suppFile.readAsBytesSync();
    final suppliers = ExcelHelper.parseSuppliers(suppBytes);
    final suppMap = {for (var s in suppliers) s.code: s};

    final importBytes = importFile.readAsBytesSync();
    final fixedBytes = ExcelHelper.fixExcelPrefixesAndRels(importBytes);
    final excel = Excel.decodeBytes(fixedBytes);
    final sheet = excel.tables[excel.tables.keys.first]!;

    print('Checking cross-reference between receipts and suppliers:');
    final missingSuppliers = <String>{};
    final receiptsBySupplier = <String, double>{};

    for (int r = 1; r < sheet.maxRows; r++) {
      final row = sheet.rows[r].map((c) => c?.value?.toString() ?? '').toList();
      if (row.isEmpty || row.length < 15) continue;
      final suppCode = row[5].trim();
      final suppName = row[6].trim();
      final needPay = double.tryParse(row[13]) ?? 0.0;
      final paid = double.tryParse(row[14]) ?? 0.0;
      final debt = needPay - paid;

      if (suppCode.isNotEmpty) {
        if (!suppMap.containsKey(suppCode)) {
          missingSuppliers.add('$suppCode ($suppName)');
        }
      }
    }

    print('Missing supplier codes from receipts in supplier list: $missingSuppliers');
    print('Suppliers with NCC000005: ${suppMap['NCC000005']?.name}, debt: ${suppMap['NCC000005']?.currentDebt}, totalPurchase: ${suppMap['NCC000005']?.totalPurchase}');
  }, skip: !hasFiles ? 'Raw export Excel files not present in project root' : null);
}
