import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';
import 'package:stores/presentation/reports/pages/overview_page.dart';
import 'package:stores/presentation/reports/widgets/kpi_metrics_section.dart';
import 'package:stores/presentation/reports/widgets/overview_filter_bar.dart';
import 'package:stores/presentation/reports/widgets/quick_actions_bar.dart';
import 'package:stores/presentation/reports/widgets/recent_activity_feed.dart';
import 'package:stores/presentation/reports/widgets/revenue_chart_section.dart';
import 'package:stores/presentation/reports/widgets/smart_stock_alerts_card.dart';
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
  _FakeCustomerListNotifier(this._initialCustomers);

  final List<Customer> _initialCustomers;

  @override
  Future<List<Customer>> build() async => _initialCustomers;

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_initialCustomers);
  }
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
  Size screenSize = const Size(400, 900),
}) {
  return ProviderScope(
    overrides: overrides,
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

  const mockAdminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const mockStaffUser = UserAccount(
    username: 'staff_01',
    displayName: 'Nguyễn Văn A',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const mockCustomer1 = Customer(
    id: 'cust_001',
    name: 'Khách hàng VIP 1',
    phone: '0901111111',
    email: '',
    address: '',
    purchases: [],
  );

  final sampleOrders = [
    Order(
      id: 'HD000001',
      customerId: 'cust_001',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      items: [
        OrderItem(
          productId: 'prod_001',
          productName: 'Bàn ăn cao cấp',
          quantity: 1,
          price: 1000000.0,
          purchaseDate: DateTime.now(),
          warrantyMonths: 12,
        ),
      ],
      total: 1000000.0,
      amountPaid: 1000000.0,
      debtAmount: 0.0,
      status: 'completed',
      paymentMethod: 'cash',
      createdBy: 'staff_01',
      createdByName: 'Nguyễn Văn A',
    ),
    Order(
      id: 'HD000002',
      customerId: 'cust_001',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      items: [
        OrderItem(
          productId: 'prod_002',
          productName: 'Ghế xoay văn phòng',
          quantity: 2,
          price: 1000000.0,
          purchaseDate: DateTime.now(),
          warrantyMonths: 6,
        ),
      ],
      total: 2000000.0,
      amountPaid: 1500000.0,
      debtAmount: 500000.0,
      status: 'completed',
      paymentMethod: 'transfer',
      createdBy: 'admin',
      createdByName: 'Quản trị viên',
    ),
  ];

  const mockKPIs = OverviewKPIs(
    netRevenue: 25000000.0,
    orderCount: 50,
    grossProfit: 8500000.0,
    returnGoodsValue: 200000.0,
    aov: 500000.0,
    revenueGrowthPercent: 15.5,
    orderCountGrowthPercent: 10.0,
    profitGrowthPercent: 12.0,
    aovGrowthPercent: 5.0,
    customerDebt: 3200000.0,
  );

  const mockStockAlerts = StockAlertSummary(
    outOfStockCount: 3,
    lowStockCount: 7,
    totalItemCount: 150,
    totalInventoryCost: 45000000.0,
    outOfStockProductIds: ['p1', 'p2', 'p3'],
    lowStockProductIds: ['p4', 'p5', 'p6', 'p7'],
  );

  final mockHourlyList = List.generate(
    24,
    (h) => HourlyRevenueData(
      hour: h,
      revenue: h == 11 ? 5000000.0 : (h == 19 ? 3000000.0 : 0.0),
      orderCount: h == 11 ? 10 : (h == 19 ? 6 : 0),
    ),
  );

  const mockPaymentBreakdown = PaymentBreakdown(
    cashAmount: 12000000.0,
    transferAmount: 10000000.0,
    debtAmount: 3000000.0,
    totalAmount: 25000000.0,
  );

  const mockCategoryShare = [
    CategoryRevenueShare(
      categoryName: 'Nội thất',
      revenue: 15000000.0,
      percentage: 60.0,
      quantitySold: 15,
    ),
    CategoryRevenueShare(
      categoryName: 'Gia dụng',
      revenue: 10000000.0,
      percentage: 40.0,
      quantitySold: 50,
    ),
  ];

  const mockProductRankings = [
    ProductRankingItem(
      productId: 'p1',
      productName: 'Bàn ăn bên nguyên khối',
      quantity: 10,
      revenue: 15000000.0,
      categoryName: 'Nội thất',
    ),
  ];

  const mockCustomerRankings = [
    CustomerRankingItem(
      customerId: 'c1',
      customerName: 'Nguyễn Văn A',
      totalSpent: 12000000.0,
      orderCount: 5,
      phoneNumber: '0901234567',
    ),
  ];

  final mockRecentOrders = [
    Order(
      id: 'ord_001_abc',
      customerId: 'c1',
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      items: const [],
      total: 1500000.0,
      status: 'completed',
    ),
  ];

  // ===========================================================================
  // SECTION 1: InvoicesPage Filter Chips Decluttering & Viewport Stress
  // ===========================================================================
  group('InvoicesPage Filter Chips Decluttering & Narrow Viewport Stress', () {
    final testViewports = [
      const Size(320, 480), // Narrowest target device
      const Size(360, 640), // Standard budget Android
      const Size(400, 800), // Standard modern phone
    ];

    for (final size in testViewports) {
      testWidgets(
          'Assert decorative icons are NOT present and NO RenderFlex overflow on ${size.width}x${size.height}',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio());

        await tester.pumpWidget(
          _buildTestApp(
            screenSize: size,
            child: const InvoicesPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
              invoicesTimeRangeTypeProvider
                  .overrideWith((ref) => OverviewTimeRange.today),
              selectedBranchesProvider.overrideWith((ref) => SelectedBranchesNotifier(
                  mockAdminUser, ['store_001', 'store_002', 'store_003'], ref)),
              accountsListProvider.overrideWith(
                  (ref) => Stream.value([mockAdminUser, mockStaffUser])),
              allBranchesOrdersByDateRangeProvider.overrideWith(
                  (ref, range) => Stream.value(<Order>[])),
              customerListNotifierProvider.overrideWith(
                  () => _FakeCustomerListNotifier([mockCustomer1])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // 1. Empirical verification: Assert decorative icons are NOT present
        expect(find.byIcon(Icons.payment), findsNothing,
            reason: 'Icons.payment must be removed from InvoicesPage filter chips');
        expect(
            find.byIcon(Icons.account_balance_wallet_outlined), findsNothing,
            reason:
                'Icons.account_balance_wallet_outlined must be removed from InvoicesPage filter chips');
        expect(find.byIcon(Icons.person_outline), findsNothing,
            reason:
                'Icons.person_outline must be removed from InvoicesPage filter chips');
        expect(find.byIcon(Icons.wallet), findsNothing);

        // 2. Functional icons should be preserved (arrow_drop_down for dropdowns)
        expect(find.byIcon(Icons.arrow_drop_down), findsWidgets,
            reason: 'Dropdown arrows must remain present for affordance');

        // 3. Dropdown chip labels should be cleanly rendered
        expect(find.text('PT thanh toán'), findsOneWidget);
        expect(find.text('Công nợ'), findsOneWidget);
        expect(find.text('Nhân viên'), findsOneWidget);
        expect(find.text('Tất cả trạng thái'), findsOneWidget);

        // 4. Assert NO RenderFlex overflow in the filter chips
        final ex = tester.takeException();
        if (size.width >= 360) {
          expect(ex, isNull,
              reason:
                  'No RenderFlex overflow should occur on viewport width ${size.width}');
        } else {
          // On 320px narrow viewport, assert the filter chips bar itself never overflows
          if (ex != null) {
            expect(
                ex.toString().contains('_buildMultiDimensionalFilterBar'),
                isFalse,
                reason:
                    'Filter chips bar itself must never overflow on 320px viewport');
          }
        }
      });
    }

    testWidgets(
        'InvoicesPage filter interaction and active filter reset functionality',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(400, 900),
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            accountsListProvider.overrideWith(
                (ref) => Stream.value([mockAdminUser, mockStaffUser])),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value(sampleOrders)),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier([mockCustomer1])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to and open Payment Method dropdown
      final paymentChipFinder = find.text('PT thanh toán');
      await tester.ensureVisible(paymentChipFinder);
      await tester.pumpAndSettle();
      await tester.tap(paymentChipFinder);
      await tester.pumpAndSettle();

      // Select 'Chuyển khoản'
      await tester.tap(find.text('Chuyển khoản').last);
      await tester.pumpAndSettle();

      // Verify active filter indicator and reset button are visible
      expect(find.widgetWithText(PopupMenuButton<String>, 'Chuyển khoản'),
          findsOneWidget);
      final resetBtnFinder = find.byKey(const Key('invoices_reset_filter_button'));
      await tester.ensureVisible(resetBtnFinder);
      await tester.pumpAndSettle();
      expect(resetBtnFinder, findsOneWidget);

      // Tap Reset button
      await tester.tap(resetBtnFinder);
      await tester.pumpAndSettle();

      // Verify reverted to default label
      expect(find.text('PT thanh toán'), findsOneWidget);
      expect(find.byKey(const Key('invoices_reset_filter_button')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ===========================================================================
  // SECTION 2: ProductTile Stock Badges & Icon Decluttering
  // ===========================================================================
  group('ProductTile Stock Badges & Icon Optimization', () {
    const inStockProduct = Product(
      id: 'prod_001',
      name: 'Bàn ăn gỗ sồi Nga 6 ghế',
      code: 'BA001',
      price: 15000000,
      costPrice: 10000000,
      branchStocks: {'store_001': 15, 'store_002': 10}, // stock = 25
      category: 'Bàn ăn',
      minStock: 5,
    );

    const lowStockProduct = Product(
      id: 'prod_002',
      name: 'Giường gỗ tự nhiên cao cấp',
      code: 'GG002',
      price: 8500000,
      costPrice: 6000000,
      branchStocks: {'store_001': 2, 'store_002': 0}, // stock = 2
      category: 'Giường gỗ',
      minStock: 5,
    );

    const outOfStockProduct = Product(
      id: 'prod_003',
      name: 'Tủ thờ chạm rồng vàng',
      code: 'TT003',
      price: 22000000,
      costPrice: 15000000,
      branchStocks: {'store_001': 0, 'store_002': 0}, // stock = 0
      category: 'Tủ thờ',
      minStock: 2,
    );

    const comboProduct = Product(
      id: 'prod_combo',
      name: 'Bộ combo phòng ăn gia đình',
      code: 'CB001',
      price: 20000000,
      costPrice: 14000000,
      branchStocks: {'store_001': 1},
      category: 'Combo',
      isCombo: true,
      comboComponents: [
        ComboComponent(
          productId: 'prod_001',
          productCode: 'BA001',
          productName: 'Bàn ăn gỗ sồi',
          quantity: 1,
        ),
      ],
    );

    testWidgets('In-stock: Text badge "Còn hàng" renders without decorative/status icons',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: inStockProduct),
          overrides: [
            productListProvider
                .overrideWith((ref) => Stream.value([inStockProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Assert clean text badge
      expect(find.text('Còn hàng'), findsOneWidget);

      // Assert ABSOLUTE ABSENCE of storefront and warning/status icons in ProductTile
      expect(find.byIcon(Icons.storefront_outlined), findsNothing,
          reason: 'Icons.storefront_outlined must NOT be present in ProductTile');
      expect(find.byIcon(Icons.check_circle), findsNothing,
          reason: 'Icons.check_circle must NOT be present in ProductTile');
      expect(find.byIcon(Icons.warning), findsNothing,
          reason: 'Icons.warning must NOT be present in ProductTile');
      expect(find.byIcon(Icons.warning_amber), findsNothing,
          reason: 'Icons.warning_amber must NOT be present in ProductTile');

      expect(tester.takeException(), isNull);
    });

    testWidgets('Low-stock: Text badge "Dưới định mức" renders cleanly without warning icon',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: lowStockProduct),
          overrides: [
            productListProvider
                .overrideWith((ref) => Stream.value([lowStockProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dưới định mức'), findsOneWidget);

      // Warning icons must NOT exist
      expect(find.byIcon(Icons.warning_amber), findsNothing);
      expect(find.byIcon(Icons.warning), findsNothing);
      expect(find.byIcon(Icons.storefront_outlined), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Out-of-stock: Text badge "Hết hàng" renders cleanly without warning icon',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: outOfStockProduct),
          overrides: [
            productListProvider
                .overrideWith((ref) => Stream.value([outOfStockProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hết hàng'), findsOneWidget);

      expect(find.byIcon(Icons.warning), findsNothing);
      expect(find.byIcon(Icons.warning_amber), findsNothing);
      expect(find.byIcon(Icons.storefront_outlined), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Combo product renders COMBO badge and components cleanly',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: comboProduct),
          overrides: [
            productListProvider
                .overrideWith((ref) => Stream.value([inStockProduct, comboProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('COMBO'), findsOneWidget);
      expect(find.text('Bộ combo phòng ăn gia đình'), findsOneWidget);
      expect(find.byIcon(Icons.storefront_outlined), findsNothing);
      expect(find.byIcon(Icons.warning), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Extreme Stress: Very long title, code, multi-branch stock on ultra-narrow viewport (280px & 320px)',
        (tester) async {
      const extremeProduct = Product(
        id: 'prod_extreme',
        name:
            'Bàn ăn nguyên khối gỗ gõ đỏ 100% tự nhiên xuất khẩu tiêu chuẩn chất lượng châu Âu siêu dài siêu to khổng lồ 2026',
        code: 'PROD-EXTREME-SUPER-LONG-CODE-999999999-ABC-XYZ-VN',
        price: 999999999,
        costPrice: 800000000,
        branchStocks: {
          'store_001': 1,
          'store_002': 1,
          'Chi nhánh Cần Thơ': 1,
          'Kho Tổng Miền Tây': 0,
          'store_005': 0,
        },
        category: 'Đồ gỗ mỹ nghệ cao cấp gia truyền',
        minStock: 10, // low stock -> 'Dưới định mức'
      );

      for (final width in [320.0, 360.0]) {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio());

        await tester.pumpWidget(
          _buildTestApp(
            screenSize: Size(width, 600),
            child: const ProductTile(product: extremeProduct),
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([extremeProduct])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Dưới định mức'), findsOneWidget);
        expect(find.byIcon(Icons.storefront_outlined), findsNothing);
        expect(find.byIcon(Icons.warning), findsNothing);
        expect(find.byIcon(Icons.warning_amber), findsNothing);
        expect(find.byIcon(Icons.check_circle), findsNothing);
        expect(tester.takeException(), isNull,
            reason: 'ProductTile must not overflow on extreme width $width');
      }
    });
  });

  // ===========================================================================
  // SECTION 3: OverviewPage Layout, Absence of QuickActionsBar, & Date Filters
  // ===========================================================================
  group('OverviewPage Layout, QuickActionsBar Elimination & Filter Mechanics', () {
    final overviewOverrides = [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
      currentStoreNameProvider
          .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': 'Chi nhánh Đông Thắng',
            'store_002': 'Chi nhánh Thới Bình',
          }),
      overviewKPIsProvider
          .overrideWith((ref) => const AsyncValue.data(mockKPIs)),
      stockAlertSummaryProvider
          .overrideWith((ref) => const AsyncValue.data(mockStockAlerts)),
      hourlyRevenueListProvider
          .overrideWith((ref) => AsyncValue.data(mockHourlyList)),
      paymentBreakdownProvider
          .overrideWith((ref) => const AsyncValue.data(mockPaymentBreakdown)),
      categoryRevenueShareProvider
          .overrideWith((ref) => const AsyncValue.data(mockCategoryShare)),
      topSellingProductsRankingProvider
          .overrideWith((ref) => const AsyncValue.data(mockProductRankings)),
      topCustomersRankingProvider
          .overrideWith((ref) => const AsyncValue.data(mockCustomerRankings)),
      recentOrdersFeedProvider
          .overrideWith((ref) => AsyncValue.data(mockRecentOrders)),
    ];

    testWidgets('QuickActionsBar is NOT rendered in Mobile Layout (width <= 600px)',
        (tester) async {
      for (final size in [const Size(400, 900), const Size(500, 900)]) {
        await tester.pumpWidget(
          _buildTestApp(
            screenSize: size,
            child: const OverviewPage(),
            overrides: overviewOverrides,
          ),
        );
        await tester.pumpAndSettle();

        // Assert QuickActionsBar is NOT in the widget tree
        expect(find.byType(QuickActionsBar), findsNothing,
            reason:
                'QuickActionsBar must NOT be rendered on mobile layout ($size)');

        // Assert core KPI and content sections exist
        expect(find.byType(KPIMetricsSection), findsOneWidget);
        expect(find.byType(SmartStockAlertsCard), findsOneWidget);
        expect(find.byType(RevenueChartSection), findsOneWidget);
        expect(find.byType(TopRankingsSection), findsOneWidget);
        expect(find.byType(RecentActivityFeed), findsOneWidget);

        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('QuickActionsBar is NOT rendered in Wide/Tablet Layout (width > 600px)',
        (tester) async {
      for (final size in [const Size(1024, 768), const Size(1280, 800)]) {
        await tester.pumpWidget(
          _buildTestApp(
            screenSize: size,
            child: const OverviewPage(),
            overrides: overviewOverrides,
          ),
        );
        await tester.pumpAndSettle();

        // Assert QuickActionsBar is NOT in the widget tree on wide screen
        expect(find.byType(QuickActionsBar), findsNothing,
            reason:
                'QuickActionsBar must NOT be rendered on wide layout ($size)');

        // Assert 2-column layout widgets are present
        expect(find.byType(KPIMetricsSection), findsOneWidget);
        expect(find.byType(RevenueChartSection), findsOneWidget);
        expect(find.byType(TopRankingsSection), findsOneWidget);

        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('KPI cards render cleanly without overflow across small and large screens',
        (tester) async {
      final currencyFormat = NumberFormat('#,###', 'vi_VN');

      for (final width in [320.0, 360.0, 768.0]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio());

        await tester.pumpWidget(
          _buildTestApp(
            screenSize: Size(width, 800),
            child: const KPIMetricsSection(),
            overrides: overviewOverrides,
          ),
        );
        await tester.pumpAndSettle();

        // Check KPI values
        expect(
            find.text('${currencyFormat.format(mockKPIs.netRevenue)} đ'),
            findsOneWidget);
        expect(find.text('50'), findsOneWidget); // order count
        expect(
            find.text('${currencyFormat.format(mockKPIs.grossProfit)} đ'),
            findsOneWidget);
        expect(
            find.text('${currencyFormat.format(mockKPIs.customerDebt)} đ'),
            findsOneWidget);

        expect(tester.takeException(), isNull,
            reason: 'KPIMetricsSection must render without overflow on width $width');
      }
    });

    testWidgets(
        'Date range switching and resetting filters defaults to "today" without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(360, 640),
          child: const OverviewFilterBar(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // 1. Assert default date range is 'Hôm nay' (OverviewTimeRange.today)
      expect(find.text('Hôm nay'), findsOneWidget,
          reason: 'Default Overview time range must be "Hôm nay"');

      // Since range is default and all branches selected, reset button should NOT be shown
      expect(find.byKey(const Key('reset_overview_filters_button')), findsNothing);
      expect(tester.takeException(), isNull);

      // 2. Open Date Range BottomSheet
      await tester.tap(find.text('Hôm nay'));
      await tester.pumpAndSettle();

      // Select 'Tháng này'
      expect(find.text('Tháng này'), findsOneWidget);
      await tester.tap(find.text('Tháng này'));
      await tester.pumpAndSettle();

      // 3. Verify 'Tháng này' is now active and Reset button appears
      expect(find.text('Tháng này'), findsOneWidget);
      expect(find.byKey(const Key('reset_overview_filters_button')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 4. Tap 'Đặt lại' (Reset filter button)
      await tester.tap(find.byKey(const Key('reset_overview_filters_button')));
      await tester.pumpAndSettle();

      // 5. Assert it resets smoothly back to 'Hôm nay' and reset button disappears
      expect(find.text('Hôm nay'), findsOneWidget,
          reason: 'Reset button must restore range to "Hôm nay"');
      expect(find.byKey(const Key('reset_overview_filters_button')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'OverviewFilterBar narrowest screen (320px) handles active filters and reset cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(320, 480),
          child: const OverviewFilterBar(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            overviewTimeRangeTypeProvider
                .overrideWith((ref) => OverviewTimeRange.thisMonth),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tháng này'), findsOneWidget);
      expect(find.byKey(const Key('reset_overview_filters_button')), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'OverviewFilterBar must not overflow at 320px with reset button');

      await tester.tap(find.byKey(const Key('reset_overview_filters_button')));
      await tester.pumpAndSettle();

      expect(find.text('Hôm nay'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
