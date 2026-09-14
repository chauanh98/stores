import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/core/errors/exceptions.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
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
  late CancelInvoiceUseCase useCase;

  const adminUser = UserAccount(
    username: 'admin1',
    displayName: 'Khanh Dang',
    role: 'admin',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'nhanvien1',
    displayName: 'Staff 1',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  final testDate = DateTime(2026, 8, 17, 10, 0);

  setUp(() {
    orderRepo = FakeOrderRepository();
    productRepo = FakeProductRepository();
    inventoryRepo = FakeInventoryRepository();
    customerRepo = FakeCustomerRepository();

    useCase = CancelInvoiceUseCase(
      orderRepository: orderRepo,
      productRepository: productRepo,
      inventoryRepository: inventoryRepo,
      customerRepository: customerRepo,
    );
  });

  group('CancelInvoiceUseCase Tests', () {
    test('Non-admin user cannot cancel invoice and throws UnauthorizedException', () async {
      final order = Order(
        id: 'HD000001',
        customerId: 'CUST1',
        createdAt: testDate,
        items: const [],
        total: 1000000,
        status: 'completed',
      );

      expect(
        () => useCase.execute(
          order: order,
          cancelReason: 'Khách yêu cầu hủy',
          currentUser: staffUser,
          storeId: 'store_001',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('Empty cancel reason throws ValidationException', () async {
      final order = Order(
        id: 'HD000001',
        customerId: 'CUST1',
        createdAt: testDate,
        items: const [],
        total: 1000000,
        status: 'completed',
      );

      expect(
        () => useCase.execute(
          order: order,
          cancelReason: '   ',
          currentUser: adminUser,
          storeId: 'store_001',
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('Admin successfully cancels invoice, restoring stock and reverting customer debt and sales', () async {
      // 1. Setup Standard Product
      const product1 = Product(
        id: 'P_MONITOR',
        name: 'Màn hình Dell 27 inch',
        code: 'DELL27',
        price: 5000000,
        costPrice: 3800000,
        branchStocks: {'store_001': 3, 'store_002': 2},
        category: 'Màn hình',
      );
      await productRepo.upsert(product1);

      // 2. Setup Combo Product with 2 child items
      const child1 = Product(
        id: 'C_KEY',
        name: 'Phím cơ',
        code: 'K1',
        price: 800000,
        costPrice: 500000,
        branchStocks: {'store_001': 10},
        category: 'Phụ kiện',
      );
      const child2 = Product(
        id: 'C_MOUSE',
        name: 'Chuột quang',
        code: 'M1',
        price: 200000,
        costPrice: 120000,
        branchStocks: {'store_001': 15},
        category: 'Phụ kiện',
      );
      await productRepo.upsert(child1);
      await productRepo.upsert(child2);

      const combo = Product(
        id: 'P_COMBO',
        name: 'Combo Văn Phòng',
        code: 'OFFICE01',
        price: 900000,
        costPrice: 620000,
        branchStocks: {'store_001': 0},
        category: 'Combo',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'C_KEY',
            productCode: 'K1',
            productName: 'Phím cơ',
            quantity: 1,
          ),
          ComboComponent(
            productId: 'C_MOUSE',
            productCode: 'M1',
            productName: 'Chuột quang',
            quantity: 2,
          ),
        ],
      );
      await productRepo.upsert(combo);

      // 3. Setup Customer with existing debt and sales
      const customer = Customer(
        id: 'CUST_V',
        name: 'Công ty Alpha',
        phone: '0912345678',
        email: 'alpha@example.com',
        address: 'Hà Nội',
        purchases: [],
        currentDebt: 4000000,
        totalSales: 10000000,
        netSales: 10000000,
      );
      await customerRepo.upsert(customer);


      // 4. Order: 1 Monitor (5,000,000) + 1 Combo (900,000) = 5,900,000
      // Paid 2,900,000, Debt 3,000,000
      final order = Order(
        id: 'HD000010',
        customerId: 'CUST_V',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_MONITOR',
            productName: 'Màn hình Dell 27 inch',
            quantity: 1,
            price: 5000000,
            warrantyMonths: 36,
            purchaseDate: testDate,
          ),
          OrderItem(
            productId: 'P_COMBO',
            productName: 'Combo Văn Phòng',
            quantity: 1,
            price: 900000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 5900000,
        amountPaid: 2900000,
        debtAmount: 3000000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      // 5. Execute Cancel Invoice
      final cancelledOrder = await useCase.execute(
        order: order,
        cancelReason: 'Khách hàng đổi dự án khác',
        currentUser: adminUser,
        storeId: 'store_001',
      );

      // Verify order status and cancellation fields
      expect(cancelledOrder.isCancelled, true);
      expect(cancelledOrder.status, 'cancelled');
      expect(cancelledOrder.cancelReason, 'Khách hàng đổi dự án khác');
      expect(cancelledOrder.cancelledBy, 'admin1');
      expect(cancelledOrder.cancelledByName, 'Khanh Dang');
      expect(cancelledOrder.cancelledAt, isNotNull);

      // Verify stock restoration
      // Monitor: 3 + 1 = 4 at store_001
      final updatedMonitor = await productRepo.fetchById('P_MONITOR');
      expect(updatedMonitor?.branchStocks['store_001'], 4);

      // Combo component 1 (Key): 10 + (1 * 1) = 11
      final updatedKey = await productRepo.fetchById('C_KEY');
      expect(updatedKey?.branchStocks['store_001'], 11);

      // Combo component 2 (Mouse): 15 + (1 * 2) = 17
      final updatedMouse = await productRepo.fetchById('C_MOUSE');
      expect(updatedMouse?.branchStocks['store_001'], 17);

      // Verify inventory transactions (1 for Monitor, 2 for combo components = 3 total)
      expect(inventoryRepo.transactions.length, 3);
      expect(inventoryRepo.transactions.every((t) => t.type == TransactionType.import), true);

      // Verify customer debt & sales reversal
      final updatedCustomer = await customerRepo.fetchById('CUST_V');
      // Debt reversed: 4,000,000 - 3,000,000 = 1,000,000
      expect(updatedCustomer?.currentDebt, 1000000);
      // Total sales reversed: 10,000,000 - 5,900,000 = 4,100,000
      expect(updatedCustomer?.totalSales, 4100000);
      expect(updatedCustomer?.netSales, 4100000);
    });

    test('Already cancelled invoice cannot be cancelled again', () async {
      final cancelledOrder = Order(
        id: 'HD_ALREADY_CANCEL',
        customerId: 'CUST1',
        createdAt: testDate,
        items: [],
        total: 1000000,
        status: 'cancelled',
        cancelReason: 'Đã hủy',
      );

      expect(
        () => useCase.execute(
          order: cancelledOrder,
          cancelReason: 'Hủy lại lần nữa',
          currentUser: adminUser,
          storeId: 'store_001',
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
