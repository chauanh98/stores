import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';

void main() {
  group('Order Entity Tests', () {
    final testDate = DateTime(2026, 8, 17, 10, 30);
    final testItems = [
      OrderItem(
        productId: 'P001',
        productName: 'iPhone 17 Pro',
        quantity: 2,
        price: 30000000,
        warrantyMonths: 12,
        purchaseDate: testDate,
        returnedQuantity: 0,
      ),
      OrderItem(
        productId: 'P002',
        productName: 'Ốp lưng',
        quantity: 1,
        price: 500000,
        warrantyMonths: 0,
        purchaseDate: testDate,
        returnedQuantity: 1,
      ),
    ];

    test('Default values and getters calculation', () {
      final order = Order(
        id: 'HD000001',
        customerId: 'CUST001',
        createdAt: testDate,
        items: testItems,
        total: 60500000,
        amountPaid: 40000000,
        debtAmount: 20500000,
        paymentMethod: 'cash',
        createdBy: 'admin1',
        createdByName: 'Admin User',
        storeId: 'store_001',
      );

      expect(order.id, 'HD000001');
      expect(order.customerId, 'CUST001');
      expect(order.status, 'completed');
      expect(order.isCompleted, true);
      expect(order.isDraft, false);
      expect(order.isCancelled, false);
      expect(order.remainingDebt, 20500000);
      expect(order.hasDebt, true);
      expect(order.storeId, 'store_001');
    });

    test('Remaining debt is clamped to 0 when overpaid or paid in full', () {
      final fullyPaidOrder = Order(
        id: 'HD000002',
        customerId: 'CUST002',
        createdAt: testDate,
        items: testItems,
        total: 60000000,
        amountPaid: 60000000,
        debtAmount: 0,
      );

      expect(fullyPaidOrder.remainingDebt, 0.0);
      expect(fullyPaidOrder.hasDebt, false);

      final overpaidOrder = Order(
        id: 'HD000003',
        customerId: 'CUST003',
        createdAt: testDate,
        items: testItems,
        total: 50000000,
        amountPaid: 60000000,
      );

      expect(overpaidOrder.remainingDebt, 0.0);
      expect(overpaidOrder.hasDebt, false);
    });

    test('Status getters for draft and cancelled', () {
      final draftOrder = Order(
        id: 'HD_DRAFT',
        customerId: 'CUST001',
        createdAt: testDate,
        items: testItems,
        total: 1000000,
        status: 'draft',
      );
      expect(draftOrder.isDraft, true);
      expect(draftOrder.isCompleted, false);
      expect(draftOrder.isCancelled, false);

      final cancelledOrder = Order(
        id: 'HD_CANCEL',
        customerId: 'CUST001',
        createdAt: testDate,
        items: testItems,
        total: 1000000,
        status: 'cancelled',
        cancelReason: 'Khách đổi ý',
        cancelledAt: testDate,
        cancelledBy: 'admin1',
        cancelledByName: 'Admin User',
      );
      expect(cancelledOrder.isCancelled, true);
      expect(cancelledOrder.isCompleted, false);
      expect(cancelledOrder.isDraft, false);
      expect(cancelledOrder.cancelReason, 'Khách đổi ý');
      expect(cancelledOrder.cancelledAt, testDate);
      expect(cancelledOrder.cancelledBy, 'admin1');
      expect(cancelledOrder.cancelledByName, 'Admin User');

      final returnedOrder = Order(
        id: 'HD_RETURNED',
        customerId: 'CUST001',
        createdAt: testDate,
        items: testItems,
        total: 0,
        status: 'returned',
      );
      expect(returnedOrder.isReturned, true);
      expect(returnedOrder.hasReturns, true);
      expect(returnedOrder.isCompleted, false);
      expect(returnedOrder.isCancelled, false);

      final noReturnsOrder = Order(
        id: 'HD_NO_RETURNS',
        customerId: 'CUST001',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P001',
            productName: 'iPhone 17 Pro',
            quantity: 2,
            price: 30000000,
            warrantyMonths: 12,
            purchaseDate: testDate,
            returnedQuantity: 0,
          ),
        ],
        total: 60000000,
        status: 'completed',
      );
      expect(noReturnsOrder.isReturned, false);
      expect(noReturnsOrder.hasReturns, false);
    });

    test('copyWith properly updates all fields', () {
      final initialOrder = Order(
        id: 'HD000001',
        customerId: 'CUST001',
        createdAt: testDate,
        items: testItems,
        total: 60500000,
        amountPaid: 40000000,
        debtAmount: 20500000,
      );

      final cancelDate = DateTime(2026, 8, 17, 12, 0);
      final updated = initialOrder.copyWith(
        status: 'cancelled',
        amountPaid: 60500000,
        debtAmount: 0,
        cancelReason: 'Nhập sai hóa đơn',
        cancelledAt: cancelDate,
        cancelledBy: 'supervisor',
        cancelledByName: 'Supervisor Khanh',
        storeId: 'store_002',
      );

      expect(updated.id, 'HD000001');
      expect(updated.status, 'cancelled');
      expect(updated.isCancelled, true);
      expect(updated.amountPaid, 60500000);
      expect(updated.debtAmount, 0);
      expect(updated.remainingDebt, 0.0);
      expect(updated.cancelReason, 'Nhập sai hóa đơn');
      expect(updated.cancelledAt, cancelDate);
      expect(updated.cancelledBy, 'supervisor');
      expect(updated.cancelledByName, 'Supervisor Khanh');
      expect(updated.storeId, 'store_002');
    });
  });
}
