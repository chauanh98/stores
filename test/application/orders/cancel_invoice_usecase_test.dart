import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/core/errors/exceptions.dart';
import 'package:stores/data/datasources/firebase/customer_remote_data_source.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
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

import '../../support/firebase_test_harness.dart';

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
  late MockFirebaseDatabase mockDb;
  late CustomerRemoteDataSource customerDataSource;
  late CancelInvoiceUseCase useCase;

  const adminUser = UserAccount(
    username: 'admin1',
    displayName: 'Khanh Dang',
    role: 'admin',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'sup1',
    displayName: 'Supervisor Dan',
    role: 'supervisor',
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
    mockDb = MockFirebaseDatabase();
    customerDataSource = CustomerRemoteDataSource(mockDb);

    useCase = CancelInvoiceUseCase(
      orderRepository: orderRepo,
      productRepository: productRepo,
      inventoryRepository: inventoryRepo,
      customerRepository: customerRepo,
      customerDataSource: customerDataSource,
    );
  });

  group('CancelInvoiceUseCase Lifecycle & Regression Tests', () {
    test('Non-admin, non-supervisor user cannot cancel invoice and throws UnauthorizedException', () async {
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

    test('Supervisor user can cancel invoice even without direct delete invoice permission', () async {
      final order = Order(
        id: 'HD_SUP_01',
        customerId: 'khach_le',
        createdAt: testDate,
        items: const [],
        total: 500000,
        status: 'completed',
      );

      final cancelled = await useCase.execute(
        order: order,
        cancelReason: 'Quản lý duyệt hủy đơn',
        currentUser: supervisorUser,
        storeId: 'store_001',
      );

      expect(cancelled.status, 'cancelled');
      expect(cancelled.cancelledBy, 'sup1');
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

    test('Already cancelled invoice cannot be cancelled again and throws ValidationException', () async {
      final cancelledOrder = Order(
        id: 'HD_ALREADY_CANCEL',
        customerId: 'CUST1',
        createdAt: testDate,
        items: const [],
        total: 1000000,
        status: 'cancelled',
        cancelReason: 'Đã hủy trước đó',
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

    test('Standard product invoice cancel: updates status, increments branch stock, logs import tx, decrements debt & logs CustomerDebtTransaction', () async {
      // 1. Setup Standard Product with multi-branch stock
      const product = Product(
        id: 'P_MONITOR',
        name: 'Màn hình Dell 27 inch',
        code: 'DELL27',
        price: 5000000,
        costPrice: 3800000,
        branchStocks: {'store_001': 3, 'store_002': 2},
        category: 'Màn hình',
      );
      await productRepo.upsert(product);

      // 2. Setup Customer with existing debt and sales
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

      // 3. Order: 2 Monitors @ 5,000,000 = 10,000,000. Paid 7,000,000, Debt 3,000,000
      final order = Order(
        id: 'HD000010',
        customerId: 'CUST_V',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_MONITOR',
            productName: 'Màn hình Dell 27 inch',
            quantity: 2,
            price: 5000000,
            warrantyMonths: 36,
            purchaseDate: testDate,
          ),
        ],
        total: 10000000,
        amountPaid: 7000000,
        debtAmount: 3000000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      // 4. Execute Cancel Invoice
      final cancelledOrder = await useCase.execute(
        order: order,
        cancelReason: 'Khách hàng đổi dự án khác',
        currentUser: adminUser,
        storeId: 'store_001',
      );

      // Verify order status
      expect(cancelledOrder.isCancelled, true);
      expect(cancelledOrder.status, 'cancelled');
      expect(cancelledOrder.cancelReason, 'Khách hàng đổi dự án khác');
      expect(cancelledOrder.cancelledBy, 'admin1');
      expect(cancelledOrder.cancelledByName, 'Khanh Dang');
      expect(cancelledOrder.cancelledAt, isNotNull);

      // Verify stock restoration (+2 at store_001: 3 + 2 = 5; store_002 remains 2)
      final updatedMonitor = await productRepo.fetchById('P_MONITOR');
      expect(updatedMonitor?.branchStocks['store_001'], 5);
      expect(updatedMonitor?.branchStocks['store_002'], 2);

      // Verify inventory transaction was recorded
      expect(inventoryRepo.transactions.length, 1);
      final invTx = inventoryRepo.transactions.first;
      expect(invTx.type, TransactionType.import);
      expect(invTx.quantity, 2);
      expect(invTx.productId, 'P_MONITOR');
      expect(invTx.storeId, 'store_001');
      expect(invTx.note.contains('HD000010'), true);

      // Verify customer debt & sales reversal
      final updatedCustomer = await customerRepo.fetchById('CUST_V');
      expect(updatedCustomer?.currentDebt, 1000000); // 4,000,000 - 3,000,000
      expect(updatedCustomer?.totalSales, 0.0); // 10,000,000 - 10,000,000
      expect(updatedCustomer?.netSales, 0.0);

      // Verify CustomerDebtTransaction recorded via CustomerRemoteDataSource in RTDB
      final debtTxCalls = mockDb.recorder.callsFor('set');
      expect(debtTxCalls.isNotEmpty, true);
      final debtTxCall = debtTxCalls.firstWhere(
        (c) => c.path.contains('shared_customers/CUST_V/debt_transactions'),
      );
      final debtData = debtTxCall.value as Map;
      expect(debtData['customerId'], 'CUST_V');
      expect(debtData['amount'], -3000000.0);
      expect(debtData['remainingDebt'], 1000000.0);
      expect(debtData['type'], DebtTransactionType.adjustment.name);
      expect(debtData['createdBy'], 'admin1');
      expect(debtData['note'].toString().contains('HD000010'), true);
    });

    test('Combo product invoice cancel: unpacks combo components, increments each component branch stock, logs separate import transactions', () async {
      // 1. Setup child component products
      const keyProduct = Product(
        id: 'C_KEY',
        name: 'Phím cơ',
        code: 'K1',
        price: 800000,
        costPrice: 500000,
        branchStocks: {'store_001': 10, 'store_002': 4},
        category: 'Phụ kiện',
      );
      const mouseProduct = Product(
        id: 'C_MOUSE',
        name: 'Chuột quang',
        code: 'M1',
        price: 200000,
        costPrice: 120000,
        branchStocks: {'store_001': 15, 'store_002': 6},
        category: 'Phụ kiện',
      );
      await productRepo.upsert(keyProduct);
      await productRepo.upsert(mouseProduct);

      // 2. Setup Combo Product: 1 Key + 2 Mice
      const comboProduct = Product(
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
      await productRepo.upsert(comboProduct);

      // 3. Order: 2 Combos = 1,800,000. Paid 1,800,000 (0 debt)
      final order = Order(
        id: 'HD_COMBO_01',
        customerId: 'CUST_PAID',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_COMBO',
            productName: 'Combo Văn Phòng',
            quantity: 2,
            price: 900000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 1800000,
        amountPaid: 1800000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      const customer = Customer(
        id: 'CUST_PAID',
        name: 'Nguyễn Văn A',
        phone: '0988776655',
        email: 'a@example.com',
        address: 'Hồ Chí Minh',
        purchases: [],
        currentDebt: 500000,
        totalSales: 2000000,
        netSales: 2000000,
      );
      await customerRepo.upsert(customer);

      // 4. Cancel Combo invoice
      await useCase.execute(
        order: order,
        cancelReason: 'Hủy đơn combo đã thanh toán đủ',
        currentUser: adminUser,
        storeId: 'store_001',
      );

      // Combo component 1 (Key): 10 + (2 combo * 1) = 12 at store_001
      final updatedKey = await productRepo.fetchById('C_KEY');
      expect(updatedKey?.branchStocks['store_001'], 12);
      expect(updatedKey?.branchStocks['store_002'], 4);

      // Combo component 2 (Mouse): 15 + (2 combo * 2) = 19 at store_001
      final updatedMouse = await productRepo.fetchById('C_MOUSE');
      expect(updatedMouse?.branchStocks['store_001'], 19);
      expect(updatedMouse?.branchStocks['store_002'], 6);

      // 2 separate import transactions logged
      expect(inventoryRepo.transactions.length, 2);
      expect(inventoryRepo.transactions.every((t) => t.type == TransactionType.import), true);
      final keyTx = inventoryRepo.transactions.firstWhere((t) => t.productId == 'C_KEY');
      final mouseTx = inventoryRepo.transactions.firstWhere((t) => t.productId == 'C_MOUSE');
      expect(keyTx.quantity, 2);
      expect(mouseTx.quantity, 4);

      // Since order had 0 debt, customer currentDebt remains 500,000 (no debt reversal)
      final updatedCustomer = await customerRepo.fetchById('CUST_PAID');
      expect(updatedCustomer?.currentDebt, 500000);
      expect(updatedCustomer?.totalSales, 200000); // 2,000,000 - 1,800,000
      expect(updatedCustomer?.netSales, 200000);

      // No debt transaction recorded because debtToReverse was 0
      final debtCalls = mockDb.recorder.callsFor('set').where(
        (c) => c.path.contains('shared_customers/CUST_PAID/debt_transactions'),
      );
      expect(debtCalls.isEmpty, true);
    });

    test('Edge case: Walk-in customer (khach_le or empty customerId) restores stock without customer debt errors', () async {
      const product = Product(
        id: 'P_ITEM',
        name: 'Tai nghe Bluetooth',
        code: 'TN01',
        price: 300000,
        costPrice: 150000,
        branchStocks: {'store_001': 5},
        category: 'Phụ kiện',
      );
      await productRepo.upsert(product);

      final orderWalkIn = Order(
        id: 'HD_WALKIN_01',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_ITEM',
            productName: 'Tai nghe Bluetooth',
            quantity: 3,
            price: 300000,
            warrantyMonths: 6,
            purchaseDate: testDate,
          ),
        ],
        total: 900000,
        amountPaid: 900000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(orderWalkIn);

      final cancelled = await useCase.execute(
        order: orderWalkIn,
        cancelReason: 'Khách lẻ trả hàng và hủy hóa đơn',
        currentUser: adminUser,
        storeId: 'store_001',
      );

      expect(cancelled.status, 'cancelled');
      final updatedProduct = await productRepo.fetchById('P_ITEM');
      expect(updatedProduct?.branchStocks['store_001'], 8); // 5 + 3 = 8
      expect(inventoryRepo.transactions.length, 1);
    });
  });
}
