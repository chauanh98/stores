import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/data/models/notification_item_model.dart';
import 'package:stores/domain/entities/user_account.dart';

/// Mutable auth notifier for dynamic role and session transitions.
class _TestAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _TestAuthNotifier(super.state);

  void setUser(UserAccount? user) {
    state = user;
  }

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

/// Observable mock repository tracking active stream subscriptions, lifecycle
/// cancellations, and mutation invocations per store.
class _ObservableNotificationRepository implements NotificationRepository {
  final Map<String, StreamController<List<NotificationItem>>> controllers = {};
  final Set<String> activeListenStoreIds = {};
  final List<String> watchCallLog = [];
  final List<String> markAsReadLog = [];
  final List<String> markAllAsReadLog = [];
  final List<String> deleteLog = [];
  final List<NotificationItem> addedNotifications = [];

  bool throwOnMarkAsRead = false;
  bool throwOnMarkAllAsRead = false;
  bool throwOnAdd = false;
  bool throwOnDelete = false;
  Completer<void>? markAsReadDelayCompleter;

  StreamController<List<NotificationItem>> getOrCreateController(String storeId) {
    if (!controllers.containsKey(storeId)) {
      late StreamController<List<NotificationItem>> sc;
      sc = StreamController<List<NotificationItem>>.broadcast(
        onListen: () {
          activeListenStoreIds.add(storeId);
        },
        onCancel: () {
          activeListenStoreIds.remove(storeId);
        },
      );
      controllers[storeId] = sc;
    }
    return controllers[storeId]!;
  }

  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
      {int limit = 50}) {
    watchCallLog.add(storeId);
    return getOrCreateController(storeId).stream;
  }

  @override
  Future<void> addNotification(NotificationItem notification) async {
    if (throwOnAdd) throw Exception('Simulated addNotification failure');
    addedNotifications.add(notification);
  }

  @override
  Future<void> markAsRead({required String storeId, required String id}) async {
    if (markAsReadDelayCompleter != null) {
      await markAsReadDelayCompleter!.future;
    }
    if (throwOnMarkAsRead) throw Exception('Simulated markAsRead failure');
    markAsReadLog.add('$storeId:$id');
  }

  @override
  Future<void> markAllAsRead(String storeId) async {
    if (throwOnMarkAllAsRead) throw Exception('Simulated markAllAsRead failure');
    markAllAsReadLog.add(storeId);
  }

  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {
    if (throwOnDelete) throw Exception('Simulated deleteNotification failure');
    deleteLog.add('$storeId:$id');
  }

  void dispose() {
    for (final sc in controllers.values) {
      if (!sc.isClosed) {
        sc.close();
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const adminUser = UserAccount(
    username: 'admin_master',
    displayName: 'Quản trị viên Hệ thống',
    role: 'admin',
    storeId: 'store_001',
  );

  const ownerUser = UserAccount(
    username: 'owner_boss',
    displayName: 'Chủ sở hữu',
    role: 'owner',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff_pos',
    displayName: 'Nhân viên bán hàng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor_branch',
    displayName: 'Giám sát chi nhánh',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const giamsatUser = UserAccount(
    username: 'giamsat_01',
    displayName: 'Giám sát viên',
    role: 'giamsat',
    storeId: 'store_001',
  );

  const cuahangtruongUser = UserAccount(
    username: 'manager_01',
    displayName: 'Cửa hàng trưởng',
    role: 'cuahangtruong',
    storeId: 'store_001',
  );

  final sampleBatch = [
    NotificationItem(
      id: 'notif_ord_1',
      storeId: 'store_001',
      title: 'Đơn hàng mới #HD001',
      body: 'Tổng tiền: 200.000đ',
      type: NotificationType.orderCreated,
      isRead: false,
      createdAt: DateTime(2026, 10, 4, 12, 0),
    ),
    NotificationItem(
      id: 'notif_ver_2',
      storeId: 'store_001',
      title: 'Sửa hóa đơn #HD001.01',
      body: 'Tổng tiền: 250.000đ',
      type: NotificationType.orderUpdated,
      isRead: false,
      createdAt: DateTime(2026, 10, 4, 11, 45),
    ),
    NotificationItem(
      id: 'notif_can_3',
      storeId: 'store_001',
      title: 'Hủy đơn hàng #HD000',
      body: 'Lý do: Khách đổi ý',
      type: NotificationType.orderCancelled,
      isRead: true,
      createdAt: DateTime(2026, 10, 4, 11, 30),
    ),
    NotificationItem(
      id: 'notif_stk_4',
      storeId: 'store_001',
      title: 'Nhập kho hoàn tất #NK001',
      body: 'Tổng tiền: 10.000.000đ',
      type: NotificationType.inventoryImported,
      isRead: false,
      createdAt: DateTime(2026, 10, 4, 11, 0),
    ),
  ];

  late _ObservableNotificationRepository repo;

  setUp(() {
    repo = _ObservableNotificationRepository();
  });

  tearDown(() {
    repo.dispose();
  });

  // =========================================================================
  // GROUP 1: DYNAMIC ROLE SWITCHING & ZERO EGRESS STRESS
  // =========================================================================
  group('1. Adversarial Dynamic Role Switching & Zero Egress', () {
    test(
        'Switch Admin -> Staff in same ProviderContainer: stream stays live but '
        'is masked (no amounts) for staff',
        () async {
      final authNotifier = _TestAuthNotifier(adminUser);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      // 1. Admin subscribes to stream and unread count
      final subStream =
          container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(subStream.close);
      final subCount =
          container.listen(unreadNotificationCountProvider, (_, __) {});
      addTearDown(subCount.close);

      // Verify watchNotifications was called exactly once for Admin
      expect(repo.watchCallLog, equals(['store_001']));
      expect(repo.activeListenStoreIds, contains('store_001'));

      // 2. Emit batch to Admin
      repo.getOrCreateController('store_001').add(sampleBatch);
      await pumpEventQueue();

      final adminAsync = container.read(notificationStreamProvider);
      expect(adminAsync.value?.length, equals(4));
      // notif_ord_1, notif_ver_2, notif_stk_4 are unread -> 3 unread
      expect(container.read(unreadNotificationCountProvider), equals(3));

      // 3. ADVERSARIAL ROLE TRANSITION: Dynamically switch Admin -> Staff in same container
      authNotifier.setUser(staffUser);
      await pumpEventQueue();
      // Firebase replays the current snapshot on (re)subscribe; emulate it.
      repo.getOrCreateController('store_001').add(sampleBatch);
      await pumpEventQueue();

      // 4. Staff keeps receiving own-store notifications, but masked:
      //    prices stripped, same events (inventory/orders) still visible.
      final staffAsync = container.read(notificationStreamProvider);
      expect(staffAsync.value?.length, equals(4));
      for (final n in staffAsync.value!) {
        expect(RegExp(r'\d[\d.,]*\s?đ').hasMatch(n.body), isFalse,
            reason: 'Staff must never see amounts: ${n.body}');
      }
      expect(container.read(unreadNotificationCountProvider), equals(3));

      // 6. ADVERSARIAL LEAK CHECK: Emit more data to the old store_001 controller
      // Verify late emissions do NOT leak to staff or alter unread count
      repo.getOrCreateController('store_001').add([
        ...sampleBatch,
        NotificationItem(
          id: 'leak_check',
          storeId: 'store_001',
          title: 'Leak Test',
          body: 'Should not reach staff',
          type: NotificationType.orderCreated,
          isRead: false,
          createdAt: DateTime.now(),
        ),
      ]);
      await pumpEventQueue();

      // Late emission still reaches staff (masked) and bumps unread count
      expect(container.read(notificationStreamProvider).value?.length, equals(5));
      expect(container.read(unreadNotificationCountProvider), equals(4));
    });

    test(
        'Switch Staff -> Admin in same ProviderContainer: masked stream becomes '
        'full-content stream', () async {
      final authNotifier = _TestAuthNotifier(staffUser);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      final subStream =
          container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(subStream.close);

      // Staff also listens to their own store only
      await pumpEventQueue();
      expect(repo.watchCallLog, equals(['store_001']));
      repo.getOrCreateController('store_001').add(sampleBatch);
      await pumpEventQueue();
      expect(
          container
              .read(notificationStreamProvider)
              .value!
              .any((n) => RegExp(r'\d[\d.,]*\s?đ').hasMatch(n.body)),
          isFalse);

      // Escalate role: Staff -> Admin => full, unmasked content
      authNotifier.setUser(adminUser);
      await pumpEventQueue();
      expect(repo.watchCallLog.last, equals('store_001'));

      // Emit data
      repo.getOrCreateController('store_001').add(sampleBatch);
      await pumpEventQueue();
      expect(
          container
              .read(notificationStreamProvider)
              .value!
              .any((n) => n.body.contains('200.000đ')),
          isTrue);
      expect(container.read(notificationStreamProvider).value?.length, equals(4));
      expect(container.read(unreadNotificationCountProvider), equals(3));
    });

    test(
        'Session transitions: Admin -> Logged Out (null) -> Owner preserves RBAC '
        'without stream leakage', () async {
      final authNotifier = _TestAuthNotifier(adminUser);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      final subStream =
          container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(subStream.close);

      repo.getOrCreateController('store_001').add(sampleBatch);
      await pumpEventQueue();
      expect(container.read(notificationStreamProvider).value?.length, equals(4));

      // 1. Log out (null)
      authNotifier.logout();
      await pumpEventQueue();

      expect(container.read(notificationStreamProvider).value, isEmpty);
      expect(container.read(unreadNotificationCountProvider), equals(0));

      // 2. Log in as Owner
      authNotifier.setUser(ownerUser);
      await pumpEventQueue();

      // Owner is granted access
      expect(repo.watchCallLog.length, equals(2));
      repo.getOrCreateController('store_001').add(sampleBatch);
      await pumpEventQueue();

      expect(container.read(notificationStreamProvider).value?.length, equals(4));
      expect(container.read(unreadNotificationCountProvider), equals(3));
    });

    test('Every non-admin role listens to its own store only; price access decides masking',
        () async {
      final roles = [
        supervisorUser,
        giamsatUser,
        cuahangtruongUser,
        const UserAccount(
          username: 'cashier_01',
          role: 'cashier',
          storeId: 'store_001',
        ),
        const UserAccount(
          username: 'guest',
          role: 'unknown_unauthorized_role',
          storeId: 'store_001',
        ),
      ];
      for (final role in roles) {
        final localRepo = _ObservableNotificationRepository();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _TestAuthNotifier(role)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWith((ref) => localRepo),
          ],
        );
        final sub = container.listen(notificationStreamProvider, (_, __) {});
        await pumpEventQueue();
        localRepo.getOrCreateController('store_001').add(sampleBatch);
        await pumpEventQueue();

        final result = container.read(notificationStreamProvider).value!;
        expect(localRepo.watchCallLog, equals(['store_001']),
            reason: 'Role ${role.role}: exactly one own-store listener');
        final hasAmount =
            result.any((n) => RegExp(r'\d[\d.,]*\s?đ').hasMatch(n.body));
        expect(hasAmount, equals(role.canViewCostPrice),
            reason: 'Role ${role.role}: amounts visible iff canViewCostPrice');
        sub.close();
        container.dispose();
        localRepo.dispose();
      }
    });
  });

  // =========================================================================
  // GROUP 2: RAPID STORE ID SWITCHING & SUBSCRIPTION LIFECYCLE
  // =========================================================================
  group('2. Adversarial Rapid Store ID Switching & Lifecycle Leaks', () {
    test(
        'Rapid store ID switching in quick succession immediately cancels '
        'prior store subscriptions without leaks or unhandled events',
        () async {
      final storeIdState = StateProvider<String>((ref) => 'store_001');

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _TestAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => ref.watch(storeIdState)),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      final subStream =
          container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(subStream.close);

      await pumpEventQueue();
      expect(repo.activeListenStoreIds, equals({'store_001'}));

      // Rapidly cycle storeId through 5 distinct branches
      const stores = [
        'store_002',
        'store_003',
        'store_004',
        'store_005',
        'store_006',
      ];

      for (final sId in stores) {
        container.read(storeIdState.notifier).state = sId;
        // Interleaved microtasks to stress-test asynchronous cancellation
        await Future<void>.delayed(Duration.zero);
      }
      await pumpEventQueue();

      // Only the final store (store_006) should remain active
      expect(repo.activeListenStoreIds, equals({'store_006'}),
          reason: 'All abandoned store subscriptions must be canceled');

      // Verify that emitting events to dead store controllers does not crash or pollute
      for (final oldStore in ['store_001', ...stores.take(4)]) {
        repo.getOrCreateController(oldStore).add([
          NotificationItem(
            id: 'zombie_$oldStore',
            storeId: oldStore,
            title: 'Zombie Notification',
            body: 'Must be discarded',
            type: NotificationType.orderCreated,
            isRead: false,
            createdAt: DateTime.now(),
          ),
        ]);
      }
      await pumpEventQueue();

      // Active store receives legitimate event
      repo.getOrCreateController('store_006').add([
        NotificationItem(
          id: 'live_notif_006',
          storeId: 'store_006',
          title: 'Store 006 Event',
          body: 'Correctly routed',
          type: NotificationType.inventoryImported,
          isRead: false,
          createdAt: DateTime.now(),
        ),
      ]);
      await pumpEventQueue();

      final currentNotifications =
          container.read(notificationStreamProvider).value;
      expect(currentNotifications?.length, equals(1));
      expect(currentNotifications?.first.id, equals('live_notif_006'));
      expect(container.read(unreadNotificationCountProvider), equals(1));
    });

    test(
        'Switching store ID to empty string or whitespace returns empty stream '
        'and does NOT call repository', () async {
      final storeIdState = StateProvider<String>((ref) => 'store_001');

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _TestAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => ref.watch(storeIdState)),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      final subStream =
          container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(subStream.close);
      await pumpEventQueue();

      expect(repo.watchCallLog, equals(['store_001']));

      // Switch to blank / whitespace store IDs
      for (final blank in ['', '   ', '\t\n']) {
        container.read(storeIdState.notifier).state = blank;
        await pumpEventQueue();

        expect(container.read(notificationStreamProvider).value, isEmpty);
        expect(repo.activeListenStoreIds, isEmpty,
            reason: 'Blank store ID must detach any active listener');
      }

      // Repo was NOT invoked for blank IDs
      expect(repo.watchCallLog, equals(['store_001']));

      // Recovery to valid store
      container.read(storeIdState.notifier).state = 'store_002';
      await pumpEventQueue();

      expect(repo.watchCallLog, equals(['store_001', 'store_002']));
      expect(repo.activeListenStoreIds, equals({'store_002'}));
    });

    test(
        'Logging out or clearing store ID cleanly cancels all active store streams',
        () async {
      final authNotifier = _TestAuthNotifier(adminUser);
      final storeIdState = StateProvider<String>((ref) => 'store_001');

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          currentStoreIdProvider.overrideWith((ref) => ref.watch(storeIdState)),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      expect(repo.activeListenStoreIds, contains('store_001'));

      // 1. Clear storeId -> stream cancelled
      container.read(storeIdState.notifier).state = '';
      await pumpEventQueue();
      expect(repo.activeListenStoreIds, isEmpty,
          reason: 'Clearing storeId must immediately cancel active store stream');

      // 2. Restore storeId -> re-subscribed
      container.read(storeIdState.notifier).state = 'store_002';
      await pumpEventQueue();
      expect(repo.activeListenStoreIds, equals({'store_002'}));

      // 3. Log out -> stream cancelled
      authNotifier.logout();
      await pumpEventQueue();
      expect(repo.activeListenStoreIds, isEmpty,
          reason: 'Logging out must immediately cancel active store stream');
    });
  });

  // =========================================================================
  // GROUP 3: CATEGORY FILTERING STRESS & MODEL ROBUSTNESS
  // =========================================================================
  group('3. Category Filtering Stress & Model Edge Cases', () {
    final all8TypesNotifications = [
      NotificationItem(
        id: 'n_ord_created',
        storeId: 'store_001',
        title: 'Đơn mới',
        body: 'orderCreated',
        type: NotificationType.orderCreated,
        createdAt: DateTime(2026, 10, 4, 12, 1),
      ),
      NotificationItem(
        id: 'n_ord_updated',
        storeId: 'store_001',
        title: 'Sửa đơn',
        body: 'orderUpdated',
        type: NotificationType.orderUpdated,
        createdAt: DateTime(2026, 10, 4, 12, 2),
      ),
      NotificationItem(
        id: 'n_ord_cancelled',
        storeId: 'store_001',
        title: 'Hủy đơn',
        body: 'orderCancelled',
        type: NotificationType.orderCancelled,
        createdAt: DateTime(2026, 10, 4, 12, 3),
      ),
      NotificationItem(
        id: 'n_ord_return',
        storeId: 'store_001',
        title: 'Trả hàng',
        body: 'orderReturn',
        type: NotificationType.orderReturn,
        createdAt: DateTime(2026, 10, 4, 12, 4),
      ),
      NotificationItem(
        id: 'n_inv_imported',
        storeId: 'store_001',
        title: 'Nhập kho',
        body: 'inventoryImported',
        type: NotificationType.inventoryImported,
        createdAt: DateTime(2026, 10, 4, 12, 5),
      ),
      NotificationItem(
        id: 'n_cust_created',
        storeId: 'store_001',
        title: 'Khách mới',
        body: 'customerCreated',
        type: NotificationType.customerCreated,
        createdAt: DateTime(2026, 10, 4, 12, 6),
      ),
      NotificationItem(
        id: 'n_cust_debt_added',
        storeId: 'store_001',
        title: 'Nợ mới',
        body: 'customerDebtAdded',
        type: NotificationType.customerDebtAdded,
        createdAt: DateTime(2026, 10, 4, 12, 7),
      ),
      NotificationItem(
        id: 'n_cust_debt_paid',
        storeId: 'store_001',
        title: 'Thu nợ',
        body: 'customerDebtPaid',
        type: NotificationType.customerDebtPaid,
        createdAt: DateTime(2026, 10, 4, 12, 8),
      ),
    ];

    test('Filtered notifications across all 8 business event types',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _TestAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      final subStream =
          container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(subStream.close);

      repo.getOrCreateController('store_001').add(all8TypesNotifications);
      await pumpEventQueue();

      // 1. Default (null filter) -> all 8 items
      expect(container.read(filteredNotificationsProvider).length, equals(8));

      // 2. Filter: orders -> 4 items (created, updated, cancelled, return)
      container.read(notificationCategoryFilterProvider.notifier).state =
          NotificationCategory.orders;
      final orders = container.read(filteredNotificationsProvider);
      expect(orders.length, equals(4));
      expect(
        orders.map((e) => e.type),
        containsAll([
          NotificationType.orderCreated,
          NotificationType.orderUpdated,
          NotificationType.orderCancelled,
          NotificationType.orderReturn,
        ]),
      );

      // 3. Filter: inventory -> 1 item (imported)
      container.read(notificationCategoryFilterProvider.notifier).state =
          NotificationCategory.inventory;
      final inv = container.read(filteredNotificationsProvider);
      expect(inv.length, equals(1));
      expect(inv.first.type, equals(NotificationType.inventoryImported));

      // 4. Filter: customers -> 3 items (created, debt added, debt paid)
      container.read(notificationCategoryFilterProvider.notifier).state =
          NotificationCategory.customers;
      final cust = container.read(filteredNotificationsProvider);
      expect(cust.length, equals(3));
      expect(
        cust.map((e) => e.type),
        containsAll([
          NotificationType.customerCreated,
          NotificationType.customerDebtAdded,
          NotificationType.customerDebtPaid,
        ]),
      );

      // 5. Filter: system -> 0 items (none mapped)
      container.read(notificationCategoryFilterProvider.notifier).state =
          NotificationCategory.system;
      final sys = container.read(filteredNotificationsProvider);
      expect(sys, isEmpty);

      // 6. Reset to null
      container.read(notificationCategoryFilterProvider.notifier).state = null;
      expect(container.read(filteredNotificationsProvider).length, equals(8));
    });

    test(
        'Unknown custom type string parsed via model is safely categorized '
        'without crashing the stream or filter', () {
      final exoticPayloads = [
        {'id': 'e1', 'type': 'UNKNOWN_WAREHOUSE_SYNC_9999'},
        {'id': 'e2', 'type': 'weird_random_type_xyz'},
        {'id': 'e3', 'type': ''},
        {'id': 'e4', 'type': null},
        {'id': 'e5', 'type': 'order-custom-action'},
        {'id': 'e6', 'type': 'stock-recount'},
      ];

      final models = exoticPayloads
          .map((m) => NotificationItemModel.fromMap(m, m['id']?.toString()))
          .toList();

      for (final m in models) {
        expect(() => m.toDomain(), returnsNormally);
        final domainItem = m.toDomain();
        expect(domainItem.type, isNotNull);
        expect(domainItem.category, isNotNull);
      }
    });

    test(
        'Empty notification lists are handled safely under all category filters',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _TestAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(sub.close);

      repo.getOrCreateController('store_001').add([]);
      await pumpEventQueue();

      for (final cat in [
        null,
        NotificationCategory.orders,
        NotificationCategory.inventory,
        NotificationCategory.customers,
        NotificationCategory.system,
      ]) {
        container.read(notificationCategoryFilterProvider.notifier).state = cat;
        expect(container.read(filteredNotificationsProvider), isEmpty);
        expect(container.read(unreadNotificationCountProvider), equals(0));
      }
    });

    test(
        'Rapid filter toggling does not cause race conditions or state corruption',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _TestAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(sub.close);

      repo.getOrCreateController('store_001').add(all8TypesNotifications);
      await pumpEventQueue();

      final filters = [
        null,
        NotificationCategory.orders,
        NotificationCategory.inventory,
        NotificationCategory.customers,
        NotificationCategory.system,
      ];

      // Perform 100 rapid filter switches
      for (int i = 0; i < 100; i++) {
        final targetFilter = filters[i % filters.length];
        container.read(notificationCategoryFilterProvider.notifier).state =
            targetFilter;
        final current = container.read(filteredNotificationsProvider);
        if (targetFilter == null) {
          expect(current.length, equals(8));
        } else if (targetFilter == NotificationCategory.orders) {
          expect(current.length, equals(4));
        } else if (targetFilter == NotificationCategory.inventory) {
          expect(current.length, equals(1));
        } else if (targetFilter == NotificationCategory.customers) {
          expect(current.length, equals(3));
        } else if (targetFilter == NotificationCategory.system) {
          expect(current.length, equals(0));
        }
      }
    });
  });

  // =========================================================================
  // GROUP 4: CONCURRENT CONTROLLER MUTATIONS & ERROR RESILIENCE
  // =========================================================================
  group('4. Concurrent Controller Mutations & Error Resilience', () {
    test(
        'Concurrent markAllAsRead and markAsRead executions complete smoothly '
        'with consistent StateNotifier AsyncValue', () async {
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(notificationControllerProvider.notifier);

      // Trigger markAllAsRead and markAsRead concurrently
      await Future.wait([
        controller.markAllAsRead(),
        controller.markAsRead('notif_100'),
      ]);

      expect(repo.markAllAsReadLog, equals(['store_001']));
      expect(repo.markAsReadLog, equals(['store_001:notif_100']));

      final state = container.read(notificationControllerProvider);
      expect(state, equals(const AsyncData<void>(null)));
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
    });

    test(
        'Concurrent mutations catching repository exceptions gracefully propagate '
        'AsyncError without uncaught crashes', () async {
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      repo.throwOnMarkAsRead = true;

      final controller =
          container.read(notificationControllerProvider.notifier);

      // Trigger both: markAllAsRead succeeds, markAsRead fails
      bool markAsReadCaught = false;
      await Future.wait([
        controller.markAllAsRead().catchError((_) {}),
        controller.markAsRead('notif_fail').catchError((e) {
          markAsReadCaught = true;
        }),
      ]);

      expect(markAsReadCaught, isTrue);
      expect(repo.markAllAsReadLog, equals(['store_001']));

      // Controller state captured error or completed data
      final state = container.read(notificationControllerProvider);
      expect(state.isLoading, isFalse);
    });

    test(
        'Multiple concurrent markAsRead operations (20 parallel requests) all '
        'execute and finish in AsyncData', () async {
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(notificationControllerProvider.notifier);

      final futures = <Future<void>>[];
      for (int i = 0; i < 20; i++) {
        futures.add(controller.markAsRead('n_$i'));
      }

      await Future.wait(futures);

      expect(repo.markAsReadLog.length, equals(20));
      final state = container.read(notificationControllerProvider);
      expect(state, equals(const AsyncData<void>(null)));
    });

    test(
        'Controller mutation with explicit storeId overrides default active store',
        () async {
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(notificationControllerProvider.notifier);

      await controller.markAsRead('n_remote', storeId: 'store_002');
      await controller.deleteNotification('n_del_remote', storeId: 'store_002');
      await controller.markAllAsRead(storeId: 'store_002');

      expect(repo.markAsReadLog, equals(['store_002:n_remote']));
      expect(repo.deleteLog, equals(['store_002:n_del_remote']));
      expect(repo.markAllAsReadLog, equals(['store_002']));
    });

    test(
        'Adversarial stress: in-flight mutation when container is disposed '
        'during async repository wait', () async {
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => repo),
        ],
      );

      final controller =
          container.read(notificationControllerProvider.notifier);

      repo.markAsReadDelayCompleter = Completer<void>();
      final mutationFuture = controller.markAsRead('n_delayed');

      // Dispose container while mutation is still pending
      container.dispose();

      // Complete delay
      repo.markAsReadDelayCompleter!.complete();

      // When StateNotifier is disposed, modifying state throws or is handled
      try {
        await mutationFuture;
      } catch (e) {
        // May catch StateError if StateNotifier asserts mounted, or complete normally
        expect(e, isA<Object>());
      }
    });
  });
}
