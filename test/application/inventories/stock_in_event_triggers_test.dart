import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

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

class _MockProductRepository implements ProductRepository {
  final Map<String, Product> products = {};

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Future<void> upsert(Product product) async {
    products[product.id] = product;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async {
    transactions.add(tx);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockSupplierRepository implements SupplierRepository {
  final Map<String, Supplier> suppliers = {};
  final List<SupplierDebtTransaction> debtTransactions = [];

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async =>
      suppliers[id];

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    suppliers[supplier.id] = supplier;
  }

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction tx,
      {String? storeId}) async {
    debtTransactions.add(tx);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockStockInReceiptRepository implements StockInReceiptRepository {
  final Map<String, StockInReceipt> receipts = {};

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
  }

  @override
  Future<String> saveDraft(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
    return receipt.id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _MockProductRepository mockProductRepo;
  late _MockInventoryRepository mockInventoryRepo;
  late _MockSupplierRepository mockSupplierRepo;
  late _MockStockInReceiptRepository mockReceiptRepo;
  late _FakeNotificationRepository fakeNotifRepo;
  late NotificationDispatcher dispatcher;
  late CompleteStockInReceiptUseCase useCase;

  const adminUser = UserAccount(
    username: 'admin01',
    displayName: 'Quản lý kho',
    role: 'admin',
    storeId: 'store_001',
  );

  final testDate = DateTime(2026, 10, 4, 10, 0);

  const testProduct = Product(
    id: 'prod_import_1',
    code: 'NK01',
    name: 'Sofa Da Bò Cao Cấp',
    category: 'Nội thất',
    price: 15000000,
    costPrice: 10000000,
    branchStocks: {'store_001': 5},
  );

  const testSupplier = Supplier(
    id: 'sup_01',
    code: 'NCC01',
    name: 'Công ty Nội Thất An Cường',
    phone: '0901234567',
    currentDebt: 0,
    totalPurchase: 0,
  );

  final testReceipt = StockInReceipt(
    id: 'PN_TEST_001',
    importCode: 'PN261004001',
    date: testDate,
    storeId: 'store_001',
    supplierId: 'sup_01',
    supplierName: 'Công ty Nội Thất An Cường',
    createdBy: 'staff_kho',
    createdByName: 'Nhân viên kho',
    items: const [
      StockInReceiptItem(
        transactionId: 'tx_1',
        productId: 'prod_import_1',
        productName: 'Sofa Da Bò Cao Cấp',
        productCode: 'NK01',
        quantity: 2,
        importPrice: 10000000,
      ),
    ],
    discount: 0,
    paidAmount: 20000000,
    status: 'completed',
  );

  setUp(() {
    mockProductRepo = _MockProductRepository();
    mockInventoryRepo = _MockInventoryRepository();
    mockSupplierRepo = _MockSupplierRepository();
    mockReceiptRepo = _MockStockInReceiptRepository();
    fakeNotifRepo = _FakeNotificationRepository();
    dispatcher = NotificationDispatcher(fakeNotifRepo);

    mockProductRepo.products[testProduct.id] = testProduct;
    mockSupplierRepo.suppliers[testSupplier.id] = testSupplier;

    useCase = CompleteStockInReceiptUseCase(
      productRepository: mockProductRepo,
      inventoryRepository: mockInventoryRepo,
      supplierRepository: mockSupplierRepo,
      receiptRepository: mockReceiptRepo,
      notificationDispatcher: dispatcher,
    );
  });

  group('CompleteStockInReceiptUseCase — Stock-In Event Triggers', () {
    test('1. Successful stock-in completion dispatches notifyStockInCompleted with user',
        () async {
      final result = await useCase.execute(
        testReceipt,
        user: adminUser,
      );

      expect(result.status, equals('completed'));
      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.inventoryImported));
      expect(notif.category, equals(NotificationCategory.inventory));
      expect(notif.targetRoute, equals('stock_in_detail'));
      expect(notif.targetId, equals(testReceipt.importCode));
      expect(notif.title, contains(testReceipt.importCode));
      expect(notif.body, contains('Công ty Nội Thất An Cường'));
      expect(notif.body, contains('20.000.000đ'));
      expect(notif.metadata?['importCode'], equals(testReceipt.importCode));
      expect(notif.metadata?['supplierName'], equals('Công ty Nội Thất An Cường'));
      expect(notif.metadata?['totalAmount'], equals(20000000.0));
      expect(notif.metadata?['createdBy'], equals('Quản lý kho'));
    });

    test('2. Stock-in completion falls back to createdBy/createdByName when user is null',
        () async {
      final result = await useCase.execute(
        testReceipt,
        user: null,
      );

      expect(result.status, equals('completed'));
      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.metadata?['createdBy'], equals('Nhân viên kho'));
    });

    test('3. Null notificationDispatcher completes receipt safely without error',
        () async {
      final safeUseCase = CompleteStockInReceiptUseCase(
        productRepository: mockProductRepo,
        inventoryRepository: mockInventoryRepo,
        supplierRepository: mockSupplierRepo,
        receiptRepository: mockReceiptRepo,
        notificationDispatcher: null,
      );

      final result = await safeUseCase.execute(testReceipt);

      expect(result.status, equals('completed'));
      expect(mockReceiptRepo.receipts[testReceipt.id], isNotNull);
      expect(fakeNotifRepo.added, isEmpty);
    });

    test('4. Notification failure does not disrupt receipt completion', () async {
      fakeNotifRepo.shouldThrow = true;

      final result = await useCase.execute(
        testReceipt,
        user: adminUser,
      );

      expect(result.status, equals('completed'));
      expect(mockReceiptRepo.receipts[testReceipt.id], isNotNull);
      expect(mockProductRepo.products[testProduct.id]?.branchStocks['store_001'],
          equals(7)); // 5 + 2 = 7
    });

    test('5. notifyStockInCompleted ignores draft or cancelled receipts', () async {
      final draftReceipt = testReceipt.copyWith(status: 'draft');
      await dispatcher.notifyStockInCompleted(
        storeId: 'store_001',
        receipt: draftReceipt,
        user: adminUser,
      );

      final cancelReceipt = testReceipt.copyWith(status: 'cancelled');
      await dispatcher.notifyStockInCompleted(
        storeId: 'store_001',
        receipt: cancelReceipt,
        user: adminUser,
      );

      expect(fakeNotifRepo.added, isEmpty);
    });
  });

  group('Customer Creation — notifyCustomerCreated Trigger', () {
    test('1. notifyCustomerCreated dispatches customerCreated with metadata',
        () async {
      const customer = Customer(
        id: 'KH_NEW_001',
        name: 'Trần Thị Bích',
        phone: '0987654321',
        email: 'bich@example.com',
        address: 'Cần Thơ',
        purchases: [],
        currentDebt: 0.0,
      );

      await dispatcher.notifyCustomerCreated(
        storeId: 'store_001',
        customer: customer,
        user: adminUser,
      );

      expect(fakeNotifRepo.added.length, equals(1));
      final notif = fakeNotifRepo.added.first;
      expect(notif.type, equals(NotificationType.customerCreated));
      expect(notif.category, equals(NotificationCategory.customers));
      expect(notif.targetRoute, equals('customer_detail'));
      expect(notif.targetId, equals('KH_NEW_001'));
      expect(notif.title, equals('Khách hàng mới'));
      expect(notif.body, contains('Trần Thị Bích'));
      expect(notif.body, contains('0987654321'));
      expect(notif.metadata?['customerId'], equals('KH_NEW_001'));
      expect(notif.metadata?['phone'], equals('0987654321'));
      expect(notif.metadata?['customerName'], equals('Trần Thị Bích'));
      expect(notif.metadata?['createdBy'], equals('Quản lý kho'));
    });
  });

  group('CompleteStockInReceiptUseCaseProvider — Riverpod Wiring', () {
    test('Resolves autoDispose provider with notificationDispatcherProvider wired',
        () {
      final container = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(fakeNotifRepo),
          productRepositoryProvider.overrideWithValue(mockProductRepo),
          inventoryRepositoryProvider.overrideWithValue(mockInventoryRepo),
          supplierRepositoryProvider.overrideWithValue(mockSupplierRepo),
          stockInReceiptRepositoryProvider.overrideWithValue(mockReceiptRepo),
        ],
      );
      addTearDown(container.dispose);

      final resolvedUseCase =
          container.read(completeStockInReceiptUseCaseProvider);
      expect(resolvedUseCase, isA<CompleteStockInReceiptUseCase>());
    });
  });
}
