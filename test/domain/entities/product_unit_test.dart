import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/product_unit.dart';

import '../../fixtures/mock_product_data.dart';

void main() {
  group('ProductUnit Entity Unit Tests', () {
    test('Default values for optional fields', () {
      const unit = ProductUnit(
        id: 'u_default',
        unitName: 'Cái',
        price: 10000.0,
      );

      expect(unit.id, equals('u_default'));
      expect(unit.unitName, equals('Cái'));
      expect(unit.conversionRate, equals(1));
      expect(unit.price, equals(10000.0));
      expect(unit.costPrice, isNull);
      expect(unit.barcode, isNull);
      expect(unit.code, isNull);
      expect(unit.isDirectSale, isTrue);
    });

    test('Full parameter initialization', () {
      final unit = MockProductData.createProductUnit(
        id: 'u_thung',
        unitName: 'Thùng 24 lon',
        conversionRate: 24,
        price: 360000.0,
        costPrice: 240000.0,
        barcode: '893999999024',
        code: 'BSG-T24',
        isDirectSale: true,
      );

      expect(unit.id, equals('u_thung'));
      expect(unit.unitName, equals('Thùng 24 lon'));
      expect(unit.conversionRate, equals(24));
      expect(unit.price, equals(360000.0));
      expect(unit.costPrice, equals(240000.0));
      expect(unit.barcode, equals('893999999024'));
      expect(unit.code, equals('BSG-T24'));
      expect(unit.isDirectSale, isTrue);
    });

    test('copyWith creates modified clone while retaining unmodified fields', () {
      const original = ProductUnit(
        id: 'u_loc',
        unitName: 'Lốc 6',
        conversionRate: 6,
        price: 90000.0,
        costPrice: 60000.0,
        barcode: '8930006',
        code: 'LOC-06',
        isDirectSale: true,
      );

      final modified = original.copyWith(
        price: 95000.0,
        costPrice: 62000.0,
        isDirectSale: false,
      );

      expect(modified.id, equals('u_loc'));
      expect(modified.unitName, equals('Lốc 6'));
      expect(modified.conversionRate, equals(6));
      expect(modified.price, equals(95000.0));
      expect(modified.costPrice, equals(62000.0));
      expect(modified.barcode, equals('8930006'));
      expect(modified.code, equals('LOC-06'));
      expect(modified.isDirectSale, isFalse);
    });

    test('Serialization toMap and deserialization fromMap round-trip', () {
      final unit = MockProductData.createProductUnit(
        id: 'u_hop',
        unitName: 'Hộp 10 gói',
        conversionRate: 10,
        price: 150000.0,
        costPrice: 95000.0,
        barcode: '893888888010',
        code: 'HOP-10',
        isDirectSale: true,
      );

      final map = unit.toMap();
      expect(map['id'], equals('u_hop'));
      expect(map['unitName'], equals('Hộp 10 gói'));
      expect(map['conversionRate'], equals(10));
      expect(map['price'], equals(150000.0));
      expect(map['costPrice'], equals(95000.0));
      expect(map['barcode'], equals('893888888010'));
      expect(map['code'], equals('HOP-10'));
      expect(map['isDirectSale'], isTrue);

      final deserialized = ProductUnit.fromMap(map);
      expect(deserialized, equals(unit));
      expect(deserialized.id, equals(unit.id));
      expect(deserialized.unitName, equals(unit.unitName));
      expect(deserialized.conversionRate, equals(unit.conversionRate));
      expect(deserialized.price, equals(unit.price));
      expect(deserialized.costPrice, equals(unit.costPrice));
      expect(deserialized.barcode, equals(unit.barcode));
      expect(deserialized.code, equals(unit.code));
      expect(deserialized.isDirectSale, equals(unit.isDirectSale));
    });

    test('fromMap gracefully handles nulls and int/double numeric variations', () {
      final rawMap = {
        'id': 'u_raw',
        'unitName': 'Gói lẻ',
        'conversionRate': 1.0, // double from json
        'price': 15000, // int from json
        'costPrice': 10000, // int from json
        // barcode, code omitted
        'isDirectSale': null,
      };

      final unit = ProductUnit.fromMap(rawMap);

      expect(unit.id, equals('u_raw'));
      expect(unit.unitName, equals('Gói lẻ'));
      expect(unit.conversionRate, equals(1));
      expect(unit.price, equals(15000.0));
      expect(unit.costPrice, equals(10000.0));
      expect(unit.barcode, isNull);
      expect(unit.code, isNull);
      expect(unit.isDirectSale, isTrue); // default true when null
    });

    test('Value equality and hashCode', () {
      final unit1 = MockProductData.createProductUnit(
        id: 'u_1',
        unitName: 'Chai',
        conversionRate: 1,
        price: 20000.0,
      );

      final unit2 = MockProductData.createProductUnit(
        id: 'u_1',
        unitName: 'Chai',
        conversionRate: 1,
        price: 20000.0,
      );

      final unit3 = MockProductData.createProductUnit(
        id: 'u_2',
        unitName: 'Chai',
        conversionRate: 1,
        price: 20000.0,
      );

      expect(unit1, equals(unit2));
      expect(unit1.hashCode, equals(unit2.hashCode));
      expect(unit1, isNot(equals(unit3)));
    });

    test('toString contains all essential fields', () {
      const unit = ProductUnit(
        id: 'u_tst',
        unitName: 'TestUnit',
        conversionRate: 12,
        price: 120000.0,
        costPrice: 80000.0,
        barcode: '123456',
        code: 'TU12',
        isDirectSale: false,
      );

      final str = unit.toString();
      expect(str, contains('u_tst'));
      expect(str, contains('TestUnit'));
      expect(str, contains('12'));
      expect(str, contains('120000.0'));
      expect(str, contains('80000.0'));
      expect(str, contains('123456'));
      expect(str, contains('TU12'));
      expect(str, contains('false'));
    });
  });
}
