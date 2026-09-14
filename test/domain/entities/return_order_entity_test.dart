import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/return_order.dart';

void main() {
  group('ReturnOrder and ReturnOrderItem Entity Tests', () {
    final testDate = DateTime(2026, 8, 17, 14, 0);

    test('ReturnOrderItem creation, calculation and serialization', () {
      final comboComponents = [
        const ComboComponent(
          productId: 'COMP1',
          productCode: 'C1',
          productName: 'Chuột không dây',
          quantity: 1,
        ),
        const ComboComponent(
          productId: 'COMP2',
          productCode: 'C2',
          productName: 'Lót chuột',
          quantity: 2,
        ),
      ];

      final item = ReturnOrderItem(
        productId: 'COMBO1',
        productName: 'Combo Gaming',
        price: 1500000,
        quantity: 2,
        unit: 'Bộ',
        isCombo: true,
        comboComponents: comboComponents,
      );

      expect(item.totalRefund, 3000000);
      expect(item.total, 3000000);
      expect(item.isCombo, true);
      expect(item.comboComponents.length, 2);

      final map = item.toMap();
      expect(map['productId'], 'COMBO1');
      expect(map['total'], 3000000);
      expect(map['isCombo'], true);

      final fromMapItem = ReturnOrderItem.fromMap(map);
      expect(fromMapItem.productId, 'COMBO1');
      expect(fromMapItem.totalRefund, 3000000);
      expect(fromMapItem.isCombo, true);
      expect(fromMapItem.comboComponents.length, 2);
    });

    test('ReturnOrder creation, copyWith and serialization', () {
      final returnItems = [
        const ReturnOrderItem(
          productId: 'P1',
          productName: 'Tai nghe Bluetooth',
          price: 500000,
          quantity: 2,
        ),
      ];

      final returnOrder = ReturnOrder(
        id: 'TH_001',
        orderId: 'HD000001',
        customerId: 'CUST1',
        storeId: 'store_001',
        createdAt: testDate,
        items: returnItems,
        totalReturnAmount: 1000000,
        debtDeducted: 400000,
        cashRefunded: 600000,
        reason: 'Khách không ưng màu',
        createdBy: 'admin1',
        createdByName: 'Admin Khanh',
        refundPaymentMethod: 'cash',
      );

      expect(returnOrder.totalRefund, 1000000);
      expect(returnOrder.debtDeducted, 400000);
      expect(returnOrder.cashRefunded, 600000);
      expect(returnOrder.refundPaymentMethod, 'cash');

      final map = returnOrder.toMap();
      expect(map['id'], 'TH_001');
      expect(map['orderId'], 'HD000001');
      expect(map['totalReturnAmount'], 1000000);
      expect(map['debtDeducted'], 400000);
      expect(map['cashRefunded'], 600000);

      final restored = ReturnOrder.fromMap(map);
      expect(restored.id, 'TH_001');
      expect(restored.orderId, 'HD000001');
      expect(restored.totalReturnAmount, 1000000);
      expect(restored.debtDeducted, 400000);
      expect(restored.cashRefunded, 600000);
      expect(restored.items.length, 1);
      expect(restored.items.first.productName, 'Tai nghe Bluetooth');

      final updated = returnOrder.copyWith(
        cashRefunded: 500000,
        debtDeducted: 500000,
        refundPaymentMethod: 'transfer',
      );
      expect(updated.cashRefunded, 500000);
      expect(updated.debtDeducted, 500000);
      expect(updated.refundPaymentMethod, 'transfer');
    });
  });
}
