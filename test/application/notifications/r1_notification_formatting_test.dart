import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/domain/entities/customer.dart';
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
      {int limit = 50}) {
    return Stream.value(added);
  }
}

void main() {
  const storeId = 'store_test_01';
  const testCashier = UserAccount(
    username: 'thu_ngan_lan',
    displayName: 'Thu ngân Lan',
    role: 'nhanvien',
    storeId: storeId,
  );
  const testAdmin = UserAccount(
    username: 'admin_quan',
    displayName: 'Quản lý Quân',
    role: 'admin',
    storeId: storeId,
  );

  late _MockNotificationRepository mockRepo;
  late NotificationDispatcher dispatcher;

  setUp(() {
    mockRepo = _MockNotificationRepository();
    dispatcher = NotificationDispatcher(mockRepo);
  });

  group('R1: Notification Formatting — Creator & Customer In All 8 Events', () {
    // 1. Đơn hàng mới
    test('1. notifyOrderCreated shows amount, customer name, and creator without duplicate order ID', () async {
      final order = Order(
        id: 'HD01',
        customerId: 'KH001',
        customerName: 'Nguyễn Văn A',
        createdAt: DateTime.now(),
        items: const [],
        total: 250000.0,
      );

      await dispatcher.notifyOrderCreated(
        storeId: storeId,
        order: order,
        user: testCashier,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Đơn hàng mới #HD01'));
      expect(notif.body, equals('250.000đ - Khách: Nguyễn Văn A (Tạo bởi: Thu ngân Lan)'));
      expect(notif.body.contains('Đơn hàng mới #HD01:'), isFalse);
      expect(notif.body.contains('HD01'), isFalse);
      expect(notif.metadata?['createdBy'], equals('Thu ngân Lan'));
      expect(notif.metadata?['customerName'], equals('Nguyễn Văn A'));
      expect(notif.metadata?['customerId'], equals('KH001'));
    });

    test('1b. notifyOrderCreated fallback for Khách lẻ and null user', () async {
      final order = Order(
        id: 'HD02',
        customerId: '',
        customerName: '',
        createdAt: DateTime.now(),
        items: const [],
        total: 120000.0,
      );

      await dispatcher.notifyOrderCreated(
        storeId: storeId,
        order: order,
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Đơn hàng mới #HD02'));
      expect(notif.body, equals('120.000đ - Khách: Khách lẻ (Tạo bởi: Không xác định)'));
      expect(notif.body.contains('HD02'), isFalse);
      expect(notif.metadata?['createdBy'], equals('Không xác định'));
      expect(notif.metadata?['customerName'], equals('Khách lẻ'));
      expect(notif.metadata?['customerId'], equals('default'));
    });

    // 2. Sửa hóa đơn
    test('2. notifyOrderUpdated shows new order ID, total, customer, and editor', () async {
      final order = Order(
        id: 'HD01.01',
        customerId: 'KH001',
        customerName: 'Nguyễn Văn A',
        createdAt: DateTime.now(),
        items: const [],
        total: 350000.0,
      );

      await dispatcher.notifyOrderUpdated(
        storeId: storeId,
        order: order,
        originalOrderId: 'HD01',
        user: testAdmin,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Sửa hóa đơn #HD01'));
      expect(notif.body, equals('Mã mới #HD01.01: 350.000đ - Khách: Nguyễn Văn A (Bởi: Quản lý Quân)'));
      expect(notif.body.contains('HD01:'), isFalse);
      expect(notif.metadata?['createdBy'], equals('Quản lý Quân'));
      expect(notif.metadata?['customerName'], equals('Nguyễn Văn A'));
      expect(notif.metadata?['customerId'], equals('KH001'));
    });

    test('2b. notifyOrderUpdated fallback for Khách lẻ and null user', () async {
      final order = Order(
        id: 'HD02.01',
        customerId: 'default',
        customerName: null,
        createdAt: DateTime.now(),
        items: const [],
        total: 180000.0,
      );

      await dispatcher.notifyOrderUpdated(
        storeId: storeId,
        order: order,
        originalOrderId: 'HD02',
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Sửa hóa đơn #HD02'));
      expect(notif.body, equals('Mã mới #HD02.01: 180.000đ - Khách: Khách lẻ (Bởi: Không xác định)'));
      expect(notif.metadata?['createdBy'], equals('Không xác định'));
      expect(notif.metadata?['customerName'], equals('Khách lẻ'));
      expect(notif.metadata?['customerId'], equals('default'));
    });

    // 3. Hủy đơn hàng
    test('3. notifyOrderCancelled shows order ID in title, reason, customer, and canceller without duplicate ID in body', () async {
      final order = Order(
        id: 'HD01',
        customerId: 'KH001',
        customerName: 'Nguyễn Văn A',
        createdAt: DateTime.now(),
        items: const [],
        total: 250000.0,
      );

      await dispatcher.notifyOrderCancelled(
        storeId: storeId,
        order: order,
        cancelReason: 'Khách hết nhu cầu',
        user: testCashier,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Hủy đơn hàng #HD01'));
      expect(notif.body, equals('Lý do: Khách hết nhu cầu - Khách: Nguyễn Văn A (Bởi: Thu ngân Lan)'));
      expect(notif.body.contains('HD01'), isFalse);
      expect(notif.metadata?['createdBy'], equals('Thu ngân Lan'));
      expect(notif.metadata?['customerName'], equals('Nguyễn Văn A'));
      expect(notif.metadata?['customerId'], equals('KH001'));
    });

    test('3b. notifyOrderCancelled fallback when blank reason and null user', () async {
      final order = Order(
        id: 'HD02',
        customerId: '',
        createdAt: DateTime.now(),
        items: const [],
        total: 100000.0,
      );

      await dispatcher.notifyOrderCancelled(
        storeId: storeId,
        order: order,
        cancelReason: '',
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Hủy đơn hàng #HD02'));
      expect(notif.body, equals('Lý do: Không có lý do - Khách: Khách lẻ (Bởi: Không xác định)'));
      expect(notif.body.contains('HD02'), isFalse);
      expect(notif.metadata?['createdBy'], equals('Không xác định'));
      expect(notif.metadata?['customerName'], equals('Khách lẻ'));
    });

    // 4. Đơn trả hàng
    test('4. notifyOrderReturned shows refund amount, customer, and processor without duplicate order ID', () async {
      final returnOrder = ReturnOrder(
        id: 'TH01',
        orderId: 'HD01',
        customerId: 'KH001',
        customerName: 'Nguyễn Văn A',
        storeId: storeId,
        createdAt: DateTime.now(),
        items: const [],
        totalReturnAmount: 80000.0,
      );

      await dispatcher.notifyOrderReturned(
        storeId: storeId,
        returnOrder: returnOrder,
        user: testCashier,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Đơn trả hàng #HD01'));
      expect(notif.body, equals('Hoàn 80.000đ - Khách: Nguyễn Văn A (Xử lý: Thu ngân Lan)'));
      expect(notif.body.contains('HD01'), isFalse);
      expect(notif.body.contains('TH01'), isFalse);
      expect(notif.metadata?['createdBy'], equals('Thu ngân Lan'));
      expect(notif.metadata?['customerName'], equals('Nguyễn Văn A'));
      expect(notif.metadata?['customerId'], equals('KH001'));
    });

    test('4b. notifyOrderReturned fallback for walk-in customer and null user', () async {
      final returnOrder = ReturnOrder(
        id: 'TH02',
        orderId: 'HD02',
        customerId: 'default',
        storeId: storeId,
        createdAt: DateTime.now(),
        items: const [],
        totalReturnAmount: 30000.0,
      );

      await dispatcher.notifyOrderReturned(
        storeId: storeId,
        returnOrder: returnOrder,
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Đơn trả hàng #HD02'));
      expect(notif.body, equals('Hoàn 30.000đ - Khách: Khách lẻ (Xử lý: Không xác định)'));
      expect(notif.body.contains('HD02'), isFalse);
      expect(notif.metadata?['createdBy'], equals('Không xác định'));
      expect(notif.metadata?['customerName'], equals('Khách lẻ'));
    });

    // 5. Nhập kho
    test('5. notifyStockInCompleted shows total amount, supplier, and creator without duplicate code', () async {
      final receipt = StockInReceipt(
        id: 'REC_01',
        importCode: 'NK001',
        date: DateTime.now(),
        supplierName: 'Công ty Dược Hậu Giang',
        totalAmount: 12500000.0,
        items: const [],
      );

      await dispatcher.notifyStockInCompleted(
        storeId: storeId,
        receipt: receipt,
        user: testAdmin,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Phiếu nhập kho #NK001'));
      expect(notif.body, equals('12.500.000đ - NCC: Công ty Dược Hậu Giang (Lập bởi: Quản lý Quân)'));
      expect(notif.body.contains('NK001'), isFalse);
      expect(notif.metadata?['createdBy'], equals('Quản lý Quân'));
      expect(notif.metadata?['supplierName'], equals('Công ty Dược Hậu Giang'));
      expect(notif.metadata?['customerName'], equals('Công ty Dược Hậu Giang'));
    });

    test('5b. notifyStockInCompleted fallback when supplier is blank and null user', () async {
      final receipt = StockInReceipt(
        id: 'REC_02',
        importCode: 'NK002',
        date: DateTime.now(),
        supplierName: '',
        totalAmount: 50000.0,
        items: const [],
      );

      await dispatcher.notifyStockInCompleted(
        storeId: storeId,
        receipt: receipt,
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Phiếu nhập kho #NK002'));
      expect(notif.body, equals('50.000đ - NCC: Nhà cung cấp lẻ (Lập bởi: Không xác định)'));
      expect(notif.body.contains('NK002'), isFalse);
      expect(notif.metadata?['supplierName'], equals('Nhà cung cấp lẻ'));
      expect(notif.metadata?['createdBy'], equals('Không xác định'));
      expect(notif.metadata?['customerName'], equals('Nhà cung cấp lẻ'));
      expect(notif.metadata?['customerId'], equals('default'));
    });

    test('5c. notifyStockInCompleted fallback to receipt.createdByName when user is null', () async {
      final receipt = StockInReceipt(
        id: 'REC_03',
        importCode: 'NK003',
        date: DateTime.now(),
        supplierName: 'Công ty ABC',
        totalAmount: 1000000.0,
        items: const [],
        createdByName: 'Kho Trưởng Hùng',
        createdBy: 'hung_kho',
      );

      await dispatcher.notifyStockInCompleted(
        storeId: storeId,
        receipt: receipt,
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Phiếu nhập kho #NK003'));
      expect(notif.body, equals('1.000.000đ - NCC: Công ty ABC (Lập bởi: Kho Trưởng Hùng)'));
      expect(notif.body.contains('NK003'), isFalse);
      expect(notif.metadata?['createdBy'], equals('Kho Trưởng Hùng'));
    });

    test('1c. notifyOrderCreated fallback to order.createdByName when user is null', () async {
      final order = Order(
        id: 'HD03',
        customerId: 'KH003',
        customerName: 'Lê Văn Nam',
        createdAt: DateTime.now(),
        items: const [],
        total: 500000.0,
        createdByName: 'Thu ngân Mai',
      );

      await dispatcher.notifyOrderCreated(
        storeId: storeId,
        order: order,
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Đơn hàng mới #HD03'));
      expect(notif.body, equals('500.000đ - Khách: Lê Văn Nam (Tạo bởi: Thu ngân Mai)'));
      expect(notif.body.contains('HD03'), isFalse);
      expect(notif.metadata?['createdBy'], equals('Thu ngân Mai'));
    });

    test('3c. notifyOrderCancelled fallback to order.cancelledByName when user is null', () async {
      final order = Order(
        id: 'HD04',
        customerId: 'KH004',
        customerName: 'Hoàng Văn B',
        createdAt: DateTime.now(),
        items: const [],
        total: 200000.0,
        cancelledByName: 'Giám sát Nam',
      );

      await dispatcher.notifyOrderCancelled(
        storeId: storeId,
        order: order,
        cancelReason: 'Lỗi thanh toán',
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Hủy đơn hàng #HD04'));
      expect(notif.body, equals('Lý do: Lỗi thanh toán - Khách: Hoàng Văn B (Bởi: Giám sát Nam)'));
      expect(notif.body.contains('HD04'), isFalse);
      expect(notif.metadata?['createdBy'], equals('Giám sát Nam'));
      expect(notif.metadata?['cancelledBy'], equals('Giám sát Nam'));
    });

    // 6. Khách hàng mới
    test('6. notifyCustomerCreated shows customer name, phone, and creator', () async {
      const customer = Customer(
        id: 'KH_NEW_01',
        name: 'Phạm Hồng C',
        phone: '0912345678',
        email: '',
        address: '',
        purchases: [],
      );

      await dispatcher.notifyCustomerCreated(
        storeId: storeId,
        customer: customer,
        user: testCashier,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Khách hàng mới'));
      expect(notif.body, equals('Phạm Hồng C - SĐT: 0912345678 (Tạo bởi: Thu ngân Lan)'));
      expect(notif.metadata?['createdBy'], equals('Thu ngân Lan'));
      expect(notif.metadata?['customerName'], equals('Phạm Hồng C'));
      expect(notif.metadata?['customerId'], equals('KH_NEW_01'));
    });

    test('6b. notifyCustomerCreated fallback for blank name and null user', () async {
      const customer = Customer(
        id: 'KH_NEW_02',
        name: '',
        phone: '',
        email: '',
        address: '',
        purchases: [],
      );

      await dispatcher.notifyCustomerCreated(
        storeId: storeId,
        customer: customer,
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Khách hàng mới'));
      expect(notif.body, equals('Khách lẻ - SĐT: --- (Tạo bởi: Không xác định)'));
      expect(notif.metadata?['createdBy'], equals('Không xác định'));
      expect(notif.metadata?['customerName'], equals('Khách lẻ'));
    });

    // 7. Ghi nợ khách hàng
    test('7. notifyCustomerDebtAdded shows debt amount, customer, order, and creator', () async {
      await dispatcher.notifyCustomerDebtAdded(
        storeId: storeId,
        customerId: 'KH001',
        customerName: 'Nguyễn Văn A',
        debtAmount: 150000.0,
        orderId: 'HD01',
        user: testCashier,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Ghi nhận nợ mới'));
      expect(notif.body, equals('Ghi nợ 150.000đ từ đơn #HD01 - Khách: Nguyễn Văn A (Bởi: Thu ngân Lan)'));
      expect(notif.metadata?['createdBy'], equals('Thu ngân Lan'));
      expect(notif.metadata?['customerName'], equals('Nguyễn Văn A'));
      expect(notif.metadata?['customerId'], equals('KH001'));
    });

    test('7b. notifyCustomerDebtAdded fallback for empty customer name and null user', () async {
      await dispatcher.notifyCustomerDebtAdded(
        storeId: storeId,
        customerId: '',
        customerName: '',
        debtAmount: 50000.0,
        orderId: 'HD02',
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Ghi nhận nợ mới'));
      expect(notif.body, equals('Ghi nợ 50.000đ từ đơn #HD02 - Khách: Khách lẻ (Bởi: Không xác định)'));
      expect(notif.metadata?['createdBy'], equals('Không xác định'));
      expect(notif.metadata?['customerName'], equals('Khách lẻ'));
    });

    // 8. Thu nợ khách hàng
    test('8. notifyCustomerDebtCollected shows collected amount, customer, and collector', () async {
      await dispatcher.notifyCustomerDebtCollected(
        storeId: storeId,
        customerId: 'KH001',
        customerName: 'Nguyễn Văn A',
        collectedAmount: 100000.0,
        remainingDebt: 50000.0,
        user: testCashier,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Thu nợ khách hàng'));
      expect(notif.body, equals('Thu 100.000đ từ khách Nguyễn Văn A (Thu bởi: Thu ngân Lan)'));
      expect(notif.metadata?['createdBy'], equals('Thu ngân Lan'));
      expect(notif.metadata?['customerName'], equals('Nguyễn Văn A'));
      expect(notif.metadata?['customerId'], equals('KH001'));
      expect(notif.metadata?['remainingDebt'], equals(50000.0));
    });

    test('8b. notifyCustomerDebtCollected fallback without remaining debt and null user', () async {
      await dispatcher.notifyCustomerDebtCollected(
        storeId: storeId,
        customerId: '',
        customerName: '',
        collectedAmount: 50000.0,
        user: null,
      );

      expect(mockRepo.added.length, equals(1));
      final notif = mockRepo.added.first;
      expect(notif.title, equals('Thu nợ khách hàng'));
      expect(notif.body, equals('Thu 50.000đ từ khách Khách lẻ (Thu bởi: Không xác định)'));
      expect(notif.metadata?['createdBy'], equals('Không xác định'));
      expect(notif.metadata?['customerName'], equals('Khách lẻ'));
    });
  });
}
