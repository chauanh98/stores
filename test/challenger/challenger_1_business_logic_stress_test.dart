import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/import_stock_in_receipts_usecase.dart';
import 'package:stores/core/utils/excel_helper.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

File _resolveProjectFile(String filename) {
  final candidates = [
    File(filename),
    File('../$filename'),
    File('../../$filename'),
    File('/Users/chauanh/FlutterProject/stores/$filename'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return file;
    }
  }
  throw StateError('Could not find required project test file: $filename');
}

// -----------------------------------------------------------------------------
// In-Memory Test Harness Repositories
// -----------------------------------------------------------------------------
class _HarnessProductRepo implements ProductRepository {
  final Map<String, Product> products = {};

  _HarnessProductRepo([List<Product> initial = const []]) {
    for (final p in initial) {
      products[p.id] = p;
    }
  }

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<void> upsert(Product product) async {
    products[product.id] = product;
  }

  @override
  Future<void> delete(String id) async {
    products.remove(id);
  }

  @override
  Future<void> updateStock(String id, int newStock) async {
    if (products.containsKey(id)) {
      final p = products[id]!;
      final newStocks = Map<String, int>.from(p.branchStocks);
      newStocks['store_001'] = newStock;
      products[id] = p.copyWith(branchStocks: newStocks);
    }
  }
}

class _HarnessInventoryRepo implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) {
    return Stream.value(
        transactions.where((t) => t.productId == productId).toList());
  }

  @override
  Future<void> record(InventoryTransaction tx) async {
    transactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
      DateTime startDate, DateTime endDate) {
    return Stream.value(transactions
        .where((t) =>
            t.type == TransactionType.import &&
            !t.date.isBefore(startDate) &&
            !t.date.isAfter(endDate))
        .toList());
  }
}

class _HarnessSupplierRepo implements SupplierRepository {
  final Map<String, Supplier> suppliers = {};
  final List<SupplierDebtTransaction> debtTransactions = [];

  _HarnessSupplierRepo([List<Supplier> initial = const []]) {
    for (final s in initial) {
      suppliers[s.id] = s;
    }
  }

  @override
  Stream<List<Supplier>> watchAll({String? storeId}) =>
      Stream.value(suppliers.values.toList());

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async =>
      suppliers[id];

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    suppliers[supplier.id] = supplier;
  }

  @override
  Future<void> delete(String id, {String? storeId}) async {
    suppliers.remove(id);
  }

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction transaction,
      {String? storeId}) async {
    debtTransactions.add(transaction);
  }

  @override
  Stream<List<SupplierDebtTransaction>> watchDebtTransactions(
      String supplierId, {String? storeId}) {
    return Stream.value(
        debtTransactions.where((d) => d.supplierId == supplierId).toList());
  }

  @override
  Future<List<SupplierDebtTransaction>> fetchDebtTransactions(
      String supplierId, {String? storeId}) async {
    return debtTransactions
        .where((d) => d.supplierId == supplierId)
        .toList();
  }
}

class _HarnessSupplierDebtRepo implements SupplierDebtTransactionRepository {
  final List<SupplierDebtTransaction> recorded = [];

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction transaction,
      {String? storeId}) async {
    recorded.add(transaction);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const receiptsFileName = 'DanhSachChiTietNhapHang_KV21092026-132019-161.xlsx';
  const suppliersFileName = 'DanhSachNhaCungCap_KV21092026-131848-781.xlsx';

  group('CHALLENGER 1: Empirical Verification of Real KiotViet File Invariants', () {
    late Uint8List receiptsBytes;
    late Uint8List suppliersBytes;
    late List<StockInReceipt> receipts;
    late List<Supplier> suppliers;

    setUpAll(() {
      final receiptsFile = _resolveProjectFile(receiptsFileName);
      final suppliersFile = _resolveProjectFile(suppliersFileName);
      receiptsBytes = receiptsFile.readAsBytesSync();
      suppliersBytes = suppliersFile.readAsBytesSync();

      receipts = ExcelHelper.parseStockInReceipts(receiptsBytes);
      suppliers = ExcelHelper.parseSuppliers(suppliersBytes);
    });

    test('INVARIANT 1: Exactly 24 consolidated receipts from 100 rows (99 item rows)', () {
      expect(receipts.length, equals(24),
          reason: 'Must group 99 item lines into exactly 24 distinct receipts');
      final totalLines = receipts.fold<int>(0, (sum, r) => sum + r.items.length);
      expect(totalLines, equals(99),
          reason: 'Total item lines across all 24 receipts must equal 99');
    });

    test('INVARIANT 2: Total quantity across all items equals exactly 726', () {
      final totalQty = receipts.fold<int>(0, (sum, r) => sum + r.totalQuantity);
      expect(totalQty, equals(726),
          reason: 'Total physical unit quantity must match KiotViet file total of 726');

      final directItemQty = receipts
          .expand((r) => r.items)
          .fold<int>(0, (sum, it) => sum + it.quantity);
      expect(directItemQty, equals(726));
    });

    test('INVARIANT 3: Total gross amount == 485,710,000 đ', () {
      final gross = receipts.fold<double>(0.0, (sum, r) => sum + r.totalAmount);
      expect(gross, equals(485710000.0),
          reason: 'Gross total amount must equal 485,710,000 đ');

      // Check sum of line totals matches receipt gross amounts
      for (final r in receipts) {
        final lineSum = r.items.fold<double>(0.0, (s, it) => s + it.totalPrice);
        expect(lineSum, equals(r.totalAmount),
            reason: 'Receipt ${r.importCode} sum of lines ($lineSum) must match totalAmount (${r.totalAmount})');
      }
    });

    test('INVARIANT 4: Total paid amount == 60,860,000 đ (PN001730: 660,000 đ and PN001719: 60,200,000 đ)', () {
      final paid = receipts.fold<double>(0.0, (sum, r) => sum + (r.paidAmount ?? 0.0));
      expect(paid, equals(60860000.0),
          reason: 'Total paid across all receipts must equal 60,860,000 đ');

      final pn1730 = receipts.firstWhere((r) => r.importCode == 'PN001730');
      expect(pn1730.paidAmount, equals(660000.0));
      expect(pn1730.remainingDebt, equals(0.0));

      final pn1719 = receipts.firstWhere((r) => r.importCode == 'PN001719');
      expect(pn1719.paidAmount, equals(60200000.0));
      expect(pn1719.remainingDebt, equals(0.0));

      // All remaining 22 receipts must have paidAmount == 0.0
      final zeroPaidReceipts = receipts.where((r) => (r.paidAmount ?? 0.0) == 0.0).toList();
      expect(zeroPaidReceipts.length, equals(22));
    });

    test('INVARIANT 5: Total debt == 424,850,000 đ (485,710,000 - 60,860,000 = 424,850,000)', () {
      final debt = receipts.fold<double>(0.0, (sum, r) => sum + r.remainingDebt);
      expect(debt, equals(424850000.0),
          reason: 'Total remaining debt must equal 424,850,000 đ');

      final totalNet = receipts.fold<double>(0.0, (sum, r) => sum + r.effectiveNetPayable);
      final totalPaid = receipts.fold<double>(0.0, (sum, r) => sum + (r.paidAmount ?? 0.0));
      expect(totalNet - totalPaid, equals(debt),
          reason: 'Fundamental debt identity: NetPayable - Paid == RemainingDebt');
    });

    test('INVARIANT 6: 100% of receipt suppliers exist in DanhSachNhaCungCap', () {
      final supplierMap = {for (final s in suppliers) s.code: s};
      final receiptSupplierIds = receipts.map((r) => r.supplierId).toSet();

      // Exactly 11 distinct suppliers across all 24 receipts
      expect(receiptSupplierIds.length, equals(11));

      for (final sId in receiptSupplierIds) {
        expect(sId, isNotNull);
        expect(supplierMap.containsKey(sId), isTrue,
            reason: 'Supplier ID $sId in stock-in receipts MUST exist in supplier master file');
      }

      // Check supplier name consistency
      for (final r in receipts) {
        final master = supplierMap[r.supplierId!]!;
        expect(r.supplierName, equals(master.name),
            reason: 'Receipt supplier name must match master file supplier name exactly');
      }
    });

    test('INVARIANT 7: Branch mapping correctly routes 100% receipts to store_002 for Thới Bình', () {
      for (final r in receipts) {
        expect(r.branchName, equals('Chi nhánh Thới Bình'));
        expect(r.storeId, equals('store_002'));
      }
    });

    test('INVARIANT 8: Every line item satisfies totalPrice == quantity * unitPrice', () {
      final allItems = receipts.expand((r) => r.items);
      for (final item in allItems) {
        expect(item.quantity, greaterThan(0));
        expect(item.unitPrice, greaterThan(0.0));
        expect(item.totalPrice, equals(item.quantity * item.unitPrice));
      }
    });
  });

  group('CHALLENGER 1: Adversarial Stress Testing of ExcelHelper.parseStockInReceipts', () {
    test('handles commas and spaces in price strings without throw', () {
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
        'Tiền đã trả NCC',
      ];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      final row = [
        'PN_ADV_01',
        'SKU_ADV_1',
        'Ghế Sofa Da',
        '  5  ',
        ' 1,500,000 ',
        ' 7,500,000 ',
        ' 7500000 ',
        ' 2,000,000 ',
      ];
      for (int i = 0; i < row.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = TextCellValue(row[i].toString());
      }

      final bytes = excel.encode()!;
      final parsed = ExcelHelper.parseStockInReceipts(bytes);

      expect(parsed.length, equals(1));
      final r = parsed.first;
      expect(r.importCode, equals('PN_ADV_01'));
      expect(r.items.first.quantity, equals(5));
      expect(r.items.first.unitPrice, equals(1500000.0));
      expect(r.items.first.totalPrice, equals(7500000.0));
      expect(r.totalAmount, equals(7500000.0));
      expect(r.paidAmount, equals(2000000.0));
      expect(r.remainingDebt, equals(5500000.0));
    });

    test('EDGE CASE: Non-numeric currency symbols (đ, VND) are stripped cleanly in _parseDoubleStrict', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      final headers = ['Mã nhập hàng', 'Mã hàng', 'Tên hàng', 'Số lượng', 'Đơn giá', 'Thành tiền'];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      final row = ['PN_CURR_01', 'SKU_CURR', 'Bàn trang điểm', 1, '500,000 đ', '500,000 đ'];
      for (int i = 0; i < row.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = TextCellValue(row[i].toString());
      }

      final bytes = excel.encode()!;
      final parsed = ExcelHelper.parseStockInReceipts(bytes);

      expect(parsed.length, equals(1));
      // Confirms fix: currency symbol 'đ' is stripped and parsed cleanly
      expect(parsed.first.items.first.unitPrice, equals(500000.0));
      expect(parsed.first.items.first.totalPrice, equals(500000.0));
    });

    test('handles interleaved rows: lines for same receipt separated by other receipts', () {
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

      // Interleaved:
      // Row 1: Receipt A (Item 1)
      // Row 2: Receipt B (Item 1)
      // Row 3: Receipt A (Item 2)
      final rows = [
        ['PN_INTER_A', 'SKU_A1', 'Hàng A1', 2, 100000, 200000],
        ['PN_INTER_B', 'SKU_B1', 'Hàng B1', 1, 300000, 300000],
        ['PN_INTER_A', 'SKU_A2', 'Hàng A2', 3, 150000, 450000],
      ];
      for (int r = 0; r < rows.length; r++) {
        for (int c = 0; c < rows[r].length; c++) {
          final val = rows[r][c];
          if (val is num) {
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value = DoubleCellValue(val.toDouble());
          } else {
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value = TextCellValue(val.toString());
          }
        }
      }

      final bytes = excel.encode()!;
      final parsed = ExcelHelper.parseStockInReceipts(bytes);

      expect(parsed.length, equals(2));
      final receiptA = parsed.firstWhere((r) => r.importCode == 'PN_INTER_A');
      expect(receiptA.items.length, equals(2));
      expect(receiptA.totalQuantity, equals(5));
      expect(receiptA.totalAmount, equals(650000.0));

      final receiptB = parsed.firstWhere((r) => r.importCode == 'PN_INTER_B');
      expect(receiptB.items.length, equals(1));
      expect(receiptB.totalQuantity, equals(1));
      expect(receiptB.totalAmount, equals(300000.0));
    });

    test('preserves order of receipts as they first appear in file', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      final headers = ['Mã nhập hàng', 'Mã hàng', 'Tên hàng', 'Số lượng', 'Đơn giá', 'Thành tiền'];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      final codes = ['PN_FIRST', 'PN_SECOND', 'PN_THIRD'];
      for (int i = 0; i < codes.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = TextCellValue(codes[i]);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = TextCellValue('SKU_$i');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1)).value = TextCellValue('Name $i');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1)).value = const DoubleCellValue(1);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1)).value = const DoubleCellValue(10000);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i + 1)).value = const DoubleCellValue(10000);
      }

      final bytes = excel.encode()!;
      final parsed = ExcelHelper.parseStockInReceipts(bytes);
      expect(parsed.map((r) => r.importCode).toList(), equals(codes));
    });
  });

  group('CHALLENGER 1: Weighted Average Cost Mathematical Auditing in ImportStockInReceiptsUseCase', () {
    late _HarnessProductRepo productRepo;
    late _HarnessInventoryRepo inventoryRepo;
    late _HarnessSupplierRepo supplierRepo;
    late ImportStockInReceiptsUseCase useCase;

    setUp(() {
      productRepo = _HarnessProductRepo();
      inventoryRepo = _HarnessInventoryRepo();
      supplierRepo = _HarnessSupplierRepo();
      useCase = ImportStockInReceiptsUseCase(
        productRepo: productRepo,
        inventoryRepo: inventoryRepo,
        supplierRepo: supplierRepo,
      );
    });

    test('Case 1: Clean initialization (currentStock == 0) sets costPrice to incoming unit price', () async {
      const prod = Product(
        id: 'p1',
        name: 'Giường 1m8',
        code: 'G18',
        price: 5000000,
        costPrice: 0.0,
        branchStocks: {'store_002': 0},
        category: 'Nội thất phòng ngủ',
      );
      await productRepo.upsert(prod);

      final receipt = StockInReceipt(
        id: 'R1',
        importCode: 'R1',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'G18',
            quantity: 10,
            unitPrice: 2500000,
          ),
        ],
      );

      final res = await useCase.execute(receipts: [receipt], storeId: 'store_002');
      expect(res.isSuccess, isTrue);

      final updated = await productRepo.fetchById('p1');
      expect(updated!.costPrice, equals(2500000.0));
      expect(updated.branchStocks['store_002'], equals(10));
    });

    test('Case 2: Standard dilution: (20 * 100k + 10 * 160k) / 30 == 120k', () async {
      const prod = Product(
        id: 'p2',
        name: 'Tủ Quần Áo',
        code: 'TQA',
        price: 300000,
        costPrice: 100000,
        branchStocks: {'store_001': 10, 'store_002': 10}, // Total stock = 20
        category: 'Nội thất phòng ngủ',
      );
      await productRepo.upsert(prod);

      final receipt = StockInReceipt(
        id: 'R2',
        importCode: 'R2',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        items: const [
          StockInReceiptItem(
            transactionId: 't2',
            productId: 'TQA',
            quantity: 10,
            unitPrice: 160000,
          ),
        ],
      );

      await useCase.execute(receipts: [receipt], storeId: 'store_002');

      final updated = await productRepo.fetchById('p2');
      // newCost = (20 * 100,000 + 10 * 160,000) / 30 = (2,000,000 + 1,600,000) / 30 = 120,000
      expect(updated!.costPrice, equals(120000.0));
      expect(updated.branchStocks['store_002'], equals(20));
      expect(updated.branchStocks['store_001'], equals(10));
    });

    test('Case 3: Negative initial stock (-5) with import (10) resets cost to incoming unit price', () async {
      const prod = Product(
        id: 'p3',
        name: 'Bàn Trà Mặt Đá',
        code: 'BTMD',
        price: 2000000,
        costPrice: 800000,
        branchStocks: {'store_002': -5}, // Negative stock
        category: 'Nội thất phòng khách',
      );
      await productRepo.upsert(prod);

      final receipt = StockInReceipt(
        id: 'R3',
        importCode: 'R3',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        items: const [
          StockInReceiptItem(
            transactionId: 't3',
            productId: 'BTMD',
            quantity: 10,
            unitPrice: 950000,
          ),
        ],
      );

      await useCase.execute(receipts: [receipt], storeId: 'store_002');

      final updated = await productRepo.fetchById('p3');
      // currentStock <= 0 => resets cost to unitPrice (950,000)
      expect(updated!.costPrice, equals(950000.0));
      // stock becomes -5 + 10 = 5
      expect(updated.branchStocks['store_002'], equals(5));
    });

    test('Case 4: Consecutive batches in multiple receipts compound weighted average accurately', () async {
      const prod = Product(
        id: 'p4',
        name: 'Ghế Văn Phòng',
        code: 'GVP',
        price: 500000,
        costPrice: 200000,
        branchStocks: {'store_002': 10}, // Total = 10, cost = 200k
        category: 'Nội thất văn phòng',
      );
      await productRepo.upsert(prod);

      // Receipt 1: import 10 @ 300k
      // Cost after R1 = (10 * 200k + 10 * 300k) / 20 = 250k. Total stock = 20.
      final r1 = StockInReceipt(
        id: 'R_SEQ_1',
        importCode: 'R_SEQ_1',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        items: const [
          StockInReceiptItem(
            transactionId: 't_s1',
            productId: 'GVP',
            quantity: 10,
            unitPrice: 300000,
          ),
        ],
      );

      // Receipt 2: import 20 @ 400k
      // Cost after R2 = (20 * 250k + 20 * 400k) / 40 = 325k. Total stock = 40.
      final r2 = StockInReceipt(
        id: 'R_SEQ_2',
        importCode: 'R_SEQ_2',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        items: const [
          StockInReceiptItem(
            transactionId: 't_s2',
            productId: 'GVP',
            quantity: 20,
            unitPrice: 400000,
          ),
        ],
      );

      final result = await useCase.execute(receipts: [r1, r2], storeId: 'store_002');
      expect(result.isSuccess, isTrue);
      expect(result.importedReceipts, equals(2));

      final updated = await productRepo.fetchById('p4');
      expect(updated!.costPrice, equals(325000.0));
      expect(updated.branchStocks['store_002'], equals(40));
    });

    test('Case 5: Decimal precision handling with large monetary sums (billions VND)', () async {
      const prod = Product(
        id: 'p5',
        name: 'Bộ Bàn Ăn Gỗ Gõ Đỏ 10 Món',
        code: 'BA_GOD_10',
        price: 200000000,
        costPrice: 120000000,
        branchStocks: {'store_002': 2}, // 2 * 120M = 240M
        category: 'Nội thất phòng ăn',
      );
      await productRepo.upsert(prod);

      final receipt = StockInReceipt(
        id: 'R_BILLION',
        importCode: 'R_BILLION',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        items: const [
          StockInReceiptItem(
            transactionId: 't_b1',
            productId: 'BA_GOD_10',
            quantity: 3,
            unitPrice: 150000000, // 3 * 150M = 450M
          ),
        ],
      );

      await useCase.execute(receipts: [receipt], storeId: 'store_002');

      final updated = await productRepo.fetchById('p5');
      // (240M + 450M) / 5 = 690M / 5 = 138,000,000
      expect(updated!.costPrice, equals(138000000.0));
      expect(updated.branchStocks['store_002'], equals(5));
    });
  });

  group('CHALLENGER 1: Branch Stocks Isolation & Supplier Debt Synchronization Invariants', () {
    late _HarnessProductRepo productRepo;
    late _HarnessInventoryRepo inventoryRepo;
    late _HarnessSupplierRepo supplierRepo;
    late _HarnessSupplierDebtRepo debtRepo;
    late ImportStockInReceiptsUseCase useCase;

    setUp(() {
      productRepo = _HarnessProductRepo([
        const Product(
          id: 'prod_multi_branch',
          name: 'Nệm Lò Xo Túi',
          code: 'NLX_01',
          price: 4500000,
          costPrice: 2800000,
          branchStocks: {'store_001': 15, 'store_002': 8, 'store_003': 3},
          category: 'Nội thất phòng ngủ',
        ),
      ]);
      inventoryRepo = _HarnessInventoryRepo();
      supplierRepo = _HarnessSupplierRepo([
        const Supplier(
          id: 'sup_active',
          code: 'NCC000010',
          name: 'Nệm Kim Đan',
          currentDebt: 5000000,
          totalPurchase: 20000000,
        ),
      ]);
      debtRepo = _HarnessSupplierDebtRepo();
      useCase = ImportStockInReceiptsUseCase(
        productRepo: productRepo,
        inventoryRepo: inventoryRepo,
        supplierRepo: supplierRepo,
        supplierDebtRepo: debtRepo,
      );
    });

    test('BRANCH ISOLATION: Import into store_002 strictly modifies store_002 and leaves other branches untouched', () async {
      final receipt = StockInReceipt(
        id: 'R_BRANCH_ISO',
        importCode: 'R_BRANCH_ISO',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        items: const [
          StockInReceiptItem(
            transactionId: 't_iso',
            productId: 'NLX_01',
            quantity: 7,
            unitPrice: 2800000,
          ),
        ],
      );

      final res = await useCase.execute(receipts: [receipt], storeId: 'store_002');
      expect(res.isSuccess, isTrue);

      final p = await productRepo.fetchById('prod_multi_branch');
      expect(p!.branchStocks['store_002'], equals(15)); // 8 + 7 = 15
      expect(p.branchStocks['store_001'], equals(15)); // UNTOUCHED
      expect(p.branchStocks['store_003'], equals(3));  // UNTOUCHED
    });

    test('SUPPLIER DEBT: Partial payment increases debt by unpaid difference and total purchase by net payable', () async {
      // Current: debt = 5M, purchase = 20M
      // Receipt: net = 10M, paid = 4M -> unpaid = 6M
      // Expected: debt = 11M, purchase = 30M
      final receipt = StockInReceipt(
        id: 'R_DEBT_PARTIAL',
        importCode: 'R_DEBT_PARTIAL',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        supplierId: 'NCC000010',
        totalAmount: 10000000,
        paidAmount: 4000000,
        items: const [
          StockInReceiptItem(
            transactionId: 't_debt_1',
            productId: 'NLX_01',
            quantity: 2,
            unitPrice: 5000000,
          ),
        ],
      );

      final res = await useCase.execute(receipts: [receipt], storeId: 'store_002');
      expect(res.isSuccess, isTrue);

      final s = await supplierRepo.fetchById('sup_active');
      expect(s!.currentDebt, equals(11000000.0));
      expect(s.totalPurchase, equals(30000000.0));

      expect(debtRepo.recorded.length, equals(1));
      final tx = debtRepo.recorded.first;
      expect(tx.supplierId, equals('sup_active'));
      expect(tx.amount, equals(6000000.0));
      expect(tx.remainingDebt, equals(11000000.0));
      expect(tx.referenceCode, equals('R_DEBT_PARTIAL'));
    });

    test('FIX VERIFIED: Fully paid receipt (netPayable <= paidAmount) updates supplier totalPurchase while debt remains unchanged', () async {
      // Current: debt = 5M, purchase = 20M
      // Receipt: net = 7M, paid = 7M (fully paid)
      // When receipt is fully paid:
      // - currentDebt correctly does not increase (5M)
      // - totalPurchase is updated to 27M (20M + 7M)
      final receipt = StockInReceipt(
        id: 'R_DEBT_PAID',
        importCode: 'R_DEBT_PAID',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        supplierId: 'NCC000010',
        totalAmount: 7000000,
        paidAmount: 7000000,
        items: const [
          StockInReceiptItem(
            transactionId: 't_debt_2',
            productId: 'NLX_01',
            quantity: 1,
            unitPrice: 7000000,
          ),
        ],
      );

      final res = await useCase.execute(receipts: [receipt], storeId: 'store_002');
      expect(res.isSuccess, isTrue);

      final s = await supplierRepo.fetchById('sup_active');
      expect(s!.currentDebt, equals(5000000.0)); // Unchanged
      expect(s.totalPurchase, equals(27000000.0),
          reason: 'Verifies fix: totalPurchase is updated for paid receipts');
      expect(debtRepo.recorded, isEmpty);
    });
  });

  group('CHALLENGER 1: Full Real-Data Ingestion Simulation (End-to-End Stress Harness)', () {
    late List<StockInReceipt> realReceipts;
    late List<Supplier> realSuppliers;

    setUpAll(() {
      final receiptsFile = _resolveProjectFile(receiptsFileName);
      final suppliersFile = _resolveProjectFile(suppliersFileName);

      realReceipts = ExcelHelper.parseStockInReceipts(receiptsFile.readAsBytesSync());
      realSuppliers = ExcelHelper.parseSuppliers(suppliersFile.readAsBytesSync());
    });

    test('Executes full ingestion of all 24 receipts from KiotViet file against 49 master suppliers', () async {
      final productRepo = _HarnessProductRepo();
      final inventoryRepo = _HarnessInventoryRepo();
      final supplierRepo = _HarnessSupplierRepo(realSuppliers);
      final debtRepo = _HarnessSupplierDebtRepo();

      final useCase = ImportStockInReceiptsUseCase(
        productRepo: productRepo,
        inventoryRepo: inventoryRepo,
        supplierRepo: supplierRepo,
        supplierDebtRepo: debtRepo,
      );

      // Record baseline metrics from initial suppliers
      final initialSupplierDebts = {for (final s in realSuppliers) s.code: s.currentDebt};
      final initialSupplierPurchases = {for (final s in realSuppliers) s.code: s.totalPurchase};

      // Execute ingestion of ALL 24 receipts
      final result = await useCase.execute(
        receipts: realReceipts,
        storeId: 'store_002',
        performedBy: 'Challenger1_QA',
      );

      // 1. Result verification
      expect(result.totalReceipts, equals(24));
      expect(result.importedReceipts, equals(24),
          reason: 'All 24 receipts must be imported without failure');
      expect(result.errors, isEmpty,
          reason: 'Zero errors allowed during standard real-file ingestion');
      expect(result.isSuccess, isTrue);

      // 2. Inventory transactions verification
      expect(inventoryRepo.transactions.length, equals(99),
          reason: 'Must record exactly 99 inventory transactions matching 99 item lines');
      final totalImportedQty = inventoryRepo.transactions.fold<int>(0, (s, tx) => s + tx.quantity);
      expect(totalImportedQty, equals(726),
          reason: 'Total quantity recorded across inventory transactions must equal 726');

      // 3. Mathematical check: Supplier Debt & Purchase delta across all suppliers
      double totalDebtDelta = 0.0;
      double totalPurchaseDelta = 0.0;

      for (final s in supplierRepo.suppliers.values) {
        final initialDebt = initialSupplierDebts[s.code] ?? 0.0;
        final initialPurchase = initialSupplierPurchases[s.code] ?? 0.0;

        totalDebtDelta += (s.currentDebt - initialDebt);
        totalPurchaseDelta += (s.totalPurchase - initialPurchase);
      }

      // Delta across all suppliers:
      // Total debt increase == 424,850,000 đ
      expect(totalDebtDelta, equals(424850000.0),
          reason: 'Net supplier debt increase across all suppliers must equal 424,850,000 đ');

      // All 24 receipts (including 2 fully paid receipts: PN001730: 660,000 đ and PN001719: 60,200,000 đ)
      // update totalPurchase, yielding totalPurchaseDelta == 485,710,000 đ
      expect(totalPurchaseDelta, equals(485710000.0),
          reason: 'All 485,710,000 đ of purchases across all 24 receipts are synchronized to suppliers');
      expect(485710000.0 - totalPurchaseDelta, equals(0.0));

      // 4. Exact debt transaction count:
      // 22 unpaid receipts generated debt transactions, 2 fully paid receipts (PN001730, PN001719) generated none
      expect(debtRepo.recorded.length, equals(22));
      final totalRecordedDebt = debtRepo.recorded.fold<double>(0.0, (s, tx) => s + tx.amount);
      expect(totalRecordedDebt, equals(424850000.0));
    });
  });
}
