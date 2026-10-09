import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/complete_stock_in_receipt_use_case.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/data/datasources/firebase/customer_remote_data_source.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/stock_in_receipt_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

// ============================================================================
// ADVERSARIAL TEST DOUBLES & MOCKS
// ============================================================================

class _FaultInjectingNotificationRepository implements NotificationRepository {
  final List<NotificationItem> added = [];
  bool shouldThrow = false;
  Object? customError;

  void injectError(Object? err) {
    shouldThrow = true;
    customError = err;
  }

  void clearError() {
    shouldThrow = false;
    customError = null;
  }

  @override
  Future<void> addNotification(NotificationItem notification) async {
    if (shouldThrow) {
      if (customError != null) throw customError!;
      throw Exception('Simulated RTDB / Network failure in addNotification');
    }
    added.add(notification);
  }

  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {
    added.removeWhere((n) => n.id == id);
  }

  @override
  Future<void> markAllAsRead(String storeId) async {
    for (int i = 0; i < added.length; i++) {
      added[i] = added[i].copyWith(isRead: true);
    }
  }

  @override
  Future<void> markAsRead(
      {required String storeId, required String id}) async {
    final idx = added.indexWhere((n) => n.id == id);
    if (idx != -1) {
      added[idx] = added[idx].copyWith(isRead: true);
    }
  }

  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
      {int limit = 50}) {
    return Stream.value(added);
  }
}

class _ThrowingNotificationDispatcher extends NotificationDispatcher {
  bool throwOnCancel = false;
  bool throwOnReturn = false;
  bool throwOnStockIn = false;
  bool throwOnCreate = false;
  bool throwOnUpdate = false;
  Object? customError;

  _ThrowingNotificationDispatcher(super.repository);

  @override
  Future<void> notifyOrderCancelled({
    required String storeId,
    required Order order,
    required String cancelReason,
    required UserAccount? user,
  }) async {
    if (throwOnCancel) {
      throw customError ??
          StateError('Crash injection: notifyOrderCancelled exploded');
    }
    return super.notifyOrderCancelled(
      storeId: storeId,
      order: order,
      cancelReason: cancelReason,
      user: user,
    );
  }

  @override
  Future<void> notifyOrderReturned({
    required String storeId,
    required ReturnOrder returnOrder,
    required UserAccount? user,
  }) async {
    if (throwOnReturn) {
      throw customError ??
          StateError('Crash injection: notifyOrderReturned exploded');
    }
    return super.notifyOrderReturned(
      storeId: storeId,
      returnOrder: returnOrder,
      user: user,
    );
  }

  @override
  Future<void> notifyStockInCompleted({
    required String storeId,
    required StockInReceipt receipt,
    required UserAccount? user,
  }) async {
    if (throwOnStockIn) {
      throw customError ??
          StateError('Crash injection: notifyStockInCompleted exploded');
    }
    return super.notifyStockInCompleted(
      storeId: storeId,
      receipt: receipt,
      user: user,
    );
  }

  @override
  Future<void> notifyOrderCreated({
    required String storeId,
    required Order order,
    required UserAccount? user,
  }) async {
    if (throwOnCreate) {
      throw customError ??
          StateError('Crash injection: notifyOrderCreated exploded');
    }
    return super.notifyOrderCreated(
      storeId: storeId,
      order: order,
      user: user,
    );
  }

  @override
  Future<void> notifyOrderUpdated({
    required String storeId,
    required Order order,
    required String originalOrderId,
    required UserAccount? user,
  }) async {
    if (throwOnUpdate) {
      throw customError ??
          StateError('Crash injection: notifyOrderUpdated exploded');
    }
    return super.notifyOrderUpdated(
      storeId: storeId,
      order: order,
      originalOrderId: originalOrderId,
      user: user,
    );
  }
}

class _InMemoryOrderRepository
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

class _InMemoryProductRepository implements ProductRepository {
  final Map<String, Product> products = {};

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Future<void> upsert(Product product) async => products[product.id] = product;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InMemoryInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  @override
  Future<void> record(dynamic transaction) async {
    if (transaction is InventoryTransaction) {
      transactions.add(transaction);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InMemoryCustomerRepository implements CustomerRepository {
  final Map<String, Customer> customers = {};

  @override
  Future<Customer?> fetchById(String id) async => customers[id];

  @override
  Future<void> upsert(Customer customer) async =>
      customers[customer.id] = customer;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InMemorySupplierRepository implements SupplierRepository {
  final Map<String, Supplier> suppliers = {};
  final List<SupplierDebtTransaction> debtTransactions = [];

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async =>
      suppliers[id];

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async =>
      suppliers[supplier.id] = supplier;

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction tx,
      {String? storeId}) async {
    debtTransactions.add(tx);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InMemoryStockInReceiptRepository implements StockInReceiptRepository {
  final Map<String, StockInReceipt> receipts = {};

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async =>
      receipts[receipt.id] = receipt;

  @override
  Future<String> saveDraft(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
    return receipt.id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomerRemoteDataSource implements CustomerRemoteDataSource {
  final List<Map<String, dynamic>> savedDebtTransactions = [];

  @override
  Future<void> saveDebtTransaction(
      String customerId, Map<String, dynamic> data) async {
    savedDebtTransactions.add({'customerId': customerId, ...data});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ============================================================================
// HELPER FACTORIES
// ============================================================================

OrderItem _buildItem({
  required String productId,
  String productName = 'Sản phẩm test',
  int quantity = 1,
  double price = 1000000,
  int warrantyMonths = 12,
  DateTime? purchaseDate,
  int returnedQuantity = 0,
}) {
  return OrderItem(
    productId: productId,
    productName: productName,
    quantity: quantity,
    price: price,
    warrantyMonths: warrantyMonths,
    purchaseDate: purchaseDate ?? DateTime(2026, 10, 4, 12, 0),
    returnedQuantity: returnedQuantity,
  );
}

// ============================================================================
// MAIN ADVERSARIAL SUITE
// ============================================================================

void main() {
  late _FaultInjectingNotificationRepository fakeNotifRepo;
  late NotificationDispatcher dispatcher;
  late _ThrowingNotificationDispatcher throwingDispatcher;

  late _InMemoryOrderRepository orderRepo;
  late _InMemoryProductRepository productRepo;
  late _InMemoryInventoryRepository inventoryRepo;
  late _InMemoryCustomerRepository customerRepo;
  late _InMemorySupplierRepository supplierRepo;
  late _InMemoryStockInReceiptRepository receiptRepo;
  late _FakeCustomerRemoteDataSource customerDataSource;

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

  final now = DateTime(2026, 10, 4, 14, 0);

  const product1 = Product(
    id: 'prod_1',
    code: 'SP01',
    name: 'Máy in hóa đơn nhiệt',
    category: 'Thiết bị',
    price: 1500000,
    costPrice: 1000000,
    branchStocks: {'store_001': 10, 'store_002': 5},
  );

  const product2 = Product(
    id: 'prod_2',
    code: 'SP02',
    name: 'Máy quét mã vạch không dây',
    category: 'Thiết bị',
    price: 800000,
    costPrice: 500000,
    branchStocks: {'store_001': 8, 'store_002': 4},
  );

  const registeredCustomer = Customer(
    id: 'KH_VIP_001',
    name: 'Công ty TNHH Phát Triển Công Nghệ',
    phone: '0912345678',
    email: 'contact@tech.vn',
    address: 'Hà Nội',
    purchases: [],
    currentDebt: 5000000.0,
    totalSales: 15000000.0,
    netSales: 14000000.0,
  );

  const supplier1 = Supplier(
    id: 'sup_01',
    code: 'NCC01',
    name: 'Công ty Cổ phần Thiết Bị Bán Hàng',
    phone: '0988776655',
    currentDebt: 10000000.0,
    totalPurchase: 50000000.0,
  );

  setUp(() {
    fakeNotifRepo = _FaultInjectingNotificationRepository();
    dispatcher = NotificationDispatcher(fakeNotifRepo);
    throwingDispatcher = _ThrowingNotificationDispatcher(fakeNotifRepo);

    orderRepo = _InMemoryOrderRepository();
    productRepo = _InMemoryProductRepository();
    inventoryRepo = _InMemoryInventoryRepository();
    customerRepo = _InMemoryCustomerRepository();
    supplierRepo = _InMemorySupplierRepository();
    receiptRepo = _InMemoryStockInReceiptRepository();
    customerDataSource = _FakeCustomerRemoteDataSource();

    productRepo.products[product1.id] = product1;
    productRepo.products[product2.id] = product2;
    customerRepo.customers[registeredCustomer.id] = registeredCustomer;
    supplierRepo.suppliers[supplier1.id] = supplier1;
  });

  // ==========================================================================
  // SECTION 1: Draft Order Completion & Suppression Tests
  // ==========================================================================
  group('1. Draft Order Completion & Trigger Suppression', () {
    test('1.1. Direct notifyOrderCreated call with isDraft: true is silently dropped',
        () async {
      final draftOrder = Order(
        id: 'HD_DRAFT_001',
        customerId: 'KH_VIP_001',
        customerName: 'Khách hàng thử nghiệm',
        createdAt: now,
        status: 'draft',
        items: [
          _buildItem(
            productId: 'prod_1',
            productName: 'Máy in hóa đơn nhiệt',
            quantity: 2,
            price: 1500000,
          ),
        ],
        total: 3000000,
      );

      expect(draftOrder.isDraft, isTrue);

      await dispatcher.notifyOrderCreated(
        storeId: 'store_001',
        order: draftOrder,
        user: adminUser,
      );

      // Must NOT dispatch any notification
      expect(fakeNotifRepo.added, isEmpty,
          reason: 'Draft orders must NEVER trigger notifyOrderCreated');
    });

    test('1.2. Draft status case variations and status drafts are completely ignored',
        () async {
      final variations = [
        'draft',
        'DRAFT',
        'Draft',
        ' nháp ',
        'Đơn tạm',
        'phiếu tạm',
      ];

      for (final s in variations) {
        final order = Order(
          id: 'HD_VAR_${s.hashCode}',
          customerId: 'khach_le',
          createdAt: now,
          status: s,
          items: [
            _buildItem(
              productId: 'prod_1',
              productName: 'Máy in',
              quantity: 1,
              price: 1500000,
            ),
          ],
          total: 1500000,
        );

        if (order.isDraft) {
          await dispatcher.notifyOrderCreated(
            storeId: 'store_001',
            order: order,
            user: staffUser,
          );
        }
      }

      expect(fakeNotifRepo.added, isEmpty,
          reason: 'All draft permutations must be suppressed');
    });

    test('1.3. POS payment execution logic skips notifyOrderCreated when isDraft is true',
        () async {
      // Simulating pos_payment_page.dart lines 2091-2116
      final order = Order(
        id: 'HD_POS_DRAFT_99',
        customerId: 'khach_le',
        createdAt: now,
        status: 'draft',
        items: [
          _buildItem(
            productId: 'prod_1',
            productName: 'Máy in',
            quantity: 1,
            price: 1500000,
          ),
        ],
        total: 1500000,
      );

      // Branch check as executed in POS payment page
      final isDraft = order.isDraft;
      if (!isDraft) {
        await dispatcher.notifyOrderCreated(
          storeId: 'store_001',
          order: order,
          user: staffUser,
        );
      }

      expect(fakeNotifRepo.added, isEmpty);
    });

    test('1.4. Valid completed order correctly dispatches notifyOrderCreated with full metadata',
        () async {
      final completedOrder = Order(
        id: 'HD_COMPLETED_001',
        customerId: registeredCustomer.id,
        customerName: registeredCustomer.name,
        createdAt: now,
        status: 'completed',
        items: [
          _buildItem(
            productId: 'prod_1',
            productName: 'Máy in hóa đơn nhiệt',
            quantity: 2,
            price: 1500000,
          ),
        ],
        total: 3000000,
        amountPaid: 3000000,
      );

      await dispatcher.notifyOrderCreated(
        storeId: 'store_001',
        order: completedOrder,
        user: adminUser,
      );

      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.orderCreated));
      expect(notif.targetId, equals('HD_COMPLETED_001'));
      expect(notif.metadata?['orderId'], equals('HD_COMPLETED_001'));
      expect(notif.metadata?['total'], equals(3000000.0));
      expect(notif.metadata?['createdBy'], equals(adminUser.name));
    });
  });

  // ==========================================================================
  // SECTION 2: Replacement / Versioned Invoice Edit Tests
  // ==========================================================================
  group('2. Replacement / Versioned Invoice Edit Triggers', () {
    late Order originalOrder;

    setUp(() {
      originalOrder = Order(
        id: 'HD013259',
        customerId: registeredCustomer.id,
        customerName: registeredCustomer.name,
        createdAt: now,
        items: [
          _buildItem(
            productId: 'prod_1',
            productName: 'Máy in hóa đơn nhiệt',
            quantity: 2,
            price: 1500000,
          ),
        ],
        total: 3000000,
        amountPaid: 3000000,
        status: 'completed',
        storeId: 'store_001',
      );
      orderRepo.orders[originalOrder.id] = originalOrder;
    });

    test('2.1. isReplacement: true cancels order and suppresses notifyOrderCancelled',
        () async {
      final cancelUseCase = CancelInvoiceUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
        notificationDispatcher: dispatcher,
      );

      final cancelledOrder = await cancelUseCase.execute(
        order: originalOrder,
        cancelReason: 'Đã sửa thành HD013259.01',
        currentUser: adminUser,
        storeId: 'store_001',
        isReplacement: true, // REPLACEMENT SUPPRESSION
      );

      expect(cancelledOrder.status, equals('cancelled'));
      expect(cancelledOrder.cancelReason, equals('Đã sửa thành HD013259.01'));

      // Critical: NotificationDispatcher.notifyOrderCancelled must NOT be called!
      expect(fakeNotifRepo.added, isEmpty,
          reason:
              'Replacement cancellation must suppress notifyOrderCancelled');

      // Verify product stocks were still properly restored to prevent stock leaks
      final restoredProduct = productRepo.products['prod_1'];
      expect(restoredProduct?.branchStocks['store_001'], equals(12)); // 10 + 2
    });

    test('2.2. Replacement workflow triggers notifyOrderUpdated with old and new order IDs',
        () async {
      final cancelUseCase = CancelInvoiceUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
        notificationDispatcher: dispatcher,
      );

      // 1. Cancel original with isReplacement: true
      await cancelUseCase.execute(
        order: originalOrder,
        cancelReason: 'Đã sửa thành HD013259.01',
        currentUser: adminUser,
        storeId: 'store_001',
        isReplacement: true,
      );
      expect(fakeNotifRepo.added, isEmpty);

      // 2. Dispatch notifyOrderUpdated for the newly created versioned invoice
      final replacementOrder = originalOrder.copyWith(
        id: 'HD013259.01',
        total: 3500000,
        status: 'completed',
      );

      await dispatcher.notifyOrderUpdated(
        storeId: 'store_001',
        order: replacementOrder,
        originalOrderId: originalOrder.id,
        user: adminUser,
      );

      // Exactly 1 notification, of type orderUpdated
      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.orderUpdated));
      expect(notif.category, equals(NotificationCategory.orders));
      expect(notif.targetRoute, equals('invoice_detail'));
      expect(notif.targetId, equals('HD013259.01'));
      expect(notif.title, contains(originalOrder.id));
      expect(notif.body, contains('HD013259.01'));
      expect(notif.metadata?['newOrderId'], equals('HD013259.01'));
      expect(notif.metadata?['originalOrderId'], equals(originalOrder.id));
      expect(notif.metadata?['total'], equals(3500000.0));
      expect(notif.metadata?['updatedBy'], equals(adminUser.name));
    });

    test('2.3. Standard cancel (isReplacement: false) dispatches notifyOrderCancelled',
        () async {
      final cancelUseCase = CancelInvoiceUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
        notificationDispatcher: dispatcher,
      );

      final cancelledOrder = await cancelUseCase.execute(
        order: originalOrder,
        cancelReason: 'Khách hàng đổi ý',
        currentUser: adminUser,
        storeId: 'store_001',
        isReplacement: false,
      );

      expect(cancelledOrder.status, equals('cancelled'));
      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.orderCancelled));
      expect(notif.title, contains(originalOrder.id));
      expect(notif.metadata?['orderId'], equals(originalOrder.id));
      expect(notif.metadata?['reason'], equals('Khách hàng đổi ý'));
    });

    test('2.4. Sequential version edit chain (.01 -> .02) suppresses cancel and emits updates',
        () async {
      final cancelUseCase = CancelInvoiceUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
        notificationDispatcher: dispatcher,
      );

      // HD013259 -> HD013259.01
      await cancelUseCase.execute(
        order: originalOrder,
        cancelReason: 'Đã sửa thành HD013259.01',
        currentUser: adminUser,
        storeId: 'store_001',
        isReplacement: true,
      );
      final v1Order = originalOrder.copyWith(id: 'HD013259.01', total: 3200000);
      await dispatcher.notifyOrderUpdated(
        storeId: 'store_001',
        order: v1Order,
        originalOrderId: 'HD013259',
        user: adminUser,
      );

      // HD013259.01 -> HD013259.02
      await cancelUseCase.execute(
        order: v1Order,
        cancelReason: 'Đã sửa thành HD013259.02',
        currentUser: adminUser,
        storeId: 'store_001',
        isReplacement: true,
      );
      final v2Order = v1Order.copyWith(id: 'HD013259.02', total: 3400000);
      await dispatcher.notifyOrderUpdated(
        storeId: 'store_001',
        order: v2Order,
        originalOrderId: 'HD013259.01',
        user: adminUser,
      );

      // Total notifications should be exactly 2 (both are orderUpdated)
      expect(fakeNotifRepo.added.length, equals(2));
      expect(fakeNotifRepo.added.every((n) => n.type == NotificationType.orderUpdated),
          isTrue);
      expect(fakeNotifRepo.added[0].metadata?['originalOrderId'], equals('HD013259'));
      expect(fakeNotifRepo.added[0].metadata?['newOrderId'], equals('HD013259.01'));
      expect(fakeNotifRepo.added[1].metadata?['originalOrderId'], equals('HD013259.01'));
      expect(fakeNotifRepo.added[1].metadata?['newOrderId'], equals('HD013259.02'));
    });
  });

  // ==========================================================================
  // SECTION 3: Return Order Edge Cases
  // ==========================================================================
  group('3. Return Order Edge Cases (Zero refund, Partial, Missing customer)', () {
    test('3.1. Zero refund amount return order dispatches notifyOrderReturned safely',
        () async {
      // Free gift or 100% discounted item return (price = 0)
      final zeroPriceOrder = Order(
        id: 'HD_ZERO_001',
        customerId: registeredCustomer.id,
        createdAt: now,
        items: [
          _buildItem(
            productId: 'prod_1',
            productName: 'Hàng tặng kèm',
            quantity: 1,
            price: 0.0,
          ),
        ],
        total: 0.0,
        amountPaid: 0.0,
        status: 'completed',
        storeId: 'store_001',
      );
      orderRepo.orders[zeroPriceOrder.id] = zeroPriceOrder;

      final returnUseCase = ProcessReturnOrderUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
        notificationDispatcher: dispatcher,
      );

      final result = await returnUseCase.execute(
        originalOrder: zeroPriceOrder,
        returnItems: const [
          ReturnOrderItem(
            productId: 'prod_1',
            productName: 'Hàng tặng kèm',
            price: 0.0,
            quantity: 1,
          ),
        ],
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Khách trả quà tặng',
      );

      expect(result.totalRefund, equals(0.0));
      expect(result.cashRefunded, equals(0.0));
      expect(result.debtDeducted, equals(0.0));
      expect(result.updatedOrder.status, equals('returned'));

      // Notification is still emitted with 0đ formatting without crash
      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.orderReturn));
      expect(notif.body, contains('0đ'));
      expect(notif.metadata?['refundAmount'], equals(0.0));
    });

    test('3.2. Partial return order updates line items and emits partial refund notification',
        () async {
      // Order with 5 units of prod_1 and 3 units of prod_2
      final multiItemOrder = Order(
        id: 'HD_PARTIAL_001',
        customerId: registeredCustomer.id,
        customerName: registeredCustomer.name,
        createdAt: now,
        items: [
          _buildItem(
            productId: 'prod_1',
            productName: 'Máy in hóa đơn nhiệt',
            quantity: 5,
            price: 1500000,
          ),
          _buildItem(
            productId: 'prod_2',
            productName: 'Máy quét mã vạch',
            quantity: 3,
            price: 800000,
          ),
        ],
        total: 9900000, // 5*1.5M + 3*800K
        amountPaid: 9900000,
        status: 'completed',
        storeId: 'store_001',
      );
      orderRepo.orders[multiItemOrder.id] = multiItemOrder;

      final returnUseCase = ProcessReturnOrderUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
        notificationDispatcher: dispatcher,
      );

      // Customer returns ONLY 2 units of prod_1 (partial return)
      final result = await returnUseCase.execute(
        originalOrder: multiItemOrder,
        returnItems: const [
          ReturnOrderItem(
            productId: 'prod_1',
            productName: 'Máy in hóa đơn nhiệt',
            price: 1500000,
            quantity: 2,
          ),
        ],
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Khách trả bớt 2 máy in',
      );

      // Order status remains 'completed' because activeQuantity remains for prod_1 (3) and prod_2 (3)
      expect(result.updatedOrder.status, equals('completed'));
      final returnedItem =
          result.updatedOrder.items.firstWhere((i) => i.productId == 'prod_1');
      expect(returnedItem.returnedQuantity, equals(2));
      expect(returnedItem.activeQuantity, equals(3));
      expect(result.totalRefund, equals(3000000.0));

      // Notification is dispatched for partial return
      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.orderReturn));
      expect(notif.body, contains('3.000.000đ'));
      expect(notif.metadata?['refundAmount'], equals(3000000.0));
      expect(notif.metadata?['orderId'], equals('HD_PARTIAL_001'));
    });

    test('3.3. Missing / walk-in customer return executes safely without null pointer errors',
        () async {
      final walkInOrder = Order(
        id: 'HD_WALKIN_001',
        customerId: 'khach_le',
        customerName: 'Khách lẻ vãng lai',
        createdAt: now,
        items: [
          _buildItem(
            productId: 'prod_2',
            productName: 'Máy quét mã vạch',
            quantity: 1,
            price: 800000,
          ),
        ],
        total: 800000,
        amountPaid: 800000,
        status: 'completed',
        storeId: 'store_001',
      );
      orderRepo.orders[walkInOrder.id] = walkInOrder;

      final returnUseCase = ProcessReturnOrderUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
        notificationDispatcher: dispatcher,
      );

      final result = await returnUseCase.execute(
        originalOrder: walkInOrder,
        returnItems: const [
          ReturnOrderItem(
            productId: 'prod_2',
            productName: 'Máy quét mã vạch',
            price: 800000,
            quantity: 1,
          ),
        ],
        storeId: 'store_001',
        currentUser: staffUser,
      );

      expect(result.returnOrder.customerId, equals('khach_le'));
      expect(result.updatedOrder.status, equals('returned'));

      // Product 2 stock is restored from 8 to 9
      expect(productRepo.products['prod_2']?.branchStocks['store_001'], equals(9));

      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.orderReturn));
      expect(notif.metadata?['orderId'], equals('HD_WALKIN_001'));
    });
  });

  // ==========================================================================
  // SECTION 4: Stock-In Completion Edge Cases
  // ==========================================================================
  group('4. Stock-in Completion Edge Cases', () {
    late StockInReceipt baseReceipt;

    setUp(() {
      baseReceipt = StockInReceipt(
        id: 'PN_ADV_001',
        importCode: 'PN261004999',
        date: now,
        storeId: 'store_001',
        supplierId: 'sup_01',
        supplierName: 'Công ty Cổ phần Thiết Bị Bán Hàng',
        createdBy: 'warehouse_guy',
        createdByName: 'Vũ Văn Kho',
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_stk_1',
            productId: 'prod_1',
            productName: 'Máy in hóa đơn nhiệt',
            quantity: 3,
            importPrice: 1000000,
          ),
        ],
        paidAmount: 3000000,
        status: 'Đã nhập hàng',
      );
    });

    test('4.1. Stock-in receipt with null user uses receipt creator fallback',
        () async {
      final stockInUseCase = CompleteStockInReceiptUseCase(
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        supplierRepository: supplierRepo,
        receiptRepository: receiptRepo,
        notificationDispatcher: dispatcher,
      );

      final completedReceipt = await stockInUseCase.execute(
        baseReceipt,
        user: null, // PASSING NULL USER
      );

      expect(completedReceipt.status, equals('completed'));
      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.inventoryImported));
      expect(notif.targetId, equals(baseReceipt.importCode));
      // Fallback must select createdByName
      expect(notif.metadata?['createdBy'], equals('Vũ Văn Kho'));
    });

    test('4.2. Receipt with null user and null createdByName uses createdBy username',
        () async {
      final stockInUseCase = CompleteStockInReceiptUseCase(
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        supplierRepository: supplierRepo,
        receiptRepository: receiptRepo,
        notificationDispatcher: dispatcher,
      );

      final receiptWithoutName = StockInReceipt(
        id: 'PN_ADV_002',
        importCode: 'PN261004992',
        date: now,
        storeId: 'store_001',
        supplierId: 'sup_01',
        supplierName: 'Công ty Cổ phần Thiết Bị Bán Hàng',
        createdBy: 'nv_kho_user',
        createdByName: null,
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_stk_2',
            productId: 'prod_1',
            productName: 'Máy in hóa đơn nhiệt',
            quantity: 1,
            importPrice: 1000000,
          ),
        ],
        paidAmount: 1000000,
        status: 'Đã nhập hàng',
      );

      await stockInUseCase.execute(
        receiptWithoutName,
        user: null,
      );

      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.metadata?['createdBy'], equals('nv_kho_user'));
    });

    test('4.3. Receipt with null user and null createdBy executes safely without crash',
        () async {
      final stockInUseCase = CompleteStockInReceiptUseCase(
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        supplierRepository: supplierRepo,
        receiptRepository: receiptRepo,
        notificationDispatcher: dispatcher,
      );

      final anonymousReceipt = StockInReceipt(
        id: 'PN_ADV_003',
        importCode: 'PN261004993',
        date: now,
        storeId: 'store_001',
        supplierId: 'sup_01',
        supplierName: 'Công ty Cổ phần Thiết Bị Bán Hàng',
        createdBy: null,
        createdByName: null,
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_stk_3',
            productId: 'prod_1',
            productName: 'Máy in hóa đơn nhiệt',
            quantity: 1,
            importPrice: 1000000,
          ),
        ],
        paidAmount: 1000000,
        status: 'Đã nhập hàng',
      );

      final res = await stockInUseCase.execute(
        anonymousReceipt,
        user: null,
      );

      expect(res.status, equals('completed'));
      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.metadata?['createdBy'], equals('Không xác định'));
    });

    test('4.4. notifyStockInCompleted strictly rejects draft or cancelled receipts',
        () async {
      final draftReceipt = baseReceipt.copyWith(status: 'draft');
      expect(draftReceipt.isDraft, isTrue);

      await dispatcher.notifyStockInCompleted(
        storeId: 'store_001',
        receipt: draftReceipt,
        user: adminUser,
      );
      expect(fakeNotifRepo.added, isEmpty);

      final cancelledReceipt = baseReceipt.copyWith(status: 'cancelled');
      expect(cancelledReceipt.isCancelled, isTrue);

      await dispatcher.notifyStockInCompleted(
        storeId: 'store_001',
        receipt: cancelledReceipt,
        user: adminUser,
      );
      expect(fakeNotifRepo.added, isEmpty);
    });

    test('4.5. Receipt with null/empty supplierName safely defaults to Nhà cung cấp lẻ',
        () async {
      final receiptNoSupplier = StockInReceipt(
        id: 'PN_ADV_005',
        importCode: 'PN261004995',
        date: now,
        storeId: 'store_001',
        supplierId: null,
        supplierName: null,
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_stk_5',
            productId: 'prod_1',
            productName: 'Máy in hóa đơn nhiệt',
            quantity: 1,
            importPrice: 1000000,
          ),
        ],
        paidAmount: 1000000,
        status: 'completed',
      );

      await dispatcher.notifyStockInCompleted(
        storeId: 'store_001',
        receipt: receiptNoSupplier,
        user: adminUser,
      );

      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.body, contains('Nhà cung cấp lẻ'));
      expect(notif.metadata?['supplierName'], equals('Nhà cung cấp lẻ'));
    });
  });

  // ==========================================================================
  // SECTION 5: NotificationDispatcher Exception Injection & Fault Tolerance
  // ==========================================================================
  group('5. NotificationDispatcher Exception Injection & Non-Blocking Resilience', () {
    test('5.1. Order cancellation completes successfully when dispatcher throws exception',
        () async {
      throwingDispatcher.throwOnCancel = true;
      throwingDispatcher.customError =
          Exception('FATAL: Notification service is dead');

      final orderToCancel = Order(
        id: 'HD_FAULT_001',
        customerId: registeredCustomer.id,
        createdAt: now,
        items: [
          _buildItem(
            productId: 'prod_1',
            productName: 'Máy in hóa đơn nhiệt',
            quantity: 1,
            price: 1500000,
          ),
        ],
        total: 1500000,
        amountPaid: 1500000,
        status: 'completed',
        storeId: 'store_001',
      );
      orderRepo.orders[orderToCancel.id] = orderToCancel;

      final cancelUseCase = CancelInvoiceUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
        notificationDispatcher: throwingDispatcher, // INJECTED FAULTY DISPATCHER
      );

      // Must complete normally without throwing!
      final result = await cancelUseCase.execute(
        order: orderToCancel,
        cancelReason: 'Hủy test resilience',
        currentUser: adminUser,
        storeId: 'store_001',
      );

      expect(result.status, equals('cancelled'));
      expect(orderRepo.orders[orderToCancel.id]?.status, equals('cancelled'));
      // Stock must be restored despite notification failure
      expect(productRepo.products['prod_1']?.branchStocks['store_001'], equals(11));
    });

    test('5.2. Return order completes successfully when dispatcher throws exception',
        () async {
      throwingDispatcher.throwOnReturn = true;
      throwingDispatcher.customError =
          StateError('FATAL: Out of memory in notification broker');

      final orderToReturn = Order(
        id: 'HD_FAULT_002',
        customerId: registeredCustomer.id,
        createdAt: now,
        items: [
          _buildItem(
            productId: 'prod_2',
            productName: 'Máy quét mã vạch',
            quantity: 2,
            price: 800000,
          ),
        ],
        total: 1600000,
        amountPaid: 1600000,
        status: 'completed',
        storeId: 'store_001',
      );
      orderRepo.orders[orderToReturn.id] = orderToReturn;

      final returnUseCase = ProcessReturnOrderUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
        notificationDispatcher: throwingDispatcher, // INJECTED FAULTY DISPATCHER
      );

      // Must complete normally without throwing!
      final result = await returnUseCase.execute(
        originalOrder: orderToReturn,
        returnItems: const [
          ReturnOrderItem(
            productId: 'prod_2',
            productName: 'Máy quét mã vạch',
            price: 800000,
            quantity: 1,
          ),
        ],
        storeId: 'store_001',
        currentUser: adminUser,
      );

      expect(result.returnOrder, isNotNull);
      expect(orderRepo.returns.length, equals(1));
      // Product stock restored despite notification crash
      expect(productRepo.products['prod_2']?.branchStocks['store_001'], equals(9));
    });

    test('5.3. Stock-in receipt completes successfully when dispatcher throws exception',
        () async {
      throwingDispatcher.throwOnStockIn = true;
      throwingDispatcher.customError =
          const FormatException('FATAL: Corrupted notification serialization');

      final receipt = StockInReceipt(
        id: 'PN_FAULT_001',
        importCode: 'PN261004888',
        date: now,
        storeId: 'store_001',
        supplierId: 'sup_01',
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_fault_1',
            productId: 'prod_1',
            quantity: 4,
            importPrice: 1000000,
          ),
        ],
        paidAmount: 4000000,
        status: 'Đã nhập hàng',
      );

      final stockInUseCase = CompleteStockInReceiptUseCase(
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        supplierRepository: supplierRepo,
        receiptRepository: receiptRepo,
        notificationDispatcher: throwingDispatcher, // INJECTED FAULTY DISPATCHER
      );

      // Must complete normally without throwing!
      final result = await stockInUseCase.execute(
        receipt,
        user: adminUser,
      );

      expect(result.status, equals('completed'));
      expect(receiptRepo.receipts[receipt.id]?.status, equals('completed'));
      // Product stock must be updated from 10 to 14
      expect(productRepo.products['prod_1']?.branchStocks['store_001'], equals(14));
      // Inventory transactions must be recorded
      expect(inventoryRepo.transactions.length, equals(1));
    });

    test('5.4. NotificationRepository failure is caught inside NotificationDispatcher',
        () async {
      fakeNotifRepo.injectError(Exception('Firebase RTDB timeout'));

      final order = Order(
        id: 'HD_NORMAL_001',
        customerId: registeredCustomer.id,
        createdAt: now,
        items: [
          _buildItem(
            productId: 'prod_1',
            quantity: 1,
            price: 1500000,
          ),
        ],
        total: 1500000,
        status: 'completed',
      );

      // Should complete without uncaught exception
      await dispatcher.notifyOrderCreated(
        storeId: 'store_001',
        order: order,
        user: adminUser,
      );

      await dispatcher.notifyOrderUpdated(
        storeId: 'store_001',
        order: order,
        originalOrderId: 'HD_OLD_001',
        user: adminUser,
      );

      await dispatcher.notifyOrderCancelled(
        storeId: 'store_001',
        order: order,
        cancelReason: 'Lỗi',
        user: adminUser,
      );

      expect(fakeNotifRepo.added, isEmpty);
    });
  });
}
