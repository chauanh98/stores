import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/data/repositories/order_repository_impl.dart';
import 'package:stores/data/repositories/revenue_repository_impl.dart';
import 'package:stores/domain/entities/revenue_report.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';

import '../../revenue_e2e/dataset.dart';
import 'fuzz_support.dart';

class _Customers extends CustomerListNotifier {
  _Customers(this.list);
  final List<Customer> list;
  @override
  Future<List<Customer>> build() async => list;
}

void near(num a, num b, String what) {
  expect(a.isNaN, isFalse, reason: '$what NaN');
  expect((a - b).abs() <= 0.01 + 1e-9 * b.abs(), isTrue, reason: '$what app=$a ref=$b');
}

DateTime eod(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

void main() {
  test('fuzz: payment breakdown, KPI cards, rankings, hourly, category vs reference',
      () async {
    final sw = Stopwatch()..start();
    var datasets = 0, checks = 0;
    for (var i = 0; i < stressIter && sw.elapsed.inSeconds < 50; i++) {
      final seed = stressSeed + 1000 + i;
      // provider layer is heavier per order: cap dataset size
      final ds = generateDataset(seed, orderTotal: 500 + (seed % 7) * 150);
      final rnd = Random(seed);
      datasets++;
      final allRaw = [for (final s in stores) ...ds.orders[s]!];
      final products = [
        for (var k = 0; k < ds.products.length; k++)
          Product(
            id: ds.products[k]['id'] as String,
            name: ds.products[k]['name'] as String,
            code: ds.products[k]['id'] as String,
            price: ds.products[k]['price'] as double,
            costPrice: (ds.products[k]['costPrice'] as double?) ?? 0,
            branchStocks: const {},
            category: 'cat${k % 3}',
          )
      ];
      final catOf = {for (final p in products) p.id: p.category};
      // customers: debt = sum of remaining debt of completed orders
      final debtBy = <String, double>{};
      for (final raw in allRaw) {
        final o = RefOrder(raw);
        if (o.status != 'completed' || o.customer.isEmpty) continue;
        debtBy[o.customer] = (debtBy[o.customer] ?? 0) + o.remainingDebt;
      }
      final customers = [
        for (final c in ds.customers)
          Customer(
              id: c, name: c, phone: '', email: '', address: '',
              purchases: const [], currentDebt: debtBy[c] ?? 0)
      ];
      // Map raw -> Order via the real repository mapping.
      Future<List<Order>> mapped(DateTime s, DateTime e) async {
        final out = <Order>[];
        for (final st in stores) {
          out.addAll(await OrderRepositoryImpl(FakeOrderDs(st, ds.orders[st]!))
              .watchByDateRange(s, eod(e))
              .first);
        }
        return out;
      }

      Future<RevenueSummary> sums(DateTime s, DateTime e) async {
        final list = <RevenueSummary>[];
        for (final st in stores) {
          list.add(await RevenueRepositoryImpl(FakeOrderDs(st, ds.orders[st]!),
                  FakeInvDs(ds.inv[st]!), FakeProdDs(ds.products))
              .getRevenueByDateRange(s, e));
        }
        return mergeRevenueSummaries(list, s, e);
      }

      final picks = randomRanges(rnd).take(3).toList();
      for (final (s, e) in picks) {
        if (e.isBefore(s)) continue;
        final range = DateTimeRange(start: s, end: eod(e));
        final days = e.difference(s).inDays + 1;
        final priorRange = DateTimeRange(
            start: s.subtract(Duration(days: days)), end: eod(s.subtract(const Duration(days: 1))));
        final cur = await sums(s, e);
        final pri = await sums(priorRange.start, priorRange.end);
        final orders = await mapped(s, e);
        final ctx = 'seed=$seed $s..$e';
        final returns = [
          for (var k = 0; k < 3; k++)
            ReturnOrder(
                id: 'R$k', orderId: 'x', customerId: 'c', storeId: stores[0],
                createdAt: s, items: const [], totalReturnAmount: 1000.0 * (k + 1))
        ];
        final c = ProviderContainer(overrides: [
          overviewCurrentDateRangeProvider.overrideWithValue(range),
          overviewPriorPeriodDateRangeProvider.overrideWithValue(priorRange),
          allBranchesOrdersByDateRangeProvider.overrideWith((ref, r) => Stream.value(orders)),
          allBranchesReturnOrdersByDateRangeProvider.overrideWith((ref, r) => Stream.value(returns)),
          revenueByDateRangeProvider.overrideWith((ref, r) => Stream.value(r == range ? cur : pri)),
          allStoresProductsProvider.overrideWith((ref) => Stream.value(products)),
          customerListNotifierProvider.overrideWith(() => _Customers(customers)),
        ]);
        addTearDown(c.dispose);
        await c.read(allBranchesOrdersByDateRangeProvider(range).future);
        await c.read(revenueByDateRangeProvider(range).future);
        await c.read(revenueByDateRangeProvider(priorRange).future);
        await c.read(allBranchesReturnOrdersByDateRangeProvider(range).future);
        await c.read(customerListNotifierProvider.future);
        await c.read(allStoresProductsProvider.future);

        // ---- payment breakdown ----
        final pb = c.read(paymentBreakdownProvider).value!;
        final rp = refPayment(allRaw, s, e);
        near(pb.cashAmount, rp.cash, '$ctx cash');
        near(pb.transferAmount, rp.transfer, '$ctx transfer');
        near(pb.debtAmount, rp.debt, '$ctx debt');
        near(pb.totalAmount, rp.total, '$ctx total');
        // invariant: sums to net revenue (= merged revenue, since fully returned add 0)
        near(pb.totalAmount, cur.totalRevenue, '$ctx breakdown total == revenue');
        near(pb.cashAmount + pb.transferAmount + pb.debtAmount, pb.totalAmount, '$ctx buckets sum');
        for (final v in [pb.cashAmount, pb.transferAmount, pb.debtAmount]) {
          expect(v, greaterThanOrEqualTo(0));
        }

        // ---- KPI ----
        final k = c.read(overviewKPIsProvider).value!;
        final rc = [for (final st in stores) refCompute(ds.orders[st]!, ds.inv[st]!, ds.products, s, e)];
        final rpri = [for (final st in stores) refCompute(ds.orders[st]!, ds.inv[st]!, ds.products, priorRange.start, priorRange.end)];
        final rev = rc.fold(0.0, (a, r) => a + r.revenue);
        final cost = rc.fold(0.0, (a, r) => a + r.cost);
        final cnt = rc.fold(0, (a, r) => a + r.orders);
        final prev = rpri.fold(0.0, (a, r) => a + r.revenue);
        final pcnt = rpri.fold(0, (a, r) => a + r.orders);
        final pprof = prev - rpri.fold(0.0, (a, r) => a + r.cost);
        near(k.netRevenue, rev, '$ctx kpi rev');
        near(k.grossProfit, rev - cost, '$ctx kpi profit');
        expect(k.orderCount, cnt);
        near(k.aov, cnt > 0 ? rev / cnt : 0, '$ctx aov');
        near(k.revenueGrowthPercent, refGrowth(rev, prev), '$ctx rev growth');
        near(k.orderCountGrowthPercent, refGrowth(cnt.toDouble(), pcnt.toDouble()), '$ctx ord growth');
        near(k.profitGrowthPercent, refGrowth(rev - cost, pprof), '$ctx profit growth');
        near(k.customerDebt, debtBy.values.where((v) => v > 0).fold(0.0, (a, v) => a + v), '$ctx debt');
        near(k.returnGoodsValue, 6000, '$ctx returns');
        expect(k.revenueGrowthPercent.isNaN || k.revenueGrowthPercent.isInfinite, isFalse);

        // ---- rankings ----
        final rr = refRanking(allRaw, s, e);
        final top = c.read(topSellingProductsRankingProvider).value!;
        final refTopRev = (rr.rev.values.toList()..sort((a, b) => b.compareTo(a))).take(5).toList();
        expect(top.map((t) => t.revenue).toList().length, refTopRev.length, reason: ctx);
        for (var j = 0; j < refTopRev.length; j++) {
          near(top[j].revenue, refTopRev[j], '$ctx top product rev #$j');
        }
        for (final t in top) {
          near(t.revenue, rr.rev[t.productId] ?? -1, '$ctx top prod ${t.productId} rev');
          expect(t.quantity, rr.qty[t.productId], reason: '$ctx top prod qty');
        }
        final tc = c.read(topCustomersRankingProvider).value!;
        final refCust = rr.custSpent.entries.where((e) => e.key != 'khach_le' && e.key != 'walk_in').toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        expect(tc.length, min(5, refCust.length), reason: ctx);
        for (var j = 0; j < tc.length; j++) {
          near(tc[j].totalSpent, refCust[j].value, '$ctx top cust #$j');
        }
        for (final t in tc) {
          expect(t.orderCount, rr.custOrders[t.customerId], reason: '$ctx cust orders');
        }

        // ---- category share ----
        final cats = c.read(categoryRevenueShareProvider).value!;
        final refCat = <String, double>{};
        for (final id in rr.rev.keys) {
          final cat = catOf[id] ?? 'Khác';
          refCat[cat] = (refCat[cat] ?? 0) + rr.rev[id]!;
        }
        for (final cs in cats) {
          near(cs.revenue, refCat[cs.categoryName] ?? -1, '$ctx cat ${cs.categoryName}');
        }
        expect(cats.length, refCat.length, reason: ctx);
        if (cats.fold(0.0, (a, x) => a + x.revenue) > 0) {
          near(cats.fold(0.0, (a, x) => a + x.percentage), 100, '$ctx pct sum');
        }

        // ---- hourly (single-day ranges are its real use, but any range works) ----
        final hours = c.read(hourlyRevenueListProvider).value!;
        for (final h in hours) {
          near(h.revenue, rr.hourRev[h.hour] ?? 0, '$ctx hour ${h.hour} rev');
          expect(h.orderCount, rr.hourOrders[h.hour] ?? 0, reason: '$ctx hour ${h.hour} count');
        }
        near(hours.fold(0.0, (a, h) => a + h.revenue), rev, '$ctx hourly total == revenue');
        checks++;
      }
    }
    // ignore: avoid_print
    print('PROVIDER FUZZ: $datasets datasets, $checks range checks, ${sw.elapsed.inSeconds}s');
    expect(checks, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

