import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/notifications/local_notification_service.dart';
import 'package:stores/application/notifications/notifications_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FakeLocalNotificationService Tests', () {
    late FakeLocalNotificationService fakeService;

    setUp(() {
      fakeService = FakeLocalNotificationService();
    });

    test('initialize sets isInitialized to true and captures callback', () async {
      String? tappedPayload;
      final result = await fakeService.initialize(
        onNotificationTapped: (payload) => tappedPayload = payload,
      );

      expect(result, isTrue);
      expect(fakeService.isInitialized, isTrue);

      fakeService.simulateTap('test_payload_123');
      expect(tappedPayload, equals('test_payload_123'));
    });

    test('onNotificationTapped broadcast stream receives simulated taps', () async {
      final emitted = <String?>[];
      final sub = fakeService.onNotificationTapped.listen(emitted.add);

      fakeService.simulateTap('stream_payload_1');
      fakeService.simulateTap('stream_payload_2');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, equals(['stream_payload_1', 'stream_payload_2']));
      await sub.cancel();
    });

    test('requestPermissions returns configured value and marks flag', () async {
      fakeService.permissionResult = true;
      final res1 = await fakeService.requestPermissions();
      expect(res1, isTrue);
      expect(fakeService.permissionsRequested, isTrue);

      fakeService.permissionResult = false;
      final res2 = await fakeService.requestPermissions();
      expect(res2, isFalse);
    });

    test('showNotification records call parameters accurately', () async {
      await fakeService.showNotification(
        id: 42,
        title: 'New Order',
        body: 'Order #HD100 created',
        payload: '{"id":"HD100"}',
      );

      expect(fakeService.displayedCalls.length, equals(1));
      final call = fakeService.displayedCalls.first;
      expect(call.id, equals(42));
      expect(call.title, equals('New Order'));
      expect(call.body, equals('Order #HD100 created'));
      expect(call.payload, equals('{"id":"HD100"}'));
    });

    test('showFromNotificationItem transforms NotificationItem to 31-bit positive int and JSON payload', () async {
      final now = DateTime.utc(2026, 10, 4, 12, 0, 0);
      final item = NotificationItem(
        id: 'notif_abc_123',
        storeId: 'store_001',
        title: 'Đơn hàng mới',
        body: 'Khách hàng A thanh toán 500.000 đ',
        type: NotificationType.orderCreated,
        createdAt: now,
        targetRoute: '/orders/detail',
        targetId: 'HD013259',
      );

      await fakeService.showFromNotificationItem(item);

      expect(fakeService.displayedItems.length, equals(1));
      expect(fakeService.displayedItems.first, equals(item));
      expect(fakeService.displayedCalls.length, equals(1));

      final call = fakeService.displayedCalls.first;
      expect(call.id, isNonNegative);
      expect(call.id, equals(item.id.hashCode & 0x7FFFFFFF));
      expect(call.title, equals('Đơn hàng mới'));
      expect(call.body, equals('Khách hàng A thanh toán 500.000 đ'));

      final parsedPayload = NotificationPayload.tryParse(call.payload);
      expect(parsedPayload, isNotNull);
      expect(parsedPayload!.id, equals('notif_abc_123'));
      expect(parsedPayload.storeId, equals('store_001'));
      expect(parsedPayload.type, equals('order_created'));
      expect(parsedPayload.targetRoute, equals('/orders/detail'));
      expect(parsedPayload.targetId, equals('HD013259'));
    });

    test('cancel and cancelAll record cancellation state', () async {
      await fakeService.cancel(101);
      await fakeService.cancel(102);
      expect(fakeService.cancelledIds, equals([101, 102]));

      await fakeService.cancelAll();
      expect(fakeService.cancelledAll, isTrue);
    });

    test('clear resets recorded collections and flags', () async {
      await fakeService.showNotification(id: 1, title: 'T', body: 'B');
      await fakeService.cancel(1);
      await fakeService.requestPermissions();
      expect(fakeService.displayedCalls.isNotEmpty, isTrue);
      expect(fakeService.permissionsRequested, isTrue);

      fakeService.clear();
      expect(fakeService.displayedCalls.isEmpty, isTrue);
      expect(fakeService.displayedItems.isEmpty, isTrue);
      expect(fakeService.cancelledIds.isEmpty, isTrue);
      expect(fakeService.permissionsRequested, isFalse);
    });
  });

  group('NotificationPayload Serialization Tests', () {
    test('roundtrips valid payload between object and JSON string', () {
      const payload = NotificationPayload(
        id: 'n_1',
        storeId: 'store_002',
        type: 'inventory_imported',
        targetRoute: '/inventory/detail',
        targetId: 'NK1728045600',
      );

      final jsonStr = payload.toJsonString();
      final parsed = NotificationPayload.tryParse(jsonStr);

      expect(parsed, isNotNull);
      expect(parsed!.id, equals('n_1'));
      expect(parsed.storeId, equals('store_002'));
      expect(parsed.type, equals('inventory_imported'));
      expect(parsed.targetRoute, equals('/inventory/detail'));
      expect(parsed.targetId, equals('NK1728045600'));
    });

    test('tryParse handles null, empty, and invalid strings gracefully', () {
      expect(NotificationPayload.tryParse(null), isNull);
      expect(NotificationPayload.tryParse(''), isNull);
      expect(NotificationPayload.tryParse('   '), isNull);
      expect(NotificationPayload.tryParse('not a json'), isNull);
      expect(NotificationPayload.tryParse('42'), isNull);
      expect(NotificationPayload.tryParse('["array"]'), isNull);
    });

    test('tryParse handles partial maps missing optional fields', () {
      const jsonStr = '{"id":"n_partial","storeId":"store_001"}';
      final parsed = NotificationPayload.tryParse(jsonStr);

      expect(parsed, isNotNull);
      expect(parsed!.id, equals('n_partial'));
      expect(parsed.storeId, equals('store_001'));
      expect(parsed.type, isNull);
      expect(parsed.targetRoute, isNull);
      expect(parsed.targetId, isNull);
    });
  });

  group('NotificationListenerService Core Logic Tests', () {
    late FakeLocalNotificationService fakeService;
    late DateTime fixedNow;

    setUp(() {
      fakeService = FakeLocalNotificationService();
      fixedNow = DateTime.utc(2026, 10, 4, 12, 0, 0);
    });

    NotificationItem makeItem({
      required String id,
      required Duration ageAgo,
      bool isRead = false,
      NotificationType type = NotificationType.orderCreated,
    }) {
      return NotificationItem(
        id: id,
        storeId: 'store_001',
        title: 'Title for $id',
        body: 'Body for $id',
        type: type,
        isRead: isRead,
        createdAt: fixedNow.subtract(ageAgo),
      );
    }

    test('triggers notification for fresh unread item (< 60s)', () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      final freshItem = makeItem(id: 'item_1', ageAgo: const Duration(seconds: 15));
      final triggered = await listener.processNotifications([freshItem]);

      expect(triggered, equals(1));
      expect(fakeService.displayedCalls.length, equals(1));
      expect(fakeService.displayedCalls.first.title, equals('Title for item_1'));
      expect(listener.shownIds.contains('item_1'), isTrue);
    });

    test('ignores old unread item (> 60s) to prevent spam on initial load', () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      final oldItem = makeItem(id: 'item_old', ageAgo: const Duration(seconds: 75));
      final triggered = await listener.processNotifications([oldItem]);

      expect(triggered, equals(0));
      expect(fakeService.displayedCalls.isEmpty, isTrue);
      expect(listener.shownIds.contains('item_old'), isFalse);
    });

    test('ignores already read item even if fresh', () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      final readItem = makeItem(
        id: 'item_read',
        ageAgo: const Duration(seconds: 5),
        isRead: true,
      );
      final triggered = await listener.processNotifications([readItem]);

      expect(triggered, equals(0));
      expect(fakeService.displayedCalls.isEmpty, isTrue);
      expect(listener.shownIds.contains('item_read'), isFalse);
    });

    test('deduplicates: does not trigger again when same item is re-emitted in subsequent stream snapshot', () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      final item = makeItem(id: 'item_dedup', ageAgo: const Duration(seconds: 10));

      // First stream emission
      final count1 = await listener.processNotifications([item]);
      expect(count1, equals(1));
      expect(fakeService.displayedCalls.length, equals(1));

      // Second stream emission with identical item
      final count2 = await listener.processNotifications([item]);
      expect(count2, equals(0));
      expect(fakeService.displayedCalls.length, equals(1));
    });

    test('triggers for newly appended fresh items while skipping existing ones', () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      final item1 = makeItem(id: 'item_1', ageAgo: const Duration(seconds: 30));
      final item2 = makeItem(id: 'item_2', ageAgo: const Duration(seconds: 5));

      await listener.processNotifications([item1]);
      expect(fakeService.displayedCalls.length, equals(1));

      final count2 = await listener.processNotifications([item1, item2]);
      expect(count2, equals(1));
      expect(fakeService.displayedCalls.length, equals(2));
      expect(fakeService.displayedCalls.last.title, equals('Title for item_2'));
    });

    test('handles small future clock skew (-10s) tolerance gracefully', () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      final itemFuture = NotificationItem(
        id: 'item_future_skew',
        storeId: 'store_001',
        title: 'Title Future',
        body: 'Body Future',
        type: NotificationType.orderCreated,
        createdAt: fixedNow.add(const Duration(seconds: 4)),
      );

      final count = await listener.processNotifications([itemFuture]);
      expect(count, equals(1));
      expect(fakeService.displayedCalls.length, equals(1));
    });

    test('rejects timestamps excessively in the future (> 10s ahead)', () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      final itemWayFuture = NotificationItem(
        id: 'item_excessive_future',
        storeId: 'store_001',
        title: 'Title Way Future',
        body: 'Body Way Future',
        type: NotificationType.orderCreated,
        createdAt: fixedNow.add(const Duration(seconds: 30)),
      );

      final count = await listener.processNotifications([itemWayFuture]);
      expect(count, equals(0));
      expect(fakeService.displayedCalls.isEmpty, isTrue);
    });

    test('reset clears internal cache allowing fresh re-triggers', () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      final item = makeItem(id: 'item_reset', ageAgo: const Duration(seconds: 10));
      await listener.processNotifications([item]);
      expect(fakeService.displayedCalls.length, equals(1));

      listener.reset();
      expect(listener.shownIds.isEmpty, isTrue);

      final countAfterReset = await listener.processNotifications([item]);
      expect(countAfterReset, equals(1));
      expect(fakeService.displayedCalls.length, equals(2));
    });

    test('prunes shown IDs cache when exceeding memory threshold (500)', () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      final initialItems = List.generate(
        505,
        (i) => makeItem(id: 'bulk_$i', ageAgo: const Duration(seconds: 10)),
      );

      await listener.processNotifications(initialItems.sublist(0, 501));
      expect(listener.shownIds.length, greaterThan(500));

      final activeItems = [
        makeItem(id: 'bulk_0', ageAgo: const Duration(seconds: 10)),
        makeItem(id: 'bulk_504', ageAgo: const Duration(seconds: 5)),
      ];

      await listener.processNotifications(activeItems);
      expect(listener.shownIds.length, lessThanOrEqualTo(2));
    });
  });

  group('Riverpod Provider Integration Tests', () {
    late FakeLocalNotificationService fakeService;
    late StreamController<List<NotificationItem>> testStreamController;

    setUp(() {
      fakeService = FakeLocalNotificationService();
      testStreamController = StreamController<List<NotificationItem>>.broadcast();
    });

    tearDown(() async {
      await testStreamController.close();
    });

    test('notificationListenerServiceProvider triggers notifications on stream events', () async {
      final container = ProviderContainer(
        overrides: [
          localNotificationServiceProvider.overrideWithValue(fakeService),
          notificationStreamProvider.overrideWith(
            (ref) => testStreamController.stream,
          ),
        ],
      );
      addTearDown(container.dispose);

      final listener = container.read(notificationListenerServiceProvider);
      expect(listener, isNotNull);

      final freshItem = NotificationItem(
        id: 'stream_item_1',
        storeId: 'store_001',
        title: 'Stream Notification',
        body: 'Fresh Order Arrived',
        type: NotificationType.orderCreated,
        createdAt: DateTime.now().subtract(const Duration(seconds: 10)),
      );

      testStreamController.add([freshItem]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fakeService.displayedCalls.length, equals(1));
      expect(fakeService.displayedCalls.first.title, equals('Stream Notification'));
    });

    test('empty stream emits 0 notifications', () async {
      final container = ProviderContainer(
        overrides: [
          localNotificationServiceProvider.overrideWithValue(fakeService),
          notificationStreamProvider.overrideWith(
            (ref) => Stream.value(<NotificationItem>[]),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(notificationListenerServiceProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fakeService.displayedCalls.isEmpty, isTrue);
    });
  });

  group('FlutterLocalNotificationServiceImpl Resilience Tests', () {
    test('instantiates with default and custom plugin without throwing', () {
      final defaultService = FlutterLocalNotificationServiceImpl();
      expect(defaultService, isNotNull);
      expect(defaultService.isInitialized, isFalse);
    });

    test('initialize catches channel exceptions gracefully in test environment', () async {
      final service = FlutterLocalNotificationServiceImpl();
      final result = await service.initialize();
      expect(result, isFalse);
    });

    test('requestPermissions catches channel exceptions gracefully in test environment', () async {
      final service = FlutterLocalNotificationServiceImpl();
      final result = await service.requestPermissions();
      expect(result, isFalse);
    });

    test('showNotification catches channel exceptions gracefully without uncaught throw', () async {
      final service = FlutterLocalNotificationServiceImpl();
      await expectLater(
        service.showNotification(
          id: 99,
          title: 'Resilience Test',
          body: 'Must not crash',
        ),
        completes,
      );
    });
  });
}
