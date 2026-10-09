import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/user_account.dart';

class _FakeNotificationRepository implements NotificationRepository {
  final List<NotificationItem> added = [];
  bool shouldThrow = false;

  @override
  Future<void> addNotification(NotificationItem notification) async {
    if (shouldThrow) {
      throw Exception('Simulated database error');
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
      {int limit = 50}) {
    return Stream.value(added);
  }
}

void main() {
  const storeId = 'store_001';
  const testUser = UserAccount(
    username: 'admin01',
    displayName: 'Nguyễn Quản Trị',
    role: 'admin',
    storeId: storeId,
  );

  late _FakeNotificationRepository fakeRepo;
  late NotificationDispatcher dispatcher;

  setUp(() {
    fakeRepo = _FakeNotificationRepository();
    dispatcher = NotificationDispatcher(fakeRepo);
  });

  group('NotificationDispatcher — 8 Business Event Dispatchers', () {
    test('1. notifyOrderCreated dispatches valid NotificationItem', () async {
      final order = Order(
        id: 'HD013260',
        customerId: 'KH0001',
        customerName: 'Nguyễn Văn A',
        createdAt: DateTime.now(),
        items: const [],
        total: 250000.0,
      );

      await dispatcher.notifyOrderCreated(
        storeId: storeId,
        order: order,
        user: testUser,
      );

      expect(fakeRepo.added.length, equals(1));
      final notif = fakeRepo.added.first;
      expect(notif.type, equals(NotificationType.orderCreated));
      expect(notif.category, equals(NotificationCategory.orders));
      expect(notif.title, equals('Đơn hàng mới #HD013260'));
      expect(notif.body, equals('250.000đ - Khách: Nguyễn Văn A (Tạo bởi: Nguyễn Quản Trị)'));
      expect(notif.body.contains('HD013260'), isFalse);
      expect(notif.targetRoute, equals('invoice_detail'));
      expect(notif.targetId, equals('HD013260'));
      expect(notif.isRead, isFalse);
      expect(notif.metadata?['orderId'], equals('HD013260'));
      expect(notif.metadata?['total'], equals(250000.0));
      expect(notif.metadata?['createdBy'], equals('Nguyễn Quản Trị'));
    });

    test('1b. notifyOrderCreated skips draft orders', () async {
      final draftOrder = Order(
        id: 'HD_DRAFT_1',
        customerId: 'KH0001',
        createdAt: DateTime.now(),
        items: const [],
        total: 100000.0,
        status: 'draft',
      );

      await dispatcher.notifyOrderCreated(
        storeId: storeId,
        order: draftOrder,
        user: testUser,
      );

      expect(fakeRepo.added, isEmpty);
    });

    test('1c. notifyOrderCreated falls back to Khách lẻ when name is empty',
        () async {
      final order = Order(
        id: 'HD013261',
        customerId: '',
        createdAt: DateTime.now(),
        items: const [],
        total: 150000.0,
      );

      await dispatcher.notifyOrderCreated(
        storeId: storeId,
        order: order,
        user: null,
      );

      expect(fakeRepo.added.length, equals(1));
      expect(fakeRepo.added.first.title, equals('Đơn hàng mới #HD013261'));
      expect(fakeRepo.added.first.body, equals('150.000đ - Khách: Khách lẻ (Tạo bởi: Không xác định)'));
      expect(fakeRepo.added.first.body.contains('HD013261'), isFalse);
      expect(fakeRepo.added.first.metadata?['createdBy'], equals('Không xác định'));
    });

    test('2. notifyOrderUpdated dispatches versioned edit event', () async {
      final newOrder = Order(
        id: 'HD013260.01',
        customerId: 'KH0001',
        createdAt: DateTime.now(),
        items: const [],
        total: 320000.0,
      );

      await dispatcher.notifyOrderUpdated(
        storeId: storeId,
        order: newOrder,
        originalOrderId: 'HD013260',
        user: testUser,
      );

      expect(fakeRepo.added.length, equals(1));
      final notif = fakeRepo.added.first;
      expect(notif.type, equals(NotificationType.orderUpdated));
      expect(notif.title, equals('Sửa hóa đơn #HD013260'));
      expect(notif.body, equals('Mã mới #HD013260.01: 320.000đ - Khách: Khách lẻ (Bởi: Nguyễn Quản Trị)'));
      expect(notif.body.contains('HD013260:'), isFalse);
      expect(notif.targetRoute, equals('invoice_detail'));
      expect(notif.targetId, equals('HD013260.01'));
      expect(notif.metadata?['newOrderId'], equals('HD013260.01'));
      expect(notif.metadata?['originalOrderId'], equals('HD013260'));
    });

    test('3. notifyOrderCancelled dispatches cancellation event', () async {
      final order = Order(
        id: 'HD013260',
        customerId: 'KH0001',
        createdAt: DateTime.now(),
        items: const [],
        total: 250000.0,
      );

      await dispatcher.notifyOrderCancelled(
        storeId: storeId,
        order: order,
        cancelReason: 'Khách đổi ý hủy đơn',
        user: testUser,
      );

      expect(fakeRepo.added.length, equals(1));
      final notif = fakeRepo.added.first;
      expect(notif.type, equals(NotificationType.orderCancelled));
      expect(notif.title, equals('Hủy đơn hàng #HD013260'));
      expect(notif.body, equals('Lý do: Khách đổi ý hủy đơn - Khách: Khách lẻ (Bởi: Nguyễn Quản Trị)'));
      expect(notif.body.contains('HD013260'), isFalse);
      expect(notif.targetRoute, equals('invoice_detail'));
      expect(notif.targetId, equals('HD013260'));
      expect(notif.metadata?['reason'], equals('Khách đổi ý hủy đơn'));
    });

    test('3b. notifyOrderCancelled falls back when cancelReason is blank',
        () async {
      final order = Order(
        id: 'HD013260',
        customerId: 'KH0001',
        createdAt: DateTime.now(),
        items: const [],
        total: 250000.0,
      );

      await dispatcher.notifyOrderCancelled(
        storeId: storeId,
        order: order,
        cancelReason: '',
        user: testUser,
      );

      expect(fakeRepo.added.length, equals(1));
      expect(fakeRepo.added.first.title, equals('Hủy đơn hàng #HD013260'));
      expect(fakeRepo.added.first.body, equals('Lý do: Không có lý do - Khách: Khách lẻ (Bởi: Nguyễn Quản Trị)'));
      expect(fakeRepo.added.first.body.contains('HD013260'), isFalse);
    });

    test('4. notifyOrderReturned dispatches return event', () async {
      final returnOrder = ReturnOrder(
        id: 'TH_1728045600',
        orderId: 'HD013260',
        customerId: 'KH0001',
        storeId: storeId,
        createdAt: DateTime.now(),
        items: const [],
        totalReturnAmount: 50000.0,
      );

      await dispatcher.notifyOrderReturned(
        storeId: storeId,
        returnOrder: returnOrder,
        user: testUser,
      );

      expect(fakeRepo.added.length, equals(1));
      final notif = fakeRepo.added.first;
      expect(notif.type, equals(NotificationType.orderReturn));
      expect(notif.title, equals('Đơn trả hàng #HD013260'));
      expect(notif.body, equals('Hoàn 50.000đ - Khách: Khách lẻ (Xử lý: Nguyễn Quản Trị)'));
      expect(notif.body.contains('HD013260'), isFalse);
      expect(notif.body.contains('TH_1728045600'), isFalse);
      expect(notif.targetRoute, equals('invoice_detail'));
      expect(notif.targetId, equals('HD013260'));
      expect(notif.metadata?['returnId'], equals('TH_1728045600'));
      expect(notif.metadata?['refundAmount'], equals(50000.0));
    });

    test('5. notifyStockInCompleted dispatches inventory import event',
        () async {
      final receipt = StockInReceipt(
        id: 'REC_001',
        importCode: 'NK1728045600',
        date: DateTime.now(),
        supplierName: 'Công ty Phân Bón Ánh Dương',
        totalAmount: 15000000.0,
        items: const [],
      );

      await dispatcher.notifyStockInCompleted(
        storeId: storeId,
        receipt: receipt,
        user: testUser,
      );

      expect(fakeRepo.added.length, equals(1));
      final notif = fakeRepo.added.first;
      expect(notif.type, equals(NotificationType.inventoryImported));
      expect(notif.category, equals(NotificationCategory.inventory));
      expect(notif.title, equals('Phiếu nhập kho #NK1728045600'));
      expect(notif.body, equals('15.000.000đ - NCC: Công ty Phân Bón Ánh Dương (Lập bởi: Nguyễn Quản Trị)'));
      expect(notif.body.contains('NK1728045600'), isFalse);
      expect(notif.targetRoute, equals('stock_in_detail'));
      expect(notif.targetId, equals('NK1728045600'));
      expect(notif.metadata?['importCode'], equals('NK1728045600'));
    });

    test('5b. notifyStockInCompleted skips draft or cancelled receipts',
        () async {
      final draftReceipt = StockInReceipt(
        id: 'REC_002',
        importCode: 'NK_DRAFT',
        date: DateTime.now(),
        status: 'draft',
        items: const [],
      );
      final cancelledReceipt = StockInReceipt(
        id: 'REC_003',
        importCode: 'NK_CANCELLED',
        date: DateTime.now(),
        status: 'cancelled',
        items: const [],
      );

      await dispatcher.notifyStockInCompleted(
        storeId: storeId,
        receipt: draftReceipt,
        user: testUser,
      );
      await dispatcher.notifyStockInCompleted(
        storeId: storeId,
        receipt: cancelledReceipt,
        user: testUser,
      );

      expect(fakeRepo.added, isEmpty);
    });

    test('5c. notifyStockInCompleted falls back when supplier is null/empty',
        () async {
      final receipt = StockInReceipt(
        id: 'REC_004',
        importCode: 'NK1728045602',
        date: DateTime.now(),
        totalAmount: 500000.0,
        items: const [],
      );

      await dispatcher.notifyStockInCompleted(
        storeId: storeId,
        receipt: receipt,
        user: testUser,
      );

      expect(fakeRepo.added.length, equals(1));
      expect(fakeRepo.added.first.title, equals('Phiếu nhập kho #NK1728045602'));
      expect(fakeRepo.added.first.body, contains('Nhà cung cấp lẻ'));
      expect(fakeRepo.added.first.body.contains('NK1728045602'), isFalse);
    });

    test('6. notifyCustomerCreated dispatches customer creation event',
        () async {
      const customer = Customer(
        id: 'KH00012',
        name: 'Trần Thị B',
        phone: '0987654321',
        email: '',
        address: '',
        purchases: [],
      );

      await dispatcher.notifyCustomerCreated(
        storeId: storeId,
        customer: customer,
        user: testUser,
      );

      expect(fakeRepo.added.length, equals(1));
      final notif = fakeRepo.added.first;
      expect(notif.type, equals(NotificationType.customerCreated));
      expect(notif.category, equals(NotificationCategory.customers));
      expect(notif.title, equals('Khách hàng mới'));
      expect(notif.body, equals('Trần Thị B - SĐT: 0987654321 (Tạo bởi: Nguyễn Quản Trị)'));
      expect(notif.targetRoute, equals('customer_detail'));
      expect(notif.targetId, equals('KH00012'));
    });

    test('6b. notifyCustomerCreated falls back when phone is empty', () async {
      const customer = Customer(
        id: 'KH_WALKIN',
        name: 'Khách lẻ vãng lai',
        phone: '',
        email: '',
        address: '',
        purchases: [],
      );

      await dispatcher.notifyCustomerCreated(
        storeId: storeId,
        customer: customer,
        user: testUser,
      );

      expect(fakeRepo.added.length, equals(1));
      expect(fakeRepo.added.first.title, equals('Khách hàng mới'));
      expect(fakeRepo.added.first.body, equals('Khách lẻ vãng lai - SĐT: --- (Tạo bởi: Nguyễn Quản Trị)'));
    });

    test('7. notifyCustomerDebtAdded dispatches debt incurred event', () async {
      await dispatcher.notifyCustomerDebtAdded(
        storeId: storeId,
        customerId: 'KH00012',
        customerName: 'Trần Thị B',
        debtAmount: 120000.0,
        orderId: 'HD013261',
        user: testUser,
      );

      expect(fakeRepo.added.length, equals(1));
      final notif = fakeRepo.added.first;
      expect(notif.type, equals(NotificationType.customerDebtAdded));
      expect(notif.category, equals(NotificationCategory.customers));
      expect(notif.title, equals('Ghi nhận nợ mới'));
      expect(notif.body, equals('Ghi nợ 120.000đ từ đơn #HD013261 - Khách: Trần Thị B (Bởi: Nguyễn Quản Trị)'));
      expect(notif.targetRoute, equals('customer_debt'));
      expect(notif.targetId, equals('KH00012'));
    });

    test('7b. notifyCustomerDebtAdded skips zero or negative debt', () async {
      await dispatcher.notifyCustomerDebtAdded(
        storeId: storeId,
        customerId: 'KH00012',
        customerName: 'Trần Thị B',
        debtAmount: 0.0,
        orderId: 'HD013262',
        user: testUser,
      );

      expect(fakeRepo.added, isEmpty);
    });

    test('8. notifyCustomerDebtCollected dispatches debt paid event', () async {
      await dispatcher.notifyCustomerDebtCollected(
        storeId: storeId,
        customerId: 'KH00012',
        customerName: 'Trần Thị B',
        collectedAmount: 100000.0,
        remainingDebt: 20000.0,
        user: testUser,
      );

      expect(fakeRepo.added.length, equals(1));
      final notif = fakeRepo.added.first;
      expect(notif.type, equals(NotificationType.customerDebtPaid));
      expect(notif.category, equals(NotificationCategory.customers));
      expect(notif.title, equals('Thu nợ khách hàng'));
      expect(notif.body, equals('Thu 100.000đ từ khách Trần Thị B (Thu bởi: Nguyễn Quản Trị)'));
      expect(notif.targetRoute, equals('customer_debt'));
      expect(notif.targetId, equals('KH00012'));
    });

    test('8b. notifyCustomerDebtCollected formats cleanly without remainingDebt',
        () async {
      await dispatcher.notifyCustomerDebtCollected(
        storeId: storeId,
        customerId: 'KH00012',
        customerName: 'Trần Thị B',
        collectedAmount: 50000.0,
        user: testUser,
      );

      expect(fakeRepo.added.length, equals(1));
      expect(fakeRepo.added.first.title, equals('Thu nợ khách hàng'));
      expect(fakeRepo.added.first.body, equals('Thu 50.000đ từ khách Trần Thị B (Thu bởi: Nguyễn Quản Trị)'));
      expect(fakeRepo.added.first.body.contains('Nợ còn'), isFalse);
    });

    test('8c. notifyCustomerDebtCollected skips zero or negative amount',
        () async {
      await dispatcher.notifyCustomerDebtCollected(
        storeId: storeId,
        customerId: 'KH00012',
        customerName: 'Trần Thị B',
        collectedAmount: 0.0,
        user: testUser,
      );

      expect(fakeRepo.added, isEmpty);
    });
  });

  group('NotificationDispatcher — Resilience & Fault Tolerance', () {
    test('Catch-all protects caller from database exceptions', () async {
      fakeRepo.shouldThrow = true;
      final order = Order(
        id: 'HD_CRASH_TEST',
        customerId: 'KH0001',
        createdAt: DateTime.now(),
        items: const [],
        total: 99999.0,
      );

      // Must complete normally without throwing
      await expectLater(
        dispatcher.notifyOrderCreated(
          storeId: storeId,
          order: order,
          user: testUser,
        ),
        completes,
      );
    });
  });

  group('NotificationDispatcherProvider — Riverpod Wiring', () {
    test('notificationDispatcherProvider resolves with repository override',
        () {
      final container = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final resolvedDispatcher =
          container.read(notificationDispatcherProvider);
      expect(resolvedDispatcher, isA<NotificationDispatcher>());
    });
  });
}
