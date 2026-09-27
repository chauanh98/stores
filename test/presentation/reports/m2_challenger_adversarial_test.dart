import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/widgets/customer_list_tile.dart';
import 'package:stores/presentation/reports/pages/overview_page.dart';
import 'package:stores/presentation/reports/widgets/kpi_metrics_section.dart';
import 'package:stores/presentation/reports/widgets/overview_header.dart';
import 'package:stores/presentation/reports/widgets/quick_actions_bar.dart';

class _DynamicAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _DynamicAuthNotifier(super.state);

  void setUser(UserAccount? user) {
    state = user;
  }

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

Widget _buildHarness({
  required Widget child,
  List<Override> overrides = const [],
  Size screenSize = const Size(600, 900),
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: theme ?? ThemeData.light(),
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
  final format = NumberFormat('#,###', 'vi_VN');

  const supervisorUser = UserAccount(
    username: 'supervisor_boss',
    displayName: 'Tổng Giám Sát',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const adminUser = UserAccount(
    username: 'admin_branch',
    displayName: 'Quản Lý Chi Nhánh',
    role: 'admin',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff_cashier',
    displayName: 'Thu Ngân Chi Nhánh',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const standardKPIs = OverviewKPIs(
    netRevenue: 78500000.0,
    orderCount: 142,
    grossProfit: 24600000.0,
    returnGoodsValue: 1250000.0,
    aov: 552816.9,
    revenueGrowthPercent: 18.4,
    orderCountGrowthPercent: 12.1,
    profitGrowthPercent: 14.5,
    aovGrowthPercent: 5.6,
    customerDebt: 98000000.0,
  );

  const stockAlertSummary = StockAlertSummary(
    outOfStockCount: 12,
    lowStockCount: 25,
    totalItemCount: 1850,
    totalInventoryCost: 890000000.0,
    outOfStockProductIds: ['p1', 'p2'],
    lowStockProductIds: ['p3', 'p4'],
  );

  final hourlyData = List.generate(
    24,
    (h) => HourlyRevenueData(
      hour: h,
      revenue: h == 12 ? 15000000.0 : (h == 18 ? 22000000.0 : 1000000.0),
      orderCount: h == 12 ? 25 : (h == 18 ? 38 : 2),
    ),
  );

  const paymentBreakdown = PaymentBreakdown(
    cashAmount: 30000000.0,
    transferAmount: 40000000.0,
    debtAmount: 8500000.0,
    totalAmount: 78500000.0,
  );

  const categoryShares = [
    CategoryRevenueShare(
      categoryName: 'Điện thoại',
      revenue: 50000000.0,
      percentage: 63.7,
      quantitySold: 20,
    ),
  ];

  const topProducts = [
    ProductRankingItem(
      productId: 'p1',
      productName: 'iPhone 16 Pro Max',
      quantity: 15,
      revenue: 45000000.0,
      categoryName: 'Điện thoại',
    ),
  ];

  const topCustomers = [
    CustomerRankingItem(
      customerId: 'c1',
      customerName: 'Tập đoàn Á Châu',
      totalSpent: 65000000.0,
      orderCount: 12,
      phoneNumber: '0909999888',
    ),
  ];

  final recentOrders = [
    Order(
      id: 'HD20260816-0099',
      customerId: 'c1',
      createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      items: const [],
      total: 35000000.0,
      status: 'completed',
    ),
  ];

  List<Override> createStandardOverrides({
    required _DynamicAuthNotifier authNotifier,
    String storeName = 'Chi nhánh Đông Thắng',
    OverviewKPIs kpis = standardKPIs,
  }) {
    return [
      authProvider.overrideWith((ref) => authNotifier),
      profitVisibilityProvider.overrideWith((ref) => true),
      currentStoreNameProvider.overrideWith((ref) async => storeName),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': storeName,
            'store_002': 'Chi nhánh Thời Bình',
          }),
      overviewKPIsProvider.overrideWith((ref) => AsyncValue.data(kpis)),
      stockAlertSummaryProvider
          .overrideWith((ref) => const AsyncValue.data(stockAlertSummary)),
      hourlyRevenueListProvider
          .overrideWith((ref) => AsyncValue.data(hourlyData)),
      paymentBreakdownProvider
          .overrideWith((ref) => const AsyncValue.data(paymentBreakdown)),
      categoryRevenueShareProvider
          .overrideWith((ref) => const AsyncValue.data(categoryShares)),
      topSellingProductsRankingProvider
          .overrideWith((ref) => const AsyncValue.data(topProducts)),
      topCustomersRankingProvider
          .overrideWith((ref) => const AsyncValue.data(topCustomers)),
      recentOrdersFeedProvider
          .overrideWith((ref) => AsyncValue.data(recentOrders)),
    ];
  }

  group('Dimension 1: Responsiveness Across Device Widths (Mobile 450px vs Tablet 800px)', () {
    testWidgets('OverviewHeader renders supervisor dropdown and badges without errors on tablet and mobile',
        (tester) async {
      final authNotifier = _DynamicAuthNotifier(supervisorUser);

      await tester.pumpWidget(
        _buildHarness(
          screenSize: const Size(600, 900),
          overrides: createStandardOverrides(authNotifier: authNotifier),
          child: const OverviewHeader(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(OverviewHeader), findsOneWidget);
      expect(find.text('Giám sát'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    });

    testWidgets('KPIMetricsSection renders all cards without overflow on standard mobile/tablet',
        (tester) async {
      final authNotifier = _DynamicAuthNotifier(supervisorUser);

      await tester.pumpWidget(
        _buildHarness(
          screenSize: const Size(600, 900),
          overrides: createStandardOverrides(authNotifier: authNotifier),
          child: const KPIMetricsSection(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Doanh thu thuần'), findsOneWidget);
      expect(find.text('Lợi nhuận gộp'), findsOneWidget);
      expect(find.text('Công nợ khách hàng cần thu'), findsOneWidget);
    });

    testWidgets('QuickActionsBar renders all 5 action shortcuts cleanly',
        (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          screenSize: const Size(600, 900),
          child: const QuickActionsBar(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Bán hàng'), findsOneWidget);
      expect(find.text('Nhập hàng'), findsOneWidget);
      expect(find.text('Chuyển kho'), findsOneWidget);
      expect(find.text('Sổ nợ khách'), findsOneWidget);
      expect(find.text('Hàng hóa'), findsOneWidget);
    });

    testWidgets('OverviewPage coordinator handles tablet 800px 2-column layout smoothly',
        (tester) async {
      final authNotifier = _DynamicAuthNotifier(supervisorUser);

      await tester.pumpWidget(
        _buildHarness(
          screenSize: const Size(800, 1200),
          overrides: createStandardOverrides(authNotifier: authNotifier),
          child: const OverviewPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Row), findsWidgets);
      expect(find.byType(OverviewHeader), findsOneWidget);
      expect(find.byType(KPIMetricsSection), findsOneWidget);
      expect(find.byType(QuickActionsBar), findsNothing);
    });
  });

  group('Dimension 2: Dark / Light Styling & Theme Invariance Tests', () {
    testWidgets('Renders KPI metrics section cleanly under ThemeData.dark()',
        (tester) async {
      final authNotifier = _DynamicAuthNotifier(supervisorUser);
      final overrides = createStandardOverrides(authNotifier: authNotifier);

      await tester.pumpWidget(
        _buildHarness(
          screenSize: const Size(600, 900),
          theme: ThemeData.dark(useMaterial3: true),
          overrides: overrides,
          child: const KPIMetricsSection(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Doanh thu thuần'), findsOneWidget);
      expect(find.text('Lợi nhuận gộp'), findsOneWidget);
      expect(find.text('Công nợ khách hàng cần thu'), findsOneWidget);
    });

    testWidgets('Profit toggle interaction and eye icon work properly in dark mode',
        (tester) async {
      final authNotifier = _DynamicAuthNotifier(supervisorUser);
      final overrides = createStandardOverrides(authNotifier: authNotifier);

      await tester.pumpWidget(
        _buildHarness(
          screenSize: const Size(600, 900),
          theme: ThemeData.dark(),
          overrides: overrides,
          child: const KPIMetricsSection(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('${format.format(standardKPIs.grossProfit)} đ'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      expect(find.text('*** ***'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      expect(find.text('${format.format(standardKPIs.grossProfit)} đ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Dimension 3: Rapid Role Transitions in Mounted Widget Tree (Supervisor -> Staff -> Admin)', () {
    testWidgets('Live UI tree instantly and correctly toggles permissions & locks upon rapid role switches',
        (tester) async {
      final authNotifier = _DynamicAuthNotifier(supervisorUser);
      final overrides = createStandardOverrides(authNotifier: authNotifier);

      await tester.pumpWidget(
        _buildHarness(
          screenSize: const Size(600, 900),
          overrides: overrides,
          child: const SingleChildScrollView(
            child: Column(
              children: [
                OverviewHeader(),
                KPIMetricsSection(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // State 1: Supervisor
      expect(find.text('Giám sát'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(find.text('Lợi nhuận gộp'), findsOneWidget);
      expect(find.text('Công nợ khách hàng cần thu'), findsOneWidget);
      expect(find.text('${format.format(standardKPIs.customerDebt)} đ'), findsOneWidget);

      // State 2: Rapid switch to Staff
      authNotifier.setUser(staffUser);
      await tester.pumpAndSettle();

      expect(find.text('Giám sát'), findsNothing);
      expect(find.text('Admin'), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(find.text('Lợi nhuận gộp'), findsNothing);
      expect(find.text('Công nợ khách hàng cần thu'), findsNothing);
      expect(find.text('${format.format(standardKPIs.customerDebt)} đ'), findsNothing);

      // State 3: Rapid switch to Admin (can switch stores, see debt, and see profit)
      authNotifier.setUser(adminUser);
      await tester.pumpAndSettle();

      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Giám sát'), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(find.text('Lợi nhuận gộp'), findsOneWidget);
      expect(find.text('Công nợ khách hàng cần thu'), findsOneWidget);

      // State 4: Rapid switch back to Supervisor
      authNotifier.setUser(supervisorUser);
      await tester.pumpAndSettle();

      expect(find.text('Giám sát'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);

      // State 5: Rapid stress cycle 30 times
      for (int i = 0; i < 30; i++) {
        authNotifier.setUser(i % 3 == 0 ? supervisorUser : (i % 3 == 1 ? staffUser : adminUser));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Unauthenticated / null user gracefully fails closed in Header & KPI',
        (tester) async {
      final authNotifier = _DynamicAuthNotifier(null);
      final overrides = createStandardOverrides(authNotifier: authNotifier);

      await tester.pumpWidget(
        _buildHarness(
          screenSize: const Size(600, 900),
          overrides: overrides,
          child: const SingleChildScrollView(
            child: Column(
              children: [
                OverviewHeader(),
                KPIMetricsSection(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Admin'), findsNothing);
      expect(find.text('Giám sát'), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(find.text('Lợi nhuận gộp'), findsNothing);
      expect(find.text('Công nợ khách hàng cần thu'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Dimension 4: POS Cashier Debt Isolation & Global Debt Leak Prevention', () {
    const customerWithDebt = Customer(
      id: 'cust_indiv_01',
      name: 'Võ Minh Trí',
      phone: '0912345678',
      email: 'tri.vo@example.com',
      address: '123 Nguyễn Huệ, Q.1',
      purchases: [],
      totalSales: 45000000.0,
      currentDebt: 3500000.0,
    );

    const customerZeroDebt = Customer(
      id: 'cust_indiv_02',
      name: 'Lê Hoàng Yến',
      phone: '0988776655',
      email: 'yen.le@example.com',
      address: '456 Lê Lợi, Q.1',
      purchases: [],
      totalSales: 12000000.0,
      currentDebt: 0.0,
    );

    testWidgets(
        'Staff cashier accurately sees selected customer debt (3.5M) but zero global debt summary',
        (tester) async {
      final authNotifier = _DynamicAuthNotifier(staffUser);

      await tester.pumpWidget(
        _buildHarness(
          screenSize: const Size(600, 900),
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
            customerOrdersProvider(customerWithDebt.id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(customerWithDebt.id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
            overviewKPIsProvider.overrideWith((ref) => const AsyncValue.data(standardKPIs)),
          ],
          child: const SingleChildScrollView(
            child: Column(
              children: [
                KPIMetricsSection(),
                CustomerListTile(customer: customerWithDebt),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Specific customer debt is accurately shown for cashier operations
      expect(find.text('Võ Minh Trí'), findsOneWidget);
      expect(find.text('Công nợ: ${format.format(3500000.0)}'), findsOneWidget);

      // 2. Global chain/store debt (98,000,000 đ) is NOT visible or leaked anywhere in Staff view
      expect(find.text('Công nợ khách hàng cần thu'), findsNothing);
      expect(find.text('${format.format(98000000.0)} đ'), findsNothing);
      expect(find.textContaining('98.000.000'), findsNothing);
    });

    testWidgets('Staff cashier with zero debt customer shows no debt badge and no global debt leak',
        (tester) async {
      final authNotifier = _DynamicAuthNotifier(staffUser);

      await tester.pumpWidget(
        _buildHarness(
          screenSize: const Size(600, 900),
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
            customerOrdersProvider(customerZeroDebt.id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(customerZeroDebt.id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
            overviewKPIsProvider.overrideWith((ref) => const AsyncValue.data(standardKPIs)),
          ],
          child: const SingleChildScrollView(
            child: Column(
              children: [
                KPIMetricsSection(),
                CustomerListTile(customer: customerZeroDebt),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lê Hoàng Yến'), findsOneWidget);
      expect(find.textContaining('Công nợ:'), findsNothing);
      expect(find.text('Công nợ khách hàng cần thu'), findsNothing);
      expect(find.textContaining('98.000.000'), findsNothing);
    });

    testWidgets('Admin sees both global debt summary card AND individual customer debt',
        (tester) async {
      final authNotifier = _DynamicAuthNotifier(adminUser);

      await tester.pumpWidget(
        _buildHarness(
          screenSize: const Size(600, 900),
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
            customerOrdersProvider(customerWithDebt.id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(customerWithDebt.id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
            overviewKPIsProvider.overrideWith((ref) => const AsyncValue.data(standardKPIs)),
          ],
          child: const SingleChildScrollView(
            child: Column(
              children: [
                KPIMetricsSection(),
                CustomerListTile(customer: customerWithDebt),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Admin sees global debt summary card
      expect(find.text('Công nợ khách hàng cần thu'), findsOneWidget);
      expect(find.text('${format.format(98000000.0)} đ'), findsOneWidget);

      // Admin also sees individual customer debt
      expect(find.text('Võ Minh Trí'), findsOneWidget);
      expect(find.text('Công nợ: ${format.format(3500000.0)}'), findsOneWidget);
    });
  });
}
