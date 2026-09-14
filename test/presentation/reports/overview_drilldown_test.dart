import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/customers/pages/customer_detail_page.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/reports/widgets/payment_category_breakdown_section.dart';
import 'package:stores/presentation/reports/widgets/top_rankings_section.dart';

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
  _FakeCustomerListNotifier(this._customers);

  final List<Customer> _customers;

  @override
  Future<List<Customer>> build() async => _customers;

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_customers);
  }
}

class _FakeProductRepository implements ProductRepository {
  final Map<String, Product> _products;
  _FakeProductRepository([this._products = const {}]);

  @override
  Stream<List<Product>> watchAll() =>
      Stream.value(_products.values.toList());

  @override
  Future<List<Product>> fetchAll() async => _products.values.toList();

  @override
  Future<Product?> fetchById(String id) async => _products[id];

  @override
  Future<void> upsert(Product product) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> updateStock(String id, int newStock) async {}
}

class _FakeCustomerRepository implements CustomerRepository {
  final Map<String, Customer> _customers;
  _FakeCustomerRepository([this._customers = const {}]);

  @override
  Stream<List<Customer>> watchAll() =>
      Stream.value(_customers.values.toList());

  @override
  Future<Customer?> fetchById(String id) async => _customers[id];

  @override
  Future<void> upsert(Customer customer) async {}

  @override
  Future<void> delete(String id) async {}
}

class _FakeInventoryRepository implements InventoryRepository {
  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value([]);

  @override
  Future<void> record(InventoryTransaction tx) async {}

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime startDate, DateTime endDate) =>
      Stream.value([]);
}

const mockAdminUser = UserAccount(
  username: 'admin',
  displayName: 'Admin User',
  role: 'admin',
  storeId: 'store_001',
);

const mockProduct = Product(
  id: 'prod_001',
  name: 'iPhone 15 Pro Max',
  code: 'IP15PM',
  price: 32000000.0,
  costPrice: 28000000.0,
  branchStocks: {'store_001': 10},
  category: 'Điện thoại',
);

const mockCustomer = Customer(
  id: 'cust_001',
  name: 'Nguyễn Văn A',
  phone: '0901234567',
  email: 'a@example.com',
  address: 'Hà Nội',
  purchases: [],
  currentDebt: 500000.0,
);

const mockProductRankings = [
  ProductRankingItem(
    productId: 'prod_001',
    productName: 'iPhone 15 Pro Max',
    categoryName: 'Điện thoại',
    quantity: 10,
    revenue: 320000000.0,
  ),
];

const mockCustomerRankings = [
  CustomerRankingItem(
    customerId: 'cust_001',
    customerName: 'Nguyễn Văn A',
    phoneNumber: '0901234567',
    orderCount: 5,
    totalSpent: 50000000.0,
  ),
];

const mockCategories = [
  CategoryRevenueShare(
    categoryName: 'Điện thoại',
    revenue: 60000000.0,
    percentage: 60.0,
    quantitySold: 15,
  ),
  CategoryRevenueShare(
    categoryName: 'Phụ kiện',
    revenue: 40000000.0,
    percentage: 40.0,
    quantitySold: 50,
  ),
];

const mockPayment = PaymentBreakdown(
  totalAmount: 100000000.0,
  cashAmount: 50000000.0,
  transferAmount: 30000000.0,
  debtAmount: 20000000.0,
);

final fakeProductRepo = _FakeProductRepository({'prod_001': mockProduct});
final fakeCustomerRepo = _FakeCustomerRepository({'cust_001': mockCustomer});
final fakeInventoryRepo = _FakeInventoryRepository();

List<Override> _createBaseOverrides() {
  return [
    authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
    currentStoreIdProvider.overrideWith((ref) => 'store_001'),
    branchesProvider.overrideWithValue([
      const Branch('store_001', 'Chi nhánh Đông Thắng'),
      const Branch('store_002', 'Chi nhánh Thới Bình'),
    ]),
    availableStoresProvider.overrideWith((ref) async => {
      'store_001': 'Chi nhánh Đông Thắng',
      'store_002': 'Chi nhánh Thới Bình',
    }),
    currentStoreNameProvider
        .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
    showCostPriceProvider.overrideWith((ref) => true),
    productRepositoryProvider.overrideWithValue(fakeProductRepo),
    customerRepositoryProvider.overrideWithValue(fakeCustomerRepo),
    inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
    allStoresProductsProvider.overrideWith((ref) => Stream.value([mockProduct])),
    productListProvider.overrideWith((ref) => Stream.value([mockProduct])),
    customerListNotifierProvider
        .overrideWith(() => _FakeCustomerListNotifier([mockCustomer])),
    processedProductsProvider.overrideWith(
      (ref) => AsyncValue.data(
        ProcessedProductsData(
          filteredProducts: [mockProduct],
          categories: ['All', 'Điện thoại', 'Phụ kiện'],
          brands: [],
          totalStock: 10,
          totalCostValue: 280000000.0,
          totalProducts: 1,
        ),
      ),
    ),
    processedCustomersProvider.overrideWith((ref) => const AsyncValue.data([mockCustomer])),
    customerDebtCountsProvider.overrideWith((ref) => {
      CustomerDebtFilter.all: 1,
      CustomerDebtFilter.inDebt: 1,
      CustomerDebtFilter.cleared: 0,
    }),
    customerOrdersProvider(mockCustomer.id).overrideWith((ref) => Stream.value([])),
    customerDebtTransactionsProvider(mockCustomer.id)
        .overrideWith((ref) => Stream.value([])),
    transactionsByProductProvider(mockProduct.id)
        .overrideWith((ref) => Stream.value([])),
  ];
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
  Size screenSize = const Size(500, 1000),
}) {
  return ProviderScope(
    overrides: [
      ..._createBaseOverrides(),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: MediaQuery(
        data: MediaQueryData(size: screenSize),
        child: Material(child: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M3 KPI Overview Drill-downs - TopRankingsSection', () {
    testWidgets('Tapping on top product item navigates to ProductDetailPage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const TopRankingsSection(),
          overrides: [
            topSellingProductsRankingProvider
                .overrideWith((ref) => const AsyncValue.data(mockProductRankings)),
            topCustomersRankingProvider
                .overrideWith((ref) => const AsyncValue.data(mockCustomerRankings)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('iPhone 15 Pro Max'), findsOneWidget);

      // Verify InkWell is wrapping the product item
      final productItem = find.ancestor(
        of: find.text('iPhone 15 Pro Max'),
        matching: find.byType(InkWell),
      );
      expect(productItem, findsWidgets);

      // Tap on product item
      await tester.tap(find.text('iPhone 15 Pro Max'));
      await tester.pumpAndSettle();

      // Verify ProductDetailPage opened
      expect(find.byType(ProductDetailPage), findsOneWidget);
    });

    testWidgets('Tapping "Xem tất cả" in Top Selling Products opens ProductsPage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const TopRankingsSection(),
          overrides: [
            topSellingProductsRankingProvider
                .overrideWith((ref) => const AsyncValue.data(mockProductRankings)),
            topCustomersRankingProvider
                .overrideWith((ref) => const AsyncValue.data(mockCustomerRankings)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Two "Xem tất cả" buttons exist (one for products, one for customers)
      final viewAllButtons = find.text('Xem tất cả');
      expect(viewAllButtons, findsNWidgets(2));

      // Tap first "Xem tất cả" (Top Selling Products)
      await tester.tap(viewAllButtons.first);
      await tester.pumpAndSettle();

      expect(find.byType(ProductsPage), findsOneWidget);
    });

    testWidgets('Tapping on top customer item navigates to CustomerDetailPage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const TopRankingsSection(),
          overrides: [
            topSellingProductsRankingProvider
                .overrideWith((ref) => const AsyncValue.data(mockProductRankings)),
            topCustomersRankingProvider
                .overrideWith((ref) => const AsyncValue.data(mockCustomerRankings)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nguyễn Văn A'), findsOneWidget);

      // Verify InkWell is wrapping the customer item
      final customerItem = find.ancestor(
        of: find.text('Nguyễn Văn A'),
        matching: find.byType(InkWell),
      );
      expect(customerItem, findsWidgets);

      // Tap on customer item
      await tester.tap(find.text('Nguyễn Văn A'));
      await tester.pumpAndSettle();

      // Verify CustomerDetailPage opened
      expect(find.byType(CustomerDetailPage), findsOneWidget);
    });

    testWidgets('Tapping "Xem tất cả" in Top Customers opens CustomersPage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const TopRankingsSection(),
          overrides: [
            topSellingProductsRankingProvider
                .overrideWith((ref) => const AsyncValue.data(mockProductRankings)),
            topCustomersRankingProvider
                .overrideWith((ref) => const AsyncValue.data(mockCustomerRankings)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final viewAllButtons = find.text('Xem tất cả');
      expect(viewAllButtons, findsNWidgets(2));

      // Tap second "Xem tất cả" (Top Customers)
      await tester.tap(viewAllButtons.last);
      await tester.pumpAndSettle();

      expect(find.byType(CustomersPage), findsOneWidget);
    });
  });

  group('M3 KPI Overview Drill-downs - PaymentCategoryBreakdownSection', () {
    testWidgets('Tapping on category item navigates to ProductsPage with category filter',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const PaymentCategoryBreakdownSection(),
          overrides: [
            paymentBreakdownProvider
                .overrideWith((ref) => const AsyncValue.data(mockPayment)),
            categoryRevenueShareProvider
                .overrideWith((ref) => const AsyncValue.data(mockCategories)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Điện thoại'), findsOneWidget);

      // Verify InkWell wrapping category item
      final categoryItem = find.ancestor(
        of: find.text('Điện thoại'),
        matching: find.byType(InkWell),
      );
      expect(categoryItem, findsWidgets);

      // Tap category 'Điện thoại'
      await tester.tap(find.text('Điện thoại'));
      await tester.pumpAndSettle();

      // Verify ProductsPage opened with category filter
      final productsPageFinder = find.byType(ProductsPage);
      expect(productsPageFinder, findsOneWidget);
      final productsPage = tester.widget<ProductsPage>(productsPageFinder);
      expect(productsPage.initialCategory, equals('Điện thoại'));
    });

    testWidgets('Tapping on "Ghi nợ khách" navigates to CustomersPage with debt filter active',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const PaymentCategoryBreakdownSection(),
          overrides: [
            paymentBreakdownProvider
                .overrideWith((ref) => const AsyncValue.data(mockPayment)),
            categoryRevenueShareProvider
                .overrideWith((ref) => const AsyncValue.data(mockCategories)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ghi nợ khách'), findsOneWidget);

      // Verify InkWell wrapping Ghi nợ khách
      final debtItem = find.ancestor(
        of: find.text('Ghi nợ khách'),
        matching: find.byType(InkWell),
      );
      expect(debtItem, findsWidgets);

      // Tap 'Ghi nợ khách'
      await tester.tap(find.text('Ghi nợ khách'));
      await tester.pumpAndSettle();

      // Verify CustomersPage opened with inDebt filter
      final customersPageFinder = find.byType(CustomersPage);
      expect(customersPageFinder, findsOneWidget);
      final customersPage = tester.widget<CustomersPage>(customersPageFinder);
      expect(customersPage.initialDebtFilter, equals(CustomerDebtFilter.inDebt));
    });
  });

  group('ProductDetailPage productId support & async fallback', () {
    testWidgets('ProductDetailPage loads product asynchronously when productId is passed',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductDetailPage(productId: 'prod_001'),
        ),
      );

      // Initial pump
      await tester.pump();
      // Wait for async fetch to finish and settle
      await tester.pumpAndSettle();

      // Product details should now be populated
      expect(find.text('iPhone 15 Pro Max'), findsWidgets);
    });

    testWidgets('ProductDetailPage fallback loads full product when minimal placeholder is passed',
        (tester) async {
      const minimalProduct = Product(
        id: 'prod_001',
        name: 'Temporary Name',
        code: '', // minimal placeholder indicator
        price: 0,
        costPrice: 0,
        branchStocks: {},
        category: '',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductDetailPage(
            product: minimalProduct,
            productId: 'prod_001',
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Full product should be fetched from repository
      expect(find.text('iPhone 15 Pro Max'), findsWidgets);
    });
  });

  group('ProductsPage initialCategory support', () {
    testWidgets('ProductsPage initializes productCategoryFilterProvider with initialCategory',
        (tester) async {
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: _createBaseOverrides(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const ProductsPage(initialCategory: 'Phụ kiện');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check that productCategoryFilterProvider was updated to 'Phụ kiện'
      expect(capturedRef.read(productCategoryFilterProvider), equals('Phụ kiện'));
    });
  });
}
