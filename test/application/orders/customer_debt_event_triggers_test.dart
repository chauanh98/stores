import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/orders/usecases/collect_invoice_debt_usecase.dart';
import 'package:stores/core/errors/exceptions.dart';
import 'package:stores/data/datasources/firebase/customer_remote_data_source.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';

class _FakeNotificationRepository implements NotificationRepository {
  final List<NotificationItem> added = [];
  bool shouldThrow = false;

  @override
  Future<void> addNotification(NotificationItem notification) async {
    if (shouldThrow) {
      throw Exception('Simulated database error');
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

  @override
  Future<void> create(Order order) async => orders[order.id] = order;

  @override
  Future<void> update(Order order) async => orders[order.id] = order;

  @override
  Future<void> delete(String orderId) async => orders.remove(orderId);

  @override
  Future<Order?> fetchById(String id) async => orders[id];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomerRepository implements CustomerRepository {
  final Map<String, Customer> customers = {};

  @override
  Future<Customer?> fetchById(String id) async => customers[id];

  @override
  Future<void> upsert(Customer customer) async =>
      customers[customer.id] = customer;

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

void main() {
  late _FakeOrderRepository fakeOrderRepo;
  late _FakeCustomerRepository fakeCustomerRepo;
  late _FakeNotificationRepository fakeNotifRepo;
  late NotificationDispatcher dispatcher;
  late _FakeCustomerRemoteDataSource fakeCustomerDataSource;
  late CollectInvoiceDebtUseCase useCase;

  const testUser = UserAccount(
    username: 'admin01',
    displayName: 'Quản lý kho',
    role: 'admin',
    storeId: 'store_001',
  );

  const testCustomer = Customer(
    id: 'KH_DEBT_01',
    name: 'Nguyễn Văn Nợ',
    phone: '0912345678',
    email: '',
    address: '',
    purchases: [],
    currentDebt: 5000000.0,
  );

  final testDate = DateTime(2026, 10, 4, 10, 0);

  setUp(() {
    fakeOrderRepo = _FakeOrderRepository();
    fakeCustomerRepo = _FakeCustomerRepository();
    fakeNotifRepo = _FakeNotificationRepository();
    dispatcher = NotificationDispatcher(fakeNotifRepo);
    fakeCustomerDataSource = _FakeCustomerRemoteDataSource();

    useCase = CollectInvoiceDebtUseCase(
      orderRepository: fakeOrderRepo,
      customerRepository: fakeCustomerRepo,
      customerDataSource: fakeCustomerDataSource,
      notificationDispatcher: dispatcher,
    );
  });

  group('CollectInvoiceDebtUseCase — Debt Collected Trigger Tests', () {
    test('1. Full collection triggers notifyCustomerDebtCollected with remainingDebt 0',
        () async {
      await fakeCustomerRepo.upsert(testCustomer);

      final order = Order(
        id: 'HD_TEST_DEBT_1',
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P1',
            productName: 'Máy cắt sắt',
            quantity: 1,
            price: 2000000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 2000000,
        amountPaid: 0,
        debtAmount: 2000000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      await useCase.execute(
        order: order,
        amount: 2000000,
        paymentMethod: 'cash',
        currentUser: testUser,
      );

      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.customerDebtPaid));
      expect(notif.category, equals(NotificationCategory.customers));
      expect(notif.targetRoute, equals('customer_debt'));
      expect(notif.targetId, equals(testCustomer.id));
      expect(notif.title, equals('Thu nợ khách hàng'));
      expect(notif.body, contains('2.000.000đ'));
      expect(notif.body, contains('Nguyễn Văn Nợ'));
      expect(notif.metadata?['customerId'], equals(testCustomer.id));
      expect(notif.metadata?['collectedAmount'], equals(2000000.0));
      expect(notif.metadata?['remainingDebt'], equals(3000000.0));
    });

    test('2. Partial collection triggers notifyCustomerDebtCollected with updated balance',
        () async {
      await fakeCustomerRepo.upsert(testCustomer);

      final order = Order(
        id: 'HD_TEST_DEBT_2',
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        createdAt: testDate,
        items: const [],
        total: 1000000,
        amountPaid: 0,
        debtAmount: 1000000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      await useCase.execute(
        order: order,
        amount: 400000,
        paymentMethod: 'transfer',
        currentUser: testUser,
        note: 'Thu trước một phần',
      );

      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.customerDebtPaid));
      expect(notif.body, contains('400.000đ'));
      expect(notif.metadata?['collectedAmount'], equals(400000.0));
      expect(notif.metadata?['remainingDebt'], equals(4600000.0));
    });

    test('3. Null notificationDispatcher does not throw and executes normally',
        () async {
      final safeUseCase = CollectInvoiceDebtUseCase(
        orderRepository: fakeOrderRepo,
        customerRepository: fakeCustomerRepo,
        customerDataSource: fakeCustomerDataSource,
        notificationDispatcher: null,
      );

      await fakeCustomerRepo.upsert(testCustomer);
      final order = Order(
        id: 'HD_TEST_DEBT_3',
        customerId: testCustomer.id,
        createdAt: testDate,
        items: const [],
        total: 500000,
        amountPaid: 0,
        debtAmount: 500000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      final result = await safeUseCase.execute(
        order: order,
        amount: 500000,
        paymentMethod: 'cash',
        currentUser: testUser,
      );

      expect(result.amountPaid, equals(500000));
      expect(fakeNotifRepo.added, isEmpty);
    });

    test('4. Notification dispatch failure does not disrupt debt collection',
        () async {
      fakeNotifRepo.shouldThrow = true;

      await fakeCustomerRepo.upsert(testCustomer);
      final order = Order(
        id: 'HD_TEST_DEBT_ERR',
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        createdAt: testDate,
        items: const [],
        total: 500000,
        amountPaid: 0,
        debtAmount: 500000,
        status: 'completed',
        storeId: 'store_001',
      );
      await fakeOrderRepo.create(order);

      final result = await useCase.execute(
        order: order,
        amount: 500000,
        paymentMethod: 'cash',
        currentUser: testUser,
      );

      expect(result.amountPaid, equals(500000));
      expect(result.debtAmount, equals(0));
      expect(fakeCustomerDataSource.recordedTransactions.length, equals(1));
    });

    test('5. Zero or negative amount throws and dispatches nothing', () async {
      final order = Order(
        id: 'HD_TEST_DEBT_4',
        customerId: testCustomer.id,
        createdAt: testDate,
        items: const [],
        total: 500000,
        amountPaid: 0,
        debtAmount: 500000,
        status: 'completed',
      );

      expect(
        () => useCase.execute(
          order: order,
          amount: 0,
          paymentMethod: 'cash',
          currentUser: testUser,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(fakeNotifRepo.added, isEmpty);
    });

    test('6. Cancelled order throws and dispatches nothing', () async {
      final order = Order(
        id: 'HD_TEST_DEBT_CANCELLED',
        customerId: testCustomer.id,
        createdAt: testDate,
        items: const [],
        total: 500000,
        amountPaid: 0,
        debtAmount: 500000,
        status: 'cancelled',
      );

      expect(
        () => useCase.execute(
          order: order,
          amount: 200000,
          paymentMethod: 'cash',
          currentUser: testUser,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(fakeNotifRepo.added, isEmpty);
    });
  });

  group('Customer Debt Incurred — notifyCustomerDebtAdded', () {
    test('1. notifyCustomerDebtAdded dispatches customerDebtAdded notification with metadata',
        () async {
      await dispatcher.notifyCustomerDebtAdded(
        storeId: 'store_001',
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        debtAmount: 1500000.0,
        orderId: 'HD09999',
        user: testUser,
      );

      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.customerDebtAdded));
      expect(notif.category, equals(NotificationCategory.customers));
      expect(notif.targetRoute, equals('customer_debt'));
      expect(notif.targetId, equals(testCustomer.id));
      expect(notif.title, equals('Ghi nhận nợ mới'));
      expect(notif.body, contains('1.500.000đ'));
      expect(notif.body, contains('Nguyễn Văn Nợ'));
      expect(notif.metadata?['customerId'], equals(testCustomer.id));
      expect(notif.metadata?['debtAmount'], equals(1500000.0));
      expect(notif.metadata?['orderId'], equals('HD09999'));
      expect(notif.metadata?['createdBy'], equals('Quản lý kho'));
    });

    test('2. Zero or negative debtAmount is ignored and does not create notification',
        () async {
      await dispatcher.notifyCustomerDebtAdded(
        storeId: 'store_001',
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        debtAmount: 0.0,
        orderId: 'HD00000',
        user: testUser,
      );

      expect(fakeNotifRepo.added, isEmpty);
    });
  });

  group('CollectInvoiceDebtUseCaseProvider — Riverpod Wiring', () {
    test('Resolves autoDispose provider with notificationDispatcherProvider wired',
        () {
      final container = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(fakeNotifRepo),
          orderRepositoryProvider.overrideWithValue(fakeOrderRepo),
          customerRepositoryProvider.overrideWithValue(fakeCustomerRepo),
          customerRemoteDataSourceProvider
              .overrideWithValue(_FakeCustomerRemoteDataSource()),
        ],
      );
      addTearDown(container.dispose);

      final resolvedUseCase = container.read(collectInvoiceDebtUseCaseProvider);
      expect(resolvedUseCase, isA<CollectInvoiceDebtUseCase>());
      expect(resolvedUseCase.notificationDispatcher, isNotNull);
    });
  });
}
