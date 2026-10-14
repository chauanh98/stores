// Edge / property tests and minimal regression tests for bugs found by the
// money fuzzer.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/core/errors/exceptions.dart';
import 'package:stores/data/models/order_model.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';

import 'money_fuzz_support.dart';

OrderItem item(String pid, int qty, double price,
        {int returned = 0, String name = 'P'}) =>
    OrderItem(
        productId: pid,
        productName: name,
        quantity: qty,
        price: price,
        warrantyMonths: 0,
        purchaseDate: DateTime(2026, 8, 1),
        returnedQuantity: returned);

Order mk(
        {String id = 'HD1',
        String cust = 'khach_le',
        String status = 'completed',
        required List<OrderItem> items,
        double? total,
        double discount = 0,
        double? paid,
        double debt = 0,
        String store = 'store_001'}) =>
    Order(
        id: id,
        customerId: cust,
        createdAt: DateTime(2026, 8, 1),
        items: items,
        total: total ?? items.fold(0.0, (a, i) => a + i.price * i.quantity),
        discount: discount,
        status: status,
        amountPaid: paid ?? 0,
        debtAmount: debt,
        storeId: store);

const prod = Product(
    id: 'p1',
    name: 'P1',
    code: 'P1',
    price: 100,
    costPrice: 50,
    branchStocks: {'store_001': 100},
    category: 'c');

Future<World> worldWith(Order o) async {
  final w = World();
  w.products.products['p1'] = prod;
  await w.orders.create(o);
  return w;
}

void main() {
  group('regressions found by fuzzing', () {
    test('draft order does not count as outstanding debt', () {
      final d = mk(status: 'draft', items: [item('p1', 2, 100)]);
      expect(d.remainingDebt, 0);
      expect(d.hasDebt, isFalse);
    });

    test('collect debt twice from the same stale snapshot applies once',
        () async {
      final o = mk(
          cust: 'c1',
          items: [item('p1', 1, 100)],
          paid: 0,
          debt: 100);
      final w = await worldWith(o);
      w.customers.customers['c1'] = const CustomerStub().c(debt: 100);
      await w.collect
          .execute(order: o, amount: 60, paymentMethod: 'cash', currentUser: admin);
      // stale snapshot (debt 100) tries to collect 60 again: only 40 remains
      await expectLater(
          w.collect.execute(
              order: o, amount: 60, paymentMethod: 'cash', currentUser: admin),
          throwsA(isA<ValidationException>()));
      expect(w.customers.customers['c1']!.currentDebt, 40);
      expect((await w.orders.fetchById('HD1'))!.debtAmount, 40);
    });

    test('collect debt rejects NaN / Infinity amounts', () async {
      final o = mk(cust: 'c1', items: [item('p1', 1, 100)], debt: 100);
      final w = await worldWith(o);
      w.customers.customers['c1'] = const CustomerStub().c(debt: 100);
      for (final a in [double.nan, double.infinity, double.negativeInfinity]) {
        await expectLater(
            w.collect.execute(
                order: o, amount: a, paymentMethod: 'cash', currentUser: admin),
            throwsA(isA<ValidationException>()));
      }
    });

    test('return: duplicate product entries cannot exceed available qty',
        () async {
      final o = mk(items: [item('p1', 3, 100)], paid: 300);
      final w = await worldWith(o);
      await expectLater(
          w.ret.execute(
              originalOrder: o,
              returnItems: const [
                ReturnOrderItem(
                    productId: 'p1', productName: 'P', quantity: 2, price: 100),
                ReturnOrderItem(
                    productId: 'p1', productName: 'P', quantity: 2, price: 100),
              ],
              storeId: 'store_001',
              currentUser: admin),
          throwsA(isA<ValidationException>()));
      expect(w.products.products['p1']!.stockInBranch('store_001'), 100);
    });

    test('return: negative / NaN unit price is rejected', () async {
      final o = mk(items: [item('p1', 3, 100)], paid: 300);
      final w = await worldWith(o);
      for (final p in [-50.0, double.nan, double.infinity]) {
        await expectLater(
            w.ret.execute(
                originalOrder: o,
                returnItems: [
                  ReturnOrderItem(
                      productId: 'p1', productName: 'P', quantity: 1, price: p)
                ],
                storeId: 'store_001',
                currentUser: admin),
            throwsA(isA<ValidationException>()));
      }
      expect((await w.orders.fetchById('HD1'))!.total, 300);
    });

    test('RTDB update() merge: discount 0 after return must overwrite old value',
        () async {
      // Full return of a discounted order => discount drops to 0.
      final o = mk(items: [item('p1', 2, 100)], discount: 50, paid: 150);
      final w = await worldWith(o);
      await w.ret.execute(
          originalOrder: o,
          returnItems: const [
            ReturnOrderItem(
                productId: 'p1', productName: 'P', quantity: 2, price: 100)
          ],
          storeId: 'store_001',
          currentUser: admin);
      final after = (await w.orders.fetchById('HD1'))!;
      expect(after.status, 'returned');
      expect(after.discount, 0, reason: 'stale discount survived merge-update');
      expect(after.total, 0);
    });

    test('non-finite / negative values in legacy maps are sanitised', () {
      final m = OrderModel.fromMap({
        'id': 'X',
        'total': 'Infinity',
        'discount': 'NaN',
        'amountPaid': 'Infinity',
        'debtAmount': 'NaN',
        'cashAmount': 'Infinity',
        'items': [
          {'productId': 'a', 'quantity': -4, 'price': 'NaN'},
          {'productId': 'b', 'quantity': double.infinity, 'price': 10},
          {'productId': 'c', 'quantity': 2, 'price': 5, 'returnedQuantity': -9},
        ],
      });
      for (final v in [m.total, m.discount, m.amountPaid, m.debtAmount, m.cashAmount!]) {
        expect(v.isFinite, isTrue);
      }
      expect(m.items.every((i) => i.quantity >= 0 && i.returnedQuantity >= 0),
          isTrue);
    });

    test('cart: negative custom price with item discount does not throw', () {
      final item = CartItem(
          product: prod, quantity: 2, customPrice: -10, discount: 10);
      expect(item.effectivePrice, 0);
      expect(item.total, 0);
      final nan = CartItem(product: prod, quantity: 2, customPrice: double.nan);
      expect(nan.total, 0);
    });
  });

  group('edge cases', () {
    test('discount larger than total: net clamps to 0, flows stay sane',
        () async {
      final o = mk(items: [item('p1', 2, 100)], discount: 500, paid: 0);
      expect(o.netPayable, 0);
      final w = await worldWith(o);
      final res = await w.ret.execute(
          originalOrder: o,
          returnItems: const [
            ReturnOrderItem(
                productId: 'p1', productName: 'P', quantity: 1, price: 100)
          ],
          storeId: 'store_001',
          currentUser: admin);
      expect(res.totalRefund, 0);
      expect(res.updatedOrder.total, 100);
      expect(res.updatedOrder.netPayable, 0);
      expect(res.updatedOrder.amountPaid, 0);
      await w.cancel.execute(
          order: res.updatedOrder,
          cancelReason: 'x',
          currentUser: admin,
          storeId: 'store_001');
      expect(w.products.products['p1']!.stockInBranch('store_001'), 102);
    });

    test('100% discount: free order returns refund nothing and cancel restores',
        () async {
      final o = mk(items: [item('p1', 3, 1e10)], discount: 3e10, paid: 0);
      final w = await worldWith(o);
      final res = await w.ret.execute(
          originalOrder: o,
          returnItems: const [
            ReturnOrderItem(
                productId: 'p1', productName: 'P', quantity: 3, price: 1e10)
          ],
          storeId: 'store_001',
          currentUser: admin);
      expect(res.totalRefund, 0);
      expect(res.cashRefunded, 0);
      expect(res.updatedOrder.status, 'returned');
      expect(res.updatedOrder.total, 0);
    });

    test('zero-price lines: return/cancel are no-money but restore stock',
        () async {
      final o = mk(items: [item('p1', 4, 0)], paid: 0);
      final w = await worldWith(o);
      final res = await w.ret.execute(
          originalOrder: o,
          returnItems: const [
            ReturnOrderItem(
                productId: 'p1', productName: 'P', quantity: 4, price: 0)
          ],
          storeId: 'store_001',
          currentUser: admin);
      expect(res.totalRefund, 0);
      expect(w.products.products['p1']!.stockInBranch('store_001'), 104);
    });

    test('1e10-scale money stays finite and consistent through return+cancel',
        () async {
      final o = mk(
          cust: 'c1',
          items: [item('p1', 150, 9.99e9)],
          paid: 1e12,
          debt: 150 * 9.99e9 - 1e12);
      final w = await worldWith(o);
      w.customers.customers['c1'] = const CustomerStub()
          .c(debt: o.debtAmount, sales: o.total);
      final res = await w.ret.execute(
          originalOrder: o,
          returnItems: const [
            ReturnOrderItem(
                productId: 'p1', productName: 'P', quantity: 50, price: 9.99e9)
          ],
          storeId: 'store_001',
          currentUser: admin);
      for (final v in [res.totalRefund, res.debtDeducted, res.cashRefunded]) {
        expect(v.isFinite, isTrue);
      }
      expect(near(res.updatedOrder.amountPaid + res.updatedOrder.debtAmount,
          res.updatedOrder.netPayable), isTrue);
      await w.cancel.execute(
          order: res.updatedOrder,
          cancelReason: 'x',
          currentUser: admin,
          storeId: 'store_001');
      expect(w.customers.customers['c1']!.currentDebt, closeTo(0, 1));
      expect(w.products.products['p1']!.stockInBranch('store_001'), 250); // 100 + 50 returned + 100 cancelled
    });

    test('cart rejects 0 / negative quantity lines', () {
      final n = MultiCartNotifier();
      n.addToCart(prod, quantity: 0);
      n.addToCart(prod, quantity: -2);
      expect(n.state.activeTab.items, isEmpty);
      n.addToCart(prod, quantity: 2);
      n.updateQuantity('p1', 0);
      expect(n.state.activeTab.items, isEmpty);
    });

    test('Unicode / emoji / 100k-char names survive the RTDB round trip',
        () async {
      final long = '長' * 100000;
      for (final name in ['🛒😀 Đồ chơi ☕', long, '', '"quote" \\ \n tab\t']) {
        final o = mk(items: [item('p1', 1, 1, name: name)], paid: 1);
        final w = await worldWith(o);
        final back = (await w.orders.fetchById('HD1'))!;
        expect(back.items.single.productName, name);
      }
    });

    test('legacy maps: missing fields tolerated', () {
      final m = OrderModel.fromMap({'id': 'L1'});
      expect(m.total, 0);
      expect(m.status, 'completed');
      expect(m.items, isEmpty);
      final m2 = OrderModel.fromMap({
        'id': 'L2',
        'total': '1000',
        'items': {
          'a': {'productId': 'p', 'quantity': '3', 'price': '400'}
        }
      });
      // total reconciled with items (1200) and the 200 gap becomes discount
      expect(m2.total, 1200);
      expect(m2.discount, 200);
      expect(m2.netPayable, 1000);
    });

    test('status string variants', () {
      const cases = {
        'Đã hủy': 'cancelled',
        'CANCELED': 'cancelled',
        'huỷ': 'cancelled',
        'cancelled': 'cancelled',
        'Trả hàng': 'returned',
        'đổi trả': 'returned',
        'returned': 'returned',
        'Lưu tạm': 'draft',
        ' Draft ': 'draft',
        'completed': 'completed',
        'Hoàn thành': 'completed',
        '': 'completed',
      };
      cases.forEach((raw, want) {
        expect(OrderModel.fromMap({'id': 'S', 'status': raw}).status, want,
            reason: raw);
      });
    });

    test('POS payment math invariant (mirror): paid<=net, paid+debt==net',
        () {
      final r = Random(stressSeed);
      for (var i = 0; i < 20000; i++) {
        final net = r.nextBool() ? r.nextDouble() * 1e10 : r.nextInt(1000) / 1.0;
        final walk = r.nextBool();
        final p = posPay(r, net, walk);
        expect(p.paid, inInclusiveRange(0, net));
        final debt = (net - p.paid).clamp(0.0, net);
        expect(near(p.paid + debt, net), isTrue);
        if (walk) expect(debt, lessThan(0.01), reason: 'walk-in must never carry debt');
      }
    });
  });
}

class CustomerStub {
  const CustomerStub();
  Customer c({double debt = 0, double sales = 0}) => Customer(
      id: 'c1',
      name: 'C1',
      phone: '',
      email: '',
      address: '',
      purchases: const [],
      currentDebt: debt,
      totalSales: sales,
      netSales: sales);
}
