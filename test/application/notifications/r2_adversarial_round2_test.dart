import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/notifications/local_notification_service.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/user_account.dart';

class _MockNotificationRepository implements NotificationRepository {
  final List<NotificationItem> added = [];

  @override
  Future<void> addNotification(NotificationItem notification) async {
    added.add(notification);
  }

  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {}

  @override
  Future<void> markAllAsRead(String storeId) async {}

  @override
  Future<void> markAsRead(
      {required String storeId, required String id}) async {}

  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
      {int limit = 50}) =>
      Stream.value(added);
}

class _SpyLocalNotificationService implements LocalNotificationService {
  final List<Map<String, dynamic>> shown = [];

  @override
  bool isInitialized = true;

  @override
  Stream<String?> get onNotificationTapped => const Stream.empty();

  @override
  Future<bool> initialize({NotificationTapCallback? onNotificationTapped}) async => true;

  @override
  Future<bool?> requestPermissions() async => true;

  @override
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    shown.add({
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
    });
  }

  @override
  Future<void> showFromNotificationItem(NotificationItem item) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}
}

class _TestAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _TestAuthNotifier([super.initialUser]);

  void setUser(UserAccount? user) => state = user;

  @override
  Future<void> logout() async => state = null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Round 2 Adversarial Verification: Whitespace Customer IDs & Fallbacks', () {
    late _MockNotificationRepository mockRepo;
    late NotificationDispatcher dispatcher;

    setUp(() {
      mockRepo = _MockNotificationRepository();
      dispatcher = NotificationDispatcher(mockRepo);
    });

    test('1. Whitespace customerId in notifyOrderCreated safely falls back to "default" and "Khách lẻ"', () async {
      final order = Order(
        id: 'HD_SPACE',
        customerId: '   ',
        customerName: null,
        createdAt: DateTime.now(),
        items: const [],
        total: 150000.0,
      );

      await dispatcher.notifyOrderCreated(
        storeId: 'store_001',
        order: order,
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.metadata?['customerId'], equals('default'));
      expect(notif.metadata?['customerName'], equals('Khách lẻ'));
      expect(notif.body, contains('Khách: Khách lẻ'));
      expect(notif.body, contains('Tạo bởi: Không xác định'));
    });

    test('2. Whitespace customerId in notifyOrderUpdated safely falls back', () async {
      final order = Order(
        id: 'HD_UPD_SPACE',
        customerId: '   ',
        customerName: '   ',
        createdAt: DateTime.now(),
        items: const [],
        total: 200000.0,
      );

      await dispatcher.notifyOrderUpdated(
        storeId: 'store_001',
        order: order,
        originalOrderId: 'HD_OLD',
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.metadata?['customerId'], equals('default'));
      expect(notif.metadata?['customerName'], equals('Khách lẻ'));
      expect(notif.body, contains('Khách: Khách lẻ'));
      expect(notif.body, contains('Bởi: Không xác định'));
    });

    test('3. Whitespace customerId in notifyOrderCancelled safely falls back', () async {
      final order = Order(
        id: 'HD_CAN_SPACE',
        customerId: '   ',
        customerName: '   ',
        createdAt: DateTime.now(),
        items: const [],
        total: 300000.0,
      );

      await dispatcher.notifyOrderCancelled(
        storeId: 'store_001',
        order: order,
        cancelReason: '   ',
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.metadata?['customerId'], equals('default'));
      expect(notif.metadata?['customerName'], equals('Khách lẻ'));
      expect(notif.metadata?['reason'], equals('Không có lý do'));
      expect(notif.body, contains('Khách: Khách lẻ'));
      expect(notif.body, contains('Bởi: Không xác định'));
    });

    test('4. Whitespace customerId in notifyOrderReturned safely falls back', () async {
      final returnOrder = ReturnOrder(
        id: 'TH_SPACE',
        orderId: 'HD_RET',
        customerId: '   ',
        customerName: '   ',
        storeId: 'store_001',
        createdAt: DateTime.now(),
        items: const [],
        totalReturnAmount: 75000.0,
      );

      await dispatcher.notifyOrderReturned(
        storeId: 'store_001',
        returnOrder: returnOrder,
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.metadata?['customerId'], equals('default'));
      expect(notif.metadata?['customerName'], equals('Khách lẻ'));
      expect(notif.body, contains('Khách: Khách lẻ'));
      expect(notif.body, contains('Xử lý: Không xác định'));
    });

    test('5. Whitespace supplierId in notifyStockInCompleted safely falls back', () async {
      final receipt = StockInReceipt(
        id: 'PN_SPACE',
        importCode: 'NK_SPACE',
        storeId: 'store_001',
        date: DateTime.now(),
        items: const [],
        supplierId: '   ',
        supplierName: '   ',
      );

      await dispatcher.notifyStockInCompleted(
        storeId: 'store_001',
        receipt: receipt,
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.metadata?['customerId'], equals('default'));
      expect(notif.metadata?['customerName'], equals('Nhà cung cấp lẻ'));
      expect(notif.metadata?['createdBy'], equals('Không xác định'));
      expect(notif.body, contains('NCC: Nhà cung cấp lẻ'));
      expect(notif.body, contains('Lập bởi: Không xác định'));
    });

    test('6. Whitespace customerId in notifyCustomerDebtAdded & Collected safely falls back', () async {
      await dispatcher.notifyCustomerDebtAdded(
        storeId: 'store_001',
        customerId: '   ',
        customerName: '   ',
        debtAmount: 50000.0,
        orderId: 'HD_DEBT',
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final addedNotif = mockRepo.added.first;
      expect(addedNotif.metadata?['customerId'], equals('default'));
      expect(addedNotif.metadata?['customerName'], equals('Khách lẻ'));
      expect(addedNotif.metadata?['createdBy'], equals('Không xác định'));
      expect(addedNotif.body, contains('Khách: Khách lẻ'));
      expect(addedNotif.body, contains('Bởi: Không xác định'));

      await dispatcher.notifyCustomerDebtCollected(
        storeId: 'store_001',
        customerId: '   ',
        customerName: '   ',
        collectedAmount: 50000.0,
        user: null,
      );

      expect(mockRepo.added.length, equals(2));
      final collectedNotif = mockRepo.added.last;
      expect(collectedNotif.metadata?['customerId'], equals('default'));
      expect(collectedNotif.metadata?['customerName'], equals('Khách lẻ'));
      expect(collectedNotif.metadata?['createdBy'], equals('Không xác định'));
      expect(collectedNotif.body, contains('từ khách Khách lẻ'));
      expect(collectedNotif.body, contains('Thu bởi: Không xác định'));
    });
  });

  group('Round 2 Adversarial Verification: Multi-Branch Session Cleanup & Background Handler', () {
    test('1. Admin multi-branch switching unregisters ALL session branches upon logout', () async {
      final fakePushService = FakePushNotificationService();
      const adminUser = UserAccount(
        username: 'admin_multi',
        displayName: 'Tổng Quản Lý',
        role: 'admin',
        storeId: 'all',
      );

      final authNotifier = _TestAuthNotifier();
      final storeNotifier = StateProvider<String>((ref) => 'store_001');

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          currentStoreIdProvider.overrideWith((ref) => ref.watch(storeNotifier)),
          pushNotificationServiceProvider.overrideWithValue(fakePushService),
        ],
      );
      addTearDown(container.dispose);

      // Start lifecycle manager
      container.read(fcmTokenLifecycleManagerProvider);

      // 1. Admin logs in with active branch store_001
      authNotifier.setUser(adminUser);
      expect(fakePushService.registeredOps.any((op) => op.storeId == 'store_001'), isTrue);

      // 2. Admin switches branch to store_002
      container.read(storeNotifier.notifier).state = 'store_002';
      await Future<void>.delayed(Duration.zero);
      expect(fakePushService.registeredOps.any((op) => op.storeId == 'store_002'), isTrue);

      // 3. Admin logs out -> must unregister BOTH store_001 AND store_002
      await authNotifier.logout();

      final unregisteredStores = fakePushService.unregisteredOps.map((op) => op.storeId).toSet();
      expect(unregisteredStores, contains('store_001'));
      expect(unregisteredStores, contains('store_002'));
    });

    test('2. handleFcmBackgroundMessage produces non-zero positive notifId and passes correct payload', () async {
      final spyLocal = _SpyLocalNotificationService();
      const remoteMessage = RemoteMessage(
        messageId: 'fcm_zero_hash_test',
        data: {
          'notificationId': 'NOTIF_CUSTOM_123',
          'storeId': 'store_002',
          'title': 'Đơn hàng mới #HD99',
          'body': 'Đơn hàng mới #HD99: 100.000đ cho khách Khách lẻ (Tạo bởi: Thu ngân Lan)',
          'type': 'order_created',
          'targetRoute': 'invoice_detail',
          'targetId': 'HD99',
        },
      );

      await handleFcmBackgroundMessage(remoteMessage, localNotificationService: spyLocal);

      expect(spyLocal.shown.length, equals(1));
      final shown = spyLocal.shown.first;
      expect(shown['id'], isA<int>());
      expect(shown['id'] as int, isPositive);
      expect(shown['title'], equals('Đơn hàng mới #HD99'));
      expect(shown['body'], contains('100.000đ'));
      expect(shown['body'], contains('Thu ngân Lan'));

      final payload = NotificationPayload.tryParse(shown['payload'] as String?);
      expect(payload, isNotNull);
      expect(payload!.id, equals('NOTIF_CUSTOM_123'));
      expect(payload.storeId, equals('store_002'));
      expect(payload.targetRoute, equals('invoice_detail'));
      expect(payload.targetId, equals('HD99'));
    });

    test('3. firebaseMessagingBackgroundHandler can be called directly without crash', () async {
      const msg = RemoteMessage(
        data: {
          'title': 'Test Background',
          'body': 'Content',
        },
      );
      // Top level function handles missing Firebase apps safely without uncaught throw
      await expectLater(firebaseMessagingBackgroundHandler(msg), completes);
    });
  });
}
