import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventory/inter_store_transfer_service.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/application/orders/usecases/collect_invoice_debt_usecase.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/core/errors/exceptions.dart';
import 'package:stores/data/datasources/firebase/customer_remote_data_source.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';

import '../support/firebase_test_harness.dart';

// ============================================================================
// IN-MEMORY FAKE REPOSITORIES FOR ISOLATED EMPIRICAL STRESS TESTING
// ============================================================================

class FakeOrderRepository implements OrderRepository, OrderRepositoryReturnHandler {
  final Map<String, Order> orders = {};
  final Map<String, ReturnOrder> returnOrders = {};

  @override
  Future<void> create(Order order) async => orders[order.id] = order;

  @override
  Future<void> update(Order order) async => orders[order.id] = order;

  @override
  Future<void> delete(String orderId) async => orders.remove(orderId);

  @override
  Future<Order?> fetchById(String orderId) async => orders[orderId];

  @override
  Stream<List<Order>> watchAll() => Stream.value(orders.values.toList());

  @override
  Stream<List<Order>> watchByCustomer(String customerId) =>
      Stream.value(orders.values.where((o) => o.customerId == customerId).toList());

  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) =>
      Stream.value(orders.values.toList());

  @override
  Future<void> createReturn(ReturnOrder returnOrder) async =>
      returnOrders[returnOrder.id] = returnOrder;

  @override
  Future<ReturnOrder?> fetchReturnById(String returnId) async =>
      returnOrders[returnId];

  @override
  Stream<List<ReturnOrder>> watchReturnsByDateRange(
          DateTime start, DateTime end) =>
      Stream.value(returnOrders.values.toList());

  @override
  Stream<List<ReturnOrder>> watchReturnsByOrderId(String orderId) =>
      Stream.value(returnOrders.values.where((r) => r.orderId == orderId).toList());
}

class FakeProductRepository implements ProductRepository {
  final Map<String, Product> products = {};

  @override
  Future<void> delete(String id) async => products.remove(id);

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<void> updateStock(String id, int newStock) async {
    final p = products[id];
    if (p != null) {
      products[id] = p.copyWith(branchStocks: {'store_001': newStock});
    }
  }

  @override
  Future<void> upsert(Product product) async => products[product.id] = product;

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());
}

class FakeInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async => transactions.add(tx);

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(transactions.where((t) => t.productId == productId).toList());

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime startDate, DateTime endDate) =>
      Stream.value(transactions);
}

class FakeCustomerRepository implements CustomerRepository {
  final Map<String, Customer> customers = {};

  @override
  Future<void> delete(String id) async => customers.remove(id);

  @override
  Future<Customer?> fetchById(String id) async => customers[id];

  @override
  Future<void> upsert(Customer customer) async =>
      customers[customer.id] = customer;

  @override
  Stream<List<Customer>> watchAll() => Stream.value(customers.values.toList());
}

// ============================================================================
// ADVERSARIAL TEST SUITE
// ============================================================================

void main() {
  late MockFirebaseDatabase mockDb;
  late CustomerRemoteDataSource customerDataSource;
  late FakeOrderRepository orderRepo;
  late FakeProductRepository productRepo;
  late FakeInventoryRepository inventoryRepo;
  late FakeCustomerRepository customerRepo;

  late CancelInvoiceUseCase cancelInvoiceUseCase;
  late CollectInvoiceDebtUseCase collectDebtUseCase;
  late ProcessReturnOrderUseCase processReturnOrderUseCase;
  late InterStoreTransferService interStoreTransferService;

  const adminUser = UserAccount(
    username: 'super_admin',
    displayName: 'Quản Trị Viên Trưởng',
    role: 'admin',
    storeId: 'store_001',
  );

  const cashierUser = UserAccount(
    username: 'staff_cashier',
    displayName: 'Thu Ngân Viên',
    role: 'staff',
    storeId: 'store_001',
  );

  final testDate = DateTime(2026, 9, 19, 10, 0);

  setUp(() {
    mockDb = MockFirebaseDatabase();
    customerDataSource = CustomerRemoteDataSource(mockDb);

    orderRepo = FakeOrderRepository();
    productRepo = FakeProductRepository();
    inventoryRepo = FakeInventoryRepository();
    customerRepo = FakeCustomerRepository();

    cancelInvoiceUseCase = CancelInvoiceUseCase(
      orderRepository: orderRepo,
      productRepository: productRepo,
      inventoryRepository: inventoryRepo,
      customerRepository: customerRepo,
      customerDataSource: customerDataSource,
    );

    collectDebtUseCase = CollectInvoiceDebtUseCase(
      orderRepository: orderRepo,
      customerRepository: customerRepo,
      customerDataSource: customerDataSource,
    );

    processReturnOrderUseCase = ProcessReturnOrderUseCase(
      orderRepository: orderRepo,
      productRepository: productRepo,
      inventoryRepository: inventoryRepo,
      customerRepository: customerRepo,
      customerDataSource: customerDataSource,
    );

    interStoreTransferService = InterStoreTransferService(mockDb);
  });

  // ==========================================================================
  // SECTION 1: CANCEL INVOICE STRESS
  // ==========================================================================
  group('1. Cancel Invoice Adversarial Stress Tests', () {
    test('Cancelling already cancelled orders throws ValidationException and prevents double stock restoration or debt decrement', () async {
      // Setup product with 10 units in store_001
      const product = Product(
        id: 'PROD_MONITOR',
        name: 'Màn hình 27 inch 4K',
        code: 'MH27',
        price: 8000000,
        costPrice: 6000000,
        branchStocks: {'store_001': 10},
        category: 'Màn hình',
      );
      await productRepo.upsert(product);

      // Customer with 5,000,000 preexisting debt
      const customer = Customer(
        id: 'CUST_STRESS_1',
        name: 'Nguyễn Văn Stress',
        phone: '0901112233',
        email: 'stress1@example.com',
        address: 'Hà Nội',
        purchases: [],
        currentDebt: 5000000,
        totalSales: 20000000,
        netSales: 20000000,
      );
      await customerRepo.upsert(customer);

      // Order with 2 monitors, debt 3,000,000
      final initialOrder = Order(
        id: 'HD_CANCEL_001',
        customerId: 'CUST_STRESS_1',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'PROD_MONITOR',
            productName: 'Màn hình 27 inch 4K',
            quantity: 2,
            price: 8000000,
            warrantyMonths: 24,
            purchaseDate: testDate,
          ),
        ],
        total: 16000000,
        amountPaid: 13000000,
        debtAmount: 3000000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(initialOrder);

      // 1. First Cancellation: Should succeed
      final cancelledOrder = await cancelInvoiceUseCase.execute(
        order: initialOrder,
        cancelReason: 'Khách yêu cầu hủy do đổi ý',
        currentUser: adminUser,
        storeId: 'store_001',
      );

      expect(cancelledOrder.status, 'cancelled');
      expect(cancelledOrder.isCancelled, true);

      // Stock should have been restored: 10 + 2 = 12
      final prodAfterFirstCancel = await productRepo.fetchById('PROD_MONITOR');
      expect(prodAfterFirstCancel?.branchStocks['store_001'], 12);
      expect(inventoryRepo.transactions.length, 1);

      // Customer debt decreased: 5,000,000 - 3,000,000 = 2,000,000
      final custAfterFirstCancel = await customerRepo.fetchById('CUST_STRESS_1');
      expect(custAfterFirstCancel?.currentDebt, 2000000.0);

      // 2. Second Cancellation Attempt on the same order: MUST throw ValidationException
      expect(
        () async => await cancelInvoiceUseCase.execute(
          order: cancelledOrder,
          cancelReason: 'Cố tình hủy lần 2 để trục lợi kho',
          currentUser: adminUser,
          storeId: 'store_001',
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('Hóa đơn này đã được hủy trước đó'),
          ),
        ),
      );

      // Verify invariants: Stock NOT increased again, customer debt NOT decremented again, no new transaction
      final prodAfterSecondAttempt = await productRepo.fetchById('PROD_MONITOR');
      expect(prodAfterSecondAttempt?.branchStocks['store_001'], 12,
          reason: 'Stock must remain at 12 and not double-increment');
      expect(inventoryRepo.transactions.length, 1,
          reason: 'No duplicate inventory transactions allowed');
      final custAfterSecondAttempt = await customerRepo.fetchById('CUST_STRESS_1');
      expect(custAfterSecondAttempt?.currentDebt, 2000000.0,
          reason: 'Customer debt must not be decremented again');
    });

    test('Cancelling order with combo items restores child components even when component stock was exactly 0 or negative', () async {
      // Child component 1: CPU with 0 branch stock in store_001
      const childCpu = Product(
        id: 'P_CPU_I9',
        name: 'Intel Core i9 14900K',
        code: 'CPU_I9',
        price: 15000000,
        costPrice: 12000000,
        branchStocks: {'store_001': 0},
        category: 'Linh kiện',
      );
      // Child component 2: RAM with negative stock (-2) due to overselling
      const childRam = Product(
        id: 'P_RAM_64G',
        name: 'Corsair DDR5 64GB',
        code: 'RAM_64G',
        price: 6000000,
        costPrice: 4500000,
        branchStocks: {'store_001': -2},
        category: 'Linh kiện',
      );

      // Combo product: "Bộ Máy Tính Khủng" (1 CPU + 2 RAM)
      const comboProduct = Product(
        id: 'P_COMBO_STATION',
        name: 'Bộ Máy Tính Workstation',
        code: 'WS_2026',
        price: 30000000,
        costPrice: 21000000,
        branchStocks: {'store_001': 0},
        category: 'Máy bộ',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'P_CPU_I9',
            productCode: 'CPU_I9',
            productName: 'Intel Core i9 14900K',
            quantity: 1,
          ),
          ComboComponent(
            productId: 'P_RAM_64G',
            productCode: 'RAM_64G',
            productName: 'Corsair DDR5 64GB',
            quantity: 2,
          ),
        ],
      );

      await productRepo.upsert(childCpu);
      await productRepo.upsert(childRam);
      await productRepo.upsert(comboProduct);

      // Order with 3 combos: requires 3 x 1 = 3 CPUs and 3 x 2 = 6 RAMs
      final comboOrder = Order(
        id: 'HD_COMBO_CANCEL_002',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_COMBO_STATION',
            productName: 'Bộ Máy Tính Workstation',
            quantity: 3,
            price: 30000000,
            warrantyMonths: 36,
            purchaseDate: testDate,
          ),
        ],
        total: 90000000,
        amountPaid: 90000000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(comboOrder);

      // Cancel the combo invoice
      final result = await cancelInvoiceUseCase.execute(
        order: comboOrder,
        cancelReason: 'Doanh nghiệp hủy hợp đồng dự án',
        currentUser: adminUser,
        storeId: 'store_001',
      );

      expect(result.status, 'cancelled');

      // Verify CPU stock: 0 + (3 * 1) = 3
      final updatedCpu = await productRepo.fetchById('P_CPU_I9');
      expect(updatedCpu?.branchStocks['store_001'], 3);

      // Verify RAM stock: -2 + (3 * 2) = -2 + 6 = 4
      final updatedRam = await productRepo.fetchById('P_RAM_64G');
      expect(updatedRam?.branchStocks['store_001'], 4);

      // Verify 2 separate inventory import transactions were logged
      expect(inventoryRepo.transactions.length, 2);
      final cpuTx = inventoryRepo.transactions
          .firstWhere((t) => t.productId == 'P_CPU_I9');
      expect(cpuTx.quantity, 3);
      expect(cpuTx.type, TransactionType.import);
      expect(cpuTx.note, contains('Combo: Bộ Máy Tính Workstation'));

      final ramTx = inventoryRepo.transactions
          .firstWhere((t) => t.productId == 'P_RAM_64G');
      expect(ramTx.quantity, 6);
      expect(ramTx.type, TransactionType.import);
      expect(ramTx.note, contains('Combo: Bộ Máy Tính Workstation'));
    });

    test('Cancelling order with zero debt or negative debt preserves customer debt and records no false debt reversal transactions', () async {
      const customer = Customer(
        id: 'CUST_ZERO_DEBT',
        name: 'Đoàn Thanh Toán Đầy Đủ',
        phone: '0988776655',
        email: 'doan@example.com',
        address: 'Đà Nẵng',
        purchases: [],
        currentDebt: 4500000, // Preexisting debt from other invoices
        totalSales: 15000000,
        netSales: 15000000,
      );
      await customerRepo.upsert(customer);

      // Case A: Fully paid order (debtAmount = 0.0, remainingDebt = 0.0)
      final zeroDebtOrder = Order(
        id: 'HD_ZERO_DEBT',
        customerId: 'CUST_ZERO_DEBT',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_GENERAL',
            productName: 'Tai nghe Bluetooth',
            quantity: 1,
            price: 1500000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 1500000,
        amountPaid: 1500000,
        debtAmount: 0.0,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(zeroDebtOrder);

      await cancelInvoiceUseCase.execute(
        order: zeroDebtOrder,
        cancelReason: 'Hủy đơn đã thanh toán đủ',
        currentUser: adminUser,
        storeId: 'store_001',
      );

      // Customer preexisting debt MUST remain unchanged at 4,500,000
      final custAfterZeroCancel =
          await customerRepo.fetchById('CUST_ZERO_DEBT');
      expect(custAfterZeroCancel?.currentDebt, 4500000.0,
          reason: 'Cancelling a zero-debt order must not alter customer preexisting debt');
      expect(custAfterZeroCancel?.totalSales, 13500000.0);

      // Verify NO CustomerDebtTransaction was written in RTDB (since debtToReverse == 0)
      final debtCalls = mockDb.recorder.callsFor('set').where(
            (c) => c.path.contains('shared_customers/CUST_ZERO_DEBT/debt_transactions'),
          );
      expect(debtCalls.isEmpty, true,
          reason: 'No debt transaction should be recorded when cancelled order had 0 debt');

      // Case B: Corrupted/Dirty negative debt order (amountPaid > total, debtAmount <= 0)
      final dirtyNegativeDebtOrder = Order(
        id: 'HD_NEG_DEBT',
        customerId: 'CUST_ZERO_DEBT',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_GENERAL',
            productName: 'Tai nghe Bluetooth',
            quantity: 1,
            price: 1000000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 1000000,
        amountPaid: 1500000, // overpaid in legacy record
        debtAmount: -500000, // negative debt
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(dirtyNegativeDebtOrder);

      await cancelInvoiceUseCase.execute(
        order: dirtyNegativeDebtOrder,
        cancelReason: 'Hủy đơn có công nợ âm dirty data',
        currentUser: adminUser,
        storeId: 'store_001',
      );

      // Customer debt must NOT increase or corrupt
      final custAfterNegCancel =
          await customerRepo.fetchById('CUST_ZERO_DEBT');
      expect(custAfterNegCancel?.currentDebt, 4500000.0,
          reason: 'Negative debt on invoice must not corrupt customer debt');
    });

    test('Cancel invoice RBAC check: Staff without supervisor or deleteInvoice rights is strictly rejected', () async {
      final validOrder = Order(
        id: 'HD_RBAC_CHECK',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [],
        total: 500000,
        amountPaid: 500000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );

      expect(
        () async => await cancelInvoiceUseCase.execute(
          order: validOrder,
          cancelReason: 'Thu ngân tự ý hủy đơn',
          currentUser: cashierUser, // cashier lacks canDeleteInvoice & isSupervisor
          storeId: 'store_001',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });

  // ==========================================================================
  // SECTION 2: COLLECT DEBT STRESS
  // ==========================================================================
  group('2. Collect Invoice Debt Adversarial Stress Tests', () {
    test('Overpayment exceeding remaining debt is strictly rejected with ValidationException', () async {
      // Order with total 1,000,000, paid 700,000, remainingDebt: 300,000
      final orderWithDebt = Order(
        id: 'HD_DEBT_STRESS_001',
        customerId: 'CUST_DEBTOR_1',
        createdAt: testDate,
        items: [],
        total: 1000000,
        amountPaid: 700000,
        debtAmount: 300000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(orderWithDebt);

      // Attempt 1: Exceeds by 0.05 (beyond the 0.01 floating point threshold)
      expect(
        () async => await collectDebtUseCase.execute(
          order: orderWithDebt,
          amount: 300000.05,
          paymentMethod: 'cash',
          currentUser: adminUser,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('vượt quá công nợ còn lại (300000.0) của hóa đơn'),
          ),
        ),
      );

      // Attempt 2: Massive overpayment attempt
      expect(
        () async => await collectDebtUseCase.execute(
          order: orderWithDebt,
          amount: 5000000,
          paymentMethod: 'transfer',
          currentUser: adminUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      // Attempt 3: Non-positive amounts (0 and negative)
      expect(
        () async => await collectDebtUseCase.execute(
          order: orderWithDebt,
          amount: 0,
          paymentMethod: 'cash',
          currentUser: adminUser,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('Số tiền thu nợ phải lớn hơn 0'),
          ),
        ),
      );
      expect(
        () async => await collectDebtUseCase.execute(
          order: orderWithDebt,
          amount: -50000,
          paymentMethod: 'cash',
          currentUser: adminUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      // Order state must remain intact
      final untouchedOrder = await orderRepo.fetchById('HD_DEBT_STRESS_001');
      expect(untouchedOrder?.amountPaid, 700000.0);
      expect(untouchedOrder?.debtAmount, 300000.0);
    });

    test('Multiple partial collections until debt is exactly 0 maintains zero drift and blocks subsequent collection', () async {
      const customer = Customer(
        id: 'CUST_PARTIAL_PAYER',
        name: 'Lê Văn Từng Phần',
        phone: '0977665544',
        email: 'partial@example.com',
        address: 'Hồ Chí Minh',
        purchases: [],
        currentDebt: 5000000, // Total customer debt
        totalSales: 10000000,
      );
      await customerRepo.upsert(customer);

      // Order with 1,200,000 debt
      var order = Order(
        id: 'HD_MULTI_PARTIAL',
        customerId: 'CUST_PARTIAL_PAYER',
        createdAt: testDate,
        items: [],
        total: 1200000,
        amountPaid: 0,
        debtAmount: 1200000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      // Payment 1: 400,000
      order = await collectDebtUseCase.execute(
        order: order,
        amount: 400000,
        paymentMethod: 'cash',
        currentUser: adminUser,
        note: 'Đợt 1',
      );
      expect(order.amountPaid, 400000.0);
      expect(order.debtAmount, 800000.0);
      expect(order.remainingDebt, 800000.0);
      expect(order.hasDebt, true);

      var cust = (await customerRepo.fetchById('CUST_PARTIAL_PAYER'))!;
      expect(cust.currentDebt, 4600000.0);

      // Payment 2: 500,000
      order = await collectDebtUseCase.execute(
        order: order,
        amount: 500000,
        paymentMethod: 'transfer',
        currentUser: adminUser,
        note: 'Đợt 2',
      );
      expect(order.amountPaid, 900000.0);
      expect(order.debtAmount, 300000.0);
      expect(order.remainingDebt, 300000.0);

      cust = (await customerRepo.fetchById('CUST_PARTIAL_PAYER'))!;
      expect(cust.currentDebt, 4100000.0);

      // Payment 3: 300,000 (Exactly reaches 0)
      order = await collectDebtUseCase.execute(
        order: order,
        amount: 300000,
        paymentMethod: 'cash',
        currentUser: adminUser,
        note: 'Đợt 3 dứt điểm',
      );
      expect(order.amountPaid, 1200000.0);
      expect(order.debtAmount, 0.0);
      expect(order.remainingDebt, 0.0);
      expect(order.hasDebt, false);

      cust = (await customerRepo.fetchById('CUST_PARTIAL_PAYER'))!;
      expect(cust.currentDebt, 3800000.0); // 5,000,000 - 1,200,000 = 3,800,000

      // Verify 3 distinct CustomerDebtTransaction events logged
      final txCalls = mockDb.recorder.callsFor('set').where(
            (c) => c.path.contains('shared_customers/CUST_PARTIAL_PAYER/debt_transactions'),
          );
      expect(txCalls.length, 3);

      // Subsequent Payment 4: Attempt to pay even 1 dong when remaining debt is 0 -> MUST throw
      expect(
        () async => await collectDebtUseCase.execute(
          order: order,
          amount: 1.0,
          paymentMethod: 'cash',
          currentUser: adminUser,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('vượt quá công nợ còn lại (0.0) của hóa đơn'),
          ),
        ),
      );
    });

    test('Debt collection on orders with non-existent customer or walk-in customer updates order cleanly without unhandled exceptions', () async {
      // Order with non-existent registered ID
      final ghostCustomerOrder = Order(
        id: 'HD_GHOST_CUST',
        customerId: 'CUST_DOES_NOT_EXIST_404',
        createdAt: testDate,
        items: [],
        total: 2000000,
        amountPaid: 500000,
        debtAmount: 1500000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(ghostCustomerOrder);

      // Collect 500,000 debt
      final updatedGhostOrder = await collectDebtUseCase.execute(
        order: ghostCustomerOrder,
        amount: 500000,
        paymentMethod: 'cash',
        currentUser: adminUser,
      );

      expect(updatedGhostOrder.amountPaid, 1000000.0);
      expect(updatedGhostOrder.debtAmount, 1000000.0);

      // Order with walk-in customer 'khach_le'
      final walkInOrder = Order(
        id: 'HD_WALK_IN_DEBT',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [],
        total: 1000000,
        amountPaid: 200000,
        debtAmount: 800000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(walkInOrder);

      final updatedWalkIn = await collectDebtUseCase.execute(
        order: walkInOrder,
        amount: 300000,
        paymentMethod: 'transfer',
        currentUser: adminUser,
      );

      expect(updatedWalkIn.amountPaid, 500000.0);
      expect(updatedWalkIn.debtAmount, 500000.0);
    });

    test('Debt collection on cancelled or draft orders is strictly forbidden', () async {
      final cancelledOrder = Order(
        id: 'HD_CANCELLED_DEBT',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [],
        total: 1000000,
        amountPaid: 0,
        debtAmount: 1000000,
        status: 'cancelled',
        storeId: 'store_001',
      );

      expect(
        () async => await collectDebtUseCase.execute(
          order: cancelledOrder,
          amount: 500000,
          paymentMethod: 'cash',
          currentUser: adminUser,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('Không thể thu nợ cho hóa đơn đã hủy'),
          ),
        ),
      );

      final draftOrder = cancelledOrder.copyWith(status: 'draft');
      expect(
        () async => await collectDebtUseCase.execute(
          order: draftOrder,
          amount: 500000,
          paymentMethod: 'cash',
          currentUser: adminUser,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('Chỉ có thể thu nợ cho hóa đơn đã hoàn thành'),
          ),
        ),
      );
    });
  });

  // ==========================================================================
  // SECTION 3: PROCESS RETURN ORDER STRESS
  // ==========================================================================
  group('3. Process Return Order Adversarial Stress Tests', () {
    test('Full return after partial return enforces remaining quantity limit and transitions status to returned', () async {
      const productA = Product(
        id: 'PROD_SSD_1TB',
        name: 'Ổ cứng SSD 1TB NVMe',
        code: 'SSD1TB',
        price: 2000000,
        costPrice: 1500000,
        branchStocks: {'store_001': 10},
        category: 'Ổ cứng',
      );
      const productB = Product(
        id: 'PROD_USB_HUB',
        name: 'Bộ chia USB Type-C 7 in 1',
        code: 'HUB7',
        price: 500000,
        costPrice: 300000,
        branchStocks: {'store_001': 15},
        category: 'Phụ kiện',
      );
      await productRepo.upsert(productA);
      await productRepo.upsert(productB);

      // Order with 5 SSDs (10,000,000) + 4 Hubs (2,000,000) = 12,000,000 (Fully paid)
      final initialOrder = Order(
        id: 'HD_RETURN_LIFECYCLE_001',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'PROD_SSD_1TB',
            productName: 'Ổ cứng SSD 1TB NVMe',
            quantity: 5,
            price: 2000000,
            warrantyMonths: 36,
            purchaseDate: testDate,
          ),
          OrderItem(
            productId: 'PROD_USB_HUB',
            productName: 'Bộ chia USB Type-C 7 in 1',
            quantity: 4,
            price: 500000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 12000000,
        amountPaid: 12000000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(initialOrder);

      // 1. Partial Return: Return 2 SSDs and 1 Hub
      final partialResult = await processReturnOrderUseCase.execute(
        originalOrder: initialOrder,
        returnItems: [
          const ReturnOrderItem(
            productId: 'PROD_SSD_1TB',
            productName: 'Ổ cứng SSD 1TB NVMe',
            price: 2000000,
            quantity: 2,
          ),
          const ReturnOrderItem(
            productId: 'PROD_USB_HUB',
            productName: 'Bộ chia USB Type-C 7 in 1',
            price: 500000,
            quantity: 1,
          ),
        ],
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Khách mua dư dùng đợt 1',
      );

      // Total refund: (2 * 2M) + (1 * 0.5M) = 4,500,000
      expect(partialResult.totalRefund, 4500000.0);
      expect(partialResult.cashRefunded, 4500000.0);
      expect(partialResult.debtDeducted, 0.0);

      // Order status is still completed because items are still active
      final orderAfterPartial = partialResult.updatedOrder;
      expect(orderAfterPartial.status, 'completed');
      expect(orderAfterPartial.total, 7500000.0);
      expect(orderAfterPartial.amountPaid, 7500000.0);

      // Active quantity check: SSD has 3 remaining (5 - 2), Hub has 3 remaining (4 - 1)
      final ssdItem = orderAfterPartial.items
          .firstWhere((i) => i.productId == 'PROD_SSD_1TB');
      expect(ssdItem.returnedQuantity, 2);
      expect(ssdItem.activeQuantity, 3);

      final hubItem = orderAfterPartial.items
          .firstWhere((i) => i.productId == 'PROD_USB_HUB');
      expect(hubItem.returnedQuantity, 1);
      expect(hubItem.activeQuantity, 3);

      // Stock check: SSD: 10 + 2 = 12, Hub: 15 + 1 = 16
      expect((await productRepo.fetchById('PROD_SSD_1TB'))?.branchStocks['store_001'], 12);
      expect((await productRepo.fetchById('PROD_USB_HUB'))?.branchStocks['store_001'], 16);

      // 2. Adversarial Attempt: Attempt to return 4 SSDs (when only 3 are active) -> MUST throw
      expect(
        () async => await processReturnOrderUseCase.execute(
          originalOrder: orderAfterPartial,
          returnItems: [
            const ReturnOrderItem(
              productId: 'PROD_SSD_1TB',
              productName: 'Ổ cứng SSD 1TB NVMe',
              price: 2000000,
              quantity: 4,
            ),
          ],
          storeId: 'store_001',
          currentUser: adminUser,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('vượt quá số lượng khả dụng (3)'),
          ),
        ),
      );

      // 3. Full Return of All Remaining: Return remaining 3 SSDs and remaining 3 Hubs
      final fullResult = await processReturnOrderUseCase.execute(
        originalOrder: orderAfterPartial,
        returnItems: [
          const ReturnOrderItem(
            productId: 'PROD_SSD_1TB',
            productName: 'Ổ cứng SSD 1TB NVMe',
            price: 2000000,
            quantity: 3,
          ),
          const ReturnOrderItem(
            productId: 'PROD_USB_HUB',
            productName: 'Bộ chia USB Type-C 7 in 1',
            price: 500000,
            quantity: 3,
          ),
        ],
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Khách trả nốt toàn bộ số còn lại',
      );

      expect(fullResult.totalRefund, 7500000.0);

      // All items are now fully returned -> Order status transitions to 'returned'!
      final orderAfterFull = fullResult.updatedOrder;
      expect(orderAfterFull.status, 'returned');
      expect(orderAfterFull.isReturned, true);
      expect(orderAfterFull.items.every((i) => i.activeQuantity == 0), true);

      // Stock check: SSD: 12 + 3 = 15, Hub: 16 + 3 = 19
      expect((await productRepo.fetchById('PROD_SSD_1TB'))?.branchStocks['store_001'], 15);
      expect((await productRepo.fetchById('PROD_USB_HUB'))?.branchStocks['store_001'], 19);

      // 4. Post-Full Return Adversarial Attempt: Trying to return on an already 'returned' order MUST throw
      expect(
        () async => await processReturnOrderUseCase.execute(
          originalOrder: orderAfterFull,
          returnItems: [
            const ReturnOrderItem(
              productId: 'PROD_SSD_1TB',
              productName: 'Ổ cứng SSD 1TB NVMe',
              price: 2000000,
              quantity: 1,
            ),
          ],
          storeId: 'store_001',
          currentUser: adminUser,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('Chỉ có thể trả hàng cho hóa đơn đã hoàn thành'),
          ),
        ),
      );
    });

    test('Returning combo products correctly restores child component branch stocks and logs audit import transactions', () async {
      // Child component A: Tai nghe (stock: 4)
      const childHeadphone = Product(
        id: 'P_CHILD_HEADPHONE',
        name: 'Tai nghe chụp tai Pro',
        code: 'HP_PRO',
        price: 1200000,
        costPrice: 800000,
        branchStocks: {'store_001': 4},
        category: 'Âm thanh',
      );
      // Child component B: Giá đỡ tai nghe (stock: 7)
      const childStand = Product(
        id: 'P_CHILD_STAND',
        name: 'Giá đỡ tai nghe nhôm',
        code: 'STAND_ALU',
        price: 300000,
        costPrice: 150000,
        branchStocks: {'store_001': 7},
        category: 'Phụ kiện',
      );

      // Combo product: "Combo Streamer" (1 Headphone + 2 Stands)
      const comboStreamer = Product(
        id: 'P_COMBO_STREAMER',
        name: 'Combo Streamer Khởi Nghiệp',
        code: 'STREAMER_KIT',
        price: 1600000,
        costPrice: 1100000,
        branchStocks: {'store_001': 0},
        category: 'Combo',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'P_CHILD_HEADPHONE',
            productCode: 'HP_PRO',
            productName: 'Tai nghe chụp tai Pro',
            quantity: 1,
          ),
          ComboComponent(
            productId: 'P_CHILD_STAND',
            productCode: 'STAND_ALU',
            productName: 'Giá đỡ tai nghe nhôm',
            quantity: 2,
          ),
        ],
      );

      await productRepo.upsert(childHeadphone);
      await productRepo.upsert(childStand);
      await productRepo.upsert(comboStreamer);

      final orderWithCombo = Order(
        id: 'HD_COMBO_RETURN_001',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_COMBO_STREAMER',
            productName: 'Combo Streamer Khởi Nghiệp',
            quantity: 3,
            price: 1600000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 4800000,
        amountPaid: 4800000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(orderWithCombo);

      // Return 2 Combos: should restore 2 * 1 = 2 Headphones, and 2 * 2 = 4 Stands
      final returnResult = await processReturnOrderUseCase.execute(
        originalOrder: orderWithCombo,
        returnItems: [
          const ReturnOrderItem(
            productId: 'P_COMBO_STREAMER',
            productName: 'Combo Streamer Khởi Nghiệp',
            price: 1600000,
            quantity: 2,
          ),
        ],
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Khách trả 2 bộ combo',
      );

      expect(returnResult.totalRefund, 3200000.0);

      // Stock check: Headphone: 4 + 2 = 6, Stand: 7 + 4 = 11
      final updatedHeadphone = await productRepo.fetchById('P_CHILD_HEADPHONE');
      expect(updatedHeadphone?.branchStocks['store_001'], 6);

      final updatedStand = await productRepo.fetchById('P_CHILD_STAND');
      expect(updatedStand?.branchStocks['store_001'], 11);

      // Check inventory transactions
      expect(inventoryRepo.transactions.length, 2);
      final hpTx = inventoryRepo.transactions
          .firstWhere((t) => t.productId == 'P_CHILD_HEADPHONE');
      expect(hpTx.quantity, 2);
      expect(hpTx.note, contains('Combo: Combo Streamer Khởi Nghiệp'));

      final standTx = inventoryRepo.transactions
          .firstWhere((t) => t.productId == 'P_CHILD_STAND');
      expect(standTx.quantity, 4);
      expect(standTx.note, contains('Combo: Combo Streamer Khởi Nghiệp'));
    });

    test('Financial balance: when debt deduction equals total return, cash refund is 0 and order total perfectly equals amountPaid + debtAmount', () async {
      const customer = Customer(
        id: 'CUST_FIN_BALANCE',
        name: 'Trần Cân Bằng Tài Chính',
        phone: '0933221100',
        email: 'balance@example.com',
        address: 'Cần Thơ',
        purchases: [],
        currentDebt: 3000000,
        totalSales: 8000000,
      );
      await customerRepo.upsert(customer);

      const itemProduct = Product(
        id: 'P_ITEM_FIN',
        name: 'Bộ Nguồn 850W Gold',
        code: 'PSU850',
        price: 2500000,
        costPrice: 1800000,
        branchStocks: {'store_001': 10},
        category: 'Nguồn',
      );
      await productRepo.upsert(itemProduct);

      // Order total: 5,000,000 (2 PSUs @ 2.5M).
      // Customer paid: 2,500,000. Remaining Debt on invoice: 2,500,000.
      final orderWithDebt = Order(
        id: 'HD_FIN_BALANCE_001',
        customerId: 'CUST_FIN_BALANCE',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_ITEM_FIN',
            productName: 'Bộ Nguồn 850W Gold',
            quantity: 2,
            price: 2500000,
            warrantyMonths: 60,
            purchaseDate: testDate,
          ),
        ],
        total: 5000000,
        amountPaid: 2500000,
        debtAmount: 2500000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(orderWithDebt);

      // Return 1 PSU (refund value: 2,500,000, exactly matching remaining invoice debt 2,500,000)
      final result = await processReturnOrderUseCase.execute(
        originalOrder: orderWithDebt,
        returnItems: [
          const ReturnOrderItem(
            productId: 'P_ITEM_FIN',
            productName: 'Bộ Nguồn 850W Gold',
            price: 2500000,
            quantity: 1,
          ),
        ],
        storeId: 'store_001',
        currentUser: adminUser,
      );

      // Exact mathematical balance verification
      expect(result.totalRefund, 2500000.0);
      expect(result.debtDeducted, 2500000.0);
      expect(result.cashRefunded, 0.0,
          reason: 'When debt deduction equals total return, cash refund must be exactly 0');

      final updatedOrder = result.updatedOrder;
      expect(updatedOrder.total, 2500000.0);
      expect(updatedOrder.debtAmount, 0.0);
      expect(updatedOrder.amountPaid, 2500000.0);
      expect(updatedOrder.remainingDebt, 0.0);

      // Fundamental accounting invariant: total == amountPaid + debtAmount
      expect(updatedOrder.total, updatedOrder.amountPaid + updatedOrder.debtAmount,
          reason: 'Accounting balance invariant violated: total != amountPaid + debtAmount');

      // Customer debt was reduced by debtDeducted: 3,000,000 - 2,500,000 = 500,000
      final updatedCust = await customerRepo.fetchById('CUST_FIN_BALANCE');
      expect(updatedCust?.currentDebt, 500000.0);

      // CustomerDebtTransaction recorded in RTDB
      final debtCalls = mockDb.recorder.callsFor('set').where(
            (c) => c.path.contains('shared_customers/CUST_FIN_BALANCE/debt_transactions'),
          );
      expect(debtCalls.length, 1);
      final debtTx = debtCalls.first.value as Map;
      expect(debtTx['amount'], -2500000.0);
      expect(debtTx['remainingDebt'], 500000.0);
    });
  });

  // ==========================================================================
  // SECTION 4: INTER-STORE TRANSFER STRESS
  // ==========================================================================
  group('4. Inter-Store Transfer Adversarial Stress Tests', () {
    test('Transfer attempt when source branch has 0 units but other branches have stock fails with error and makes no DB updates', () async {
      // Product has 0 units in store_001, but 50 units in store_002 and 20 in store_003
      // Global stock = 70 units
      const product = Product(
        id: 'PROD_TRANSFER_STRESS',
        name: 'Card Màn Hình RTX 4090',
        code: 'RTX4090',
        price: 50000000,
        costPrice: 42000000,
        branchStocks: {
          'store_001': 0,
          'store_002': 50,
          'store_003': 20,
        },
        category: 'VGA',
      );

      expect(product.stock, 70);
      expect(product.hasStock, true);
      expect(product.stockInBranch('store_001'), 0);

      // Attempt to transfer 1 unit from store_001 to store_002
      final error = await interStoreTransferService.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: product,
        quantity: 1,
        sourceStoreName: 'Chi nhánh 1',
        targetStoreName: 'Chi nhánh 2',
      );

      // Must fail and return error message derived from thrown exception
      expect(error, isNotNull);
      expect(error, equals('Không đủ số lượng trong kho'));

      // Crucial: No database update calls were made
      final updateCalls = mockDb.recorder.callsFor('update');
      expect(updateCalls.isEmpty, true,
          reason: 'No database write should occur when source branch stock is 0');

      // Also verify when source branch does not exist at all in branchStocks map
      const productNoStore1 = Product(
        id: 'PROD_TRANSFER_STRESS_2',
        name: 'VGA RTX 4080',
        code: 'RTX4080',
        price: 30000000,
        costPrice: 25000000,
        branchStocks: {
          'store_002': 15,
        },
        category: 'VGA',
      );

      final errorMissingBranch = await interStoreTransferService.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: productNoStore1,
        quantity: 1,
      );

      expect(errorMissingBranch, isNotNull);
      expect(errorMissingBranch, equals('Không đủ số lượng trong kho'));
      expect(mockDb.recorder.callsFor('update').isEmpty, true);
    });

    test('Transfer to same branch is strictly rejected without DB write', () async {
      const product = Product(
        id: 'PROD_SAME_STORE',
        name: 'Chuột Gaming RGB',
        code: 'GM_RGB',
        price: 800000,
        costPrice: 500000,
        branchStocks: {'store_001': 20, 'store_002': 10},
        category: 'Phụ kiện',
      );

      final errorSameStore = await interStoreTransferService.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_001',
        product: product,
        quantity: 5,
      );

      expect(errorSameStore, equals('Không thể chuyển cùng kho'));
      expect(mockDb.recorder.callsFor('update').isEmpty, true,
          reason: 'Self-transfer must not trigger DB updates');
    });

    test('Transfer rejects non-positive quantities and empty store parameters', () async {
      const product = Product(
        id: 'PROD_PARAM_CHECK',
        name: 'Bàn phím cơ Mini',
        code: 'KB_MINI',
        price: 900000,
        costPrice: 600000,
        branchStocks: {'store_001': 10, 'store_002': 10},
        category: 'Phụ kiện',
      );

      // Zero quantity
      final errorZero = await interStoreTransferService.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: product,
        quantity: 0,
      );
      expect(errorZero, equals('Số lượng phải lớn hơn 0'));

      // Negative quantity
      final errorNeg = await interStoreTransferService.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: product,
        quantity: -10,
      );
      expect(errorNeg, equals('Số lượng phải lớn hơn 0'));

      // Empty source store ID
      final errorEmptySource = await interStoreTransferService.transferProduct(
        sourceStoreId: '',
        targetStoreId: 'store_002',
        product: product,
        quantity: 3,
      );
      expect(errorEmptySource, equals('Chi nhánh không hợp lệ'));

      // Empty target store ID
      final errorEmptyTarget = await interStoreTransferService.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: '',
        product: product,
        quantity: 3,
      );
      expect(errorEmptyTarget, equals('Chi nhánh không hợp lệ'));

      expect(mockDb.recorder.callsFor('update').isEmpty, true);
    });

    test('Valid inter-store transfer performs atomic multi-path update with source export and target import records', () async {
      const product = Product(
        id: 'PROD_VALID_TRANSFER',
        name: 'Bộ Phát Wifi 6 Mesh',
        code: 'WIFI6_MESH',
        price: 2500000,
        costPrice: 1800000,
        branchStocks: {'store_001': 30, 'store_002': 5},
        category: 'Thiết bị mạng',
      );

      // Seed product in target store
      mockDb.seedData('stores/store_002/products/PROD_VALID_TRANSFER', {
        'id': 'PROD_VALID_TRANSFER',
        'name': 'Bộ Phát Wifi 6 Mesh',
        'code': 'WIFI6_MESH',
        'branchStocks': {'store_001': 30, 'store_002': 5},
      });

      // Transfer 12 units from store_001 (has 30) to store_002 (has 5)
      final result = await interStoreTransferService.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: product,
        quantity: 12,
        sourceStoreName: 'Chi nhánh Đông Thắng',
        targetStoreName: 'Chi nhánh Thới Bình',
        createdBy: 'admin_user',
        createdByName: 'Admin User',
      );

      expect(result, isNull, reason: 'Valid transfer must succeed returning null');

      final updateCalls = mockDb.recorder.callsFor('update');
      expect(updateCalls.length, 1);
      final updates = updateCalls.first.value as Map<String, dynamic>;

      // Check source store branchStocks decremented: 30 - 12 = 18
      final srcStocks =
          updates['stores/store_001/products/PROD_VALID_TRANSFER/branchStocks'] as Map<String, int>;
      expect(srcStocks['store_001'], 18);

      // Check target store branchStocks incremented: 5 + 12 = 17
      final tgtStocks =
          updates['stores/store_002/products/PROD_VALID_TRANSFER/branchStocks'] as Map<String, int>;
      expect(tgtStocks['store_002'], 17);

      // Check export and import transactions
      final exportEntry = updates.entries.firstWhere(
        (e) => e.key.startsWith('stores/store_001/inventory_transactions/'),
      );
      expect((exportEntry.value as Map)['type'], 'export');
      expect((exportEntry.value as Map)['quantity'], 12);
      expect((exportEntry.value as Map)['note'], contains('Chuyển hàng sang Chi nhánh Thới Bình'));

      final importEntry = updates.entries.firstWhere(
        (e) => e.key.startsWith('stores/store_002/inventory_transactions/'),
      );
      expect((importEntry.value as Map)['type'], 'import');
      expect((importEntry.value as Map)['quantity'], 12);
      expect((importEntry.value as Map)['note'], contains('Nhận chuyển kho từ Chi nhánh Đông Thắng'));
    });
  });
}
