import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/attendance_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/datasources/stock_in_receipt_remote_data_source.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';

import '../../support/firebase_test_harness.dart';

/// Spy Query recording every chained call on query constraints.
class M4SpyQuery extends MockQuery {
  final List<String> callChain;
  final List<M4SpyQuery> queryRegistry;

  M4SpyQuery({
    required super.path,
    required super.storeData,
    required super.recorder,
    required this.queryRegistry,
    super.orderedByChildKey,
    super.startRange,
    super.endRange,
    super.equalToVal,
    super.limitFirst,
    super.limitLast,
    super.queryValueStream,
    super.queryChildAddedStream,
    super.queryChildChangedStream,
    super.queryChildRemovedStream,
    List<String>? initialCallChain,
  }) : callChain = initialCallChain ?? [] {
    queryRegistry.add(this);
  }

  @override
  Query orderByChild(String key) {
    final nextChain = List<String>.from(callChain)..add('orderByChild($key)');
    return M4SpyQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      queryRegistry: queryRegistry,
      orderedByChildKey: key,
      startRange: startRange,
      endRange: endRange,
      equalToVal: equalToVal,
      limitFirst: limitFirst,
      limitLast: limitLast,
      queryValueStream: queryValueStream,
      queryChildAddedStream: queryChildAddedStream,
      queryChildChangedStream: queryChildChangedStream,
      queryChildRemovedStream: queryChildRemovedStream,
      initialCallChain: nextChain,
    );
  }

  @override
  Query equalTo(dynamic value, {String? key}) {
    final nextChain = List<String>.from(callChain)..add('equalTo($value)');
    return M4SpyQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      queryRegistry: queryRegistry,
      orderedByChildKey: orderedByChildKey,
      startRange: value,
      endRange: value,
      equalToVal: value,
      limitFirst: limitFirst,
      limitLast: limitLast,
      queryValueStream: queryValueStream,
      queryChildAddedStream: queryChildAddedStream,
      queryChildChangedStream: queryChildChangedStream,
      queryChildRemovedStream: queryChildRemovedStream,
      initialCallChain: nextChain,
    );
  }

  @override
  Query limitToLast(int limit) {
    final nextChain = List<String>.from(callChain)..add('limitToLast($limit)');
    return M4SpyQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      queryRegistry: queryRegistry,
      orderedByChildKey: orderedByChildKey,
      startRange: startRange,
      endRange: endRange,
      equalToVal: equalToVal,
      limitFirst: limitFirst,
      limitLast: limit,
      queryValueStream: queryValueStream,
      queryChildAddedStream: queryChildAddedStream,
      queryChildChangedStream: queryChildChangedStream,
      queryChildRemovedStream: queryChildRemovedStream,
      initialCallChain: nextChain,
    );
  }
}

/// Spy DatabaseReference returning [M4SpyQuery] to record query chain.
class M4SpyDatabaseReference extends MockDatabaseReference {
  int? recordedLimitToLast;
  String? recordedOrderByChild;
  final List<String> rootOperations = [];
  final List<M4SpyQuery> createdQueries = [];

  M4SpyDatabaseReference({
    required super.path,
    required super.recorder,
    super.initialData,
  });

  @override
  Query limitToLast(int limit) {
    recordedLimitToLast = limit;
    rootOperations.add('limitToLast($limit)');
    return M4SpyQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      queryRegistry: createdQueries,
      limitLast: limit,
      queryValueStream: valueStream,
      queryChildAddedStream: childAddedStream,
      queryChildChangedStream: childChangedStream,
      queryChildRemovedStream: childRemovedStream,
      initialCallChain: ['limitToLast($limit)'],
    );
  }

  @override
  Query orderByChild(String key) {
    recordedOrderByChild = key;
    rootOperations.add('orderByChild($key)');
    return M4SpyQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      queryRegistry: createdQueries,
      orderedByChildKey: key,
      queryValueStream: valueStream,
      queryChildAddedStream: childAddedStream,
      queryChildChangedStream: childChangedStream,
      queryChildRemovedStream: childRemovedStream,
      initialCallChain: ['orderByChild($key)'],
    );
  }
}

/// Mock Firebase Database delivering [M4SpyDatabaseReference].
class M4SpyFirebaseDatabase extends MockFirebaseDatabase {
  final Map<String, M4SpyDatabaseReference> spyReferences = {};

  @override
  MockDatabaseReference getOrCreateRef(String path,
      {Map<String, dynamic>? initialData}) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    requestedPaths.add(cleanPath);
    return spyReferences.putIfAbsent(
      cleanPath,
      () => M4SpyDatabaseReference(
        path: cleanPath,
        recorder: recorder,
        initialData: initialData,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 4: Comprehensive Query Constraints & Debouncing Unit Tests',
      () {
    late M4SpyFirebaseDatabase spyDb;
    const storeId = 'store_test_001';

    setUp(() {
      spyDb = M4SpyFirebaseDatabase();
    });

    // =========================================================================
    // 1. OrderRemoteDataSource
    // =========================================================================
    group('1. OrderRemoteDataSource Query Constraints & 250ms Debounce', () {
      const ordersPath = 'stores/$storeId/orders';

      test('watchRecentOrders() enforces limitToLast(50) by default', () async {
        final ds = OrderRemoteDataSource(spyDb, storeId);
        final spyRef =
            spyDb.getOrCreateRef(ordersPath) as M4SpyDatabaseReference;

        final stream = ds.watchRecentOrders();
        final sub = stream.listen((_) {});

        expect(spyRef.recordedLimitToLast, equals(50));
        await sub.cancel();
      });

      test('watchRecentOrders() respects custom limit argument', () async {
        final ds = OrderRemoteDataSource(spyDb, storeId);
        final spyRef =
            spyDb.getOrCreateRef(ordersPath) as M4SpyDatabaseReference;

        final stream = ds.watchRecentOrders(limit: 25);
        final sub = stream.listen((_) {});

        expect(spyRef.recordedLimitToLast, equals(25));
        await sub.cancel();
      });

      test(
          'watchAll() enforces limitToLast(50) and never makes unbounded get()',
          () async {
        final ds = OrderRemoteDataSource(spyDb, storeId);
        final spyRef =
            spyDb.getOrCreateRef(ordersPath) as M4SpyDatabaseReference;

        final stream = ds.watchAll();
        final sub = stream.listen((_) {});

        expect(spyRef.recordedLimitToLast, equals(50));
        expect(
            spyDb.recorder
                .callsFor('get')
                .where((c) => c.path == ordersPath && c.extra == null),
            isEmpty);
        await sub.cancel();
      });

      test(
          'watchRecentOrders() coalesces rapid burst of childAdded events into 1 emission after 250ms',
          () async {
        final ds = OrderRemoteDataSource(spyDb, storeId);
        final spyRef = spyDb.getOrCreateRef(ordersPath);
        final emissions = <List<Map<String, dynamic>>>[];
        final sub = ds.watchRecentOrders().listen(emissions.add);

        // Emit 20 rapid orders
        for (int i = 1; i <= 20; i++) {
          spyRef.emitChildAdded('order_$i', {
            'id': 'order_$i',
            'orderDate': '2026-09-27T10:00:00.000Z',
            'total': i * 50000.0,
          });
        }

        // Before 250ms: No emissions should have fired yet
        await Future.delayed(const Duration(milliseconds: 50));
        expect(emissions, isEmpty,
            reason: 'Debounce window of 250ms must hold back burst emissions');

        // After 250ms debounce expires: Exactly 1 consolidated emission containing all 20 items
        await Future.delayed(const Duration(milliseconds: 230));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(20));

        await sub.cancel();
      });

      test(
          'watchRecentOrders() emits immediately on childChanged without waiting for debounce',
          () async {
        final ds = OrderRemoteDataSource(spyDb, storeId);
        final spyRef = spyDb.getOrCreateRef(ordersPath);
        final emissions = <List<Map<String, dynamic>>>[];
        final sub = ds.watchRecentOrders().listen(emissions.add);

        spyRef.emitChildAdded('order_imm', {
          'id': 'order_imm',
          'total': 100000.0,
          'status': 'draft',
        });
        await Future.delayed(const Duration(milliseconds: 270));
        expect(emissions.length, equals(1));

        final stopwatch = Stopwatch()..start();
        spyRef.emitChildChanged('order_imm', {
          'id': 'order_imm',
          'total': 100000.0,
          'status': 'completed',
        });
        await Future.delayed(const Duration(milliseconds: 15));
        stopwatch.stop();

        expect(emissions.length, equals(2));
        expect(emissions.last.first['status'], equals('completed'));
        expect(stopwatch.elapsedMilliseconds, lessThan(50),
            reason: 'childChanged must emit immediately');

        await sub.cancel();
      });
    });

    // =========================================================================
    // 2. InventoryRemoteDataSource
    // =========================================================================
    group('2. InventoryRemoteDataSource Query Constraints & 250ms Debounce',
        () {
      const txPath = 'stores/$storeId/inventory_transactions';

      test('watchRecentTransactions() enforces limitToLast(50) by default',
          () async {
        final ds = InventoryRemoteDataSource(spyDb, storeId);
        final spyRef = spyDb.getOrCreateRef(txPath) as M4SpyDatabaseReference;

        final stream = ds.watchRecentTransactions();
        final sub = stream.listen((_) {});

        expect(spyRef.recordedLimitToLast, equals(50));
        await sub.cancel();
      });

      test('watchRecentTransactions() respects custom limit', () async {
        final ds = InventoryRemoteDataSource(spyDb, storeId);
        final spyRef = spyDb.getOrCreateRef(txPath) as M4SpyDatabaseReference;

        final stream = ds.watchRecentTransactions(limit: 15);
        final sub = stream.listen((_) {});

        expect(spyRef.recordedLimitToLast, equals(15));
        await sub.cancel();
      });

      test(
          'fetchAll() enforces limitToLast(50) and zero unconstrained root .get() calls',
          () async {
        final ds = InventoryRemoteDataSource(spyDb, storeId);
        final spyRef = spyDb.getOrCreateRef(txPath) as M4SpyDatabaseReference;

        final items = await ds.fetchAll();
        expect(items, isEmpty);
        expect(spyRef.recordedLimitToLast, equals(50));

        final unconstrained = spyDb.recorder
            .callsFor('get')
            .where((c) => c.path == txPath && c.extra == null)
            .toList();
        expect(unconstrained, isEmpty);
      });

      test(
          'watchRecentTransactions() coalesces rapid burst of childAdded events with 250ms debounce',
          () async {
        final ds = InventoryRemoteDataSource(spyDb, storeId);
        final spyRef = spyDb.getOrCreateRef(txPath);
        final emissions = <List<Map>>[];
        final sub = ds.watchRecentTransactions().listen(emissions.add);

        for (int i = 1; i <= 15; i++) {
          spyRef.emitChildAdded('tx_$i', {
            'id': 'tx_$i',
            'type': 'import',
            'quantity': i * 5,
            'timestamp': '2026-09-27T10:00:00.000Z',
          });
        }

        // Before 250ms: No emissions
        await Future.delayed(const Duration(milliseconds: 50));
        expect(emissions, isEmpty);

        // After 250ms: Exactly 1 emission with 15 items
        await Future.delayed(const Duration(milliseconds: 230));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(15));

        await sub.cancel();
      });

      test(
          'watchRecentTransactions() emits immediately on childRemoved without debounce delay',
          () async {
        final ds = InventoryRemoteDataSource(spyDb, storeId);
        final spyRef = spyDb.getOrCreateRef(txPath);
        final emissions = <List<Map>>[];
        final sub = ds.watchRecentTransactions().listen(emissions.add);

        spyRef.emitChildAdded('tx_del', {
          'id': 'tx_del',
          'type': 'export',
          'quantity': 10,
        });
        await Future.delayed(const Duration(milliseconds: 270));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(1));

        // Delete item: childRemoved fires
        spyRef.emitChildRemoved('tx_del');
        await Future.delayed(const Duration(milliseconds: 15));

        expect(emissions.length, equals(2));
        expect(emissions.last, isEmpty,
            reason: 'Transaction item should be purged immediately');

        await sub.cancel();
      });
    });

    // =========================================================================
    // 3. AttendanceRemoteDataSource
    // =========================================================================
    group('3. AttendanceRemoteDataSource Indexed Queries & Scoped GPS', () {
      const attendancesPath = 'attendances';
      const adjPath = 'attendance_adjustments';
      const gpsConfigPath = 'stores/$storeId/gps_config';
      const storeRootPath = 'stores/$storeId';

      test(
          'getAttendances() with dateStr applies orderByChild("date").equalTo(dateStr)',
          () async {
        final ds = AttendanceRemoteDataSource(db: spyDb);
        final spyRef =
            spyDb.getOrCreateRef(attendancesPath) as M4SpyDatabaseReference;

        await ds.getAttendances(storeId: storeId, dateStr: '2026-09-27');

        expect(spyRef.rootOperations, contains('orderByChild(date)'));
        final matchingQueries = spyRef.createdQueries.where(
          (q) => q.orderedByChildKey == 'date' && q.equalToVal == '2026-09-27',
        );
        expect(matchingQueries, isNotEmpty);

        final getCalls = spyDb.recorder.callsFor('get').where(
              (c) =>
                  c.path == attendancesPath &&
                  c.extra?['orderedByChildKey'] == 'date' &&
                  c.extra?['equalToVal'] == '2026-09-27',
            );
        expect(getCalls, isNotEmpty);
      });

      test(
          'getAttendances() without dateStr applies orderByChild("storeId").equalTo(storeId)',
          () async {
        final ds = AttendanceRemoteDataSource(db: spyDb);
        final spyRef =
            spyDb.getOrCreateRef(attendancesPath) as M4SpyDatabaseReference;

        await ds.getAttendances(storeId: storeId);

        expect(spyRef.rootOperations, contains('orderByChild(storeId)'));
        final matchingQueries = spyRef.createdQueries.where(
          (q) => q.orderedByChildKey == 'storeId' && q.equalToVal == storeId,
        );
        expect(matchingQueries, isNotEmpty);
      });

      test(
          'getAttendances() with empty storeId and null dateStr falls back to limitToLast(50)',
          () async {
        final ds = AttendanceRemoteDataSource(db: spyDb);
        final spyRef =
            spyDb.getOrCreateRef(attendancesPath) as M4SpyDatabaseReference;

        await ds.getAttendances(storeId: '');

        expect(spyRef.recordedLimitToLast, equals(50));
      });

      test(
          'watchAttendances() with dateStr applies orderByChild("date").equalTo(dateStr)',
          () async {
        final ds = AttendanceRemoteDataSource(db: spyDb);
        final spyRef =
            spyDb.getOrCreateRef(attendancesPath) as M4SpyDatabaseReference;

        final stream =
            ds.watchAttendances(storeId: storeId, dateStr: '2026-09-27');
        final sub = stream.listen((_) {});

        expect(spyRef.rootOperations, contains('orderByChild(date)'));
        final matchingQueries = spyRef.createdQueries.where(
          (q) => q.orderedByChildKey == 'date' && q.equalToVal == '2026-09-27',
        );
        expect(matchingQueries, isNotEmpty);

        await sub.cancel();
      });

      test('getAdjustments() applies limitToLast(50) by default', () async {
        final ds = AttendanceRemoteDataSource(db: spyDb);
        final spyRef = spyDb.getOrCreateRef(adjPath) as M4SpyDatabaseReference;

        await ds.getAdjustments(storeId: storeId);

        expect(spyRef.recordedLimitToLast, equals(50));
      });

      test(
          'getStoreGpsConfig() strictly scopes query to stores/\$storeId/gps_config and never fetches root stores/\$storeId',
          () async {
        final ds = AttendanceRemoteDataSource(db: spyDb);

        final config = await ds.getStoreGpsConfig(storeId);
        expect(config, isNotNull);

        final gpsGets = spyDb.recorder
            .callsFor('get')
            .where((c) => c.path == gpsConfigPath)
            .toList();
        expect(gpsGets, isNotEmpty,
            reason: 'Must fetch specifically from stores/$storeId/gps_config');

        final rootGets = spyDb.recorder
            .callsFor('get')
            .where((c) => c.path == storeRootPath)
            .toList();
        expect(rootGets, isEmpty,
            reason: 'Must NEVER fetch whole store root node stores/$storeId');
      });
    });

    // =========================================================================
    // 4. StockInReceiptRemoteDataSource
    // =========================================================================
    group('4. StockInReceiptRemoteDataSource Query Constraints', () {
      const receiptPath = 'stores/$storeId/stock_in_receipts';

      test('fetchReceipts() enforces limitToLast(50)', () async {
        final ds = StockInReceiptRemoteDataSource(spyDb);
        final spyRef =
            spyDb.getOrCreateRef(receiptPath) as M4SpyDatabaseReference;

        await ds.fetchReceipts(storeId);
        expect(spyRef.recordedLimitToLast, equals(50));
      });

      test('watchReceipts() enforces limitToLast(50)', () async {
        final ds = StockInReceiptRemoteDataSource(spyDb);
        final spyRef =
            spyDb.getOrCreateRef(receiptPath) as M4SpyDatabaseReference;

        final stream = ds.watchReceipts(storeId);
        final sub = stream.listen((_) {});

        expect(spyRef.recordedLimitToLast, equals(50));
        await sub.cancel();
      });
    });

    // =========================================================================
    // 5. StockInReceiptItem.toMap() Base64 Stripping & Payload Optimization
    // =========================================================================
    group('5. StockInReceiptItem.toMap() Base64 Filtering', () {
      test('case-insensitively strips data:image URIs', () {
        final base64Uris = [
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          'DATA:IMAGE/PNG;BASE64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          'Data:Image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP...',
          'data:image/webp;base64,UklGRkAAAABXRUJQVlA4IDQAAADwAQCdASoBAAEAAQAcJaACdLoAAP7/2Q==',
          'DATA:IMAGE/SVG+XML;BASE64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjwvc3ZnPg==',
        ];

        for (final uri in base64Uris) {
          final item = StockInReceiptItem(
            transactionId: 'tx_b64',
            productId: 'p_b64',
            quantity: 1,
            unitPrice: 100000,
            imageUrl: uri,
          );

          final map = item.toMap();
          expect(map.containsKey('imageUrl'), isFalse,
              reason:
                  'Base64 image URI "$uri" must be omitted from toMap() payload');
        }
      });

      test('trims whitespace and rejects padded data:image URIs', () {
        final paddedUris = [
          '  data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=  ',
          '\t\nDATA:IMAGE/JPEG;BASE64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP...\n',
          '  \r\n  data:image/webp;base64,UklGRkAAAABXRUJQVlA4IDQAAADwAQCdASoBAAEAAQAcJaACdLoAAP7/2Q==  ',
        ];

        for (final uri in paddedUris) {
          final item = StockInReceiptItem(
            transactionId: 'tx_pad',
            productId: 'p_pad',
            quantity: 1,
            unitPrice: 50000,
            imageUrl: uri,
          );

          final map = item.toMap();
          expect(map.containsKey('imageUrl'), isFalse,
              reason: 'Padded Base64 URI "$uri" must be trimmed and stripped');
        }
      });

      test('preserves legitimate HTTP, HTTPS, and storage URLs', () {
        final validUrls = [
          'https://firebasestorage.googleapis.com/v0/b/store.appspot.com/o/product_1.png?alt=media',
          'http://cdn.store.vn/images/products/prod123.jpg',
          'https://images.unsplash.com/photo-1555041469-a586c61ea9bc',
          'gs://store.appspot.com/products/img_01.png',
        ];

        for (final url in validUrls) {
          final item = StockInReceiptItem(
            transactionId: 'tx_valid',
            productId: 'p_valid',
            quantity: 2,
            unitPrice: 75000,
            imageUrl: url,
          );

          final map = item.toMap();
          expect(map['imageUrl'], equals(url),
              reason: 'Remote URL "$url" must be preserved');
        }
      });

      test('omits imageUrl key when imageUrl is null', () {
        const itemNull = StockInReceiptItem(
          transactionId: 'tx_null',
          productId: 'p_null',
          quantity: 1,
          unitPrice: 20000,
          imageUrl: null,
        );
        expect(itemNull.toMap().containsKey('imageUrl'), isFalse);
      });
    });
  });
}
