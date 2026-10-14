// Randomised operation sequences on the REAL use cases (return / collect-debt
// / cancel / replacement edit) checked after EVERY operation against an
// independent, deliberately naive reference ledger plus global invariants.
//
//   STRESS_SEED=123 STRESS_ITER=2000 flutter test test/stress/money_fuzz/money_fuzz_ops_test.dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/errors/exceptions.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'money_fuzz_support.dart';

class RL {
  final String pid;
  final int qty;
  final double price;
  int ret = 0;
  RL(this.pid, this.qty, this.price);
  int get active => qty - ret;
}

class RO {
  final String id, cust, store;
  String status;
  final List<RL> lines;
  double total, discount, paid, debt;
  RO(this.id, this.cust, this.store, this.status, this.lines, this.total,
      this.discount, this.paid, this.debt);
  double get net => max(0.0, total - discount);
  double get rem =>
      status == 'cancelled' ? 0.0 : (debt > 0 ? debt : max(0.0, net - paid));
  bool get registered => cust != 'khach_le';
}

class RC {
  double debt, total, net;
  RC(this.debt, this.total, this.net);
}

class RetItem {
  String pid;
  int qty;
  double price;
  RetItem(this.pid, this.qty, this.price);
}

class Ref {
  final Map<String, RO> orders = {};
  final Map<String, RC> cust = {};
  final Map<String, Map<String, int>> stock = {};
  final Scenario s;
  Ref(this.s) {
    for (final b in branches) {
      stock[b] = {for (final p in s.catalog) p.id: initialStock};
    }
    for (final c in s.w.customers.customers.values) {
      cust[c.id] = RC(c.currentDebt ?? 0, c.totalSales ?? 0, c.netSales ?? 0);
    }
  }

  void moveStock(String store, String pid, int qty, int sign) {
    final p = s.prod(pid);
    if (p.isCombo && p.comboComponents.isNotEmpty) {
      for (final c in p.comboComponents) {
        stock[store]![c.productId] =
            stock[store]![c.productId]! + sign * qty * c.quantity;
      }
    } else {
      stock[store]![pid] = stock[store]![pid]! + sign * qty;
    }
  }

  bool ret(RO o, List<RetItem> items) {
    if (o.status != 'completed' || items.isEmpty) return false;
    final agg = <String, int>{};
    for (final i in items) {
      if (i.qty <= 0 || !i.price.isFinite || i.price < 0) return false;
      if (!o.lines.any((l) => l.pid == i.pid)) return false;
      agg[i.pid] = (agg[i.pid] ?? 0) + i.qty;
    }
    for (final e in agg.entries) {
      final avail = o.lines
          .where((l) => l.pid == e.key)
          .fold<int>(0, (a, l) => a + l.active);
      if (e.value > avail) return false;
    }
    var gross = 0.0;
    for (final i in items) {
      gross += i.price * i.qty;
    }
    final rd = (o.total > 0 && o.discount > 0)
        ? o.discount * min(1.0, gross / o.total)
        : 0.0;
    final refund = (gross - rd).clamp(0.0, o.net);
    final dd = min(refund, o.rem);
    final cash = min(max(0.0, refund - dd), max(0.0, o.paid));
    if (o.registered) {
      final c = cust[o.cust]!;
      c.debt = max(0.0, c.debt - dd);
      c.total = max(0.0, c.total - gross);
      c.net = max(0.0, c.net - refund);
    }
    for (final i in items) {
      moveStock(o.store, i.pid, i.qty, 1);
    }
    for (final e in agg.entries) {
      var left = e.value;
      for (final l in o.lines.where((l) => l.pid == e.key)) {
        final take = min(left, l.active);
        l.ret += take;
        left -= take;
      }
    }
    o.total = max(0.0, o.total - gross);
    o.discount = max(0.0, o.discount - rd);
    o.debt = max(0.0, o.debt - dd);
    o.paid = max(0.0, o.paid - cash);
    if (o.lines.every((l) => l.active <= 0)) o.status = 'returned';
    return true;
  }

  bool collect(RO o, double amt) {
    if (o.status == 'cancelled' || o.status != 'completed') return false;
    if (!(amt > 0) || !amt.isFinite) return false;
    final rem = o.rem;
    if (amt > rem + 0.01) return false;
    o.paid += amt;
    o.debt = max(0.0, rem - amt);
    if (o.registered) {
      final c = cust[o.cust]!;
      c.debt = max(0.0, c.debt - amt);
    }
    return true;
  }

  bool cancel(RO o, String reason) {
    if (reason.trim().isEmpty || o.status == 'cancelled') return false;
    if (o.status != 'draft') {
      for (final l in o.lines) {
        if (l.active > 0) moveStock(o.store, l.pid, l.active, 1);
      }
      if (o.registered) {
        final c = cust[o.cust]!;
        final dtr = o.debt > 0 ? o.debt : o.rem;
        c.debt = max(0.0, c.debt - dtr);
        c.total = max(0.0, c.total - o.total);
        c.net = max(0.0, c.net - o.net);
      }
    }
    o.status = 'cancelled';
    o.debt = 0;
    return true;
  }
}

int _orderSeq = 0;

/// POS "complete sale" mirror: create order, add customer sales/debt, deduct stock.
Future<String> sell(Scenario s, Ref ref, String customerId, List<Line> lines,
    {required bool draft, String? store, Order? checkAgainst}) async {
  final r = s.r;
  var total = 0.0;
  for (final l in lines) {
    total += l.price * l.qty;
  }
  final kind = r.nextInt(4);
  final discount = switch (kind) {
    1 => total * r.nextDouble(),
    2 => total * r.nextInt(101) / 100,
    3 => total, // 100% off
    _ => 0.0,
  };
  final net = max(0.0, total - discount);
  final walkIn = customerId == 'khach_le';
  final pay = draft ? Pay('cash', 0, null, null) : posPay(r, net, walkIn);
  final debt = draft ? 0.0 : (net - pay.paid).clamp(0.0, net);
  final st = store ?? branches[r.nextInt(2)];
  final id = 'HD${++_orderSeq}';
  final now = DateTime(2026, 8, 1, 10);
  final order = Order(
    id: id,
    customerId: customerId,
    customerName: walkIn ? null : 'KH',
    createdAt: now,
    items: [
      for (final l in lines)
        OrderItem(
            productId: l.pid,
            productName: s.prod(l.pid).name,
            quantity: l.qty,
            price: l.price,
            originalPrice: l.orig,
            discount: l.disc,
            isDiscountPercent: l.pct,
            warrantyMonths: 12,
            purchaseDate: now)
    ],
    total: total,
    discount: discount,
    status: draft ? 'draft' : 'completed',
    amountPaid: pay.paid,
    debtAmount: debt,
    paymentMethod: pay.method,
    storeId: st,
    cashAmount: draft ? null : pay.cash,
    transferAmount: draft ? null : pay.transfer,
  );
  await s.w.orders.create(order);
  final ro = RO(id, customerId, st, order.status,
      [for (final l in lines) RL(l.pid, l.qty, l.price)], total, discount,
      pay.paid, debt);
  ref.orders[id] = ro;
  if (!draft) {
    for (final l in lines) {
      ref.moveStock(st, l.pid, l.qty, -1);
      final p = s.prod(l.pid);
      final comps = (p.isCombo && p.comboComponents.isNotEmpty)
          ? p.comboComponents.map((c) => (c.productId, l.qty * c.quantity))
          : [(l.pid, l.qty)];
      for (final (pid, q) in comps) {
        final prod = s.w.products.products[pid]!;
        final m = Map<String, int>.from(prod.branchStocks);
        m[st] = m[st]! - q;
        s.w.products.products[pid] = prod.copyWith(branchStocks: m);
      }
    }
    if (!walkIn) {
      final c = s.w.customers.customers[customerId]!;
      s.w.customers.customers[customerId] = c.copyWith(
        totalSales: (c.totalSales ?? 0) + total,
        netSales: (c.netSales ?? 0) + net,
        currentDebt: c.displayCurrentDebt + debt,
      );
      final rc = ref.cust[customerId]!;
      rc.total += total;
      rc.net += net;
      rc.debt += debt;
    }
  }
  return id;
}

String _ctx = '';
void _check(bool ok, String what) {
  if (!ok) fail('$what\n$_ctx');
}

Future<void> verify(Scenario s, Ref ref) async {
  // orders: persisted (through OrderModel) == reference
  for (final ro in ref.orders.values) {
    final o = await s.w.orders.fetchById(ro.id);
    _check(o != null, 'order ${ro.id} missing');
    o!;
    for (final v in [o.total, o.discount, o.amountPaid, o.debtAmount]) {
      _check(v.isFinite, 'non-finite money in ${ro.id}');
    }
    _check(o.status == ro.status, '${ro.id} status ${o.status} vs ${ro.status}');
    _check(near(o.total, ro.total), '${ro.id} total ${o.total} vs ${ro.total}');
    _check(near(o.discount, ro.discount),
        '${ro.id} discount ${o.discount} vs ${ro.discount}');
    _check(near(o.amountPaid, ro.paid),
        '${ro.id} paid ${o.amountPaid} vs ${ro.paid}');
    _check(near(o.debtAmount, ro.status == 'cancelled' ? 0 : ro.debt),
        '${ro.id} debt ${o.debtAmount} vs ${ro.debt}');
    _check(o.items.length == ro.lines.length, '${ro.id} line count');
    for (var i = 0; i < ro.lines.length; i++) {
      _check(o.items[i].returnedQuantity == ro.lines[i].ret,
          '${ro.id} line $i returned ${o.items[i].returnedQuantity} vs ${ro.lines[i].ret}');
      _check(o.items[i].returnedQuantity <= o.items[i].quantity,
          '${ro.id} returned > quantity');
    }
    // global per-order invariants
    if (o.status == 'completed' || o.status == 'returned') {
      _check(o.amountPaid >= -0.01 && o.debtAmount >= -0.01, '${ro.id} negative');
      _check(near(o.amountPaid + o.debtAmount, o.netPayable),
          '${ro.id} paid+debt ${o.amountPaid + o.debtAmount} != net ${o.netPayable}');
    }
    if (o.status == 'cancelled' || o.status == 'draft') {
      _check(o.debtAmount == 0 || o.status == 'draft' && o.debtAmount == 0,
          '${ro.id} ${o.status} carries debt');
      _check(o.remainingDebt == 0 || o.status == 'draft',
          '${ro.id} ${o.status} remainingDebt ${o.remainingDebt}');
    }
    if (o.status == 'draft') {
      _check(o.remainingDebt == 0, 'draft ${ro.id} must not count as debt');
    }
  }
  // stock == reference, never negative, units conserved (independent formula)
  final expected = <String, Map<String, int>>{
    for (final b in branches) b: {for (final p in s.catalog) p.id: initialStock}
  };
  for (final ro in ref.orders.values) {
    final o = (await s.w.orders.fetchById(ro.id))!;
    if (o.status == 'cancelled' || o.status == 'draft') continue;
    for (final it in o.items) {
      final p = s.prod(it.productId);
      if (p.isCombo && p.comboComponents.isNotEmpty) {
        for (final c in p.comboComponents) {
          expected[o.storeId]![c.productId] =
              expected[o.storeId]![c.productId]! -
                  it.activeQuantity * c.quantity;
        }
      } else {
        expected[o.storeId]![it.productId] =
            expected[o.storeId]![it.productId]! - it.activeQuantity;
      }
    }
  }
  for (final b in branches) {
    for (final p in s.catalog) {
      final actual = s.w.products.products[p.id]!.branchStocks[b];
      _check(actual == ref.stock[b]![p.id],
          'stock $b/${p.id}: $actual vs ref ${ref.stock[b]![p.id]}');
      _check(actual == expected[b]![p.id],
          'stock conservation $b/${p.id}: $actual vs ${expected[b]![p.id]}');
      _check(actual! >= 0, 'negative stock $b/${p.id}');
    }
  }
  // customers
  for (final e in ref.cust.entries) {
    final c = s.w.customers.customers[e.key]!;
    _check(near(c.displayCurrentDebt, e.value.debt),
        'customer ${e.key} debt ${c.displayCurrentDebt} vs ${e.value.debt}');
    _check(near(c.totalSales ?? 0, e.value.total),
        'customer ${e.key} totalSales ${c.totalSales} vs ${e.value.total}');
    _check(near(c.netSales ?? 0, e.value.net),
        'customer ${e.key} netSales ${c.netSales} vs ${e.value.net}');
    _check(c.displayCurrentDebt >= 0, 'negative debt ${e.key}');
  }
}

Future<List<RetItem>> genReturn(Scenario s, Order snap, Random r) async {
  final items = <RetItem>[];
  final byPid = <String, List<OrderItem>>{};
  for (final i in snap.items) {
    byPid.putIfAbsent(i.productId, () => []).add(i);
  }
  for (final e in byPid.entries) {
    if (r.nextInt(3) != 0 && items.isNotEmpty) continue;
    var avail = e.value.fold<int>(0, (a, i) => a + max(0, i.activeQuantity));
    if (avail <= 0) continue;
    var want = r.nextInt(3) == 0 ? avail : 1 + r.nextInt(avail);
    for (final line in e.value) {
      final take = min(want, max(0, line.activeQuantity));
      if (take <= 0) continue;
      items.add(RetItem(e.key, take, line.price));
      want -= take;
    }
    if (items.length > 40) break;
  }
  return items;
}

void main() {
  test('random op sequences vs reference ledger', () async {
    final sw = Stopwatch()..start();
    var ops = 0, rejectedOk = 0, scenarios = 0, ordersMade = 0;
    for (var it = 0; it < stressIter; it++) {
      final r = Random(stressSeed * 100003 + it);
      final s = Scenario(r);
      final ref = Ref(s);
      final log = <String>[];
      _ctx = 'seed=$stressSeed iter=$it';
      scenarios++;
      final snaps = <String, List<Order>>{};
      Future<void> snapshot(String id) async {
        final o = await s.w.orders.fetchById(id);
        if (o != null) (snaps[id] ??= []).add(o);
      }

      final nOrders = 1 + r.nextInt(4);
      for (var k = 0; k < nOrders; k++) {
        final cust = r.nextInt(3) == 0
            ? 'khach_le'
            : s.customerIds[r.nextInt(s.customerIds.length)];
        final draft = r.nextInt(8) == 0;
        final id = await sell(s, ref, cust, s.randLines(), draft: draft);
        ordersMade++;
        log.add('sell $id cust=$cust draft=$draft');
        _ctx = 'seed=$stressSeed iter=$it log=${log.join(' | ')}';
        await snapshot(id);
        await verify(s, ref);
      }

      final nOps = 3 + r.nextInt(10);
      for (var k = 0; k < nOps; k++) {
        final ids = ref.orders.keys.toList();
        final id = ids[r.nextInt(ids.length)];
        final ro = ref.orders[id]!;
        final snapList = snaps[id]!;
        // 40%: act through a stale snapshot
        final snap = r.nextInt(5) < 2
            ? snapList[r.nextInt(snapList.length)]
            : snapList.last;
        final kind = r.nextInt(10);
        ops++;
        if (kind <= 3) {
          // ---- return
          var items = await genReturn(s, snap, r);
          final mut = r.nextInt(12);
          if (mut == 0 && items.isNotEmpty) items[0].qty = 0;
          if (mut == 1 && items.isNotEmpty) items[0].qty = -3;
          if (mut == 2 && items.isNotEmpty) {
            items[0].qty = items[0].qty + 1000000;
          }
          if (mut == 3) items = [];
          if (mut == 4) items = [RetItem('ghost', 1, 10)];
          if (mut == 5 && items.isNotEmpty) {
            // same product twice: each ok alone, sum exceeds availability
            final a = items.first;
            final avail = ro.lines
                .where((l) => l.pid == a.pid)
                .fold<int>(0, (x, l) => x + l.active);
            items = [
              RetItem(a.pid, max(1, avail), a.price),
              RetItem(a.pid, max(1, avail), a.price)
            ];
          }
          if (mut == 6 && items.isNotEmpty) items[0].price = -items[0].price - 5;
          if (mut == 7 && items.isNotEmpty) items[0].price = double.nan;
          final expectOk = ref.ret(ro, items.map((e) => RetItem(e.pid, e.qty, e.price)).toList());
          // ref.ret mutated already only when ok
          log.add('return $id ${items.map((e) => '${e.pid}x${e.qty}@${e.price}').join(',')} ok=$expectOk stale=${!identical(snap, snapList.last)}');
          _ctx = 'seed=$stressSeed iter=$it log=${log.join(' | ')}';
          await _run(expectOk, () async {
            await s.w.ret.execute(
                originalOrder: snap,
                returnItems: [
                  for (final i in items)
                    ReturnOrderItem(
                        productId: i.pid,
                        productName: i.pid,
                        price: i.price,
                        quantity: i.qty)
                ],
                storeId: ro.store,
                currentUser: admin,
                reason: 'fuzz');
          });
          if (!expectOk) rejectedOk++;
        } else if (kind <= 5) {
          // ---- collect debt
          double amt;
          final m = r.nextInt(8);
          final rem = snap.remainingDebt;
          amt = switch (m) {
            0 => rem * 1.5 + 1,
            1 => -5,
            2 => 0,
            3 => double.nan,
            4 => rem,
            _ => rem * r.nextDouble(),
          };
          final expectOk = ref.collect(ro, amt);
          log.add('collect $id amt=$amt ok=$expectOk');
          _ctx = 'seed=$stressSeed iter=$it log=${log.join(' | ')}';
          await _run(expectOk, () async {
            await s.w.collect.execute(
                order: snap,
                amount: amt,
                paymentMethod: 'cash',
                currentUser: admin);
          });
          if (!expectOk) rejectedOk++;
        } else if (kind <= 7) {
          // ---- cancel (incl. double cancel / draft / empty reason)
          final reason = r.nextInt(8) == 0 ? '  ' : 'fuzz';
          final expectOk = ref.cancel(ro, reason);
          log.add('cancel $id reason="$reason" ok=$expectOk');
          _ctx = 'seed=$stressSeed iter=$it log=${log.join(' | ')}';
          await _run(expectOk, () async {
            await s.w.cancel.execute(
                order: snap,
                cancelReason: reason,
                currentUser: admin,
                storeId: ro.store);
          });
          if (!expectOk) rejectedOk++;
        } else if (kind == 8) {
          // ---- versioned edit: new order first, then cancel old (isReplacement)
          if (ro.status == 'cancelled') continue;
          final newId = await sell(s, ref, ro.cust, s.randLines(),
              draft: false, store: ro.store);
          ordersMade++;
          await snapshot(newId);
          final expectOk = ref.cancel(ro, 'Đã sửa thành $newId');
          log.add('replace $id -> $newId ok=$expectOk');
          _ctx = 'seed=$stressSeed iter=$it log=${log.join(' | ')}';
          await _run(expectOk, () async {
            await s.w.cancel.execute(
                order: snapList.last,
                cancelReason: 'Đã sửa thành $newId',
                currentUser: const UserAccount(
                    username: 'staff', role: 'nhanvien', storeId: 'store_001'),
                storeId: ro.store,
                isReplacement: true);
          });
        } else {
          // ---- read-only re-verification only
          log.add('noop');
        }
        await snapshot(id);
        await verify(s, ref);
      }
    }
    print('MONEY_FUZZ ops: scenarios=$scenarios orders=$ordersMade '
        'ops=$ops rejectedAsExpected=$rejectedOk in ${sw.elapsedMilliseconds}ms');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<void> _run(bool expectOk, Future<void> Function() body) async {
  try {
    await body();
    if (!expectOk) fail('use case accepted an operation the ledger rejects\n$_ctx');
  } on ValidationException {
    if (expectOk) fail('use case rejected a valid operation\n$_ctx');
  }
}
