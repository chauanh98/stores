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
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/notification_repository.dart';

import '../../support/firebase_test_harness.dart';

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
  group('Round 4 Adversarial Verification: Third-Party FCM Payload Sanitization', () {
    late _SpyLocalNotificationService spyLocal;

    setUp(() {
      spyLocal = _SpyLocalNotificationService();
    });

    test('1. Literal "null" and "undefined" in both title and body cleanly skips notification', () async {
      const message1 = RemoteMessage(
        messageId: 'fcm_null_msg',
        data: {
          'title': 'null',
          'body': 'null',
        },
      );
      await handleFcmBackgroundMessage(message1, localNotificationService: spyLocal);
      expect(spyLocal.shown, isEmpty);

      const message2 = RemoteMessage(
        messageId: 'fcm_undef_msg',
        data: {
          'title': 'undefined',
          'body': 'undefined',
        },
      );
      await handleFcmBackgroundMessage(message2, localNotificationService: spyLocal);
      expect(spyLocal.shown, isEmpty);
    });

    test('2. Literal "null" title with valid body falls back to default store title', () async {
      const message = RemoteMessage(
        messageId: 'fcm_null_title',
        data: {
          'title': 'null',
          'body': 'Đơn hàng mới #HD123: 500.000đ',
        },
      );
      await handleFcmBackgroundMessage(message, localNotificationService: spyLocal);
      expect(spyLocal.shown.length, equals(1));
      expect(spyLocal.shown.first['title'], equals('Thông báo cửa hàng'));
      expect(spyLocal.shown.first['body'], equals('Đơn hàng mới #HD123: 500.000đ'));
    });

    test('3. Data title/body equal to "null" falls back to RemoteMessage.notification object', () async {
      const message = RemoteMessage(
        messageId: 'fcm_fallback_to_notif',
        data: {
          'title': 'null',
          'body': 'null',
        },
        notification: RemoteNotification(
          title: 'Đơn hàng mới #HD999',
          body: '1.200.000đ - Khách: Nguyễn Văn A (Tạo bởi: Lan)',
        ),
      );
      await handleFcmBackgroundMessage(message, localNotificationService: spyLocal);
      expect(spyLocal.shown.length, equals(1));
      expect(spyLocal.shown.first['title'], equals('Đơn hàng mới #HD999'));
      expect(spyLocal.shown.first['body'], equals('1.200.000đ - Khách: Nguyễn Văn A (Tạo bởi: Lan)'));
    });

    test('4. NotificationPayload.tryParse sanitizes literal "null" and "undefined" strings', () {
      const rawJson = '{"id":"null","storeId":"null","type":"null","targetRoute":"null","targetId":"undefined"}';
      final payload = NotificationPayload.tryParse(rawJson);
      expect(payload, isNotNull);
      expect(payload!.id, equals(''));
      expect(payload.storeId, equals(''));
      expect(payload.type, isNull);
      expect(payload.targetRoute, isNull);
      expect(payload.targetId, isNull);
    });
  });

  group('Round 4 Adversarial Verification: RTDB FCM Token Extraction Robustness', () {
    late MockFirebaseDatabase mockDb;
    late FcmRemoteDataSource remoteDataSource;
    const storeId = 'store_001';

    setUp(() {
      mockDb = MockFirebaseDatabase();
      remoteDataSource = FcmRemoteDataSource(mockDb);
    });

    test('1. Extracts tokens when user entry is a List/Iterable in RTDB', () async {
      final ref = mockDb.getOrCreateRef('stores/$storeId/fcm_tokens');
      await ref.set({
        'admin_user_1': [
          {'token': 'fcm_token_list_1'},
          {'token': 'fcm_token_list_2'},
        ],
        'admin_user_2': {
          'device_1': {'token': 'fcm_token_map_1'},
        },
      });

      final tokens = await remoteDataSource.getAdminTokens(storeId: storeId);
      expect(tokens, contains('fcm_token_list_1'));
      expect(tokens, contains('fcm_token_list_2'));
      expect(tokens, contains('fcm_token_map_1'));
      expect(tokens.length, equals(3));
    });

    test('2. Extracts tokens across alternative field keys (fcmToken, deviceToken, registrationToken)', () async {
      final ref = mockDb.getOrCreateRef('stores/$storeId/fcm_tokens');
      await ref.set({
        'admin_alt': {
          'entry_1': {'fcmToken': 'token_alt_1'},
          'entry_2': {'deviceToken': 'token_alt_2'},
          'entry_3': {'registrationToken': 'token_alt_3'},
        },
      });

      final tokens = await remoteDataSource.getAdminTokens(storeId: storeId);
      expect(tokens, contains('token_alt_1'));
      expect(tokens, contains('token_alt_2'));
      expect(tokens, contains('token_alt_3'));
      expect(tokens.length, equals(3));
    });

    test('3. Filters out corrupted tokens ("null", "undefined", empty strings)', () async {
      final ref = mockDb.getOrCreateRef('stores/$storeId/fcm_tokens');
      await ref.set({
        'admin_corrupt': {
          'entry_1': {'token': 'null'},
          'entry_2': {'token': 'undefined'},
          'entry_3': {'token': '   '},
          'entry_4': 'null',
          'entry_5': 'undefined',
          'entry_6': {'token': 'valid_token_abc'},
        },
      });

      final tokens = await remoteDataSource.getAdminTokens(storeId: storeId);
      expect(tokens, equals(['valid_token_abc']));
    });

    test('4. Extracts tokens when root storeTokens node is an array (sequential keys)', () async {
      final ref = mockDb.getOrCreateRef('stores/$storeId/fcm_tokens');
      await ref.set([
        {
          'dev_1': {'token': 'token_from_array_root'},
        },
      ]);

      final tokens = await remoteDataSource.getAdminTokens(storeId: storeId);
      expect(tokens, contains('token_from_array_root'));
    });
  });

  group('Round 4 Adversarial Verification: NotificationDispatcher Null/Undefined Sanitization', () {
    late _MockNotificationRepository mockRepo;
    late NotificationDispatcher dispatcher;

    setUp(() {
      mockRepo = _MockNotificationRepository();
      dispatcher = NotificationDispatcher(mockRepo);
    });

    test('1. notifyOrderCreated with "null" customerName falls back to Khách lẻ', () async {
      final order = Order(
        id: 'HD_NULL_CUST',
        customerId: 'null',
        customerName: 'null',
        createdAt: DateTime.now(),
        items: const [],
        total: 100000.0,
      );

      await dispatcher.notifyOrderCreated(
        storeId: 'store_001',
        order: order,
        user: const UserAccount(
          username: 'cashier',
          displayName: 'null',
          role: 'nhanvien',
          storeId: 'store_001',
        ),
      );

      expect(mockRepo.added.isNotEmpty, isTrue);
      final notif = mockRepo.added.last;
      expect(notif.metadata?['customerName'], equals('Khách lẻ'));
      expect(notif.metadata?['customerId'], equals('default'));
      expect(notif.body, contains('Khách: Khách lẻ'));
      expect(notif.body, isNot(contains('Khách: null')));
      expect(notif.body, isNot(contains('Tạo bởi: null')));
    });

    test('2. notifyOrderUpdated with blank originalOrderId falls back to order.id', () async {
      final order = Order(
        id: 'HD_UPD_NEW',
        customerId: 'KH01',
        customerName: 'Nguyễn Văn A',
        createdAt: DateTime.now(),
        items: const [],
        total: 200000.0,
      );

      await dispatcher.notifyOrderUpdated(
        storeId: 'store_001',
        order: order,
        originalOrderId: '   ',
        user: null,
      );

      expect(mockRepo.added.isNotEmpty, isTrue);
      final notif = mockRepo.added.last;
      expect(notif.title, equals('Sửa hóa đơn #HD_UPD_NEW'));
      expect(notif.title, isNot(equals('Sửa hóa đơn #')));
      expect(notif.metadata?['originalOrderId'], equals('HD_UPD_NEW'));
    });

    test('3. notifyOrderCancelled with "null" reason falls back to "Không có lý do"', () async {
      final order = Order(
        id: 'HD_CAN_NULL',
        customerId: 'KH01',
        customerName: 'Nguyễn Văn A',
        createdAt: DateTime.now(),
        items: const [],
        total: 150000.0,
      );

      await dispatcher.notifyOrderCancelled(
        storeId: 'store_001',
        order: order,
        cancelReason: 'null',
        user: null,
      );

      expect(mockRepo.added.isNotEmpty, isTrue);
      final notif = mockRepo.added.last;
      expect(notif.body, contains('Lý do: Không có lý do'));
      expect(notif.body, isNot(contains('Lý do: null')));
      expect(notif.metadata?['reason'], equals('Không có lý do'));
    });

    test('4. notifyCustomerCreated with phone "null" or "undefined" falls back to "---"', () async {
      const customer = Customer(
        id: 'CUST_NULL_PH',
        name: 'Trần Văn B',
        phone: 'undefined',
        email: '',
        address: '',
        purchases: [],
      );

      await dispatcher.notifyCustomerCreated(
        storeId: 'store_001',
        customer: customer,
        user: null,
      );

      expect(mockRepo.added.isNotEmpty, isTrue);
      final notif = mockRepo.added.last;
      expect(notif.body, contains('SĐT: ---'));
      expect(notif.body, isNot(contains('SĐT: undefined')));
      expect(notif.metadata?['phone'], equals('---'));
    });

    test('5. notifyStockInCompleted with supplierName "null" falls back to "Nhà cung cấp lẻ"', () async {
      final receipt = StockInReceipt(
        id: 'REC_NULL_SUP',
        importCode: 'NK_NULL_01',
        supplierId: 'null',
        supplierName: 'null',
        date: DateTime.now(),
        createdAt: DateTime.now(),
        totalAmount: 3000000.0,
        storeId: 'store_001',
        items: const [],
      );

      await dispatcher.notifyStockInCompleted(
        storeId: 'store_001',
        receipt: receipt,
        user: null,
      );

      expect(mockRepo.added.isNotEmpty, isTrue);
      final notif = mockRepo.added.last;
      expect(notif.body, contains('NCC: Nhà cung cấp lẻ'));
      expect(notif.body, isNot(contains('NCC: null')));
      expect(notif.metadata?['supplierName'], equals('Nhà cung cấp lẻ'));
    });
  });

  group('Round 4 Adversarial Verification: APNs and FCM Data Payload Integrity', () {
    test('1. queuePushNotification includes APNs high-priority alert config and omits null fields in data', () async {
      final mockDb = MockFirebaseDatabase();
      final remoteDs = FcmRemoteDataSource(mockDb);
      final repo = FcmTokenRepositoryImpl(remoteDs);

      final notifWithoutRoute = NotificationItem(
        id: 'NOTIF_NO_ROUTE',
        storeId: 'store_001',
        title: 'Đơn hàng mới',
        body: '100.000đ - Khách: Khách lẻ',
        type: NotificationType.orderCreated,
        createdAt: DateTime.now(),
        targetRoute: null,
        targetId: null,
      );

      await repo.queuePushNotification(
        storeId: 'store_001',
        notification: notifWithoutRoute,
        targetTokens: ['token_123'],
      );

      final queueSnap = await mockDb.getOrCreateRef('stores/store_001/fcm_queue').get();
      expect(queueSnap.exists, isTrue);
      final queueMap = queueSnap.value as Map;
      final payload = queueMap.values.first as Map;

      // APNs config
      expect(payload['apns'], isNotNull);
      final apns = payload['apns'] as Map;
      expect(apns['headers']?['apns-priority'], equals('10'));
      expect(apns['headers']?['apns-push-type'], equals('alert'));
      expect(apns['payload']?['aps']?['sound'], equals('default'));
      expect(apns['payload']?['aps']?['content-available'], equals(1));

      // Data map should omit null targetRoute and targetId
      final data = payload['data'] as Map;
      expect(data.containsKey('targetRoute'), isFalse);
      expect(data.containsKey('targetId'), isFalse);
      expect(data['priority'], equals('high'));
      expect(data['sound'], equals('default'));
    });
  });
}
