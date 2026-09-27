import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/complete_stock_in_receipt_use_case.dart';
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
  int upsertCount = 0;

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Future<void> upsert(Product product) async {
    upsertCount++;
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
  group('CompleteStockInReceiptUseCase Tests', () {
    late MockProductRepository mockProductRepo;
    late MockInventoryRepository mockInventoryRepo;
    late MockSupplierRepository mockSupplierRepo;
    late MockStockInReceiptRepository mockReceiptRepo;
    late CompleteStockInReceiptUseCase useCase;

    setUp(() {
      mockProductRepo = MockProductRepository();
      mockInventoryRepo = MockInventoryRepository();
      mockSupplierRepo = MockSupplierRepository();
      mockReceiptRepo = MockStockInReceiptRepository();

      useCase = CompleteStockInReceiptUseCase(
        productRepository: mockProductRepo,
        inventoryRepository: mockInventoryRepo,
        supplierRepository: mockSupplierRepo,
        receiptRepository: mockReceiptRepo,
      );
    });

    test('Completing receipt increments branch stock and synchronizes branch aliases', () async {
      const initialProduct = Product(
        id: 'prod_001',
        name: 'Gạo ST25',
        code: 'ST25',
        price: 200000,
        costPrice: 100000,
        branchStocks: {
          'store_001': 10,
          'branch_1': 10,
          'store_002': 5,
        },
        category: 'Gạo',
      );
      mockProductRepo.products['prod_001'] = initialProduct;

      final receipt = StockInReceipt(
        id: 'rec_001',
        importCode: 'PN_001',
        date: DateTime(2026, 9, 27),
        storeId: 'store_001',
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'prod_001',
            quantity: 15,
            unitPrice: 120000,
          ),
        ],
      );

      final completed = await useCase.execute(receipt);

      expect(completed.status, 'completed');
      expect(completed.isCompleted, isTrue);

      final updatedProduct = mockProductRepo.products['prod_001']!;
      // Current stock was 10, imported 15 -> 25
      expect(updatedProduct.branchStocks['store_001'], 25);
      // branch_1 alias is synchronized
      expect(updatedProduct.branchStocks['branch_1'], 25);
      // store_002 unchanged
      expect(updatedProduct.branchStocks['store_002'], 5);

      // Weighted average cost:
      // total current stock was 25 (10 store_001 + 10 branch_1 + 5 store_002) with cost 100,000
      // ((25 * 100,000) + (15 * 120,000)) / (25 + 15) = (2,500,000 + 1,800,000) / 40 = 107,500
      expect(updatedProduct.costPrice, 107500.0);

      // Verify inventory transaction was recorded
      expect(mockInventoryRepo.transactions.length, 1);
      final tx = mockInventoryRepo.transactions.first;
      expect(tx.productId, 'prod_001');
      expect(tx.quantity, 15);
      expect(tx.importPrice, 120000.0);
      expect(tx.type, TransactionType.import);
    });

    test('Completing receipt updates supplier debt and totalPurchase when unpaid balance exists', () async {
      const initialSupplier = Supplier(
        id: 'sup_001',
        code: 'NCC01',
        name: 'Công ty Lúa Gạo',
        currentDebt: 5000000,
        totalPurchase: 20000000,
      );
      mockSupplierRepo.suppliers['sup_001'] = initialSupplier;

      final receipt = StockInReceipt(
        id: 'rec_debt_01',
        importCode: 'PN_DEBT_01',
        date: DateTime(2026, 9, 27),
        storeId: 'store_001',
        supplierId: 'sup_001',
        paidAmount: 2000000, // netPayable = 5,000,000 -> unpaidDebt = 3,000,000
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'p_none',
            quantity: 5,
            unitPrice: 1000000, // Total = 5,000,000
          ),
        ],
      );

      final completed = await useCase.execute(receipt);
      expect(completed.isCompleted, isTrue);

      final updatedSupplier = mockSupplierRepo.suppliers['sup_001']!;
      // Total purchase increases by netPayable: 20,000,000 + 5,000,000 = 25,000,000
      expect(updatedSupplier.totalPurchase, 25000000.0);
      // Current debt increases by remainingDebt (5,000,000 - 2,000,000 = 3,000,000): 5,000,000 + 3,000,000 = 8,000,000
      expect(updatedSupplier.currentDebt, 8000000.0);

      // Verify SupplierDebtTransaction was logged
      expect(mockSupplierRepo.debtTransactions.length, 1);
      final debtTx = mockSupplierRepo.debtTransactions.first;
      expect(debtTx.supplierId, 'sup_001');
      expect(debtTx.type, SupplierDebtType.importBill);
      expect(debtTx.amount, 3000000.0);
      expect(debtTx.remainingDebt, 8000000.0);
      expect(debtTx.referenceCode, 'PN_DEBT_01');
    });

    test('Completing receipt without unpaid debt does NOT create debt transaction', () async {
      const initialSupplier = Supplier(
        id: 'sup_002',
        code: 'NCC02',
        name: 'NCC Trả Ngay',
        currentDebt: 0,
        totalPurchase: 10000000,
      );
      mockSupplierRepo.suppliers['sup_002'] = initialSupplier;

      final receipt = StockInReceipt(
        id: 'rec_paid_01',
        importCode: 'PN_PAID_01',
        date: DateTime(2026, 9, 27),
        storeId: 'store_001',
        supplierId: 'sup_002',
        paidAmount: 1000000,
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'p_none',
            quantity: 1,
            unitPrice: 1000000,
          ),
        ],
      );

      await useCase.execute(receipt);

      final updatedSupplier = mockSupplierRepo.suppliers['sup_002']!;
      expect(updatedSupplier.totalPurchase, 11000000.0);
      expect(updatedSupplier.currentDebt, 0.0);
      expect(mockSupplierRepo.debtTransactions, isEmpty);
    });

    test('Duplicate product line items in receipt accumulate quantities and compute weighted average cost', () async {
      const initialProduct = Product(
        id: 'prod_dup_complete',
        name: 'Phân Kali Clorua',
        code: 'KCL02',
        price: 250000,
        costPrice: 100000,
        branchStocks: {'store_001': 20, 'branch_1': 20},
        category: 'Phân bón',
      );
      mockProductRepo.products['prod_dup_complete'] = initialProduct;

      final receipt = StockInReceipt(
        id: 'rec_dup_complete',
        importCode: 'PN_DUP_CMP',
        date: DateTime(2026, 9, 27),
        storeId: 'store_001',
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_dc_1',
            productId: 'prod_dup_complete',
            quantity: 10,
            unitPrice: 100000,
          ),
          StockInReceiptItem(
            transactionId: 'tx_dc_2',
            productId: 'prod_dup_complete',
            quantity: 10,
            unitPrice: 160000,
          ),
        ],
      );

      final completed = await useCase.execute(receipt);
      expect(completed.isCompleted, isTrue);

      final updatedProduct = mockProductRepo.products['prod_dup_complete']!;
      // Accumulated stock: 20 initial + 10 + 10 = 40
      expect(updatedProduct.branchStocks['store_001'], 40);
      expect(updatedProduct.branchStocks['branch_1'], 40);

      // Weighted average cost:
      // (40 initial total stock * 100,000 + 1,000,000 + 1,600,000) / 60 total stock = 110,000
      expect(updatedProduct.costPrice, 110000.0);

      // Both line items recorded separate transactions
      expect(mockInventoryRepo.transactions.length, 2);
    });
  });
}
