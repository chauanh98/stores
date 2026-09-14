import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/order_item.dart';

void main() {
  group('OrderItem Entity Tests', () {
    final testDate = DateTime(2026, 8, 17);

    test('Default returnedQuantity is 0 and activeQuantity calculation', () {
      final item = OrderItem(
        productId: 'P001',
        productName: 'Bàn phím cơ',
        quantity: 5,
        price: 1200000,
        warrantyMonths: 24,
        purchaseDate: testDate,
      );

      expect(item.returnedQuantity, 0);
      expect(item.activeQuantity, 5);
      expect(item.remainingQuantity, 5);
      expect(item.isFullyReturned, false);
    });

    test('Partial return calculates activeQuantity correctly', () {
      final item = OrderItem(
        productId: 'P001',
        productName: 'Bàn phím cơ',
        quantity: 5,
        price: 1200000,
        warrantyMonths: 24,
        purchaseDate: testDate,
        returnedQuantity: 2,
      );

      expect(item.returnedQuantity, 2);
      expect(item.activeQuantity, 3);
      expect(item.remainingQuantity, 3);
      expect(item.isFullyReturned, false);
    });

    test('Full return marks isFullyReturned as true', () {
      final item = OrderItem(
        productId: 'P001',
        productName: 'Bàn phím cơ',
        quantity: 5,
        price: 1200000,
        warrantyMonths: 24,
        purchaseDate: testDate,
        returnedQuantity: 5,
      );

      expect(item.returnedQuantity, 5);
      expect(item.activeQuantity, 0);
      expect(item.remainingQuantity, 0);
      expect(item.isFullyReturned, true);
    });

    test('copyWith updates returnedQuantity and fields correctly', () {
      final item = OrderItem(
        productId: 'P001',
        productName: 'Bàn phím cơ',
        quantity: 5,
        price: 1200000,
        warrantyMonths: 24,
        purchaseDate: testDate,
      );

      final updated = item.copyWith(
        returnedQuantity: 3,
        price: 1100000,
      );

      expect(updated.productId, 'P001');
      expect(updated.returnedQuantity, 3);
      expect(updated.activeQuantity, 2);
      expect(updated.price, 1100000);
      expect(updated.quantity, 5);
    });
  });
}
