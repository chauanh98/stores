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
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';

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

  _MockOrderRepository([List<Order>? initial]) {
    if (initial != null) createdOrders.addAll(initial);
  }

  @override
  Future<void> create(Order order) async {
    createdOrders.removeWhere((o) => o.id == order.id);
    createdOrders.add(order);
  }

  @override
  Future<void> update(Order order) async {
    createdOrders.removeWhere((o) => o.id == order.id);
    createdOrders.add(order);
  }

  @override
  Future<void> delete(String orderId) async {
    createdOrders.removeWhere((o) => o.id == orderId);
  }

  @override
  Future<Order?> fetchById(String orderId) async =>
      createdOrders.where((o) => o.id == orderId).firstOrNull;

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

const productSP2 = Product(
  id: 'prod_sp2',
  name: 'Trà sen túi lọc SP2',
  code: 'SP2',
  price: 45000,
  costPrice: 25000,
  branchStocks: {
    'store_001': 10,
    'store_002': 0,
  },
  category: 'Trà',
  allowSale: true,
);

const defaultPaymentConfig = StorePaymentConfig(
  storeId: 'store_002',
  bankName: 'Vietcombank',
  accountNo: '123456789',
  accountName: 'KHANH DANG STORE',
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

  group('SWE Reviewer Round 3 Adversarial Break Tests', () {
    testWidgets(
        'Scenario 1: Cross-Branch switching in POS with multi-item cart correctly identifies out-of-stock item, blocks payment, allows item deletion, and completes order under store_002',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final mockProductRepo =
          _MockProductRepository([productCF8, productSP2]);
      final mockOrderRepo = _MockOrderRepository();
      final mockCustomerRepo = _MockCustomerRepository();
      final mockInventoryRepo = _MockInventoryRepository();

      const adminUser = UserAccount(
        username: 'admin_test',
        displayName: 'Quản Trị Viên',
        role: 'admin',
        storeId: 'store_001',
      );

      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      late ProviderContainer containerRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
            accountsListProvider
                .overrideWith((ref) => Stream.value([adminUser])),
            productRepositoryProvider.overrideWithValue(mockProductRepo),
            orderRepositoryProvider.overrideWithValue(mockOrderRepo),
            customerRepositoryProvider.overrideWithValue(mockCustomerRepo),
            inventoryRepositoryProvider.overrideWithValue(mockInventoryRepo),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value([])),
            storePaymentConfigProvider
                .overrideWith((ref) => defaultPaymentConfig),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              containerRef = ProviderScope.containerOf(context);
              return const MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: Locale('vi'),
                home: POSPage(),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Initial active POS branch is store_001
      expect(containerRef.read(selectedPOSBranchProvider), equals('store_001'));

      // SP2 has stock=10 at store_001 ("Còn hàng"), CF8 has stock=0 at store_001 ("Hết hàng")
      expect(find.text('Trà sen túi lọc SP2'), findsOneWidget);
      expect(find.text('Cà phê rang xay CF8'), findsOneWidget);

      // Add SP2 to cart (quantity 1)
      final addSp2Btn = find.descendant(
        of: find.ancestor(
          of: find.text('Trà sen túi lọc SP2'),
          matching: find.byType(Container),
        ),
        matching: find.byIcon(Icons.add),
      ).first;
      await tester.tap(addSp2Btn);
      await tester.pumpAndSettle();

      // Verify cart has SP2
      expect(containerRef.read(cartProvider).containsKey('prod_sp2'), isTrue);

      // 2. Now Admin switches active branch to Chi nhánh Thới Bình (store_002)
      final branchSwitcher =
          find.byKey(const Key('pos_branch_switcher_button'));
      expect(branchSwitcher, findsOneWidget);
      await tester.tap(branchSwitcher);
      await tester.pumpAndSettle();

      // Select Chi nhánh Thới Bình in bottom sheet
      await tester.tap(find.text('Chi nhánh Thới Bình'));
      await tester.pumpAndSettle();

      // Verify branch changed to store_002
      expect(containerRef.read(selectedPOSBranchProvider), equals('store_002'));

      // Verify branch cart isolation: SP2 added at store_001 is NOT present in store_002 cart
      expect(containerRef.read(cartProvider).containsKey('prod_sp2'), isFalse);

      // At store_002, CF8 is "Còn hàng" (stock=209)
      // Add CF8 to cart
      final addCf8Btn = find.descendant(
        of: find.ancestor(
          of: find.text('Cà phê rang xay CF8'),
          matching: find.byType(Container),
        ),
        matching: find.byIcon(Icons.add),
      ).first;
      await tester.tap(addCf8Btn);
      await tester.pumpAndSettle();

      // Pre-existing draft or synced item SP2 (which has 0 stock at store_002) is present in the cart
      containerRef.read(cartProvider.notifier).addToCart(productSP2);
      await tester.pumpAndSettle();

      // Wait for any switch-branch SnackBar to dismiss
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // 3. Tap "Xong" to navigate to POSCheckoutPage
      final doneBtn = find.widgetWithText(ElevatedButton, 'Xong');
      expect(doneBtn, findsOneWidget);
      await tester.tap(doneBtn);
      await tester.pumpAndSettle();

      // 4. Verify checkout shows branch stock status for both items:
      // SP2 has stock 0 at store_002 -> shows "Hết hàng tại chi nhánh này"
      expect(find.text('Hết hàng tại chi nhánh này'), findsOneWidget);

      // 5. Attempt payment while out-of-stock item is present -> Must be BLOCKED
      final checkoutBtn = find.widgetWithText(ElevatedButton, 'Thanh toán');
      expect(checkoutBtn, findsOneWidget);
      await tester.tap(checkoutBtn);
      await tester.pumpAndSettle();

      // Verify payment blocked with out of stock message
      expect(find.textContaining('Trà sen túi lọc SP2 - Sản phẩm đã hết hàng'),
          findsOneWidget);
      expect(mockOrderRepo.createdOrders.isEmpty, isTrue);

      // 6. Delete SP2 from cart using checkout item delete button
      final deleteButtons = find.byIcon(Icons.delete_outline);
      expect(deleteButtons, findsNWidgets(2)); // One for CF8, one for SP2
      await tester.tap(deleteButtons.last); // Delete SP2
      await tester.pumpAndSettle();

      // Out-of-stock warning is now gone
      expect(find.text('Hết hàng tại chi nhánh này'), findsNothing);
      expect(containerRef.read(cartProvider).containsKey('prod_sp2'), isFalse);
      expect(containerRef.read(cartProvider).containsKey('prod_cf8'), isTrue);

      // 7. Proceed with payment for CF8
      await tester.tap(checkoutBtn);
      await tester.pumpAndSettle();

      // Payment dialog appears
      expect(find.text('Thanh toán thành công'), findsOneWidget);

      // Verify order recorded under store_002
      expect(mockOrderRepo.createdOrders.length, equals(1));
      final savedOrder = mockOrderRepo.createdOrders.first;
      expect(savedOrder.storeId, equals('store_002'));
      expect(savedOrder.status, equals('completed'));
      expect(savedOrder.items.first.productId, equals('prod_cf8'));

      // Verify inventory deduction at store_002
      expect(mockProductRepo.lastUpserted?.branchStocks['store_002'],
          equals(208)); // 209 - 1 = 208
      expect(mockInventoryRepo.recordedTransactions.length, equals(1));
      expect(mockInventoryRepo.recordedTransactions.first.storeId,
          equals('store_002'));
      expect(mockInventoryRepo.recordedTransactions.first.productId,
          equals('prod_cf8'));
    });

    testWidgets(
        'Scenario 2: InvoicesPage default status "completed", hidden orange card, and reset button restores default completed state',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final sampleOrderCompleted = Order(
        id: 'HD_COMPLETED_01',
        customerId: 'cust_01',
        createdAt: DateTime.now(),
        items: [
          OrderItem(
            productId: 'prod_cf8',
            productName: 'CF8',
            quantity: 1,
            price: 65000,
            warrantyMonths: 12,
            purchaseDate: DateTime.now(),
          ),
        ],
        total: 65000,
        amountPaid: 65000,
        debtAmount: 0,
        status: 'completed',
        paymentMethod: 'cash',
        storeId: 'store_002',
      );

      final sampleOrderDraft = Order(
        id: 'HD_DRAFT_01',
        customerId: 'cust_01',
        createdAt: DateTime.now(),
        items: [
          OrderItem(
            productId: 'prod_cf8',
            productName: 'CF8',
            quantity: 1,
            price: 65000,
            warrantyMonths: 12,
            purchaseDate: DateTime.now(),
          ),
        ],
        total: 65000,
        amountPaid: 0,
        debtAmount: 0,
        status: 'draft',
        paymentMethod: 'cash',
        storeId: 'store_002',
      );

      const adminUser = UserAccount(
        username: 'admin',
        displayName: 'Quản trị viên',
        role: 'admin',
        storeId: 'store_001',
      );

      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
            accountsListProvider
                .overrideWith((ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value([sampleOrderCompleted, sampleOrderDraft])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: InvoicesPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Orange summary card is completely absent (R3)
      expect(find.byKey(const Key('invoices_total_summary_card')), findsNothing);
      expect(find.text('Doanh thu gộp:'), findsNothing);

      // 2. Default status is "Đã hoàn thành": only HD_COMPLETED_01 is visible (R2)
      expect(find.text('Mã đơn: HD_COMPLETED_01'), findsOneWidget);
      expect(find.text('Mã đơn: HD_DRAFT_01'), findsNothing);

      // 3. Switch filter to "Lưu tạm"
      await tester.tap(find.widgetWithText(ChoiceChip, 'Lưu tạm'));
      await tester.pumpAndSettle();

      expect(find.text('Mã đơn: HD_DRAFT_01'), findsOneWidget);
      expect(find.text('Mã đơn: HD_COMPLETED_01'), findsNothing);

      // Reset button is visible immediately adjacent to status chips
      final resetBtn = find.byKey(const Key('invoices_reset_filter_button'));
      expect(resetBtn, findsOneWidget);

      // 4. Tap reset button -> restores default status to "Đã hoàn thành" (R2)
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      expect(find.text('Mã đơn: HD_COMPLETED_01'), findsOneWidget);
      expect(find.text('Mã đơn: HD_DRAFT_01'), findsNothing);
      expect(find.byKey(const Key('invoices_reset_filter_button')), findsNothing);
    });
  });
}
