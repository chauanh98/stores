// ignore_for_file: avoid_print, unused_local_variable

import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/excel_helper.dart';

void main() {
  test('Inspect KiotViet import and supplier excel files', () {
    inspectExcel('DATA_IMPORT/DanhSachNhaCungCap_KV21092026-213547-088.xlsx');
    final file = File('DATA_IMPORT/DanhSachNhaCungCap_KV21092026-213547-088.xlsx');
    if (file.existsSync()) {
      final suppliers = ExcelHelper.parseSuppliers(file.readAsBytesSync());
      print('=== Parsed Suppliers count: ${suppliers.length} ===');
      final totalDebt = suppliers.fold<double>(0.0, (sum, s) => sum + s.currentDebt);
      final totalPurchase = suppliers.fold<double>(0.0, (sum, s) => sum + s.totalPurchase);
      print('=== Total Debt from Excel: $totalDebt ===');
      print('=== Total Purchase from Excel: $totalPurchase ===');
      for (final s in suppliers.take(5)) {
        print('Supplier: code=${s.code}, name=${s.name}, phone=${s.phone}, debt=${s.currentDebt}, purchase=${s.totalPurchase}, branch=${s.branch}');
      }
    }
  });
}

void inspectExcel(String path) {
  print('=== Inspecting file: $path ===');
  final file = File(path);
  if (!file.existsSync()) {
    print('File does not exist: $path');
    return;
  }
  final bytes = file.readAsBytesSync();
  final fixedBytes = ExcelHelper.fixExcelPrefixesAndRels(bytes);
  final excel = Excel.decodeBytes(fixedBytes);

  for (final table in excel.tables.keys) {
    print('--- Sheet: $table ---');
    final sheet = excel.tables[table]!;
    print('Total rows: ${sheet.rows.length}, maxColumns: ${sheet.maxColumns}');
    for (int i = 0; i < (sheet.rows.length < 15 ? sheet.rows.length : 15); i++) {
      final rowVals = sheet.rows[i].map((c) => c?.value?.toString() ?? '').toList();
      print('Row $i: $rowVals');
    }
  }
}
