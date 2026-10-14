import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/data/repositories/revenue_repository_impl.dart';
import 'package:stores/domain/entities/revenue_report.dart';

import '../../revenue_e2e/dataset.dart';
import 'fuzz_support.dart';

RevenueRepositoryImpl repoOf(Dataset ds, String store, [List<Map<String, dynamic>>? orders]) =>
    RevenueRepositoryImpl(FakeOrderDs(store, orders ?? ds.orders[store]!),
        FakeInvDs(ds.inv[store]!), FakeProdDs(ds.products));

void near(num a, num b, String what) {
  expect(a.isNaN, isFalse, reason: '$what NaN');
  expect((a - b).abs() <= 0.01 + 1e-9 * b.abs(), isTrue, reason: '$what app=$a ref=$b');
}

void compare(RevenueSummary app, RefStore ref, String ctx) {
  near(app.totalRevenue, ref.revenue, '$ctx revenue');
  near(app.totalCost, ref.cost, '$ctx cost');
  expect(app.totalOrders, ref.orders, reason: '$ctx orders');
  expect(app.totalItemsSold, ref.items, reason: '$ctx items');
  for (final d in app.dailyReports) {
    final k = DateTime(d.date.year, d.date.month, d.date.day);
    final r = ref.days[k];
    expect(r, isNotNull, reason: '$ctx unexpected day $k');
    near(d.totalRevenue, r!.revenue, '$ctx day $k revenue');
    near(d.totalCost, r.cost, '$ctx day $k cost');
    expect(d.totalOrders, r.orders, reason: '$ctx day $k orders');
    expect(d.totalItemsSold, r.items, reason: '$ctx day $k items');
  }
  expect(app.dailyReports.length, ref.days.length, reason: '$ctx day count');
  final prods = <String, RefProd>{};
  for (final p in app.dailyReports.expand((d) => d.productRevenues)) {
    final x = prods.putIfAbsent(p.productId, () => RefProd());
    x.qty += p.quantitySold;
    x.revenue += p.revenue;
    x.cost += p.cost;
  }
  expect(prods.keys.toSet(), ref.prods.keys.toSet(), reason: '$ctx product set');
  for (final e in ref.prods.entries) {
    expect(prods[e.key]!.qty, e.value.qty, reason: '$ctx prod ${e.key} qty');
    near(prods[e.key]!.revenue, e.value.revenue, '$ctx prod ${e.key} rev');
    near(prods[e.key]!.cost, e.value.cost, '$ctx prod ${e.key} cost');
  }
}

void invariants(RevenueSummary s, String ctx) {
  for (final v in [s.totalRevenue, s.totalCost, s.totalProfit]) {
    expect(v.isNaN || v.isInfinite, isFalse, reason: ctx);
  }
  expect(s.totalRevenue, greaterThanOrEqualTo(0), reason: '$ctx revenue>=0');
  expect(s.totalCost, greaterThanOrEqualTo(0), reason: '$ctx cost>=0');
  near(s.totalProfit, s.totalRevenue - s.totalCost, '$ctx profit');
  near(s.dailyReports.fold(0.0, (a, d) => a + d.totalRevenue), s.totalRevenue, '$ctx sum days rev');
  near(s.dailyReports.fold(0.0, (a, d) => a + d.totalCost), s.totalCost, '$ctx sum days cost');
  expect(s.dailyReports.fold(0, (a, d) => a + d.totalOrders), s.totalOrders);
  for (final d in s.dailyReports) {
    expect(d.totalRevenue, greaterThanOrEqualTo(0));
    expect(d.totalCost, greaterThanOrEqualTo(0));
    near(d.profit, d.totalRevenue - d.totalCost, '$ctx day profit');
    near(d.storeRevenues.values.fold(0.0, (a, v) => a + v), d.totalRevenue, '$ctx day branch sum');
    for (final p in d.productRevenues) {
      expect(p.profitMargin.isNaN, isFalse);
      final exp = p.revenue <= 0 ? 0.0 : (p.revenue - p.cost) / p.revenue * 100;
      near(p.profitMargin, exp, '$ctx margin ${p.productId}');
    }
  }
}

void main() {
  test('fuzz: repository revenue/COGS/orders vs independent reference', () async {
    final sw = Stopwatch()..start();
    var datasets = 0, ranges = 0, ordersSeen = 0;
    for (var i = 0; i < stressIter && sw.elapsed.inSeconds < 50; i++) {
      final seed = stressSeed + i;
      final ds = generateDataset(seed);
      final rnd = Random(seed ^ 0x5bd1e995);
      datasets++;
      ordersSeen += ds.orderCount;
      for (final (s, e) in randomRanges(rnd)) {
        ranges++;
        final ctx = 'seed=$seed range=$s..$e';
        final apps = <RevenueSummary>[];
        final refs = <RefStore>[];
        for (final st in stores) {
          final app = await repoOf(ds, st).getRevenueByDateRange(s, e);
          final ref = refCompute(ds.orders[st]!, ds.inv[st]!, ds.products, s, e);
          compare(app, ref, '$ctx $st');
          invariants(app, '$ctx $st');
          apps.add(app);
          refs.add(ref);
        }
        final merged = mergeRevenueSummaries(apps, s, e);
        invariants(merged, '$ctx merged');
        near(merged.totalRevenue, refs.fold(0.0, (a, r) => a + r.revenue), '$ctx merged rev');
        near(merged.totalCost, refs.fold(0.0, (a, r) => a + r.cost), '$ctx merged cost');
        expect(merged.totalOrders, refs.fold(0, (a, r) => a + r.orders));
        expect(merged.totalItemsSold, refs.fold(0, (a, r) => a + r.items));
        // sum of branch totals == merged total
        near(apps.fold(0.0, (a, x) => a + x.totalRevenue), merged.totalRevenue, '$ctx branch sum');
        // per-day merged
        for (final d in merged.dailyReports) {
          final k = DateTime(d.date.year, d.date.month, d.date.day);
          near(d.totalRevenue, refs.fold(0.0, (a, r) => a + (r.days[k]?.revenue ?? 0)), '$ctx merged day');
        }
        if (s == e) {
          final one = await repoOf(ds, stores[0]).getRevenueByDate(s);
          near(one.totalRevenue, refs[0].revenue, '$ctx getRevenueByDate');
        }
      }

      // adding cancelled / draft / returned orders never changes totals
      final (s, e) = (DateTime(2026, 7, 10), DateTime(2026, 8, 20));
      final st = stores[rnd.nextInt(2)];
      final base = await repoOf(ds, st).getRevenueByDateRange(s, e);
      final extra = <Map<String, dynamic>>[];
      var k = 0;
      for (final o in ds.orders[st]!.take(400)) {
        if (rnd.nextDouble() < 0.5) {
          final status = const ['cancelled', 'draft', 'returned'][rnd.nextInt(3)];
          extra.add({...o, 'id': 'extra${k++}', 'status': status,
            if (status == 'returned') 'items': [for (final l in (o['items'] as List)) {...l, 'returnedQuantity': l['quantity']}]});
        }
      }
      final withExtra = await repoOf(ds, st, [...ds.orders[st]!, ...extra]).getRevenueByDateRange(s, e);
      near(withExtra.totalRevenue, base.totalRevenue, 'seed=$seed extra rev');
      near(withExtra.totalCost, base.totalCost, 'seed=$seed extra cost');
      expect(withExtra.totalOrders, base.totalOrders);
      expect(withExtra.totalItemsSold, base.totalItemsSold);
    }
    // ignore: avoid_print
    print('REPO FUZZ: $datasets datasets, $ranges ranges, $ordersSeen orders, ${sw.elapsed.inSeconds}s');
    expect(datasets, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
