import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/data/repositories/order_repository_impl.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/revenue_report.dart';

import 'dataset.dart';

class _Customers extends CustomerListNotifier {
  _Customers(this.list);
  final List<Customer> list;
  @override
  Future<List<Customer>> build() async => list;
}

Customer _cust(String id, double debt) => Customer(
    id: id,
    name: id,
    phone: '',
    email: '',
    address: '',
    purchases: const [],
    currentDebt: debt);

void main() {
  final range = DateTimeRange(start: d1, end: d3);

  Future<(RevenueSummary, RevenueSummary, RevenueSummary)> compute() async {
    final s1 = await repoFor('store_001', branch1Orders(), b1Inventory)
        .getRevenueByDateRange(d1, d3);
    final s2 = await repoFor('store_002', branch2Orders(), b2Inventory)
        .getRevenueByDateRange(d1, d3);
    return (s1, s2, mergeRevenueSummaries([s1, s2], d1, d3));
  }

  test('branch 1 per-day and total revenue / COGS / profit (FIFO)', () async {
    final (s1, _, _) = await compute();
    // D1: O1 400k (cost 3*50k + 2*28k = 206k); O2 net 380k (A4: L1 has 2 left
    //     @50k=100k + 2@55k=110k => 210k). rev 780k, cost 416k, 2 orders, 9 items
    // D2: O3 250k (5*28k=140k); O4 1,080k-80k=1,000k (12*55k=660k);
    //     O7 80k (C no lots, fallback 20k*2=40k); cancelled O5 / draft O6 ignored.
    //     rev 1,330k cost 840k, 3 orders, 5+12+2=19 items
    // D3: O8 net 1,000k, active A8,B4: A: L2 left 6 -> 6*55k=330k + 2*58k=116k;
    //     B: 4*28k=112k => 558k. O9 fully returned, O10 returned => skipped.
    //     O11 combo 150k cost 90k (fallback). O12 B12: B lots left 15-2-5-4=4@28k then 10@32k => 4*28k+8*32k=112k+256k=368k, rev 600k.
    //     O13 cancelled, O13-v2 100k cost 1*58k. rev 1,850k cost 558+90+368+58=1,074k,
    //     4 orders, 12+1+12+1=26 items
    expect(s1.dailyReports.length, 3);
    final r = s1.dailyReports;
    expect([r[0].totalRevenue, r[0].totalCost, r[0].profit, r[0].totalOrders, r[0].totalItemsSold],
        [780000, 416000, 364000, 2, 9]);
    expect([r[1].totalRevenue, r[1].totalCost, r[1].profit, r[1].totalOrders, r[1].totalItemsSold],
        [1330000, 840000, 490000, 3, 19]);
    expect([r[2].totalRevenue, r[2].totalCost, r[2].profit, r[2].totalOrders, r[2].totalItemsSold],
        [1850000, 1074000, 776000, 4, 26]);
    // totals: 780+1330+1850 = 3,960k; cost 416+840+1074 = 2,330k; profit 1,630k
    expect(s1.totalRevenue, 3960000);
    expect(s1.totalCost, 2330000);
    expect(s1.totalProfit, 1630000);
    expect(s1.totalOrders, 9);
    expect(s1.totalItemsSold, 54);
  });

  test('branch 2: oversold falls back to costPrice, debt order is revenue', () async {
    final (_, s2, _) = await compute();
    // P1 500k cost 5*52k=260k. P2 net 750k: 5@52k=260k + 3 fallback 60k = 180k
    // => 440k. P3 500k cost 10*30k (no lots, fallback) = 300k. P4 cancelled.
    final r = s2.dailyReports;
    expect(r.map((e) => e.totalRevenue), [500000, 750000, 500000]);
    expect(r.map((e) => e.totalCost), [260000, 440000, 300000]);
    expect(s2.totalRevenue, 1750000);
    expect(s2.totalCost, 1000000);
    expect(s2.totalProfit, 750000);
  });

  test('merged summary: per day, per branch and grand totals', () async {
    final (_, _, m) = await compute();
    // D1 780+500 = 1,280k cost 416+260 = 676k
    // D2 1,330+750 = 2,080k cost 840+440 = 1,280k
    // D3 1,850+500 = 2,350k cost 1,074+300 = 1,374k
    expect(m.dailyReports.map((e) => e.totalRevenue), [1280000, 2080000, 2350000]);
    expect(m.dailyReports.map((e) => e.totalCost), [676000, 1280000, 1374000]);
    expect(m.totalRevenue, 5710000);
    expect(m.totalCost, 3330000); // 2,330k + 1,000k
    expect(m.totalProfit, 2380000);
    expect(m.totalOrders, 12);
    expect(m.totalItemsSold, 77); // 54 + (5+8+10)
    // per-branch totals via storeRevenues
    final perBranch = <String, double>{};
    for (final d in m.dailyReports) {
      d.storeRevenues.forEach((k, v) => perBranch[k] = (perBranch[k] ?? 0) + v);
    }
    expect(perBranch['store_001'], 3960000);
    expect(perBranch['store_002'], 1750000);
    // product A across days/branches: B1 qty 3+4+12+8+1=28, B2 5+8=13 -> 41
    final a = m.dailyReports
        .expand((d) => d.productRevenues)
        .where((p) => p.productId == 'A')
        .fold<int>(0, (s, p) => s + p.quantitySold);
    expect(a, 41);
  });

  test('day-boundary: 23:59:59 stays in D1 and 00:00:00 goes to D2', () async {
    final rep = await repoFor('store_001', branch1Orders(), b1Inventory)
        .getRevenueByDate(DateTime(2026, 10, 12));
    expect(rep.totalRevenue, 780000); // contains O2 (23:59:59), not O3
    final rep2 = await repoFor('store_001', branch1Orders(), b1Inventory)
        .getRevenueByDate(DateTime(2026, 10, 13));
    expect(rep2.totalRevenue, 1330000); // contains O3 at 00:00:00
  });

  group('providers', () {
    final allOrders = [...branch1Orders(), ...branch2Orders()];

    Future<List<Order>> toOrders() async {
      // Real mapping path: map -> OrderModel.fromMap -> Order
      final b1 = await OrderRepositoryImpl(FakeOrderDs('store_001', branch1Orders()))
          .watchByDateRange(d1, DateTime(2026, 10, 14, 23, 59, 59))
          .first;
      final b2 = await OrderRepositoryImpl(FakeOrderDs('store_002', branch2Orders()))
          .watchByDateRange(d1, DateTime(2026, 10, 14, 23, 59, 59))
          .first;
      return [...b1, ...b2];
    }

    test('paymentBreakdownProvider: cash/transfer/card/wallet/qr/bank/debt', () async {
      expect(allOrders.length, 18);
      final orders = await toOrders();
      final c = ProviderContainer(overrides: [
        overviewCurrentDateRangeProvider.overrideWithValue(range),
        allBranchesOrdersByDateRangeProvider
            .overrideWith((ref, r) => Stream.value(orders)),
      ]);
      addTearDown(c.dispose);
      await c.read(allBranchesOrdersByDateRangeProvider(range).future);
      final sub = c.listen(paymentBreakdownProvider, (_, __) {});
      final b = sub.read().value!;
      // cash: O1 400k + O2 split cash 200k + O4 paid 400k + O13-v2 100k + P1 500k = 1,600k
      expect(b.cashAmount, 1600000);
      // transfer-like: O2 180k + O3 250k + O7 card 80k + O8 wallet 1,000k
      //   + O11 qr 150k + O12 bank_transfer 600k + P2 750k = 3,010k
      expect(b.transferAmount, 3010000);
      // debt: O4 600k + P3 500k = 1,100k
      expect(b.debtAmount, 1100000);
      // total net: 400+380+250+1000+80+1000+150+600+100 (+O9 0) +500+750+500 = 5,710k
      expect(b.totalAmount, 5710000);
      expect(b.cashAmount + b.transferAmount + b.debtAmount, b.totalAmount);
    });

    test('overviewKPIsProvider cards (cur vs prior), outstanding debt', () async {
      final (_, _, merged) = await compute();
      final prior = RevenueSummary(
          startDate: d1,
          endDate: d3,
          totalRevenue: 2855000,
          totalCost: 1665000,
          totalProfit: 1190000,
          totalOrders: 6,
          totalItemsSold: 30,
          dailyReports: const []);
      final priorRange = DateTimeRange(
          start: DateTime(2026, 10, 6), end: DateTime(2026, 10, 11, 23, 59));
      ReturnOrder ret(String id, double amt) => ReturnOrder(
          id: id,
          orderId: 'x',
          customerId: 'c',
          storeId: 'store_001',
          createdAt: d1,
          items: const [],
          totalReturnAmount: amt);
      final c = ProviderContainer(overrides: [
        overviewCurrentDateRangeProvider.overrideWithValue(range),
        overviewPriorPeriodDateRangeProvider.overrideWithValue(priorRange),
        revenueByDateRangeProvider
            .overrideWith((ref, r) => Stream.value(r == range ? merged : prior)),
        allBranchesReturnOrdersByDateRangeProvider.overrideWith((ref, r) =>
            Stream.value([ret('R1', 200000), ret('R2', 200000), ret('R3', 300000)])),
        customerListNotifierProvider.overrideWith(
            () => _Customers([_cust('c1', 600000), _cust('c2', 500000), _cust('c3', 0)])),
      ]);
      addTearDown(c.dispose);
      await c.read(revenueByDateRangeProvider(range).future);
      await c.read(revenueByDateRangeProvider(priorRange).future);
      await c.read(allBranchesReturnOrdersByDateRangeProvider(range).future);
      await c.read(customerListNotifierProvider.future);
      final sub = c.listen(overviewKPIsProvider, (_, __) {});
      final k = sub.read().value!;
      expect(k.netRevenue, 5710000);
      expect(k.grossProfit, 2380000);
      expect(k.orderCount, 12);
      expect(k.aov, closeTo(5710000 / 12, 0.001)); // 475,833.33
      expect(k.returnGoodsValue, 700000); // 200+200+300
      expect(k.customerDebt, 1100000); // 600k + 500k, equals breakdown debt
      // growth: (5710-2855)/2855 = 100%; orders (12-6)/6 = 100%; profit (2380-1190)/1190 = 100%
      expect(k.revenueGrowthPercent, closeTo(100, 1e-9));
      expect(k.orderCountGrowthPercent, closeTo(100, 1e-9));
      expect(k.profitGrowthPercent, closeTo(100, 1e-9));
      expect(k.aovGrowthPercent, closeTo(0, 1e-9)); // prior aov 2855k/6 = same
    });
  });
}
