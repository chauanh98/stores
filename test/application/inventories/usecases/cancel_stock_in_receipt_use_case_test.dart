import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/cancel_stock_in_receipt_use_case.dart';
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

class MockProductRepository implements ProductRepository {
  final Map<String, Product> products = {};

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

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
    final p = products[id];
    if (p != null) {
      products[id] = p.copyWith(branchStocks: {'store_001': newStock});
    }
  }

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());

  Stream<Product?> watchById(String id) => Stream.value(products[id]);
}

class MockInventoryRepository implements InventoryRepository {
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

class MockSupplierRepository implements SupplierRepository {
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

class MockStockInReceiptRepository implements StockInReceiptRepository {
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

void main() {
  group('CancelStockInReceiptUseCase Tests', () {
    late MockProductRepository mockProductRepo;
    late MockInventoryRepository mockInventoryRepo;
    late MockSupplierRepository mockSupplierRepo;
    late MockStockInReceiptRepository mockReceiptRepo;
    late CancelStockInReceiptUseCase useCase;

    setUp(() {
      mockProductRepo = MockProductRepository();
      mockInventoryRepo = MockInventoryRepository();
      mockSupplierRepo = MockSupplierRepository();
      mockReceiptRepo = MockStockInReceiptRepository();

      useCase = CancelStockInReceiptUseCase(
        productRepository: mockProductRepo,
        inventoryRepository: mockInventoryRepo,
        supplierRepository: mockSupplierRepo,
        receiptRepository: mockReceiptRepo,
      );
    });

    test('Cancelling receipt rolls back branch stock and synchronizes branch aliases', () async {
      const initialProduct = Product(
        id: 'prod_cancel_1',
        name: 'Phân Bón NPK',
        code: 'NPK01',
        price: 300000,
        costPrice: 200000,
        branchStocks: {
          'store_001': 25,
          'branch_1': 25,
          'store_002': 10,
        },
        category: 'Phân bón',
      );
      mockProductRepo.products['prod_cancel_1'] = initialProduct;

      final receipt = StockInReceipt(
        id: 'rec_to_cancel',
        importCode: 'PN_CANCEL_01',
        date: DateTime(2026, 9, 27),
        storeId: 'store_001',
        status: 'completed',
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_c1',
            productId: 'prod_cancel_1',
            quantity: 10, // Rollback 10 items
            unitPrice: 200000,
          ),
        ],
      );
      mockReceiptRepo.receipts['rec_to_cancel'] = receipt;

      await useCase.execute(
        storeId: 'store_001',
        receipt: receipt,
        reason: 'Hàng lỗi từ nhà sản xuất',
        cancelledBy: 'supervisor_hieu',
      );

      // Verify stock was reduced by 10 (25 - 10 = 15)
      final rolledBackProduct = mockProductRepo.products['prod_cancel_1']!;
      expect(rolledBackProduct.branchStocks['store_001'], 15);
      expect(rolledBackProduct.branchStocks['branch_1'], 15);
      expect(rolledBackProduct.branchStocks['store_002'], 10);

      // Verify receipt status in repository
      final updatedReceipt = mockReceiptRepo.receipts['rec_to_cancel']!;
      expect(updatedReceipt.status, 'cancelled');
      expect(updatedReceipt.isCancelled, isTrue);
      expect(updatedReceipt.isCompleted, isFalse);
      expect(updatedReceipt.cancelReason, 'Hàng lỗi từ nhà sản xuất');
      expect(updatedReceipt.cancelledBy, 'supervisor_hieu');

      // Verify reversal inventory transaction was recorded
      expect(mockInventoryRepo.transactions.length, 1);
      final revTx = mockInventoryRepo.transactions.first;
      expect(revTx.type, TransactionType.export);
      expect(revTx.quantity, 10);
      expect(revTx.note.contains('Hàng lỗi từ nhà sản xuất'), isTrue);
    });

    test('Cancelling receipt rolls back supplier debt and totalPurchase, and records reversal debt transaction', () async {
      const initialSupplier = Supplier(
        id: 'sup_cancel_1',
        code: 'NCC_CANCEL',
        name: 'Công ty Ánh Dương',
        currentDebt: 8000000,
        totalPurchase: 25000000,
      );
      mockSupplierRepo.suppliers['sup_cancel_1'] = initialSupplier;

      final receipt = StockInReceipt(
        id: 'rec_debt_cancel',
        importCode: 'PN_DEBT_REV',
        date: DateTime(2026, 9, 27),
        storeId: 'store_001',
        supplierId: 'sup_cancel_1',
        status: 'completed',
        paidAmount: 2000000, // Total = 5,000,000, remainingDebt = 3,000,000
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'p_none',
            quantity: 5,
            unitPrice: 1000000,
          ),
        ],
      );
      mockReceiptRepo.receipts['rec_debt_cancel'] = receipt;

      await useCase.execute(
        storeId: 'store_001',
        receipt: receipt,
        reason: 'Hủy đơn do sai thỏa thuận giá',
        cancelledBy: 'admin',
      );

      final updatedSupplier = mockSupplierRepo.suppliers['sup_cancel_1']!;
      // Total purchase rolls back by netPayable (5,000,000): 25,000,000 - 5,000,000 = 20,000,000
      expect(updatedSupplier.totalPurchase, 20000000.0);
      // Current debt rolls back by remainingDebt (3,000,000): 8,000,000 - 3,000,000 = 5,000,000
      expect(updatedSupplier.currentDebt, 5000000.0);

      // Verify reversal debt transaction
      expect(mockSupplierRepo.debtTransactions.length, 1);
      final debtRev = mockSupplierRepo.debtTransactions.first;
      expect(debtRev.supplierId, 'sup_cancel_1');
      expect(debtRev.type, SupplierDebtType.adjustment);
      expect(debtRev.amount, -3000000.0);
      expect(debtRev.remainingDebt, 5000000.0);
      expect(debtRev.referenceCode, 'PN_DEBT_REV');
      expect(debtRev.note?.contains('Hủy đơn do sai thỏa thuận giá'), isTrue);
    });

    test('Clamps rolled-back stock and debt to zero without going negative', () async {
      const productWithLowStock = Product(
        id: 'prod_low',
        name: 'Sản phẩm tồn thấp',
        code: 'LOW01',
        price: 100000,
        costPrice: 50000,
        branchStocks: {'store_001': 3},
        category: 'Hàng hóa',
      );
      mockProductRepo.products['prod_low'] = productWithLowStock;

      const supplierWithLowDebt = Supplier(
        id: 'sup_low',
        code: 'SUP_LOW',
        name: 'NCC Dư nợ thấp',
        currentDebt: 1000000,
        totalPurchase: 1000000,
      );
      mockSupplierRepo.suppliers['sup_low'] = supplierWithLowDebt;

      final receipt = StockInReceipt(
        id: 'rec_overflow',
        importCode: 'PN_OVERFLOW',
        date: DateTime(2026, 9, 27),
        storeId: 'store_001',
        supplierId: 'sup_low',
        paidAmount: 0, // remainingDebt = 4,000,000 > currentDebt (1,000,000)
        items: const [
          StockInReceiptItem(
            transactionId: 't_ov',
            productId: 'prod_low',
            quantity: 10, // 10 > currentStock 3
            unitPrice: 400000,
          ),
        ],
      );

      await useCase.execute(
        storeId: 'store_001',
        receipt: receipt,
        reason: 'Hủy phiếu nhập kiểm tra biên',
        cancelledBy: 'admin',
      );

      final p = mockProductRepo.products['prod_low']!;
      expect(p.branchStocks['store_001'], 0); // Clamped at 0

      final s = mockSupplierRepo.suppliers['sup_low']!;
      expect(s.currentDebt, 0.0); // Clamped at 0
      expect(s.totalPurchase, 0.0); // Clamped at 0
    });

    test('Throws ArgumentError when reason is empty or whitespace only', () async {
      final receipt = StockInReceipt(
        id: 'rec_invalid_reason',
        importCode: 'PN_INV_REASON',
        date: DateTime(2026, 9, 27),
        storeId: 'store_001',
        status: 'completed',
        items: const [],
      );

      expect(
        () => useCase.execute(
          storeId: 'store_001',
          receipt: receipt,
          reason: '',
          cancelledBy: 'admin',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => useCase.execute(
          storeId: 'store_001',
          receipt: receipt,
          reason: '   \t  \n  ',
          cancelledBy: 'admin',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Throws StateError when attempting to cancel an already cancelled receipt', () async {
      final cancelledReceipt = StockInReceipt(
        id: 'rec_already_cancelled',
        importCode: 'PN_ALREADY_CANCELLED',
        date: DateTime(2026, 9, 27),
        storeId: 'store_001',
        status: 'cancelled',
        items: const [],
      );

      expect(
        () => useCase.execute(
          storeId: 'store_001',
          receipt: cancelledReceipt,
          reason: 'Hủy lần nữa',
          cancelledBy: 'admin',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Throws StateError when attempting to cancel a draft receipt', () async {
      final draftReceipt = StockInReceipt(
        id: 'rec_draft',
        importCode: 'PN_DRAFT',
        date: DateTime(2026, 9, 27),
        storeId: 'store_001',
        status: 'draft',
        items: const [],
      );

      expect(
        () => useCase.execute(
          storeId: 'store_001',
          receipt: draftReceipt,
          reason: 'Hủy phiếu tạm',
          cancelledBy: 'admin',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Duplicate product line items in receipt accumulate quantities correctly during rollback', () async {
      const product = Product(
        id: 'prod_dup_rollback',
        name: 'Phân Bón Hỗn Hợp',
        code: 'HH01',
        price: 200000,
        costPrice: 150000,
        branchStocks: {'store_001': 50, 'branch_1': 50},
        category: 'Phân bón',
      );
      mockProductRepo.products['prod_dup_rollback'] = product;

      final receipt = StockInReceipt(
        id: 'rec_dup_rollback',
        importCode: 'PN_DUP_RB',
        date: DateTime(2026, 9, 27),
        storeId: 'store_001',
        status: 'completed',
        items: const [
          StockInReceiptItem(
            transactionId: 't_dup_1',
            productId: 'prod_dup_rollback',
            quantity: 12,
            unitPrice: 150000,
          ),
          StockInReceiptItem(
            transactionId: 't_dup_2',
            productId: 'prod_dup_rollback',
            quantity: 8,
            unitPrice: 150000,
          ),
        ],
      );

      await useCase.execute(
        storeId: 'store_001',
        receipt: receipt,
        reason: 'Hủy đơn hàng có dòng trùng',
        cancelledBy: 'admin',
      );

      // Rollback deduction should be 12 + 8 = 20 -> 50 - 20 = 30
      final updatedProduct = mockProductRepo.products['prod_dup_rollback']!;
      expect(updatedProduct.branchStocks['store_001'], 30);
      expect(updatedProduct.branchStocks['branch_1'], 30);

      // 2 reversal inventory transactions recorded
      expect(mockInventoryRepo.transactions.length, 2);
    });
  });
}
