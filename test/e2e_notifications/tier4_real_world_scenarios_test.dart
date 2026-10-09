import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'notification_test_harness.dart';

void main() {
  group('=== NOTIFICATION E2E SUITE: TIER 4 REAL-WORLD SCENARIOS ===', () {
    late NotificationTestHarness harness;

    setUp(() {
      harness = NotificationTestHarness();
    });

    tearDown(() {
      harness.dispose();
    });

    // ========================================================================
    // SCENARIO 1: COMPLETE POS RETAIL CHECKOUT FLOW
    // ========================================================================

    testWidgets('T4.1: POS Retail Checkout -> Notification Dispatched -> Bell Badge Updates -> Admin taps card -> Deep links to Invoice Detail -> Marked read', (tester) async {
      // 1. POS Checkout completed by cashier
      const orderId = 'HD013280';
      const storeId = NotificationTestHarness.storeDongThang;

      await harness.dispatchOrderCreated(
        storeId: storeId,
        orderId: orderId,
        totalAmount: 450000.0,
        customerName: 'Nguyễn Văn A',
        actor: NotificationTestHarness.adminUser,
      );

      // Verify RTDB state
      final notifs = harness.getNotifications(storeId);
      expect(notifs.length, equals(1));
      expect(notifs.first.isUnread, isTrue);

      // Verify Local Heads-Up alert
      expect(harness.localNotifications.displayedNotifications.length, equals(1));
      expect(harness.localNotifications.displayedNotifications.first.payload, equals(orderId));

      // 2. Admin inspects AppBar bell with reactive badge
      int currentUnread = harness.getUnreadCount(storeId);
      expect(currentUnread, equals(1));

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return Column(
                children: [
                  NotificationBellWidget(
                    user: NotificationTestHarness.adminUser,
                    unreadCount: currentUnread,
                    onTap: () {},
                  ),
                  Expanded(
                    child: NotificationCenterView(
                      items: harness.getNotifications(storeId),
                      onMarkAllAsRead: () {},
                      onItemTap: (item) async {
                        await harness.markAsRead(storeId, item.id);
                        harness.navigationRecorder.recordNavigation(
                          ctx,
                          route: item.targetRoute!,
                          targetId: item.targetId,
                        );
                        setState(() {
                          currentUnread = harness.getUnreadCount(storeId);
                        });
                      },
                      onItemDelete: (_) {},
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check badge displays '1'
      expect(find.byKey(const Key('notification_bell_badge')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      // Tap the notification card
      final cardFinder = find.byKey(Key('notification_card_${notifs.first.id}'));
      expect(cardFinder, findsOneWidget);

      await tester.tap(cardFinder);
      await tester.pumpAndSettle();

      // Verify deep linking occurred to 'invoice_detail' with orderId
      expect(harness.navigationRecorder.hasNavigatedTo('invoice_detail', targetId: orderId), isTrue);

      // Verify notification is marked read in RTDB
      final snap = await harness.db.ref('stores/$storeId/notifications/${notifs.first.id}').get();
      expect(snap.child('isRead').value, isTrue);

      // Verify badge count decremented to 0 and badge disappears
      expect(harness.getUnreadCount(storeId), equals(0));
      expect(find.byKey(const Key('notification_bell_badge')), findsNothing);
    });

    // ========================================================================
    // SCENARIO 2: VERSIONED INVOICE EDIT REPLACEMENT FLOW
    // ========================================================================

    testWidgets('T4.2: Sửa hóa đơn HD013259 -> Replaced by HD013259.01 -> Cancel and New Version notifications -> Admin inspects replacement', (tester) async {
      const storeId = NotificationTestHarness.storeDongThang;
      const originalOrderId = 'HD013259';
      const versionedOrderId = 'HD013259.01';

      // 1. Cancel original invoice as replacement
      await harness.dispatchOrderCancelled(
        storeId: storeId,
        orderId: originalOrderId,
        reason: 'Đã sửa thành $versionedOrderId',
      );

      // 2. Dispatch new versioned invoice
      await harness.dispatchOrderUpdated(
        storeId: storeId,
        newOrderId: versionedOrderId,
        originalOrderId: originalOrderId,
        newTotalAmount: 520000.0,
      );

      expect(harness.getUnreadCount(storeId), equals(2));

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationCenterView(
            items: harness.getNotifications(storeId),
            onMarkAllAsRead: () {},
            onItemTap: (item) {
              harness.navigationRecorder.recordNavigation(
                tester.element(find.byType(NotificationCenterView)),
                route: item.targetRoute!,
                targetId: item.targetId,
              );
            },
            onItemDelete: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify both notifications appear in order list
      expect(find.textContaining('Hủy đơn hàng #$originalOrderId'), findsOneWidget);
      expect(find.textContaining('Đã sửa hóa đơn #$originalOrderId'), findsOneWidget);
      expect(find.textContaining(versionedOrderId), findsWidgets);

      // Tap on the new version notification card
      final versionedNotif = harness.getNotifications(storeId).firstWhere((n) => n.targetId == versionedOrderId);
      await tester.tap(find.byKey(Key('notification_card_${versionedNotif.id}')));
      await tester.pumpAndSettle();

      // Deep linked to the new versioned order
      expect(harness.navigationRecorder.hasNavigatedTo('invoice_detail', targetId: versionedOrderId), isTrue);
    });

    // ========================================================================
    // SCENARIO 3: COMPLETE STOCK-IN RECEIPT FLOW
    // ========================================================================

    testWidgets('T4.3: Stock-In Completion -> Inventory Notification -> Heads-up alert -> Admin deep links to StockInDetail', (tester) async {
      const storeId = NotificationTestHarness.storeDongThang;
      const receiptId = 'REC_20261004_01';
      const importCode = 'NK1728045700';

      // 1. Complete Stock-In Receipt
      await harness.dispatchStockInCompleted(
        storeId: storeId,
        receiptId: receiptId,
        importCode: importCode,
        totalAmount: 25000000.0,
        supplierName: 'Công ty Phân Bón Ánh Dương',
        actor: NotificationTestHarness.adminUser,
      );

      // Verify local heads-up alert fired
      expect(harness.localNotifications.displayedNotifications.length, equals(1));
      expect(harness.localNotifications.displayedNotifications.first.payload, equals(importCode));

      // 2. Admin opens Notification Center and filters by Nhập kho
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationCenterView(
            items: harness.getNotifications(storeId),
            onMarkAllAsRead: () {},
            onItemTap: (item) {
              harness.navigationRecorder.recordNavigation(
                tester.element(find.byType(NotificationCenterView)),
                route: item.targetRoute!,
                targetId: item.targetId,
              );
            },
            onItemDelete: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chip_filter_inventory')));
      await tester.pumpAndSettle();

      expect(find.textContaining(importCode), findsOneWidget);
      expect(find.textContaining('Phân Bón Ánh Dương'), findsOneWidget);
      expect(find.textContaining('25.000.000đ'), findsOneWidget);

      // Tap card
      final notif = harness.getNotifications(storeId).first;
      await tester.tap(find.byKey(Key('notification_card_${notif.id}')));
      await tester.pumpAndSettle();

      expect(harness.navigationRecorder.hasNavigatedTo('stock_in_detail', targetId: importCode), isTrue);
    });

    // ========================================================================
    // SCENARIO 4: CUSTOMER CREDIT & DEBT SETTLEMENT CYCLE
    // ========================================================================

    testWidgets('T4.4: Customer Credit Sale -> Debt Incurred Alert -> Debt Collection Payment Alert -> Customer Tab Audit', (tester) async {
      const storeId = NotificationTestHarness.storeDongThang;
      const customerId = 'KH0099';
      const customerName = 'Trần Thị Nợ';

      // 1. Credit sale: total 1,000,000đ, debt 600,000đ
      await harness.dispatchOrderCreated(
        storeId: storeId,
        orderId: 'HD013290',
        totalAmount: 1000000.0,
        customerName: customerName,
      );
      await harness.dispatchCustomerDebtAdded(
        storeId: storeId,
        customerId: customerId,
        customerName: customerName,
        debtAmount: 600000.0,
        orderId: 'HD013290',
      );

      // 2. Later: Debt payment collected
      await harness.dispatchCustomerDebtPaid(
        storeId: storeId,
        customerId: customerId,
        customerName: customerName,
        paidAmount: 600000.0,
        remainingDebt: 0.0,
      );

      expect(harness.getUnreadCount(storeId), equals(3));

      // 3. Admin opens Notification Center and filters to Khách hàng
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationCenterView(
            items: harness.getNotifications(storeId),
            onMarkAllAsRead: () async {
              await harness.markAllAsRead(storeId);
            },
            onItemTap: (item) {
              harness.navigationRecorder.recordNavigation(
                tester.element(find.byType(NotificationCenterView)),
                route: item.targetRoute!,
                targetId: item.targetId,
              );
            },
            onItemDelete: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chip_filter_customers')));
      await tester.pumpAndSettle();

      // Verify both debt transactions are visible under Customer tab
      expect(find.textContaining('Ghi nhận công nợ mới: $customerName'), findsOneWidget);
      expect(find.textContaining('Thu nợ khách hàng: $customerName'), findsOneWidget);
      expect(find.textContaining('Phát sinh 600.000đ từ đơn hàng #HD013290'), findsOneWidget);
      expect(find.textContaining('Đã thu 600.000đ • Nợ còn: 0đ'), findsOneWidget);

      // Tap debt payment notification
      final paidNotif = harness.getNotifications(storeId).firstWhere((n) => n.type == NotificationType.customerDebtPaid);
      await tester.tap(find.byKey(Key('notification_card_${paidNotif.id}')));
      await tester.pumpAndSettle();

      expect(harness.navigationRecorder.hasNavigatedTo('customer_debt', targetId: customerId), isTrue);

      // Mark all as read
      await tester.tap(find.byKey(const Key('btn_mark_all_read')));
      await tester.pumpAndSettle();

      expect(harness.getUnreadCount(storeId), equals(0));
    });

    // ========================================================================
    // SCENARIO 5: MULTI-STORE ADMINISTRATOR DAILY OPERATIONS
    // ========================================================================

    testWidgets('T4.5: Multi-Store Admin: Đông Thắng (store_001) vs Thới Bình (store_002) stream switching & action scoping', (tester) async {
      String activeStore = NotificationTestHarness.storeDongThang;

      // Seed 3 orders in store_001
      for (int i = 1; i <= 3; i++) {
        await harness.dispatchOrderCreated(
          storeId: NotificationTestHarness.storeDongThang,
          orderId: 'HD_DT_0$i',
          totalAmount: 100000.0 * i,
          customerName: 'Khách ĐT $i',
        );
      }

      // Seed 2 shipments in store_002
      for (int i = 1; i <= 2; i++) {
        await harness.dispatchStockInCompleted(
          storeId: NotificationTestHarness.storeThoiBinh,
          receiptId: 'REC_TB_0$i',
          importCode: 'NK_TB_0$i',
          totalAmount: 5000000.0 * i,
          supplierName: 'NCC Thới Bình $i',
        );
      }

      // 1. In store_001 (Đông Thắng)
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return Column(
                children: [
                  NotificationBellWidget(
                    user: NotificationTestHarness.adminUser,
                    unreadCount: harness.getUnreadCount(activeStore),
                    onTap: () {},
                  ),
                  Expanded(
                    child: NotificationCenterView(
                      items: harness.getNotifications(activeStore),
                      onMarkAllAsRead: () async {
                        await harness.markAllAsRead(activeStore);
                        setState(() {});
                      },
                      onItemTap: (_) {},
                      onItemDelete: (item) async {
                        await harness.deleteNotification(activeStore, item.id);
                        setState(() {});
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget); // Badge shows 3
      expect(find.textContaining('HD_DT_01'), findsOneWidget);
      expect(find.textContaining('NK_TB_01'), findsNothing); // Thới Bình items hidden

      // Mark all read in store_001
      await tester.tap(find.byKey(const Key('btn_mark_all_read')));
      await tester.pumpAndSettle();

      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(0));
      expect(find.byKey(const Key('notification_bell_badge')), findsNothing);

      // 2. Switch store to store_002 (Thới Bình)
      activeStore = NotificationTestHarness.storeThoiBinh;
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return Column(
                children: [
                  NotificationBellWidget(
                    user: NotificationTestHarness.adminUser,
                    unreadCount: harness.getUnreadCount(activeStore),
                    onTap: () {},
                  ),
                  Expanded(
                    child: NotificationCenterView(
                      items: harness.getNotifications(activeStore),
                      onMarkAllAsRead: () async {
                        await harness.markAllAsRead(activeStore);
                        setState(() {});
                      },
                      onItemTap: (_) {},
                      onItemDelete: (item) async {
                        await harness.deleteNotification(activeStore, item.id);
                        setState(() {});
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget); // Badge shows 2
      expect(find.textContaining('NK_TB_01'), findsOneWidget);
      expect(find.textContaining('NK_TB_02'), findsOneWidget);

      // Swipe delete first shipment
      final notifToDelete = harness.getNotifications(activeStore).first;
      await tester.drag(find.byKey(Key('dismissible_${notifToDelete.id}')), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Badge decremented to 1 in store_002
      expect(harness.getUnreadCount(NotificationTestHarness.storeThoiBinh), equals(1));
      expect(find.text('1'), findsOneWidget);
    });
  });
}
