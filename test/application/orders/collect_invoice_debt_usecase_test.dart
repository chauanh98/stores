import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/usecases/collect_invoice_debt_usecase.dart';
import 'package:stores/core/errors/exceptions.dart';
import 'package:stores/data/datasources/firebase/customer_remote_data_source.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';

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
  late MockFirebaseDatabase mockDb;
  late CustomerRemoteDataSource customerDataSource;
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
    mockDb = MockFirebaseDatabase();
    customerDataSource = CustomerRemoteDataSource(mockDb);

    useCase = CollectInvoiceDebtUseCase(
      orderRepository: orderRepo,
      customerRepository: customerRepo,
      customerDataSource: customerDataSource,
    );
  });

  group('CollectInvoiceDebtUseCase Lifecycle Tests', () {
    test('Partial debt collection: increases order.amountPaid, decreases order.debtAmount, decreases customer.currentDebt, records CustomerDebtTransaction (payment)', () async {
      const customer = Customer(
        id: 'CUST_433',
        name: 'A Tâm (Nhựt xd)',
        phone: '0906636382',
        email: 'tam@example.com',
        address: 'Cần Thơ',
        purchases: [],
        currentDebt: 28010000,
        totalSales: 34586000,
        netSales: 34586000,
      );
      await customerRepo.upsert(customer);

      // Order total: 3,150,000; paid: 150,000; debt: 3,000,000
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
        note: 'Chuyển khoản VietQR đợt 1',
      );

      // Verify order amounts
      expect(updatedOrder.amountPaid, 1150000);
      expect(updatedOrder.debtAmount, 2000000);
      expect(updatedOrder.remainingDebt, 2000000);
      expect(updatedOrder.hasDebt, true);

      // Verify persisted in orderRepo
      final persistedOrder = await orderRepo.fetchById('HD000002');
      expect(persistedOrder?.amountPaid, 1150000);
      expect(persistedOrder?.debtAmount, 2000000);

      // Verify customer debt reduced in customerRepo: 28,010,000 - 1,000,000 = 27,010,000
      final updatedCustomer = await customerRepo.fetchById('CUST_433');
      expect(updatedCustomer?.currentDebt, 27010000);

      // Verify CustomerDebtTransaction recorded in RTDB via customerDataSource
      final debtTxCalls = mockDb.recorder.callsFor('set');
      expect(debtTxCalls.isNotEmpty, true);
      final debtTxCall = debtTxCalls.firstWhere(
        (c) => c.path.contains('shared_customers/CUST_433/debt_transactions'),
      );
      final txData = debtTxCall.value as Map;
      expect(txData['customerId'], 'CUST_433');
      expect(txData['amount'], -1000000.0);
      expect(txData['remainingDebt'], 27010000.0);
      expect(txData['type'], DebtTransactionType.payment.name);
      expect(txData['createdBy'], 'admin1');
      expect(txData['note'].toString().contains('HD000002'), true);
      expect(txData['note'].toString().contains('Chuyển khoản'), true);
    });

    test('Full debt collection: pays remaining debt down to 0 and clears order debt', () async {
      const customer = Customer(
        id: 'CUST_FULL',
        name: 'Bà Ba',
        phone: '0901112233',
        email: 'baba@example.com',
        address: 'An Giang',
        purchases: [],
        currentDebt: 3000000,
        totalSales: 5000000,
        netSales: 5000000,
      );
      await customerRepo.upsert(customer);

      final order = Order(
        id: 'HD_FULL_01',
        customerId: 'CUST_FULL',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_ITEM',
            productName: 'Bàn ghế ăn',
            quantity: 1,
            price: 3000000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 3000000,
        amountPaid: 0,
        debtAmount: 3000000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(order);

      final updatedOrder = await useCase.execute(
        order: order,
        amount: 3000000,
        paymentMethod: 'cash',
        currentUser: currentUser,
        note: 'Thu toàn bộ tiền mặt',
      );

      expect(updatedOrder.amountPaid, 3000000);
      expect(updatedOrder.debtAmount, 0.0);
      expect(updatedOrder.remainingDebt, 0.0);
      expect(updatedOrder.hasDebt, false);

      final updatedCustomer = await customerRepo.fetchById('CUST_FULL');
      expect(updatedCustomer?.currentDebt, 0.0);

      // Verify transaction recorded
      final debtCalls = mockDb.recorder.callsFor('set').where(
        (c) => c.path.contains('shared_customers/CUST_FULL/debt_transactions'),
      );
      expect(debtCalls.isNotEmpty, true);
    });

    test('Edge case: Payment amount exceeding remaining debt throws ValidationException', () async {
      final order = Order(
        id: 'HD_OVER_01',
        customerId: 'CUST_OVER',
        createdAt: testDate,
        items: const [],
        total: 1000000,
        amountPaid: 600000,
        debtAmount: 400000,
        status: 'completed',
      );

      // Attempt to pay 500,000 on remaining 400,000 debt
      expect(
        () => useCase.execute(
          order: order,
          amount: 500000,
          paymentMethod: 'cash',
          currentUser: currentUser,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('Edge case: Order without customerId or walk-in customer updates order debt without customer error', () async {
      final orderWalkIn = Order(
        id: 'HD_WALKIN_DEBT',
        customerId: 'khach_le',
        createdAt: testDate,
        items: const [],
        total: 500000,
        amountPaid: 200000,
        debtAmount: 300000,
        status: 'completed',
      );
      await orderRepo.create(orderWalkIn);

      final updated = await useCase.execute(
        order: orderWalkIn,
        amount: 300000,
        paymentMethod: 'cash',
        currentUser: currentUser,
      );

      expect(updated.amountPaid, 500000);
      expect(updated.debtAmount, 0.0);
      expect(updated.hasDebt, false);

      // No debt transactions recorded for walk-in customer
      final debtCalls = mockDb.recorder.callsFor('set');
      expect(debtCalls.isEmpty, true);
    });

    test('Edge cases: invalid amount <= 0, cancelled order, or non-completed order throw ValidationException', () async {
      final completedOrder = Order(
        id: 'HD_COMP',
        customerId: 'CUST1',
        createdAt: testDate,
        items: const [],
        total: 1000000,
        amountPaid: 500000,
        debtAmount: 500000,
        status: 'completed',
      );

      // Zero amount
      expect(
        () => useCase.execute(
          order: completedOrder,
          amount: 0,
          paymentMethod: 'cash',
          currentUser: currentUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      // Negative amount
      expect(
        () => useCase.execute(
          order: completedOrder,
          amount: -50000,
          paymentMethod: 'cash',
          currentUser: currentUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      // Cancelled order
      final cancelledOrder = completedOrder.copyWith(status: 'cancelled');
      expect(
        () => useCase.execute(
          order: cancelledOrder,
          amount: 100000,
          paymentMethod: 'cash',
          currentUser: currentUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      // Draft order
      final draftOrder = completedOrder.copyWith(status: 'draft');
      expect(
        () => useCase.execute(
          order: draftOrder,
          amount: 100000,
          paymentMethod: 'cash',
          currentUser: currentUser,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
