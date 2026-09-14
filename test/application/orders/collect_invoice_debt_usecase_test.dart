import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/usecases/collect_invoice_debt_usecase.dart';
import 'package:stores/core/errors/exceptions.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';

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
  late FakeCustomerRepository customerRepo;
  late CollectInvoiceDebtUseCase useCase;

  const currentUser = UserAccount(
    username: 'admin1',
    displayName: 'Khanh Dang',
    role: 'admin',
    storeId: 'store_001',
  );

  final testDate = DateTime(2026, 8, 17, 10, 0);

  setUp(() {
    orderRepo = FakeOrderRepository();
    customerRepo = FakeCustomerRepository();

    useCase = CollectInvoiceDebtUseCase(
      orderRepository: orderRepo,
      customerRepository: customerRepo,
    );
  });

  group('CollectInvoiceDebtUseCase Tests', () {
    test('Partial debt collection updates order paid amount and customer debt', () async {
      const customer = Customer(
        id: 'CUST_433',
        name: 'A Tâm ( Nhựt xd)',
        phone: '0906636382',
        email: '',
        address: 'Cần Thơ',
        purchases: [],
        currentDebt: 28010000,
        totalSales: 34586000,
        netSales: 34586000,
      );
      await customerRepo.upsert(customer);


      // Order total 3,150,000; paid 150,000; debt 3,000,000
      final order = Order(
        id: 'HD000002',
        customerId: 'CUST_433',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'GCG10',
            productName: 'Ghế bậc thang',
            quantity: 1,
            price: 3150000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 3150000,
        amountPaid: 150000,
        debtAmount: 3000000,
        status: 'completed',
        paymentMethod: 'cash',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      // Collect 1,000,000 via VietQR Transfer
      final updatedOrder = await useCase.execute(
        order: order,
        amount: 1000000,
        paymentMethod: 'transfer',
        currentUser: currentUser,
        note: 'Chuyển khoản VietQR',
      );

      // Verify order update: amountPaid = 1,150,000; debtAmount = 2,000,000; remainingDebt = 2,000,000
      expect(updatedOrder.amountPaid, 1150000);
      expect(updatedOrder.debtAmount, 2000000);
      expect(updatedOrder.remainingDebt, 2000000);
      expect(updatedOrder.hasDebt, true);

      // Verify repo persisted order
      final persistedOrder = await orderRepo.fetchById('HD000002');
      expect(persistedOrder?.amountPaid, 1150000);
      expect(persistedOrder?.debtAmount, 2000000);

      // Verify customer debt update: 28,010,000 - 1,000,000 = 27,010,000
      final updatedCustomer = await customerRepo.fetchById('CUST_433');
      expect(updatedCustomer?.currentDebt, 27010000);
    });

    test('Full debt collection sets remainingDebt to 0 and clears order debt', () async {
      const customer = Customer(
        id: 'CUST_433',
        name: 'A Tâm',
        phone: '0906636382',
        email: '',
        address: 'Cần Thơ',
        purchases: [],
        currentDebt: 3000000,
      );
      await customerRepo.upsert(customer);


      final order = Order(
        id: 'HD000002',
        customerId: 'CUST_433',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'GCG10',
            productName: 'Ghế bậc thang',
            quantity: 1,
            price: 3150000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 3150000,
        amountPaid: 150000,
        debtAmount: 3000000,
        status: 'completed',
      );
      await orderRepo.create(order);

      // Collect all remaining 3,000,000
      final updatedOrder = await useCase.execute(
        order: order,
        amount: 3000000,
        paymentMethod: 'cash',
        currentUser: currentUser,
      );

      expect(updatedOrder.amountPaid, 3150000);
      expect(updatedOrder.debtAmount, 0);
      expect(updatedOrder.remainingDebt, 0.0);
      expect(updatedOrder.hasDebt, false);

      final updatedCustomer = await customerRepo.fetchById('CUST_433');
      expect(updatedCustomer?.currentDebt, 0.0);
    });

    test('Validation errors throw ValidationException', () async {
      final cancelledOrder = Order(
        id: 'HD_CANC',
        customerId: 'CUST1',
        createdAt: testDate,
        items: [],
        total: 1000000,
        amountPaid: 0,
        debtAmount: 1000000,
        status: 'cancelled',
      );

      expect(
        () => useCase.execute(
          order: cancelledOrder,
          amount: 500000,
          paymentMethod: 'cash',
          currentUser: currentUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      final completedOrder = Order(
        id: 'HD_COMP',
        customerId: 'CUST1',
        createdAt: testDate,
        items: [],
        total: 1000000,
        amountPaid: 600000,
        debtAmount: 400000,
        status: 'completed',
      );

      // Amount <= 0
      expect(
        () => useCase.execute(
          order: completedOrder,
          amount: 0,
          paymentMethod: 'cash',
          currentUser: currentUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      // Amount > remainingDebt (500,000 > 400,000)
      expect(
        () => useCase.execute(
          order: completedOrder,
          amount: 500000,
          paymentMethod: 'cash',
          currentUser: currentUser,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
