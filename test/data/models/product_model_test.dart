import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/product_unit.dart';

void main() {
  group('ProductModel Data Layer Unit Tests', () {
    test('toMap and fromMap full round-trip with units, minStock, maxStock', () {
      const unit1 = ProductUnit(
        id: 'u1',
        unitName: 'Lon',
        conversionRate: 1,
        price: 15000.0,
        costPrice: 11000.0,
      );
      const unit2 = ProductUnit(
        id: 'u2',
        unitName: 'Thùng 24',
        conversionRate: 24,
        price: 340000.0,
        costPrice: 250000.0,
      );

      const model = ProductModel(
        id: 'p01',
        name: 'Bia Saigon',
        code: 'BSG01',
        barcode: '893111',
        brand: 'Sabeco',
        model: 'Special',
        price: 15000.0,
        costPrice: 11000.0,
        branchStocks: {'store_001': 100, 'store_002': 50},
        category: 'Đồ uống',
        type: 'Hàng hóa',
        unit: 'Lon',
        minStock: 20,
        maxStock: 500,
        units: [unit1, unit2],
      );

      final map = model.toMap();
      expect(map['id'], equals('p01'));
      expect(map['minStock'], equals(20));
      expect(map['maxStock'], equals(500));
      expect((map['units'] as List).length, equals(2));

      final restored = ProductModel.fromMap(map);
      expect(restored.id, equals('p01'));
      expect(restored.name, equals('Bia Saigon'));
      expect(restored.minStock, equals(20));
      expect(restored.maxStock, equals(500));
      expect(restored.units.length, equals(2));
      expect(restored.units[0].unitName, equals('Lon'));
      expect(restored.units[1].conversionRate, equals(24));
      expect(restored.branchStocks['store_001'], equals(100));
      expect(restored.branchStocks['store_002'], equals(50));
    });

    test('fromMap provides backwards compatibility for legacy records with single stock field', () {
      final legacyMap = {
        'id': 'p_legacy_01',
        'name': 'Sản phẩm cũ',
        'code': 'OLD01',
        'price': 100000,
        'stock': 42, // legacy single stock field without branchStocks
        'category': 'Gia dụng',
      };

      final model = ProductModel.fromMap(legacyMap);

      expect(model.id, equals('p_legacy_01'));
      expect(model.branchStocks['store_001'], equals(42));
      expect(model.branchStocks['store_002'], equals(0));
      expect(model.costPrice, equals(70000.0), reason: 'Cost price fallback is 70% of price');
      expect(model.minStock, isNull);
      expect(model.maxStock, isNull);
      expect(model.units, isEmpty);
      expect(model.isCombo, isFalse);
    });

    test('fromMap safely parses numeric and map variations from Firebase RTDB and normalizes legacy keys', () {
      final rtdbMap = {
        'id': 'p_rtdb',
        'name': 'RTDB Product',
        'price': 50000.0,
        'costPrice': 30000,
        'minStock': 5.0, // numeric double
        'maxStock': 100.0,
        'branchStocks': {
          'branch_1': 10.0, // legacy double value in map
          'branch_2': 20,
        },
        'units': {
          '0': {
            'id': 'u1',
            'unitName': 'Hộp',
            'conversionRate': 1.0,
            'price': 50000,
          },
          '1': {
            'id': 'u2',
            'unitName': 'Thùng',
            'conversionRate': 12,
            'price': 550000,
          },
        },
      };

      final model = ProductModel.fromMap(rtdbMap);

      expect(model.minStock, equals(5));
      expect(model.maxStock, equals(100));
      expect(model.branchStocks['store_001'], equals(10));
      expect(model.branchStocks['store_002'], equals(20));
      expect(model.units.length, equals(2));
      expect(model.units[0].unitName, equals('Hộp'));
      expect(model.units[1].conversionRate, equals(12));
    });

    test('fromMap handles comboComponents list properly', () {
      final comboMap = {
        'id': 'combo_01',
        'name': 'Gói quà Tết',
        'price': 500000.0,
        'isCombo': true,
        'comboComponents': [
          {
            'productId': 'p1',
            'productCode': 'B01',
            'productName': 'Bánh',
            'quantity': 2,
            'costPrice': 50000.0,
          },
          {
            'productId': 'p2',
            'productCode': 'K01',
            'productName': 'Kẹo',
            'quantity': 3,
            'costPrice': 30000.0,
          },
        ],
      };

      final model = ProductModel.fromMap(comboMap);

      expect(model.isCombo, isTrue);
      expect(model.comboComponents.length, equals(2));
      expect(model.comboComponents[0].productName, equals('Bánh'));
      expect(model.comboComponents[0].quantity, equals(2));
      expect(model.comboComponents[1].productName, equals('Kẹo'));
      expect(model.comboComponents[1].quantity, equals(3));
    });

    test('fromMap and toMap preserve canonical store IDs without collapsing to branch_1', () {
      final canonicalMap = {
        'id': 'p_canon_01',
        'name': 'Nước ngọt Pepsi 330ml',
        'code': 'PEP01',
        'price': 10000.0,
        'costPrice': 7000.0,
        'branchStocks': {
          'store_001': 100,
          'store_002': 45,
          'store_003': 30,
        },
        'category': 'Đồ uống',
      };

      final model = ProductModel.fromMap(canonicalMap);

      expect(model.branchStocks['store_001'], equals(100));
      expect(model.branchStocks['store_002'], equals(45));
      expect(model.branchStocks['store_003'], equals(30));

      final serialized = model.toMap();
      final serializedStocks = serialized['branchStocks'] as Map;
      expect(serializedStocks['store_001'], equals(100));
      expect(serializedStocks['store_002'], equals(45));
      expect(serializedStocks['store_003'], equals(30));
    });
  });
}
