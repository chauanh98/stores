import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/revenue_report.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/reports/widgets/revenue_chart_section.dart';

RevenueReport _buildDailyReport({
  required DateTime date,
  required double totalRevenue,
  required double totalCost,
  double? profit,
  int totalOrders = 5,
  int totalItemsSold = 15,
  Map<String, double> storeRevenues = const {},
}) {
  return RevenueReport(
    date: date,
    totalRevenue: totalRevenue,
    totalCost: totalCost,
    profit: profit ?? (totalRevenue - totalCost),
    totalOrders: totalOrders,
    totalItemsSold: totalItemsSold,
    productRevenues: const [],
    storeRevenues: storeRevenues,
  );
}

class _FakeAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

Widget _wrapWidget({
  required Widget child,
  List<Override> overrides = const [],
  Size screenSize = const Size(400, 800),
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: MediaQuery(
        data: MediaQueryData(size: screenSize),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const supervisor = UserAccount(
    username: 'supervisor_user',
    displayName: 'Giám Sát',
    role: 'supervisor',
    storeId: 'store_001',
  );

  final storesMap = {
    'store_001': 'Chi nhánh Quận 1',
    'store_002': 'Chi nhánh Quận 7',
    'store_003': 'Chi nhánh Thủ Đức',
  };

  group('Empirical Widget & UI Stress Testing for R3 RevenueChartSection', () {
    testWidgets('Renders hourly peak chart for 1-day range and toggles to hourly list mode',
        (tester) async {
      final singleDayRange = DateTimeRange(
        start: DateTime(2026, 8, 16),
        end: DateTime(2026, 8, 16, 23, 59, 59),
      );

      final hourlyData = List.generate(
        24,
        (h) => HourlyRevenueData(
          hour: h,
          revenue: h == 14 ? 12000000.0 : (h == 19 ? 18000000.0 : 500000.0),
          orderCount: h == 19 ? 25 : (h == 14 ? 15 : 1),
        ),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisor)),
            overviewActiveDateRangeProvider.overrideWith((ref) => singleDayRange),
            hourlyRevenueListProvider.overrideWith((ref) => AsyncValue.data(hourlyData)),
            availableStoresProvider.overrideWith((ref) async => storesMap),
          ],
          child: const RevenueChartSection(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Doanh thu theo giờ trong ngày'), findsOneWidget);
      expect(find.textContaining('Khung giờ cao điểm: 19:00 - 20:00'), findsOneWidget);
      expect(find.textContaining('(18.000.000 đ)'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);

      // Toggle to list view
      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(BarChart), findsNothing);
      expect(find.text('19:00'), findsOneWidget);
      expect(find.text('18.000.000 đ'), findsOneWidget);
      expect(find.text('25 đơn'), findsOneWidget);
    });

    testWidgets('Renders Daily stacked multi-store chart for 7-day range and toggles to daily list',
        (tester) async {
      final range7d = DateTimeRange(
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 16),
      );

      final dailyReports = List.generate(7, (i) {
        final d = DateTime(2026, 8, 10).add(Duration(days: i));
        return _buildDailyReport(
          date: d,
          totalRevenue: 30000000.0,
          totalCost: 18000000.0,
          totalOrders: 20,
          storeRevenues: {
            'store_001': 15000000.0,
            'store_002': 10000000.0,
            'store_003': 5000000.0,
          },
        );
      });

      final summary = RevenueSummary(
        startDate: range7d.start,
        endDate: range7d.end,
        totalRevenue: 210000000.0,
        totalCost: 126000000.0,
        totalProfit: 84000000.0,
        totalOrders: 140,
        totalItemsSold: 350,
        dailyReports: dailyReports,
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisor)),
            overviewActiveDateRangeProvider.overrideWith((ref) => range7d),
            revenueByDateRangeProvider(range7d).overrideWith((ref) => Stream.value(summary)),
            availableStoresProvider.overrideWith((ref) async => storesMap),
          ],
          child: const RevenueChartSection(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Biểu đồ doanh thu'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('Chi nhánh Quận 1'), findsOneWidget);
      expect(find.text('Chi nhánh Quận 7'), findsOneWidget);
      expect(find.text('Chi nhánh Thủ Đức'), findsOneWidget);

      // Toggle to list view
      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(BarChart), findsNothing);
      expect(find.text('16/08/2026'), findsOneWidget);
      expect(find.text('30.000.000 đ'), findsWidgets);
      expect(find.text('(20 đơn)'), findsWidgets);
    });

    testWidgets('Renders Weekly stacked chart for 45-day range with weekly labels (T1 Th07, T2 Th07...)',
        (tester) async {
      final range45d = DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 8, 14),
      );

      final dailyReports = [
        _buildDailyReport(
          date: DateTime(2026, 7, 3),
          totalRevenue: 50000000.0,
          totalCost: 30000000.0,
          totalOrders: 50,
          storeRevenues: {'store_001': 30000000.0, 'store_002': 20000000.0},
        ),
        _buildDailyReport(
          date: DateTime(2026, 7, 10),
          totalRevenue: 60000000.0,
          totalCost: 36000000.0,
          totalOrders: 60,
          storeRevenues: {'store_001': 35000000.0, 'store_002': 25000000.0},
        ),
        _buildDailyReport(
          date: DateTime(2026, 8, 5),
          totalRevenue: 70000000.0,
          totalCost: 42000000.0,
          totalOrders: 70,
          storeRevenues: {'store_001': 40000000.0, 'store_002': 30000000.0},
        ),
      ];

      final summary = RevenueSummary(
        startDate: range45d.start,
        endDate: range45d.end,
        totalRevenue: 180000000.0,
        totalCost: 108000000.0,
        totalProfit: 72000000.0,
        totalOrders: 180,
        totalItemsSold: 500,
        dailyReports: dailyReports,
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisor)),
            overviewActiveDateRangeProvider.overrideWith((ref) => range45d),
            revenueByDateRangeProvider(range45d).overrideWith((ref) => Stream.value(summary)),
            availableStoresProvider.overrideWith((ref) async => storesMap),
          ],
          child: const RevenueChartSection(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BarChart), findsOneWidget);

      // Toggle to List View
      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Tuần 1 - Tháng 07/2026'), findsOneWidget);
      expect(find.text('Tuần 2 - Tháng 07/2026'), findsOneWidget);
      expect(find.text('Tuần 1 - Tháng 08/2026'), findsOneWidget);
      expect(find.text('50.000.000 đ'), findsOneWidget);
      expect(find.text('60.000.000 đ'), findsOneWidget);
      expect(find.text('70.000.000 đ'), findsOneWidget);
    });

    testWidgets('Renders Monthly stacked chart for 365-day range with monthly labels (Th09, Th12, Th08...)',
        (tester) async {
      final range365d = DateTimeRange(
        start: DateTime(2025, 9, 1),
        end: DateTime(2026, 8, 31),
      );

      final dailyReports = [
        _buildDailyReport(
          date: DateTime(2025, 9, 15),
          totalRevenue: 100000000.0,
          totalCost: 60000000.0,
          totalOrders: 100,
          storeRevenues: {'store_001': 60000000.0, 'store_002': 40000000.0},
        ),
        _buildDailyReport(
          date: DateTime(2025, 12, 20),
          totalRevenue: 250000000.0,
          totalCost: 150000000.0,
          totalOrders: 250,
          storeRevenues: {'store_001': 150000000.0, 'store_002': 100000000.0},
        ),
        _buildDailyReport(
          date: DateTime(2026, 8, 10),
          totalRevenue: 300000000.0,
          totalCost: 180000000.0,
          totalOrders: 300,
          storeRevenues: {'store_001': 200000000.0, 'store_002': 100000000.0},
        ),
      ];

      final summary = RevenueSummary(
        startDate: range365d.start,
        endDate: range365d.end,
        totalRevenue: 650000000.0,
        totalCost: 390000000.0,
        totalProfit: 260000000.0,
        totalOrders: 650,
        totalItemsSold: 1800,
        dailyReports: dailyReports,
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisor)),
            overviewActiveDateRangeProvider.overrideWith((ref) => range365d),
            revenueByDateRangeProvider(range365d).overrideWith((ref) => Stream.value(summary)),
            availableStoresProvider.overrideWith((ref) async => storesMap),
          ],
          child: const RevenueChartSection(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BarChart), findsOneWidget);

      // Toggle to List View
      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Tháng 09/2025'), findsOneWidget);
      expect(find.text('Tháng 12/2025'), findsOneWidget);
      expect(find.text('Tháng 08/2026'), findsOneWidget);
      expect(find.text('100.000.000 đ'), findsOneWidget);
      expect(find.text('250.000.000 đ'), findsOneWidget);
      expect(find.text('300.000.000 đ'), findsOneWidget);
    });

    testWidgets('Empty summary / 0 reports renders empty message safely without crash',
        (tester) async {
      final range = DateTimeRange(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 15),
      );

      final emptySummary = RevenueSummary(
        startDate: range.start,
        endDate: range.end,
        totalRevenue: 0,
        totalCost: 0,
        totalProfit: 0,
        totalOrders: 0,
        totalItemsSold: 0,
        dailyReports: const [],
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisor)),
            overviewActiveDateRangeProvider.overrideWith((ref) => range),
            revenueByDateRangeProvider(range).overrideWith((ref) => Stream.value(emptySummary)),
            availableStoresProvider.overrideWith((ref) async => storesMap),
          ],
          child: const RevenueChartSection(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Không có dữ liệu hiển thị'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Toggle to list view
      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Chưa có giao dịch phát sinh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
