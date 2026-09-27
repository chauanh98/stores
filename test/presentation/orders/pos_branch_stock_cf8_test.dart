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
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/presentation/orders/pages/pos_checkout_page.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';

// Mock HTTP client for widget tests with images
final _transparentPixelPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
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
  Product? lastUpserted;

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
    lastUpserted = product;
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

const productCF8 = Product(
  id: 'prod_cf8',
  name: 'Cà phê rang xay CF8',
  code: 'CF8',
  barcode: '893000000008',
  brand: 'Thới Bình Farm',
  price: 65000,
  costPrice: 40000,
  branchStocks: {
    'store_001': 0,
    'store_002': 209,
  },
  category: 'Cà phê',
  allowSale: true,
);

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

  group('R1: Branch-scoped inventory checks in POS (Product CF8)', () {
    testWidgets(
      'CF8 at Chi nhánh Thới Bình (store_002) displays "Còn hàng", allows adding to cart and increasing qty',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final mockProductRepo = _MockProductRepository([productCF8]);

        const thoiBinhStaff = UserAccount(
          username: 'staff_thoibinh',
          displayName: 'Nhân viên Thới Bình',
          role: 'nhanvien',
          storeId: 'store_002',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider
                  .overrideWith((ref) => _FakeAuthNotifier(thoiBinhStaff)),
              currentStoreIdProvider.overrideWith((ref) => 'store_002'),
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

        // 1. Verify AppBar shows 'Chi nhánh Thới Bình'
        expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);

        // 2. Verify Product CF8 is listed and badge is "Còn hàng"
        expect(find.text('Cà phê rang xay CF8'), findsOneWidget);
        expect(find.text('Còn hàng'), findsOneWidget);
        expect(find.text('Hết hàng'), findsNothing);

        // 3. Tap to add CF8 to cart via the add icon in the product container
        final addBtn = find.descendant(
          of: find.ancestor(
            of: find.text('Cà phê rang xay CF8'),
            matching: find.byType(Container),
          ),
          matching: find.byIcon(Icons.add),
        ).first;

        await tester.tap(addBtn);
        await tester.pumpAndSettle();

        // 4. Cart badge now shows 1
        expect(find.text('1'), findsWidgets);

        // 5. Tap the '+' button to increase quantity
        final plusBtn = find.byWidgetPredicate(
            (w) => w is Icon && w.icon == Icons.add && w.size == 14);
        expect(plusBtn, findsOneWidget);
        await tester.tap(plusBtn);
        await tester.pumpAndSettle();

        // Quantity should now be 2
        expect(find.text('2'), findsWidgets);
      },
    );

    testWidgets(
      'CF8 at Chi nhánh Đông Thắng (store_001) displays "Hết hàng", blocks adding to cart with out of stock alert',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final mockProductRepo = _MockProductRepository([productCF8]);

        const dongThangStaff = UserAccount(
          username: 'staff_dongthang',
          displayName: 'Nhân viên Đông Thắng',
          role: 'nhanvien',
          storeId: 'store_001',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider
                  .overrideWith((ref) => _FakeAuthNotifier(dongThangStaff)),
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

        // 1. Verify AppBar shows 'Chi nhánh Đông Thắng'
        expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);

        // 2. Verify Product CF8 is listed and badge is "Hết hàng"
        expect(find.text('Cà phê rang xay CF8'), findsOneWidget);
        expect(find.text('Hết hàng'), findsOneWidget);
        expect(find.text('Còn hàng'), findsNothing);

        // 3. Tap to add CF8 to cart via the add icon -> should show out of stock alert
        final addBtn = find.descendant(
          of: find.ancestor(
            of: find.text('Cà phê rang xay CF8'),
            matching: find.byType(Container),
          ),
          matching: find.byIcon(Icons.add),
        ).first;

        await tester.tap(addBtn);
        await tester.pump();

        // 4. Verify SnackBar alert appears
        expect(find.text('Sản phẩm đã hết hàng trong kho!'), findsOneWidget);
      },
    );

    testWidgets(
      'Admin switches branch from store_001 to store_002 in POS: CF8 updates from "Hết hàng" to "Còn hàng" and can be added to cart',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final mockProductRepo = _MockProductRepository([productCF8]);

        const adminUser = UserAccount(
          username: 'admin',
          displayName: 'Quản trị viên',
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

        // Initially at store_001: badge is "Hết hàng"
        expect(find.text('Hết hàng'), findsOneWidget);
        expect(find.text('Còn hàng'), findsNothing);

        // Tap the branch switcher button in the AppBar
        final branchSwitcher =
            find.byKey(const Key('pos_branch_switcher_button'));
        expect(branchSwitcher, findsOneWidget);
        await tester.tap(branchSwitcher);
        await tester.pumpAndSettle();

        // Verify bottom sheet opened with available branches
        expect(find.text('Chọn chi nhánh làm việc'), findsOneWidget);
        expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);

        // Tap on 'Chi nhánh Thới Bình' in the modal bottom sheet
        await tester.tap(find.text('Chi nhánh Thới Bình'));
        await tester.pumpAndSettle();

        // Stock badge dynamically updates to "Còn hàng"
        expect(find.text('Còn hàng'), findsOneWidget);
        expect(find.text('Hết hàng'), findsNothing);

        // Tap on CF8 to add to cart
        final addBtn = find.descendant(
          of: find.ancestor(
            of: find.text('Cà phê rang xay CF8'),
            matching: find.byType(Container),
          ),
          matching: find.byIcon(Icons.add),
        ).first;
        await tester.tap(addBtn);
        await tester.pumpAndSettle();

        // Cart now has 1 item
        expect(find.text('1'), findsWidgets);
      },
    );

    testWidgets(
      'Checkout at Chi nhánh Thới Bình (store_002) records order under store_002 and deducts store_002 stock',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final mockProductRepo = _MockProductRepository([productCF8]);
        final mockOrderRepo = _MockOrderRepository();
        final mockCustomerRepo = _MockCustomerRepository();
        final mockInventoryRepo = _MockInventoryRepository();

        const supervisorUser = UserAccount(
          username: 'supervisor_tb',
          displayName: 'Giám sát Thới Bình',
          role: 'giamsat',
          storeId: 'store_002',
        );

        final container = ProviderContainer(
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
            selectedPOSBranchProvider.overrideWith((ref) => 'store_002'),
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
                  storeId: 'store_002',
                  bankName: 'Vietcombank',
                  accountNo: '123456789',
                  accountName: 'KHANH DANG STORE',
                )),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier()),
          ],
        );
        addTearDown(container.dispose);

        // Pre-populate cart with 2 items of CF8
        container.read(cartProvider.notifier).addToCart(productCF8, quantity: 2);

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

        // Verify total amount displayed for 2 items: 65,000 * 2 = 130,000
        expect(find.text('130.000 đ'), findsWidgets);

        // Tap on "Thanh toán" button
        final checkoutButton =
            find.widgetWithText(ElevatedButton, 'Thanh toán');
        expect(checkoutButton, findsOneWidget);
        await tester.tap(checkoutButton);
        await tester.pumpAndSettle();

        // Verify order created has storeId == 'store_002'
        expect(mockOrderRepo.createdOrders.length, equals(1));
        final createdOrder = mockOrderRepo.createdOrders.first;
        expect(createdOrder.storeId, equals('store_002'));
        expect(createdOrder.items.first.productId, equals('prod_cf8'));
        expect(createdOrder.items.first.quantity, equals(2));

        // Verify product in mockProductRepo had store_002 stock deducted by 2 (209 -> 207)
        final updatedProduct = mockProductRepo.products['prod_cf8']!;
        expect(updatedProduct.branchStocks['store_002'], equals(207));
        expect(updatedProduct.branchStocks['store_001'], equals(0));

        // Verify inventory export transaction recorded under store_002
        expect(mockInventoryRepo.recordedTransactions.length, equals(1));
        final tx = mockInventoryRepo.recordedTransactions.first;
        expect(tx.storeId, equals('store_002'));
        expect(tx.quantity, equals(2));
        expect(tx.productId, equals('prod_cf8'));
      },
    );
  });
}
