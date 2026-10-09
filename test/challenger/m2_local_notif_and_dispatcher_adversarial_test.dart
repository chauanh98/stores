import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/notifications/local_notification_service.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/user_account.dart';

/// Configurable mock repository for fault injection and stress tests.
class _FaultInjectingNotificationRepository implements NotificationRepository {
  final List<NotificationItem> storedNotifications = [];
  Object? errorToThrow;

  void injectError(Object? error) {
    errorToThrow = error;
  }

  void clearError() {
    errorToThrow = null;
  }

  @override
  Future<void> addNotification(NotificationItem notification) async {
    if (errorToThrow != null) {
      final err = errorToThrow!;
      if (err is Error) {
        throw err;
      } else if (err is Exception) {
        throw err;
      } else {
        throw Exception(err.toString());
      }
    }
    storedNotifications.add(notification);
  }

  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {
    if (errorToThrow != null) throw errorToThrow!;
    storedNotifications.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> markAllAsRead(String storeId) async {
    if (errorToThrow != null) throw errorToThrow!;
    for (int i = 0; i < storedNotifications.length; i++) {
      storedNotifications[i] =
          storedNotifications[i].copyWith(isRead: true);
    }
  }

  @override
  Future<void> markAsRead(
      {required String storeId, required String id}) async {
    if (errorToThrow != null) throw errorToThrow!;
    final index = storedNotifications.indexWhere((item) => item.id == id);
    if (index != -1) {
      storedNotifications[index] =
          storedNotifications[index].copyWith(isRead: true);
    }
  }

  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
      {int limit = 50}) {
    return Stream.value(storedNotifications);
  }
}

NotificationItem _createTestItem({
  required String id,
  required DateTime createdAt,
  bool isRead = false,
  String storeId = 'store_001',
  NotificationType type = NotificationType.orderCreated,
  String title = 'Test Title',
  String body = 'Test Body',
}) {
  return NotificationItem(
    id: id,
    storeId: storeId,
    title: title,
    body: body,
    type: type,
    createdAt: createdAt,
    isRead: isRead,
    targetRoute: 'invoice_detail',
    targetId: id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storeId = 'store_001';
  const testUser = UserAccount(
    username: 'admin01',
    displayName: 'Admin Master',
    role: 'admin',
    storeId: storeId,
  );

  group('M2 ADVERSARIAL STRESS HARNESS', () {
    // =========================================================================
    // 1. HIGH VOLUME FLOOD & CACHE PRUNING STRESS HARNESS
    // =========================================================================
    group('1. High Volume Flood & Cache Pruning Stress', () {
      late FakeLocalNotificationService fakeService;

      setUp(() {
        fakeService = FakeLocalNotificationService();
      });

      test('Feed 1,000 notifications in batches: pruning never throws, bounds memory, preserves recent dedup', () async {
        final fixedNow = DateTime.utc(2026, 10, 4, 12, 0, 0);
        final listener = NotificationListenerService(
          localNotificationService: fakeService,
          maxAge: const Duration(seconds: 60),
          clock: () => fixedNow,
        );

        // Generate 1,000 notifications in 10 batches of 100 items
        const totalItems = 1000;
        const batchSize = 100;
        const totalBatches = totalItems ~/ batchSize;

        final allBatches = <List<NotificationItem>>[];
        for (int b = 0; b < totalBatches; b++) {
          final batch = List.generate(batchSize, (i) {
            final globalIdx = b * batchSize + i;
            return _createTestItem(
              id: 'flood_item_$globalIdx',
              createdAt: fixedNow.subtract(const Duration(seconds: 10)),
              title: 'Batch $b Item $i',
            );
          });
          allBatches.add(batch);
        }

        int totalTriggered = 0;
        for (int b = 0; b < totalBatches; b++) {
          final batch = allBatches[b];
          final triggered = await listener.processNotifications(batch);
          totalTriggered += triggered;

          // Pruning rule: When _shownIds.length > 500, it retains only the current items
          // Therefore, memory must NEVER grow without bounds (must never exceed batchSize + 500)
          expect(listener.shownIds.length, lessThanOrEqualTo(500 + batchSize),
              reason: 'Cache size must remain strictly bounded at batch $b');
        }

        expect(totalTriggered, equals(1000),
            reason: 'All 1,000 unique fresh items must be processed and triggered');
        expect(fakeService.displayedCalls.length, equals(1000));

        // After processing the 10th batch, cache size is at 500 (threshold boundary)
        expect(listener.shownIds.length, lessThanOrEqualTo(500),
            reason: 'Cache size must remain within 500 limit before next prune cycle');

        // CRITICAL ADVERSARIAL CHECK: Does it drop recent deduplications?
        // Re-process the last batch (batch 9, indices 900..999)
        final lastBatch = allBatches.last;
        final reTriggered = await listener.processNotifications(lastBatch);

        expect(reTriggered, equals(0),
            reason: 'Recent deduplications MUST NOT be dropped; last batch must not re-trigger');
        expect(fakeService.displayedCalls.length, equals(1000),
            reason: 'No additional notification pop-ups should have been fired');

        // Now push 1 extra item to cross > 500 threshold and verify prune triggers
        final overflowItem = _createTestItem(
          id: 'overflow_item_1001',
          createdAt: fixedNow.subtract(const Duration(seconds: 1)),
        );
        final overflowTriggered = await listener.processNotifications([overflowItem]);
        expect(overflowTriggered, equals(1));
        // Pruning should have triggered (> 500) and retained only current items (1 item)
        expect(listener.shownIds.length, equals(1));
        expect(listener.shownIds.first, equals('overflow_item_1001'));
      });

      test('Sliding window stream flood: 1,000 rolling snapshot updates keeping memory strictly bounded', () async {
        final fixedNow = DateTime.utc(2026, 10, 4, 12, 0, 0);
        final listener = NotificationListenerService(
          localNotificationService: fakeService,
          maxAge: const Duration(seconds: 60),
          clock: () => fixedNow,
        );

        // Simulate Firebase RTDB limitToLast(50) window sliding over 1,000 sequential items
        const windowSize = 50;
        final window = <NotificationItem>[];

        for (int i = 0; i < 1000; i++) {
          final newItem = _createTestItem(
            id: 'stream_item_$i',
            createdAt: fixedNow.subtract(const Duration(seconds: 5)),
            title: 'Stream Item $i',
          );
          window.add(newItem);
          if (window.length > windowSize) {
            window.removeAt(0);
          }

          // Process the snapshot
          await listener.processNotifications(List.of(window));

          // Verify memory bounded condition
          expect(listener.shownIds.length, lessThanOrEqualTo(500 + windowSize));
        }

        expect(fakeService.displayedCalls.length, equals(1000),
            reason: 'Each rolling item must have triggered exactly once');

        // Verify re-emitting identical current window causes 0 new notifications
        final dupCount = await listener.processNotifications(List.of(window));
        expect(dupCount, equals(0));
        expect(fakeService.displayedCalls.length, equals(1000));
      });

      test('Single extreme burst of 1,000 items in one call: triggers all, subsequent smaller batch prunes', () async {
        final fixedNow = DateTime.utc(2026, 10, 4, 12, 0, 0);
        final listener = NotificationListenerService(
          localNotificationService: fakeService,
          maxAge: const Duration(seconds: 60),
          clock: () => fixedNow,
        );

        final burstItems = List.generate(
          1000,
          (i) => _createTestItem(
            id: 'burst_item_$i',
            createdAt: fixedNow.subtract(const Duration(seconds: 2)),
          ),
        );

        final count = await listener.processNotifications(burstItems);
        expect(count, equals(1000));
        expect(fakeService.displayedCalls.length, equals(1000));

        // Re-feed identical burst
        final countDup = await listener.processNotifications(burstItems);
        expect(countDup, equals(0));

        // Now feed a fresh batch of 10 items
        final next10 = List.generate(
          10,
          (i) => _createTestItem(
            id: 'next_item_$i',
            createdAt: fixedNow.subtract(const Duration(seconds: 1)),
          ),
        );

        final countNext = await listener.processNotifications(next10);
        expect(countNext, equals(10));
        // Pruning should have collapsed shownIds to only the active items (10 items)
        expect(listener.shownIds.length, equals(10));
      });
    });

    // =========================================================================
    // 2. FRESHNESS BOUNDARY & CLOCK SKEW PRECISION TESTS
    // =========================================================================
    group('2. Freshness Boundary & Clock Skew Precision', () {
      late FakeLocalNotificationService fakeService;
      final fixedNow = DateTime.utc(2026, 10, 4, 12, 0, 0);

      setUp(() {
        fakeService = FakeLocalNotificationService();
      });

      test('Exact boundary tests around 60 seconds and future tolerance', () async {
        final listener = NotificationListenerService(
          localNotificationService: fakeService,
          maxAge: const Duration(seconds: 60),
          clock: () => fixedNow,
        );

        // 1. 59s ago -> SHOWS notification
        final item59s = _createTestItem(
          id: 'item_59s',
          createdAt: fixedNow.subtract(const Duration(seconds: 59)),
        );
        final count59s = await listener.processNotifications([item59s]);
        expect(count59s, equals(1), reason: 'Item 59s ago is within 60s maxAge');
        expect(fakeService.displayedCalls.any((c) => c.payload?.contains('item_59s') ?? false), isTrue);

        // 2. Exact 60.0s ago -> SHOWS notification (age == maxAge)
        final item60s = _createTestItem(
          id: 'item_60s',
          createdAt: fixedNow.subtract(const Duration(seconds: 60)),
        );
        final count60s = await listener.processNotifications([item60s]);
        expect(count60s, equals(1), reason: 'Item exactly 60.0s ago is within age <= maxAge');

        // 3. 60.1s ago (60s + 100ms) -> IGNORED
        final item60_1s = _createTestItem(
          id: 'item_60_1s',
          createdAt: fixedNow.subtract(const Duration(milliseconds: 60100)),
        );
        final count60_1s = await listener.processNotifications([item60_1s]);
        expect(count60_1s, equals(0), reason: 'Item 60.1s ago must be ignored');
        expect(listener.shownIds.contains('item_60_1s'), isFalse);

        // 4. Future +5s -> SHOWS notification (within -10s clock drift)
        final itemFuture5s = _createTestItem(
          id: 'item_future_5s',
          createdAt: fixedNow.add(const Duration(seconds: 5)),
        );
        final countFuture5s = await listener.processNotifications([itemFuture5s]);
        expect(countFuture5s, equals(1), reason: 'Future +5s is within -10s skew tolerance');
        expect(listener.shownIds.contains('item_future_5s'), isTrue);

        // 5. Future +10.0s exact -> SHOWS notification (age == -10s)
        final itemFuture10s = _createTestItem(
          id: 'item_future_10s',
          createdAt: fixedNow.add(const Duration(seconds: 10)),
        );
        final countFuture10s = await listener.processNotifications([itemFuture10s]);
        expect(countFuture10s, equals(1), reason: 'Future +10s is exact skew boundary');

        // 6. Future +10.1s -> IGNORED (exceeds -10s tolerance)
        final itemFuture10_1s = _createTestItem(
          id: 'item_future_10_1s',
          createdAt: fixedNow.add(const Duration(milliseconds: 10100)),
        );
        final countFuture10_1s = await listener.processNotifications([itemFuture10_1s]);
        expect(countFuture10_1s, equals(0), reason: 'Future +10.1s exceeds clock drift tolerance');
        expect(listener.shownIds.contains('item_future_10_1s'), isFalse);

        // 7. Future +30s -> IGNORED
        final itemFuture30s = _createTestItem(
          id: 'item_future_30s',
          createdAt: fixedNow.add(const Duration(seconds: 30)),
        );
        final countFuture30s = await listener.processNotifications([itemFuture30s]);
        expect(countFuture30s, equals(0), reason: 'Future +30s must be ignored');
        expect(listener.shownIds.contains('item_future_30s'), isFalse);
      });

      test('Mixed boundary batch containing 59s, 60.1s, future +5s, future +30s: triggers only the 2 valid items', () async {
        final listener = NotificationListenerService(
          localNotificationService: fakeService,
          maxAge: const Duration(seconds: 60),
          clock: () => fixedNow,
        );

        final mixedBatch = [
          _createTestItem(
            id: 'item_59s_mixed',
            createdAt: fixedNow.subtract(const Duration(seconds: 59)),
            title: 'Valid 59s',
          ),
          _createTestItem(
            id: 'item_60_1s_mixed',
            createdAt: fixedNow.subtract(const Duration(milliseconds: 60100)),
            title: 'Invalid 60.1s',
          ),
          _createTestItem(
            id: 'item_future_5s_mixed',
            createdAt: fixedNow.add(const Duration(seconds: 5)),
            title: 'Valid +5s',
          ),
          _createTestItem(
            id: 'item_future_30s_mixed',
            createdAt: fixedNow.add(const Duration(seconds: 30)),
            title: 'Invalid +30s',
          ),
        ];

        final triggered = await listener.processNotifications(mixedBatch);
        expect(triggered, equals(2), reason: 'Only exactly 59s and future +5s should trigger');
        expect(fakeService.displayedCalls.length, equals(2));

        final titles = fakeService.displayedCalls.map((c) => c.title).toList();
        expect(titles, contains('Valid 59s'));
        expect(titles, contains('Valid +5s'));
        expect(titles, isNot(contains('Invalid 60.1s')));
        expect(titles, isNot(contains('Invalid +30s')));
      });
    });

    // =========================================================================
    // 3. FAULT INJECTION ON DISPATCHER (ALL 8 BUSINESS METHODS)
    // =========================================================================
    group('3. Fault Injection on Dispatcher Across All 8 Business Methods', () {
      late _FaultInjectingNotificationRepository mockRepo;
      late NotificationDispatcher dispatcher;

      setUp(() {
        mockRepo = _FaultInjectingNotificationRepository();
        dispatcher = NotificationDispatcher(mockRepo);
      });

      // Sample domain fixtures for testing
      final sampleOrder = Order(
        id: 'HD099999',
        customerId: 'KH0001',
        customerName: 'Khách Test Hóa Đơn',
        createdAt: DateTime.now(),
        items: const [],
        total: 100000.0,
      );

      final sampleReturnOrder = ReturnOrder(
        id: 'TH001',
        orderId: 'HD099999',
        customerId: 'KH0001',
        storeId: storeId,
        createdAt: DateTime.now(),
        items: const [
          ReturnOrderItem(
            productId: 'P001',
            productName: 'SP 1',
            price: 50000.0,
            quantity: 1,
          )
        ],
        totalReturnAmount: 50000.0,
      );

      final sampleReceipt = StockInReceipt(
        id: 'RCP_001',
        importCode: 'NK123456',
        date: DateTime.now(),
        storeId: storeId,
        supplierName: 'Nhà Cung Cấp ABC',
        items: const [],
        totalAmount: 500000.0,
        status: 'Đã nhập hàng',
      );

      const sampleCustomer = Customer(
        id: 'KH00099',
        name: 'Trần Văn Khách',
        phone: '0901234567',
        email: 'test@customer.com',
        address: '123 Test St',
        purchases: [],
      );

      final injectedFaults = <String, Object>{
        'FirebaseException': FirebaseException(
          plugin: 'firebase_database',
          code: 'unavailable',
          message: 'Realtime Database backend cluster is temporarily unreachable',
        ),
        'TimeoutException': TimeoutException(
          'Timeout waiting for Firebase write ack after 5000ms',
        ),
        'SocketException': const SocketException(
          'Failed host lookup: https://stores-production.firebaseio.com',
        ),
        'StateError': StateError(
          'Bad state: DatabaseReference stream has been closed or torn down',
        ),
      };

      for (final entry in injectedFaults.entries) {
        final faultName = entry.key;
        final fault = entry.value;

        test('Fault injection [$faultName] does NOT throw across all 8 business methods', () async {
          mockRepo.injectError(fault);

          // 1. notifyOrderCreated
          await expectLater(
            dispatcher.notifyOrderCreated(
              storeId: storeId,
              order: sampleOrder,
              user: testUser,
            ),
            completes,
            reason: 'notifyOrderCreated must absorb $faultName',
          );

          // 2. notifyOrderUpdated
          await expectLater(
            dispatcher.notifyOrderUpdated(
              storeId: storeId,
              order: sampleOrder,
              originalOrderId: 'HD099998',
              user: testUser,
            ),
            completes,
            reason: 'notifyOrderUpdated must absorb $faultName',
          );

          // 3. notifyOrderCancelled
          await expectLater(
            dispatcher.notifyOrderCancelled(
              storeId: storeId,
              order: sampleOrder,
              cancelReason: 'Khách đổi ý',
              user: testUser,
            ),
            completes,
            reason: 'notifyOrderCancelled must absorb $faultName',
          );

          // 4. notifyOrderReturned
          await expectLater(
            dispatcher.notifyOrderReturned(
              storeId: storeId,
              returnOrder: sampleReturnOrder,
              user: testUser,
            ),
            completes,
            reason: 'notifyOrderReturned must absorb $faultName',
          );

          // 5. notifyStockInCompleted
          await expectLater(
            dispatcher.notifyStockInCompleted(
              storeId: storeId,
              receipt: sampleReceipt,
              user: testUser,
            ),
            completes,
            reason: 'notifyStockInCompleted must absorb $faultName',
          );

          // 6. notifyCustomerCreated
          await expectLater(
            dispatcher.notifyCustomerCreated(
              storeId: storeId,
              customer: sampleCustomer,
              user: testUser,
            ),
            completes,
            reason: 'notifyCustomerCreated must absorb $faultName',
          );

          // 7. notifyCustomerDebtAdded
          await expectLater(
            dispatcher.notifyCustomerDebtAdded(
              storeId: storeId,
              customerId: sampleCustomer.id,
              customerName: sampleCustomer.name,
              debtAmount: 250000.0,
              orderId: sampleOrder.id,
              user: testUser,
            ),
            completes,
            reason: 'notifyCustomerDebtAdded must absorb $faultName',
          );

          // 8. notifyCustomerDebtCollected
          await expectLater(
            dispatcher.notifyCustomerDebtCollected(
              storeId: storeId,
              customerId: sampleCustomer.id,
              customerName: sampleCustomer.name,
              collectedAmount: 150000.0,
              remainingDebt: 100000.0,
              user: testUser,
            ),
            completes,
            reason: 'notifyCustomerDebtCollected must absorb $faultName',
          );

          expect(mockRepo.storedNotifications, isEmpty);
        });
      }
    });

    // =========================================================================
    // 4. EXTREME NUMBER FORMATTING & BORDER VALUE STRESS
    // =========================================================================
    group('4. Extreme Number Formatting & Border Value Stress', () {
      late _FaultInjectingNotificationRepository mockRepo;
      late NotificationDispatcher dispatcher;

      setUp(() {
        mockRepo = _FaultInjectingNotificationRepository();
        dispatcher = NotificationDispatcher(mockRepo);
      });

      Order buildOrderWithTotal(double total) {
        return Order(
          id: 'HD_EXTREME',
          customerId: 'KH001',
          customerName: 'Khách Hàng Biên',
          createdAt: DateTime.now(),
          items: const [],
          total: total,
        );
      }

      test('Amount = 0: formats cleanly without throwing', () async {
        final order0 = buildOrderWithTotal(0.0);
        await dispatcher.notifyOrderCreated(
          storeId: storeId,
          order: order0,
          user: testUser,
        );

        expect(mockRepo.storedNotifications.length, equals(1));
        final notif = mockRepo.storedNotifications.first;
        expect(notif.body, contains('0đ'));
        expect(notif.metadata?['total'], equals(0.0));
      });

      test('Amount = negative: formats negative currency cleanly without crashing', () async {
        final orderNeg = buildOrderWithTotal(-50000.0);
        await dispatcher.notifyOrderCreated(
          storeId: storeId,
          order: orderNeg,
          user: testUser,
        );

        expect(mockRepo.storedNotifications.length, equals(1));
        final notif = mockRepo.storedNotifications.first;
        expect(notif.body, contains('-50.000đ'));
        expect(notif.metadata?['total'], equals(-50000.0));
      });

      test('Amount = 1e12 (Trillion VND): formats large number with thousands separator', () async {
        final orderTrillion = buildOrderWithTotal(1000000000000.0);
        await dispatcher.notifyOrderCreated(
          storeId: storeId,
          order: orderTrillion,
          user: testUser,
        );

        expect(mockRepo.storedNotifications.length, equals(1));
        final notif = mockRepo.storedNotifications.first;
        expect(notif.body, contains('1.000.000.000.000đ'));
        expect(notif.metadata?['total'], equals(1000000000000.0));
      });

      test('Amount = double.nan: does NOT throw or crash caller', () async {
        final orderNaN = buildOrderWithTotal(double.nan);
        await expectLater(
          dispatcher.notifyOrderCreated(
            storeId: storeId,
            order: orderNaN,
            user: testUser,
          ),
          completes,
        );
      });

      test('Amount = double.infinity: does NOT throw or crash caller', () async {
        final orderInf = buildOrderWithTotal(double.infinity);
        await expectLater(
          dispatcher.notifyOrderCreated(
            storeId: storeId,
            order: orderInf,
            user: testUser,
          ),
          completes,
        );
      });

      test('Amount = double.negativeInfinity: does NOT throw or crash caller', () async {
        final orderNegInf = buildOrderWithTotal(double.negativeInfinity);
        await expectLater(
          dispatcher.notifyOrderCreated(
            storeId: storeId,
            order: orderNegInf,
            user: testUser,
          ),
          completes,
        );
      });

      test('Extreme numbers across debt and stock-in methods', () async {
        // Stock-in with 1e12
        final receipt1e12 = StockInReceipt(
          id: 'RCP_BIG',
          importCode: 'NK_BIG',
          date: DateTime.now(),
          storeId: storeId,
          supplierName: 'Tập đoàn đa quốc gia',
          items: const [],
          totalAmount: 1000000000000.0,
          status: 'Đã nhập hàng',
        );
        await dispatcher.notifyStockInCompleted(
          storeId: storeId,
          receipt: receipt1e12,
          user: testUser,
        );
        expect(mockRepo.storedNotifications.last.body, contains('1.000.000.000.000đ'));

        // Customer debt with 1e12
        await dispatcher.notifyCustomerDebtAdded(
          storeId: storeId,
          customerId: 'KH001',
          customerName: 'Đại Gia',
          debtAmount: 1000000000000.0,
          orderId: 'HD_BIG',
          user: testUser,
        );
        expect(mockRepo.storedNotifications.last.body, contains('1.000.000.000.000đ'));

        // Customer debt collected with 1e12
        await dispatcher.notifyCustomerDebtCollected(
          storeId: storeId,
          customerId: 'KH001',
          customerName: 'Đại Gia',
          collectedAmount: 1000000000000.0,
          remainingDebt: 0.0,
          user: testUser,
        );
        expect(mockRepo.storedNotifications.last.body, contains('1.000.000.000.000đ'));
        expect(mockRepo.storedNotifications.last.body, contains('0đ'));
      });
    });

    // =========================================================================
    // 5. LOCAL NOTIFICATION PAYLOAD & ID BITMASK SAFETY
    // =========================================================================
    group('5. NotificationPayload & ID Bitmask Stress Tests', () {
      test('NotificationPayload.tryParse handles all malformed inputs safely', () {
        expect(NotificationPayload.tryParse(null), isNull);
        expect(NotificationPayload.tryParse(''), isNull);
        expect(NotificationPayload.tryParse('    '), isNull);
        expect(NotificationPayload.tryParse('{invalid_json:'), isNull);
        expect(NotificationPayload.tryParse('[1, 2, 3]'), isNull);
        expect(NotificationPayload.tryParse('"just a string"'), isNull);
        expect(NotificationPayload.tryParse('12345'), isNull);
        expect(NotificationPayload.tryParse('true'), isNull);

        // Valid empty map -> defaults id and storeId to empty string
        final emptyMap = NotificationPayload.tryParse('{}');
        expect(emptyMap, isNotNull);
        expect(emptyMap!.id, equals(''));
        expect(emptyMap.storeId, equals(''));
        expect(emptyMap.targetRoute, isNull);
      });

      test('ID generation bitmask is strictly non-negative 31-bit integer', () {
        // Android local notification IDs must fit in a 31-bit signed Java int (0 <= id <= 0x7FFFFFFF)
        final testIds = [
          '',
          'a',
          'NOTIF_ORD_1728045600_1',
          'very_long_notification_identifier_with_special_chars_!@#\$%^&*()',
          'id_with_extreme_unicode_ tiếng_việt_đông_thắng_thới_bình',
        ];

        for (final id in testIds) {
          final int positiveId = id.hashCode & 0x7FFFFFFF;
          expect(positiveId, isNonNegative,
              reason: 'ID must never be negative for Android notification channel');
          expect(positiveId, lessThanOrEqualTo(0x7FFFFFFF),
              reason: 'ID must fit within 31-bit integer');
        }
      });
    });
  });
}
