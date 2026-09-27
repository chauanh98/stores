import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventory/inter_store_transfer_service.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/application/orders/usecases/collect_invoice_debt_usecase.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/application/products/usecases/cascade_category_update_usecase.dart';
import 'package:stores/data/datasources/firebase/customer_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/repositories/order_repository_impl.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/category_repository.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';

import '../support/firebase_test_harness.dart';

class InMemoryProductRepository implements ProductRepository {
  final Map<String, Product> products = {};
  final MockFirebaseDatabase mockDb;

  InMemoryProductRepository(this.mockDb);

  @override
  Future<void> delete(String id) async {
    products.remove(id);
    await mockDb.ref('stores/store_001/products/$id').remove();
  }

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<void> updateStock(String id, int newStock) async {
    final p = products[id];
    if (p != null) {
      final updated = p.copyWith(branchStocks: {'store_001': newStock});
      products[id] = updated;
      await mockDb.ref('stores/store_001/products/$id/branchStocks').set({'store_001': newStock});
    }
  }

  @override
  Future<void> upsert(Product product) async {
    products[product.id] = product;
    await mockDb.ref('stores/store_001/products/${product.id}').set({
      'id': product.id,
      'name': product.name,
      'code': product.code,
      'price': product.price,
      'costPrice': product.costPrice,
      'branchStocks': product.branchStocks,
      'category': product.category,
      'category3Levels': product.category3Levels,
    });
  }

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());
}

class InMemoryInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];
  final MockFirebaseDatabase mockDb;

  InMemoryInventoryRepository(this.mockDb);

  @override
  Future<void> record(InventoryTransaction tx) async {
    transactions.add(tx);
    await mockDb
        .ref('stores/${tx.storeId ?? 'store_001'}/inventory_transactions/${tx.id}')
        .set({
      'id': tx.id,
      'productId': tx.productId,
      'type': tx.type.name,
      'quantity': tx.quantity,
      'date': tx.date.toIso8601String(),
      'note': tx.note,
      'storeId': tx.storeId,
    });
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(transactions.where((t) => t.productId == productId).toList());

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime startDate, DateTime endDate) =>
      Stream.value(transactions);
}

class InMemoryCustomerRepository implements CustomerRepository {
  final Map<String, Customer> customers = {};
  final MockFirebaseDatabase mockDb;

  InMemoryCustomerRepository(this.mockDb);

  @override
  Future<void> delete(String id) async {
    customers.remove(id);
    await mockDb.ref('shared_customers/$id').remove();
  }

  @override
  Future<Customer?> fetchById(String id) async => customers[id];

  @override
  Future<void> upsert(Customer customer) async {
    customers[customer.id] = customer;
    await mockDb.ref('shared_customers/${customer.id}').update({
      'id': customer.id,
      'name': customer.name,
      'phone': customer.phone,
      'currentDebt': customer.currentDebt,
      'totalSales': customer.totalSales,
      'netSales': customer.netSales,
    });
  }

  @override
  Stream<List<Customer>> watchAll() => Stream.value(customers.values.toList());
}

class InMemoryCategoryRepository implements CategoryRepository {
  final Map<String, Category> categories = {};
  final MockFirebaseDatabase mockDb;

  InMemoryCategoryRepository(this.mockDb);

  @override
  Future<void> delete(String id) async {
    categories.remove(id);
    await mockDb.ref('shared_categories/$id').remove();
  }

  @override
  Future<List<Category>> fetchAll() async => categories.values.toList();

  @override
  Future<void> upsert(Category category) async {
    categories[category.id] = category;
    await mockDb.ref('shared_categories/${category.id}').set({
      'id': category.id,
      'name': category.name,
      'parentId': category.parentId,
    });
  }

  @override
  Stream<List<Category>> watchAll() => Stream.value(categories.values.toList());
}

void main() {
  late MockFirebaseDatabase mockDb;
  late OrderRemoteDataSource orderDataSource;
  late CustomerRemoteDataSource customerDataSource;
  late OrderRepository orderRepository;
  late InMemoryProductRepository productRepository;
  late InMemoryInventoryRepository inventoryRepository;
  late InMemoryCustomerRepository customerRepository;
  late InMemoryCategoryRepository categoryRepository;

  late CollectInvoiceDebtUseCase collectDebtUseCase;
  late CancelInvoiceUseCase cancelInvoiceUseCase;
  late InterStoreTransferService interStoreTransferService;
  late ProcessReturnOrderUseCase processReturnOrderUseCase;
  late CascadeCategoryUpdateUseCase cascadeCategoryUpdateUseCase;

  const adminUser = UserAccount(
    username: 'admin_audit',
    displayName: 'Quản trị viên Hệ thống',
    role: 'admin',
    storeId: 'store_001',
  );

  final testDate = DateTime(2026, 8, 20, 9, 30);

  setUp(() {
    mockDb = MockFirebaseDatabase();
    orderDataSource = OrderRemoteDataSource(mockDb, 'store_001');
    customerDataSource = CustomerRemoteDataSource(mockDb);

    orderRepository = OrderRepositoryImpl(orderDataSource);
    productRepository = InMemoryProductRepository(mockDb);
    inventoryRepository = InMemoryInventoryRepository(mockDb);
    customerRepository = InMemoryCustomerRepository(mockDb);
    categoryRepository = InMemoryCategoryRepository(mockDb);

    collectDebtUseCase = CollectInvoiceDebtUseCase(
      orderRepository: orderRepository,
      customerRepository: customerRepository,
      customerDataSource: customerDataSource,
    );

    cancelInvoiceUseCase = CancelInvoiceUseCase(
      orderRepository: orderRepository,
      productRepository: productRepository,
      inventoryRepository: inventoryRepository,
      customerRepository: customerRepository,
      customerDataSource: customerDataSource,
    );

    interStoreTransferService = InterStoreTransferService(mockDb);

    processReturnOrderUseCase = ProcessReturnOrderUseCase(
      orderRepository: orderRepository,
      productRepository: productRepository,
      inventoryRepository: inventoryRepository,
      customerRepository: customerRepository,
      customerDataSource: customerDataSource,
    );

    cascadeCategoryUpdateUseCase = CascadeCategoryUpdateUseCase(
      categoryRepository: categoryRepository,
      productRepository: productRepository,
      firebaseDatabase: mockDb,
      currentStoreId: 'store_001',
    );
  });

  group('Challenger R2 Adversarial Core Business Use Cases Lifecycle Integration Tests', () {
    test('End-to-End Orchestrated Adversarial Lifecycle across 6 Core Business Operations', () async {
      // =======================================================================
      // STAGE 0: Initial State Setup
      // =======================================================================

      // 1. Categories
      const catRoot = Category(id: 'cat_root', name: 'Linh kiện');
      const catKb = Category(id: 'cat_kb', name: 'Bàn phím', parentId: 'cat_root');
      const catMouse = Category(id: 'cat_mouse', name: 'Chuột', parentId: 'cat_root');
      await categoryRepository.upsert(catRoot);
      await categoryRepository.upsert(catKb);
      await categoryRepository.upsert(catMouse);

      // 2. Products
      const kbProduct = Product(
        id: 'P_KB',
        name: 'Bàn phím cơ Pro',
        code: 'KB_PRO',
        price: 1500000,
        costPrice: 900000,
        branchStocks: {'store_001': 10, 'store_002': 5},
        category: 'Bàn phím',
        category3Levels: 'Linh kiện >> Bàn phím',
      );
      const mouseProduct = Product(
        id: 'P_MOUSE',
        name: 'Chuột không dây Silent',
        code: 'M_SILENT',
        price: 500000,
        costPrice: 300000,
        branchStocks: {'store_001': 20, 'store_002': 8},
        category: 'Chuột',
        category3Levels: 'Linh kiện >> Chuột',
      );
      const comboProduct = Product(
        id: 'P_COMBO',
        name: 'Bộ Văn Phòng Cao Cấp',
        code: 'COMBO_PRO',
        price: 2200000,
        costPrice: 1500000,
        branchStocks: {'store_001': 0},
        category: 'Combo',
        category3Levels: 'Linh kiện >> Combo',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'P_KB',
            productCode: 'KB_PRO',
            productName: 'Bàn phím cơ Pro',
            quantity: 1,
          ),
          ComboComponent(
            productId: 'P_MOUSE',
            productCode: 'M_SILENT',
            productName: 'Chuột không dây Silent',
            quantity: 2,
          ),
        ],
      );
      await productRepository.upsert(kbProduct);
      await productRepository.upsert(mouseProduct);
      await productRepository.upsert(comboProduct);

      // Also seed into store_002 for inter-store transfer testing
      mockDb.seedData('stores/store_002/products/P_KB', {
        'id': 'P_KB',
        'name': 'Bàn phím cơ Pro',
        'code': 'KB_PRO',
        'branchStocks': {'store_001': 10, 'store_002': 5},
      });

      // 3. Customer
      const customer = Customer(
        id: 'CUST_ALPHA',
        name: 'Công ty Công nghệ Alpha',
        phone: '0912345678',
        email: 'alpha@example.com',
        address: 'Hà Nội',
        purchases: [],
        currentDebt: 2000000,
        totalSales: 10000000,
        netSales: 10000000,
      );
      await customerRepository.upsert(customer);

      // =======================================================================
      // STEP 1: [Module 1] Create Invoice via OrderRemoteDataSource
      // =======================================================================
      // Order: 2 x Keyboard (3,000,000) + 1 x Combo (2,200,000) = 5,200,000
      // Customer pays 2,200,000; remaining debt: 3,000,000
      final orderInitial = Order(
        id: 'HD_ADV_001',
        customerId: 'CUST_ALPHA',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_KB',
            productName: 'Bàn phím cơ Pro',
            quantity: 2,
            price: 1500000,
            warrantyMonths: 24,
            purchaseDate: testDate,
          ),
          OrderItem(
            productId: 'P_COMBO',
            productName: 'Bộ Văn Phòng Cao Cấp',
            quantity: 1,
            price: 2200000,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 5200000,
        amountPaid: 2200000,
        debtAmount: 3000000,
        status: 'completed',
        paymentMethod: 'cash',
        storeId: 'store_001',
      );

      // Persist via OrderRepository (which uses OrderRemoteDataSource)
      await orderRepository.create(orderInitial);

      // Customer debt increases by order debt (2,000,000 + 3,000,000 = 5,000,000)
      await customerRepository.upsert(
        customer.copyWith(
          currentDebt: 5000000,
          totalSales: 15200000,
          netSales: 15200000,
        ),
      );

      // Verify in MockFirebaseDatabase
      final fetchedOrderSnap = await orderDataSource.fetchById('HD_ADV_001');
      expect(fetchedOrderSnap, isNotNull);
      expect(fetchedOrderSnap!['total'], 5200000.0);
      expect(fetchedOrderSnap['amountPaid'], 2200000.0);
      expect(fetchedOrderSnap['debtAmount'], 3000000.0);
      expect(fetchedOrderSnap['status'], 'completed');

      // =======================================================================
      // STEP 2: [Module 2] Collect Debt via CollectInvoiceDebtUseCase
      // =======================================================================
      // Customer pays 1,000,000 towards the invoice debt via bank transfer
      final fetchedOrder1 = (await orderRepository.fetchById('HD_ADV_001'))!;
      final orderAfterDebtPay = await collectDebtUseCase.execute(
        order: fetchedOrder1,
        amount: 1000000,
        paymentMethod: 'transfer',
        currentUser: adminUser,
        note: 'Đợt 1 thanh toán QR',
      );

      // Order assertions
      expect(orderAfterDebtPay.amountPaid, 3200000.0);
      expect(orderAfterDebtPay.debtAmount, 2000000.0);
      expect(orderAfterDebtPay.remainingDebt, 2000000.0);
      expect(orderAfterDebtPay.hasDebt, true);

      // Customer debt assertions: 5,000,000 - 1,000,000 = 4,000,000
      final custAfterDebt = await customerRepository.fetchById('CUST_ALPHA');
      expect(custAfterDebt?.currentDebt, 4000000.0);

      // Verify CustomerDebtTransaction recorded in RTDB
      final debtPaymentCall = mockDb.recorder.callsFor('set').firstWhere(
        (c) =>
            c.path.contains('shared_customers/CUST_ALPHA/debt_transactions') &&
            (c.value as Map)['type'] == DebtTransactionType.payment.name,
      );
      final paymentTx = debtPaymentCall.value as Map;
      expect(paymentTx['amount'], -1000000.0);
      expect(paymentTx['remainingDebt'], 4000000.0);

      // =======================================================================
      // STEP 3: [Module 5] Process Return Order via ProcessReturnOrderUseCase
      // =======================================================================
      // Customer returns 1 x Keyboard (value: 1,500,000)
      // Remaining invoice debt is 2,000,000
      // debtDeducted = min(1,500,000, 2,000,000) = 1,500,000; cashRefunded = 0
      final returnResult = await processReturnOrderUseCase.execute(
        originalOrder: orderAfterDebtPay,
        returnItems: [
          const ReturnOrderItem(
            productId: 'P_KB',
            productName: 'Bàn phím cơ Pro',
            price: 1500000,
            quantity: 1,
          ),
        ],
        storeId: 'store_001',
        currentUser: adminUser,
        reason: 'Khách đổi ý trả 1 bàn phím',
      );

      expect(returnResult.totalRefund, 1500000.0);
      expect(returnResult.debtDeducted, 1500000.0);
      expect(returnResult.cashRefunded, 0.0);

      // Restock: store_001 stock restored (+1: 10 + 1 = 11)
      final kbAfterReturn = await productRepository.fetchById('P_KB');
      expect(kbAfterReturn?.branchStocks['store_001'], 11);

      // Customer debt decremented: 4,000,000 - 1,500,000 = 2,500,000
      final custAfterReturn = await customerRepository.fetchById('CUST_ALPHA');
      expect(custAfterReturn?.currentDebt, 2500000.0);

      // ReturnOrder persisted in stores/store_001/return_orders
      final returnOrderSnap =
          await orderDataSource.fetchReturnById(returnResult.returnOrder.id);
      expect(returnOrderSnap, isNotNull);
      expect(returnOrderSnap!['totalReturnAmount'], 1500000.0);
      expect(returnOrderSnap['debtDeducted'], 1500000.0);

      // Order financial update: remaining debt is now 500,000 (2,000,000 - 1,500,000)
      final orderAfterReturn = returnResult.updatedOrder;
      expect(orderAfterReturn.debtAmount, 500000.0);
      expect(orderAfterReturn.status, 'completed'); // 1 KB and 1 Combo still remain active

      // =======================================================================
      // STEP 4: [Module 3] Cancel Invoice with Combo Item via CancelInvoiceUseCase
      // =======================================================================
      // Customer cancels the rest of the invoice
      // Remaining active items: 1 x Keyboard (active: 1), 1 x Combo (active: 1)
      final cancelledOrder = await cancelInvoiceUseCase.execute(
        order: orderAfterReturn,
        cancelReason: 'Khách hủy phần còn lại của hợp đồng',
        currentUser: adminUser,
        storeId: 'store_001',
      );

      expect(cancelledOrder.status, 'cancelled');
      expect(cancelledOrder.isCancelled, true);

      // Stock restoration:
      // 1. Keyboard active (1 unit): 11 + 1 = 12
      // 2. Combo component Keyboard (1 unit): 12 + 1 = 13
      final kbAfterCancel = await productRepository.fetchById('P_KB');
      expect(kbAfterCancel?.branchStocks['store_001'], 13);

      // 3. Combo component Mouse (2 units): 20 + 2 = 22
      final mouseAfterCancel = await productRepository.fetchById('P_MOUSE');
      expect(mouseAfterCancel?.branchStocks['store_001'], 22);

      // Customer debt reversed by remaining debt (500,000):
      // 2,500,000 - 500,000 = 2,000,000 (returned to initial baseline debt!)
      final custAfterCancel = await customerRepository.fetchById('CUST_ALPHA');
      expect(custAfterCancel?.currentDebt, 2000000.0);

      // =======================================================================
      // STEP 5: [Module 4] Inter-Store Transfer via InterStoreTransferService
      // =======================================================================
      // Transfer 5 Keyboards from store_001 (has 13) to store_002 (has 5)
      final latestKb = (await productRepository.fetchById('P_KB'))!;
      final transferSuccess = await interStoreTransferService.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: latestKb,
        quantity: 5,
        sourceStoreName: 'Chi nhánh Đông Thắng',
        targetStoreName: 'Chi nhánh Thới Bình',
        createdBy: adminUser.username,
        createdByName: adminUser.displayName,
      );

      expect(transferSuccess, isNull);

      // Verify multi-path atomic updates
      final updateCalls = mockDb.recorder.callsFor('update');
      expect(updateCalls.isNotEmpty, true);
      final transferUpdates = updateCalls.last.value as Map<String, dynamic>;

      // Source stock decremented: 13 - 5 = 8
      final srcStocks =
          transferUpdates['stores/store_001/products/P_KB/branchStocks'] as Map<String, int>;
      expect(srcStocks['store_001'], 8);

      // Target stock incremented: 5 + 5 = 10
      final tgtStocks =
          transferUpdates['stores/store_002/products/P_KB/branchStocks'] as Map<String, int>;
      expect(tgtStocks['store_002'], 10);

      // Adversarial Check: Attempt insufficient branch stock transfer from store_002
      // store_002 has 5 in product object, requesting 12 (global stock is 8 + 10 = 18 >= 12, but store_002 has only 5)
      final errorInsufficient = await interStoreTransferService.transferProduct(
        sourceStoreId: 'store_002',
        targetStoreId: 'store_001',
        product: latestKb.copyWith(branchStocks: {'store_001': 8, 'store_002': 5}),
        quantity: 12,
      );
      expect(errorInsufficient, isNotNull);
      expect(errorInsufficient, equals('Không đủ số lượng trong kho'));

      // =======================================================================
      // STEP 6: [Module 6] Dynamic Category Cascade Update
      // =======================================================================
      // Admin renames Category "Bàn phím" to "Bàn phím cơ Gaming"
      final targetCategory = (await categoryRepository.fetchAll())
          .firstWhere((c) => c.id == 'cat_kb');
      final allCategories = await categoryRepository.fetchAll();
      final allProducts = await productRepository.fetchAll();

      final cascadeResult = await cascadeCategoryUpdateUseCase.execute(
        targetCategory: targetCategory,
        newName: 'Bàn phím cơ Gaming',
        newParentId: 'cat_root',
        allCategories: allCategories,
        currentProducts: allProducts,
      );

      // Verify category updated in repository
      final updatedCat = (await categoryRepository.fetchAll())
          .firstWhere((c) => c.id == 'cat_kb');
      expect(updatedCat.name, 'Bàn phím cơ Gaming');

      // Verify product category updated in cascade result and repository
      expect(cascadeResult.updatedProductsCount, greaterThanOrEqualTo(1));
      final updatedKbProduct = (await productRepository.fetchById('P_KB'))!;
      expect(updatedKbProduct.category, 'Bàn phím cơ Gaming');
      expect(updatedKbProduct.category3Levels, 'Linh kiện >> Bàn phím cơ Gaming');

      // =======================================================================
      // FINAL AUDIT: Complete Cross-Module State Verification
      // =======================================================================
      // 1. Order status is cancelled
      final finalOrder = await orderRepository.fetchById('HD_ADV_001');
      expect(finalOrder?.status, 'cancelled');

      // 2. Customer debt is preserved at exact 2,000,000 baseline
      final finalCust = await customerRepository.fetchById('CUST_ALPHA');
      expect(finalCust?.currentDebt, 2000000.0);

      // 3. ReturnOrder is registered in store return orders
      final finalReturns = await orderDataSource.watchReturnsByOrderId('HD_ADV_001').first;
      expect(finalReturns.length, 1);
      expect(finalReturns.first['totalReturnAmount'], 1500000.0);

      // 4. Products have accurate branch stock and updated category
      expect(updatedKbProduct.category, 'Bàn phím cơ Gaming');
      expect(mouseAfterCancel?.branchStocks['store_001'], 22);
    });
  });
}
