import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/notification_item.dart';
import 'package:stores/domain/entities/notification_type.dart';

void main() {
  group('NotificationCategory & NotificationType Enums', () {
    test('NotificationCategory parsing and values', () {
      expect(NotificationCategory.fromString('orders'), NotificationCategory.orders);
      expect(NotificationCategory.fromString('inventory'), NotificationCategory.inventory);
      expect(NotificationCategory.fromString('customers'), NotificationCategory.customers);
      expect(NotificationCategory.fromString('system'), NotificationCategory.system);
      expect(NotificationCategory.fromString('unknown_val'), NotificationCategory.system);
      expect(NotificationCategory.fromString(null), NotificationCategory.system);
      expect(NotificationCategory.fromString('   ORDERS   '), NotificationCategory.orders);
    });

    test('NotificationType parsing and category mapping', () {
      expect(NotificationType.fromString('order_created'), NotificationType.orderCreated);
      expect(NotificationType.fromString('orderCreated'), NotificationType.orderCreated);
      expect(NotificationType.fromString('order_updated'), NotificationType.orderUpdated);
      expect(NotificationType.fromString('order_cancelled'), NotificationType.orderCancelled);
      expect(NotificationType.fromString('order_return'), NotificationType.orderReturn);
      expect(NotificationType.fromString('inventory_imported'), NotificationType.inventoryImported);
      expect(NotificationType.fromString('customer_created'), NotificationType.customerCreated);
      expect(NotificationType.fromString('customer_debt_added'), NotificationType.customerDebtAdded);
      expect(NotificationType.fromString('customer_debt_paid'), NotificationType.customerDebtPaid);

      expect(NotificationType.orderCreated.category, NotificationCategory.orders);
      expect(NotificationType.orderUpdated.category, NotificationCategory.orders);
      expect(NotificationType.orderCancelled.category, NotificationCategory.orders);
      expect(NotificationType.orderReturn.category, NotificationCategory.orders);
      expect(NotificationType.inventoryImported.category, NotificationCategory.inventory);
      expect(NotificationType.customerCreated.category, NotificationCategory.customers);
      expect(NotificationType.customerDebtAdded.category, NotificationCategory.customers);
      expect(NotificationType.customerDebtPaid.category, NotificationCategory.customers);
    });

    test('NotificationType fallback matching for loose keywords', () {
      expect(NotificationType.fromString('order-cancelled'), NotificationType.orderCancelled);
      expect(NotificationType.fromString('return_goods'), NotificationType.orderReturn);
      expect(NotificationType.fromString('edit_order'), NotificationType.orderUpdated);
      expect(NotificationType.fromString('stock_import'), NotificationType.inventoryImported);
      expect(NotificationType.fromString('collect_money'), NotificationType.customerDebtPaid);
      expect(NotificationType.fromString('new_debt'), NotificationType.customerDebtAdded);
      expect(NotificationType.fromString('unknown_gibberish'), NotificationType.orderCreated);
      expect(NotificationType.fromString(null), NotificationType.orderCreated);
    });
  });

  group('NotificationItem Entity', () {
    final now = DateTime(2026, 10, 4, 12, 0);
    final item = NotificationItem(
      id: 'notif_1',
      storeId: 'store_001',
      title: 'Đơn hàng mới HD013259',
      body: 'Đơn hàng trị giá 250.000 đ vừa được tạo',
      type: NotificationType.orderCreated,
      createdAt: now,
      targetRoute: '/orders/detail',
      targetId: 'HD013259',
      metadata: {'amount': 250000},
    );

    test('default properties and category getter', () {
      expect(item.id, 'notif_1');
      expect(item.isRead, false);
      expect(item.category, NotificationCategory.orders);
      expect(item.targetId, 'HD013259');
      expect(item.targetRoute, '/orders/detail');
      expect(item.metadata?['amount'], 250000);
      expect(item.toString(), contains('notif_1'));
    });

    test('copyWith updates fields correctly', () {
      final updated = item.copyWith(
        isRead: true,
        targetId: 'HD013260',
        metadata: {'amount': 300000},
      );
      expect(updated.isRead, true);
      expect(updated.targetId, 'HD013260');
      expect(updated.id, 'notif_1');
      expect(updated.title, item.title);
      expect(updated.metadata?['amount'], 300000);

      // copyWith preserving metadata
      final updatedPreserve = item.copyWith(title: 'Tiêu đề mới');
      expect(updatedPreserve.title, 'Tiêu đề mới');
      expect(updatedPreserve.metadata?['amount'], 250000);
    });

    test('equality and hashCode work properly', () {
      final item2 = NotificationItem(
        id: 'notif_1',
        storeId: 'store_001',
        title: 'Đơn hàng mới HD013259',
        body: 'Đơn hàng trị giá 250.000 đ vừa được tạo',
        type: NotificationType.orderCreated,
        createdAt: now,
        targetRoute: '/orders/detail',
        targetId: 'HD013259',
        metadata: {'amount': 250000},
      );

      final itemDifferent = item.copyWith(id: 'notif_2');

      expect(item, equals(item2));
      expect(item.hashCode, equals(item2.hashCode));
      expect(item, isNot(equals(itemDifferent)));
    });

    test('metadata map equality handles null and identical', () {
      final itemNoMeta1 = NotificationItem(
        id: 'n1',
        storeId: 's1',
        title: 'T',
        body: 'B',
        type: NotificationType.orderCreated,
        createdAt: now,
      );
      final itemNoMeta2 = NotificationItem(
        id: 'n1',
        storeId: 's1',
        title: 'T',
        body: 'B',
        type: NotificationType.orderCreated,
        createdAt: now,
      );
      expect(itemNoMeta1, equals(itemNoMeta2));
    });
  });
}
