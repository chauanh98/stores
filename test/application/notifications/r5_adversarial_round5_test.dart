import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/notifications/fcm_service.dart';
import 'package:stores/application/notifications/local_notification_service.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/data/datasources/firebase/fcm_remote_data_source.dart';
import 'package:stores/data/repositories/fcm_token_repository_impl.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/notification_item.dart';
import 'package:stores/domain/entities/notification_type.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/repositories/notification_repository.dart';

import '../../support/firebase_test_harness.dart';

class _FaultTolerantMockRepo implements NotificationRepository {
  final List<NotificationItem> added = [];
  bool shouldThrow = false;

  @override
  Future<void> addNotification(NotificationItem notification) async {
    if (shouldThrow) {
      throw Exception('Simulated RTDB quota exceeded / network timeout');
    }
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

class _SpyPushService implements PushNotificationService {
  final List<NotificationItem> synced = [];

  @override
  bool isInitialized = true;

  @override
  String? currentToken = 'token_test_123';

  @override
  Stream<RemoteMessage> get onMessage => const Stream.empty();

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Future<bool> initialize() async => true;

  @override
  Future<bool?> requestPermissions() async => true;

  @override
  Future<String?> getToken() async => currentToken;

  @override
  Future<void> registerAdminToken({
    required String storeId,
    required String userId,
  }) async {}

  @override
  Future<void> unregisterAdminToken({
    required String storeId,
    required String userId,
  }) async {}

  @override
  Future<void> syncPushNotification({
    required String storeId,
    required NotificationItem notification,
  }) async {
    synced.add(notification);
  }
}

class _SpyLocalNotificationService implements LocalNotificationService {
  final List<Map<String, dynamic>> shown = [];

  @override
  bool isInitialized = true;

  @override
  Stream<String?> get onNotificationTapped => const Stream.empty();

  @override
  Future<bool> initialize({NotificationTapCallback? onNotificationTapped}) async =>
      true;

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

void main() {
  group('Round 5 Adversarial Verification: Fallback Identifier Sanitization', () {
    late _FaultTolerantMockRepo mockRepo;
    late _SpyPushService spyPush;
    late NotificationDispatcher dispatcher;

    setUp(() {
      mockRepo = _FaultTolerantMockRepo();
      spyPush = _SpyPushService();
      dispatcher = NotificationDispatcher(mockRepo, spyPush);
    });

    test('1. notifyOrderUpdated with "null", "undefined", "none" originalOrderId falls back to order.id', () async {
      for (final invalidId in ['null', 'NULL', 'undefined', 'Undefined', 'none', '   ']) {
        final order = Order(
          id: 'HD_FALLBACK_01',
          customerId: 'KH01',
          customerName: 'Khách VIP',
          createdAt: DateTime.now(),
          items: const [],
          total: 500000.0,
        );

        await dispatcher.notifyOrderUpdated(
          storeId: 'store_001',
          order: order,
          originalOrderId: invalidId,
          user: null,
        );

        final notif = mockRepo.added.last;
        expect(notif.title, equals('Sửa hóa đơn #HD_FALLBACK_01'));
        expect(notif.metadata?['originalOrderId'], equals('HD_FALLBACK_01'));
        expect(notif.title, isNot(contains('#null')));
        expect(notif.title, isNot(contains('#undefined')));
      }
    });

    test('2. notifyOrderReturned with "null" or blank orderId falls back to returnOrder.id', () async {
      for (final invalidId in ['null', 'undefined', 'none', '  ']) {
        final ret = ReturnOrder(
          id: 'RET_ID_999',
          orderId: invalidId,
          customerId: 'KH02',
          customerName: 'Khách Trả',
          createdAt: DateTime.now(),
          totalReturnAmount: 150000.0,
          storeId: 'store_001',
          items: const [],
        );

        await dispatcher.notifyOrderReturned(
          storeId: 'store_001',
          returnOrder: ret,
          user: null,
        );

        final notif = mockRepo.added.last;
        expect(notif.title, equals('Đơn trả hàng #RET_ID_999'));
        expect(notif.targetId, equals('RET_ID_999'));
        expect(notif.title, isNot(contains('#null')));
      }
    });

    test('3. notifyStockInCompleted with "null" or blank importCode falls back to receipt.id', () async {
      for (final invalidCode in ['null', 'undefined', 'none', '']) {
        final receipt = StockInReceipt(
          id: 'RECEIPT_FALLBACK_ID',
          importCode: invalidCode,
          supplierId: 'NCC01',
          supplierName: 'Đại Lý Phân Phối',
          date: DateTime.now(),
          createdAt: DateTime.now(),
          totalAmount: 2000000.0,
          storeId: 'store_001',
          items: const [],
        );

        await dispatcher.notifyStockInCompleted(
          storeId: 'store_001',
          receipt: receipt,
          user: null,
        );

        final notif = mockRepo.added.last;
        expect(notif.title, equals('Phiếu nhập kho #RECEIPT_FALLBACK_ID'));
        expect(notif.targetId, equals('RECEIPT_FALLBACK_ID'));
        expect(notif.title, isNot(contains('#null')));
      }
    });

    test('4. notifyCustomerDebtAdded with "null" or blank orderId falls back to "---"', () async {
      for (final invalidId in ['null', 'undefined', 'none', '   ']) {
        await dispatcher.notifyCustomerDebtAdded(
          storeId: 'store_001',
          customerId: 'KH_DEBT_01',
          customerName: 'Anh Bình',
          debtAmount: 300000.0,
          orderId: invalidId,
          user: null,
        );

        final notif = mockRepo.added.last;
        expect(notif.body, contains('từ đơn #---'));
        expect(notif.body, isNot(contains('từ đơn #null')));
        expect(notif.metadata?['orderId'], equals('---'));
      }
    });

    test('5. notifyCustomerCreated with case-insensitive "NONE" or "Null" phone falls back to "---"', () async {
      for (final badPhone in ['None', 'NONE', 'Null', 'NULL', 'undefined', '   ']) {
        final cust = Customer(
          id: 'CUST_BAD_PHONE',
          name: 'Chị Mai',
          phone: badPhone,
          email: '',
          address: '',
          purchases: const [],
        );

        await dispatcher.notifyCustomerCreated(
          storeId: 'store_001',
          customer: cust,
          user: null,
        );

        final notif = mockRepo.added.last;
        expect(notif.body, contains('SĐT: ---'));
        expect(notif.metadata?['phone'], equals('---'));
      }
    });

    test('6. RTDB addNotification failure does NOT suppress FCM push sync delivery', () async {
      mockRepo.shouldThrow = true; // Simulate RTDB connection error or quota drop

      final order = Order(
        id: 'HD_PUSH_RESILIENT',
        customerId: 'default',
        customerName: 'Khách lẻ',
        createdAt: DateTime.now(),
        items: const [],
        total: 750000.0,
      );

      // Must complete without unhandled exception
      await dispatcher.notifyOrderCreated(
        storeId: 'store_001',
        order: order,
        user: null,
      );

      // FCM push delivery was still triggered!
      expect(spyPush.synced.length, equals(1));
      expect(spyPush.synced.first.title, equals('Đơn hàng mới #HD_PUSH_RESILIENT'));
      expect(spyPush.synced.first.body, contains('750.000đ'));
    });
  });

  group('Round 5 Adversarial Verification: Payload Normalization & Safe Notification IDs', () {
    test('1. queuePushNotification completely omits null targetRoute and targetId from root map', () async {
      final mockDb = MockFirebaseDatabase();
      final remoteDs = FcmRemoteDataSource(mockDb);
      final repo = FcmTokenRepositoryImpl(remoteDs);

      final notif = NotificationItem(
        id: 'NOTIF_CLEAN_ROOT',
        storeId: 'store_001',
        title: 'Thông báo',
        body: 'Nội dung',
        type: NotificationType.orderCreated,
        createdAt: DateTime.now(),
        targetRoute: null,
        targetId: null,
      );

      await repo.queuePushNotification(
        storeId: 'store_001',
        notification: notif,
        targetTokens: ['token_1'],
      );

      final snap = await mockDb.getOrCreateRef('stores/store_001/fcm_queue').get();
      final payload = (snap.value as Map).values.first as Map;

      expect(payload.containsKey('targetRoute'), isFalse);
      expect(payload.containsKey('targetId'), isFalse);
      expect(payload['data'].containsKey('targetRoute'), isFalse);
      expect(payload['data'].containsKey('targetId'), isFalse);
    });

    test('2. handleFcmBackgroundMessage cleanly parses snake_case payload keys (store_id, target_route, target_id)', () async {
      final spyLocal = _SpyLocalNotificationService();
      const message = RemoteMessage(
        messageId: 'fcm_snake_case',
        data: {
          'title': 'Đơn hàng mới #HD555',
          'body': '250.000đ - Khách: Khách lẻ',
          'store_id': 'store_002',
          'target_route': 'invoice_detail',
          'target_id': 'HD555',
        },
      );

      await handleFcmBackgroundMessage(message, localNotificationService: spyLocal);

      expect(spyLocal.shown.length, equals(1));
      final rawPayload = spyLocal.shown.first['payload'] as String;
      final parsed = NotificationPayload.tryParse(rawPayload);

      expect(parsed, isNotNull);
      expect(parsed!.storeId, equals('store_002'));
      expect(parsed.targetRoute, equals('invoice_detail'));
      expect(parsed.targetId, equals('HD555'));
    });

    test('3. NotificationPayload.tryParse parses snake_case keys and alternate notificationId', () {
      const rawJson = '{"notificationId":"NID_123","store_id":"store_001","target_route":"invoice_detail","target_id":"HD123"}';
      final parsed = NotificationPayload.tryParse(rawJson);

      expect(parsed, isNotNull);
      expect(parsed!.id, equals('NID_123'));
      expect(parsed.storeId, equals('store_001'));
      expect(parsed.targetRoute, equals('invoice_detail'));
      expect(parsed.targetId, equals('HD123'));
    });

    test('4. NotificationPayload.tryParse safely handles case-insensitive "NONE" and "NULL"', () {
      const rawJson = '{"id":"NONE","storeId":"NULL","targetRoute":"undefined","targetId":"none"}';
      final parsed = NotificationPayload.tryParse(rawJson);

      expect(parsed, isNotNull);
      expect(parsed!.id, equals(''));
      expect(parsed.storeId, equals(''));
      expect(parsed.targetRoute, isNull);
      expect(parsed.targetId, isNull);
    });
  });
}
