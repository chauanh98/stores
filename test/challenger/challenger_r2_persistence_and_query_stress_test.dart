import 'dart:async';
import 'dart:io';

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

  group('CHALLENGER R2: Static & Config Guardrails Verification', () {
    test(
        'Static Check: No unbounded onValue.take(1) queries exist anywhere in lib/',
        () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib directory must exist');

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final violations = <String>[];

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          // Look for onValue.take(1) that is not preceded by limitToFirst
          if (line.contains('onValue.take(1)')) {
            if (!line.contains('limitToFirst')) {
              // Ignore comments
              final trimmed = line.trim();
              if (!trimmed.startsWith('//') &&
                  !trimmed.startsWith('///') &&
                  !trimmed.startsWith('*')) {
                violations.add('${file.path}:${i + 1} -> $line');
              }
            }
          }
        }
      }

      expect(violations, isEmpty,
          reason:
              'Found unbounded onValue.take(1) queries without limitToFirst: $violations');
    });

    test(
        'Config Check: setPersistenceEnabled(false) is active in lib/main.dart',
        () {
      final mainFile = File('lib/main.dart');
      expect(mainFile.existsSync(), isTrue);
      final content = mainFile.readAsStringSync();

      expect(content,
          contains('FirebaseDatabase.instance.setPersistenceEnabled(false)'),
          reason:
              'setPersistenceEnabled(false) must be configured in lib/main.dart to prevent OOM crash in SqlPersistenceStorageEngine');
      expect(
          content,
          isNot(contains(
              'FirebaseDatabase.instance.setPersistenceEnabled(true)')),
          reason: 'setPersistenceEnabled(true) must NOT be active');
    });

    test(
        'Config Check: android:largeHeap="true" is configured in AndroidManifest.xml',
        () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue);
      final content = manifestFile.readAsStringSync();

      expect(content, contains('android:largeHeap="true"'),
          reason:
              'android:largeHeap="true" must be set in <application> tag of AndroidManifest.xml');
    });

    test(
        'Static Check: Zero queries scanning the entire root ref("stores").get()',
        () {
      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final violations = <String>[];

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        if (content.contains("ref('stores').get()") ||
            content.contains('ref("stores").get()')) {
          violations.add(file.path);
        }
      }

      expect(violations, isEmpty,
          reason:
              'Found dangerous unbounded ref("stores").get() query in $violations');
    });
  });

  group('CHALLENGER R2: Test Harness Robustness & Zero UnimplementedError', () {
    late MockFirebaseDatabase mockDb;

    setUp(() {
      mockDb = MockFirebaseDatabase();
    });

    test(
        'MockFirebaseDatabase and MockQuery handle all query primitives without UnimplementedError',
        () async {
      final ref = mockDb.getOrCreateRef('test/stress_node');

      // Chaining all query operations
      final query1 = ref.orderByChild('createdAt');
      final query2 = query1.startAt('2026-01-01');
      final query3 = query2.endAt('2026-12-31');
      final query4 = query3.equalTo('someVal');
      final query5 = query4.limitToFirst(10);
      final query6 = query5.limitToLast(5);

      expect(query6, isNotNull);

      // Verify get() execution
      final snap = await query6.get();
      expect(snap, isNotNull);
      expect(snap.exists, isFalse);

      // Verify onValue stream doesn't throw
      final eventFuture = ref.limitToFirst(1).onValue.first;
      ref.emitValue({'id': 'item1'});
      final event = await eventFuture;
      expect(event.snapshot.value, isNotNull);
    });

    test(
        'MockDatabaseReference direct limitToFirst(1).onValue emits through valueStream without crash',
        () async {
      final ref = mockDb.getOrCreateRef('stores/store_001/products');
      final stream = ref.limitToFirst(1).onValue;

      final completer = Completer<dynamic>();
      final sub = stream.take(1).listen((event) {
        completer.complete(event.snapshot.value);
      });

      ref.emitNullValue();
      final result =
          await completer.future.timeout(const Duration(milliseconds: 200));
      expect(result, isNull);
      await sub.cancel();
    });
  });

  group(
      'CHALLENGER R2: limitToFirst(1).onValue.take(1) Streaming & Stress Verification',
      () {
    late MockFirebaseDatabase mockDb;

    setUp(() {
      mockDb = MockFirebaseDatabase();
    });

    test(
        'Empty Node: All 7 remote data sources emit empty list [] without hanging',
        () async {
      final productDs = ProductRemoteDataSource(mockDb, 'store_001');
      final orderDs = OrderRemoteDataSource(mockDb, 'store_001');
      final customerDs = CustomerRemoteDataSource(mockDb);
      final supplierDs = SupplierRemoteDataSource(mockDb);
      final categoryDs = CategoryRemoteDataSource(mockDb);
      final inventoryDs = InventoryRemoteDataSource(mockDb, 'store_001');
      final authDs = AuthRemoteDataSource(mockDb);

      // Helper to test empty node emission
      Future<void> verifyEmptyEmission(
          Stream<List<dynamic>> stream, String path) async {
        final completer = Completer<List<dynamic>>();
        final sub = stream.listen((list) {
          if (!completer.isCompleted) completer.complete(list);
        });

        // Emit null snapshot on the target path
        mockDb.getOrCreateRef(path).emitNullValue();

        final result = await completer.future.timeout(
          const Duration(milliseconds: 250),
          onTimeout: () =>
              throw TimeoutException('Stream at $path timed out on empty node'),
        );

        expect(result, isEmpty, reason: '$path should emit [] for empty node');
        await sub.cancel();
      }

      await verifyEmptyEmission(
          productDs.watchAll(), 'stores/store_001/products');
      await verifyEmptyEmission(orderDs.watchAll(), 'stores/store_001/orders');
      await verifyEmptyEmission(customerDs.watchAll(), 'shared_customers');
      await verifyEmptyEmission(supplierDs.watchAll(), 'shared_suppliers');
      await verifyEmptyEmission(categoryDs.watchAll(), 'shared_categories');
      await verifyEmptyEmission(
          inventoryDs.watchAll(), 'stores/store_001/inventory_transactions');
      await verifyEmptyEmission(authDs.watchAllAccounts(), 'stores/accounts');
    });

    test(
        'Single Child Node: Emits exactly 1 item and does not trigger empty node false positive',
        () async {
      final productDs = ProductRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/products');

      final emissions = <List<Map>>[];
      final sub = productDs.watchAll().listen(emissions.add);

      // On Firebase RTDB, when children exist, limitToFirst(1) returns the 1st child
      ref.emitValue({
        'prod_1': {'id': 'prod_1', 'name': 'Table', 'price': 1000000}
      });
      ref.emitChildAdded(
          'prod_1', {'id': 'prod_1', 'name': 'Table', 'price': 1000000});

      await Future.delayed(const Duration(milliseconds: 70));

      // Should emit the 1 product, NOT []
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(1));
      expect(emissions.first.first['name'], equals('Table'));

      await sub.cancel();
    });

    test(
        'Multi-Thousand Scale Stress: 3,000 children burst with limitToFirst(1) does not OOM or duplicate',
        () async {
      final productDs = ProductRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/products');

      final emissions = <List<Map>>[];
      final sub = productDs.watchAll().listen(emissions.add);

      // 1. limitToFirst(1).onValue fires with only 1 child (OOM prevention simulation)
      ref.emitValue({
        'p_1': {'id': 'p_1', 'name': 'Product 1', 'price': 1000}
      });

      // 2. onChildAdded streams 3,000 children sequentially
      const totalItems = 3000;
      for (int i = 1; i <= totalItems; i++) {
        ref.emitChildAdded('p_$i', {
          'id': 'p_$i',
          'name': 'Stress Item $i',
          'price': i * 1000,
        });
      }

      // During rapid burst (at 20ms), debounce prevents re-rendering
      await Future.delayed(const Duration(milliseconds: 20));
      expect(emissions, isEmpty,
          reason: 'Rapid 3000 items stream must be debounced');

      // After 50ms debounce window (wait 60ms more -> 80ms total)
      await Future.delayed(const Duration(milliseconds: 60));

      expect(emissions.length, equals(1),
          reason:
              'Debounce must coalesce all 3,000 items into 1 initial batch');
      expect(emissions.first.length, equals(totalItems));

      // Verify take(1) subscription on valueStream was cancelled and did not leak
      expect(ref.valueStream.activeListeners, equals(0),
          reason:
              'emptyCheckSub with take(1) must be auto-cancelled after the first event');

      await sub.cancel();
    });

    test(
        'Cancellation Safety: Unsubscribing tears down all 5 sub-streams cleanly',
        () async {
      final productDs = ProductRemoteDataSource(mockDb, 'store_001');
      final ref = mockDb.getOrCreateRef('stores/store_001/products');

      final sub = productDs.watchAll().listen((_) {});

      expect(ref.childAddedStream.activeListeners, equals(1));
      expect(ref.childChangedStream.activeListeners, equals(1));
      expect(ref.childRemovedStream.activeListeners, equals(1));
      expect(ref.valueStream.activeListeners, equals(1));

      // Cancel subscription
      await sub.cancel();

      expect(ref.childAddedStream.activeListeners, equals(0));
      expect(ref.childChangedStream.activeListeners, equals(0));
      expect(ref.childRemovedStream.activeListeners, equals(0));
      expect(ref.valueStream.activeListeners, equals(0));
    });
  });
}
