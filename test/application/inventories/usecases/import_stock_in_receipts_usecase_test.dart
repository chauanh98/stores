import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/import_stock_in_receipts_usecase.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

class _FakeProductRepo implements ProductRepository {
  final Map<String, Product> products = {};

  _FakeProductRepo([List<Product> initial = const []]) {
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

class _FakeInventoryRepo implements InventoryRepository {
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

class _FakeSupplierRepo implements SupplierRepository {
  final Map<String, Supplier> suppliers = {};
  final List<SupplierDebtTransaction> debtTransactions = [];

  _FakeSupplierRepo([List<Supplier> initial = const []]) {
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

class _FakeSupplierDebtRepo implements SupplierDebtTransactionRepository {
  final List<SupplierDebtTransaction> recorded = [];

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction transaction,
      {String? storeId}) async {
    recorded.add(transaction);
  }
}

void main() {
  group('ImportResult Unit Tests', () {
    test('default constructor initializes correctly and computes isSuccess', () {
      const result = ImportResult();
      expect(result.totalReceipts, 0);
      expect(result.importedReceipts, 0);
      expect(result.updatedProductsCount, 0);
      expect(result.updatedSuppliersCount, 0);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
      expect(result.isSuccess, isTrue);
      expect(result.hasErrors, isFalse);
      expect(result.hasWarnings, isFalse);
    });

    test('compatibility aliases and summary string', () {
      const result = ImportResult(
        totalReceipts: 5,
        importedReceipts: 4,
        updatedProductsCount: 8,
        updatedSuppliersCount: 2,
        errors: ['Lỗi 1'],
        warnings: ['Cảnh báo 1'],
      );

      expect(result.total, 5);
      expect(result.added, 4);
      expect(result.updated, 8);
      expect(result.skipped, 1);
      expect(result.errorCount, 1);
      expect(result.errorMessages, ['Lỗi 1']);
      expect(result.isSuccess, isFalse);
      expect(result.hasErrors, isTrue);
      expect(result.hasWarnings, isTrue);
      expect(result.toSummaryString(), contains('Tổng số phiếu: 5'));
      expect(result.toSummaryString(), contains('Lỗi: 1'));
      expect(result.toSummaryString(), contains('Cảnh báo: 1'));
    });

    test('equality and copyWith work correctly', () {
      const r1 = ImportResult(totalReceipts: 2, importedReceipts: 2);
      final r2 = r1.copyWith(totalReceipts: 3);

      expect(r1 == r2, isFalse);
      expect(r2.totalReceipts, 3);
      expect(r2.importedReceipts, 2);

      const r3 = ImportResult(totalReceipts: 2, importedReceipts: 2);
      expect(r1 == r3, isTrue);
      expect(r1.hashCode == r3.hashCode, isTrue);
    });
  });

  group('ImportStockInReceiptsUseCase Logic Tests', () {
    late _FakeProductRepo fakeProductRepo;
    late _FakeInventoryRepo fakeInventoryRepo;
    late _FakeSupplierRepo fakeSupplierRepo;
    late ImportStockInReceiptsUseCase useCase;

    setUp(() {
      fakeProductRepo = _FakeProductRepo([
        const Product(
          id: 'prod_001',
          name: 'Nước xả vải Downy',
          code: 'XD15',
          barcode: '8930001',
          price: 90000,
          costPrice: 50000,
          branchStocks: {'store_001': 10, 'store_002': 5},
          category: 'Chăm sóc nhà cửa',
        ),
        const Product(
          id: 'prod_002',
          name: 'Bia Heineken lon 330ml',
          code: 'HEIN330',
          barcode: '8930002',
          price: 22000,
          costPrice: 15000,
          branchStocks: {'store_001': 0, 'store_002': 0},
          category: 'Đồ uống',
        ),
      ]);

      fakeInventoryRepo = _FakeInventoryRepo();
      fakeSupplierRepo = _FakeSupplierRepo([
        const Supplier(
          id: 'sup_001',
          code: 'NCC000050',
          name: 'Shopee Cần Thơ',
          currentDebt: 1000000,
          totalPurchase: 5000000,
        ),
      ]);

      useCase = ImportStockInReceiptsUseCase(
        productRepository: fakeProductRepo,
        inventoryRepository: fakeInventoryRepo,
        supplierRepository: fakeSupplierRepo,
      );
    });

    test('returns empty result when receipts list is empty', () async {
      final result = await useCase.execute(
        receipts: [],
        storeId: 'store_001',
        performedBy: 'Admin',
      );

      expect(result.totalReceipts, 0);
      expect(result.importedReceipts, 0);
      expect(result.isSuccess, isTrue);
    });

    test('updates branch stock and computes weighted average cost accurately', () async {
      // prod_001 initially has:
      // total stock = 15 (store_001: 10, store_002: 5)
      // costPrice = 50,000
      // We import 10 units at 70,000 into store_002:
      // newCost = (15 * 50,000 + 10 * 70,000) / (15 + 10) = (750,000 + 700,000) / 25 = 1,450,000 / 25 = 58,000
      // new stock in store_002 = 5 + 10 = 15
      final receipt = StockInReceipt(
        id: 'PN001737',
        importCode: 'PN001737',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_item_1',
            productId: 'XD15', // Matches code XD15
            quantity: 10,
            unitPrice: 70000,
          ),
        ],
      );

      final result = await useCase.execute(
        receipts: [receipt],
        storeId: 'store_001',
        performedBy: 'Khánh Đăng',
      );

      expect(result.isSuccess, isTrue);
      expect(result.importedReceipts, 1);
      expect(result.updatedProductsCount, 1);

      final updatedProd = await fakeProductRepo.fetchById('prod_001');
      expect(updatedProd, isNotNull);
      expect(updatedProd!.branchStocks['store_002'], 15);
      expect(updatedProd.branchStocks['store_001'], 10);
      expect(updatedProd.costPrice, 58000);

      // Verify InventoryTransaction recorded
      expect(fakeInventoryRepo.transactions.length, 1);
      final tx = fakeInventoryRepo.transactions.first;
      expect(tx.productId, 'prod_001');
      expect(tx.type, TransactionType.import);
      expect(tx.quantity, 10);
      expect(tx.importPrice, 70000);
      expect(tx.storeId, 'store_002');
      expect(tx.createdBy, 'Khánh Đăng');
      expect(tx.note, 'Nhập hàng từ Excel: PN001737');
    });

    test('handles zero initial stock: newCost becomes import unit price', () async {
      // prod_002 initially has stock 0
      final receipt = StockInReceipt(
        id: 'PN001738',
        importCode: 'PN001738',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_item_2',
            productId: 'HEIN330',
            quantity: 24,
            unitPrice: 18000,
          ),
        ],
      );

      final result = await useCase.execute(
        receipts: [receipt],
        storeId: 'store_002',
        performedBy: 'Staff',
      );

      expect(result.isSuccess, isTrue);
      final updatedProd = await fakeProductRepo.fetchById('prod_002');
      expect(updatedProd!.branchStocks['store_002'], 24);
      expect(updatedProd.costPrice, 18000);
    });

    test('synchronizes supplier debt and total purchase when unpaid debt exists', () async {
      // sup_001: currentDebt 1,000,000, totalPurchase 5,000,000
      // Receipt has netPayable = 2,500,000, paidAmount = 500,000
      // unpaid = 2,000,000
      // newDebt = 3,000,000, newTotalPurchase = 7,500,000
      final receipt = StockInReceipt(
        id: 'PN001739',
        importCode: 'PN001739',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        supplierId: 'NCC000050',
        supplierName: 'Shopee Cần Thơ',
        totalAmount: 2500000,
        paidAmount: 500000,
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_item_3',
            productId: 'XD15',
            quantity: 5,
            unitPrice: 500000,
          ),
        ],
      );

      final result = await useCase.execute(
        receipts: [receipt],
        storeId: 'store_002',
        performedBy: 'Manager',
      );

      expect(result.isSuccess, isTrue);
      expect(result.updatedSuppliersCount, 1);

      final updatedSupplier = await fakeSupplierRepo.fetchById('sup_001');
      expect(updatedSupplier, isNotNull);
      expect(updatedSupplier!.currentDebt, 3000000);
      expect(updatedSupplier.totalPurchase, 7500000);

      // Verify SupplierDebtTransaction recorded
      expect(fakeSupplierRepo.debtTransactions.length, 1);
      final debtTx = fakeSupplierRepo.debtTransactions.first;
      expect(debtTx.supplierId, 'sup_001');
      expect(debtTx.type, SupplierDebtType.importBill);
      expect(debtTx.amount, 2000000);
      expect(debtTx.remainingDebt, 3000000);
      expect(debtTx.referenceCode, 'PN001739');
      expect(debtTx.createdBy, 'Manager');
    });

    test(
        'synchronizes supplier totalPurchase and preserves currentDebt when receipt is fully paid',
        () async {
      // sup_001 initially has currentDebt 1,000,000 and totalPurchase 5,000,000
      // Paid in full: netPayable 1,000,000, paidAmount 1,000,000
      final receipt = StockInReceipt(
        id: 'PN001740',
        importCode: 'PN001740',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        supplierId: 'NCC000050',
        totalAmount: 1000000,
        paidAmount: 1000000,
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_item_4',
            productId: 'XD15',
            quantity: 2,
            unitPrice: 500000,
          ),
        ],
      );

      final result = await useCase.execute(
        receipts: [receipt],
        storeId: 'store_002',
        performedBy: 'Staff',
      );

      expect(result.isSuccess, isTrue);
      expect(result.updatedSuppliersCount, 1);
      final supplier = await fakeSupplierRepo.fetchById('sup_001');
      expect(supplier, isNotNull);
      // supplier.totalPurchase increases by netPayable (5,000,000 + 1,000,000 = 6,000,000)
      expect(supplier!.totalPurchase, 6000000);
      // supplier.currentDebt remains unchanged
      expect(supplier.currentDebt, 1000000);
      // No debt transaction is recorded
      expect(fakeSupplierRepo.debtTransactions, isEmpty);
    });

    test(
        'handles overpaid receipts: increases totalPurchase, preserves currentDebt, no debt transaction',
        () async {
      // sup_001: currentDebt 1,000,000, totalPurchase 5,000,000
      // Overpaid: netPayable = 800,000, paidAmount = 1,000,000
      final receipt = StockInReceipt(
        id: 'PN001740_OVERPAID',
        importCode: 'PN001740_OVERPAID',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        supplierId: 'NCC000050',
        totalAmount: 800000,
        paidAmount: 1000000,
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_item_overpaid',
            productId: 'XD15',
            quantity: 1,
            unitPrice: 800000,
          ),
        ],
      );

      final result = await useCase.execute(
        receipts: [receipt],
        storeId: 'store_002',
        performedBy: 'Staff',
      );

      expect(result.isSuccess, isTrue);
      expect(result.updatedSuppliersCount, 1);
      final supplier = await fakeSupplierRepo.fetchById('sup_001');
      expect(supplier, isNotNull);
      // totalPurchase increases by netPayable (5,000,000 + 800,000 = 5,800,000)
      expect(supplier!.totalPurchase, 5800000);
      // currentDebt remains unchanged
      expect(supplier.currentDebt, 1000000);
      // No debt transaction recorded
      expect(fakeSupplierRepo.debtTransactions, isEmpty);
    });

    test('supports dedicated SupplierDebtTransactionRepository injection', () async {
      final fakeDebtRepo = _FakeSupplierDebtRepo();
      final useCaseWithDebtRepo = ImportStockInReceiptsUseCase(
        productRepo: fakeProductRepo,
        inventoryRepo: fakeInventoryRepo,
        supplierRepo: fakeSupplierRepo,
        supplierDebtRepo: fakeDebtRepo,
      );

      final receipt = StockInReceipt(
        id: 'PN001741',
        importCode: 'PN001741',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        supplierId: 'NCC000050',
        totalAmount: 1000000,
        paidAmount: 0,
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_item_5',
            productId: 'XD15',
            quantity: 2,
            unitPrice: 500000,
          ),
        ],
      );

      final result = await useCaseWithDebtRepo.execute(
        receipts: [receipt],
        storeId: 'store_002',
        performedBy: 'Admin',
      );

      expect(result.isSuccess, isTrue);
      expect(fakeDebtRepo.recorded.length, 1);
      expect(fakeDebtRepo.recorded.first.amount, 1000000);
      expect(fakeDebtRepo.recorded.first.remainingDebt, 2000000);
    });

    test('records warning and continues gracefully if product or supplier is not found', () async {
      final receipt = StockInReceipt(
        id: 'PN001742',
        importCode: 'PN001742',
        date: DateTime(2026, 9, 21),
        storeId: 'store_002',
        supplierId: 'UNKNOWN_SUPPLIER',
        totalAmount: 100000,
        paidAmount: 0,
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_item_6',
            productId: 'UNKNOWN_SKU',
            quantity: 1,
            unitPrice: 100000,
          ),
        ],
      );

      final result = await useCase.execute(
        receipts: [receipt],
        storeId: 'store_002',
        performedBy: 'Admin',
      );

      expect(result.isSuccess, isTrue); // No fatal errors
      expect(result.warnings.length, 2);
      expect(result.warnings[0], contains('UNKNOWN_SKU'));
      expect(result.warnings[1], contains('UNKNOWN_SUPPLIER'));

      // Inventory transaction is still safely recorded
      expect(fakeInventoryRepo.transactions.length, 1);
      expect(fakeInventoryRepo.transactions.first.productId, 'UNKNOWN_SKU');
    });

    test('branch storeId fallback logic: uses storeId argument if receipt storeId is store_001 or empty', () async {
      final receipt = StockInReceipt(
        id: 'PN001743',
        importCode: 'PN001743',
        date: DateTime(2026, 9, 21),
        storeId: 'store_001', // Should fallback to storeId argument
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_item_7',
            productId: 'XD15',
            quantity: 3,
            unitPrice: 70000,
          ),
        ],
      );

      final result = await useCase.execute(
        receipts: [receipt],
        storeId: 'store_002',
        performedBy: 'Admin',
      );

      expect(result.isSuccess, isTrue);
      final prod = await fakeProductRepo.fetchById('prod_001');
      // Updated in store_002
      expect(prod!.branchStocks['store_002'], 8);
    });

    test('Riverpod Provider correctly instantiates usecase', () {
      final container = ProviderContainer(
        overrides: [
          productRepositoryProvider.overrideWithValue(fakeProductRepo),
          inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
          supplierRepositoryProvider.overrideWithValue(fakeSupplierRepo),
        ],
      );
      addTearDown(container.dispose);

      final uc = container.read(importStockInReceiptsUseCaseProvider);
      expect(uc, isA<ImportStockInReceiptsUseCase>());
      expect(uc.productRepository, fakeProductRepo);
      expect(uc.inventoryRepository, fakeInventoryRepo);
      expect(uc.supplierRepository, fakeSupplierRepo);
    });
  });
}
