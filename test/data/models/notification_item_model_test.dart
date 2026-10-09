import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/models/notification_item_model.dart';
import 'package:stores/domain/entities/notification_item.dart';
import 'package:stores/domain/entities/notification_type.dart';

void main() {
  final testDate = DateTime.utc(2026, 10, 4, 12, 30, 0);

  group('NotificationItemModel Serialization (toMap)', () {
    test('serializes complete model to clean map with ISO8601 string', () {
      final model = NotificationItemModel(
        id: 'notif_100',
        storeId: 'store_001',
        title: 'Đơn hàng mới HD013259',
        body: 'Đơn hàng trị giá 250.000 đ vừa được tạo thành công',
        type: 'order_created',
        isRead: true,
        createdAt: testDate,
        targetRoute: '/invoices',
        targetId: 'HD013259',
        metadata: {'total': 250000, 'itemsCount': 2},
      );

      final map = model.toMap();

      expect(map['id'], 'notif_100');
      expect(map['storeId'], 'store_001');
      expect(map['title'], 'Đơn hàng mới HD013259');
      expect(map['body'], 'Đơn hàng trị giá 250.000 đ vừa được tạo thành công');
      expect(map['type'], 'order_created');
      expect(map['isRead'], true);
      expect(map['createdAt'], testDate.toIso8601String());
      expect(map['targetRoute'], '/invoices');
      expect(map['targetId'], 'HD013259');
      expect(map['metadata'], {'total': 250000, 'itemsCount': 2});
    });

    test('omits optional null fields from map to conserve RTDB bandwidth', () {
      final model = NotificationItemModel(
        id: 'notif_101',
        storeId: 'store_001',
        title: 'Cảnh báo',
        body: 'Nội dung thông báo',
        type: 'inventory_imported',
        isRead: false,
        createdAt: testDate,
        targetRoute: null,
        targetId: null,
        metadata: null,
      );

      final map = model.toMap();

      expect(map.containsKey('targetRoute'), isFalse);
      expect(map.containsKey('targetId'), isFalse);
      expect(map.containsKey('metadata'), isFalse);
      expect(map['isRead'], false);
    });
  });

  group('NotificationItemModel Deserialization (fromMap)', () {
    test('deserializes complete map correctly', () {
      final rawMap = {
        'id': 'notif_200',
        'storeId': 'store_002',
        'title': 'Phiếu nhập kho',
        'body': 'Đã hoàn tất phiếu nhập NK1728045600',
        'type': 'inventory_imported',
        'isRead': false,
        'createdAt': testDate.toIso8601String(),
        'targetRoute': '/stock-in',
        'targetId': 'NK1728045600',
        'metadata': {'importCode': 'NK1728045600', 'totalCost': 15000000},
      };

      final model = NotificationItemModel.fromMap(rawMap);

      expect(model.id, 'notif_200');
      expect(model.storeId, 'store_002');
      expect(model.title, 'Phiếu nhập kho');
      expect(model.body, 'Đã hoàn tất phiếu nhập NK1728045600');
      expect(model.type, 'inventory_imported');
      expect(model.isRead, false);
      expect(model.createdAt, testDate);
      expect(model.targetRoute, '/stock-in');
      expect(model.targetId, 'NK1728045600');
      expect(model.metadata?['totalCost'], 15000000);
      expect(model.category, NotificationCategory.inventory);
    });

    test('resolves RTDB snapshot key from optional positional parameter [id]', () {
      final mapWithoutId = {
        'storeId': 'store_001',
        'title': 'Khách hàng mới',
        'body': 'Tạo khách hàng KH001',
        'type': 'customer_created',
        'createdAt': testDate.toIso8601String(),
      };

      // Scenario A: id parameter provided (e.g. DataSnapshot.key)
      final modelWithKey =
          NotificationItemModel.fromMap(mapWithoutId, '-PushKey999');
      expect(modelWithKey.id, '-PushKey999');

      // Scenario B: id in map overrides empty key
      final mapWithId = {'id': 'internal_id', ...mapWithoutId};
      final modelWithBoth =
          NotificationItemModel.fromMap(mapWithId, '-ExplicitKey');
      expect(modelWithBoth.id, '-ExplicitKey');

      // Scenario C: no external key provided
      final modelWithInternal = NotificationItemModel.fromMap(mapWithId);
      expect(modelWithInternal.id, 'internal_id');
    });

    test('handles empty map and null fields gracefully with safe fallbacks', () {
      final model = NotificationItemModel.fromMap({});

      expect(model.id, '');
      expect(model.storeId, '');
      expect(model.title, '');
      expect(model.body, '');
      expect(model.type, 'order_created');
      expect(model.isRead, false);
      expect(model.createdAt, isA<DateTime>());
      expect(model.targetRoute, isNull);
      expect(model.targetId, isNull);
      expect(model.metadata, isNull);
    });

    test('falls back to message or content keys for body if body is missing', () {
      final map1 = {'message': 'Message text'};
      final model1 = NotificationItemModel.fromMap(map1);
      expect(model1.body, 'Message text');

      final map2 = {'content': 'Content text'};
      final model2 = NotificationItemModel.fromMap(map2);
      expect(model2.body, 'Content text');
    });
  });

  group('String Boolean & Type Conversion Defense', () {
    test('parses various string and number representations of isRead correctly', () {
      expect(
          NotificationItemModel.fromMap({'isRead': true}).isRead, isTrue);
      expect(
          NotificationItemModel.fromMap({'isRead': 'true'}).isRead, isTrue);
      expect(
          NotificationItemModel.fromMap({'isRead': 'True'}).isRead, isTrue);
      expect(
          NotificationItemModel.fromMap({'isRead': 'TRUE'}).isRead, isTrue);
      expect(
          NotificationItemModel.fromMap({'isRead': '1'}).isRead, isTrue);
      expect(
          NotificationItemModel.fromMap({'isRead': 1}).isRead, isTrue);
      expect(
          NotificationItemModel.fromMap({'isRead': 'yes'}).isRead, isTrue);

      expect(
          NotificationItemModel.fromMap({'isRead': false}).isRead, isFalse);
      expect(
          NotificationItemModel.fromMap({'isRead': 'false'}).isRead, isFalse);
      expect(
          NotificationItemModel.fromMap({'isRead': 'False'}).isRead, isFalse);
      expect(
          NotificationItemModel.fromMap({'isRead': '0'}).isRead, isFalse);
      expect(
          NotificationItemModel.fromMap({'isRead': 0}).isRead, isFalse);
      expect(
          NotificationItemModel.fromMap({'isRead': null}).isRead, isFalse);
      expect(
          NotificationItemModel.fromMap({'isRead': 'invalid'}).isRead, isFalse);

      // Alternate key 'read'
      expect(
          NotificationItemModel.fromMap({'read': true}).isRead, isTrue);
      expect(
          NotificationItemModel.fromMap({'read': 'true'}).isRead, isTrue);
    });
  });

  group('Robust Date Parsing & Fallbacks', () {
    test('parses ISO8601 strings accurately', () {
      final model = NotificationItemModel.fromMap({
        'createdAt': '2026-10-04T12:30:00.000Z',
      });
      expect(model.createdAt, DateTime.utc(2026, 10, 4, 12, 30, 0));
    });

    test('parses millisecond timestamps in integer and string formats', () {
      const epochMillis = 1728043200000;
      final expectedDate =
          DateTime.fromMillisecondsSinceEpoch(epochMillis);

      final modelInt =
          NotificationItemModel.fromMap({'createdAt': epochMillis});
      expect(modelInt.createdAt, expectedDate);

      final modelStr =
          NotificationItemModel.fromMap({'createdAt': '$epochMillis'});
      expect(modelStr.createdAt, expectedDate);
    });

    test('parses second timestamps (10-digit epoch) correctly', () {
      const epochSeconds = 1728043200;
      final expectedDate =
          DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);

      final model =
          NotificationItemModel.fromMap({'createdAt': epochSeconds});
      expect(model.createdAt, expectedDate);
    });

    test('supports alternate timestamp and date keys', () {
      final modelTimestamp = NotificationItemModel.fromMap({
        'timestamp': '2026-10-04T10:00:00.000Z',
      });
      expect(
          modelTimestamp.createdAt, DateTime.utc(2026, 10, 4, 10, 0, 0));

      final modelDate = NotificationItemModel.fromMap({
        'date': '2026-10-04T11:00:00.000Z',
      });
      expect(modelDate.createdAt, DateTime.utc(2026, 10, 4, 11, 0, 0));
    });

    test('falls back safely to DateTime.now() without throwing on invalid date string', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final model = NotificationItemModel.fromMap({
        'createdAt': 'not-a-valid-date-value',
      });
      final after = DateTime.now().add(const Duration(seconds: 1));

      expect(model.createdAt.isAfter(before), isTrue);
      expect(model.createdAt.isBefore(after), isTrue);
    });
  });

  group('Dynamic Map Types & Nested Metadata Sanitization', () {
    test('recursively converts Map<dynamic, dynamic> with integer keys to Map<String, dynamic>', () {
      final dynamicRawMap = <dynamic, dynamic>{
        'id': 'notif_300',
        'metadata': <dynamic, dynamic>{
          101: 'order_ref_num',
          'nested': <dynamic, dynamic>{
            'keyA': 'valA',
            99: 100,
          },
          'list': [
            <dynamic, dynamic>{'subKey': 'subVal'},
            'simpleString',
          ],
        },
      };

      final model = NotificationItemModel.fromMap(dynamicRawMap);

      expect(model.metadata, isA<Map<String, dynamic>>());
      expect(model.metadata?['101'], 'order_ref_num');
      expect(model.metadata?['nested'], isA<Map<String, dynamic>>());
      expect(model.metadata?['nested']['keyA'], 'valA');
      expect(model.metadata?['nested']['99'], 100);
      expect(model.metadata?['list'], isA<List>());
      expect((model.metadata?['list'] as List)[0],
          isA<Map<String, dynamic>>());
      expect((model.metadata?['list'] as List)[0]['subKey'], 'subVal');
    });

    test('ignores non-map metadata values safely without throwing', () {
      final model = NotificationItemModel.fromMap({
        'metadata': 'plain_corrupted_string',
      });
      expect(model.metadata, isNull);
    });
  });

  group('Domain Conversion & Round-Trip (toDomain / fromDomain)', () {
    test('preserves exact domain entity state in bidirectional conversion', () {
      final domainItem = NotificationItem(
        id: 'notif_400',
        storeId: 'store_001',
        title: 'Thu nợ khách hàng KH0012',
        body: 'Đã thu 1.000.000 đ tiền nợ',
        type: NotificationType.customerDebtPaid,
        isRead: true,
        createdAt: testDate,
        targetRoute: '/customers/debt',
        targetId: 'KH0012',
        metadata: {'paidAmount': 1000000},
      );

      final model = NotificationItemModel.fromDomain(domainItem);
      expect(model.id, domainItem.id);
      expect(model.storeId, domainItem.storeId);
      expect(model.type, 'customer_debt_paid');
      expect(model.isRead, domainItem.isRead);
      expect(model.category, NotificationCategory.customers);

      final reconstructedDomain = model.toDomain();
      expect(reconstructedDomain, equals(domainItem));
      expect(reconstructedDomain.category, NotificationCategory.customers);
    });

    test('round-trip model -> toMap -> fromMap maintains exact equality', () {
      final initialModel = NotificationItemModel(
        id: 'notif_500',
        storeId: 'store_002',
        title: 'Hủy đơn HD099',
        body: 'Đơn hàng HD099 đã bị hủy',
        type: 'order_cancelled',
        isRead: false,
        createdAt: testDate,
        targetRoute: '/orders',
        targetId: 'HD099',
        metadata: {'reason': 'Khách đổi ý'},
      );

      final map = initialModel.toMap();
      final roundTripModel = NotificationItemModel.fromMap(map);

      expect(roundTripModel, equals(initialModel));
      expect(roundTripModel.hashCode, equals(initialModel.hashCode));
    });
  });

  group('Model Utilities (copyWith, operator ==, hashCode)', () {
    test('copyWith updates specified fields and preserves originals', () {
      final original = NotificationItemModel(
        id: 'notif_600',
        storeId: 'store_001',
        title: 'Title',
        body: 'Body',
        type: 'order_created',
        isRead: false,
        createdAt: testDate,
      );

      final updated = original.copyWith(
        isRead: true,
        title: 'Updated Title',
        targetId: 'TARGET_1',
      );

      expect(updated.isRead, true);
      expect(updated.title, 'Updated Title');
      expect(updated.targetId, 'TARGET_1');
      expect(updated.id, original.id);
      expect(updated.storeId, original.storeId);
      expect(updated.body, original.body);
    });

    test('value equality handles nested metadata maps accurately', () {
      final a = NotificationItemModel(
        id: 'notif_700',
        storeId: 'store_001',
        title: 'A',
        body: 'B',
        type: 'order_created',
        createdAt: testDate,
        metadata: {'key': 123},
      );

      final b = NotificationItemModel(
        id: 'notif_700',
        storeId: 'store_001',
        title: 'A',
        body: 'B',
        type: 'order_created',
        createdAt: testDate,
        metadata: {'key': 123},
      );

      final c = a.copyWith(title: 'Different Title');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
