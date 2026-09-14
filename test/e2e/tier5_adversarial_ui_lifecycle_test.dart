import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/inventory/inter_store_transfer_service.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/customers/pages/customer_debt_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

// =============================================================================
// TEST FAKES & REPOSITORIES
// =============================================================================

class _FakeProductRepository extends Fake implements ProductRepository {
  final List<Product> products;
  Product? lastUpsertedProduct;

  _FakeProductRepository([List<Product>? initial])
      : products = initial != null ? List<Product>.from(initial) : [];

  @override
  Stream<List<Product>> watchAll() => Stream.value(products);

  @override
  Future<List<Product>> fetchAll() async => products;

  @override
  Future<Product?> fetchById(String id) async {
    try {
      return products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> upsert(Product product) async {
    lastUpsertedProduct = product;
    final idx = products.indexWhere((p) => p.id == product.id);
    if (idx >= 0) {
      products[idx] = product;
    } else {
      products.add(product);
    }
  }
}

class _FakeInventoryRepository extends Fake implements InventoryRepository {
  final List<InventoryTransaction> recordedTransactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async {
    recordedTransactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(recordedTransactions.where((t) => t.productId == productId).toList());
}

class _FakeCustomerRepository extends Fake implements CustomerRepository {
  final List<Customer> customers;

  _FakeCustomerRepository([List<Customer>? initial])
      : customers = initial != null ? List<Customer>.from(initial) : [];

  @override
  Stream<List<Customer>> watchAll() => Stream.value(customers);

  @override
  Future<Customer?> fetchById(String id) async {
    try {
      return customers.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> upsert(Customer customer) async {
    final idx = customers.indexWhere((c) => c.id == customer.id);
    if (idx >= 0) {
      customers[idx] = customer;
    } else {
      customers.add(customer);
    }
  }

  @override
  Future<void> delete(String id) async {
    customers.removeWhere((c) => c.id == id);
  }
}

class _FakeOrderRepository extends Fake implements OrderRepository {
  final List<Order> orders;

  _FakeOrderRepository([List<Order>? initial])
      : orders = initial != null ? List<Order>.from(initial) : [];

  @override
  Stream<List<Order>> watchByCustomer(String customerId) =>
      Stream.value(orders.where((o) => o.customerId == customerId).toList());

  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) =>
      Stream.value(orders
          .where((o) => !o.createdAt.isBefore(start) && !o.createdAt.isAfter(end))
          .toList());
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

// =============================================================================
// TEST APP BUILDER
// =============================================================================

final _canonicalBranches = [
  const Branch('store_001', 'Chi nhánh Đông Thắng'),
  const Branch('store_002', 'Chi nhánh Thới Bình'),
];

const _adminUser = UserAccount(
  username: 'admin_test',
  displayName: 'Quản trị viên Hệ Thống',
  role: 'admin',
  storeId: 'store_001',
);

const _staffUser = UserAccount(
  username: 'staff_test',
  displayName: 'Nhân viên Bán hàng',
  role: 'nhanvien',
  storeId: 'store_001',
);

const _supervisorUser = UserAccount(
  username: 'supervisor_test',
  displayName: 'Giám sát Vùng',
  role: 'supervisor',
  storeId: 'store_001',
);

Widget _buildTestApp({
  required Widget child,
  String currentStoreId = 'store_001',
  UserAccount? currentUser = _adminUser,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    key: ValueKey('provider_scope_$currentStoreId'),
    overrides: [
      currentStoreIdProvider.overrideWith((ref) => currentStoreId),
      authProvider.overrideWith((ref) => _FakeAuthNotifier(currentUser)),
      branchesProvider.overrideWithValue(_canonicalBranches),
      productListProvider.overrideWith((ref) => Stream.value(const [])),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': 'Chi nhánh Đông Thắng',
            'store_002': 'Chi nhánh Thới Bình',
          }),
      ...overrides,
    ],
    child: MaterialApp(
      key: ValueKey('app_$currentStoreId'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: child,
    ),
  );
}

// =============================================================================
// MAIN TEST SUITE
// =============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('=== TIER 5: ADVERSARIAL UI, STATE & RIVERPOD LIFECYCLE TESTS ===', () {
    // -------------------------------------------------------------------------
    // GROUP 1: Riverpod Provider Lifecycle & AutoDispose Invalidation
    // -------------------------------------------------------------------------
    group('Group 1: Riverpod Provider Lifecycle & AutoDispose Invalidation', () {
      test('[LIFECYCLE-01] processedProductsProvider cleanly initializes, extracts categories/brands, computes metrics, and autoDisposes on teardown', () async {
        final products = [
          const Product(
            id: 'P01',
            name: 'Xi măng SCG',
            code: 'XMSC',
            price: 90000,
            costPrice: 70000,
            branchStocks: {'store_001': 10, 'store_002': 20},
            category: 'Xi măng',
            brand: 'SCG',
          ),
          const Product(
            id: 'P02',
            name: 'Gạch Đồng Tâm 60x60',
            code: 'GDT60',
            price: 250000,
            costPrice: 200000,
            branchStocks: {'store_001': 5, 'store_002': 0},
            category: 'Gạch ốp lát',
            brand: 'Đồng Tâm',
          ),
          const Product(
            id: 'P03',
            name: 'Combo Xây Dựng 1',
            code: 'CB01',
            price: 500000,
            costPrice: 350000,
            branchStocks: {'store_001': 2, 'store_002': 1},
            category: 'Combo',
            isCombo: true,
          ),
        ];

        final repo = _FakeProductRepository(products);
        final container = ProviderContainer(
          overrides: [
            productRepositoryProvider.overrideWithValue(repo),
          ],
        );

        // Listen to provider to initialize stream
        container.listen(processedProductsProvider, (_, __) {});
        await container.read(productListProvider.future);

        // Read processedProductsProvider
        final stateAsync = container.read(processedProductsProvider);
        expect(stateAsync.hasValue, isTrue);

        final data = stateAsync.value!;
        expect(data.totalProducts, equals(3));
        // Total stock = (10+20) + (5+0) + (2+1) = 30 + 5 + 3 = 38
        expect(data.totalStock, equals(38));
        // Total cost value = (30 * 70,000) + (5 * 200,000) + (Combo excluded: 0) = 2,100,000 + 1,000,000 = 3,100,000
        expect(data.totalCostValue, equals(3100000.0));
        // Categories & Brands extracted dynamically
        expect(data.categories, containsAll(['All', 'Xi măng', 'Gạch ốp lát', 'Combo']));
        expect(data.brands, containsAll(['SCG', 'Đồng Tâm']));

        // Teardown container
        container.dispose();
      });

      test('[LIFECYCLE-02] processedProductsProvider reacts synchronously to rapid fine-grained filter changes (search, category, brand, stockStatus, sort)', () async {
        final products = [
          const Product(
            id: 'A1',
            name: 'Sơn Dulux Trắng',
            code: 'SN01',
            price: 300000,
            costPrice: 220000,
            branchStocks: {'store_001': 100, 'store_002': 50},
            category: 'Sơn',
            brand: 'Dulux',
          ),
          const Product(
            id: 'A2',
            name: 'Sơn Maxilite Xám',
            code: 'SN02',
            price: 150000,
            costPrice: 100000,
            branchStocks: {'store_001': 0, 'store_002': 0},
            category: 'Sơn',
            brand: 'Maxilite',
          ),
          const Product(
            id: 'A3',
            name: 'Ống Nhựa Bình Minh phi 21',
            code: 'ON21',
            price: 45000,
            costPrice: 30000,
            branchStocks: {'store_001': 2, 'store_002': 1},
            category: 'Điện nước',
            brand: 'Bình Minh',
            minStock: 10,
          ),
        ];

        final container = ProviderContainer(
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value(products)),
          ],
        );

        container.listen(processedProductsProvider, (_, __) {});
        await container.read(productListProvider.future);

        // 1. Initial State
        var data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(3));

        // 2. Search Filter
        container.read(productSearchQueryProvider.notifier).state = 'Dulux';
        data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.id, equals('A1'));

        // Reset search
        container.read(productSearchQueryProvider.notifier).state = '';

        // 3. Category Filter
        container.read(productCategoryFilterProvider.notifier).state = 'Điện nước';
        data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.id, equals('A3'));

        // Reset category
        container.read(productCategoryFilterProvider.notifier).state = 'All';

        // 4. Stock Status Filter: Out of stock
        container.read(productStockStatusFilterProvider.notifier).state = StockStatus.outOfStock;
        data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.id, equals('A2'));

        // 5. Stock Status Filter: Below min stock
        container.read(productStockStatusFilterProvider.notifier).state = StockStatus.belowMinStock;
        data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.id, equals('A3'));

        // 6. Sort Option: Price Descending
        container.read(productStockStatusFilterProvider.notifier).state = StockStatus.all;
        container.read(productSortOptionProvider.notifier).state = ProductSortOption.priceDesc;
        data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.map((p) => p.id).toList(), equals(['A1', 'A2', 'A3']));

        container.dispose();
      });

      test('[LIFECYCLE-03] allStoresProductsProvider aggregates products across multiple store streams and closes inner subscriptions on dispose', () async {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(_adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            selectedStoreFilterProvider.overrideWith((ref) => null),
            selectedBranchesProvider.overrideWith((ref) => SelectedBranchesNotifier(_adminUser)),
          ],
        );

        final subscription = container.listen(allStoresProductsProvider, (prev, next) {});
        expect(subscription, isNotNull);

        // Teardown should close subscriptions without unhandled errors
        container.dispose();
      });

      test('[LIFECYCLE-04] processedCustomersProvider reactivity: scopes by staff store and date range filtering without retaining stale entries', () async {
        final todayStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
        final customers = [
          Customer(
            id: 'C1',
            name: 'Nguyễn Văn A',
            phone: '0901234567',
            email: 'a@gmail.com',
            address: 'Hà Nội',
            purchases: [],
            branch: 'store_001',
            createdAt: todayStr,
            currentDebt: 500000,
          ),
          Customer(
            id: 'C2',
            name: 'Trần Thị B',
            phone: '0912345678',
            email: 'b@gmail.com',
            address: 'Hồ Chí Minh',
            purchases: [],
            branch: 'store_002',
            createdAt: todayStr,
            currentDebt: 1000000,
          ),
          const Customer(
            id: 'C3',
            name: 'Lê Văn C',
            phone: '0987654321',
            email: 'c@gmail.com',
            address: 'Hà Nội',
            purchases: [],
            branch: 'store_001',
            createdAt: '01/01/2026 12:00',
            currentDebt: 0,
          ),
        ];

        final repo = _FakeCustomerRepository(customers);
        // Staff user assigned to store_001
        final container = ProviderContainer(
          overrides: [
            customerRepositoryProvider.overrideWithValue(repo),
            authProvider.overrideWith((ref) => _FakeAuthNotifier(_staffUser)),
          ],
        );

        // Wait for customer list to load
        final sub = container.listen(processedCustomersProvider, (_, __) {});
        await Future<void>.delayed(const Duration(milliseconds: 50));

        var data = container.read(processedCustomersProvider).value!;
        // Staff at store_001 should only see C1 and C3 (store_002 excluded)
        final staffCustomers = data.whereType<Customer>().toList();
        expect(staffCustomers.map((c) => c.id).toList(), containsAll(['C1', 'C3']));
        expect(staffCustomers.any((c) => c.id == 'C2'), isFalse);

        // Set date filter to today
        container.read(customerTimeRangeTypeProvider.notifier).state = OverviewTimeRange.today;
        data = container.read(processedCustomersProvider).value!;
        final todayCustomers = data.whereType<Customer>().toList();
        expect(todayCustomers.length, equals(1));
        expect(todayCustomers.first.id, equals('C1'));

        sub.close();
        container.dispose();
      });

      test('[LIFECYCLE-05] selectedBranchesProvider invariant enforcement: staff role prevents store selection, admin clearAll/toggle maintains at least 1 branch', () async {
        // 1. Staff user
        final staffContainer = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(_staffUser)),
          ],
        );

        final staffNotifier = staffContainer.read(selectedBranchesProvider.notifier);
        expect(staffContainer.read(selectedBranchesProvider), equals(['store_001']));
        // Staff cannot toggle or clear branches
        staffNotifier.toggleBranch('store_002');
        expect(staffContainer.read(selectedBranchesProvider), equals(['store_001']));
        staffNotifier.clearAll();
        expect(staffContainer.read(selectedBranchesProvider), equals(['store_001']));
        staffContainer.dispose();

        // 2. Admin user
        final adminContainer = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(_adminUser)),
          ],
        );

        final adminNotifier = adminContainer.read(selectedBranchesProvider.notifier);
        expect(adminContainer.read(selectedBranchesProvider), equals(['store_001', 'store_002']));

        // Toggle store_002 off -> store_001 remains
        adminNotifier.toggleBranch('store_002');
        expect(adminContainer.read(selectedBranchesProvider), equals(['store_001']));

        // Attempt to toggle last branch off -> must maintain at least 1 branch
        adminNotifier.toggleBranch('store_001');
        expect(adminContainer.read(selectedBranchesProvider), equals(['store_001']));

        // clearAll -> must fall back to first branch, never empty
        adminNotifier.selectAll();
        expect(adminContainer.read(selectedBranchesProvider).length, equals(2));
        adminNotifier.clearAll();
        expect(adminContainer.read(selectedBranchesProvider), equals(['store_001']));

        adminContainer.dispose();
      });
    });

    // -------------------------------------------------------------------------
    // GROUP 2: Dynamic Branch Stocks Mapping & Key Resilience
    // -------------------------------------------------------------------------
    group('Group 2: Dynamic Branch Stocks Mapping & Key Resilience', () {
      test('[MAPPING-06] ProductModel.fromMap resiliently parses malformed, string-encoded, negative, float, and nested stocks maps', () {
        final rawJson = {
          'id': 'PROD_MAPPING_1',
          'name': 'Gạch Block Xây Dựng',
          'code': 'GB01',
          'price': 12000,
          'costPrice': 8000,
          'branchStocks': {
            'store_001': '15', // string number
            'store_002': 25.7, // float number
            'store_003': -5, // negative number
            '': 100, // empty key
          },
          'category': 'Vật liệu cơ bản',
        };

        final model = ProductModel.fromMap(rawJson);
        expect(model.branchStocks['store_001'], equals(15));
        expect(model.branchStocks['store_002'], equals(25));
        expect(model.branchStocks['store_003'], equals(-5));
        expect(model.branchStocks.containsKey(''), isFalse);
        // Computed aggregate stock = 15 + 25 - 5 = 35
        expect(model.stock, equals(35));
      });

      test('[MAPPING-07] ProductModel.fromMap resolves complex legacy aliases (Đông Thắng, Thới Bình, ĐT, TB, branch_1, branch_2) alongside unmapped store IDs', () {
        final legacyMap = {
          'id': 'PROD_LEGACY',
          'name': 'Thép Hòa Phát phi 10',
          'code': 'THP10',
          'price': 18500,
          'stocks': {
            'Chi nhánh Đông Thắng': 40,
            'branch_2': 60,
            'Chi nhánh Cần Thơ': 10,
          },
        };

        final model = ProductModel.fromMap(legacyMap);
        expect(model.branchStocks['store_001'], equals(40));
        expect(model.branchStocks['store_002'], equals(60));
        expect(model.branchStocks['Chi nhánh Cần Thơ'], equals(10));
        expect(model.stock, equals(110));
      });

      test('[MAPPING-08] Product.stockInBranch handles case-insensitivity, unicode accents, and whitespace padding across standard and custom branch IDs', () {
        const product = Product(
          id: 'PROD_TEST',
          name: 'Sơn Expo Trắng',
          code: 'EXP01',
          price: 80000,
          costPrice: 55000,
          branchStocks: {
            'store_001': 50,
            'store_002': 75,
            'store_003': 30,
          },
          category: 'Sơn',
        );

        // Store 001 aliases & formatting
        expect(product.stockInBranch('store_001'), equals(50));
        expect(product.stockInBranch('STORE_001'), equals(50));
        expect(product.stockInBranch('  store_001  '), equals(50));
        expect(product.stockInBranch('branch_1'), equals(50));
        expect(product.stockInBranch('ĐT'), equals(50));
        expect(product.stockInBranch('dt'), equals(50));
        expect(product.stockInBranch('Chi nhánh Đông Thắng'), equals(50));
        expect(product.stockInBranch('dong thang'), equals(50));

        // Store 002 aliases & formatting
        expect(product.stockInBranch('store_002'), equals(75));
        expect(product.stockInBranch('branch_2'), equals(75));
        expect(product.stockInBranch('TB'), equals(75));
        expect(product.stockInBranch('tb'), equals(75));
        expect(product.stockInBranch('Chi nhánh Thới Bình'), equals(75));
        expect(product.stockInBranch('thoi binh'), equals(75));

        // Custom store & unknown store
        expect(product.stockInBranch('store_003'), equals(30));
        expect(product.stockInBranch('STORE_003'), equals(30));
        expect(product.stockInBranch('store_999'), equals(0));
        expect(product.stockInBranch(''), equals(0));
      });

      testWidgets('[MAPPING-09] ProductTile multi-branch badge formatting handles 0, 1, 2 canonical branches, custom store codes (CN3), and long names dynamically', (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const p1 = Product(
          id: 'T1',
          name: 'Cát Xây Dựng',
          code: 'CAT01',
          price: 350000,
          costPrice: 200000,
          branchStocks: {'store_001': 12, 'store_002': 18},
          category: 'Vật liệu',
        );

        const p2 = Product(
          id: 'T2',
          name: 'Đá 1x2',
          code: 'DA12',
          price: 450000,
          costPrice: 300000,
          branchStocks: {'store_001': 5},
          category: 'Vật liệu',
        );

        const p3 = Product(
          id: 'T3',
          name: 'Vữa Khô Trộn Sẵn',
          code: 'VK01',
          price: 65000,
          costPrice: 40000,
          branchStocks: {
            'store_001': 10,
            'store_002': 20,
            'store_003': 30,
            'Chi nhánh Cần Thơ': 40,
          },
          category: 'Vật liệu',
        );

        await tester.pumpWidget(_buildTestApp(
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value([p1, p2, p3])),
          ],
          child: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  ProductTile(product: p1),
                  ProductTile(product: p2),
                  ProductTile(product: p3),
                ],
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        // Check p1 badges: ĐT: 12 | TB: 18
        expect(find.text('ĐT: 12 | TB: 18'), findsOneWidget);
        // Check p2 badges: ĐT: 5
        expect(find.text('ĐT: 5'), findsOneWidget);
        // Check p3 badges: ĐT: 10 | TB: 20 | CN3: 30 | CT: 40
        expect(find.text('ĐT: 10 | TB: 20 | CN3: 30 | CT: 40'), findsOneWidget);
      });

      testWidgets('[MAPPING-10] ProductTile combo stock calculation with missing component products in product list degrades gracefully to 0 without throwing', (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const combo = Product(
          id: 'CB_ORPHAN',
          name: 'Combo Trọn Gói Nhà Tắm',
          code: 'CBPKG',
          price: 2500000,
          costPrice: 1800000,
          branchStocks: {'store_001': 5, 'store_002': 5},
          category: 'Combo',
          isCombo: true,
          comboComponents: [
            ComboComponent(productId: 'NON_EXISTENT_1', productCode: 'BC01', productName: 'Bồn cầu Viglacera', quantity: 1),
            ComboComponent(productId: 'NON_EXISTENT_2', productCode: 'LB01', productName: 'Lavabo Inax', quantity: 1),
          ],
        );

        await tester.pumpWidget(_buildTestApp(
          child: const Scaffold(body: ProductTile(product: combo)),
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value(const [])),
          ],
        ));
        await tester.pumpAndSettle();

        // Should display Tồn bộ: 0 and Out of Stock badge without crash
        expect(find.text('COMBO'), findsOneWidget);
        expect(find.text('Tồn bộ: 0'), findsOneWidget);
        expect(find.text('Hết hàng'), findsOneWidget);
      });
    });

    // -------------------------------------------------------------------------
    // GROUP 3: Scoped Stock Editing, Pre-fill Form Bindings & Direct Stock Ledger Audit in ProductDetailPage
    // -------------------------------------------------------------------------
    group('Group 3: Scoped Stock Editing & Direct Ledger Audit in ProductDetailPage', () {
      testWidgets('[MUTATION-11a] ProductDetailPage edit form pre-fills _stockController strictly with active store stock under store_001', (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const product = Product(
          id: 'TEST_PREFILL',
          name: 'Sơn Chống Thấm Kova',
          code: 'KV01',
          price: 450000,
          costPrice: 320000,
          branchStocks: {'store_001': 28, 'store_002': 14},
          category: 'Sơn',
        );

        await tester.pumpWidget(_buildTestApp(
          currentStoreId: 'store_001',
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value([product])),
            transactionsByProductProvider(product.id).overrideWith((ref) => Stream.value([])),
          ],
          child: const ProductDetailPage(product: product),
        ));
        await tester.pumpAndSettle();

        // Tap Edit button in AppBar
        await tester.tap(find.widgetWithText(TextButton, 'Sửa'));
        await tester.pumpAndSettle();

        // Check field label and pre-filled value for store_001
        expect(find.text('Số lượng tồn kho (Chi nhánh Đông Thắng)'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, '28'), findsOneWidget);
      });

      testWidgets('[MUTATION-11b] ProductDetailPage edit form pre-fills _stockController strictly with active store stock under store_002', (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const product = Product(
          id: 'TEST_PREFILL',
          name: 'Sơn Chống Thấm Kova',
          code: 'KV01',
          price: 450000,
          costPrice: 320000,
          branchStocks: {'store_001': 28, 'store_002': 14},
          category: 'Sơn',
        );

        await tester.pumpWidget(_buildTestApp(
          currentStoreId: 'store_002',
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value([product])),
            transactionsByProductProvider(product.id).overrideWith((ref) => Stream.value([])),
          ],
          child: const ProductDetailPage(product: product),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TextButton, 'Sửa'));
        await tester.pumpAndSettle();

        expect(find.text('Số lượng tồn kho (Chi nhánh Thới Bình)'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, '14'), findsOneWidget);
      });

      testWidgets('[MUTATION-12] ProductDetailPage direct stock edit (+) increments only active store stock and records structured positive audit transaction', (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const initialProduct = Product(
          id: 'PROD_AUDIT_INC',
          name: 'Keo Dán Gạch Weber',
          code: 'WB01',
          price: 150000,
          costPrice: 110000,
          branchStocks: {'store_001': 10, 'store_002': 20},
          category: 'Keo',
        );

        final productRepo = _FakeProductRepository([initialProduct]);
        final inventoryRepo = _FakeInventoryRepository();

        await tester.pumpWidget(_buildTestApp(
          currentStoreId: 'store_002', // Editing in store_002
          currentUser: _adminUser,
          overrides: [
            productRepositoryProvider.overrideWithValue(productRepo),
            inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
            productListProvider.overrideWith((ref) => Stream.value([initialProduct])),
            transactionsByProductProvider(initialProduct.id).overrideWith((ref) => Stream.value([])),
          ],
          child: const ProductDetailPage(product: initialProduct),
        ));
        await tester.pumpAndSettle();

        // Enter edit mode
        await tester.tap(find.widgetWithText(TextButton, 'Sửa'));
        await tester.pumpAndSettle();

        // Find stock input (currently 20) and update to 35 (+15)
        final stockFinder = find.widgetWithText(TextFormField, '20');
        expect(stockFinder, findsOneWidget);
        await tester.enterText(stockFinder, '35');
        await tester.pumpAndSettle();

        // Save
        await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
        await tester.pumpAndSettle();

        // Verify product repository updated
        expect(productRepo.lastUpsertedProduct, isNotNull);
        final updated = productRepo.lastUpsertedProduct!;
        expect(updated.branchStocks['store_001'], equals(10)); // Unchanged!
        expect(updated.branchStocks['store_002'], equals(35)); // Updated!
        expect(updated.stock, equals(45)); // Recomputed total

        // Verify inventory repository recorded structured audit transaction
        expect(inventoryRepo.recordedTransactions.length, equals(1));
        final tx = inventoryRepo.recordedTransactions.first;
        expect(tx.productId, equals('PROD_AUDIT_INC'));
        expect(tx.type, equals(TransactionType.inventoryAudit));
        expect(tx.storeId, equals('store_002'));
        expect(tx.quantity, equals(15));
        expect(tx.auditDifference, equals(15));
        expect(tx.isAuditNegative, isFalse);
        expect(tx.importPrice, equals(110000.0));
      });

      testWidgets('[MUTATION-13] ProductDetailPage direct stock edit (-) decrements only active store stock and records structured negative audit transaction', (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const initialProduct = Product(
          id: 'PROD_AUDIT_DEC',
          name: 'Ống Nhựa Tiền Phong',
          code: 'TP27',
          price: 55000,
          costPrice: 38000,
          branchStocks: {'store_001': 50, 'store_002': 30},
          category: 'Điện nước',
        );

        final productRepo = _FakeProductRepository([initialProduct]);
        final inventoryRepo = _FakeInventoryRepository();

        await tester.pumpWidget(_buildTestApp(
          currentStoreId: 'store_001', // Editing in store_001
          currentUser: _adminUser,
          overrides: [
            productRepositoryProvider.overrideWithValue(productRepo),
            inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
            productListProvider.overrideWith((ref) => Stream.value([initialProduct])),
            transactionsByProductProvider(initialProduct.id).overrideWith((ref) => Stream.value([])),
          ],
          child: const ProductDetailPage(product: initialProduct),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TextButton, 'Sửa'));
        await tester.pumpAndSettle();

        // Decrease stock from 50 to 30 (-20)
        final stockFinder = find.widgetWithText(TextFormField, '50');
        expect(stockFinder, findsOneWidget);
        await tester.enterText(stockFinder, '30');
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
        await tester.pumpAndSettle();

        // Verify Product update
        final updated = productRepo.lastUpsertedProduct!;
        expect(updated.branchStocks['store_001'], equals(30)); // Decremented!
        expect(updated.branchStocks['store_002'], equals(30)); // Unchanged!
        expect(updated.stock, equals(60));

        // Verify audit transaction
        expect(inventoryRepo.recordedTransactions.length, equals(1));
        final tx = inventoryRepo.recordedTransactions.first;
        expect(tx.productId, equals('PROD_AUDIT_DEC'));
        expect(tx.type, equals(TransactionType.inventoryAudit));
        expect(tx.storeId, equals('store_001'));
        expect(tx.quantity, equals(20)); // Absolute quantity
        expect(tx.auditDifference, equals(-20)); // Signed difference
        expect(tx.isAuditNegative, isTrue);
      });

      testWidgets('[MUTATION-14] ProductDetailPage direct stock edit with 0 change produces no spurious audit transaction', (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const initialProduct = Product(
          id: 'PROD_NO_CHANGE',
          name: 'Dây Điện Cadivi 2.5',
          code: 'CD25',
          price: 850000,
          costPrice: 700000,
          branchStocks: {'store_001': 100, 'store_002': 100},
          category: 'Điện',
        );

        final productRepo = _FakeProductRepository([initialProduct]);
        final inventoryRepo = _FakeInventoryRepository();

        await tester.pumpWidget(_buildTestApp(
          currentStoreId: 'store_001',
          currentUser: _adminUser,
          overrides: [
            productRepositoryProvider.overrideWithValue(productRepo),
            inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
            productListProvider.overrideWith((ref) => Stream.value([initialProduct])),
            transactionsByProductProvider(initialProduct.id).overrideWith((ref) => Stream.value([])),
          ],
          child: const ProductDetailPage(product: initialProduct),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TextButton, 'Sửa'));
        await tester.pumpAndSettle();

        // Change price only, stock remains 100
        final priceFinder = find.widgetWithText(TextFormField, '850000');
        await tester.enterText(priceFinder, '870000');
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
        await tester.pumpAndSettle();

        // Product updated
        expect(productRepo.lastUpsertedProduct?.price, equals(870000.0));
        // No audit transaction generated
        expect(inventoryRepo.recordedTransactions, isEmpty);
      });

      testWidgets('[MUTATION-15] ProductDetailPage direct stock edit on Combo product updates fields but bypasses inventory audit record', (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const combo = Product(
          id: 'CB_AUDIT',
          name: 'Bộ Thiết Bị Vệ Sinh',
          code: 'CBVS',
          price: 4500000,
          costPrice: 3200000,
          branchStocks: {'store_001': 5, 'store_002': 5},
          category: 'Combo',
          isCombo: true,
        );

        final productRepo = _FakeProductRepository([combo]);
        final inventoryRepo = _FakeInventoryRepository();

        await tester.pumpWidget(_buildTestApp(
          currentStoreId: 'store_001',
          currentUser: _adminUser,
          overrides: [
            productRepositoryProvider.overrideWithValue(productRepo),
            inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
            productListProvider.overrideWith((ref) => Stream.value([combo])),
            transactionsByProductProvider(combo.id).overrideWith((ref) => Stream.value([])),
          ],
          child: const ProductDetailPage(product: combo),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TextButton, 'Sửa'));
        await tester.pumpAndSettle();

        // On Combo products, the stock field is omitted/hidden, but price can be edited
        final priceFinder = find.widgetWithText(TextFormField, '4500000');
        expect(priceFinder, findsOneWidget);
        await tester.enterText(priceFinder, '4800000');
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
        await tester.pumpAndSettle();

        // Combo products update price and should not record direct stock audit transactions
        expect(productRepo.lastUpsertedProduct?.price, equals(4800000.0));
        expect(inventoryRepo.recordedTransactions, isEmpty);
      });

      testWidgets('[MUTATION-16] ProductDetailPage direct stock edit with invalid or empty input shows SnackBar validation error and blocks mutation', (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const initialProduct = Product(
          id: 'PROD_INVALID',
          name: 'Xi măng Hà Tiên',
          code: 'XMHT',
          price: 88000,
          costPrice: 72000,
          branchStocks: {'store_001': 50, 'store_002': 50},
          category: 'Xi măng',
        );

        final productRepo = _FakeProductRepository([initialProduct]);

        await tester.pumpWidget(_buildTestApp(
          currentStoreId: 'store_001',
          currentUser: _adminUser,
          overrides: [
            productRepositoryProvider.overrideWithValue(productRepo),
            productListProvider.overrideWith((ref) => Stream.value([initialProduct])),
            transactionsByProductProvider(initialProduct.id).overrideWith((ref) => Stream.value([])),
          ],
          child: const ProductDetailPage(product: initialProduct),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TextButton, 'Sửa'));
        await tester.pumpAndSettle();

        // Clear name field
        final nameFinder = find.widgetWithText(TextFormField, 'Xi măng Hà Tiên');
        await tester.enterText(nameFinder, '');
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
        await tester.pumpAndSettle();

        // Validation SnackBar displayed, upsert blocked
        expect(find.byType(SnackBar), findsOneWidget);
        expect(productRepo.lastUpsertedProduct, isNull);
      });
    });

    // -------------------------------------------------------------------------
    // GROUP 4: Rapid Store Switching & Cross-Store State Synchronization
    // -------------------------------------------------------------------------
    group('Group 4: Rapid Store Switching & Cross-Store State Synchronization', () {
      test('[SYNC-17] Rapid store switching sequentially updates currentStoreIdProvider and derived store providers without race conditions', () {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(_adminUser)),
          ],
        );

        expect(container.read(currentStoreIdProvider), equals('store_001'));

        // Rapid switching sequence
        container.read(selectedStoreIdProvider.notifier).state = 'store_002';
        expect(container.read(currentStoreIdProvider), equals('store_002'));

        container.read(selectedStoreIdProvider.notifier).state = 'store_001';
        expect(container.read(currentStoreIdProvider), equals('store_001'));

        container.read(selectedStoreIdProvider.notifier).state = 'store_003';
        expect(container.read(currentStoreIdProvider), equals('store_003'));

        container.read(selectedStoreIdProvider.notifier).state = null;
        expect(container.read(currentStoreIdProvider), equals('store_001'));

        container.dispose();
      });

      testWidgets('[SYNC-18] Switching active store before entering edit mode in ProductDetailPage dynamically updates pre-fill to new store stock', (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const product = Product(
          id: 'PROD_DYNAMIC_SWITCH',
          name: 'Bồn Nước Đại Thành 1000L',
          code: 'BN1000',
          price: 2800000,
          costPrice: 2100000,
          branchStocks: {'store_001': 8, 'store_002': 19},
          category: 'Bồn nước',
        );

        // Store 002
        await tester.pumpWidget(_buildTestApp(
          currentStoreId: 'store_002',
          currentUser: _adminUser,
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value([product])),
            transactionsByProductProvider(product.id).overrideWith((ref) => Stream.value([])),
          ],
          child: const ProductDetailPage(key: ValueKey('store_002_test'), product: product),
        ));
        await tester.pumpAndSettle();

        // Open edit
        await tester.tap(find.widgetWithText(TextButton, 'Sửa'));
        await tester.pumpAndSettle();

        // Pre-fill must be 19 for store_002
        expect(find.widgetWithText(TextFormField, '19'), findsOneWidget);
        expect(find.text('Số lượng tồn kho (Chi nhánh Thới Bình)'), findsOneWidget);
      });

      testWidgets('[SYNC-19] CustomerDebtPage combines order invoices and debt receipts accurately and updates on customer change', (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const customer = Customer(
          id: 'CUST_DEBT_01',
          name: 'Công ty Xây dựng Minh Phát',
          phone: '0933445566',
          email: 'minhphat@gmail.com',
          address: 'Cần Thơ',
          purchases: [],
          branch: 'store_001',
          currentDebt: 15000000,
        );

        final orders = [
          Order(
            id: 'HD001',
            customerId: 'CUST_DEBT_01',
            items: [
              OrderItem(
                productId: 'P1',
                productName: 'Xi măng',
                quantity: 50,
                price: 90000,
                warrantyMonths: 0,
                purchaseDate: DateTime(2026, 8, 10),
              ),
            ],
            total: 4500000,
            createdAt: DateTime(2026, 8, 10, 14, 0),
            status: 'completed',
          ),
          Order(
            id: 'HD002',
            customerId: 'CUST_DEBT_01',
            items: [
              OrderItem(
                productId: 'P2',
                productName: 'Thép',
                quantity: 100,
                price: 150000,
                warrantyMonths: 12,
                purchaseDate: DateTime(2026, 8, 12),
              ),
            ],
            total: 15000000,
            createdAt: DateTime(2026, 8, 12, 10, 0),
            status: 'completed',
          ),
        ];

        final debtTransactions = [
          CustomerDebtTransaction(
            id: 'TX_PAY_01',
            customerId: 'CUST_DEBT_01',
            code: 'TT001',
            date: DateTime(2026, 8, 15, 16, 0),
            amount: 4500000,
            remainingDebt: 15000000,
            type: DebtTransactionType.payment,
            note: 'Thanh toán hóa đơn HD001',
          ),
        ];

        final customerRepo = _FakeCustomerRepository([customer]);
        final orderRepo = _FakeOrderRepository(orders);

        await tester.pumpWidget(_buildTestApp(
          currentUser: _adminUser,
          overrides: [
            customerRepositoryProvider.overrideWithValue(customerRepo),
            orderRepositoryProvider.overrideWithValue(orderRepo),
            customerOrdersProvider('CUST_DEBT_01').overrideWith((ref) => Stream.value(orders)),
            customerDebtTransactionsProvider('CUST_DEBT_01').overrideWith((ref) => Stream.value(debtTransactions)),
          ],
          child: const CustomerDebtPage(customer: customer),
        ));
        await tester.pumpAndSettle();

        // Verify summary header
        expect(find.text('Nợ cần thu'), findsOneWidget);
        expect(find.text('15.000.000 đ'), findsOneWidget);
        // Verify ledger entries
        expect(find.text('HD001'), findsOneWidget);
        expect(find.text('HD002'), findsOneWidget);
        expect(find.text('TT001'), findsOneWidget);
        expect(find.text('Thanh toán hóa đơn HD001'), findsOneWidget);
      });

      test('[SYNC-20] InterStoreTransferService rejects transfers with insufficient stock, zero quantity, or identical source and destination stores', () async {
        final service = InterStoreTransferService(null);
        const product = Product(
          id: 'PROD_XFER',
          name: 'Máy Khoan Bosch',
          code: 'BSCH',
          price: 1800000,
          costPrice: 1400000,
          branchStocks: {'store_001': 5, 'store_002': 10},
          category: 'Công cụ',
        );

        // 1. Invalid quantity <= 0
        final err1 = await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: 'store_002',
          product: product,
          quantity: 0,
        );
        expect(err1, equals('Số lượng phải lớn hơn 0'));

        // 2. Insufficient stock (product.stock is 15, request 20)
        final err2 = await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: 'store_002',
          product: product,
          quantity: 20,
        );
        expect(err2, equals('Không đủ số lượng trong kho'));

        // 3. Same source and target store
        final err3 = await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: 'store_001',
          product: product,
          quantity: 2,
        );
        expect(err3, equals('Không thể chuyển cùng kho'));

        // 4. Empty store ID
        final err4 = await service.transferProduct(
          sourceStoreId: '',
          targetStoreId: 'store_002',
          product: product,
          quantity: 2,
        );
        expect(err4, equals('Chi nhánh không hợp lệ'));
      });
    });

    // -------------------------------------------------------------------------
    // GROUP 5: RBAC Permissions & UI Guard Resilience
    // -------------------------------------------------------------------------
    group('Group 5: RBAC Permissions & UI Guard Resilience', () {
      testWidgets('[RBAC-21] Staff role in ProductDetailPage blocks edit action with permission denied SnackBar and prevents edit mode', (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const product = Product(
          id: 'PROD_RBAC_EDIT',
          name: 'Khóa Cửa Việt Tiệp',
          code: 'VT01',
          price: 220000,
          costPrice: 150000,
          branchStocks: {'store_001': 10, 'store_002': 10},
          category: 'Khóa',
        );

        await tester.pumpWidget(_buildTestApp(
          currentUser: _staffUser, // Staff role
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value([product])),
            transactionsByProductProvider(product.id).overrideWith((ref) => Stream.value([])),
          ],
          child: const ProductDetailPage(product: product),
        ));
        await tester.pumpAndSettle();

        // Tap Edit in quick actions
        await tester.tap(find.text('Chỉnh sửa'));
        await tester.pumpAndSettle();

        // Must show permission error SnackBar and not enter edit mode
        expect(find.text('Bạn không có quyền chỉnh sửa sản phẩm'), findsOneWidget);
        expect(find.byIcon(Icons.save_rounded), findsNothing);
      });

      test('[RBAC-22] Staff role restricts currentStoreIdProvider strictly to assigned user storeId regardless of selectedStoreIdProvider', () {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(_staffUser)),
          ],
        );

        // Staff user has storeId = 'store_001' and canSwitchStore = false
        expect(container.read(currentStoreIdProvider), equals('store_001'));

        // Changing selectedStoreIdProvider has zero effect on staff
        container.read(selectedStoreIdProvider.notifier).state = 'store_002';
        expect(container.read(currentStoreIdProvider), equals('store_001'));

        container.dispose();
      });

      test('[RBAC-23] Role-based permission getters on UserAccount strictly distinguish supervisor, admin, and staff permissions', () {
        // 1. Staff
        expect(_staffUser.isStaff, isTrue);
        expect(_staffUser.isAdmin, isFalse);
        expect(_staffUser.isSupervisor, isFalse);
        expect(_staffUser.canSwitchStore, isFalse);
        expect(_staffUser.canManageProducts, isFalse);
        expect(_staffUser.canDeleteInvoice, isFalse);
        expect(_staffUser.canDeleteCustomer, isFalse);
        expect(_staffUser.canExportCustomers, isFalse);
        expect(_staffUser.canViewCostPrice, isFalse);
        expect(_staffUser.canViewDebtSummary, isFalse);

        // 2. Admin
        expect(_adminUser.isStaff, isFalse);
        expect(_adminUser.isAdmin, isTrue);
        expect(_adminUser.isSupervisor, isFalse);
        expect(_adminUser.canSwitchStore, isTrue);
        expect(_adminUser.canManageProducts, isTrue);
        expect(_adminUser.canDeleteInvoice, isTrue);
        expect(_adminUser.canDeleteCustomer, isTrue);
        expect(_adminUser.canExportCustomers, isTrue);
        expect(_adminUser.canViewCostPrice, isFalse); // Only supervisor can view cost price
        expect(_adminUser.canViewDebtSummary, isTrue);

        // 3. Supervisor
        expect(_supervisorUser.isStaff, isFalse);
        expect(_supervisorUser.isAdmin, isTrue); // Supervisor inherits Admin rights
        expect(_supervisorUser.isSupervisor, isTrue);
        expect(_supervisorUser.canSwitchStore, isTrue);
        expect(_supervisorUser.canManageProducts, isTrue);
        expect(_supervisorUser.canViewCostPrice, isTrue); // Supervisor permission!
        expect(_supervisorUser.canViewDebtSummary, isTrue);
      });

      test('[RBAC-24] OverviewTimeRange period selector accurately calculates start and end DateTimeRange boundaries for all pre-set and custom ranges', () {
        final now = DateTime.now();

        // 1. Today
        final todayRange = OverviewTimeRange.today.getRange();
        expect(todayRange.start.year, equals(now.year));
        expect(todayRange.start.month, equals(now.month));
        expect(todayRange.start.day, equals(now.day));
        expect(todayRange.start.hour, equals(0));
        expect(todayRange.end.hour, equals(23));

        // 2. Yesterday
        final yesterday = now.subtract(const Duration(days: 1));
        final yesterdayRange = OverviewTimeRange.yesterday.getRange();
        expect(yesterdayRange.start.day, equals(yesterday.day));
        expect(yesterdayRange.end.day, equals(yesterday.day));

        // 3. Last 7 Days
        final last7DaysRange = OverviewTimeRange.last7Days.getRange();
        final diffDays = last7DaysRange.end.difference(last7DaysRange.start).inDays;
        expect(diffDays, equals(6));

        // 4. This Month
        final thisMonthRange = OverviewTimeRange.thisMonth.getRange();
        expect(thisMonthRange.start.day, equals(1));
        expect(thisMonthRange.start.month, equals(now.month));
      });

      test('[RBAC-25] Invoices and Overview date range providers maintain independent reactive state and custom date overrides', () {
        final container = ProviderContainer();

        // Initial default: thisMonth
        expect(container.read(overviewTimeRangeTypeProvider), equals(OverviewTimeRange.thisMonth));
        expect(container.read(invoicesTimeRangeTypeProvider), equals(OverviewTimeRange.thisMonth));

        // Change overview to today
        container.read(overviewTimeRangeTypeProvider.notifier).state = OverviewTimeRange.today;
        expect(container.read(overviewTimeRangeTypeProvider), equals(OverviewTimeRange.today));
        // Invoices remains thisMonth (independent state!)
        expect(container.read(invoicesTimeRangeTypeProvider), equals(OverviewTimeRange.thisMonth));

        // Custom range test
        final customRange = DateTimeRange(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 6, 30, 23, 59, 59),
        );
        container.read(overviewCustomDateRangeProvider.notifier).state = customRange;
        container.read(overviewTimeRangeTypeProvider.notifier).state = OverviewTimeRange.custom;

        final activeRange = container.read(overviewActiveDateRangeProvider);
        expect(activeRange.start, equals(DateTime(2026, 1, 1)));
        expect(activeRange.end, equals(DateTime(2026, 6, 30, 23, 59, 59)));

        container.dispose();
      });
    });
  });
}
