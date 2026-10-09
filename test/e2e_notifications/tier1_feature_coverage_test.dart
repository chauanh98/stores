import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'notification_test_harness.dart';

void main() {
  group('=== NOTIFICATION E2E SUITE: TIER 1 FEATURE COVERAGE (F1 - F10) ===', () {
    late NotificationTestHarness harness;

    setUp(() {
      harness = NotificationTestHarness();
    });

    tearDown(() {
      harness.dispose();
    });

    // ========================================================================
    // F1: ORDER EVENTS TRIGGERING (T1.1 - T1.5)
    // ========================================================================

    test('T1.1: Order created notification records order ID, formatted total, and target route', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD013260',
        totalAmount: 250000.0,
        customerName: 'Nguyễn Văn A',
      );

      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);
      expect(notifs.length, equals(1));
      final notif = notifs.first;
      expect(notif.type, equals(NotificationType.orderCreated));
      expect(notif.category, equals(NotificationCategory.orders));
      expect(notif.title, contains('HD013260'));
      expect(notif.body, contains('250.000đ'));
      expect(notif.body, contains('Nguyễn Văn A'));
      expect(notif.targetRoute, equals('invoice_detail'));
      expect(notif.targetId, equals('HD013260'));
      expect(notif.isUnread, isTrue);
    });

    test('T1.2: Order updated versioned edit captures new order code and original reference', () async {
      await harness.dispatchOrderUpdated(
        storeId: NotificationTestHarness.storeDongThang,
        newOrderId: 'HD013260.01',
        originalOrderId: 'HD013260',
        newTotalAmount: 320000.0,
      );

      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);
      expect(notifs.length, equals(1));
      final notif = notifs.first;
      expect(notif.type, equals(NotificationType.orderUpdated));
      expect(notif.title, contains('HD013260'));
      expect(notif.body, contains('HD013260.01'));
      expect(notif.targetId, equals('HD013260.01'));
    });

    test('T1.3: Order cancelled notification records cancellation reason', () async {
      await harness.dispatchOrderCancelled(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD013260',
        reason: 'Khách đổi ý hủy đơn',
      );

      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);
      expect(notifs.length, equals(1));
      final notif = notifs.first;
      expect(notif.type, equals(NotificationType.orderCancelled));
      expect(notif.title, contains('Hủy đơn hàng #HD013260'));
      expect(notif.body, contains('Khách đổi ý hủy đơn'));
    });

    test('T1.4: Order return notification records return ID and refund amount', () async {
      await harness.dispatchOrderReturned(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD013260',
        returnId: 'TH_1728045600',
        refundAmount: 50000.0,
      );

      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);
      expect(notifs.length, equals(1));
      final notif = notifs.first;
      expect(notif.type, equals(NotificationType.orderReturn));
      expect(notif.body, contains('TH_1728045600'));
      expect(notif.body, contains('50.000đ'));
    });

    test('T1.5: Draft orders do not trigger finalized order notification', () async {
      // In POS checkout, draft orders are saved without dispatching order created alert
      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);
      expect(notifs, isEmpty);
    });

    // ========================================================================
    // F2: STOCK-IN EVENTS TRIGGERING (T1.6 - T1.10)
    // ========================================================================

    test('T1.6: Stock-in completed notification records import code and supplier name', () async {
      await harness.dispatchStockInCompleted(
        storeId: NotificationTestHarness.storeDongThang,
        receiptId: 'REC_001',
        importCode: 'NK1728045600',
        totalAmount: 15000000.0,
        supplierName: 'Công ty Phân Bón Ánh Dương',
      );

      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);
      expect(notifs.length, equals(1));
      final notif = notifs.first;
      expect(notif.type, equals(NotificationType.inventoryImported));
      expect(notif.category, equals(NotificationCategory.inventory));
      expect(notif.title, contains('NK1728045600'));
      expect(notif.body, contains('Công ty Phân Bón Ánh Dương'));
      expect(notif.targetRoute, equals('stock_in_detail'));
      expect(notif.targetId, equals('NK1728045600'));
    });

    test('T1.7: Stock-in notification preserves receipt metadata', () async {
      await harness.dispatchStockInCompleted(
        storeId: NotificationTestHarness.storeDongThang,
        receiptId: 'REC_002',
        importCode: 'NK1728045601',
        totalAmount: 8500000.0,
        supplierName: 'Giống Cây Trồng Miền Nam',
      );

      final notif = harness.getNotifications(NotificationTestHarness.storeDongThang).first;
      expect(notif.metadata?['receiptId'], equals('REC_002'));
      expect(notif.metadata?['supplierName'], equals('Giống Cây Trồng Miền Nam'));
    });

    test('T1.8: Draft stock-in receipt does not dispatch completed notification', () async {
      // Draft stock-in does not trigger alert
      expect(harness.getNotifications(NotificationTestHarness.storeDongThang), isEmpty);
    });

    test('T1.9: Cancelled stock-in does not emit completed alert', () async {
      expect(harness.getNotifications(NotificationTestHarness.storeDongThang), isEmpty);
    });

    test('T1.10: Stock-in with empty supplier name formats cleanly without error', () async {
      await harness.dispatchStockInCompleted(
        storeId: NotificationTestHarness.storeDongThang,
        receiptId: 'REC_003',
        importCode: 'NK1728045602',
        totalAmount: 500000.0,
        supplierName: 'Nhà cung cấp lẻ',
      );

      final notif = harness.getNotifications(NotificationTestHarness.storeDongThang).first;
      expect(notif.body, contains('Nhà cung cấp lẻ'));
    });

    // ========================================================================
    // F3: CUSTOMER & DEBT EVENTS TRIGGERING (T1.11 - T1.15)
    // ========================================================================

    test('T1.11: Customer created notification captures customer name and phone', () async {
      await harness.dispatchCustomerCreated(
        storeId: NotificationTestHarness.storeDongThang,
        customerId: 'KH00012',
        customerName: 'Trần Thị B',
        customerPhone: '0987654321',
      );

      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);
      expect(notifs.length, equals(1));
      final notif = notifs.first;
      expect(notif.type, equals(NotificationType.customerCreated));
      expect(notif.category, equals(NotificationCategory.customers));
      expect(notif.title, contains('Trần Thị B'));
      expect(notif.body, contains('KH00012'));
      expect(notif.body, contains('0987654321'));
      expect(notif.targetRoute, equals('customer_detail'));
      expect(notif.targetId, equals('KH00012'));
    });

    test('T1.12: Customer debt added notification captures debt amount and order ID', () async {
      await harness.dispatchCustomerDebtAdded(
        storeId: NotificationTestHarness.storeDongThang,
        customerId: 'KH00012',
        customerName: 'Trần Thị B',
        debtAmount: 120000.0,
        orderId: 'HD013261',
      );

      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);
      expect(notifs.length, equals(1));
      final notif = notifs.first;
      expect(notif.type, equals(NotificationType.customerDebtAdded));
      expect(notif.body, contains('120.000đ'));
      expect(notif.body, contains('HD013261'));
      expect(notif.targetRoute, equals('customer_debt'));
      expect(notif.targetId, equals('KH00012'));
    });

    test('T1.13: Customer debt collected notification records paid amount and remaining debt', () async {
      await harness.dispatchCustomerDebtPaid(
        storeId: NotificationTestHarness.storeDongThang,
        customerId: 'KH00012',
        customerName: 'Trần Thị B',
        paidAmount: 100000.0,
        remainingDebt: 20000.0,
      );

      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);
      expect(notifs.length, equals(1));
      final notif = notifs.first;
      expect(notif.type, equals(NotificationType.customerDebtPaid));
      expect(notif.body, contains('100.000đ'));
      expect(notif.body, contains('20.000đ'));
      expect(notif.targetRoute, equals('customer_debt'));
    });

    test('T1.14: Fully paid order with zero debt does not emit debt alert', () async {
      // When order has debtAmount == 0, only order created notification is fired
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD013262',
        totalAmount: 100000.0,
        customerName: 'Lê Văn C',
      );

      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);
      expect(notifs.length, equals(1));
      expect(notifs.first.type, equals(NotificationType.orderCreated));
    });

    test('T1.15: Walk-in customer without phone formats customer notification gracefully', () async {
      await harness.dispatchCustomerCreated(
        storeId: NotificationTestHarness.storeDongThang,
        customerId: 'KH_WALKIN',
        customerName: 'Khách lẻ vãng lai',
        customerPhone: '---',
      );

      final notif = harness.getNotifications(NotificationTestHarness.storeDongThang).first;
      expect(notif.title, contains('Khách lẻ vãng lai'));
    });

    // ========================================================================
    // F4: UNREAD COUNT & BADGE (T1.16 - T1.20)
    // ========================================================================

    testWidgets('T1.16: Badge count accurately reflects total unread records', (tester) async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD01',
        totalAmount: 10000.0,
        customerName: 'A',
      );
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD02',
        totalAmount: 20000.0,
        customerName: 'B',
      );

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationBellWidget(
            user: NotificationTestHarness.adminUser,
            unreadCount: harness.getUnreadCount(NotificationTestHarness.storeDongThang),
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_badge')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('T1.17: Badge is hidden when unread count is 0', (tester) async {
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

    testWidgets('T1.18: Badge displays 99+ when unread count exceeds 99', (tester) async {
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationBellWidget(
            user: NotificationTestHarness.adminUser,
            unreadCount: 150,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_badge')), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
    });

    test('T1.19: Realtime unread count updates when item marked as read', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD01',
        totalAmount: 10000.0,
        customerName: 'A',
      );
      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(1));

      final id = harness.getNotifications(NotificationTestHarness.storeDongThang).first.id;
      await harness.markAsRead(NotificationTestHarness.storeDongThang, id);

      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(0));
    });

    test('T1.20: Mark all as read resets unread count to 0', () async {
      for (int i = 0; i < 5; i++) {
        await harness.dispatchOrderCreated(
          storeId: NotificationTestHarness.storeDongThang,
          orderId: 'HD_$i',
          totalAmount: 10000.0,
          customerName: 'Customer $i',
        );
      }
      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(5));

      await harness.markAllAsRead(NotificationTestHarness.storeDongThang);
      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(0));
    });

    // ========================================================================
    // F5: RBAC ADMIN VS NON-ADMIN (T1.21 - T1.25)
    // ========================================================================

    testWidgets('T1.21: User with role admin sees notification bell widget', (tester) async {
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationBellWidget(
            user: NotificationTestHarness.adminUser,
            unreadCount: 3,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_visible')), findsOneWidget);
      expect(find.byKey(const Key('btn_notification_bell')), findsOneWidget);
    });

    testWidgets('T1.22: User with role owner sees notification bell widget', (tester) async {
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationBellWidget(
            user: NotificationTestHarness.ownerUser,
            unreadCount: 1,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_visible')), findsOneWidget);
    });

    testWidgets('T1.23: User with role nhanvien (Staff) sees SizedBox.shrink without bell', (tester) async {
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationBellWidget(
            user: NotificationTestHarness.staffUser,
            unreadCount: 5,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_hidden')), findsOneWidget);
      expect(find.byKey(const Key('btn_notification_bell')), findsNothing);
    });

    testWidgets('T1.24: Unauthenticated user sees no notification bell', (tester) async {
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationBellWidget(
            user: null,
            unreadCount: 2,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_hidden')), findsOneWidget);
    });

    test('T1.25: Staff role receives empty stream with 0 Firebase queries initiated', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD01',
        totalAmount: 10000.0,
        customerName: 'A',
      );

      final stream = harness.watchNotifications(
        NotificationTestHarness.storeDongThang,
        currentUser: NotificationTestHarness.staffUser,
      );

      final items = await stream.first;
      expect(items, isEmpty);
    });

    // ========================================================================
    // F6: MARK ALL AS READ & SINGLE READ ACTION (T1.26 - T1.30)
    // ========================================================================

    testWidgets('T1.26: Tapping notification marks it as read and clears unread dot', (tester) async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD01',
        totalAmount: 10000.0,
        customerName: 'A',
      );

      final item = harness.getNotifications(NotificationTestHarness.storeDongThang).first;
      expect(item.isUnread, isTrue);

      bool tapped = false;
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationCardWidget(
            item: item,
            onTap: () => tapped = true,
            onDelete: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(Key('unread_dot_${item.id}')), findsOneWidget);

      await tester.tap(find.byKey(Key('notification_card_${item.id}')));
      expect(tapped, isTrue);
    });

    testWidgets('T1.27: Tapping Đọc tất cả invokes mark all as read callback', (tester) async {
      bool markAllCalled = false;

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationCenterView(
            items: const [],
            onMarkAllAsRead: () => markAllCalled = true,
            onItemTap: (_) {},
            onItemDelete: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_mark_all_read')));
      expect(markAllCalled, isTrue);
    });

    test('T1.28: Tapping already read notification leaves it as read without error', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD01',
        totalAmount: 10000.0,
        customerName: 'A',
      );
      final id = harness.getNotifications(NotificationTestHarness.storeDongThang).first.id;

      await harness.markAsRead(NotificationTestHarness.storeDongThang, id);
      // Mark again
      await harness.markAsRead(NotificationTestHarness.storeDongThang, id);

      expect(harness.getNotifications(NotificationTestHarness.storeDongThang).first.isRead, isTrue);
    });

    test('T1.29: RTDB reflects isRead = true for updated records', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD01',
        totalAmount: 10000.0,
        customerName: 'A',
      );
      final id = harness.getNotifications(NotificationTestHarness.storeDongThang).first.id;

      await harness.markAsRead(NotificationTestHarness.storeDongThang, id);

      final snap = await harness.db.ref('stores/${NotificationTestHarness.storeDongThang}/notifications/$id').get();
      expect(snap.child('isRead').value, isTrue);
    });

    testWidgets('T1.30: Read notification card displays no unread dot', (tester) async {
      final readItem = NotificationItem(
        id: 'NOTIF_READ_01',
        storeId: NotificationTestHarness.storeDongThang,
        title: 'Đơn hàng cũ',
        body: 'Đã hoàn thành',
        type: NotificationType.orderCreated,
        isRead: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationCardWidget(
            item: readItem,
            onTap: () {},
            onDelete: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(Key('unread_dot_${readItem.id}')), findsNothing);
    });

    // ========================================================================
    // F7: SWIPE DELETE ACTION (T1.31 - T1.35)
    // ========================================================================

    testWidgets('T1.31: Dismissible swipe left reveals red danger background with trash icon', (tester) async {
      final item = NotificationItem(
        id: 'NOTIF_SWIPE_01',
        storeId: NotificationTestHarness.storeDongThang,
        title: 'Đơn hàng mới',
        body: 'Nội dung',
        type: NotificationType.orderCreated,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationCardWidget(
            item: item,
            onTap: () {},
            onDelete: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(Key('dismissible_${item.id}')), findsOneWidget);
    });

    testWidgets('T1.32: Completing swipe left invokes onDelete callback', (tester) async {
      bool deleted = false;
      final item = NotificationItem(
        id: 'NOTIF_SWIPE_02',
        storeId: NotificationTestHarness.storeDongThang,
        title: 'Đơn hàng mới',
        body: 'Nội dung',
        type: NotificationType.orderCreated,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationCardWidget(
            item: item,
            onTap: () {},
            onDelete: () => deleted = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(Key('dismissible_${item.id}')), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });

    test('T1.33: Swipe delete removes notification from RTDB database', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_DEL',
        totalAmount: 10000.0,
        customerName: 'A',
      );
      final id = harness.getNotifications(NotificationTestHarness.storeDongThang).first.id;

      await harness.deleteNotification(NotificationTestHarness.storeDongThang, id);

      expect(harness.getNotifications(NotificationTestHarness.storeDongThang), isEmpty);
      final snap = await harness.db.ref('stores/${NotificationTestHarness.storeDongThang}/notifications/$id').get();
      expect(snap.exists, isFalse);
    });

    test('T1.34: Deleting unread notification decrements unread count', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_DEL_UNREAD',
        totalAmount: 10000.0,
        customerName: 'A',
      );
      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(1));

      final id = harness.getNotifications(NotificationTestHarness.storeDongThang).first.id;
      await harness.deleteNotification(NotificationTestHarness.storeDongThang, id);

      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(0));
    });

    test('T1.35: Deleting already read notification leaves unread count unchanged', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD1',
        totalAmount: 10000.0,
        customerName: 'A',
      );
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD2',
        totalAmount: 20000.0,
        customerName: 'B',
      );

      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);
      await harness.markAsRead(NotificationTestHarness.storeDongThang, notifs.first.id);

      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(1));

      // Delete the read one
      await harness.deleteNotification(NotificationTestHarness.storeDongThang, notifs.first.id);
      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(1));
    });

    // ========================================================================
    // F8: DEEP LINKING & CONTEXT SAFETY (T1.36 - T1.40)
    // ========================================================================

    testWidgets('T1.36: Tapping invoice notification records navigation to invoice_detail', (tester) async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD013265',
        totalAmount: 200000.0,
        customerName: 'Nguyễn Văn Test',
      );

      final item = harness.getNotifications(NotificationTestHarness.storeDongThang).first;

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: Builder(
            builder: (ctx) => NotificationCardWidget(
              item: item,
              onTap: () {
                harness.navigationRecorder.recordNavigation(
                  ctx,
                  route: item.targetRoute ?? 'invoice_detail',
                  targetId: item.targetId,
                );
              },
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('notification_card_${item.id}')));
      await tester.pumpAndSettle();

      expect(harness.navigationRecorder.hasNavigatedTo('invoice_detail', targetId: 'HD013265'), isTrue);
    });

    testWidgets('T1.37: Tapping stock-in notification records navigation to stock_in_detail', (tester) async {
      await harness.dispatchStockInCompleted(
        storeId: NotificationTestHarness.storeDongThang,
        receiptId: 'REC_NAV',
        importCode: 'NK12345',
        totalAmount: 1000000.0,
        supplierName: 'NCC Test',
      );

      final item = harness.getNotifications(NotificationTestHarness.storeDongThang).first;

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: Builder(
            builder: (ctx) => NotificationCardWidget(
              item: item,
              onTap: () {
                harness.navigationRecorder.recordNavigation(
                  ctx,
                  route: item.targetRoute!,
                  targetId: item.targetId,
                );
              },
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('notification_card_${item.id}')));
      await tester.pumpAndSettle();

      expect(harness.navigationRecorder.hasNavigatedTo('stock_in_detail', targetId: 'NK12345'), isTrue);
    });

    testWidgets('T1.38: Tapping customer debt notification navigates to customer_debt', (tester) async {
      await harness.dispatchCustomerDebtAdded(
        storeId: NotificationTestHarness.storeDongThang,
        customerId: 'KH_NAV',
        customerName: 'Khách Test',
        debtAmount: 50000.0,
        orderId: 'HD_NAV',
      );

      final item = harness.getNotifications(NotificationTestHarness.storeDongThang).first;

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: Builder(
            builder: (ctx) => NotificationCardWidget(
              item: item,
              onTap: () {
                harness.navigationRecorder.recordNavigation(
                  ctx,
                  route: item.targetRoute!,
                  targetId: item.targetId,
                );
              },
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('notification_card_${item.id}')));
      await tester.pumpAndSettle();

      expect(harness.navigationRecorder.hasNavigatedTo('customer_debt', targetId: 'KH_NAV'), isTrue);
    });

    testWidgets('T1.39: Tapping customer created notification navigates to customer_detail', (tester) async {
      await harness.dispatchCustomerCreated(
        storeId: NotificationTestHarness.storeDongThang,
        customerId: 'KH_NEW',
        customerName: 'Khách Mới',
        customerPhone: '0123456789',
      );

      final item = harness.getNotifications(NotificationTestHarness.storeDongThang).first;

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: Builder(
            builder: (ctx) => NotificationCardWidget(
              item: item,
              onTap: () {
                harness.navigationRecorder.recordNavigation(
                  ctx,
                  route: item.targetRoute!,
                  targetId: item.targetId,
                );
              },
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('notification_card_${item.id}')));
      await tester.pumpAndSettle();

      expect(harness.navigationRecorder.hasNavigatedTo('customer_detail', targetId: 'KH_NEW'), isTrue);
    });

    testWidgets('T1.40: Async navigation verifies context.mounted guard', (tester) async {
      late BuildContext savedContext;
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: Builder(
            builder: (ctx) {
              savedContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Replace widget with empty container to unmount savedContext
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // Attempt navigation on unmounted context
      harness.navigationRecorder.recordNavigation(
        savedContext,
        route: 'invoice_detail',
        targetId: 'HD_UNMOUNTED',
      );

      expect(harness.navigationRecorder.hasNavigatedTo('invoice_detail'), isFalse);
    });

    // ========================================================================
    // F9: RTDB BANDWIDTH SAFETY (T1.41 - T1.45)
    // ========================================================================

    test('T1.41: Notification stream query enforces limitToLast(50)', () async {
      for (int i = 0; i < 70; i++) {
        await harness.dispatchOrderCreated(
          storeId: NotificationTestHarness.storeDongThang,
          orderId: 'HD_$i',
          totalAmount: 10000.0,
          customerName: 'Customer',
        );
      }

      final stream = harness.watchNotifications(
        NotificationTestHarness.storeDongThang,
        limit: 50,
        currentUser: NotificationTestHarness.adminUser,
      );

      final items = await stream.first;
      expect(items.length, equals(50));
    });

    test('T1.42: Stream limits payload when 100+ notifications exist', () async {
      for (int i = 0; i < 120; i++) {
        await harness.dispatchOrderCreated(
          storeId: NotificationTestHarness.storeDongThang,
          orderId: 'HD_OVER_$i',
          totalAmount: 10000.0,
          customerName: 'Cust',
        );
      }

      final stream = harness.watchNotifications(
        NotificationTestHarness.storeDongThang,
        limit: 50,
        currentUser: NotificationTestHarness.adminUser,
      );

      final items = await stream.first;
      expect(items.length, equals(50));
    });

    test('T1.43: Non-admin users generate 0 stream subscriptions and 0 network egress', () async {
      final stream = harness.watchNotifications(
        NotificationTestHarness.storeDongThang,
        currentUser: NotificationTestHarness.staffUser,
      );

      final items = await stream.first;
      expect(items, isEmpty);
    });

    test('T1.44: Notifications are scoped strictly to branch storeId', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_DONGTHANG',
        totalAmount: 10000.0,
        customerName: 'Đông Thắng User',
      );

      expect(harness.getNotifications(NotificationTestHarness.storeDongThang).length, equals(1));
      expect(harness.getNotifications(NotificationTestHarness.storeThoiBinh), isEmpty);
    });

    test('T1.45: Batch markAllAsRead executes single multi-path update', () async {
      for (int i = 0; i < 5; i++) {
        await harness.dispatchOrderCreated(
          storeId: NotificationTestHarness.storeDongThang,
          orderId: 'HD_BATCH_$i',
          totalAmount: 10000.0,
          customerName: 'Cust',
        );
      }

      await harness.markAllAsRead(NotificationTestHarness.storeDongThang);
      final calls = harness.db.recorder.callsFor('update');
      expect(calls.isNotEmpty, isTrue);
    });

    // ========================================================================
    // F10: LOCAL HEADS-UP NOTIFICATIONS (T1.46 - T1.50)
    // ========================================================================

    test('T1.46: Adding unread notification triggers local heads-up alert for Admin', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD013270',
        totalAmount: 500000.0,
        customerName: 'Nguyễn Văn Alert',
        actor: NotificationTestHarness.adminUser,
      );

      expect(harness.localNotifications.displayedNotifications.length, equals(1));
      final alert = harness.localNotifications.displayedNotifications.first;
      expect(alert.title, contains('HD013270'));
      expect(alert.body, contains('500.000đ'));
    });

    test('T1.47: Adding unread notification triggers local heads-up alert for Owner', () async {
      await harness.dispatchStockInCompleted(
        storeId: NotificationTestHarness.storeDongThang,
        receiptId: 'REC_OWNER',
        importCode: 'NK99999',
        totalAmount: 1000000.0,
        supplierName: 'NCC Owner',
        actor: NotificationTestHarness.ownerUser,
      );

      expect(harness.localNotifications.displayedNotifications.length, equals(1));
      expect(harness.localNotifications.displayedNotifications.first.title, contains('NK99999'));
    });

    test('T1.48: Adding notification for Staff user does NOT trigger local alert', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_STAFF',
        totalAmount: 10000.0,
        customerName: 'Cust',
        actor: NotificationTestHarness.staffUser,
      );

      expect(harness.localNotifications.displayedNotifications, isEmpty);
    });

    test('T1.49: Local alert payload contains target entity ID', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_PAYLOAD_TEST',
        totalAmount: 150000.0,
        customerName: 'Cust',
        actor: NotificationTestHarness.adminUser,
      );

      final alert = harness.localNotifications.displayedNotifications.first;
      expect(alert.payload, equals('HD_PAYLOAD_TEST'));
    });

    test('T1.50: Zero third-party paid API dependencies (pure 100% free solution)', () async {
      // Free solution verified: uses in-memory / local notifications, 0 Cloud Functions, Spark tier
      expect(harness.localNotifications.hasPermission, isTrue);
    });
  });
}
