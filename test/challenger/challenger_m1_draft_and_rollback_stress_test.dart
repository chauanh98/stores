import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/cancel_stock_in_receipt_use_case.dart';
import 'package:stores/application/inventories/usecases/complete_stock_in_receipt_use_case.dart';
import 'package:stores/application/inventories/usecases/delete_stock_in_receipt_use_case.dart';
import 'package:stores/application/inventories/usecases/save_stock_in_draft_use_case.dart';
import 'package:stores/data/datasources/stock_in_receipt_remote_data_source.dart';
import 'package:stores/data/repositories/stock_in_receipt_repository_impl.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/stock_in_receipt_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

import '../support/firebase_test_harness.dart';

// ============================================================================
// IN-MEMORY FAKES FOR REPOSITORIES
// ============================================================================

class FakeProductRepository implements ProductRepository {
  final Map<String, Product> products = {};
  int fetchCallCount = 0;
  int upsertCallCount = 0;

  @override
  Future<Product?> fetchById(String id) async {
    fetchCallCount++;
    return products[id];
  }

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Future<void> upsert(Product product) async {
    upsertCallCount++;
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
}

class FakeInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];
  int recordCallCount = 0;

  @override
  Future<void> record(InventoryTransaction tx) async {
    recordCallCount++;
    transactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(transactions.where((t) => t.productId == productId).toList());

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(DateTime start, DateTime end) =>
      Stream.value(transactions.where((t) => t.type == TransactionType.import).toList());
}

class FakeSupplierRepository implements SupplierRepository {
  final Map<String, Supplier> suppliers = {};
  final List<SupplierDebtTransaction> debtTransactions = [];
  int upsertCallCount = 0;
  int recordDebtCallCount = 0;

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async => suppliers[id];

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    upsertCallCount++;
    suppliers[supplier.id] = supplier;
  }

  @override
  Future<void> delete(String id, {String? storeId}) async {
    suppliers.remove(id);
  }

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction tx, {String? storeId}) async {
    recordDebtCallCount++;
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

// ============================================================================
// MAIN ADVERSARIAL CHALLENGE SUITE
// ============================================================================

void main() {
  group('Challenger M1_1: Draft Zero-Mutation & Atomic Rollback Stress Suite', () {
    late MockFirebaseDatabase mockDb;
    late StockInReceiptRemoteDataSource remoteDataSource;
    late StockInReceiptRepository receiptRepo;
    late FakeProductRepository productRepo;
    late FakeInventoryRepository inventoryRepo;
    late FakeSupplierRepository supplierRepo;

    late SaveStockInDraftUseCase saveDraftUseCase;
    late CompleteStockInReceiptUseCase completeUseCase;
    late CancelStockInReceiptUseCase cancelUseCase;
    late DeleteStockInReceiptUseCase deleteUseCase;

    setUp(() {
      mockDb = MockFirebaseDatabase();
      remoteDataSource = StockInReceiptRemoteDataSource(mockDb);
      productRepo = FakeProductRepository();
      inventoryRepo = FakeInventoryRepository();
      supplierRepo = FakeSupplierRepository();
      receiptRepo = StockInReceiptRepositoryImpl(
        remoteDataSource,
        productRepository: productRepo,
      );

      saveDraftUseCase = SaveStockInDraftUseCase(receiptRepo);
      completeUseCase = CompleteStockInReceiptUseCase(
        db: mockDb,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        supplierRepository: supplierRepo,
        receiptRepository: receiptRepo,
      );
      cancelUseCase = CancelStockInReceiptUseCase(
        db: mockDb,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        supplierRepository: supplierRepo,
        receiptRepository: receiptRepo,
      );
      deleteUseCase = DeleteStockInReceiptUseCase(receiptRepo);
    });

    // -------------------------------------------------------------------------
    // 1. DRAFT ZERO-MUTATION INVARIANT & BOUNDARY STRESS TESTING
    // -------------------------------------------------------------------------
    group('1. Draft Zero-Mutation Invariant & Boundary Conditions', () {
      test('1.1 Empty items draft: saves with status "draft" and 100% zero mutations to stocks, debt, or transactions', () async {
        // Initial setup with a product and supplier
        const initialProduct = Product(
          id: 'p_base_01',
          name: 'Phân NPK 20-20-15',
          code: 'NPK20',
          price: 450000,
          costPrice: 380000,
          branchStocks: {'store_001': 100, 'branch_1': 100, 'store_002': 50},
          category: 'Phân bón',
        );
        productRepo.products['p_base_01'] = initialProduct;

        const initialSupplier = Supplier(
          id: 'sup_base_01',
          code: 'NCC01',
          name: 'Công ty Phân Bón Bình Điền',
          currentDebt: 10000000,
          totalPurchase: 50000000,
        );
        supplierRepo.suppliers['sup_base_01'] = initialSupplier;

        mockDb.recorder.clear();

        final draftReceipt = StockInReceipt(
          id: 'draft_empty_01',
          importCode: 'PN_DRAFT_EMPTY',
          date: DateTime(2026, 9, 27, 8, 30),
          storeId: 'store_001',
          supplierId: 'sup_base_01',
          items: const [], // Empty items boundary
          discount: 0,
          paidAmount: 0,
        );

        final returnedId = await saveDraftUseCase.execute(draftReceipt);
        expect(returnedId, 'draft_empty_01');

        // Verify draft was saved in RTDB
        final savedMap = await remoteDataSource.getReceipt('store_001', 'draft_empty_01');
        expect(savedMap, isNotNull);
        expect(savedMap!['status'], 'draft');
        expect(savedMap['storeId'], 'store_001');

        // ASSERT 100% ZERO-MUTATION INVARIANTS:
        // 1. Branch stocks must remain completely untouched
        final p = productRepo.products['p_base_01']!;
        expect(p.branchStocks['store_001'], 100);
        expect(p.branchStocks['branch_1'], 100);
        expect(p.branchStocks['store_002'], 50);
        expect(productRepo.upsertCallCount, 0);

        // 2. Inventory transactions must remain untouched (0 recorded)
        expect(inventoryRepo.transactions, isEmpty);
        expect(inventoryRepo.recordCallCount, 0);

        // 3. Supplier debts must remain untouched
        final s = supplierRepo.suppliers['sup_base_01']!;
        expect(s.currentDebt, 10000000.0);
        expect(s.totalPurchase, 50000000.0);
        expect(supplierRepo.debtTransactions, isEmpty);
        expect(supplierRepo.upsertCallCount, 0);

        // 4. Verify in MockFirebaseDatabase: ONLY stores/store_001/stock_in_receipts/draft_empty_01 was touched
        for (final call in mockDb.recorder.calls) {
          expect(call.path.contains('products'), isFalse, reason: 'Must not touch products in RTDB: ${call.path}');
          expect(call.path.contains('inventory_transactions'), isFalse, reason: 'Must not touch inventory_transactions in RTDB: ${call.path}');
          expect(call.path.contains('shared_suppliers'), isFalse, reason: 'Must not touch shared_suppliers in RTDB: ${call.path}');
        }
      });

      test('1.2 Massive numerical boundary: trillions VND & huge quantities preserve precision with 0 mutations', () async {
        const initialProduct = Product(
          id: 'p_gold',
          name: 'Phân bón lá sinh học nhập khẩu',
          code: 'BIO_GOLD',
          price: 500000000,
          costPrice: 400000000,
          branchStocks: {'store_001': 500, 'branch_1': 500},
          category: 'Phân bón lá',
        );
        productRepo.products['p_gold'] = initialProduct;

        const initialSupplier = Supplier(
          id: 'sup_mega',
          code: 'SUP_MEGA',
          name: 'Tập đoàn Hóa chất Quốc tế',
          currentDebt: 500000000000.0, // 500 billion VND
          totalPurchase: 1000000000000.0, // 1 trillion VND
        );
        supplierRepo.suppliers['sup_mega'] = initialSupplier;

        mockDb.recorder.clear();

        // 10 million units @ 500,000,000 = 5,000,000,000,000,000 (5 quadrillion VND)
        const hugeQty = 10000000;
        const hugeUnitPrice = 500000000.0;
        final draftReceipt = StockInReceipt(
          id: 'draft_huge_01',
          importCode: 'PN_DRAFT_HUGE',
          date: DateTime(2026, 9, 27, 9, 0),
          storeId: 'store_001',
          supplierId: 'sup_mega',
          items: const [
            StockInReceiptItem(
              transactionId: 'tx_huge_1',
              productId: 'p_gold',
              quantity: hugeQty,
              unitPrice: hugeUnitPrice,
            ),
          ],
          discount: 1000000000.0, // 1 billion discount
          paidAmount: 2000000000000000.0, // 2 quadrillion paid
        );

        expect(draftReceipt.totalQuantity, hugeQty);
        expect(draftReceipt.totalAmount, 5000000000000000.0);
        expect(draftReceipt.effectiveNetPayable, 4999999000000000.0);
        expect(draftReceipt.remainingDebt, 2999999000000000.0);

        final returnedId = await saveDraftUseCase.execute(draftReceipt);
        expect(returnedId, 'draft_huge_01');

        // Assert 100% untouched
        expect(productRepo.products['p_gold']!.branchStocks['store_001'], 500);
        expect(supplierRepo.suppliers['sup_mega']!.currentDebt, 500000000000.0);
        expect(supplierRepo.suppliers['sup_mega']!.totalPurchase, 1000000000000.0);
        expect(inventoryRepo.transactions, isEmpty);
        expect(supplierRepo.debtTransactions, isEmpty);
      });

      test('1.3 Adversarial strings: special characters, multiline, unicode diacritics & injection strings in notes', () async {
        const adversarialNote = 'Hàng nhập đợt 1: Đạm Cà Mau & NPK 16-16-8! @#\$%^&*()_+{}[]|:;"\'<>?,./\n'
            'Dòng 2: Ghi chú tiếng Việt có dấu: Ắ, Ằ, Ẳ, Ẵ, Ặ, Ế, Ề, Ể, Ễ, Ệ, Ố, Ồ, Ổ, Ỗ, Ộ\n'
            'Emoji: 🔥📦🚀💊\n'
            'SQL Injection test: \'; DROP TABLE receipts; --\n'
            'XSS test: <script>alert("xss")</script>\n'
            'Zero-width space test: \u200B\u200C\u200D';

        final receipt = StockInReceipt(
          id: 'draft_adv_note_01',
          importCode: 'PN_ADV_NOTE',
          date: DateTime(2026, 9, 27, 9, 30),
          storeId: 'store_001',
          note: adversarialNote,
          items: const [
            StockInReceiptItem(
              transactionId: 't_adv_1',
              productId: 'p_adv_1',
              quantity: 5,
              unitPrice: 100000,
              note: 'Item note: <xml><danger>true</danger></xml>',
            ),
          ],
        );

        final returnedId = await saveDraftUseCase.execute(receipt);
        expect(returnedId, 'draft_adv_note_01');

        // Retrieve and verify lossless round-trip
        final fetched = await receiptRepo.getReceiptById(storeId: 'store_001', receiptId: 'draft_adv_note_01');
        expect(fetched, isNotNull);
        expect(fetched!.note, adversarialNote);
        expect(fetched.items.first.note, 'Item note: <xml><danger>true</danger></xml>');
        expect(fetched.isDraft, isTrue);

        // Verify zero mutations
        expect(productRepo.upsertCallCount, 0);
        expect(inventoryRepo.recordCallCount, 0);
        expect(supplierRepo.upsertCallCount, 0);
      });

      test('1.4 Draft lifecycle: update and delete preserves zero-mutation invariant throughout', () async {
        final initialDraft = StockInReceipt(
          id: 'draft_lifecycle_01',
          importCode: 'PN_LIFECYCLE',
          date: DateTime(2026, 9, 27),
          storeId: 'store_001',
          items: const [
            StockInReceiptItem(
              transactionId: 'tx_l1',
              productId: 'p_life',
              quantity: 10,
              unitPrice: 100000,
            ),
          ],
        );

        // 1. Save draft
        await saveDraftUseCase.execute(initialDraft);

        // 2. Update draft with changed quantity and price
        final updatedDraft = initialDraft.copyWith(
          note: 'Updated draft note',
          items: const [
            StockInReceiptItem(
              transactionId: 'tx_l1',
              productId: 'p_life',
              quantity: 25,
              unitPrice: 120000,
            ),
          ],
        );
        await receiptRepo.updateDraft(updatedDraft);

        var stored = await receiptRepo.getReceiptById(storeId: 'store_001', receiptId: 'draft_lifecycle_01');
        expect(stored, isNotNull);
        expect(stored!.items.first.quantity, 25);
        expect(stored.note, 'Updated draft note');

        // 3. Delete draft
        await deleteUseCase.execute(storeId: 'store_001', receipt: stored);

        stored = await receiptRepo.getReceiptById(storeId: 'store_001', receiptId: 'draft_lifecycle_01');
        expect(stored, isNull);

        // 4. Assert 100% zero mutations
        expect(productRepo.upsertCallCount, 0);
        expect(inventoryRepo.recordCallCount, 0);
        expect(supplierRepo.upsertCallCount, 0);
      });
    });

    // -------------------------------------------------------------------------
    // 2. COMPLETE -> CANCEL LIFECYCLE ATOMIC ROLLBACK CORRECTNESS
    // -------------------------------------------------------------------------
    group('2. Complete -> Cancel Lifecycle Atomic Rollback Correctness', () {
      test('2.1 Multi-item, multi-branch receipt: cancelling perfectly restores pre-receipt stock & debt', () async {
        // Setup initial products in both branches
        const initialProductA = Product(
          id: 'prod_a',
          name: 'Phân Ure Cà Mau',
          code: 'URE_CM',
          price: 600000,
          costPrice: 500000,
          branchStocks: {
            'store_001': 50,
            'branch_1': 50,
            'store_002': 20,
            'branch_2': 20,
          },
          category: 'Phân bón vô cơ',
        );
        const initialProductB = Product(
          id: 'prod_b',
          name: 'Thuốc Trừ Sâu Regent',
          code: 'REGENT',
          price: 250000,
          costPrice: 200000,
          branchStocks: {
            'store_001': 30,
            'branch_1': 30,
            'store_002': 15,
            'branch_2': 15,
          },
          category: 'Thuốc BVTV',
        );
        productRepo.products['prod_a'] = initialProductA;
        productRepo.products['prod_b'] = initialProductB;

        const initialSupplier = Supplier(
          id: 'sup_sun',
          code: 'NCC_SUN',
          name: 'Công ty Ánh Thái Dương',
          currentDebt: 10000000.0,
          totalPurchase: 40000000.0,
        );
        supplierRepo.suppliers['sup_sun'] = initialSupplier;

        // STEP 1: Complete Receipt
        // Item A: 20 units @ 520,000 = 10,400,000
        // Item B: 10 units @ 210,000 = 2,100,000
        // Total = 12,500,000, Discount = 500,000, NetPayable = 12,000,000
        // Paid = 4,000,000, Remaining Debt = 8,000,000
        final receipt = StockInReceipt(
          id: 'rec_lifecycle_full',
          importCode: 'PN_LIFECYCLE_FULL',
          date: DateTime(2026, 9, 27, 10, 0),
          storeId: 'store_001',
          supplierId: 'sup_sun',
          supplierName: 'Công ty Ánh Thái Dương',
          discount: 500000,
          paidAmount: 4000000,
          items: const [
            StockInReceiptItem(
              transactionId: 'tx_a',
              productId: 'prod_a',
              quantity: 20,
              unitPrice: 520000,
            ),
            StockInReceiptItem(
              transactionId: 'tx_b',
              productId: 'prod_b',
              quantity: 10,
              unitPrice: 210000,
            ),
          ],
        );

        final completed = await completeUseCase.execute(receipt);
        expect(completed.isCompleted, isTrue);
        expect(completed.status, 'completed');

        // Verify post-completion state:
        // Product A: 50 + 20 = 70 in store_001 and branch_1, store_002 remains 20
        expect(productRepo.products['prod_a']!.branchStocks['store_001'], 70);
        expect(productRepo.products['prod_a']!.branchStocks['branch_1'], 70);
        expect(productRepo.products['prod_a']!.branchStocks['store_002'], 20);

        // Product B: 30 + 10 = 40 in store_001 and branch_1, store_002 remains 15
        expect(productRepo.products['prod_b']!.branchStocks['store_001'], 40);
        expect(productRepo.products['prod_b']!.branchStocks['branch_1'], 40);
        expect(productRepo.products['prod_b']!.branchStocks['store_002'], 15);

        // Supplier: debt = 10M + 8M = 18M, purchase = 40M + 12M = 52M
        expect(supplierRepo.suppliers['sup_sun']!.currentDebt, 18000000.0);
        expect(supplierRepo.suppliers['sup_sun']!.totalPurchase, 52000000.0);
        expect(inventoryRepo.transactions.length, 2);
        expect(supplierRepo.debtTransactions.length, 1);
        expect(supplierRepo.debtTransactions.first.amount, 8000000.0);

        // STEP 2: Cancel Completed Receipt
        mockDb.recorder.clear();
        await cancelUseCase.execute(
          storeId: 'store_001',
          receipt: completed,
          reason: 'Hàng không đúng quy cách chất lượng cam kết',
          cancelledBy: 'supervisor_long',
        );

        // STEP 3: ASSERT PRECISE 100% RESTORATION TO PRE-RECEIPT STATE
        // Product A exactly pre-receipt:
        final rolledBackA = productRepo.products['prod_a']!;
        expect(rolledBackA.branchStocks['store_001'], initialProductA.branchStocks['store_001']);
        expect(rolledBackA.branchStocks['branch_1'], initialProductA.branchStocks['branch_1']);
        expect(rolledBackA.branchStocks['store_002'], initialProductA.branchStocks['store_002']);
        expect(rolledBackA.branchStocks['branch_2'], initialProductA.branchStocks['branch_2']);

        // Product B exactly pre-receipt:
        final rolledBackB = productRepo.products['prod_b']!;
        expect(rolledBackB.branchStocks['store_001'], initialProductB.branchStocks['store_001']);
        expect(rolledBackB.branchStocks['branch_1'], initialProductB.branchStocks['branch_1']);
        expect(rolledBackB.branchStocks['store_002'], initialProductB.branchStocks['store_002']);
        expect(rolledBackB.branchStocks['branch_2'], initialProductB.branchStocks['branch_2']);

        // Supplier debt & total purchase exactly pre-receipt:
        final rolledBackSupplier = supplierRepo.suppliers['sup_sun']!;
        expect(rolledBackSupplier.currentDebt, initialSupplier.currentDebt);
        expect(rolledBackSupplier.totalPurchase, initialSupplier.totalPurchase);

        // Receipt status updated to cancelled:
        final cancelledDoc = await receiptRepo.getReceiptById(storeId: 'store_001', receiptId: completed.id);
        expect(cancelledDoc, isNotNull);
        expect(cancelledDoc!.status, 'cancelled');
        expect(cancelledDoc.isCancelled, isTrue);
        expect(cancelledDoc.isCompleted, isFalse);
        expect(cancelledDoc.cancelReason, 'Hàng không đúng quy cách chất lượng cam kết');
        expect(cancelledDoc.cancelledBy, 'supervisor_long');
        expect(cancelledDoc.cancelledAt, isNotNull);

        // Reversal inventory transactions recorded (type: export):
        expect(inventoryRepo.transactions.length, 4); // 2 import + 2 reversal export
        final revTxA = inventoryRepo.transactions.firstWhere((t) => t.productId == 'prod_a' && t.type == TransactionType.export);
        expect(revTxA.quantity, 20);
        expect(revTxA.note.contains('Hàng không đúng quy cách chất lượng cam kết'), isTrue);

        final revTxB = inventoryRepo.transactions.firstWhere((t) => t.productId == 'prod_b' && t.type == TransactionType.export);
        expect(revTxB.quantity, 10);
        expect(revTxB.note.contains('Hàng không đúng quy cách chất lượng cam kết'), isTrue);

        // Reversal supplier debt transaction recorded:
        expect(supplierRepo.debtTransactions.length, 2);
        final revDebtTx = supplierRepo.debtTransactions.last;
        expect(revDebtTx.type, SupplierDebtType.adjustment);
        expect(revDebtTx.amount, -8000000.0);
        expect(revDebtTx.remainingDebt, 10000000.0); // Restored to 10M
        expect(revDebtTx.referenceCode, 'PN_LIFECYCLE_FULL');
      });

      test('2.2 Cross-branch store_002 (Thới Bình) lifecycle rolls back store_002 and leaves store_001 completely untouched', () async {
        const product = Product(
          id: 'p_thoi_binh',
          name: 'Lúa giống ST25',
          code: 'ST25',
          price: 35000,
          costPrice: 28000,
          branchStocks: {
            'store_001': 1000,
            'branch_1': 1000,
            'store_002': 200,
            'branch_2': 200,
          },
          category: 'Giống cây trồng',
        );
        productRepo.products['p_thoi_binh'] = product;

        final receipt = StockInReceipt(
          id: 'rec_tb_01',
          importCode: 'PN_TB_01',
          date: DateTime(2026, 9, 27),
          storeId: 'store_002',
          items: const [
            StockInReceiptItem(
              transactionId: 't_tb',
              productId: 'p_thoi_binh',
              quantity: 150,
              unitPrice: 28000,
            ),
          ],
        );

        final completed = await completeUseCase.execute(receipt);
        // store_002 increased to 350, store_001 stays 1000
        expect(productRepo.products['p_thoi_binh']!.branchStocks['store_002'], 350);
        expect(productRepo.products['p_thoi_binh']!.branchStocks['branch_2'], 350);
        expect(productRepo.products['p_thoi_binh']!.branchStocks['store_001'], 1000);
        expect(productRepo.products['p_thoi_binh']!.branchStocks['branch_1'], 1000);

        // Cancel on store_002
        await cancelUseCase.execute(
          storeId: 'store_002',
          receipt: completed,
          reason: 'Hủy phiếu nhập giống Thới Bình',
          cancelledBy: 'admin',
        );

        // store_002 restored to exactly 200, store_001 still exactly 1000
        expect(productRepo.products['p_thoi_binh']!.branchStocks['store_002'], 200);
        expect(productRepo.products['p_thoi_binh']!.branchStocks['branch_2'], 200);
        expect(productRepo.products['p_thoi_binh']!.branchStocks['store_001'], 1000);
        expect(productRepo.products['p_thoi_binh']!.branchStocks['branch_1'], 1000);
      });

      test('2.3 Fully paid (100% cash) receipt lifecycle: debt is never mutated, totalPurchase rolls back cleanly', () async {
        const initialSupplier = Supplier(
          id: 'sup_cash_only',
          code: 'NCC_CASH',
          name: 'Đại lý Tiền Mặt',
          currentDebt: 3000000.0,
          totalPurchase: 10000000.0,
        );
        supplierRepo.suppliers['sup_cash_only'] = initialSupplier;

        final receipt = StockInReceipt(
          id: 'rec_cash_01',
          importCode: 'PN_CASH_01',
          date: DateTime(2026, 9, 27),
          storeId: 'store_001',
          supplierId: 'sup_cash_only',
          paidAmount: 5000000.0, // Full payment
          items: const [
            StockInReceiptItem(
              transactionId: 't_c1',
              productId: 'p_none',
              quantity: 10,
              unitPrice: 500000,
            ),
          ],
        );

        final completed = await completeUseCase.execute(receipt);
        // Debt does not increase because remainingDebt = 0
        expect(supplierRepo.suppliers['sup_cash_only']!.currentDebt, 3000000.0);
        expect(supplierRepo.suppliers['sup_cash_only']!.totalPurchase, 15000000.0);

        await cancelUseCase.execute(
          storeId: 'store_001',
          receipt: completed,
          reason: 'Hủy đơn tiền mặt',
          cancelledBy: 'admin',
        );

        // Debt remains 3,000,000 and totalPurchase rolls back to 10,000,000
        expect(supplierRepo.suppliers['sup_cash_only']!.currentDebt, 3000000.0);
        expect(supplierRepo.suppliers['sup_cash_only']!.totalPurchase, 10000000.0);
      });

      test('2.4 Anonymous purchase (no supplier ID): stock completes and cancels cleanly without supplier side-effects', () async {
        const product = Product(
          id: 'p_anon',
          name: 'Hàng chợ vãng lai',
          code: 'ANON01',
          price: 10000,
          costPrice: 8000,
          branchStocks: {'store_001': 50},
          category: 'Vãng lai',
        );
        productRepo.products['p_anon'] = product;

        final receipt = StockInReceipt(
          id: 'rec_anon_01',
          importCode: 'PN_ANON_01',
          date: DateTime(2026, 9, 27),
          storeId: 'store_001',
          supplierId: null, // No supplier
          items: const [
            StockInReceiptItem(
              transactionId: 't_anon',
              productId: 'p_anon',
              quantity: 20,
              unitPrice: 8000,
            ),
          ],
        );

        final completed = await completeUseCase.execute(receipt);
        expect(productRepo.products['p_anon']!.branchStocks['store_001'], 70);
        expect(supplierRepo.suppliers, isEmpty);

        await cancelUseCase.execute(
          storeId: 'store_001',
          receipt: completed,
          reason: 'Hủy hàng vãng lai',
          cancelledBy: 'admin',
        );

        expect(productRepo.products['p_anon']!.branchStocks['store_001'], 50);
        expect(supplierRepo.suppliers, isEmpty);
      });
    });

    // -------------------------------------------------------------------------
    // 3. EDGE CASES, PARTIAL DEPLETION CLAMPING & ANOMALY HANDLING
    // -------------------------------------------------------------------------
    group('3. Edge Cases, Partial Depletion Clamping & Anomaly Handling', () {
      test('3.1 Stock partially depleted before cancellation: non-negative clamping prevents negative inventory', () async {
        // Scenario: Initial stock 5, receipt adds 20 -> stock 25.
        // Sales/transfers sell 22 units -> current stock drops to 3 (which is < 20).
        // Receipt cancellation is triggered.
        const product = Product(
          id: 'p_depleted',
          name: 'Phân bón bán chạy',
          code: 'DEP01',
          price: 200000,
          costPrice: 150000,
          branchStocks: {'store_001': 5, 'branch_1': 5},
          category: 'Phân bón',
        );
        productRepo.products['p_depleted'] = product;

        final receipt = StockInReceipt(
          id: 'rec_depleted_01',
          importCode: 'PN_DEP_01',
          date: DateTime(2026, 9, 27),
          storeId: 'store_001',
          items: const [
            StockInReceiptItem(
              transactionId: 't_dep',
              productId: 'p_depleted',
              quantity: 20,
              unitPrice: 150000,
            ),
          ],
        );

        final completed = await completeUseCase.execute(receipt);
        expect(productRepo.products['p_depleted']!.branchStocks['store_001'], 25);

        // Simulate sales depletion: stock drops to 3
        productRepo.products['p_depleted'] = productRepo.products['p_depleted']!.copyWith(
          branchStocks: {'store_001': 3, 'branch_1': 3},
        );

        // Execute cancellation
        await cancelUseCase.execute(
          storeId: 'store_001',
          receipt: completed,
          reason: 'Hủy phiếu sau khi đã bán bớt',
          cancelledBy: 'admin',
        );

        // ASSERTION:
        // Stock must be clamped to 0 (3 - 20 clamped to 0), NEVER -17
        final finalProduct = productRepo.products['p_depleted']!;
        expect(finalProduct.branchStocks['store_001'], 0);
        expect(finalProduct.branchStocks['branch_1'], 0);
        expect(finalProduct.stockInBranch('store_001') >= 0, isTrue);

        // Audit integrity: Reversal export transaction still logs full 20 units for traceability
        final revTx = inventoryRepo.transactions.last;
        expect(revTx.type, TransactionType.export);
        expect(revTx.quantity, 20);
      });

      test('3.2 Supplier debt partially cleared before cancellation: non-negative clamping prevents negative debt & purchase', () async {
        // Scenario: Initial supplier debt 1M.
        // Receipt adds 5M remaining debt -> debt = 6M.
        // Store pays off 5.5M cash in the interim -> current debt drops to 500,000 (< 5M).
        // Also totalPurchase was adjusted to 3M.
        // Cancellation of 5M receipt is triggered.
        const supplier = Supplier(
          id: 'sup_depleted_debt',
          code: 'SUP_DEP',
          name: 'NCC Dư nợ đã thanh toán một phần',
          currentDebt: 1000000.0,
          totalPurchase: 10000000.0,
        );
        supplierRepo.suppliers['sup_depleted_debt'] = supplier;

        final receipt = StockInReceipt(
          id: 'rec_debt_clamp',
          importCode: 'PN_DEBT_CLAMP',
          date: DateTime(2026, 9, 27),
          storeId: 'store_001',
          supplierId: 'sup_depleted_debt',
          paidAmount: 0, // 5M remaining debt
          items: const [
            StockInReceiptItem(
              transactionId: 't_dc',
              productId: 'p_dummy',
              quantity: 10,
              unitPrice: 500000,
            ),
          ],
        );

        final completed = await completeUseCase.execute(receipt);
        expect(supplierRepo.suppliers['sup_depleted_debt']!.currentDebt, 6000000.0);

        // Simulate debt payment and purchase adjustment:
        supplierRepo.suppliers['sup_depleted_debt'] = supplierRepo.suppliers['sup_depleted_debt']!.copyWith(
          currentDebt: 500000.0, // 500k < 5M
          totalPurchase: 3000000.0, // 3M < 5M
        );

        // Execute cancellation
        await cancelUseCase.execute(
          storeId: 'store_001',
          receipt: completed,
          reason: 'Hủy phiếu khi nợ NCC đã được trả bớt',
          cancelledBy: 'admin',
        );

        final finalSupplier = supplierRepo.suppliers['sup_depleted_debt']!;
        // Clamped at 0.0, NEVER negative (-4.5M)
        expect(finalSupplier.currentDebt, 0.0);
        expect(finalSupplier.totalPurchase, 0.0);
        expect(finalSupplier.currentDebt >= 0.0, isTrue);

        // Reversal debt transaction records remainingDebt = 0.0
        final revDebtTx = supplierRepo.debtTransactions.last;
        expect(revDebtTx.type, SupplierDebtType.adjustment);
        expect(revDebtTx.amount, -5000000.0);
        expect(revDebtTx.remainingDebt, 0.0);
      });

      test('3.3 Safety Invariant: Deleting completed receipt directly throws StateError without mutating database', () async {
        final completedReceipt = StockInReceipt(
          id: 'rec_cannot_delete',
          importCode: 'PN_CANNOT_DELETE',
          date: DateTime(2026, 9, 27),
          storeId: 'store_001',
          status: 'completed',
          items: const [],
        );
        await receiptRepo.saveReceipt(completedReceipt);

        expect(
          () => deleteUseCase.execute(storeId: 'store_001', receipt: completedReceipt),
          throwsA(isA<StateError>()),
        );

        // Receipt remains in repository
        final stillThere = await receiptRepo.getReceiptById(storeId: 'store_001', receiptId: 'rec_cannot_delete');
        expect(stillThere, isNotNull);

        // Once cancelled, delete succeeds
        final cancelledReceipt = completedReceipt.copyWith(status: 'cancelled');
        await receiptRepo.saveReceipt(cancelledReceipt);
        await deleteUseCase.execute(storeId: 'store_001', receipt: cancelledReceipt);

        final deleted = await receiptRepo.getReceiptById(storeId: 'store_001', receiptId: 'rec_cannot_delete');
        expect(deleted, isNull);
      });

      test('3.4 Atomic Multi-Path RTDB updates validation during complete and cancel', () async {
        const product = Product(
          id: 'p_atomic',
          name: 'Phân Kali Clorua',
          code: 'KCL01',
          price: 300000,
          costPrice: 200000,
          branchStocks: {'store_001': 40, 'branch_1': 40},
          category: 'Phân Kali',
        );
        productRepo.products['p_atomic'] = product;

        const supplier = Supplier(
          id: 'sup_atomic',
          code: 'SUP_ATOMIC',
          name: 'NCC Hóa chất Mỏ',
          currentDebt: 5000000.0,
          totalPurchase: 20000000.0,
        );
        supplierRepo.suppliers['sup_atomic'] = supplier;

        mockDb.recorder.clear();

        final receipt = StockInReceipt(
          id: 'rec_atomic_01',
          importCode: 'PN_ATOMIC_01',
          date: DateTime(2026, 9, 27),
          storeId: 'store_001',
          supplierId: 'sup_atomic',
          paidAmount: 1000000, // netPayable = 3M, remainingDebt = 2M
          items: const [
            StockInReceiptItem(
              transactionId: 'tx_atom',
              productId: 'p_atomic',
              quantity: 10,
              unitPrice: 300000,
            ),
          ],
        );

        final completed = await completeUseCase.execute(receipt);

        // Verify root-level multi-path update occurred
        final completeUpdates = mockDb.recorder.callsFor('update', path: '');
        expect(completeUpdates, isNotEmpty);
        final completeMap = completeUpdates.last.value as Map<String, dynamic>;

        expect(completeMap.containsKey('stores/store_001/products/p_atomic/branchStocks'), isTrue);
        expect(completeMap.containsKey('stores/store_001/products/p_atomic/costPrice'), isTrue);
        expect(completeMap.containsKey('stores/store_001/stock_in_receipts/rec_atomic_01'), isTrue);
        expect(completeMap.containsKey('shared_suppliers/sup_atomic/currentDebt'), isTrue);
        expect(completeMap.containsKey('shared_suppliers/sup_atomic/totalPurchase'), isTrue);

        mockDb.recorder.clear();

        await cancelUseCase.execute(
          storeId: 'store_001',
          receipt: completed,
          reason: 'Test rollback atomic paths',
          cancelledBy: 'lead_dev',
        );

        final rootCancelUpdates = mockDb.recorder.calls
            .where((c) => c.method == 'update' && (c.path.isEmpty || c.path == '/'))
            .toList();
        expect(rootCancelUpdates, isNotEmpty);
        final cancelMap = rootCancelUpdates.last.value as Map<String, dynamic>;

        expect(cancelMap.containsKey('stores/store_001/stock_in_receipts/rec_atomic_01'), isTrue);
        expect(cancelMap.containsKey('stores/store_001/products/p_atomic/branchStocks'), isTrue);
        expect(cancelMap.containsKey('shared_suppliers/sup_atomic/currentDebt'), isTrue);
        expect(cancelMap.containsKey('shared_suppliers/sup_atomic/totalPurchase'), isTrue);
      });

      test('3.5 Empirical Challenge: Duplicate product line items in a single receipt', () async {
        const product = Product(
          id: 'p_duplicate',
          name: 'Phân Lân Văn Điển',
          code: 'LAN_VD',
          price: 150000,
          costPrice: 100000,
          branchStocks: {'store_001': 20, 'branch_1': 20},
          category: 'Phân lân',
        );
        productRepo.products['p_duplicate'] = product;

        // Adversarial receipt with two line items referencing the SAME product
        final receipt = StockInReceipt(
          id: 'rec_dup_01',
          importCode: 'PN_DUP_01',
          date: DateTime(2026, 9, 27),
          storeId: 'store_001',
          items: const [
            StockInReceiptItem(
              transactionId: 'tx_dup_1',
              productId: 'p_duplicate',
              quantity: 10,
              unitPrice: 100000,
            ),
            StockInReceiptItem(
              transactionId: 'tx_dup_2',
              productId: 'p_duplicate',
              quantity: 5,
              unitPrice: 100000,
            ),
          ],
        );

        final completed = await completeUseCase.execute(receipt);
        expect(completed.isCompleted, isTrue);
        final stockAfterComplete = productRepo.products['p_duplicate']!.stockInBranch('store_001');

        // FIXED: Duplicate line items in receipt correctly accumulate in-flight: 20 + 10 + 5 = 35
        expect(
          stockAfterComplete,
          35,
          reason: 'Duplicate line items in receipt correctly accumulate in-flight rather than overwriting',
        );

        // Verify rollback also aggregates correctly: 35 - 15 = 20
        await cancelUseCase.execute(
          storeId: 'store_001',
          receipt: completed,
          reason: 'Hủy phiếu có dòng hàng trùng',
          cancelledBy: 'user1',
        );
        final stockAfterCancel = productRepo.products['p_duplicate']!.stockInBranch('store_001');
        expect(stockAfterCancel, 20);
      });

      test('3.6 Empirical Challenge: Idempotency of cancellation (double cancel / replay)', () async {
        const product = Product(
          id: 'p_double_cancel',
          name: 'Phân Kali Muối Ớt',
          code: 'K_MUOI',
          price: 300000,
          costPrice: 200000,
          branchStocks: {'store_001': 50, 'branch_1': 50},
          category: 'Phân kali',
        );
        productRepo.products['p_double_cancel'] = product;

        final receipt = StockInReceipt(
          id: 'rec_double_cancel',
          importCode: 'PN_DBL_CNC',
          date: DateTime(2026, 9, 27),
          storeId: 'store_001',
          items: const [
            StockInReceiptItem(
              transactionId: 'tx_dc1',
              productId: 'p_double_cancel',
              quantity: 10,
              unitPrice: 200000,
            ),
          ],
        );

        final completed = await completeUseCase.execute(receipt);
        expect(productRepo.products['p_double_cancel']!.branchStocks['store_001'], 60);

        // First cancellation: stock 60 -> 50
        await cancelUseCase.execute(
          storeId: 'store_001',
          receipt: completed,
          reason: 'Lần hủy 1',
          cancelledBy: 'user1',
        );
        expect(productRepo.products['p_double_cancel']!.branchStocks['store_001'], 50);

        // Fetch updated receipt from repo which has status 'cancelled'
        final alreadyCancelled = await receiptRepo.getReceiptById(storeId: 'store_001', receiptId: 'rec_double_cancel');
        expect(alreadyCancelled!.isCancelled, isTrue);

        // Second cancellation attempt on already-cancelled receipt:
        // FIXED: CancelStockInReceiptUseCase enforces status guard and throws StateError
        expect(
          () => cancelUseCase.execute(
            storeId: 'store_001',
            receipt: alreadyCancelled,
            reason: 'Lần hủy 2 (Double click/Replay)',
            cancelledBy: 'user1',
          ),
          throwsA(isA<StateError>()),
        );
        final stockAfterDoubleCancel = productRepo.products['p_double_cancel']!.branchStocks['store_001'];
        expect(
          stockAfterDoubleCancel,
          50,
          reason: 'Double cancellation is blocked by status guard, preventing double decrement',
        );
      });

      test('3.7 Empirical Challenge: Calling cancelUseCase on a draft receipt', () async {
        const product = Product(
          id: 'p_draft_cancel',
          name: 'Thuốc Trừ Cỏ Sofit',
          code: 'SOFIT',
          price: 180000,
          costPrice: 140000,
          branchStocks: {'store_001': 30, 'branch_1': 30},
          category: 'Thuốc trừ cỏ',
        );
        productRepo.products['p_draft_cancel'] = product;

        final draftReceipt = StockInReceipt(
          id: 'draft_to_cancel',
          importCode: 'PN_DRAFT_CNC',
          date: DateTime(2026, 9, 27),
          storeId: 'store_001',
          status: 'draft',
          items: const [
            StockInReceiptItem(
              transactionId: 'tx_dc_draft',
              productId: 'p_draft_cancel',
              quantity: 10,
              unitPrice: 140000,
            ),
          ],
        );
        await saveDraftUseCase.execute(draftReceipt);
        expect(productRepo.products['p_draft_cancel']!.branchStocks['store_001'], 30);

        // If someone invokes cancelUseCase on a draft receipt:
        // FIXED: CancelStockInReceiptUseCase enforces draft status guard and throws StateError
        expect(
          () => cancelUseCase.execute(
            storeId: 'store_001',
            receipt: draftReceipt,
            reason: 'Hủy nhầm draft',
            cancelledBy: 'user1',
          ),
          throwsA(isA<StateError>()),
        );
        final stockAfterDraftCancel = productRepo.products['p_draft_cancel']!.branchStocks['store_001'];
        expect(
          stockAfterDraftCancel,
          30,
          reason: 'Draft cancellation is blocked by status guard, preserving stock intact',
        );
      });

      test('3.8 Cancellation reason validation: empty or whitespace reason throws ArgumentError', () async {
        final receipt = StockInReceipt(
          id: 'rec_empty_reason',
          importCode: 'PN_EMP_REASON',
          date: DateTime(2026, 9, 27),
          storeId: 'store_001',
          status: 'completed',
          items: const [],
        );
        expect(
          () => cancelUseCase.execute(
            storeId: 'store_001',
            receipt: receipt,
            reason: '',
            cancelledBy: 'user1',
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => cancelUseCase.execute(
            storeId: 'store_001',
            receipt: receipt,
            reason: '   \n  \t  ',
            cancelledBy: 'user1',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
