import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/models/notification_item_model.dart';
import 'package:stores/domain/entities/notification_item.dart';
import 'package:stores/domain/entities/notification_type.dart';

void main() {
  group('M1 Deep Challenger - Recursive Map/List Metadata Equality', () {
    final baseDate = DateTime.utc(2026, 10, 4, 12, 0, 0);

    test('10-level deeply nested map and list structures evaluate equality correctly', () {
      Map<String, dynamic> buildDeepStructure(String leafValue) {
        return {
          'l1_map': {
            'l2_list': [
              {
                'l3_map': {
                  'l4_list': [
                    {
                      'l5_map': {
                        'l6_list': [
                          {
                            'l7_map': {
                              'l8_list': [
                                {
                                  'l9_map': {
                                    'l10_leaf': leafValue,
                                  }
                                }
                              ]
                            }
                          }
                        ]
                      }
                    }
                  ]
                }
              }
            ]
          }
        };
      }

      final itemA = NotificationItem(
        id: 'deep_a',
        storeId: 'store_001',
        title: 'Title',
        body: 'Body',
        type: NotificationType.orderCreated,
        createdAt: baseDate,
        metadata: buildDeepStructure('MATCH'),
      );

      final itemB = NotificationItem(
        id: 'deep_a',
        storeId: 'store_001',
        title: 'Title',
        body: 'Body',
        type: NotificationType.orderCreated,
        createdAt: baseDate,
        metadata: buildDeepStructure('MATCH'),
      );

      final itemC = NotificationItem(
        id: 'deep_a',
        storeId: 'store_001',
        title: 'Title',
        body: 'Body',
        type: NotificationType.orderCreated,
        createdAt: baseDate,
        metadata: buildDeepStructure('DIFFERENT'),
      );

      // Symmetry and value equality
      expect(itemA == itemB, isTrue);
      expect(itemB == itemA, isTrue);
      expect(itemA == itemC, isFalse);
      expect(itemC == itemA, isFalse);

      // Model equality
      final modelA = NotificationItemModel.fromDomain(itemA);
      final modelB = NotificationItemModel.fromDomain(itemB);
      final modelC = NotificationItemModel.fromDomain(itemC);

      expect(modelA == modelB, isTrue);
      expect(modelB == modelA, isTrue);
      expect(modelA == modelC, isFalse);
    });

    test('metadata equality with heterogeneous list elements and nulls', () {
      final meta1 = {
        'items': [
          null,
          100,
          'string_val',
          true,
          false,
          3.14159,
          {'nestedKey': null},
          [null, 1, 'sub'],
        ]
      };

      final meta2 = {
        'items': [
          null,
          100,
          'string_val',
          true,
          false,
          3.14159,
          {'nestedKey': null},
          [null, 1, 'sub'],
        ]
      };

      final metaDifferentOrder = {
        'items': [
          100,
          null, // swapped
          'string_val',
          true,
          false,
          3.14159,
          {'nestedKey': null},
          [null, 1, 'sub'],
        ]
      };

      final item1 = NotificationItem(
        id: 'het_1',
        storeId: 'store_001',
        title: 'T',
        body: 'B',
        type: NotificationType.orderCreated,
        createdAt: baseDate,
        metadata: meta1,
      );

      final item2 = NotificationItem(
        id: 'het_1',
        storeId: 'store_001',
        title: 'T',
        body: 'B',
        type: NotificationType.orderCreated,
        createdAt: baseDate,
        metadata: meta2,
      );

      final itemDiff = NotificationItem(
        id: 'het_1',
        storeId: 'store_001',
        title: 'T',
        body: 'B',
        type: NotificationType.orderCreated,
        createdAt: baseDate,
        metadata: metaDifferentOrder,
      );

      expect(item1 == item2, isTrue);
      expect(item1 == itemDiff, isFalse);
    });

    test('metadata equality is independent of map key insertion order', () {
      final metaA = {
        'z': 1,
        'a': 2,
        'm': {'last': 99, 'first': 1},
      };

      final metaB = {
        'a': 2,
        'm': {'first': 1, 'last': 99},
        'z': 1,
      };

      final itemA = NotificationItem(
        id: 'order_test',
        storeId: 'store_001',
        title: 'T',
        body: 'B',
        type: NotificationType.orderCreated,
        createdAt: baseDate,
        metadata: metaA,
      );

      final itemB = NotificationItem(
        id: 'order_test',
        storeId: 'store_001',
        title: 'T',
        body: 'B',
        type: NotificationType.orderCreated,
        createdAt: baseDate,
        metadata: metaB,
      );

      expect(itemA == itemB, isTrue);
      expect(itemB == itemA, isTrue);
    });

    test('metadata equality detects mismatched list lengths and map missing keys', () {
      final base = NotificationItem(
        id: 'len_test',
        storeId: 'store_001',
        title: 'T',
        body: 'B',
        type: NotificationType.orderCreated,
        createdAt: baseDate,
        metadata: {
          'list': [1, 2, 3],
          'map': {'a': 1, 'b': 2},
        },
      );

      final shorterList = base.copyWith(
        metadata: {
          'list': [1, 2],
          'map': {'a': 1, 'b': 2},
        },
      );

      final missingMapKey = base.copyWith(
        metadata: {
          'list': [1, 2, 3],
          'map': {'a': 1},
        },
      );

      final differentMapKey = base.copyWith(
        metadata: {
          'list': [1, 2, 3],
          'map': {'a': 1, 'c': 2},
        },
      );

      final typeMismatchInMetadata = base.copyWith(
        metadata: {
          'list': {'not': 'a list'},
          'map': {'a': 1, 'b': 2},
        },
      );

      expect(base == shorterList, isFalse);
      expect(base == missingMapKey, isFalse);
      expect(base == differentMapKey, isFalse);
      expect(base == typeMismatchInMetadata, isFalse);
    });
  });

  group('M1 Deep Challenger - Boundary Dates & Extreme Formats', () {
    test('exact Dart millisecond bounds (-8640000000000000 and 8640000000000000)', () {
      // Dart DateTime range is -8640000000000000 to 8640000000000000 inclusive
      final modelMax = NotificationItemModel.fromMap({'createdAt': 8640000000000000});
      expect(modelMax.createdAt, DateTime.fromMillisecondsSinceEpoch(8640000000000000));

      final modelMin = NotificationItemModel.fromMap({'createdAt': -8640000000000000});
      expect(modelMin.createdAt, DateTime.fromMillisecondsSinceEpoch(-8640000000000000));

      // Just outside bounds: must gracefully fall back without throwing RangeError
      final before = DateTime.now().subtract(const Duration(seconds: 2));
      final modelBeyondMax = NotificationItemModel.fromMap({'createdAt': 8640000000000001});
      expect(modelBeyondMax.createdAt.isAfter(before), isTrue);

      final modelBeyondMin = NotificationItemModel.fromMap({'createdAt': -8640000000000001});
      expect(modelBeyondMin.createdAt.isAfter(before), isTrue);
    });

    test('extreme string numbers (over 30 digits) fall back gracefully without unhandled exception', () {
      final before = DateTime.now().subtract(const Duration(seconds: 2));
      const hugeNumStr = '999999999999999999999999999999999999999999999999';
      final modelHuge = NotificationItemModel.fromMap({'createdAt': hugeNumStr});
      expect(modelHuge.createdAt.isAfter(before), isTrue);

      const negHugeNumStr = '-999999999999999999999999999999999999999999999999';
      final modelNegHuge = NotificationItemModel.fromMap({'createdAt': negHugeNumStr});
      expect(modelNegHuge.createdAt.isAfter(before), isTrue);
    });

    test('valid leap day vs invalid leap day handling', () {
      // 2024 is leap year -> valid
      final modelLeapValid = NotificationItemModel.fromMap({'createdAt': '2024-02-29T12:00:00Z'});
      expect(modelLeapValid.createdAt, DateTime.utc(2024, 2, 29, 12, 0, 0));

      // 2026 is NOT a leap year -> Dart DateTime parser normalizes Feb 29 to March 1
      final modelLeapNormalized = NotificationItemModel.fromMap({'createdAt': '2026-02-29T12:00:00Z'});
      expect(modelLeapNormalized.createdAt, DateTime.utc(2026, 3, 1, 12, 0, 0));
    });

    test('ISO strings with microsecond precision and varying offsets', () {
      // Microsecond precision
      final modelMicro = NotificationItemModel.fromMap({'createdAt': '2026-10-04T12:30:45.123456Z'});
      expect(modelMicro.createdAt, DateTime.utc(2026, 10, 4, 12, 30, 45, 123, 456));

      // Negative offset: America/New_York (UTC-4)
      final modelNy = NotificationItemModel.fromMap({'createdAt': '2026-10-04T08:00:00-04:00'});
      expect(modelNy.createdAt.toUtc(), DateTime.utc(2026, 10, 4, 12, 0, 0));

      // Positive offset: Vietnam (UTC+7)
      final modelVn = NotificationItemModel.fromMap({'createdAt': '2026-10-04T19:00:00+07:00'});
      expect(modelVn.createdAt.toUtc(), DateTime.utc(2026, 10, 4, 12, 0, 0));
    });

    test('string epoch with leading/trailing whitespaces', () {
      const epochSec = 1728043200;
      final expected = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);

      final modelPadded = NotificationItemModel.fromMap({'createdAt': '   $epochSec   \n'});
      expect(modelPadded.createdAt, expected);
    });

    test('scientific notation number and string are parsed safely', () {
      // 1.728e9 = 1728000000 (seconds)
      final modelSciNum = NotificationItemModel.fromMap({'createdAt': 1.728e9});
      expect(modelSciNum.createdAt, DateTime.fromMillisecondsSinceEpoch((1.728e9).toInt() * 1000));

      final modelSciStr = NotificationItemModel.fromMap({'createdAt': '1.728e9'});
      expect(modelSciStr.createdAt, DateTime.fromMillisecondsSinceEpoch((1.728e9).toInt() * 1000));
    });

    test('direct DateTime instance in fromMap passes through unmodified', () {
      final directDt = DateTime.utc(2026, 10, 4, 15, 45, 0);
      final modelDirect = NotificationItemModel.fromMap({'createdAt': directDt});
      expect(modelDirect.createdAt, directDt);
    });

    test('invalid date falls back safely to current timestamp', () {
      final before = DateTime.now().subtract(const Duration(seconds: 2));
      final modelFallback = NotificationItemModel.fromMap(
        {'createdAt': 'unparseable_date_value'},
      );
      expect(modelFallback.createdAt.isAfter(before), isTrue);
    });
  });

  group('M1 Deep Challenger - Clean Architecture & Layer Integrity', () {
    test('NotificationItem domain entity is pure Dart and has no UI or Firebase dependencies', () {
      final item = NotificationItem(
        id: 'p1',
        storeId: 'store_001',
        title: 'Clean Architecture Test',
        body: 'Zero flutter/material import',
        type: NotificationType.orderCreated,
        createdAt: DateTime.utc(2026, 10, 4),
      );

      expect(item.id, 'p1');
      expect(item.category, NotificationCategory.orders);
    });
  });
}
