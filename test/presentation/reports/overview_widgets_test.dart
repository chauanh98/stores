import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/revenue_report.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/reports/pages/overview_page.dart';
import 'package:stores/presentation/reports/widgets/kpi_metrics_section.dart';
import 'package:stores/presentation/reports/widgets/overview_filter_bar.dart';
import 'package:stores/presentation/reports/widgets/overview_header.dart';
import 'package:stores/presentation/reports/widgets/payment_category_breakdown_section.dart';
import 'package:stores/presentation/reports/widgets/quick_actions_bar.dart';
import 'package:stores/presentation/reports/widgets/recent_activity_feed.dart';
import 'package:stores/presentation/reports/widgets/revenue_chart_section.dart';
import 'package:stores/presentation/reports/widgets/smart_stock_alerts_card.dart';
import 'package:stores/presentation/reports/widgets/top_rankings_section.dart';

class FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

Widget _createTestableWidget({
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
  final format = NumberFormat('#,###', 'vi_VN');

  const mockAdminUser = UserAccount(
    username: 'admin',
    displayName: 'Admin User',
    role: 'admin',
    storeId: 'store_001',
  );

  const mockSupervisorUser = UserAccount(
    username: 'sup',
    displayName: 'Supervisor User',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const mockStaffUser = UserAccount(
    username: 'staff',
    displayName: 'Staff User',
    role: 'nhanvien',
    storeId: 'store_001',
  );

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
      categoryName: 'Điện thoại',
      revenue: 15000000.0,
      percentage: 60.0,
      quantitySold: 15,
    ),
    CategoryRevenueShare(
      categoryName: 'Phụ kiện',
      revenue: 10000000.0,
      percentage: 40.0,
      quantitySold: 50,
    ),
  ];

  const mockProductRankings = [
    ProductRankingItem(
      productId: 'p1',
      productName: 'iPhone 15 Pro Max',
      quantity: 10,
      revenue: 15000000.0,
      categoryName: 'Điện thoại',
    ),
    ProductRankingItem(
      productId: 'p2',
      productName: 'Củ sạc 20W',
      quantity: 40,
      revenue: 8000000.0,
      categoryName: 'Phụ kiện',
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
    CustomerRankingItem(
      customerId: 'c2',
      customerName: 'Trần Thị B',
      totalSpent: 8000000.0,
      orderCount: 3,
      phoneNumber: '0987654321',
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
    Order(
      id: 'ord_002_def',
      customerId: 'c2',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      items: const [],
      total: 750000.0,
      status: 'pending',
    ),
  ];

  group('OverviewHeader Widget Tests', () {
    testWidgets('Renders app title, logo, admin badge, and current store name for admin (no refresh icon)',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const OverviewHeader(),
          overrides: [
            authProvider.overrideWith((ref) => FakeAuthNotifier(mockAdminUser)),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Đã đồng bộ'), findsOneWidget);
      expect(find.byIcon(Icons.insert_chart_rounded), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    });

    testWidgets('Renders supervisor badge and current store name for supervisor (no refresh icon)',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const OverviewHeader(),
          overrides: [
            authProvider
                .overrideWith((ref) => FakeAuthNotifier(mockSupervisorUser)),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Giám sát'), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    });

    testWidgets('Renders current store name and no role badge for staff user (no refresh icon)',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const OverviewHeader(),
          overrides: [
            authProvider.overrideWith((ref) => FakeAuthNotifier(mockStaffUser)),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Admin'), findsNothing);
      expect(find.text('Giám sát'), findsNothing);
      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    });
  });

  group('OverviewFilterBar Widget Tests', () {
    testWidgets('Renders single-row layout with Date Range and Branch dropdowns',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const OverviewFilterBar(),
          overrides: [
            authProvider.overrideWith((ref) => FakeAuthNotifier(mockAdminUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tháng này'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_rounded), findsOneWidget);
      expect(find.byIcon(Icons.store_rounded), findsOneWidget);
      expect(find.text('Tất cả chi nhánh'), findsOneWidget);

      // Redundant quick chip row is removed from main bar
      expect(find.text('Hôm nay'), findsNothing);
      expect(find.text('Hôm qua'), findsNothing);
      expect(find.text('7 ngày qua'), findsNothing);
      expect(find.text('Tháng trước'), findsNothing);
      expect(find.text('Tùy chỉnh'), findsNothing);
    });

    testWidgets('Tapping date range dropdown opens modal bottom sheet and selects range',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const OverviewFilterBar(),
          overrides: [
            authProvider.overrideWith((ref) => FakeAuthNotifier(mockAdminUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap date range dropdown
      await tester.tap(find.text('Tháng này'));
      await tester.pumpAndSettle();

      // BottomSheet opens showing all options
      expect(find.text('Chọn khoảng thời gian'), findsOneWidget);
      expect(find.text('Hôm nay'), findsOneWidget);
      expect(find.text('Hôm qua'), findsOneWidget);
      expect(find.text('7 ngày qua'), findsOneWidget);
      expect(find.text('Tháng trước'), findsOneWidget);
      expect(find.text('Tùy chỉnh'), findsOneWidget);

      // Tap 'Hôm nay'
      await tester.tap(find.text('Hôm nay'));
      await tester.pumpAndSettle();

      // Modal closed and filter bar updated to 'Hôm nay'
      expect(find.text('Hôm nay'), findsOneWidget);
    });

    testWidgets('Tapping branch dropdown opens branch selector modal',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const OverviewFilterBar(),
          overrides: [
            authProvider.overrideWith((ref) => FakeAuthNotifier(mockAdminUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap branch dropdown
      await tester.tap(find.text('Tất cả chi nhánh'));
      await tester.pumpAndSettle();

      expect(find.text('Chọn chi nhánh lọc'), findsOneWidget);
      expect(find.text('Chọn tất cả'), findsOneWidget);
      expect(find.text('Xong'), findsOneWidget);
    });
  });

  group('QuickActionsBar Widget Tests (R6)', () {
    testWidgets('Renders 5 quick action buttons', (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const QuickActionsBar(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thao tác nhanh'), findsOneWidget);
      expect(find.text('Bán hàng'), findsOneWidget);
      expect(find.text('Nhập hàng'), findsOneWidget);
      expect(find.text('Chuyển kho'), findsOneWidget);
      expect(find.text('Sổ nợ khách'), findsOneWidget);
      expect(find.text('Hàng hóa'), findsOneWidget);
    });
  });

  group('KPIMetricsSection Widget Tests (R1)', () {
    testWidgets(
        'Renders revenue and customer debt card for Admin, but hides Gross Profit (canViewCostPrice == false)',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const KPIMetricsSection(),
          overrides: [
            authProvider.overrideWith((ref) => FakeAuthNotifier(mockAdminUser)),
            profitVisibilityProvider.overrideWith((ref) => true),
            overviewKPIsProvider.overrideWith(
                (ref) => const AsyncValue.data(mockKPIs)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Doanh thu thuần'), findsOneWidget);
      expect(find.text('${format.format(25000000.0)} đ'), findsOneWidget);
      expect(find.text('+15.5%'), findsOneWidget);
      // Profit is hidden for Admin
      expect(find.text('Lợi nhuận gộp'), findsNothing);
      expect(find.text('${format.format(8500000.0)} đ'), findsNothing);
      // Customer debt summary is visible for Admin
      expect(find.text('Công nợ khách hàng cần thu'), findsOneWidget);
      expect(find.text('${format.format(3200000.0)} đ'), findsOneWidget);
      expect(find.text('Sổ nợ'), findsOneWidget);
    });

    testWidgets(
        'Renders customer debt card and profit section for Supervisor (canViewCostPrice == true)',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const KPIMetricsSection(),
          overrides: [
            authProvider
                .overrideWith((ref) => FakeAuthNotifier(mockSupervisorUser)),
            profitVisibilityProvider.overrideWith((ref) => true),
            overviewKPIsProvider.overrideWith(
                (ref) => const AsyncValue.data(mockKPIs)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Doanh thu thuần'), findsOneWidget);
      expect(find.text('Lợi nhuận gộp'), findsOneWidget);
      expect(find.text('${format.format(8500000.0)} đ'), findsOneWidget);
      expect(find.text('Công nợ khách hàng cần thu'), findsOneWidget);
      expect(find.text('${format.format(3200000.0)} đ'), findsOneWidget);
      expect(find.text('Sổ nợ'), findsOneWidget);
    });

    testWidgets(
        'Hides customer debt card and profit section for Staff role',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const KPIMetricsSection(),
          overrides: [
            authProvider.overrideWith((ref) => FakeAuthNotifier(mockStaffUser)),
            profitVisibilityProvider.overrideWith((ref) => true),
            overviewKPIsProvider.overrideWith(
                (ref) => const AsyncValue.data(mockKPIs)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Doanh thu thuần'), findsOneWidget);
      expect(find.text('${format.format(25000000.0)} đ'), findsOneWidget);
      // Profit is hidden for staff
      expect(find.text('Lợi nhuận gộp'), findsNothing);
      // Debt card is completely omitted for staff
      expect(find.text('Công nợ khách hàng cần thu'), findsNothing);
      expect(find.text('Sổ nợ'), findsNothing);
    });

    testWidgets('Toggling eye icon hides/shows profit for supervisor', (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const KPIMetricsSection(),
          overrides: [
            authProvider
                .overrideWith((ref) => FakeAuthNotifier(mockSupervisorUser)),
            profitVisibilityProvider.overrideWith((ref) => true),
            overviewKPIsProvider.overrideWith(
                (ref) => const AsyncValue.data(mockKPIs)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('${format.format(8500000.0)} đ'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      expect(find.text('*** ***'), findsOneWidget);
    });
  });

  group('SmartStockAlertsCard Widget Tests (R3)', () {
    testWidgets('Renders Out-of-Stock, Low-Stock counts and valuations for Supervisor',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const SmartStockAlertsCard(),
          overrides: [
            authProvider
                .overrideWith((ref) => FakeAuthNotifier(mockSupervisorUser)),
            stockAlertSummaryProvider.overrideWith(
                (ref) => const AsyncValue.data(mockStockAlerts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cảnh báo kho & Vận hành'), findsOneWidget);
      expect(find.text('Hết hàng'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Sắp hết hàng'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('150 sản phẩm'), findsOneWidget);
      expect(find.text('${format.format(45000000.0)} đ'), findsOneWidget);
      expect(find.text('Nhập hàng'), findsOneWidget);
    });

    testWidgets('Renders stock counts but hides cost valuation for Admin (canViewCostPrice == false)',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const SmartStockAlertsCard(),
          overrides: [
            authProvider.overrideWith((ref) => FakeAuthNotifier(mockAdminUser)),
            stockAlertSummaryProvider.overrideWith(
                (ref) => const AsyncValue.data(mockStockAlerts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cảnh báo kho & Vận hành'), findsOneWidget);
      expect(find.text('Hết hàng'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Sắp hết hàng'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('150 sản phẩm'), findsOneWidget);
      expect(find.text('Giá trị kho (Giá vốn)'), findsNothing);
      expect(find.text('${format.format(45000000.0)} đ'), findsNothing);
    });
  });

  group('RevenueChartSection Widget Tests (R2 & R3)', () {
    testWidgets('Renders hourly peak chart and peak rush hour badge for single day',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const RevenueChartSection(),
          overrides: [
            overviewTimeRangeTypeProvider
                .overrideWith((ref) => OverviewTimeRange.today),
            hourlyRevenueListProvider.overrideWith(
                (ref) => AsyncValue.data(mockHourlyList)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Doanh thu theo giờ trong ngày'), findsOneWidget);
      expect(find.textContaining('Khung giờ cao điểm: 11:00 - 12:00'),
          findsOneWidget);
    });

    testWidgets('Toggles between chart and list view in hourly mode',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const RevenueChartSection(),
          overrides: [
            overviewTimeRangeTypeProvider
                .overrideWith((ref) => OverviewTimeRange.today),
            hourlyRevenueListProvider.overrideWith(
                (ref) => AsyncValue.data(mockHourlyList)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Switch to list view
      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      expect(find.text('11:00'), findsOneWidget);
      expect(find.text('19:00'), findsOneWidget);
      expect(find.text('10 đơn'), findsOneWidget);
      expect(find.text('6 đơn'), findsOneWidget);
    });

    testWidgets(
        'Renders multi-day daily chart and toggles to daily list view (7 days)',
        (tester) async {
      final range7d = DateTimeRange(
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 16),
      );
      final mock7dSummary = RevenueSummary(
        startDate: range7d.start,
        endDate: range7d.end,
        totalRevenue: 7000000.0,
        totalCost: 4200000.0,
        totalProfit: 2800000.0,
        totalOrders: 14,
        totalItemsSold: 28,
        dailyReports: [
          RevenueReport(
            date: DateTime(2026, 8, 10),
            totalRevenue: 3000000.0,
            totalCost: 1800000.0,
            profit: 1200000.0,
            totalOrders: 6,
            totalItemsSold: 12,
            productRevenues: const [],
          ),
          RevenueReport(
            date: DateTime(2026, 8, 15),
            totalRevenue: 4000000.0,
            totalCost: 2400000.0,
            profit: 1600000.0,
            totalOrders: 8,
            totalItemsSold: 16,
            productRevenues: const [],
          ),
        ],
      );

      await tester.pumpWidget(
        _createTestableWidget(
          child: const RevenueChartSection(),
          overrides: [
            overviewActiveDateRangeProvider.overrideWith((ref) => range7d),
            revenueByDateRangeProvider(range7d)
                .overrideWith((ref) => Stream.value(mock7dSummary)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Biểu đồ doanh thu'), findsOneWidget);

      // Toggle to List View
      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      expect(find.text('15/08/2026'), findsOneWidget);
      expect(find.text('10/08/2026'), findsOneWidget);
      expect(find.text('${format.format(4000000.0)} đ'), findsOneWidget);
      expect(find.text('(8 đơn)'), findsOneWidget);
    });

    testWidgets(
        'Renders weekly grouped aggregation and weekly list view for 32..60 days (45 days)',
        (tester) async {
      final range45d = DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 8, 14),
      );
      final mockWeeklySummary = RevenueSummary(
        startDate: range45d.start,
        endDate: range45d.end,
        totalRevenue: 15000000.0,
        totalCost: 9000000.0,
        totalProfit: 6000000.0,
        totalOrders: 30,
        totalItemsSold: 60,
        dailyReports: [
          RevenueReport(
            date: DateTime(2026, 7, 3), // Week 1 July
            totalRevenue: 5000000.0,
            totalCost: 3000000.0,
            profit: 2000000.0,
            totalOrders: 10,
            totalItemsSold: 20,
            productRevenues: const [],
          ),
          RevenueReport(
            date: DateTime(2026, 7, 10), // Week 2 July
            totalRevenue: 10000000.0,
            totalCost: 6000000.0,
            profit: 4000000.0,
            totalOrders: 20,
            totalItemsSold: 40,
            productRevenues: const [],
          ),
        ],
      );

      await tester.pumpWidget(
        _createTestableWidget(
          child: const RevenueChartSection(),
          overrides: [
            overviewActiveDateRangeProvider.overrideWith((ref) => range45d),
            revenueByDateRangeProvider(range45d)
                .overrideWith((ref) => Stream.value(mockWeeklySummary)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Biểu đồ doanh thu'), findsOneWidget);

      // Toggle to List View
      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Tuần 2 - Tháng 07/2026'), findsOneWidget);
      expect(find.text('Tuần 1 - Tháng 07/2026'), findsOneWidget);
      expect(find.text('${format.format(10000000.0)} đ'), findsOneWidget);
      expect(find.text('(20 đơn)'), findsOneWidget);
    });

    testWidgets(
        'Renders monthly grouped aggregation and monthly list view for > 60 days (90 days)',
        (tester) async {
      final range90d = DateTimeRange(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 7, 30),
      );
      final mockMonthlySummary = RevenueSummary(
        startDate: range90d.start,
        endDate: range90d.end,
        totalRevenue: 50000000.0,
        totalCost: 30000000.0,
        totalProfit: 20000000.0,
        totalOrders: 100,
        totalItemsSold: 200,
        dailyReports: [
          RevenueReport(
            date: DateTime(2026, 5, 15),
            totalRevenue: 20000000.0,
            totalCost: 12000000.0,
            profit: 8000000.0,
            totalOrders: 40,
            totalItemsSold: 80,
            productRevenues: const [],
          ),
          RevenueReport(
            date: DateTime(2026, 6, 20),
            totalRevenue: 30000000.0,
            totalCost: 18000000.0,
            profit: 12000000.0,
            totalOrders: 60,
            totalItemsSold: 120,
            productRevenues: const [],
          ),
        ],
      );

      await tester.pumpWidget(
        _createTestableWidget(
          child: const RevenueChartSection(),
          overrides: [
            overviewActiveDateRangeProvider.overrideWith((ref) => range90d),
            revenueByDateRangeProvider(range90d)
                .overrideWith((ref) => Stream.value(mockMonthlySummary)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Biểu đồ doanh thu'), findsOneWidget);

      // Toggle to List View
      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Tháng 06/2026'), findsOneWidget);
      expect(find.text('Tháng 05/2026'), findsOneWidget);
      expect(find.text('${format.format(30000000.0)} đ'), findsOneWidget);
      expect(find.text('(60 đơn)'), findsOneWidget);
    });

    testWidgets('Renders multi-store legend when multiple stores are available',
        (tester) async {
      final range7d = DateTimeRange(
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 16),
      );
      final mockSummary = RevenueSummary(
        startDate: range7d.start,
        endDate: range7d.end,
        totalRevenue: 10000000.0,
        totalCost: 6000000.0,
        totalProfit: 4000000.0,
        totalOrders: 20,
        totalItemsSold: 40,
        dailyReports: [
          RevenueReport(
            date: DateTime(2026, 8, 12),
            totalRevenue: 10000000.0,
            totalCost: 6000000.0,
            profit: 4000000.0,
            totalOrders: 20,
            totalItemsSold: 40,
            productRevenues: const [],
            storeRevenues: {
              'store_001': 6000000.0,
              'store_002': 4000000.0,
            },
          ),
        ],
      );

      await tester.pumpWidget(
        _createTestableWidget(
          child: const RevenueChartSection(),
          overrides: [
            overviewActiveDateRangeProvider.overrideWith((ref) => range7d),
            revenueByDateRangeProvider(range7d)
                .overrideWith((ref) => Stream.value(mockSummary)),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thời Bình',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.text('Chi nhánh Thời Bình'), findsOneWidget);
    });
  });

  group('PaymentCategoryBreakdownSection Widget Tests (R4)', () {
    testWidgets('Renders payment breakdown and category shares',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const PaymentCategoryBreakdownSection(),
          overrides: [
            paymentBreakdownProvider.overrideWith(
                (ref) => const AsyncValue.data(mockPaymentBreakdown)),
            categoryRevenueShareProvider.overrideWith(
                (ref) => const AsyncValue.data(mockCategoryShare)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cơ cấu phương thức thanh toán'), findsOneWidget);
      expect(find.text('Tiền mặt'), findsOneWidget);
      expect(find.text('Chuyển khoản / QR'), findsOneWidget);
      expect(find.text('Ghi nợ khách'), findsOneWidget);

      expect(find.text('Doanh thu theo danh mục'), findsOneWidget);
      expect(find.text('Điện thoại'), findsOneWidget);
      expect(find.text('Phụ kiện'), findsOneWidget);
      expect(find.text('60.0%'), findsOneWidget);
      expect(find.text('40.0%'), findsOneWidget);
    });
  });

  group('TopRankingsSection Widget Tests (R5)', () {
    testWidgets('Renders top selling products and top customers',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const TopRankingsSection(),
          overrides: [
            topSellingProductsRankingProvider.overrideWith(
                (ref) => const AsyncValue.data(mockProductRankings)),
            topCustomersRankingProvider.overrideWith(
                (ref) => const AsyncValue.data(mockCustomerRankings)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Top hàng bán chạy'), findsOneWidget);
      expect(find.text('iPhone 15 Pro Max'), findsOneWidget);
      expect(find.text('Đã bán: 10'), findsOneWidget);
      expect(find.text('Củ sạc 20W'), findsOneWidget);
      expect(find.text('Đã bán: 40'), findsOneWidget);

      expect(find.text('Top khách hàng chi tiêu'), findsOneWidget);
      expect(find.text('Nguyễn Văn A'), findsOneWidget);
      expect(find.text('Trần Thị B'), findsOneWidget);
    });
  });

  group('RecentActivityFeed Widget Tests (R6)', () {
    testWidgets('Renders recent orders with status badges', (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          child: const RecentActivityFeed(),
          overrides: [
            recentOrdersFeedProvider.overrideWith(
                (ref) => AsyncValue.data(mockRecentOrders)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Giao dịch gần đây'), findsOneWidget);
      expect(find.text('Hoàn thành'), findsOneWidget);
      expect(find.text('Lưu tạm'), findsOneWidget);
    });
  });

  group('OverviewPage Coordinator Widget Tests (M3)', () {
    testWidgets('Renders coordinator layout on mobile screen (<= 600px)',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          screenSize: const Size(390, 844),
          child: const OverviewPage(),
          overrides: [
            authProvider.overrideWith((ref) => FakeAuthNotifier(mockAdminUser)),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thời Bình',
                }),
            overviewKPIsProvider.overrideWith(
                (ref) => const AsyncValue.data(mockKPIs)),
            stockAlertSummaryProvider.overrideWith(
                (ref) => const AsyncValue.data(mockStockAlerts)),
            hourlyRevenueListProvider.overrideWith(
                (ref) => AsyncValue.data(mockHourlyList)),
            paymentBreakdownProvider.overrideWith(
                (ref) => const AsyncValue.data(mockPaymentBreakdown)),
            categoryRevenueShareProvider.overrideWith(
                (ref) => const AsyncValue.data(mockCategoryShare)),
            topSellingProductsRankingProvider.overrideWith(
                (ref) => const AsyncValue.data(mockProductRankings)),
            topCustomersRankingProvider.overrideWith(
                (ref) => const AsyncValue.data(mockCustomerRankings)),
            recentOrdersFeedProvider.overrideWith(
                (ref) => AsyncValue.data(mockRecentOrders)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OverviewHeader), findsOneWidget);
      expect(find.byType(OverviewFilterBar), findsOneWidget);
      expect(find.byType(QuickActionsBar), findsOneWidget);
      expect(find.byType(KPIMetricsSection), findsOneWidget);
      expect(find.byType(SmartStockAlertsCard), findsOneWidget);
      expect(find.byType(RevenueChartSection), findsOneWidget);
      expect(find.byType(PaymentCategoryBreakdownSection), findsOneWidget);
      expect(find.byType(TopRankingsSection), findsOneWidget);
      expect(find.byType(RecentActivityFeed), findsOneWidget);
    });

    testWidgets('Renders 2-column layout on wide screen (> 600px)',
        (tester) async {
      await tester.pumpWidget(
        _createTestableWidget(
          screenSize: const Size(1024, 768),
          child: const OverviewPage(),
          overrides: [
            authProvider.overrideWith((ref) => FakeAuthNotifier(mockAdminUser)),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thời Bình',
                }),
            overviewKPIsProvider.overrideWith(
                (ref) => const AsyncValue.data(mockKPIs)),
            stockAlertSummaryProvider.overrideWith(
                (ref) => const AsyncValue.data(mockStockAlerts)),
            hourlyRevenueListProvider.overrideWith(
                (ref) => AsyncValue.data(mockHourlyList)),
            paymentBreakdownProvider.overrideWith(
                (ref) => const AsyncValue.data(mockPaymentBreakdown)),
            categoryRevenueShareProvider.overrideWith(
                (ref) => const AsyncValue.data(mockCategoryShare)),
            topSellingProductsRankingProvider.overrideWith(
                (ref) => const AsyncValue.data(mockProductRankings)),
            topCustomersRankingProvider.overrideWith(
                (ref) => const AsyncValue.data(mockCustomerRankings)),
            recentOrdersFeedProvider.overrideWith(
                (ref) => AsyncValue.data(mockRecentOrders)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Row), findsWidgets);
      expect(find.byType(QuickActionsBar), findsOneWidget);
      expect(find.byType(KPIMetricsSection), findsOneWidget);
      expect(find.byType(RevenueChartSection), findsOneWidget);
      expect(find.byType(PaymentCategoryBreakdownSection), findsOneWidget);
      expect(find.byType(SmartStockAlertsCard), findsOneWidget);
      expect(find.byType(TopRankingsSection), findsOneWidget);
      expect(find.byType(RecentActivityFeed), findsOneWidget);
    });
  });
}
