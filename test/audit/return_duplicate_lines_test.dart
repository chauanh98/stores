import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/core/errors/exceptions.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'audit_support.dart';

const _admin = UserAccount(
    username: 'a', displayName: 'A', role: 'admin', storeId: 'store_001');

OrderItem _line(int qty, double price) => OrderItem(
    productId: 'p1',
    productName: 'P1',
    quantity: qty,
    price: price,
    warrantyMonths: 0,
    purchaseDate: DateTime(2026, 8, 1));

void main() {
  late AOrderRepo orders;
  late AProductRepo products;
  late ProcessReturnOrderUseCase uc;
  late Order order;

  setUp(() {
    orders = AOrderRepo();
    products = AProductRepo()
      ..products['p1'] = const Product(
          id: 'p1',
          name: 'P1',
          code: 'P1',
          price: 100,
          costPrice: 50,
          branchStocks: {'store_001': 0},
          category: 'c');
    uc = ProcessReturnOrderUseCase(
        orderRepository: orders,
        productRepository: products,
        inventoryRepository: AInvRepo(),
        customerRepository: ACustomerRepo());
    // same product on 2 lines: 2 @100 and 3 @90
    order = Order(
      id: 'HD1',
      customerId: 'khach_le',
      createdAt: DateTime(2026, 8, 1),
      items: [_line(2, 100), _line(3, 90)],
      total: 470,
      amountPaid: 470,
      status: 'completed',
      storeId: 'store_001',
    );
    orders.orders[order.id] = order;
  });

  ReturnOrderItem ret(int q, double price) => ReturnOrderItem(
      productId: 'p1', productName: 'P1', quantity: q, price: price);

  test('returning 1 unit does not mark BOTH lines as returned', () async {
    await uc.execute(
        originalOrder: order,
        returnItems: [ret(1, 100)],
        storeId: 'store_001',
        currentUser: _admin);
    final saved = orders.orders['HD1']!;
    final totalReturned =
        saved.items.fold<int>(0, (s, i) => s + i.returnedQuantity);
    expect(totalReturned, 1, reason: 'exactly the returned quantity');
    expect(products.products['p1']!.stockInBranch('store_001'), 1);
  });

  test('return can span lines of the same product (4 of 2+3 units)', () async {
    await uc.execute(
        originalOrder: order,
        returnItems: [ret(4, 95)],
        storeId: 'store_001',
        currentUser: _admin);
    final saved = orders.orders['HD1']!;
    expect(saved.items[0].returnedQuantity, 2);
    expect(saved.items[1].returnedQuantity, 2);
    expect(saved.items.fold<int>(0, (s, i) => s + i.activeQuantity), 1);
  });

  test('returning more than all lines combined is rejected', () async {
    await expectLater(
        uc.execute(
            originalOrder: order,
            returnItems: [ret(6, 95)],
            storeId: 'store_001',
            currentUser: _admin),
        throwsA(isA<ValidationException>()));
    expect(products.products['p1']!.stockInBranch('store_001'), 0);
  });
}
