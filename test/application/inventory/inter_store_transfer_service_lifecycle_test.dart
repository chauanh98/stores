import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventory/inter_store_transfer_service.dart';
import 'package:stores/domain/entities/product.dart';

import '../../support/firebase_test_harness.dart';

void main() {
  late MockFirebaseDatabase mockDb;
  late InterStoreTransferService service;

  const sampleProduct = Product(
    id: 'prod_100',
    name: 'Bàn phím cơ không dây',
    code: 'KB100',
    price: 1500000,
    costPrice: 950000,
    branchStocks: {'store_001': 15, 'store_002': 5},
    category: 'Phụ kiện',
  );

  setUp(() {
    mockDb = MockFirebaseDatabase();
    service = InterStoreTransferService(mockDb);
  });

  group('InterStoreTransferService Lifecycle Tests', () {
    test('Successful transfer: verifies multi-path atomic update decrements source branch stock, increments target branch stock, and records 2 inventory transactions (export from source, import to target)', () async {
      // 1. Seed existing product in target store
      mockDb.seedData('stores/store_002/products/prod_100', {
        'id': 'prod_100',
        'name': 'Bàn phím cơ không dây',
        'code': 'KB100',
        'branchStocks': {'store_001': 15, 'store_002': 5},
      });

      // 2. Execute transfer of 6 units from store_001 to store_002
      final result = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: sampleProduct,
        quantity: 6,
        sourceStoreName: 'Chi nhánh Đông Thắng',
        targetStoreName: 'Chi nhánh Thới Bình',
        createdBy: 'admin_user',
        createdByName: 'Admin Manager',
      );

      // Result should be null (indicating success)
      expect(result, isNull);

      // 3. Verify atomic multi-path update call on root ref
      final updateCalls = mockDb.recorder.callsFor('update');
      expect(updateCalls.length, 1);
      final updateData = updateCalls.first.value as Map<String, dynamic>;

      // Check source store product branch stock: 15 - 6 = 9 for source, synchronized 5 + 6 = 11 for target
      const sourceStockKey = 'stores/store_001/products/prod_100/branchStocks';
      expect(updateData.containsKey(sourceStockKey), true);
      final sourceStocks = updateData[sourceStockKey] as Map<String, int>;
      expect(sourceStocks['store_001'], 9);
      expect(sourceStocks['store_002'], 11);

      // Check target store product branch stock: 5 + 6 = 11 for target, synchronized 9 for source
      const targetStockKey = 'stores/store_002/products/prod_100/branchStocks';
      expect(updateData.containsKey(targetStockKey), true);
      final targetStocks = updateData[targetStockKey] as Map<String, int>;
      expect(targetStocks['store_002'], 11);
      expect(targetStocks['store_001'], 9);

      // Check source store export transaction
      final exportEntry = updateData.entries.firstWhere(
        (e) => e.key.startsWith('stores/store_001/inventory_transactions/'),
      );
      final exportTx = exportEntry.value as Map<String, dynamic>;
      expect(exportTx['productId'], 'prod_100');
      expect(exportTx['type'], 'export');
      expect(exportTx['quantity'], 6);
      expect(exportTx['storeId'], 'store_001');
      expect(exportTx['importPrice'], 950000.0);
      expect(exportTx['createdBy'], 'admin_user');
      expect(exportTx['createdByName'], 'Admin Manager');
      expect(exportTx['note'].toString().contains('Chi nhánh Thới Bình'), true);

      // Check target store import transaction
      final importEntry = updateData.entries.firstWhere(
        (e) => e.key.startsWith('stores/store_002/inventory_transactions/'),
      );
      final importTx = importEntry.value as Map<String, dynamic>;
      expect(importTx['productId'], 'prod_100');
      expect(importTx['type'], 'import');
      expect(importTx['quantity'], 6);
      expect(importTx['storeId'], 'store_002');
      expect(importTx['importPrice'], 950000.0);
      expect(importTx['createdBy'], 'admin_user');
      expect(importTx['createdByName'], 'Admin Manager');
      expect(importTx['note'].toString().contains('Chi nhánh Đông Thắng'), true);
    });

    test('Insufficient source branch stock: throws error when source branch stock < transfer quantity (even if global stock across all stores is sufficient)', () async {
      // Global stock is 20 (store_001: 2, store_002: 18)
      const lowSourceProduct = Product(
        id: 'prod_low',
        name: 'Màn hình văn phòng',
        code: 'MN01',
        price: 2000000,
        costPrice: 1500000,
        branchStocks: {'store_001': 2, 'store_002': 18},
        category: 'Màn hình',
      );

      // Attempt to transfer 5 units from store_001. Global stock is 20 >= 5, but branch stock is only 2.
      final error = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: lowSourceProduct,
        quantity: 5,
      );

      // Must throw/return branch stock validation error and NOT touch the DB
      expect(error, isNotNull);
      expect(error, equals('Không đủ số lượng trong kho'));
      expect(mockDb.recorder.callsFor('update').isEmpty, true);
    });

    test('Edge case: transfer between same store is rejected', () async {
      final error = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_001',
        product: sampleProduct,
        quantity: 3,
      );

      expect(error, equals('Không thể chuyển cùng kho'));
      expect(mockDb.recorder.callsFor('update').isEmpty, true);
    });

    test('Edge case: invalid store IDs or non-positive quantities are rejected', () async {
      // Empty source store ID
      final errEmptySource = await service.transferProduct(
        sourceStoreId: '',
        targetStoreId: 'store_002',
        product: sampleProduct,
        quantity: 3,
      );
      expect(errEmptySource, equals('Chi nhánh không hợp lệ'));

      // Empty target store ID
      final errEmptyTarget = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: '',
        product: sampleProduct,
        quantity: 3,
      );
      expect(errEmptyTarget, equals('Chi nhánh không hợp lệ'));

      // Zero quantity
      final errZero = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: sampleProduct,
        quantity: 0,
      );
      expect(errZero, equals('Số lượng phải lớn hơn 0'));

      // Negative quantity
      final errNeg = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: sampleProduct,
        quantity: -4,
      );
      expect(errNeg, equals('Số lượng phải lớn hơn 0'));

      expect(mockDb.recorder.callsFor('update').isEmpty, true);
    });

    test('Target product does not exist yet: creates new product record in target store with initial branchStocks', () async {
      // Do not seed target product in store_002
      final result = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: sampleProduct,
        quantity: 4,
      );

      expect(result, isNull);

      final updateCalls = mockDb.recorder.callsFor('update');
      expect(updateCalls.length, 1);
      final updateData = updateCalls.first.value as Map<String, dynamic>;

      // Target product full document created
      const targetProductKey = 'stores/store_002/products/prod_100';
      expect(updateData.containsKey(targetProductKey), true);
      final createdProduct = updateData[targetProductKey] as Map<String, dynamic>;
      expect(createdProduct['id'], 'prod_100');
      expect(createdProduct['branchStocks']['store_001'], 11);
      expect(createdProduct['branchStocks']['store_002'], 9);

      // Source product stock decremented
      final sourceStocks =
          updateData['stores/store_001/products/prod_100/branchStocks'] as Map<String, int>;
      expect(sourceStocks['store_001'], 11); // 15 - 4 = 11
      expect(sourceStocks['store_002'], 9); // Synchronized target stock
    });

    test('Canonical branch alias resolution: maps store_001 to branch_1 and store_002 to branch_2 accurately', () async {
      const aliasProduct = Product(
        id: 'prod_alias',
        name: 'Chuột quang',
        code: 'CQ01',
        price: 250000,
        costPrice: 150000,
        branchStocks: {'branch_1': 10, 'branch_2': 2},
        category: 'Phụ kiện',
      );

      mockDb.seedData('stores/store_002/products/prod_alias', {
        'id': 'prod_alias',
        'branchStocks': {'branch_1': 10, 'branch_2': 2},
      });

      final result = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: aliasProduct,
        quantity: 3,
      );

      expect(result, isNull);

      final updateCalls = mockDb.recorder.callsFor('update');
      final updateData = updateCalls.first.value as Map<String, dynamic>;

      // Source stock decremented on 'branch_1' key: 10 - 3 = 7
      final sourceStocks =
          updateData['stores/store_001/products/prod_alias/branchStocks'] as Map<String, int>;
      expect(sourceStocks['branch_1'], 7);

      // Target stock incremented on 'branch_2' key: 2 + 3 = 5
      final targetStocks =
          updateData['stores/store_002/products/prod_alias/branchStocks'] as Map<String, int>;
      expect(targetStocks['branch_2'], 5);
    });
  });
}
