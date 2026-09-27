import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/category_remote_data_source.dart';

import '../../support/firebase_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CategoryRemoteDataSource', () {
    late MockFirebaseDatabase mockDb;
    late CategoryRemoteDataSource dataSource;
    const categoryPath = 'shared_categories';

    setUp(() {
      mockDb = MockFirebaseDatabase();
      dataSource = CategoryRemoteDataSource(mockDb);
    });

    group('watchAll() - Bandwidth Optimization & Reactivity', () {
      test('No double fetch: .get() is NEVER called when subscribing to watchAll()', () async {
        final ref = mockDb.getOrCreateRef(categoryPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('cat_1', {'id': 'cat_1', 'name': 'Furniture'});
        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));

        expect(mockDb.wasGetCalled(categoryPath), isFalse);
        expect(mockDb.getCallCount(categoryPath), equals(0));

        await sub.cancel();
      });

      test('Debounce grouping: rapid burst of category events results in 1 initial emission', () async {
        final ref = mockDb.getOrCreateRef(categoryPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        for (int i = 1; i <= 20; i++) {
          ref.emitChildAdded('cat_$i', {'id': 'cat_$i', 'name': 'Category $i'});
        }

        await Future.delayed(const Duration(milliseconds: 20));
        expect(emissions, isEmpty);

        await Future.delayed(const Duration(milliseconds: 55));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(20));

        await sub.cancel();
      });

      test('emptyCheckSub: empty node emits [] without hanging', () async {
        final ref = mockDb.getOrCreateRef(categoryPath);
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
        final ref = mockDb.getOrCreateRef(categoryPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('cat_1', {'id': 'cat_1', 'name': 'Electronics'});
        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));

        final stopwatch = Stopwatch()..start();
        ref.emitChildChanged('cat_1', {'id': 'cat_1', 'name': 'Consumer Electronics'});
        await Future.delayed(const Duration(milliseconds: 10));
        stopwatch.stop();

        expect(emissions.length, equals(2));
        expect(emissions.last.first['name'], equals('Consumer Electronics'));
        expect(stopwatch.elapsedMilliseconds, lessThan(40));

        await sub.cancel();
      });

      test('Immediate emit on childRemoved: purges category from cache immediately', () async {
        final ref = mockDb.getOrCreateRef(categoryPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('cat_1', {'id': 'cat_1', 'name': 'Cat 1'});
        ref.emitChildAdded('cat_2', {'id': 'cat_2', 'name': 'Cat 2'});
        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(2));

        ref.emitChildRemoved('cat_1');
        await Future.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, equals(2));
        expect(emissions.last.length, equals(1));
        expect(emissions.last.first['id'], equals('cat_2'));

        await sub.cancel();
      });

      test('Stream cancellation tears down listeners and cancels debounce timer', () async {
        final ref = mockDb.getOrCreateRef(categoryPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        ref.emitChildAdded('cat_cancel', {'id': 'cat_cancel', 'name': 'Cancelling'});
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

    group('Hierarchical Category Tree Data Streaming', () {
      test('streams full hierarchical parent-child category tree structures', () async {
        final ref = mockDb.getOrCreateRef(categoryPath);
        final emissions = <List<Map>>[];
        final sub = dataSource.watchAll().listen(emissions.add);

        // Root category 1: Đồ gỗ & Nội thất
        ref.emitChildAdded('noi_that', {
          'id': 'noi_that',
          'name': 'Đồ gỗ & Nội thất',
          'parentId': null,
          'level': 0,
        });

        // Child category of noi_that: Bàn ăn
        ref.emitChildAdded('ban_an', {
          'id': 'ban_an',
          'name': 'Bàn ăn',
          'parentId': 'noi_that',
          'level': 1,
        });

        // Sub-child category of ban_an: Bàn ăn bên
        ref.emitChildAdded('ban_an_ben', {
          'id': 'ban_an_ben',
          'name': 'Bàn ăn bên',
          'parentId': 'ban_an',
          'level': 2,
        });

        // Root category 2: Thiết bị điện tử
        ref.emitChildAdded('dien_tu', {
          'id': 'dien_tu',
          'name': 'Thiết bị điện tử',
          'parentId': null,
          'level': 0,
        });

        // Child category of dien_tu: Smartphone
        ref.emitChildAdded('smartphone', {
          'id': 'smartphone',
          'name': 'Smartphone',
          'parentId': 'dien_tu',
          'level': 1,
        });

        await Future.delayed(const Duration(milliseconds: 65));

        expect(emissions.length, equals(1));
        final categories = emissions.first;
        expect(categories.length, equals(5));

        // Verify parent-child linkages
        final roots = categories.where((c) => c['parentId'] == null).toList();
        expect(roots.length, equals(2));
        expect(roots.map((c) => c['id']), containsAll(['noi_that', 'dien_tu']));

        final noiThatChildren = categories.where((c) => c['parentId'] == 'noi_that').toList();
        expect(noiThatChildren.length, equals(1));
        expect(noiThatChildren.first['id'], equals('ban_an'));

        final banAnChildren = categories.where((c) => c['parentId'] == 'ban_an').toList();
        expect(banAnChildren.length, equals(1));
        expect(banAnChildren.first['id'], equals('ban_an_ben'));

        await sub.cancel();
      });
    });

    group('Category CRUD Operations & Null Safety', () {
      test('fetchAll() returns categories from database', () async {
        mockDb.seedData(categoryPath, {
          'c1': {'id': 'c1', 'name': 'Root 1'},
          'c2': {'id': 'c2', 'name': 'Root 2'},
        });

        final list = await dataSource.fetchAll();
        expect(list.length, equals(2));
        final names = list.map((c) => c['name']).toList();
        expect(names, containsAll(['Root 1', 'Root 2']));
      });

      test('upsert() writes category data to database', () async {
        await dataSource.upsert('cat_new', {
          'id': 'cat_new',
          'name': 'New Category',
          'parentId': 'noi_that',
        });

        final snap = await mockDb.getOrCreateRef(categoryPath).child('cat_new').get();
        expect(snap.exists, isTrue);
        expect((snap.value as Map)['name'], equals('New Category'));
        expect((snap.value as Map)['parentId'], equals('noi_that'));
      });

      test('delete() removes category from database', () async {
        mockDb.seedData(categoryPath, {
          'cat_del': {'id': 'cat_del', 'name': 'To Delete'},
        });

        await dataSource.delete('cat_del');

        final snap = await mockDb.getOrCreateRef(categoryPath).child('cat_del').get();
        expect(snap.exists, isFalse);
      });

      test('null database safety: constructor without db behaves gracefully', () async {
        final nullDataSource = CategoryRemoteDataSource(null);

        // watchAll() should return empty stream
        final streamData = await nullDataSource.watchAll().toList();
        expect(streamData, isEmpty);

        // fetchAll() returns empty list
        final list = await nullDataSource.fetchAll();
        expect(list, isEmpty);

        // upsert and delete complete without error
        await expectLater(nullDataSource.upsert('any', {}), completes);
        await expectLater(nullDataSource.delete('any'), completes);
      });
    });
  });
}
