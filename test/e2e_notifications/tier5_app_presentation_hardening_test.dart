import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/notifications/local_notification_service.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/presentation/customers/pages/customer_debt_page.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_receipt_detail_bottom_sheet.dart';
import 'package:stores/presentation/notifications/pages/notifications_page.dart';
import 'package:stores/presentation/notifications/utils/notification_navigation_handler.dart';
import 'package:stores/presentation/notifications/widgets/notification_bell_action.dart';
import 'package:stores/presentation/notifications/widgets/notification_card.dart';
import 'package:stores/presentation/orders/widgets/invoice_detail_bottom_sheet.dart';
import 'package:stores/presentation/orders/widgets/return_order_detail_bottom_sheet.dart';

// ============================================================================
// ADVERSARIAL TEST DOUBLES & MOCKS
// ============================================================================

class _AdversarialAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _AdversarialAuthNotifier([super.state]);

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

class _AdversarialNotificationRepository implements NotificationRepository {
  final List<NotificationItem> items;
  final List<String> markedReadIds = [];
  final List<String> deletedIds = [];
  final List<NotificationItem> addedItems = [];

  int watchCallCount = 0;
  String? lastWatchStoreId;
  int? lastWatchLimit;
  int activeSubscriptions = 0;

  int markAllAsReadCalls = 0;
  String? lastMarkAllStoreId;

  int markAsReadCalls = 0;
  String? lastMarkReadStoreId;
  String? lastMarkReadId;

  int deleteCalls = 0;
  String? lastDeleteStoreId;
  String? lastDeleteId;

  int addCalls = 0;

  Completer<void>? markAllCompleter;
  Completer<void>? markAsReadCompleter;
  Completer<void>? deleteCompleter;

  bool shouldThrowOnMarkAll = false;
  bool shouldThrowOnDelete = false;
  bool shouldThrowOnAdd = false;
  bool shouldThrowOnMarkRead = false;

  final StreamController<List<NotificationItem>> _controller =
      StreamController<List<NotificationItem>>.broadcast();

  _AdversarialNotificationRepository([List<NotificationItem>? initial])
      : items = initial != null ? List.from(initial) : [];

  @override
  Stream<List<NotificationItem>> watchNotifications(
    String storeId, {
    int limit = 50,
  }) {
    watchCallCount++;
    lastWatchStoreId = storeId;
    lastWatchLimit = limit;

    return Stream<List<NotificationItem>>.multi((multiController) {
      activeSubscriptions++;
      multiController.add(List.unmodifiable(items));

      final sub = _controller.stream.listen(
        (data) => multiController.add(data),
        onError: (e) => multiController.addError(e),
        onDone: () => multiController.close(),
      );

      multiController.onCancel = () {
        activeSubscriptions--;
        sub.cancel();
      };
    });
  }

  void emitCurrent() {
    _controller.add(List.unmodifiable(items));
  }

  void emitItems(List<NotificationItem> newItems) {
    items.clear();
    items.addAll(newItems);
    emitCurrent();
  }

  @override
  Future<void> addNotification(NotificationItem notification) async {
    if (shouldThrowOnAdd) {
      throw Exception('Adversarial simulated failure on addNotification');
    }
    addCalls++;
    addedItems.add(notification);
    items.insert(0, notification);
    emitCurrent();
  }

  @override
  Future<void> markAsRead({required String storeId, required String id}) async {
    if (markAsReadCompleter != null && !markAsReadCompleter!.isCompleted) {
      await markAsReadCompleter!.future;
    }
    if (shouldThrowOnMarkRead) {
      throw Exception('Adversarial simulated failure on markAsRead');
    }
    markAsReadCalls++;
    lastMarkReadStoreId = storeId;
    lastMarkReadId = id;
    markedReadIds.add(id);

    final idx = items.indexWhere((i) => i.id == id);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(isRead: true);
      emitCurrent();
    }
  }

  @override
  Future<void> markAllAsRead(String storeId) async {
    if (markAllCompleter != null && !markAllCompleter!.isCompleted) {
      await markAllCompleter!.future;
    }
    if (shouldThrowOnMarkAll) {
      throw Exception('Adversarial simulated failure on markAllAsRead');
    }
    markAllAsReadCalls++;
    lastMarkAllStoreId = storeId;

    for (int i = 0; i < items.length; i++) {
      items[i] = items[i].copyWith(isRead: true);
    }
    emitCurrent();
  }

  @override
  Future<void> deleteNotification({
    required String storeId,
    required String id,
  }) async {
    if (deleteCompleter != null && !deleteCompleter!.isCompleted) {
      await deleteCompleter!.future;
    }
    if (shouldThrowOnDelete) {
      throw Exception('Adversarial simulated failure on deleteNotification');
    }
    deleteCalls++;
    lastDeleteStoreId = storeId;
    lastDeleteId = id;
    deletedIds.add(id);

    items.removeWhere((i) => i.id == id);
    emitCurrent();
  }

  void dispose() {
    _controller.close();
  }
}

class _AdversarialOrderRepository implements OrderRepository {
  Completer<Order?>? fetchCompleter;
  Order? orderToReturn;
  int fetchCount = 0;
  bool shouldThrowOnFetch = false;

  @override
  Future<Order?> fetchById(String orderId) async {
    fetchCount++;
    if (fetchCompleter != null && !fetchCompleter!.isCompleted) {
      await fetchCompleter!.future;
    }
    if (shouldThrowOnFetch) {
      throw Exception('Simulated order fetch error');
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
  bool shouldThrowOnFetch = false;

  @override
  Future<Customer?> fetchById(String id) async {
    fetchCount++;
    if (fetchCompleter != null && !fetchCompleter!.isCompleted) {
      await fetchCompleter!.future;
    }
    if (shouldThrowOnFetch) {
      throw Exception('Simulated customer fetch error');
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

class _ThrowingLocalNotificationPlugin implements FlutterLocalNotificationsPlugin {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    throw Exception('Simulated plugin initialization crash');
  }

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    throw Exception('Simulated platform channel show() crash');
  }

  @override
  Future<void> cancel(int id, {String? tag}) async {
    throw Exception('Simulated cancel crash');
  }

  @override
  Future<void> cancelAll() async {
    throw Exception('Simulated cancelAll crash');
  }
}

// ============================================================================
// TEST APP BUILDER
// ============================================================================

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
  List<NavigatorObserver> observers = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      navigatorObservers: observers,
      routes: {
        '/notifications': (context) => const NotificationsPage(),
      },
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

  const ownerUser = UserAccount(
    username: 'owner',
    displayName: 'Chủ cửa hàng',
    role: 'owner',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff',
    displayName: 'Nhân viên',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  final sampleDate = DateTime.utc(2026, 10, 4, 12, 0, 0);

  NotificationItem makeNotification({
    required String id,
    String storeId = 'store_001',
    String title = 'Thông báo mẫu',
    String body = 'Nội dung thông báo',
    NotificationType type = NotificationType.orderCreated,
    bool isRead = false,
    DateTime? createdAt,
    String? targetRoute = 'invoice_detail',
    String? targetId = 'HD001',
    Map<String, dynamic>? metadata,
  }) {
    return NotificationItem(
      id: id,
      storeId: storeId,
      title: title,
      body: body,
      type: type,
      isRead: isRead,
      createdAt: createdAt ?? sampleDate,
      targetRoute: targetRoute,
      targetId: targetId,
      metadata: metadata,
    );
  }

  // ==========================================================================
  // SECTION 1: EXTREME RBAC LIFECYCLE TRANSITIONS
  // ==========================================================================
  group('=== TIER 5: SECTION 1 - EXTREME RBAC LIFECYCLE TRANSITIONS ===', () {
    test('T5.1: Active Admin user logged out mid-stream cancels repo subscription and zeroes unread badge',
        () async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(id: 'N1', isRead: false),
        makeNotification(id: 'N2', isRead: false),
      ]);
      final authNotifier = _AdversarialAuthNotifier(adminUser);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(repo.dispose);

      // 1. Initial Admin stream subscription
      final initialItems =
          await container.read(notificationStreamProvider.future);
      expect(initialItems.length, equals(2));
      expect(container.read(unreadNotificationCountProvider), equals(2));
      expect(repo.activeSubscriptions, equals(1));

      // 2. Mid-stream logout: auth emits null
      authNotifier.logout();

      // Pump microtasks for stream transition
      await container.pump();

      // 3. Verify stream returns empty list and previous subscription was cancelled
      final loggedOutItems =
          await container.read(notificationStreamProvider.future);
      expect(loggedOutItems, isEmpty);
      expect(container.read(unreadNotificationCountProvider), equals(0));
      expect(repo.activeSubscriptions, equals(0));
    });

    test('T5.2: Logged out user logs in as Staff (nhanvien) with 0 network queries; re-login as Admin reconnects',
        () async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(id: 'N1', isRead: false),
      ]);
      final authNotifier = _AdversarialAuthNotifier(null);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(repo.dispose);

      // 1. Logged out: stream is empty, repo not called
      final unauthItems =
          await container.read(notificationStreamProvider.future);
      expect(unauthItems, isEmpty);
      expect(repo.watchCallCount, equals(0));

      // 2. Login as Staff
      authNotifier.setUser(staffUser);
      await container.pump();

      final staffItems =
          await container.read(notificationStreamProvider.future);
      expect(staffItems, isEmpty);
      expect(repo.watchCallCount, equals(0)); // 0 Firebase egress for Staff

      // 3. Re-login as Admin
      authNotifier.setUser(adminUser);
      await container.pump();

      final adminItems =
          await container.read(notificationStreamProvider.future);
      expect(adminItems.length, equals(1));
      expect(repo.watchCallCount, equals(1)); // Repository connected
      expect(container.read(unreadNotificationCountProvider), equals(1));
    });

    test('T5.3: Dynamic role promotion (Staff -> Admin -> Owner) transitions stream smoothly',
        () async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(id: 'N1', isRead: false),
      ]);
      final authNotifier = _AdversarialAuthNotifier(staffUser);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(repo.dispose);

      // 1. Staff: empty stream
      expect(await container.read(notificationStreamProvider.future), isEmpty);

      // 2. Promote to Admin
      authNotifier.setUser(adminUser);
      await container.pump();

      final adminItems =
          await container.read(notificationStreamProvider.future);
      expect(adminItems.length, equals(1));
      expect(container.read(unreadNotificationCountProvider), equals(1));

      // 3. Promote to Owner
      authNotifier.setUser(ownerUser);
      await container.pump();

      final ownerItems =
          await container.read(notificationStreamProvider.future);
      expect(ownerItems.length, equals(1));
      expect(container.read(unreadNotificationCountProvider), equals(1));
    });

    test('T5.4: Dynamic role demotion (Admin -> Staff -> Unknown role) drops stream to empty immediately',
        () async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(id: 'N1', isRead: false),
      ]);
      final authNotifier = _AdversarialAuthNotifier(adminUser);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          notificationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(repo.dispose);

      // 1. Admin: active stream
      expect(
          (await container.read(notificationStreamProvider.future)).length,
          equals(1));

      // 2. Demote to Staff
      authNotifier.setUser(staffUser);
      await container.pump();

      expect(await container.read(notificationStreamProvider.future), isEmpty);
      expect(container.read(unreadNotificationCountProvider), equals(0));

      // 3. Demote to unknown / custom role
      authNotifier.setUser(const UserAccount(
        username: 'guest',
        displayName: 'Khách',
        role: 'guest',
        storeId: 'store_001',
      ));
      await container.pump();

      expect(await container.read(notificationStreamProvider.future), isEmpty);
    });

    test('T5.5: NotificationController batch & mutation operations under storeId switch preserve target scoping',
        () async {
      final repo = _AdversarialNotificationRepository();
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_002'),
          notificationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(repo.dispose);

      final controller =
          container.read(notificationControllerProvider.notifier);

      // Explicit storeId: 'store_001' while active store is 'store_002'
      await controller.markAllAsRead(storeId: 'store_001');
      expect(repo.lastMarkAllStoreId, equals('store_001'));

      await controller.deleteNotification('N_DELETE', storeId: 'store_001');
      expect(repo.lastDeleteStoreId, equals('store_001'));
      expect(repo.lastDeleteId, equals('N_DELETE'));

      await controller.markAsRead('N_READ', storeId: 'store_001');
      expect(repo.lastMarkReadStoreId, equals('store_001'));
      expect(repo.lastMarkReadId, equals('N_READ'));
    });

    test('T5.6: NotificationController fallback behavior when storeId is omitted, null, or whitespace',
        () async {
      final repo = _AdversarialNotificationRepository();
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_default'),
          notificationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(repo.dispose);

      final controller =
          container.read(notificationControllerProvider.notifier);

      // Omitted storeId -> defaults to 'store_default'
      await controller.markAllAsRead();
      expect(repo.lastMarkAllStoreId, equals('store_default'));

      // Empty storeId -> defaults to 'store_default'
      await controller.markAsRead('N1', storeId: '');
      expect(repo.lastMarkReadStoreId, equals('store_default'));

      // Whitespace storeId -> defaults to 'store_default'
      await controller.deleteNotification('N2', storeId: '   ');
      expect(repo.lastDeleteStoreId, equals('store_default'));
    });

    test('T5.7: NotificationStreamProvider handling of empty or whitespace storeId returns empty stream',
        () async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(id: 'N1'),
      ]);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => '   '),
          notificationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(repo.dispose);

      final items = await container.read(notificationStreamProvider.future);
      expect(items, isEmpty);
      expect(repo.watchCallCount, equals(0)); // Zero network egress
    });

    test('T5.8: Switching currentStoreIdProvider mid-stream unsubscribes from old store and attaches to new store',
        () async {
      final repo = _AdversarialNotificationRepository();
      final activeStoreProvider = StateProvider<String>((ref) => 'store_001');

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
          currentStoreIdProvider
              .overrideWith((ref) => ref.watch(activeStoreProvider)),
          notificationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(repo.dispose);

      // 1. Initial watch on store_001
      await container.read(notificationStreamProvider.future);
      expect(repo.lastWatchStoreId, equals('store_001'));
      expect(repo.watchCallCount, equals(1));

      // 2. Switch store to store_002
      container.read(activeStoreProvider.notifier).state = 'store_002';
      await container.pump();

      await container.read(notificationStreamProvider.future);
      expect(repo.lastWatchStoreId, equals('store_002'));
      expect(repo.watchCallCount, equals(2));
    });
  });

  // ==========================================================================
  // SECTION 2: LOCAL NOTIFICATION STRESS & RESILIENCE
  // ==========================================================================
  group('=== TIER 5: SECTION 2 - LOCAL NOTIFICATION STRESS & RESILIENCE ===', () {
    late FakeLocalNotificationService fakeLocalService;
    final fixedNow = DateTime.utc(2026, 10, 4, 12, 0, 0);

    setUp(() {
      fakeLocalService = FakeLocalNotificationService();
    });

    test('T5.9: Clock skew future boundary stress (-10s threshold)', () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeLocalService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      // Exactly at future boundary: age = -10s -> ACCEPTED
      final itemAtBoundary = makeNotification(
        id: 'NOTIF_FUTURE_10S',
        createdAt: fixedNow.add(const Duration(seconds: 10)),
      );
      final count1 = await listener.processNotifications([itemAtBoundary]);
      expect(count1, equals(1));
      expect(fakeLocalService.displayedCalls.length, equals(1));

      // Beyond future boundary: age = -10.001s -> REJECTED (future threshold exceeded)
      final itemBeyondBoundary = makeNotification(
        id: 'NOTIF_FUTURE_TOO_FAR',
        createdAt: fixedNow.add(const Duration(seconds: 10, milliseconds: 1)),
      );
      final count2 = await listener.processNotifications([itemBeyondBoundary]);
      expect(count2, equals(0));
      expect(fakeLocalService.displayedCalls.length, equals(1));

      // Safely within future skew: age = -5s -> ACCEPTED
      final itemWithin = makeNotification(
        id: 'NOTIF_FUTURE_5S',
        createdAt: fixedNow.add(const Duration(seconds: 5)),
      );
      final count3 = await listener.processNotifications([itemWithin]);
      expect(count3, equals(1));
      expect(fakeLocalService.displayedCalls.length, equals(2));
    });

    test('T5.10: Clock skew past boundary stress (maxAge 60s threshold)', () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeLocalService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      // Exactly at past boundary: age = +60s -> ACCEPTED
      final itemAtMaxAge = makeNotification(
        id: 'NOTIF_PAST_60S',
        createdAt: fixedNow.subtract(const Duration(seconds: 60)),
      );
      final count1 = await listener.processNotifications([itemAtMaxAge]);
      expect(count1, equals(1));

      // Older than maxAge: age = 60s + 1ms -> REJECTED
      final itemTooOld = makeNotification(
        id: 'NOTIF_PAST_60S_1MS',
        createdAt:
            fixedNow.subtract(const Duration(seconds: 60, milliseconds: 1)),
      );
      final count2 = await listener.processNotifications([itemTooOld]);
      expect(count2, equals(0));

      // Safely within past threshold: age = 30s -> ACCEPTED
      final itemFresh = makeNotification(
        id: 'NOTIF_PAST_30S',
        createdAt: fixedNow.subtract(const Duration(seconds: 30)),
      );
      final count3 = await listener.processNotifications([itemFresh]);
      expect(count3, equals(1));
    });

    test('T5.11: Already read items are strictly suppressed regardless of creation timestamp',
        () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeLocalService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      final readItem = makeNotification(
        id: 'NOTIF_READ_ITEM',
        isRead: true,
        createdAt: fixedNow,
      );

      final triggered = await listener.processNotifications([readItem]);
      expect(triggered, equals(0));
      expect(fakeLocalService.displayedCalls, isEmpty);
    });

    test('T5.12: Deduplication across multiple stream emissions suppresses redundant pop-ups',
        () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeLocalService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      final itemA = makeNotification(id: 'NOTIF_A', createdAt: fixedNow);
      final itemB = makeNotification(id: 'NOTIF_B', createdAt: fixedNow);

      // First emission: 2 notifications triggered
      final count1 = await listener.processNotifications([itemA, itemB]);
      expect(count1, equals(2));
      expect(fakeLocalService.displayedCalls.length, equals(2));

      // Second emission with same items + 1 new item: only 1 triggered
      final itemC = makeNotification(id: 'NOTIF_C', createdAt: fixedNow);
      final count2 = await listener.processNotifications([itemA, itemB, itemC]);
      expect(count2, equals(1));
      expect(fakeLocalService.displayedCalls.length, equals(3));
    });

    test('T5.13: 500+ deduplication cache rolling eviction bounds memory and prevents leaks',
        () async {
      final listener = NotificationListenerService(
        localNotificationService: fakeLocalService,
        maxAge: const Duration(seconds: 60),
        clock: () => fixedNow,
      );

      // Generate 505 unique items
      final allItems = List.generate(
        505,
        (i) => makeNotification(id: 'EV_ITEM_$i', createdAt: fixedNow),
      );

      // Feed in 10 chunks of 50 items each, then 1 chunk of 5 items
      for (int chunk = 0; chunk < 10; chunk++) {
        final sublist = allItems.sublist(chunk * 50, (chunk + 1) * 50);
        await listener.processNotifications(sublist);
      }
      expect(listener.shownIds.length, equals(500));

      // 11th chunk: items 500 to 504 (5 items) -> total exceeds 500
      final lastChunk = allItems.sublist(500, 505);
      final triggered = await listener.processNotifications(lastChunk);
      expect(triggered, equals(5));

      // Cache size must now be bounded to active incoming items (evicted older IDs)
      expect(listener.shownIds.length, equals(5));
      expect(listener.shownIds.contains('EV_ITEM_0'), isFalse);
      expect(listener.shownIds.contains('EV_ITEM_504'), isTrue);

      // Re-processing the active chunk produces 0 duplicates
      final retriggerCount = await listener.processNotifications(lastChunk);
      expect(retriggerCount, equals(0));
    });

    test('T5.14: Plugin error isolation in FlutterLocalNotificationServiceImpl catches and handles exceptions',
        () async {
      final throwingPlugin = _ThrowingLocalNotificationPlugin();
      final service = FlutterLocalNotificationServiceImpl(throwingPlugin);

      // 1. initialize catches plugin exception safely
      final initResult = await service.initialize();
      expect(initResult, isFalse);

      // 2. showNotification catches plugin crash safely without throwing
      await expectLater(
        service.showNotification(
          id: 1,
          title: 'Title',
          body: 'Body',
        ),
        completes,
      );

      // 3. cancel and cancelAll catch exceptions safely
      await expectLater(service.cancel(1), completes);
      await expectLater(service.cancelAll(), completes);

      // 4. requestPermissions completes safely without crashing
      final permResult = await service.requestPermissions();
      expect(permResult != null, isTrue);
    });

    test('T5.15: NotificationDispatcher exception isolation for all 8 business events protects POS & inventory',
        () async {
      final repo = _AdversarialNotificationRepository();
      repo.shouldThrowOnAdd = true; // Repository crashes on any save
      final dispatcher = NotificationDispatcher(repo);

      final dummyOrder = Order(
        id: 'HD_TEST',
        customerId: 'CUST_1',
        createdAt: DateTime.now(),
        items: [
          OrderItem(
            productId: 'P1',
            productName: 'SP A',
            quantity: 1,
            price: 100000,
            warrantyMonths: 0,
            purchaseDate: DateTime.utc(2026, 10, 4),
          ),
        ],
        total: 100000,
      );

      final dummyReturnOrder = ReturnOrder(
        id: 'RET_TEST',
        orderId: 'HD_TEST',
        customerId: 'CUST_1',
        storeId: 'store_001',
        createdAt: DateTime.now(),
        items: const [
          ReturnOrderItem(
            productId: 'P1',
            productName: 'SP A',
            price: 100000,
            quantity: 1,
          ),
        ],
        totalReturnAmount: 100000,
      );

      final dummyReceipt = StockInReceipt(
        id: 'REC_TEST',
        importCode: 'NK001',
        date: DateTime.now(),
        items: const [],
        status: 'completed',
      );

      const dummyCustomer = Customer(
        id: 'CUST_TEST',
        name: 'Nguyễn Văn Test',
        phone: '0901234567',
        email: '',
        address: '',
        purchases: [],
      );

      // 1. Order created
      await expectLater(
        dispatcher.notifyOrderCreated(
          storeId: 'store_001',
          order: dummyOrder,
          user: adminUser,
        ),
        completes,
      );

      // 2. Order updated
      await expectLater(
        dispatcher.notifyOrderUpdated(
          storeId: 'store_001',
          order: dummyOrder,
          originalOrderId: 'HD_ORIG',
          user: adminUser,
        ),
        completes,
      );

      // 3. Order cancelled
      await expectLater(
        dispatcher.notifyOrderCancelled(
          storeId: 'store_001',
          order: dummyOrder,
          cancelReason: 'Khách đổi ý',
          user: adminUser,
        ),
        completes,
      );

      // 4. Order returned
      await expectLater(
        dispatcher.notifyOrderReturned(
          storeId: 'store_001',
          returnOrder: dummyReturnOrder,
          user: adminUser,
        ),
        completes,
      );

      // 5. Stock-in completed
      await expectLater(
        dispatcher.notifyStockInCompleted(
          storeId: 'store_001',
          receipt: dummyReceipt,
          user: adminUser,
        ),
        completes,
      );

      // 6. Customer created
      await expectLater(
        dispatcher.notifyCustomerCreated(
          storeId: 'store_001',
          customer: dummyCustomer,
          user: adminUser,
        ),
        completes,
      );

      // 7. Customer debt added
      await expectLater(
        dispatcher.notifyCustomerDebtAdded(
          storeId: 'store_001',
          customerId: 'CUST_TEST',
          customerName: 'Nguyễn Văn Test',
          debtAmount: 50000,
          orderId: 'HD_TEST',
          user: adminUser,
        ),
        completes,
      );

      // 8. Customer debt collected
      await expectLater(
        dispatcher.notifyCustomerDebtCollected(
          storeId: 'store_001',
          customerId: 'CUST_TEST',
          customerName: 'Nguyễn Văn Test',
          collectedAmount: 50000,
          user: adminUser,
        ),
        completes,
      );
    });

    test('T5.16: NotificationDispatcher business rule guards skip invalid and draft records',
        () async {
      final repo = _AdversarialNotificationRepository();
      final dispatcher = NotificationDispatcher(repo);

      // Draft order -> skipped
      final draftOrder = Order(
        id: 'HD_DRAFT',
        customerId: 'CUST_1',
        createdAt: DateTime.now(),
        items: const [],
        total: 100000,
        status: 'draft',
      );
      await dispatcher.notifyOrderCreated(
        storeId: 'store_001',
        order: draftOrder,
        user: adminUser,
      );
      expect(repo.addCalls, equals(0));

      // Draft stock-in receipt -> skipped
      final draftReceipt = StockInReceipt(
        id: 'REC_DRAFT',
        importCode: 'NK_DRAFT',
        date: DateTime.now(),
        items: const [],
        status: 'draft',
      );
      await dispatcher.notifyStockInCompleted(
        storeId: 'store_001',
        receipt: draftReceipt,
        user: adminUser,
      );
      expect(repo.addCalls, equals(0));

      // Cancelled stock-in receipt -> skipped
      final cancelledReceipt = StockInReceipt(
        id: 'REC_CAN',
        importCode: 'NK_CAN',
        date: DateTime.now(),
        items: const [],
        status: 'cancelled',
      );
      await dispatcher.notifyStockInCompleted(
        storeId: 'store_001',
        receipt: cancelledReceipt,
        user: adminUser,
      );
      expect(repo.addCalls, equals(0));

      // Non-positive customer debt added -> skipped
      await dispatcher.notifyCustomerDebtAdded(
        storeId: 'store_001',
        customerId: 'C1',
        customerName: 'Khách',
        debtAmount: 0.0,
        orderId: 'HD1',
        user: adminUser,
      );
      await dispatcher.notifyCustomerDebtAdded(
        storeId: 'store_001',
        customerId: 'C1',
        customerName: 'Khách',
        debtAmount: -50000.0,
        orderId: 'HD1',
        user: adminUser,
      );
      expect(repo.addCalls, equals(0));

      // Non-positive customer debt collected -> skipped
      await dispatcher.notifyCustomerDebtCollected(
        storeId: 'store_001',
        customerId: 'C1',
        customerName: 'Khách',
        collectedAmount: 0.0,
        user: adminUser,
      );
      await dispatcher.notifyCustomerDebtCollected(
        storeId: 'store_001',
        customerId: 'C1',
        customerName: 'Khách',
        collectedAmount: -10000.0,
        user: adminUser,
      );
      expect(repo.addCalls, equals(0));
    });

    test('T5.17: NotificationPayload parser robustness under malformed & adversarial payloads',
        () {
      // Null and empty
      expect(NotificationPayload.tryParse(null), isNull);
      expect(NotificationPayload.tryParse(''), isNull);
      expect(NotificationPayload.tryParse('   '), isNull);

      // Malformed / Non-JSON
      expect(NotificationPayload.tryParse('{invalid_json'), isNull);
      expect(NotificationPayload.tryParse('plain string'), isNull);
      expect(NotificationPayload.tryParse('12345'), isNull);
      expect(NotificationPayload.tryParse('[1, 2, 3]'), isNull);

      // Valid JSON round-trip
      const raw =
          '{"id":"N_123","storeId":"store_001","type":"order_created","targetRoute":"invoice_detail","targetId":"HD100"}';
      final parsed = NotificationPayload.tryParse(raw);
      expect(parsed, isNotNull);
      expect(parsed!.id, equals('N_123'));
      expect(parsed.storeId, equals('store_001'));
      expect(parsed.type, equals('order_created'));
      expect(parsed.targetRoute, equals('invoice_detail'));
      expect(parsed.targetId, equals('HD100'));

      final jsonRoundTrip = parsed.toJsonString();
      final parsedAgain = NotificationPayload.tryParse(jsonRoundTrip);
      expect(parsedAgain!.id, equals('N_123'));
      expect(parsedAgain.targetId, equals('HD100'));
    });
  });

  // ==========================================================================
  // SECTION 3: UI CONCURRENCY & WIDGET HARDENING
  // ==========================================================================
  group('=== TIER 5: SECTION 3 - UI CONCURRENCY & WIDGET HARDENING ===', () {
    testWidgets(
        'T5.18: Rapid simultaneous dismissals on Dismissible remove items without key collisions or crash',
        (tester) async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(id: 'N1', title: 'Đơn hàng 1'),
        makeNotification(id: 'N2', title: 'Đơn hàng 2'),
        makeNotification(id: 'N3', title: 'Đơn hàng 3'),
      ]);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWithValue(repo),
          ],
          child: const NotificationsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đơn hàng 1'), findsOneWidget);
      expect(find.text('Đơn hàng 2'), findsOneWidget);
      expect(find.text('Đơn hàng 3'), findsOneWidget);

      // Dismiss N1
      await tester.drag(
        find.byKey(const Key('dismissible_N1')),
        const Offset(-500.0, 0.0),
      );
      await tester.pumpAndSettle();

      // Dismiss N2
      await tester.drag(
        find.byKey(const Key('dismissible_N2')),
        const Offset(-500.0, 0.0),
      );
      await tester.pumpAndSettle();

      // N1 and N2 are cleanly removed; N3 remains
      expect(find.text('Đơn hàng 1'), findsNothing);
      expect(find.text('Đơn hàng 2'), findsNothing);
      expect(find.text('Đơn hàng 3'), findsOneWidget);

      expect(repo.deletedIds, containsAll(['N1', 'N2']));
    });

    testWidgets(
        'T5.19: Dismissal Undo functionality restores notification locally and re-adds to repository',
        (tester) async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(id: 'N_UNDO', title: 'Thông báo cần hoàn tác'),
      ]);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWithValue(repo),
          ],
          child: const NotificationsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thông báo cần hoàn tác'), findsOneWidget);

      // Swipe to delete
      await tester.drag(
        find.byKey(const Key('dismissible_N_UNDO')),
        const Offset(-500.0, 0.0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thông báo cần hoàn tác'), findsNothing);
      expect(repo.deletedIds, contains('N_UNDO'));

      // Find and tap Undo button on SnackBar
      final undoButton = find.text('Hoàn tác');
      expect(undoButton, findsOneWidget);
      await tester.tap(undoButton);
      await tester.pumpAndSettle();

      // Notification is restored back into the list
      expect(find.text('Thông báo cần hoàn tác'), findsOneWidget);
      expect(repo.addedItems.any((i) => i.id == 'N_UNDO'), isTrue);
    });

    testWidgets(
        'T5.20: Rapid category filter cycling under streaming updates maintains UI consistency without race conditions',
        (tester) async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(
            id: 'N_ORD',
            title: 'Hóa đơn A',
            type: NotificationType.orderCreated),
        makeNotification(
            id: 'N_INV',
            title: 'Nhập kho B',
            type: NotificationType.inventoryImported),
        makeNotification(
            id: 'N_CUST',
            title: 'Khách hàng C',
            type: NotificationType.customerCreated),
      ]);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWithValue(repo),
          ],
          child: const NotificationsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // All tab: all 3 items visible
      expect(find.text('Hóa đơn A'), findsOneWidget);
      expect(find.text('Nhập kho B'), findsOneWidget);
      expect(find.text('Khách hàng C'), findsOneWidget);

      // 1. Filter Orders
      await tester.tap(find.byKey(const Key('notification_chip_orders')));
      await tester.pumpAndSettle();
      expect(find.text('Hóa đơn A'), findsOneWidget);
      expect(find.text('Nhập kho B'), findsNothing);
      expect(find.text('Khách hàng C'), findsNothing);

      // Stream emits new Inventory item while Orders is selected
      repo.items.add(makeNotification(
        id: 'N_INV_2',
        title: 'Nhập kho mới',
        type: NotificationType.inventoryImported,
      ));
      repo.emitCurrent();
      await tester.pumpAndSettle();
      expect(find.text('Hóa đơn A'), findsOneWidget);
      expect(find.text('Nhập kho mới'), findsNothing); // Filtered out

      // 2. Filter Inventory
      await tester.tap(find.byKey(const Key('notification_chip_inventory')));
      await tester.pumpAndSettle();
      expect(find.text('Nhập kho B'), findsOneWidget);
      expect(find.text('Nhập kho mới'), findsOneWidget);
      expect(find.text('Hóa đơn A'), findsNothing);

      // 3. Filter Customers
      await tester.tap(find.byKey(const Key('notification_chip_customers')));
      await tester.pumpAndSettle();
      expect(find.text('Khách hàng C'), findsOneWidget);
      expect(find.text('Nhập kho B'), findsNothing);

      // 4. Back to All
      await tester.tap(find.byKey(const Key('notification_chip_all')));
      await tester.pumpAndSettle();
      expect(find.text('Hóa đơn A'), findsOneWidget);
      expect(find.text('Nhập kho B'), findsOneWidget);
      expect(find.text('Khách hàng C'), findsOneWidget);
      expect(find.text('Nhập kho mới'), findsOneWidget);
    });

    testWidgets(
        'T5.21: Category filter empty state renders localized description when zero items match filter',
        (tester) async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(
          id: 'N_ORD',
          title: 'Hóa đơn duy nhất',
          type: NotificationType.orderCreated,
        ),
      ]);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWithValue(repo),
          ],
          child: const NotificationsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Customers filter (0 customer notifications exist)
      await tester.tap(find.byKey(const Key('notification_chip_customers')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_empty_state')), findsOneWidget);
      expect(find.text('Không có thông báo nào'), findsOneWidget);
    });

    testWidgets(
        'T5.22: Deep link navigation with unmounting context aborts safely without crash',
        (tester) async {
      final repo = _AdversarialNotificationRepository();
      repo.markAsReadCompleter = Completer<void>(); // Hold markAsRead in-flight

      final orderRepo = _AdversarialOrderRepository();

      bool isMounted = true;

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWithValue(repo),
            orderRepositoryProvider.overrideWithValue(orderRepo),
          ],
          child: StatefulBuilder(
            builder: (context, setState) {
              if (!isMounted) return const SizedBox.shrink();

              return Consumer(
                builder: (ctx, ref, _) {
                  return ElevatedButton(
                    key: const Key('btn_trigger_tap'),
                    onPressed: () async {
                      await NotificationNavigationHandler.handleTap(
                        context: ctx,
                        ref: ref,
                        notification: makeNotification(
                          id: 'N_UNMOUNT',
                          isRead: false,
                          targetRoute: 'invoice_detail',
                          targetId: 'HD_SLOW',
                        ),
                      );
                    },
                    child: const Text('Tap'),
                  );
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger tap
      await tester.tap(find.byKey(const Key('btn_trigger_tap')));
      await tester.pump();

      // Unmount widget while markAsRead is pending
      isMounted = false;
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWithValue(repo),
            orderRepositoryProvider.overrideWithValue(orderRepo),
          ],
          child: const SizedBox.shrink(),
        ),
      );

      // Now complete markAsRead
      repo.markAsReadCompleter!.complete();
      await tester.pumpAndSettle();

      // Navigation was aborted safely: order lookup was never invoked
      expect(orderRepo.fetchCount, equals(0));
    });

    testWidgets(
        'T5.23: Deep link navigation to Order Detail marks notification read and opens InvoiceDetailBottomSheet',
        (tester) async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(
          id: 'N_ORD_TAP',
          isRead: false,
          targetRoute: 'invoice_detail',
          targetId: 'HD100',
        ),
      ]);

      final dummyOrder = Order(
        id: 'HD100',
        customerId: 'CUST_1',
        customerName: 'Nguyễn Văn Đơn',
        createdAt: DateTime.now(),
        items: [
          OrderItem(
            productId: 'P1',
            productName: 'Bột giặt OMO',
            quantity: 2,
            price: 50000,
            originalPrice: 60000,
            discount: 10000,
            warrantyMonths: 0,
            purchaseDate: DateTime.utc(2026, 10, 4),
          ),
        ],
        total: 100000,
      );

      final orderRepo = _AdversarialOrderRepository();
      orderRepo.orderToReturn = dummyOrder;

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWithValue(repo),
            orderRepositoryProvider.overrideWithValue(orderRepo),
          ],
          child: const NotificationsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap card
      await tester.tap(find.byKey(const Key('notification_card_N_ORD_TAP')));
      await tester.pumpAndSettle();

      // Marked read
      expect(repo.markedReadIds, contains('N_ORD_TAP'));

      // Bottom sheet opened
      expect(find.byType(InvoiceDetailBottomSheet), findsOneWidget);
      expect(find.text('Bột giặt OMO'), findsOneWidget);
    });

    testWidgets(
        'T5.24: Deep link navigation to Return Order Detail opens ReturnOrderDetailBottomSheet',
        (tester) async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(
          id: 'N_RET_TAP',
          isRead: false,
          type: NotificationType.orderReturn,
          targetRoute: 'invoice_detail',
          targetId: 'HD_RET',
        ),
      ]);

      final returnedOrder = Order(
        id: 'HD_RET',
        customerId: 'CUST_1',
        createdAt: DateTime.now(),
        items: const [],
        total: 100000,
        status: 'returned',
      );

      final orderRepo = _AdversarialOrderRepository();
      orderRepo.orderToReturn = returnedOrder;

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWithValue(repo),
            orderRepositoryProvider.overrideWithValue(orderRepo),
          ],
          child: const NotificationsPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notification_card_N_RET_TAP')));
      await tester.pumpAndSettle();

      expect(find.byType(ReturnOrderDetailBottomSheet), findsOneWidget);
    });

    testWidgets(
        'T5.25: Deep link navigation to Stock-In Detail opens StockInReceiptDetailBottomSheet',
        (tester) async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(
          id: 'N_STK_TAP',
          isRead: false,
          type: NotificationType.inventoryImported,
          targetRoute: 'stock_in_detail',
          targetId: 'NK999',
        ),
      ]);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWithValue(repo),
            stockInReceiptByIdProvider('NK999').overrideWith((ref) => null),
          ],
          child: const NotificationsPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notification_card_N_STK_TAP')));
      await tester.pumpAndSettle();

      expect(find.byType(StockInReceiptDetailBottomSheet), findsOneWidget);
      expect(repo.markedReadIds, contains('N_STK_TAP'));
    });

    testWidgets(
        'T5.26: Deep link navigation to Customer Debt & Detail with fallback metadata resilience',
        (tester) async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(
          id: 'N_DEBT_TAP',
          isRead: false,
          type: NotificationType.customerDebtAdded,
          targetRoute: 'customer_debt',
          targetId: 'CUST_DEBT_1',
          metadata: {
            'customerName': 'Khách Nợ A',
            'phone': '0911222333',
          },
        ),
      ]);

      final custRepo = _AdversarialCustomerRepository();
      custRepo.customerToReturn = null; // Customer not found in DB

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWithValue(repo),
            customerRepositoryProvider.overrideWithValue(custRepo),
            customerOrdersProvider('CUST_DEBT_1')
                .overrideWith((ref) => Stream.value([])),
            customerDebtTransactionsProvider('CUST_DEBT_1')
                .overrideWith((ref) => Stream.value([])),
          ],
          child: const NotificationsPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notification_card_N_DEBT_TAP')));
      await tester.pumpAndSettle();

      // Fallback customer constructed and CustomerDebtPage opened
      expect(find.byType(CustomerDebtPage), findsOneWidget);
      expect(find.textContaining('Khách Nợ A'), findsOneWidget);
    });

    testWidgets(
        'T5.27: Deep link navigation with missing targetId marks as read without throwing or invalid navigation',
        (tester) async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(
          id: 'N_NO_TARGET',
          isRead: false,
          targetRoute: 'invoice_detail',
          targetId: '', // Empty targetId
        ),
      ]);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWithValue(repo),
          ],
          child: const NotificationsPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notification_card_N_NO_TARGET')));
      await tester.pumpAndSettle();

      expect(repo.markedReadIds, contains('N_NO_TARGET'));
      expect(find.byType(InvoiceDetailBottomSheet), findsNothing);
    });

    testWidgets(
        'T5.28: Deep link navigation when order not found displays error SnackBar safely',
        (tester) async {
      final repo = _AdversarialNotificationRepository([
        makeNotification(
          id: 'N_NOT_FOUND',
          isRead: false,
          targetRoute: 'invoice_detail',
          targetId: 'HD_MISSING',
        ),
      ]);

      final orderRepo = _AdversarialOrderRepository();
      orderRepo.orderToReturn = null; // Order doesn't exist

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _AdversarialAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWithValue(repo),
            orderRepositoryProvider.overrideWithValue(orderRepo),
          ],
          child: const NotificationsPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notification_card_N_NOT_FOUND')));
      await tester.pumpAndSettle();

      expect(find.text('Không tìm thấy thông tin đơn hàng #HD_MISSING'),
          findsOneWidget);
    });

    testWidgets(
        'T5.29: NotificationBellAction reactive badge & RBAC boundaries',
        (tester) async {
      final repo = _AdversarialNotificationRepository();
      final authNotifier = _AdversarialAuthNotifier(staffUser);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            notificationRepositoryProvider.overrideWithValue(repo),
          ],
          child: const NotificationBellAction(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Staff user: returns SizedBox.shrink()
      expect(find.byKey(const Key('notification_bell_action_button')),
          findsNothing);

      // 2. Promote to Admin with 0 unread: Bell action visible, badge hidden
      authNotifier.setUser(adminUser);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_action_button')),
          findsOneWidget);
      final badgeWidgetZero = tester.widget<Badge>(find.byType(Badge));
      expect(badgeWidgetZero.isLabelVisible, isFalse);

      // 3. Admin with 99 unread: badge label '99'
      repo.emitItems(List.generate(
        99,
        (i) => makeNotification(id: 'N_$i', isRead: false),
      ));
      await tester.pumpAndSettle();

      expect(find.text('99'), findsOneWidget);

      // 4. Admin with 100 unread: badge label '99+'
      repo.emitItems(List.generate(
        100,
        (i) => makeNotification(id: 'N_$i', isRead: false),
      ));
      await tester.pumpAndSettle();

      expect(find.text('99+'), findsOneWidget);

      // 5. Tap bell opens notifications page
      await tester.tap(find.byKey(const Key('notification_bell_action_button')));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsPage), findsOneWidget);
    });

    testWidgets(
        'T5.30: NotificationCard relative time formatting boundaries across time deltas',
        (tester) async {
      final now = DateTime.now();

      await tester.pumpWidget(
        _buildTestApp(
          child: Column(
            children: [
              NotificationCard(
                item: makeNotification(
                  id: 'T1',
                  createdAt: now.subtract(const Duration(seconds: 10)),
                ),
              ),
              NotificationCard(
                item: makeNotification(
                  id: 'T2',
                  createdAt: now.subtract(const Duration(minutes: 5)),
                ),
              ),
              NotificationCard(
                item: makeNotification(
                  id: 'T3',
                  createdAt: now.subtract(const Duration(hours: 3)),
                ),
              ),
              NotificationCard(
                item: makeNotification(
                  id: 'T4',
                  createdAt: now.subtract(const Duration(days: 2)),
                ),
              ),
              NotificationCard(
                item: makeNotification(
                  id: 'T5',
                  createdAt: DateTime(2026, 1, 15, 10, 30),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vừa xong'), findsOneWidget);
      expect(find.text('5 phút trước'), findsOneWidget);
      expect(find.text('3 giờ trước'), findsOneWidget);
      expect(find.text('2 ngày trước'), findsOneWidget);
      expect(find.text('15/01/2026 10:30'), findsOneWidget);
    });
  });
}
