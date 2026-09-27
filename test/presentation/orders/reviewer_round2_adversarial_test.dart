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
import 'package:stores/presentation/orders/pages/pos_checkout_page.dart';
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

  group('SWE Reviewer Round 2 Adversarial Verification', () {
    testWidgets(
        '1. Resuming draft from InvoicesPage syncs selectedPOSBranch to draft storeId and retains discount and note',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final draftOrder = Order(
        id: 'HD_DRAFT_TB_001',
        customerId: 'cust_tb',
        customerName: 'Khách hàng Thới Bình',
        createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
        items: [
          OrderItem(
            productId: 'prod_cf8',
            productName: 'Cà phê rang xay CF8',
            quantity: 2,
            price: 65000,
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 9, 23),
          ),
        ],
        total: 130000,
        discount: 10000,
        status: 'draft',
        amountPaid: 0,
        debtAmount: 0,
        paymentMethod: 'cash',
        storeId: 'store_002',
        note: 'Đơn giao Thới Bình',
      );

      const customer = Customer(
        id: 'cust_tb',
        name: 'Khách hàng Thới Bình',
        phone: '0912345678',
        email: '',
        address: 'Huyện Thới Bình, Cà Mau',
        purchases: [],
      );

      final mockProductRepo = _MockProductRepository([productCF8]);
      final mockOrderRepo = _MockOrderRepository([draftOrder]);
      final mockCustomerRepo = _MockCustomerRepository();
      mockCustomerRepo.customers[customer.id] = customer;
      final mockInventoryRepo = _MockInventoryRepository();

      const adminUser = UserAccount(
        username: 'admin',
        displayName: 'Quản trị viên',
        role: 'admin',
        storeId: 'store_001',
      );

      tester.view.physicalSize = const Size(1000, 1600);
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
            accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value([draftOrder])),
            productRepositoryProvider.overrideWithValue(mockProductRepo),
            orderRepositoryProvider.overrideWithValue(mockOrderRepo),
            customerRepositoryProvider.overrideWithValue(mockCustomerRepo),
            inventoryRepositoryProvider.overrideWithValue(mockInventoryRepo),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier([customer])),
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
                home: InvoicesPage(),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially POS branch is store_001
      expect(containerRef.read(selectedPOSBranchProvider), equals('store_001'));

      // Switch status filter to 'Lưu tạm' to view draft invoices
      await tester.tap(find.text('Lưu tạm'));
      await tester.pumpAndSettle();

      expect(find.textContaining('HD_DRAFT_TB_001'), findsOneWidget);

      // Tap on the invoice to open bottom sheet
      await tester.tap(find.textContaining('HD_DRAFT_TB_001'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Tiếp tục thanh toán'), findsOneWidget);

      // Tap 'Tiếp tục thanh toán'
      await tester.tap(find.textContaining('Tiếp tục thanh toán'));
      await tester.pumpAndSettle();

      // Verify POS branch was synchronized to draft's storeId (store_002)
      expect(containerRef.read(selectedPOSBranchProvider), equals('store_002'));

      // Verify POSCheckoutPage is shown with correct branch name in AppBar
      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);

      // Verify Customer was retained
      expect(find.text('Khách hàng Thới Bình'), findsOneWidget);

      // Verify discount (10000) was passed
      expect(find.textContaining('10'), findsWidgets);

      // Verify order note ('Đơn giao Thới Bình') was passed
      expect(find.text('Đơn giao Thới Bình'), findsOneWidget);

      // Verify CF8 is NOT marked out-of-stock because store_002 has 209 units
      expect(find.text('Hết hàng tại chi nhánh này'), findsNothing);

      // Tap 'Thanh toán'
      await tester.tap(find.widgetWithText(ElevatedButton, 'Thanh toán'));
      await tester.pumpAndSettle();

      // Complete order in confirmation dialog if any, or verify success dialog
      expect(find.text('Thanh toán thành công'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Về màn hình chính'));
      await tester.pumpAndSettle();

      // Verify created order has storeId == 'store_002'
      final completedOrder = mockOrderRepo.createdOrders
          .firstWhere((o) => o.id == 'HD_DRAFT_TB_001');
      expect(completedOrder.storeId, equals('store_002'));
      expect(completedOrder.status, equals('completed'));

      // Verify stock in store_002 was deducted (209 - 2 = 207)
      expect(mockProductRepo.lastUpserted?.branchStocks['store_002'], equals(207));
      // store_001 stock remains 0
      expect(mockProductRepo.lastUpserted?.branchStocks['store_001'], equals(0));
    });

    testWidgets(
        '2. Saving draft resets activeOrderIdProvider to prevent ID reuse in subsequent orders',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final mockProductRepo = _MockProductRepository([productCF8]);
      final mockOrderRepo = _MockOrderRepository();
      final mockInventoryRepo = _MockInventoryRepository();

      const adminUser = UserAccount(
        username: 'admin',
        displayName: 'Quản trị viên',
        role: 'admin',
        storeId: 'store_002',
      );

      late ProviderContainer containerRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
            productRepositoryProvider.overrideWithValue(mockProductRepo),
            orderRepositoryProvider.overrideWithValue(mockOrderRepo),
            inventoryRepositoryProvider.overrideWithValue(mockInventoryRepo),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
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
                home: POSCheckoutPage(),
              );
            },
          ),
        ),
      );

      // Add item to cart
      containerRef.read(cartProvider.notifier).addToCart(productCF8, quantity: 1);
      containerRef.read(activeOrderIdProvider.notifier).state = 'DRAFT_INITIAL';

      await tester.pumpAndSettle();

      // Tap 'Lưu tạm'
      await tester.tap(find.widgetWithText(OutlinedButton, 'Lưu tạm'));
      await tester.pumpAndSettle();

      // Confirm in dialog
      expect(
          find.text(
              'Bạn có muốn lưu đơn hàng này vào danh sách lưu tạm không?'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu tạm'));
      await tester.pumpAndSettle();

      expect(find.text('Đã lưu đơn nháp'), findsOneWidget);

      // Verify activeOrderIdProvider was reset to null
      expect(containerRef.read(activeOrderIdProvider), isNull);
    });

    testWidgets(
        '3. Checkout page displays branch stock warning and allows deleting out-of-stock items',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // SP2 has 0 stock at store_002
      final mockProductRepo = _MockProductRepository([productSP2]);
      final mockOrderRepo = _MockOrderRepository();
      final mockInventoryRepo = _MockInventoryRepository();

      const adminUser = UserAccount(
        username: 'admin',
        displayName: 'Quản trị viên',
        role: 'admin',
        storeId: 'store_002',
      );

      late ProviderContainer containerRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
            selectedPOSBranchProvider.overrideWith((ref) => 'store_002'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
            productRepositoryProvider.overrideWithValue(mockProductRepo),
            orderRepositoryProvider.overrideWithValue(mockOrderRepo),
            inventoryRepositoryProvider.overrideWithValue(mockInventoryRepo),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
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
                home: POSCheckoutPage(),
              );
            },
          ),
        ),
      );

      // Add SP2 to cart
      containerRef.read(cartProvider.notifier).addToCart(productSP2, quantity: 2);
      await tester.pumpAndSettle();

      // Verify out-of-stock warning badge is shown for SP2
      expect(find.text('Hết hàng tại chi nhánh này'), findsOneWidget);

      // Tap trash button next to SP2
      final deleteIcon = find.byTooltip('Xóa khỏi giỏ');
      expect(deleteIcon, findsOneWidget);

      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      // SP2 removed -> cart empty
      expect(find.text('Giỏ hàng đang trống'), findsOneWidget);

      // Checkout and Save Draft buttons are disabled
      final checkoutButton =
          tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Thanh toán'));
      expect(checkoutButton.onPressed, isNull);

      final saveDraftButton =
          tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Lưu tạm'));
      expect(saveDraftButton.onPressed, isNull);
    });

    testWidgets(
        '4. POSPage forwards activeTab customer, discount, and note to POSCheckoutPage',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final mockProductRepo = _MockProductRepository([productCF8]);
      final mockOrderRepo = _MockOrderRepository();
      final mockInventoryRepo = _MockInventoryRepository();

      const customer = Customer(
        id: 'c_regular',
        name: 'Trần Văn VIP',
        phone: '0988776655',
        email: '',
        address: 'Đông Thắng',
        purchases: [],
      );

      const adminUser = UserAccount(
        username: 'admin',
        displayName: 'Quản trị viên',
        role: 'admin',
        storeId: 'store_002',
      );

      late ProviderContainer containerRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
            selectedPOSBranchProvider.overrideWith((ref) => 'store_002'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
            productRepositoryProvider.overrideWithValue(mockProductRepo),
            orderRepositoryProvider.overrideWithValue(mockOrderRepo),
            inventoryRepositoryProvider.overrideWithValue(mockInventoryRepo),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([customer])),
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

      // Configure active tab with customer, discount, note and an item
      final multi = containerRef.read(multiCartProvider.notifier);
      multi.addToCart(productCF8, quantity: 1);
      multi.setCustomer(customer);
      multi.setDiscount(25000, false);
      multi.setNote('Khách quen giảm 25k');

      await tester.pumpAndSettle();

      // Tap 'Xong' button in bottom summary bar
      await tester.tap(find.widgetWithText(ElevatedButton, 'Xong'));
      await tester.pumpAndSettle();

      // Verify POSCheckoutPage has the customer
      expect(find.text('Trần Văn VIP'), findsOneWidget);

      // Verify discount is prefilled
      expect(find.textContaining('25'), findsWidgets);

      // Verify note is prefilled
      expect(find.text('Khách quen giảm 25k'), findsOneWidget);
    });

    test(
        '5. selectedPOSBranchProvider hydrates stored branch for supervisor from FilterStorageService',
        () async {
      SharedPreferences.setMockInitialValues({
        'selected_store_supervisor_01': 'store_002',
      });
      final prefs = await SharedPreferences.getInstance();

      const supervisor = UserAccount(
        username: 'supervisor_01',
        displayName: 'Giám sát chi nhánh',
        role: 'supervisor',
        storeId: 'store_001',
      );

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisor)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
        ],
      );
      addTearDown(container.dispose);

      // Should automatically load stored branch 'store_002' for supervisor
      expect(container.read(selectedPOSBranchProvider), equals('store_002'));
    });
  });
}
