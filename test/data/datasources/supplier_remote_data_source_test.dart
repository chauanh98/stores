import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/supplier_remote_data_source.dart';

import '../../support/firebase_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupplierRemoteDataSource', () {
    late MockFirebaseDatabase mockDb;
    late SupplierRemoteDataSource dataSource;
    const defaultSharedPath = 'shared_suppliers';
    const storeId = 'store_branch_001';

    setUp(() {
      mockDb = MockFirebaseDatabase();
      dataSource = SupplierRemoteDataSource(mockDb);
    });

    group('watchAll() - Bandwidth Optimization & Reactivity', () {
      test('No double fetch: .get() is NEVER called when subscribing to watchAll()', () async {
        final ref = mockDb.getOrCreateRef(defaultSharedPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('supp_1', {'id': 'supp_1', 'name': 'Supplier A'});
        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));

        expect(mockDb.wasGetCalled(defaultSharedPath), isFalse);
        expect(mockDb.getCallCount(defaultSharedPath), equals(0));

        await sub.cancel();
      });

      test('50ms debounce coalesces rapid supplier arrivals', () async {
        final ref = mockDb.getOrCreateRef(defaultSharedPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        for (int i = 1; i <= 20; i++) {
          ref.emitChildAdded('supp_$i', {
            'id': 'supp_$i',
            'name': 'Supplier $i',
            'currentDebt': i * 100000.0,
          });
        }

        await Future.delayed(const Duration(milliseconds: 20));
        expect(emissions, isEmpty);

        await Future.delayed(const Duration(milliseconds: 55));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(20));

        await sub.cancel();
      });

      test('emptyCheckSub: empty node emits [] (protects against infinite loading bug)', () async {
        final ref = mockDb.getOrCreateRef(defaultSharedPath);
        final completer = Completer<List<Map>>();
        final sub = dataSource.watchAll().listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        });

        ref.emitNullValue();

        final result = await completer.future.timeout(const Duration(milliseconds: 150));
        expect(result, isEmpty);

        await sub.cancel();
      });

      test('Immediate emit on childChanged without debounce delay', () async {
        final ref = mockDb.getOrCreateRef(defaultSharedPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('s1', {'id': 's1', 'name': 'Orig Supplier', 'currentDebt': 50000.0});
        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));

        final stopwatch = Stopwatch()..start();
        ref.emitChildChanged('s1', {'id': 's1', 'name': 'Updated Supplier', 'currentDebt': 0.0});
        await Future.delayed(const Duration(milliseconds: 10));
        stopwatch.stop();

        expect(emissions.length, equals(2));
        expect(emissions.last.first['name'], equals('Updated Supplier'));
        expect(emissions.last.first['currentDebt'], equals(0.0));
        expect(stopwatch.elapsedMilliseconds, lessThan(40));

        await sub.cancel();
      });

      test('Immediate emit on childRemoved: purges by both key and id immediately', () async {
        final ref = mockDb.getOrCreateRef(defaultSharedPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        // Record with snapshot.key only
        ref.emitChildAdded('s_key_only', {'name': 'Supplier Key Only'});
        // Record with explicit id
        ref.emitChildAdded('s_with_id', {'id': 's_with_id', 'name': 'Supplier With ID'});
        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(2));

        // Purge by key
        ref.emitChildRemoved('s_key_only');
        await Future.delayed(const Duration(milliseconds: 10));
        expect(emissions.length, equals(2));
        expect(emissions.last.length, equals(1));

        // Purge by id
        ref.emitChildRemoved('s_with_id');
        await Future.delayed(const Duration(milliseconds: 10));
        expect(emissions.length, equals(3));
        expect(emissions.last, isEmpty);

        await sub.cancel();
      });

      test('Unified supplier master: watches shared_suppliers even when storeId provided', () async {
        final sharedRef = mockDb.getOrCreateRef(defaultSharedPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll(storeId: storeId).listen(emissions.add);

        sharedRef.emitChildAdded('supp_shared_1', {
          'id': 'supp_shared_1',
          'name': 'Shared Master Supplier',
        });

        await Future.delayed(const Duration(milliseconds: 65));

        expect(emissions.length, equals(1));
        expect(emissions.first.first['name'], equals('Shared Master Supplier'));
        expect(mockDb.wasGetCalled(defaultSharedPath), isFalse);

        await sub.cancel();
      });

      test('Stream cancellation tears down listeners and cancels debounce', () async {
        final ref = mockDb.getOrCreateRef(defaultSharedPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('s_cancel', {'id': 's_cancel', 'name': 'Cancel Me'});
        await Future.delayed(const Duration(milliseconds: 10));

        await sub.cancel();

        expect(ref.childAddedStream.activeListeners, equals(0));
        expect(ref.childChangedStream.activeListeners, equals(0));
        expect(ref.childRemovedStream.activeListeners, equals(0));
        expect(ref.valueStream.activeListeners, equals(0));

        await Future.delayed(const Duration(milliseconds: 70));
        expect(emissions, isEmpty);
      });
    });

    group('Supplier CRUD & Debt Transactions', () {
      test('fetchById() retrieves supplier from database', () async {
        mockDb.seedData(defaultSharedPath, {
          's_target': {'id': 's_target', 'name': 'Target Supplier'},
        });

        final supplier = await dataSource.fetchById('s_target');
        expect(supplier, isNotNull);
        expect(supplier!['name'], equals('Target Supplier'));

        final missing = await dataSource.fetchById('s_missing');
        expect(missing, isNull);
      });

      test('upsert() modifies supplier attributes in database', () async {
        await dataSource.upsert('s_new', {
          'name': 'New Supplier',
          'currentDebt': 5000000.0,
        });

        final snap = await mockDb.getOrCreateRef(defaultSharedPath).child('s_new').get();
        expect(snap.exists, isTrue);
        expect((snap.value as Map)['name'], equals('New Supplier'));
      });

      test('delete() removes supplier from database', () async {
        mockDb.seedData(defaultSharedPath, {
          's_del': {'name': 'Delete Me'},
        });

        await dataSource.delete('s_del');

        final snap = await mockDb.getOrCreateRef(defaultSharedPath).child('s_del').get();
        expect(snap.exists, isFalse);
      });

      test('saveDebtTransaction() records debt transaction and updates supplier currentDebt when remainingDebt provided', () async {
        // Initial supplier
        mockDb.seedData(defaultSharedPath, {
          's_ncc_1': {'id': 's_ncc_1', 'name': 'NCC 1', 'currentDebt': 1000000.0},
        });

        await dataSource.saveDebtTransaction('s_ncc_1', {
          'id': 'debt_tx_1',
          'amount': 500000.0,
          'remainingDebt': 1500000.0,
          'type': 'import_debt',
        });

        // Verify transaction recorded
        final txSnap = await mockDb
            .getOrCreateRef('shared_suppliers/s_ncc_1/debt_transactions')
            .child('debt_tx_1')
            .get();
        expect(txSnap.exists, isTrue);
        expect((txSnap.value as Map)['amount'], equals(500000.0));

        // Verify supplier currentDebt updated to 1,500,000.0
        final supplierSnap = await mockDb.getOrCreateRef(defaultSharedPath).child('s_ncc_1').get();
        expect((supplierSnap.value as Map)['currentDebt'], equals(1500000.0));
      });

      test('watchDebtTransactions() streams debt transactions for supplier', () async {
        final txRef = mockDb.getOrCreateRef('shared_suppliers/s_stream/debt_transactions');
        final stream = dataSource.watchDebtTransactions('s_stream');
        final emissions = <List<Map>>[];
        final sub = stream.listen(emissions.add);

        txRef.emitValue({
          'tx1': {'id': 'tx1', 'amount': 200000.0},
          'tx2': {'id': 'tx2', 'amount': 300000.0},
        });

        await Future.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(2));
        final ids = emissions.first.map((t) => t['id']).toList();
        expect(ids, containsAll(['tx1', 'tx2']));

        await sub.cancel();
      });

      test('fetchDebtTransactions() returns list of transactions', () async {
        mockDb.seedData('shared_suppliers/s_fetch/debt_transactions', {
          'txA': {'id': 'txA', 'amount': 10000.0},
          'txB': {'id': 'txB', 'amount': 20000.0},
        });

        final list = await dataSource.fetchDebtTransactions('s_fetch');
        expect(list.length, equals(2));
        final amounts = list.map((t) => t['amount']).toList();
        expect(amounts, containsAll([10000.0, 20000.0]));
      });
    });
  });
}
