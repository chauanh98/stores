import 'dart:convert';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/notification_remote_data_source.dart';
import 'package:stores/data/repositories/notification_repository_impl.dart';
import 'package:stores/domain/entities/notification_item.dart';
import 'package:stores/domain/entities/notification_type.dart';

import '../support/firebase_test_harness.dart';

// =============================================================================
// ADVERSARIAL TEST HARNESS & SPY DEFINITIONS
// =============================================================================

class AdversarialSpyFirebaseDatabase extends MockFirebaseDatabase {
  final List<String> unboundedGetCalls = [];
  final List<Map<String, dynamic>> boundedGetCalls = [];
  final List<Map<String, dynamic>> constraintCalls = [];

  void recordUnboundedGet(String path) {
    unboundedGetCalls.add(path);
  }

  void recordBoundedGet(String path, Map<String, dynamic> details) {
    boundedGetCalls.add({'path': path, ...details});
  }

  void recordQueryConstraint(String path, String constraint, dynamic value) {
    constraintCalls.add({'path': path, 'constraint': constraint, 'value': value});
  }

  @override
  DatabaseReference ref([String? path]) {
    final cleanPath =
        (path != null && path.startsWith('/')) ? path.substring(1) : (path ?? '');
    requestedPaths.add(cleanPath);
    return references.putIfAbsent(
      cleanPath,
      () => AdversarialMockReference(
        path: cleanPath,
        recorder: recorder,
        parentDb: this,
      ),
    );
  }

  @override
  AdversarialMockReference getOrCreateRef(String path,
      {Map<String, dynamic>? initialData}) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    requestedPaths.add(cleanPath);
    final existing = references[cleanPath];
    if (existing != null && existing is AdversarialMockReference) {
      if (initialData != null) {
        existing.storeData.addAll(initialData);
      }
      return existing;
    }
    final created = AdversarialMockReference(
      path: cleanPath,
      recorder: recorder,
      parentDb: this,
      initialData: initialData,
    );
    references[cleanPath] = created;
    return created;
  }
}

class AdversarialMockReference extends MockDatabaseReference {
  final AdversarialSpyFirebaseDatabase parentDb;
  bool isUnboundedGetCalled = false;

  AdversarialMockReference({
    required super.path,
    required super.recorder,
    required this.parentDb,
    super.initialData,
    super.parent,
  });

  @override
  DatabaseReference child(String childPath) {
    final segments =
        childPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return this;

    AdversarialMockReference current = this;
    for (final seg in segments) {
      final childRef = current.children.putIfAbsent(
        seg,
        () {
          Map<String, dynamic> childStore = {};
          if (current.storeData[seg] is Map) {
            childStore =
                Map<String, dynamic>.from(current.storeData[seg] as Map);
          }
          final newChild = AdversarialMockReference(
            path: '${current.path}/$seg',
            recorder: recorder,
            parentDb: parentDb,
            initialData: childStore,
            parent: current,
          );
          parentDb.references['${current.path}/$seg'] = newChild;
          return newChild;
        },
      );
      current = childRef as AdversarialMockReference;
    }
    return current;
  }

  @override
  Query orderByChild(String key) {
    parentDb.recordQueryConstraint(path, 'orderByChild', key);
    return AdversarialMockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      orderedByChildKey: key,
      parentRef: this,
      parentDb: parentDb,
      queryValueStream: valueStream,
      queryChildAddedStream: childAddedStream,
      queryChildChangedStream: childChangedStream,
      queryChildRemovedStream: childRemovedStream,
    );
  }

  @override
  Query limitToLast(int limit) {
    parentDb.recordQueryConstraint(path, 'limitToLast', limit);
    return AdversarialMockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      orderedByChildKey: orderedByChildKey,
      limitLast: limit,
      parentRef: this,
      parentDb: parentDb,
      queryValueStream: valueStream,
      queryChildAddedStream: childAddedStream,
      queryChildChangedStream: childChangedStream,
      queryChildRemovedStream: childRemovedStream,
    );
  }

  @override
  Future<DataSnapshot> get() async {
    isUnboundedGetCalled = true;
    parentDb.recordUnboundedGet(path);
    return super.get();
  }

  @override
  Future<void> update(Map<String, dynamic> value) async {
    recorder.record('update', path: path, value: value);
    // Apply multi-path updates so in-memory store reflects changes
    for (final entry in value.entries) {
      if (entry.key.contains('/')) {
        final parts = entry.key.split('/');
        final childKey = parts[0];
        final field = parts[1];
        if (storeData[childKey] is Map) {
          (storeData[childKey] as Map)[field] = entry.value;
        } else {
          storeData[childKey] = {field: entry.value};
        }
      } else {
        storeData[entry.key] = entry.value;
      }
    }
  }
}

class AdversarialMockQuery extends MockQuery {
  final AdversarialMockReference? parentRef;
  final AdversarialSpyFirebaseDatabase parentDb;

  AdversarialMockQuery({
    required super.path,
    required super.storeData,
    required super.recorder,
    required this.parentDb,
    this.parentRef,
    super.orderedByChildKey,
    super.startRange,
    super.endRange,
    super.equalToVal,
    super.limitFirst,
    super.limitLast,
    super.queryValueStream,
    super.queryChildAddedStream,
    super.queryChildChangedStream,
    super.queryChildRemovedStream,
  });

  @override
  Query orderByChild(String key) {
    parentDb.recordQueryConstraint(path, 'orderByChild', key);
    return AdversarialMockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      parentRef: parentRef,
      parentDb: parentDb,
      orderedByChildKey: key,
      startRange: startRange,
      endRange: endRange,
      equalToVal: equalToVal,
      limitFirst: limitFirst,
      limitLast: limitLast,
      queryValueStream: queryValueStream,
      queryChildAddedStream: queryChildAddedStream,
      queryChildChangedStream: queryChildChangedStream,
      queryChildRemovedStream: queryChildRemovedStream,
    );
  }

  @override
  Query limitToLast(int limit) {
    parentDb.recordQueryConstraint(path, 'limitToLast', limit);
    return AdversarialMockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      parentRef: parentRef,
      parentDb: parentDb,
      orderedByChildKey: orderedByChildKey,
      startRange: startRange,
      endRange: endRange,
      equalToVal: equalToVal,
      limitFirst: limitFirst,
      limitLast: limit,
      queryValueStream: queryValueStream,
      queryChildAddedStream: queryChildAddedStream,
      queryChildChangedStream: queryChildChangedStream,
      queryChildRemovedStream: queryChildRemovedStream,
    );
  }

  @override
  Query equalTo(dynamic value, {String? key}) {
    parentDb.recordQueryConstraint(path, 'equalTo', value);
    return AdversarialMockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      parentRef: parentRef,
      parentDb: parentDb,
      orderedByChildKey: orderedByChildKey,
      startRange: value,
      endRange: value,
      equalToVal: value,
      limitFirst: limitFirst,
      limitLast: limitLast,
      queryValueStream: queryValueStream,
      queryChildAddedStream: queryChildAddedStream,
      queryChildChangedStream: queryChildChangedStream,
      queryChildRemovedStream: queryChildRemovedStream,
    );
  }

  @override
  Future<DataSnapshot> get() async {
    parentDb.recordBoundedGet(path, {
      'orderedByChildKey': orderedByChildKey,
      'limitLast': limitLast,
      'equalToVal': equalToVal,
    });
    return super.get();
  }
}

// =============================================================================
// MAIN ADVERSARIAL TEST SUITE
// =============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storeId = 'store_challenger_001';
  const notifPath = 'stores/$storeId/notifications';

  group('Adversarial M1-2: RTDB Query Constraints & Egress Bypass Resistance', () {
    late AdversarialSpyFirebaseDatabase spyDb;
    late NotificationRemoteDataSource dataSource;

    setUp(() {
      spyDb = AdversarialSpyFirebaseDatabase();
      dataSource = NotificationRemoteDataSource(spyDb);
    });

    test('watchNotifications strictly applies limitToLast(50) and orderByChild(createdAt)', () async {
      final stream = dataSource.watchNotifications(storeId);
      final sub = stream.listen((_) {});

      // Verify that query constraints were recorded
      final orderCalls = spyDb.constraintCalls
          .where((c) => c['constraint'] == 'orderByChild' && c['value'] == 'createdAt');
      final limitCalls = spyDb.constraintCalls
          .where((c) => c['constraint'] == 'limitToLast' && c['value'] == 50);

      expect(orderCalls.isNotEmpty, isTrue,
          reason: 'watchNotifications must sort by createdAt on RTDB server');
      expect(limitCalls.isNotEmpty, isTrue,
          reason: 'watchNotifications must enforce limitToLast(50) by default');

      await sub.cancel();
    });

    test('watchNotifications sanitizes invalid or negative limit to default 50', () async {
      // Adversarial attempt to bypass limit with 0 or negative values
      final subZero = dataSource.watchNotifications(storeId, limit: 0).listen((_) {});
      final subNeg = dataSource.watchNotifications(storeId, limit: -99).listen((_) {});

      final limit50Calls = spyDb.constraintCalls
          .where((c) => c['constraint'] == 'limitToLast' && c['value'] == 50)
          .length;

      // Both zero and negative limit must be coerced to 50
      expect(limit50Calls, greaterThanOrEqualTo(2),
          reason: 'Invalid or negative limits must be clamped to 50 to prevent unbounded egress');

      await subZero.cancel();
      await subNeg.cancel();
    });

    test('fetchNotifications executes bounded get() and NEVER calls unbounded parent.get()', () async {
      final parentRef = spyDb.getOrCreateRef(notifPath);
      parentRef.storeData['n1'] = {
        'id': 'n1',
        'title': 'Test 1',
        'createdAt': '2026-10-04T12:00:00Z',
        'isRead': false,
      };

      final results = await dataSource.fetchNotifications(storeId);

      expect(results.length, equals(1));
      // Unbounded root get must be strictly 0
      expect(spyDb.unboundedGetCalls.where((p) => p == notifPath), isEmpty,
          reason: 'Parent node stores/$storeId/notifications must NEVER be fetched unbounded');

      // Exactly 1 bounded get with limitToLast(50)
      expect(spyDb.boundedGetCalls.length, equals(1));
      final boundedCall = spyDb.boundedGetCalls.first;
      expect(boundedCall['orderedByChildKey'], equals('createdAt'));
      expect(boundedCall['limitLast'], equals(50));
    });

    test('fetchNotifications sanitizes negative limit to 50', () async {
      await dataSource.fetchNotifications(storeId, limit: -5);

      final boundedCall = spyDb.boundedGetCalls.last;
      expect(boundedCall['limitLast'], equals(50),
          reason: 'Negative limit must be clamped to 50 in fetchNotifications');
    });

    test('NotificationRepositoryImpl.watchNotifications propagates default and custom limit', () async {
      final repo = NotificationRepositoryImpl(dataSource);

      // Default limit 50
      final subDefault = repo.watchNotifications(storeId).listen((_) {});
      expect(
        spyDb.constraintCalls.any((c) => c['constraint'] == 'limitToLast' && c['value'] == 50),
        isTrue,
      );
      await subDefault.cancel();

      // Custom limit 25
      final subCustom = repo.watchNotifications(storeId, limit: 25).listen((_) {});
      expect(
        spyDb.constraintCalls.any((c) => c['constraint'] == 'limitToLast' && c['value'] == 25),
        isTrue,
      );
      await subCustom.cancel();
    });

    test('database.rules.json contains .indexOn for createdAt, isRead, type on notifications', () {
      final file = File('database.rules.json');
      expect(file.existsSync(), isTrue, reason: 'database.rules.json must exist');
      final content = file.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;

      final stores = json['rules']?['stores']?[r'$storeId'] as Map<String, dynamic>?;
      expect(stores, isNotNull);

      final notifRules = stores?['notifications'] as Map<String, dynamic>?;
      expect(notifRules, isNotNull,
          reason: 'notifications node must be defined in database.rules.json');

      final indexOn = (notifRules?['.indexOn'] as List?)?.cast<String>();
      expect(indexOn, isNotNull);
      expect(indexOn, containsAll(['createdAt', 'isRead', 'type']),
          reason: 'All query fields (createdAt, isRead, type) must be indexed on RTDB server');
    });
  });

  group('Adversarial M1-2: Stream Debounce Stress Testing (100+ Rapid Events)', () {
    late AdversarialSpyFirebaseDatabase spyDb;
    late NotificationRemoteDataSource dataSource;

    setUp(() {
      spyDb = AdversarialSpyFirebaseDatabase();
      dataSource = NotificationRemoteDataSource(spyDb);
    });

    test('120 rapid events burst in <10ms coalesces into exactly 1 emission after 250ms silence', () async {
      final parentRef = spyDb.getOrCreateRef(notifPath);
      final stream = dataSource.watchNotifications(storeId);
      final emissions = <List<Map<String, dynamic>>>[];
      final sub = stream.listen(emissions.add);

      // Burst 120 rapid value updates
      final stopwatch = Stopwatch()..start();
      for (int i = 1; i <= 120; i++) {
        parentRef.storeData['n_$i'] = {
          'id': 'n_$i',
          'title': 'Event $i',
          'body': 'Body $i',
          'createdAt': DateTime(2026, 10, 4, 12, 0, i).toIso8601String(),
          'isRead': false,
          'type': 'order_created',
        };
        parentRef.emitValue(Map<String, dynamic>.from(parentRef.storeData));
      }
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: '120 updates must be fired in a tight rapid burst');

      // Before debounce window (at 20ms and 150ms) -> ZERO emissions
      await Future.delayed(const Duration(milliseconds: 20));
      expect(emissions, isEmpty, reason: 'Debounce must suppress intermediate emissions at 20ms');

      await Future.delayed(const Duration(milliseconds: 130));
      expect(emissions, isEmpty, reason: 'Debounce must suppress intermediate emissions at 150ms');

      // Wait until silence window passes (250ms total silence from last event)
      await Future.delayed(const Duration(milliseconds: 160)); // total > 310ms since burst
      expect(emissions.length, equals(1),
          reason: '120 rapid events must coalesce into exactly ONE aggregated emission');
      expect(emissions.single.length, equals(120),
          reason: 'Aggregated emission must contain all 120 items');

      await sub.cancel();
    });

    test('Two separated bursts yield exactly 2 emissions with respective counts', () async {
      final parentRef = spyDb.getOrCreateRef(notifPath);
      final stream = dataSource.watchNotifications(storeId);
      final emissions = <List<Map<String, dynamic>>>[];
      final sub = stream.listen(emissions.add);

      // Burst 1: 50 events
      for (int i = 1; i <= 50; i++) {
        parentRef.storeData['burst1_$i'] = {
          'id': 'burst1_$i',
          'title': 'Burst1 Item $i',
          'createdAt': '2026-10-04T12:00:00Z',
          'isRead': false,
          'type': 'order_created',
        };
      }
      parentRef.emitValue(Map<String, dynamic>.from(parentRef.storeData));

      // Wait for burst 1 debounce to fire (300ms > 250ms)
      await Future.delayed(const Duration(milliseconds: 300));
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(50));

      // Burst 2: 60 more events
      for (int i = 1; i <= 60; i++) {
        parentRef.storeData['burst2_$i'] = {
          'id': 'burst2_$i',
          'title': 'Burst2 Item $i',
          'createdAt': '2026-10-04T12:01:00Z',
          'isRead': false,
          'type': 'inventory_imported',
        };
      }
      parentRef.emitValue(Map<String, dynamic>.from(parentRef.storeData));

      // Wait for burst 2 debounce to fire
      await Future.delayed(const Duration(milliseconds: 300));
      expect(emissions.length, equals(2));
      expect(emissions.last.length, equals(110));

      await sub.cancel();
    });

    test('Repository layer handles 100 rapid events, coalesces to 1, and sorts newest first', () async {
      final parentRef = spyDb.getOrCreateRef(notifPath);
      final repo = NotificationRepositoryImpl(dataSource);
      final stream = repo.watchNotifications(storeId);
      final domainEmissions = <List<NotificationItem>>[];
      final sub = stream.listen(domainEmissions.add);

      // Add 100 notifications with scrambled creation dates
      for (int i = 1; i <= 100; i++) {
        // Vary seconds deliberately to verify sort order
        final sec = (i * 37) % 60;
        parentRef.storeData['item_$i'] = {
          'id': 'item_$i',
          'title': 'Notif $i',
          'body': 'Content $i',
          'createdAt': DateTime(2026, 10, 4, 12, 0, sec).toIso8601String(),
          'isRead': i % 2 == 0,
          'type': i % 3 == 0 ? 'order_created' : 'inventory_imported',
        };
        parentRef.emitValue(Map<String, dynamic>.from(parentRef.storeData));
      }

      await Future.delayed(const Duration(milliseconds: 320));

      expect(domainEmissions.length, equals(1),
          reason: 'Repository stream must also emit exactly once after 100 rapid events');
      final items = domainEmissions.single;
      expect(items.length, equals(100));

      // Assert strictly sorted newest first
      for (int j = 0; j < items.length - 1; j++) {
        expect(items[j].createdAt.isAfter(items[j + 1].createdAt) ||
               items[j].createdAt.isAtSameMomentAs(items[j + 1].createdAt), isTrue,
            reason: 'NotificationItem stream must strictly be sorted newest first');
      }

      await sub.cancel();
    });

    test('Subscription cancellation cancels debounce timer cleanly without leaks or errors', () async {
      final parentRef = spyDb.getOrCreateRef(notifPath);
      final stream = dataSource.watchNotifications(storeId);
      final emissions = <List<Map<String, dynamic>>>[];
      final sub = stream.listen(emissions.add);

      // Emit 50 events
      for (int i = 1; i <= 50; i++) {
        parentRef.storeData['leak_test_$i'] = {
          'id': 'leak_test_$i',
          'title': 'Leak Test $i',
          'createdAt': '2026-10-04T12:00:00Z',
          'isRead': false,
        };
      }
      parentRef.emitValue(Map<String, dynamic>.from(parentRef.storeData));

      // Cancel at 50ms (well before 250ms debounce timer)
      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      // Wait beyond the 250ms window
      await Future.delayed(const Duration(milliseconds: 300));
      expect(emissions, isEmpty,
          reason: 'No emissions should fire after subscription cancellation');
    });
  });

  group('Adversarial M1-2: markAllAsRead Atomic Batch Update Stress Test', () {
    late AdversarialSpyFirebaseDatabase spyDb;
    late NotificationRemoteDataSource dataSource;

    setUp(() {
      spyDb = AdversarialSpyFirebaseDatabase();
      dataSource = NotificationRemoteDataSource(spyDb);
    });

    test('0 unread records: performs 0 update operations (0 egress / 0 writes)', () async {
      // Empty store
      await dataSource.markAllAsRead(storeId);
      expect(spyDb.recorder.hasCalled('update', path: notifPath), isFalse,
          reason: 'markAllAsRead must not call update when store has 0 records');

      // Store with only already-read records
      final parentRef = spyDb.getOrCreateRef(notifPath);
      parentRef.storeData['read_1'] = {'id': 'read_1', 'isRead': true, 'title': 'R1'};
      parentRef.storeData['read_2'] = {'id': 'read_2', 'isRead': true, 'title': 'R2'};

      await dataSource.markAllAsRead(storeId);
      expect(spyDb.recorder.hasCalled('update', path: notifPath), isFalse,
          reason: 'markAllAsRead must not call update when all records are already read');
    });

    test('1 unread record: queries unread records and executes exactly 1 atomic update', () async {
      final parentRef = spyDb.getOrCreateRef(notifPath);
      parentRef.storeData['r1'] = {'id': 'r1', 'isRead': true, 'title': 'Already Read'};
      parentRef.storeData['u1'] = {'id': 'u1', 'isRead': false, 'title': 'Single Unread'};

      await dataSource.markAllAsRead(storeId);

      expect(spyDb.recorder.hasCalled('update', path: notifPath), isTrue);
      final updateCalls = spyDb.recorder.callsFor('update', path: notifPath);
      expect(updateCalls.length, equals(1), reason: 'Must execute exactly 1 update call');

      final payload = updateCalls.first.value as Map<String, dynamic>;
      expect(payload.length, equals(1), reason: 'Payload must only update the 1 unread record');
      expect(payload['u1/isRead'], isTrue);
      expect(payload.containsKey('r1/isRead'), isFalse, reason: 'Already read item must be excluded');

      // In-memory verification
      expect((parentRef.storeData['u1'] as Map)['isRead'], isTrue);
    });

    test('75 unread + 25 read records (50+ stress): executes 1 atomic multi-path update', () async {
      final parentRef = spyDb.getOrCreateRef(notifPath);

      // Seed 75 unread records
      for (int i = 1; i <= 75; i++) {
        parentRef.storeData['unread_$i'] = {
          'id': 'unread_$i',
          'isRead': false,
          'title': 'Unread $i',
          'createdAt': '2026-10-04T12:00:00Z',
        };
      }
      // Seed 25 read records
      for (int i = 1; i <= 25; i++) {
        parentRef.storeData['read_$i'] = {
          'id': 'read_$i',
          'isRead': true,
          'title': 'Read $i',
          'createdAt': '2026-10-04T11:00:00Z',
        };
      }

      await dataSource.markAllAsRead(storeId);

      // Verify query constraint: must query isRead == false with limitToLast(100)
      final equalCalls = spyDb.constraintCalls
          .where((c) => c['constraint'] == 'equalTo' && c['value'] == false);
      final limitCalls = spyDb.constraintCalls
          .where((c) => c['constraint'] == 'limitToLast' && c['value'] == 100);
      expect(equalCalls.isNotEmpty, isTrue, reason: 'Must filter by isRead == false');
      expect(limitCalls.isNotEmpty, isTrue, reason: 'Must bound unread query with limitToLast(100)');

      // Verify ATOMIC multi-path update: exactly 1 update call (NOT 75 calls)
      final updateCalls = spyDb.recorder.callsFor('update', path: notifPath);
      expect(updateCalls.length, equals(1),
          reason: 'Must update 75 records in exactly ONE atomic multi-path batch');

      final payload = updateCalls.first.value as Map<String, dynamic>;
      expect(payload.length, equals(75),
          reason: 'Payload must contain exactly 75 unread entries');

      // Verify all unread keys are present and marked true
      for (int i = 1; i <= 75; i++) {
        expect(payload['unread_$i/isRead'], isTrue);
        expect((parentRef.storeData['unread_$i'] as Map)['isRead'], isTrue);
      }

      // Verify none of the 25 already-read records are in the payload
      for (int i = 1; i <= 25; i++) {
        expect(payload.containsKey('read_$i/isRead'), isFalse);
      }
    });

    test('Snapshot returned as List format (numeric keys) cleanly updates multi-path', () async {
      final parentRef = spyDb.getOrCreateRef(notifPath);
      // Simulate List format from RTDB
      parentRef.storeData['0'] = {'id': '0', 'isRead': false, 'title': 'L0'};
      parentRef.storeData['1'] = {'id': '1', 'isRead': false, 'title': 'L1'};

      await dataSource.markAllAsRead(storeId);

      final updateCalls = spyDb.recorder.callsFor('update', path: notifPath);
      expect(updateCalls.isNotEmpty, isTrue);
      final payload = updateCalls.first.value as Map<String, dynamic>;
      expect(payload['0/isRead'], isTrue);
      expect(payload['1/isRead'], isTrue);
    });
  });

  group('Adversarial M1-2: Deletion Behavior & Target Isolation', () {
    late AdversarialSpyFirebaseDatabase spyDb;
    late NotificationRemoteDataSource dataSource;

    setUp(() {
      spyDb = AdversarialSpyFirebaseDatabase();
      dataSource = NotificationRemoteDataSource(spyDb);
    });

    test('deleteNotification calls remove() strictly on target child node', () async {
      final parentRef = spyDb.getOrCreateRef(notifPath);
      parentRef.storeData['keep_1'] = {'id': 'keep_1', 'title': 'Keep 1'};
      parentRef.storeData['target_del'] = {'id': 'target_del', 'title': 'To Delete'};
      parentRef.storeData['keep_2'] = {'id': 'keep_2', 'title': 'Keep 2'};

      await dataSource.deleteNotification(storeId, 'target_del');

      // Target child node must be removed
      expect(spyDb.recorder.hasCalled('remove', path: '$notifPath/target_del'), isTrue);

      // Parent node must NEVER be removed
      final parentExactRemoveCalls =
          spyDb.recorder.calls.where((c) => c.method == 'remove' && c.path == notifPath);
      expect(parentExactRemoveCalls, isEmpty,
          reason: 'Parent notifications collection must NEVER be removed');

      // Sibling nodes must remain intact
      expect(parentRef.storeData.containsKey('target_del'), isFalse);
      expect(parentRef.storeData.containsKey('keep_1'), isTrue);
      expect(parentRef.storeData.containsKey('keep_2'), isTrue);
    });

    test('deleteNotification is idempotent on non-existent node without throwing', () async {
      await expectLater(
        dataSource.deleteNotification(storeId, 'non_existent_id_999'),
        completes,
      );
    });

    test('Reactive stream reflects item deletion after debounce window', () async {
      final parentRef = spyDb.getOrCreateRef(notifPath);
      parentRef.storeData['n_live_1'] = {
        'id': 'n_live_1',
        'title': 'Live 1',
        'createdAt': '2026-10-04T12:00:00Z',
        'isRead': false,
      };
      parentRef.storeData['n_live_2'] = {
        'id': 'n_live_2',
        'title': 'Live 2',
        'createdAt': '2026-10-04T12:01:00Z',
        'isRead': false,
      };

      final stream = dataSource.watchNotifications(storeId);
      final emissions = <List<Map<String, dynamic>>>[];
      final sub = stream.listen(emissions.add);

      // Emit initial 2 items
      parentRef.emitValue(Map<String, dynamic>.from(parentRef.storeData));
      await Future.delayed(const Duration(milliseconds: 300));
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(2));

      // Delete 1 item and emit new snapshot
      await dataSource.deleteNotification(storeId, 'n_live_1');
      parentRef.emitValue(Map<String, dynamic>.from(parentRef.storeData));

      await Future.delayed(const Duration(milliseconds: 300));
      expect(emissions.length, equals(2));
      expect(emissions.last.length, equals(1));
      expect(emissions.last.first['id'], equals('n_live_2'));

      await sub.cancel();
    });

    test('NotificationRepositoryImpl delegates deleteNotification correctly', () async {
      final repo = NotificationRepositoryImpl(dataSource);
      final parentRef = spyDb.getOrCreateRef(notifPath);
      parentRef.storeData['del_repo'] = {'id': 'del_repo', 'title': 'Repo Delete'};

      await repo.deleteNotification(storeId: storeId, id: 'del_repo');

      expect(spyDb.recorder.hasCalled('remove', path: '$notifPath/del_repo'), isTrue);
      expect(parentRef.storeData.containsKey('del_repo'), isFalse);
    });
  });

  group('Adversarial M1-2: Egress Payload Sanitization & Fault Tolerance', () {
    late AdversarialSpyFirebaseDatabase spyDb;
    late NotificationRemoteDataSource dataSource;

    setUp(() {
      spyDb = AdversarialSpyFirebaseDatabase();
      dataSource = NotificationRemoteDataSource(spyDb);
    });

    test('Snapshot with null, primitive, or malformed values handles gracefully', () async {
      final parentRef = spyDb.getOrCreateRef(notifPath);
      parentRef.storeData['corrupted_null'] = null;
      parentRef.storeData['corrupted_string'] = 'invalid_primitive';
      parentRef.storeData['valid'] = {
        'id': 'valid_1',
        'title': 'Valid Item',
        'createdAt': '2026-10-04T12:00:00Z',
        'isRead': false,
      };

      final results = await dataSource.fetchNotifications(storeId);

      // Corrupted items must be filtered out safely without throwing
      expect(results.length, equals(1));
      expect(results.first['id'], equals('valid_1'));
    });

    test('Missing ID in map adopts parent snapshot key without losing identification', () async {
      final parentRef = spyDb.getOrCreateRef(notifPath);
      parentRef.storeData['auto_key_123'] = {
        // Missing 'id' field
        'title': 'Missing ID Field',
        'createdAt': '2026-10-04T12:00:00Z',
        'isRead': false,
      };

      final results = await dataSource.fetchNotifications(storeId);

      expect(results.length, equals(1));
      expect(results.first['id'], equals('auto_key_123'),
          reason: 'Notification without id field must fallback to snapshot key');
    });

    test('Round-trip domain translation preserves category and type fidelity', () async {
      final repo = NotificationRepositoryImpl(dataSource);
      final parentRef = spyDb.getOrCreateRef(notifPath);

      final typesToTest = [
        NotificationType.orderCreated,
        NotificationType.orderUpdated,
        NotificationType.orderCancelled,
        NotificationType.orderReturn,
        NotificationType.inventoryImported,
        NotificationType.customerCreated,
        NotificationType.customerDebtAdded,
        NotificationType.customerDebtPaid,
      ];

      for (int i = 0; i < typesToTest.length; i++) {
        final type = typesToTest[i];
        parentRef.storeData['item_$i'] = {
          'id': 'item_$i',
          'title': 'Title $i',
          'body': 'Body $i',
          'createdAt': '2026-10-04T12:0$i:00Z',
          'isRead': false,
          'type': type.value,
        };
      }

      final stream = repo.watchNotifications(storeId);
      final emissions = <List<NotificationItem>>[];
      final sub = stream.listen(emissions.add);

      parentRef.emitValue(Map<String, dynamic>.from(parentRef.storeData));
      await Future.delayed(const Duration(milliseconds: 300));

      expect(emissions.isNotEmpty, isTrue);
      final items = emissions.first;
      expect(items.length, equals(typesToTest.length));

      for (final item in items) {
        expect(item.type, isNotNull);
        expect(item.category, isNotNull);
      }

      await sub.cancel();
    });
  });
}
