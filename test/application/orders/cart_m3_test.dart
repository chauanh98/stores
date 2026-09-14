import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/product.dart';

void main() {
  group('Milestone 3: allowSale Domain & Model Tests', () {
    test('Product entity has allowSale default true and isActive getter', () {
      const pDefault = Product(
        id: 'p1',
        name: 'Product 1',
        code: 'P01',
        price: 10000,
        costPrice: 7000,
        branchStocks: {'branch_1': 10},
        category: 'Food',
      );
      expect(pDefault.allowSale, isTrue);
      expect(pDefault.isActive, isTrue);

      final pDisabled = pDefault.copyWith(allowSale: false);
      expect(pDisabled.allowSale, isFalse);
      expect(pDisabled.isActive, isFalse);
    });

    test('ProductModel serializes allowSale to Map', () {
      const model = ProductModel(
        id: 'p1',
        name: 'Product 1',
        code: 'P01',
        price: 10000,
        costPrice: 7000,
        branchStocks: {'branch_1': 10},
        category: 'Food',
        allowSale: false,
      );

      final map = model.toMap();
      expect(map['allowSale'], isFalse);
    });

    test('ProductModel fromMap deserializes allowSale with backward compatibility', () {
      // 1. New format with explicit allowSale: false
      final mapNew = {
        'id': 'p1',
        'name': 'P1',
        'allowSale': false,
      };
      final m1 = ProductModel.fromMap(mapNew);
      expect(m1.allowSale, isFalse);

      // 2. Legacy format with isActive: false
      final mapLegacy = {
        'id': 'p2',
        'name': 'P2',
        'isActive': false,
      };
      final m2 = ProductModel.fromMap(mapLegacy);
      expect(m2.allowSale, isFalse);

      // 3. Fallback when neither field is present (defaults to true)
      final mapEmpty = {
        'id': 'p3',
        'name': 'P3',
      };
      final m3 = ProductModel.fromMap(mapEmpty);
      expect(m3.allowSale, isTrue);
    });
  });

  group('Milestone 3: CartNotifier & POS Cart Locking Tests', () {
    late CartNotifier cartNotifier;

    setUp(() {
      cartNotifier = CartNotifier();
    });

    test('CartNotifier accepts active products with allowSale: true', () {
      const activeProduct = Product(
        id: 'active_01',
        name: 'Sản phẩm đang bán',
        code: 'ACT01',
        price: 50000,
        costPrice: 30000,
        branchStocks: {'branch_1': 10},
        category: 'Drinks',
        allowSale: true,
      );

      cartNotifier.addToCart(activeProduct);
      expect(cartNotifier.state.containsKey('active_01'), isTrue);
      expect(cartNotifier.state['active_01']!.quantity, equals(1));
    });

    test('CartNotifier strictly rejects disabled products with allowSale: false', () {
      const disabledProduct = Product(
        id: 'disabled_01',
        name: 'Sản phẩm ngừng kinh doanh',
        code: 'DIS01',
        price: 50000,
        costPrice: 30000,
        branchStocks: {'branch_1': 10},
        category: 'Drinks',
        allowSale: false,
      );

      cartNotifier.addToCart(disabledProduct);
      expect(cartNotifier.state.containsKey('disabled_01'), isFalse);
      expect(cartNotifier.state.isEmpty, isTrue);
    });
  });
}
