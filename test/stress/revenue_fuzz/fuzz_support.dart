import 'dart:io';
import 'dart:math';

/// Seeded generator + INDEPENDENT reference calculator for the revenue stress
/// tests. The reference only looks at raw RTDB-style maps; it never calls
/// OrderModel / FifoCalculator / RevenueRepositoryImpl.
///
/// Env: STRESS_SEED (default 20261014), STRESS_ITER (default 300 datasets).

int envInt(String name, int def) =>
    int.tryParse(Platform.environment[name] ?? '') ?? def;

final int stressSeed = envInt('STRESS_SEED', 20261014);
final int stressIter = envInt('STRESS_ITER', 300);

const stores = ['store_001', 'store_002'];
final dataStart = DateTime(2026, 7, 1); // 90 days: Jul 1 .. Sep 28
const dataDays = 90;

class Dataset {
  Dataset(this.seed, this.orders, this.inv, this.products, this.customers);
  final int seed;
  final Map<String, List<Map<String, dynamic>>> orders;
  final Map<String, List<Map>> inv;
  final List<Map> products;
  final List<String> customers;
  int get orderCount => orders.values.fold(0, (s, l) => s + l.length);
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Formats [local] (a local DateTime) as one of three string shapes that all
/// denote the SAME instant: local ISO (no suffix), UTC 'Z', or fixed +07:00.
String fmtInstant(DateTime local, int variant) {
  switch (variant) {
    case 1:
      return local.toUtc().toIso8601String();
    case 2:
      final shifted = local.toUtc().add(const Duration(hours: 7));
      final y = shifted.year.toString().padLeft(4, '0');
      final ms = shifted.millisecond.toString().padLeft(3, '0');
      return '$y-${_two(shifted.month)}-${_two(shifted.day)}T'
          '${_two(shifted.hour)}:${_two(shifted.minute)}:${_two(shifted.second)}.$ms+07:00';
    default:
      return local.toIso8601String();
  }
}

Dataset generateDataset(int seed, {int? orderTotal}) {
  final r = Random(seed);
  final total = orderTotal ??
      (500 + (4500 * pow(r.nextDouble(), 2.2)).floor()); // skewed to small
  final products = <Map>[];
  for (var i = 0; i < 12; i++) {
    final price = (20 + r.nextInt(180)) * 1000.0;
    final p = <String, dynamic>{
      'id': 'P$i',
      'name': 'Product $i',
      'price': price,
    };
    if (i != 5) p['costPrice'] = (price * (0.4 + r.nextDouble() * 0.3) ~/ 1000) * 1000.0;
    products.add(p);
  }
  products.add({'id': 'COMBO1', 'name': 'Combo', 'price': 300000.0, 'costPrice': 180000.0});
  final pids = products.map((p) => p['id'] as String).toList();
  final customers = [for (var i = 0; i < 40; i++) 'c$i'];

  final orders = <String, List<Map<String, dynamic>>>{};
  final inv = <String, List<Map>>{};

  for (final s in stores) {
    final usedOrderInstants = <int>{};
    final usedInvInstants = <int>{};
    final share = s == stores[0] ? 0.62 : 0.38;
    final n = (total * share).round();
    final list = <Map<String, dynamic>>[];

    DateTime uniqueInstant(Set<int> used, DateTime day, {bool lot = false}) {
      final roll = r.nextDouble();
      for (var tries = 0; tries < 2000; tries++) {
        DateTime t;
        if (!lot && roll < 0.04) {
          t = DateTime(day.year, day.month, day.day, 23, 59, 59, 999 - (tries));
        } else if (!lot && roll < 0.08) {
          t = DateTime(day.year, day.month, day.day, 0, 0, 0, tries);
        } else {
          t = DateTime(day.year, day.month, day.day, r.nextInt(24),
              r.nextInt(60), r.nextInt(60), r.nextInt(1000));
        }
        if (used.add(t.microsecondsSinceEpoch)) return t;
      }
      throw StateError('no free instant');
    }

    // ---- inventory (lots) ----
    final txs = <Map>[];
    var seq = 0;
    for (final pid in pids) {
      final imports = 2 + r.nextInt(5);
      for (var k = 0; k < imports; k++) {
        final day = dataStart.add(Duration(days: r.nextInt(dataDays + 40) - 40));
        final t = uniqueInstant(usedInvInstants, day, lot: true);
        txs.add({
          'id': 'imp_${s}_${seq++}',
          'productId': pid,
          'type': 'import',
          'quantity': 20 + r.nextInt(400),
          if (r.nextDouble() > 0.03)
            'importPrice': (10 + r.nextInt(120)) * 1000.0,
          'date': t.toIso8601String(),
          'note': '',
          'storeId': s,
        });
      }
      if (r.nextDouble() < 0.5) {
        final t = uniqueInstant(
            usedInvInstants, dataStart.add(Duration(days: r.nextInt(dataDays))),
            lot: true);
        final q = 1 + r.nextInt(8);
        txs.add({
          'id': 'aud_${s}_${seq++}',
          'productId': pid,
          'type': 'INVENTORY_AUDIT',
          'quantity': q,
          'date': t.toIso8601String(),
          'note': '',
          'storeId': s,
          'isAuditNegative': true,
          'auditDifference': -q,
        });
      }
      if (r.nextDouble() < 0.5) {
        final t = uniqueInstant(
            usedInvInstants, dataStart.add(Duration(days: r.nextInt(dataDays))),
            lot: true);
        final q = 1 + r.nextInt(30);
        txs.add({
          'id': 'audp_${s}_${seq++}',
          'productId': pid,
          'type': 'INVENTORY_AUDIT',
          'quantity': q,
          'date': t.toIso8601String(),
          'note': '',
          'storeId': s,
          'isAuditNegative': false,
          'auditDifference': q,
          'importPrice': (10 + r.nextInt(120)) * 1000.0,
        });
      }
      if (r.nextDouble() < 0.4) {
        final t = uniqueInstant(
            usedInvInstants, dataStart.add(Duration(days: r.nextInt(dataDays))),
            lot: true);
        txs.add({
          'id': 'xfer_${s}_${seq++}',
          'productId': pid,
          'type': 'export',
          'quantity': 1 + r.nextInt(15),
          'date': t.toIso8601String(),
          'note': 'chuyen kho',
          'storeId': s,
        });
      }
    }
    // POS export_* rows (must be ignored)
    for (var k = 0; k < 40; k++) {
      final t = uniqueInstant(
          usedInvInstants, dataStart.add(Duration(days: r.nextInt(dataDays))),
          lot: true);
      final pid = pids[r.nextInt(pids.length)];
      txs.add({
        'id': 'export_${t.millisecondsSinceEpoch}_$pid',
        'productId': pid,
        'type': 'export',
        'quantity': 1 + r.nextInt(5),
        'date': t.toIso8601String(),
        'note': '',
        'storeId': s,
      });
    }
    inv[s] = txs;

    // ---- orders ----
    var oi = 0;
    while (list.length < n) {
      final day = dataStart.add(Duration(days: r.nextInt(dataDays)));
      final at = uniqueInstant(usedOrderInstants, day);
      final fmtVar = () {
        final x = r.nextDouble();
        return x < 0.70 ? 0 : (x < 0.85 ? 1 : 2);
      }();
      final stamp = fmtInstant(at, fmtVar);
      final id = '${s}_O${oi++}';

      // items (duplicate product lines + combos)
      final lines = <Map<String, dynamic>>[];
      final nl = 1 + r.nextInt(4);
      for (var k = 0; k < nl; k++) {
        final pid = r.nextDouble() < 0.06 ? 'COMBO1' : pids[r.nextInt(pids.length - 1)];
        final prod = products.firstWhere((p) => p['id'] == pid);
        final listPrice = prod['price'] as double;
        var price = (listPrice * (0.8 + r.nextDouble() * 0.3) ~/ 1000) * 1000.0;
        if (r.nextDouble() < 0.02) price = 0; // falls back to list price in product revenue
        final q = 1 + r.nextInt(6);
        lines.add(_line(pid, q, price));
        if (r.nextDouble() < 0.12) lines.add(_line(pid, 1 + r.nextInt(3), price)); // dup line
      }

      // status
      final sx = r.nextDouble();
      String status;
      var rawStatus = 'completed';
      var mode = 'completed'; // completed | cancelled | draft | returned | partial | fullyReturnedCompleted
      if (sx < 0.76) {
        mode = 'completed';
      } else if (sx < 0.83) {
        mode = 'cancelled';
      } else if (sx < 0.87) {
        mode = 'draft';
      } else if (sx < 0.91) {
        mode = 'returned';
      } else if (sx < 0.97) {
        mode = 'partial';
      } else {
        mode = 'fullyReturnedCompleted';
      }
      switch (mode) {
        case 'cancelled':
          rawStatus = const ['cancelled', 'canceled', 'Hủy', 'đã huỷ'][r.nextInt(4)];
        case 'draft':
          rawStatus = const ['draft', 'Lưu tạm'][r.nextInt(2)];
        case 'returned':
          rawStatus = const ['returned', 'Trả hàng', 'đổi trả'][r.nextInt(3)];
        default:
          rawStatus = const ['completed', 'completed', 'Completed ', ''][r.nextInt(4)];
      }
      status = rawStatus;

      var gross = 0.0;
      for (final l in lines) {
        gross += (l['price'] as double) * (l['quantity'] as int);
      }

      var returnedValue = 0.0;
      if (mode == 'returned' || mode == 'fullyReturnedCompleted') {
        for (final l in lines) {
          l['returnedQuantity'] = l['quantity'];
          returnedValue += (l['price'] as double) * (l['quantity'] as int);
        }
      } else if (mode == 'partial') {
        for (final l in lines) {
          final rq = r.nextInt((l['quantity'] as int) + 1);
          // keep at least the first line partially active
          l['returnedQuantity'] = rq;
          returnedValue += (l['price'] as double) * rq;
        }
      }
      var totalField = gross - returnedValue; // return use-case reduces total
      var discount = 0.0;
      if (r.nextDouble() < 0.30 && totalField > 0) {
        discount = ((totalField * r.nextDouble() * 0.3) ~/ 1000) * 1000.0;
      }
      final fullyReturned = mode == 'returned' || mode == 'fullyReturnedCompleted';
      if (fullyReturned) discount = 0;
      final net = max(0.0, totalField - discount);

      // legacy: total stores net, no discount field (reconciled by OrderModel)
      final legacyNet = discount > 0 && mode == 'completed' && r.nextDouble() < 0.05;
      final omitDiscountField = legacyNet;

      final cust = r.nextDouble() < 0.12 ? (r.nextBool() ? 'khach_le' : '') : customers[r.nextInt(customers.length)];

      // payment
      var method = const [
        'cash', 'cash', 'cash', 'transfer', 'card', 'wallet', 'qr', 'vietqr',
        'split', 'bank_transfer', 'Chuyển khoản', 'Tiền mặt', 'momo'
      ][r.nextInt(13)];
      var debt = 0.0;
      if (net > 0 && cust.isNotEmpty && cust != 'khach_le' && r.nextDouble() < 0.14) {
        debt = ((net * (0.2 + r.nextDouble() * 0.8)) ~/ 1000) * 1000.0;
        if (debt > net) debt = net;
      }
      final paid = net - debt;
      double? cashAmt;
      double? trfAmt;
      final m = method.toLowerCase();
      if (m == 'split') {
        final c = ((paid * r.nextDouble()) ~/ 1000) * 1000.0;
        cashAmt = c;
        trfAmt = paid - c;
      } else if (m == 'cash' || m == 'tiền mặt') {
        cashAmt = paid;
        trfAmt = 0;
      } else {
        cashAmt = 0;
        trfAmt = paid;
      }
      final omitPaid = !fullyReturned && debt == 0 && mode == 'completed' && r.nextDouble() < 0.05;

      final o = <String, dynamic>{
        'id': id,
        'customerId': cust,
        'createdAt': stamp,
        if (r.nextDouble() > 0.05) 'orderDate': stamp,
        'items': lines,
        'total': legacyNet ? net : totalField,
        if (discount > 0 && !omitDiscountField) 'discount': discount,
        'status': status,
        if (!omitPaid) 'amountPaid': paid,
        'debtAmount': debt,
        'paymentMethod': method,
        'storeId': s,
        'cashAmount': cashAmt,
        'transferAmount': trfAmt,
      };
      if (omitPaid) {
        o.remove('cashAmount');
        o.remove('transferAmount');
        if (m == 'split') o['paymentMethod'] = 'cash';
      }
      list.add(o);

      // versioned edit: original replaced (cancelled) + v2 completed
      if (mode == 'completed' && r.nextDouble() < 0.04) {
        list.add({
          ...o,
          'id': '$id-v2',
          'createdAt': stamp,
        });
        o['status'] = 'cancelled';
      }
    }
    orders[s] = list;
  }
  return Dataset(seed, orders, inv, products, customers);
}

Map<String, dynamic> _line(String pid, int q, double price) => {
      'productId': pid,
      'productName': pid,
      'quantity': q,
      'price': price,
      'originalPrice': price,
      'warrantyMonths': 0,
      'purchaseDate': '2026-07-01T00:00:00.000',
      'returnedQuantity': 0,
    };

// =============================================================================
// Reference calculator (independent re-implementation from the raw maps)
// =============================================================================

DateTime refDay(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

DateTime _instant(Object? s) => DateTime.parse(s.toString());

num _num(Object? v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);

String refStatus(Object? raw) {
  final s = (raw?.toString() ?? 'completed').trim().toLowerCase();
  if (s.contains('cancel') || s.contains('hủy') || s.contains('huỷ') || s.contains('huy')) {
    return 'cancelled';
  }
  if (s == 'returned' || s == 'return' || s.contains('trả hàng') || s.contains('đổi trả')) {
    return 'returned';
  }
  if (s == 'draft' || s.contains('lưu tạm')) return 'draft';
  return 'completed';
}

class RefLine {
  RefLine(this.pid, this.qty, this.returned, this.price);
  final String pid;
  final int qty;
  final int returned;
  final double price;
  int get active => max(0, qty - returned);
}

class RefOrder {
  RefOrder(this.raw)
      : status = refStatus(raw['status']),
        at = _instant(raw['orderDate'] ?? raw['createdAt']),
        sortAt = _instant(raw['createdAt'] ?? raw['orderDate']) {
    lines = [
      for (final l in (raw['items'] as List))
        RefLine(l['productId'].toString(), _num(l['quantity']).toInt(),
            _num(l['returnedQuantity']).toInt(), max(0, _num(l['price'])).toDouble()),
    ];
    var rawTotal = max(0, _num(raw['total'])).toDouble();
    var disc = max(0, _num(raw['discount'])).toDouble();
    final itemsSum = lines.fold<double>(0, (s, l) => s + l.price * l.qty);
    final anyReturn = lines.any((l) => l.returned > 0);
    var t = rawTotal;
    if (!anyReturn && itemsSum > rawTotal + 0.01) {
      t = itemsSum;
      if (disc <= 0.01) disc = itemsSum - rawTotal;
    }
    net = max(0, t - disc).toDouble();
  }
  final Map<String, dynamic> raw;
  final String status;
  final DateTime at;
  final DateTime sortAt;
  late final List<RefLine> lines;
  late final double net;
  bool get allReturned => lines.isNotEmpty && lines.every((l) => l.active <= 0);
  bool get isSale => status == 'completed' && !allReturned;
  String get customer => raw['customerId']?.toString() ?? '';

  /// amountPaid missing => fully paid (net).
  double get paid {
    final p = raw['amountPaid'];
    if (p == null) return net;
    return max(0, _num(p)).toDouble();
  }

  double get remainingDebt {
    final d = max(0, _num(raw['debtAmount'])).toDouble();
    return d > 0 ? d : max(0, net - paid).toDouble();
  }
}

class RefDay {
  double revenue = 0, cost = 0;
  int orders = 0, items = 0;
}

class RefProd {
  int qty = 0;
  double revenue = 0, cost = 0;
}

class RefStore {
  final Map<DateTime, RefDay> days = {};
  final Map<String, RefProd> prods = {};
  double get revenue => days.values.fold(0, (s, d) => s + d.revenue);
  double get cost => days.values.fold(0, (s, d) => s + d.cost);
  int get orders => days.values.fold(0, (s, d) => s + d.orders);
  int get items => days.values.fold(0, (s, d) => s + d.items);
}

/// Range-local FIFO as the app defines it: lots = import / audit(+) minus
/// audit(-) / transfer-export events dated <= end of range; POS `export_*`
/// rows ignored; only in-range sales consume lots, chronologically.
RefStore refCompute(
  List<Map<String, dynamic>> orders,
  List<Map> inv,
  List<Map> products,
  DateTime start,
  DateTime end, {
  bool importsOnlyInRange = false,
}) {
  final s0 = DateTime(start.year, start.month, start.day);
  final e0 = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
  final prod = {for (final p in products) p['id'].toString(): p};

  // lots[pid] = list of [qty, price]
  final lots = <String, List<List<num>>>{};
  final evs = inv.where((t) {
    final id = t['id'].toString();
    final type = t['type'].toString().toLowerCase();
    if (id.startsWith('export_')) return false;
    final d = _instant(t['date']);
    if (d.isAfter(e0)) return false;
    if (importsOnlyInRange) {
      return type == 'import' && !d.isBefore(s0);
    }
    return true;
  }).toList()
    ..sort((a, b) => _instant(a['date']).compareTo(_instant(b['date'])));
  void consume(String pid, int q) {
    final l = lots[pid];
    if (l == null) return;
    for (final lot in l) {
      if (q <= 0) break;
      final take = min(q, lot[0].toInt());
      lot[0] -= take;
      q -= take;
    }
  }

  for (final t in evs) {
    final pid = t['productId'].toString();
    final type = t['type'].toString().toLowerCase();
    final q = _num(t['quantity']).toInt();
    if (type == 'import') {
      if (q > 0) {
        final price = t['importPrice'] != null
            ? _num(t['importPrice']).toDouble()
            : (prod[pid]?['costPrice'] != null ? _num(prod[pid]!['costPrice']).toDouble() : 0.0);
        (lots[pid] ??= []).add([q, price]);
      }
    } else if (type == 'inventory_audit' || type == 'inventoryaudit') {
      if (t['isAuditNegative'] == true) {
        consume(pid, _num(t['auditDifference']).abs().toInt());
      } else {
        final dq = _num(t['auditDifference']).toInt();
        final price = t['importPrice'] != null
            ? _num(t['importPrice']).toDouble()
            : (prod[pid]?['costPrice'] != null ? _num(prod[pid]!['costPrice']).toDouble() : 0.0);
        if (dq > 0 || q > 0) (lots[pid] ??= []).add([dq > 0 ? dq : q, price]);
      }
    } else if (type == 'export') {
      consume(pid, q);
    }
  }

  final res = RefStore();
  // day buckets exist for each calendar day of the range
  for (var d = s0; !d.isAfter(DateTime(end.year, end.month, end.day));
      d = DateTime(d.year, d.month, d.day + 1)) {
    res.days[d] = RefDay();
  }
  final inRange = <RefOrder>[];
  for (final raw in orders) {
    final o = RefOrder(raw);
    if (o.at.isBefore(s0) || o.at.isAfter(e0)) continue;
    inRange.add(o);
  }
  inRange.sort((a, b) => a.sortAt.compareTo(b.sortAt));
  for (final o in inRange) {
    if (!o.isSale) continue;
    final day = res.days[refDay(o.at)]!;
    day.orders++;
    day.revenue += o.net;
    for (final l in o.lines) {
      if (l.active <= 0) continue;
      final p = prod[l.pid];
      final fallback = p == null
          ? 0.0
          : (p['costPrice'] != null
              ? _num(p['costPrice']).toDouble()
              : (p['price'] != null ? _num(p['price']).toDouble() * 0.7 : 0.0));
      var need = l.active;
      var cost = 0.0;
      for (final lot in lots[l.pid] ?? const <List<num>>[]) {
        if (need <= 0) break;
        final take = min(need, lot[0].toInt());
        cost += take * lot[1];
        lot[0] -= take;
        need -= take;
      }
      cost += need * fallback;
      final price = l.price != 0 ? l.price : (p != null ? _num(p['price']).toDouble() : 0.0);
      day.cost += cost;
      day.items += l.active;
      final pr = res.prods.putIfAbsent(l.pid, () => RefProd());
      pr.qty += l.active;
      pr.revenue += l.active * price;
      pr.cost += cost;
    }
  }
  return res;
}

class RefPayment {
  double cash = 0, transfer = 0, debt = 0, total = 0;
}

bool _nonCash(String m) {
  final x = m.toLowerCase();
  return !(x == 'cash' || x == 'tiền mặt' || x.isEmpty);
}

/// Payment breakdown rule (documented):
///  * Only status == completed orders (fully-returned legacy ones add 0).
///  * total += net payable; debt += remaining debt.
///  * split: cash += cashAmount, transfer += transferAmount.
///  * otherwise paid>0: whole `paid` to cash (cash) or transfer (all others).
///  * paid == 0 and no debt: whole net to the method's bucket.
/// => cash + transfer + debt == total whenever paid + debt == net.
RefPayment refPayment(List<Map<String, dynamic>> orders, DateTime start, DateTime end) {
  final s0 = DateTime(start.year, start.month, start.day);
  final e0 = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
  final res = RefPayment();
  for (final raw in orders) {
    final o = RefOrder(raw);
    if (o.at.isBefore(s0) || o.at.isAfter(e0)) continue;
    if (o.status != 'completed') continue;
    final method = (raw['paymentMethod'] ?? 'cash').toString().toLowerCase();
    res.total += o.net;
    final debt = o.remainingDebt;
    if (debt > 0) res.debt += debt;
    if (method.contains('split')) {
      res.cash += _num(raw['cashAmount']).toDouble();
      res.transfer += _num(raw['transferAmount']).toDouble();
    } else if (o.paid > 0) {
      if (_nonCash(method)) {
        res.transfer += o.paid;
      } else {
        res.cash += o.paid;
      }
    } else if (debt == 0) {
      if (_nonCash(method)) {
        res.transfer += o.net;
      } else {
        res.cash += o.net;
      }
    }
  }
  return res;
}

double refGrowth(double cur, double prior) {
  if (prior == 0 && cur == 0) return 0;
  if (prior == 0 && cur > 0) return 100;
  if (prior > 0 && cur == 0) return -100;
  return (cur - prior) / prior.abs() * 100;
}

/// Net-of-returns top products and customers over the range (completed, not
/// fully returned orders, active quantity only).
class RefRanking {
  final Map<String, int> qty = {};
  final Map<String, double> rev = {};
  final Map<String, double> custSpent = {};
  final Map<String, int> custOrders = {};
  final Map<int, double> hourRev = {};
  final Map<int, int> hourOrders = {};
}

RefRanking refRanking(List<Map<String, dynamic>> orders, DateTime start, DateTime end) {
  final s0 = DateTime(start.year, start.month, start.day);
  final e0 = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
  final r = RefRanking();
  for (final raw in orders) {
    final o = RefOrder(raw);
    if (o.at.isBefore(s0) || o.at.isAfter(e0)) continue;
    if (!o.isSale) continue;
    for (final l in o.lines) {
      if (l.active <= 0) continue;
      r.qty[l.pid] = (r.qty[l.pid] ?? 0) + l.active;
      r.rev[l.pid] = (r.rev[l.pid] ?? 0) + l.active * l.price;
    }
    if (o.customer.isNotEmpty) {
      r.custSpent[o.customer] = (r.custSpent[o.customer] ?? 0) + o.net;
      r.custOrders[o.customer] = (r.custOrders[o.customer] ?? 0) + 1;
    }
    final h = o.at.toLocal().hour;
    r.hourRev[h] = (r.hourRev[h] ?? 0) + o.net;
    r.hourOrders[h] = (r.hourOrders[h] ?? 0) + 1;
  }
  return r;
}

/// Random ranges: single day, week, month, cross-month, full, empty (before/after
/// data), inverted.
List<(DateTime, DateTime)> randomRanges(Random r) {
  DateTime day(int off) => DateTime(dataStart.year, dataStart.month, dataStart.day + off);
  final out = <(DateTime, DateTime)>[];
  final d = r.nextInt(dataDays);
  out.add((day(d), day(d)));
  final w = r.nextInt(dataDays - 7);
  out.add((day(w), day(w + 6)));
  final m = r.nextInt(3);
  out.add((DateTime(2026, 7 + m, 1), DateTime(2026, 7 + m + 1, 0)));
  out.add((DateTime(2026, 7, 15 + r.nextInt(10)), DateTime(2026, 8, 5 + r.nextInt(10))));
  final x = r.nextDouble();
  if (x < 0.1) out.add((day(0), day(dataDays - 1)));
  if (x > 0.85) out.add((DateTime(2026, 5, 1), DateTime(2026, 5, 9)));
  if (x > 0.92) out.add((DateTime(2026, 12, 1), DateTime(2026, 12, 3)));
  if (x > 0.97) out.add((day(10), day(5)));
  return out;
}
