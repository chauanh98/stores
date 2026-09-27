import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';

import '../../support/firebase_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OrderRemoteDataSource', () {
    late MockFirebaseDatabase mockDb;
    late OrderRemoteDataSource dataSource;
    const storeId = 'store_test_001';
    const ordersPath = 'stores/$storeId/orders';
    const returnsPath = 'stores/$storeId/return_orders';

    setUp(() {
      mockDb = MockFirebaseDatabase();
      dataSource = OrderRemoteDataSource(mockDb, storeId);
    });

    group('watchAll() - Bandwidth Optimization & Reactivity', () {
      test('No double fetch: .get() is NEVER called when subscribing to watchAll()', () async {
        final ref = mockDb.getOrCreateRef(ordersPath);
        final emissions = <List<Map<String, dynamic>>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('order_1', {
          'id': 'order_1',
          'total': 150000.0,
          'createdAt': '2026-09-19T08:00:00.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 270));
        expect(emissions.length, equals(1));

        // Must NEVER call .get() on orders node
        expect(mockDb.wasGetCalled(ordersPath), isFalse);
        expect(mockDb.getCallCount(ordersPath), equals(0));

        await sub.cancel();
      });

      test('Debounce grouping: rapid burst of childAdded events coalesces into 1 emission', () async {
        final ref = mockDb.getOrCreateRef(ordersPath);
        final emissions = <List<Map<String, dynamic>>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        for (int i = 1; i <= 30; i++) {
          ref.emitChildAdded('ord_$i', {
            'id': 'ord_$i',
            'total': i * 10000.0,
          });
        }

        // Before 250ms elapses
        await Future.delayed(const Duration(milliseconds: 50));
        expect(emissions, isEmpty);

        // After 250ms debounce
        await Future.delayed(const Duration(milliseconds: 230));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(30));

        await sub.cancel();
      });

      test('emptyCheckSub: empty node emits [] instead of hanging or waiting forever', () async {
        final ref = mockDb.getOrCreateRef(ordersPath);
        final completer = Completer<List<Map<String, dynamic>>>();
        final sub = dataSource.watchAll().listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        });

        ref.emitNullValue();

        final result = await completer.future.timeout(const Duration(milliseconds: 150));
        expect(result, isEmpty);

        await sub.cancel();
      });

      test('Immediate emit on childChanged without waiting for debounce', () async {
        final ref = mockDb.getOrCreateRef(ordersPath);
        final emissions = <List<Map<String, dynamic>>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('ord_1', {'id': 'ord_1', 'status': 'draft', 'total': 100000.0});
        await Future.delayed(const Duration(milliseconds: 270));
        expect(emissions.length, equals(1));

        final stopwatch = Stopwatch()..start();
        ref.emitChildChanged('ord_1', {'id': 'ord_1', 'status': 'completed', 'total': 100000.0});
        await Future.delayed(const Duration(milliseconds: 10));
        stopwatch.stop();

        expect(emissions.length, equals(2));
        expect(emissions.last.first['status'], equals('completed'));
        expect(stopwatch.elapsedMilliseconds, lessThan(40));

        await sub.cancel();
      });

      test('Immediate emit on childRemoved: purges order from cache immediately', () async {
        final ref = mockDb.getOrCreateRef(ordersPath);
        final emissions = <List<Map<String, dynamic>>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('ord_1', {'id': 'ord_1', 'total': 100000.0});
        ref.emitChildAdded('ord_2', {'id': 'ord_2', 'total': 200000.0});
        await Future.delayed(const Duration(milliseconds: 270));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(2));

        ref.emitChildRemoved('ord_1');
        await Future.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, equals(2));
        expect(emissions.last.length, equals(1));
        expect(emissions.last.first['id'], equals('ord_2'));

        await sub.cancel();
      });

      test('Stream cancellation tears down all 4 listeners properly', () async {
        final ref = mockDb.getOrCreateRef(ordersPath);
        final sub = dataSource.watchAll().listen((_) {});

        expect(ref.childAddedStream.activeListeners, equals(1));
        expect(ref.childChangedStream.activeListeners, equals(1));
        expect(ref.childRemovedStream.activeListeners, equals(1));
        expect(ref.valueStream.activeListeners, equals(1));

        await sub.cancel();

        expect(ref.childAddedStream.activeListeners, equals(0));
        expect(ref.childChangedStream.activeListeners, equals(0));
        expect(ref.childRemovedStream.activeListeners, equals(0));
        expect(ref.valueStream.activeListeners, equals(0));
      });
    });

    group('fetchByDateRange() - Bounded Queries & Fallback Elimination', () {
      final sampleOrders = {
        'ord_before': {
          'id': 'ord_before',
          'total': 100000.0,
          'createdAt': '2026-09-01T10:00:00.000Z',
        },
        'ord_in_1': {
          'id': 'ord_in_1',
          'total': 200000.0,
          'createdAt': '2026-09-15T10:00:00.000Z',
        },
        'ord_in_2': {
          'id': 'ord_in_2',
          'total': 300000.0,
          'createdAt': '2026-09-16T15:30:00.000Z',
        },
        'ord_after': {
          'id': 'ord_after',
          'total': 400000.0,
          'createdAt': '2026-09-25T10:00:00.000Z',
        },
      };

      test('fetches orders within date range on successful ordered query', () async {
        mockDb.seedData(ordersPath, sampleOrders);

        final start = DateTime.parse('2026-09-15T00:00:00.000Z');
        final end = DateTime.parse('2026-09-17T00:00:00.000Z');

        final results = await dataSource.fetchByDateRange(start, end);
        expect(results.length, equals(2));
        final ids = results.map((o) => o['id']).toList();
        expect(ids, containsAll(['ord_in_1', 'ord_in_2']));
        expect(ids, isNot(contains('ord_before')));
        expect(ids, isNot(contains('ord_after')));
      });

      test('eliminates full collection fallback: returns empty list when query throws to protect egress quota', () async {
        mockDb.seedData(ordersPath, sampleOrders);
        // Simulate missing index error on orderByChild
        mockDb.setSimulateQueryFailure(ordersPath, true);

        final start = DateTime.parse('2026-09-15T00:00:00.000Z');
        final end = DateTime.parse('2026-09-17T00:00:00.000Z');

        final results = await dataSource.fetchByDateRange(start, end);

        // Must NOT scan full collection via .get() fallback; returns empty list
        expect(results, isEmpty);
        // Only the initial bounded query was attempted (call count 1), no second fallback .get()
        expect(mockDb.getCallCount(ordersPath), equals(1));
      });

      test('returns empty list when both query and fallback fail', () async {
        mockDb.seedData(ordersPath, sampleOrders);
        mockDb.setSimulateQueryFailure(ordersPath, true);
        mockDb.setThrowOnGet(ordersPath, true);

        final start = DateTime.parse('2026-09-15T00:00:00.000Z');
        final end = DateTime.parse('2026-09-17T00:00:00.000Z');

        final results = await dataSource.fetchByDateRange(start, end);
        expect(results, isEmpty);
      });
    });

    group('Return Orders & Customer Queries', () {
      test('watchReturnsByDateRange streams return orders filtered by date', () async {
        mockDb.seedData(returnsPath, {
          'ret_1': {
            'id': 'ret_1',
            'orderId': 'ord_1',
            'createdAt': '2026-09-15T12:00:00.000Z',
            'refundAmount': 50000.0,
          },
          'ret_2': {
            'id': 'ret_2',
            'orderId': 'ord_2',
            'createdAt': '2026-09-22T12:00:00.000Z',
            'refundAmount': 70000.0,
          },
        });

        final start = DateTime.parse('2026-09-14T00:00:00.000Z');
        final end = DateTime.parse('2026-09-16T00:00:00.000Z');

        final stream = dataSource.watchReturnsByDateRange(start, end);
        final list = await stream.first;

        expect(list.length, equals(1));
        expect(list.first['id'], equals('ret_1'));
      });

      test('watchReturnsByOrderId streams return orders for specific order', () async {
        mockDb.seedData(returnsPath, {
          'ret_1': {'id': 'ret_1', 'orderId': 'ord_100', 'refundAmount': 30000.0},
          'ret_2': {'id': 'ret_2', 'orderId': 'ord_200', 'refundAmount': 40000.0},
          'ret_3': {'id': 'ret_3', 'orderId': 'ord_100', 'refundAmount': 15000.0},
        });

        final stream = dataSource.watchReturnsByOrderId('ord_100');
        final list = await stream.first;

        expect(list.length, equals(2));
        final ids = list.map((r) => r['id']).toList();
        expect(ids, containsAll(['ret_1', 'ret_3']));
      });

      test('watchByCustomer streams orders matching customerId', () async {
        mockDb.seedData(ordersPath, {
          'ord_c1': {'id': 'ord_c1', 'customerId': 'cust_A', 'total': 100000.0},
          'ord_c2': {'id': 'ord_c2', 'customerId': 'cust_B', 'total': 200000.0},
        });

        final stream = dataSource.watchByCustomer('cust_A');
        final list = await stream.first;

        expect(list.length, equals(1));
        expect(list.first['id'], equals('ord_c1'));
      });

      test('createReturn() and fetchReturnById() operations', () async {
        await dataSource.createReturn('ret_new', {
          'id': 'ret_new',
          'orderId': 'ord_99',
          'refundAmount': 60000.0,
        });

        final result = await dataSource.fetchReturnById('ret_new');
        expect(result, isNotNull);
        expect(result!['refundAmount'], equals(60000.0));

        final absent = await dataSource.fetchReturnById('non_existent');
        expect(absent, isNull);
      });
    });

    group('Order CRUD Operations', () {
      test('create() writes order to database', () async {
        await dataSource.create('ord_new', {
          'id': 'ord_new',
          'total': 120000.0,
          'status': 'draft',
        });

        final snap = await mockDb.getOrCreateRef(ordersPath).child('ord_new').get();
        expect(snap.exists, isTrue);
        expect((snap.value as Map)['total'], equals(120000.0));
      });

      test('update() modifies order fields', () async {
        mockDb.seedData(ordersPath, {
          'ord_up': {'id': 'ord_up', 'status': 'draft', 'total': 50000.0},
        });

        await dataSource.update('ord_up', {'status': 'completed'});

        final snap = await mockDb.getOrCreateRef(ordersPath).child('ord_up').get();
        expect((snap.value as Map)['status'], equals('completed'));
        expect((snap.value as Map)['total'], equals(50000.0));
      });

      test('delete() removes order from database', () async {
        mockDb.seedData(ordersPath, {
          'ord_del': {'id': 'ord_del', 'total': 30000.0},
        });

        await dataSource.delete('ord_del');

        final snap = await mockDb.getOrCreateRef(ordersPath).child('ord_del').get();
        expect(snap.exists, isFalse);
      });

      test('fetchById() returns order data if exists, null otherwise', () async {
        mockDb.seedData(ordersPath, {
          'ord_find': {'id': 'ord_find', 'total': 88000.0},
        });

        final found = await dataSource.fetchById('ord_find');
        expect(found, isNotNull);
        expect(found!['total'], equals(88000.0));

        final notFound = await dataSource.fetchById('ord_missing');
        expect(notFound, isNull);
      });
    });
  });
}
