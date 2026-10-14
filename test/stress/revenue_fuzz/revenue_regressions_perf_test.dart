import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/data/models/order_model.dart';
import 'package:stores/data/repositories/revenue_repository_impl.dart';
import 'package:stores/domain/entities/revenue_report.dart';

import '../../revenue_e2e/dataset.dart';
import 'fuzz_support.dart';

void main() {
  group('regressions found by the fuzzer', () {
    test('UTC ("Z") order is bucketed by its LOCAL day (not lost from a 1-day report)',
        () async {
      final local = DateTime(2026, 10, 13, 2, 30); // early morning local
      final o = order('Z1', local.toUtc().toIso8601String(),
          [item('A', 1, 100000)], total: 100000);
      final rep = await repoFor('store_001', [o], []).getRevenueByDate(DateTime(2026, 10, 13));
      expect(rep.totalRevenue, 100000);
      final other = await repoFor('store_001', [o], []).getRevenueByDate(DateTime(2026, 10, 12));
      expect(other.totalRevenue, 0);
    });

    test('OrderModel.createdAt of a UTC string is local time', () {
      final local = DateTime(2026, 10, 13, 2, 30);
      final m = OrderModel.fromMap({
        'id': 'x', 'total': 1, 'items': [],
        'createdAt': local.toUtc().toIso8601String(),
      });
      expect(m.createdAt.isUtc, isFalse);
      expect(m.createdAt.hour, 2);
    });

    test('missing amountPaid on a discounted order defaults to net, not gross', () {
      final m = OrderModel.fromMap({
        'id': 'x', 'total': 100000, 'discount': 20000, 'status': 'completed',
        'items': [], 'createdAt': '2026-10-13T10:00:00.000',
      });
      expect(m.amountPaid, 80000);
    });

    test('merged productRevenue margin is profit/revenue (same as per-store)', () {
      ProductRevenue pr(double rev, double cost) => ProductRevenue(
          productId: 'A', productName: 'A', quantitySold: 1, revenue: rev,
          cost: cost, profit: rev - cost, profitMargin: (rev - cost) / rev * 100);
      RevenueSummary sum(ProductRevenue p) => RevenueSummary(
          startDate: d1, endDate: d1, totalRevenue: p.revenue, totalCost: p.cost,
          totalProfit: p.profit, totalOrders: 1, totalItemsSold: 1,
          dailyReports: [RevenueReport(date: d1, totalRevenue: p.revenue,
              totalCost: p.cost, profit: p.profit, totalOrders: 1,
              totalItemsSold: 1, productRevenues: [p])]);
      final m = mergeRevenueSummaries([sum(pr(100, 60)), sum(pr(100, 60))], d1, d1);
      expect(m.dailyReports.single.productRevenues.single.profitMargin, closeTo(40, 1e-9));
    });
  });

  test('performance: 20,000 orders over 90 days aggregate in < 3s', () async {
    final ds = generateDataset(777, orderTotal: 20000);
    expect(ds.orderCount, greaterThan(19990));
    final all = ds.orders[stores[0]]!;
    final repo = RevenueRepositoryImpl(FakeOrderDs(stores[0], all),
        FakeInvDs(ds.inv[stores[0]]!), FakeProdDs(ds.products));
    Future<(int, RevenueSummary, RevenueSummary)> once() async {
      final sw = Stopwatch()..start();
      final a = await repo.getRevenueByDateRange(dataStart, DateTime(2026, 9, 28));
      final b = await RevenueRepositoryImpl(
              FakeOrderDs(stores[1], ds.orders[stores[1]]!),
              FakeInvDs(ds.inv[stores[1]]!),
              FakeProdDs(ds.products))
          .getRevenueByDateRange(dataStart, DateTime(2026, 9, 28));
      mergeRevenueSummaries([a, b], dataStart, DateTime(2026, 9, 28));
      return (sw.elapsedMilliseconds, a, b);
    }

    // best of 3: other test processes may be hogging the CPU
    var best = 1 << 30;
    late RevenueSummary s;
    for (var i = 0; i < 3 && best >= 3000; i++) {
      final (t, a, _) = await once();
      if (t < best) best = t;
      s = a;
    }
    // ignore: avoid_print
    print('PERF: ${all.length + ds.orders[stores[1]]!.length} orders, 2 branches + merge: ${best}ms');
    expect(best, lessThan(3000));
    final ref = refCompute(all, ds.inv[stores[0]]!, ds.products, dataStart, DateTime(2026, 9, 28));
    expect((s.totalRevenue - ref.revenue).abs(), lessThan(0.01));
    expect((s.totalCost - ref.cost).abs(), lessThan(0.01));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
