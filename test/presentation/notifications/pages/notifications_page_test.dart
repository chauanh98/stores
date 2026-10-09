import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/notifications/pages/notifications_page.dart';
import 'package:stores/presentation/notifications/widgets/notification_card.dart';

class _FakeNotificationRepository implements NotificationRepository {
  final List<NotificationItem> items;
  final List<String> markedReadIds = [];
  final List<String> deletedIds = [];
  int markAllAsReadCalls = 0;
  final StreamController<List<NotificationItem>> _controller =
      StreamController<List<NotificationItem>>.broadcast();

  _FakeNotificationRepository(this.items);

  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
      {int limit = 50}) {
    return _controller.stream;
  }

  void emitCurrent() {
    _controller.add(List.unmodifiable(items));
  }

  @override
  Future<void> addNotification(NotificationItem notification) async {
    items.insert(0, notification);
    emitCurrent();
  }

  @override
  Future<void> markAsRead({required String storeId, required String id}) async {
    markedReadIds.add(id);
    final idx = items.indexWhere((i) => i.id == id);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(isRead: true);
      emitCurrent();
    }
  }

  @override
  Future<void> markAllAsRead(String storeId) async {
    markAllAsReadCalls++;
    for (int i = 0; i < items.length; i++) {
      items[i] = items[i].copyWith(isRead: true);
    }
    emitCurrent();
  }

  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {
    deletedIds.add(id);
    items.removeWhere((i) => i.id == id);
    emitCurrent();
  }
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

Widget _buildTestApp({
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  final sampleOrderNotif = NotificationItem(
    id: 'n_ord_1',
    storeId: 'store_001',
    title: 'Đơn hàng mới #HD001',
    body: 'Đơn hàng trị giá 500.000đ cho khách A',
    type: NotificationType.orderCreated,
    isRead: false,
    createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
    targetRoute: 'invoice_detail',
    targetId: 'HD001',
  );

  final sampleInventoryNotif = NotificationItem(
    id: 'n_inv_1',
    storeId: 'store_001',
    title: 'Nhập kho hoàn tất #NK001',
    body: 'Nhập từ NCC B • 1.200.000đ',
    type: NotificationType.inventoryImported,
    isRead: true,
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    targetRoute: 'stock_in_detail',
    targetId: 'NK001',
  );

  final sampleCustomerNotif = NotificationItem(
    id: 'n_cust_1',
    storeId: 'store_001',
    title: 'Khách hàng mới: Chị Lan',
    body: 'Mã: KH001 • SĐT: 0901234567',
    type: NotificationType.customerCreated,
    isRead: false,
    createdAt: DateTime.now().subtract(const Duration(seconds: 30)),
    targetRoute: 'customer_detail',
    targetId: 'KH001',
  );

  testWidgets('NotificationsPage renders empty state when no notifications',
      (tester) async {
    final fakeRepo = _FakeNotificationRepository([]);

    await tester.pumpWidget(
      _buildTestApp(
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

    expect(find.byKey(const Key('notification_empty_state')), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none_outlined), findsOneWidget);
    expect(find.text('Không có thông báo nào'), findsOneWidget);
  });

  testWidgets(
      'NotificationsPage displays list of cards with relative time and category icons',
      (tester) async {
    final fakeRepo = _FakeNotificationRepository([
      sampleOrderNotif,
      sampleInventoryNotif,
      sampleCustomerNotif,
    ]);

    await tester.pumpWidget(
      _buildTestApp(
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

    // All 3 cards visible
    expect(find.byType(NotificationCard), findsNWidgets(3));
    expect(find.text('Đơn hàng mới #HD001'), findsOneWidget);
    expect(find.text('Nhập kho hoàn tất #NK001'), findsOneWidget);
    expect(find.text('Khách hàng mới: Chị Lan'), findsOneWidget);

    // Unread dots: 2 items are unread (sampleOrderNotif and sampleCustomerNotif)
    expect(find.byKey(const Key('notification_unread_dot')), findsNWidgets(2));
  });

  testWidgets('Category filter chips filter items correctly', (tester) async {
    final fakeRepo = _FakeNotificationRepository([
      sampleOrderNotif,
      sampleInventoryNotif,
      sampleCustomerNotif,
    ]);

    await tester.pumpWidget(
      _buildTestApp(
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

    // Tap Orders Chip
    await tester.tap(find.byKey(const Key('notification_chip_orders')));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationCard), findsOneWidget);
    expect(find.text('Đơn hàng mới #HD001'), findsOneWidget);

    // Tap Inventory Chip
    await tester.tap(find.byKey(const Key('notification_chip_inventory')));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationCard), findsOneWidget);
    expect(find.text('Nhập kho hoàn tất #NK001'), findsOneWidget);

    // Tap Customers Chip
    await tester.tap(find.byKey(const Key('notification_chip_customers')));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationCard), findsOneWidget);
    expect(find.text('Khách hàng mới: Chị Lan'), findsOneWidget);

    // Tap All Chip restores all 3
    await tester.tap(find.byKey(const Key('notification_chip_all')));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationCard), findsNWidgets(3));
  });

  testWidgets('Mark all as read button updates all items to read',
      (tester) async {
    final fakeRepo = _FakeNotificationRepository([
      sampleOrderNotif,
      sampleCustomerNotif,
    ]);

    await tester.pumpWidget(
      _buildTestApp(
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

    final markAllBtn =
        find.byKey(const Key('notifications_mark_all_read_button'));
    expect(markAllBtn, findsOneWidget);

    await tester.tap(markAllBtn);
    await tester.pumpAndSettle();

    expect(fakeRepo.markAllAsReadCalls, equals(1));
    // After marking all as read, unread dots disappear
    expect(find.byKey(const Key('notification_unread_dot')), findsNothing);
  });

  testWidgets('Swipe-to-delete dismisses notification and undo restores it',
      (tester) async {
    final fakeRepo = _FakeNotificationRepository([
      sampleOrderNotif,
      sampleInventoryNotif,
    ]);

    await tester.pumpWidget(
      _buildTestApp(
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

    // Swipe dismiss first item to the left (endToStart)
    final dismissibleFinder =
        find.byKey(Key('dismissible_${sampleOrderNotif.id}'));
    expect(dismissibleFinder, findsOneWidget);

    await tester.drag(dismissibleFinder, const Offset(-500, 0));
    await tester.pumpAndSettle();

    // Verify deleted
    expect(find.text('Đơn hàng mới #HD001'), findsNothing);
    expect(find.text('Đã xóa thông báo'), findsOneWidget);
    expect(find.text('Hoàn tác'), findsOneWidget);
    expect(fakeRepo.deletedIds, contains('n_ord_1'));

    // Tap Undo
    await tester.tap(find.text('Hoàn tác'));
    await tester.pumpAndSettle();

    // Restored back into view
    expect(find.text('Đơn hàng mới #HD001'), findsOneWidget);
  });
}
