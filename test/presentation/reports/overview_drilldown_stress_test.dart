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

class _StressProductRepository implements ProductRepository {
  final Map<String, Product> _products;
  final bool shouldThrow;

  _StressProductRepository(this._products, {this.shouldThrow = false});

  @override
  Stream<List<Product>> watchAll() =>
      Stream.value(_products.values.toList());

  @override
  Future<List<Product>> fetchAll() async => _products.values.toList();

  @override
  Future<Product?> fetchById(String id) async {
    if (shouldThrow) {
      throw Exception('Simulated repository network error');
    }
    return _products[id];
  }

  @override
  Future<void> upsert(Product product) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> updateStock(String id, int newStock) async {}
}

class _StressCustomerRepository implements CustomerRepository {
  final Map<String, Customer> _customers;

  _StressCustomerRepository(this._customers);

  @override
  Stream<List<Customer>> watchAll() =>
      Stream.value(_customers.values.toList());

  @override
  Future<Customer?> fetchById(String id) async {
    return _customers[id];
  }

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

const stressProduct1 = Product(
  id: 'prod_special_01',
  name: 'Bộ Thiết Bị & Phụ Kiện (Cao Cấp)',
  code: 'TB_PK_01',
  price: 1500000.0,
  costPrice: 1000000.0,
  branchStocks: {'store_001': 10},
  category: 'Thiết bị & Phụ kiện (Điện tử)',
);

const stressCustomer1 = Customer(
  id: 'cust_special_01',
  name: 'Trần Thị Bích Ngọc (VIP)',
  phone: '0918889999',
  email: 'ngoc@vip.com',
  address: 'Hải Châu, Đà Nẵng',
  purchases: [],
  currentDebt: 2500000.0,
);

const stressProductRankings = [
  ProductRankingItem(
    productId: 'prod_special_01',
    productName: 'Bộ Thiết Bị & Phụ Kiện (Cao Cấp)',
    categoryName: 'Thiết bị & Phụ kiện (Điện tử)',
    quantity: 25,
    revenue: 37500000.0,
  ),
];

const stressCustomerRankings = [
  CustomerRankingItem(
    customerId: 'cust_special_01',
    customerName: 'Trần Thị Bích Ngọc (VIP)',
    phoneNumber: '0918889999',
    orderCount: 12,
    totalSpent: 45000000.0,
  ),
];

const stressCategories = [
  CategoryRevenueShare(
    categoryName: 'Thiết bị & Phụ kiện (Điện tử)',
    revenue: 50000000.0,
    percentage: 50.0,
    quantitySold: 25,
  ),
  CategoryRevenueShare(
    categoryName: 'Đồ gia dụng / Nhà bếp [Hot]',
    revenue: 30000000.0,
    percentage: 30.0,
    quantitySold: 40,
  ),
  CategoryRevenueShare(
    categoryName: '100% Cà phê & Trà',
    revenue: 20000000.0,
    percentage: 20.0,
    quantitySold: 60,
  ),
];

const stressPayment = PaymentBreakdown(
  totalAmount: 100000000.0,
  cashAmount: 40000000.0,
  transferAmount: 35000000.0,
  debtAmount: 25000000.0,
);

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
  ProductRepository? productRepo,
  CustomerRepository? customerRepo,
}) {
  final prodRepo = productRepo ??
      _StressProductRepository({'prod_special_01': stressProduct1});
  final custRepo = customerRepo ??
      _StressCustomerRepository({'cust_special_01': stressCustomer1});

  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
      currentStoreIdProvider.overrideWith((ref) => 'store_001'),
      branchesProvider.overrideWithValue([
        const Branch('store_001', 'Chi nhánh Đông Thắng'),
      ]),
      availableStoresProvider.overrideWith((ref) async => {
        'store_001': 'Chi nhánh Đông Thắng',
      }),
      currentStoreNameProvider
          .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
      showCostPriceProvider.overrideWith((ref) => true),
      productRepositoryProvider.overrideWithValue(prodRepo),
      customerRepositoryProvider.overrideWithValue(custRepo),
      inventoryRepositoryProvider.overrideWithValue(_FakeInventoryRepository()),
      allStoresProductsProvider.overrideWith((ref) => Stream.value([stressProduct1])),
      productListProvider.overrideWith((ref) => Stream.value([stressProduct1])),
      customerListNotifierProvider
          .overrideWith(() => _FakeCustomerListNotifier([stressCustomer1])),
      processedProductsProvider.overrideWith(
        (ref) => AsyncValue.data(
          ProcessedProductsData(
            filteredProducts: [stressProduct1],
            categories: [
              'All',
              'Thiết bị & Phụ kiện (Điện tử)',
              'Đồ gia dụng / Nhà bếp [Hot]',
              '100% Cà phê & Trà',
            ],
            brands: [],
            totalStock: 10,
            totalCostValue: 10000000.0,
            totalProducts: 1,
          ),
        ),
      ),
      processedCustomersProvider
          .overrideWith((ref) => const AsyncValue.data([stressCustomer1])),
      customerDebtCountsProvider.overrideWith((ref) => {
        CustomerDebtFilter.all: 1,
        CustomerDebtFilter.inDebt: 1,
        CustomerDebtFilter.cleared: 0,
      }),
      customerOrdersProvider(stressCustomer1.id).overrideWith((ref) => Stream.value([])),
      customerDebtTransactionsProvider(stressCustomer1.id)
          .overrideWith((ref) => Stream.value([])),
      transactionsByProductProvider(stressProduct1.id)
          .overrideWith((ref) => Stream.value([])),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Material(child: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 3 Stress: Rapid Taps Resilience', () {
    testWidgets('Rapid multiple taps on top product do not crash or produce unhandled exceptions',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const TopRankingsSection(),
          overrides: [
            topSellingProductsRankingProvider
                .overrideWith((ref) => const AsyncValue.data(stressProductRankings)),
            topCustomersRankingProvider
                .overrideWith((ref) => const AsyncValue.data(stressCustomerRankings)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final productItem = find.text('Bộ Thiết Bị & Phụ Kiện (Cao Cấp)');
      expect(productItem, findsOneWidget);

      // Perform 5 rapid taps in succession
      for (int i = 0; i < 5; i++) {
        await tester.tap(productItem, warnIfMissed: false);
      }
      await tester.pumpAndSettle();

      // Should land on ProductDetailPage gracefully
      expect(find.byType(ProductDetailPage), findsOneWidget);
    });

    testWidgets('Rapid multiple taps on top customer do not crash or produce unhandled exceptions',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const TopRankingsSection(),
          overrides: [
            topSellingProductsRankingProvider
                .overrideWith((ref) => const AsyncValue.data(stressProductRankings)),
            topCustomersRankingProvider
                .overrideWith((ref) => const AsyncValue.data(stressCustomerRankings)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final customerItem = find.text('Trần Thị Bích Ngọc (VIP)');
      expect(customerItem, findsOneWidget);

      // Perform 5 rapid taps in succession
      for (int i = 0; i < 5; i++) {
        await tester.tap(customerItem, warnIfMissed: false);
      }
      await tester.pumpAndSettle();

      // Should land on CustomerDetailPage gracefully
      expect(find.byType(CustomerDetailPage), findsOneWidget);
    });
  });

  group('Milestone 3 Stress: ProductDetailPage Async Fallback Scenarios', () {
    testWidgets('Fallback: Missing productId (null returned from repo) renders gracefully without crash',
        (tester) async {
      final emptyRepo = _StressProductRepository({});

      await tester.pumpWidget(
        _buildTestApp(
          productRepo: emptyRepo,
          child: const ProductDetailPage(productId: 'unknown_product_999'),
        ),
      );

      // Trigger initial pump and async settlement
      await tester.pump();
      await tester.pumpAndSettle();

      // Should finish loading without crash, displaying empty/fallback form
      expect(find.byType(ProductDetailPage), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Fallback: Repository network exception during fetchById is caught cleanly',
        (tester) async {
      final throwingRepo = _StressProductRepository({}, shouldThrow: true);

      await tester.pumpWidget(
        _buildTestApp(
          productRepo: throwingRepo,
          child: const ProductDetailPage(productId: 'error_trigger_prod'),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      // Page handled error cleanly, stopped loading indicator, did not crash
      expect(find.byType(ProductDetailPage), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Fallback: Minimal placeholder product triggers async enrichment',
        (tester) async {
      const minimalPlaceholder = Product(
        id: 'prod_special_01',
        name: 'Tên tạm thời',
        code: '', // minimal indicator
        price: 0,
        costPrice: 0,
        branchStocks: {},
        category: '',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductDetailPage(
            product: minimalPlaceholder,
            productId: 'prod_special_01',
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      // Full product should have been loaded from repository
      expect(find.text('Bộ Thiết Bị & Phụ Kiện (Cao Cấp)'), findsWidgets);
      expect(find.text('TB_PK_01'), findsWidgets);
    });
  });

  group('Milestone 3 Stress: Special Character Category Drill-down', () {
    testWidgets('Category drilldown handles ampersands, slashes, brackets and diacritics',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const PaymentCategoryBreakdownSection(),
          overrides: [
            paymentBreakdownProvider
                .overrideWith((ref) => const AsyncValue.data(stressPayment)),
            categoryRevenueShareProvider
                .overrideWith((ref) => const AsyncValue.data(stressCategories)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Check categories with special symbols are displayed
      expect(find.text('Thiết bị & Phụ kiện (Điện tử)'), findsOneWidget);
      expect(find.text('Đồ gia dụng / Nhà bếp [Hot]'), findsOneWidget);
      expect(find.text('100% Cà phê & Trà'), findsOneWidget);

      // Tap on 'Đồ gia dụng / Nhà bếp [Hot]'
      await tester.tap(find.text('Đồ gia dụng / Nhà bếp [Hot]'));
      await tester.pumpAndSettle();

      // Should open ProductsPage with exact initialCategory string
      final productsPageFinder = find.byType(ProductsPage);
      expect(productsPageFinder, findsOneWidget);
      final productsPage = tester.widget<ProductsPage>(productsPageFinder);
      expect(productsPage.initialCategory, equals('Đồ gia dụng / Nhà bếp [Hot]'));
    });
  });

  group('Milestone 3 Stress: "Ghi nợ khách" Legend Drill-down to CustomersPage', () {
    testWidgets('Tapping "Ghi nợ khách" legend passes inDebt filter and activates "Còn nợ" tab',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const PaymentCategoryBreakdownSection(),
          overrides: [
            paymentBreakdownProvider
                .overrideWith((ref) => const AsyncValue.data(stressPayment)),
            categoryRevenueShareProvider
                .overrideWith((ref) => const AsyncValue.data(stressCategories)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Verify legend item exists
      expect(find.text('Ghi nợ khách'), findsOneWidget);
      expect(find.text('25.000.000 đ'), findsOneWidget);

      // Tap 'Ghi nợ khách'
      await tester.tap(find.text('Ghi nợ khách'));
      await tester.pumpAndSettle();

      // Verify CustomersPage is pushed with initialDebtFilter == CustomerDebtFilter.inDebt
      final customersPageFinder = find.byType(CustomersPage);
      expect(customersPageFinder, findsOneWidget);
      final customersPage = tester.widget<CustomersPage>(customersPageFinder);
      expect(customersPage.initialDebtFilter, equals(CustomerDebtFilter.inDebt));

      // Verify the 'Còn nợ' filter tab is selected on the CustomersPage
      final inDebtTabFinder = find.byKey(const Key('debt_filter_tab_inDebt'));
      expect(inDebtTabFinder, findsOneWidget);
      expect(find.text('Còn nợ'), findsOneWidget);

      // Verify customer in debt is displayed
      expect(find.text('Trần Thị Bích Ngọc (VIP)'), findsOneWidget);
    });
  });
}
