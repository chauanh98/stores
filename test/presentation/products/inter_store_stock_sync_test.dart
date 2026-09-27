import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/complete_stock_in_receipt_use_case.dart';
import 'package:stores/application/inventory/inter_store_transfer_service.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/data/repositories/product_repository_impl.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/stock_in_receipt_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

import '../../support/firebase_test_harness.dart';

class _FakeInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async {
    transactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value([]);

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime start, DateTime end) =>
      Stream.value([]);
}

class _FakeSupplierRepository implements SupplierRepository {
  final Map<String, Supplier> suppliers = {};

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
  Future<void> recordDebtTransaction(SupplierDebtTransaction tx,
      {String? storeId}) async {}

  @override
  Future<List<SupplierDebtTransaction>> fetchDebtTransactions(String supplierId,
          {String? storeId}) async =>
      [];

  @override
  Stream<List<Supplier>> watchAll({String? storeId}) =>
      Stream.value(suppliers.values.toList());

  @override
  Stream<List<SupplierDebtTransaction>> watchDebtTransactions(String supplierId,
          {String? storeId}) =>
      Stream.value([]);
}

class _FakeStockInReceiptRepository implements StockInReceiptRepository {
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
  Future<void> deleteDraft(
      {required String storeId, required String receiptId}) async {
    receipts.remove(receiptId);
  }

  @override
  Future<void> deleteReceipt(
      {required String storeId, required String receiptId}) async {
    receipts.remove(receiptId);
  }

  @override
  Future<double?> getLatestImportPrice(
      {required String storeId, required String productId}) async =>
      null;

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
  Future<StockInReceipt?> getReceiptById(
          {required String storeId, required String receiptId}) async =>
      receipts[receiptId];

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
  }
}

void main() {
  late MockFirebaseDatabase mockDb;

  setUp(() {
    mockDb = MockFirebaseDatabase();
    ProductRemoteDataSource.resetAutoHealedForTesting();
  });

  group('SP000775 Inter-Store Stock Synchronization & Auto-Healing Test', () {
    test(
        '1. Product creation at Thới Bình (store_002) with 100 stock replicates to Đông Thắng (store_001)',
        () async {
      final ds002 = ProductRemoteDataSource(mockDb, 'store_002');
      final repo002 = ProductRepositoryImpl(ds002);

      const product = Product(
        id: 'SP000775',
        name: 'Sản phẩm SP000775',
        code: 'SP000775',
        category: 'Hàng hóa',
        price: 20000,
        costPrice: 15000,
        branchStocks: {'store_002': 100, 'store_001': 0},
      );

      await repo002.upsert(product);

      // Verify stored in store_002
      final snap002 =
          await mockDb.ref('stores/store_002/products').child('SP000775').get();
      expect(snap002.exists, true);
      final data002 = Map<dynamic, dynamic>.from(snap002.value as Map);
      expect(data002['branchStocks']['store_002'], 100);

      // Verify automatically replicated to store_001
      final snap001 =
          await mockDb.ref('stores/store_001/products').child('SP000775').get();
      expect(snap001.exists, true);
      final data001 = Map<dynamic, dynamic>.from(snap001.value as Map);
      expect(data001['branchStocks']['store_002'], 100);
      expect(data001['branchStocks']['store_001'], 0);
    });

    test(
        '2. Complete stock-in receipt of 7 items at Thới Bình updates branchStocks to 107 across all stores',
        () async {
      // Seed product SP000775 in both stores
      final initialProductData = {
        'id': 'SP000775',
        'name': 'Sản phẩm SP000775',
        'code': 'SP000775',
        'category': 'Hàng hóa',
        'price': 20000,
        'costPrice': 15000,
        'branchStocks': {
          'store_001': 0,
          'store_002': 100,
          'branch_1': 0,
          'branch_2': 100
        },
      };
      mockDb.seedData(
          'stores/store_001/products', {'SP000775': initialProductData});
      mockDb.seedData(
          'stores/store_002/products', {'SP000775': initialProductData});

      final ds002 = ProductRemoteDataSource(mockDb, 'store_002');
      final repo002 = ProductRepositoryImpl(ds002);

      final receipt = StockInReceipt(
        id: 'receipt_001',
        importCode: 'PN0001',
        date: DateTime.now(),
        storeId: 'store_002',
        totalAmount: 105000,
        paidAmount: 105000,
        status: 'completed',
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_01',
            productId: 'SP000775',
            productName: 'Sản phẩm SP000775',
            quantity: 7,
            unitPrice: 15000,
          ),
        ],
      );

      final completeUseCase = CompleteStockInReceiptUseCase(
        db: mockDb,
        receiptRepository: _FakeStockInReceiptRepository(),
        productRepository: repo002,
        inventoryRepository: _FakeInventoryRepository(),
        supplierRepository: _FakeSupplierRepository(),
      );

      await completeUseCase.execute(receipt);

      // Verify atomic updates updated both store nodes in updates map
      final updateCalls = mockDb.recorder.callsFor('update');
      expect(updateCalls.length, 1);
      final updateMap = updateCalls.first.value as Map<String, dynamic>;

      const s002Key = 'stores/store_002/products/SP000775/branchStocks';
      const s001Key = 'stores/store_001/products/SP000775/branchStocks';
      expect(updateMap.containsKey(s002Key), true);
      expect(updateMap.containsKey(s001Key), true);

      final stocks002 = updateMap[s002Key] as Map<String, int>;
      final stocks001 = updateMap[s001Key] as Map<String, int>;
      expect(stocks002['store_002'], 107);
      expect(stocks001['store_002'], 107);
    });

    test(
        '3. Transfer 7 items from Thới Bình (store_002) to Đông Thắng (store_001) leaves 100 at store_002, 7 at store_001, synchronized on BOTH stores',
        () async {
      final transferService = InterStoreTransferService(mockDb);

      const productBeforeTransfer = Product(
        id: 'SP000775',
        name: 'Sản phẩm SP000775',
        code: 'SP000775',
        category: 'Hàng hóa',
        price: 20000,
        costPrice: 15000,
        branchStocks: {
          'store_001': 0,
          'store_002': 107,
          'branch_1': 0,
          'branch_2': 107
        },
      );

      // Seed target store existing state
      mockDb.seedData('stores/store_001/products/SP000775', {
        'id': 'SP000775',
        'name': 'Sản phẩm SP000775',
        'code': 'SP000775',
        'category': 'Hàng hóa',
        'price': 20000,
        'costPrice': 15000,
        'branchStocks': {
          'store_001': 0,
          'store_002': 107,
          'branch_1': 0,
          'branch_2': 107
        },
      });

      final result = await transferService.transferProduct(
        sourceStoreId: 'store_002',
        targetStoreId: 'store_001',
        product: productBeforeTransfer,
        quantity: 7,
        sourceStoreName: 'Chi nhánh Thới Bình',
        targetStoreName: 'Chi nhánh Đông Thắng',
      );

      expect(result, isNull);

      final updateCalls = mockDb.recorder.callsFor('update');
      expect(updateCalls.length, 1);
      final updateData = updateCalls.first.value as Map<String, dynamic>;

      // Check source store product branch stock: 107 - 7 = 100 at TB, 7 at ĐT
      const sourceKey = 'stores/store_002/products/SP000775/branchStocks';
      expect(updateData.containsKey(sourceKey), true);
      final sourceStocks = updateData[sourceKey] as Map<String, int>;
      expect(sourceStocks['store_002'], 100);
      expect(sourceStocks['store_001'], 7);

      // Check target store product branch stock: 100 at TB, 7 at ĐT
      const targetKey = 'stores/store_001/products/SP000775/branchStocks';
      expect(updateData.containsKey(targetKey), true);
      final targetStocks = updateData[targetKey] as Map<String, int>;
      expect(targetStocks['store_002'], 100);
      expect(targetStocks['store_001'], 7);
    });

    test(
        '4. Auto-healing heals legacy split-brain products (SP000775 with store_002:100 on store_002, and store_001:7 on store_001)',
        () async {
      // Simulate exact split-brain bug state in Firebase
      mockDb.seedData('stores/store_002/products', {
        'SP000775': {
          'id': 'SP000775',
          'name': 'Sản phẩm SP000775',
          'code': 'SP000775',
          'branchStocks': {'store_002': 100, 'store_001': 0},
        }
      });
      mockDb.seedData('stores/store_001/products', {
        'SP000775': {
          'id': 'SP000775',
          'name': 'Sản phẩm SP000775',
          'code': 'SP000775',
          'branchStocks': {'store_001': 7, 'store_002': 0},
        }
      });

      // Run auto-heal
      await ProductRemoteDataSource.autoHealSplitBranchStocks(mockDb, force: true);

      final updateCalls = mockDb.recorder.callsFor('update');
      expect(updateCalls.isNotEmpty, true);
      final updates = updateCalls.first.value as Map<String, dynamic>;

      // Both stores must be updated to have store_001: 7 and store_002: 100!
      expect(
          updates.containsKey('stores/store_001/products/SP000775/branchStocks'),
          true);
      expect(
          updates.containsKey('stores/store_002/products/SP000775/branchStocks'),
          true);

      final healed001 = updates['stores/store_001/products/SP000775/branchStocks']
          as Map<String, dynamic>;
      final healed002 = updates['stores/store_002/products/SP000775/branchStocks']
          as Map<String, dynamic>;

      expect(healed001['store_001'], 7);
      expect(healed001['store_002'], 100);

      expect(healed002['store_001'], 7);
      expect(healed002['store_002'], 100);
    });

    test(
        '5. ProductModel.fromMap resolves branch_1 to store_001 and branch_2 to store_002 consistently regardless of sourceStoreId',
        () {
      final map = {
        'id': 'P1',
        'name': 'Product 1',
        'branchStocks': {'branch_1': 10, 'branch_2': 25},
      };

      final modelFrom002 = ProductModel.fromMap(map, 'store_002');
      expect(modelFrom002.branchStocks['store_001'], 10);
      expect(modelFrom002.branchStocks['store_002'], 25);

      final modelFrom001 = ProductModel.fromMap(map, 'store_001');
      expect(modelFrom001.branchStocks['store_001'], 10);
      expect(modelFrom001.branchStocks['store_002'], 25);
    });

    test(
        '6. ProductModel.fromMap canonicalizes alias keys and produces exact aggregate stock',
        () {
      final map = {
        'id': 'P1',
        'name': 'Product 1',
        'code': 'P1',
        'category': 'Hàng hóa',
        'price': 10000,
        'costPrice': 5000,
        'branchStocks': {
          'store_001': 7,
          'branch_1': 7,
          'store_002': 100,
          'branch_2': 100,
        },
      };

      final product = ProductModel.fromMap(map).toEntity();
      expect(product.branchStocks.containsKey('branch_1'), false);
      expect(product.branchStocks.containsKey('branch_2'), false);
      expect(product.branchStocks['store_001'], 7);
      expect(product.branchStocks['store_002'], 100);
      expect(product.stock, 107);
    });
  });
}
