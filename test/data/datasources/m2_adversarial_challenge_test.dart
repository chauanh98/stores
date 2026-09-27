import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/attendance_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/datasources/stock_in_receipt_remote_data_source.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';

import '../../support/firebase_test_harness.dart';

/// Spy Database Reference that records calls to query building methods like limitToLast.
class SpyDatabaseReference extends MockDatabaseReference {
  int? recordedLimitToLast;
  int? recordedLimitToFirst;

  SpyDatabaseReference({
    required super.path,
    required super.recorder,
    super.initialData,
  });

  @override
  Query limitToLast(int limit) {
    recordedLimitToLast = limit;
    return super.limitToLast(limit);
  }

  @override
  Query limitToFirst(int limit) {
    recordedLimitToFirst = limit;
    return super.limitToFirst(limit);
  }
}

/// Custom mock database injecting [SpyDatabaseReference].
class SpyFirebaseDatabase extends MockFirebaseDatabase {
  final Map<String, SpyDatabaseReference> spyReferences = {};

  @override
  MockDatabaseReference getOrCreateRef(String path,
      {Map<String, dynamic>? initialData}) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    requestedPaths.add(cleanPath);
    return spyReferences.putIfAbsent(
      cleanPath,
      () => SpyDatabaseReference(
        path: cleanPath,
        recorder: recorder,
        initialData: initialData,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone M2 Adversarial Challenge Suite', () {
    late SpyFirebaseDatabase spyDb;
    const storeId = 'store_test_001';

    setUp(() {
      spyDb = SpyFirebaseDatabase();
    });

    group('Requirement 1: Unconstrained .get() Scans on Collection Roots', () {
      test('OrderRemoteDataSource: NEVER performs unconstrained .get() on collection root', () async {
        final ds = OrderRemoteDataSource(spyDb, storeId);
        const ordersPath = 'stores/$storeId/orders';

        // 1. fetchById queries child path
        await ds.fetchById('ord_123');
        final rootGets = spyDb.recorder
            .callsFor('get')
            .where((c) => c.path == ordersPath)
            .toList();
        expect(rootGets, isEmpty);
        expect(spyDb.recorder.callsFor('get').any((c) => c.path == '$ordersPath/ord_123'), isTrue);

        // 2. fetchByDateRange failure does NOT fall back to unconstrained _ref.get()
        spyDb.setSimulateQueryFailure(ordersPath, true);
        final results = await ds.fetchByDateRange(
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 30),
        );
        expect(results, isEmpty);
        // Only 1 attempt was made (the bounded query), no unconstrained fallback _ref.get() was called
        final unconstrainedGets = spyDb.recorder
            .callsFor('get')
            .where((c) => c.path == ordersPath && c.extra == null)
            .toList();
        expect(unconstrainedGets, isEmpty);
      });

      test('InventoryRemoteDataSource: fetchAll() enforces limitToLast(50) and eliminates unconstrained _ref.get()', () async {
        final ds = InventoryRemoteDataSource(spyDb, storeId);
        const txPath = 'stores/$storeId/inventory_transactions';
        final spyRef = spyDb.getOrCreateRef(txPath) as SpyDatabaseReference;

        final items = await ds.fetchAll();
        expect(items, isEmpty);
        // Bounded query enforced: limitToLast(50) applied and no unconstrained .get() on root
        final unconstrainedGets = spyDb.recorder
            .callsFor('get')
            .where((c) => c.path == txPath && c.extra == null)
            .toList();
        expect(unconstrainedGets, isEmpty);
        expect(spyRef.recordedLimitToLast, equals(50));
      });

      test('InventoryRemoteDataSource: fetchImportsByDateRange on failure does NOT fall back to unconstrained _ref.get()', () async {
        final ds = InventoryRemoteDataSource(spyDb, storeId);
        const txPath = 'stores/$storeId/inventory_transactions';

        spyDb.setSimulateQueryFailure(txPath, true);
        final results = await ds.fetchImportsByDateRange(
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 30),
        );
        expect(results, isEmpty);
        // Fallback unconstrained .get() was successfully eliminated (extra is null)
        final unconstrainedGets = spyDb.recorder
            .callsFor('get')
            .where((c) => c.path == txPath && c.extra == null)
            .toList();
        expect(unconstrainedGets, isEmpty);
      });

      test('AttendanceRemoteDataSource: getAdjustments() performs unconstrained .get() on root attendance_adjustments', () async {
        final ds = AttendanceRemoteDataSource(db: spyDb);
        const adjPath = 'attendance_adjustments';

        expect(spyDb.wasGetCalled(adjPath), isFalse);
        await ds.getAdjustments(storeId: storeId);
        // BUG / FINDING: getAdjustments() downloads the ENTIRE attendance_adjustments node and filters locally
        expect(spyDb.wasGetCalled(adjPath), isTrue);
      });

      test('AttendanceRemoteDataSource: getStoreGpsConfig() performs unconstrained .get() on root stores/\$storeId', () async {
        final ds = AttendanceRemoteDataSource(db: spyDb);
        const storeRootPath = 'stores/$storeId';

        expect(spyDb.wasGetCalled(storeRootPath), isFalse);
        await ds.getStoreGpsConfig(storeId);
        // BUG / FINDING: getStoreGpsConfig() downloads the entire store root tree (including orders, transactions, products)
        expect(spyDb.wasGetCalled(storeRootPath), isTrue);
      });
    });

    group('Requirement 2: watchRecentOrders and watchRecentTransactions limitToLast(50)', () {
      test('OrderRemoteDataSource.watchRecentOrders enforces limitToLast(50) by default', () async {
        final ds = OrderRemoteDataSource(spyDb, storeId);
        const ordersPath = 'stores/$storeId/orders';
        final spyRef = spyDb.getOrCreateRef(ordersPath) as SpyDatabaseReference;

        final stream = ds.watchRecentOrders();
        final sub = stream.listen((_) {});

        expect(spyRef.recordedLimitToLast, equals(50));
        await sub.cancel();
      });

      test('OrderRemoteDataSource.watchRecentOrders respects custom limit', () async {
        final ds = OrderRemoteDataSource(spyDb, storeId);
        const ordersPath = 'stores/$storeId/orders';
        final spyRef = spyDb.getOrCreateRef(ordersPath) as SpyDatabaseReference;

        final stream = ds.watchRecentOrders(limit: 100);
        final sub = stream.listen((_) {});

        expect(spyRef.recordedLimitToLast, equals(100));
        await sub.cancel();
      });

      test('OrderRemoteDataSource.watchAll enforces limitToLast(50)', () async {
        final ds = OrderRemoteDataSource(spyDb, storeId);
        const ordersPath = 'stores/$storeId/orders';
        final spyRef = spyDb.getOrCreateRef(ordersPath) as SpyDatabaseReference;

        final stream = ds.watchAll();
        final sub = stream.listen((_) {});

        expect(spyRef.recordedLimitToLast, equals(50));
        await sub.cancel();
      });

      test('InventoryRemoteDataSource.watchRecentTransactions enforces limitToLast(50) by default', () async {
        final ds = InventoryRemoteDataSource(spyDb, storeId);
        const txPath = 'stores/$storeId/inventory_transactions';
        final spyRef = spyDb.getOrCreateRef(txPath) as SpyDatabaseReference;

        final stream = ds.watchRecentTransactions();
        final sub = stream.listen((_) {});

        expect(spyRef.recordedLimitToLast, equals(50));
        await sub.cancel();
      });

      test('InventoryRemoteDataSource.watchRecentTransactions respects custom limit', () async {
        final ds = InventoryRemoteDataSource(spyDb, storeId);
        const txPath = 'stores/$storeId/inventory_transactions';
        final spyRef = spyDb.getOrCreateRef(txPath) as SpyDatabaseReference;

        final stream = ds.watchRecentTransactions(limit: 25);
        final sub = stream.listen((_) {});

        expect(spyRef.recordedLimitToLast, equals(25));
        await sub.cancel();
      });

      test('InventoryRemoteDataSource.watchAll enforces limitToLast(50)', () async {
        final ds = InventoryRemoteDataSource(spyDb, storeId);
        const txPath = 'stores/$storeId/inventory_transactions';
        final spyRef = spyDb.getOrCreateRef(txPath) as SpyDatabaseReference;

        final stream = ds.watchAll();
        final sub = stream.listen((_) {});

        expect(spyRef.recordedLimitToLast, equals(50));
        await sub.cancel();
      });

      test('StockInReceiptRemoteDataSource enforces limitToLast(50) on fetchReceipts and watchReceipts', () async {
        final ds = StockInReceiptRemoteDataSource(spyDb);
        const receiptPath = 'stores/$storeId/stock_in_receipts';
        final spyRef = spyDb.getOrCreateRef(receiptPath) as SpyDatabaseReference;

        await ds.fetchReceipts(storeId);
        expect(spyRef.recordedLimitToLast, equals(50));

        spyRef.recordedLimitToLast = null;
        final stream = ds.watchReceipts(storeId);
        final sub = stream.listen((_) {});
        expect(spyRef.recordedLimitToLast, equals(50));
        await sub.cancel();
      });
    });

    group('Requirement 3: StockInReceiptItem.toMap Base64 Data URI Filtering', () {
      test('Standard base64 data:image URIs are strictly excluded', () {
        const itemPng = StockInReceiptItem(
          transactionId: 'tx_1',
          productId: 'p_1',
          quantity: 1,
          imageUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        );
        expect(itemPng.toMap().containsKey('imageUrl'), isFalse);

        const itemJpeg = StockInReceiptItem(
          transactionId: 'tx_2',
          productId: 'p_2',
          quantity: 1,
          imageUrl: 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBD...',
        );
        expect(itemJpeg.toMap().containsKey('imageUrl'), isFalse);

        const itemWebp = StockInReceiptItem(
          transactionId: 'tx_3',
          productId: 'p_3',
          quantity: 1,
          imageUrl: 'data:image/webp;base64,UklGRkAAAABXRUJQVlA4IDQAAADwAQCdASoBAAEAAQAcJaACdLoAAP7/2wAA',
        );
        expect(itemWebp.toMap().containsKey('imageUrl'), isFalse);
      });

      test('Normal HTTP and HTTPS URLs are preserved in toMap()', () {
        const itemRemote = StockInReceiptItem(
          transactionId: 'tx_4',
          productId: 'p_remote',
          quantity: 1,
          imageUrl: 'https://firebasestorage.googleapis.com/v0/b/project/o/product.png?alt=media',
        );
        expect(itemRemote.toMap()['imageUrl'], equals('https://firebasestorage.googleapis.com/v0/b/project/o/product.png?alt=media'));

        const itemHttp = StockInReceiptItem(
          transactionId: 'tx_5',
          productId: 'p_http',
          quantity: 1,
          imageUrl: 'http://cdn.store.vn/images/sp1.jpg',
        );
        expect(itemHttp.toMap()['imageUrl'], equals('http://cdn.store.vn/images/sp1.jpg'));
      });

      test('Null imageUrl does not produce imageUrl key in toMap()', () {
        const itemNull = StockInReceiptItem(
          transactionId: 'tx_6',
          productId: 'p_null',
          quantity: 1,
          imageUrl: null,
        );
        expect(itemNull.toMap().containsKey('imageUrl'), isFalse);
      });

      test('Edge case: Uppercase DATA:image URI or leading whitespace is strictly dropped', () {
        // Adversarial check: Does case sensitivity or leading whitespace allow Base64 URI through?
        const itemUpper = StockInReceiptItem(
          transactionId: 'tx_7',
          productId: 'p_upper',
          quantity: 1,
          imageUrl: 'DATA:IMAGE/PNG;BASE64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        );
        final isDroppedUpper = !itemUpper.toMap().containsKey('imageUrl');

        const itemTrim = StockInReceiptItem(
          transactionId: 'tx_8',
          productId: 'p_trim',
          quantity: 1,
          imageUrl: ' data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        );
        final isDroppedTrim = !itemTrim.toMap().containsKey('imageUrl');

        // Document that uppercase DATA:image and untrimmed URIs are strictly dropped
        expect(isDroppedUpper, isTrue, reason: 'startsWith is case-insensitive; uppercase DATA:image is dropped');
        expect(isDroppedTrim, isTrue, reason: 'startsWith is sensitive to leading whitespace; untrimmed URI is dropped');
      });
    });
  });
}
