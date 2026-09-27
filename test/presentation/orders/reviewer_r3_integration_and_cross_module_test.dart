import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/application/orders/usecases/collect_invoice_debt_usecase.dart';
import 'package:stores/application/orders/usecases/import_invoices_usecase.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/data/datasources/firebase/customer_remote_data_source.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';

import '../../support/firebase_test_harness.dart';

class _FakeOrderRepo implements OrderRepository, OrderRepositoryReturnHandler {
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
  Stream<List<Order>> watchByCustomer(String customerId) => Stream.value(
      orders.values.where((o) => o.customerId == customerId).toList());

  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) =>
      Stream.value(orders.values.toList());

  @override
  Future<void> createReturn(ReturnOrder returnOrder) async {
    returnOrders[returnOrder.id] = returnOrder;
  }

  @override
  Future<ReturnOrder?> fetchReturnById(String returnId) async =>
      returnOrders[returnId];

  @override
  Stream<List<ReturnOrder>> watchReturnsByDateRange(
          DateTime start, DateTime end) =>
      Stream.value(returnOrders.values.toList());

  @override
  Stream<List<ReturnOrder>> watchReturnsByOrderId(String orderId) =>
      Stream.value(
          returnOrders.values.where((r) => r.orderId == orderId).toList());
}

class _FakeProductRepo implements ProductRepository {
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
      products[id] = p.copyWith(branchStocks: {'store_002': newStock});
    }
  }

  @override
  Future<void> upsert(Product product) async => products[product.id] = product;

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());
}

class _FakeInventoryRepo implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async => transactions.add(tx);

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(
          transactions.where((t) => t.productId == productId).toList());

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime startDate, DateTime endDate) =>
      Stream.value(transactions);
}

class _FakeCustomerRepo implements CustomerRepository {
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

void main() {
  late _FakeOrderRepo orderRepo;
  late _FakeProductRepo productRepo;
  late _FakeInventoryRepo inventoryRepo;
  late _FakeCustomerRepo customerRepo;
  late MockFirebaseDatabase mockDb;
  late CustomerRemoteDataSource customerDataSource;

  const adminUser = UserAccount(
    username: 'admin_tb',
    displayName: 'Thới Bình Manager',
    role: 'admin',
    storeId: 'store_002',
  );

  final testDate = DateTime(2026, 9, 20, 14, 0);

  setUp(() {
    orderRepo = _FakeOrderRepo();
    productRepo = _FakeProductRepo();
    inventoryRepo = _FakeInventoryRepo();
    customerRepo = _FakeCustomerRepo();
    mockDb = MockFirebaseDatabase();
    customerDataSource = CustomerRemoteDataSource(mockDb);
  });

  group('Review Round 3: Cross-Module Integration & Adversarial Stress Tests',
      () {
    test('1. ProcessReturnOrderUseCase with invoice discount (Full Return)',
        () async {
      // Setup Product
      const product = Product(
        id: 'SP_TB_01',
        name: 'Sản phẩm Thới Bình 1',
        code: 'TB01',
        price: 10000000,
        costPrice: 6000000,
        category: 'Thiết bị',
        branchStocks: {'store_002': 5},
      );
      await productRepo.upsert(product);

      // Customer with 0 initial stats
      const customer = Customer(
        id: 'CUST_TB_01',
        name: 'Nguyễn Văn TB',
        phone: '0988777666',
        email: 'tb@test.com',
        address: 'Thới Bình, Cà Mau',
        purchases: [],
        currentDebt: 0,
        totalSales: 10000000,
        netSales: 9000000,
      );
      await customerRepo.upsert(customer);

      // Order: Gross 10,000,000; Discount 1,000,000; NetPayable 9,000,000; Paid 9,000,000; Debt 0
      final order = Order(
        id: 'HD_DISCOUNT_RET_01',
        customerId: 'CUST_TB_01',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'SP_TB_01',
            productName: 'Sản phẩm Thới Bình 1',
            quantity: 1,
            price: 10000000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 10000000,
        discount: 1000000,
        amountPaid: 9000000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_002',
      );
      await orderRepo.create(order);

      final useCase = ProcessReturnOrderUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
      );

      // Return 1 item (full return)
      final result = await useCase.execute(
        originalOrder: order,
        returnItems: [
          const ReturnOrderItem(
            productId: 'SP_TB_01',
            productName: 'Sản phẩm Thới Bình 1',
            price: 10000000,
            quantity: 1,
          ),
        ],
        storeId: 'store_002',
        currentUser: adminUser,
        reason: 'Khách đổi ý',
      );

      // Invariant: Total refund MUST reflect netPayable (9,000,000), NOT gross (10,000,000)
      expect(result.totalRefund, 9000000.0);
      expect(result.debtDeducted, 0.0);
      expect(result.cashRefunded, 9000000.0);
      expect(result.cashRefunded <= order.amountPaid, true);

      // Customer net sales must be reduced by net refund (9,000,000 - 9,000,000 = 0)
      final updatedCustomer = await customerRepo.fetchById('CUST_TB_01');
      expect(updatedCustomer?.netSales, 0.0);

      // Order financial residuals
      expect(result.updatedOrder.total, 0.0);
      expect(result.updatedOrder.discount, 0.0);
      expect(result.updatedOrder.netPayable, 0.0);
      expect(result.updatedOrder.amountPaid, 0.0);
      expect(result.updatedOrder.remainingDebt, 0.0);
      expect(result.updatedOrder.status, 'returned');
    });

    test(
        '2. ProcessReturnOrderUseCase with invoice discount (Partial Return & Debt)',
        () async {
      // Product
      const product = Product(
        id: 'SP_TB_02',
        name: 'Sản phẩm Thới Bình 2',
        code: 'TB02',
        price: 5000000,
        costPrice: 3000000,
        category: 'Thiết bị',
        branchStocks: {'store_002': 10},
      );
      await productRepo.upsert(product);

      // Order: 2 items @ 5,000,000 = Gross 10,000,000; Discount 1,000,000; Net 9,000,000.
      // Customer paid 6,000,000; Debt 3,000,000
      const customer = Customer(
        id: 'CUST_TB_02',
        name: 'Trần Thị B',
        phone: '0911223344',
        email: 'b@test.com',
        address: 'Thới Bình',
        purchases: [],
        currentDebt: 3000000,
        totalSales: 10000000,
        netSales: 9000000,
      );
      await customerRepo.upsert(customer);

      final order = Order(
        id: 'HD_DISCOUNT_RET_02',
        customerId: 'CUST_TB_02',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'SP_TB_02',
            productName: 'Sản phẩm Thới Bình 2',
            quantity: 2,
            price: 5000000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 10000000,
        discount: 1000000,
        amountPaid: 6000000,
        debtAmount: 3000000,
        status: 'completed',
        storeId: 'store_002',
      );
      await orderRepo.create(order);

      final useCase = ProcessReturnOrderUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
      );

      // Return 1 of 2 items: gross return is 5,000,000 (50%).
      // Discount share is 50% * 1,000,000 = 500,000.
      // Net return value is 4,500,000.
      // Outstanding debt is 3,000,000.
      // debtDeducted = min(4,500,000, 3,000,000) = 3,000,000.
      // cashRefunded = 4,500,000 - 3,000,000 = 1,500,000.
      final result = await useCase.execute(
        originalOrder: order,
        returnItems: [
          const ReturnOrderItem(
            productId: 'SP_TB_02',
            productName: 'Sản phẩm Thới Bình 2',
            price: 5000000,
            quantity: 1,
          ),
        ],
        storeId: 'store_002',
        currentUser: adminUser,
        reason: 'Khách trả bớt 1 cái',
      );

      expect(result.totalRefund, 4500000.0);
      expect(result.debtDeducted, 3000000.0);
      expect(result.cashRefunded, 1500000.0);

      // Residual order financials
      expect(result.updatedOrder.total, 5000000.0);
      expect(result.updatedOrder.discount, 500000.0);
      expect(result.updatedOrder.netPayable, 4500000.0);
      expect(result.updatedOrder.debtAmount, 0.0);
      expect(
          result.updatedOrder.amountPaid, 4500000.0); // 6,000,000 - 1,500,000
      expect(result.updatedOrder.remainingDebt, 0.0);
      expect(result.updatedOrder.status, 'completed');

      // Customer debt cleared
      final updatedCustomer = await customerRepo.fetchById('CUST_TB_02');
      expect(updatedCustomer?.currentDebt, 0.0);
      expect(updatedCustomer?.netSales, 4500000.0);
    });

    test(
        '3. CancelInvoiceUseCase with discount reverses gross totalSales & net netSales',
        () async {
      const product = Product(
        id: 'SP_TB_03',
        name: 'Sản phẩm 3',
        code: 'TB03',
        price: 4000000,
        costPrice: 2500000,
        category: 'Thiết bị',
        branchStocks: {'store_002': 4},
      );
      await productRepo.upsert(product);

      const customer = Customer(
        id: 'CUST_TB_03',
        name: 'Lê Văn C',
        phone: '0933445566',
        email: 'c@test.com',
        address: 'Thới Bình',
        purchases: [],
        currentDebt: 1000000,
        totalSales: 4000000,
        netSales: 3500000,
      );
      await customerRepo.upsert(customer);

      final order = Order(
        id: 'HD_CANCEL_DISCOUNT_01',
        customerId: 'CUST_TB_03',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'SP_TB_03',
            productName: 'Sản phẩm 3',
            quantity: 1,
            price: 4000000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 4000000,
        discount: 500000,
        amountPaid: 2500000,
        debtAmount: 1000000,
        status: 'completed',
        storeId: 'store_002',
      );
      await orderRepo.create(order);

      final cancelUseCase = CancelInvoiceUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
      );

      final cancelled = await cancelUseCase.execute(
        order: order,
        cancelReason: 'Hủy đơn do nhập sai chi nhánh',
        currentUser: adminUser,
        storeId: 'store_002',
      );

      expect(cancelled.isCancelled, true);
      expect(cancelled.status, 'cancelled');

      final updatedCustomer = await customerRepo.fetchById('CUST_TB_03');
      // Gross sales decremented by order.total (4,000,000 - 4,000,000 = 0)
      expect(updatedCustomer?.totalSales, 0.0);
      // Net sales decremented by order.netPayable (3,500,000 - 3,500,000 = 0)
      expect(updatedCustomer?.netSales, 0.0);
      // Debt reversed (1,000,000 - 1,000,000 = 0)
      expect(updatedCustomer?.currentDebt, 0.0);
    });

    test(
        '4. Customer.effectiveCurrentDebt: orders only without phantom gross debt',
        () {
      const customer = Customer(
        id: 'CUST_GHOST_TEST',
        name: 'Khách Thử Phantom',
        phone: '0909090909',
        email: 'test@test.com',
        address: 'Cà Mau',
        purchases: [],
        currentDebt: null, // No static currentDebt
      );

      // Order 1: fully paid (Gross 2,000,000, discount 200,000, paid 1,800,000, debt 0)
      final o1 = Order(
        id: 'HD_P1',
        customerId: 'CUST_GHOST_TEST',
        createdAt: testDate,
        items: [],
        total: 2000000,
        discount: 200000,
        amountPaid: 1800000,
        debtAmount: 0,
        status: 'completed',
      );

      // Order 2: partial debt (Gross 3,000,000, discount 0, paid 2,000,000, debt 1,000,000)
      final o2 = Order(
        id: 'HD_P2',
        customerId: 'CUST_GHOST_TEST',
        createdAt: testDate,
        items: [],
        total: 3000000,
        discount: 0,
        amountPaid: 2000000,
        debtAmount: 1000000,
        status: 'completed',
      );

      // Effective debt should be exactly 1,000,000 (o1 has 0 remaining debt, o2 has 1,000,000)
      final effectiveDebt = customer.effectiveCurrentDebt([o1, o2], []);
      expect(effectiveDebt, 1000000.0);
    });

    test(
        '5. CollectInvoiceDebtUseCase handles unpopulated debtAmount field gracefully',
        () async {
      // Order created without explicit debtAmount (0.0), but netPayable 2,000,000, amountPaid 1,200,000
      final order = Order(
        id: 'HD_UNPOP_DEBT',
        customerId: 'CUST_COLLECT_1',
        createdAt: testDate,
        items: [],
        total: 2000000,
        discount: 0,
        amountPaid: 1200000,
        debtAmount: 0.0,
        // not explicitly stored
        status: 'completed',
      );
      expect(order.remainingDebt, 800000.0);

      const customer = Customer(
        id: 'CUST_COLLECT_1',
        name: 'Khách Thu Nợ',
        phone: '0977889900',
        email: 'collect@test.com',
        address: 'Thới Bình',
        purchases: [],
        currentDebt: 800000,
      );
      await customerRepo.upsert(customer);
      await orderRepo.create(order);

      final collectUseCase = CollectInvoiceDebtUseCase(
        orderRepository: orderRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
      );

      // Collect 500,000
      final updated = await collectUseCase.execute(
        order: order,
        amount: 500000,
        paymentMethod: 'cash',
        currentUser: adminUser,
      );

      expect(updated.amountPaid, 1700000.0);
      expect(updated.debtAmount, 300000.0);
      expect(updated.remainingDebt, 300000.0);
    });

    test(
        '6. ImportInvoicesUseCase preserves gross totalSales and net netSales with discount',
        () async {
      const customer = Customer(
        id: 'CUST_IMPORT_ACC',
        name: 'Khách Import',
        phone: '0922334455',
        email: 'import@test.com',
        address: 'Thới Bình',
        purchases: [],
        totalSales: 0,
        netSales: 0,
        currentDebt: 0,
      );
      await customerRepo.upsert(customer);

      const prod = Product(
        id: 'P_IMP_01',
        name: 'Mặt hàng Import',
        code: 'MH01',
        price: 5000000,
        costPrice: 3000000,
        category: 'Thiết bị',
        branchStocks: {'store_002': 10},
      );
      await productRepo.upsert(prod);

      final order = Order(
        id: 'HD_IMP_001',
        customerId: 'CUST_IMPORT_ACC',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_IMP_01',
            productName: 'Mặt hàng Import',
            quantity: 1,
            price: 5000000,
            warrantyMonths: 0,
            purchaseDate: testDate,
          ),
        ],
        total: 5000000,
        discount: 500000,
        amountPaid: 4500000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_002',
      );

      final importUseCase = ImportInvoicesUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
        customerDataSource: customerDataSource,
      );

      final result = await importUseCase.execute(
        orders: [order],
        targetStoreId: 'store_002',
      );

      expect(result.isSuccess, true);
      expect(result.added, 1);

      final updatedCustomer = await customerRepo.fetchById('CUST_IMPORT_ACC');
      expect(updatedCustomer?.totalSales, 5000000.0);
      expect(updatedCustomer?.netSales, 4500000.0);
    });
  });
}
