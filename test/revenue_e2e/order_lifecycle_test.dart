import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/data/models/order_item_model.dart';
import 'package:stores/data/models/order_model.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../audit/audit_support.dart';
import 'dataset.dart';

const admin = UserAccount(
    username: 'a', displayName: 'A', role: 'admin', storeId: 'store_001');

Order mk(String id, List<OrderItem> items, double total,
        {String status = 'completed', double discount = 0}) =>
    Order(
      id: id,
      customerId: 'khach_le',
      createdAt: DateTime(2026, 10, 12, 10),
      items: items,
      total: total,
      discount: discount,
      amountPaid: total - discount,
      status: status,
      storeId: 'store_001',
    );

OrderItem oi(String pid, int q, double price) => OrderItem(
    productId: pid,
    productName: pid,
    quantity: q,
    price: price,
    warrantyMonths: 0,
    purchaseDate: DateTime(2026, 10, 12));

Map<String, dynamic> toMap(Order o) => OrderModel(
      id: o.id,
      customerId: o.customerId,
      createdAt: o.createdAt,
      total: o.total,
      discount: o.discount,
      status: o.status,
      amountPaid: o.amountPaid,
      debtAmount: o.debtAmount,
      storeId: o.storeId,
      items: o.items
          .map((i) => OrderItemModel(
              productId: i.productId,
              productName: i.productName,
              quantity: i.quantity,
              price: i.price,
              warrantyMonths: 0,
              purchaseDate: i.purchaseDate,
              returnedQuantity: i.returnedQuantity))
          .toList(),
    ).toMap();

Product prod(String id) => Product(
    id: id,
    name: id,
    code: id,
    price: 100000,
    costPrice: 60000,
    branchStocks: const {'store_001': 50},
    category: 'c');

void main() {
  // Lots for A: 10@50k (10-01), 10@55k (10-02)
  final inventory = <Map>[
    inv('i1', 'A', 'import', 10, '2026-10-01T09:00:00.000', price: 50000),
    inv('i2', 'A', 'import', 10, '2026-10-02T09:00:00.000', price: 55000),
  ];

  Future<dynamic> report(List<Order> orders) => repoFor(
          'store_001', orders.map(toMap).toList(), inventory)
      .getRevenueByDate(DateTime(2026, 10, 12));

  late AOrderRepo orders;
  late AProductRepo prods;
  late AInvRepo invRepo;
  late CancelInvoiceUseCase cancel;
  late ProcessReturnOrderUseCase ret;

  setUp(() {
    orders = AOrderRepo();
    prods = AProductRepo()..products['A'] = prod('A');
    invRepo = AInvRepo();
    final cust = ACustomerRepo();
    cancel = CancelInvoiceUseCase(
        orderRepository: orders,
        productRepository: prods,
        inventoryRepository: invRepo,
        customerRepository: cust);
    ret = ProcessReturnOrderUseCase(
        orderRepository: orders,
        productRepository: prods,
        inventoryRepository: invRepo,
        customerRepository: cust);
  });

  test('baseline: A x4 @100k => revenue 400k, FIFO cost 4*50k = 200k', () async {
    final r = await report([mk('HD1', [oi('A', 4, 100000)], 400000)]);
    expect(r.totalRevenue, 400000);
    expect(r.totalCost, 200000);
    expect(r.profit, 200000);
  });

  test('cancel => order excluded from revenue, cost and counts', () async {
    final o = mk('HD1', [oi('A', 4, 100000)], 400000);
    orders.orders['HD1'] = o;
    final cancelled = await cancel.execute(
        order: o, cancelReason: 'sai', currentUser: admin, storeId: 'store_001');
    final r = await report([cancelled]);
    expect(r.totalRevenue, 0);
    expect(r.totalCost, 0);
    expect(r.totalOrders, 0);
    expect(r.totalItemsSold, 0);
  });

  test('partial return => revenue reduced by exactly the refund (1 x 100k)',
      () async {
    final o = mk('HD1', [oi('A', 4, 100000)], 400000);
    orders.orders['HD1'] = o;
    final res = await ret.execute(
        originalOrder: o,
        returnItems: const [
          ReturnOrderItem(
              productId: 'A', productName: 'A', price: 100000, quantity: 1)
        ],
        storeId: 'store_001',
        currentUser: admin);
    expect(res.totalRefund, 100000);
    final r = await report([res.updatedOrder]);
    // 400k - 100k refund = 300k; active qty 3 => cost 3*50k = 150k
    expect(r.totalRevenue, 300000);
    expect(r.totalCost, 150000);
    expect(r.totalItemsSold, 3);
    expect(r.totalOrders, 1);
  });

  test('full return => order drops out of revenue entirely', () async {
    final o = mk('HD1', [oi('A', 4, 100000)], 400000);
    orders.orders['HD1'] = o;
    final res = await ret.execute(
        originalOrder: o,
        returnItems: const [
          ReturnOrderItem(
              productId: 'A', productName: 'A', price: 100000, quantity: 4)
        ],
        storeId: 'store_001',
        currentUser: admin);
    final r = await report([res.updatedOrder]);
    expect(res.updatedOrder.status, 'returned');
    expect(r.totalRevenue, 0);
    expect(r.totalOrders, 0);
  });

  test('versioned edit: cancelled original + v2 counted once (not doubled)',
      () async {
    final o = mk('HD1', [oi('A', 4, 100000)], 400000);
    orders.orders['HD1'] = o;
    final cancelled = await cancel.execute(
        order: o,
        cancelReason: 'sửa hóa đơn',
        currentUser: admin,
        storeId: 'store_001',
        isReplacement: true);
    final v2 = mk('HD1-v2', [oi('A', 5, 100000)], 500000);
    final r = await report([cancelled, v2]);
    // only v2: rev 500k, cost 5*50k = 250k, 1 order
    expect(r.totalRevenue, 500000);
    expect(r.totalCost, 250000);
    expect(r.totalOrders, 1);
    expect(r.totalItemsSold, 5);
  });
}
