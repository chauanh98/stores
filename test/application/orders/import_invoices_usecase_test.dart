import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/usecases/import_invoices_usecase.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';

class _FakeOrderRepository implements OrderRepository {
  final Map<String, Order> storage = {};

  _FakeOrderRepository([List<Order> initial = const []]) {
    for (final o in initial) {
      storage[o.id] = o;
    }
  }

  @override
  Future<void> create(Order order) async {
    storage[order.id] = order;
  }

  @override
  Future<void> update(Order order) async {
    storage[order.id] = order;
  }

  @override
  Future<void> delete(String orderId) async {
    storage.remove(orderId);
  }

  @override
  Future<Order?> fetchById(String orderId) async => storage[orderId];

  @override
  Stream<List<Order>> watchAll() => Stream.value(storage.values.toList());

  @override
  Stream<List<Order>> watchByCustomer(String customerId) => Stream.value(
      storage.values.where((o) => o.customerId == customerId).toList());

  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) =>
      Stream.value(storage.values.toList());
}

class _FakeProductRepository implements ProductRepository {
  final Map<String, Product> storage = {};

  _FakeProductRepository([List<Product> initial = const []]) {
    for (final p in initial) {
      storage[p.id] = p;
    }
  }

  @override
  Stream<List<Product>> watchAll() => Stream.value(storage.values.toList());

  @override
  Future<List<Product>> fetchAll() async => storage.values.toList();

  @override
  Future<Product?> fetchById(String id) async => storage[id];

  @override
  Future<void> upsert(Product product) async {
    storage[product.id] = product;
  }

  @override
  Future<void> delete(String id) async {
    storage.remove(id);
  }

  @override
  Future<void> updateStock(String id, int newStock) async {
    final p = storage[id];
    if (p != null) {
      storage[id] = p.copyWith(branchStocks: {'store_001': newStock});
    }
  }
}

class _FakeInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async {
    transactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(
          transactions.where((t) => t.productId == productId).toList());

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime start, DateTime end,
          {String? storeId}) =>
      Stream.value(transactions);
}

class _FakeCustomerRepository implements CustomerRepository {
  final Map<String, Customer> storage = {};

  _FakeCustomerRepository([List<Customer> initial = const []]) {
    for (final c in initial) {
      storage[c.id] = c;
    }
  }

  @override
  Stream<List<Customer>> watchAll() =>
      Stream.value(storage.values.toList());

  @override
  Future<Customer?> fetchById(String id) async => storage[id];

  @override
  Future<void> upsert(Customer customer) async {
    storage[customer.id] = customer;
  }

  @override
  Future<void> delete(String id) async {
    storage.remove(id);
  }
}

void main() {
  group('ImportInvoicesUseCase Tests', () {
    late _FakeOrderRepository orderRepo;
    late _FakeProductRepository productRepo;
    late _FakeInventoryRepository inventoryRepo;
    late _FakeCustomerRepository customerRepo;
    late ImportInvoicesUseCase useCase;

    setUp(() {
      orderRepo = _FakeOrderRepository();
      productRepo = _FakeProductRepository();
      inventoryRepo = _FakeInventoryRepository();
      customerRepo = _FakeCustomerRepository();
      useCase = ImportInvoicesUseCase(
        orderRepository: orderRepo,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        customerRepository: customerRepo,
      );
    });

    test('Empty list returns empty ImportResult', () async {
      final result = await useCase.execute(
        orders: [],
        targetStoreId: 'store_001',
      );
      expect(result.total, 0);
      expect(result.added, 0);
      expect(result.skipped, 0);
      expect(result.errors, 0);
    });

    test(
        'Existing invoice is UPDATED with latest fields without double revenue, double debt, or double stock deduction',
        () async {
      // 1. Existing order in system
      final existingOrder = Order(
        id: 'HD_DUP_001',
        customerId: 'cust_dup_1',
        createdAt: DateTime(2026, 2, 1),
        items: [
          OrderItem(
            productId: 'prod_item_1',
            productName: 'Chuột Gaming',
            quantity: 2,
            price: 500000,
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 2, 1),
          ),
        ],
        total: 1000000,
        discount: 0,
        amountPaid: 600000,
        debtAmount: 400000,
        storeId: 'store_001',
        status: 'completed',
      );
      await orderRepo.create(existingOrder);

      // 2. Existing product in store with 10 units
      const existingProduct = Product(
        id: 'prod_item_1',
        name: 'Chuột Gaming',
        code: 'MS_G1',
        price: 500000,
        costPrice: 300000,
        branchStocks: {'store_001': 10},
        category: 'Phụ kiện',
      );
      await productRepo.upsert(existingProduct);

      // 3. Existing customer with currentDebt 400000, totalSales 1000000
      const existingCustomer = Customer(
        id: 'cust_dup_1',
        name: 'Khách hàng A',
        phone: '0901234567',
        email: '',
        address: '',
        purchases: [],
        currentDebt: 400000,
        totalSales: 1000000,
        netSales: 1000000,
      );
      await customerRepo.upsert(existingCustomer);

      // 4. Try re-importing updated invoice HD_DUP_001 with gross total 1,200,000, discount 200,000, updated status and customer name
      final updatedImportOrder = Order(
        id: 'HD_DUP_001',
        customerId: 'cust_dup_1',
        customerName: 'Khách hàng A (VIP)',
        createdAt: DateTime(2026, 2, 1),
        items: [
          OrderItem(
            productId: 'prod_item_1',
            productName: 'Chuột Gaming RGB',
            quantity: 2,
            price: 600000,
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 2, 1),
          ),
        ],
        total: 1200000,
        discount: 200000,
        amountPaid: 800000,
        debtAmount: 200000,
        paymentMethod: 'transfer',
        status: 'completed',
      );

      final result = await useCase.execute(
        orders: [updatedImportOrder],
        targetStoreId: 'store_001',
      );

      // 5. Must be UPDATED
      expect(result.total, 1);
      expect(result.updated, 1);
      expect(result.added, 0);
      expect(result.skipped, 0);
      expect(result.errors, 0);

      // 6. Existing order fields MUTATED to latest values:
      final updatedInDb = await orderRepo.fetchById('HD_DUP_001');
      expect(updatedInDb, isNotNull);
      expect(updatedInDb!.total, 1200000);
      expect(updatedInDb.discount, 200000);
      expect(updatedInDb.customerName, 'Khách hàng A (VIP)');
      expect(updatedInDb.paymentMethod, 'transfer');
      expect(updatedInDb.amountPaid, 800000);
      expect(updatedInDb.debtAmount, 200000);
      expect(updatedInDb.items.first.productName, 'Chuột Gaming RGB');

      // 7. ZERO DOUBLE-DEDUCTION SIDE EFFECTS:
      // Product stock remains 10 (not deducted to 8!)
      final p = await productRepo.fetchById('prod_item_1');
      expect(p!.branchStocks['store_001'], 10);

      // Customer debt remains 400000 (not double-added to 600000!)
      final c = await customerRepo.fetchById('cust_dup_1');
      expect(c!.currentDebt, 400000);
      expect(c.totalSales, 1000000);

      // Zero inventory export transactions created!
      expect(inventoryRepo.transactions, isEmpty);
    });

    test(
        'New invoice inserts order, updates customer purchases/sales/debt, and deducts inventory',
        () async {
      // Setup product with 15 units in store_001
      const product = Product(
        id: 'prod_single_1',
        name: 'Tai nghe Sony WH-1000XM5',
        code: 'SONY_XM5',
        price: 8000000,
        costPrice: 6500000,
        branchStocks: {'store_001': 15},
        category: 'Âm thanh',
      );
      await productRepo.upsert(product);

      // Setup customer
      const customer = Customer(
        id: 'cust_new_order_1',
        name: 'Hoàng Văn D',
        phone: '0988776655',
        email: '',
        address: 'Hà Nội',
        purchases: [],
        currentDebt: 0.0,
        totalSales: 0.0,
        netSales: 0.0,
      );
      await customerRepo.upsert(customer);

      // New invoice for 2 headphones with 5,000,000 debt
      final newOrder = Order(
        id: 'HD_NEW_888',
        customerId: 'cust_new_order_1',
        createdAt: DateTime(2026, 3, 1),
        items: [
          OrderItem(
            productId: 'prod_single_1',
            productName: 'Tai nghe Sony WH-1000XM5',
            quantity: 2,
            price: 8000000,
            warrantyMonths: 24,
            purchaseDate: DateTime(2026, 3, 1),
          ),
        ],
        total: 16000000,
        amountPaid: 11000000,
        debtAmount: 5000000,
      );

      final result = await useCase.execute(
        orders: [newOrder],
        targetStoreId: 'store_001',
      );

      expect(result.total, 1);
      expect(result.added, 1);
      expect(result.skipped, 0);
      expect(result.errors, 0);

      // 1. Order stored
      final storedOrder = await orderRepo.fetchById('HD_NEW_888');
      expect(storedOrder, isNotNull);
      expect(storedOrder!.storeId, 'store_001');

      // 2. Customer updated: purchases, sales, debt
      final updatedCust =
          await customerRepo.fetchById('cust_new_order_1');
      expect(updatedCust, isNotNull);
      expect(updatedCust!.purchases.length, 1);
      expect(updatedCust.purchases.first.productId, 'prod_single_1');
      expect(updatedCust.purchases.first.quantity, 2);
      expect(updatedCust.totalSales, 16000000);
      expect(updatedCust.netSales, 16000000);
      expect(updatedCust.currentDebt, 5000000);

      // 3. Product stock deducted from 15 to 13
      final updatedProd = await productRepo.fetchById('prod_single_1');
      expect(updatedProd!.branchStocks['store_001'], 13);

      // 4. Inventory export transaction recorded
      expect(inventoryRepo.transactions.length, 1);
      final tx = inventoryRepo.transactions.first;
      expect(tx.productId, 'prod_single_1');
      expect(tx.type, TransactionType.export);
      expect(tx.quantity, 2);
      expect(tx.storeId, 'store_001');
    });

    test('New invoice deducts combo components stock correctly', () async {
      // Child component product in store_001 with 20 units
      const childComponent = Product(
        id: 'comp_cable',
        name: 'Cáp sạc',
        code: 'CABLE',
        price: 100000,
        costPrice: 50000,
        branchStocks: {'store_001': 20},
        category: 'Linh kiện',
      );
      await productRepo.upsert(childComponent);

      // Combo product (contains 2 cables per combo)
      const comboProduct = Product(
        id: 'prod_combo_set',
        name: 'Combo 2 Cáp',
        code: 'COMBO_2C',
        price: 180000,
        costPrice: 100000,
        branchStocks: {'store_001': 0},
        category: 'Combo',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'comp_cable',
            productCode: 'CABLE',
            productName: 'Cáp sạc',
            quantity: 2,
          ),
        ],
      );
      await productRepo.upsert(comboProduct);

      // Order 3 combos => should deduct 3 * 2 = 6 cables from comp_cable
      final comboOrder = Order(
        id: 'HD_COMBO_01',
        customerId: '',
        createdAt: DateTime.now(),
        items: [
          OrderItem(
            productId: 'prod_combo_set',
            productName: 'Combo 2 Cáp',
            quantity: 3,
            price: 180000,
            warrantyMonths: 6,
            purchaseDate: DateTime.now(),
          ),
        ],
        total: 540000,
      );

      final result = await useCase.execute(
        orders: [comboOrder],
        targetStoreId: 'store_001',
      );

      expect(result.added, 1);

      // Verify childComponent stock: 20 - 6 = 14
      final storedChild = await productRepo.fetchById('comp_cable');
      expect(storedChild!.branchStocks['store_001'], 14);

      // Verify export transaction recorded for component
      expect(inventoryRepo.transactions.length, 1);
      final tx = inventoryRepo.transactions.first;
      expect(tx.productId, 'comp_cable');
      expect(tx.quantity, 6);
      expect(tx.type, TransactionType.export);
    });

    test('Summary string matches standard format', () async {
      final existing = Order(
        id: 'HD_EXISTING',
        customerId: '',
        createdAt: DateTime.now(),
        items: [],
        total: 100,
      );
      await orderRepo.create(existing);

      final o1 = Order(
        id: 'HD_EXISTING', // Will be updated
        customerId: '',
        createdAt: DateTime.now(),
        items: [],
        total: 150,
      );
      final o2 = Order(
        id: 'HD_NEW', // Will be added
        customerId: '',
        createdAt: DateTime.now(),
        items: [],
        total: 200,
      );

      final result = await useCase.execute(
        orders: [o1, o2],
        targetStoreId: 'store_001',
      );

      expect(result.total, 2);
      expect(result.added, 1);
      expect(result.skipped, 0);
      expect(result.updated, 1);
      expect(result.errors, 0);
      expect(
        result.toSummaryString(),
        'Tổng số dòng: 2 | Thêm mới: 1 | Cập nhật: 1 | Bỏ qua: 0 | Lỗi: 0',
      );
    });

    test('Adversarial: re-importing existing invoice updates customerId and storeId if provided', () async {
      final oldOrder = Order(
        id: 'HD_GUEST_TO_REAL',
        customerId: 'khach_le',
        createdAt: DateTime(2026, 1, 1),
        items: const [],
        total: 500000,
        discount: 0,
        amountPaid: 500000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(oldOrder);

      final reImport = Order(
        id: 'HD_GUEST_TO_REAL',
        customerId: 'KH009999',
        customerName: 'Nguyễn Văn VIP',
        createdAt: DateTime(2026, 1, 1),
        items: const [],
        total: 500000,
        discount: 0,
        amountPaid: 500000,
        status: 'completed',
        storeId: 'store_002',
      );

      final result = await useCase.execute(
        orders: [reImport],
        targetStoreId: 'store_002',
      );

      expect(result.updated, 1);
      final updated = await orderRepo.fetchById('HD_GUEST_TO_REAL');
      expect(updated!.customerId, 'KH009999');
      expect(updated.customerName, 'Nguyễn Văn VIP');
      expect(updated.storeId, 'store_002');
    });

    test('Adversarial: re-importing existing invoice updates seller, cancelReason and protects non-empty customerName', () async {
      final oldOrder = Order(
        id: 'HD_SELLER_TEST',
        customerId: 'KH01',
        customerName: 'Trần Văn Cố Định',
        createdAt: DateTime(2026, 1, 1),
        items: const [],
        total: 500000,
        discount: 0,
        amountPaid: 500000,
        status: 'completed',
        storeId: 'store_001',
        createdBy: null,
        createdByName: null,
      );
      await orderRepo.create(oldOrder);

      final reImportWithSellerAndCancelled = Order(
        id: 'HD_SELLER_TEST',
        customerId: 'KH01',
        customerName: '   ', // Whitespace string should not overwrite existing name
        createdAt: DateTime(2026, 1, 1),
        items: const [],
        total: 500000,
        discount: 0,
        amountPaid: 0,
        status: 'cancelled',
        cancelReason: 'Khách đổi ý hủy đơn',
        createdBy: 'admin_nv',
        createdByName: 'Nguyễn Văn Bán Hàng',
        storeId: 'store_001',
      );

      final result = await useCase.execute(
        orders: [reImportWithSellerAndCancelled],
        targetStoreId: 'store_001',
      );

      expect(result.updated, 1);
      final updated = await orderRepo.fetchById('HD_SELLER_TEST');
      expect(updated, isNotNull);
      expect(updated!.customerName, 'Trần Văn Cố Định', reason: 'Whitespace must not overwrite name');
      expect(updated.createdBy, 'admin_nv');
      expect(updated.createdByName, 'Nguyễn Văn Bán Hàng');
      expect(updated.status, 'cancelled');
      expect(updated.cancelReason, 'Khách đổi ý hủy đơn');
      expect(updated.cancelledAt, isNotNull, reason: 'cancelledAt should be recorded');
    });

    test('Adversarial: re-importing with empty or fallback dummy item preserves detailed existing items', () async {
      final detailedOrder = Order(
        id: 'HD_DETAILED_ITEMS',
        customerId: 'KH01',
        createdAt: DateTime(2026, 1, 1),
        items: [
          OrderItem(
            productId: 'P_REAL_1',
            productName: 'Sản phẩm thực tế',
            quantity: 2,
            price: 500000,
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 1, 1),
          ),
        ],
        total: 1000000,
        discount: 0,
        amountPaid: 1000000,
        status: 'completed',
        storeId: 'store_001',
      );
      await orderRepo.create(detailedOrder);

      // Re-import with dummy fallback item (e.g. from summary-only export)
      final dummySummaryOrder = Order(
        id: 'HD_DETAILED_ITEMS',
        customerId: 'KH01',
        createdAt: DateTime(2026, 1, 1),
        items: [
          OrderItem(
            productId: 'inv_item_HD_DETAILED_ITEMS',
            productName: 'Hàng hóa theo hóa đơn HD_DETAILED_ITEMS',
            quantity: 1,
            price: 1000000,
            warrantyMonths: 0,
            purchaseDate: DateTime(2026, 1, 1),
          ),
        ],
        total: 1000000,
        discount: 0,
        amountPaid: 1000000,
        status: 'completed',
        storeId: 'store_001',
      );

      final result = await useCase.execute(
        orders: [dummySummaryOrder],
        targetStoreId: 'store_001',
      );

      expect(result.updated, 1);
      final updated = await orderRepo.fetchById('HD_DETAILED_ITEMS');
      expect(updated!.items.length, 1);
      expect(updated.items.first.productId, 'P_REAL_1',
          reason: 'Detailed item must not be wiped out by dummy fallback');
    });

    test('Adversarial: ImportInvoicesUseCase defensively auto-reconciles gross total and discount from items', () async {
      // Order with legacy total = 900,000 and discount = 0, but item price = 1,000,000
      final rawOrderWithDiscrepancy = Order(
        id: 'HD_DEFENSIVE_GROSS',
        customerId: 'KH01',
        createdAt: DateTime(2026, 1, 1),
        items: [
          OrderItem(
            productId: 'P_SAMPLE',
            productName: 'Sample',
            quantity: 1,
            price: 1000000,
            warrantyMonths: 0,
            purchaseDate: DateTime(2026, 1, 1),
          ),
        ],
        total: 900000, // Legacy net payable
        discount: 0,   // Missing discount
        amountPaid: 900000,
        status: 'completed',
      );

      final result = await useCase.execute(
        orders: [rawOrderWithDiscrepancy],
        targetStoreId: 'store_001',
      );

      expect(result.added, 1);
      final saved = await orderRepo.fetchById('HD_DEFENSIVE_GROSS');
      expect(saved!.total, 1000000.0, reason: 'Gross total must be reconciled to 1,000,000');
      expect(saved.discount, 100000.0, reason: 'Discount must be auto-calculated to 100,000');
      expect(saved.netPayable, 900000.0);
    });
  });
}
