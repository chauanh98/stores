import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/excel_helper.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier.dart';

File? _resolveProjectFile(String filename) {
  final candidates = [
    File(filename),
    File('DATA_IMPORT/$filename'),
    File('../$filename'),
    File('../../$filename'),
    File('/Users/chauanh/FlutterProject/stores/$filename'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return file;
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const receiptsFileName = 'DanhSachChiTietNhapHang_KV21092026-132019-161.xlsx';
  const suppliersFileName = 'DanhSachNhaCungCap_KV21092026-131848-781.xlsx';
  final receiptsFile = _resolveProjectFile(receiptsFileName);
  final suppliersFile = _resolveProjectFile(suppliersFileName);
  final hasReceipts = receiptsFile != null;
  final hasBoth = receiptsFile != null && suppliersFile != null;

  group('ExcelHelper.parseStockInReceipts - Real KiotViet File Verification', () {
    late Uint8List receiptsBytes;
    late List<StockInReceipt> receipts;

    setUpAll(() {
      if (!hasReceipts) return;
      receiptsBytes = receiptsFile.readAsBytesSync();
      receipts = ExcelHelper.parseStockInReceipts(receiptsBytes);
    });

    test('parses exactly 24 consolidated receipts from 100 rows (1 header + 99 item lines)', () {
      expect(receipts.length, equals(24));
    });

    test('verifies total line items across all receipts equals exactly 99', () {
      final totalItemLines = receipts.fold<int>(0, (sum, r) => sum + r.items.length);
      expect(totalItemLines, equals(99));

      final itemCountSum = receipts.fold<int>(0, (sum, r) => sum + r.itemCount);
      expect(itemCountSum, equals(99));
    });

    test('verifies total quantity across all items equals exactly 726', () {
      final totalQuantity = receipts.fold<int>(0, (sum, r) => sum + r.totalQuantity);
      expect(totalQuantity, equals(726));

      // Also sum directly from all individual items
      final allItemsQuantity = receipts
          .expand((r) => r.items)
          .fold<int>(0, (sum, item) => sum + item.quantity);
      expect(allItemsQuantity, equals(726));
    });

    test('verifies gross totalAmount across all receipts equals 485,710,000 đ', () {
      final totalAmount = receipts.fold<double>(0.0, (sum, r) => sum + r.totalAmount);
      expect(totalAmount, equals(485710000.0));
    });

    test('verifies total receipt discount across all receipts equals 0 đ', () {
      final totalDiscount = receipts.fold<double>(0.0, (sum, r) => sum + r.discount);
      expect(totalDiscount, equals(0.0));

      for (final r in receipts) {
        expect(r.discount, equals(0.0));
      }
    });

    test('verifies total netPayable across all receipts equals 485,710,000 đ', () {
      final totalNetPayable = receipts.fold<double>(0.0, (sum, r) => sum + r.effectiveNetPayable);
      expect(totalNetPayable, equals(485710000.0));

      for (final r in receipts) {
        expect(r.effectiveNetPayable, equals(r.totalAmount - r.discount));
      }
    });

    test('verifies total paidAmount across all receipts equals 60,860,000 đ', () {
      final totalPaid = receipts.fold<double>(0.0, (sum, r) => sum + (r.paidAmount ?? 0.0));
      expect(totalPaid, equals(60860000.0));

      // Only exactly 2 receipts have paid amounts in the file:
      // PN001730: 660,000 đ and PN001719: 60,200,000 đ
      final paidReceipts = receipts.where((r) => (r.paidAmount ?? 0.0) > 0).toList();
      expect(paidReceipts.length, equals(2));

      final pn1730 = receipts.firstWhere((r) => r.importCode == 'PN001730');
      expect(pn1730.paidAmount, equals(660000.0));
      expect(pn1730.remainingDebt, equals(0.0));

      final pn1719 = receipts.firstWhere((r) => r.importCode == 'PN001719');
      expect(pn1719.paidAmount, equals(60200000.0));
      expect(pn1719.remainingDebt, equals(0.0));
    });

    test('verifies total remaining debt across all receipts equals 424,850,000 đ', () {
      final totalDebt = receipts.fold<double>(0.0, (sum, r) => sum + r.remainingDebt);
      expect(totalDebt, equals(424850000.0));

      // 22 receipts have full remaining debt, 2 receipts are fully paid
      final unpaidReceipts = receipts.where((r) => r.remainingDebt > 0).toList();
      expect(unpaidReceipts.length, equals(22));

      for (final r in unpaidReceipts) {
        expect(r.remainingDebt, equals(r.effectiveNetPayable));
      }
    });

    test('verifies branch mapping: all 24 receipts map to store_002 for Chi nhánh Thới Bình', () {
      for (final r in receipts) {
        expect(r.branchName, equals('Chi nhánh Thới Bình'));
        expect(r.storeId, equals('store_002'));
      }
    });

    test('verifies receipt codes sequence spans from PN001714 through PN001737', () {
      final codes = receipts.map((r) => r.importCode).toList();
      expect(codes.length, equals(24));

      // All 24 consecutive codes from PN001714 to PN001737 must be present
      final expectedCodes = List.generate(24, (i) => 'PN00${1714 + i}');
      expect(codes.toSet(), equals(expectedCodes.toSet()));

      // In the source file, receipts are listed descending by date (PN001737 down to PN001714)
      expect(codes.first, equals('PN001737'));
      expect(codes.last, equals('PN001714'));
    });

    test('verifies receipt dates, status, and creator information', () {
      for (final r in receipts) {
        expect(r.status, equals('Đã nhập hàng'));
        expect(r.date.year, equals(2026));
        expect(r.date.month, equals(9));
        expect(r.date.day, inInclusiveRange(1, 21));
        expect(r.createdBy, isNotNull);
        expect(r.createdBy, isNotEmpty);
      }

      // Check specific creators
      final pn1737 = receipts.firstWhere((r) => r.importCode == 'PN001737');
      expect(pn1737.createdBy, equals('aixuancute'));

      final pn1714 = receipts.firstWhere((r) => r.importCode == 'PN001714');
      expect(pn1714.createdBy, equals('Khánh Đăng'));
    });

    test('verifies item-level details (barcode, originalPrice, discount, unitPrice, totalPrice)', () {
      final allItems = receipts.expand((r) => r.items).toList();
      expect(allItems.length, equals(99));

      int barcodeCount = 0;
      for (final item in allItems) {
        // Product identification
        expect(item.productId, isNotEmpty);
        expect(item.productName, isNotEmpty);
        expect(item.quantity, greaterThan(0));
        expect(item.unitPrice, greaterThan(0.0));
        expect(item.totalPrice, greaterThan(0.0));

        // Line calculation: totalPrice == quantity * unitPrice
        expect(item.totalPrice, equals(item.quantity * item.unitPrice));

        // Pricing integrity: originalPrice >= unitPrice
        expect(item.effectiveOriginalPrice, greaterThanOrEqualTo(item.unitPrice));
        expect(item.discount, equals(0.0));
        expect(item.discountPercentage, equals(0.0));

        if (item.barcode != null && item.barcode!.isNotEmpty) {
          barcodeCount++;
        }
      }

      // 44 items in the file have barcodes, 55 are null/empty
      expect(barcodeCount, equals(44));

      // Check specific item with barcode: e.g. TREO9
      final itemWithBarcode = allItems.firstWhere((it) => it.barcode == 'TREO9');
      expect(itemWithBarcode.barcode, equals('TREO9'));

      // Check specific item without barcode
      final itemWithoutBarcode = allItems.firstWhere((it) => it.productCode == 'KET6');
      expect(itemWithoutBarcode.barcode, isNull);
      expect(itemWithoutBarcode.productName, equals('Két sắt vuông - khoá chữ - 40cm'));
      expect(itemWithoutBarcode.quantity, equals(1));
      expect(itemWithoutBarcode.unitPrice, equals(1500000.0));
      expect(itemWithoutBarcode.totalPrice, equals(1500000.0));
    });

    test('verifies multi-item receipt PN001720 with 28 items and 52 total quantity', () {
      final receipt = receipts.firstWhere((r) => r.importCode == 'PN001720');
      expect(receipt.supplierId, equals('NCC000003'));
      expect(receipt.supplierName, equals('Chú Vinh Hố Nai'));
      expect(receipt.items.length, equals(28));
      expect(receipt.totalQuantity, equals(52));
      expect(receipt.totalAmount, equals(188760000.0));
      expect(receipt.effectiveNetPayable, equals(188760000.0));
      expect(receipt.paidAmount, equals(0.0));
      expect(receipt.remainingDebt, equals(188760000.0));

      // Sum of item totals matches receipt totalAmount exactly
      final itemSum = receipt.items.fold<double>(0.0, (s, it) => s + it.totalPrice);
      expect(itemSum, equals(188760000.0));
    });

    test('verifies serialization toMap and fromMap round-trip preserves all fields', () {
      for (final r in receipts) {
        final map = r.toMap();
        final restored = StockInReceipt.fromMap(map);

        expect(restored.id, equals(r.id));
        expect(restored.importCode, equals(r.importCode));
        expect(restored.storeId, equals(r.storeId));
        expect(restored.branchName, equals(r.branchName));
        expect(restored.supplierId, equals(r.supplierId));
        expect(restored.supplierName, equals(r.supplierName));
        expect(restored.supplierPhone, equals(r.supplierPhone));
        expect(restored.totalAmount, equals(r.totalAmount));
        expect(restored.discount, equals(r.discount));
        expect(restored.effectiveNetPayable, equals(r.effectiveNetPayable));
        expect(restored.paidAmount, equals(r.paidAmount));
        expect(restored.remainingDebt, equals(r.remainingDebt));
        expect(restored.status, equals(r.status));
        expect(restored.items.length, equals(r.items.length));

        for (int i = 0; i < r.items.length; i++) {
          final origItem = r.items[i];
          final restItem = restored.items[i];
          expect(restItem.productId, equals(origItem.productId));
          expect(restItem.productName, equals(origItem.productName));
          expect(restItem.barcode, equals(origItem.barcode));
          expect(restItem.quantity, equals(origItem.quantity));
          expect(restItem.unitPrice, equals(origItem.unitPrice));
          expect(restItem.originalPrice, equals(origItem.originalPrice));
          expect(restItem.totalPrice, equals(origItem.totalPrice));
        }
      }
    });
  }, skip: !hasReceipts ? 'Real KiotViet file $receiptsFileName not found' : null);

  group('Cross-File Compatibility with DanhSachNhaCungCap', () {
    late Uint8List receiptsBytes;
    late Uint8List suppliersBytes;
    late List<StockInReceipt> receipts;
    late List<Supplier> suppliers;

    setUpAll(() {
      if (!hasBoth) return;
      receiptsBytes = receiptsFile.readAsBytesSync();
      suppliersBytes = suppliersFile.readAsBytesSync();

      receipts = ExcelHelper.parseStockInReceipts(receiptsBytes);
      suppliers = ExcelHelper.parseSuppliers(suppliersBytes);
    });

    test('parses exactly 49 suppliers from DanhSachNhaCungCap master file', () {
      expect(suppliers.length, equals(49));
    });

    test('all 24 receipts match valid supplier IDs in the supplier master file', () {
      final supplierMap = {for (final s in suppliers) s.code: s};

      // 11 distinct suppliers across all 24 receipts
      final distinctReceiptSupplierIds = receipts.map((r) => r.supplierId).toSet();
      expect(distinctReceiptSupplierIds.length, equals(11));

      for (final r in receipts) {
        expect(r.supplierId, isNotNull);
        expect(supplierMap.containsKey(r.supplierId), isTrue,
            reason: 'Receipt ${r.importCode} supplierId ${r.supplierId} not in master file');

        final masterSupplier = supplierMap[r.supplierId!]!;
        expect(r.supplierName, equals(masterSupplier.name));
      }
    });

    test('Shopee supplier NCC000050 metrics match the stock-in receipts to the exact penny', () {
      // 1. Filter receipts for Shopee (NCC000050)
      final shopeeReceipts = receipts.where((r) => r.supplierId == 'NCC000050').toList();
      expect(shopeeReceipts.length, equals(6));

      final shopeeCodes = shopeeReceipts.map((r) => r.importCode).toSet();
      expect(shopeeCodes, equals({
        'PN001717',
        'PN001723',
        'PN001726',
        'PN001727',
        'PN001730',
        'PN001733',
      }));

      // 2. Sum financial metrics from receipts
      final shopeeTotalNet = shopeeReceipts.fold<double>(0.0, (s, r) => s + r.effectiveNetPayable);
      final shopeePaid = shopeeReceipts.fold<double>(0.0, (s, r) => s + (r.paidAmount ?? 0.0));
      final shopeeDebt = shopeeReceipts.fold<double>(0.0, (s, r) => s + r.remainingDebt);

      expect(shopeeTotalNet, equals(4840000.0)); // 4.84M đ
      expect(shopeePaid, equals(660000.0));      // 660k đ (PN001730)
      expect(shopeeDebt, equals(4180000.0));      // 4.18M đ

      // 3. Compare with master supplier file
      final shopeeMaster = suppliers.firstWhere((s) => s.code == 'NCC000050');
      expect(shopeeMaster.name, equals('Shopee'));
      expect(shopeeMaster.phone, equals('0956113861'));
      expect(shopeeMaster.totalPurchase, equals(shopeeTotalNet));
      expect(shopeeMaster.currentDebt, equals(shopeeDebt));
    });

    test('preserves supplier phone numbers with leading zeros', () {
      final loiPhat = receipts.firstWhere((r) => r.supplierId == 'NCC000005');
      expect(loiPhat.supplierPhone, equals('0003531308'));

      final chuVinh = receipts.firstWhere((r) => r.supplierId == 'NCC000003');
      expect(chuVinh.supplierPhone, equals('0001'));

      final chuThao = receipts.firstWhere((r) => r.supplierId == 'NCC000006');
      expect(chuThao.supplierPhone, equals('00004'));
    });
  }, skip: !hasBoth ? 'Real KiotViet master files not found' : null);

  group('Branch Mapping & Fallbacks', () {
    test('maps Chi nhánh Thới Bình to store_002', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      final headers = [
        'Chi nhánh',
        'Mã nhập hàng',
        'Thời gian',
        'Mã nhà cung cấp',
        'Tên nhà cung cấp',
        'Tổng tiền hàng',
        'Cần trả NCC',
        'Trạng thái',
        'Mã hàng',
        'Tên hàng',
        'Số lượng',
        'Đơn giá',
        'Thành tiền',
      ];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      final row = [
        'Chi nhánh Thới Bình',
        'PN_TEST_01',
        '2026-09-21 10:00:00',
        'NCC001',
        'Nhà cung cấp 1',
        1000000,
        1000000,
        'Đã nhập hàng',
        'SP01',
        'Sản phẩm 1',
        2,
        500000,
        1000000,
      ];
      for (int i = 0; i < row.length; i++) {
        final val = row[i];
        if (val is num) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = DoubleCellValue(val.toDouble());
        } else {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = TextCellValue(val.toString());
        }
      }

      final bytes = excel.encode()!;
      final parsed = ExcelHelper.parseStockInReceipts(bytes);

      expect(parsed.length, equals(1));
      expect(parsed.first.branchName, equals('Chi nhánh Thới Bình'));
      expect(parsed.first.storeId, equals('store_002'));
    });

    test('maps Chi nhánh Đông Thắng to store_001', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      final headers = [
        'Chi nhánh',
        'Mã nhập hàng',
        'Thời gian',
        'Mã nhà cung cấp',
        'Tên nhà cung cấp',
        'Tổng tiền hàng',
        'Cần trả NCC',
        'Trạng thái',
        'Mã hàng',
        'Tên hàng',
        'Số lượng',
        'Đơn giá',
        'Thành tiền',
      ];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      final row = [
        'Chi nhánh Đông Thắng',
        'PN_TEST_02',
        '2026-09-21 11:00:00',
        'NCC002',
        'Nhà cung cấp 2',
        2000000,
        2000000,
        'Đã nhập hàng',
        'SP02',
        'Sản phẩm 2',
        4,
        500000,
        2000000,
      ];
      for (int i = 0; i < row.length; i++) {
        final val = row[i];
        if (val is num) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = DoubleCellValue(val.toDouble());
        } else {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = TextCellValue(val.toString());
        }
      }

      final bytes = excel.encode()!;
      final parsed = ExcelHelper.parseStockInReceipts(bytes);

      expect(parsed.length, equals(1));
      expect(parsed.first.branchName, equals('Chi nhánh Đông Thắng'));
      expect(parsed.first.storeId, equals('store_001'));
    });

    test('falls back to defaultStoreId when branch is unknown or empty', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      final headers = [
        'Chi nhánh',
        'Mã nhập hàng',
        'Thời gian',
        'Mã nhà cung cấp',
        'Tên nhà cung cấp',
        'Tổng tiền hàng',
        'Cần trả NCC',
        'Trạng thái',
        'Mã hàng',
        'Tên hàng',
        'Số lượng',
        'Đơn giá',
        'Thành tiền',
      ];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      final row = [
        'Chi nhánh Khác',
        'PN_TEST_03',
        '2026-09-21 12:00:00',
        'NCC003',
        'Nhà cung cấp 3',
        1500000,
        1500000,
        'Đã nhập hàng',
        'SP03',
        'Sản phẩm 3',
        3,
        500000,
        1500000,
      ];
      for (int i = 0; i < row.length; i++) {
        final val = row[i];
        if (val is num) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = DoubleCellValue(val.toDouble());
        } else {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = TextCellValue(val.toString());
        }
      }

      final bytes = excel.encode()!;
      final parsedWithCustomDefault = ExcelHelper.parseStockInReceipts(bytes, defaultStoreId: 'store_custom');
      expect(parsedWithCustomDefault.first.storeId, equals('store_custom'));

      final parsedWithFallback = ExcelHelper.parseStockInReceipts(bytes);
      expect(parsedWithFallback.first.storeId, equals('store_001'));
    });
  });

  group('Item-Level Discount & Financial Pricing Logic (Synthetic)', () {
    test('parses line items with discount, discountPercentage and receipt discount correctly', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      final headers = [
        'Chi nhánh',
        'Mã nhập hàng',
        'Thời gian',
        'Mã nhà cung cấp',
        'Tên nhà cung cấp',
        'Tổng tiền hàng',
        'Giảm giá phiếu nhập',
        'Cần trả NCC',
        'Tiền đã trả NCC',
        'Trạng thái',
        'Mã hàng',
        'Mã vạch',
        'Tên hàng',
        'Đơn giá',
        'Giảm giá %',
        'Giảm giá',
        'Giá nhập',
        'Thành tiền',
        'Số lượng',
      ];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      // Line 1: Item 1 with 10% discount (original 100,000, discount 10,000, net importPrice 90,000, qty 2 -> total 180,000)
      final row1 = [
        'Chi nhánh Thới Bình',
        'PN_SYNTH_01',
        '2026-09-21 14:00:00',
        'NCC999',
        'NCC Test',
        430000, // Total subtotal = 180,000 + 250,000 = 430,000
        30000,  // Receipt discount
        400000, // Net payable = 430,000 - 30,000 = 400,000
        100000, // Paid amount
        'Đã nhập hàng',
        'SP_DISC_1',
        'BARCODE_123',
        'Sản phẩm giảm giá dòng',
        100000, // originalPrice
        10,     // discount %
        10000,  // line discount
        90000,  // import price after line discount
        180000, // line total
        2,      // quantity
      ];
      for (int i = 0; i < row1.length; i++) {
        final val = row1[i];
        if (val is num) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = DoubleCellValue(val.toDouble());
        } else {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = TextCellValue(val.toString());
        }
      }

      // Line 2: Item 2 without discount (original 250,000, net importPrice 250,000, qty 1 -> total 250,000)
      final row2 = [
        'Chi nhánh Thới Bình',
        'PN_SYNTH_01',
        '2026-09-21 14:00:00',
        'NCC999',
        'NCC Test',
        430000,
        30000,
        400000,
        100000,
        'Đã nhập hàng',
        'SP_DISC_2',
        '',
        'Sản phẩm không giảm giá',
        250000,
        0,
        0,
        250000,
        250000,
        1,
      ];
      for (int i = 0; i < row2.length; i++) {
        final val = row2[i];
        if (val is num) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2)).value = DoubleCellValue(val.toDouble());
        } else {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2)).value = TextCellValue(val.toString());
        }
      }

      final bytes = excel.encode()!;
      final parsed = ExcelHelper.parseStockInReceipts(bytes);

      expect(parsed.length, equals(1));
      final receipt = parsed.first;

      expect(receipt.importCode, equals('PN_SYNTH_01'));
      expect(receipt.totalAmount, equals(430000.0));
      expect(receipt.discount, equals(30000.0));
      expect(receipt.effectiveNetPayable, equals(400000.0));
      expect(receipt.paidAmount, equals(100000.0));
      expect(receipt.remainingDebt, equals(300000.0));
      expect(receipt.items.length, equals(2));

      // Item 1
      final item1 = receipt.items[0];
      expect(item1.productId, equals('SP_DISC_1'));
      expect(item1.barcode, equals('BARCODE_123'));
      expect(item1.originalPrice, equals(100000.0));
      expect(item1.discountPercentage, equals(10.0));
      expect(item1.discount, equals(10000.0));
      expect(item1.unitPrice, equals(90000.0));
      expect(item1.importPrice, equals(90000.0));
      expect(item1.quantity, equals(2));
      expect(item1.totalPrice, equals(180000.0));

      // Item 2
      final item2 = receipt.items[1];
      expect(item2.productId, equals('SP_DISC_2'));
      expect(item2.barcode, isNull);
      expect(item2.originalPrice, equals(250000.0));
      expect(item2.discountPercentage, equals(0.0));
      expect(item2.discount, equals(0.0));
      expect(item2.unitPrice, equals(250000.0));
      expect(item2.quantity, equals(1));
      expect(item2.totalPrice, equals(250000.0));
    });
  });

  group('Adversarial & Edge Cases', () {
    test('returns empty list on empty byte array', () {
      final result = ExcelHelper.parseStockInReceipts([]);
      expect(result, isEmpty);
    });

    test('returns empty list on corrupted or non-Excel bytes', () {
      final result = ExcelHelper.parseStockInReceipts([1, 2, 3, 4, 5]);
      expect(result, isEmpty);
    });

    test('returns empty list when Excel sheet contains no matching headers', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Unrelated');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = TextCellValue('Columns');

      final bytes = excel.encode()!;
      final result = ExcelHelper.parseStockInReceipts(bytes);
      expect(result, isEmpty);
    });

    test('skips total / summary rows (starts with Tổng, Cộng, Total)', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      final headers = [
        'Mã nhập hàng',
        'Mã hàng',
        'Tên hàng',
        'Số lượng',
        'Đơn giá',
        'Thành tiền',
      ];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      // Valid item row
      final row1 = ['PN_SUM_01', 'SP01', 'Bàn làm việc', 1, 1000000, 1000000];
      for (int i = 0; i < row1.length; i++) {
        final val = row1[i];
        if (val is num) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = DoubleCellValue(val.toDouble());
        } else {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = TextCellValue(val.toString());
        }
      }

      // Summary row 1: 'Tổng cộng'
      final row2 = ['Tổng cộng', '', '', 1, 1000000, 1000000];
      for (int i = 0; i < row2.length; i++) {
        final val = row2[i];
        if (val is num) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2)).value = DoubleCellValue(val.toDouble());
        } else {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2)).value = TextCellValue(val.toString());
        }
      }

      // Summary row 2: 'Cộng tiền hàng'
      final row3 = ['Cộng tiền hàng', '', '', 1, 1000000, 1000000];
      for (int i = 0; i < row3.length; i++) {
        final val = row3[i];
        if (val is num) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 3)).value = DoubleCellValue(val.toDouble());
        } else {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 3)).value = TextCellValue(val.toString());
        }
      }

      // Summary row 3: 'Total'
      final row4 = ['Total', '', '', 1, 1000000, 1000000];
      for (int i = 0; i < row4.length; i++) {
        final val = row4[i];
        if (val is num) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 4)).value = DoubleCellValue(val.toDouble());
        } else {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 4)).value = TextCellValue(val.toString());
        }
      }

      final bytes = excel.encode()!;
      final result = ExcelHelper.parseStockInReceipts(bytes);

      expect(result.length, equals(1));
      expect(result.first.importCode, equals('PN_SUM_01'));
      expect(result.first.items.length, equals(1));
    });

    test('ignores item rows with both productId and productName empty', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      final headers = [
        'Mã nhập hàng',
        'Mã hàng',
        'Tên hàng',
        'Số lượng',
        'Đơn giá',
        'Thành tiền',
      ];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      // Valid row
      final row1 = ['PN_EMP_01', 'SP01', 'Ghế đẩu', 2, 150000, 300000];
      for (int i = 0; i < row1.length; i++) {
        final val = row1[i];
        if (val is num) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = DoubleCellValue(val.toDouble());
        } else {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = TextCellValue(val.toString());
        }
      }

      // Empty item row with same importCode
      final row2 = ['PN_EMP_01', '', '', 0, 0, 0];
      for (int i = 0; i < row2.length; i++) {
        final val = row2[i];
        if (val is num) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2)).value = DoubleCellValue(val.toDouble());
        } else {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2)).value = TextCellValue(val.toString());
        }
      }

      final bytes = excel.encode()!;
      final result = ExcelHelper.parseStockInReceipts(bytes);

      expect(result.length, equals(1));
      expect(result.first.items.length, equals(1));
      expect(result.first.items.first.productId, equals('SP01'));
    });

    test('parses currency strings with đ, Đ, VND, vnd, and whitespace correctly in _parseDoubleStrict', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      final headers = [
        'Mã nhập hàng',
        'Mã hàng',
        'Tên hàng',
        'Số lượng',
        'Đơn giá',
        'Thành tiền',
        'Tổng tiền hàng',
        'Giảm giá phiếu nhập',
        'Cần trả NCC',
        'Tiền đã trả NCC',
      ];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      final row = [
        'PN_CURR_TEST',
        'SP_CURR',
        'Sản phẩm tiền tệ',
        2,
        ' 500,000 đ ',
        ' 1,000,000 Đ ',
        ' 1,000,000 VND ',
        ' 100,000 vnd ',
        ' 900,000 đ ',
        ' 400,000 VND ',
      ];
      for (int i = 0; i < row.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = TextCellValue(row[i].toString());
      }

      final bytes = excel.encode()!;
      final result = ExcelHelper.parseStockInReceipts(bytes);

      expect(result.length, equals(1));
      final receipt = result.first;
      expect(receipt.totalAmount, equals(1000000.0));
      expect(receipt.discount, equals(100000.0));
      expect(receipt.effectiveNetPayable, equals(900000.0));
      expect(receipt.paidAmount, equals(400000.0));
      expect(receipt.remainingDebt, equals(500000.0));

      final item = receipt.items.first;
      expect(item.quantity, equals(2));
      expect(item.unitPrice, equals(500000.0));
      expect(item.totalPrice, equals(1000000.0));
    });
  });
}
