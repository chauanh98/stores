import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/core/utils/code_generator_helper.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/data/datasources/firebase/customer_remote_data_source.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/pages/pos_checkout_page.dart';
import 'package:stores/presentation/orders/pages/pos_payment_page.dart';

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

class _FakeCustomerListNotifier
    extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _FakeCustomerListNotifier(this._initialCustomers);

  final List<Customer> _initialCustomers;

  @override
  Future<List<Customer>> build() async => _initialCustomers;

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_initialCustomers);
  }
}

class _InMemoryOrderRepository implements OrderRepository {
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

class _InMemoryProductRepository implements ProductRepository {
  final Map<String, Product> products = {};

  @override
  Future<void> delete(String id) async => products.remove(id);

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<void> upsert(Product product) async => products[product.id] = product;

  @override
  Future<void> updateStock(String id, int newStock) async {
    final p = products[id];
    if (p != null) {
      products[id] = p.copyWith(branchStocks: {'store_001': newStock});
    }
  }

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());
}

class _InMemoryCustomerRepository implements CustomerRepository {
  final Map<String, Customer> customers = {};

  @override
  Future<void> delete(String id) async => customers.remove(id);

  @override
  Future<Customer?> fetchById(String id) async => customers[id];

  @override
  Future<void> upsert(Customer customer) async => customers[customer.id] = customer;

  @override
  Stream<List<Customer>> watchAll() => Stream.value(customers.values.toList());
}

class _InMemoryInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  @override
  Future<void> record(InventoryTransaction transaction) async =>
      transactions.add(transaction);

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(transactions.where((t) => t.productId == productId).toList());

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime start, DateTime end) =>
      Stream.value(transactions);
}

class _FakeCustomerRemoteDataSource implements CustomerRemoteDataSource {
  @override
  Future<void> saveDebtTransaction(
          String customerId, Map<String, dynamic> data) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const initialCustomer = Customer(
    id: 'cust_100',
    name: 'Trần Thị B',
    phone: '0988776655',
    email: 'b@example.com',
    address: 'Đà Nẵng',
    purchases: [],
    currentDebt: 500000.0,
    totalSales: 2000000.0,
    netSales: 1800000.0,
  );

  const product1 = Product(
    id: 'prod_101',
    name: 'Bàn Trà Sofa Mặt Đá',
    code: 'BT01',
    price: 2000000.0,
    costPrice: 1200000.0,
    branchStocks: {'store_001': 5},
    category: 'Bàn',
  );

  final completedOrder = Order(
    id: 'HD013259',
    customerId: 'cust_100',
    customerName: 'Trần Thị B',
    customerPhone: '0988776655',
    createdAt: DateTime(2026, 10, 4, 9, 0),
    items: [
      OrderItem(
        productId: 'prod_101',
        productName: 'Bàn Trà Sofa Mặt Đá',
        quantity: 2,
        price: 1800000.0, // Discounted unit price
        originalPrice: 2000000.0,
        discount: 200000.0,
        note: 'Kiểm tra mặt đá kỹ trước khi giao',
        warrantyMonths: 12,
        purchaseDate: DateTime(2026, 10, 4),
      ),
    ],
    total: 4000000.0,
    discount: 400000.0,
    amountPaid: 3100000.0,
    debtAmount: 500000.0,
    status: 'completed',
    paymentMethod: 'cash',
    storeId: 'store_001',
    note: 'Giao buổi sáng',
  );

  test('Versioned code generator increments correctly', () {
    expect(CodeGeneratorHelper.generateVersionedInvoiceCode('HD013259'), 'HD013259_01');
    expect(CodeGeneratorHelper.generateVersionedInvoiceCode('HD001234'), 'HD001234_01');
    expect(CodeGeneratorHelper.generateVersionedInvoiceCode('HD000001'), 'HD000001_01');
  });

  testWidgets(
      'Tapping "Sửa hóa đơn" populates POS cart with full items, discount, note and opens POS Checkout with new versioned ID',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();

    await orderRepo.create(completedOrder);
    await productRepo.upsert(product1);
    await customerRepo.upsert(initialCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        productListProvider.overrideWith((ref) => Stream.value([product1])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([completedOrder])),
        customerListNotifierProvider.overrideWith(
            () => _FakeCustomerListNotifier([initialCustomer])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open bottom sheet
    await tester.tap(find.text('Trần Thị B'));
    await tester.pumpAndSettle();

    // Find and tap "Sửa hóa đơn"
    final editBtn = find.byKey(const Key('edit_invoice_action_button'));
    expect(editBtn, findsOneWidget);
    await tester.tap(editBtn);
    await tester.pumpAndSettle();

    // 1. Verify bottom sheet closed and navigated to POS Checkout
    expect(find.byType(POSCheckoutPage), findsOneWidget);

    // 2. Verify new versioned ID was generated and stored in activeOrderIdProvider
    expect(container.read(activeOrderIdProvider), 'HD013259_01');

    // 3. Verify original order is linked in editingOriginalOrderProvider
    expect(container.read(editingOriginalOrderProvider)?.id, 'HD013259');

    // 4. Verify cart was populated with items, quantity, discount, item note, order discount, customer
    final cart = container.read(cartProvider);
    expect(cart.containsKey('prod_101'), isTrue);
    final cartItem = cart['prod_101']!;
    expect(cartItem.quantity, 2);
    expect(cartItem.discount, 200000.0);
    expect(cartItem.note, 'Kiểm tra mặt đá kỹ trước khi giao');
    expect(cartItem.effectivePrice, 1800000.0);

    // Verify active tab has customer and order note
    final activeTab = container.read(multiCartProvider).activeTab;
    expect(activeTab.customer?.id, 'cust_100');
    expect(activeTab.note, 'Giao buổi sáng');
  });

  testWidgets(
      'Saving edited invoice updates old order to cancelled ("Đã sửa thành HD013259.01") and avoids inventory/debt discrepancy',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();
    final inventoryRepo = _InMemoryInventoryRepository();

    await orderRepo.create(completedOrder);
    await productRepo.upsert(product1);
    await customerRepo.upsert(initialCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
        productListProvider.overrideWith((ref) => Stream.value([product1])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([completedOrder])),
        customerListNotifierProvider.overrideWith(
            () => _FakeCustomerListNotifier([initialCustomer])),
        cancelInvoiceUseCaseProvider.overrideWithValue(
          CancelInvoiceUseCase(
            orderRepository: orderRepo,
            productRepository: productRepo,
            inventoryRepository: inventoryRepo,
            customerRepository: customerRepo,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Open sheet and tap "Sửa hóa đơn"
    await tester.tap(find.text('Trần Thị B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_invoice_action_button')));
    await tester.pumpAndSettle();

    // We are now on POSCheckoutPage with new versioned code HD013259_01
    expect(container.read(activeOrderIdProvider), 'HD013259_01');
    expect(container.read(editingOriginalOrderProvider)?.id, 'HD013259');

    // 2. Click "Lưu tạm" to trigger confirmation dialog and confirm
    final saveDraftBtn = find.text('Lưu tạm');
    expect(saveDraftBtn, findsOneWidget);
    await tester.tap(saveDraftBtn);
    await tester.pumpAndSettle();

    final confirmDraftBtn = find.widgetWithText(FilledButton, 'Lưu tạm');
    expect(confirmDraftBtn, findsOneWidget);
    await tester.tap(confirmDraftBtn);
    await tester.pumpAndSettle();

    // 3. Verify old order HD013259 was cancelled with reason "Đã sửa thành HD013259_01"
    final oldOrder = orderRepo.orders['HD013259']!;
    expect(oldOrder.status, 'cancelled');
    expect(oldOrder.cancelReason, 'Đã sửa thành HD013259_01');

    // 4. Verify old order stock was restored (2 items imported back)
    final updatedProduct = productRepo.products['prod_101']!;
    // Initially stock was 5. Restoring 2 items yields 7.
    expect(updatedProduct.branchStocks['store_001'], 7);

    // 5. Verify old debt (500.000) was reversed for customer
    final updatedCustomer = customerRepo.customers['cust_100']!;
    expect(updatedCustomer.currentDebt, 0.0); // 500.000 - 500.000 = 0.0

    // 6. Verify new draft order HD013259_01 was created
    expect(orderRepo.orders.containsKey('HD013259_01'), isTrue);
    final newDraft = orderRepo.orders['HD013259_01']!;
    expect(newDraft.id, 'HD013259_01');
    expect(newDraft.status, 'draft');

    // 7. Verify activeOrderId and editingOriginalOrder are cleared
    expect(container.read(activeOrderIdProvider), isNull);
    expect(container.read(editingOriginalOrderProvider), isNull);
  });

  testWidgets(
      'Completing payment of edited invoice cancels original order ("Đã sửa thành HD013259_01") and persists replacement order with accurate stock & debt',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();
    final inventoryRepo = _InMemoryInventoryRepository();

    await orderRepo.create(completedOrder);
    await productRepo.upsert(product1);
    await customerRepo.upsert(initialCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
        customerRemoteDataSourceProvider
            .overrideWithValue(_FakeCustomerRemoteDataSource()),
        productListProvider.overrideWith((ref) => Stream.value([product1])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([completedOrder])),
        customerListNotifierProvider.overrideWith(
            () => _FakeCustomerListNotifier([initialCustomer])),
        cancelInvoiceUseCaseProvider.overrideWithValue(
          CancelInvoiceUseCase(
            orderRepository: orderRepo,
            productRepository: productRepo,
            inventoryRepository: inventoryRepo,
            customerRepository: customerRepo,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Open sheet and tap "Sửa hóa đơn"
    await tester.tap(find.text('Trần Thị B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_invoice_action_button')));
    await tester.pumpAndSettle();

    // Verify on POSCheckoutPage
    expect(find.byType(POSCheckoutPage), findsOneWidget);

    // 2. Tap "Thanh toán" on POS Checkout to open POS Payment Page
    final checkoutBtn = find.widgetWithText(ElevatedButton, 'Thanh toán');
    expect(checkoutBtn, findsOneWidget);
    await tester.tap(checkoutBtn);
    await tester.pumpAndSettle();

    // Verify on POSPaymentPage
    expect(find.byType(POSPaymentPage), findsOneWidget);

    // 3. Complete payment on POSPaymentPage
    final payBtn = find.widgetWithText(FilledButton, 'Thanh toán');
    expect(payBtn, findsOneWidget);
    await tester.tap(payBtn);
    await tester.pumpAndSettle();

    // 4. Verify old order HD013259 was cancelled
    final oldOrder = orderRepo.orders['HD013259']!;
    expect(oldOrder.status, 'cancelled');
    expect(oldOrder.cancelReason, 'Đã sửa thành HD013259_01');

    // 5. Verify new order HD013259_01 was completed
    expect(orderRepo.orders.containsKey('HD013259_01'), isTrue);
    final newOrder = orderRepo.orders['HD013259_01']!;
    expect(newOrder.id, 'HD013259_01');
    expect(newOrder.status, 'completed');

    // 6. Verify inventory was restored for old order (+2) and deducted for new order (-2) -> net stock 5
    final finalProduct = productRepo.products['prod_101']!;
    expect(finalProduct.branchStocks['store_001'], 5);

    // 7. Verify activeOrderId and editingOriginalOrder are cleared
    expect(container.read(activeOrderIdProvider), isNull);
    expect(container.read(editingOriginalOrderProvider), isNull);
  });

  testWidgets(
      'Adversarial: Backing out of POS Checkout clears activeOrderIdProvider and editingOriginalOrderProvider, leaving original invoice completed',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();

    await orderRepo.create(completedOrder);
    await productRepo.upsert(product1);
    await customerRepo.upsert(initialCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        productListProvider.overrideWith((ref) => Stream.value([product1])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([completedOrder])),
        customerListNotifierProvider.overrideWith(
            () => _FakeCustomerListNotifier([initialCustomer])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Open sheet and tap "Sửa hóa đơn"
    await tester.tap(find.text('Trần Thị B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_invoice_action_button')));
    await tester.pumpAndSettle();

    // Verify on POSCheckoutPage with active providers set
    expect(find.byType(POSCheckoutPage), findsOneWidget);
    expect(container.read(activeOrderIdProvider), 'HD013259_01');
    expect(container.read(editingOriginalOrderProvider)?.id, 'HD013259');

    // 2. Cashier backs out (taps back button in AppBar)
    final backBtn = find.byType(BackButton);
    expect(backBtn, findsOneWidget);
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    // We are back on InvoicesPage
    expect(find.byType(InvoicesPage), findsOneWidget);

    // 3. Verify dangling providers and cart are safely cleaned up
    expect(container.read(activeOrderIdProvider), isNull);
    expect(container.read(editingOriginalOrderProvider), isNull);
    expect(container.read(cartProvider), isEmpty);

    // 4. Verify original invoice remains completed
    final original = orderRepo.orders['HD013259']!;
    expect(original.status, 'completed');
    expect(original.isCancelled, isFalse);
  });

  testWidgets(
      'Adversarial: Draft saved during edit retains order-level discount and customer phone',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();
    final inventoryRepo = _InMemoryInventoryRepository();

    await orderRepo.create(completedOrder);
    await productRepo.upsert(product1);
    await customerRepo.upsert(initialCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
        productListProvider.overrideWith((ref) => Stream.value([product1])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([completedOrder])),
        customerListNotifierProvider.overrideWith(
            () => _FakeCustomerListNotifier([initialCustomer])),
        cancelInvoiceUseCaseProvider.overrideWithValue(
          CancelInvoiceUseCase(
            orderRepository: orderRepo,
            productRepository: productRepo,
            inventoryRepository: inventoryRepo,
            customerRepository: customerRepo,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Open sheet and tap "Sửa hóa đơn"
    await tester.tap(find.text('Trần Thị B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_invoice_action_button')));
    await tester.pumpAndSettle();

    // 2. Click "Lưu tạm" and confirm
    await tester.tap(find.text('Lưu tạm'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu tạm'));
    await tester.pumpAndSettle();

    // 3. Verify draft retained discount 400.000 and phone 0988776655
    final draft = orderRepo.orders['HD013259_01']!;
    expect(draft.discount, 400000.0);
    expect(draft.customerPhone, '0988776655');
  });

  testWidgets(
      'Adversarial: Insufficient stock rejects payment and DOES NOT cancel original order',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    // Only 1 item in stock. Old order had 2 items. Total possible is 1 + 2 = 3.
    const limitedProduct = Product(
      id: 'prod_101',
      name: 'Bàn Trà Sofa Mặt Đá',
      code: 'BT01',
      price: 2000000.0,
      costPrice: 1200000.0,
      branchStocks: {'store_001': 1},
      category: 'Bàn',
    );
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();
    final inventoryRepo = _InMemoryInventoryRepository();

    await orderRepo.create(completedOrder);
    await productRepo.upsert(limitedProduct);
    await customerRepo.upsert(initialCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
        customerRemoteDataSourceProvider
            .overrideWithValue(_FakeCustomerRemoteDataSource()),
        productListProvider.overrideWith((ref) => Stream.value([limitedProduct])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([completedOrder])),
        customerListNotifierProvider.overrideWith(
            () => _FakeCustomerListNotifier([initialCustomer])),
        cancelInvoiceUseCaseProvider.overrideWithValue(
          CancelInvoiceUseCase(
            orderRepository: orderRepo,
            productRepository: productRepo,
            inventoryRepository: inventoryRepo,
            customerRepository: customerRepo,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Open sheet and tap "Sửa hóa đơn"
    await tester.tap(find.text('Trần Thị B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_invoice_action_button')));
    await tester.pumpAndSettle();

    // 2. In POS cart, set quantity to 10 (exceeds 1 + 2 = 3)
    container.read(cartProvider.notifier).updateQuantity('prod_101', 10);
    await tester.pumpAndSettle();

    // 3. Tap "Thanh toán" on POS Checkout to open POS Payment Page
    final checkoutBtn = find.widgetWithText(ElevatedButton, 'Thanh toán');
    await tester.tap(checkoutBtn);
    await tester.pumpAndSettle();

    // 4. Tap "Thanh toán" on POS Payment Page
    final payBtn = find.widgetWithText(FilledButton, 'Thanh toán');
    await tester.tap(payBtn);
    await tester.pumpAndSettle();

    // 5. Verify error SnackBar was shown
    expect(find.textContaining('Không đủ hàng'), findsOneWidget);

    // 6. Crucial: Original order MUST REMAIN COMPLETED and UNTOUCHED!
    final originalOrder = orderRepo.orders['HD013259']!;
    expect(originalOrder.status, 'completed');
    expect(originalOrder.isCancelled, isFalse);
    expect(orderRepo.orders.containsKey('HD013259_01'), isFalse);
  });

  testWidgets(
      'Adversarial: Partially returned order hides Sửa hóa đơn button in InvoicesPage',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();

    // Partially returned order: activeQuantity = 1, returnedQuantity = 1
    final partiallyReturnedOrder = completedOrder.copyWith(
      id: 'HD_PARTIAL_RET',
      items: [
        completedOrder.items.first.copyWith(
          quantity: 2,
          returnedQuantity: 1,
        ),
      ],
    );

    await orderRepo.create(partiallyReturnedOrder);
    await productRepo.upsert(product1);
    await customerRepo.upsert(initialCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        productListProvider.overrideWith((ref) => Stream.value([product1])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([partiallyReturnedOrder])),
        customerListNotifierProvider.overrideWith(
            () => _FakeCustomerListNotifier([initialCustomer])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap order to open details sheet
    await tester.tap(find.text('Trần Thị B'));
    await tester.pumpAndSettle();

    // Verify Sửa hóa đơn action button is NOT shown for partially returned order
    expect(find.byKey(const Key('edit_invoice_action_button')), findsNothing);
    // Return action button is still available to return remaining items
    expect(find.byKey(const Key('return_order_action_button')), findsOneWidget);
  });

  testWidgets(
      'Adversarial: Editing invoice with Combo product whose component has 0 warehouse stock succeeds via stock replenishment',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();
    final inventoryRepo = _InMemoryInventoryRepository();

    // Component product has 0 stock in store_001
    const componentProduct = Product(
      id: 'comp_cpu_01',
      name: 'CPU Intel Core i5',
      code: 'CPU01',
      price: 3000000.0,
      costPrice: 2500000.0,
      branchStocks: {'store_001': 0},
      category: 'Linh kiện',
    );

    // Combo product composed of componentProduct
    const comboProduct = Product(
      id: 'combo_pc_01',
      name: 'PC Gaming Chiến Game',
      code: 'PC01',
      price: 5000000.0,
      costPrice: 4000000.0,
      branchStocks: {},
      category: 'Combo',
      isCombo: true,
      comboComponents: [
        ComboComponent(
          productId: 'comp_cpu_01',
          productCode: 'CPU01',
          productName: 'CPU Intel Core i5',
          quantity: 1,
        ),
      ],
    );

    final comboOrder = Order(
      id: 'HD_COMBO_100',
      customerId: 'cust_100',
      customerName: 'Trần Thị B',
      customerPhone: '0988776655',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      items: [
        OrderItem(
          productId: 'combo_pc_01',
          productName: 'PC Gaming Chiến Game',
          quantity: 1,
          price: 5000000.0,
          originalPrice: 5000000.0,
          warrantyMonths: 12,
          purchaseDate: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ],
      total: 5000000.0,
      discount: 0.0,
      status: 'completed',
      amountPaid: 5000000.0,
      debtAmount: 0.0,
      storeId: 'store_001',
    );

    await orderRepo.create(comboOrder);
    await productRepo.upsert(componentProduct);
    await productRepo.upsert(comboProduct);
    await customerRepo.upsert(initialCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
        customerRemoteDataSourceProvider
            .overrideWithValue(_FakeCustomerRemoteDataSource()),
        productListProvider.overrideWith(
            (ref) => Stream.value([componentProduct, comboProduct])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([comboOrder])),
        customerListNotifierProvider.overrideWith(
            () => _FakeCustomerListNotifier([initialCustomer])),
        cancelInvoiceUseCaseProvider.overrideWithValue(
          CancelInvoiceUseCase(
            orderRepository: orderRepo,
            productRepository: productRepo,
            inventoryRepository: inventoryRepo,
            customerRepository: customerRepo,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Open sheet and tap "Sửa hóa đơn"
    await tester.tap(find.text('Trần Thị B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_invoice_action_button')));
    await tester.pumpAndSettle();

    // 2. On POS Checkout, proceed to Payment
    final checkoutBtn = find.widgetWithText(ElevatedButton, 'Thanh toán');
    await tester.tap(checkoutBtn);
    await tester.pumpAndSettle();

    // 3. On POS Payment Page, tap "Thanh toán"
    final payBtn = find.widgetWithText(FilledButton, 'Thanh toán');
    await tester.tap(payBtn);
    await tester.pumpAndSettle();

    // 4. Verify checkout was NOT blocked by 0 component stock because old order stock was restored!
    expect(find.text('Thanh toán thành công'), findsOneWidget);

    // 5. Verify old order was cancelled with proper versioned link
    final oldOrder = orderRepo.orders['HD_COMBO_100']!;
    expect(oldOrder.status, 'cancelled');
    final newOrder = orderRepo.orders.values.firstWhere((o) => o.id != 'HD_COMBO_100');
    expect(oldOrder.cancelReason, 'Đã sửa thành ${newOrder.id}');
    expect(newOrder.id.contains('.'), isFalse);
    expect(newOrder.status, 'completed');
    expect(newOrder.total, 5000000.0);

    // 7. Verify component product stock was restored (+1) and re-deducted (-1), ending at 0
    final updatedComp = (await productRepo.fetchById('comp_cpu_01'))!;
    expect(updatedComp.stockInBranch('store_001'), 0);
  });

  testWidgets(
      'Adversarial: Editing invoice paid with partial debt reverses old debt and updates customer debt correctly',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();
    final inventoryRepo = _InMemoryInventoryRepository();

    // Initial customer with 500.000đ initial debt
    const debtCustomer = Customer(
      id: 'cust_debt',
      name: 'Phạm Văn Nợ',
      phone: '0911223344',
      email: 'debt@example.com',
      address: 'Hà Nội',
      purchases: [],
      currentDebt: 500000.0,
      totalSales: 1000000.0,
      netSales: 1000000.0,
    );

    // Old order: Total 1.000.000đ, paid 500.000đ, debt 500.000đ
    final debtOrder = Order(
      id: 'HD_DEBT_01',
      customerId: 'cust_debt',
      customerName: 'Phạm Văn Nợ',
      customerPhone: '0911223344',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      items: [
        OrderItem(
          productId: 'prod_101',
          productName: 'Bàn Trà Sofa Mặt Đá',
          quantity: 1,
          price: 1000000.0,
          originalPrice: 1000000.0,
          warrantyMonths: 12,
          purchaseDate: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ],
      total: 1000000.0,
      discount: 0.0,
      status: 'completed',
      amountPaid: 500000.0,
      debtAmount: 500000.0,
      storeId: 'store_001',
    );

    await orderRepo.create(debtOrder);
    await productRepo.upsert(product1);
    await customerRepo.upsert(debtCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
        customerRemoteDataSourceProvider
            .overrideWithValue(_FakeCustomerRemoteDataSource()),
        productListProvider.overrideWith((ref) => Stream.value([product1])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([debtOrder])),
        customerListNotifierProvider.overrideWith(
            () => _FakeCustomerListNotifier([debtCustomer])),
        cancelInvoiceUseCaseProvider.overrideWithValue(
          CancelInvoiceUseCase(
            orderRepository: orderRepo,
            productRepository: productRepo,
            inventoryRepository: inventoryRepo,
            customerRepository: customerRepo,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Open sheet and tap "Sửa hóa đơn"
    await tester.tap(find.text('Phạm Văn Nợ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_invoice_action_button')));
    await tester.pumpAndSettle();

    // 2. On POS Checkout, proceed to Payment
    final checkoutBtn = find.widgetWithText(ElevatedButton, 'Thanh toán');
    await tester.tap(checkoutBtn);
    await tester.pumpAndSettle();

    // 3. In Payment page, user pays 2.000.000 (full payment of 2x product1 = 3.600.000đ? No, 1 item = 1.800.000đ)
    // Pay full so debt for new order is 0
    final payBtn = find.widgetWithText(FilledButton, 'Thanh toán');
    await tester.tap(payBtn);
    await tester.pumpAndSettle();

    // 4. Verify checkout success
    expect(find.text('Thanh toán thành công'), findsOneWidget);

    // 5. Customer debt calculation check:
    // Old debt (500.000đ) was reversed by cancelUseCase: 500.000 - 500.000 = 0đ!
    // New order: Total = 1.000.000đ, payment = 0đ paid by default.
    // So new debt becomes 0 (reversed) + 1.000.000đ = 1.000.000đ!
    // Old 500.000đ was NOT double-counted with the new debt!
    final updatedCustomer = (await customerRepo.fetchById('cust_debt'))!;
    expect(updatedCustomer.displayCurrentDebt, 1000000.0);
  });

  testWidgets(
      'Adversarial: Customer with empty phone does not overwrite originalOrder.customerPhone on payment',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();
    final inventoryRepo = _InMemoryInventoryRepository();

    // Customer with empty phone string
    const emptyPhoneCustomer = Customer(
      id: 'cust_empty_phone',
      name: 'Khách Không Số',
      phone: '',
      email: '',
      address: '',
      purchases: [],
    );

    // Old order that had customerPhone = '0933445566'
    final orderWithPhone = completedOrder.copyWith(
      id: 'HD_PHONE_01',
      customerId: 'cust_empty_phone',
      customerName: 'Khách Không Số',
      customerPhone: '0933445566',
    );

    await orderRepo.create(orderWithPhone);
    await productRepo.upsert(product1);
    await customerRepo.upsert(emptyPhoneCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
        customerRemoteDataSourceProvider
            .overrideWithValue(_FakeCustomerRemoteDataSource()),
        productListProvider.overrideWith((ref) => Stream.value([product1])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([orderWithPhone])),
        customerListNotifierProvider.overrideWith(
            () => _FakeCustomerListNotifier([emptyPhoneCustomer])),
        cancelInvoiceUseCaseProvider.overrideWithValue(
          CancelInvoiceUseCase(
            orderRepository: orderRepo,
            productRepository: productRepo,
            inventoryRepository: inventoryRepo,
            customerRepository: customerRepo,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Open sheet and tap "Sửa hóa đơn"
    await tester.tap(find.text('Khách Không Số'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_invoice_action_button')));
    await tester.pumpAndSettle();

    // 2. On POS Checkout, proceed to Payment
    final checkoutBtn = find.widgetWithText(ElevatedButton, 'Thanh toán');
    await tester.tap(checkoutBtn);
    await tester.pumpAndSettle();

    // 3. On POS Payment Page, tap "Thanh toán"
    final payBtn = find.widgetWithText(FilledButton, 'Thanh toán');
    await tester.tap(payBtn);
    await tester.pumpAndSettle();

    // 4. Verify checkout was successful
    expect(find.text('Thanh toán thành công'), findsOneWidget);

    // 5. Verify the replacement order retained the original order's phone number!
    final replacementOrder = orderRepo.orders.values.firstWhere((o) => o.id != 'HD_PHONE_01');
    expect(replacementOrder.id.contains('.'), isFalse);
    expect(replacementOrder.customerPhone, '0933445566');
  });

  testWidgets(
      'Adversarial: Switching customer to a different customer without phone does NOT bleed previous customer phone',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();
    final inventoryRepo = _InMemoryInventoryRepository();

    const customerA = Customer(
      id: 'cust_A',
      name: 'Khách A',
      phone: '0911223344',
      email: '',
      address: '',
      purchases: [],
    );

    const customerB = Customer(
      id: 'cust_B',
      name: 'Công ty B',
      phone: '',
      email: '',
      address: '',
      purchases: [],
    );

    final orderA = completedOrder.copyWith(
      id: 'HD_CUST_A',
      customerId: 'cust_A',
      customerName: 'Khách A',
      customerPhone: '0911223344',
    );

    await orderRepo.create(orderA);
    await productRepo.upsert(product1);
    await customerRepo.upsert(customerA);
    await customerRepo.upsert(customerB);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
        customerRemoteDataSourceProvider
            .overrideWithValue(_FakeCustomerRemoteDataSource()),
        productListProvider.overrideWith((ref) => Stream.value([product1])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([orderA])),
        customerListNotifierProvider
            .overrideWith(() => _FakeCustomerListNotifier([customerA, customerB])),
        cancelInvoiceUseCaseProvider.overrideWithValue(
          CancelInvoiceUseCase(
            orderRepository: orderRepo,
            productRepository: productRepo,
            inventoryRepository: inventoryRepo,
            customerRepository: customerRepo,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Open sheet and tap "Sửa hóa đơn"
    await tester.tap(find.text('Khách A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_invoice_action_button')));
    await tester.pumpAndSettle();

    // 2. Change customer to customerB on POS Checkout
    await tester.tap(find.text('Khách A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Công ty B'));
    await tester.pumpAndSettle();

    // 3. Proceed to payment and pay
    final checkoutBtn = find.widgetWithText(ElevatedButton, 'Thanh toán');
    await tester.tap(checkoutBtn);
    await tester.pumpAndSettle();

    final payBtn = find.widgetWithText(FilledButton, 'Thanh toán');
    await tester.tap(payBtn);
    await tester.pumpAndSettle();

    // 4. Verify replacement order belongs to Customer B and phone is null (not Customer A's phone!)
    final replacementOrder = orderRepo.orders.values.firstWhere((o) => o.id != 'HD_CUST_A');
    expect(replacementOrder.id.contains('.'), isFalse);
    expect(replacementOrder.customerId, 'cust_B');
    expect(replacementOrder.customerName, 'Công ty B');
    expect(replacementOrder.customerPhone, isNull);
  });

  testWidgets(
      'Editing invoice and modifying item note updates note in replacement order',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();
    final inventoryRepo = _InMemoryInventoryRepository();

    final orderWithInitialNote = completedOrder.copyWith(
      id: 'HD_NOTE_01',
      items: [
        OrderItem(
          productId: 'prod_101',
          productName: 'Màn hình Dell UltraSharp 27"',
          quantity: 1,
          price: 500000.0,
          originalPrice: 500000.0,
          note: 'Ghi chú ban đầu',
          warrantyMonths: 12,
          purchaseDate: DateTime.now(),
        ),
      ],
    );

    await orderRepo.create(orderWithInitialNote);
    await productRepo.upsert(product1);
    await customerRepo.upsert(initialCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
        customerRemoteDataSourceProvider
            .overrideWithValue(_FakeCustomerRemoteDataSource()),
        productListProvider.overrideWith((ref) => Stream.value([product1])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([orderWithInitialNote])),
        customerListNotifierProvider
            .overrideWith(() => _FakeCustomerListNotifier([initialCustomer])),
        cancelInvoiceUseCaseProvider.overrideWithValue(
          CancelInvoiceUseCase(
            orderRepository: orderRepo,
            productRepository: productRepo,
            inventoryRepository: inventoryRepo,
            customerRepository: customerRepo,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Open sheet and tap "Sửa hóa đơn"
    await tester.tap(find.text('Trần Thị B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_invoice_action_button')));
    await tester.pumpAndSettle();

    // 2. Tap to edit item details
    await tester.tap(find.text('Chạm để sửa giảm giá / ghi chú'));
    await tester.pumpAndSettle();

    // 3. Enter new note in edit item dialog
    final noteInput = find.widgetWithText(TextField, 'Nhập ghi chú (tối đa 300 ký tự)');
    expect(noteInput, findsOneWidget);
    await tester.enterText(noteInput, 'Ghi chú đã được cập nhật mới');
    await tester.pumpAndSettle();

    // 4. Tap Xong
    await tester.tap(find.widgetWithText(FilledButton, 'Xong'));
    await tester.pumpAndSettle();

    // 5. Proceed to payment and pay
    final checkoutBtn = find.widgetWithText(ElevatedButton, 'Thanh toán');
    await tester.tap(checkoutBtn);
    await tester.pumpAndSettle();

    final payBtn = find.widgetWithText(FilledButton, 'Thanh toán');
    await tester.tap(payBtn);
    await tester.pumpAndSettle();

    // 6. Verify replacement order has updated note!
    final replacementOrder = orderRepo.orders.values.firstWhere((o) => o.id != 'HD_NOTE_01');
    expect(replacementOrder.items.first.note, 'Ghi chú đã được cập nhật mới');
  });

  testWidgets(
      'Adversarial: Sửa hóa đơn checks repository fetchById and skips existing code to avoid collision',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();
    final inventoryRepo = _InMemoryInventoryRepository();

    final baseOrder = completedOrder.copyWith(id: 'HD013259');
    // Pre-populate HD013259_01 directly into repo, but NOT in this month stream
    final existingVersion1 = completedOrder.copyWith(id: 'HD013259_01');

    await orderRepo.create(baseOrder);
    await orderRepo.create(existingVersion1);
    await productRepo.upsert(product1);
    await customerRepo.upsert(initialCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
        customerRemoteDataSourceProvider
            .overrideWithValue(_FakeCustomerRemoteDataSource()),
        productListProvider.overrideWith((ref) => Stream.value([product1])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([baseOrder])),
        customerListNotifierProvider
            .overrideWith(() => _FakeCustomerListNotifier([initialCustomer])),
        cancelInvoiceUseCaseProvider.overrideWithValue(
          CancelInvoiceUseCase(
            orderRepository: orderRepo,
            productRepository: productRepo,
            inventoryRepository: inventoryRepo,
            customerRepository: customerRepo,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap order and edit
    await tester.tap(find.text('Trần Thị B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_invoice_action_button')));
    await tester.pumpAndSettle();

    // Verify it detected HD013259_01 in DB and skipped to HD013259_02!
    expect(container.read(activeOrderIdProvider), 'HD013259_02');
  });

  testWidgets(
      'Cancelled order shows "Tạo lại đơn" and "Khôi phục đơn" buttons, and "Tạo lại đơn" populates POS cart without linking editingOriginalOrder',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();

    final cancelledOrder = completedOrder.copyWith(
      id: 'HD000001',
      status: 'cancelled',
      cancelReason: 'Hủy nhầm',
      cancelledAt: DateTime.now(),
    );

    await orderRepo.create(cancelledOrder);
    await productRepo.upsert(product1);
    await customerRepo.upsert(initialCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        productListProvider.overrideWith((ref) => Stream.value([product1])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([cancelledOrder])),
        customerListNotifierProvider.overrideWith(
            () => _FakeCustomerListNotifier([initialCustomer])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch filter to "Đã hủy" tab
    await tester.tap(find.text('Đã hủy'));
    await tester.pumpAndSettle();

    // Tap cancelled order to open details
    await tester.tap(find.text('Trần Thị B'));
    await tester.pumpAndSettle();

    // Both action buttons must be visible
    final recreateBtn = find.byKey(const Key('recreate_cancelled_order_action_button'));
    final restoreBtn = find.byKey(const Key('restore_cancelled_order_action_button'));
    expect(recreateBtn, findsOneWidget);
    expect(restoreBtn, findsOneWidget);

    // Tap "Tạo lại đơn"
    await tester.tap(recreateBtn);
    await tester.pumpAndSettle();

    // Navigated to POS Checkout
    expect(find.byType(POSCheckoutPage), findsOneWidget);
    // New ID is generated as HD000002 (HD000001 + 1)
    expect(container.read(activeOrderIdProvider), 'HD000002');
    // Important: editingOriginalOrderProvider is null because cancelled order is not replaced
    expect(container.read(editingOriginalOrderProvider), isNull);
    // Cart is populated with the items
    expect(container.read(cartProvider).containsKey('prod_101'), isTrue);
  });

  testWidgets(
      'Cancelled order "Khôi phục đơn" prompts dialog and restores status to completed',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final orderRepo = _InMemoryOrderRepository();
    final productRepo = _InMemoryProductRepository();
    final customerRepo = _InMemoryCustomerRepository();
    final inventoryRepo = _InMemoryInventoryRepository();

    final cancelledOrder = completedOrder.copyWith(
      id: 'HD000001',
      status: 'cancelled',
      cancelReason: 'Hủy nhầm',
      cancelledAt: DateTime.now(),
    );

    await orderRepo.create(cancelledOrder);
    await productRepo.upsert(product1);
    await customerRepo.upsert(initialCustomer);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        orderRepositoryProvider.overrideWithValue(orderRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        customerRepositoryProvider.overrideWithValue(customerRepo),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
        productListProvider.overrideWith((ref) => Stream.value([product1])),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, range) => Stream.value([cancelledOrder])),
        customerListNotifierProvider.overrideWith(
            () => _FakeCustomerListNotifier([initialCustomer])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: InvoicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch filter to "Đã hủy" tab
    await tester.tap(find.text('Đã hủy'));
    await tester.pumpAndSettle();

    // Tap cancelled order to open details
    await tester.tap(find.text('Trần Thị B'));
    await tester.pumpAndSettle();

    final restoreBtn = find.byKey(const Key('restore_cancelled_order_action_button'));
    await tester.tap(restoreBtn);
    await tester.pumpAndSettle();

    // Confirm dialog appears
    expect(find.text('Khôi phục hóa đơn'), findsOneWidget);
    final confirmRestoreBtn = find.widgetWithText(FilledButton, 'Khôi phục');
    await tester.tap(confirmRestoreBtn);
    await tester.pumpAndSettle();

    // Verify order was restored to completed
    final restored = orderRepo.orders['HD000001']!;
    expect(restored.status, 'completed');
    expect(restored.cancelReason, isNull);
    expect(restored.cancelledAt, isNull);
  });
}
