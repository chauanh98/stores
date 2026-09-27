import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';

import '../../support/firebase_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProductRemoteDataSource', () {
    late MockFirebaseDatabase mockDb;
    late ProductRemoteDataSource dataSource;
    const storeId = 'store_test_001';
    const productPath = 'stores/$storeId/products';

    setUp(() {
      mockDb = MockFirebaseDatabase();
      dataSource = ProductRemoteDataSource(mockDb, storeId);
    });

    group('watchAll() - Bandwidth Optimization & Reactivity', () {
      test(
          'No double fetch: .get() is NEVER called when subscribing to watchAll()',
          () async {
        final ref = mockDb.getOrCreateRef(productPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        // Emit child events
        ref.emitChildAdded(
            'p1', {'id': 'p1', 'name': 'Product 1', 'price': 10000});

        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));

        // Verify .get() was NEVER invoked on products path
        expect(mockDb.wasGetCalled(productPath), isFalse);
        expect(mockDb.getCallCount(productPath), equals(0));

        await sub.cancel();
      });

      test(
          'Debounce grouping: rapid burst of 50 childAdded events results in exactly 1 initial emission',
          () async {
        final ref = mockDb.getOrCreateRef(productPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        // Emit 50 items rapidly
        for (int i = 1; i <= 50; i++) {
          ref.emitChildAdded('p_$i', {
            'id': 'p_$i',
            'name': 'Product $i',
            'price': i * 5000,
          });
        }

        // Before 50ms debounce window expires (e.g. at 20ms) -> no emission
        await Future.delayed(const Duration(milliseconds: 20));
        expect(emissions, isEmpty,
            reason: 'Rapid burst must be coalesced by debounce');

        // After debounce window (at 75ms total) -> exactly 1 emission with 50 items
        await Future.delayed(const Duration(milliseconds: 55));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(50));
        expect(
            emissions.first.map((p) => p['id']), containsAll(['p_1', 'p_50']));

        await sub.cancel();
      });

      test(
          'emptyCheckSub: empty node emits [] instead of hanging or waiting forever',
          () async {
        final ref = mockDb.getOrCreateRef(productPath);
        final completer = Completer<List<Map>>();
        final sub = dataSource.watchAll().listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        });

        // Firebase RTDB emits null value snapshot when the node is empty
        ref.emitNullValue();

        final result =
            await completer.future.timeout(const Duration(milliseconds: 150));
        expect(result, isEmpty);

        await sub.cancel();
      });

      test('Immediate emit on childChanged: does not wait for 50ms debounce',
          () async {
        final ref = mockDb.getOrCreateRef(productPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        // Initial add
        ref.emitChildAdded(
            'p1', {'id': 'p1', 'name': 'Original Name', 'price': 20000});
        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));

        // Update item
        final stopwatch = Stopwatch()..start();
        ref.emitChildChanged(
            'p1', {'id': 'p1', 'name': 'Updated Name', 'price': 25000});

        // Should emit immediately (wait only 10ms)
        await Future.delayed(const Duration(milliseconds: 10));
        stopwatch.stop();

        expect(emissions.length, equals(2));
        expect(emissions.last.first['name'], equals('Updated Name'));
        expect(emissions.last.first['price'], equals(25000));
        expect(stopwatch.elapsedMilliseconds, lessThan(40));

        await sub.cancel();
      });

      test(
          'Immediate emit on childRemoved: removes by key and purges cache immediately',
          () async {
        final ref = mockDb.getOrCreateRef(productPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('p1', {'id': 'p1', 'name': 'Product 1'});
        ref.emitChildAdded('p2', {'id': 'p2', 'name': 'Product 2'});
        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(2));

        // Remove p1 by key
        ref.emitChildRemoved('p1');
        await Future.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, equals(2));
        expect(emissions.last.length, equals(1));
        expect(emissions.last.first['id'], equals('p2'));

        await sub.cancel();
      });

      test(
          'Immediate emit on childRemoved: removes by id when id matches event key',
          () async {
        final ref = mockDb.getOrCreateRef(productPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        // Record with explicit id matching key
        ref.emitChildAdded(
            'custom_key', {'id': 'custom_key', 'name': 'Item X'});
        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.first.length, equals(1));

        ref.emitChildRemoved('custom_key');
        await Future.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, equals(2));
        expect(emissions.last, isEmpty);

        await sub.cancel();
      });

      test(
          'Stream cancellation teardown: detaches all 4 listeners and cancels timer',
          () async {
        final ref = mockDb.getOrCreateRef(productPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        // Verify listeners attached
        expect(ref.childAddedStream.activeListeners, equals(1));
        expect(ref.childChangedStream.activeListeners, equals(1));
        expect(ref.childRemovedStream.activeListeners, equals(1));
        expect(ref.valueStream.activeListeners, equals(1));

        // Trigger debounce timer
        ref.emitChildAdded(
            'p_cancelling', {'id': 'p_cancelling', 'name': 'Will Cancel'});
        await Future.delayed(const Duration(milliseconds: 10));

        // Cancel before debounce fires
        await sub.cancel();

        // Verify all underlying listeners detached
        expect(ref.childAddedStream.activeListeners, equals(0));
        expect(ref.childChangedStream.activeListeners, equals(0));
        expect(ref.childRemovedStream.activeListeners, equals(0));
        expect(ref.valueStream.activeListeners, equals(0));

        // Wait past debounce schedule -> no emission should leak
        await Future.delayed(const Duration(milliseconds: 70));
        expect(emissions, isEmpty);
      });
    });

    group('CRUD & Fetch Methods', () {
      test('fetchAll() loads and parses products from map snapshot', () async {
        mockDb.seedData(productPath, {
          'p1': {'id': 'p1', 'name': 'P1', 'price': 1000},
          'p2': {'id': 'p2', 'name': 'P2', 'price': 2000},
        });

        final list = await dataSource.fetchAll();
        expect(list.length, equals(2));
        final names = list.map((p) => p['name']).toList();
        expect(names, containsAll(['P1', 'P2']));
      });

      test('fetchAll() returns empty list on null node', () async {
        final list = await dataSource.fetchAll();
        expect(list, isEmpty);
      });

      test('fetchById() returns product map if exists, null if absent',
          () async {
        mockDb.seedData(productPath, {
          'p100': {'id': 'p100', 'name': 'Specific Product', 'price': 50000},
        });

        final product = await dataSource.fetchById('p100');
        expect(product, isNotNull);
        expect(product!['name'], equals('Specific Product'));

        final missing = await dataSource.fetchById('non_existent');
        expect(missing, isNull);
      });

      test('getById() delegates to fetchById()', () async {
        mockDb.seedData(productPath, {
          'p200': {'id': 'p200', 'name': 'Delegated Product'},
        });

        final product = await dataSource.getById('p200');
        expect(product, isNotNull);
        expect(product!['name'], equals('Delegated Product'));
      });

      test('upsert() saves product map in database', () async {
        await dataSource.upsert(
            'p_new', {'id': 'p_new', 'name': 'New Product', 'price': 99000});

        final ref = mockDb.getOrCreateRef(productPath);
        final snap = await ref.child('p_new').get();
        expect(snap.exists, isTrue);
        expect((snap.value as Map)['name'], equals('New Product'));
      });

      test('delete() removes product from database', () async {
        mockDb.seedData(productPath, {
          'p_del': {'id': 'p_del', 'name': 'Delete Me'},
        });

        await dataSource.delete('p_del');

        final ref = mockDb.getOrCreateRef(productPath);
        final snap = await ref.child('p_del').get();
        expect(snap.exists, isFalse);
      });

      test('updateStock() updates the stock attribute', () async {
        mockDb.seedData(productPath, {
          'p_stock': {'id': 'p_stock', 'name': 'Stock Product', 'stock': 10},
        });

        await dataSource.updateStock('p_stock', 25);

        final ref = mockDb.getOrCreateRef(productPath);
        final snap = await ref.child('p_stock').get();
        expect((snap.value as Map)['stock'], equals(25));
      });
    });
  });
}
