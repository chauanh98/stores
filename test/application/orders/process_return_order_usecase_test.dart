import 'package:flutter_test/flutter_test.dart';
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
  late ProcessReturnOrderUseCase useCase;

  const currentUser = UserAccount(
    username: 'admin1',
    displayName: 'Khanh Dang',
    role: 'admin',
    storeId: 'store_001',
  );

  final testDate = DateTime(2026, 8, 17, 10, 0);

  setUp(() {
    orderRepo = FakeOrderRepository();
    productRepo = FakeProductRepository();
    inventoryRepo = FakeInventoryRepository();
    customerRepo = FakeCustomerRepository();

    useCase = ProcessReturnOrderUseCase(
      orderRepository: orderRepo,
      productRepository: productRepo,
      inventoryRepository: inventoryRepo,
      customerRepository: customerRepo,
    );
  });

  group('ProcessReturnOrderUseCase Tests', () {
    test('Partial return with debt deduction and cash refund', () async {
      // Setup Product
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

      // Setup Customer with debt
      const customer = Customer(
        id: 'CUST_01',
        name: 'A Tâm',
        phone: '0901234567',
        email: 'tam@example.com',
        address: 'Cần Thơ',
        purchases: [],
        currentDebt: 1500000,
        totalSales: 3000000,
        netSales: 3000000,
      );
      await customerRepo.upsert(customer);


      // Setup Order: 2 items @ 1,000,000 = 2,000,000. Paid 1,200,000, Debt 800,000
      final order = Order(
        id: 'HD000001',
        customerId: 'CUST_01',
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

      // Execute: Return 1 item (value 1,000,000)
      // Expected:
      // totalRefund = 1,000,000
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
        reason: 'Khách đổi sang bản Pro',
      );

      expect(result.totalRefund, 1000000);
      expect(result.debtDeducted, 800000);
      expect(result.cashRefunded, 200000);

      // Verify stock was restored (+1 at store_001: 10 + 1 = 11)
      final updatedProduct = await productRepo.fetchById('PROD_01');
      expect(updatedProduct?.branchStocks['store_001'], 11);

      // Verify inventory transaction was recorded
      expect(inventoryRepo.transactions.length, 1);
      expect(inventoryRepo.transactions.first.type, TransactionType.import);
      expect(inventoryRepo.transactions.first.quantity, 1);
      expect(inventoryRepo.transactions.first.note.contains('HD000001'), true);

      // Verify customer debt and netSales
      final updatedCustomer = await customerRepo.fetchById('CUST_01');
      expect(updatedCustomer?.currentDebt, 700000); // 1,500,000 - 800,000
      expect(updatedCustomer?.netSales, 2000000); // 3,000,000 - 1,000,000

      // Verify updated order
      final updatedOrder = await orderRepo.fetchById('HD000001');
      expect(updatedOrder?.items.first.returnedQuantity, 1);
      expect(updatedOrder?.items.first.activeQuantity, 1);
      expect(updatedOrder?.total, 1000000);
      expect(updatedOrder?.debtAmount, 0); // 800,000 - 800,000
      expect(updatedOrder?.amountPaid, 1000000); // 1,200,000 - 200,000
      expect(updatedOrder?.status, 'completed'); // 1 item still remaining
    });

    test('Full return restores all stock and marks order status as returned', () async {
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
        id: 'HD000002',
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

      expect(result.totalRefund, 5000000);
      expect(result.debtDeducted, 0);
      expect(result.cashRefunded, 5000000);

      // Verify product stock (+2: 5 + 2 = 7)
      final updatedProduct = await productRepo.fetchById('P_MOUSE');
      expect(updatedProduct?.branchStocks['store_001'], 7);

      // Verify order status is returned
      final updatedOrder = await orderRepo.fetchById('HD000002');
      expect(updatedOrder?.status, 'returned');
      expect(updatedOrder?.items.first.returnedQuantity, 2);
      expect(updatedOrder?.items.first.activeQuantity, 0);
      expect(updatedOrder?.total, 0.0);
    });

    test('Return of Combo product restores component product stocks', () async {
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
        id: 'HD000003',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'COMBO_01',
            productName: 'Combo Streamer Starter',
            quantity: 1,
            price: 1200000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 1200000,
        amountPaid: 1200000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

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

      // Verify mouse stock: 10 + (1 * 2) = 12
      final updatedMouse = await productRepo.fetchById('COMP_MOUSE');
      expect(updatedMouse?.branchStocks['store_001'], 12);

      // Verify headset stock: 8 + (1 * 1) = 9
      final updatedHeadset = await productRepo.fetchById('COMP_HEADSET');
      expect(updatedHeadset?.branchStocks['store_001'], 9);

      // Verify 2 inventory transactions were recorded (1 for each component)
      expect(inventoryRepo.transactions.length, 2);
    });

    test('Validation failures throw ValidationException', () async {
      final cancelledOrder = Order(
        id: 'HD_CANC',
        customerId: 'CUST1',
        createdAt: testDate,
        items: [],
        total: 1000,
        status: 'cancelled',
      );

      expect(
        () => useCase.execute(
          originalOrder: cancelledOrder,
          returnItems: [
            const ReturnOrderItem(
              productId: 'P1',
              productName: 'Item 1',
              price: 1000,
              quantity: 1,
            ),
          ],
          storeId: 'store_001',
          currentUser: currentUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      final validOrder = Order(
        id: 'HD_VAL',
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
            returnedQuantity: 1,
          ),
        ],
        total: 2000,
        amountPaid: 2000,
        status: 'completed',
      );

      // Quantity to return (2) > available activeQuantity (1)
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
