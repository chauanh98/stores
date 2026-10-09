import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/notifications/local_notification_service.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/presentation/notifications/utils/notification_navigation_handler.dart';

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

class _TestAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _TestAuthNotifier([super.initialUser]);

  void setUser(UserAccount? user) => state = user;

  @override
  Future<void> logout() async => state = null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockOrderRepository implements OrderRepository {
  @override
  Future<Order?> fetchById(String orderId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Round 3 Adversarial Verification: Retail Slug Leak Prevention', () {
    late _MockNotificationRepository mockRepo;
    late NotificationDispatcher dispatcher;

    setUp(() {
      mockRepo = _MockNotificationRepository();
      dispatcher = NotificationDispatcher(mockRepo);
    });

    final retailSlugs = [
      'khach_le',
      'walk_in',
      'retail',
      'KHACH_LE',
      'Walk_In',
      '   '
    ];

    for (final slug in retailSlugs) {
      test(
          '1. notifyOrderCreated with slug "$slug" resolves to "Khách lẻ" and "default"',
          () async {
        final order = Order(
          id: 'HD01',
          customerId: slug,
          customerName: null,
          createdAt: DateTime.now(),
          items: const [],
          total: 100000.0,
        );

        await dispatcher.notifyOrderCreated(
          storeId: 'store_001',
          order: order,
          user: const UserAccount(
            username: 'cashier',
            displayName: 'Thu ngân Lan',
            role: 'nhanvien',
            storeId: 'store_001',
          ),
        );

        expect(mockRepo.added.isNotEmpty, isTrue);
        final notif = mockRepo.added.last;
        expect(notif.metadata?['customerId'], equals('default'));
        expect(notif.metadata?['customerName'], equals('Khách lẻ'));
        expect(notif.body, contains('Khách: Khách lẻ'));
        if (slug.trim().isNotEmpty) {
          expect(notif.body, isNot(contains('Khách: ${slug.trim()}')));
        }
        expect(notif.body, contains('Tạo bởi: Thu ngân Lan'));
      });

      test('2. notifyOrderUpdated with slug "$slug" resolves to "Khách lẻ"',
          () async {
        final order = Order(
          id: 'HD02',
          customerId: slug,
          customerName: slug,
          createdAt: DateTime.now(),
          items: const [],
          total: 150000.0,
        );

        await dispatcher.notifyOrderUpdated(
          storeId: 'store_001',
          order: order,
          originalOrderId: 'HD_OLD',
          user: const UserAccount(
            username: 'manager',
            displayName: 'Quản lý Quân',
            role: 'supervisor',
            storeId: 'store_001',
          ),
        );

        final notif = mockRepo.added.last;
        expect(notif.metadata?['customerId'], equals('default'));
        expect(notif.metadata?['customerName'], equals('Khách lẻ'));
        expect(notif.body, contains('Khách: Khách lẻ'));
        expect(notif.body, contains('Bởi: Quản lý Quân'));
      });

      test('3. notifyOrderCancelled with slug "$slug" resolves to "Khách lẻ"',
          () async {
        final order = Order(
          id: 'HD03',
          customerId: slug,
          customerName: slug,
          createdAt: DateTime.now(),
          items: const [],
          total: 200000.0,
        );

        await dispatcher.notifyOrderCancelled(
          storeId: 'store_001',
          order: order,
          cancelReason: 'Khách không mua nữa',
          user: const UserAccount(
            username: 'admin',
            displayName: 'Admin Mai',
            role: 'admin',
            storeId: 'store_001',
          ),
        );

        final notif = mockRepo.added.last;
        expect(notif.metadata?['customerId'], equals('default'));
        expect(notif.metadata?['customerName'], equals('Khách lẻ'));
        expect(notif.body, contains('Khách: Khách lẻ'));
        expect(notif.body, contains('Bởi: Admin Mai'));
      });

      test('4. notifyOrderReturned with slug "$slug" resolves to "Khách lẻ"',
          () async {
        final returnOrder = ReturnOrder(
          id: 'RET01',
          orderId: 'HD_ORIG',
          customerId: slug,
          customerName: slug,
          createdAt: DateTime.now(),
          items: const [],
          totalReturnAmount: 80000.0,
          storeId: 'store_001',
        );

        await dispatcher.notifyOrderReturned(
          storeId: 'store_001',
          returnOrder: returnOrder,
          user: const UserAccount(
            username: 'clerk',
            displayName: 'Nhân viên Hùng',
            role: 'nhanvien',
            storeId: 'store_001',
          ),
        );

        final notif = mockRepo.added.last;
        expect(notif.metadata?['customerId'], equals('default'));
        expect(notif.metadata?['customerName'], equals('Khách lẻ'));
        expect(notif.body, contains('Khách: Khách lẻ'));
        expect(notif.body, contains('Xử lý: Nhân viên Hùng'));
      });

      test(
          '5. notifyCustomerDebtCollected with slug "$slug" resolves to "Khách lẻ"',
          () async {
        await dispatcher.notifyCustomerDebtCollected(
          storeId: 'store_001',
          customerId: slug,
          customerName: slug,
          collectedAmount: 50000.0,
          user: const UserAccount(
            username: 'cashier',
            displayName: 'Thu ngân Lan',
            role: 'nhanvien',
            storeId: 'store_001',
          ),
        );

        final notif = mockRepo.added.last;
        expect(notif.metadata?['customerId'], equals('default'));
        expect(notif.metadata?['customerName'], equals('Khách lẻ'));
        expect(notif.body, contains('từ khách Khách lẻ'));
        expect(notif.body, contains('Thu bởi: Thu ngân Lan'));
      });
    }

    test(
        '6. notifyStockInCompleted with "ncc_le" or "walk_in" supplier resolves to "Nhà cung cấp lẻ"',
        () async {
      final receipt = StockInReceipt(
        id: 'REC_001',
        importCode: 'NK001',
        supplierId: 'ncc_le',
        supplierName: 'ncc_le',
        date: DateTime.now(),
        createdAt: DateTime.now(),
        totalAmount: 5000000.0,
        storeId: 'store_001',
        items: const [],
      );

      await dispatcher.notifyStockInCompleted(
        storeId: 'store_001',
        receipt: receipt,
        user: const UserAccount(
          username: 'wh',
          displayName: 'Thủ kho Nam',
          role: 'supervisor',
          storeId: 'store_001',
        ),
      );

      final notif = mockRepo.added.last;
      expect(notif.metadata?['customerId'], equals('default'));
      expect(notif.metadata?['customerName'], equals('Nhà cung cấp lẻ'));
      expect(notif.metadata?['supplierName'], equals('Nhà cung cấp lẻ'));
      expect(notif.body, contains('NCC: Nhà cung cấp lẻ'));
      expect(notif.body, contains('Lập bởi: Thủ kho Nam'));
    });
  });

  group('Round 3 Adversarial Verification: All-Stores FCM Registration & Fanout',
      () {
    test('1. Admin in "all" store view registers BOTH canonical store branches',
        () async {
      final fakePushService = FakePushNotificationService();
      const adminUser = UserAccount(
        username: 'super_admin',
        displayName: 'Tổng Giám Đốc',
        role: 'admin',
        storeId: 'all',
      );

      final authNotifier = _TestAuthNotifier();
      final storeNotifier = StateProvider<String>((ref) => 'all');

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          currentStoreIdProvider
              .overrideWith((ref) => ref.watch(storeNotifier)),
          pushNotificationServiceProvider
              .overrideWithValue(fakePushService),
        ],
      );
      addTearDown(container.dispose);

      container.read(fcmTokenLifecycleManagerProvider);

      authNotifier.setUser(adminUser);
      await Future<void>.delayed(Duration.zero);

      final registeredStores =
          fakePushService.registeredOps.map((op) => op.storeId).toSet();
      expect(registeredStores, contains('store_001'));
      expect(registeredStores, contains('store_002'));

      // Logout unregisters BOTH
      await authNotifier.logout();
      await Future<void>.delayed(Duration.zero);

      final unregisteredStores =
          fakePushService.unregisteredOps.map((op) => op.storeId).toSet();
      expect(unregisteredStores, contains('store_001'));
      expect(unregisteredStores, contains('store_002'));
    });

    test(
        '2. handleFcmBackgroundMessage with custom Title and empty Body displays notification',
        () async {
      final spyLocal = _SpyLocalNotificationService();
      const remoteMessage = RemoteMessage(
        messageId: 'fcm_title_only',
        data: {
          'title': 'Cảnh báo tồn kho tối thiểu',
          'body': '',
          'storeId': 'store_001',
        },
      );

      await handleFcmBackgroundMessage(remoteMessage,
          localNotificationService: spyLocal);

      expect(spyLocal.shown.length, equals(1));
      expect(spyLocal.shown.first['title'], equals('Cảnh báo tồn kho tối thiểu'));
    });

    test(
        '3. handleFcmBackgroundMessage with zero Title and zero Body skips display cleanly',
        () async {
      final spyLocal = _SpyLocalNotificationService();
      const remoteMessage = RemoteMessage(
        messageId: 'fcm_empty_alert',
        data: {
          'title': '',
          'body': '',
        },
      );

      await handleFcmBackgroundMessage(remoteMessage,
          localNotificationService: spyLocal);

      expect(spyLocal.shown, isEmpty);
    });

    test(
        '4. handleFcmBackgroundMessage with notification.title equal to fallback title displays notification',
        () async {
      final spyLocal = _SpyLocalNotificationService();
      const remoteMessage = RemoteMessage(
        messageId: 'fcm_console_test',
        notification: RemoteNotification(
          title: 'Thông báo cửa hàng',
          body: '',
        ),
        data: {},
      );

      await handleFcmBackgroundMessage(remoteMessage,
          localNotificationService: spyLocal);

      expect(spyLocal.shown.length, equals(1));
      expect(spyLocal.shown.first['title'], equals('Thông báo cửa hàng'));
      expect(spyLocal.shown.first['body'], equals(''));
    });

    test(
        '5. handleFcmBackgroundMessage sanitizes literal "null" strings in data payload',
        () async {
      final spyLocal = _SpyLocalNotificationService();
      const remoteMessage = RemoteMessage(
        messageId: 'fcm_msg_123',
        data: {
          'title': 'Cập nhật hệ thống',
          'body': 'Đã hoàn tất sao lưu',
          'storeId': 'null',
          'notificationId': 'null',
          'id': 'null',
          'targetRoute': 'null',
        },
      );

      await handleFcmBackgroundMessage(remoteMessage,
          localNotificationService: spyLocal);

      expect(spyLocal.shown.length, equals(1));
      final shown = spyLocal.shown.first;
      expect(shown['title'], equals('Cập nhật hệ thống'));
      expect(shown['body'], equals('Đã hoàn tất sao lưu'));

      final payload = NotificationPayload.tryParse(shown['payload'] as String?);
      expect(payload, isNotNull);
      // storeId should be sanitized to empty string, not literal 'null'
      expect(payload!.storeId, equals(''));
      // id should fall back to messageId, not literal 'null'
      expect(payload.id, equals('fcm_msg_123'));
      // targetRoute should be null, not literal 'null'
      expect(payload.targetRoute, isNull);
    });

    test(
        '6. handleFcmBackgroundMessage with body only displays default fallback title',
        () async {
      final spyLocal = _SpyLocalNotificationService();
      const remoteMessage = RemoteMessage(
        messageId: 'fcm_body_only',
        notification: RemoteNotification(
          title: null,
          body: 'Nội dung kiểm tra hệ thống',
        ),
        data: {},
      );

      await handleFcmBackgroundMessage(remoteMessage,
          localNotificationService: spyLocal);

      expect(spyLocal.shown.length, equals(1));
      expect(spyLocal.shown.first['title'], equals('Thông báo cửa hàng'));
      expect(spyLocal.shown.first['body'], equals('Nội dung kiểm tra hệ thống'));
    });
  });

  group('Round 3 Adversarial Verification: Context Safety in Navigation Handler',
      () {
    testWidgets(
        'NotificationNavigationHandler does not crash when WidgetRef is disposed before tap handler finishes',
        (tester) async {
      final notif = NotificationItem(
        id: 'NOTIF_TAP_TEST',
        storeId: 'store_001',
        title: 'Đơn hàng mới',
        body: 'Nội dung',
        type: NotificationType.orderCreated,
        createdAt: DateTime.now(),
        targetRoute: 'invoice_detail',
        targetId: 'HD_MISSING_999',
      );

      Future<void>? tapFuture;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderRepositoryProvider.overrideWithValue(_MockOrderRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  return ElevatedButton(
                    onPressed: () {
                      tapFuture = NotificationNavigationHandler.handleTap(
                        context: context,
                        ref: ref,
                        notification: notif,
                      );
                    },
                    child: const Text('Tap Me'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap Me'));
      await tapFuture;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Expect safe error snackbar when order HD_MISSING_999 is not found
      expect(find.textContaining('Không tìm thấy thông tin đơn hàng'),
          findsOneWidget);
    });
  });
}
