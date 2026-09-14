import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/application/orders/usecases/collect_invoice_debt_usecase.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/core/errors/exceptions.dart';
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

class FakeOrderRepository implements OrderRepository {
  final Map<String, Order> orders = {};

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

void main() {
  late FakeOrderRepository orderRepo;
  late FakeProductRepository productRepo;
  late FakeInventoryRepository inventoryRepo;
  late FakeCustomerRepository customerRepo;

  late ProcessReturnOrderUseCase returnUseCase;
  late CollectInvoiceDebtUseCase debtUseCase;
  late CancelInvoiceUseCase cancelUseCase;

  const adminUser = UserAccount(
    username: 'admin_test',
    displayName: 'Admin Tester',
    role: 'admin',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor_test',
    displayName: 'Supervisor Tester',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'nhanvien_test',
    displayName: 'Staff Tester',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  final testDate = DateTime(2026, 8, 17, 10, 0, 0);

  setUp(() {
    orderRepo = FakeOrderRepository();
    productRepo = FakeProductRepository();
    inventoryRepo = FakeInventoryRepository();
    customerRepo = FakeCustomerRepository();

    returnUseCase = ProcessReturnOrderUseCase(
      orderRepository: orderRepo,
      productRepository: productRepo,
      inventoryRepository: inventoryRepo,
      customerRepository: customerRepo,
    );

    debtUseCase = CollectInvoiceDebtUseCase(
      orderRepository: orderRepo,
      customerRepository: customerRepo,
    );

    cancelUseCase = CancelInvoiceUseCase(
      orderRepository: orderRepo,
      productRepository: productRepo,
      inventoryRepository: inventoryRepo,
      customerRepository: customerRepo,
    );
  });

  group('Adversarial Stress Suite 1: Sequential Partial Returns Until Full Return', () {
    test('Multi-step sequential returns on multi-item invoice drain activeQuantity and transition to returned', () async {
      // 1. Initial product setup
      // Product A: 10 in store_001
      const prodA = Product(
        id: 'PROD_A',
        name: 'Sản phẩm A',
        code: 'PA',
        price: 200000,
        costPrice: 120000,
        branchStocks: {'store_001': 10},
        category: 'Test',
      );
      // Product B: 15 in store_001
      const prodB = Product(
        id: 'PROD_B',
        name: 'Sản phẩm B',
        code: 'PB',
        price: 500000,
        costPrice: 300000,
        branchStocks: {'store_001': 15},
        category: 'Test',
      );
      await productRepo.upsert(prodA);
      await productRepo.upsert(prodB);

      // Customer with starting debt: 5,000,000
      const customer = Customer(
        id: 'CUST_SEQ',
        name: 'Khách hàng thử nghiệm',
        phone: '0999888777',
        email: 'test@example.com',
        address: 'Hà Nội',
        purchases: [],
        currentDebt: 5000000,
        totalSales: 8000000,
        netSales: 8000000,
      );
      await customerRepo.upsert(customer);

      // Order with:
      // Item A: 5 units @ 200,000 = 1,000,000
      // Item B: 3 units @ 500,000 = 1,500,000
      // Total = 2,500,000. Paid: 1,500,000. Debt: 1,000,000.
      var currentOrder = Order(
        id: 'HD_SEQ_001',
        customerId: 'CUST_SEQ',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'PROD_A',
            productName: 'Sản phẩm A',
            quantity: 5,
            price: 200000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
          OrderItem(
            productId: 'PROD_B',
            productName: 'Sản phẩm B',
            quantity: 3,
            price: 500000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 2500000,
        amountPaid: 1500000,
        debtAmount: 1000000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(currentOrder);

      // --- STEP 1: Return 2 units of Item A (Total return = 400,000) ---
      // Order remainingDebt was 1,000,000.
      // debtDeducted = min(400,000, 1,000,000) = 400,000. cashRefund = 0.
      final res1 = await returnUseCase.execute(
        originalOrder: currentOrder,
        returnItems: [
          const ReturnOrderItem(
            productId: 'PROD_A',
            productName: 'Sản phẩm A',
            price: 200000,
            quantity: 2,
          ),
        ],
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Trả lần 1: 2 cái A',
      );

      currentOrder = res1.updatedOrder;
      expect(res1.totalRefund, 400000);
      expect(res1.debtDeducted, 400000);
      expect(res1.cashRefunded, 0);

      // Stock A should be 10 + 2 = 12
      var updatedA = await productRepo.fetchById('PROD_A');
      expect(updatedA?.branchStocks['store_001'], 12);
      // Stock B unchanged = 15
      var updatedB = await productRepo.fetchById('PROD_B');
      expect(updatedB?.branchStocks['store_001'], 15);

      // Order check
      expect(currentOrder.items[0].returnedQuantity, 2);
      expect(currentOrder.items[0].activeQuantity, 3);
      expect(currentOrder.items[1].returnedQuantity, 0);
      expect(currentOrder.items[1].activeQuantity, 3);
      expect(currentOrder.total, 2100000);
      expect(currentOrder.debtAmount, 600000);
      expect(currentOrder.amountPaid, 1500000);
      expect(currentOrder.status, 'completed');

      // Customer debt check: 5,000,000 - 400,000 = 4,600,000
      var custCheck = await customerRepo.fetchById('CUST_SEQ');
      expect(custCheck?.currentDebt, 4600000);
      expect(custCheck?.netSales, 7600000);

      // --- STEP 2: Return 2 units of Item A (400,000) + 1 unit of Item B (500,000) ---
      // Total return = 900,000.
      // Order remainingDebt was 600,000.
      // debtDeducted = min(900,000, 600,000) = 600,000.
      // cashRefund = 900,000 - 600,000 = 300,000.
      final res2 = await returnUseCase.execute(
        originalOrder: currentOrder,
        returnItems: [
          const ReturnOrderItem(
            productId: 'PROD_A',
            productName: 'Sản phẩm A',
            price: 200000,
            quantity: 2,
          ),
          const ReturnOrderItem(
            productId: 'PROD_B',
            productName: 'Sản phẩm B',
            price: 500000,
            quantity: 1,
          ),
        ],
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Trả lần 2: 2 cái A, 1 cái B',
      );

      currentOrder = res2.updatedOrder;
      expect(res2.totalRefund, 900000);
      expect(res2.debtDeducted, 600000);
      expect(res2.cashRefunded, 300000);

      // Stock A: 12 + 2 = 14. Stock B: 15 + 1 = 16
      updatedA = await productRepo.fetchById('PROD_A');
      expect(updatedA?.branchStocks['store_001'], 14);
      updatedB = await productRepo.fetchById('PROD_B');
      expect(updatedB?.branchStocks['store_001'], 16);

      // Order check
      expect(currentOrder.items[0].returnedQuantity, 4);
      expect(currentOrder.items[0].activeQuantity, 1);
      expect(currentOrder.items[1].returnedQuantity, 1);
      expect(currentOrder.items[1].activeQuantity, 2);
      expect(currentOrder.total, 1200000);
      expect(currentOrder.debtAmount, 0);
      expect(currentOrder.amountPaid, 1200000); // 1,500,000 - 300,000
      expect(currentOrder.status, 'completed');

      // Customer debt: 4,600,000 - 600,000 = 4,000,000
      custCheck = await customerRepo.fetchById('CUST_SEQ');
      expect(custCheck?.currentDebt, 4000000);
      expect(custCheck?.netSales, 6700000);

      // --- STEP 3: Return remaining 1 unit of Item A (200,000) + 2 units of Item B (1,000,000) ---
      // Total return = 1,200,000.
      // Order debt was 0.
      // debtDeducted = 0.
      // cashRefund = 1,200,000.
      final res3 = await returnUseCase.execute(
        originalOrder: currentOrder,
        returnItems: [
          const ReturnOrderItem(
            productId: 'PROD_A',
            productName: 'Sản phẩm A',
            price: 200000,
            quantity: 1,
          ),
          const ReturnOrderItem(
            productId: 'PROD_B',
            productName: 'Sản phẩm B',
            price: 500000,
            quantity: 2,
          ),
        ],
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Trả lần 3: Trả hết số còn lại',
      );

      currentOrder = res3.updatedOrder;
      expect(res3.totalRefund, 1200000);
      expect(res3.debtDeducted, 0);
      expect(res3.cashRefunded, 1200000);

      // Stock A: 14 + 1 = 15 (Initial 10 + 5 returned). Stock B: 16 + 2 = 18 (Initial 15 + 3 returned)
      updatedA = await productRepo.fetchById('PROD_A');
      expect(updatedA?.branchStocks['store_001'], 15);
      updatedB = await productRepo.fetchById('PROD_B');
      expect(updatedB?.branchStocks['store_001'], 18);

      // All items fully returned -> Status must be 'returned'
      expect(currentOrder.items[0].returnedQuantity, 5);
      expect(currentOrder.items[0].activeQuantity, 0);
      expect(currentOrder.items[0].isFullyReturned, true);
      expect(currentOrder.items[1].returnedQuantity, 3);
      expect(currentOrder.items[1].activeQuantity, 0);
      expect(currentOrder.items[1].isFullyReturned, true);
      expect(currentOrder.total, 0.0);
      expect(currentOrder.amountPaid, 0.0);
      expect(currentOrder.debtAmount, 0.0);
      expect(currentOrder.status, 'returned');

      // --- STEP 4 (Adversarial): Attempt to return 1 more item from fully returned order ---
      // Case 4a: Return on order with status 'returned' (not 'completed')
      expect(
        () => returnUseCase.execute(
          originalOrder: currentOrder,
          returnItems: [
            const ReturnOrderItem(
              productId: 'PROD_A',
              productName: 'Sản phẩm A',
              price: 200000,
              quantity: 1,
            ),
          ],
          storeId: 'store_001',
          currentUser: adminUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      // Case 4b: Return exceeding activeQuantity when status is spoofed as 'completed'
      final spoofedOrder = currentOrder.copyWith(status: 'completed');
      expect(
        () => returnUseCase.execute(
          originalOrder: spoofedOrder,
          returnItems: [
            const ReturnOrderItem(
              productId: 'PROD_A',
              productName: 'Sản phẩm A',
              price: 200000,
              quantity: 1,
            ),
          ],
          storeId: 'store_001',
          currentUser: adminUser,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('Adversarial Stress Suite 2: Combo Products Return & Exact Stock Restoration', () {
    test('Returning multi-component combo restores exact sub-component stocks across canonical store keys', () async {
      // Sub-component 1: RAM (2 per combo)
      const ram = Product(
        id: 'RAM_16GB',
        name: 'RAM DDR5 16GB',
        code: 'RAM16',
        price: 1500000,
        costPrice: 1100000,
        branchStocks: {'store_001': 20, 'store_002': 10},
        category: 'Linh kiện',
      );
      // Sub-component 2: SSD (1 per combo)
      const ssd = Product(
        id: 'SSD_1TB',
        name: 'SSD NVMe 1TB',
        code: 'SSD1T',
        price: 2000000,
        costPrice: 1400000,
        branchStocks: {'store_001': 15, 'store_002': 5},
        category: 'Linh kiện',
      );
      // Sub-component 3: Case Fan (3 per combo) - Using 'branch_1' alias
      const fan = Product(
        id: 'FAN_RGB',
        name: 'Quạt tản nhiệt RGB',
        code: 'FAN3',
        price: 200000,
        costPrice: 100000,
        branchStocks: {'branch_1': 30, 'branch_2': 12},
        category: 'Linh kiện',
      );

      await productRepo.upsert(ram);
      await productRepo.upsert(ssd);
      await productRepo.upsert(fan);

      // Parent Combo Product: PC Gaming Bundle
      const comboProd = Product(
        id: 'COMBO_PC',
        name: 'Bộ nâng cấp PC Pro',
        code: 'PCPRO',
        price: 5500000,
        costPrice: 3900000,
        branchStocks: {'store_001': 0},
        category: 'Combo',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'RAM_16GB',
            productCode: 'RAM16',
            productName: 'RAM DDR5 16GB',
            quantity: 2,
          ),
          ComboComponent(
            productId: 'SSD_1TB',
            productCode: 'SSD1T',
            productName: 'SSD NVMe 1TB',
            quantity: 1,
          ),
          ComboComponent(
            productId: 'FAN_RGB',
            productCode: 'FAN3',
            productName: 'Quạt tản nhiệt RGB',
            quantity: 3,
          ),
        ],
      );
      await productRepo.upsert(comboProd);

      // Order with 3 quantities of COMBO_PC (Total = 16,500,000)
      final order = Order(
        id: 'HD_COMBO_STRESS',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'COMBO_PC',
            productName: 'Bộ nâng cấp PC Pro',
            quantity: 3,
            price: 5500000,
            warrantyMonths: 36,
            purchaseDate: testDate,
          ),
        ],
        total: 16500000,
        amountPaid: 16500000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      // Return 2 units of Combo at store_001
      final res = await returnUseCase.execute(
        originalOrder: order,
        returnItems: [
          ReturnOrderItem(
            productId: 'COMBO_PC',
            productName: 'Bộ nâng cấp PC Pro',
            price: 5500000,
            quantity: 2,
            isCombo: true,
            comboComponents: comboProd.comboComponents,
          ),
        ],
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Khách trả 2 bộ combo',
      );

      expect(res.totalRefund, 11000000);
      expect(res.cashRefunded, 11000000);

      // Verify exact stock restorations:
      // RAM: initial 20 + (2 returned * 2 per combo) = 24 at store_001
      final updatedRam = await productRepo.fetchById('RAM_16GB');
      expect(updatedRam?.branchStocks['store_001'], 24);
      expect(updatedRam?.branchStocks['store_002'], 10); // store_002 unchanged

      // SSD: initial 15 + (2 returned * 1 per combo) = 17 at store_001
      final updatedSsd = await productRepo.fetchById('SSD_1TB');
      expect(updatedSsd?.branchStocks['store_001'], 17);
      expect(updatedSsd?.branchStocks['store_002'], 5); // store_002 unchanged

      // Fan: initial 30 at 'branch_1' + (2 returned * 3 per combo) = 36 at 'branch_1'
      final updatedFan = await productRepo.fetchById('FAN_RGB');
      expect(updatedFan?.branchStocks['branch_1'], 36);
      expect(updatedFan?.branchStocks['branch_2'], 12); // branch_2 unchanged

      // Verify inventory transactions: 3 import transactions logged (one for each component)
      expect(inventoryRepo.transactions.length, 3);
      final ramTx = inventoryRepo.transactions.firstWhere((t) => t.productId == 'RAM_16GB');
      expect(ramTx.quantity, 4);
      expect(ramTx.type, TransactionType.import);

      final ssdTx = inventoryRepo.transactions.firstWhere((t) => t.productId == 'SSD_1TB');
      expect(ssdTx.quantity, 2);

      final fanTx = inventoryRepo.transactions.firstWhere((t) => t.productId == 'FAN_RGB');
      expect(fanTx.quantity, 6);
    });
  });

  group('Adversarial Stress Suite 3: Debt Collection Boundary Checks & Overpayment Guard', () {
    test('Debt collection exact match, partial match, and overpayment rejection', () async {
      const customer = Customer(
        id: 'CUST_DEBT_ADV',
        name: 'Khách nợ lớn',
        phone: '0912345678',
        email: 'debt@example.com',
        address: 'Cần Thơ',
        purchases: [],
        currentDebt: 10000000,
        totalSales: 20000000,
        netSales: 20000000,
      );
      await customerRepo.upsert(customer);

      // Order: total 5,000,000; paid 2,000,000; debt 3,000,000
      var order = Order(
        id: 'HD_DEBT_001',
        customerId: 'CUST_DEBT_ADV',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_GENERAL',
            productName: 'Hàng hoá chung',
            quantity: 5,
            price: 1000000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 5000000,
        amountPaid: 2000000,
        debtAmount: 3000000,
        status: 'completed',
        paymentMethod: 'cash',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      // 1. Partial debt payment: collect 1,000,000
      order = await debtUseCase.execute(
        order: order,
        amount: 1000000,
        paymentMethod: 'transfer',
        currentUser: adminUser,
        note: 'Đợt 1',
      );

      expect(order.amountPaid, 3000000);
      expect(order.debtAmount, 2000000);
      expect(order.remainingDebt, 2000000);
      expect(order.hasDebt, true);

      var updatedCust = await customerRepo.fetchById('CUST_DEBT_ADV');
      expect(updatedCust?.currentDebt, 9000000); // 10,000,000 - 1,000,000

      // 2. Adversarial Overpayment Attempt: Try to collect 2,500,000 when remaining is 2,000,000
      expect(
        () => debtUseCase.execute(
          order: order,
          amount: 2500000,
          paymentMethod: 'cash',
          currentUser: adminUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      // 3. Exact remaining debt collection: collect 2,000,000
      order = await debtUseCase.execute(
        order: order,
        amount: 2000000,
        paymentMethod: 'cash',
        currentUser: adminUser,
        note: 'Thanh toán tất toán',
      );

      expect(order.amountPaid, 5000000);
      expect(order.debtAmount, 0.0);
      expect(order.remainingDebt, 0.0);
      expect(order.hasDebt, false);

      updatedCust = await customerRepo.fetchById('CUST_DEBT_ADV');
      expect(updatedCust?.currentDebt, 7000000); // 9,000,000 - 2,000,000

      // 4. Overpayment on fully paid invoice: Try to collect even 1 VND
      expect(
        () => debtUseCase.execute(
          order: order,
          amount: 1,
          paymentMethod: 'cash',
          currentUser: adminUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      // 5. Zero and negative debt collection attempts
      expect(
        () => debtUseCase.execute(
          order: order,
          amount: 0,
          paymentMethod: 'cash',
          currentUser: adminUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      expect(
        () => debtUseCase.execute(
          order: order,
          amount: -500000,
          paymentMethod: 'cash',
          currentUser: adminUser,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('Adversarial Stress Suite 4: RBAC Invoice Cancellation Enforcement', () {
    test('Non-admin roles (nhanvien/staff) are strictly rejected with UnauthorizedException and cause NO side-effects', () async {
      const product = Product(
        id: 'P_PROTECTED',
        name: 'Máy in Canon',
        code: 'CANON1',
        price: 4000000,
        costPrice: 3000000,
        branchStocks: {'store_001': 5},
        category: 'Máy in',
      );
      await productRepo.upsert(product);

      final order = Order(
        id: 'HD_RBAC_CHECK',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_PROTECTED',
            productName: 'Máy in Canon',
            quantity: 2,
            price: 4000000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 8000000,
        amountPaid: 8000000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      // Attempt cancellation as staff
      expect(
        () => cancelUseCase.execute(
          order: order,
          cancelReason: 'Nhân viên muốn hủy đơn',
          currentUser: staffUser,
          storeId: 'store_001',
        ),
        throwsA(isA<UnauthorizedException>()),
      );

      // Verify NO side effects occurred
      // 1. Order status remained 'completed'
      final orderInRepo = await orderRepo.fetchById('HD_RBAC_CHECK');
      expect(orderInRepo?.status, 'completed');
      expect(orderInRepo?.isCancelled, false);

      // 2. Product stock remained 5 (no false restoration)
      final prodInRepo = await productRepo.fetchById('P_PROTECTED');
      expect(prodInRepo?.branchStocks['store_001'], 5);

      // 3. No inventory transactions recorded
      expect(inventoryRepo.transactions.isEmpty, true);

      // Admin or Supervisor CAN cancel
      final cancelledBySupervisor = await cancelUseCase.execute(
        order: order,
        cancelReason: 'Quản lý duyệt hủy đơn',
        currentUser: supervisorUser,
        storeId: 'store_001',
      );

      expect(cancelledBySupervisor.isCancelled, true);
      expect(cancelledBySupervisor.status, 'cancelled');
      expect(cancelledBySupervisor.cancelledBy, 'supervisor_test');

      // Product stock now restored: 5 + 2 = 7
      final prodAfterCancel = await productRepo.fetchById('P_PROTECTED');
      expect(prodAfterCancel?.branchStocks['store_001'], 7);
    });
  });

  group('Adversarial Stress Suite 5: Re-entry Guard & Partial Return followed by Cancellation', () {
    test('Attempting cancellation on already cancelled order throws ValidationException and prevents double stock restoration', () async {
      const product = Product(
        id: 'P_DOUBLE',
        name: 'Màn hình AOC',
        code: 'AOC24',
        price: 3000000,
        costPrice: 2200000,
        branchStocks: {'store_001': 8},
        category: 'Màn hình',
      );
      await productRepo.upsert(product);

      final order = Order(
        id: 'HD_DOUBLE_CANCEL',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_DOUBLE',
            productName: 'Màn hình AOC',
            quantity: 3,
            price: 3000000,
            warrantyMonths: 24,
            purchaseDate: testDate,
          ),
        ],
        total: 9000000,
        amountPaid: 9000000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      // Cancel once
      final cancelledOrder = await cancelUseCase.execute(
        order: order,
        cancelReason: 'Hủy đơn lần đầu',
        currentUser: adminUser,
        storeId: 'store_001',
      );
      expect(cancelledOrder.isCancelled, true);

      // Stock after 1st cancel: 8 + 3 = 11
      var prod = await productRepo.fetchById('P_DOUBLE');
      expect(prod?.branchStocks['store_001'], 11);
      expect(inventoryRepo.transactions.length, 1);

      // Attempt 2nd cancel on the cancelled order
      expect(
        () => cancelUseCase.execute(
          order: cancelledOrder,
          cancelReason: 'Cố tình hủy lần 2',
          currentUser: adminUser,
          storeId: 'store_001',
        ),
        throwsA(isA<ValidationException>()),
      );

      // Verify stock did NOT increase again (remains 11)
      prod = await productRepo.fetchById('P_DOUBLE');
      expect(prod?.branchStocks['store_001'], 11);
      // No extra transactions
      expect(inventoryRepo.transactions.length, 1);
    });

    test('Invoice with prior partial return: Cancellation only restores remaining activeQuantity (no double restoration)', () async {
      const product = Product(
        id: 'P_PARTIAL_THEN_CANCEL',
        name: 'Tai nghe Bluetooth',
        code: 'TNBT',
        price: 1000000,
        costPrice: 600000,
        branchStocks: {'store_001': 10},
        category: 'Phụ kiện',
      );
      await productRepo.upsert(product);

      // Order with 4 units of Tai nghe
      final order = Order(
        id: 'HD_PARTIAL_CANCEL',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_PARTIAL_THEN_CANCEL',
            productName: 'Tai nghe Bluetooth',
            quantity: 4,
            price: 1000000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 4000000,
        amountPaid: 4000000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      // Phase 1: Return 1 unit via Return Goods
      final returnResult = await returnUseCase.execute(
        originalOrder: order,
        returnItems: [
          const ReturnOrderItem(
            productId: 'P_PARTIAL_THEN_CANCEL',
            productName: 'Tai nghe Bluetooth',
            price: 1000000,
            quantity: 1,
          ),
        ],
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Khách đổi ý 1 cái',
      );

      // Stock should now be 10 + 1 = 11
      var prod = await productRepo.fetchById('P_PARTIAL_THEN_CANCEL');
      expect(prod?.branchStocks['store_001'], 11);
      expect(returnResult.updatedOrder.items.first.returnedQuantity, 1);
      expect(returnResult.updatedOrder.items.first.activeQuantity, 3);

      // Phase 2: Cancel the invoice (which has 3 active items left)
      final cancelledOrder = await cancelUseCase.execute(
        order: returnResult.updatedOrder,
        cancelReason: 'Hủy toàn bộ đơn còn lại',
        currentUser: adminUser,
        storeId: 'store_001',
      );

      expect(cancelledOrder.isCancelled, true);

      // Crucial assertion: Total stock should be initial 10 + 1 (from return) + 3 (from cancel) = 14!
      // If cancel reinstated all 4, stock would be 15 (bug/double restoration).
      prod = await productRepo.fetchById('P_PARTIAL_THEN_CANCEL');
      expect(prod?.branchStocks['store_001'], 14);

      // Verify inventory transactions: 1 from return (qty 1), 1 from cancel (qty 3)
      expect(inventoryRepo.transactions.length, 2);
      expect(inventoryRepo.transactions[0].quantity, 1);
      expect(inventoryRepo.transactions[1].quantity, 3);
    });
  });
}
