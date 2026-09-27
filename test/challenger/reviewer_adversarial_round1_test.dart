import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/presentation/customers/pages/customer_detail_page.dart';
import 'package:stores/presentation/customers/widgets/customer_list_tile.dart';
import 'package:stores/presentation/orders/pages/create_order_page.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

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

class _CountingCustomerListNotifier
    extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _CountingCustomerListNotifier(this._initialCustomers);

  final List<Customer> _initialCustomers;
  int buildCallCount = 0;

  @override
  Future<List<Customer>> build() async {
    buildCallCount++;
    return _initialCustomers;
  }

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_initialCustomers);
  }
}

class _FakeOrderRepository implements OrderRepository {
  Order? lastCreatedOrder;

  @override
  Future<void> create(Order order) async {
    lastCreatedOrder = order;
  }

  @override
  Future<void> update(Order order) async {}

  @override
  Future<void> delete(String orderId) async {}

  @override
  Future<Order?> fetchById(String orderId) async => null;

  @override
  Stream<List<Order>> watchAll() => Stream.value([]);

  @override
  Stream<List<Order>> watchByCustomer(String customerId) => Stream.value([]);

  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) =>
      Stream.value([]);
}

class _FakeCustomerRepository implements CustomerRepository {
  final Map<String, Customer> _store = {};

  void add(Customer c) => _store[c.id] = c;

  @override
  Future<Customer?> fetchById(String id) async => _store[id];

  @override
  Future<void> upsert(Customer customer) async {
    _store[customer.id] = customer;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Stream<List<Customer>> watchAll() => Stream.value(_store.values.toList());
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
  Size screenSize = const Size(400, 900),
  double textScaleFactor = 1.0,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: MediaQuery(
        data: MediaQueryData(
          size: screenSize,
          textScaler: TextScaler.linear(textScaleFactor),
        ),
        child: Material(child: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mockAdminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  final List<Product> sampleProducts = [
    const Product(
      id: 'SP001',
      code: 'SP001',
      name: 'Bàn ăn cao cấp gỗ tự nhiên nhập khẩu',
      price: 1500000.0,
      costPrice: 900000.0,
      branchStocks: {'store_001': 30, 'store_002': 20},
      category: 'Bàn ghế',
    ),
  ];

  group('Adversarial Reviewer: CustomerListTile N+1 Bandwidth Elimination', () {
    testWidgets(
        'Rendering CustomerListTile does not watch customerOrdersProvider or customerDebtTransactionsProvider',
        (tester) async {
      int orderProviderBuilds = 0;
      int debtProviderBuilds = 0;

      const testCustomer = Customer(
        id: 'cust_bandwidth_test',
        name: 'Nguyễn Văn Kiểm Thử',
        phone: '0988776655',
        email: 'test@example.com',
        address: 'Hà Nội',
        purchases: [],
        totalSales: 12500000.0,
        currentDebt: 3200000.0,
      );

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            customerOrdersProvider('cust_bandwidth_test').overrideWith((ref) {
              orderProviderBuilds++;
              return Stream.value([]);
            }),
            customerDebtTransactionsProvider('cust_bandwidth_test')
                .overrideWith((ref) {
              debtProviderBuilds++;
              return Stream.value([]);
            }),
          ],
          child: const CustomerListTile(customer: testCustomer),
        ),
      );
      await tester.pumpAndSettle();

      // Assert that values display directly from entity
      expect(find.text('Nguyễn Văn Kiểm Thử'), findsOneWidget);
      expect(find.text('12.500.000'), findsOneWidget);
      expect(find.textContaining('3.200.000'), findsOneWidget);

      // Verify ZERO subscriptions to per-item order and debt transaction providers
      expect(orderProviderBuilds, 0,
          reason:
              'CustomerListTile must NEVER subscribe to customerOrdersProvider');
      expect(debtProviderBuilds, 0,
          reason:
              'CustomerListTile must NEVER subscribe to customerDebtTransactionsProvider');
    });
  });

  group('Adversarial Reviewer: InvoicesPage Customer Catalog Decoupling & Navigation', () {
    testWidgets(
        'When orders have customerName embedded, customerListNotifierProvider is NEVER triggered',
        (tester) async {
      final notifier = _CountingCustomerListNotifier([]);

      final orders = [
        Order(
          id: 'HD_EMBEDDED_01',
          customerId: 'cust_emb_1',
          customerName: 'Công ty Cổ phần VinaTech',
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: 'SP001',
              productName: 'Bàn ăn',
              quantity: 1,
              price: 1500000,
              warrantyMonths: 12,
              purchaseDate: DateTime.now(),
            ),
          ],
          total: 1500000,
          amountPaid: 1500000,
          debtAmount: 0,
          status: 'completed',
          paymentMethod: 'cash',
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value(orders)),
            customerListNotifierProvider.overrideWith(() => notifier),
          ],
          child: const InvoicesPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Công ty Cổ phần VinaTech'), findsOneWidget);
      expect(notifier.buildCallCount, 0,
          reason:
              'customerListNotifierProvider must not be triggered when orders have embedded customerName');
    });

    testWidgets(
        'InvoicesPage: Invoice details sheet provides clickable customer row for embedded customerName and navigates to CustomerDetailPage',
        (tester) async {
      final orders = [
        Order(
          id: 'HD_EMBEDDED_NAV',
          customerId: 'cust_nav_01',
          customerName: 'Phạm Nhật Vượng',
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: 'SP001',
              productName: 'Bàn ăn',
              quantity: 1,
              price: 1500000,
              warrantyMonths: 12,
              purchaseDate: DateTime.now(),
            ),
          ],
          total: 1500000,
          amountPaid: 1000000,
          debtAmount: 500000,
          status: 'completed',
          paymentMethod: 'cash',
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value(orders)),
            customerListNotifierProvider
                .overrideWith(() => _CountingCustomerListNotifier([])),
            customerOrdersProvider('cust_nav_01')
                .overrideWith((ref) => Stream.value([])),
            customerDebtTransactionsProvider('cust_nav_01')
                .overrideWith((ref) => Stream.value([])),
          ],
          child: const InvoicesPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on invoice tile to open bottom sheet
      await tester.tap(find.text('Phạm Nhật Vượng'));
      await tester.pumpAndSettle();

      // Find customer detail row
      expect(find.text('Chi tiết hoá đơn'), findsOneWidget);
      final customerRowFinder = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(InkWell, 'Phạm Nhật Vượng'),
      );
      expect(customerRowFinder, findsOneWidget,
          reason: 'Customer name row must be clickable even when catalog was not eagerly loaded');

      // Tap customer name row to navigate to CustomerDetailPage
      await tester.tap(customerRowFinder);
      await tester.pumpAndSettle();

      // Assert CustomerDetailPage opened successfully
      expect(find.byType(CustomerDetailPage), findsOneWidget);
    });

    testWidgets(
        'InvoicesPage: Searching for "khách lẻ" matches walk_in and empty customerId orders',
        (tester) async {
      final orders = [
        Order(
          id: 'HD_WALKIN_01',
          customerId: 'walk_in',
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: 'SP001',
              productName: 'Bàn ăn',
              quantity: 1,
              price: 500000,
              warrantyMonths: 0,
              purchaseDate: DateTime.now(),
            ),
          ],
          total: 500000,
          amountPaid: 500000,
          debtAmount: 0,
          status: 'completed',
          paymentMethod: 'cash',
        ),
        Order(
          id: 'HD_CUSTOM_01',
          customerId: 'cust_specific',
          customerName: 'Trịnh Văn Quyết',
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: 'SP001',
              productName: 'Ghế',
              quantity: 1,
              price: 200000,
              warrantyMonths: 0,
              purchaseDate: DateTime.now(),
            ),
          ],
          total: 200000,
          amountPaid: 200000,
          debtAmount: 0,
          status: 'completed',
          paymentMethod: 'cash',
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value(orders)),
            customerListNotifierProvider
                .overrideWith(() => _CountingCustomerListNotifier([])),
          ],
          child: const InvoicesPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Enter search query
      await tester.enterText(find.byType(TextField).first, 'khách lẻ');
      await tester.pumpAndSettle();

      // Assert walk_in is found (via ID label "Mã đơn: HD_WALKIN_01") and specific customer is filtered out
      expect(find.textContaining('HD_WALKIN_01'), findsOneWidget);
      expect(find.textContaining('HD_CUSTOM_01'), findsNothing);
    });
  });

  group('Adversarial Reviewer: CreateOrderPage Embeds customerName', () {
    testWidgets('CreateOrderPage embeds customerName on created Order',
        (tester) async {
      final fakeOrderRepo = _FakeOrderRepository();
      final fakeCustomerRepo = _FakeCustomerRepository();

      const customer = Customer(
        id: 'KH_CREATE_001',
        name: 'Bà Nguyễn Thị Mai',
        phone: '0912345678',
        email: '',
        address: '',
        purchases: [],
        totalSales: 0,
        netSales: 0,
      );
      fakeCustomerRepo.add(customer);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            orderRepositoryProvider.overrideWithValue(fakeOrderRepo),
            customerRepositoryProvider.overrideWithValue(fakeCustomerRepo),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          ],
          child: const CreateOrderPage(selectedCustomerId: 'KH_CREATE_001'),
        ),
      );
      await tester.pumpAndSettle();

      // Enter product search in autocomplete field (first TextFormField in the form)
      final searchField = find.byType(TextFormField).first;
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'Bàn ăn');
      await tester.pumpAndSettle();

      // Tap suggestion
      await tester.tap(find.textContaining('Bàn ăn cao cấp').last);
      await tester.pumpAndSettle();

      // Save order
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // Verify created order has embedded customerName
      expect(fakeOrderRepo.lastCreatedOrder, isNotNull);
      expect(fakeOrderRepo.lastCreatedOrder!.customerId, 'KH_CREATE_001');
      expect(fakeOrderRepo.lastCreatedOrder!.customerName, 'Bà Nguyễn Thị Mai',
          reason: 'CreateOrderPage must embed customerName on Order entity');
    });
  });

  group('Adversarial Reviewer: UI Declutter & Zero RenderFlex Overflow on 320px & 1.25x scaling', () {
    const superLongProduct = Product(
      id: 'SP_EXTREME_9999',
      code: 'PROD-EXTREME-SUPER-LONG-CODE-999999999-ABC-XYZ-VN',
      name: 'Bộ bàn ghế phòng khách gỗ hương đá Nam Phi chạm rồng phượng tinh xảo mẫu 2026',
      price: 999999999.0,
      costPrice: 850000000.0,
      branchStocks: {'store_001': 50000, 'store_002': 49999},
      category: 'Nội thất phòng khách cao cấp',
    );

    const superLongCustomer = Customer(
      id: 'KH_LONG_NAME_9999',
      name: 'Công ty Cổ phần Xây dựng Dịch vụ Thương mại Quốc tế Hoàng Gia Việt Nam',
      phone: '09887766554433',
      email: 'hoanggiavietnam@corporation.com.vn',
      address: 'Số 9999 Đường Nguyễn Hữu Thọ, Phường Tân Phong, Quận 7, TP. Hồ Chí Minh',
      purchases: [],
      totalSales: 9999999999.0,
      currentDebt: 8888888888.0,
    );

    final extremeOrder = Order(
      id: 'HD_SUPER_LONG_ORDER_ID_2026_999999',
      customerId: superLongCustomer.id,
      customerName: superLongCustomer.name,
      createdAt: DateTime(2026, 9, 19, 15, 30),
      items: [
        OrderItem(
          productId: superLongProduct.id,
          productName: superLongProduct.name,
          quantity: 10,
          price: superLongProduct.price,
          warrantyMonths: 36,
          purchaseDate: DateTime(2026, 9, 19),
        ),
      ],
      total: 9999999999.0,
      amountPaid: 1111111111.0,
      debtAmount: 8888888888.0,
      status: 'completed',
      paymentMethod: 'transfer',
    );

    testWidgets('ProductTile renders with 0 overflow at 320px and 1.25x text scaling',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(320, 800),
          textScaleFactor: 1.25,
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            productListProvider
                .overrideWith((ref) => Stream.value([superLongProduct])),
          ],
          child: const ProductTile(product: superLongProduct),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'ProductTile must not overflow on 320px viewport with 1.25x scale');
    });

    testWidgets('CustomerListTile renders with 0 overflow at 320px and 1.25x text scaling',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(320, 800),
          textScaleFactor: 1.25,
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
          ],
          child: const CustomerListTile(customer: superLongCustomer),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'CustomerListTile must not overflow on 320px viewport with 1.25x scale');
    });

    testWidgets('InvoicesPage renders with 0 overflow at 320px and 1.25x text scaling',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(320, 800),
          textScaleFactor: 1.25,
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value([extremeOrder])),
          ],
          child: const InvoicesPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'InvoicesPage must not overflow on 320px viewport with 1.25x scale');
    });
  });
}
