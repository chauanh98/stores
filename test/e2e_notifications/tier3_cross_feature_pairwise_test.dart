import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'notification_test_harness.dart';

void main() {
  group('=== NOTIFICATION E2E SUITE: TIER 3 CROSS-FEATURE COMBINATIONS ===', () {
    late NotificationTestHarness harness;

    setUp(() {
      harness = NotificationTestHarness();
    });

    tearDown(() {
      harness.dispose();
    });

    // ========================================================================
    // T3.1: FILTER CHIP SELECTION + MARK ALL AS READ
    // ========================================================================

    testWidgets('T3.1: Selecting category filter chip and tapping Mark all as read updates all items and clears unread badges', (tester) async {
      // Seed 2 orders and 1 inventory
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_PAIR_01',
        totalAmount: 100000.0,
        customerName: 'A',
      );
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_PAIR_02',
        totalAmount: 150000.0,
        customerName: 'B',
      );
      await harness.dispatchStockInCompleted(
        storeId: NotificationTestHarness.storeDongThang,
        receiptId: 'REC_PAIR_01',
        importCode: 'NK_PAIR_01',
        totalAmount: 5000000.0,
        supplierName: 'NCC C',
      );

      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(3));

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationCenterView(
            items: harness.getNotifications(NotificationTestHarness.storeDongThang),
            onMarkAllAsRead: () async {
              await harness.markAllAsRead(NotificationTestHarness.storeDongThang);
            },
            onItemTap: (_) {},
            onItemDelete: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Select Hóa đơn filter chip
      await tester.tap(find.byKey(const Key('chip_filter_orders')));
      await tester.pumpAndSettle();

      // Verify only 2 order items are displayed
      expect(find.textContaining('HD_PAIR_01'), findsOneWidget);
      expect(find.textContaining('HD_PAIR_02'), findsOneWidget);
      expect(find.textContaining('NK_PAIR_01'), findsNothing);

      // 2. Tap Mark all as read
      await tester.tap(find.byKey(const Key('btn_mark_all_read')));
      await tester.pumpAndSettle();

      // Verify all items are now marked read in harness
      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(0));
    });

    // ========================================================================
    // T3.2: FILTER CHIP SELECTION + SWIPE DELETE
    // ========================================================================

    testWidgets('T3.2: Swipe-deleting an item while filtered retains category filter state without jumping to All', (tester) async {
      await harness.dispatchStockInCompleted(
        storeId: NotificationTestHarness.storeDongThang,
        receiptId: 'REC_DEL_01',
        importCode: 'NK_DEL_01',
        totalAmount: 2000000.0,
        supplierName: 'NCC 1',
      );
      await harness.dispatchStockInCompleted(
        storeId: NotificationTestHarness.storeDongThang,
        receiptId: 'REC_DEL_02',
        importCode: 'NK_DEL_02',
        totalAmount: 3000000.0,
        supplierName: 'NCC 2',
      );

      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return NotificationCenterView(
                items: harness.getNotifications(NotificationTestHarness.storeDongThang),
                onMarkAllAsRead: () {},
                onItemTap: (_) {},
                onItemDelete: (item) async {
                  await harness.deleteNotification(NotificationTestHarness.storeDongThang, item.id);
                  setState(() {});
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select Nhập kho chip
      await tester.tap(find.byKey(const Key('chip_filter_inventory')));
      await tester.pumpAndSettle();

      expect(find.textContaining('NK_DEL_01'), findsOneWidget);
      expect(find.textContaining('NK_DEL_02'), findsOneWidget);

      // Swipe delete first item
      final firstId = notifs.first.id;
      await tester.drag(find.byKey(Key('dismissible_$firstId')), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Only second item remains
      expect(find.textContaining('NK_DEL_01'), findsNothing);
      expect(find.textContaining('NK_DEL_02'), findsOneWidget);

      // Verify category chip is still Nhập kho
      final chipFinder = find.byKey(const Key('chip_filter_inventory'));
      final ChoiceChip chip = tester.widget(chipFinder);
      expect(chip.selected, isTrue);
    });

    // ========================================================================
    // T3.3: REALTIME ARRIVAL WHILE VIEWING FILTERED TAB
    // ========================================================================

    testWidgets('T3.3: Realtime event arrival updates bell badge and populates appropriate tab', (tester) async {
      // Initial: 1 customer notification
      await harness.dispatchCustomerCreated(
        storeId: NotificationTestHarness.storeDongThang,
        customerId: 'KH01',
        customerName: 'Khách A',
        customerPhone: '0901',
      );

      int currentUnread = harness.getUnreadCount(NotificationTestHarness.storeDongThang);
      expect(currentUnread, equals(1));

      // Build NotificationBellWidget
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
                      items: harness.getNotifications(NotificationTestHarness.storeDongThang),
                      onMarkAllAsRead: () {},
                      onItemTap: (_) {},
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

      expect(find.text('1'), findsOneWidget); // Badge

      // Background order arrives
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_NEW_REALTIME',
        totalAmount: 300000.0,
        customerName: 'Khách B',
      );
      currentUnread = harness.getUnreadCount(NotificationTestHarness.storeDongThang);

      // Re-pump UI to simulate stream update
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: Column(
            children: [
              NotificationBellWidget(
                user: NotificationTestHarness.adminUser,
                unreadCount: currentUnread,
                onTap: () {},
              ),
              Expanded(
                child: NotificationCenterView(
                  items: harness.getNotifications(NotificationTestHarness.storeDongThang),
                  onMarkAllAsRead: () {},
                  onItemTap: (_) {},
                  onItemDelete: (_) {},
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget); // Badge updated to 2
      expect(find.textContaining('HD_NEW_REALTIME'), findsOneWidget);
    });

    // ========================================================================
    // T3.4: RBAC SESSION STATE TRANSITION
    // ========================================================================

    testWidgets('T3.4: Session switch from Admin to Staff hides Bell and closes stream; Admin login restores Bell', (tester) async {
      UserAccount? sessionUser = NotificationTestHarness.adminUser;

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return NotificationBellWidget(
                user: sessionUser,
                unreadCount: 3,
                onTap: () {},
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Admin sees bell
      expect(find.byKey(const Key('notification_bell_visible')), findsOneWidget);

      // 2. Logout -> user is null
      sessionUser = null;
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationBellWidget(
            user: sessionUser,
            unreadCount: 3,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notification_bell_hidden')), findsOneWidget);

      // 3. Login as Staff -> bell remains hidden
      sessionUser = NotificationTestHarness.staffUser;
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationBellWidget(
            user: sessionUser,
            unreadCount: 3,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notification_bell_hidden')), findsOneWidget);

      // 4. Login back as Owner -> bell appears
      sessionUser = NotificationTestHarness.ownerUser;
      await tester.pumpWidget(
        buildNotificationTestApp(
          child: NotificationBellWidget(
            user: sessionUser,
            unreadCount: 3,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notification_bell_visible')), findsOneWidget);
    });

    // ========================================================================
    // T3.5: MULTI-STORE BRANCH ISOLATION
    // ========================================================================

    test('T3.5: Events in store_001 are strictly isolated from store_002', () async {
      // Event in Dong Thang (store_001)
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_DT_01',
        totalAmount: 100000.0,
        customerName: 'Dong Thang Client',
      );

      // Event in Thoi Binh (store_002)
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeThoiBinh,
        orderId: 'HD_TB_01',
        totalAmount: 200000.0,
        customerName: 'Thoi Binh Client',
      );

      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(1));
      expect(harness.getUnreadCount(NotificationTestHarness.storeThoiBinh), equals(1));

      // Mark all read in store_001 only
      await harness.markAllAsRead(NotificationTestHarness.storeDongThang);

      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(0));
      // store_002 remains unread
      expect(harness.getUnreadCount(NotificationTestHarness.storeThoiBinh), equals(1));
    });

    // ========================================================================
    // T3.6: CONCURRENT SWIPE DELETE & BACKGROUND EVENT
    // ========================================================================

    test('T3.6: Concurrent swipe delete while background event arrives maintains store consistency', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_CONC_1',
        totalAmount: 10000.0,
        customerName: 'A',
      );
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_CONC_2',
        totalAmount: 20000.0,
        customerName: 'B',
      );

      final notifs = harness.getNotifications(NotificationTestHarness.storeDongThang);
      final idToDelete = notifs.first.id;

      // Execute delete on first item and add third item concurrently
      await Future.wait([
        harness.deleteNotification(NotificationTestHarness.storeDongThang, idToDelete),
        harness.dispatchOrderCreated(
          storeId: NotificationTestHarness.storeDongThang,
          orderId: 'HD_CONC_3',
          totalAmount: 30000.0,
          customerName: 'C',
        ),
      ]);

      final updated = harness.getNotifications(NotificationTestHarness.storeDongThang);
      expect(updated.length, equals(2));
      expect(updated.any((n) => n.id == idToDelete), isFalse);
      expect(updated.any((n) => n.title.contains('HD_CONC_3')), isTrue);
    });

    // ========================================================================
    // T3.7: NOTIFICATION TAP -> DEEP LINK NAV -> UNREAD DECREMENT
    // ========================================================================

    testWidgets('T3.7: Tapping notification marks it read, decrements unread count, and opens target detail sheet', (tester) async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_TAP_TEST',
        totalAmount: 500000.0,
        customerName: 'Khách Tap',
      );

      final item = harness.getNotifications(NotificationTestHarness.storeDongThang).first;
      expect(item.isUnread, isTrue);
      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(1));

      await tester.pumpWidget(
        buildNotificationTestApp(
          child: Builder(
            builder: (ctx) => NotificationCardWidget(
              item: item,
              onTap: () async {
                await harness.markAsRead(NotificationTestHarness.storeDongThang, item.id);
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

      expect(harness.navigationRecorder.hasNavigatedTo('invoice_detail', targetId: 'HD_TAP_TEST'), isTrue);
      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(0));
    });

    // ========================================================================
    // T3.8: INTERLEAVED EVENTS IN STREAM
    // ========================================================================

    test('T3.8: Interleaved order, stock-in, and debt events sort strictly descending by createdAt', () async {
      final t1 = DateTime(2026, 10, 4, 10, 0);
      final t2 = DateTime(2026, 10, 4, 10, 5);
      final t3 = DateTime(2026, 10, 4, 10, 10);

      final notifOrder = NotificationItem(
        id: 'N_ORD',
        storeId: NotificationTestHarness.storeDongThang,
        title: 'Order 1',
        body: 'Body',
        type: NotificationType.orderCreated,
        createdAt: t1,
      );
      final notifStock = NotificationItem(
        id: 'N_STK',
        storeId: NotificationTestHarness.storeDongThang,
        title: 'Stock 1',
        body: 'Body',
        type: NotificationType.inventoryImported,
        createdAt: t3, // Most recent
      );
      final notifDebt = NotificationItem(
        id: 'N_DEBT',
        storeId: NotificationTestHarness.storeDongThang,
        title: 'Debt 1',
        body: 'Body',
        type: NotificationType.customerDebtAdded,
        createdAt: t2,
      );

      await harness.addNotification(notifOrder);
      await harness.addNotification(notifStock);
      await harness.addNotification(notifDebt);

      final stream = harness.watchNotifications(
        NotificationTestHarness.storeDongThang,
        currentUser: NotificationTestHarness.adminUser,
      );
      final list = await stream.first;

      expect(list.length, equals(3));
      expect(list[0].id, equals('N_STK')); // t3
      expect(list[1].id, equals('N_DEBT')); // t2
      expect(list[2].id, equals('N_ORD')); // t1
    });

    // ========================================================================
    // T3.9: LOCAL HEADS-UP ALERT SUPPRESSION DURING STAFF SESSION
    // ========================================================================

    test('T3.9: Orders created by Staff do not trigger heads-up alert on Staff device', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_STAFF_POS',
        totalAmount: 120000.0,
        customerName: 'Customer',
        actor: NotificationTestHarness.staffUser,
      );

      expect(harness.localNotifications.displayedNotifications, isEmpty);
    });

    // ========================================================================
    // T3.10: MARK ALL READ WITH MIXED READ AND UNREAD ITEMS
    // ========================================================================

    test('T3.10: Mark all read on mixed items modifies only unread records', () async {
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_MIX_1',
        totalAmount: 10000.0,
        customerName: 'A',
      );
      await harness.dispatchOrderCreated(
        storeId: NotificationTestHarness.storeDongThang,
        orderId: 'HD_MIX_2',
        totalAmount: 20000.0,
        customerName: 'B',
      );

      // Pre-mark first one as read
      final firstId = harness.getNotifications(NotificationTestHarness.storeDongThang).first.id;
      await harness.markAsRead(NotificationTestHarness.storeDongThang, firstId);
      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(1));

      // Mark all read
      await harness.markAllAsRead(NotificationTestHarness.storeDongThang);
      expect(harness.getUnreadCount(NotificationTestHarness.storeDongThang), equals(0));
    });
  });
}
