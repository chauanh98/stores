// Performance guard: 5,000 generated orders through OrderModel parsing +
// KPI-style aggregation must stay under 3 s (debug mode).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/models/order_model.dart';

import 'money_fuzz_support.dart';

void main() {
  test('5,000 orders parse + aggregate < 3s', () {
    final r = Random(stressSeed);
    final maps = <Map<String, dynamic>>[];
    for (var i = 0; i < 5000; i++) {
      final n = 1 + r.nextInt(r.nextInt(10) == 0 ? 150 : 8);
      final items = [
        for (var k = 0; k < n; k++)
          {
            'productId': 'p${r.nextInt(50)}',
            'productName': 'Sản phẩm $k',
            'quantity': 1 + r.nextInt(20),
            'price': randPrice(r),
            'returnedQuantity': r.nextInt(8) == 0 ? 1 : 0,
          }
      ];
      var total = 0.0;
      for (final it in items) {
        total += (it['price'] as double) * (it['quantity'] as int);
      }
      final status = ['completed', 'completed', 'cancelled', 'draft', 'returned'][r.nextInt(5)];
      maps.add({
        'id': 'HD$i',
        'customerId': r.nextBool() ? 'khach_le' : 'c${r.nextInt(100)}',
        'createdAt': DateTime(2026, 1, 1).add(Duration(hours: i)).toIso8601String(),
        'total': total,
        'discount': total * r.nextDouble() * 0.2,
        'amountPaid': total * 0.5,
        'debtAmount': total * 0.3,
        'status': status,
        'paymentMethod': 'cash',
        'items': items,
      });
    }
    final sw = Stopwatch()..start();
    var revenue = 0.0, debt = 0.0, units = 0;
    final byDay = <int, double>{};
    for (final m in maps) {
      final o = OrderModel.fromMap(m);
      if (o.isCancelled || o.status == 'draft') continue;
      revenue += o.netPayable;
      debt += o.debtAmount;
      for (final it in o.items) {
        units += it.activeQuantity;
      }
      byDay.update(o.createdAt.day, (v) => v + o.netPayable,
          ifAbsent: () => o.netPayable);
    }
    sw.stop();
    print('MONEY_FUZZ perf: 5000 orders parsed+aggregated in '
        '${sw.elapsedMilliseconds}ms (revenue=$revenue units=$units)');
    expect(revenue.isFinite && debt.isFinite, isTrue);
    expect(sw.elapsedMilliseconds, lessThan(3000));
  });
}
