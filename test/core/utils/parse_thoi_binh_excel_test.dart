import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/excel_helper.dart';

void main() {
  final legacyFile = File('DanhSachChiTietHoaDon_KV20092026-185010-522.xlsx');
  test(
    'Verify parseInvoices on DanhSachChiTietHoaDon_KV20092026-185010-522.xlsx',
    () {
      final bytes = legacyFile.readAsBytesSync();
      final orders = ExcelHelper.parseInvoices(bytes, defaultStoreId: 'store_002');

    // 1. Total invoices count: exactly 100
    expect(orders.length, 100);

    // 2. All storeIds are store_002
    for (final o in orders) {
      expect(o.storeId, 'store_002');
    }

    // 3. Completed vs Cancelled
    final completed = orders.where((o) => o.status == 'completed').toList();
    final cancelled = orders.where((o) => o.isCancelled).toList();
    expect(completed.length, 94);
    expect(cancelled.length, 6);

    // 4. Gross revenue (Tổng tiền hàng) across all 100 invoices: 445.360.000
    final grossRevenue = orders.fold<double>(0.0, (sum, o) => sum + o.total);
    expect(grossRevenue, 445360000.0);

    // 5. Total discount: 11.330.000
    final totalDiscount = orders.fold<double>(0.0, (sum, o) => sum + o.discount);
    expect(totalDiscount, 11330000.0);

    // 6. Net payable (Khách cần trả): 434.030.000
    final totalPayable = orders.fold<double>(0.0, (sum, o) => sum + o.netPayable);
    expect(totalPayable, 434030000.0);

    // 7. Cancelled orders total: 28.480.000
    final cancelledGross = cancelled.fold<double>(0.0, (sum, o) => sum + o.total);
    expect(cancelledGross, 28480000.0);

    // 8. Total amount paid: 187.900.000
    final totalPaid = orders.fold<double>(0.0, (sum, o) => sum + o.amountPaid);
    expect(totalPaid, 187900000.0);
  }, skip: !legacyFile.existsSync() ? 'Legacy Excel file not found' : null);

  test('Adversarial: ExcelHelper.parseInvoices auto-reconstructs gross total and discount from items when row has net payable', () {
    final excel = Excel.createExcel();
    final sheet = excel[excel.sheets.keys.first];

    final headers = [
      'Mã hóa đơn',
      'Tổng cộng', // Net payable in legacy column
      'Giảm giá',  // 0.0
      'Khách đã trả',
      'Trạng thái',
      'Mã hàng',
      'Tên hàng',
      'Số lượng',
      'Đơn giá',
    ];

    for (int i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value =
          TextCellValue(headers[i]);
    }

    // Row 1: Item 1 (Price: 300k, Qty: 1)
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('HD_RECON_01');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value = const DoubleCellValue(450000.0); // Net
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1)).value = const DoubleCellValue(0.0); // No discount specified
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1)).value = const DoubleCellValue(450000.0);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1)).value = TextCellValue('Đã hoàn thành');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 1)).value = TextCellValue('SP01');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 1)).value = TextCellValue('Bàn gỗ');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 1)).value = const IntCellValue(1);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 1)).value = const DoubleCellValue(300000.0);

    // Row 2: Item 2 (Price: 200k, Qty: 1) => Items sum = 500k, raw total was 450k
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('HD_RECON_01');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 2)).value = TextCellValue('SP02');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 2)).value = TextCellValue('Ghế gỗ');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 2)).value = const IntCellValue(1);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 2)).value = const DoubleCellValue(200000.0);

    final parsed = ExcelHelper.parseInvoices(excel.encode()!);
    expect(parsed.length, 1);
    final o = parsed.first;
    expect(o.total, 500000.0, reason: 'Gross total must be reconciled to 500,000 from items');
    expect(o.discount, 50000.0, reason: 'Discount must be calculated as 50,000');
    expect(o.netPayable, 450000.0);
    expect(o.items.length, 2);
  });
}
