import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/auth_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/category_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/customer_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/supplier_remote_data_source.dart';

import '../support/firebase_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
      'Milestone 4 Adversarial Verification - Bandwidth & Reactive Streams Stress',
      () {
    late MockFirebaseDatabase mockDb;
    const storeId = 'store_stress_001';

    setUp(() {
      mockDb = MockFirebaseDatabase();
    });

    // =========================================================================
    // 1. RAPID EVENT BURSTS (100+ events in <10ms) DEBOUNCE COALESCING
    // =========================================================================
    group('1. Rapid Event Bursts (100+ events in <10ms)', () {
      test(
          'ProductRemoteDataSource: 120 rapid events burst coalesces into exactly 1 emission',
          () async {
        final ds = ProductRemoteDataSource(mockDb, storeId);
        final ref = mockDb.getOrCreateRef('stores/$storeId/products');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        final stopwatch = Stopwatch()..start();
        // Burst 120 events in a synchronous tight loop (<10ms)
        for (int i = 1; i <= 120; i++) {
          ref.emitChildAdded('prod_$i', {
            'id': 'prod_$i',
            'name': 'Product $i',
            'price': i * 1000,
            'stock': 100,
          });
        }
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(100),
            reason: 'Burst emission must finish quickly');

        // Check before debounce window (at 20ms) -> ZERO emissions
        await Future.delayed(const Duration(milliseconds: 20));
        expect(emissions, isEmpty,
            reason: 'Events within 50ms debounce must be coalesced');

        // Check after debounce window (at 75ms total) -> exactly 1 emission with 120 items
        await Future.delayed(const Duration(milliseconds: 55));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(120));
        expect(emissions.first.map((p) => p['id']),
            containsAll(['prod_1', 'prod_60', 'prod_120']));

        // Verify .get() was NEVER called on products path (zero double fetch)
        expect(mockDb.wasGetCalled('stores/$storeId/products'), isFalse);
        expect(mockDb.getCallCount('stores/$storeId/products'), equals(0));

        await sub.cancel();
      });

      test(
          'OrderRemoteDataSource: 150 rapid events burst coalesces into exactly 1 emission',
          () async {
        final ds = OrderRemoteDataSource(mockDb, storeId);
        final ref = mockDb.getOrCreateRef('stores/$storeId/orders');
        final emissions = <List<Map<String, dynamic>>>[];
        final sub = ds.watchAll().listen(emissions.add);

        for (int i = 1; i <= 150; i++) {
          ref.emitChildAdded('ord_$i', {
            'id': 'ord_$i',
            'totalAmount': i * 50000,
            'status': 'completed',
          });
        }

        // Before debounce window (at 20ms)
        await Future.delayed(const Duration(milliseconds: 20));
        expect(emissions, isEmpty);

        // After debounce window (75ms total)
        await Future.delayed(const Duration(milliseconds: 55));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(150));
        expect(mockDb.wasGetCalled('stores/$storeId/orders'), isFalse);

        await sub.cancel();
      });

      test(
          'CustomerRemoteDataSource: 100 rapid events burst coalesces into exactly 1 emission',
          () async {
        final ds = CustomerRemoteDataSource(mockDb);
        final ref = mockDb.getOrCreateRef('shared_customers');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        for (int i = 1; i <= 100; i++) {
          ref.emitChildAdded('cust_$i', {
            'id': 'cust_$i',
            'name': 'Customer $i',
            'currentDebt': i * 10000,
          });
        }

        await Future.delayed(const Duration(milliseconds: 20));
        expect(emissions, isEmpty);

        await Future.delayed(const Duration(milliseconds: 55));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(100));
        expect(mockDb.wasGetCalled('shared_customers'), isFalse);

        await sub.cancel();
      });

      test(
          'SupplierRemoteDataSource: 100 rapid events burst coalesces into exactly 1 emission',
          () async {
        final ds = SupplierRemoteDataSource(mockDb);
        final ref = mockDb.getOrCreateRef('shared_suppliers');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        for (int i = 1; i <= 100; i++) {
          ref.emitChildAdded('sup_$i', {
            'id': 'sup_$i',
            'name': 'Supplier $i',
            'currentDebt': i * 20000,
          });
        }

        await Future.delayed(const Duration(milliseconds: 20));
        expect(emissions, isEmpty);

        await Future.delayed(const Duration(milliseconds: 55));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(100));
        expect(mockDb.wasGetCalled('shared_suppliers'), isFalse);

        await sub.cancel();
      });

      test(
          'InventoryRemoteDataSource: 100 rapid events burst coalesces into exactly 1 emission',
          () async {
        final ds = InventoryRemoteDataSource(mockDb, storeId);
        final ref =
            mockDb.getOrCreateRef('stores/$storeId/inventory_transactions');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        for (int i = 1; i <= 100; i++) {
          ref.emitChildAdded('inv_$i', {
            'id': 'inv_$i',
            'productId': 'p_$i',
            'type': 'import',
            'quantity': i,
          });
        }

        await Future.delayed(const Duration(milliseconds: 20));
        expect(emissions, isEmpty);

        await Future.delayed(const Duration(milliseconds: 55));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(100));
        expect(mockDb.wasGetCalled('stores/$storeId/inventory_transactions'),
            isFalse);

        await sub.cancel();
      });

      test(
          'CategoryRemoteDataSource: 100 rapid events burst coalesces into exactly 1 emission',
          () async {
        final ds = CategoryRemoteDataSource(mockDb);
        final ref = mockDb.getOrCreateRef('shared_categories');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        for (int i = 1; i <= 100; i++) {
          ref.emitChildAdded('cat_$i', {
            'id': 'cat_$i',
            'name': 'Category $i',
          });
        }

        await Future.delayed(const Duration(milliseconds: 20));
        expect(emissions, isEmpty);

        await Future.delayed(const Duration(milliseconds: 55));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(100));
        expect(mockDb.wasGetCalled('shared_categories'), isFalse);

        await sub.cancel();
      });

      test(
          'AuthRemoteDataSource: 100 rapid accounts burst coalesces into exactly 1 emission',
          () async {
        final ds = AuthRemoteDataSource(mockDb);
        final ref = mockDb.getOrCreateRef('stores/accounts');
        final emissions = <List<Map<String, dynamic>>>[];
        final sub = ds.watchAllAccounts().listen(emissions.add);

        for (int i = 1; i <= 100; i++) {
          ref.emitChildAdded('user_$i', {
            'fullName': 'User $i',
            'role': 'nhanvien',
          });
        }

        await Future.delayed(const Duration(milliseconds: 20));
        expect(emissions, isEmpty);

        await Future.delayed(const Duration(milliseconds: 55));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(100));
        expect(mockDb.wasGetCalled('stores/accounts'), isFalse);

        await sub.cancel();
      });

      test(
          'Double burst stress: continuous event arrivals within window reset timer correctly',
          () async {
        final ds = ProductRemoteDataSource(mockDb, storeId);
        final ref = mockDb.getOrCreateRef('stores/$storeId/products');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        // First burst: 50 items at t=0
        for (int i = 1; i <= 50; i++) {
          ref.emitChildAdded(
              'b1_$i', {'id': 'b1_$i', 'name': 'Batch 1 Item $i'});
        }

        // Wait 30ms (timer is active, has not fired yet)
        await Future.delayed(const Duration(milliseconds: 30));
        expect(emissions, isEmpty);

        // Second burst: 50 items at t=30ms (resets the 50ms debounce timer)
        for (int i = 1; i <= 50; i++) {
          ref.emitChildAdded(
              'b2_$i', {'id': 'b2_$i', 'name': 'Batch 2 Item $i'});
        }

        // At t=55ms (25ms after second burst, 55ms after first) -> still NO emission because timer reset!
        await Future.delayed(const Duration(milliseconds: 25));
        expect(emissions, isEmpty,
            reason:
                'Debounce timer should have been reset by the second burst');

        // At t=95ms (65ms after second burst) -> exactly 1 emission containing all 100 items
        await Future.delayed(const Duration(milliseconds: 40));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(100));
        expect(emissions.first.map((p) => p['id']),
            containsAll(['b1_1', 'b1_50', 'b2_1', 'b2_50']));

        await sub.cancel();
      });
    });

    // =========================================================================
    // 2. EMPTY NODE IMMEDIATE RESOLUTION (No hanging on empty or deleted nodes)
    // =========================================================================
    group('2. Empty Node Immediate Resolution', () {
      test(
          'ProductRemoteDataSource: resolves [] immediately (<25ms) on null node without hanging',
          () async {
        final ds = ProductRemoteDataSource(mockDb, storeId);
        final ref = mockDb.getOrCreateRef('stores/$storeId/products');
        final completer = Completer<List<Map>>();

        final sub = ds.watchAll().listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        });

        // Firebase RTDB emits null snapshot on empty node
        ref.emitNullValue();

        // Must resolve promptly, never wait or timeout
        final result = await completer.future.timeout(
          const Duration(milliseconds: 40),
          onTimeout: () => throw TimeoutException(
              'emptyCheckSub failed to resolve empty node promptly'),
        );

        expect(result, isEmpty);
        await sub.cancel();
      });

      test('CustomerRemoteDataSource: resolves [] immediately on null node',
          () async {
        final ds = CustomerRemoteDataSource(mockDb);
        final ref = mockDb.getOrCreateRef('shared_customers');
        final completer = Completer<List<Map>>();

        final sub = ds.watchAll().listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        });

        ref.emitNullValue();

        final result =
            await completer.future.timeout(const Duration(milliseconds: 40));
        expect(result, isEmpty);
        await sub.cancel();
      });

      test('SupplierRemoteDataSource: resolves [] immediately on null node',
          () async {
        final ds = SupplierRemoteDataSource(mockDb);
        final ref = mockDb.getOrCreateRef('shared_suppliers');
        final completer = Completer<List<Map>>();

        final sub = ds.watchAll().listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        });

        ref.emitNullValue();

        final result =
            await completer.future.timeout(const Duration(milliseconds: 40));
        expect(result, isEmpty);
        await sub.cancel();
      });

      test('OrderRemoteDataSource: resolves [] immediately on null node',
          () async {
        final ds = OrderRemoteDataSource(mockDb, storeId);
        final ref = mockDb.getOrCreateRef('stores/$storeId/orders');
        final completer = Completer<List<Map<String, dynamic>>>();

        final sub = ds.watchAll().listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        });

        ref.emitNullValue();

        final result =
            await completer.future.timeout(const Duration(milliseconds: 40));
        expect(result, isEmpty);
        await sub.cancel();
      });

      test('InventoryRemoteDataSource: resolves [] immediately on null node',
          () async {
        final ds = InventoryRemoteDataSource(mockDb, storeId);
        final ref =
            mockDb.getOrCreateRef('stores/$storeId/inventory_transactions');
        final completer = Completer<List<Map>>();

        final sub = ds.watchAll().listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        });

        ref.emitNullValue();

        final result =
            await completer.future.timeout(const Duration(milliseconds: 40));
        expect(result, isEmpty);
        await sub.cancel();
      });

      test('CategoryRemoteDataSource: resolves [] immediately on null node',
          () async {
        final ds = CategoryRemoteDataSource(mockDb);
        final ref = mockDb.getOrCreateRef('shared_categories');
        final completer = Completer<List<Map>>();

        final sub = ds.watchAll().listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        });

        ref.emitNullValue();

        final result =
            await completer.future.timeout(const Duration(milliseconds: 40));
        expect(result, isEmpty);
        await sub.cancel();
      });

      test('AuthRemoteDataSource: resolves [] immediately on null node',
          () async {
        final ds = AuthRemoteDataSource(mockDb);
        final ref = mockDb.getOrCreateRef('stores/accounts');
        final completer = Completer<List<Map<String, dynamic>>>();

        final sub = ds.watchAllAccounts().listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        });

        ref.emitNullValue();

        final result =
            await completer.future.timeout(const Duration(milliseconds: 40));
        expect(result, isEmpty);
        await sub.cancel();
      });

      test(
          'Lifecycle: empty node resolves [] first, then transitions smoothly to populated on new items',
          () async {
        final ds = ProductRemoteDataSource(mockDb, storeId);
        final ref = mockDb.getOrCreateRef('stores/$storeId/products');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        // Initially empty
        ref.emitNullValue();
        await Future.delayed(const Duration(milliseconds: 20));
        expect(emissions.length, equals(1));
        expect(emissions.first, isEmpty);

        // Later, 3 items are added
        ref.emitChildAdded('p1', {'id': 'p1', 'name': 'First Item'});
        ref.emitChildAdded('p2', {'id': 'p2', 'name': 'Second Item'});
        ref.emitChildAdded('p3', {'id': 'p3', 'name': 'Third Item'});

        await Future.delayed(const Duration(milliseconds: 70));
        expect(emissions.length, equals(2));
        expect(emissions.last.length, equals(3));
        expect(emissions.last.map((p) => p['id']),
            containsAll(['p1', 'p2', 'p3']));

        await sub.cancel();
      });

      test(
          'Late empty check guard: onValue(null) arriving after childAdded does NOT overwrite cache',
          () async {
        final ds = ProductRemoteDataSource(mockDb, storeId);
        final ref = mockDb.getOrCreateRef('stores/$storeId/products');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        // ChildAdded arrived first
        ref.emitChildAdded('p_fast', {'id': 'p_fast', 'name': 'Fast Item'});

        // Then onValue(null) arrives (out of order or race condition)
        ref.emitNullValue();

        // Wait for debounce
        await Future.delayed(const Duration(milliseconds: 70));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(1));
        expect(emissions.first.first['id'], equals('p_fast'));

        await sub.cancel();
      });
    });

    // =========================================================================
    // 3. OUT-OF-ORDER childRemoved EVENTS & CACHE PURGING
    // =========================================================================
    group('3. Out-of-Order childRemoved Events & Cache Purging', () {
      test(
          'ProductRemoteDataSource: rapid reverse-order removals purge cache cleanly with immediate emissions',
          () async {
        final ds = ProductRemoteDataSource(mockDb, storeId);
        final ref = mockDb.getOrCreateRef('stores/$storeId/products');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        // Populate 50 products p_1 to p_50
        for (int i = 1; i <= 50; i++) {
          ref.emitChildAdded('p_$i', {'id': 'p_$i', 'name': 'Product $i'});
        }
        await Future.delayed(const Duration(milliseconds: 70));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(50));

        // Rapidly remove products in reverse order from p_50 down to p_26 (25 removals)
        for (int i = 50; i > 25; i--) {
          ref.emitChildRemoved('p_$i');
        }

        // Each removal triggers an immediate emit
        await Future.delayed(const Duration(milliseconds: 25));
        expect(emissions.length, equals(26)); // 1 initial + 25 removals
        expect(emissions.last.length, equals(25));
        expect(
            emissions.last.map((p) => p['id']), containsAll(['p_1', 'p_25']));
        expect(emissions.last.map((p) => p['id']), isNot(contains('p_26')));
        expect(emissions.last.map((p) => p['id']), isNot(contains('p_50')));

        await sub.cancel();
      });

      test(
          'CustomerRemoteDataSource: removal by key and by id fallback purges cache completely',
          () async {
        final ds = CustomerRemoteDataSource(mockDb);
        final ref = mockDb.getOrCreateRef('shared_customers');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        // Add 3 customers where id field is explicitly present
        ref.emitChildAdded(
            'cust_key_A', {'id': 'cust_key_A', 'name': 'Cust A'});
        ref.emitChildAdded(
            'cust_key_B', {'id': 'cust_key_B', 'name': 'Cust B'});
        ref.emitChildAdded(
            'cust_key_C', {'id': 'cust_key_C', 'name': 'Cust C'});

        await Future.delayed(const Duration(milliseconds: 70));
        expect(emissions.first.length, equals(3));

        // Remove B
        ref.emitChildRemoved('cust_key_B');
        await Future.delayed(const Duration(milliseconds: 15));

        expect(emissions.last.length, equals(2));
        expect(emissions.last.map((c) => c['id']),
            containsAll(['cust_key_A', 'cust_key_C']));
        expect(
            emissions.last.map((c) => c['id']), isNot(contains('cust_key_B')));

        await sub.cancel();
      });

      test(
          'Resilience to ghost/non-existent key removals: does not crash or corrupt existing cache',
          () async {
        final ds = ProductRemoteDataSource(mockDb, storeId);
        final ref = mockDb.getOrCreateRef('stores/$storeId/products');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        ref.emitChildAdded('real_1', {'id': 'real_1', 'name': 'Real Product'});
        await Future.delayed(const Duration(milliseconds: 70));
        expect(emissions.length, equals(1));

        // Remove ghost keys that never existed
        ref.emitChildRemoved('ghost_x');
        ref.emitChildRemoved('ghost_y');
        ref.emitChildRemoved('ghost_z');

        await Future.delayed(const Duration(milliseconds: 20));
        // State remains intact with real_1
        expect(emissions.last.length, equals(1));
        expect(emissions.last.first['id'], equals('real_1'));

        await sub.cancel();
      });

      test(
          'SupplierRemoteDataSource: purge to complete empty list [] and recover on new add',
          () async {
        final ds = SupplierRemoteDataSource(mockDb);
        final ref = mockDb.getOrCreateRef('shared_suppliers');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        ref.emitChildAdded('s1', {'id': 's1', 'name': 'S1'});
        ref.emitChildAdded('s2', {'id': 's2', 'name': 'S2'});
        await Future.delayed(const Duration(milliseconds: 70));
        expect(emissions.first.length, equals(2));

        // Remove both
        ref.emitChildRemoved('s1');
        ref.emitChildRemoved('s2');
        await Future.delayed(const Duration(milliseconds: 20));

        expect(emissions.last, isEmpty);

        // Add a brand new supplier
        ref.emitChildAdded('s3', {'id': 's3', 'name': 'S3'});
        await Future.delayed(const Duration(milliseconds: 70));

        expect(emissions.last.length, equals(1));
        expect(emissions.last.first['id'], equals('s3'));

        await sub.cancel();
      });

      test(
          'Idempotent repeated removals: multiple childRemoved for same key do not crash or produce negative count',
          () async {
        final ds = ProductRemoteDataSource(mockDb, storeId);
        final ref = mockDb.getOrCreateRef('stores/$storeId/products');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        ref.emitChildAdded(
            'item_one', {'id': 'item_one', 'name': 'Single Item'});
        await Future.delayed(const Duration(milliseconds: 70));
        expect(emissions.first.length, equals(1));

        // Repeated removals for item_one
        ref.emitChildRemoved('item_one');
        ref.emitChildRemoved('item_one');
        ref.emitChildRemoved('item_one');
        await Future.delayed(const Duration(milliseconds: 20));

        expect(emissions.last, isEmpty);

        await sub.cancel();
      });

      test(
          'Removal emission latency: childRemoved emits in <20ms (zero 50ms debounce penalty)',
          () async {
        final ds = ProductRemoteDataSource(mockDb, storeId);
        final ref = mockDb.getOrCreateRef('stores/$storeId/products');
        final emissions = <List<Map>>[];
        final sub = ds.watchAll().listen(emissions.add);

        ref.emitChildAdded(
            'lat_test', {'id': 'lat_test', 'name': 'Latency Test'});
        await Future.delayed(const Duration(milliseconds: 70));

        final stopwatch = Stopwatch()..start();
        ref.emitChildRemoved('lat_test');

        // Check within 20ms: emission must already be present
        await Future.delayed(const Duration(milliseconds: 15));
        stopwatch.stop();

        expect(emissions.last, isEmpty);
        expect(stopwatch.elapsedMilliseconds, lessThan(40),
            reason: 'Removal must emit immediately without debounce delay');

        await sub.cancel();
      });
    });

    // =========================================================================
    // 4. RESUBSCRIPTION STRESS & MEMORY SAFETY (No leaks, no zombie timers)
    // =========================================================================
    group('4. Resubscription Stress & Memory Safety', () {
      test(
          'ProductRemoteDataSource: 100 rapid subscribe & cancel cycles tear down all listeners with zero zombie timers',
          () async {
        final ds = ProductRemoteDataSource(mockDb, storeId);
        final ref = mockDb.getOrCreateRef('stores/$storeId/products');

        // Run 100 rapid listen -> emit -> cancel iterations
        for (int i = 1; i <= 100; i++) {
          final emissions = <List<Map>>[];
          final sub = ds.watchAll().listen(emissions.add);

          // Emit an event that sets the 50ms debounce timer
          ref.emitChildAdded('temp_$i', {'id': 'temp_$i', 'name': 'Temp $i'});

          // Immediately cancel the subscription (<1ms)
          await sub.cancel();
        }

        // Verify all 4 event stream listeners are completely detached (count == 0)
        expect(ref.childAddedStream.activeListeners, equals(0),
            reason: 'onChildAdded must have 0 active listeners');
        expect(ref.childChangedStream.activeListeners, equals(0),
            reason: 'onChildChanged must have 0 active listeners');
        expect(ref.childRemovedStream.activeListeners, equals(0),
            reason: 'onChildRemoved must have 0 active listeners');
        expect(ref.valueStream.activeListeners, equals(0),
            reason: 'onValue must have 0 active listeners');

        // Wait 80ms to ensure no orphaned timers fire or throw 'Bad state: Cannot add event after closing'
        await Future.delayed(const Duration(milliseconds: 80));

        // Re-subscribe after stress: works cleanly as fresh listener
        final freshEmissions = <List<Map>>[];
        final freshSub = ds.watchAll().listen(freshEmissions.add);

        expect(ref.childAddedStream.activeListeners, equals(1));
        ref.emitChildAdded('fresh_p', {'id': 'fresh_p', 'name': 'Fresh'});
        await Future.delayed(const Duration(milliseconds: 70));

        expect(freshEmissions.length, equals(1));
        expect(freshEmissions.first.first['id'], equals('fresh_p'));

        await freshSub.cancel();
        expect(ref.childAddedStream.activeListeners, equals(0));
      });

      test(
          'Multi-DataSource resubscription churn: 20 cycles across all 6 remote data sources',
          () async {
        final orderDs = OrderRemoteDataSource(mockDb, storeId);
        final custDs = CustomerRemoteDataSource(mockDb);
        final supDs = SupplierRemoteDataSource(mockDb);
        final invDs = InventoryRemoteDataSource(mockDb, storeId);
        final catDs = CategoryRemoteDataSource(mockDb);
        final authDs = AuthRemoteDataSource(mockDb);

        final orderRef = mockDb.getOrCreateRef('stores/$storeId/orders');
        final custRef = mockDb.getOrCreateRef('shared_customers');
        final supRef = mockDb.getOrCreateRef('shared_suppliers');
        final invRef =
            mockDb.getOrCreateRef('stores/$storeId/inventory_transactions');
        final catRef = mockDb.getOrCreateRef('shared_categories');
        final authRef = mockDb.getOrCreateRef('stores/accounts');

        for (int i = 0; i < 20; i++) {
          final s1 = orderDs.watchAll().listen((_) {});
          final s2 = custDs.watchAll().listen((_) {});
          final s3 = supDs.watchAll().listen((_) {});
          final s4 = invDs.watchAll().listen((_) {});
          final s5 = catDs.watchAll().listen((_) {});
          final s6 = authDs.watchAllAccounts().listen((_) {});

          await Future.wait([
            s1.cancel(),
            s2.cancel(),
            s3.cancel(),
            s4.cancel(),
            s5.cancel(),
            s6.cancel(),
          ]);
        }

        // Verify zero lingering listeners across all references
        expect(orderRef.childAddedStream.activeListeners, equals(0));
        expect(custRef.childAddedStream.activeListeners, equals(0));
        expect(supRef.childAddedStream.activeListeners, equals(0));
        expect(invRef.childAddedStream.activeListeners, equals(0));
        expect(catRef.childAddedStream.activeListeners, equals(0));
        expect(authRef.childAddedStream.activeListeners, equals(0));
      });

      test(
          'Concurrent subscriber churn: partial subscriber cancellation does not disrupt surviving subscribers',
          () async {
        final ds = ProductRemoteDataSource(mockDb, storeId);
        final ref = mockDb.getOrCreateRef('stores/$storeId/products');

        final subs = <StreamSubscription>[];
        final results = List.generate(10, (_) => <List<Map>>[]);

        for (int i = 0; i < 10; i++) {
          subs.add(ds.watchAll().listen(results[i].add));
        }
        expect(ref.childAddedStream.activeListeners, equals(10));

        // Emit 10 items
        for (int i = 1; i <= 10; i++) {
          ref.emitChildAdded(
              'shared_$i', {'id': 'shared_$i', 'name': 'Shared $i'});
        }

        // Cancel first 6 subscribers while debounce is in progress
        await Future.wait(subs.take(6).map((s) => s.cancel()));
        expect(ref.childAddedStream.activeListeners, equals(4));

        // Let debounce finish for the surviving 4 subscribers
        await Future.delayed(const Duration(milliseconds: 70));

        // The first 6 received nothing (cancelled before debounce)
        for (int i = 0; i < 6; i++) {
          expect(results[i], isEmpty);
        }

        // The remaining 4 subscribers successfully received the 10 items
        for (int i = 6; i < 10; i++) {
          expect(results[i].length, equals(1));
          expect(results[i].first.length, equals(10));
        }

        // Cancel the remaining 4
        await Future.wait(subs.skip(6).map((s) => s.cancel()));
        expect(ref.childAddedStream.activeListeners, equals(0));
      });
    });

    // =========================================================================
    // 5. SIMULATED NETWORK FAILURE ON RANGE QUERIES (Fallback Recovery)
    // =========================================================================
    group('5. Simulated Network Failure on Range Queries & Fallback Recovery',
        () {
      final startDate = DateTime(2026, 9, 1, 0, 0, 0);
      final endDate = DateTime(2026, 9, 19, 23, 59, 59);
      const ordersPath = 'stores/$storeId/orders';
      const inventoryPath = 'stores/$storeId/inventory_transactions';

      test(
          'OrderRemoteDataSource.fetchByDateRange(): succeeds on indexed query under normal conditions',
          () async {
        final ds = OrderRemoteDataSource(mockDb, storeId);
        mockDb.seedData(ordersPath, {
          'o1': {
            'id': 'o1',
            'createdAt': '2026-09-05T10:00:00.000Z',
            'totalAmount': 100000
          },
          'o2': {
            'id': 'o2',
            'createdAt': '2026-09-10T15:30:00.000Z',
            'totalAmount': 200000
          },
          'o3': {
            'id': 'o3',
            'createdAt': '2026-09-19T12:00:00.000Z',
            'totalAmount': 300000
          },
          'o_past': {
            'id': 'o_past',
            'createdAt': '2026-08-31T23:59:59.000Z',
            'totalAmount': 50000
          },
          'o_future': {
            'id': 'o_future',
            'createdAt': '2026-09-20T00:00:01.000Z',
            'totalAmount': 60000
          },
        });

        final list = await ds.fetchByDateRange(startDate, endDate);
        expect(list.length, equals(3));
        expect(list.map((o) => o['id']), containsAll(['o1', 'o2', 'o3']));
        expect(list.map((o) => o['id']), isNot(contains('o_past')));
        expect(list.map((o) => o['id']), isNot(contains('o_future')));
      });

      test(
          'OrderRemoteDataSource.fetchByDateRange(): correctly shifts UTC timestamps to local timezone',
          () async {
        final ds = OrderRemoteDataSource(mockDb, storeId);
        // An order at 20:00 UTC on Sept 19 is 03:00 on Sept 20 in UTC+7 (outside Sept 19 range)
        mockDb.seedData(ordersPath, {
          'o_utc_afternoon': {
            'id': 'o_utc_afternoon',
            'createdAt': '2026-09-19T10:00:00.000Z',
            'totalAmount': 100000
          },
          'o_utc_late_night': {
            'id': 'o_utc_late_night',
            'createdAt': '2026-09-19T22:00:00.000Z',
            'totalAmount': 200000
          },
        });

        // Query for single day: Sept 19
        final singleDayStart = DateTime(2026, 9, 19, 0, 0, 0);
        final singleDayEnd = DateTime(2026, 9, 19, 23, 59, 59);

        final list = await ds.fetchByDateRange(singleDayStart, singleDayEnd);

        // o_utc_afternoon (17:00 local) is within Sept 19
        expect(list.any((o) => o['id'] == 'o_utc_afternoon'), isTrue);

        // If local timezone is ahead of UTC (e.g. UTC+7), o_utc_late_night (22:00 UTC = 05:00 next day) is excluded
        if (DateTime.now().timeZoneOffset.inHours >= 3) {
          expect(list.any((o) => o['id'] == 'o_utc_late_night'), isFalse,
              reason: 'Late night UTC must shift into next local calendar day');
        }
      });

      test(
          'OrderRemoteDataSource.fetchByDateRange(): recovers via fallback when query throws index-not-defined',
          () async {
        final ds = OrderRemoteDataSource(mockDb, storeId);
        mockDb.seedData(ordersPath, {
          'o1': {
            'id': 'o1',
            'createdAt': '2026-09-05T10:00:00.000Z',
            'totalAmount': 100000
          },
          'o2': {
            'id': 'o2',
            'createdAt': '2026-09-12T10:00:00.000Z',
            'totalAmount': 200000
          },
          'o_out': {
            'id': 'o_out',
            'createdAt': '2026-08-15T10:00:00.000Z',
            'totalAmount': 50000
          },
        });

        // Simulate Firebase index error on orderByChild('createdAt')
        mockDb.setSimulateQueryFailure(
          ordersPath,
          true,
          FirebaseException(
            plugin: 'firebase_database',
            code: 'index-not-defined',
            message: 'Index not defined for createdAt',
          ),
        );

        final list = await ds.fetchByDateRange(startDate, endDate);

        // Verify fallback succeeded in loading and filtering data
        expect(list.length, equals(2));
        expect(list.map((o) => o['id']), containsAll(['o1', 'o2']));
        expect(list.map((o) => o['id']), isNot(contains('o_out')));

        // Verify fallback called .get() on the node
        expect(mockDb.wasGetCalled(ordersPath), isTrue);
      });

      test(
          'OrderRemoteDataSource.fetchByDateRange(): returns [] gracefully when BOTH query and fallback fail (total network failure)',
          () async {
        final ds = OrderRemoteDataSource(mockDb, storeId);

        // Simulate both query failure AND fallback .get() failure
        mockDb.setSimulateQueryFailure(ordersPath, true);
        mockDb.setThrowOnGet(ordersPath, true);

        final list = await ds.fetchByDateRange(startDate, endDate);

        // Graceful degradation: returns [] instead of rethrowing
        expect(list, isEmpty);
      });

      test(
          'OrderRemoteDataSource.fetchByDateRange(): strict boundary date and malformed string handling in fallback',
          () async {
        final ds = OrderRemoteDataSource(mockDb, storeId);
        mockDb.seedData(ordersPath, {
          'b_start': {
            'id': 'b_start',
            'createdAt': '2026-09-01T00:00:00.000',
            'totalAmount': 100
          },
          'b_end': {
            'id': 'b_end',
            'createdAt': '2026-09-19T23:59:59.999',
            'totalAmount': 200
          },
          'b_before': {
            'id': 'b_before',
            'createdAt': '2026-08-31T23:59:59.999',
            'totalAmount': 300
          },
          'b_after': {
            'id': 'b_after',
            'createdAt': '2026-09-20T00:00:00.000',
            'totalAmount': 400
          },
          'b_null': {'id': 'b_null', 'createdAt': null},
          'b_invalid': {'id': 'b_invalid', 'createdAt': 'not_a_valid_date'},
        });

        // Trigger fallback path
        mockDb.setSimulateQueryFailure(ordersPath, true);

        final list = await ds.fetchByDateRange(startDate, endDate);

        expect(list.length, equals(2));
        expect(list.map((o) => o['id']), containsAll(['b_start', 'b_end']));
        expect(list.map((o) => o['id']), isNot(contains('b_before')));
        expect(list.map((o) => o['id']), isNot(contains('b_after')));
        expect(list.map((o) => o['id']), isNot(contains('b_null')));
        expect(list.map((o) => o['id']), isNot(contains('b_invalid')));
      });

      test(
          'InventoryRemoteDataSource.fetchImportsByDateRange(): succeeds on indexed query',
          () async {
        final ds = InventoryRemoteDataSource(mockDb, storeId);
        mockDb.seedData(inventoryPath, {
          't1': {
            'id': 't1',
            'type': 'import',
            'date': '2026-09-05T10:00:00.000'
          },
          't2': {
            'id': 't2',
            'type': 'export',
            'date': '2026-09-08T10:00:00.000'
          },
          't3': {
            'id': 't3',
            'type': 'import',
            'date': '2026-09-15T10:00:00.000'
          },
          't_out': {
            'id': 't_out',
            'type': 'import',
            'date': '2026-08-20T10:00:00.000'
          },
        });

        final list = await ds.fetchImportsByDateRange(startDate, endDate);

        expect(list.length, equals(2));
        expect(list.map((t) => t['id']), containsAll(['t1', 't3']));
        expect(
            list.map((t) => t['id']), isNot(contains('t2'))); // export excluded
        expect(list.map((t) => t['id']),
            isNot(contains('t_out'))); // out of range excluded
      });

      test(
          'InventoryRemoteDataSource.fetchImportsByDateRange(): recovers via fallback on index failure',
          () async {
        final ds = InventoryRemoteDataSource(mockDb, storeId);
        mockDb.seedData(inventoryPath, {
          't1': {
            'id': 't1',
            'type': 'import',
            'date': '2026-09-05T10:00:00.000'
          },
          't2': {
            'id': 't2',
            'type': 'export',
            'date': '2026-09-08T10:00:00.000'
          },
          't3': {
            'id': 't3',
            'type': 'import',
            'date': '2026-09-15T10:00:00.000'
          },
          't_out': {
            'id': 't_out',
            'type': 'import',
            'date': '2026-08-20T10:00:00.000'
          },
          't_bad_date': {
            'id': 't_bad_date',
            'type': 'import',
            'date': 'invalid'
          },
          't_null_date': {'id': 't_null_date', 'type': 'import', 'date': null},
        });

        mockDb.setSimulateQueryFailure(inventoryPath, true);

        final list = await ds.fetchImportsByDateRange(startDate, endDate);

        expect(list.length, equals(2));
        expect(list.map((t) => t['id']), containsAll(['t1', 't3']));
        expect(mockDb.wasGetCalled(inventoryPath), isTrue);
      });

      test(
          'InventoryRemoteDataSource.fetchImportsByDateRange(): returns [] gracefully on total network failure',
          () async {
        final ds = InventoryRemoteDataSource(mockDb, storeId);

        mockDb.setSimulateQueryFailure(inventoryPath, true);
        mockDb.setThrowOnGet(inventoryPath, true);

        final list = await ds.fetchImportsByDateRange(startDate, endDate);

        expect(list, isEmpty);
      });
    });
  });
}
