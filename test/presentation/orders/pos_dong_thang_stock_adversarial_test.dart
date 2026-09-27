import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/orders/pages/pos_checkout_page.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';

final _transparentPixelPng = [
  0x89, 0x49, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
];

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => _transparentPixelPng.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(_transparentPixelPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockProductRepository implements ProductRepository {
  final Map<String, Product> products;

  _MockProductRepository(List<Product> list)
      : products = {for (final p in list) p.id: p};

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();
  @override
  Future<Product?> fetchById(String id) async => products[id];
  @override
  Future<void> updateStock(String id, int newStock) async {}
  @override
  Future<void> upsert(Product product) async {
    products[product.id] = product;
  }

  @override
  Future<void> delete(String id) async {
    products.remove(id);
  }

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());
}

class _MockOrderRepository implements OrderRepository {
  final List<Order> createdOrders = [];

  @override
  Future<void> create(Order order) async {
    createdOrders.add(order);
  }

  @override
  Future<void> update(Order order) async {}
  @override
  Future<void> delete(String orderId) async {}
  @override
  Future<Order?> fetchById(String orderId) async => null;
  @override
  Stream<List<Order>> watchAll() => Stream.value(createdOrders);
  @override
  Stream<List<Order>> watchByCustomer(String customerId) => Stream.value([]);
  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) =>
      Stream.value(createdOrders);
}

class _MockCustomerRepository implements CustomerRepository {
  final Map<String, Customer> customers = {};

  @override
  Future<Customer?> fetchById(String id) async => customers[id];
  @override
  Future<void> upsert(Customer customer) async {
    customers[customer.id] = customer;
  }

  @override
  Future<void> delete(String id) async {
    customers.remove(id);
  }

  @override
  Stream<List<Customer>> watchAll() => Stream.value(customers.values.toList());
}

class _MockInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> recordedTransactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async {
    recordedTransactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value([]);

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime startDate, DateTime endDate) =>
      Stream.value([]);
}

class _FakeCustomerListNotifier
    extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  @override
  Future<List<Customer>> build() async => [];

  @override
  Future<void> refresh() async {}
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

void main() {
  setUpAll(() {
    HttpOverrides.global = _MockHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  setUp(() {
    MultiCartNotifier.resetBranchCartsCache();
  });

  tearDown(() {
    MultiCartNotifier.resetBranchCartsCache();
  });

  const productDTInStock = Product(
    id: 'prod_dt_stock_3',
    name: 'Sản phẩm Đông Thắng Có Tồn Kho',
    code: 'DT01',
    price: 120000,
    costPrice: 70000,
    branchStocks: {
      'store_001': 3, // Đông Thắng có 3 cái
      'store_002': 0, // Thới Bình = 0
    },
    category: 'Gia dụng',
    allowSale: true,
  );

  const productDTOOutOfStock = Product(
    id: 'prod_dt_stock_0',
    name: 'Sản phẩm Đông Thắng Hết Hàng',
    code: 'DT02',
    price: 250000,
    costPrice: 150000,
    branchStocks: {
      'store_001': 0, // Đông Thắng = 0
      'store_002': 50, // Thới Bình = 50
    },
    category: 'Gia dụng',
    allowSale: true,
  );

  const productDualBranch = Product(
    id: 'prod_dual_branch',
    name: 'Sản phẩm Cả 2 Chi Nhánh Đều Có',
    code: 'DUAL01',
    price: 80000,
    costPrice: 45000,
    branchStocks: {
      'store_001': 2,
      'store_002': 10,
    },
    category: 'Điện máy',
    allowSale: true,
  );

  const dongThangCashier = UserAccount(
    username: 'cashier_dt',
    displayName: 'Thu ngân Đông Thắng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  group('Challenger 2 POS Stock Validation & Isolation Adversarial Suite', () {
    testWidgets(
      'Objective 1A: Cashier at Đông Thắng (store_001) adding item with stock > 0 succeeds and increments',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final mockProductRepo =
            _MockProductRepository([productDTInStock, productDTOOutOfStock]);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider
                  .overrideWith((ref) => _FakeAuthNotifier(dongThangCashier)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                    'store_002': 'Chi nhánh Thới Bình',
                  }),
              productRepositoryProvider.overrideWithValue(mockProductRepo),
              filterStorageServiceProvider
                  .overrideWithValue(FilterStorageService(prefs)),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('vi'),
              home: POSPage(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify productDTInStock is displayed with "Sắp hết" (stock 3 <= 5)
        expect(find.text('Sản phẩm Đông Thắng Có Tồn Kho'), findsOneWidget);
        expect(find.text('Sắp hết'), findsOneWidget);

        // Tap add button
        final addBtn = find.descendant(
          of: find.ancestor(
            of: find.text('Sản phẩm Đông Thắng Có Tồn Kho'),
            matching: find.byType(Container),
          ),
          matching: find.byIcon(Icons.add),
        ).first;

        await tester.tap(addBtn);
        await tester.pumpAndSettle();

        // Successfully added 1 item into cart
        expect(find.text('1'), findsWidgets);
        expect(find.textContaining('Giỏ hàng'), findsOneWidget);
      },
    );

    testWidgets(
      'Objective 1B: Cashier at Đông Thắng (store_001) adding item with stock == 0 is blocked with outOfStockAlert',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final mockProductRepo =
            _MockProductRepository([productDTOOutOfStock]);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider
                  .overrideWith((ref) => _FakeAuthNotifier(dongThangCashier)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                    'store_002': 'Chi nhánh Thới Bình',
                  }),
              productRepositoryProvider.overrideWithValue(mockProductRepo),
              filterStorageServiceProvider
                  .overrideWithValue(FilterStorageService(prefs)),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('vi'),
              home: POSPage(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify product displays "Hết hàng"
        expect(find.text('Sản phẩm Đông Thắng Hết Hàng'), findsOneWidget);
        expect(find.text('Hết hàng'), findsOneWidget);
        expect(find.text('Còn hàng'), findsNothing);

        // Tap add button on out-of-stock item
        final addBtn = find.descendant(
          of: find.ancestor(
            of: find.text('Sản phẩm Đông Thắng Hết Hàng'),
            matching: find.byType(Container),
          ),
          matching: find.byIcon(Icons.add),
        ).first;

        await tester.tap(addBtn);
        await tester.pump();

        // Verbatim check for l10n.outOfStockAlert
        expect(find.text('Sản phẩm đã hết hàng trong kho!'), findsOneWidget);

        // Verify cart is NOT populated
        expect(find.textContaining('Giỏ hàng'), findsNothing);
      },
    );

    testWidgets(
      'Objective 1C: Adding beyond available stock (qty > effectiveStock) is blocked with stockLimitAlert',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final mockProductRepo =
            _MockProductRepository([productDTInStock]); // stock at store_001 is 3

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider
                  .overrideWith((ref) => _FakeAuthNotifier(dongThangCashier)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                    'store_002': 'Chi nhánh Thới Bình',
                  }),
              productRepositoryProvider.overrideWithValue(mockProductRepo),
              filterStorageServiceProvider
                  .overrideWithValue(FilterStorageService(prefs)),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('vi'),
              home: POSPage(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. Add first item (qty = 1)
        final initialAddBtn = find.descendant(
          of: find.ancestor(
            of: find.text('Sản phẩm Đông Thắng Có Tồn Kho'),
            matching: find.byType(Container),
          ),
          matching: find.byIcon(Icons.add),
        ).first;

        await tester.tap(initialAddBtn);
        await tester.pumpAndSettle();
        expect(find.text('1'), findsWidgets);

        // 2. Tap '+' to reach qty = 2
        final plusBtn = find.byWidgetPredicate(
            (w) => w is Icon && w.icon == Icons.add && w.size == 14);
        expect(plusBtn, findsOneWidget);
        await tester.tap(plusBtn);
        await tester.pumpAndSettle();
        expect(find.text('2'), findsWidgets);

        // 3. Tap '+' to reach qty = 3 (stock limit)
        await tester.tap(plusBtn);
        await tester.pumpAndSettle();
        expect(find.text('3'), findsWidgets);

        // 4. Tap '+' a 4th time: Should hit limit and trigger stockLimitAlert
        await tester.tap(plusBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Verbatim alert verification
        expect(
          find.text('Không thể vượt quá số lượng tồn kho (3)!'),
          findsOneWidget,
        );

        // Quantity in cart must strictly stay at 3 (not 4)
        final qtyText = find.byWidgetPredicate((w) =>
            w is Text && w.data == '3' && w.style?.fontSize == 14);
        expect(qtyText, findsOneWidget);
      },
    );

    testWidgets(
      'Objective 1D: Branch isolation: Adding in Đông Thắng does NOT affect Thới Bình stock or cart',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final mockProductRepo = _MockProductRepository([productDualBranch]);

        const adminUser = UserAccount(
          username: 'admin_isolation',
          displayName: 'Quản Trị Viên',
          role: 'admin',
          storeId: 'store_001',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                    'store_002': 'Chi nhánh Thới Bình',
                  }),
              productRepositoryProvider.overrideWithValue(mockProductRepo),
              filterStorageServiceProvider
                  .overrideWithValue(FilterStorageService(prefs)),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('vi'),
              home: POSPage(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Đông Thắng has 2 in stock
        expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
        expect(find.text('Sản phẩm Cả 2 Chi Nhánh Đều Có'), findsOneWidget);

        // Add 2 items at Đông Thắng
        final addBtn = find.descendant(
          of: find.ancestor(
            of: find.text('Sản phẩm Cả 2 Chi Nhánh Đều Có'),
            matching: find.byType(Container),
          ),
          matching: find.byIcon(Icons.add),
        ).first;
        await tester.tap(addBtn);
        await tester.pumpAndSettle();

        final plusBtn = find.byWidgetPredicate(
            (w) => w is Icon && w.icon == Icons.add && w.size == 14);
        await tester.tap(plusBtn);
        await tester.pumpAndSettle();

        // Đông Thắng cart has 2 items
        expect(find.text('2'), findsWidgets);

        // Switch to Thới Bình (store_002) via bottom sheet ListTile
        await tester.tap(find.byKey(const Key('pos_branch_switcher_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Chi nhánh Thới Bình'));
        await tester.pumpAndSettle();

        // 1. Thới Bình cart is pristine: total items = 0, no cart summary bar
        expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
        expect(find.textContaining('Giỏ hàng'), findsNothing);
        expect(find.byIcon(Icons.remove), findsNothing);

        // 2. Thới Bình stock is 10: Can add up to 5 items without error
        final tbAddBtn = find.descendant(
          of: find.ancestor(
            of: find.text('Sản phẩm Cả 2 Chi Nhánh Đều Có'),
            matching: find.byType(Container),
          ),
          matching: find.byIcon(Icons.add),
        ).first;
        await tester.tap(tbAddBtn);
        await tester.pumpAndSettle();

        final tbPlusBtn = find.byWidgetPredicate(
            (w) => w is Icon && w.icon == Icons.add && w.size == 14);
        for (int i = 0; i < 4; i++) {
          await tester.tap(tbPlusBtn);
          await tester.pumpAndSettle();
        }
        // Thới Bình cart now has 5 items
        expect(find.text('5'), findsWidgets);

        // Switch back to Đông Thắng (store_001) via bottom sheet ListTile
        await tester.tap(find.byKey(const Key('pos_branch_switcher_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Chi nhánh Đông Thắng'));
        await tester.pumpAndSettle();

        // Đông Thắng cart is restored with its original 2 items!
        expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
        expect(find.text('2'), findsWidgets);

        // Đông Thắng stock limit (2) is still strictly preserved:
        // Trying to tap '+' at 2 triggers limit alert (2)!
        final dtPlusBtn = find.byWidgetPredicate(
            (w) => w is Icon && w.icon == Icons.add && w.size == 14);
        await tester.tap(dtPlusBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.text('Không thể vượt quá số lượng tồn kho (2)!'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Objective 1E: Checkout at Đông Thắng (store_001) deducts ONLY store_001 stock, leaves store_002 stock intact',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final mockProductRepo = _MockProductRepository([productDualBranch]);
        final mockOrderRepo = _MockOrderRepository();
        final mockCustomerRepo = _MockCustomerRepository();
        final mockInventoryRepo = _MockInventoryRepository();

        final container = ProviderContainer(
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(dongThangCashier)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            selectedPOSBranchProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
            productRepositoryProvider.overrideWithValue(mockProductRepo),
            orderRepositoryProvider.overrideWithValue(mockOrderRepo),
            customerRepositoryProvider.overrideWithValue(mockCustomerRepo),
            inventoryRepositoryProvider.overrideWithValue(mockInventoryRepo),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value([])),
            storePaymentConfigProvider.overrideWith((ref) =>
                const StorePaymentConfig(
                  storeId: 'store_001',
                  bankName: 'MBBank',
                  accountNo: '987654321',
                  accountName: 'KHANH DANG DONG THANG',
                )),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier()),
          ],
        );
        addTearDown(container.dispose);

        // Pre-populate cart with 2 units of productDualBranch
        container
            .read(cartProvider.notifier)
            .addToCart(productDualBranch, quantity: 2);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('vi'),
              home: POSCheckoutPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 2 units * 80,000 = 160,000 đ
        expect(find.text('160.000 đ'), findsWidgets);

        // Tap checkout
        final checkoutButton =
            find.widgetWithText(ElevatedButton, 'Thanh toán');
        await tester.tap(checkoutButton);
        await tester.pumpAndSettle();

        // 1. Order storeId is store_001
        expect(mockOrderRepo.createdOrders.length, equals(1));
        final order = mockOrderRepo.createdOrders.first;
        expect(order.storeId, equals('store_001'));
        expect(order.items.first.productId, equals('prod_dual_branch'));
        expect(order.items.first.quantity, equals(2));

        // 2. Product store_001 stock reduced from 2 -> 0; store_002 stock remains 10!
        final updatedProduct = mockProductRepo.products['prod_dual_branch']!;
        expect(updatedProduct.branchStocks['store_001'], equals(0));
        expect(updatedProduct.branchStocks['store_002'], equals(10));

        // 3. Inventory export transaction recorded under store_001
        expect(mockInventoryRepo.recordedTransactions.length, equals(1));
        final tx = mockInventoryRepo.recordedTransactions.first;
        expect(tx.storeId, equals('store_001'));
        expect(tx.quantity, equals(2));
        expect(tx.productId, equals('prod_dual_branch'));
      },
    );

    testWidgets(
      'Objective 1F: Combo product stock limit at Đông Thắng respects component stocks in store_001',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        const compA = Product(
          id: 'comp_a',
          name: 'Linh kiện A',
          code: 'CA',
          price: 50000,
          costPrice: 20000,
          branchStocks: {'store_001': 2, 'store_002': 20},
          category: 'Linh kiện',
          allowSale: true,
        );

        const compB = Product(
          id: 'comp_b',
          name: 'Linh kiện B',
          code: 'CB',
          price: 30000,
          costPrice: 15000,
          branchStocks: {'store_001': 5, 'store_002': 20},
          category: 'Linh kiện',
          allowSale: true,
        );

        const combo = Product(
          id: 'combo_ab',
          name: 'Gói Combo AB',
          code: 'CAB',
          price: 100000,
          costPrice: 50000,
          branchStocks: {'store_001': 99, 'store_002': 99},
          category: 'Combo',
          allowSale: true,
          isCombo: true,
          comboComponents: [
            ComboComponent(productId: 'comp_a', productCode: 'CA', productName: 'Linh kiện A', quantity: 1),
            ComboComponent(productId: 'comp_b', productCode: 'CB', productName: 'Linh kiện B', quantity: 2),
          ],
        );

        // At store_001: comp_a allows 2 / 1 = 2 combos. comp_b allows 5 / 2 = 2 combos.
        // Effective combo stock = 2.
        final mockProductRepo = _MockProductRepository([compA, compB, combo]);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider
                  .overrideWith((ref) => _FakeAuthNotifier(dongThangCashier)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                    'store_002': 'Chi nhánh Thới Bình',
                  }),
              productRepositoryProvider.overrideWithValue(mockProductRepo),
              filterStorageServiceProvider
                  .overrideWithValue(FilterStorageService(prefs)),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('vi'),
              home: POSPage(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Combo badge is "Còn 2"
        expect(find.text('Gói Combo AB'), findsOneWidget);
        expect(find.text('COMBO'), findsOneWidget);

        // Add 1st combo
        final comboAddBtn = find.descendant(
          of: find.ancestor(
            of: find.text('Gói Combo AB'),
            matching: find.byType(Container),
          ),
          matching: find.byIcon(Icons.add),
        ).first;

        await tester.tap(comboAddBtn);
        await tester.pumpAndSettle();

        // Add 2nd combo (hits max stock 2)
        final plusBtn = find.byWidgetPredicate(
            (w) => w is Icon && w.icon == Icons.add && w.size == 14);
        await tester.tap(plusBtn);
        await tester.pumpAndSettle();
        expect(find.text('2'), findsWidgets);

        // Attempt to add 3rd combo -> blocked with stockLimitAlert(2)!
        await tester.tap(plusBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.text('Không thể vượt quá số lượng tồn kho (2)!'),
          findsOneWidget,
        );

        // Cart item quantity widget strictly stays at 2
        final cartQtyText = find.byWidgetPredicate((w) =>
            w is Text && w.data == '2' && w.style?.fontSize == 14);
        expect(cartQtyText, findsOneWidget);

        // And no cart item quantity widget with text '3' exists
        final cartQty3Text = find.byWidgetPredicate((w) =>
            w is Text && w.data == '3' && w.style?.fontSize == 14);
        expect(cartQty3Text, findsNothing);
      },
    );
  });
}
