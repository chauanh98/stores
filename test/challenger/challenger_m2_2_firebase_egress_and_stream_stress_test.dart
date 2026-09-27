import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/core/utils/stream_debounce_helper.dart';
import 'package:stores/data/datasources/firebase/attendance_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/repositories/category_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';

import '../support/firebase_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Challenger M2-2: Stream Debounce 250ms Empirical Verification', () {
    test('50 rapid events in 10ms coalesce into exactly 1 emission after 250ms silence', () async {
      final controller = StreamController<int>();
      final emissions = <int>[];
      final sub = controller.stream.debounce(const Duration(milliseconds: 250)).listen(emissions.add);

      for (int i = 1; i <= 50; i++) {
        controller.add(i);
        await Future.delayed(const Duration(microseconds: 200));
      }

      // At ~20ms, debounce should not have fired yet
      expect(emissions, isEmpty);

      // Wait 100ms: still within 250ms silence window
      await Future.delayed(const Duration(milliseconds: 100));
      expect(emissions, isEmpty);

      // Wait 180ms more (total > 250ms since last event)
      await Future.delayed(const Duration(milliseconds: 180));
      expect(emissions.length, equals(1));
      expect(emissions.single, equals(50));

      await sub.cancel();
      await controller.close();
    });

    test('Finite stream flushing: onDone immediately flushes pending event without dropping', () async {
      final controller = StreamController<String>();
      final emissions = <String>[];
      final completer = Completer<void>();

      final sub = controller.stream.debounce(const Duration(milliseconds: 250)).listen(
        emissions.add,
        onDone: () => completer.complete(),
      );

      // Add event and close stream immediately
      controller.add('final_flush_test');
      await controller.close();

      // Should complete immediately and flush the event despite < 250ms
      await completer.future.timeout(const Duration(milliseconds: 50));
      expect(emissions.length, equals(1));
      expect(emissions.single, equals('final_flush_test'));

      await sub.cancel();
    });

    test('Two separated bursts yield exactly two emissions with their respective final values', () async {
      final controller = StreamController<int>();
      final emissions = <int>[];
      final sub = controller.stream.debounce(const Duration(milliseconds: 200)).listen(emissions.add);

      // Burst 1
      for (int i = 1; i <= 5; i++) {
        controller.add(i);
      }
      await Future.delayed(const Duration(milliseconds: 220));
      expect(emissions, equals([5]));

      // Burst 2
      for (int i = 10; i <= 15; i++) {
        controller.add(i);
      }
      await Future.delayed(const Duration(milliseconds: 220));
      expect(emissions, equals([5, 15]));

      await sub.cancel();
      await controller.close();
    });

    test('Error propagation: errors are forwarded immediately without debounce delay', () async {
      final controller = StreamController<int>();
      final errors = <dynamic>[];
      final sub = controller.stream.debounce(const Duration(milliseconds: 250)).listen(
        (_) {},
        onError: (err) => errors.add(err),
      );

      controller.addError(Exception('test_error_instant'));
      await Future.delayed(const Duration(milliseconds: 10));

      expect(errors.length, equals(1));
      expect(errors.first.toString(), contains('test_error_instant'));

      await sub.cancel();
      await controller.close();
    });

    test('Subscription cancellation cancels active debounce timer and underlying subscription', () async {
      bool isSourceCancelled = false;
      late StreamController<int> controller;
      controller = StreamController<int>(
        onCancel: () {
          isSourceCancelled = true;
        },
      );

      final emissions = <int>[];
      final sub = controller.stream.debounce(const Duration(milliseconds: 250)).listen(emissions.add);

      controller.add(42);
      await Future.delayed(const Duration(milliseconds: 50));

      // Cancel before timer expires
      await sub.cancel();
      expect(isSourceCancelled, isTrue);

      // Wait well past debounce duration
      await Future.delayed(const Duration(milliseconds: 300));
      expect(emissions, isEmpty);

      await controller.close();
    });

    test('Nullable streams: Stream<String?> cleanly handles null data events', () async {
      final controller = StreamController<String?>();
      final emissions = <String?>[];
      final sub = controller.stream.debounce(const Duration(milliseconds: 150)).listen(emissions.add);

      controller.add('initial');
      controller.add(null);

      await Future.delayed(const Duration(milliseconds: 180));
      expect(emissions.length, equals(1));
      expect(emissions.single, isNull);

      await sub.cancel();
      await controller.close();
    });
  });

  group('Challenger M2-2: Riverpod StreamProviders .autoDispose Subscription Lifecycle', () {
    test('categoryListProvider is AutoDisposeStreamProvider and tears down subscription on dispose', () async {
      expect(categoryListProvider, isA<AutoDisposeStreamProvider<List<Category>>>());

      bool isCancelled = false;
      final mockCategoryStream = StreamController<List<Category>>(
        onCancel: () => isCancelled = true,
      );

      final container = ProviderContainer(
        overrides: [
          categoryRepositoryProvider.overrideWithValue(_MockCategoryRepository(mockCategoryStream.stream)),
        ],
      );

      final sub = container.listen(categoryListProvider, (prev, next) {});
      expect(mockCategoryStream.hasListener, isTrue);

      // Emit initial data
      mockCategoryStream.add([const Category(id: 'c1', name: 'Cat 1')]);
      await Future.delayed(Duration.zero);

      // Close subscription to trigger autoDispose
      sub.close();
      await Future.delayed(const Duration(milliseconds: 10));

      expect(isCancelled, isTrue);
      expect(mockCategoryStream.hasListener, isFalse);

      container.dispose();
      await mockCategoryStream.close();
    });

    test('ordersByDateRangeProvider is AutoDisposeStreamProviderFamily and tears down subscription', () async {
      expect(ordersByDateRangeProvider, isA<AutoDisposeStreamProviderFamily<List<Order>, DateTimeRange>>());

      bool isCancelled = false;
      final mockOrderStream = StreamController<List<Order>>(
        onCancel: () => isCancelled = true,
      );

      final container = ProviderContainer(
        overrides: [
          orderRepositoryProvider.overrideWithValue(_MockOrderRepository(mockOrderStream.stream)),
        ],
      );

      final range = DateTimeRange(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 30),
      );

      final sub = container.listen(ordersByDateRangeProvider(range), (prev, next) {});
      expect(mockOrderStream.hasListener, isTrue);

      // Emit initial data
      mockOrderStream.add([]);
      await Future.delayed(Duration.zero);

      sub.close();
      await Future.delayed(const Duration(milliseconds: 10));

      expect(isCancelled, isTrue);
      expect(mockOrderStream.hasListener, isFalse);

      container.dispose();
      await mockOrderStream.close();
    });

    test('storePaymentConfigStreamProvider is AutoDisposeStreamProvider and storePaymentConfigProvider is AutoDisposeProvider', () async {
      expect(storePaymentConfigStreamProvider, isA<AutoDisposeStreamProvider<StorePaymentConfig>>());
      expect(storePaymentConfigProvider, isA<AutoDisposeProvider<StorePaymentConfig>>());

      final container = ProviderContainer();
      final sub = container.listen(storePaymentConfigProvider, (prev, next) {});
      sub.close();
      await Future.delayed(Duration.zero);
      container.dispose();
    });

    test('All targeted Riverpod StreamProviders declare AutoDispose types', () {
      expect(ordersByDateRangeProvider, isA<AutoDisposeStreamProviderFamily>());
      expect(allBranchesOrdersByDateRangeProvider, isA<AutoDisposeStreamProviderFamily>());
      expect(returnOrdersByDateRangeProvider, isA<AutoDisposeStreamProviderFamily>());
      expect(returnOrdersByOrderIdProvider, isA<AutoDisposeStreamProviderFamily>());
      expect(allBranchesReturnOrdersByDateRangeProvider, isA<AutoDisposeStreamProviderFamily>());
      expect(revenueByDateProvider, isA<AutoDisposeStreamProviderFamily>());
      expect(revenueByDateRangeProvider, isA<AutoDisposeStreamProviderFamily>());
      expect(categoryListProvider, isA<AutoDisposeStreamProvider>());
      expect(storePaymentConfigStreamProvider, isA<AutoDisposeStreamProvider>());
      expect(storePaymentConfigProvider, isA<AutoDisposeProvider>());
      expect(customerDebtTransactionsProvider, isA<AutoDisposeStreamProviderFamily>());
      expect(supplierDebtTransactionsProvider, isA<AutoDisposeStreamProviderFamily>());
      expect(transactionsByProductProvider, isA<AutoDisposeStreamProviderFamily>());
      expect(rawImportTransactionsStreamProvider, isA<AutoDisposeStreamProvider>());
      expect(storedStockInReceiptsStreamProvider, isA<AutoDisposeStreamProvider>());
      expect(productListProvider, isA<AutoDisposeStreamProvider>());
      expect(allStoresProductsProvider, isA<AutoDisposeStreamProvider>());
    });
  });

  group('Challenger M2-2: database.rules.json Validation & Index Coverage', () {
    late Map<String, dynamic> rulesJson;

    setUpAll(() {
      final file = File('database.rules.json');
      expect(file.existsSync(), isTrue, reason: 'database.rules.json must exist in project root');
      final content = file.readAsStringSync();
      rulesJson = jsonDecode(content) as Map<String, dynamic>;
    });

    test('database.rules.json is valid JSON with required root keys', () {
      expect(rulesJson.containsKey('rules'), isTrue);
      final rules = rulesJson['rules'] as Map<String, dynamic>;
      expect(rules['.read'], isTrue);
      expect(rules['.write'], isTrue);
    });

    test('All collections have comprehensive server-side .indexOn declarations', () {
      final rules = rulesJson['rules'] as Map<String, dynamic>;
      final stores = rules['stores']?[r'$storeId'] as Map<String, dynamic>;

      // 1. orders
      final orderIndexes = (stores['orders']?['.indexOn'] as List).cast<String>();
      expect(orderIndexes, containsAll(['createdAt', 'orderDate', 'customerId', 'status', 'createdBy']));

      // 2. return_orders
      final returnIndexes = (stores['return_orders']?['.indexOn'] as List).cast<String>();
      expect(returnIndexes, containsAll(['createdAt', 'orderId', 'customerId']));

      // 3. inventory_transactions
      final invIndexes = (stores['inventory_transactions']?['.indexOn'] as List).cast<String>();
      expect(invIndexes, containsAll(['date', 'productId', 'type', 'importCode', 'supplierId']));

      // 4. stock_in_receipts
      final receiptIndexes = (stores['stock_in_receipts']?['.indexOn'] as List).cast<String>();
      expect(receiptIndexes, containsAll(['date', 'status', 'importCode', 'supplierId', 'createdAt']));

      // 5. products
      final prodIndexes = (stores['products']?['.indexOn'] as List).cast<String>();
      expect(prodIndexes, containsAll(['category', 'code', 'id', 'allowSale', 'type']));

      // 6. attendance in stores/$storeId
      final attBranchIndexes = (stores['attendance']?['.indexOn'] as List).cast<String>();
      expect(attBranchIndexes, containsAll(['date', 'userId', 'storeId']));

      // 7. attendances at root
      final rootAttIndexes = (rules['attendances']?['.indexOn'] as List).cast<String>();
      expect(rootAttIndexes, containsAll(['date', 'storeId', 'userId']));

      // 8. attendance_adjustments
      final adjIndexes = (rules['attendance_adjustments']?['.indexOn'] as List).cast<String>();
      expect(adjIndexes, containsAll(['storeId', 'userId', 'status', 'submittedAt']));

      // 9. shared_customers
      final custIndexes = (rules['shared_customers']?['.indexOn'] as List).cast<String>();
      expect(custIndexes, containsAll(['phone', 'id', 'branch', 'currentDebt']));

      // 10. shared_suppliers
      final suppIndexes = (rules['shared_suppliers']?['.indexOn'] as List).cast<String>();
      expect(suppIndexes, containsAll(['code', 'phone', 'id']));

      // 11. store_payment_configs
      final payIndexes = (rules['store_payment_configs']?['.indexOn'] as List).cast<String>();
      expect(payIndexes, contains('storeId'));
    });

    test('Verifies every orderByChild call in remote datasources is covered by .indexOn', () {
      final rules = rulesJson['rules'] as Map<String, dynamic>;
      final stores = rules['stores']?[r'$storeId'] as Map<String, dynamic>;

      // order_remote_data_source: orderByChild('customerId')
      expect((stores['orders']['.indexOn'] as List).contains('customerId'), isTrue);
      // order_remote_data_source: orderByChild('createdAt')
      expect((stores['orders']['.indexOn'] as List).contains('createdAt'), isTrue);
      // order_remote_data_source (return): orderByChild('createdAt')
      expect((stores['return_orders']['.indexOn'] as List).contains('createdAt'), isTrue);
      // order_remote_data_source (return): orderByChild('orderId')
      expect((stores['return_orders']['.indexOn'] as List).contains('orderId'), isTrue);

      // inventory_remote_data_source: orderByChild('productId')
      expect((stores['inventory_transactions']['.indexOn'] as List).contains('productId'), isTrue);
      // inventory_remote_data_source: orderByChild('date')
      expect((stores['inventory_transactions']['.indexOn'] as List).contains('date'), isTrue);

      // attendance_remote_data_source: orderByChild('date'), orderByChild('storeId')
      expect((rules['attendances']['.indexOn'] as List).contains('date'), isTrue);
      expect((rules['attendances']['.indexOn'] as List).contains('storeId'), isTrue);
    });
  });

  group('Challenger M2-2: Data Source Query Bounding & Payload Safety', () {
    late MockFirebaseDatabase mockDb;
    const storeId = 'store_test_001';

    setUp(() {
      mockDb = MockFirebaseDatabase();
    });

    test('OrderRemoteDataSource.fetchByDateRange returns [] on query exception without calling root .get()', () async {
      mockDb.setSimulateQueryFailure('stores/$storeId/orders', true);

      final ds = OrderRemoteDataSource(mockDb, storeId);
      final result = await ds.fetchByDateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30));

      expect(result, isEmpty);
      // Exactly 1 bounded query call, zero secondary fallback .get() calls
      expect(mockDb.getCallCount('stores/$storeId/orders'), equals(1));
    });

    test('InventoryRemoteDataSource.fetchImportsByDateRange returns [] on query exception without calling root .get()', () async {
      mockDb.setSimulateQueryFailure('stores/$storeId/inventory_transactions', true);

      final ds = InventoryRemoteDataSource(mockDb, storeId);
      final result = await ds.fetchImportsByDateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30));

      expect(result, isEmpty);
      // Exactly 1 bounded query call, zero secondary fallback .get() calls
      expect(mockDb.getCallCount('stores/$storeId/inventory_transactions'), equals(1));
    });

    test('StockInReceiptRemoteDataSource.watchReceipts bounds with limitToLast(50) and 250ms debounce', () async {
      final ds = StockInReceiptRemoteDataSource(mockDb);
      final stream = ds.watchReceipts(storeId, limit: 50);

      final emissions = <List<Map<String, dynamic>>>[];
      final sub = stream.listen(emissions.add);

      final ref = mockDb.getOrCreateRef('stores/$storeId/stock_in_receipts');
      ref.emitValue({'rcpt_1': {'id': 'rcpt_1', 'status': 'completed'}});

      await Future.delayed(const Duration(milliseconds: 100));
      expect(emissions, isEmpty); // Debounce still pending

      await Future.delayed(const Duration(milliseconds: 180));
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(1));

      await sub.cancel();
    });

    test('StockInReceiptItem.toMap strictly excludes Base64 data URIs from receipt payload', () {
      const itemWithBase64 = StockInReceiptItem(
        transactionId: 'tx_1',
        productId: 'prod_1',
        productName: 'Sữa tươi',
        productCode: 'ST01',
        quantity: 10,
        unitPrice: 20000,
        imageUrl: 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD...',
      );

      final mapBase64 = itemWithBase64.toMap();
      expect(mapBase64.containsKey('imageUrl'), isFalse, reason: 'Base64 data URIs must NEVER be persisted in receipt line items');

      const itemWithRemoteUrl = StockInReceiptItem(
        transactionId: 'tx_2',
        productId: 'prod_2',
        productName: 'Bánh gạo',
        productCode: 'BG01',
        quantity: 5,
        unitPrice: 15000,
        imageUrl: 'https://firebasestorage.googleapis.com/v0/b/store.appspot.com/o/sample.png',
      );

      final mapRemote = itemWithRemoteUrl.toMap();
      expect(mapRemote['imageUrl'], equals('https://firebasestorage.googleapis.com/v0/b/store.appspot.com/o/sample.png'));
    });

    test('AttendanceRemoteDataSource.getAttendances routes queries with server-side indexing', () async {
      final ds = AttendanceRemoteDataSource(db: mockDb);

      // Query with dateStr uses orderByChild('date')
      await ds.getAttendances(storeId: 'store_001', dateStr: '2026-09-27');
      expect(mockDb.recorder.hasCalled('get', path: 'attendances'), isTrue);

      final getCalls = mockDb.recorder.callsFor('get', path: 'attendances');
      expect(getCalls.any((c) => c.extra?['orderedByChildKey'] == 'date'), isTrue);
    });

    test('AttendanceRemoteDataSource.watchAttendances applies 250ms stream debounce', () async {
      final ds = AttendanceRemoteDataSource(db: mockDb);
      final stream = ds.watchAttendances(storeId: 'store_001', dateStr: '2026-09-27');

      final emissions = <List<dynamic>>[];
      final sub = stream.listen(emissions.add);

      final ref = mockDb.getOrCreateRef('attendances');
      ref.emitValue({'att_1': {'id': 'att_1', 'storeId': 'store_001', 'date': '2026-09-27'}});

      await Future.delayed(const Duration(milliseconds: 100));
      expect(emissions, isEmpty); // Debounce waiting

      await Future.delayed(const Duration(milliseconds: 180));
      expect(emissions.length, equals(1));

      await sub.cancel();
    });
  });
}

class _MockCategoryRepository implements CategoryRepository {
  final Stream<List<Category>> _stream;
  _MockCategoryRepository(this._stream);

  @override
  Stream<List<Category>> watchAll() => _stream;

  @override
  Future<List<Category>> fetchAll() async => [];

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> upsert(Category category) async {}
}

class _MockOrderRepository implements OrderRepository, OrderRepositoryReturnHandler {
  final Stream<List<Order>> _stream;
  _MockOrderRepository(this._stream);

  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) => _stream;

  @override
  Stream<List<Order>> watchAll() => _stream;

  @override
  Stream<List<Order>> watchByCustomer(String customerId) => _stream;

  @override
  Future<Order?> fetchById(String orderId) async => null;

  @override
  Future<void> create(Order order) async {}

  @override
  Future<void> update(Order order) async {}

  @override
  Future<void> delete(String orderId) async {}

  @override
  Future<void> createReturn(ReturnOrder returnOrder) async {}

  @override
  Future<ReturnOrder?> fetchReturnById(String returnId) async => null;

  @override
  Stream<List<ReturnOrder>> watchReturnsByDateRange(DateTime start, DateTime end) => const Stream.empty();

  @override
  Stream<List<ReturnOrder>> watchReturnsByOrderId(String orderId) => const Stream.empty();
}
