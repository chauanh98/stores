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

class _Challenger2ProductRepo implements ProductRepository {
  final Map<String, Product> products = {};

  _Challenger2ProductRepo([List<Product> initial = const []]) {
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

class _Challenger2InventoryRepo implements InventoryRepository {
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

class _Challenger2SupplierRepo implements SupplierRepository {
  final Map<String, Supplier> suppliers = {};
  final List<SupplierDebtTransaction> debtTransactions = [];

  _Challenger2SupplierRepo([List<Supplier> initial = const []]) {
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

class _Challenger2SupplierDebtRepo
    implements SupplierDebtTransactionRepository {
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

  group('CHALLENGER 2: Exhaustive Currency Symbol & Numeric Formatting Stress Testing', () {
    test('parses various combinations of currency suffixes, cases, and non-breaking spaces', () {
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
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value =
            TextCellValue(headers[i]);
      }

      // Test cases with diverse currency formats:
      // Row 1: lower-case 'đ', upper-case 'Đ', mixed case 'Vnd', 'vnd', non-breaking space
      final testCases = [
        [
          'PN_CURR_VAR_1',
          'SKU_1',
          'Item 1',
          1,
          ' 1,234,567 đ ',
          ' 1,234,567 Đ ',
          ' 1,234,567 VND ',
          ' 34,567 vnd ',
          ' 1,200,000 Vnd ',
          ' 500,000 \u00A0 đ ',
        ],
        [
          'PN_CURR_VAR_2',
          'SKU_2',
          'Item 2 with zero values',
          2,
          ' 0 đ ',
          ' 0 VND ',
          ' 0 Đ ',
          ' 0 vnd ',
          ' 0 đ ',
          ' 0 VND ',
        ],
        [
          'PN_CURR_VAR_3',
          'SKU_3',
          'Item 3 with decimal values',
          1,
          ' 150,000.50 đ ',
          ' 150,000.50 VND ',
          ' 150,000.50 đ ',
          ' 0.50 đ ',
          ' 150,000.00 đ ',
          ' 100,000.00 VND ',
        ],
      ];

      for (int r = 0; r < testCases.length; r++) {
        final row = testCases[r];
        for (int c = 0; c < row.length; c++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value =
              TextCellValue(row[c].toString());
        }
      }

      final bytes = excel.encode()!;
      final receipts = ExcelHelper.parseStockInReceipts(bytes);

      expect(receipts.length, equals(3));

      // Receipt 1 assertions
      final r1 = receipts[0];
      expect(r1.importCode, equals('PN_CURR_VAR_1'));
      expect(r1.items.first.unitPrice, equals(1234567.0));
      expect(r1.items.first.totalPrice, equals(1234567.0));
      expect(r1.totalAmount, equals(1234567.0));
      expect(r1.discount, equals(34567.0));
      expect(r1.effectiveNetPayable, equals(1200000.0));
      expect(r1.paidAmount, equals(500000.0));
      expect(r1.remainingDebt, equals(700000.0));

      // Receipt 2 assertions (zero values)
      final r2 = receipts[1];
      expect(r2.items.first.unitPrice, equals(0.0));
      expect(r2.items.first.totalPrice, equals(0.0));
      expect(r2.totalAmount, equals(0.0));
      expect(r2.discount, equals(0.0));
      expect(r2.effectiveNetPayable, equals(0.0));
      expect(r2.paidAmount, equals(0.0));
      expect(r2.remainingDebt, equals(0.0));

      // Receipt 3 assertions (decimals)
      final r3 = receipts[2];
      expect(r3.items.first.unitPrice, equals(150000.50));
      expect(r3.items.first.totalPrice, equals(150000.50));
      expect(r3.totalAmount, equals(150000.50));
      expect(r3.discount, equals(0.50));
      expect(r3.effectiveNetPayable, equals(150000.00));
      expect(r3.paidAmount, equals(100000.00));
      expect(r3.remainingDebt, equals(50000.00));
    });
  });

  group('CHALLENGER 2: Multi-Receipt Sequential Supplier Ingestion (Stress Test)', () {
    late _Challenger2ProductRepo productRepo;
    late _Challenger2InventoryRepo inventoryRepo;
    late _Challenger2SupplierRepo supplierRepo;
    late _Challenger2SupplierDebtRepo debtRepo;
    late ImportStockInReceiptsUseCase useCase;

    setUp(() {
      productRepo = _Challenger2ProductRepo([
        const Product(
          id: 'prod_test',
          name: 'Bàn Tròn Gỗ',
          code: 'BTG01',
          price: 1500000,
          costPrice: 800000,
          branchStocks: {'store_002': 10},
          category: 'Nội thất',
        ),
      ]);
      inventoryRepo = _Challenger2InventoryRepo();
      supplierRepo = _Challenger2SupplierRepo([
        const Supplier(
          id: 'sup_stress',
          code: 'NCC_STRESS',
          name: 'NCC Chịu Tải Cao',
          currentDebt: 2000000,
          totalPurchase: 10000000,
        ),
      ]);
      debtRepo = _Challenger2SupplierDebtRepo();
      useCase = ImportStockInReceiptsUseCase(
        productRepo: productRepo,
        inventoryRepo: inventoryRepo,
        supplierRepo: supplierRepo,
        supplierDebtRepo: debtRepo,
      );
    });

    test('ingests 4 mixed receipts for same supplier in a single batch with in-memory state propagation', () async {
      // Receipt 1: Fully paid (netPayable: 1,000,000, paid: 1,000,000)
      // Total purchase should become 11M, debt remains 2M, 0 debt transactions
      final r1 = StockInReceipt(
        id: 'R_SEQ_1',
        importCode: 'R_SEQ_1',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        supplierId: 'NCC_STRESS',
        totalAmount: 1000000,
        paidAmount: 1000000,
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'BTG01',
            quantity: 1,
            unitPrice: 1000000,
          ),
        ],
      );

      // Receipt 2: Partially paid (netPayable: 2,000,000, paid: 500,000 -> unpaid 1,500,000)
      // Total purchase should become 13M, debt becomes 2M + 1.5M = 3.5M, 1 debt transaction
      final r2 = StockInReceipt(
        id: 'R_SEQ_2',
        importCode: 'R_SEQ_2',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        supplierId: 'NCC_STRESS',
        totalAmount: 2000000,
        paidAmount: 500000,
        items: const [
          StockInReceiptItem(
            transactionId: 't2',
            productId: 'BTG01',
            quantity: 2,
            unitPrice: 1000000,
          ),
        ],
      );

      // Receipt 3: Overpaid (netPayable: 500,000, paid: 800,000)
      // Total purchase should become 13.5M, debt remains 3.5M, 0 debt transactions
      final r3 = StockInReceipt(
        id: 'R_SEQ_3',
        importCode: 'R_SEQ_3',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        supplierId: 'NCC_STRESS',
        totalAmount: 500000,
        paidAmount: 800000,
        items: const [
          StockInReceiptItem(
            transactionId: 't3',
            productId: 'BTG01',
            quantity: 1,
            unitPrice: 500000,
          ),
        ],
      );

      // Receipt 4: Fully unpaid (netPayable: 3,000,000, paid: 0 -> unpaid 3,000,000)
      // Total purchase should become 16.5M, debt becomes 3.5M + 3M = 6.5M, 1 debt transaction
      final r4 = StockInReceipt(
        id: 'R_SEQ_4',
        importCode: 'R_SEQ_4',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        supplierId: 'NCC_STRESS',
        totalAmount: 3000000,
        paidAmount: 0,
        items: const [
          StockInReceiptItem(
            transactionId: 't4',
            productId: 'BTG01',
            quantity: 3,
            unitPrice: 1000000,
          ),
        ],
      );

      final result = await useCase.execute(
        receipts: [r1, r2, r3, r4],
        storeId: 'store_002',
        performedBy: 'EmpiricalChallenger',
      );

      expect(result.isSuccess, isTrue);
      expect(result.importedReceipts, equals(4));

      final updatedSupplier = await supplierRepo.fetchById('sup_stress');
      expect(updatedSupplier, isNotNull);

      // Verify exact accumulated total purchase
      expect(updatedSupplier!.totalPurchase, equals(16500000.0),
          reason: 'Initial 10M + 1M + 2M + 0.5M + 3M must equal 16.5M');

      // Verify exact accumulated current debt
      expect(updatedSupplier.currentDebt, equals(6500000.0),
          reason: 'Initial 2M + 0 + 1.5M + 0 + 3M must equal 6.5M');

      // Verify exactly 2 debt transactions recorded (only for r2 and r4)
      expect(debtRepo.recorded.length, equals(2));
      expect(debtRepo.recorded[0].amount, equals(1500000.0));
      expect(debtRepo.recorded[0].remainingDebt, equals(3500000.0));
      expect(debtRepo.recorded[0].referenceCode, equals('R_SEQ_2'));

      expect(debtRepo.recorded[1].amount, equals(3000000.0));
      expect(debtRepo.recorded[1].remainingDebt, equals(6500000.0));
      expect(debtRepo.recorded[1].referenceCode, equals('R_SEQ_4'));
    });
  });

  group('CHALLENGER 2: Per-Supplier Detailed Forensic Audit Across All 11 Real Suppliers', () {
    late Uint8List receiptsBytes;
    late Uint8List suppliersBytes;
    late List<StockInReceipt> realReceipts;
    late List<Supplier> realSuppliers;

    setUpAll(() {
      final receiptsFile = _resolveProjectFile(receiptsFileName);
      final suppliersFile = _resolveProjectFile(suppliersFileName);
      receiptsBytes = receiptsFile.readAsBytesSync();
      suppliersBytes = suppliersFile.readAsBytesSync();

      realReceipts = ExcelHelper.parseStockInReceipts(receiptsBytes);
      realSuppliers = ExcelHelper.parseSuppliers(suppliersBytes);
    });

    test('audits individual purchase and debt deltas for every single one of the 11 suppliers', () async {
      final productRepo = _Challenger2ProductRepo();
      final inventoryRepo = _Challenger2InventoryRepo();
      final supplierRepo = _Challenger2SupplierRepo(realSuppliers);
      final debtRepo = _Challenger2SupplierDebtRepo();

      final useCase = ImportStockInReceiptsUseCase(
        productRepo: productRepo,
        inventoryRepo: inventoryRepo,
        supplierRepo: supplierRepo,
        supplierDebtRepo: debtRepo,
      );

      final initialSuppliersMap = {for (final s in realSuppliers) s.code: s};

      // Group real receipts by supplier
      final receiptsBySupplier = <String, List<StockInReceipt>>{};
      for (final r in realReceipts) {
        receiptsBySupplier.putIfAbsent(r.supplierId!, () => []).add(r);
      }

      expect(receiptsBySupplier.keys.length, equals(11),
          reason: 'Exactly 11 suppliers must be present in the 24 receipts');

      // Execute ingestion
      final result = await useCase.execute(
        receipts: realReceipts,
        storeId: 'store_002',
        performedBy: 'Challenger2_Forensic',
      );

      expect(result.isSuccess, isTrue);
      expect(result.importedReceipts, equals(24));
      expect(result.errors, isEmpty);

      // Audit every supplier individually
      for (final sCode in receiptsBySupplier.keys) {
        final supplierReceipts = receiptsBySupplier[sCode]!;
        final initialSupplier = initialSuppliersMap[sCode]!;
        final updatedSupplier = supplierRepo.suppliers.values.firstWhere((s) => s.code == sCode);

        final expectedPurchaseDelta = supplierReceipts.fold<double>(
            0.0, (sum, r) => sum + r.effectiveNetPayable);
        final expectedPaid = supplierReceipts.fold<double>(
            0.0, (sum, r) => sum + (r.paidAmount ?? 0.0));
        final expectedDebtDelta = supplierReceipts.fold<double>(
            0.0, (sum, r) => sum + r.remainingDebt);

        final actualPurchaseDelta = updatedSupplier.totalPurchase - initialSupplier.totalPurchase;
        final actualDebtDelta = updatedSupplier.currentDebt - initialSupplier.currentDebt;

        expect(actualPurchaseDelta, equals(expectedPurchaseDelta),
            reason: 'Supplier $sCode purchase delta ($actualPurchaseDelta) must exactly match receipts sum ($expectedPurchaseDelta)');

        expect(actualDebtDelta, equals(expectedDebtDelta),
            reason: 'Supplier $sCode debt delta ($actualDebtDelta) must exactly match remaining debt ($expectedDebtDelta)');

        // If supplier had paid receipts, verify paid amounts did NOT increase debt
        if (expectedPaid > 0) {
          expect(actualDebtDelta, equals(expectedPurchaseDelta - expectedPaid),
              reason: 'Supplier $sCode debt delta must equal purchase minus paid');
        }
      }

      // Check PN001719 supplier (fully paid receipt: 60,200,000 đ)
      final pn1719 = realReceipts.firstWhere((r) => r.importCode == 'PN001719');
      expect(pn1719.paidAmount, equals(60200000.0));
      expect(pn1719.remainingDebt, equals(0.0));
      final pn1719SupplierCode = pn1719.supplierId!;
      final pn1719Initial = initialSuppliersMap[pn1719SupplierCode]!;
      final pn1719Updated = supplierRepo.suppliers.values.firstWhere((s) => s.code == pn1719SupplierCode);
      expect(pn1719Updated.totalPurchase - pn1719Initial.totalPurchase, greaterThanOrEqualTo(60200000.0),
          reason: 'Supplier with fully paid PN001719 must increase totalPurchase by at least 60,200,000 đ');
      expect(pn1719Updated.currentDebt - pn1719Initial.currentDebt,
          equals(receiptsBySupplier[pn1719SupplierCode]!.fold<double>(0.0, (s, r) => s + r.remainingDebt)),
          reason: 'Supplier currentDebt increases strictly by remaining debt of its receipts, ignoring fully paid PN001719');

      // Check PN001730 supplier: Shopee (NCC000050)
      // PN001730 has total 660,000 đ and paid 660,000 đ. Shopee has 6 receipts total.
      final shopeeInitial = initialSuppliersMap['NCC000050']!;
      final shopeeUpdated = supplierRepo.suppliers.values.firstWhere((s) => s.code == 'NCC000050');
      expect(shopeeUpdated.totalPurchase - shopeeInitial.totalPurchase, equals(4840000.0),
          reason: 'Shopee 6 receipts must increase totalPurchase by exactly 4,840,000 đ');
      expect(shopeeUpdated.currentDebt - shopeeInitial.currentDebt, equals(4180000.0),
          reason: 'Shopee debt must increase by 4,180,000 đ (4,840,000 - 660,000)');

      // Grand total check across ALL suppliers
      final totalPurchaseDelta = supplierRepo.suppliers.values.fold<double>(
        0.0,
        (sum, s) => sum + (s.totalPurchase - (initialSuppliersMap[s.code]?.totalPurchase ?? 0.0)),
      );
      final totalDebtDelta = supplierRepo.suppliers.values.fold<double>(
        0.0,
        (sum, s) => sum + (s.currentDebt - (initialSuppliersMap[s.code]?.currentDebt ?? 0.0)),
      );

      expect(totalPurchaseDelta, equals(485710000.0),
          reason: 'Total purchase volume delta across all 49 master suppliers must equal exactly 485,710,000 đ');
      expect(totalDebtDelta, equals(424850000.0),
          reason: 'Total debt delta across all 49 master suppliers must equal exactly 424,850,000 đ');
    });
  });
}
