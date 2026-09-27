import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/customer_remote_data_source.dart';

import '../../support/firebase_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomerRemoteDataSource', () {
    late MockFirebaseDatabase mockDb;
    late CustomerRemoteDataSource dataSource;
    const customersPath = 'shared_customers';

    setUp(() {
      mockDb = MockFirebaseDatabase();
      dataSource = CustomerRemoteDataSource(mockDb);
    });

    group('watchAll() - Bandwidth Optimization & Reactivity', () {
      test('No double fetch: .get() is NEVER called when subscribing to watchAll()', () async {
        final ref = mockDb.getOrCreateRef(customersPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('cust_1', {
          'id': 'cust_1',
          'name': 'Customer 1',
          'phone': '0901234567',
        });

        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));

        expect(mockDb.wasGetCalled(customersPath), isFalse);
        expect(mockDb.getCallCount(customersPath), equals(0));

        await sub.cancel();
      });

      test('50ms debounce coalesces rapid stream arrivals', () async {
        final ref = mockDb.getOrCreateRef(customersPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        for (int i = 1; i <= 20; i++) {
          ref.emitChildAdded('c_$i', {
            'id': 'c_$i',
            'name': 'Customer $i',
            'currentDebt': i * 10000.0,
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
        final ref = mockDb.getOrCreateRef(customersPath);
        final completer = Completer<List<Map>>();
        final sub = dataSource.watchAll().listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        });

        // Simulates empty node in Firebase RTDB
        ref.emitNullValue();

        final result = await completer.future.timeout(const Duration(milliseconds: 150));
        expect(result, isEmpty);

        await sub.cancel();
      });

      test('Key and id extraction fallback: record without id field uses snapshot.key', () async {
        final ref = mockDb.getOrCreateRef(customersPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        // Record with NO 'id' field in the value map
        ref.emitChildAdded('KH_NO_ID_001', {
          'name': 'Nguyen Van A',
          'phone': '0912345678',
          'currentDebt': 500000.0,
        });

        await Future.delayed(const Duration(milliseconds: 65));

        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(1));
        // The cached entity map was populated using the snapshot key as identifier
        final customer = emissions.first.first;
        expect(customer['name'], equals('Nguyen Van A'));

        await sub.cancel();
      });

      test('Immediate emit on childChanged: updates cache and emits immediately', () async {
        final ref = mockDb.getOrCreateRef(customersPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('c1', {'id': 'c1', 'name': 'Orig Name', 'currentDebt': 0.0});
        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));

        final stopwatch = Stopwatch()..start();
        ref.emitChildChanged('c1', {'id': 'c1', 'name': 'Updated Name', 'currentDebt': 250000.0});
        await Future.delayed(const Duration(milliseconds: 10));
        stopwatch.stop();

        expect(emissions.length, equals(2));
        expect(emissions.last.first['name'], equals('Updated Name'));
        expect(emissions.last.first['currentDebt'], equals(250000.0));
        expect(stopwatch.elapsedMilliseconds, lessThan(40));

        await sub.cancel();
      });

      test('Immediate emit on childRemoved: purges by both key and id immediately', () async {
        final ref = mockDb.getOrCreateRef(customersPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        // cust_1 has no id field (stored by key)
        ref.emitChildAdded('cust_1', {'name': 'Customer 1'});
        // cust_2 has explicit id field matching key
        ref.emitChildAdded('cust_2', {'id': 'cust_2', 'name': 'Customer 2'});
        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(2));

        // Remove cust_1 by key (which had no id field)
        ref.emitChildRemoved('cust_1');
        await Future.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, equals(2));
        expect(emissions.last.length, equals(1));
        expect(emissions.last.first['id'] ?? emissions.last.first['name'], isNot(equals('Customer 1')));

        // Remove cust_2 by id
        ref.emitChildRemoved('cust_2');
        await Future.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, equals(3));
        expect(emissions.last, isEmpty);

        await sub.cancel();
      });

      test('Stream cancellation properly cancels subscriptions and timers', () async {
        final ref = mockDb.getOrCreateRef(customersPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        expect(ref.childAddedStream.activeListeners, equals(1));
        expect(ref.childChangedStream.activeListeners, equals(1));
        expect(ref.childRemovedStream.activeListeners, equals(1));
        expect(ref.valueStream.activeListeners, equals(1));

        ref.emitChildAdded('c_cancel', {'id': 'c_cancel', 'name': 'Cancel'});
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

    group('Customer CRUD & Debt Transactions', () {
      test('fetchById() returns customer map if present, null if missing', () async {
        mockDb.seedData(customersPath, {
          'c_found': {'id': 'c_found', 'name': 'Found Customer'},
        });

        final found = await dataSource.fetchById('c_found');
        expect(found, isNotNull);
        expect(found!['name'], equals('Found Customer'));

        final missing = await dataSource.fetchById('c_missing');
        expect(missing, isNull);
      });

      test('upsert() modifies/creates customer map', () async {
        await dataSource.upsert('c_up', {
          'name': 'Updated Customer',
          'currentDebt': 150000.0,
        });

        final snap = await mockDb.getOrCreateRef(customersPath).child('c_up').get();
        expect(snap.exists, isTrue);
        expect((snap.value as Map)['name'], equals('Updated Customer'));
      });

      test('delete() removes customer from database', () async {
        mockDb.seedData(customersPath, {
          'c_del': {'name': 'Delete Me'},
        });

        await dataSource.delete('c_del');

        final snap = await mockDb.getOrCreateRef(customersPath).child('c_del').get();
        expect(snap.exists, isFalse);
      });

      test('saveDebtTransaction() records debt transaction under customer node', () async {
        await dataSource.saveDebtTransaction('c_debtor', {
          'id': 'tx_debt_1',
          'amount': 200000.0,
          'type': 'order_debt',
        });

        final ref = mockDb.getOrCreateRef(customersPath);
        final txSnap = await ref
            .child('c_debtor')
            .child('debt_transactions')
            .child('tx_debt_1')
            .get();

        expect(txSnap.exists, isTrue);
        expect((txSnap.value as Map)['amount'], equals(200000.0));
      });

      test('watchDebtTransactions() streams debt transactions for customer', () async {
        final txRef = mockDb
            .getOrCreateRef(customersPath)
            .child('c_stream')
            .child('debt_transactions') as MockDatabaseReference;

        final stream = dataSource.watchDebtTransactions('c_stream');
        final emissions = <List<Map>>[];
        final sub = stream.listen(emissions.add);

        txRef.emitValue({
          'tx1': {'id': 'tx1', 'amount': 100000.0},
          'tx2': {'id': 'tx2', 'amount': 150000.0},
        });

        await Future.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(2));
        final amounts = emissions.first.map((t) => t['amount']).toList();
        expect(amounts, containsAll([100000.0, 150000.0]));

        await sub.cancel();
      });
    });
  });
}
