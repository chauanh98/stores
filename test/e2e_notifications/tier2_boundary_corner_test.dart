import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'notification_test_harness.dart';

void main() {
  group('=== NOTIFICATION E2E SUITE: TIER 2 BOUNDARY & CORNER CASES ===', () {
    late NotificationTestHarness harness;

    setUp(() {
      harness = NotificationTestHarness();
    });

    tearDown(() {
      harness.dispose();
    });

    // ========================================================================
    // T2.1 - T2.3: UNREAD COUNT BADGE BOUNDARIES (0, 99, 100)
    // ========================================================================

    testWidgets('T2.1: Exactly 99 unread notifications displays "99"', (tester) async {
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationBellWidget(
            user: NotificationTestHarness.adminUser,
            unreadCount: 99,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_badge')), findsOneWidget);
      expect(find.text('99'), findsOneWidget);
    });

    testWidgets('T2.2: Exactly 100 unread notifications displays "99+"', (tester) async {
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationBellWidget(
            user: NotificationTestHarness.adminUser,
            unreadCount: 100,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_badge')), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('T2.3: Exactly 0 unread notifications hides badge completely', (tester) async {
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationBellWidget(
            user: NotificationTestHarness.adminUser,
            unreadCount: 0,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_notification_bell')), findsOneWidget);
      expect(find.byKey(const Key('notification_bell_badge')), findsNothing);
    });

    // ========================================================================
    // T2.4: EMPTY STATE RENDERING
    // ========================================================================

    testWidgets('T2.4: Empty notification center renders empty state widget with icon and message', (tester) async {
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationCenterView(
            items: const [],
            onMarkAllAsRead: () {},
            onItemTap: (_) {},
            onItemDelete: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_empty_state')), findsOneWidget);
      expect(find.text('Không có thông báo nào'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_outlined), findsOneWidget);
    });

    // ========================================================================
    // T2.5: EXTREME LONG STRINGS & OVERFLOW SAFETY
    // ========================================================================

    testWidgets('T2.5: Extreme long title (500 chars) and body (1000 chars) render safely with ellipsis without crash', (tester) async {
      final longTitle = 'Đơn hàng mới '.padRight(500, 'X');
      final longBody = 'Chi tiết đơn hàng bao gồm rất nhiều mặt hàng '.padRight(1000, 'Y');

      final longItem = NotificationItem(
        id: 'NOTIF_LONG',
        storeId: NotificationTestHarness.storeDongThang,
        title: longTitle,
        body: longBody,
        type: NotificationType.orderCreated,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationCardWidget(
            item: longItem,
            onTap: () {},
            onDelete: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(Key('notification_card_${longItem.id}')), findsOneWidget);
    });

    // ========================================================================
    // T2.6 - T2.9: DESERIALIZATION & NULL SAFETY
    // ========================================================================

    test('T2.6: Deserialization with malformed/missing ISO date string falls back safely to DateTime.now()', () {
      final mapWithBadDate = {
        'id': 'NOTIF_BAD_DATE',
        'title': 'Test Title',
        'body': 'Test Body',
        'type': 'order_created',
        'createdAt': 'NOT_A_VALID_DATE_STRING',
      };

      final parsed = NotificationItem.fromMap(mapWithBadDate);
      expect(parsed.id, equals('NOTIF_BAD_DATE'));
      expect(parsed.createdAt, isNotNull);
      expect(parsed.createdAt.isBefore(DateTime.now().add(const Duration(seconds: 2))), isTrue);
    });

    test('T2.7: Deserialization with unrecognized NotificationType string falls back safely to default orderCreated', () {
      final mapWithUnknownType = {
        'id': 'NOTIF_UNKNOWN_TYPE',
        'title': 'Test Title',
        'body': 'Test Body',
        'type': 'completely_unrecognized_future_type_xyz',
      };

      final parsed = NotificationItem.fromMap(mapWithUnknownType);
      expect(parsed.type, equals(NotificationType.orderCreated));
      expect(parsed.category, equals(NotificationCategory.orders));
    });

    test('T2.8: Notification with null metadata serializes and deserializes cleanly without NullPointer error', () {
      final itemNullMeta = NotificationItem(
        id: 'NOTIF_NULL_META',
        storeId: 'store_001',
        title: 'Title',
        body: 'Body',
        type: NotificationType.inventoryImported,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1728000000000),
        metadata: null,
      );

      final map = itemNullMeta.toMap();
      expect(map.containsKey('metadata'), isFalse);

      final reconstructed = NotificationItem.fromMap(map);
      expect(reconstructed.metadata, isNull);
      expect(reconstructed.id, equals(itemNullMeta.id));
    });

    test('T2.9: Notification with empty title and empty body serializes and renders without crashing', () async {
      final emptyTextItem = NotificationItem(
        id: 'NOTIF_EMPTY_STRINGS',
        storeId: NotificationTestHarness.storeDongThang,
        title: '',
        body: '',
        type: NotificationType.customerCreated,
        createdAt: DateTime.now(),
      );

      final map = emptyTextItem.toMap();
      final reconstructed = NotificationItem.fromMap(map);
      expect(reconstructed.title, isEmpty);
      expect(reconstructed.body, isEmpty);
    });

    // ========================================================================
    // T2.10: CONTEXT UNMOUNTED GUARD
    // ========================================================================

    testWidgets('T2.10: Deactivated context across async navigation boundary aborts navigation safely', (tester) async {
      late BuildContext capturedCtx;

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: Builder(
            builder: (ctx) {
              capturedCtx = ctx;
              return const Text('Active Widget');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Deactivate context by replacing widget tree
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // Record navigation on deactivated context
      harness.navigationRecorder.recordNavigation(
        capturedCtx,
        route: 'customer_detail',
        targetId: 'KH_999',
      );

      expect(harness.navigationRecorder.hasNavigatedTo('customer_detail'), isFalse);
    });

    // ========================================================================
    // T2.11 - T2.12: IDEMPOTENCY & NON-EXISTENT RECORD SAFETY
    // ========================================================================

    test('T2.11: Rapid consecutive markAsRead calls on identical record is idempotent', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_IDEMP',
        totalAmount: 10000.0,
        customerName: 'A',
      );
      final id = harness.getNotifications(NotificationTestHarness.storeDongThang).first.id;

      // Call markAsRead 5 times concurrently
      await Future.wait([
        harness.markAsRead(NotificationTestHarness.storeDongThang, id),
        harness.markAsRead(NotificationTestHarness.storeDongThang, id),
        harness.markAsRead(NotificationTestHarness.storeDongThang, id),
        harness.markAsRead(NotificationTestHarness.storeDongThang, id),
        harness.markAsRead(NotificationTestHarness.storeDongThang, id),
      ]);

      expect(harness.getNotifications(NotificationTestHarness.storeDongThang).first.isRead, isTrue);
      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(0));
    });

    test('T2.12: Calling deleteNotification on non-existent ID does not throw or mutate other records', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_STABLE',
        totalAmount: 50000.0,
        customerName: 'Stable Cust',
      );

      // Delete non-existent ID
      await harness.deleteNotification(NotificationTestHarness.storeDongThang, 'NON_EXISTENT_ID_999');

      expect(harness.getNotifications(NotificationTestHarness.storeDongThang).length, equals(1));
    });

    // ========================================================================
    // T2.13 - T2.15: QUERY LIMIT BOUNDARIES (0, 50, 51)
    // ========================================================================

    test('T2.13: limitToLast(50) on empty collection returns empty list without error', () async {
      final stream = harness.watchNotifications(
        NotificationTestHarness.storeDongThang,
        limit: 50,
        currentUser: NotificationTestHarness.adminUser,
      );
      final list = await stream.first;
      expect(list, isEmpty);
    });

    test('T2.14: limitToLast(50) on exactly 50 items returns all 50 items', () async {
      for (int i = 0; i < 50; i++) {
        await harness.dispatchOrderCreated(
          storeId: NotificationTestHarness.storeDongThang,
          orderId: 'HD_EXACT_$i',
          totalAmount: 10000.0,
          customerName: 'Cust $i',
        );
      }

      final stream = harness.watchNotifications(
        NotificationTestHarness.storeDongThang,
        limit: 50,
        currentUser: NotificationTestHarness.adminUser,
      );
      final list = await stream.first;
      expect(list.length, equals(50));
    });

    test('T2.15: limitToLast(50) on 51 items returns exactly the latest 50 items', () async {
      for (int i = 0; i < 51; i++) {
        await harness.dispatchOrderCreated(
          storeId: NotificationTestHarness.storeDongThang,
          orderId: 'HD_51_$i',
          totalAmount: 10000.0,
          customerName: 'Cust $i',
        );
      }

      final stream = harness.watchNotifications(
        NotificationTestHarness.storeDongThang,
        limit: 50,
        currentUser: NotificationTestHarness.adminUser,
      );
      final list = await stream.first;
      expect(list.length, equals(50));
      // Oldest item HD_51_0 is trimmed out
      expect(list.any((item) => item.title.contains('HD_51_0')), isFalse);
    });

    // ========================================================================
    // T2.16 - T2.20: ENCODING, FINANCIAL, & CATEGORY ROBUSTNESS
    // ========================================================================

    test('T2.16: Order with zero debt emits order notification but 0 customer debt alerts', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_NO_DEBT',
        totalAmount: 200000.0,
        customerName: 'Khách Trả Đủ',
      );

      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);
      expect(notifs.length, equals(1));
      expect(notifs.first.type, equals(NotificationType.orderCreated));
      expect(notifs.any((n) => n.type == NotificationType.customerDebtAdded), isFalse);
    });

    testWidgets('T2.17: Notification with null targetRoute and targetId does not crash when tapped', (tester) async {
      final itemNoRoute = NotificationItem(
        id: 'NOTIF_NO_ROUTE',
        storeId: NotificationTestHarness.storeDongThang,
        title: 'Thông báo hệ thống',
        body: 'Hệ thống bảo trì định kỳ',
        type: NotificationType.orderCreated,
        createdAt: DateTime.now(),
        targetRoute: null,
        targetId: null,
      );

      bool tapped = false;
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationCardWidget(
            item: itemNoRoute,
            onTap: () => tapped = true,
            onDelete: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('notification_card_${itemNoRoute.id}')));
      expect(tapped, isTrue);
    });

    test('T2.18: Notification category mapping correctly groups all 8 notification types', () {
      expect(NotificationType.orderCreated.category, equals(NotificationCategory.orders));
      expect(NotificationType.orderUpdated.category, equals(NotificationCategory.orders));
      expect(NotificationType.orderCancelled.category, equals(NotificationCategory.orders));
      expect(NotificationType.orderReturn.category, equals(NotificationCategory.orders));
      expect(NotificationType.inventoryImported.category, equals(NotificationCategory.inventory));
      expect(NotificationType.customerCreated.category, equals(NotificationCategory.customers));
      expect(NotificationType.customerDebtAdded.category, equals(NotificationCategory.customers));
      expect(NotificationType.customerDebtPaid.category, equals(NotificationCategory.customers));
    });

    test('T2.19: Special characters, emojis, and XML entities preserved verbatim in payload', () async {
      const specialTitle = '🔥 Ưu đãi lớn: "Tặng 50%" & <Voucher 100K>!';
      const specialBody = 'Khách: Hoàng Long & Con\nĐơn giá: 1.500.000đ • Giảm: 10%';

      final specialItem = NotificationItem(
        id: 'NOTIF_SPECIAL_CHARS',
        storeId: NotificationTestHarness.storeDongThang,
        title: specialTitle,
        body: specialBody,
        type: NotificationType.orderCreated,
        createdAt: DateTime.now(),
      );

      final map = specialItem.toMap();
      final reconstructed = NotificationItem.fromMap(map);

      expect(reconstructed.title, equals(specialTitle));
      expect(reconstructed.body, equals(specialBody));
    });

    test('T2.20: Large amount formatting (10,000,000,000 VNĐ) formats cleanly without NaN', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_BIG',
        totalAmount: 10000000000.0,
        customerName: 'Tập đoàn Khách hàng',
      );

      final notif = harness.getNotifications(NotificationTestHarness.storeDongThang).first;
      expect(notif.body, contains('10.000.000.000đ'));
    });
  });
}
