import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/complete_stock_in_receipt_use_case.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/stock_in_receipt_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

// ----------------------------------------------------------------------
// Replicated Mocks from the 3 audited files
// ----------------------------------------------------------------------

/// Exact replicate of SpyCompleteStockInReceiptUseCase in
/// test/challenger/challenger_m4_receipt_management_stress_test.dart:183
class AuditSpyCompleteStockInReceiptUseCase
    extends CompleteStockInReceiptUseCase {
  StockInReceipt? lastCompletedReceipt;

  AuditSpyCompleteStockInReceiptUseCase({
    required super.productRepository,
    required super.inventoryRepository,
    required super.supplierRepository,
    required super.receiptRepository,
  });

  @override
  Future<StockInReceipt> execute(StockInReceipt receipt,
      {UserAccount? user}) async {
    lastCompletedReceipt = receipt;
    return receipt.copyWith(status: 'completed');
  }
}

/// Exact replicate of _MockCompleteStockInReceiptUseCase in
/// test/presentation/inventories/challenger_m3_2_stress_test.dart:170
class AuditMockCompleteStockInReceiptUseCase1
    implements CompleteStockInReceiptUseCase {
  final List<StockInReceipt> executed = [];

  @override
  Future<StockInReceipt> execute(StockInReceipt receipt,
      {UserAccount? user}) async {
    final completed = receipt.copyWith(status: 'completed');
    executed.add(completed);
    return completed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Exact replicate of _MockCompleteStockInReceiptUseCase in
/// test/presentation/inventories/tier5_ui_adversarial_hardening_test.dart:219
class AuditMockCompleteStockInReceiptUseCase2
    implements CompleteStockInReceiptUseCase {
  int executeCallCount = 0;
  final List<StockInReceipt> executed = [];

  @override
  Future<StockInReceipt> execute(StockInReceipt receipt,
      {UserAccount? user}) async {
    executeCallCount++;
    final completed = receipt.copyWith(status: 'completed');
    executed.add(completed);
    return completed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ----------------------------------------------------------------------
// Stubs for Production CompleteStockInReceiptUseCase testing
// ----------------------------------------------------------------------

class _StubProductRepo implements ProductRepository {
  final Map<String, Product> products = {};
  @override
  Future<Product?> fetchById(String id) async => products[id];
  @override
  Future<void> upsert(Product product) async {
    products[product.id] = product;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubInventoryRepo implements InventoryRepository {
  @override
  Future<void> record(dynamic tx) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubSupplierRepo implements SupplierRepository {
  final Map<String, Supplier> suppliers = {};
  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async =>
      suppliers[id];
  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    suppliers[supplier.id] = supplier;
  }
  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction tx,
      {String? storeId}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubReceiptRepo implements StockInReceiptRepository {
  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyNotifRepo implements NotificationRepository {
  final List<NotificationItem> items = [];
  @override
  Future<void> addNotification(NotificationItem notification) async {
    items.add(notification);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const adminUser = UserAccount(
    username: 'admin_test',
    displayName: 'Quản Trị Viên Kho',
    role: 'admin',
    storeId: 'store_001',
  );

  final testDate = DateTime(2026, 10, 4);

  final testReceipt = StockInReceipt(
    id: 'PN_CHALLENGER_01',
    importCode: 'NK2026100401',
    storeId: 'store_001',
    date: testDate,
    status: 'draft',
    createdBy: 'staff_1',
    createdByName: 'Nhân viên 1',
    items: const [],
  );

  group('Adversarial Challenge 1: SpyCompleteStockInReceiptUseCase Signature & Polymorphism', () {
    test('Can be called without named user parameter (execute(receipt))', () async {
      final CompleteStockInReceiptUseCase spy = AuditSpyCompleteStockInReceiptUseCase(
        productRepository: _StubProductRepo(),
        inventoryRepository: _StubInventoryRepo(),
        supplierRepository: _StubSupplierRepo(),
        receiptRepository: _StubReceiptRepo(),
      );

      final result = await spy.execute(testReceipt);
      expect(result.status, equals('completed'));
      expect((spy as AuditSpyCompleteStockInReceiptUseCase).lastCompletedReceipt?.id,
          equals('PN_CHALLENGER_01'));
    });

    test('Can be called with explicit user: adminUser', () async {
      final CompleteStockInReceiptUseCase spy = AuditSpyCompleteStockInReceiptUseCase(
        productRepository: _StubProductRepo(),
        inventoryRepository: _StubInventoryRepo(),
        supplierRepository: _StubSupplierRepo(),
        receiptRepository: _StubReceiptRepo(),
      );

      final result = await spy.execute(testReceipt, user: adminUser);
      expect(result.status, equals('completed'));
      expect((spy as AuditSpyCompleteStockInReceiptUseCase).lastCompletedReceipt?.id,
          equals('PN_CHALLENGER_01'));
    });

    test('Can be called with explicit user: null', () async {
      final CompleteStockInReceiptUseCase spy = AuditSpyCompleteStockInReceiptUseCase(
        productRepository: _StubProductRepo(),
        inventoryRepository: _StubInventoryRepo(),
        supplierRepository: _StubSupplierRepo(),
        receiptRepository: _StubReceiptRepo(),
      );

      final result = await spy.execute(testReceipt, user: null);
      expect(result.status, equals('completed'));
    });
  });

  group('Adversarial Challenge 2: AuditMockCompleteStockInReceiptUseCase1 Signature & Polymorphism', () {
    test('Can be called without named user parameter', () async {
      final CompleteStockInReceiptUseCase mock = AuditMockCompleteStockInReceiptUseCase1();

      final result = await mock.execute(testReceipt);
      expect(result.status, equals('completed'));
      expect((mock as AuditMockCompleteStockInReceiptUseCase1).executed.length, equals(1));
    });

    test('Can be called with explicit user: adminUser', () async {
      final CompleteStockInReceiptUseCase mock = AuditMockCompleteStockInReceiptUseCase1();

      final result = await mock.execute(testReceipt, user: adminUser);
      expect(result.status, equals('completed'));
      expect((mock as AuditMockCompleteStockInReceiptUseCase1).executed.length, equals(1));
    });

    test('Can be called with explicit user: null', () async {
      final CompleteStockInReceiptUseCase mock = AuditMockCompleteStockInReceiptUseCase1();

      final result = await mock.execute(testReceipt, user: null);
      expect(result.status, equals('completed'));
      expect((mock as AuditMockCompleteStockInReceiptUseCase1).executed.length, equals(1));
    });
  });

  group('Adversarial Challenge 3: AuditMockCompleteStockInReceiptUseCase2 Call Counter & Signature', () {
    test('Can be called with and without user, incrementing executeCallCount correctly', () async {
      final CompleteStockInReceiptUseCase mock = AuditMockCompleteStockInReceiptUseCase2();

      await mock.execute(testReceipt);
      await mock.execute(testReceipt, user: adminUser);
      await mock.execute(testReceipt, user: null);

      final casted = mock as AuditMockCompleteStockInReceiptUseCase2;
      expect(casted.executeCallCount, equals(3));
      expect(casted.executed.length, equals(3));
    });
  });

  group('Adversarial Challenge 4: Production CompleteStockInReceiptUseCase Fallback Attribution', () {
    test('When user is passed, notificationDispatcher receives that user', () async {
      final spyNotif = _SpyNotifRepo();
      final dispatcher = NotificationDispatcher(spyNotif);
      final productRepo = _StubProductRepo();
      const prod = Product(
        id: 'p1',
        name: 'Item 1',
        code: 'I1',
        category: 'General',
        costPrice: 100,
        price: 200,
        branchStocks: {'store_001': 5},
      );
      productRepo.products['p1'] = prod;

      final useCase = CompleteStockInReceiptUseCase(
        productRepository: productRepo,
        inventoryRepository: _StubInventoryRepo(),
        supplierRepository: _StubSupplierRepo(),
        receiptRepository: _StubReceiptRepo(),
        notificationDispatcher: dispatcher,
      );

      final receipt = StockInReceipt(
        id: 'PN_01',
        importCode: 'NK_01',
        storeId: 'store_001',
        date: testDate,
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'p1',
            productName: 'Item 1',
            quantity: 1,
            importPrice: 100,
          ),
        ],
        createdBy: 'fallback_user',
        createdByName: 'Fallback User Name',
      );

      await useCase.execute(receipt, user: adminUser);

      expect(spyNotif.items.length, equals(1));
      final item = spyNotif.items.first;
      expect(item.type, equals(NotificationType.inventoryImported));
      expect(item.metadata?['createdBy'], equals('Quản Trị Viên Kho'));
    });

    test('When user is omitted, notificationDispatcher falls back to createdByName', () async {
      final spyNotif = _SpyNotifRepo();
      final dispatcher = NotificationDispatcher(spyNotif);
      final productRepo = _StubProductRepo();
      const prod = Product(
        id: 'p1',
        name: 'Item 1',
        code: 'I1',
        category: 'General',
        costPrice: 100,
        price: 200,
        branchStocks: {'store_001': 5},
      );
      productRepo.products['p1'] = prod;

      final useCase = CompleteStockInReceiptUseCase(
        productRepository: productRepo,
        inventoryRepository: _StubInventoryRepo(),
        supplierRepository: _StubSupplierRepo(),
        receiptRepository: _StubReceiptRepo(),
        notificationDispatcher: dispatcher,
      );

      final receipt = StockInReceipt(
        id: 'PN_01',
        importCode: 'NK_01',
        storeId: 'store_001',
        date: testDate,
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'p1',
            productName: 'Item 1',
            quantity: 1,
            importPrice: 100,
          ),
        ],
        createdBy: 'staff_auto',
        createdByName: 'Auto Staff Name',
      );

      // Call WITHOUT user named parameter
      await useCase.execute(receipt);

      expect(spyNotif.items.length, equals(1));
      final item = spyNotif.items.first;
      expect(item.metadata?['createdBy'], equals('Auto Staff Name'));
    });

    test('When both user and createdBy are null, notification handles null actor safely', () async {
      final spyNotif = _SpyNotifRepo();
      final dispatcher = NotificationDispatcher(spyNotif);
      final productRepo = _StubProductRepo();
      const prod = Product(
        id: 'p1',
        name: 'Item 1',
        code: 'I1',
        category: 'General',
        costPrice: 100,
        price: 200,
        branchStocks: {'store_001': 5},
      );
      productRepo.products['p1'] = prod;

      final useCase = CompleteStockInReceiptUseCase(
        productRepository: productRepo,
        inventoryRepository: _StubInventoryRepo(),
        supplierRepository: _StubSupplierRepo(),
        receiptRepository: _StubReceiptRepo(),
        notificationDispatcher: dispatcher,
      );

      final receipt = StockInReceipt(
        id: 'PN_01',
        importCode: 'NK_01',
        storeId: 'store_001',
        date: testDate,
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'p1',
            productName: 'Item 1',
            quantity: 1,
            importPrice: 100,
          ),
        ],
        createdBy: null,
        createdByName: null,
      );

      // Call without user and with null createdBy
      final res = await useCase.execute(receipt);
      expect(res.status, equals('completed'));
      expect(spyNotif.items.length, equals(1));
      final item = spyNotif.items.first;
      expect(item.metadata?['createdBy'], equals('Không xác định'));
    });
  });
}
