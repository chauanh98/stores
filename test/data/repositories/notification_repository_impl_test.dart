import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/notification_remote_data_source.dart';
import 'package:stores/data/repositories/notification_repository_impl.dart';
import 'package:stores/domain/entities/notification_item.dart';
import 'package:stores/domain/entities/notification_type.dart';

class _FakeNotificationRemoteDataSource implements NotificationRemoteDataSource {
  final Map<String, Map<String, dynamic>> _storage = {};
  final StreamController<List<Map<String, dynamic>>> _controller =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  void emitAll() {
    _controller.add(
        _storage.values.map((e) => Map<String, dynamic>.from(e)).toList());
  }

  @override
  Stream<List<Map<String, dynamic>>> watchNotifications(
    String storeId, {
    int limit = 50,
  }) {
    Future.microtask(emitAll);
    return _controller.stream;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchNotifications(
    String storeId, {
    int limit = 50,
  }) async {
    return _storage.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Future<void> addNotification(
    String storeId,
    Map<String, dynamic> data,
  ) async {
    final id = data['id']?.toString() ??
        'notif_${DateTime.now().millisecondsSinceEpoch}';
    _storage[id] = Map<String, dynamic>.from(data)..['id'] = id;
    emitAll();
  }

  @override
  Future<void> markAsRead(String storeId, String id) async {
    if (_storage.containsKey(id)) {
      _storage[id]!['isRead'] = true;
      emitAll();
    }
  }

  @override
  Future<void> markAllAsRead(String storeId) async {
    for (final item in _storage.values) {
      if (item['isRead'] == false) {
        item['isRead'] = true;
      }
    }
    emitAll();
  }

  @override
  Future<void> deleteNotification(String storeId, String id) async {
    _storage.remove(id);
    emitAll();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationRepositoryImpl Tests', () {
    late _FakeNotificationRemoteDataSource fakeDs;
    late NotificationRepositoryImpl repository;
    const storeId = 'store_001';

    setUp(() {
      fakeDs = _FakeNotificationRemoteDataSource();
      repository = NotificationRepositoryImpl(fakeDs);
    });

    test('addNotification saves and watchNotifications receives mapped entities sorted newest first', () async {
      final t1 = DateTime(2026, 10, 4, 10, 0);
      final t2 = DateTime(2026, 10, 4, 12, 0);
      final t3 = DateTime(2026, 10, 4, 11, 0);

      // Add out of order: older, newest, middle
      await repository.addNotification(NotificationItem(
        id: 'n1',
        storeId: storeId,
        title: 'Đơn hàng 1',
        body: 'Tạo lúc 10:00',
        type: NotificationType.orderCreated,
        createdAt: t1,
      ));
      await repository.addNotification(NotificationItem(
        id: 'n2',
        storeId: storeId,
        title: 'Đơn hàng 2',
        body: 'Tạo lúc 12:00',
        type: NotificationType.orderUpdated,
        createdAt: t2,
      ));
      await repository.addNotification(NotificationItem(
        id: 'n3',
        storeId: storeId,
        title: 'Đơn hàng 3',
        body: 'Tạo lúc 11:00',
        type: NotificationType.customerDebtAdded,
        createdAt: t3,
      ));

      final items = await repository.watchNotifications(storeId).first;
      expect(items.length, equals(3));

      // Must be sorted newest first: n2 (12:00) -> n3 (11:00) -> n1 (10:00)
      expect(items[0].id, equals('n2'));
      expect(items[0].type, equals(NotificationType.orderUpdated));
      expect(items[1].id, equals('n3'));
      expect(items[1].type, equals(NotificationType.customerDebtAdded));
      expect(items[2].id, equals('n1'));
      expect(items[2].type, equals(NotificationType.orderCreated));
    });

    test('markAsRead updates target notification isRead status', () async {
      await repository.addNotification(NotificationItem(
        id: 'target_notif',
        storeId: storeId,
        title: 'Nhập kho',
        body: 'Phiếu nhập mới',
        type: NotificationType.inventoryImported,
        isRead: false,
        createdAt: DateTime.now(),
      ));

      var items = await repository.watchNotifications(storeId).first;
      expect(items.first.isRead, isFalse);

      await repository.markAsRead(storeId: storeId, id: 'target_notif');

      items = await repository.watchNotifications(storeId).first;
      expect(items.first.isRead, isTrue);
    });

    test('markAllAsRead marks all unread notifications as read', () async {
      await repository.addNotification(NotificationItem(
        id: 'n1',
        storeId: storeId,
        title: 'Đơn 1',
        body: 'Nội dung',
        type: NotificationType.orderCreated,
        isRead: false,
        createdAt: DateTime.now(),
      ));
      await repository.addNotification(NotificationItem(
        id: 'n2',
        storeId: storeId,
        title: 'Đơn 2',
        body: 'Nội dung',
        type: NotificationType.orderCreated,
        isRead: false,
        createdAt: DateTime.now(),
      ));

      await repository.markAllAsRead(storeId);

      final items = await repository.watchNotifications(storeId).first;
      expect(items.every((item) => item.isRead), isTrue);
    });

    test('deleteNotification removes notification from stream', () async {
      await repository.addNotification(NotificationItem(
        id: 'del_me',
        storeId: storeId,
        title: 'Xóa tôi',
        body: 'Nội dung',
        type: NotificationType.orderCancelled,
        createdAt: DateTime.now(),
      ));

      var items = await repository.watchNotifications(storeId).first;
      expect(items.length, equals(1));

      await repository.deleteNotification(storeId: storeId, id: 'del_me');

      items = await repository.watchNotifications(storeId).first;
      expect(items, isEmpty);
    });
  });
}
