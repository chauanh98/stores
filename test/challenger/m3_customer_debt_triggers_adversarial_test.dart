import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
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
import 'package:stores/presentation/orders/widgets/debt_collection_dialog.dart';

// ============================================================================
// TEST HARNESS: FAKES & MOCKS
// ============================================================================

class _FakeNotificationRepository implements NotificationRepository {
  final List<NotificationItem> added = [];
  bool shouldThrow = false;
  Object? customError;

  @override
  Future<void> addNotification(NotificationItem notification) async {
    if (shouldThrow) {
      throw customError ?? Exception('Simulated NotificationRepository database failure');
    }
    added.add(notification);
  }

  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {}

  @override
  Future<void> markAllAsRead(String storeId) async {}

  @override
  Future<void> markAsRead(
      {required String storeId, required String id}) async {}

  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
      {int limit = 50}) {
    return Stream.value(added);
  }
}

class _FakeOrderRepository implements OrderRepository {
  final Map<String, Order> orders = {};
  int updateCallCount = 0;

  @override
  Future<void> create(Order order) async => orders[order.id] = order;

  @override
  Future<void> update(Order order) async {
    updateCallCount++;
    orders[order.id] = order;
  }

  @override
  Future<void> delete(String orderId) async => orders.remove(orderId);

  @override
  Future<Order?> fetchById(String id) async => orders[id];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomerRepository implements CustomerRepository {
  final Map<String, Customer> customers = {};
  int upsertCallCount = 0;

  @override
  Future<Customer?> fetchById(String id) async => customers[id];

  @override
  Future<void> upsert(Customer customer) async {
    upsertCallCount++;
    customers[customer.id] = customer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomerRemoteDataSource implements CustomerRemoteDataSource {
  final List<Map<String, dynamic>> recordedTransactions = [];

  @override
  Future<void> saveDebtTransaction(
      String customerId, Map<String, dynamic> transaction) async {
    recordedTransactions.add(transaction);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A dispatcher subclass with controllable fault injection that throws during calls.
class _FaultInjectingDispatcher extends NotificationDispatcher {
  bool throwOnDebtCollected = false;
  bool throwOnDebtAdded = false;
  Object? injectedError;
  int collectedCallCount = 0;
  int addedCallCount = 0;

  _FaultInjectingDispatcher(super.repository);

  @override
  Future<void> notifyCustomerDebtCollected({
    required String storeId,
    required String customerId,
    required String customerName,
    required double collectedAmount,
    required UserAccount? user,
    double? remainingDebt,
  }) async {
    collectedCallCount++;
    if (throwOnDebtCollected) {
      throw injectedError ?? Exception('Fault injection: Dispatcher crashed on debt collection');
    }
    return super.notifyCustomerDebtCollected(
      storeId: storeId,
      customerId: customerId,
      customerName: customerName,
      collectedAmount: collectedAmount,
      user: user,
      remainingDebt: remainingDebt,
    );
  }

  @override
  Future<void> notifyCustomerDebtAdded({
    required String storeId,
    required String customerId,
    required String customerName,
    required double debtAmount,
    required String orderId,
    required UserAccount? user,
  }) async {
    addedCallCount++;
    if (throwOnDebtAdded) {
      throw injectedError ?? StateError('Fault injection: Fatal error on debt added');
    }
    return super.notifyCustomerDebtAdded(
      storeId: storeId,
      customerId: customerId,
      customerName: customerName,
      debtAmount: debtAmount,
      orderId: orderId,
      user: user,
    );
  }
}

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

// ============================================================================
// MAIN TEST SUITE
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = UserAccount(
    username: 'admin_adversary',
    displayName: 'Quản trị viên Đối soát',
    role: 'admin',
    storeId: 'store_001',
  );

  const regularCustomer = Customer(
    id: 'CUST_REGULAR_99',
    name: 'Phạm Minh Chính',
    phone: '0909999999',
    email: '',
    address: 'Cần Thơ',
    purchases: [],
    currentDebt: 3000000.0,
  );

  final testDate = DateTime(2026, 10, 4, 14, 0);

  late _FakeOrderRepository fakeOrderRepo;
  late _FakeCustomerRepository fakeCustomerRepo;
  late _FakeNotificationRepository fakeNotifRepo;
  late _FakeCustomerRemoteDataSource fakeCustomerDataSource;
  late _FaultInjectingDispatcher faultDispatcher;
  late CollectInvoiceDebtUseCase useCase;

  setUp(() {
    fakeOrderRepo = _FakeOrderRepository();
    fakeCustomerRepo = _FakeCustomerRepository();
    fakeNotifRepo = _FakeNotificationRepository();
    fakeCustomerDataSource = _FakeCustomerRemoteDataSource();
    faultDispatcher = _FaultInjectingDispatcher(fakeNotifRepo);

    useCase = CollectInvoiceDebtUseCase(
      orderRepository: fakeOrderRepo,
      customerRepository: fakeCustomerRepo,
      customerDataSource: fakeCustomerDataSource,
      notificationDispatcher: faultDispatcher,
    );
  });

  // ==========================================================================
  // GROUP 1: WALK-IN CUSTOMER (khach_le, walk_in, empty customerId)
  // ==========================================================================
  group('Adversarial Group 1: Walk-In Customer Debt Triggers', () {
    test('1.1: Walk-in customer ("khach_le") debt collection skips customer repo and emits NO customer notification',
        () async {
      final walkInOrder = Order(
        id: 'HD_WALKIN_01',
        customerId: 'khach_le',
        customerName: 'Khách lẻ',
        createdAt: testDate,
        items: const [],
        total: 1000000,
        amountPaid: 400000,
        debtAmount: 600000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(walkInOrder);

      final result = await useCase.execute(
        order: walkInOrder,
        amount: 600000,
        paymentMethod: 'cash',
        currentUser: testUser,
      );

      // Order should be paid off
      expect(result.amountPaid, equals(1000000));
      expect(result.debtAmount, equals(0.0));
      expect(result.remainingDebt, equals(0.0));

      // Customer repository must NOT be touched for walk-in customer
      expect(fakeCustomerRepo.upsertCallCount, equals(0));
      expect(fakeCustomerDataSource.recordedTransactions, isEmpty);

      // Notification repository must NOT receive any customer debt notification
      expect(fakeNotifRepo.added, isEmpty);
      expect(faultDispatcher.collectedCallCount, equals(0));
    });

    test('1.2: Walk-in customer with "walk_in" identifier skips customer debt and emits NO customer notification',
        () async {
      final walkInOrder = Order(
        id: 'HD_WALKIN_02',
        customerId: 'walk_in',
        customerName: 'Walk-in Customer',
        createdAt: testDate,
        items: const [],
        total: 500000,
        amountPaid: 200000,
        debtAmount: 300000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(walkInOrder);

      final result = await useCase.execute(
        order: walkInOrder,
        amount: 300000,
        paymentMethod: 'transfer',
        currentUser: testUser,
      );

      expect(result.remainingDebt, equals(0.0));
      expect(fakeCustomerRepo.upsertCallCount, equals(0));
      expect(fakeNotifRepo.added, isEmpty);
      expect(faultDispatcher.collectedCallCount, equals(0));
    });

    test('1.3: Empty customerId ("") order debt collection skips customer debt and emits NO customer notification',
        () async {
      final emptyCustOrder = Order(
        id: 'HD_WALKIN_EMPTY',
        customerId: '',
        customerName: null,
        createdAt: testDate,
        items: const [],
        total: 800000,
        amountPaid: 300000,
        debtAmount: 500000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(emptyCustOrder);

      final result = await useCase.execute(
        order: emptyCustOrder,
        amount: 500000,
        paymentMethod: 'cash',
        currentUser: testUser,
      );

      expect(result.remainingDebt, equals(0.0));
      expect(fakeCustomerRepo.upsertCallCount, equals(0));
      expect(fakeNotifRepo.added, isEmpty);
      expect(faultDispatcher.collectedCallCount, equals(0));
    });

    test('1.4: Direct notifyCustomerDebtAdded with zero or negative debt for walk-in customer is completely suppressed',
        () async {
      // Calling dispatcher with walk-in customer and 0 debt
      await faultDispatcher.notifyCustomerDebtAdded(
        storeId: 'store_001',
        customerId: 'khach_le',
        customerName: 'Khách lẻ',
        debtAmount: 0.0,
        orderId: 'HD_ZERO',
        user: testUser,
      );

      await faultDispatcher.notifyCustomerDebtAdded(
        storeId: 'store_001',
        customerId: '',
        customerName: '',
        debtAmount: -50000.0,
        orderId: 'HD_NEG',
        user: testUser,
      );

      expect(fakeNotifRepo.added, isEmpty);
    });

    test('1.5: Direct notifyCustomerDebtCollected with zero amount for walk-in customer is completely suppressed',
        () async {
      await faultDispatcher.notifyCustomerDebtCollected(
        storeId: 'store_001',
        customerId: 'khach_le',
        customerName: 'Khách lẻ',
        collectedAmount: 0.0,
        user: testUser,
        remainingDebt: 0.0,
      );

      await faultDispatcher.notifyCustomerDebtCollected(
        storeId: 'store_001',
        customerId: '',
        customerName: '',
        collectedAmount: -1000.0,
        user: testUser,
      );

      expect(fakeNotifRepo.added, isEmpty);
    });
  });

  // ==========================================================================
  // GROUP 2: FULLY PAID ORDERS (debtAmount == 0)
  // ==========================================================================
  group('Adversarial Group 2: Fully Paid Order Debt Incurred Suppression', () {
    test('2.1: Fully paid order (debtAmount = 0) emits NO customer debt added notification',
        () async {
      // Even when customer has an existing debt of 3,000,000đ, a fully paid order MUST NOT trigger debt added
      await fakeCustomerRepo.upsert(regularCustomer);

      await faultDispatcher.notifyCustomerDebtAdded(
        storeId: 'store_001',
        customerId: regularCustomer.id,
        customerName: regularCustomer.name,
        debtAmount: 0.0, // Fully paid: 0 debt incurred
        orderId: 'HD_PAID_FULL_01',
        user: testUser,
      );

      expect(fakeNotifRepo.added, isEmpty);
    });

    test('2.2: Negative debt (overpayment change returned) emits NO customer debt added notification',
        () async {
      await faultDispatcher.notifyCustomerDebtAdded(
        storeId: 'store_001',
        customerId: regularCustomer.id,
        customerName: regularCustomer.name,
        debtAmount: -20000.0, // Overpayment
        orderId: 'HD_OVERPAID_01',
        user: testUser,
      );

      expect(fakeNotifRepo.added, isEmpty);
    });

    test('2.3: Order with total = 5,000,000 and amountPaid = 5,000,000 has remainingDebt = 0 and cannot be collected',
        () async {
      final fullyPaidOrder = Order(
        id: 'HD_FULL_PAID_02',
        customerId: regularCustomer.id,
        customerName: regularCustomer.name,
        createdAt: testDate,
        items: const [],
        total: 5000000,
        amountPaid: 5000000,
        debtAmount: 0,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(fullyPaidOrder);
      await fakeCustomerRepo.upsert(regularCustomer);

      // Attempting to collect debt on a fully paid order (remainingDebt = 0)
      expect(
        () => useCase.execute(
          order: fullyPaidOrder,
          amount: 100000,
          paymentMethod: 'cash',
          currentUser: testUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      expect(fakeNotifRepo.added, isEmpty);
    });
  });

  // ==========================================================================
  // GROUP 3: DEBT COLLECTION LIFECYCLE (Full Payoff, Partial, Zero, Rejections)
  // ==========================================================================
  group('Adversarial Group 3: Debt Collection Full/Partial Payoff & Validation', () {
    test('3.1: Full payoff clears order debt, updates customer balance, and emits debt collected notification',
        () async {
      await fakeCustomerRepo.upsert(regularCustomer); // debt: 3,000,000đ

      final order = Order(
        id: 'HD_PAYOFF_FULL',
        customerId: regularCustomer.id,
        customerName: regularCustomer.name,
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'PROD_01',
            productName: 'Máy khoan Bosch',
            quantity: 1,
            price: 1500000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 1500000,
        amountPaid: 0,
        debtAmount: 1500000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      final updated = await useCase.execute(
        order: order,
        amount: 1500000, // Full payoff
        paymentMethod: 'cash',
        currentUser: testUser,
      );

      // 1. Order financial verification
      expect(updated.amountPaid, equals(1500000));
      expect(updated.debtAmount, equals(0.0));
      expect(updated.remainingDebt, equals(0.0));

      // 2. Customer debt verification
      final updatedCustomer = await fakeCustomerRepo.fetchById(regularCustomer.id);
      expect(updatedCustomer, isNotNull);
      expect(updatedCustomer!.currentDebt, equals(1500000.0)); // 3.0M - 1.5M = 1.5M

      // 3. Debt transaction verification
      expect(fakeCustomerDataSource.recordedTransactions.length, equals(1));
      final tx = fakeCustomerDataSource.recordedTransactions.first;
      expect(tx['amount'], equals(-1500000.0));
      expect(tx['remainingDebt'], equals(1500000.0));
      expect(tx['type'], equals(DebtTransactionType.payment.name));

      // 4. Notification verification
      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.customerDebtPaid));
      expect(notif.category, equals(NotificationCategory.customers));
      expect(notif.targetRoute, equals('customer_debt'));
      expect(notif.targetId, equals(regularCustomer.id));
      expect(notif.title, equals('Thu nợ khách hàng'));
      expect(notif.body, contains('1.500.000đ'));
      expect(notif.body, contains(regularCustomer.name));
      expect(notif.metadata?['collectedAmount'], equals(1500000.0));
      expect(notif.metadata?['remainingDebt'], equals(1500000.0));
    });

    test('3.2: Partial payoff updates order remaining debt and emits notification with updated balance',
        () async {
      await fakeCustomerRepo.upsert(regularCustomer); // debt: 3,000,000đ

      final order = Order(
        id: 'HD_PAYOFF_PARTIAL',
        customerId: regularCustomer.id,
        customerName: regularCustomer.name,
        createdAt: testDate,
        items: const [],
        total: 2000000,
        amountPaid: 0,
        debtAmount: 2000000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      final updated = await useCase.execute(
        order: order,
        amount: 800000, // Partial payoff
        paymentMethod: 'transfer',
        currentUser: testUser,
        note: 'Trả đợt 1',
      );

      // Order verification
      expect(updated.amountPaid, equals(800000));
      expect(updated.debtAmount, equals(1200000.0));
      expect(updated.remainingDebt, equals(1200000.0));

      // Customer verification (3M - 800k = 2.2M)
      final updatedCust = await fakeCustomerRepo.fetchById(regularCustomer.id);
      expect(updatedCust!.currentDebt, equals(2200000.0));

      // Notification verification
      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.metadata?['collectedAmount'], equals(800000.0));
      expect(notif.metadata?['remainingDebt'], equals(2200000.0));
      expect(notif.body, contains('800.000đ'));
      expect(notif.body, contains(regularCustomer.name));
    });

    test('3.3: Multiple sequential partial payoffs on same invoice converge cleanly to zero debt',
        () async {
      await fakeCustomerRepo.upsert(regularCustomer.copyWith(currentDebt: 1000000));

      var currentOrder = Order(
        id: 'HD_PAYOFF_MULTI',
        customerId: regularCustomer.id,
        customerName: regularCustomer.name,
        createdAt: testDate,
        items: const [],
        total: 1000000,
        amountPaid: 0,
        debtAmount: 1000000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(currentOrder);

      // Payment 1: 300,000đ
      currentOrder = await useCase.execute(
        order: currentOrder,
        amount: 300000,
        paymentMethod: 'cash',
        currentUser: testUser,
      );
      expect(currentOrder.remainingDebt, equals(700000.0));
      expect(fakeNotifRepo.added.length, equals(1));

      // Payment 2: 400,000đ
      currentOrder = await useCase.execute(
        order: currentOrder,
        amount: 400000,
        paymentMethod: 'transfer',
        currentUser: testUser,
      );
      expect(currentOrder.remainingDebt, equals(300000.0));
      expect(fakeNotifRepo.added.length, equals(2));

      // Payment 3: 300,000đ (Final)
      currentOrder = await useCase.execute(
        order: currentOrder,
        amount: 300000,
        paymentMethod: 'cash',
        currentUser: testUser,
      );
      expect(currentOrder.remainingDebt, equals(0.0));
      expect(currentOrder.debtAmount, equals(0.0));
      expect(fakeNotifRepo.added.length, equals(3));

      // Final customer balance: 0.0
      final finalCustomer = await fakeCustomerRepo.fetchById(regularCustomer.id);
      expect(finalCustomer!.currentDebt, equals(0.0));
    });

    test('3.4: Zero amount debt collection attempt MUST be rejected with ValidationException',
        () async {
      final order = Order(
        id: 'HD_TEST_ZERO_REJECT',
        customerId: regularCustomer.id,
        createdAt: testDate,
        items: const [],
        total: 500000,
        amountPaid: 0,
        debtAmount: 500000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      // Attempting 0 amount collection
      expect(
        () => useCase.execute(
          order: order,
          amount: 0.0,
          paymentMethod: 'cash',
          currentUser: testUser,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('Số tiền thu nợ phải lớn hơn 0'),
          ),
        ),
      );

      // State remains strictly untouched
      expect(fakeOrderRepo.updateCallCount, equals(0));
      expect(fakeCustomerRepo.upsertCallCount, equals(0));
      expect(fakeNotifRepo.added, isEmpty);
      expect(faultDispatcher.collectedCallCount, equals(0));
    });

    test('3.5: Negative amount debt collection attempt MUST be rejected with ValidationException',
        () async {
      final order = Order(
        id: 'HD_TEST_NEG_REJECT',
        customerId: regularCustomer.id,
        createdAt: testDate,
        items: const [],
        total: 500000,
        amountPaid: 0,
        debtAmount: 500000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      expect(
        () => useCase.execute(
          order: order,
          amount: -150000.0,
          paymentMethod: 'cash',
          currentUser: testUser,
        ),
        throwsA(isA<ValidationException>()),
      );

      expect(fakeOrderRepo.updateCallCount, equals(0));
      expect(fakeNotifRepo.added, isEmpty);
    });

    test('3.6: Amount exceeding invoice remaining debt MUST be rejected with ValidationException',
        () async {
      final order = Order(
        id: 'HD_TEST_OVERFLOW',
        customerId: regularCustomer.id,
        createdAt: testDate,
        items: const [],
        total: 1000000,
        amountPaid: 600000,
        debtAmount: 400000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      // Remaining debt is 400,000đ; attempting to collect 500,000đ
      expect(
        () => useCase.execute(
          order: order,
          amount: 500000.0,
          paymentMethod: 'cash',
          currentUser: testUser,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('vượt quá công nợ còn lại'),
          ),
        ),
      );

      expect(fakeOrderRepo.updateCallCount, equals(0));
      expect(fakeNotifRepo.added, isEmpty);
    });

    test('3.7: Debt collection on cancelled order MUST be rejected with ValidationException',
        () async {
      final order = Order(
        id: 'HD_CANCELLED',
        customerId: regularCustomer.id,
        createdAt: testDate,
        items: const [],
        total: 1000000,
        amountPaid: 0,
        debtAmount: 1000000,
        status: 'cancelled',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      expect(
        () => useCase.execute(
          order: order,
          amount: 500000,
          paymentMethod: 'cash',
          currentUser: testUser,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('Không thể thu nợ cho hóa đơn đã hủy'),
          ),
        ),
      );

      expect(fakeOrderRepo.updateCallCount, equals(0));
      expect(fakeNotifRepo.added, isEmpty);
    });

    test('3.8: Debt collection on draft order MUST be rejected with ValidationException',
        () async {
      final order = Order(
        id: 'HD_DRAFT',
        customerId: regularCustomer.id,
        createdAt: testDate,
        items: const [],
        total: 1000000,
        amountPaid: 0,
        debtAmount: 1000000,
        status: 'draft',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      expect(
        () => useCase.execute(
          order: order,
          amount: 500000,
          paymentMethod: 'cash',
          currentUser: testUser,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('Chỉ có thể thu nợ cho hóa đơn đã hoàn thành'),
          ),
        ),
      );

      expect(fakeOrderRepo.updateCallCount, equals(0));
      expect(fakeNotifRepo.added, isEmpty);
    });
  });

  // ==========================================================================
  // GROUP 4: FAULT INJECTION ON DEBT COLLECTION (Dispatcher & Repo Failures)
  // ==========================================================================
  group('Adversarial Group 4: Fault Injection & Error Isolation', () {
    test('4.1: Dispatcher throwing network Exception does NOT abort debt collection or order update',
        () async {
      await fakeCustomerRepo.upsert(regularCustomer);

      final order = Order(
        id: 'HD_FAULT_INJECT_01',
        customerId: regularCustomer.id,
        customerName: regularCustomer.name,
        createdAt: testDate,
        items: const [],
        total: 1000000,
        amountPaid: 0,
        debtAmount: 1000000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      // Fault injection: Dispatcher throws a simulated network crash
      faultDispatcher.throwOnDebtCollected = true;
      faultDispatcher.injectedError = const SocketException('Connection reset by peer');

      final result = await useCase.execute(
        order: order,
        amount: 600000,
        paymentMethod: 'cash',
        currentUser: testUser,
      );

      // ASSERT CRITICAL INVARIATION: Financial write must succeed despite notification failure!
      expect(result.amountPaid, equals(600000));
      expect(result.debtAmount, equals(400000));
      expect(fakeOrderRepo.updateCallCount, equals(1));

      // Customer repository must be updated
      final updatedCustomer = await fakeCustomerRepo.fetchById(regularCustomer.id);
      expect(updatedCustomer!.currentDebt, equals(2400000.0)); // 3.0M - 600k = 2.4M

      // Customer remote transaction must be recorded
      expect(fakeCustomerDataSource.recordedTransactions.length, equals(1));
    });

    test('4.2: Dispatcher throwing TimeoutException does NOT disrupt debt collection',
        () async {
      await fakeCustomerRepo.upsert(regularCustomer);

      final order = Order(
        id: 'HD_FAULT_TIMEOUT',
        customerId: regularCustomer.id,
        customerName: regularCustomer.name,
        createdAt: testDate,
        items: const [],
        total: 700000,
        amountPaid: 0,
        debtAmount: 700000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      faultDispatcher.throwOnDebtCollected = true;
      faultDispatcher.injectedError = TimeoutException('Firebase Realtime Database timeout (10000ms)');

      final result = await useCase.execute(
        order: order,
        amount: 700000,
        paymentMethod: 'transfer',
        currentUser: testUser,
      );

      expect(result.remainingDebt, equals(0.0));
      expect(fakeOrderRepo.updateCallCount, equals(1));
      expect(fakeCustomerDataSource.recordedTransactions.length, equals(1));
    });

    test('4.3: Underlying NotificationRepository failure is caught internally by NotificationDispatcher',
        () async {
      // Simulate underlying repository crashing on addNotification
      fakeNotifRepo.shouldThrow = true;
      fakeNotifRepo.customError = Exception('Firebase database quota exceeded');

      await fakeCustomerRepo.upsert(regularCustomer);

      final order = Order(
        id: 'HD_REPO_CRASH',
        customerId: regularCustomer.id,
        customerName: regularCustomer.name,
        createdAt: testDate,
        items: const [],
        total: 900000,
        amountPaid: 0,
        debtAmount: 900000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      final result = await useCase.execute(
        order: order,
        amount: 450000,
        paymentMethod: 'cash',
        currentUser: testUser,
      );

      expect(result.amountPaid, equals(450000));
      expect(result.debtAmount, equals(450000));
      expect(fakeOrderRepo.updateCallCount, equals(1));
    });

    test('4.4: Null NotificationDispatcher executes cleanly with zero notifications',
        () async {
      final safeUseCase = CollectInvoiceDebtUseCase(
        orderRepository: fakeOrderRepo,
        customerRepository: fakeCustomerRepo,
        customerDataSource: fakeCustomerDataSource,
        notificationDispatcher: null, // No dispatcher
      );

      await fakeCustomerRepo.upsert(regularCustomer);

      final order = Order(
        id: 'HD_NULL_DISPATCHER',
        customerId: regularCustomer.id,
        customerName: regularCustomer.name,
        createdAt: testDate,
        items: const [],
        total: 1200000,
        amountPaid: 0,
        debtAmount: 1200000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      final result = await safeUseCase.execute(
        order: order,
        amount: 1200000,
        paymentMethod: 'cash',
        currentUser: testUser,
      );

      expect(result.remainingDebt, equals(0.0));
      expect(fakeOrderRepo.updateCallCount, equals(1));
      expect(fakeCustomerDataSource.recordedTransactions.length, equals(1));
      expect(fakeNotifRepo.added, isEmpty);
    });
  });

  // ==========================================================================
  // GROUP 5: WIDGET & DIALOG REJECTION VERIFICATION
  // ==========================================================================
  group('Adversarial Group 5: DebtCollectionDialog UI Suppression & Zero Rejection', () {
    testWidgets('5.1: DebtCollectionDialog rejects 0 amount input and blocks execution',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final order = Order(
        id: 'HD_DIALOG_ZERO',
        customerId: regularCustomer.id,
        createdAt: testDate,
        items: const [],
        total: 1000000,
        amountPaid: 200000,
        debtAmount: 800000,
        status: 'completed',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: DebtCollectionDialog(
            order: order,
            customer: regularCustomer,
            remainingDebt: order.remainingDebt,
          ),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            collectInvoiceDebtUseCaseProvider.overrideWithValue(useCase),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Enter 0 in the amount field
      final amountField = find.byKey(const Key('debt_collection_amount_field'));
      expect(amountField, findsOneWidget);

      await tester.enterText(amountField, '0');
      await tester.pumpAndSettle();

      // Tap submit button
      final submitBtn = find.byKey(const Key('confirm_debt_collection_button'));
      expect(submitBtn, findsOneWidget);
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Verify that useCase was NEVER invoked
      expect(fakeOrderRepo.updateCallCount, equals(0));
      expect(fakeNotifRepo.added, isEmpty);

      // Verify validator error message is shown
      expect(find.text('Số tiền phải lớn hơn 0'), findsOneWidget);
    });

    testWidgets('5.2: DebtCollectionDialog rejects amount exceeding remaining debt',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final order = Order(
        id: 'HD_DIALOG_EXCEED',
        customerId: regularCustomer.id,
        createdAt: testDate,
        items: const [],
        total: 1000000,
        amountPaid: 600000,
        debtAmount: 400000,
        status: 'completed',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: DebtCollectionDialog(
            order: order,
            customer: regularCustomer,
            remainingDebt: order.remainingDebt,
          ),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            collectInvoiceDebtUseCaseProvider.overrideWithValue(useCase),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final amountField = find.byKey(const Key('debt_collection_amount_field'));
      await tester.enterText(amountField, '900000'); // Exceeds 400,000đ
      await tester.pumpAndSettle();

      final submitBtn = find.byKey(const Key('confirm_debt_collection_button'));
      expect(submitBtn, findsOneWidget);
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Verify useCase was NOT invoked
      expect(fakeOrderRepo.updateCallCount, equals(0));
      expect(fakeNotifRepo.added, isEmpty);

      // Verify validator error message is shown
      expect(find.text('Vượt quá số nợ còn lại'), findsOneWidget);
    });
  });
}
