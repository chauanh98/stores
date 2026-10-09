import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/notification_remote_data_source.dart';

import '../../support/firebase_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationRemoteDataSource Tests', () {
    late MockFirebaseDatabase mockDb;
    late NotificationRemoteDataSource dataSource;
    const storeId = 'store_test_01';
    const notifPath = 'stores/$storeId/notifications';

    setUp(() {
      mockDb = MockFirebaseDatabase();
      dataSource = NotificationRemoteDataSource(mockDb);
    });

    test('addNotification with ID writes directly to child node', () async {
      final parentRef = mockDb.getOrCreateRef(notifPath);
      final data = {
        'id': 'notif_100',
        'title': 'Đơn hàng mới',
        'body': 'Khách thanh toán 500k',
        'createdAt': '2026-10-04T12:00:00.000Z',
        'isRead': false,
        'type': 'order_created',
      };

      await dataSource.addNotification(storeId, data);

      expect(mockDb.recorder.hasCalled('set', path: '$notifPath/notif_100'), isTrue);
      expect(parentRef.storeData['notif_100'], isNotNull);
      final savedData = parentRef.storeData['notif_100'] as Map;
      expect(savedData['id'], equals('notif_100'));
      expect(savedData['title'], equals('Đơn hàng mới'));
    });

    test('addNotification without ID generates push key and stores data', () async {
      final parentRef = mockDb.getOrCreateRef(notifPath);
      final data = {
        'title': 'Phiếu nhập mới',
        'body': 'Hoàn tất nhập hàng',
        'createdAt': '2026-10-04T12:00:00.000Z',
        'isRead': false,
        'type': 'inventory_imported',
      };

      await dataSource.addNotification(storeId, data);

      // Verify a child was added to parent storeData
      expect(parentRef.storeData.isNotEmpty, isTrue);
      final generatedKey = parentRef.storeData.keys.first;
      expect(generatedKey.startsWith('-M'), isTrue);
      final savedData = parentRef.storeData[generatedKey] as Map;
      expect(savedData['title'], equals('Phiếu nhập mới'));
      expect(savedData['id'], equals(generatedKey));
    });

    test('markAsRead updates child isRead to true', () async {
      final parentRef = mockDb.getOrCreateRef(notifPath);
      parentRef.storeData['notif_200'] = {
        'id': 'notif_200',
        'title': 'Test',
        'isRead': false,
      };

      await dataSource.markAsRead(storeId, 'notif_200');

      expect(mockDb.recorder.hasCalled('update', path: '$notifPath/notif_200'), isTrue);
      final childData = parentRef.storeData['notif_200'] as Map;
      expect(childData['isRead'], isTrue);
    });

    test('deleteNotification removes child node', () async {
      final parentRef = mockDb.getOrCreateRef(notifPath);
      parentRef.storeData['notif_300'] = {
        'id': 'notif_300',
        'title': 'To be deleted',
      };

      await dataSource.deleteNotification(storeId, 'notif_300');

      expect(mockDb.recorder.hasCalled('remove', path: '$notifPath/notif_300'), isTrue);
      expect(parentRef.storeData.containsKey('notif_300'), isFalse);
    });

    test('markAllAsRead queries unread records and executes batch update', () async {
      final parentRef = mockDb.getOrCreateRef(notifPath);
      parentRef.storeData['n1'] = {'id': 'n1', 'isRead': false, 'title': 'T1'};
      parentRef.storeData['n2'] = {'id': 'n2', 'isRead': false, 'title': 'T2'};
      parentRef.storeData['n3'] = {'id': 'n3', 'isRead': true, 'title': 'T3'};

      await dataSource.markAllAsRead(storeId);

      // Verify update was called on parent with multi-path updates
      expect(mockDb.recorder.hasCalled('update', path: notifPath), isTrue);
      final updateCalls = mockDb.recorder.callsFor('update', path: notifPath);
      expect(updateCalls.isNotEmpty, isTrue);
      final updatePayload = updateCalls.first.value as Map<String, dynamic>;
      expect(updatePayload['n1/isRead'], isTrue);
      expect(updatePayload['n2/isRead'], isTrue);
      expect(updatePayload.containsKey('n3/isRead'), isFalse);
    });

    test('fetchNotifications retrieves and parses snapshot', () async {
      final parentRef = mockDb.getOrCreateRef(notifPath);
      parentRef.storeData['n10'] = {
        'id': 'n10',
        'title': 'T10',
        'body': 'B10',
        'createdAt': '2026-10-04T12:00:00.000Z',
        'isRead': false,
        'type': 'order_created',
      };

      final results = await dataSource.fetchNotifications(storeId);
      expect(results.length, equals(1));
      expect(results.first['id'], equals('n10'));
      expect(results.first['title'], equals('T10'));
    });

    test('watchNotifications debounces and emits stream data', () async {
      final parentRef = mockDb.getOrCreateRef(notifPath);
      parentRef.storeData['n20'] = {
        'id': 'n20',
        'title': 'T20',
        'body': 'B20',
        'createdAt': '2026-10-04T12:00:00.000Z',
        'isRead': false,
        'type': 'order_created',
      };

      final stream = dataSource.watchNotifications(storeId, limit: 10);
      final events = <List<Map<String, dynamic>>>[];
      final sub = stream.listen(events.add);

      // Trigger value event on parentRef
      parentRef.emitValue(parentRef.storeData);

      // Wait for debounce (250ms)
      await Future.delayed(const Duration(milliseconds: 300));

      expect(events.isNotEmpty, isTrue);
      expect(events.first.length, equals(1));
      expect(events.first.first['id'], equals('n20'));

      await sub.cancel();
    });
  });
}
