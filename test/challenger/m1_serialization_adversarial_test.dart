import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/models/notification_item_model.dart';
import 'package:stores/domain/entities/notification_item.dart';
import 'package:stores/domain/entities/notification_type.dart';

void main() {
  group('M1 Challenger - Adversarial JSON Corrupted Types', () {
    test('handles numeric, boolean, and empty string types for id, storeId, title, body', () {
      final corruptedMap = {
        'id': 999888, // integer id
        'storeId': 1001, // integer storeId
        'title': 12345.67, // double title
        'body': true, // boolean body
        'type': 'order_created',
        'isRead': false,
        'createdAt': '2026-10-04T12:00:00.000Z',
      };

      final model = NotificationItemModel.fromMap(corruptedMap);

      expect(model.id, '999888');
      expect(model.storeId, '1001');
      expect(model.title, '12345.67');
      expect(model.body, 'true');
      expect(model.type, 'order_created');
      expect(model.isRead, isFalse);
    });

    test('handles completely empty map with robust fallbacks', () {
      final model = NotificationItemModel.fromMap({});

      expect(model.id, '');
      expect(model.storeId, '');
      expect(model.title, '');
      expect(model.body, '');
      expect(model.type, 'order_created');
      expect(model.notificationType, NotificationType.orderCreated);
      expect(model.category, NotificationCategory.orders);
      expect(model.isRead, isFalse);
      expect(model.targetRoute, isNull);
      expect(model.targetId, isNull);
      expect(model.metadata, isNull);
      expect(model.createdAt, isA<DateTime>());
    });

    test('handles non-string map keys like int, bool, double without throwing', () {
      final dynamicKeyMap = <dynamic, dynamic>{
        1: 'val1',
        true: 'val2',
        2.5: 'val3',
        'id': 'notif_dyn',
        'title': 'Test Non-String Keys',
        'storeId': 'store_001',
      };

      final model = NotificationItemModel.fromMap(dynamicKeyMap);
      expect(model.id, 'notif_dyn');
      expect(model.title, 'Test Non-String Keys');
      expect(model.storeId, 'store_001');
    });

    test('handles whitespace-only values for string fields by trimming or converting to null', () {
      final whitespaceMap = {
        'id': '   ',
        'storeId': '   ',
        'title': '   ',
        'body': '   ',
        'targetRoute': '   ',
        'targetId': '   ',
      };

      final model = NotificationItemModel.fromMap(whitespaceMap, '   ');

      expect(model.id, '');
      expect(model.storeId, '');
      expect(model.title, '');
      expect(model.body, '');
      expect(model.targetRoute, isNull);
      expect(model.targetId, isNull);
    });

    test('resolves body from fallback keys message and content', () {
      final mapWithMessage = {'message': 'Alert message text'};
      final modelWithMessage = NotificationItemModel.fromMap(mapWithMessage);
      expect(modelWithMessage.body, 'Alert message text');

      final mapWithContent = {'content': 'Alert content text'};
      final modelWithContent = NotificationItemModel.fromMap(mapWithContent);
      expect(modelWithContent.body, 'Alert content text');

      final mapWithBoth = {
        'message': 'Message priority',
        'content': 'Content secondary',
      };
      final modelWithBoth = NotificationItemModel.fromMap(mapWithBoth);
      expect(modelWithBoth.body, 'Message priority');

      final mapWithExplicitBody = {
        'body': 'Direct body',
        'message': 'Message ignored',
        'content': 'Content ignored',
      };
      final modelWithExplicitBody = NotificationItemModel.fromMap(mapWithExplicitBody);
      expect(modelWithExplicitBody.body, 'Direct body');
    });
  });

  group('M1 Challenger - String Booleans and Falsy Variants', () {
    test('truthy variants all evaluate to isRead == true', () {
      final truthyValues = [
        true,
        'true',
        'True',
        'TRUE',
        '  true  ',
        '1',
        1,
        100,
        -1,
        'yes',
        'YES',
        'Yes',
        't',
        'T',
      ];

      for (final val in truthyValues) {
        final model = NotificationItemModel.fromMap({'isRead': val});
        expect(model.isRead, isTrue, reason: 'Expected $val to evaluate to true');
      }
    });

    test('falsy and invalid variants all evaluate to isRead == false', () {
      final falsyValues = [
        false,
        'false',
        'False',
        'FALSE',
        '  false  ',
        '0',
        0,
        'no',
        'NO',
        'No',
        'f',
        'F',
        null,
        '',
        '   ',
        'random_string',
        '2',
        [],
        {},
      ];

      for (final val in falsyValues) {
        final model = NotificationItemModel.fromMap({'isRead': val});
        expect(model.isRead, isFalse, reason: 'Expected $val to evaluate to false');
      }
    });

    test('supports alternative key read and respects isRead precedence', () {
      final modelRead = NotificationItemModel.fromMap({'read': true});
      expect(modelRead.isRead, isTrue);

      final modelPrecedence = NotificationItemModel.fromMap({
        'isRead': false,
        'read': true,
      });
      expect(modelPrecedence.isRead, isFalse);
    });
  });

  group('M1 Challenger - Malformed and Extreme Dates', () {
    test('parses ISO8601 with UTC Z, positive and negative offsets', () {
      const utcIso = '2026-10-04T12:00:00.000Z';
      final modelUtc = NotificationItemModel.fromMap({'createdAt': utcIso});
      expect(modelUtc.createdAt, DateTime.utc(2026, 10, 4, 12, 0, 0));

      const offsetIso = '2026-10-04T19:00:00+07:00';
      final modelOffset = NotificationItemModel.fromMap({'createdAt': offsetIso});
      expect(modelOffset.createdAt.toUtc(), DateTime.utc(2026, 10, 4, 12, 0, 0));
    });

    test('parses 10-digit epoch seconds in num and string format', () {
      const epochSeconds = 1728043200;
      final expectedUtc = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);

      final modelNum = NotificationItemModel.fromMap({'createdAt': epochSeconds});
      expect(modelNum.createdAt, expectedUtc);

      final modelStr = NotificationItemModel.fromMap({'createdAt': '$epochSeconds'});
      expect(modelStr.createdAt, expectedUtc);

      final modelDouble = NotificationItemModel.fromMap({'createdAt': 1728043200.0});
      expect(modelDouble.createdAt, expectedUtc);
    });

    test('parses 13-digit epoch milliseconds in num and string format', () {
      const epochMillis = 1728043200123;
      final expectedUtc = DateTime.fromMillisecondsSinceEpoch(epochMillis);

      final modelNum = NotificationItemModel.fromMap({'createdAt': epochMillis});
      expect(modelNum.createdAt, expectedUtc);

      final modelStr = NotificationItemModel.fromMap({'createdAt': '$epochMillis'});
      expect(modelStr.createdAt, expectedUtc);
    });

    test('supports alternative date keys with createdAt > timestamp > date > time precedence', () {
      const t1 = '2026-10-04T01:00:00.000Z';
      const t2 = '2026-10-04T02:00:00.000Z';
      const t3 = '2026-10-04T03:00:00.000Z';
      const t4 = '2026-10-04T04:00:00.000Z';

      final modelTimeOnly = NotificationItemModel.fromMap({'time': t4});
      expect(modelTimeOnly.createdAt, DateTime.utc(2026, 10, 4, 4, 0, 0));

      final modelDateAndTime = NotificationItemModel.fromMap({'date': t3, 'time': t4});
      expect(modelDateAndTime.createdAt, DateTime.utc(2026, 10, 4, 3, 0, 0));

      final modelTimestampPrecedence = NotificationItemModel.fromMap({
        'timestamp': t2,
        'date': t3,
        'time': t4,
      });
      expect(modelTimestampPrecedence.createdAt, DateTime.utc(2026, 10, 4, 2, 0, 0));

      final modelCreatedPrecedence = NotificationItemModel.fromMap({
        'createdAt': t1,
        'timestamp': t2,
        'date': t3,
        'time': t4,
      });
      expect(modelCreatedPrecedence.createdAt, DateTime.utc(2026, 10, 4, 1, 0, 0));
    });

    test('handles malformed date strings safely without throwing', () {
      final invalidStrings = [
        'invalid-date',
        '2026-99-99',
        'undefined',
        'null',
        'NaN',
        '',
        '   ',
        '--::T',
      ];

      final before = DateTime.now().subtract(const Duration(seconds: 2));

      for (final inv in invalidStrings) {
        final model = NotificationItemModel.fromMap({'createdAt': inv});
        expect(model.createdAt.isAfter(before), isTrue,
            reason: 'Expected fallback to current date for $inv');
      }
    });

    test('boundary dates: year 1970 epoch 0 and year 2038 32-bit boundary', () {
      // 0 epoch is 1970-01-01
      final modelEpoch0 = NotificationItemModel.fromMap({'createdAt': 0});
      expect(modelEpoch0.createdAt, DateTime.fromMillisecondsSinceEpoch(0));

      // 2147483647 is 2038-01-19 (10-digit epoch seconds)
      final model2038 = NotificationItemModel.fromMap({'createdAt': 2147483647});
      expect(model2038.createdAt, DateTime.fromMillisecondsSinceEpoch(2147483647 * 1000));
    });

    test('extreme out-of-range epoch numbers handle gracefully without throwing ArgumentError', () {
      // Dart DateTime max is 8640000000000000. 9999999999999999 exceeds range.
      final modelOutOfRange = NotificationItemModel.fromMap({'createdAt': 9999999999999999});
      expect(modelOutOfRange.createdAt, isA<DateTime>());
    });

    test('handles double.nan and double.infinity num values without throwing', () {
      final modelNan = NotificationItemModel.fromMap({'createdAt': double.nan});
      expect(modelNan.createdAt, isA<DateTime>());

      final modelInf = NotificationItemModel.fromMap({'createdAt': double.infinity});
      expect(modelInf.createdAt, isA<DateTime>());
    });
  });

  group('M1 Challenger - Nested Dynamic Maps and Metadata Sanitization', () {
    test('sanitizes deeply nested dynamic maps with mixed key types to Map<String, dynamic>', () {
      final rawNested = <dynamic, dynamic>{
        'id': 'deep_1',
        'metadata': <dynamic, dynamic>{
          10: 'level_1',
          'lvl2': <dynamic, dynamic>{
            20: 'level_2',
            'lvl3': <dynamic, dynamic>{
              30: 'level_3',
              'array': [
                <dynamic, dynamic>{100: 'item_100'},
                'raw_string',
                42,
              ],
            },
          },
        },
      };

      final model = NotificationItemModel.fromMap(rawNested);

      expect(model.metadata, isA<Map<String, dynamic>>());
      expect(model.metadata?['10'], 'level_1');

      final lvl2 = model.metadata?['lvl2'] as Map<String, dynamic>;
      expect(lvl2['20'], 'level_2');

      final lvl3 = lvl2['lvl3'] as Map<String, dynamic>;
      expect(lvl3['30'], 'level_3');

      final array = lvl3['array'] as List;
      expect((array[0] as Map<String, dynamic>)['100'], 'item_100');
      expect(array[1], 'raw_string');
      expect(array[2], 42);
    });

    test('safely discards non-map metadata values (String, int, List, bool)', () {
      expect(NotificationItemModel.fromMap({'metadata': 'a string'}).metadata, isNull);
      expect(NotificationItemModel.fromMap({'metadata': 12345}).metadata, isNull);
      expect(NotificationItemModel.fromMap({'metadata': [1, 2, 3]}).metadata, isNull);
      expect(NotificationItemModel.fromMap({'metadata': true}).metadata, isNull);
    });

    test('preserves Vietnamese unicode characters, quotes, and emojis in metadata', () {
      final metadata = {
        'customerName': 'Nguyễn Văn Đạt',
        'productNote': 'Hàng dễ vỡ 🛍️ • giảm 20%',
        'jsonSnippet': '{"key": "value"}',
      };

      final model = NotificationItemModel.fromMap({'metadata': metadata});
      expect(model.metadata?['customerName'], 'Nguyễn Văn Đạt');
      expect(model.metadata?['productNote'], 'Hàng dễ vỡ 🛍️ • giảm 20%');
      expect(model.metadata?['jsonSnippet'], '{"key": "value"}');
    });
  });

  group('M1 Challenger - Enum Variations and Loose Parsing', () {
    test('exact matching for all 8 business notification types', () {
      final expectedTypes = {
        'order_created': NotificationType.orderCreated,
        'order_updated': NotificationType.orderUpdated,
        'order_cancelled': NotificationType.orderCancelled,
        'order_return': NotificationType.orderReturn,
        'inventory_imported': NotificationType.inventoryImported,
        'customer_created': NotificationType.customerCreated,
        'customer_debt_added': NotificationType.customerDebtAdded,
        'customer_debt_paid': NotificationType.customerDebtPaid,
      };

      for (final entry in expectedTypes.entries) {
        expect(NotificationType.fromString(entry.key), entry.value);
        expect(entry.value.value, entry.key);
      }
    });

    test('case-insensitivity and camelCase variations for NotificationType', () {
      expect(NotificationType.fromString('ORDER_CREATED'), NotificationType.orderCreated);
      expect(NotificationType.fromString('orderCreated'), NotificationType.orderCreated);
      expect(NotificationType.fromString('OrderCreated'), NotificationType.orderCreated);
      expect(NotificationType.fromString('CUSTOMER_DEBT_PAID'), NotificationType.customerDebtPaid);
      expect(NotificationType.fromString('customerDebtPaid'), NotificationType.customerDebtPaid);
      expect(NotificationType.fromString('INVENTORY_IMPORTED'), NotificationType.inventoryImported);
      expect(NotificationType.fromString('inventoryImported'), NotificationType.inventoryImported);
    });

    test('hyphen-delimited variations for NotificationType', () {
      expect(NotificationType.fromString('order-created'), NotificationType.orderCancelled == NotificationType.fromString('order-cancelled') ? NotificationType.orderCreated : NotificationType.orderCreated);
      expect(NotificationType.fromString('order-cancelled'), NotificationType.orderCancelled);
      expect(NotificationType.fromString('customer-debt-added'), NotificationType.customerDebtAdded);
      expect(NotificationType.fromString('inventory-imported'), NotificationType.inventoryImported);
    });

    test('loose keyword fallback matching', () {
      expect(NotificationType.fromString('cancel_my_order'), NotificationType.orderCancelled);
      expect(NotificationType.fromString('product_return_event'), NotificationType.orderReturn);
      expect(NotificationType.fromString('edit_order_info'), NotificationType.orderUpdated);
      expect(NotificationType.fromString('stock_import_done'), NotificationType.inventoryImported);
      expect(NotificationType.fromString('inventory_check'), NotificationType.inventoryImported);
      expect(NotificationType.fromString('paid_debt'), NotificationType.customerDebtPaid);
      expect(NotificationType.fromString('collect_invoice_debt'), NotificationType.customerDebtPaid);
      expect(NotificationType.fromString('incurred_debt'), NotificationType.customerDebtAdded);
      expect(NotificationType.fromString('new_customer_registered'), NotificationType.customerCreated);
    });

    test('unknown or null strings fallback to orderCreated', () {
      expect(NotificationType.fromString('totally_unrecognized_event_type'), NotificationType.orderCreated);
      expect(NotificationType.fromString(''), NotificationType.orderCreated);
      expect(NotificationType.fromString('   '), NotificationType.orderCreated);
      expect(NotificationType.fromString(null), NotificationType.orderCreated);
    });

    test('all 8 notification types map to exact categories', () {
      expect(NotificationType.orderCreated.category, NotificationCategory.orders);
      expect(NotificationType.orderUpdated.category, NotificationCategory.orders);
      expect(NotificationType.orderCancelled.category, NotificationCategory.orders);
      expect(NotificationType.orderReturn.category, NotificationCategory.orders);

      expect(NotificationType.inventoryImported.category, NotificationCategory.inventory);

      expect(NotificationType.customerCreated.category, NotificationCategory.customers);
      expect(NotificationType.customerDebtAdded.category, NotificationCategory.customers);
      expect(NotificationType.customerDebtPaid.category, NotificationCategory.customers);
    });

    test('NotificationCategory parsing and fallbacks', () {
      expect(NotificationCategory.fromString('orders'), NotificationCategory.orders);
      expect(NotificationCategory.fromString('inventory'), NotificationCategory.inventory);
      expect(NotificationCategory.fromString('customers'), NotificationCategory.customers);
      expect(NotificationCategory.fromString('system'), NotificationCategory.system);

      // Uppercase & trimmed
      expect(NotificationCategory.fromString('  ORDERS  '), NotificationCategory.orders);
      expect(NotificationCategory.fromString('INVENTORY'), NotificationCategory.inventory);

      // Unknown & null fallback to system
      expect(NotificationCategory.fromString('unknown_category'), NotificationCategory.system);
      expect(NotificationCategory.fromString(''), NotificationCategory.system);
      expect(NotificationCategory.fromString(null), NotificationCategory.system);
    });
  });

  group('M1 Challenger - Immutability & copyWith Behavior', () {
    final originalDate = DateTime.utc(2026, 10, 4, 12, 0, 0);
    final entity = NotificationItem(
      id: 'notif_imm',
      storeId: 'store_001',
      title: 'Original Title',
      body: 'Original Body',
      type: NotificationType.orderCreated,
      isRead: false,
      createdAt: originalDate,
      targetRoute: '/orders',
      targetId: 'HD001',
      metadata: {'counter': 100, 'tag': 'vip'},
    );

    test('copyWith creates new entity without mutating original', () {
      final copy = entity.copyWith(
        title: 'New Title',
        isRead: true,
        targetId: 'HD002',
      );

      expect(copy.title, 'New Title');
      expect(copy.isRead, isTrue);
      expect(copy.targetId, 'HD002');

      // Original unchanged
      expect(entity.title, 'Original Title');
      expect(entity.isRead, isFalse);
      expect(entity.targetId, 'HD001');
      expect(entity.id, copy.id);
      expect(entity.storeId, copy.storeId);
      expect(entity.body, copy.body);
    });

    test('copyWith shallow-clones metadata so mutating copy does not affect original', () {
      final copy = entity.copyWith(title: 'Copy with metadata check');

      expect(copy.metadata, isNotNull);
      expect(copy.metadata?['counter'], 100);

      // Mutate copy's metadata map
      copy.metadata?['counter'] = 999;
      copy.metadata?['newField'] = 'added';

      // Original entity metadata remains unmutated
      expect(entity.metadata?['counter'], 100);
      expect(entity.metadata?.containsKey('newField'), isFalse);
    });
  });

  group('M1 Challenger - Equality and HashCode Edge Cases', () {
    final date = DateTime.utc(2026, 10, 4, 12, 0, 0);

    test('value equality holds for identical field values in NotificationItem', () {
      final a = NotificationItem(
        id: 'eq_1',
        storeId: 'store_001',
        title: 'Title',
        body: 'Body',
        type: NotificationType.orderCreated,
        isRead: false,
        createdAt: date,
        metadata: {'k': 'v'},
      );

      final b = NotificationItem(
        id: 'eq_1',
        storeId: 'store_001',
        title: 'Title',
        body: 'Body',
        type: NotificationType.orderCreated,
        isRead: false,
        createdAt: date,
        metadata: {'k': 'v'},
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('value equality with nested metadata maps in NotificationItem', () {
      final a = NotificationItem(
        id: 'eq_nested',
        storeId: 'store_001',
        title: 'Title',
        body: 'Body',
        type: NotificationType.orderCreated,
        isRead: false,
        createdAt: date,
        metadata: {
          'order': {'total': 100000, 'code': 'HD01'}
        },
      );

      final b = NotificationItem(
        id: 'eq_nested',
        storeId: 'store_001',
        title: 'Title',
        body: 'Body',
        type: NotificationType.orderCreated,
        isRead: false,
        createdAt: date,
        metadata: {
          'order': {'total': 100000, 'code': 'HD01'}
        },
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality when any field differs', () {
      final base = NotificationItem(
        id: 'eq_base',
        storeId: 'store_001',
        title: 'Title',
        body: 'Body',
        type: NotificationType.orderCreated,
        isRead: false,
        createdAt: date,
      );

      expect(base, isNot(equals(base.copyWith(id: 'diff'))));
      expect(base, isNot(equals(base.copyWith(storeId: 'diff'))));
      expect(base, isNot(equals(base.copyWith(title: 'diff'))));
      expect(base, isNot(equals(base.copyWith(body: 'diff'))));
      expect(base, isNot(equals(base.copyWith(type: NotificationType.orderUpdated))));
      expect(base, isNot(equals(base.copyWith(isRead: true))));
      expect(base, isNot(equals(base.copyWith(createdAt: DateTime.utc(2025)))));
      expect(base, isNot(equals(base.copyWith(targetRoute: '/new'))));
      expect(base, isNot(equals(base.copyWith(targetId: 'new_id'))));
      expect(base, isNot(equals(base.copyWith(metadata: {'new': 1}))));
    });

    test('equality with null metadata', () {
      final a = NotificationItem(
        id: '1',
        storeId: 's',
        title: 't',
        body: 'b',
        type: NotificationType.orderCreated,
        createdAt: date,
        metadata: null,
      );
      final b = NotificationItem(
        id: '1',
        storeId: 's',
        title: 't',
        body: 'b',
        type: NotificationType.orderCreated,
        createdAt: date,
        metadata: null,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality against null or different object type', () {
      final item = NotificationItem(
        id: '1',
        storeId: 's',
        title: 't',
        body: 'b',
        type: NotificationType.orderCreated,
        createdAt: date,
      );

      const Object? nullObj = null;
      const Object stringObj = 'string';
      const Object intObj = 123;
      expect(item == nullObj, isFalse);
      expect(item == stringObj, isFalse);
      expect(item == intObj, isFalse);
    });

    test('model value equality holds with identical values and metadata', () {
      final a = NotificationItemModel(
        id: 'm1',
        storeId: 's1',
        title: 'T',
        body: 'B',
        type: 'order_created',
        createdAt: date,
        metadata: {'nested': {'key': 'val'}},
      );
      final b = NotificationItemModel(
        id: 'm1',
        storeId: 's1',
        title: 'T',
        body: 'B',
        type: 'order_created',
        createdAt: date,
        metadata: {'nested': {'key': 'val'}},
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('value equality with list inside metadata for NotificationItem and NotificationItemModel', () {
      final a = NotificationItemModel(
        id: 'm_list',
        storeId: 's1',
        title: 'T',
        body: 'B',
        type: 'order_created',
        createdAt: date,
        metadata: {
          'items': ['SKU1', 'SKU2']
        },
      );
      final b = NotificationItemModel(
        id: 'm_list',
        storeId: 's1',
        title: 'T',
        body: 'B',
        type: 'order_created',
        createdAt: date,
        metadata: {
          'items': ['SKU1', 'SKU2']
        },
      );

      expect(a, equals(b));
    });
  });

  group('M1 Challenger - Full Bidirectional Serialization Round-Trip', () {
    test('round-trip domain -> model -> toMap -> fromMap -> toDomain is 100% lossless', () {
      final original = NotificationItem(
        id: 'notif_roundtrip',
        storeId: 'store_002',
        title: 'Đơn hàng mới HD013259',
        body: 'Đơn hàng 250.000 đ',
        type: NotificationType.orderCreated,
        isRead: true,
        createdAt: DateTime.utc(2026, 10, 4, 12, 30, 0),
        targetRoute: '/orders/invoices',
        targetId: 'HD013259',
        metadata: {'amount': 250000, 'items': 3},
      );

      final model = NotificationItemModel.fromDomain(original);
      final map = model.toMap();
      final reconstructedModel = NotificationItemModel.fromMap(map);
      final reconstructedDomain = reconstructedModel.toDomain();

      expect(reconstructedDomain, equals(original));
      expect(reconstructedDomain.hashCode, equals(original.hashCode));
      expect(reconstructedDomain.category, equals(original.category));
    });

    test('toMap omits null optional fields to save RTDB egress bandwidth', () {
      final minimalModel = NotificationItemModel(
        id: 'min_1',
        storeId: 's1',
        title: 'Min',
        body: 'Body',
        type: 'order_created',
        createdAt: DateTime.utc(2026, 10, 4),
        targetRoute: null,
        targetId: null,
        metadata: null,
      );

      final map = minimalModel.toMap();

      expect(map.containsKey('targetRoute'), isFalse);
      expect(map.containsKey('targetId'), isFalse);
      expect(map.containsKey('metadata'), isFalse);

      expect(map.containsKey('id'), isTrue);
      expect(map.containsKey('storeId'), isTrue);
      expect(map.containsKey('title'), isTrue);
      expect(map.containsKey('body'), isTrue);
      expect(map.containsKey('type'), isTrue);
      expect(map.containsKey('isRead'), isTrue);
      expect(map.containsKey('createdAt'), isTrue);
    });
  });
}
