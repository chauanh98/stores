import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/presentation/notifications/pages/notifications_page.dart';
import 'package:stores/presentation/notifications/utils/notification_navigation_handler.dart';
import 'package:stores/presentation/notifications/widgets/notification_card.dart';

// ============================================================================
// ADVERSARIAL TEST DOUBLES & MOCKS
// ============================================================================

class _AdversarialNotificationRepository implements NotificationRepository {
  final List<NotificationItem> items;
  final List<String> markedReadIds = [];
  final List<String> deletedIds = [];
  final List<NotificationItem> addedItems = [];
  int markAllAsReadCalls = 0;
  Completer<void>? markAllAsReadCompleter;
  Completer<void>? markAsReadCompleter;
  bool shouldThrowOnMarkAllAsRead = false;
  bool shouldThrowOnDelete = false;

  final StreamController<List<NotificationItem>> _controller =
      StreamController<List<NotificationItem>>.broadcast();

  _AdversarialNotificationRepository(List<NotificationItem> initial)
      : items = List.from(initial);

  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
      {int limit = 50}) async* {
    yield List.unmodifiable(items);
    yield* _controller.stream;
  }

  void emitCurrent() {
    _controller.add(List.unmodifiable(items));
  }

  @override
  Future<void> addNotification(NotificationItem notification) async {
    addedItems.add(notification);
    items.insert(0, notification);
    emitCurrent();
  }

  @override
  Future<void> markAsRead({required String storeId, required String id}) async {
    if (markAsReadCompleter != null && !markAsReadCompleter!.isCompleted) {
      await markAsReadCompleter!.future;
    }
    markedReadIds.add(id);
    final idx = items.indexWhere((i) => i.id == id);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(isRead: true);
      emitCurrent();
    }
  }

  @override
  Future<void> markAllAsRead(String storeId) async {
    if (markAllAsReadCompleter != null &&
        !markAllAsReadCompleter!.isCompleted) {
      await markAllAsReadCompleter!.future;
    }
    if (shouldThrowOnMarkAllAsRead) {
      throw Exception('Simulated network error during markAllAsRead');
    }
    markAllAsReadCalls++;
    for (int i = 0; i < items.length; i++) {
      items[i] = items[i].copyWith(isRead: true);
    }
    emitCurrent();
  }

  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {
    if (shouldThrowOnDelete) {
      throw Exception('Simulated delete failure');
    }
    deletedIds.add(id);
    items.removeWhere((i) => i.id == id);
    emitCurrent();
  }
}

class _AdversarialOrderRepository implements OrderRepository {
  Completer<Order?>? fetchCompleter;
  Order? orderToReturn;
  int fetchCount = 0;

  @override
  Future<Order?> fetchById(String orderId) async {
    fetchCount++;
    if (fetchCompleter != null && !fetchCompleter!.isCompleted) {
      await fetchCompleter!.future;
    }
    return orderToReturn;
  }

  @override
  Future<void> create(Order order) async {}
  @override
  Future<void> update(Order order) async {}
  @override
  Future<void> delete(String orderId) async {}
  @override
  Stream<List<Order>> watchByCustomer(String customerId) => Stream.value([]);
  @override
  Stream<List<Order>> watchAll() => Stream.value([]);
  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) =>
      Stream.value([]);
}

class _AdversarialCustomerRepository implements CustomerRepository {
  Completer<Customer?>? fetchCompleter;
  Customer? customerToReturn;
  int fetchCount = 0;

  @override
  Future<Customer?> fetchById(String id) async {
    fetchCount++;
    if (fetchCompleter != null && !fetchCompleter!.isCompleted) {
      await fetchCompleter!.future;
    }
    return customerToReturn;
  }

  @override
  Stream<List<Customer>> watchAll() => Stream.value([]);
  @override
  Future<void> upsert(Customer customer) async {}
  @override
  Future<void> delete(String id) async {}
}

class _MockAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _MockAuthNotifier([super.state]);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

const adminUser = UserAccount(
  username: 'admin',
  displayName: 'Quản trị viên',
  role: 'admin',
  storeId: 'store_001',
);

Widget _buildApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: child,
    ),
  );
}

class _TestHost extends StatefulWidget {
  final Widget child;
  const _TestHost({super.key, required this.child});

  @override
  State<_TestHost> createState() => _TestHostState();
}

class _TestHostState extends State<_TestHost> {
  bool isChildMounted = true;

  void unmountChild() {
    setState(() {
      isChildMounted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!isChildMounted) return const SizedBox();
    return widget.child;
  }
}

// Helper to generate large mixed lists of notifications
List<NotificationItem> _generateMixedNotifications({
  int orderCount = 20,
  int inventoryCount = 20,
  int customerCount = 15,
  int systemCount = 5,
}) {
  final list = <NotificationItem>[];

  for (int i = 0; i < orderCount; i++) {
    list.add(NotificationItem(
      id: 'ord_$i',
      storeId: 'store_001',
      title: 'Đơn hàng mới #HD$i',
      body: 'Giá trị: ${(i + 1) * 100000}đ',
      type: i % 2 == 0
          ? NotificationType.orderCreated
          : NotificationType.orderUpdated,
      isRead: i % 3 == 0,
      createdAt: DateTime.now().subtract(Duration(minutes: i + 1)),
      targetRoute: 'invoice_detail',
      targetId: 'HD$i',
    ));
  }

  for (int i = 0; i < inventoryCount; i++) {
    list.add(NotificationItem(
      id: 'inv_$i',
      storeId: 'store_001',
      title: 'Nhập kho hoàn tất #NK$i',
      body: 'Mặt hàng $i đã về kho',
      type: NotificationType.inventoryImported,
      isRead: i % 2 == 0,
      createdAt: DateTime.now().subtract(Duration(hours: i + 1)),
      targetRoute: 'stock_in_detail',
      targetId: 'NK$i',
    ));
  }

  for (int i = 0; i < customerCount; i++) {
    list.add(NotificationItem(
      id: 'cust_$i',
      storeId: 'store_001',
      title: 'Khách hàng $i ghi nhận nợ',
      body: 'Công nợ mới: ${(i + 1) * 50000}đ',
      type: i % 2 == 0
          ? NotificationType.customerDebtAdded
          : NotificationType.customerCreated,
      isRead: false,
      createdAt: DateTime.now().subtract(Duration(minutes: (i + 1) * 2)),
      targetRoute: 'customer_debt',
      targetId: 'KH$i',
    ));
  }

  for (int i = 0; i < systemCount; i++) {
    list.add(NotificationItem(
      id: 'sys_$i',
      storeId: 'store_001',
      title: 'Thông báo hệ thống #$i',
      body: 'Bảo trì dữ liệu định kỳ $i',
      type: NotificationType.orderCancelled,
      isRead: true,
      createdAt: DateTime.now().subtract(Duration(days: i + 1)),
      targetRoute: null,
      targetId: null,
    ));
  }

  return list;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('=== M4 ADVERSARIAL CHALLENGE: NOTIFICATION CENTER INTERACTIONS ===', () {
    // ========================================================================
    // 1. FAST FILTER CYCLING UNDER LARGE MIXED NOTIFICATIONS
    // ========================================================================
    group('1. Fast Filter State Machine & Cycling Under Mixed Volume', () {
      testWidgets(
          'T1.1: Rapidly cycle ChoiceChips (All -> Orders -> Inventory -> Customers -> All) without race condition or item loss',
          (tester) async {
        final notifications = _generateMixedNotifications(
          orderCount: 20,
          inventoryCount: 15,
          customerCount: 10,
          systemCount: 5,
        );
        final totalCount = notifications.length; // 50 items
        final fakeRepo = _AdversarialNotificationRepository(notifications);

        late WidgetRef capturedRef;
        await tester.pumpWidget(
          _buildApp(
            child: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const NotificationsPage();
              },
            ),
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
            ],
          ),
        );
        fakeRepo.emitCurrent();
        await tester.pumpAndSettle();

        // 1. Initial State: All 50 items
        expect(capturedRef.read(notificationCategoryFilterProvider), isNull);
        expect(capturedRef.read(filteredNotificationsProvider).length,
            equals(totalCount));

        // 2. Switch to Orders (20 + 5 system cancel = 25 order-category items)
        final expectedOrders = notifications
            .where((n) => n.category == NotificationCategory.orders)
            .length;
        await tester.tap(find.byKey(const Key('notification_chip_orders')));
        await tester.pumpAndSettle();

        expect(capturedRef.read(notificationCategoryFilterProvider),
            equals(NotificationCategory.orders));
        expect(capturedRef.read(filteredNotificationsProvider).length,
            equals(expectedOrders));
        for (final item in capturedRef.read(filteredNotificationsProvider)) {
          expect(item.category, equals(NotificationCategory.orders));
        }

        // 3. Switch to Inventory (15 items)
        await tester.tap(find.byKey(const Key('notification_chip_inventory')));
        await tester.pumpAndSettle();

        expect(capturedRef.read(notificationCategoryFilterProvider),
            equals(NotificationCategory.inventory));
        expect(capturedRef.read(filteredNotificationsProvider).length,
            equals(15));
        for (final item in capturedRef.read(filteredNotificationsProvider)) {
          expect(item.category, equals(NotificationCategory.inventory));
        }

        // 4. Switch to Customers (10 items)
        await tester.tap(find.byKey(const Key('notification_chip_customers')));
        await tester.pumpAndSettle();

        expect(capturedRef.read(notificationCategoryFilterProvider),
            equals(NotificationCategory.customers));
        expect(capturedRef.read(filteredNotificationsProvider).length,
            equals(10));
        for (final item in capturedRef.read(filteredNotificationsProvider)) {
          expect(item.category, equals(NotificationCategory.customers));
        }

        // 5. Switch back to All
        await tester.tap(find.byKey(const Key('notification_chip_all')));
        await tester.pumpAndSettle();

        expect(capturedRef.read(notificationCategoryFilterProvider), isNull);
        expect(capturedRef.read(filteredNotificationsProvider).length,
            equals(totalCount));

        // Verify zero items dropped or duplicated
        final finalIds = capturedRef
            .read(filteredNotificationsProvider)
            .map((e) => e.id)
            .toSet();
        expect(finalIds.length, equals(totalCount));
      });

      testWidgets(
          'T1.2: Rapid multi-hop filter changes with no wait pumps between taps',
          (tester) async {
        final notifications = _generateMixedNotifications(
          orderCount: 15,
          inventoryCount: 15,
          customerCount: 15,
          systemCount: 0,
        );
        final fakeRepo = _AdversarialNotificationRepository(notifications);

        late WidgetRef capturedRef;
        await tester.pumpWidget(
          _buildApp(
            child: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const NotificationsPage();
              },
            ),
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
            ],
          ),
        );
        fakeRepo.emitCurrent();
        await tester.pumpAndSettle();

        // Rapid tap sequence in quick succession
        await tester.tap(find.byKey(const Key('notification_chip_orders')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('notification_chip_customers')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('notification_chip_inventory')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('notification_chip_all')));
        await tester.pumpAndSettle();

        expect(capturedRef.read(notificationCategoryFilterProvider), isNull);
        expect(capturedRef.read(filteredNotificationsProvider).length,
            equals(45));
      });

      testWidgets(
          'T1.3: Tapping already active ChoiceChip deselects it back to All (null)',
          (tester) async {
        final notifications = _generateMixedNotifications(
          orderCount: 10,
          inventoryCount: 10,
          customerCount: 10,
          systemCount: 0,
        );
        final fakeRepo = _AdversarialNotificationRepository(notifications);

        late WidgetRef capturedRef;
        await tester.pumpWidget(
          _buildApp(
            child: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const NotificationsPage();
              },
            ),
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
            ],
          ),
        );
        fakeRepo.emitCurrent();
        await tester.pumpAndSettle();

        // Select Orders
        await tester.tap(find.byKey(const Key('notification_chip_orders')));
        await tester.pumpAndSettle();
        expect(capturedRef.read(notificationCategoryFilterProvider),
            equals(NotificationCategory.orders));
        expect(capturedRef.read(filteredNotificationsProvider).length,
            equals(10));

        // Tap Orders AGAIN -> should deselect back to null / All
        await tester.tap(find.byKey(const Key('notification_chip_orders')));
        await tester.pumpAndSettle();
        expect(capturedRef.read(notificationCategoryFilterProvider), isNull);
        expect(capturedRef.read(filteredNotificationsProvider).length,
            equals(30));
      });

      testWidgets(
          'T1.4: Realtime stream insertion preserves active filter boundary',
          (tester) async {
        final notifications = _generateMixedNotifications(
          orderCount: 5,
          inventoryCount: 5,
          customerCount: 5,
          systemCount: 0,
        );
        final fakeRepo = _AdversarialNotificationRepository(notifications);

        late WidgetRef capturedRef;
        await tester.pumpWidget(
          _buildApp(
            child: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const NotificationsPage();
              },
            ),
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
            ],
          ),
        );
        fakeRepo.emitCurrent();
        await tester.pumpAndSettle();

        // Filter to Inventory
        await tester.tap(find.byKey(const Key('notification_chip_inventory')));
        await tester.pumpAndSettle();
        expect(capturedRef.read(filteredNotificationsProvider).length, equals(5));

        // Stream emits a new ORDER notification
        final newOrder = NotificationItem(
          id: 'new_ord_99',
          storeId: 'store_001',
          title: 'Đơn hàng mới #HD99',
          body: 'Giá trị: 990.000đ',
          type: NotificationType.orderCreated,
          isRead: false,
          createdAt: DateTime.now(),
        );
        await fakeRepo.addNotification(newOrder);
        await tester.pumpAndSettle();

        // Inventory view remains 5 (order is NOT leaked into inventory)
        expect(capturedRef.read(filteredNotificationsProvider).length, equals(5));

        // Switch to Orders -> now 6 orders
        await tester.tap(find.byKey(const Key('notification_chip_orders')));
        await tester.pumpAndSettle();
        expect(capturedRef.read(filteredNotificationsProvider).length, equals(6));
        expect(
          capturedRef
              .read(filteredNotificationsProvider)
              .any((n) => n.id == 'new_ord_99'),
          isTrue,
        );
      });
    });

    // ========================================================================
    // 2. SWIPE-TO-DELETE STRESS & RESTORATION
    // ========================================================================
    group('2. Swipe-to-Delete Stress & Undo Restoration', () {
      testWidgets(
          'T2.1: Dismiss item via DismissDirection.endToStart unmounts cleanly and updates repository',
          (tester) async {
        final notifications = [
          NotificationItem(
            id: 'swipe_1',
            storeId: 'store_001',
            title: 'Hóa đơn #HD101',
            body: 'Đã hoàn thành',
            type: NotificationType.orderCreated,
            isRead: false,
            createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
          ),
          NotificationItem(
            id: 'swipe_2',
            storeId: 'store_001',
            title: 'Nhập kho #NK102',
            body: 'Nhập thành công',
            type: NotificationType.inventoryImported,
            isRead: true,
            createdAt: DateTime.now().subtract(const Duration(hours: 1)),
          ),
        ];
        final fakeRepo = _AdversarialNotificationRepository(notifications);

        await tester.pumpWidget(
          _buildApp(
            child: const NotificationsPage(),
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
            ],
          ),
        );
        fakeRepo.emitCurrent();
        await tester.pumpAndSettle();

        expect(find.byType(NotificationCard), findsNWidgets(2));
        final dismissFinder = find.byKey(const Key('dismissible_swipe_1'));
        expect(dismissFinder, findsOneWidget);

        // Perform swipe left (endToStart)
        await tester.drag(dismissFinder, const Offset(-500, 0));
        await tester.pumpAndSettle();

        // 1. Card swipe_1 is unmounted
        expect(find.text('Hóa đơn #HD101'), findsNothing);
        expect(find.text('Nhập kho #NK102'), findsOneWidget);
        expect(find.byType(NotificationCard), findsOneWidget);

        // 2. Repository recorded deletion
        expect(fakeRepo.deletedIds, contains('swipe_1'));

        // 3. SnackBar shows delete message and Undo action
        expect(find.text('Đã xóa thông báo'), findsOneWidget);
        expect(find.text('Hoàn tác'), findsOneWidget);
      });

      testWidgets(
          'T2.2: Tapping Undo on SnackBar immediately restores item and calls addNotification',
          (tester) async {
        final originalItem = NotificationItem(
          id: 'swipe_restore',
          storeId: 'store_001',
          title: 'Hóa đơn #HD202',
          body: 'Đơn hàng giá trị 400.000đ',
          type: NotificationType.orderCreated,
          isRead: false,
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        final fakeRepo =
            _AdversarialNotificationRepository([originalItem]);

        await tester.pumpWidget(
          _buildApp(
            child: const NotificationsPage(),
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
            ],
          ),
        );
        fakeRepo.emitCurrent();
        await tester.pumpAndSettle();

        expect(find.text('Hóa đơn #HD202'), findsOneWidget);

        // Swipe dismiss
        await tester.drag(
            find.byKey(const Key('dismissible_swipe_restore')),
            const Offset(-500, 0));
        await tester.pumpAndSettle();

        // Verify empty state is reached when sole item is deleted
        expect(find.byKey(const Key('notification_empty_state')),
            findsOneWidget);
        expect(fakeRepo.deletedIds, contains('swipe_restore'));

        // Tap Undo on SnackBar
        final undoBtn = find.text('Hoàn tác');
        expect(undoBtn, findsOneWidget);
        await tester.tap(undoBtn);
        await tester.pumpAndSettle();

        // Item is restored into view and empty state unmounts cleanly
        expect(find.byKey(const Key('notification_empty_state')), findsNothing);
        expect(find.text('Hóa đơn #HD202'), findsOneWidget);
        expect(fakeRepo.addedItems.map((e) => e.id),
            contains('swipe_restore'));

        // Restored item unread dot preserved
        expect(find.byKey(const Key('notification_unread_dot')),
            findsOneWidget);
      });

      testWidgets(
          'T2.3: Restored item can be swiped-to-delete again without state collision',
          (tester) async {
        final item = NotificationItem(
          id: 'repeat_swipe',
          storeId: 'store_001',
          title: 'Khách hàng mới: Anh Bình',
          body: 'SĐT: 0912345678',
          type: NotificationType.customerCreated,
          isRead: false,
          createdAt: DateTime.now(),
        );
        final fakeRepo = _AdversarialNotificationRepository([item]);

        await tester.pumpWidget(
          _buildApp(
            child: const NotificationsPage(),
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
            ],
          ),
        );
        fakeRepo.emitCurrent();
        await tester.pumpAndSettle();

        // Swipe 1
        await tester.drag(
            find.byKey(const Key('dismissible_repeat_swipe')),
            const Offset(-500, 0));
        await tester.pumpAndSettle();
        expect(find.text('Khách hàng mới: Anh Bình'), findsNothing);

        // Undo 1
        await tester.tap(find.text('Hoàn tác'));
        await tester.pumpAndSettle();
        expect(find.text('Khách hàng mới: Anh Bình'), findsOneWidget);

        // Swipe 2 (same item re-swiped)
        await tester.drag(
            find.byKey(const Key('dismissible_repeat_swipe')),
            const Offset(-500, 0));
        await tester.pumpAndSettle();
        expect(find.text('Khách hàng mới: Anh Bình'), findsNothing);
        expect(fakeRepo.deletedIds.where((id) => id == 'repeat_swipe').length,
            equals(2));
      });

      testWidgets(
          'T2.4: Sequential multi-item swiping dismisses items without index offset collision',
          (tester) async {
        final items = [
          NotificationItem(
            id: 'multi_1',
            storeId: 'store_001',
            title: 'Item 1',
            body: 'Body 1',
            type: NotificationType.orderCreated,
            createdAt: DateTime.now(),
          ),
          NotificationItem(
            id: 'multi_2',
            storeId: 'store_001',
            title: 'Item 2',
            body: 'Body 2',
            type: NotificationType.orderCreated,
            createdAt: DateTime.now(),
          ),
          NotificationItem(
            id: 'multi_3',
            storeId: 'store_001',
            title: 'Item 3',
            body: 'Body 3',
            type: NotificationType.orderCreated,
            createdAt: DateTime.now(),
          ),
        ];
        final fakeRepo = _AdversarialNotificationRepository(items);

        await tester.pumpWidget(
          _buildApp(
            child: const NotificationsPage(),
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
            ],
          ),
        );
        fakeRepo.emitCurrent();
        await tester.pumpAndSettle();

        expect(find.byType(NotificationCard), findsNWidgets(3));

        // Dismiss multi_1
        await tester.drag(
            find.byKey(const Key('dismissible_multi_1')), const Offset(-500, 0));
        await tester.pumpAndSettle();
        expect(find.byType(NotificationCard), findsNWidgets(2));
        expect(find.text('Item 1'), findsNothing);

        // Dismiss multi_2
        await tester.drag(
            find.byKey(const Key('dismissible_multi_2')), const Offset(-500, 0));
        await tester.pumpAndSettle();
        expect(find.byType(NotificationCard), findsOneWidget);
        expect(find.text('Item 2'), findsNothing);
        expect(find.text('Item 3'), findsOneWidget);

        expect(fakeRepo.deletedIds, containsAll(['multi_1', 'multi_2']));
      });

      testWidgets(
          'T2.5: Repository deletion failure does not throw unhandled exception or crash UI',
          (tester) async {
        final item = NotificationItem(
          id: 'fail_item',
          storeId: 'store_001',
          title: 'Item to fail',
          body: 'Body',
          type: NotificationType.orderCreated,
          createdAt: DateTime.now(),
        );
        final fakeRepo = _AdversarialNotificationRepository([item]);
        fakeRepo.shouldThrowOnDelete = true;

        await tester.pumpWidget(
          _buildApp(
            child: const NotificationsPage(),
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
            ],
          ),
        );
        fakeRepo.emitCurrent();
        await tester.pumpAndSettle();

        // Dismiss will trigger error in repo
        await tester.drag(
            find.byKey(const Key('dismissible_fail_item')),
            const Offset(-500, 0));
        await tester.pumpAndSettle();

        // Verified: No uncaught exception crashed the app
        expect(tester.takeException(), isNull);
      });
    });

    // ========================================================================
    // 3. BATCH MARK-ALL-READ UNDER ASYNC DELAY
    // ========================================================================
    group('3. Batch Mark-All-Read Under Async Delay & Loading States', () {
      testWidgets(
          'T3.1: Progress indicator appears during async markAllAsRead, dismisses on completion, and unread dots vanish',
          (tester) async {
        final notifications = [
          NotificationItem(
            id: 'unread_1',
            storeId: 'store_001',
            title: 'Chưa đọc 1',
            body: 'Nội dung 1',
            type: NotificationType.orderCreated,
            isRead: false,
            createdAt: DateTime.now(),
          ),
          NotificationItem(
            id: 'unread_2',
            storeId: 'store_001',
            title: 'Chưa đọc 2',
            body: 'Nội dung 2',
            type: NotificationType.orderCreated,
            isRead: false,
            createdAt: DateTime.now(),
          ),
          NotificationItem(
            id: 'read_3',
            storeId: 'store_001',
            title: 'Đã đọc 3',
            body: 'Nội dung 3',
            type: NotificationType.orderCreated,
            isRead: true,
            createdAt: DateTime.now(),
          ),
        ];

        final fakeRepo = _AdversarialNotificationRepository(notifications);
        final markAllCompleter = Completer<void>();
        fakeRepo.markAllAsReadCompleter = markAllCompleter;

        late WidgetRef capturedRef;
        await tester.pumpWidget(
          _buildApp(
            child: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const NotificationsPage();
              },
            ),
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
            ],
          ),
        );
        fakeRepo.emitCurrent();
        await tester.pumpAndSettle();

        // Unread count is 2 initially
        expect(capturedRef.read(unreadNotificationCountProvider), equals(2));
        expect(find.byKey(const Key('notification_unread_dot')),
            findsNWidgets(2));

        // Locate and tap Mark All Read button
        final markAllButton =
            find.byKey(const Key('notifications_mark_all_read_button'));
        expect(markAllButton, findsOneWidget);

        await tester.tap(markAllButton);
        // Pump 1 frame to start async controller mutation
        await tester.pump();

        // 1. While mutating: CircularProgressIndicator is displayed in AppBar
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        // The Mark All Read TextButton is replaced/hidden while isMutating
        expect(
          find.byKey(const Key('notifications_mark_all_read_button')),
          findsNothing,
        );

        // 2. Complete the async operation
        markAllCompleter.complete();
        await tester.pumpAndSettle();

        // 3. Progress indicator dismisses
        expect(find.byType(CircularProgressIndicator), findsNothing);

        // 4. SnackBar confirmation shows
        expect(find.text('Đã đánh dấu tất cả thông báo là đã đọc'),
            findsOneWidget);

        // 5. Unread count becomes 0, and unread dots vanish
        expect(capturedRef.read(unreadNotificationCountProvider), equals(0));
        expect(find.byKey(const Key('notification_unread_dot')), findsNothing);
        expect(fakeRepo.markAllAsReadCalls, equals(1));

        // 6. Mark All Read button reappears in disabled state (unreadCount == 0)
        final restoredButton =
            find.byKey(const Key('notifications_mark_all_read_button'));
        expect(restoredButton, findsOneWidget);
        final textButtonWidget =
            tester.widget<TextButton>(restoredButton);
        expect(textButtonWidget.onPressed, isNull);
      });

      testWidgets(
          'T3.2: Tapping Mark All Read when unreadCount == 0 does nothing (disabled button)',
          (tester) async {
        final notifications = [
          NotificationItem(
            id: 'read_only_1',
            storeId: 'store_001',
            title: 'Đã đọc 1',
            body: 'Nội dung',
            type: NotificationType.inventoryImported,
            isRead: true,
            createdAt: DateTime.now(),
          ),
        ];

        final fakeRepo = _AdversarialNotificationRepository(notifications);

        await tester.pumpWidget(
          _buildApp(
            child: const NotificationsPage(),
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
            ],
          ),
        );
        fakeRepo.emitCurrent();
        await tester.pumpAndSettle();

        final markAllButton =
            find.byKey(const Key('notifications_mark_all_read_button'));
        expect(markAllButton, findsOneWidget);
        final textButton = tester.widget<TextButton>(markAllButton);
        expect(textButton.onPressed, isNull);

        // Attempt tap
        await tester.tap(markAllButton);
        await tester.pumpAndSettle();

        // Zero repository calls
        expect(fakeRepo.markAllAsReadCalls, equals(0));
      });

      testWidgets(
          'T3.3: Mark All Read error recovery does not break UI and dismisses spinner',
          (tester) async {
        final notifications = [
          NotificationItem(
            id: 'unread_err',
            storeId: 'store_001',
            title: 'Đơn hàng lỗi',
            body: 'Nội dung',
            type: NotificationType.orderCreated,
            isRead: false,
            createdAt: DateTime.now(),
          ),
        ];

        final fakeRepo = _AdversarialNotificationRepository(notifications);
        fakeRepo.shouldThrowOnMarkAllAsRead = true;

        await tester.pumpWidget(
          _buildApp(
            child: const NotificationsPage(),
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
            ],
          ),
        );
        fakeRepo.emitCurrent();
        await tester.pumpAndSettle();

        await tester.tap(
            find.byKey(const Key('notifications_mark_all_read_button')));
        await tester.pumpAndSettle();

        // Verified: Spinner dismissed and no crash
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    // ========================================================================
    // 4. CONTEXT-SAFE DEEP LINKING UNDER UNMOUNTING
    // ========================================================================
    group('4. Context-Safe Deep Linking Under Unmounting Navigation Context', () {
      testWidgets(
          'T4.1: Unmounting NotificationsPage while markAsRead is pending terminates cleanly without errors',
          (tester) async {
        final orderNotif = NotificationItem(
          id: 'order_unmount_1',
          storeId: 'store_001',
          title: 'Đơn hàng #HD888',
          body: 'Nội dung',
          type: NotificationType.orderCreated,
          isRead: false,
          createdAt: DateTime.now(),
          targetRoute: 'invoice_detail',
          targetId: 'HD888',
        );

        final fakeRepo = _AdversarialNotificationRepository([orderNotif]);
        final markAsReadCompleter = Completer<void>();
        fakeRepo.markAsReadCompleter = markAsReadCompleter;

        final fakeOrderRepo = _AdversarialOrderRepository();

        final hostKey = GlobalKey<_TestHostState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
              orderRepositoryProvider.overrideWith((ref) => fakeOrderRepo),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('vi'),
              home: _TestHost(
                key: hostKey,
                child: const NotificationsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Đơn hàng #HD888'), findsOneWidget);

        // Tap notification card: triggers markAsRead (async pause on Completer)
        await tester.tap(find.text('Đơn hàng #HD888'));
        await tester.pump();

        // While markAsRead is pending, unmount NotificationsPage
        hostKey.currentState!.unmountChild();
        await tester.pump();

        // Verify NotificationsPage is now unmounted
        expect(find.byType(NotificationsPage), findsNothing);

        // Complete the pending markAsRead
        markAsReadCompleter.complete();
        await tester.pumpAndSettle();

        // Context check: `if (!context.mounted) return;` caught this.
        // Zero exceptions thrown, and order fetch never attempted on dead context.
        expect(tester.takeException(), isNull);
        expect(fakeOrderRepo.fetchCount, equals(0));
      });

      testWidgets(
          'T4.2: Unmounting while orderRepo.fetchById is pending safely aborts modal sheet presentation',
          (tester) async {
        final orderNotif = NotificationItem(
          id: 'order_unmount_2',
          storeId: 'store_001',
          title: 'Đơn hàng #HD999',
          body: 'Nội dung',
          type: NotificationType.orderCreated,
          isRead: true, // Already read, skips markAsRead delay
          createdAt: DateTime.now(),
          targetRoute: 'invoice_detail',
          targetId: 'HD999',
        );

        final fakeRepo = _AdversarialNotificationRepository([orderNotif]);
        final fakeOrderRepo = _AdversarialOrderRepository();
        final fetchCompleter = Completer<Order?>();
        fakeOrderRepo.fetchCompleter = fetchCompleter;
        fakeOrderRepo.orderToReturn = Order(
          id: 'HD999',
          customerId: 'KH01',
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: 'P1',
              productName: 'Món 1',
              price: 100000,
              quantity: 1,
              warrantyMonths: 12,
              purchaseDate: DateTime(2026, 1, 1),
            ),
          ],
          total: 100000,
        );

        final hostKey = GlobalKey<_TestHostState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
              orderRepositoryProvider.overrideWith((ref) => fakeOrderRepo),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('vi'),
              home: _TestHost(
                key: hostKey,
                child: const NotificationsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap order card -> fetchById begins and pauses on fetchCompleter
        await tester.tap(find.text('Đơn hàng #HD999'));
        await tester.pump();
        expect(fakeOrderRepo.fetchCount, equals(1));

        // Unmount NotificationsPage while awaiting fetchById
        hostKey.currentState!.unmountChild();
        await tester.pump();
        expect(find.byType(NotificationsPage), findsNothing);

        // Now complete the order fetch
        fetchCompleter.complete(fakeOrderRepo.orderToReturn);
        await tester.pumpAndSettle();

        // Verify: `if (!context.mounted) return;` prevented sheet presentation on unmounted context
        expect(tester.takeException(), isNull);
        // Modal sheet should not be mounted on root
        expect(find.text('Chi tiết hóa đơn'), findsNothing);
      });

      testWidgets(
          'T4.3: Unmounting while customerRepo.fetchById is pending safely aborts route push',
          (tester) async {
        final custNotif = NotificationItem(
          id: 'cust_unmount_3',
          storeId: 'store_001',
          title: 'Khách hàng nợ #KH555',
          body: 'Nợ mới',
          type: NotificationType.customerDebtAdded,
          isRead: true,
          createdAt: DateTime.now(),
          targetRoute: 'customer_debt',
          targetId: 'KH555',
        );

        final fakeRepo = _AdversarialNotificationRepository([custNotif]);
        final fakeCustRepo = _AdversarialCustomerRepository();
        final custFetchCompleter = Completer<Customer?>();
        fakeCustRepo.fetchCompleter = custFetchCompleter;
        fakeCustRepo.customerToReturn = const Customer(
          id: 'KH555',
          name: 'Khách Test',
          phone: '0901234567',
          email: '',
          address: '',
          purchases: [],
        );

        final hostKey = GlobalKey<_TestHostState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith((ref) => _MockAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              notificationRepositoryProvider.overrideWith((ref) => fakeRepo),
              customerRepositoryProvider.overrideWith((ref) => fakeCustRepo),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('vi'),
              home: _TestHost(
                key: hostKey,
                child: const NotificationsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap customer debt card -> customer fetch pauses
        await tester.tap(find.text('Khách hàng nợ #KH555'));
        await tester.pump();
        expect(fakeCustRepo.fetchCount, equals(1));

        // Pop NotificationsPage mid-flight
        hostKey.currentState!.unmountChild();
        await tester.pump();
        expect(find.byType(NotificationsPage), findsNothing);

        // Complete customer fetch
        custFetchCompleter.complete(fakeCustRepo.customerToReturn);
        await tester.pumpAndSettle();

        // Verify: No navigation occurred on dead context and no unhandled exceptions
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'T4.4: Directly calling NotificationNavigationHandler with deactivated context exits immediately',
          (tester) async {
        late BuildContext savedContext;
        late WidgetRef savedRef;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  savedContext = context;
                  savedRef = ref;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Replace tree so savedContext is now unmounted/deactivated
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        expect(savedContext.mounted, isFalse);

        final dummyNotif = NotificationItem(
          id: 'deactivated_test',
          storeId: 'store_001',
          title: 'Title',
          body: 'Body',
          type: NotificationType.orderCreated,
          isRead: false,
          createdAt: DateTime.now(),
          targetRoute: 'invoice_detail',
          targetId: 'HD999',
        );

        // Calling handleTap with deactivated context must not throw
        await NotificationNavigationHandler.handleTap(
          context: savedContext,
          ref: savedRef,
          notification: dummyNotif,
        );

        expect(tester.takeException(), isNull);
      });
    });
  });
}
