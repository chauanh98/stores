import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../../support/firebase_test_harness.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _MockNotificationRepository implements NotificationRepository {
  int watchNotificationsCallCount = 0;
  String? lastWatchStoreId;
  int? lastWatchLimit;

  int addNotificationCallCount = 0;
  NotificationItem? lastAddedNotification;

  int markAsReadCallCount = 0;
  String? lastMarkAsReadStoreId;
  String? lastMarkAsReadId;

  int markAllAsReadCallCount = 0;
  String? lastMarkAllAsReadStoreId;

  int deleteNotificationCallCount = 0;
  String? lastDeleteStoreId;
  String? lastDeleteId;

  final StreamController<List<NotificationItem>> streamController =
      StreamController<List<NotificationItem>>.broadcast();

  bool throwError = false;

  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
      {int limit = 50}) {
    watchNotificationsCallCount++;
    lastWatchStoreId = storeId;
    lastWatchLimit = limit;
    return streamController.stream;
  }

  @override
  Future<void> addNotification(NotificationItem notification) async {
    if (throwError) throw Exception('Simulated repository error');
    addNotificationCallCount++;
    lastAddedNotification = notification;
  }

  @override
  Future<void> markAsRead({required String storeId, required String id}) async {
    if (throwError) throw Exception('Simulated repository error');
    markAsReadCallCount++;
    lastMarkAsReadStoreId = storeId;
    lastMarkAsReadId = id;
  }

  @override
  Future<void> markAllAsRead(String storeId) async {
    if (throwError) throw Exception('Simulated repository error');
    markAllAsReadCallCount++;
    lastMarkAllAsReadStoreId = storeId;
  }

  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {
    if (throwError) throw Exception('Simulated repository error');
    deleteNotificationCallCount++;
    lastDeleteStoreId = storeId;
    lastDeleteId = id;
  }

  void dispose() {
    streamController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const ownerUser = UserAccount(
    username: 'owner',
    displayName: 'Chủ cửa hàng',
    role: 'owner',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff',
    displayName: 'Nhân viên bán hàng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor',
    displayName: 'Giám sát chi nhánh',
    role: 'supervisor',
    storeId: 'store_001',
  );

  final sampleNotifications = [
    NotificationItem(
      id: 'notif_1',
      storeId: 'store_001',
      title: 'Đơn hàng mới #HD013259',
      body: 'Tổng tiền: 150.000đ',
      type: NotificationType.orderCreated,
      isRead: false,
      createdAt: DateTime(2026, 10, 4, 10, 0),
    ),
    NotificationItem(
      id: 'notif_2',
      storeId: 'store_001',
      title: 'Nhập kho hoàn tất #NK001',
      body: 'Tổng tiền: 5.000.000đ',
      type: NotificationType.inventoryImported,
      isRead: true,
      createdAt: DateTime(2026, 10, 4, 9, 30),
    ),
    NotificationItem(
      id: 'notif_3',
      storeId: 'store_001',
      title: 'Khách hàng mới: Nguyễn Văn A',
      body: 'SĐT: 0912345678',
      type: NotificationType.customerCreated,
      isRead: false,
      createdAt: DateTime(2026, 10, 4, 9, 0),
    ),
    NotificationItem(
      id: 'notif_4',
      storeId: 'store_001',
      title: 'Đã hủy đơn hàng #HD013250',
      body: 'Lý do: Khách đổi ý',
      type: NotificationType.orderCancelled,
      isRead: false,
      createdAt: DateTime(2026, 10, 4, 8, 30),
    ),
  ];

  late _MockNotificationRepository mockRepo;

  setUp(() {
    mockRepo = _MockNotificationRepository();
  });

  tearDown(() {
    mockRepo.dispose();
  });

  group('1. RBAC & Bandwidth Guard (notificationStreamProvider)', () {
    test('Staff user receives empty stream and watchNotifications is NOT called',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final emitted = await container.read(notificationStreamProvider.future);

      expect(emitted, isEmpty);
      expect(mockRepo.watchNotificationsCallCount, equals(0),
          reason: 'Non-admin staff must not trigger any Firebase stream query');
    });

    test('Supervisor user receives empty stream and watchNotifications is NOT called',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final emitted = await container.read(notificationStreamProvider.future);

      expect(emitted, isEmpty);
      expect(mockRepo.watchNotificationsCallCount, equals(0));
    });

    test('Unauthenticated user (null) receives empty stream without calling repository',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(null)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final emitted = await container.read(notificationStreamProvider.future);

      expect(emitted, isEmpty);
      expect(mockRepo.watchNotificationsCallCount, equals(0));
    });

    test('Admin user invokes watchNotifications with storeId and limit=50',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final future = container.read(notificationStreamProvider.future);

      // Emit data from mock repository
      mockRepo.streamController.add(sampleNotifications);
      final emitted = await future;

      expect(mockRepo.watchNotificationsCallCount, equals(1));
      expect(mockRepo.lastWatchStoreId, equals('store_001'));
      expect(mockRepo.lastWatchLimit, equals(50));
      expect(emitted.length, equals(4));
      expect(emitted.first.id, equals('notif_1'));
    });

    test('Owner user invokes watchNotifications successfully', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(ownerUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_002'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final future = container.read(notificationStreamProvider.future);
      mockRepo.streamController.add(sampleNotifications);
      final emitted = await future;

      expect(mockRepo.watchNotificationsCallCount, equals(1));
      expect(mockRepo.lastWatchStoreId, equals('store_002'));
      expect(emitted.length, equals(4));
    });

    test('Empty storeId returns empty stream without invoking repository',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => ''),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final emitted = await container.read(notificationStreamProvider.future);

      expect(emitted, isEmpty);
      expect(mockRepo.watchNotificationsCallCount, equals(0));
    });
  });

  group('2. Unread Count Provider (unreadNotificationCountProvider)', () {
    test('Calculates correct count of notifications where isRead == false',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      // Listen to stream
      final subscription =
          container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(subscription.close);

      // Emit sample notifications (notif_1, notif_3, notif_4 are unread -> 3 unread)
      mockRepo.streamController.add(sampleNotifications);
      await Future<void>.delayed(Duration.zero);

      final unreadCount = container.read(unreadNotificationCountProvider);
      expect(unreadCount, equals(3));
    });

    test('Returns 0 when all notifications are marked as read', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final subscription =
          container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(subscription.close);

      final allRead =
          sampleNotifications.map((n) => n.copyWith(isRead: true)).toList();
      mockRepo.streamController.add(allRead);
      await Future<void>.delayed(Duration.zero);

      final unreadCount = container.read(unreadNotificationCountProvider);
      expect(unreadCount, equals(0));
    });

    test('Returns 0 for staff user since stream is empty', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final unreadCount = container.read(unreadNotificationCountProvider);
      expect(unreadCount, equals(0));
    });
  });

  group('3. Category Filtering (filteredNotificationsProvider)', () {
    test('Default filter (null) returns all notifications unfiltered',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final subscription =
          container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(subscription.close);

      mockRepo.streamController.add(sampleNotifications);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(notificationCategoryFilterProvider), isNull);
      final filtered = container.read(filteredNotificationsProvider);
      expect(filtered.length, equals(4));
    });

    test('Filter by orders category returns orderCreated and orderCancelled',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final subscription =
          container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(subscription.close);

      mockRepo.streamController.add(sampleNotifications);
      await Future<void>.delayed(Duration.zero);

      container.read(notificationCategoryFilterProvider.notifier).state =
          NotificationCategory.orders;

      final filtered = container.read(filteredNotificationsProvider);
      expect(filtered.length, equals(2));
      expect(filtered.every((n) => n.category == NotificationCategory.orders),
          isTrue);
      expect(filtered.map((n) => n.id), containsAll(['notif_1', 'notif_4']));
    });

    test('Filter by inventory category returns inventoryImported', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final subscription =
          container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(subscription.close);

      mockRepo.streamController.add(sampleNotifications);
      await Future<void>.delayed(Duration.zero);

      container.read(notificationCategoryFilterProvider.notifier).state =
          NotificationCategory.inventory;

      final filtered = container.read(filteredNotificationsProvider);
      expect(filtered.length, equals(1));
      expect(filtered.first.id, equals('notif_2'));
      expect(filtered.first.category, equals(NotificationCategory.inventory));
    });

    test('Filter by customers category returns customerCreated', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final subscription =
          container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(subscription.close);

      mockRepo.streamController.add(sampleNotifications);
      await Future<void>.delayed(Duration.zero);

      container.read(notificationCategoryFilterProvider.notifier).state =
          NotificationCategory.customers;

      final filtered = container.read(filteredNotificationsProvider);
      expect(filtered.length, equals(1));
      expect(filtered.first.id, equals('notif_3'));
      expect(filtered.first.category, equals(NotificationCategory.customers));
    });

    test('Resetting filter to null restores full notification list', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final subscription =
          container.listen(notificationStreamProvider, (_, __) {});
      addTearDown(subscription.close);

      mockRepo.streamController.add(sampleNotifications);
      await Future<void>.delayed(Duration.zero);

      container.read(notificationCategoryFilterProvider.notifier).state =
          NotificationCategory.customers;
      expect(container.read(filteredNotificationsProvider).length, equals(1));

      container.read(notificationCategoryFilterProvider.notifier).state = null;
      expect(container.read(filteredNotificationsProvider).length, equals(4));
    });
  });

  group('4. Notification Controller (notificationControllerProvider)', () {
    test('markAsRead calls repository with active storeId and notification ID',
        () async {
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(notificationControllerProvider.notifier);
      await controller.markAsRead('notif_1');

      expect(mockRepo.markAsReadCallCount, equals(1));
      expect(mockRepo.lastMarkAsReadStoreId, equals('store_001'));
      expect(mockRepo.lastMarkAsReadId, equals('notif_1'));
      expect(container.read(notificationControllerProvider),
          equals(const AsyncData<void>(null)));
    });

    test('markAsRead respects explicit storeId argument', () async {
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(notificationControllerProvider.notifier);
      await controller.markAsRead('notif_99', storeId: 'store_002');

      expect(mockRepo.markAsReadCallCount, equals(1));
      expect(mockRepo.lastMarkAsReadStoreId, equals('store_002'));
      expect(mockRepo.lastMarkAsReadId, equals('notif_99'));
    });

    test('markAllAsRead calls repository with active storeId', () async {
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(notificationControllerProvider.notifier);
      await controller.markAllAsRead();

      expect(mockRepo.markAllAsReadCallCount, equals(1));
      expect(mockRepo.lastMarkAllAsReadStoreId, equals('store_001'));
      expect(container.read(notificationControllerProvider),
          equals(const AsyncData<void>(null)));
    });

    test('deleteNotification calls repository with active storeId and target ID',
        () async {
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(notificationControllerProvider.notifier);
      await controller.deleteNotification('notif_1');

      expect(mockRepo.deleteNotificationCallCount, equals(1));
      expect(mockRepo.lastDeleteStoreId, equals('store_001'));
      expect(mockRepo.lastDeleteId, equals('notif_1'));
      expect(container.read(notificationControllerProvider),
          equals(const AsyncData<void>(null)));
    });

    test('addNotification calls repository with notification item', () async {
      final container = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(notificationControllerProvider.notifier);
      await controller.addNotification(sampleNotifications.first);

      expect(mockRepo.addNotificationCallCount, equals(1));
      expect(mockRepo.lastAddedNotification?.id, equals('notif_1'));
    });

    test('Controller handles error and rethrows with AsyncError state',
        () async {
      mockRepo.throwError = true;

      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWith((ref) => mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(notificationControllerProvider.notifier);

      await expectLater(
        controller.markAsRead('notif_fail'),
        throwsException,
      );

      expect(container.read(notificationControllerProvider).hasError, isTrue);
    });
  });

  group('5. Data Source & Repository Provider Construction', () {
    test('notificationRemoteDataSourceProvider constructs safely with mock database',
        () {
      final mockDb = MockFirebaseDatabase();
      final container = ProviderContainer(
        overrides: [
          notificationRemoteDataSourceProvider.overrideWithValue(
            NotificationRemoteDataSource(mockDb),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(() => container.read(notificationRemoteDataSourceProvider),
          returnsNormally);
    });

    test('notificationRepositoryProvider creates repository instance', () {
      final mockDb = MockFirebaseDatabase();
      final container = ProviderContainer(
        overrides: [
          notificationRemoteDataSourceProvider.overrideWithValue(
            NotificationRemoteDataSource(mockDb),
          ),
        ],
      );
      addTearDown(container.dispose);

      final repo = container.read(notificationRepositoryProvider);
      expect(repo, isA<NotificationRepository>());
    });
  });
}
