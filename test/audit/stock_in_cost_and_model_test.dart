import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/cancel_stock_in_receipt_use_case.dart';
import 'package:stores/application/inventories/usecases/complete_stock_in_receipt_use_case.dart';
import 'package:stores/data/models/order_model.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/repositories/stock_in_receipt_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

import 'audit_support.dart';

class _SupRepo implements SupplierRepository {
  @override
  dynamic noSuchMethod(Invocation i) async => null;
}

class _ReceiptRepo implements StockInReceiptRepository {
  @override
  dynamic noSuchMethod(Invocation i) async => null;
}

StockInReceipt receipt(int qty, double price) => StockInReceipt(
      id: 'r${qty}_$price',
      importCode: 'PN$qty',
      date: DateTime(2026, 8, 1),
      storeId: 'store_001',
      status: 'completed',
      items: [
        StockInReceiptItem(
            transactionId: 't', productId: 'p1', quantity: qty, unitPrice: price)
      ],
    );

void main() {
  test('weighted-average cost is not skewed by alias keys (store_001/branch_1)',
      () async {
    final products = AProductRepo();
    // Shape produced by the use case itself: both aliases hold the SAME 10 units.
    products.products['p1'] = const Product(
        id: 'p1',
        name: 'P',
        code: 'P',
        price: 300,
        costPrice: 100,
        branchStocks: {'store_001': 10, 'branch_1': 10},
        category: 'c');
    final uc = CompleteStockInReceiptUseCase(
        productRepository: products,
        inventoryRepository: AInvRepo(),
        supplierRepository: _SupRepo(),
        receiptRepository: _ReceiptRepo());
    await uc.execute(receipt(10, 200));
    // (10*100 + 10*200) / 20 = 150
    expect(products.products['p1']!.costPrice, closeTo(150, 0.001));
  });

  test('cancelling a stock-in restores the pre-receipt costPrice', () async {
    final products = AProductRepo();
    products.products['p1'] = const Product(
        id: 'p1',
        name: 'P',
        code: 'P',
        price: 300,
        costPrice: 100,
        branchStocks: {'store_001': 10},
        category: 'c');
    final r = receipt(10, 300);
    final complete = CompleteStockInReceiptUseCase(
        productRepository: products,
        inventoryRepository: AInvRepo(),
        supplierRepository: _SupRepo(),
        receiptRepository: _ReceiptRepo());
    final done = await complete.execute(r);
    final cancel = CancelStockInReceiptUseCase(
        productRepository: products,
        inventoryRepository: AInvRepo(),
        supplierRepository: _SupRepo(),
        receiptRepository: _ReceiptRepo());
    await cancel.execute(
        storeId: 'store_001', receipt: done, reason: 'x', cancelledBy: 'u');
    expect(products.products['p1']!.stockInBranch('store_001'), 10);
    expect(products.products['p1']!.costPrice, closeTo(100, 0.001));
  });

  test('order reloaded after a partial return keeps net payable', () {
    // Stored by ProcessReturnOrderUseCase: total 100, discount 10, return half
    // -> total 50, discount 5 (net 45). Item still lists qty 2 with 1 returned.
    final m = OrderModel.fromMap({
      'id': 'HD1',
      'customerId': 'c',
      'createdAt': DateTime(2026, 8, 1).toIso8601String(),
      'total': 50.0,
      'discount': 5.0,
      'amountPaid': 45.0,
      'status': 'completed',
      'items': [
        {
          'productId': 'p1',
          'productName': 'P',
          'quantity': 2,
          'price': 50.0,
          'returnedQuantity': 1,
          'warrantyMonths': 0,
          'purchaseDate': DateTime(2026, 8, 1).toIso8601String(),
        }
      ],
    });
    expect(m.netPayable, closeTo(45, 0.001));
  });
}
