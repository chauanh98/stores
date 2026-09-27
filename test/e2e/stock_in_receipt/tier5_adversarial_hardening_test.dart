import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/data/repositories/stock_in_receipt_repository_impl.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

import '../../support/firebase_test_harness.dart';

// ============================================================================
// TEST MOCK REPOSITORIES FOR PURE PRODUCTION USE CASE TESTING
// ============================================================================

class _TestProductRepo implements ProductRepository {
  final Map<String, Product> products = {};
  int upsertCalls = 0;

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Future<void> upsert(Product product) async {
    upsertCalls++;
    products[product.id] = product;
  }

  @override
  Future<void> delete(String id) async {
    products.remove(id);
  }

  @override
  Future<void> updateStock(String id, int newStock) async {
    final p = products[id];
    if (p != null) {
      products[id] = p.copyWith(branchStocks: {'store_001': newStock});
    }
  }

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());

  Stream<Product?> watchById(String id) => Stream.value(products[id]);
}

class _TestInventoryRepo implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async {
    transactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(transactions.where((t) => t.productId == productId).toList());

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(DateTime start, DateTime end) =>
      Stream.value(transactions.where((t) => t.type == TransactionType.import).toList());
}

class _TestSupplierRepo implements SupplierRepository {
  final Map<String, Supplier> suppliers = {};
  final List<SupplierDebtTransaction> debtTransactions = [];

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async => suppliers[id];

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    suppliers[supplier.id] = supplier;
  }

  @override
  Future<void> delete(String id, {String? storeId}) async {
    suppliers.remove(id);
  }

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction tx, {String? storeId}) async {
    debtTransactions.add(tx);
  }

  @override
  Future<List<SupplierDebtTransaction>> fetchDebtTransactions(String supplierId, {String? storeId}) async =>
      debtTransactions.where((t) => t.supplierId == supplierId).toList();

  @override
  Stream<List<Supplier>> watchAll({String? storeId}) =>
      Stream.value(suppliers.values.toList());

  @override
  Stream<List<SupplierDebtTransaction>> watchDebtTransactions(String supplierId, {String? storeId}) =>
      Stream.value(debtTransactions.where((t) => t.supplierId == supplierId).toList());
}

class _TestReceiptRepo implements StockInReceiptRepository {
  final Map<String, StockInReceipt> receipts = {};

  @override
  Future<String> saveDraft(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
    return receipt.id;
  }

  @override
  Future<void> updateDraft(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
  }

  @override
  Future<void> deleteDraft({required String storeId, required String receiptId}) async {
    receipts.remove(receiptId);
  }

  @override
  Future<void> cancelReceipt({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Cancellation reason cannot be empty');
    }
    if (receipt.isCancelled) {
      throw StateError('Receipt is already cancelled');
    }
    if (receipt.isDraft) {
      throw StateError('Cannot cancel a draft receipt. Use deleteDraft instead.');
    }
    receipts[receipt.id] = receipt.copyWith(
      status: 'cancelled',
      cancelReason: reason,
      cancelledBy: cancelledBy,
      cancelledAt: DateTime.now(),
    );
  }

  @override
  Stream<List<StockInReceipt>> watchReceipts(String storeId) =>
      Stream.value(receipts.values.toList());

  @override
  Future<List<StockInReceipt>> fetchReceipts(String storeId) async =>
      receipts.values.toList();

  @override
  Future<StockInReceipt?> getReceiptById({required String storeId, required String receiptId}) async =>
      receipts[receiptId];

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
  }

  @override
  Future<void> deleteReceipt({required String storeId, required String receiptId}) async {
    receipts.remove(receiptId);
  }

  @override
  Future<double?> getLatestImportPrice({required String storeId, required String productId}) async => null;
}

// ============================================================================
// MAIN TEST SUITE
// ============================================================================

void main() {
  group('=== MOBILE STOCK-IN UPGRADE: TIER 5 ADVERSARIAL COVERAGE HARDENING ===', () {
    // ========================================================================
    // 1. EXTREME TRANSACTIONS, PRECISION & NUMERICAL BOUNDS
    // ========================================================================
    group('1. Extreme Transactions, Precision & Numerical Bounds', () {
      test('T5.1.1: Multi-trillion VND receipt & extreme quantities serialize and execute without precision loss or overflow', () async {
        final mockDb = MockFirebaseDatabase();
        final pRepo = _TestProductRepo();
        final invRepo = _TestInventoryRepo();
        final supRepo = _TestSupplierRepo();
        final rRepo = _TestReceiptRepo();

        const pBulk = Product(
          id: 'PROD_BULK_01',
          name: 'Phân bón công nghiệp xuất khẩu',
          code: 'BULK01',
          price: 60000000.0,
          costPrice: 50000000.0,
          category: 'Phân bón',
          branchStocks: {'store_001': 1000, 'branch_1': 1000},
        );
        pRepo.products[pBulk.id] = pBulk;

        const supCorp = Supplier(
          id: 'SUP_CORP_01',
          code: 'NCC_CORP',
          name: 'Tập đoàn Hóa chất Quốc gia',
          totalPurchase: 100000000000.0, // 100 Billion
          currentDebt: 20000000000.0,    // 20 Billion
        );
        supRepo.suppliers[supCorp.id] = supCorp;

        // Extreme receipt: 1,000,000 units @ 50,000,000 đ = 50,000,000,000,000 đ (50 Trillion VND)
        final extremeReceipt = StockInReceipt(
          id: 'REC_EXTREME_50T',
          importCode: 'PN_EXTREME_001',
          date: DateTime(2026, 9, 27, 10, 0),
          storeId: 'store_001',
          supplierId: supCorp.id,
          supplierName: supCorp.name,
          items: const [
            StockInReceiptItem(
              transactionId: 'TX_BULK_1',
              productId: 'PROD_BULK_01',
              quantity: 1000000,
              unitPrice: 50000000.0,
              productName: 'Phân bón công nghiệp xuất khẩu',
              productCode: 'BULK01',
            ),
          ],
          discount: 1000000000.0, // 1 Billion discount
          paidAmount: 20000000000000.0, // 20 Trillion paid
        );

        expect(extremeReceipt.totalQuantity, equals(1000000));
        expect(extremeReceipt.totalAmount, equals(50000000000000.0));
        expect(extremeReceipt.effectiveNetPayable, equals(49999000000000.0));
        expect(extremeReceipt.remainingDebt, equals(29999000000000.0));

        // Test Map Serialization round-trip
        final map = extremeReceipt.toMap();
        final deserialized = StockInReceipt.fromMap(map);
        expect(deserialized.id, equals(extremeReceipt.id));
        expect(deserialized.totalAmount, equals(extremeReceipt.totalAmount));
        expect(deserialized.effectiveNetPayable, equals(extremeReceipt.effectiveNetPayable));
        expect(deserialized.remainingDebt, equals(extremeReceipt.remainingDebt));

        // Execute Complete use case
        final completeUseCase = CompleteStockInReceiptUseCase(
          db: mockDb,
          productRepository: pRepo,
          inventoryRepository: invRepo,
          supplierRepository: supRepo,
          receiptRepository: rRepo,
        );

        final completed = await completeUseCase.execute(extremeReceipt);
        expect(completed.status, equals('completed'));

        // Product stock: 1000 + 1,000,000 = 1,001,000
        final updatedP = pRepo.products[pBulk.id]!;
        expect(updatedP.stockInBranch('store_001'), equals(1001000));
        expect(updatedP.stockInBranch('branch_1'), equals(1001000));

        // Supplier purchase & debt
        final updatedSup = supRepo.suppliers[supCorp.id]!;
        expect(updatedSup.totalPurchase, equals(100000000000.0 + 49999000000000.0));
        expect(updatedSup.currentDebt, equals(20000000000.0 + 29999000000000.0));
      });

      test('T5.1.2: Boundary zero-cost item imports (promotional stock) calculate weighted cost without division by zero', () async {
        final mockDb = MockFirebaseDatabase();
        final pRepo = _TestProductRepo();
        final invRepo = _TestInventoryRepo();
        final supRepo = _TestSupplierRepo();
        final rRepo = _TestReceiptRepo();

        const pPromo = Product(
          id: 'PROD_PROMO_01',
          name: 'Nón bảo hiểm quà tặng khuyến mãi',
          code: 'PROMO01',
          price: 0.0,
          costPrice: 50000.0,
          category: 'Quà tặng',
          branchStocks: {'store_001': 5, 'branch_1': 5},
        );
        pRepo.products[pPromo.id] = pPromo;

        // Import 15 units at 0.0 VND (bonus stock)
        final promoReceipt = StockInReceipt(
          id: 'REC_PROMO_FREE',
          importCode: 'PN_FREE_001',
          date: DateTime.now(),
          storeId: 'store_001',
          items: const [
            StockInReceiptItem(
              transactionId: 'TX_PROMO_1',
              productId: 'PROD_PROMO_01',
              quantity: 15,
              unitPrice: 0.0,
            ),
          ],
        );

        final completeUseCase = CompleteStockInReceiptUseCase(
          db: mockDb,
          productRepository: pRepo,
          inventoryRepository: invRepo,
          supplierRepository: supRepo,
          receiptRepository: rRepo,
        );

        await completeUseCase.execute(promoReceipt);

        // Product.stock sums all branchStocks keys: 5 (store_001) + 5 (branch_1) = 10.
        // Initial value: 10 * 50,000 = 500,000. Added: 15 * 0 = 0.
        // Total units: 10 + 15 = 25. New Cost: 500,000 / 25 = 20,000 VND.
        final updatedP = pRepo.products[pPromo.id]!;
        expect(updatedP.stockInBranch('store_001'), equals(20));
        expect(updatedP.costPrice, equals(20000.0));
        expect(updatedP.costPrice.isNaN, isFalse);
        expect(updatedP.costPrice.isInfinite, isFalse);
      });

      test('T5.1.3: Fractional division and high-precision rounding stability in weighted cost', () {
        const currentStock = 3;
        const currentCost = 10000.0;
        const importQty = 7;
        const importPrice = 25333.333333;

        const newCost = ((currentStock * currentCost) + (importQty * importPrice)) /
            (currentStock + importQty);

        expect(newCost, closeTo(20733.33, 0.01));
        expect(newCost.isFinite, isTrue);
      });

      test('T5.1.4: Resilient entity deserialization (StockInReceipt.fromMap) under valid/null fallback shapes and string-type vulnerability check', () {
        // 1. Resilient parsing with null date, missing discount, Map-shaped items
        final resilientMap = {
          'id': 12345, // integer instead of string
          'importCode': 'PN_CORRUPTED_001',
          'date': null, // null date fallback
          'createdAt': '2026-09-27T08:00:00.000Z',
          'totalAmount': 500000.0,
          'discount': null,
          'items': {
            'item_key_1': {
              'transactionId': 'TX_CORRUPT_1',
              'productId': 'PROD_ST25',
              'quantity': 10,
              'unitPrice': 120000.0,
              'productName': 'Lúa giống ST25',
            },
          },
        };

        final parsed = StockInReceipt.fromMap(resilientMap);
        expect(parsed.id, equals('12345'));
        expect(parsed.importCode, equals('PN_CORRUPTED_001'));
        expect(parsed.items.length, equals(1));
        expect(parsed.items.first.quantity, equals(10));
        expect(parsed.items.first.unitPrice, equals(120000.0));
        expect(parsed.totalAmount, equals(500000.0));
        expect(parsed.discount, equals(0.0));

        // 2. Adversarial vulnerability assertion:
        // StockInReceiptItem.fromMap performs hardcast (map['quantity'] as num?),
        // which throws a TypeError when given a string-encoded quantity from raw external imports.
        final mapWithStringQuantity = {
          'transactionId': 'TX_1',
          'productId': 'PROD_1',
          'quantity': '10', // String instead of num
          'unitPrice': 10000.0,
        };
        expect(
          () => StockInReceiptItem.fromMap(mapWithStringQuantity),
          throwsA(isA<TypeError>()),
          reason: 'Exposes absence of num.tryParse() in StockInReceiptItem.fromMap',
        );
      });

      test('T5.1.5: Extreme line discount and negative discount financial bounds', () {
        const item = StockInReceiptItem(
          transactionId: 'TX_DISC_1',
          productId: 'PROD_ST25',
          quantity: 2,
          originalPrice: 100000.0,
          discount: 150000.0,
          unitPrice: 0.0,
        );

        expect(item.unitPrice, equals(0.0));
        expect(item.totalPrice, equals(0.0));
        expect(item.subtotal, equals(200000.0));
        expect(item.totalDiscount, equals(200000.0));
      });
    });

    // ========================================================================
    // 2. MULTI-BRANCH STOCK MUTATIONS & DUPLICATE LINE ITEMS
    // ========================================================================
    group('2. Multi-Branch Stock Mutations & Duplicate Line Items', () {
      test('T5.2.1: Receipt with multiple duplicate line items for same product accumulates stock and records distinct transactions', () async {
        final mockDb = MockFirebaseDatabase();
        final pRepo = _TestProductRepo();
        final invRepo = _TestInventoryRepo();
        final supRepo = _TestSupplierRepo();
        final rRepo = _TestReceiptRepo();

        const pST25 = Product(
          id: 'PROD_ST25',
          name: 'Lúa giống ST25',
          code: 'ST25',
          price: 180000.0,
          costPrice: 120000.0,
          category: 'Lúa giống',
          branchStocks: {'store_001': 10, 'branch_1': 10, 'store_002': 25, 'branch_2': 25},
        );
        pRepo.products[pST25.id] = pST25;

        // Single receipt with 3 lines of the SAME product
        // Line 1: 10 @ 100,000 = 1,000,000
        // Line 2: 20 @ 110,000 = 2,200,000
        // Line 3: 30 @ 120,000 = 3,600,000
        // Total imported: 60 units, total added cost: 6,800,000
        final multiLineReceipt = StockInReceipt(
          id: 'REC_MULTI_DUP_01',
          importCode: 'PN_DUP_001',
          date: DateTime.now(),
          storeId: 'store_001',
          items: const [
            StockInReceiptItem(
              transactionId: 'TX_LINE_1',
              productId: 'PROD_ST25',
              quantity: 10,
              unitPrice: 100000.0,
              note: 'Lô A',
            ),
            StockInReceiptItem(
              transactionId: 'TX_LINE_2',
              productId: 'PROD_ST25',
              quantity: 20,
              unitPrice: 110000.0,
              note: 'Lô B',
            ),
            StockInReceiptItem(
              transactionId: 'TX_LINE_3',
              productId: 'PROD_ST25',
              quantity: 30,
              unitPrice: 120000.0,
              note: 'Lô C',
            ),
          ],
        );

        final completeUseCase = CompleteStockInReceiptUseCase(
          db: mockDb,
          productRepository: pRepo,
          inventoryRepository: invRepo,
          supplierRepository: supRepo,
          receiptRepository: rRepo,
        );

        await completeUseCase.execute(multiLineReceipt);

        // 1. Stock accumulation: 10 (initial) + 60 (imported) = 70
        final updatedP = pRepo.products[pST25.id]!;
        expect(updatedP.stockInBranch('store_001'), equals(70));
        expect(updatedP.stockInBranch('branch_1'), equals(70));
        // Other branch must remain untouched
        expect(updatedP.stockInBranch('store_002'), equals(25));
        expect(updatedP.stockInBranch('branch_2'), equals(25));

        // 2. Weighted Cost Calculation:
        // Product.stock sums all branchStocks keys: 10 + 10 + 25 + 25 = 70.
        // Initial value: 70 * 120,000 = 8,400,000. Added: 6,800,000.
        // Total units: 70 + 60 = 130. Cost: 15,200,000 / 130 = 116,923.0769...
        expect(updatedP.costPrice, closeTo(116923.08, 0.05));

        // 3. Exactly 3 inventory transactions recorded
        expect(invRepo.transactions.length, equals(3));
        expect(invRepo.transactions[0].quantity, equals(10));
        expect(invRepo.transactions[1].quantity, equals(20));
        expect(invRepo.transactions[2].quantity, equals(30));
        expect(invRepo.transactions.every((t) => t.type == TransactionType.import), isTrue);

        // 4. Test atomic rollback using CancelStockInReceiptUseCase
        final cancelUseCase = CancelStockInReceiptUseCase(
          db: mockDb,
          productRepository: pRepo,
          inventoryRepository: invRepo,
          supplierRepository: supRepo,
          receiptRepository: rRepo,
        );

        await cancelUseCase.execute(
          storeId: 'store_001',
          receipt: multiLineReceipt,
          reason: 'Hủy phiếu nhập trùng dòng hàng',
          cancelledBy: 'admin_test',
        );

        // Stock rolled back: 70 - 60 = 10
        final cancelledP = pRepo.products[pST25.id]!;
        expect(cancelledP.stockInBranch('store_001'), equals(10));
        expect(cancelledP.stockInBranch('branch_1'), equals(10));
        expect(cancelledP.stockInBranch('store_002'), equals(25));

        // 3 reversal inventory transactions added
        final reversalTxs = invRepo.transactions.where((t) => t.type == TransactionType.export).toList();
        expect(reversalTxs.length, equals(3));
        expect(reversalTxs[0].quantity, equals(10));
        expect(reversalTxs[1].quantity, equals(20));
        expect(reversalTxs[2].quantity, equals(30));
        expect(reversalTxs.every((t) => t.note.contains('Hủy phiếu nhập trùng dòng hàng')), isTrue);
      });

      test('T5.2.2: Interleaved cross-branch imports and cancellations with dual-branch alias isolation', () async {
        final mockDb = MockFirebaseDatabase();
        final pRepo = _TestProductRepo();
        final invRepo = _TestInventoryRepo();
        final supRepo = _TestSupplierRepo();
        final rRepo = _TestReceiptRepo();

        const pST26 = Product(
          id: 'PROD_ST26',
          name: 'Gạo ST26',
          code: 'ST26',
          price: 6800000.0,
          costPrice: 6100000.0,
          category: 'Gạo đặc sản',
          branchStocks: {'store_001': 1, 'branch_1': 1, 'store_002': 5, 'branch_2': 5},
        );
        pRepo.products[pST26.id] = pST26;

        final completeUseCase = CompleteStockInReceiptUseCase(
          db: mockDb,
          productRepository: pRepo,
          inventoryRepository: invRepo,
          supplierRepository: supRepo,
          receiptRepository: rRepo,
        );
        final cancelUseCase = CancelStockInReceiptUseCase(
          db: mockDb,
          productRepository: pRepo,
          inventoryRepository: invRepo,
          supplierRepository: supRepo,
          receiptRepository: rRepo,
        );

        // Branch 1 import: 10 units
        final rBranch1 = StockInReceipt(
          id: 'REC_B1_001',
          importCode: 'PN_B1_001',
          date: DateTime.now(),
          storeId: 'store_001',
          items: const [
            StockInReceiptItem(
              transactionId: 'TX_B1',
              productId: 'PROD_ST26',
              quantity: 10,
              unitPrice: 6000000.0,
            ),
          ],
        );

        // Branch 2 import: 20 units
        final rBranch2 = StockInReceipt(
          id: 'REC_B2_001',
          importCode: 'PN_B2_001',
          date: DateTime.now(),
          storeId: 'store_002',
          items: const [
            StockInReceiptItem(
              transactionId: 'TX_B2',
              productId: 'PROD_ST26',
              quantity: 20,
              unitPrice: 6200000.0,
            ),
          ],
        );

        await completeUseCase.execute(rBranch1);
        await completeUseCase.execute(rBranch2);

        // store_001: 1 + 10 = 11; store_002: 5 + 20 = 25
        var p = pRepo.products[pST26.id]!;
        expect(p.stockInBranch('store_001'), equals(11));
        expect(p.stockInBranch('branch_1'), equals(11));
        expect(p.stockInBranch('store_002'), equals(25));
        expect(p.stockInBranch('branch_2'), equals(25));

        // Now cancel Branch 1 receipt only
        await cancelUseCase.execute(
          storeId: 'store_001',
          receipt: rBranch1,
          reason: 'Lỗi giao hàng chi nhánh Đông Thắng',
          cancelledBy: 'admin_test',
        );

        // store_001 reverts to 1; store_002 stays at 25!
        p = pRepo.products[pST26.id]!;
        expect(p.stockInBranch('store_001'), equals(1));
        expect(p.stockInBranch('branch_1'), equals(1));
        expect(p.stockInBranch('store_002'), equals(25));
        expect(p.stockInBranch('branch_2'), equals(25));
      });

      test('T5.2.3: Uncataloged or deleted product IDs gracefully complete without crash', () async {
        final mockDb = MockFirebaseDatabase();
        final pRepo = _TestProductRepo();
        final invRepo = _TestInventoryRepo();
        final supRepo = _TestSupplierRepo();
        final rRepo = _TestReceiptRepo();

        final receiptWithDeletedProduct = StockInReceipt(
          id: 'REC_GHOST_PROD',
          importCode: 'PN_GHOST_001',
          date: DateTime.now(),
          storeId: 'store_001',
          items: const [
            StockInReceiptItem(
              transactionId: 'TX_GHOST',
              productId: 'NON_EXISTENT_PROD_999',
              quantity: 5,
              unitPrice: 50000.0,
              productName: 'Sản phẩm đã bị xóa',
            ),
          ],
        );

        final completeUseCase = CompleteStockInReceiptUseCase(
          db: mockDb,
          productRepository: pRepo,
          inventoryRepository: invRepo,
          supplierRepository: supRepo,
          receiptRepository: rRepo,
        );

        // Should complete without null pointer exception
        final completed = await completeUseCase.execute(receiptWithDeletedProduct);
        expect(completed.status, equals('completed'));
        expect(invRepo.transactions.length, equals(1));
        expect(invRepo.transactions.first.productId, equals('NON_EXISTENT_PROD_999'));
      });
    });

    // ========================================================================
    // 3. REVERSAL TRANSACTIONS, PARTIAL PAYMENTS & ZERO-DEBT INVARIANTS
    // ========================================================================
    group('3. Reversal Transactions, Partial Payments & Zero-Debt Invariants', () {
      test('T5.3.1: Partial payment lifecycle with debt audit trail and exact balance restoration', () async {
        final mockDb = MockFirebaseDatabase();
        final pRepo = _TestProductRepo();
        final invRepo = _TestInventoryRepo();
        final supRepo = _TestSupplierRepo();
        final rRepo = _TestReceiptRepo();

        const supplier = Supplier(
          id: 'SUP_PARTIAL',
          code: 'NCC_PARTIAL',
          name: 'Nhà cung cấp phân bón Miền Tây',
          totalPurchase: 50000000.0,
          currentDebt: 10000000.0,
        );
        supRepo.suppliers[supplier.id] = supplier;

        // Total: 10,000,000. Discount: 1,000,000 -> Net: 9,000,000. Paid: 4,000,000. Remaining Debt: 5,000,000.
        final receipt = StockInReceipt(
          id: 'REC_PARTIAL_PAY_01',
          importCode: 'PN_PARTIAL_001',
          date: DateTime.now(),
          storeId: 'store_001',
          supplierId: supplier.id,
          supplierName: supplier.name,
          items: const [
            StockInReceiptItem(
              transactionId: 'TX_1',
              productId: 'PROD_P1',
              quantity: 10,
              unitPrice: 1000000.0,
            ),
          ],
          totalAmount: 10000000.0,
          discount: 1000000.0,
          paidAmount: 4000000.0,
        );

        final completeUseCase = CompleteStockInReceiptUseCase(
          db: mockDb,
          productRepository: pRepo,
          inventoryRepository: invRepo,
          supplierRepository: supRepo,
          receiptRepository: rRepo,
        );
        final cancelUseCase = CancelStockInReceiptUseCase(
          db: mockDb,
          productRepository: pRepo,
          inventoryRepository: invRepo,
          supplierRepository: supRepo,
          receiptRepository: rRepo,
        );

        // 1. Complete receipt
        await completeUseCase.execute(receipt);

        var currentSup = supRepo.suppliers[supplier.id]!;
        expect(currentSup.totalPurchase, equals(59000000.0)); // 50M + 9M
        expect(currentSup.currentDebt, equals(15000000.0));    // 10M + 5M

        // Debt transaction created
        expect(supRepo.debtTransactions.length, equals(1));
        final initialDebtTx = supRepo.debtTransactions.first;
        expect(initialDebtTx.type, equals(SupplierDebtType.importBill));
        expect(initialDebtTx.amount, equals(5000000.0));
        expect(initialDebtTx.remainingDebt, equals(15000000.0));

        // 2. Cancel receipt
        await cancelUseCase.execute(
          storeId: 'store_001',
          receipt: receipt,
          reason: 'Hàng không đúng quy cách',
          cancelledBy: 'supervisor_dongthang',
        );

        currentSup = supRepo.suppliers[supplier.id]!;
        expect(currentSup.totalPurchase, equals(50000000.0)); // Restored 100%
        expect(currentSup.currentDebt, equals(10000000.0));    // Restored 100%

        // Reversal debt transaction created
        expect(supRepo.debtTransactions.length, equals(2));
        final revDebtTx = supRepo.debtTransactions[1];
        expect(revDebtTx.type, equals(SupplierDebtType.adjustment));
        expect(revDebtTx.amount, equals(-5000000.0));
        expect(revDebtTx.remainingDebt, equals(10000000.0));
      });

      test('T5.3.2: Full cash payment (zero-debt invariant) does not alter supplier debt on complete or cancel', () async {
        final mockDb = MockFirebaseDatabase();
        final pRepo = _TestProductRepo();
        final invRepo = _TestInventoryRepo();
        final supRepo = _TestSupplierRepo();
        final rRepo = _TestReceiptRepo();

        const supplier = Supplier(
          id: 'SUP_FULL_CASH',
          code: 'NCC_CASH',
          name: 'Đại lý thanh toán tiền mặt',
          totalPurchase: 20000000.0,
          currentDebt: 5000000.0,
        );
        supRepo.suppliers[supplier.id] = supplier;

        // Total 9,000,000. Paid in full: 9,000,000. Remaining Debt: 0.0
        final receipt = StockInReceipt(
          id: 'REC_FULL_CASH_01',
          importCode: 'PN_CASH_001',
          date: DateTime.now(),
          storeId: 'store_001',
          supplierId: supplier.id,
          supplierName: supplier.name,
          items: const [
            StockInReceiptItem(
              transactionId: 'TX_1',
              productId: 'PROD_P1',
              quantity: 1,
              unitPrice: 9000000.0,
            ),
          ],
          totalAmount: 9000000.0,
          paidAmount: 9000000.0,
        );

        final completeUseCase = CompleteStockInReceiptUseCase(
          db: mockDb,
          productRepository: pRepo,
          inventoryRepository: invRepo,
          supplierRepository: supRepo,
          receiptRepository: rRepo,
        );
        final cancelUseCase = CancelStockInReceiptUseCase(
          db: mockDb,
          productRepository: pRepo,
          inventoryRepository: invRepo,
          supplierRepository: supRepo,
          receiptRepository: rRepo,
        );

        await completeUseCase.execute(receipt);

        var currentSup = supRepo.suppliers[supplier.id]!;
        expect(currentSup.currentDebt, equals(5000000.0)); // Zero change in debt
        expect(currentSup.totalPurchase, equals(29000000.0));
        // No debt transaction created for zero debt
        expect(supRepo.debtTransactions.isEmpty, isTrue);

        await cancelUseCase.execute(
          storeId: 'store_001',
          receipt: receipt,
          reason: 'Hủy đơn tiền mặt',
          cancelledBy: 'admin_test',
        );

        currentSup = supRepo.suppliers[supplier.id]!;
        expect(currentSup.currentDebt, equals(5000000.0)); // Still zero change in debt
        expect(currentSup.totalPurchase, equals(20000000.0)); // Rolled back
      });

      test('T5.3.3: Overpayment boundary invariant prevents negative supplier debt', () async {
        final mockDb = MockFirebaseDatabase();
        final pRepo = _TestProductRepo();
        final invRepo = _TestInventoryRepo();
        final supRepo = _TestSupplierRepo();
        final rRepo = _TestReceiptRepo();

        const supplier = Supplier(
          id: 'SUP_OVERPAY',
          code: 'NCC_OVERPAY',
          name: 'Nhà cung cấp overpay test',
          totalPurchase: 1000000.0,
          currentDebt: 0.0,
        );
        supRepo.suppliers[supplier.id] = supplier;

        // Net: 1,000,000. Paid: 2,000,000
        final receipt = StockInReceipt(
          id: 'REC_OVERPAY_01',
          importCode: 'PN_OVERPAY_001',
          date: DateTime.now(),
          storeId: 'store_001',
          supplierId: supplier.id,
          supplierName: supplier.name,
          items: const [
            StockInReceiptItem(
              transactionId: 'TX_1',
              productId: 'PROD_P1',
              quantity: 1,
              unitPrice: 1000000.0,
            ),
          ],
          totalAmount: 1000000.0,
          paidAmount: 2000000.0,
        );

        final completeUseCase = CompleteStockInReceiptUseCase(
          db: mockDb,
          productRepository: pRepo,
          inventoryRepository: invRepo,
          supplierRepository: supRepo,
          receiptRepository: rRepo,
        );

        await completeUseCase.execute(receipt);

        final currentSup = supRepo.suppliers[supplier.id]!;
        // Clamped at 0.0, never negative
        expect(currentSup.currentDebt, greaterThanOrEqualTo(0.0));
      });

      test('T5.3.4: Complete state transition guard & idempotency matrix', () async {
        final mockDb = MockFirebaseDatabase();
        final pRepo = _TestProductRepo();
        final invRepo = _TestInventoryRepo();
        final supRepo = _TestSupplierRepo();
        final rRepo = _TestReceiptRepo();

        final cancelUseCase = CancelStockInReceiptUseCase(
          db: mockDb,
          productRepository: pRepo,
          inventoryRepository: invRepo,
          supplierRepository: supRepo,
          receiptRepository: rRepo,
        );
        final deleteUseCase = DeleteStockInReceiptUseCase(rRepo);

        final completedReceipt = StockInReceipt(
          id: 'REC_GUARD_01',
          importCode: 'PN_GUARD_01',
          date: DateTime.now(),
          status: 'completed',
          items: const [],
        );

        final cancelledReceipt = StockInReceipt(
          id: 'REC_GUARD_02',
          importCode: 'PN_GUARD_02',
          date: DateTime.now(),
          status: 'cancelled',
          items: const [],
        );

        final draftReceipt = StockInReceipt(
          id: 'REC_GUARD_03',
          importCode: 'PN_GUARD_03',
          date: DateTime.now(),
          status: 'draft',
          items: const [],
        );

        // Guard 1: Empty reason throws ArgumentError
        expect(
          () => cancelUseCase.execute(
            storeId: 'store_001',
            receipt: completedReceipt,
            reason: '   ',
            cancelledBy: 'admin',
          ),
          throwsArgumentError,
        );

        // Guard 2: Already cancelled receipt throws StateError
        expect(
          () => cancelUseCase.execute(
            storeId: 'store_001',
            receipt: cancelledReceipt,
            reason: 'Cancel again',
            cancelledBy: 'admin',
          ),
          throwsStateError,
        );

        // Guard 3: Draft receipt cannot be cancelled via CancelUseCase (use DeleteDraft)
        expect(
          () => cancelUseCase.execute(
            storeId: 'store_001',
            receipt: draftReceipt,
            reason: 'Cancel draft',
            cancelledBy: 'admin',
          ),
          throwsStateError,
        );

        // Guard 4: Completed receipt cannot be directly deleted via DeleteUseCase
        expect(
          () => deleteUseCase.execute(
            storeId: 'store_001',
            receipt: completedReceipt,
          ),
          throwsStateError,
        );
      });
    });

    // ========================================================================
    // 4. CONCURRENCY, OUT-OF-ORDER STREAMS & PROVIDER INVALIDATION
    // ========================================================================
    group('4. Concurrency, Out-Of-Order Streams & Provider Invalidation', () {
      test('T5.4.1: Out-of-order raw transactions grouping resilience (groupTransactionsToReceipts)', () {
        final date1 = DateTime(2026, 9, 20, 10, 0);
        final date2 = DateTime(2026, 9, 22, 14, 0);
        final date3 = DateTime(2026, 9, 21, 12, 0); // Out of order

        final txList = [
          InventoryTransaction(
            id: 'TX_1',
            productId: 'PROD_ST25',
            type: TransactionType.import,
            quantity: 5,
            importPrice: 120000.0,
            date: date1,
            importCode: 'PN_GROUP_01',
            note: 'Đợt 1',
            storeId: 'store_001',
            supplierId: 'SUP_001',
            supplierName: 'Công ty Ánh Dương',
          ),
          InventoryTransaction(
            id: 'TX_2',
            productId: 'PROD_ST26',
            type: TransactionType.import,
            quantity: 10,
            importPrice: 6100000.0,
            date: date2,
            importCode: 'PN_GROUP_01',
            note: 'Đợt 2',
            storeId: 'store_001',
            supplierId: 'SUP_001',
            supplierName: 'Công ty Ánh Dương',
          ),
          InventoryTransaction(
            id: 'TX_3',
            productId: 'UNKNOWN_PRODUCT',
            type: TransactionType.import,
            quantity: 2,
            importPrice: 50000.0,
            date: date3,
            importCode: 'PN_GROUP_01',
            note: 'Đợt 3',
            storeId: 'store_001',
          ),
        ];

        final grouped = groupTransactionsToReceipts(transactions: txList);

        expect(grouped.length, equals(1));
        final receipt = grouped.first;
        expect(receipt.importCode, equals('PN_GROUP_01'));
        expect(receipt.items.length, equals(3));
        // Must resolve latest date among all transactions (date2)
        expect(receipt.date, equals(date2));
        // Notes combined: 'Đợt 1; Đợt 2; Đợt 3'
        expect(receipt.note, equals('Đợt 1; Đợt 2; Đợt 3'));
        // Unknown product name resolved gracefully
        expect(receipt.items[2].productName, equals('Sản phẩm UNKNOWN_PRODUCT'));
      });

      test('T5.4.2: Riverpod merge provider precedence: Stored RTDB receipt overwrites legacy grouped receipt', () {
        final legacyReceipt = StockInReceipt(
          id: 'PN_OVERRIDE_001',
          importCode: 'PN_OVERRIDE_001',
          date: DateTime(2026, 9, 20),
          items: const [
            StockInReceiptItem(
              transactionId: 'TX_OLD',
              productId: 'PROD_1',
              quantity: 5,
              unitPrice: 10000.0,
            ),
          ],
          status: 'Đã nhập hàng',
        );

        final storedReceipt = StockInReceipt(
          id: 'STORED_RECEIPT_ID_999',
          importCode: 'PN_OVERRIDE_001', // Same importCode
          date: DateTime(2026, 9, 25),
          items: const [
            StockInReceiptItem(
              transactionId: 'TX_NEW',
              productId: 'PROD_1',
              quantity: 10,
              unitPrice: 12000.0,
            ),
          ],
          status: 'completed',
        );

        // Simulation of stockInReceiptsProvider merge logic
        final List<StockInReceipt> legacyReceipts = [legacyReceipt];
        final List<StockInReceipt> storedReceipts = [storedReceipt];

        final Map<String, StockInReceipt> receiptsByKey = {};
        final Map<String, String> codeToIdMap = {};

        for (final legacy in legacyReceipts) {
          receiptsByKey[legacy.id] = legacy;
          if (legacy.importCode.isNotEmpty) {
            codeToIdMap[legacy.importCode] = legacy.id;
          }
        }

        for (final stored in storedReceipts) {
          if (stored.importCode.isNotEmpty && codeToIdMap.containsKey(stored.importCode)) {
            final oldId = codeToIdMap[stored.importCode]!;
            receiptsByKey.remove(oldId);
          }
          receiptsByKey[stored.id] = stored;
          if (stored.importCode.isNotEmpty) {
            codeToIdMap[stored.importCode] = stored.id;
          }
        }

        final merged = receiptsByKey.values.toList();
        expect(merged.length, equals(1));
        expect(merged.first.id, equals('STORED_RECEIPT_ID_999'));
        expect(merged.first.items.first.quantity, equals(10));
        expect(merged.first.status, equals('completed'));
      });

      test('T5.4.3: Reactive filter state transitions, time boundary clamping (23:59:59.999), and Vietnamese unaccented search', () {
        final now = DateTime(2026, 9, 27, 23, 59, 59, 999);
        final wideRange = DateTimeRange(start: DateTime(2020), end: DateTime(2030));

        final r1 = StockInReceipt(
          id: 'REC_VN_1',
          importCode: 'PN_LUA_01',
          date: now,
          supplierName: 'Công ty Phân Bón Bình Điền',
          storeId: 'store_001',
          status: 'completed',
          items: const [
            StockInReceiptItem(
              transactionId: 'TX_VN_1',
              productId: 'PROD_ST25',
              quantity: 1,
              unitPrice: 100000.0,
              productName: 'Lúa giống ST25 Sóc Trăng',
            ),
          ],
        );

        final r2 = StockInReceipt(
          id: 'REC_VN_2',
          importCode: 'PN_DRAFT_02',
          date: now.subtract(const Duration(days: 40)), // Previous month
          supplierName: 'Hợp tác xã Nông nghiệp',
          storeId: 'store_002',
          status: 'draft',
          items: const [],
        );

        final allReceipts = [r1, r2];

        // 1. Search unaccented contiguous substring: "lua giong" matches "Lúa giống ST25 Sóc Trăng"
        var filter = StockInReceiptsFilterState(
          searchQuery: 'lua giong',
          timeRange: OverviewTimeRange.custom,
          customDateRange: wideRange,
        );
        var filtered = filterStockInReceipts(allReceipts, filter);
        expect(filtered.length, equals(1));
        expect(filtered.first.id, equals('REC_VN_1'));

        // 2. Search unaccented keyword: "soc trang" matches "Lúa giống ST25 Sóc Trăng"
        filter = StockInReceiptsFilterState(
          searchQuery: 'soc trang',
          timeRange: OverviewTimeRange.custom,
          customDateRange: wideRange,
        );
        filtered = filterStockInReceipts(allReceipts, filter);
        expect(filtered.length, equals(1));
        expect(filtered.first.id, equals('REC_VN_1'));

        // 3. Search unaccented supplier: "binh dien" matches "Bình Điền"
        filter = StockInReceiptsFilterState(
          searchQuery: 'binh dien',
          timeRange: OverviewTimeRange.custom,
          customDateRange: wideRange,
        );
        filtered = filterStockInReceipts(allReceipts, filter);
        expect(filtered.length, equals(1));
        expect(filtered.first.id, equals('REC_VN_1'));

        // 4. Non-contiguous query verification: "lua giong soc trang" returns 0 due to substring .contains
        filter = StockInReceiptsFilterState(
          searchQuery: 'lua giong soc trang',
          timeRange: OverviewTimeRange.custom,
          customDateRange: wideRange,
        );
        filtered = filterStockInReceipts(allReceipts, filter);
        expect(filtered.length, equals(0),
            reason: 'Exposes substring .contains requirement rather than tokenized matching');

        // 5. Status filter 'draft' / 'phiếu tạm'
        filter = StockInReceiptsFilterState(
          statusFilter: 'phiếu tạm',
          timeRange: OverviewTimeRange.custom,
          customDateRange: wideRange,
        );
        filtered = filterStockInReceipts(allReceipts, filter);
        expect(filtered.length, equals(1));
        expect(filtered.first.id, equals('REC_VN_2'));

        // 6. Store filter with canonical alias normalization ('branch_1' matches 'store_001')
        filter = StockInReceiptsFilterState(
          storeId: 'branch_1',
          timeRange: OverviewTimeRange.custom,
          customDateRange: wideRange,
        );
        filtered = filterStockInReceipts(allReceipts, filter);
        expect(filtered.length, equals(1));
        expect(filtered.first.id, equals('REC_VN_1'));
      });

      test('T5.4.4: Bounded latest import price query resilience with corrupted data and fallback', () async {
        final mockDb = MockFirebaseDatabase();
        final pRepo = _TestProductRepo();
        final ds = StockInReceiptRemoteDataSource(mockDb);
        final repo = StockInReceiptRepositoryImpl(ds, productRepository: pRepo);

        const testProd = Product(
          id: 'PROD_PRICE_TEST',
          name: 'Test price product',
          code: 'PRICE01',
          price: 100000.0,
          costPrice: 75000.0, // Fallback price
          category: 'Vật tư nông nghiệp',
          branchStocks: {'store_001': 10, 'store_002': 20},
        );
        pRepo.products[testProd.id] = testProd;

        // Seed transactions at parent collection node 'stores/store_001/inventory_transactions'
        // so query .orderByChild('productId').equalTo(...) accesses child records
        mockDb.seedData('stores/store_001/inventory_transactions', {
          'tx_1': {
            'productId': testProd.id,
            'type': 'export',
            'importPrice': 990000.0,
            'date': '2026-09-27T10:00:00.000Z',
          },
          'tx_2': {
            'productId': testProd.id,
            'type': 'import',
            'importPrice': -50000.0,
            'date': '2026-09-27T11:00:00.000Z',
          },
          'tx_3': {
            'productId': testProd.id,
            'type': 'import',
            'importPrice': 80000.0,
            'date': '2026-09-20T10:00:00.000Z',
          },
          'tx_4': {
            'productId': testProd.id,
            'type': 'import',
            'importPrice': 85000.0,
            'date': '2026-09-25T10:00:00.000Z',
          },
        });

        final latestPrice = await repo.getLatestImportPrice(
          storeId: 'store_001',
          productId: testProd.id,
        );

        // Correctly selects newer valid import price (85,000)
        expect(latestPrice, equals(85000.0));

        // When product has no transactions in store_002, falls back to product.costPrice (75,000)
        final fallbackPrice = await repo.getLatestImportPrice(
          storeId: 'store_002',
          productId: testProd.id,
        );
        expect(fallbackPrice, equals(75000.0));

        // When product does not exist, returns null
        final nullPrice = await repo.getLatestImportPrice(
          storeId: 'store_001',
          productId: 'NON_EXISTENT_ID',
        );
        expect(nullPrice, isNull);
      });
    });
  });
}
