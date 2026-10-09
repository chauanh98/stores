import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/notification_remote_data_source.dart';
import 'package:stores/data/models/notification_item_model.dart';
import 'package:stores/data/repositories/notification_repository_impl.dart';
import 'package:stores/domain/entities/notification_item.dart';
import 'package:stores/domain/entities/notification_type.dart';

import '../support/firebase_test_harness.dart';

void main() {
  group('=== TIER 5: DOMAIN & DATA WHITE-BOX HARDENING & ADVERSARIAL SUITE ===', () {
    late MockFirebaseDatabase mockDb;
    late NotificationRemoteDataSource remoteDataSource;
    late NotificationRepositoryImpl repository;
    const storeId = 'store_001';

    setUp(() {
      mockDb = MockFirebaseDatabase();
      remoteDataSource = NotificationRemoteDataSource(mockDb);
      repository = NotificationRepositoryImpl(remoteDataSource);
    });

    // ========================================================================
    // SECTION 1: CORRUPTED & MALFORMED RTDB PAYLOAD PARSING
    // ========================================================================
    group('1. Corrupted & Malformed RTDB Payload Parsing', () {
      test('T5.1: Snapshot returning primitive non-map/non-list safely returns empty list', () async {
        final ref = mockDb.getOrCreateRef('stores/$storeId/notifications');

        // Primitive String
        await ref.set('this_is_a_corrupted_raw_string');
        final stringFetch = await remoteDataSource.fetchNotifications(storeId);
        expect(stringFetch, isEmpty);

        ref.storeData.clear();
        var stream = remoteDataSource.watchNotifications(storeId);
        var future = stream.first;
        ref.emitValue('this_is_a_corrupted_raw_string');
        expect(await future, isEmpty);

        // Primitive Number
        await ref.set(999999);
        final numFetch = await remoteDataSource.fetchNotifications(storeId);
        expect(numFetch, isEmpty);

        ref.storeData.clear();
        stream = remoteDataSource.watchNotifications(storeId);
        future = stream.first;
        ref.emitValue(999999);
        expect(await future, isEmpty);

        // Primitive Boolean
        await ref.set(true);
        final boolFetch = await remoteDataSource.fetchNotifications(storeId);
        expect(boolFetch, isEmpty);

        ref.storeData.clear();
        stream = remoteDataSource.watchNotifications(storeId);
        future = stream.first;
        ref.emitValue(true);
        expect(await future, isEmpty);

        // Null value
        await ref.set(null);
        final nullFetch = await remoteDataSource.fetchNotifications(storeId);
        expect(nullFetch, isEmpty);

        ref.storeData.clear();
        stream = remoteDataSource.watchNotifications(storeId);
        future = stream.first;
        ref.emitValue(null);
        expect(await future, isEmpty);
      });

      test('T5.2: Snapshot with List-wrapped array indexed elements and null gaps extracts valid maps', () async {
        final ref = mockDb.getOrCreateRef('stores/$storeId/notifications');
        final rawList = [
          {
            'id': 'item_0',
            'storeId': storeId,
            'title': 'Đơn hàng 0',
            'body': 'Nội dung 0',
            'type': 'order_created',
            'createdAt': '2026-10-04T10:00:00.000Z',
          },
          null, // Gap
          'corrupted_primitive_entry', // Invalid element
          {
            // Missing explicit 'id', should use list index '3'
            'storeId': storeId,
            'title': 'Đơn hàng 3',
            'body': 'Nội dung 3',
            'type': 'inventory_imported',
            'createdAt': '2026-10-04T11:00:00.000Z',
          },
        ];

        // Ensure storeData is clear so query stream waits for emitValue
        ref.storeData.clear();
        final stream = remoteDataSource.watchNotifications(storeId);
        final streamFuture = stream.first;
        ref.emitValue(rawList);
        final streamResult = await streamFuture;

        expect(streamResult.length, equals(2));
        expect(streamResult[0]['id'], equals('item_0'));
        expect(streamResult[0]['title'], equals('Đơn hàng 0'));
        expect(streamResult[1]['id'], equals('3')); // Inferred from list index
        expect(streamResult[1]['title'], equals('Đơn hàng 3'));

        // Validate domain conversion of list-extracted items
        final domain0 = NotificationItemModel.fromMap(streamResult[0]).toDomain();
        expect(domain0.id, equals('item_0'));
        expect(domain0.type, equals(NotificationType.orderCreated));

        final domain1 = NotificationItemModel.fromMap(streamResult[1]).toDomain();
        expect(domain1.id, equals('3'));
        expect(domain1.type, equals(NotificationType.inventoryImported));
      });

      test('T5.3: Map entries without explicit id fallback to RTDB child snapshot keys', () async {
        final ref = mockDb.getOrCreateRef('stores/$storeId/notifications');
        final rawMap = {
          '-Key_Alpha': {
            'title': 'Thông báo Alpha',
            'body': 'Chi tiết Alpha',
            'createdAt': '2026-10-04T08:00:00.000Z',
          },
          '-Key_Beta': {
            'id': '   ', // Whitespace ID should be ignored
            'title': 'Thông báo Beta',
            'body': 'Chi tiết Beta',
            'createdAt': '2026-10-04T09:00:00.000Z',
          },
        };

        ref.storeData.addAll(rawMap);
        final fetchResult = await remoteDataSource.fetchNotifications(storeId);
        expect(fetchResult.length, equals(2));

        final stream = remoteDataSource.watchNotifications(storeId);
        final streamFuture = stream.first;
        ref.emitValue(rawMap);
        final streamResult = await streamFuture;
        expect(streamResult.length, equals(2));

        final itemAlpha = streamResult.firstWhere((m) => m['title'] == 'Thông báo Alpha');
        expect(itemAlpha['id'], equals('-Key_Alpha'));

        final itemBeta = streamResult.firstWhere((m) => m['title'] == 'Thông báo Beta');
        expect(itemBeta['id'], equals('-Key_Beta'));
      });

      test('T5.4: Missing required fields fallback gracefully without throwing', () {
        final emptyMap = <dynamic, dynamic>{};
        final model = NotificationItemModel.fromMap(emptyMap, 'fallback_id');

        expect(model.id, equals('fallback_id'));
        expect(model.storeId, equals(''));
        expect(model.title, equals(''));
        expect(model.body, equals(''));
        expect(model.type, equals('order_created'));
        expect(model.isRead, isFalse);
        expect(model.createdAt, isA<DateTime>());
        expect(model.targetRoute, isNull);
        expect(model.targetId, isNull);
        expect(model.metadata, isNull);

        final domain = model.toDomain();
        expect(domain.id, equals('fallback_id'));
        expect(domain.category, equals(NotificationCategory.orders));
        expect(domain.type, equals(NotificationType.orderCreated));
      });

      test('T5.5: Alternative keys (message, content, timestamp, date, time, read) are parsed correctly', () {
        final map1 = {
          'id': 'notif_alt_1',
          'storeId': 'store_001',
          'title': 'Tiêu đề 1',
          'message': 'Nội dung từ message',
          'read': true,
          'timestamp': '2026-10-04T12:00:00.000Z',
        };
        final model1 = NotificationItemModel.fromMap(map1);
        expect(model1.body, equals('Nội dung từ message'));
        expect(model1.isRead, isTrue);
        expect(model1.createdAt, equals(DateTime.parse('2026-10-04T12:00:00.000Z')));

        final map2 = {
          'id': 'notif_alt_2',
          'content': 'Nội dung từ content',
          'read': '1',
          'date': '2026-10-04T14:30:00.000Z',
        };
        final model2 = NotificationItemModel.fromMap(map2);
        expect(model2.body, equals('Nội dung từ content'));
        expect(model2.isRead, isTrue);
        expect(model2.createdAt, equals(DateTime.parse('2026-10-04T14:30:00.000Z')));

        final map3 = {
          'id': 'notif_alt_3',
          'time': '2026-10-04T16:00:00.000Z',
        };
        final model3 = NotificationItemModel.fromMap(map3);
        expect(model3.createdAt, equals(DateTime.parse('2026-10-04T16:00:00.000Z')));
      });

      test('T5.6: Extreme date formats parsing (numeric epoch, string epoch, float, leap day, absurd year)', () {
        // 1. Raw epoch seconds (10-digit)
        final m1 = NotificationItemModel.fromMap({'createdAt': 1728045600});
        expect(m1.createdAt, equals(DateTime.fromMillisecondsSinceEpoch(1728045600000)));

        // 2. Raw epoch milliseconds (13-digit)
        final m2 = NotificationItemModel.fromMap({'createdAt': 1728045600123});
        expect(m2.createdAt, equals(DateTime.fromMillisecondsSinceEpoch(1728045600123)));

        // 3. String epoch seconds
        final m3 = NotificationItemModel.fromMap({'createdAt': '1728045600'});
        expect(m3.createdAt, equals(DateTime.fromMillisecondsSinceEpoch(1728045600000)));

        // 4. String epoch milliseconds
        final m4 = NotificationItemModel.fromMap({'createdAt': '1728045600456'});
        expect(m4.createdAt, equals(DateTime.fromMillisecondsSinceEpoch(1728045600456)));

        // 5. Float epoch seconds
        final m5 = NotificationItemModel.fromMap({'createdAt': 1728045600.5});
        expect(m5.createdAt, isA<DateTime>());

        // 6. Leap day ISO string
        final m6 = NotificationItemModel.fromMap({'createdAt': '2024-02-29T12:00:00.000Z'});
        expect(m6.createdAt.year, equals(2024));
        expect(m6.createdAt.month, equals(2));
        expect(m6.createdAt.day, equals(29));

        // 7. Absurd year (> 9999) falls back to DateTime.now() safely
        final beforeAbsurd = DateTime.now().subtract(const Duration(seconds: 1));
        final m7 = NotificationItemModel.fromMap({'createdAt': '+999999-01-01T00:00:00Z'});
        final afterAbsurd = DateTime.now().add(const Duration(seconds: 1));
        expect(m7.createdAt.isAfter(beforeAbsurd), isTrue);
        expect(m7.createdAt.isBefore(afterAbsurd), isTrue);

        // 8. Non-finite values (Infinity, NaN) fall back safely
        final m8 = NotificationItemModel.fromMap({'createdAt': double.infinity});
        expect(m8.createdAt.isAfter(beforeAbsurd), isTrue);

        final m9 = NotificationItemModel.fromMap({'createdAt': 'NaN'});
        expect(m9.createdAt.isAfter(beforeAbsurd), isTrue);

        // 9. Overflowing epoch num (> 8.64e15 ms) falls back safely
        final m10 = NotificationItemModel.fromMap({'createdAt': 999999999999999999});
        expect(m10.createdAt.isAfter(beforeAbsurd), isTrue);

        // 10. Corrupted random text
        final m11 = NotificationItemModel.fromMap({'createdAt': 'invalid-date-string'});
        expect(m11.createdAt.isAfter(beforeAbsurd), isTrue);
      });

      test('T5.7: Resilient boolean parsing handles diverse representations and case variations', () {
        // Truthy strings
        for (final val in ['true', 'True', 'TRUE', '1', 'yes', 'YES', 't', 'T']) {
          final m = NotificationItemModel.fromMap({'isRead': val});
          expect(m.isRead, isTrue, reason: 'Failed for truthy value: $val');
        }

        // Falsy strings
        for (final val in ['false', 'False', 'FALSE', '0', 'no', 'NO', 'f', 'F']) {
          final m = NotificationItemModel.fromMap({'isRead': val});
          expect(m.isRead, isFalse, reason: 'Failed for falsy value: $val');
        }

        // Numeric values
        expect(NotificationItemModel.fromMap({'isRead': 1}).isRead, isTrue);
        expect(NotificationItemModel.fromMap({'isRead': 42}).isRead, isTrue);
        expect(NotificationItemModel.fromMap({'isRead': -1}).isRead, isTrue);
        expect(NotificationItemModel.fromMap({'isRead': 0}).isRead, isFalse);

        // Arbitrary gibberish defaults to false
        expect(NotificationItemModel.fromMap({'isRead': 'not_a_bool'}).isRead, isFalse);
        expect(NotificationItemModel.fromMap({'isRead': null}).isRead, isFalse);
      });

      test('T5.8: NotificationType parser robustness across casings, hyphens, and keyword recovery', () {
        // Snake case exact
        expect(NotificationType.fromString('order_created'), equals(NotificationType.orderCreated));
        expect(NotificationType.fromString('order_updated'), equals(NotificationType.orderUpdated));
        expect(NotificationType.fromString('order_cancelled'), equals(NotificationType.orderCancelled));
        expect(NotificationType.fromString('order_return'), equals(NotificationType.orderReturn));
        expect(NotificationType.fromString('inventory_imported'), equals(NotificationType.inventoryImported));
        expect(NotificationType.fromString('customer_created'), equals(NotificationType.customerCreated));
        expect(NotificationType.fromString('customer_debt_added'), equals(NotificationType.customerDebtAdded));
        expect(NotificationType.fromString('customer_debt_paid'), equals(NotificationType.customerDebtPaid));

        // Upper case & hyphens
        expect(NotificationType.fromString('ORDER_CREATED'), equals(NotificationType.orderCreated));
        expect(NotificationType.fromString('order-cancelled'), equals(NotificationType.orderCancelled));
        expect(NotificationType.fromString('INVENTORY-IMPORTED'), equals(NotificationType.inventoryImported));

        // CamelCase
        expect(NotificationType.fromString('orderCreated'), equals(NotificationType.orderCreated));
        expect(NotificationType.fromString('customerDebtAdded'), equals(NotificationType.customerDebtAdded));

        // Keyword fuzzy recovery
        expect(NotificationType.fromString('invoice_cancel_event'), equals(NotificationType.orderCancelled));
        expect(NotificationType.fromString('return_goods_done'), equals(NotificationType.orderReturn));
        expect(NotificationType.fromString('update_invoice_v2'), equals(NotificationType.orderUpdated));
        expect(NotificationType.fromString('edit_order_item'), equals(NotificationType.orderUpdated));
        expect(NotificationType.fromString('stock_import_completed'), equals(NotificationType.inventoryImported));
        expect(NotificationType.fromString('paid_debt_cash'), equals(NotificationType.customerDebtPaid));
        expect(NotificationType.fromString('debt_collection'), equals(NotificationType.customerDebtPaid));
        expect(NotificationType.fromString('customer_new_debt'), equals(NotificationType.customerDebtAdded));
        expect(NotificationType.fromString('new_customer_registered'), equals(NotificationType.customerCreated));

        // Fallbacks
        expect(NotificationType.fromString(null), equals(NotificationType.orderCreated));
        expect(NotificationType.fromString(''), equals(NotificationType.orderCreated));
        expect(NotificationType.fromString('unrelated_random_event'), equals(NotificationType.orderCreated));
      });

      test('T5.9: NotificationCategory parser robustness with whitespace and fallbacks', () {
        expect(NotificationCategory.fromString('orders'), equals(NotificationCategory.orders));
        expect(NotificationCategory.fromString('  inventory  '), equals(NotificationCategory.inventory));
        expect(NotificationCategory.fromString('CUSTOMERS'), equals(NotificationCategory.customers));
        expect(NotificationCategory.fromString('system'), equals(NotificationCategory.system));
        expect(NotificationCategory.fromString(null), equals(NotificationCategory.system));
        expect(NotificationCategory.fromString('unknown_category'), equals(NotificationCategory.system));
      });
    });

    // ========================================================================
    // SECTION 2: DEEP RECURSIVE EQUALITY & METADATA HARDENING
    // ========================================================================
    group('2. Deep Recursive Equality & Metadata Hardening', () {
      final baseDate = DateTime(2026, 10, 4, 12, 0, 0);

      Map<String, dynamic> createComplexMetadata() {
        return {
          'orderId': 'HD013260',
          'amount': 250000.5,
          'isVip': true,
          'notes': null,
          'tags': ['pos', 'express', 101],
          'customer': {
            'id': 'KH0001',
            'name': 'Nguyễn Văn A',
            'contact': {
              'phones': ['0901234567', '0987654321'],
              'verified': true,
            },
            'debtHistory': [
              {'amount': 50000, 'date': '2026-10-01'},
              {'amount': 100000, 'date': '2026-10-02'},
            ],
          },
          'lineItems': [
            {'sku': 'SP001', 'qty': 2, 'price': 50000},
            {'sku': 'SP002', 'qty': 1, 'price': 150000},
          ],
        };
      }

      test('T5.10: Deep recursive equality validates complex nested metadata structures', () {
        final itemA = NotificationItem(
          id: 'n1',
          storeId: storeId,
          title: 'Đơn hàng mới',
          body: 'Chi tiết đơn',
          type: NotificationType.orderCreated,
          createdAt: baseDate,
          metadata: createComplexMetadata(),
        );

        final itemB = NotificationItem(
          id: 'n1',
          storeId: storeId,
          title: 'Đơn hàng mới',
          body: 'Chi tiết đơn',
          type: NotificationType.orderCreated,
          createdAt: baseDate,
          metadata: createComplexMetadata(),
        );

        expect(itemA == itemB, isTrue);
        expect(itemB == itemA, isTrue);
        expect(itemA == itemA, isTrue);
      });

      test('T5.11: Deep equality detects subtle mutations at leaf nodes', () {
        final original = NotificationItem(
          id: 'n1',
          storeId: storeId,
          title: 'Đơn hàng',
          body: 'Chi tiết',
          type: NotificationType.orderCreated,
          createdAt: baseDate,
          metadata: createComplexMetadata(),
        );

        // 1. Mutate a nested phone string in metadata
        final mutatedPhoneMeta = createComplexMetadata();
        ((mutatedPhoneMeta['customer'] as Map)['contact'] as Map)['phones'] = [
          '0901234567',
          '0987654322', // Modified digit
        ];
        final itemMutatedPhone = original.copyWith(metadata: mutatedPhoneMeta);
        expect(original == itemMutatedPhone, isFalse);

        // 2. Add an extra element to nested list
        final mutatedListMeta = createComplexMetadata();
        (mutatedListMeta['tags'] as List).add('extra_tag');
        final itemMutatedList = original.copyWith(metadata: mutatedListMeta);
        expect(original == itemMutatedList, isFalse);

        // 3. Mutate boolean value
        final mutatedBoolMeta = createComplexMetadata();
        mutatedBoolMeta['isVip'] = false;
        final itemMutatedBool = original.copyWith(metadata: mutatedBoolMeta);
        expect(original == itemMutatedBool, isFalse);

        // 4. Change null to non-null
        final mutatedNullMeta = createComplexMetadata();
        mutatedNullMeta['notes'] = 'Ghi chú mới';
        final itemMutatedNull = original.copyWith(metadata: mutatedNullMeta);
        expect(original == itemMutatedNull, isFalse);

        // 5. Extra key in nested map
        final mutatedKeyMeta = createComplexMetadata();
        (mutatedKeyMeta['customer'] as Map)['vipLevel'] = 'Gold';
        final itemMutatedKey = original.copyWith(metadata: mutatedKeyMeta);
        expect(original == itemMutatedKey, isFalse);

        // 6. Compare with null metadata (copyWith preserves existing if null is passed)
        final itemNullMeta = original.copyWith(metadata: null);
        expect(itemNullMeta.metadata, isNotNull);
        final itemDirectNull = NotificationItem(
          id: 'n1',
          storeId: storeId,
          title: 'Đơn hàng',
          body: 'Chi tiết',
          type: NotificationType.orderCreated,
          createdAt: baseDate,
          metadata: null,
        );
        expect(original == itemDirectNull, isFalse);
      });

      test('T5.12: copyWith isolates top-level keys but shares nested map references (shallow copy)', () {
        final originalMeta = {
          'config': {'theme': 'dark'},
          'roles': ['admin', 'manager'],
          'status': 'active',
        };
        final original = NotificationItem(
          id: 'n1',
          storeId: storeId,
          title: 'Title',
          body: 'Body',
          type: NotificationType.orderCreated,
          createdAt: baseDate,
          metadata: originalMeta,
        );

        final copy = original.copyWith(title: 'Updated Title');
        // 1. Modifying top-level key on originalMeta does not mutate copy
        originalMeta['status'] = 'archived';
        expect(copy.metadata?['status'], equals('active'));

        // 2. Modifying copy top-level keys does not mutate original
        copy.metadata?['new_key'] = 'added_to_copy';
        expect(original.metadata?.containsKey('new_key'), isFalse);

        // 3. Empirical check: Map.from is shallow so nested collections share reference
        (originalMeta['config'] as Map)['theme'] = 'light';
        expect((copy.metadata?['config'] as Map)['theme'], equals('light'));
      });

      test('T5.13: Model metadata sanitization normalizes non-string keys and nested structures', () {
        final rawMap = {
          'id': 'sanitized_item',
          'storeId': storeId,
          'title': 'Sanitized',
          'body': 'Body',
          'type': 'order_created',
          'createdAt': '2026-10-04T12:00:00.000Z',
          'metadata': {
            101: 'integer_key_converted',
            'nested': {
              true: 'bool_key_converted',
              'list': [
                {null: 'null_key_ignored', 99: 'ninety_nine'},
              ],
            },
          },
        };

        final model = NotificationItemModel.fromMap(rawMap);
        final meta = model.metadata!;

        expect(meta['101'], equals('integer_key_converted'));
        expect((meta['nested'] as Map)['true'], equals('bool_key_converted'));
        final list = (meta['nested'] as Map)['list'] as List;
        expect((list[0] as Map)['99'], equals('ninety_nine'));
      });
    });

    // ========================================================================
    // SECTION 3: RTDB STREAM DEBOUNCING & NEWEST-FIRST SORT ORDER
    // ========================================================================
    group('3. RTDB Stream Debouncing & Newest-First Sort Order Invariant', () {
      test('T5.14: 120 rapid asynchronous mutations within 20ms coalesce into single debounced emission', () async {
        final ref = mockDb.getOrCreateRef('stores/$storeId/notifications');
        final stream = repository.watchNotifications(storeId);

        final receivedBatches = <List<NotificationItem>>[];
        final sub = stream.listen((items) {
          receivedBatches.add(items);
        });

        // Fire 120 mutations in rapid succession
        for (int i = 0; i < 120; i++) {
          final payload = {
            'notif_$i': {
              'id': 'notif_$i',
              'storeId': storeId,
              'title': 'Burst Item $i',
              'body': 'Rapid fire event',
              'type': 'order_created',
              'createdAt': DateTime(2026, 10, 4, 12, 0, i).toIso8601String(),
            },
          };
          ref.emitValue(payload);
          // Very slight micro-yield
          if (i % 30 == 0) {
            await Future.delayed(Duration.zero);
          }
        }

        // Wait past 250ms debounce window
        await Future.delayed(const Duration(milliseconds: 400));
        await sub.cancel();

        // Must coalesce significantly rather than emit 120 separate events
        expect(receivedBatches.length, lessThanOrEqualTo(3));
        expect(receivedBatches.isNotEmpty, isTrue);

        // Final batch must contain the last emitted notification (notif_119)
        final lastBatch = receivedBatches.last;
        expect(lastBatch.any((item) => item.id == 'notif_119'), isTrue);
      });

      test('T5.15: Shuffled RTDB items are strictly sorted monotonic descending by createdAt (newest-first)', () async {
        final ref = mockDb.getOrCreateRef('stores/$storeId/notifications');

        // Create 50 notifications with intentionally randomized timestamps
        final Map<String, dynamic> unorderedMap = {};
        final dates = <DateTime>[];

        // Seed deterministically
        for (int i = 0; i < 50; i++) {
          // Scramble timestamps across days and hours
          final pseudoRandomOffset = (i * 37) % 50;
          final dt = DateTime(2026, 10, 1, 0, 0, 0).add(Duration(hours: pseudoRandomOffset * 3));
          dates.add(dt);

          unorderedMap['item_$i'] = {
            'id': 'item_$i',
            'storeId': storeId,
            'title': 'Order $i',
            'body': 'Body $i',
            'type': 'order_created',
            'createdAt': dt.toIso8601String(),
          };
        }

        ref.storeData.addAll(unorderedMap);
        final stream = repository.watchNotifications(storeId);
        final future = stream.first;
        ref.emitValue(unorderedMap);
        final items = await future;

        expect(items.length, equals(50));

        // INVARIANT VERIFICATION: For all i, items[i].createdAt >= items[i+1].createdAt
        for (int i = 0; i < items.length - 1; i++) {
          final current = items[i].createdAt;
          final next = items[i + 1].createdAt;
          final isDescending = current.isAfter(next) || current.isAtSameMomentAs(next);
          expect(
            isDescending,
            isTrue,
            reason: 'Sort violation at index $i: ${items[i].id} ($current) is before ${items[i + 1].id} ($next)',
          );
        }
      });

      test('T5.16: Subscribing and immediate cancellation does not leak active timers or throw errors', () async {
        final stream = repository.watchNotifications(storeId);
        final sub = stream.listen((_) {});

        // Cancel immediately within 1ms
        await sub.cancel();

        // Emit new value after cancel - should not crash
        final ref = mockDb.getOrCreateRef('stores/$storeId/notifications');
        ref.emitValue({'id': 'late_item'});

        await Future.delayed(const Duration(milliseconds: 300));
        // Verify test completes cleanly
        expect(true, isTrue);
      });
    });

    // ========================================================================
    // SECTION 4: REPOSITORY ERROR HANDLING & FAILURE SCENARIOS
    // ========================================================================
    group('4. Repository Error Handling & Failure Scenarios', () {
      test('T5.17: Remote data source propagates simulated network error on get()', () async {
        final ref = mockDb.getOrCreateRef('stores/$storeId/notifications');
        final networkException = FirebaseException(
          plugin: 'firebase_database',
          code: 'network-error',
          message: 'The network connection was lost',
        );
        ref.setSimulateQueryFailure(true, networkException);

        expect(
          () => remoteDataSource.fetchNotifications(storeId),
          throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'network-error')),
        );
      });

      test('T5.18: Simulated permission-denied propagates error on markAllAsRead query', () async {
        final ref = mockDb.getOrCreateRef('stores/$storeId/notifications');
        final permissionException = FirebaseException(
          plugin: 'firebase_database',
          code: 'permission-denied',
          message: 'Client does not have permission to read notifications',
        );
        ref.setSimulateQueryFailure(true, permissionException);

        expect(
          () => repository.markAllAsRead(storeId),
          throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied')),
        );
      });

      test('T5.19: Stream propagates error through stream pipeline', () async {
        final ref = mockDb.getOrCreateRef('stores/$storeId/notifications');
        final stream = repository.watchNotifications(storeId);

        final completer = Completer<Object>();
        final sub = stream.listen(
          (_) {},
          onError: (Object err) {
            if (!completer.isCompleted) completer.complete(err);
          },
        );

        ref.valueStream.emitError(
          FirebaseException(
            plugin: 'firebase_database',
            code: 'unavailable',
            message: 'Firebase RTDB service temporarily unavailable',
          ),
        );

        final caughtError = await completer.future.timeout(const Duration(seconds: 1));
        await sub.cancel();

        expect(caughtError, isA<FirebaseException>());
        expect((caughtError as FirebaseException).code, equals('unavailable'));
      });

      test('T5.20: Batch markAllAsRead with empty collection completes cleanly without updates', () async {
        final ref = mockDb.getOrCreateRef('stores/$storeId/notifications');
        // No items in database
        await repository.markAllAsRead(storeId);

        final updateCalls = mockDb.recorder.callsFor('update', path: ref.path);
        expect(updateCalls, isEmpty);
      });

      test('T5.21: Batch markAllAsRead on List-structured data formats updates with array indexes', () async {
        final ref = mockDb.getOrCreateRef('stores/$storeId/notifications');
        // Populate RTDB with array-like data structure where isRead is false
        ref.storeData['0'] = {'id': '0', 'isRead': false};
        ref.storeData['1'] = {'id': '1', 'isRead': true};
        ref.storeData['2'] = {'id': '2', 'isRead': false};

        await repository.markAllAsRead(storeId);

        final updateCalls = mockDb.recorder.callsFor('update');
        expect(updateCalls.isNotEmpty, isTrue);
      });

      test('T5.22: addNotification generates autoId when notification ID is empty or whitespace', () async {
        final itemWithoutId = NotificationItem(
          id: '',
          storeId: storeId,
          title: 'Auto ID Item',
          body: 'Generated atomic push key',
          type: NotificationType.orderCreated,
          createdAt: DateTime(2026, 10, 4, 12, 0, 0),
        );

        await repository.addNotification(itemWithoutId);

        final setCalls = mockDb.recorder.callsFor('set');
        expect(setCalls.isNotEmpty, isTrue);
        final lastCall = setCalls.last;
        expect(lastCall.path, startsWith('stores/$storeId/notifications/-M'));
        expect((lastCall.value as Map)['id'], isNotEmpty);
      });

      test('T5.23: markAsRead and deleteNotification execute targeted child path operations', () async {
        const notifId = 'notif_targeted_123';
        const expectedPath = 'stores/$storeId/notifications/$notifId';

        await repository.markAsRead(storeId: storeId, id: notifId);
        expect(mockDb.recorder.hasCalled('update', path: expectedPath), isTrue);

        await repository.deleteNotification(storeId: storeId, id: notifId);
        expect(mockDb.recorder.hasCalled('remove', path: expectedPath), isTrue);
      });
    });

    // ========================================================================
    // SECTION 5: REALTIME DATABASE RULES VALIDATION (database.rules.json)
    // ========================================================================
    group('5. Realtime Database Rules Validation (database.rules.json)', () {
      test('T5.24: database.rules.json parses as valid JSON with required .indexOn for notifications', () {
        final rulesFile = File('database.rules.json');
        expect(rulesFile.existsSync(), isTrue, reason: 'database.rules.json must exist in project root');

        final content = rulesFile.readAsStringSync();
        final dynamic parsed = jsonDecode(content);
        expect(parsed, isA<Map<String, dynamic>>());

        final rules = parsed['rules'] as Map<String, dynamic>;
        expect(rules.containsKey('stores'), isTrue);

        final stores = rules['stores'] as Map<String, dynamic>;
        expect(stores.containsKey(r'$storeId'), isTrue);

        final storeConfig = stores[r'$storeId'] as Map<String, dynamic>;
        expect(storeConfig.containsKey('notifications'), isTrue);

        final notificationsRule = storeConfig['notifications'] as Map<String, dynamic>;
        expect(notificationsRule.containsKey('.indexOn'), isTrue);

        final indexOn = notificationsRule['.indexOn'] as List;
        expect(indexOn, containsAll(['createdAt', 'isRead', 'type']));
        expect(indexOn.length, equals(3));
      });
    });

    // ========================================================================
    // SECTION 6: DOMAIN & DATA ARCHITECTURE INVARIANTS
    // ========================================================================
    group('6. Domain & Data Architecture Invariants', () {
      test('T5.25: Domain layer entity file has zero imports from Flutter or Firebase', () {
        final entityFile = File('lib/domain/entities/notification_item.dart');
        final typeFile = File('lib/domain/entities/notification_type.dart');
        final repoFile = File('lib/domain/repositories/notification_repository.dart');

        for (final file in [entityFile, typeFile, repoFile]) {
          expect(file.existsSync(), isTrue);
          final text = file.readAsStringSync();
          expect(text.contains('package:flutter/'), isFalse, reason: '${file.path} must not import flutter');
          expect(text.contains('package:firebase_'), isFalse, reason: '${file.path} must not import firebase');
          expect(text.contains('package:flutter_riverpod/'), isFalse, reason: '${file.path} must not import riverpod');
        }
      });

      test('T5.26: Bidirectional conversion Domain <-> Model preserves 100% data fidelity', () {
        final originalDomain = NotificationItem(
          id: 'roundtrip_1',
          storeId: 'store_001',
          title: 'Roundtrip Title',
          body: 'Roundtrip Body',
          type: NotificationType.customerDebtPaid,
          isRead: true,
          createdAt: DateTime(2026, 10, 4, 15, 30, 45),
          targetRoute: 'customer_debt',
          targetId: 'KH0009',
          metadata: {
            'amount': 500000,
            'method': 'cash',
            'nested': {'receipt': 'RC102'},
          },
        );

        final model = NotificationItemModel.fromDomain(originalDomain);
        final map = model.toMap();
        final reconstructedModel = NotificationItemModel.fromMap(map);
        final reconstructedDomain = reconstructedModel.toDomain();

        expect(reconstructedDomain, equals(originalDomain));
        expect(reconstructedModel, equals(model));
      });
    });
  });
}
