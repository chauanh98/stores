import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/presentation/reports/pages/overview_page.dart';
import 'package:stores/presentation/reports/pages/revenue_statistics_page.dart';

import 'stress_kit.dart';

final _g = Gen();

List<Override> ov(user,
    {String mode = 'normal', int days = 365, bool error = false}) {
  final summary = _g.revenue(days, mode: mode);
  AsyncValue<T> v<T>(T data) => error
      ? AsyncValue<T>.error('boom', StackTrace.empty)
      : AsyncValue.data(data);
  final big = mode == 'outlier' ? 1e12 : 123456789.0;
  final zero = mode == 'zeros';
  final nan = mode == 'nan';
  return [
    authProvider.overrideWith((ref) => SweepAuth(user)),
    currentStoreIdProvider.overrideWithValue('store_001'),
    currentStoreNameProvider.overrideWith((ref) async => sweepLongStore),
    availableStoresProvider.overrideWith((ref) async => {
          'store_001': sweepLongStore,
          'store_002': 'Chi nhánh Thới Bình',
          'store_003': emojiStr,
        }),
    overviewKPIsProvider.overrideWith((ref) => v(zero
        ? OverviewKPIs.empty
        : OverviewKPIs(
            netRevenue: nan ? double.nan : big,
            orderCount: 99999999,
            grossProfit: nan ? double.infinity : big,
            returnGoodsValue: big,
            aov: nan ? double.negativeInfinity : big,
            revenueGrowthPercent: nan ? double.nan : -99999.9,
            orderCountGrowthPercent: mode == 'negative' ? -100 : 99999.9,
            profitGrowthPercent: nan ? double.infinity : 0,
            aovGrowthPercent: -0.0,
            customerDebt: -big,
          ))),
    stockAlertSummaryProvider.overrideWith((ref) => v(zero
        ? StockAlertSummary.empty
        : const StockAlertSummary(
            outOfStockCount: 99999,
            lowStockCount: 0,
            totalItemCount: 999999,
            totalInventoryCost: 1e12,
            outOfStockProductIds: ['p1'],
            lowStockProductIds: []))),
    hourlyRevenueListProvider.overrideWith((ref) => v([
          for (var h = 0; h < 24; h++)
            HourlyRevenueData(
                hour: h,
                revenue: switch (mode) {
                  'zeros' => 0.0,
                  'equal' => 5.0,
                  'nan' => h.isEven ? double.nan : double.infinity,
                  'outlier' => h == 12 ? 1e12 : 10.0,
                  _ => big * (h + 1),
                },
                orderCount: zero ? 0 : 1000 * h)
        ])),
    paymentBreakdownProvider.overrideWith((ref) => v(zero
        ? PaymentBreakdown.empty
        : PaymentBreakdown(
            cashAmount: nan ? double.nan : big,
            transferAmount: mode == 'negative' ? -big : big,
            debtAmount: 0,
            totalAmount: nan ? double.infinity : big * 2))),
    categoryRevenueShareProvider.overrideWith((ref) => v([
          if (!zero)
            for (var i = 0; i < (mode == 'single' ? 1 : 40); i++)
              CategoryRevenueShare(
                  categoryName: _g.maybeAdv('Nhóm $i', p: .3),
                  revenue: big,
                  percentage: nan ? double.nan : (mode == 'single' ? 100 : 2.5),
                  quantitySold: 99999999)
        ])),
    topSellingProductsRankingProvider.overrideWith((ref) => v([
          if (!zero)
            for (var i = 0; i < 10; i++)
              ProductRankingItem(
                  productId: 'p$i',
                  productName: _g.adv(),
                  quantity: 99999999,
                  revenue: big,
                  categoryName: _g.adv())
        ])),
    topCustomersRankingProvider.overrideWith((ref) => v([
          if (!zero)
            for (var i = 0; i < 10; i++)
              CustomerRankingItem(
                  customerId: 'c$i',
                  customerName: _g.adv(),
                  totalSpent: big,
                  orderCount: 99999999,
                  phoneNumber: _g.adv())
        ])),
    recentOrdersFeedProvider.overrideWith((ref) => v([
          if (!zero)
            for (var i = 0; i < 20; i++)
              Order(
                  id: 'ord_$i',
                  customerId: 'c$i',
                  customerName: _g.adv(),
                  createdAt: DateTime.now().subtract(Duration(minutes: 5 * i)),
                  items: const [],
                  total: big,
                  status: i.isEven ? 'completed' : 'pending')
        ])),
    revenueByDateRangeProvider.overrideWith(
        (ref, range) => error ? Stream.error('boom') : Stream.value(summary)),
    revenueByDateProvider.overrideWith((ref, date) => error
        ? Stream.error('boom')
        : Stream.value(summary.dailyReports.first)),
  ];
}

void main() {
  const modes = [
    'normal',
    'zeros',
    'outlier',
    'equal',
    'single',
    'negative',
    'nan'
  ];
  for (var i = 0; i < modes.length; i++) {
    final m = modes[i];
    stressMatrix(
        'OverviewPage[$m]', () => const OverviewPage(), (u) => ov(u, mode: m),
        rot: i, maxMs: 4000);
    stressMatrix('RevenueStatisticsPage[$m]',
        () => const RevenueStatisticsPage(), (u) => ov(u, mode: m),
        rot: i + 2, maxMs: 4000);
  }
  stressMatrix('OverviewPage[error]', () => const OverviewPage(),
      (u) => ov(u, error: true),
      rot: 1);
  stressMatrix('RevenueStatisticsPage[error]',
      () => const RevenueStatisticsPage(), (u) => ov(u, error: true),
      rot: 3);

  // Range mode with a 365-day summary: daily list must build lazily.
  for (final mode in ['normal', 'outlier', 'nan']) {
    for (final d in [devices[3], devices[8], devices[15]]) {
      testWidgets('RevenueStatisticsPage range 365d [$mode] @${d.name}',
          (t) async {
        setDevice(t, d);
        debugErrors();
        addTearDown(t.view.reset);
        await t.pumpWidget(stressHost(
            const RevenueStatisticsPage(), ov(sweepAdmin, mode: mode),
            // 360x640 @1.3: Flutter's own DateRangePicker header overflows (framework).
            textScale: d.w < 400 ? 1.0 : 1.3));
        await t.pumpAndSettle();
        await t.tap(find.byIcon(Icons.date_range).first);
        await t.pumpAndSettle();
        await t.tap(find.byIcon(Icons.date_range).first);
        await t.pumpAndSettle();
        // Flutter's own DateRangePicker overflows a 224px header on 360px phones.
        final pickerErr = drain(t);
        if (pickerErr != null)
          debugPrint('STRESS (framework picker) $pickerErr');
        await t.tap(find.text('10').first);
        await t.pump();
        await t.tap(find.text('12').first);
        await t.pump();
        final save =
            MaterialLocalizations.of(t.element(find.byType(Scaffold).last))
                .saveButtonLabel;
        await t.tap(find.text(save));
        final sw = Stopwatch()..start();
        await t.pumpAndSettle();
        sw.stop();
        expectClean(t, 'range $mode');
        debugPrint(
            'STRESS range365 $mode @${d.name}: ${sw.elapsedMilliseconds}ms '
            'built ${find.byType(Container, skipOffstage: false).evaluate().length} containers');
        // scroll to bottom of the 365-row list
        await t.fling(
            find.byType(Scrollable).first, const Offset(0, -20000), 8000);
        await t.pumpAndSettle();
        expectClean(t, 'range $mode scrolled');
        expect(sw.elapsedMilliseconds, lessThan(1500));
      });
    }
  }
}
