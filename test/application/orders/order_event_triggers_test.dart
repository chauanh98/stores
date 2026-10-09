import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/core/errors/exceptions.dart';
import 'package:stores/data/datasources/firebase/customer_remote_data_source.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';

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

class _FakeOrderRepository
    implements OrderRepository, OrderRepositoryReturnHandler {
  final Map<String, Order> orders = {};
  final List<ReturnOrder> returns = [];

  @override
  Future<void> create(Order order) async => orders[order.id] = order;

  @override
  Future<void> update(Order order) async => orders[order.id] = order;

  @override
  Future<void> delete(String orderId) async => orders.remove(orderId);

  @override
  Future<Order?> fetchById(String orderId) async => orders[orderId];

  @override
  Future<void> createReturn(ReturnOrder returnOrder) async =>
      returns.add(returnOrder);

  @override
  Future<ReturnOrder?> fetchReturnById(String returnId) async => null;

  @override
  Stream<List<ReturnOrder>> watchAllReturns() => Stream.value(returns);

  @override
  Stream<List<ReturnOrder>> watchReturnsByDateRange(
          DateTime start, DateTime end) =>
      Stream.value(returns);

  @override
  Stream<List<ReturnOrder>> watchReturnsByOrderId(String orderId) =>
      Stream.value(returns.where((r) => r.orderId == orderId).toList());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductRepository implements ProductRepository {
  final Map<String, Product> products = {};

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<void> upsert(Product product) async => products[product.id] = product;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryRepository implements InventoryRepository {
  final List<dynamic> transactions = [];

  @override
  Future<void> record(dynamic transaction) async =>
      transactions.add(transaction);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomerRepository implements CustomerRepository {
  final Map<String, Customer> customers = {};

  @override
  Future<Customer?> fetchById(String id) async => customers[id];

  @override
  Future<void> upsert(Customer customer) async =>
      customers[customer.id] = customer;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomerRemoteDataSource implements CustomerRemoteDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeNotificationRepository fakeNotifRepo;
  late NotificationDispatcher dispatcher;
  late _FakeOrderRepository fakeOrderRepo;
  late _FakeProductRepository fakeProductRepo;
  late _FakeInventoryRepository fakeInventoryRepo;
  late _FakeCustomerRepository fakeCustomerRepo;

  const adminUser = UserAccount(
    username: 'admin01',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff01',
    displayName: 'Nhân viên bán hàng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  final testDate = DateTime(2026, 10, 4, 12, 0);

  const testProduct = Product(
    id: 'prod_1',
    code: 'SP01',
    name: 'Máy in hóa đơn',
    category: 'Thiết bị',
    price: 1500000,
    costPrice: 1000000,
    branchStocks: {'store_001': 10},
  );

  final testOrder = Order(
    id: 'HD01001',
    customerId: 'KH001',
    customerName: 'Nguyễn Văn A',
    createdAt: testDate,
    items: [
      OrderItem(
        productId: 'prod_1',
        productName: 'Máy in hóa đơn',
        quantity: 2,
        price: 1500000,
        warrantyMonths: 12,
        purchaseDate: testDate,
      ),
    ],
    total: 3000000,
    discount: 0,
    amountPaid: 3000000,
    debtAmount: 0,
    status: 'completed',
    storeId: 'store_001',
  );

  setUp(() {
    fakeNotifRepo = _FakeNotificationRepository();
    dispatcher = NotificationDispatcher(fakeNotifRepo);
    fakeOrderRepo = _FakeOrderRepository();
    fakeProductRepo = _FakeProductRepository();
    fakeInventoryRepo = _FakeInventoryRepository();
    fakeCustomerRepo = _FakeCustomerRepository();

    fakeProductRepo.products[testProduct.id] = testProduct;
    fakeOrderRepo.orders[testOrder.id] = testOrder;
  });

  group('CancelInvoiceUseCase Event Triggers', () {
    test('1. Normal cancellation dispatches notifyOrderCancelled with exact details',
        () async {
      final useCase = CancelInvoiceUseCase(
        orderRepository: fakeOrderRepo,
        productRepository: fakeProductRepo,
        inventoryRepository: fakeInventoryRepo,
        customerRepository: fakeCustomerRepo,
        notificationDispatcher: dispatcher,
      );

      final result = await useCase.execute(
        order: testOrder,
        cancelReason: 'Khách đổi ý không mua nữa',
        currentUser: adminUser,
        storeId: 'store_001',
        isReplacement: false,
      );

      expect(result.status, equals('cancelled'));
      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.orderCancelled));
      expect(notif.category, equals(NotificationCategory.orders));
      expect(notif.targetRoute, equals('invoice_detail'));
      expect(notif.targetId, equals(testOrder.id));
      expect(notif.title, contains(testOrder.id));
      expect(notif.body, contains('Khách đổi ý không mua nữa'));
      expect(notif.metadata?['orderId'], equals(testOrder.id));
      expect(notif.metadata?['reason'], equals('Khách đổi ý không mua nữa'));
      expect(notif.metadata?['cancelledBy'], equals('Quản trị viên'));
    });

    test('2. Replacement cancellation (isReplacement: true) suppresses notifyOrderCancelled',
        () async {
      final useCase = CancelInvoiceUseCase(
        orderRepository: fakeOrderRepo,
        productRepository: fakeProductRepo,
        inventoryRepository: fakeInventoryRepo,
        customerRepository: fakeCustomerRepo,
        notificationDispatcher: dispatcher,
      );

      final result = await useCase.execute(
        order: testOrder,
        cancelReason: 'Đã sửa thành HD01001.01',
        currentUser: adminUser,
        storeId: 'store_001',
        isReplacement: true,
      );

      expect(result.status, equals('cancelled'));
      // Replacement cancellation must NOT dispatch orderCancelled
      expect(fakeNotifRepo.added, isEmpty);
    });

    test('3. Null notificationDispatcher executes cancellation safely without errors',
        () async {
      final useCase = CancelInvoiceUseCase(
        orderRepository: fakeOrderRepo,
        productRepository: fakeProductRepo,
        inventoryRepository: fakeInventoryRepo,
        customerRepository: fakeCustomerRepo,
        notificationDispatcher: null,
      );

      final result = await useCase.execute(
        order: testOrder,
        cancelReason: 'Hủy test',
        currentUser: adminUser,
        storeId: 'store_001',
        isReplacement: false,
      );

      expect(result.status, equals('cancelled'));
      expect(fakeNotifRepo.added, isEmpty);
    });

    test('4. Notification failure does not disrupt invoice cancellation', () async {
      fakeNotifRepo.shouldThrow = true;
      final useCase = CancelInvoiceUseCase(
        orderRepository: fakeOrderRepo,
        productRepository: fakeProductRepo,
        inventoryRepository: fakeInventoryRepo,
        customerRepository: fakeCustomerRepo,
        notificationDispatcher: dispatcher,
      );

      final result = await useCase.execute(
        order: testOrder,
        cancelReason: 'Hủy khi lỗi mạng',
        currentUser: adminUser,
        storeId: 'store_001',
        isReplacement: false,
      );

      expect(result.status, equals('cancelled'));
      expect(fakeOrderRepo.orders[testOrder.id]?.status, equals('cancelled'));
    });

    test('5. Unauthorized user throws UnauthorizedException and dispatches nothing',
        () async {
      final useCase = CancelInvoiceUseCase(
        orderRepository: fakeOrderRepo,
        productRepository: fakeProductRepo,
        inventoryRepository: fakeInventoryRepo,
        customerRepository: fakeCustomerRepo,
        notificationDispatcher: dispatcher,
      );

      expect(
        () => useCase.execute(
          order: testOrder,
          cancelReason: 'Nhân viên tự hủy',
          currentUser: staffUser,
          storeId: 'store_001',
          isReplacement: false,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(fakeNotifRepo.added, isEmpty);
    });
  });

  group('ProcessReturnOrderUseCase Event Triggers', () {
    test('1. Successful return order dispatches notifyOrderReturned', () async {
      final useCase = ProcessReturnOrderUseCase(
        orderRepository: fakeOrderRepo,
        productRepository: fakeProductRepo,
        inventoryRepository: fakeInventoryRepo,
        customerRepository: fakeCustomerRepo,
        notificationDispatcher: dispatcher,
      );

      final returnItems = [
        const ReturnOrderItem(
          productId: 'prod_1',
          productName: 'Máy in hóa đơn',
          quantity: 1,
          price: 1500000,
        ),
      ];

      final result = await useCase.execute(
        originalOrder: testOrder,
        returnItems: returnItems,
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Hàng bị lỗi đầu kim in',
        refundPaymentMethod: 'cash',
      );

      expect(result.returnOrder, isNotNull);
      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.orderReturn));
      expect(notif.category, equals(NotificationCategory.orders));
      expect(notif.targetRoute, equals('invoice_detail'));
      expect(notif.targetId, equals(testOrder.id));
      expect(notif.title, contains(testOrder.id));
      expect(notif.body, contains('1.500.000đ'));
      expect(notif.metadata?['returnId'], equals(result.returnOrder.id));
      expect(notif.metadata?['refundAmount'], equals(1500000.0));
      expect(notif.metadata?['createdBy'], equals('Quản trị viên'));
    });

    test('2. Null notificationDispatcher executes return safely without error',
        () async {
      final useCase = ProcessReturnOrderUseCase(
        orderRepository: fakeOrderRepo,
        productRepository: fakeProductRepo,
        inventoryRepository: fakeInventoryRepo,
        customerRepository: fakeCustomerRepo,
        notificationDispatcher: null,
      );

      final returnItems = [
        const ReturnOrderItem(
          productId: 'prod_1',
          productName: 'Máy in hóa đơn',
          quantity: 1,
          price: 1500000,
        ),
      ];

      final result = await useCase.execute(
        originalOrder: testOrder,
        returnItems: returnItems,
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Đổi máy khác',
      );

      expect(result.returnOrder, isNotNull);
      expect(fakeNotifRepo.added, isEmpty);
    });

    test('3. Notification failure does not disrupt return order completion', () async {
      fakeNotifRepo.shouldThrow = true;
      final useCase = ProcessReturnOrderUseCase(
        orderRepository: fakeOrderRepo,
        productRepository: fakeProductRepo,
        inventoryRepository: fakeInventoryRepo,
        customerRepository: fakeCustomerRepo,
        notificationDispatcher: dispatcher,
      );

      final returnItems = [
        const ReturnOrderItem(
          productId: 'prod_1',
          productName: 'Máy in hóa đơn',
          quantity: 1,
          price: 1500000,
        ),
      ];

      final result = await useCase.execute(
        originalOrder: testOrder,
        returnItems: returnItems,
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Đổi máy',
      );

      expect(result.returnOrder, isNotNull);
      expect(fakeOrderRepo.returns.length, equals(1));
    });

    test('4. Empty return items throws ValidationException and dispatches nothing',
        () async {
      final useCase = ProcessReturnOrderUseCase(
        orderRepository: fakeOrderRepo,
        productRepository: fakeProductRepo,
        inventoryRepository: fakeInventoryRepo,
        customerRepository: fakeCustomerRepo,
        notificationDispatcher: dispatcher,
      );

      expect(
        () => useCase.execute(
          originalOrder: testOrder,
          returnItems: const [],
          storeId: 'store_001',
          currentUser: adminUser,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(fakeNotifRepo.added, isEmpty);
    });
  });

  group('POS Payment Dispatcher Simulation', () {
    test('1. notifyOrderCreated dispatches orderCreated notification', () async {
      await dispatcher.notifyOrderCreated(
        storeId: 'store_001',
        order: testOrder,
        user: adminUser,
      );

      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.orderCreated));
      expect(notif.category, equals(NotificationCategory.orders));
      expect(notif.targetRoute, equals('invoice_detail'));
      expect(notif.targetId, equals(testOrder.id));
      expect(notif.title, contains(testOrder.id));
      expect(notif.body, contains('3.000.000đ'));
    });

    test('2. notifyOrderUpdated dispatches orderUpdated with version metadata',
        () async {
      final updatedOrder = testOrder.copyWith(id: 'HD01001.01', total: 3200000);

      await dispatcher.notifyOrderUpdated(
        storeId: 'store_001',
        order: updatedOrder,
        originalOrderId: 'HD01001',
        user: adminUser,
      );

      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.orderUpdated));
      expect(notif.category, equals(NotificationCategory.orders));
      expect(notif.targetRoute, equals('invoice_detail'));
      expect(notif.targetId, equals('HD01001.01'));
      expect(notif.title, contains('HD01001'));
      expect(notif.body, contains('HD01001.01'));
      expect(notif.metadata?['newOrderId'], equals('HD01001.01'));
      expect(notif.metadata?['originalOrderId'], equals('HD01001'));
    });

    test('3. Draft order is ignored by notifyOrderCreated', () async {
      final draftOrder = testOrder.copyWith(status: 'draft');

      await dispatcher.notifyOrderCreated(
        storeId: 'store_001',
        order: draftOrder,
        user: adminUser,
      );

      expect(fakeNotifRepo.added, isEmpty);
    });
  });

  group('Riverpod Providers Wiring', () {
    test('cancelInvoiceUseCaseProvider and processReturnOrderUseCaseProvider resolve with dispatcher',
        () {
      final container = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(fakeNotifRepo),
          orderRepositoryProvider.overrideWithValue(fakeOrderRepo),
          productRepositoryProvider.overrideWithValue(fakeProductRepo),
          inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
          customerRepositoryProvider.overrideWithValue(fakeCustomerRepo),
          customerRemoteDataSourceProvider
              .overrideWithValue(_FakeCustomerRemoteDataSource()),
        ],
      );
      addTearDown(container.dispose);

      final cancelUseCase = container.read(cancelInvoiceUseCaseProvider);
      expect(cancelUseCase, isA<CancelInvoiceUseCase>());
      expect(cancelUseCase.notificationDispatcher, isNotNull);

      final returnUseCase = container.read(processReturnOrderUseCaseProvider);
      expect(returnUseCase, isA<ProcessReturnOrderUseCase>());
      expect(returnUseCase.notificationDispatcher, isNotNull);
    });
  });
}
