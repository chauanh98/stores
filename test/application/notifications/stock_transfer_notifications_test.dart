import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notification_visibility.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/stock_transfer.dart';
import 'package:stores/domain/entities/user_account.dart';

class _Repo implements NotificationRepository {
  final List<NotificationItem> added = [];
  @override
  Future<void> addNotification(NotificationItem n) async => added.add(n);
  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {}
  @override
  Future<void> markAllAsRead(String storeId) async {}
  @override
  Future<void> markAsRead(
      {required String storeId, required String id}) async {}
  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
          {int limit = 50}) =>
      Stream.value(added);
}

StockTransfer _transfer({
  StockTransferStatus status = StockTransferStatus.inTransit,
  int received = 0,
  String targetId = 'store_002',
}) =>
    StockTransfer(
      id: 'T1',
      code: 'TRF000009',
      status: status,
      sourceStoreId: 'store_001',
      sourceStoreName: 'Chi nhánh Đông Thắng',
      targetStoreId: targetId,
      targetStoreName: 'Chi nhánh Thới Bình',
      createdAt: DateTime(2026, 1, 1),
      items: [
        StockTransferItem(
            productId: 'p',
            name: 'X',
            code: 'x',
            unitPrice: 1000000,
            quantity: 2,
            receivedQuantity: received),
      ],
    );

void main() {
  late _Repo repo;
  late NotificationDispatcher d;
  setUp(() {
    repo = _Repo();
    d = NotificationDispatcher(repo);
  });

  group('notifyStockTransfer', () {
    test('created: one notification per store, same content', () async {
      await d.notifyStockTransfer(
          transfer: _transfer(), received: false, actorName: 'Khánh Đăng');
      expect(repo.added.length, 2);
      expect(repo.added.map((n) => n.storeId), ['store_001', 'store_002']);
      expect(repo.added[0].title, 'Chuyển hàng #TRF000009');
      expect(repo.added[0].body, contains('Khánh Đăng'));
      expect(repo.added[0].body, contains('1 mặt hàng'));
      expect(repo.added[0].targetId, 'T1');
      expect(repo.added[0].metadata?['transferCode'], 'TRF000009');
      expect(repo.added[0].id, isNot(repo.added[1].id));
    });

    test('received: shows received/sent quantity for both stores', () async {
      await d.notifyStockTransfer(
          transfer:
              _transfer(status: StockTransferStatus.received, received: 1),
          received: true,
          actorName: 'Chị Hồng');
      expect(repo.added.length, 2);
      expect(repo.added[0].title, 'Nhận chuyển hàng #TRF000009');
      expect(repo.added[0].body, contains('1/2'));
    });

    test('no price is ever put in the body', () async {
      await d.notifyStockTransfer(transfer: _transfer(), received: false);
      expect(repo.added.any((n) => RegExp(r'\d[\d.,]*\s?đ').hasMatch(n.body)),
          false);
    });

    test('blank actor falls back; empty target store is skipped', () async {
      await d.notifyStockTransfer(
          transfer: _transfer(targetId: ''), received: false, actorName: '  ');
      expect(repo.added.length, 1);
      expect(repo.added.first.body, startsWith('Nhân viên'));
    });

    test('repository failure does not throw', () async {
      final failing = NotificationDispatcher(_ThrowingRepo());
      await failing.notifyStockTransfer(transfer: _transfer(), received: false);
    });

    test('admin dedupe collapses the two copies, staff view keeps them clean',
        () async {
      await d.notifyStockTransfer(transfer: _transfer(), received: false);
      expect(dedupeCrossStoreNotifications(repo.added).length, 1);
      const staff =
          UserAccount(username: 's', role: 'nhanvien', storeId: 'store_002');
      final visible = notificationsForViewer(repo.added, staff);
      expect(visible.length, 2,
          reason: 'inventory category is visible to staff');
    });
  });

  group('notifyStockInCancelled', () {
    final receipt = StockInReceipt(
      id: 'R1',
      importCode: 'NK001',
      date: DateTime(2026, 1, 1),
      totalAmount: 5000000,
      items: const [],
    );

    test('writes cancel notification with reason and actor', () async {
      await d.notifyStockInCancelled(
          storeId: 'store_001',
          receipt: receipt,
          reason: 'Nhập nhầm',
          cancelledBy: 'admin1');
      expect(repo.added.length, 1);
      final n = repo.added.first;
      expect(n.title, 'Hủy phiếu nhập kho #NK001');
      expect(n.body, contains('Nhập nhầm'));
      expect(n.body, contains('admin1'));
      expect(n.type, NotificationType.inventoryImported);
      expect(n.targetRoute, 'stock_in_detail');
      expect(n.targetId, 'NK001');
    });

    test('blank reason falls back, repo failure is swallowed', () async {
      await d.notifyStockInCancelled(
          storeId: 's', receipt: receipt, reason: ' ', cancelledBy: 'x');
      expect(repo.added.first.body, contains('Không có'));
      await NotificationDispatcher(_ThrowingRepo()).notifyStockInCancelled(
          storeId: 's', receipt: receipt, reason: 'r', cancelledBy: 'x');
    });

    test('staff sees the cancel notice without amounts', () async {
      await d.notifyStockInCancelled(
          storeId: 's', receipt: receipt, reason: 'r', cancelledBy: 'x');
      const staff =
          UserAccount(username: 's', role: 'nhanvien', storeId: 'store_001');
      final v = notificationsForViewer(repo.added, staff);
      expect(v.length, 1);
      expect(v.first.title, contains('NK001'));
    });
  });

  group('stripNotificationAmounts / viewer rules', () {
    test('strips prices from every dispatcher body format', () {
      expect(stripNotificationAmounts('1.250.000đ - Khách: A (Tạo bởi: B)'),
          'Khách: A (Tạo bởi: B)');
      expect(
          stripNotificationAmounts('Mã mới #2: 500.000đ - Khách: A (Bởi: B)'),
          'Mã mới #2: Khách: A (Bởi: B)');
      expect(stripNotificationAmounts('Lý do: Hết hàng - Khách: A (Bởi: B)'),
          'Lý do: Hết hàng - Khách: A (Bởi: B)');
    });

    test('supervisor keeps full content', () {
      const sup =
          UserAccount(username: 'g', role: 'supervisor', storeId: 'store_001');
      final n = NotificationItem(
          id: '1',
          storeId: 's',
          title: 't',
          body: '1.000đ - x',
          type: NotificationType.orderCreated,
          createdAt: DateTime(2026));
      expect(notificationsForViewer([n], sup).first.body, '1.000đ - x');
    });

    test('keyword fallback maps *transfer* types', () {
      expect(NotificationType.fromString('stock-transfer'),
          NotificationType.stockTransfer);
      expect(NotificationType.fromString('transfer_created'),
          NotificationType.stockTransfer);
      expect(NotificationType.stockTransfer.category,
          NotificationCategory.inventory);
    });
  });
}

class _ThrowingRepo extends _Repo {
  @override
  Future<void> addNotification(NotificationItem n) async =>
      throw Exception('boom');
}
