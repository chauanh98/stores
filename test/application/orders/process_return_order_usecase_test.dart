import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/core/errors/exceptions.dart';
import 'package:stores/data/datasources/firebase/customer_remote_data_source.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
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

import '../../support/firebase_test_harness.dart';

class FakeOrderRepository implements OrderRepository, OrderRepositoryReturnHandler {
  final Map<String, Order> orders = {};
  final Map<String, ReturnOrder> returnOrders = {};
  final MockFirebaseDatabase? mockDb;

  FakeOrderRepository([this.mockDb]);

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
  Future<void> createReturn(ReturnOrder returnOrder) async {
    returnOrders[returnOrder.id] = returnOrder;
    if (mockDb != null) {
      await mockDb!
          .ref('stores/${returnOrder.storeId}/return_orders/${returnOrder.id}')
          .set(returnOrder.toMap());
    }
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

void main() {
  late FakeOrderRepository orderRepo;
  late FakeProductRepository productRepo;
  late FakeInventoryRepository inventoryRepo;
  late FakeCustomerRepository customerRepo;
  late MockFirebaseDatabase mockDb;
  late CustomerRemoteDataSource customerDataSource;
  late ProcessReturnOrderUseCase useCase;

  const currentUser = UserAccount(
    username: 'admin1',
    displayName: 'Khanh Dang',
    role: 'admin',
    storeId: 'store_001',
  );

  final testDate = DateTime(2026, 8, 17, 10, 0);

  setUp(() {
    mockDb = MockFirebaseDatabase();
    orderRepo = FakeOrderRepository(mockDb);
    productRepo = FakeProductRepository();
    inventoryRepo = FakeInventoryRepository();
    customerRepo = FakeCustomerRepository();
    customerDataSource = CustomerRemoteDataSource(mockDb);

    useCase = ProcessReturnOrderUseCase(
      orderRepository: orderRepo,
      productRepository: productRepo,
      inventoryRepository: inventoryRepo,
      customerRepository: customerRepo,
      customerDataSource: customerDataSource,
    );
  });

  group('ProcessReturnOrderUseCase Lifecycle & Regression Tests', () {
    test('Standard return order: creates ReturnOrder in stores/storeId/return_orders, restocks returned items with import transactions', () async {
      const product = Product(
        id: 'PROD_01',
        name: 'Bàn phím cơ Aula F75',
        code: 'AULA75',
        price: 1000000,
        costPrice: 600000,
        branchStocks: {'store_001': 10, 'store_002': 5},
        category: 'Bàn phím',
      );
      await productRepo.upsert(product);

      final order = Order(
        id: 'HD000001',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'PROD_01',
            productName: 'Bàn phím cơ Aula F75',
            quantity: 2,
            price: 1000000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 2000000,
        amountPaid: 2000000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      // Return 1 item
      final result = await useCase.execute(
        originalOrder: order,
        returnItems: [
          const ReturnOrderItem(
            productId: 'PROD_01',
            productName: 'Bàn phím cơ Aula F75',
            price: 1000000,
            quantity: 1,
          ),
        ],
        storeId: 'store_001',
        currentUser: currentUser,
        reason: 'Khách đổi trả bàn phím',
      );

      // 1. Verify return order record was saved in ReturnOrderHandler and MockFirebaseDatabase
      expect(orderRepo.returnOrders.containsKey(result.returnOrder.id), true);
      final rtdbReturn = mockDb.recorder.callsFor('set').firstWhere(
        (c) => c.path == 'stores/store_001/return_orders/${result.returnOrder.id}',
      );
      expect(rtdbReturn.value, isNotNull);
      final returnMap = rtdbReturn.value as Map;
      expect(returnMap['orderId'], 'HD000001');
      expect(returnMap['totalReturnAmount'], 1000000.0);
      expect(returnMap['storeId'], 'store_001');

      // 2. Verify restock (+1 at store_001: 10 + 1 = 11, store_002 stays 5)
      final updatedProduct = await productRepo.fetchById('PROD_01');
      expect(updatedProduct?.branchStocks['store_001'], 11);
      expect(updatedProduct?.branchStocks['store_002'], 5);

      // 3. Verify import inventory transaction recorded
      expect(inventoryRepo.transactions.length, 1);
      final tx = inventoryRepo.transactions.first;
      expect(tx.type, TransactionType.import);
      expect(tx.quantity, 1);
      expect(tx.productId, 'PROD_01');
      expect(tx.storeId, 'store_001');
      expect(tx.note.contains('HD000001'), true);

      // 4. Financial check: paid in full, so cashRefunded = 1,000,000; debtDeducted = 0
      expect(result.totalRefund, 1000000);
      expect(result.debtDeducted, 0);
      expect(result.cashRefunded, 1000000);

      // 5. Order items: 1 returned, 1 active; status stays 'completed'
      expect(result.updatedOrder.items.first.returnedQuantity, 1);
      expect(result.updatedOrder.items.first.activeQuantity, 1);
      expect(result.updatedOrder.status, 'completed');
    });

    test('Financial reconciliation: deducts outstanding debt before paying out cash refund (debtDeducted = min(totalRefund, remainingDebt)) and logs CustomerDebtTransaction', () async {
      const product = Product(
        id: 'PROD_01',
        name: 'Bàn phím cơ Aula F75',
        code: 'AULA75',
        price: 1000000,
        costPrice: 600000,
        branchStocks: {'store_001': 10},
        category: 'Bàn phím',
      );
      await productRepo.upsert(product);

      const customer = Customer(
        id: 'CUST_RECON',
        name: 'Trần Văn B',
        phone: '0901234567',
        email: 'b@example.com',
        address: 'Cần Thơ',
        purchases: [],
        currentDebt: 1500000,
        totalSales: 3000000,
        netSales: 3000000,
      );
      await customerRepo.upsert(customer);

      // Order total: 2,000,000 (2 items). Paid: 1,200,000. Debt: 800,000
      final order = Order(
        id: 'HD_RECON_01',
        customerId: 'CUST_RECON',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'PROD_01',
            productName: 'Bàn phím cơ Aula F75',
            quantity: 2,
            price: 1000000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 2000000,
        amountPaid: 1200000,
        debtAmount: 800000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      // Return 1 item (value 1,000,000). Remaining debt is 800,000
      // debtDeducted = min(1,000,000, 800,000) = 800,000
      // cashRefunded = 1,000,000 - 800,000 = 200,000
      final result = await useCase.execute(
        originalOrder: order,
        returnItems: [
          const ReturnOrderItem(
            productId: 'PROD_01',
            productName: 'Bàn phím cơ Aula F75',
            price: 1000000,
            quantity: 1,
          ),
        ],
        storeId: 'store_001',
        currentUser: currentUser,
        reason: 'Khách muốn trả bớt',
      );

      expect(result.totalRefund, 1000000);
      expect(result.debtDeducted, 800000);
      expect(result.cashRefunded, 200000);

      // Verify customer debt: 1,500,000 - 800,000 = 700,000
      final updatedCustomer = await customerRepo.fetchById('CUST_RECON');
      expect(updatedCustomer?.currentDebt, 700000);
      expect(updatedCustomer?.netSales, 2000000); // 3,000,000 - 1,000,000

      // Verify CustomerDebtTransaction recorded in RTDB via customerDataSource
      final debtCalls = mockDb.recorder.callsFor('set').where(
        (c) => c.path.contains('shared_customers/CUST_RECON/debt_transactions'),
      );
      expect(debtCalls.isNotEmpty, true);
      final debtTxData = debtCalls.first.value as Map;
      expect(debtTxData['customerId'], 'CUST_RECON');
      expect(debtTxData['amount'], -800000.0);
      expect(debtTxData['remainingDebt'], 700000.0);
      expect(debtTxData['type'], DebtTransactionType.adjustment.name);
      expect(debtTxData['note'].toString().contains('HD_RECON_01'), true);

      // Verify order financial update: debtAmount becomes 0, amountPaid becomes 1,000,000
      expect(result.updatedOrder.debtAmount, 0.0);
      expect(result.updatedOrder.amountPaid, 1000000.0);
      expect(result.updatedOrder.total, 1000000.0);
    });

    test('Marks order status as returned when all items are fully returned', () async {
      const product = Product(
        id: 'P_MOUSE',
        name: 'Chuột Logitech MX Master 3S',
        code: 'LOGI3S',
        price: 2500000,
        costPrice: 1800000,
        branchStocks: {'store_001': 5},
        category: 'Chuột',
      );
      await productRepo.upsert(product);

      final order = Order(
        id: 'HD_ALL_RETURN',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_MOUSE',
            productName: 'Chuột Logitech MX Master 3S',
            quantity: 2,
            price: 2500000,
            warrantyMonths: 24,
            purchaseDate: testDate,
          ),
        ],
        total: 5000000,
        amountPaid: 5000000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      // Return all 2 items
      final result = await useCase.execute(
        originalOrder: order,
        returnItems: [
          const ReturnOrderItem(
            productId: 'P_MOUSE',
            productName: 'Chuột Logitech MX Master 3S',
            price: 2500000,
            quantity: 2,
          ),
        ],
        storeId: 'store_001',
        currentUser: currentUser,
        reason: 'Trả toàn bộ đơn hàng',
      );

      // Status transitioned to 'returned'
      expect(result.updatedOrder.status, 'returned');
      expect(result.updatedOrder.items.first.returnedQuantity, 2);
      expect(result.updatedOrder.items.first.activeQuantity, 0);
      expect(result.updatedOrder.total, 0.0);
      expect(result.totalRefund, 5000000);
      expect(result.cashRefunded, 5000000);

      // Product stock restored (+2: 5 + 2 = 7)
      final updatedProd = await productRepo.fetchById('P_MOUSE');
      expect(updatedProd?.branchStocks['store_001'], 7);
    });

    test('Combo item return: unpacks combo components and restocks components into branch stock', () async {
      // Child component 1: Chuột (2 per combo)
      const mouseComp = Product(
        id: 'COMP_MOUSE',
        name: 'Chuột Gaming M1',
        code: 'GM1',
        price: 300000,
        costPrice: 200000,
        branchStocks: {'store_001': 10},
        category: 'Phụ kiện',
      );
      await productRepo.upsert(mouseComp);

      // Child component 2: Tai nghe (1 per combo)
      const headsetComp = Product(
        id: 'COMP_HEADSET',
        name: 'Tai nghe Gaming H1',
        code: 'GH1',
        price: 700000,
        costPrice: 500000,
        branchStocks: {'store_001': 8},
        category: 'Phụ kiện',
      );
      await productRepo.upsert(headsetComp);

      // Parent Combo Product
      const comboProduct = Product(
        id: 'COMBO_01',
        name: 'Combo Streamer Starter',
        code: 'STREAM01',
        price: 1200000,
        costPrice: 900000,
        branchStocks: {'store_001': 0},
        category: 'Combo',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'COMP_MOUSE',
            productCode: 'GM1',
            productName: 'Chuột Gaming M1',
            quantity: 2,
          ),
          ComboComponent(
            productId: 'COMP_HEADSET',
            productCode: 'GH1',
            productName: 'Tai nghe Gaming H1',
            quantity: 1,
          ),
        ],
      );
      await productRepo.upsert(comboProduct);

      final order = Order(
        id: 'HD_COMBO_RET',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'COMBO_01',
            productName: 'Combo Streamer Starter',
            quantity: 2,
            price: 1200000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 2400000,
        amountPaid: 2400000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      // Return 1 combo
      await useCase.execute(
        originalOrder: order,
        returnItems: [
          ReturnOrderItem(
            productId: 'COMBO_01',
            productName: 'Combo Streamer Starter',
            price: 1200000,
            quantity: 1,
            isCombo: true,
            comboComponents: comboProduct.comboComponents,
          ),
        ],
        storeId: 'store_001',
        currentUser: currentUser,
      );

      // Mouse component stock: 10 + (1 combo * 2) = 12
      final updatedMouse = await productRepo.fetchById('COMP_MOUSE');
      expect(updatedMouse?.branchStocks['store_001'], 12);

      // Headset component stock: 8 + (1 combo * 1) = 9
      final updatedHeadset = await productRepo.fetchById('COMP_HEADSET');
      expect(updatedHeadset?.branchStocks['store_001'], 9);

      // 2 separate import transactions recorded for child components
      expect(inventoryRepo.transactions.length, 2);
      expect(inventoryRepo.transactions.every((t) => t.type == TransactionType.import), true);
    });

    test('Validation edge cases: empty return items, return qty <= 0, item not in order, or qty > activeQuantity throw ValidationException', () async {
      final validOrder = Order(
        id: 'HD_VALID',
        customerId: 'CUST1',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P1',
            productName: 'Item 1',
            quantity: 2,
            price: 1000,
            warrantyMonths: 0,
            purchaseDate: testDate,
            returnedQuantity: 1, // activeQuantity is 1
          ),
        ],
        total: 2000,
        amountPaid: 2000,
        status: 'completed',
      );

      // Empty items
      expect(
        () => useCase.execute(
          originalOrder: validOrder,
          returnItems: const [],
          storeId: 'store_001',
          currentUser: currentUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      // Return quantity <= 0
      expect(
        () => useCase.execute(
          originalOrder: validOrder,
          returnItems: [
            const ReturnOrderItem(
              productId: 'P1',
              productName: 'Item 1',
              price: 1000,
              quantity: 0,
            ),
          ],
          storeId: 'store_001',
          currentUser: currentUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      // Item not in order
      expect(
        () => useCase.execute(
          originalOrder: validOrder,
          returnItems: [
            const ReturnOrderItem(
              productId: 'P_UNKNOWN',
              productName: 'Unknown Product',
              price: 1000,
              quantity: 1,
            ),
          ],
          storeId: 'store_001',
          currentUser: currentUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      // Quantity > activeQuantity (active is 1, asking 2)
      expect(
        () => useCase.execute(
          originalOrder: validOrder,
          returnItems: [
            const ReturnOrderItem(
              productId: 'P1',
              productName: 'Item 1',
              price: 1000,
              quantity: 2,
            ),
          ],
          storeId: 'store_001',
          currentUser: currentUser,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
