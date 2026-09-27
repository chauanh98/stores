import 'dart:async';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/data/datasources/firebase/auth_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/category_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/data/repositories/revenue_repository_impl.dart';

// =============================================================================
// ADVERSARIAL MOCK CLASSES FOR FIREBASE REALTIME DATABASE
// =============================================================================

class MockDataSnapshot extends Fake implements DataSnapshot {
  @override
  final dynamic value;
  @override
  final String? key;
  @override
  final bool exists;

  MockDataSnapshot({this.value, this.key, this.exists = true});
}

class MockDatabaseEvent extends Fake implements DatabaseEvent {
  @override
  final DataSnapshot snapshot;

  MockDatabaseEvent(this.snapshot);
}

/// A custom stream helper to track subscriber counts and cancellations deterministically.
class CancellableEventStream {
  final StreamController<DatabaseEvent> _controller =
      StreamController<DatabaseEvent>.broadcast();
  int activeListeners = 0;
  int cancelCount = 0;

  Stream<DatabaseEvent> get stream {
    return Stream<DatabaseEvent>.multi((multiController) {
      activeListeners++;
      final sub = _controller.stream.listen(
        multiController.add,
        onError: multiController.addError,
        onDone: multiController.close,
      );
      multiController.onCancel = () {
        activeListeners--;
        cancelCount++;
        sub.cancel();
      };
    });
  }

  void emit(DatabaseEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void close() {
    _controller.close();
  }
}

class MockQuery extends Fake implements Query {
  @override
  final String path;
  final Map<String, dynamic> storeData;
  final String? orderedByChildKey;
  final dynamic startRange;
  final dynamic endRange;
  final CancellableEventStream? queryValueStream;

  MockQuery({
    required this.path,
    required this.storeData,
    this.orderedByChildKey,
    this.startRange,
    this.endRange,
    this.queryValueStream,
  });

  @override
  Query orderByChild(String key) {
    return MockQuery(
      path: path,
      storeData: storeData,
      orderedByChildKey: key,
      startRange: startRange,
      endRange: endRange,
      queryValueStream: queryValueStream,
    );
  }

  @override
  Query startAt(dynamic value, {String? key}) {
    return MockQuery(
      path: path,
      storeData: storeData,
      orderedByChildKey: orderedByChildKey,
      startRange: value,
      endRange: endRange,
      queryValueStream: queryValueStream,
    );
  }

  @override
  Query endAt(dynamic value, {String? key}) {
    return MockQuery(
      path: path,
      storeData: storeData,
      orderedByChildKey: orderedByChildKey,
      startRange: startRange,
      endRange: value,
      queryValueStream: queryValueStream,
    );
  }

  @override
  Query equalTo(dynamic value, {String? key}) {
    return MockQuery(
      path: path,
      storeData: storeData,
      orderedByChildKey: orderedByChildKey,
      startRange: value,
      endRange: value,
      queryValueStream: queryValueStream,
    );
  }

  @override
  Query limitToFirst(int limit) {
    return MockQuery(
      path: path,
      storeData: storeData,
      orderedByChildKey: orderedByChildKey,
      startRange: startRange,
      endRange: endRange,
      queryValueStream: queryValueStream,
    );
  }

  @override
  Query limitToLast(int limit) {
    return MockQuery(
      path: path,
      storeData: storeData,
      orderedByChildKey: orderedByChildKey,
      startRange: startRange,
      endRange: endRange,
      queryValueStream: queryValueStream,
    );
  }

  @override
  Future<DataSnapshot> get() async {
    final Map<String, dynamic> filtered = {};
    storeData.forEach((k, v) {
      if (v is Map && orderedByChildKey != null) {
        final itemVal = v[orderedByChildKey]?.toString() ?? '';
        final start = startRange?.toString();
        final end = endRange?.toString();
        bool match = true;
        if (start != null && itemVal.compareTo(start) < 0) match = false;
        if (end != null && itemVal.compareTo(end) > 0) match = false;
        if (match) filtered[k] = v;
      } else {
        filtered[k] = v;
      }
    });
    return MockDataSnapshot(
      key: path.split('/').last,
      value: filtered.isEmpty ? null : filtered,
      exists: filtered.isNotEmpty,
    );
  }

  @override
  Stream<DatabaseEvent> get onValue {
    if (queryValueStream != null) {
      return queryValueStream!.stream;
    }
    return Stream.fromFuture(get()).map((snap) => MockDatabaseEvent(snap));
  }
}

class MockDatabaseReference extends MockQuery implements DatabaseReference {
  final CancellableEventStream childAddedStream = CancellableEventStream();
  final CancellableEventStream childChangedStream = CancellableEventStream();
  final CancellableEventStream childRemovedStream = CancellableEventStream();
  final CancellableEventStream valueStream = CancellableEventStream();

  final Map<String, MockDatabaseReference> children = {};

  MockDatabaseReference({
    required super.path,
    Map<String, dynamic>? initialData,
  }) : super(storeData: initialData ?? {});

  @override
  Stream<DatabaseEvent> get onChildAdded => childAddedStream.stream;

  @override
  Stream<DatabaseEvent> get onChildChanged => childChangedStream.stream;

  @override
  Stream<DatabaseEvent> get onChildRemoved => childRemovedStream.stream;

  @override
  Stream<DatabaseEvent> get onValue => valueStream.stream;

  @override
  Query limitToFirst(int limit) {
    return MockQuery(
      path: path,
      storeData: storeData,
      orderedByChildKey: orderedByChildKey,
      startRange: startRange,
      endRange: endRange,
      queryValueStream: valueStream,
    );
  }

  @override
  Query limitToLast(int limit) {
    return MockQuery(
      path: path,
      storeData: storeData,
      orderedByChildKey: orderedByChildKey,
      startRange: startRange,
      endRange: endRange,
      queryValueStream: valueStream,
    );
  }

  @override
  DatabaseReference child(String childPath) {
    return children.putIfAbsent(
      childPath,
      () => MockDatabaseReference(
        path: '$path/$childPath',
        initialData: storeData[childPath] is Map
            ? Map<String, dynamic>.from(storeData[childPath] as Map)
            : {},
      ),
    );
  }

  @override
  Future<void> set(dynamic value) async {
    if (value is Map) {
      storeData.addAll(Map<String, dynamic>.from(value));
    }
  }

  @override
  Future<void> update(Map<String, dynamic> value) async {
    storeData.addAll(value);
  }

  @override
  Future<void> remove() async {
    storeData.clear();
  }
}

class MockFirebaseDatabase extends Fake implements FirebaseDatabase {
  final Map<String, MockDatabaseReference> references = {};
  final List<String> requestedPaths = [];

  MockDatabaseReference getOrCreateRef(String path) {
    requestedPaths.add(path);
    return references.putIfAbsent(
      path,
      () => MockDatabaseReference(path: path),
    );
  }

  @override
  DatabaseReference ref([String? path]) {
    return getOrCreateRef(path ?? '');
  }
}

// =============================================================================
// ADVERSARIAL EMPIRICAL SUITE FOR R1 BANDWIDTH & STREAM OPTIMIZATION
// =============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // GROUP 1: DEBOUNCED STREAM LOGIC (BURSTS & TIMING)
  // ---------------------------------------------------------------------------
  group('R1 - Debounced Stream Logic (Bursts & Timing)', () {
    late MockFirebaseDatabase mockDb;

    setUp(() {
      mockDb = MockFirebaseDatabase();
    });

    test('ProductRemoteDataSource: rapid burst of 50 childAdded events emits exactly once after 50ms', () async {
      final ds = ProductRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/products');

      final emissions = <List<Map>>[];
      final sub = ds.watchAll().listen(emissions.add);

      // Emit 50 items in rapid bursts
      for (int i = 1; i <= 50; i++) {
        ref.childAddedStream.emit(
          MockDatabaseEvent(
            MockDataSnapshot(
              key: 'prod_$i',
              value: {'id': 'prod_$i', 'name': 'Product $i', 'price': i * 1000},
            ),
          ),
        );
      }

      // At 20ms: Debounce timer is still ticking, should NOT have emitted yet
      await Future.delayed(const Duration(milliseconds: 20));
      expect(emissions, isEmpty, reason: 'Debounce window must coalesce rapid burst');

      // At 75ms (20ms + 55ms): Debounce timer should have elapsed and emitted exactly 1 batch
      await Future.delayed(const Duration(milliseconds: 55));
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(50));
      expect(emissions.first.map((p) => p['id']), containsAll(['prod_1', 'prod_50']));

      await sub.cancel();
    });

    test('Debounce timer resets on continuous arrivals before 50ms window elapses', () async {
      final ds = OrderRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/orders');

      final emissions = <List<Map<String, dynamic>>>[];
      final sub = ds.watchAll().listen(emissions.add);

      // Item 1 at t=0
      ref.childAddedStream.emit(MockDatabaseEvent(MockDataSnapshot(
        key: 'order_1',
        value: {'id': 'order_1', 'total': 100000.0, 'items': []},
      )));

      // Item 2 at t=25ms (resets timer)
      await Future.delayed(const Duration(milliseconds: 25));
      expect(emissions, isEmpty);
      ref.childAddedStream.emit(MockDatabaseEvent(MockDataSnapshot(
        key: 'order_2',
        value: {'id': 'order_2', 'total': 200000.0, 'items': []},
      )));

      // Item 3 at t=50ms (resets timer again)
      await Future.delayed(const Duration(milliseconds: 25));
      expect(emissions, isEmpty);
      ref.childAddedStream.emit(MockDatabaseEvent(MockDataSnapshot(
        key: 'order_3',
        value: {'id': 'order_3', 'total': 300000.0, 'items': []},
      )));

      // At t=75ms (25ms after item 3): still has not emitted
      await Future.delayed(const Duration(milliseconds: 25));
      expect(emissions, isEmpty);

      // At t=115ms (65ms after item 3): emits exactly once with all 3 orders
      await Future.delayed(const Duration(milliseconds: 40));
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(3));
      expect(emissions.first.map((o) => o['id']), containsAll(['order_1', 'order_2', 'order_3']));

      await sub.cancel();
    });

    test('InventoryRemoteDataSource: bursts of inventory transactions coalesce into single emission', () async {
      final ds = InventoryRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/inventory_transactions');

      final emissions = <List<Map>>[];
      final sub = ds.watchAll().listen(emissions.add);

      for (int i = 1; i <= 25; i++) {
        ref.childAddedStream.emit(MockDatabaseEvent(MockDataSnapshot(
          key: 'inv_$i',
          value: {'id': 'inv_$i', 'productId': 'prod_$i', 'quantity': i, 'type': 'import'},
        )));
      }

      await Future.delayed(const Duration(milliseconds: 70));
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(25));

      await sub.cancel();
    });

    test('CategoryRemoteDataSource: bursts of category updates coalesce cleanly', () async {
      final ds = CategoryRemoteDataSource(mockDb);
      final ref = mockDb.getOrCreateRef('shared_categories');

      final emissions = <List<Map>>[];
      final sub = ds.watchAll().listen(emissions.add);

      for (int i = 1; i <= 15; i++) {
        ref.childAddedStream.emit(MockDatabaseEvent(MockDataSnapshot(
          key: 'cat_$i',
          value: {'id': 'cat_$i', 'name': 'Category $i'},
        )));
      }

      await Future.delayed(const Duration(milliseconds: 70));
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(15));

      await sub.cancel();
    });

    test('AuthRemoteDataSource: bursts of user accounts emit with username properly populated', () async {
      final ds = AuthRemoteDataSource(mockDb);
      final ref = mockDb.getOrCreateRef('stores/accounts');

      final emissions = <List<Map<String, dynamic>>>[];
      final sub = ds.watchAllAccounts().listen(emissions.add);

      for (int i = 1; i <= 10; i++) {
        ref.childAddedStream.emit(MockDatabaseEvent(MockDataSnapshot(
          key: 'user_$i',
          value: {'displayName': 'User $i', 'role': 'staff', 'storeId': 'store_001'},
        )));
      }

      await Future.delayed(const Duration(milliseconds: 70));
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(10));
      expect(emissions.first.first['username'], isNotNull);
      expect(emissions.first.map((u) => u['username']), contains('user_1'));

      await sub.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  // GROUP 2: EMPTY NODE HANDLING (NO DEADLOCKS / HANGS)
  // ---------------------------------------------------------------------------
  group('R1 - Empty Node Handling (onValue.take(1) emits [] without deadlock)', () {
    late MockFirebaseDatabase mockDb;

    setUp(() {
      mockDb = MockFirebaseDatabase();
    });

    test('ProductRemoteDataSource emits [] immediately when onValue snapshot is null', () async {
      final ds = ProductRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/products');

      final completer = Completer<List<Map>>();
      final sub = ds.watchAll().listen((data) {
        if (!completer.isCompleted) completer.complete(data);
      });

      // Firebase returns null snapshot on empty node
      ref.valueStream.emit(MockDatabaseEvent(MockDataSnapshot(value: null, exists: false)));

      final result = await completer.future.timeout(const Duration(milliseconds: 100));
      expect(result, isEmpty);

      await sub.cancel();
    });

    test('OrderRemoteDataSource emits [] immediately when onValue snapshot is null', () async {
      final ds = OrderRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/orders');

      final completer = Completer<List<Map<String, dynamic>>>();
      final sub = ds.watchAll().listen((data) {
        if (!completer.isCompleted) completer.complete(data);
      });

      ref.valueStream.emit(MockDatabaseEvent(MockDataSnapshot(value: null, exists: false)));

      final result = await completer.future.timeout(const Duration(milliseconds: 100));
      expect(result, isEmpty);

      await sub.cancel();
    });

    test('InventoryRemoteDataSource emits [] immediately when onValue snapshot is null', () async {
      final ds = InventoryRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/inventory_transactions');

      final completer = Completer<List<Map>>();
      final sub = ds.watchAll().listen((data) {
        if (!completer.isCompleted) completer.complete(data);
      });

      ref.valueStream.emit(MockDatabaseEvent(MockDataSnapshot(value: null, exists: false)));

      final result = await completer.future.timeout(const Duration(milliseconds: 100));
      expect(result, isEmpty);

      await sub.cancel();
    });

    test('CategoryRemoteDataSource emits [] immediately when onValue snapshot is null', () async {
      final ds = CategoryRemoteDataSource(mockDb);
      final ref = mockDb.getOrCreateRef('shared_categories');

      final completer = Completer<List<Map>>();
      final sub = ds.watchAll().listen((data) {
        if (!completer.isCompleted) completer.complete(data);
      });

      ref.valueStream.emit(MockDatabaseEvent(MockDataSnapshot(value: null, exists: false)));

      final result = await completer.future.timeout(const Duration(milliseconds: 100));
      expect(result, isEmpty);

      await sub.cancel();
    });

    test('AuthRemoteDataSource emits [] immediately when onValue snapshot is null', () async {
      final ds = AuthRemoteDataSource(mockDb);
      final ref = mockDb.getOrCreateRef('stores/accounts');

      final completer = Completer<List<Map<String, dynamic>>>();
      final sub = ds.watchAllAccounts().listen((data) {
        if (!completer.isCompleted) completer.complete(data);
      });

      ref.valueStream.emit(MockDatabaseEvent(MockDataSnapshot(value: null, exists: false)));

      final result = await completer.future.timeout(const Duration(milliseconds: 100));
      expect(result, isEmpty);

      await sub.cancel();
    });

    test('Empty check does NOT override non-empty cache if onChildAdded emitted first', () async {
      final ds = ProductRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/products');

      final emissions = <List<Map>>[];
      final sub = ds.watchAll().listen(emissions.add);

      // Child arrives first
      ref.childAddedStream.emit(MockDatabaseEvent(MockDataSnapshot(
        key: 'prod_1',
        value: {'id': 'prod_1', 'name': 'Item 1'},
      )));

      // Wait 60ms for debounce timer to emit
      await Future.delayed(const Duration(milliseconds: 60));
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(1));

      // Belated null onValue event should NOT clear the cache or emit []
      ref.valueStream.emit(MockDatabaseEvent(MockDataSnapshot(value: null, exists: false)));
      await Future.delayed(const Duration(milliseconds: 20));

      expect(emissions.length, equals(1), reason: 'Null onValue must not wipe existing cached items');
      expect(emissions.first.first['id'], equals('prod_1'));

      await sub.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  // GROUP 3: SUBSEQUENT MODIFICATIONS & REMOVALS EMIT IMMEDIATELY
  // ---------------------------------------------------------------------------
  group('R1 - Subsequent Modifications & Removals Emit Immediately', () {
    late MockFirebaseDatabase mockDb;

    setUp(() {
      mockDb = MockFirebaseDatabase();
    });

    test('onChildChanged emits immediately without 50ms debounce wait', () async {
      final ds = ProductRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/products');

      final emissions = <List<Map>>[];
      final sub = ds.watchAll().listen(emissions.add);

      // Initial item
      ref.childAddedStream.emit(MockDatabaseEvent(MockDataSnapshot(
        key: 'prod_1',
        value: {'id': 'prod_1', 'name': 'Item 1', 'price': 10000},
      )));
      await Future.delayed(const Duration(milliseconds: 60));
      expect(emissions.length, equals(1));

      // Modify item
      final stopwatch = Stopwatch()..start();
      ref.childChangedStream.emit(MockDatabaseEvent(MockDataSnapshot(
        key: 'prod_1',
        value: {'id': 'prod_1', 'name': 'Item 1 Updated', 'price': 15000},
      )));

      // Wait 10ms only (much less than 50ms debounce)
      await Future.delayed(const Duration(milliseconds: 10));
      stopwatch.stop();

      expect(emissions.length, equals(2), reason: 'Child updates must emit immediately');
      expect(emissions.last.first['name'], equals('Item 1 Updated'));
      expect(emissions.last.first['price'], equals(15000));
      expect(stopwatch.elapsedMilliseconds, lessThan(40));

      await sub.cancel();
    });

    test('onChildRemoved emits immediately and purges item from cache', () async {
      final ds = OrderRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/orders');

      final emissions = <List<Map<String, dynamic>>>[];
      final sub = ds.watchAll().listen(emissions.add);

      // Add two orders
      ref.childAddedStream.emit(MockDatabaseEvent(MockDataSnapshot(
        key: 'order_1',
        value: {'id': 'order_1', 'total': 50000.0},
      )));
      ref.childAddedStream.emit(MockDatabaseEvent(MockDataSnapshot(
        key: 'order_2',
        value: {'id': 'order_2', 'total': 75000.0},
      )));

      await Future.delayed(const Duration(milliseconds: 60));
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(2));

      // Remove order_1
      ref.childRemovedStream.emit(MockDatabaseEvent(MockDataSnapshot(
        key: 'order_1',
        value: null,
      )));

      // Within 10ms
      await Future.delayed(const Duration(milliseconds: 10));
      expect(emissions.length, equals(2));
      expect(emissions.last.length, equals(1));
      expect(emissions.last.first['id'], equals('order_2'));

      await sub.cancel();
    });

    test('Removal by key cleans up correctly when id matches key', () async {
      final ds = InventoryRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/inventory_transactions');

      final emissions = <List<Map>>[];
      final sub = ds.watchAll().listen(emissions.add);

      ref.childAddedStream.emit(MockDatabaseEvent(MockDataSnapshot(
        key: 'inv_100',
        value: {'id': 'inv_100', 'quantity': 10},
      )));

      await Future.delayed(const Duration(milliseconds: 60));
      expect(emissions.length, equals(1));

      ref.childRemovedStream.emit(MockDatabaseEvent(MockDataSnapshot(
        key: 'inv_100',
        value: null,
      )));

      await Future.delayed(const Duration(milliseconds: 10));
      expect(emissions.length, equals(2));
      expect(emissions.last, isEmpty);

      await sub.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  // GROUP 4: SAFE UNMOUNT / CANCEL BEHAVIOR & RESOURCE DISPOSAL
  // ---------------------------------------------------------------------------
  group('R1 - Safe Unmount / Cancel Behavior (No Memory Leaks / Cancelled Timers)', () {
    late MockFirebaseDatabase mockDb;

    setUp(() {
      mockDb = MockFirebaseDatabase();
    });

    test('Debounce timer is cancelled when subscription is cancelled before 50ms', () async {
      final ds = ProductRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/products');

      final emissions = <List<Map>>[];
      final sub = ds.watchAll().listen(emissions.add);

      // Add item (starts 50ms timer)
      ref.childAddedStream.emit(MockDatabaseEvent(MockDataSnapshot(
        key: 'prod_cancel',
        value: {'id': 'prod_cancel', 'name': 'Cancel Me'},
      )));

      // Cancel at 10ms (before timer fires)
      await Future.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      // Wait 70ms past the initial debounce schedule
      await Future.delayed(const Duration(milliseconds: 70));

      expect(emissions, isEmpty, reason: 'Cancelled subscription must not emit delayed timer events');
    });

    test('Underlying stream listeners are all cancelled when watchAll() is cancelled', () async {
      final ds = ProductRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/products');

      final sub = ds.watchAll().listen((_) {});

      // Verify active listeners connected
      expect(ref.childAddedStream.activeListeners, equals(1));
      expect(ref.childChangedStream.activeListeners, equals(1));
      expect(ref.childRemovedStream.activeListeners, equals(1));
      expect(ref.valueStream.activeListeners, equals(1));

      // Cancel subscription
      await sub.cancel();

      // Verify all listeners cleanly detached
      expect(ref.childAddedStream.activeListeners, equals(0));
      expect(ref.childChangedStream.activeListeners, equals(0));
      expect(ref.childRemovedStream.activeListeners, equals(0));
      expect(ref.valueStream.activeListeners, equals(0));
    });

    test('Stress test: Rapid subscribe and unsubscribe loop (50 cycles) produces no errors or leaks', () async {
      final ds = OrderRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/orders');

      for (int cycle = 0; cycle < 50; cycle++) {
        final sub = ds.watchAll().listen((_) {});
        ref.childAddedStream.emit(MockDatabaseEvent(MockDataSnapshot(
          key: 'order_$cycle',
          value: {'id': 'order_$cycle', 'total': cycle * 1000.0},
        )));
        // Immediate or near-immediate unmount
        await sub.cancel();
      }

      // Allow any stray event loop ticks to settle
      await Future.delayed(const Duration(milliseconds: 80));

      expect(ref.childAddedStream.activeListeners, equals(0));
      expect(ref.childChangedStream.activeListeners, equals(0));
      expect(ref.childRemovedStream.activeListeners, equals(0));
      expect(ref.valueStream.activeListeners, equals(0));
    });
  });

  // ---------------------------------------------------------------------------
  // GROUP 5: BOUNDED INVENTORY DATE QUERIES & REVENUE REPORTING FALLBACK
  // ---------------------------------------------------------------------------
  group('R1 - Bounded fetchImportsByDateRange & Revenue Fallback Calculations', () {
    late MockFirebaseDatabase mockDb;

    setUp(() {
      mockDb = MockFirebaseDatabase();
    });

    test('fetchImportsByDateRange filters by date range and type == import', () async {
      final inventoryData = <String, dynamic>{
        'tx_1': {
          'id': 'tx_1',
          'type': 'import',
          'productId': 'p1',
          'quantity': 10,
          'date': '2026-09-01T08:00:00.000Z', // Before range
          'importPrice': 50000.0,
        },
        'tx_2': {
          'id': 'tx_2',
          'type': 'import',
          'productId': 'p1',
          'quantity': 20,
          'date': '2026-09-12T10:00:00.000Z', // Inside range
          'importPrice': 52000.0,
        },
        'tx_3': {
          'id': 'tx_3',
          'type': 'export', // Non-import inside range
          'productId': 'p1',
          'quantity': 5,
          'date': '2026-09-15T14:00:00.000Z',
        },
        'tx_4': {
          'id': 'tx_4',
          'type': 'import',
          'productId': 'p2',
          'quantity': 15,
          'date': '2026-09-18T16:00:00.000Z', // Inside range
          'importPrice': 70000.0,
        },
        'tx_5': {
          'id': 'tx_5',
          'type': 'import',
          'productId': 'p2',
          'quantity': 30,
          'date': '2026-09-25T09:00:00.000Z', // After range
          'importPrice': 75000.0,
        },
      };

      final ref = MockDatabaseReference(
        path: 'stores/store_001/inventory_transactions',
        initialData: inventoryData,
      );
      mockDb.references['stores/store_001/inventory_transactions'] = ref;

      final ds = InventoryRemoteDataSource(mockDb, 'store_001');

      final start = DateTime.parse('2026-09-10T00:00:00.000Z');
      final end = DateTime.parse('2026-09-20T23:59:59.999Z');

      final results = await ds.fetchImportsByDateRange(start, end);

      expect(results.length, equals(2), reason: 'Only imports within range must be returned');
      final ids = results.map((r) => r['id']).toList();
      expect(ids, containsAll(['tx_2', 'tx_4']));
      expect(ids, isNot(contains('tx_1')));
      expect(ids, isNot(contains('tx_3')));
      expect(ids, isNot(contains('tx_5')));
    });

    test('RevenueRepositoryImpl: FIFO lots used when imports exist in range', () {
      final orderDs = OrderRemoteDataSource(mockDb, 'store_001');
      final inventoryDs = InventoryRemoteDataSource(mockDb, 'store_001');
      final productDs = ProductRemoteDataSource(mockDb, 'store_001');

      final repo = RevenueRepositoryImpl(orderDs, inventoryDs, productDs);

      final products = [
        {'id': 'p_fifo', 'name': 'FIFO Item', 'price': 100000.0, 'costPrice': 40000.0},
      ];

      final inventoryTxs = [
        {
          'id': 'inv_1',
          'productId': 'p_fifo',
          'quantity': 5,
          'type': 'import',
          'importPrice': 60000.0, // Specific lot price in range
          'date': '2026-09-15T08:00:00.000Z',
          'storeId': 'store_001',
        },
      ];

      final orders = [
        {
          'id': 'ord_1',
          'createdAt': '2026-09-15T10:00:00.000Z',
          'total': 200000.0,
          'status': 'completed',
          'items': [
            {
              'productId': 'p_fifo',
              'productName': 'FIFO Item',
              'quantity': 2,
              'price': 100000.0,
              'warrantyMonths': 0,
              'purchaseDate': '2026-09-15T10:00:00.000Z',
            },
          ],
        },
      ];

      final report = repo.calculateRevenueReport(
        orders: orders,
        inventoryTransactions: inventoryTxs,
        products: products,
        date: DateTime.parse('2026-09-15'),
      );

      expect(report.totalRevenue, equals(200000.0));
      // Cost should be 2 * 60,000 = 120,000 (from lot), NOT fallback 40,000
      expect(report.totalCost, equals(120000.0));
      expect(report.profit, equals(80000.0));
      expect(report.totalOrders, equals(1));
      expect(report.totalItemsSold, equals(2));
    });

    test('RevenueRepositoryImpl: Falls back to product.costPrice when no imports exist in range', () {
      final orderDs = OrderRemoteDataSource(mockDb, 'store_001');
      final inventoryDs = InventoryRemoteDataSource(mockDb, 'store_001');
      final productDs = ProductRemoteDataSource(mockDb, 'store_001');

      final repo = RevenueRepositoryImpl(orderDs, inventoryDs, productDs);

      final products = [
        {'id': 'p_fallback', 'name': 'Fallback Item', 'price': 100000.0, 'costPrice': 55000.0},
      ];

      // No imports in bounded range for p_fallback
      final inventoryTxs = <Map>[];

      final orders = [
        {
          'id': 'ord_2',
          'createdAt': '2026-09-15T12:00:00.000Z',
          'total': 300000.0,
          'status': 'completed',
          'items': [
            {
              'productId': 'p_fallback',
              'productName': 'Fallback Item',
              'quantity': 3,
              'price': 100000.0,
              'warrantyMonths': 0,
              'purchaseDate': '2026-09-15T12:00:00.000Z',
            },
          ],
        },
      ];

      final report = repo.calculateRevenueReport(
        orders: orders,
        inventoryTransactions: inventoryTxs,
        products: products,
        date: DateTime.parse('2026-09-15'),
      );

      expect(report.totalRevenue, equals(300000.0));
      // Cost should fallback to 3 * 55,000 = 165,000
      expect(report.totalCost, equals(165000.0));
      expect(report.profit, equals(135000.0));
    });

    test('RevenueRepositoryImpl: Falls back to 70% of price when costPrice is absent and no imports', () {
      final orderDs = OrderRemoteDataSource(mockDb, 'store_001');
      final inventoryDs = InventoryRemoteDataSource(mockDb, 'store_001');
      final productDs = ProductRemoteDataSource(mockDb, 'store_001');

      final repo = RevenueRepositoryImpl(orderDs, inventoryDs, productDs);

      final products = [
        {'id': 'p_noprice', 'name': 'No Cost Price Item', 'price': 200000.0, 'costPrice': null},
      ];

      final inventoryTxs = <Map>[];

      final orders = [
        {
          'id': 'ord_3',
          'createdAt': '2026-09-15T14:00:00.000Z',
          'total': 200000.0,
          'status': 'completed',
          'items': [
            {
              'productId': 'p_noprice',
              'productName': 'No Cost Price Item',
              'quantity': 1,
              'price': 200000.0,
              'warrantyMonths': 0,
              'purchaseDate': '2026-09-15T14:00:00.000Z',
            },
          ],
        },
      ];

      final report = repo.calculateRevenueReport(
        orders: orders,
        inventoryTransactions: inventoryTxs,
        products: products,
        date: DateTime.parse('2026-09-15'),
      );

      expect(report.totalRevenue, equals(200000.0));
      // Fallback is 70% of 200,000 = 140,000
      expect(report.totalCost, equals(140000.0));
      expect(report.profit, equals(60000.0));
    });

    test('calculateRevenueSummary accurately preserves FIFO across multiple consecutive days', () {
      final orderDs = OrderRemoteDataSource(mockDb, 'store_001');
      final inventoryDs = InventoryRemoteDataSource(mockDb, 'store_001');
      final productDs = ProductRemoteDataSource(mockDb, 'store_001');

      final repo = RevenueRepositoryImpl(orderDs, inventoryDs, productDs);

      final products = [
        {'id': 'p1', 'name': 'Product 1', 'price': 100000.0, 'costPrice': 50000.0},
      ];

      // Two lots: Lot 1 has 2 units @ 30k, Lot 2 has 5 units @ 40k
      final inventoryTxs = [
        {
          'id': 'inv_lot1',
          'productId': 'p1',
          'quantity': 2,
          'type': 'import',
          'importPrice': 30000.0,
          'date': '2026-09-15T07:00:00.000Z',
          'storeId': 'store_001',
        },
        {
          'id': 'inv_lot2',
          'productId': 'p1',
          'quantity': 5,
          'type': 'import',
          'importPrice': 40000.0,
          'date': '2026-09-15T08:00:00.000Z',
          'storeId': 'store_001',
        },
      ];

      // Day 1 sells 2 units (depletes lot 1 completely)
      // Day 2 sells 2 units (should consume from lot 2 @ 40k, NOT reset to lot 1)
      final orders = [
        {
          'id': 'ord_day1',
          'createdAt': '2026-09-15T10:00:00.000Z',
          'total': 200000.0,
          'status': 'completed',
          'items': [
            {
              'productId': 'p1',
              'productName': 'Product 1',
              'quantity': 2,
              'price': 100000.0,
              'warrantyMonths': 0,
              'purchaseDate': '2026-09-15T10:00:00.000Z',
            },
          ],
        },
        {
          'id': 'ord_day2',
          'createdAt': '2026-09-16T10:00:00.000Z',
          'total': 200000.0,
          'status': 'completed',
          'items': [
            {
              'productId': 'p1',
              'productName': 'Product 1',
              'quantity': 2,
              'price': 100000.0,
              'warrantyMonths': 0,
              'purchaseDate': '2026-09-16T10:00:00.000Z',
            },
          ],
        },
      ];

      final summary = repo.calculateRevenueSummary(
        orders: orders,
        inventoryTransactions: inventoryTxs,
        products: products,
        startDate: DateTime.parse('2026-09-15'),
        endDate: DateTime.parse('2026-09-16'),
      );

      expect(summary.totalRevenue, equals(400000.0));
      // Day 1 cost: 2 * 30k = 60k
      // Day 2 cost: 2 * 40k = 80k
      // Total cost = 140k
      expect(summary.totalCost, equals(140000.0));
      expect(summary.totalProfit, equals(260000.0));
      expect(summary.totalOrders, equals(2));
      expect(summary.totalItemsSold, equals(4));
      expect(summary.dailyReports.length, equals(2));
    });
  });

  // ---------------------------------------------------------------------------
  // GROUP 6: STATIC INTEGRITY & ARCHITECTURAL VERIFICATION
  // ---------------------------------------------------------------------------
  group('R1 - Static Integrity & Absence of ref(\'stores\').get()', () {
    test('Zero occurrences of ref(\'stores\').get() across entire lib/ codebase', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib directory must exist');

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final violations = <String>[];

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        if (content.contains("ref('stores').get()") ||
            content.contains('ref("stores").get()') ||
            content.contains("ref('stores')") ||
            content.contains('ref("stores")')) {
          violations.add('${file.path}: contains unindexed root stores reference');
        }
      }

      expect(violations, isEmpty, reason: 'Unindexed ref(\'stores\') queries must be completely eliminated');
    });

    test('main.dart configures Firebase persistence disabled to prevent OOM crash', () {
      final mainFile = File('lib/main.dart');
      expect(mainFile.existsSync(), isTrue);

      final content = mainFile.readAsStringSync();
      expect(content.contains('setPersistenceEnabled(false)'), isTrue,
          reason: 'Offline persistence must be disabled to prevent OOM crash');
      expect(content.contains('setPersistenceCacheSizeBytes'), isFalse,
          reason: 'Persistence cache size must not be configured when persistence is disabled');
    });

    test('OverviewTimeRange defaults to today in overview_providers.dart', () {
      expect(OverviewTimeRange.today.name, equals('today'));
      expect(OverviewTimeRange.today.label, equals('Hôm nay'));

      final overviewFile = File('lib/application/reports/overview_providers.dart');
      expect(overviewFile.existsSync(), isTrue);

      final content = overviewFile.readAsStringSync();
      expect(content.contains('if (user == null) return OverviewTimeRange.today;'), isTrue);
      expect(content.contains('return OverviewTimeRange.today;'), isTrue);
    });
  });
}
