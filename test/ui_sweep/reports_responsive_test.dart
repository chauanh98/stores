import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/revenue_report.dart';
import 'package:stores/presentation/reports/pages/overview_page.dart';
import 'package:stores/presentation/reports/pages/revenue_statistics_page.dart';

import 'sweep_harness.dart';

const _huge = sweepHugeMoney;

RevenueReport _day(int i) => RevenueReport(
      date: DateTime(2026, 8, 1).add(Duration(days: i)),
      totalRevenue: _huge,
      totalCost: _huge / 2,
      profit: _huge / 2,
      totalOrders: 1000000,
      totalItemsSold: 99999999,
      storeRevenues: {'store_001': _huge, 'store_002': _huge / 3},
      productRevenues: [
        for (var p = 0; p < 12; p++)
          ProductRevenue(
              productId: 'p$p',
              productName: '$sweepLongName $p',
              quantitySold: 1000000,
              revenue: _huge,
              cost: _huge / 2,
              profit: _huge / 2,
              profitMargin: 50),
      ],
    );

RevenueSummary _summary(int days) => RevenueSummary(
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 1).add(Duration(days: days)),
      totalRevenue: _huge * days,
      totalCost: _huge * days / 2,
      totalProfit: _huge * days / 2,
      totalOrders: 1000000 * days,
      totalItemsSold: 99999999,
      dailyReports: [for (var i = 0; i < days; i++) _day(i)],
    );

List<Override> _ov(user, {bool error = false, bool empty = false}) {
  AsyncValue<T> v<T>(T data) => error
      ? AsyncValue<T>.error('boom', StackTrace.empty)
      : AsyncValue.data(data);
  return [
    authProvider.overrideWith((ref) => SweepAuth(user)),
    currentStoreIdProvider.overrideWithValue('store_001'),
    currentStoreNameProvider.overrideWith((ref) async => sweepLongStore),
    availableStoresProvider.overrideWith((ref) async => {
          'store_001': sweepLongStore,
          'store_002': 'Chi nhánh Thới Bình',
          'store_003': 'Chi nhánh Thủ Đức rất dài tên để kiểm tra',
        }),
    overviewKPIsProvider.overrideWith((ref) => v(empty
        ? OverviewKPIs.empty
        : const OverviewKPIs(
            netRevenue: _huge,
            orderCount: 99999999,
            grossProfit: _huge,
            returnGoodsValue: _huge,
            aov: _huge,
            revenueGrowthPercent: 99999.9,
            orderCountGrowthPercent: -99999.9,
            profitGrowthPercent: 15.5,
            aovGrowthPercent: 5,
            customerDebt: _huge,
          ))),
    stockAlertSummaryProvider.overrideWith((ref) => v(empty
        ? StockAlertSummary.empty
        : const StockAlertSummary(
            outOfStockCount: 99999,
            lowStockCount: 99999,
            totalItemCount: 999999,
            totalInventoryCost: _huge,
            outOfStockProductIds: ['p1'],
            lowStockProductIds: ['p2']))),
    hourlyRevenueListProvider.overrideWith((ref) => v([
          for (var h = 0; h < 24; h++)
            HourlyRevenueData(
                hour: h,
                revenue: empty ? 0 : _huge * (h + 1),
                orderCount: empty ? 0 : 1000000 * h)
        ])),
    paymentBreakdownProvider.overrideWith((ref) => v(empty
        ? PaymentBreakdown.empty
        : const PaymentBreakdown(
            cashAmount: _huge,
            transferAmount: _huge,
            debtAmount: _huge,
            totalAmount: _huge * 3))),
    categoryRevenueShareProvider.overrideWith((ref) => v([
          if (!empty)
            for (var i = 0; i < 12; i++)
              CategoryRevenueShare(
                  categoryName:
                      'Bia, Rượu, Nước giải khát >> Nước ngọt có ga $i',
                  revenue: _huge,
                  percentage: 100 / 12,
                  quantitySold: 99999999)
        ])),
    topSellingProductsRankingProvider.overrideWith((ref) => v([
          if (!empty)
            for (var i = 0; i < 10; i++)
              ProductRankingItem(
                  productId: 'p$i',
                  productName: '$sweepLongName $i',
                  quantity: 99999999,
                  revenue: _huge,
                  categoryName: 'Nhóm hàng rất dài để kiểm tra tràn dòng')
        ])),
    topCustomersRankingProvider.overrideWith((ref) => v([
          if (!empty)
            for (var i = 0; i < 10; i++)
              CustomerRankingItem(
                  customerId: 'c$i',
                  customerName:
                      'Nguyễn Thị Thanh Thảo Hoàng Gia Bảo Châu Quận Bình Thạnh',
                  totalSpent: _huge,
                  orderCount: 99999999,
                  phoneNumber: '0901234567')
        ])),
    recentOrdersFeedProvider.overrideWith((ref) => v([
          if (!empty)
            for (var i = 0; i < 5; i++)
              Order(
                  id: 'ord_00${i}_abcdefghijklmnop',
                  customerId: 'c$i',
                  customerName:
                      'Nguyễn Thị Thanh Thảo Hoàng Gia Bảo Châu Quận Bình Thạnh',
                  createdAt: DateTime.now().subtract(Duration(minutes: 5 * i)),
                  items: const [],
                  total: _huge,
                  status: i.isEven ? 'completed' : 'pending')
        ])),
    revenueByDateRangeProvider.overrideWith((ref, range) =>
        error ? Stream.error('boom') : Stream.value(_summary(empty ? 0 : 31))),
    revenueByDateProvider.overrideWith((ref, date) => error
        ? Stream.error('boom')
        : Stream.value(empty ? _day(0).copyWithEmpty() : _day(0))),
  ];
}

extension on RevenueReport {
  RevenueReport copyWithEmpty() => RevenueReport(
      date: date,
      totalRevenue: 0,
      totalCost: 0,
      profit: 0,
      totalOrders: 0,
      totalItemsSold: 0,
      productRevenues: const []);
}

void main() {
  final small = {
    '320x568': sweepScreens['320x568']!,
    '1280x800': sweepScreens['1280x800']!
  };
  sweepMatrix('OverviewPage', () => const OverviewPage(), (u) => _ov(u));
  sweepMatrix('OverviewPage(empty)', () => const OverviewPage(),
      (u) => _ov(u, empty: true),
      screens: small);
  sweepMatrix('OverviewPage(error)', () => const OverviewPage(),
      (u) => _ov(u, error: true),
      screens: small);
  sweepMatrix('RevenueStatisticsPage', () => const RevenueStatisticsPage(),
      (u) => _ov(u));
  sweepMatrix('RevenueStatisticsPage(empty)',
      () => const RevenueStatisticsPage(), (u) => _ov(u, empty: true),
      screens: small);
  sweepMatrix('RevenueStatisticsPage(error)',
      () => const RevenueStatisticsPage(), (u) => _ov(u, error: true),
      screens: small);
}
