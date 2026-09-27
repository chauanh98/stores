import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';

import '../../support/firebase_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InventoryRemoteDataSource', () {
    late MockFirebaseDatabase mockDb;
    late InventoryRemoteDataSource dataSource;
    const storeId = 'store_test_001';
    const inventoryPath = 'stores/$storeId/inventory_transactions';

    setUp(() {
      mockDb = MockFirebaseDatabase();
      dataSource = InventoryRemoteDataSource(mockDb, storeId);
    });

    group('watchAll() - Bandwidth Optimization & Reactivity', () {
      test('No double fetch: .get() is NEVER called when subscribing to watchAll()', () async {
        final ref = mockDb.getOrCreateRef(inventoryPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('inv_1', {
          'id': 'inv_1',
          'type': 'import',
          'quantity': 5,
        });

        await Future.delayed(const Duration(milliseconds: 270));
        expect(emissions.length, equals(1));

        expect(mockDb.wasGetCalled(inventoryPath), isFalse);
        expect(mockDb.getCallCount(inventoryPath), equals(0));

        await sub.cancel();
      });

      test('Debounce grouping: rapid burst of inventory transactions coalesces into 1 emission', () async {
        final ref = mockDb.getOrCreateRef(inventoryPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        for (int i = 1; i <= 25; i++) {
          ref.emitChildAdded('inv_$i', {
            'id': 'inv_$i',
            'productId': 'prod_$i',
            'quantity': i * 2,
            'type': 'import',
          });
        }

        // Before 250ms elapses
        await Future.delayed(const Duration(milliseconds: 50));
        expect(emissions, isEmpty);

        // After 250ms debounce
        await Future.delayed(const Duration(milliseconds: 230));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(25));

        await sub.cancel();
      });

      test('emptyCheckSub: empty node emits [] instead of hanging', () async {
        final ref = mockDb.getOrCreateRef(inventoryPath);
        final completer = Completer<List<Map>>();
        final sub = dataSource.watchAll().listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        });

        ref.emitNullValue();

        final result = await completer.future.timeout(const Duration(milliseconds: 150));
        expect(result, isEmpty);

        await sub.cancel();
      });

      test('Immediate emit on childChanged without waiting for debounce', () async {
        final ref = mockDb.getOrCreateRef(inventoryPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('inv_1', {'id': 'inv_1', 'quantity': 10});
        await Future.delayed(const Duration(milliseconds: 270));
        expect(emissions.length, equals(1));

        final stopwatch = Stopwatch()..start();
        ref.emitChildChanged('inv_1', {'id': 'inv_1', 'quantity': 20});
        await Future.delayed(const Duration(milliseconds: 10));
        stopwatch.stop();

        expect(emissions.length, equals(2));
        expect(emissions.last.first['quantity'], equals(20));
        expect(stopwatch.elapsedMilliseconds, lessThan(40));

        await sub.cancel();
      });

      test('Immediate emit on childRemoved: purges transaction from cache immediately', () async {
        final ref = mockDb.getOrCreateRef(inventoryPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('inv_1', {'id': 'inv_1', 'quantity': 10});
        ref.emitChildAdded('inv_2', {'id': 'inv_2', 'quantity': 20});
        await Future.delayed(const Duration(milliseconds: 270));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(2));

        ref.emitChildRemoved('inv_1');
        await Future.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, equals(2));
        expect(emissions.last.length, equals(1));
        expect(emissions.last.first['id'], equals('inv_2'));

        await sub.cancel();
      });

      test('Stream cancellation tears down listeners and cancels pending debounce', () async {
        final ref = mockDb.getOrCreateRef(inventoryPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('inv_cancel', {'id': 'inv_cancel', 'quantity': 1});
        await Future.delayed(const Duration(milliseconds: 10));

        await sub.cancel();

        expect(ref.childAddedStream.activeListeners, equals(0));
        expect(ref.childChangedStream.activeListeners, equals(0));
        expect(ref.childRemovedStream.activeListeners, equals(0));
        expect(ref.valueStream.activeListeners, equals(0));

        await Future.delayed(const Duration(milliseconds: 270));
        expect(emissions, isEmpty);
      });
    });

    group('fetchImportsByDateRange() - Bounded Queries & Fallback Elimination', () {
      final sampleTransactions = {
        'tx_before': {
          'id': 'tx_before',
          'type': 'import',
          'date': '2026-09-01T08:00:00.000Z',
          'quantity': 10,
        },
        'tx_in_import': {
          'id': 'tx_in_import',
          'type': 'import',
          'date': '2026-09-15T10:00:00.000Z',
          'quantity': 20,
        },
        'tx_in_export': {
          'id': 'tx_in_export',
          'type': 'export',
          'date': '2026-09-16T12:00:00.000Z',
          'quantity': 5,
        },
        'tx_after': {
          'id': 'tx_after',
          'type': 'import',
          'date': '2026-09-28T09:00:00.000Z',
          'quantity': 30,
        },
      };

      test('filters by date range and type == import on successful query', () async {
        mockDb.seedData(inventoryPath, sampleTransactions);

        final start = DateTime.parse('2026-09-10T00:00:00.000Z');
        final end = DateTime.parse('2026-09-20T00:00:00.000Z');

        final results = await dataSource.fetchImportsByDateRange(start, end);
        expect(results.length, equals(1));
        expect(results.first['id'], equals('tx_in_import'));
      });

      test('eliminates full collection fallback: returns empty list when query fails to protect egress quota', () async {
        mockDb.seedData(inventoryPath, sampleTransactions);
        mockDb.setSimulateQueryFailure(inventoryPath, true);

        final start = DateTime.parse('2026-09-10T00:00:00.000Z');
        final end = DateTime.parse('2026-09-20T00:00:00.000Z');

        final results = await dataSource.fetchImportsByDateRange(start, end);

        // Must NOT scan full collection via fallback; returns empty list
        expect(results, isEmpty);
        expect(mockDb.getCallCount(inventoryPath), equals(1));
      });

      test('returns empty list when both query and fallback fail', () async {
        mockDb.seedData(inventoryPath, sampleTransactions);
        mockDb.setSimulateQueryFailure(inventoryPath, true);
        mockDb.setThrowOnGet(inventoryPath, true);

        final start = DateTime.parse('2026-09-10T00:00:00.000Z');
        final end = DateTime.parse('2026-09-20T00:00:00.000Z');

        final results = await dataSource.fetchImportsByDateRange(start, end);
        expect(results, isEmpty);
      });
    });

    group('Inventory Queries & CRUD', () {
      test('record() writes inventory transaction to database', () async {
        await dataSource.record('tx_new', {
          'id': 'tx_new',
          'productId': 'p1',
          'type': 'import',
          'quantity': 50,
        });

        final snap = await mockDb.getOrCreateRef(inventoryPath).child('tx_new').get();
        expect(snap.exists, isTrue);
        expect((snap.value as Map)['quantity'], equals(50));
      });

      test('fetchAll() loads all inventory transactions', () async {
        mockDb.seedData(inventoryPath, {
          't1': {'id': 't1', 'type': 'import'},
          't2': {'id': 't2', 'type': 'export'},
        });

        final list = await dataSource.fetchAll();
        expect(list.length, equals(2));
      });

      test('watchByProduct() streams transactions matching productId', () async {
        mockDb.seedData(inventoryPath, {
          't1': {'id': 't1', 'productId': 'prod_target', 'quantity': 10},
          't2': {'id': 't2', 'productId': 'prod_other', 'quantity': 5},
          't3': {'id': 't3', 'productId': 'prod_target', 'quantity': 15},
        });

        final stream = dataSource.watchByProduct('prod_target');
        final list = await stream.first;

        expect(list.length, equals(2));
        final ids = list.map((t) => t['id']).toList();
        expect(ids, containsAll(['t1', 't3']));
      });

      test('watchImportsByDateRange() streams only import transactions in date range', () async {
        mockDb.seedData(inventoryPath, {
          't1': {'id': 't1', 'type': 'import', 'date': '2026-09-15T08:00:00.000Z'},
          't2': {'id': 't2', 'type': 'export', 'date': '2026-09-15T09:00:00.000Z'},
          't3': {'id': 't3', 'type': 'import', 'date': '2026-09-25T08:00:00.000Z'},
        });

        final start = DateTime.parse('2026-09-14T00:00:00.000Z');
        final end = DateTime.parse('2026-09-16T00:00:00.000Z');

        final stream = dataSource.watchImportsByDateRange(start, end);
        final list = await stream.first;

        expect(list.length, equals(1));
        expect(list.first['id'], equals('t1'));
      });
    });
  });
}
