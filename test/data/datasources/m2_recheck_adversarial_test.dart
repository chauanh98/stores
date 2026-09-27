import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/attendance_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/data/repositories/revenue_repository_impl.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';

import '../../support/firebase_test_harness.dart';

/// Spy Database Reference that records query constraints.
class RecheckSpyDatabaseReference extends MockDatabaseReference {
  int? recordedLimitToLast;
  int? recordedLimitToFirst;

  RecheckSpyDatabaseReference({
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

/// Custom mock database injecting [RecheckSpyDatabaseReference].
class RecheckSpyFirebaseDatabase extends MockFirebaseDatabase {
  final Map<String, RecheckSpyDatabaseReference> spyReferences = {};

  @override
  MockDatabaseReference getOrCreateRef(String path,
      {Map<String, dynamic>? initialData}) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    requestedPaths.add(cleanPath);
    return spyReferences.putIfAbsent(
      cleanPath,
      () => RecheckSpyDatabaseReference(
        path: cleanPath,
        recorder: recorder,
        initialData: initialData,
      ),
    );
  }
}

class SpyInventoryRemoteDataSource extends Fake implements InventoryRemoteDataSource {
  bool fetchTransactionsUpToDateCalled = false;
  bool fetchAllCalled = false;
  DateTime? recordedEndDate;
  int? recordedLimit;

  @override
  Future<List<Map>> fetchTransactionsUpToDate(DateTime endDate, {int limit = 100}) async {
    fetchTransactionsUpToDateCalled = true;
    recordedEndDate = endDate;
    recordedLimit = limit;
    return [];
  }

  @override
  Future<List<Map>> fetchAll() async {
    fetchAllCalled = true;
    return [];
  }
}

class FakeOrderRemoteDataSource extends Fake implements OrderRemoteDataSource {
  @override
  String get storeId => 'store_test_001';

  @override
  Stream<List<Map<String, dynamic>>> watchByDateRange(DateTime start, DateTime end) =>
      Stream.value([]);
}

class FakeProductRemoteDataSource extends Fake implements ProductRemoteDataSource {
  @override
  Future<List<Map>> fetchAll() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone M2 Recheck Adversarial Verification', () {
    late RecheckSpyFirebaseDatabase spyDb;
    const storeId = 'store_test_001';

    setUp(() {
      spyDb = RecheckSpyFirebaseDatabase();
    });

    test('1a. InventoryRemoteDataSource.fetchAll() applies limitToLast(50) and zero unconstrained gets', () async {
      final ds = InventoryRemoteDataSource(spyDb, storeId);
      const txPath = 'stores/$storeId/inventory_transactions';
      final spyRef = spyDb.getOrCreateRef(txPath) as RecheckSpyDatabaseReference;

      final items = await ds.fetchAll();
      expect(items, isEmpty);

      // Verify that limitToLast was called with 50
      expect(spyRef.recordedLimitToLast, equals(50));

      // Verify no unconstrained .get() occurred on root txPath
      final unconstrainedGets = spyDb.recorder
          .callsFor('get')
          .where((c) => c.path == txPath && c.extra == null)
          .toList();
      expect(unconstrainedGets, isEmpty);
    });

    test('1b. RevenueRepositoryImpl invokes fetchTransactionsUpToDate and does not call unconstrained fetchAll()', () async {
      final orderDs = FakeOrderRemoteDataSource();
      final invDs = SpyInventoryRemoteDataSource();
      final prodDs = FakeProductRemoteDataSource();

      final repo = RevenueRepositoryImpl(orderDs, invDs, prodDs);

      final report = await repo.getRevenueByDate(DateTime(2026, 9, 27));
      expect(report, isNotNull);

      // Verify bounded fetchTransactionsUpToDate was called, not unconstrained fetchAll
      expect(invDs.fetchTransactionsUpToDateCalled, isTrue);
      expect(invDs.fetchAllCalled, isFalse);
      expect(invDs.recordedLimit, equals(100));
      expect(invDs.recordedEndDate, equals(DateTime(2026, 9, 27, 23, 59, 59, 999)));

      // Also test getRevenueByDateRange
      invDs.fetchTransactionsUpToDateCalled = false;
      invDs.fetchAllCalled = false;
      final summary = await repo.getRevenueByDateRange(
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
      );
      expect(summary, isNotNull);
      expect(invDs.fetchTransactionsUpToDateCalled, isTrue);
      expect(invDs.fetchAllCalled, isFalse);
      expect(invDs.recordedLimit, equals(100));
      expect(invDs.recordedEndDate, equals(DateTime(2026, 9, 30, 23, 59, 59, 999)));
    });

    test('2. AttendanceRemoteDataSource.getAdjustments() enforces limitToLast(50) by default', () async {
      final ds = AttendanceRemoteDataSource(db: spyDb);
      const adjPath = 'attendance_adjustments';
      final spyRef = spyDb.getOrCreateRef(adjPath) as RecheckSpyDatabaseReference;

      await ds.getAdjustments(storeId: storeId);

      // Verify that limitToLast was called on adjustments reference
      expect(spyRef.recordedLimitToLast, equals(50));

      // Test with custom limit and boundary clamp
      await ds.getAdjustments(storeId: storeId, limit: 25);
      expect(spyRef.recordedLimitToLast, equals(25));

      await ds.getAdjustments(storeId: storeId, limit: 0);
      expect(spyRef.recordedLimitToLast, equals(50)); // Clamped to 50

      await ds.getAdjustments(storeId: storeId, limit: -5);
      expect(spyRef.recordedLimitToLast, equals(50)); // Clamped to 50
    });

    test('3. AttendanceRemoteDataSource GPS queries use stores/$storeId/gps_config specifically', () async {
      final ds = AttendanceRemoteDataSource(db: spyDb);
      const gpsConfigPath = 'stores/$storeId/gps_config';
      const storeRootPath = 'stores/$storeId';

      final config = await ds.getStoreGpsConfig(storeId);
      expect(config, isNotNull);

      // Verify that .get() was called on exact path stores/$storeId/gps_config
      final exactGpsGets = spyDb.recorder
          .callsFor('get')
          .where((c) => c.path == gpsConfigPath)
          .toList();
      expect(exactGpsGets, isNotEmpty, reason: 'Expected get() on gps_config child path');

      // Verify that .get() was NEVER called on storeRootPath (stores/$storeId) directly
      final exactRootGets = spyDb.recorder
          .callsFor('get')
          .where((c) => c.path == storeRootPath)
          .toList();
      expect(exactRootGets, isEmpty, reason: 'Root store node stores/$storeId must NEVER receive a .get() call for GPS');
    });

    test('4. StockInReceiptItem.toMap() trims and case-insensitively rejects data:image Base64 URIs', () {
      final testCases = [
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        'DATA:IMAGE/PNG;BASE64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        '   data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP...',
        ' \t DATA:IMAGE/WEBP;BASE64,UklGRkAAAABXRUJQVlA4IDQAAADwAQCdASoBAAEAAQAcJaACdLoAAP7/2Q== \n ',
        'Data:Image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjwvc3ZnPg==',
      ];

      for (final uri in testCases) {
        final item = StockInReceiptItem(
          transactionId: 'tx_1',
          productId: 'prod_1',
          productName: 'Sản phẩm thử nghiệm',
          quantity: 2,
          unitPrice: 50000,
          imageUrl: uri,
        );

        final map = item.toMap();
        expect(map.containsKey('imageUrl'), isFalse,
            reason: 'Base64 image URI "$uri" should be stripped from toMap()');
      }

      // Valid remote URLs must be preserved
      final validUrls = [
        'https://firebasestorage.googleapis.com/v0/b/store.appspot.com/o/product.png',
        'http://example.com/images/prod123.jpg',
        'images/products/item_01.png',
      ];

      for (final url in validUrls) {
        final item = StockInReceiptItem(
          transactionId: 'tx_2',
          productId: 'prod_1',
          productName: 'Sản phẩm thử nghiệm',
          quantity: 2,
          unitPrice: 50000,
          imageUrl: url,
        );

        final map = item.toMap();
        expect(map['imageUrl'], equals(url),
            reason: 'Legitimate image URL "$url" should be preserved in toMap()');
      }

      // Null imageUrl must not produce imageUrl key
      const nullItem = StockInReceiptItem(
        transactionId: 'tx_3',
        productId: 'prod_1',
        productName: 'Sản phẩm thử nghiệm',
        quantity: 2,
        unitPrice: 50000,
        imageUrl: null,
      );
      expect(nullItem.toMap().containsKey('imageUrl'), isFalse);
    });
  });
}
