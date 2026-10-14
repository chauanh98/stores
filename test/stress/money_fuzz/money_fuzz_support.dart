import 'dart:io';
import 'dart:math';

import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/application/orders/usecases/collect_invoice_debt_usecase.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/repositories/order_repository_impl.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../../audit/audit_support.dart';
import '../../support/fake_rtdb.dart';

int envInt(String k, int d) => int.tryParse(Platform.environment[k] ?? '') ?? d;
final int stressSeed = envInt('STRESS_SEED', 20261014);
final int stressIter = envInt('STRESS_ITER', 2000);

const admin = UserAccount(
    username: 'admin', displayName: 'Admin', role: 'admin', storeId: 'store_001');
const branches = ['store_001', 'store_002'];
const initialStock = 1000000;

bool near(double a, double b) {
  if (a.isNaN || b.isNaN) return false;
  final mag = max(a.abs(), b.abs());
  return (a - b).abs() <= 0.01 + 1e-11 * mag;
}

/// Everything the real use cases touch, wired on in-memory fakes. Orders go
/// through the REAL OrderRepositoryImpl + OrderModel on a FakeRtdb so that
/// (de)serialisation and RTDB `update` merge semantics are exercised.
class World {
  final db = FakeRtdb();
  late final OrderRepositoryImpl orders =
      OrderRepositoryImpl(OrderRemoteDataSource(db, 'shop'));
  final products = AProductRepo();
  final inv = AInvRepo();
  final customers = ACustomerRepo();
  late final cancel = CancelInvoiceUseCase(
      orderRepository: orders,
      productRepository: products,
      inventoryRepository: inv,
      customerRepository: customers);
  late final ret = ProcessReturnOrderUseCase(
      orderRepository: orders,
      productRepository: products,
      inventoryRepository: inv,
      customerRepository: customers);
  late final collect = CollectInvoiceDebtUseCase(
      orderRepository: orders, customerRepository: customers);
}

class Line {
  final String pid;
  final int qty;
  final double price; // effective unit price
  final double orig;
  final double disc;
  final bool pct;
  Line(this.pid, this.qty, this.price, this.orig, this.disc, this.pct);
}

class Pay {
  final String method;
  final double paid;
  final double? cash;
  final double? transfer;
  Pay(this.method, this.paid, this.cash, this.transfer);
}

/// Mirrors the maths in lib/presentation/orders/pages/pos_payment_page.dart
/// (read-only there): paid = input.clamp(0, netPay); debt = netPay - paid.
Pay posPay(Random r, double net, bool walkIn) {
  final mode = walkIn ? 0 : r.nextInt(5); // 0 full 1 partial 2 zero 3 overpay 4 split-partial
  final methods = ['cash', 'transfer', 'card', 'wallet', 'qr'];
  final m = methods[r.nextInt(methods.length)];
  double input;
  switch (mode) {
    case 0:
      input = net;
      break;
    case 1:
      input = net * r.nextDouble();
      break;
    case 2:
      input = 0;
      break;
    case 3:
      input = net * (1 + r.nextDouble()) + r.nextInt(1000);
      break;
    default:
      input = -1;
  }
  if (mode == 4 || (walkIn && r.nextInt(4) == 0)) {
    final cash = net * r.nextDouble() * (walkIn ? 0.5 : 0.6);
    final tr = walkIn ? net - cash : net * r.nextDouble() * 0.6;
    final paid = (cash + tr).clamp(0.0, net);
    return Pay('split', paid, cash, tr);
  }
  final paid = input.clamp(0.0, net);
  if (m == 'cash') return Pay('cash', paid, paid, 0.0);
  return Pay(m, paid, 0.0, paid);
}

double randPrice(Random r) {
  final k = r.nextInt(100);
  if (k < 5) return 0.0;
  if (k < 8) return (r.nextDouble() * 9.99e9);
  if (k < 8 + 20) return (r.nextInt(2000000) / 100.0) + 0.01 * r.nextInt(100);
  if (k < 40) return 0.5 + r.nextInt(100000);
  return (1 + r.nextInt(5000)) * 1000.0;
}

const _names = [
  'Bàn phím cơ',
  'Chuột 🖱️ không dây',
  '日本語の商品',
  'x',
  'Sản phẩm có tên rất rất dài ',
  '',
];
String randName(Random r, int i) {
  final base = _names[r.nextInt(_names.length)];
  if (base.startsWith('Sản phẩm')) return '$base${'dài ' * 300}$i';
  return '$base $i';
}

class Scenario {
  final World w = World();
  final Random r;
  final List<Product> catalog = [];
  final List<String> customerIds = [];
  Scenario(this.r) {
    final n = 6 + r.nextInt(14);
    for (var i = 0; i < n; i++) {
      final id = 'p$i';
      final isCombo = i >= n - 3 && n > 6;
      final comps = isCombo
          ? [
              for (final ci in {r.nextInt(n - 3), r.nextInt(n - 3)})
                ComboComponent(
                    productId: 'p$ci',
                    productCode: 'p$ci',
                    productName: 'p$ci',
                    quantity: 1 + r.nextInt(3))
            ]
          : <ComboComponent>[];
      final price = randPrice(r);
      final p = Product(
        id: id,
        name: randName(r, i),
        code: id,
        price: price,
        costPrice: price / 2,
        branchStocks: {for (final b in branches) b: initialStock},
        category: 'c',
        isCombo: isCombo,
        comboComponents: comps,
        unit: r.nextBool() ? 'cái' : 'thùng',
      );
      catalog.add(p);
      w.products.products[id] = p;
    }
    // customers
    for (var i = 0; i < 3; i++) {
      final hasNull = r.nextInt(5) == 0;
      final ts = hasNull ? null : r.nextInt(100000000) / 1.0;
      final c = Customer(
        id: 'c$i',
        name: 'KH $i',
        phone: '09$i',
        email: '',
        address: '',
        purchases: const [],
        currentDebt: r.nextInt(3) == 0 ? null : r.nextInt(20000000) / 1.0,
        totalSales: ts,
        netSales: ts,
      );
      w.customers.customers[c.id] = c;
      customerIds.add(c.id);
    }
  }

  Product prod(String id) => catalog.firstWhere((p) => p.id == id);

  /// Random cart: 1-150 lines, duplicates, wholesale/retail, item discounts.
  List<Line> randLines() {
    final maxLines = r.nextInt(10) == 0 ? 150 : (1 + r.nextInt(12));
    final lines = <Line>[];
    final n = 1 + r.nextInt(maxLines);
    for (var i = 0; i < n; i++) {
      final p = (lines.isNotEmpty && r.nextInt(4) == 0)
          ? prod(lines[r.nextInt(lines.length)].pid) // duplicate product line
          : catalog[r.nextInt(catalog.length)];
      final wholesale = r.nextBool();
      final orig = wholesale ? p.price * 0.8 : p.price;
      var disc = 0.0;
      var pct = false;
      if (r.nextInt(4) == 0) {
        pct = r.nextBool();
        disc = pct ? r.nextInt(101).toDouble() : orig * r.nextDouble();
      }
      final unitDisc = disc <= 0
          ? 0.0
          : (pct ? (orig * disc / 100) : disc).clamp(0.0, orig);
      final eff = orig - unitDisc;
      lines.add(Line(p.id, 1 + r.nextInt(30), eff, orig, disc, pct));
    }
    return lines;
  }
}
