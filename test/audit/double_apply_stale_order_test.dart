import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'audit_support.dart';

const admin = UserAccount(
    username: 'a', displayName: 'A', role: 'admin', storeId: 'store_001');

Order completedOrder({String status = 'completed'}) => Order(
      id: 'HD1',
      customerId: 'khach_le',
      createdAt: DateTime(2026, 8, 1),
      items: [
        OrderItem(
            productId: 'p1',
            productName: 'P1',
            quantity: 2,
            price: 100,
            warrantyMonths: 0,
            purchaseDate: DateTime(2026, 8, 1))
      ],
      total: 200,
      amountPaid: 200,
      status: status,
      storeId: 'store_001',
    );

const prod = Product(
    id: 'p1',
    name: 'P1',
    code: 'P1',
    price: 100,
    costPrice: 50,
    branchStocks: {'store_001': 5},
    category: 'c');

void main() {
  test('cancelling the same (stale) order twice restores stock only once',
      () async {
    final orders = AOrderRepo();
    final products = AProductRepo()..products['p1'] = prod;
    final uc = CancelInvoiceUseCase(
        orderRepository: orders,
        productRepository: products,
        inventoryRepository: AInvRepo(),
        customerRepository: ACustomerRepo());
    final order = completedOrder();
    orders.orders[order.id] = order;

    // Two devices / double tap both hold the pre-cancel snapshot.
    await uc.execute(
        order: order, cancelReason: 'x', currentUser: admin, storeId: 'store_001');
    try {
      await uc.execute(
          order: order,
          cancelReason: 'x',
          currentUser: admin,
          storeId: 'store_001');
    } catch (_) {}
    expect(products.products['p1']!.stockInBranch('store_001'), 7,
        reason: '5 + 2 returned to shelf exactly once');
  });

  test('cancelling a DRAFT order must not add stock (draft never deducted it)',
      () async {
    final orders = AOrderRepo();
    final products = AProductRepo()..products['p1'] = prod;
    final uc = CancelInvoiceUseCase(
        orderRepository: orders,
        productRepository: products,
        inventoryRepository: AInvRepo(),
        customerRepository: ACustomerRepo());
    await uc.execute(
        order: completedOrder(status: 'draft'),
        cancelReason: 'x',
        currentUser: admin,
        storeId: 'store_001');
    expect(products.products['p1']!.stockInBranch('store_001'), 5);
  });

  test('submitting the same return twice (stale order) restores stock once',
      () async {
    final orders = AOrderRepo();
    final products = AProductRepo()..products['p1'] = prod;
    final uc = ProcessReturnOrderUseCase(
        orderRepository: orders,
        productRepository: products,
        inventoryRepository: AInvRepo(),
        customerRepository: ACustomerRepo());
    final order = completedOrder();
    orders.orders[order.id] = order;
    final items = [
      const ReturnOrderItem(
          productId: 'p1', productName: 'P1', quantity: 2, price: 100)
    ];
    await uc.execute(
        originalOrder: order,
        returnItems: items,
        storeId: 'store_001',
        currentUser: admin);
    try {
      await uc.execute(
          originalOrder: order,
          returnItems: items,
          storeId: 'store_001',
          currentUser: admin);
    } catch (_) {}
    expect(products.products['p1']!.stockInBranch('store_001'), 7);
  });
}
