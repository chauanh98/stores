import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/notifications/notification_visibility.dart';
import 'package:stores/domain/entities/notification_item.dart';
import 'package:stores/domain/entities/notification_type.dart';
import 'package:stores/domain/entities/user_account.dart';

NotificationItem n(NotificationType t, String body, {String? target}) =>
    NotificationItem(
      id: '${t.value}$body',
      storeId: 's',
      title: 'T',
      body: body,
      type: t,
      createdAt: DateTime(2026),
      targetId: target,
    );

void main() {
  const staff =
      UserAccount(username: 's', role: 'nhanvien', storeId: 'store_001');
  const admin = UserAccount(username: 'a', role: 'admin', storeId: 'store_001');

  test('staff: amounts stripped, customer notifications hidden', () {
    final out = notificationsForViewer([
      n(NotificationType.inventoryImported,
          '1.250.000đ - NCC: Abc (Lập bởi: X)'),
      n(NotificationType.customerDebtAdded, 'Ghi nợ 500.000đ - Khách: K'),
    ], staff);
    expect(out.length, 1);
    expect(out.first.body, 'NCC: Abc (Lập bởi: X)');
  });

  test('admin sees everything unchanged; null sees nothing', () {
    final items = [n(NotificationType.orderCreated, '1.000đ - Khách: K')];
    expect(notificationsForViewer(items, admin), items);
    expect(notificationsForViewer(items, null), isEmpty);
  });

  test('cross-store duplicates collapse', () {
    final a = n(NotificationType.stockTransfer, 'same', target: 'trf1');
    final b = a.copyWith(id: 'other', storeId: 's2');
    expect(dedupeCrossStoreNotifications([a, b]).length, 1);
  });
}
