import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/product_unit.dart';

import '../../fixtures/mock_product_data.dart';

void main() {
  group('Product Entity Unit Tests', () {
    test('Total stock calculates aggregate sum of all branch stocks', () {
      final product = MockProductData.createProduct(
        branchStocks: {'branch_1': 15, 'branch_2': 25, 'branch_3': 10},
      );

      expect(product.stock, equals(50));
    });

    test('stockInBranch returns specific branch stock with dual-key and alias resolution', () {
      final legacyProduct = MockProductData.createProduct(
        branchStocks: {'branch_1': 12, 'branch_2': 8},
      );

      // Legacy key lookup
      expect(legacyProduct.stockInBranch('branch_1'), equals(12));
      expect(legacyProduct.stockInBranch('branch_2'), equals(8));
      // Canonical store ID lookup on legacy map
      expect(legacyProduct.stockInBranch('store_001'), equals(12));
      expect(legacyProduct.stockInBranch('store_002'), equals(8));
      // Vietnamese name and short code alias lookup
      expect(legacyProduct.stockInBranch('Chi nhánh Đông Thắng'), equals(12));
      expect(legacyProduct.stockInBranch('Chi nhánh Thới Bình'), equals(8));
      expect(legacyProduct.stockInBranch('ĐT'), equals(12));
      expect(legacyProduct.stockInBranch('TB'), equals(8));
      expect(legacyProduct.stockInBranch('branch_unknown'), equals(0));
      expect(legacyProduct.stockInBranch(''), equals(0));

      final canonicalProduct = MockProductData.createProduct(
        branchStocks: {'store_001': 25, 'store_002': 15},
      );

      // Canonical store ID lookup
      expect(canonicalProduct.stockInBranch('store_001'), equals(25));
      expect(canonicalProduct.stockInBranch('store_002'), equals(15));
      // Legacy key lookup on canonical map
      expect(canonicalProduct.stockInBranch('branch_1'), equals(25));
      expect(canonicalProduct.stockInBranch('branch_2'), equals(15));
      // Vietnamese name and short code alias lookup
      expect(canonicalProduct.stockInBranch('Chi nhánh Đông Thắng'), equals(25));
      expect(canonicalProduct.stockInBranch('Chi nhánh Thới Bình'), equals(15));
      expect(canonicalProduct.stockInBranch('ĐT'), equals(25));
      expect(canonicalProduct.stockInBranch('TB'), equals(15));
    });

    test('isOutOfStock returns true only when total stock is zero or negative', () {
      final outOfStockProd = MockProductData.createProduct(
        branchStocks: {'branch_1': 0, 'branch_2': 0},
      );
      final negativeStockProd = MockProductData.createProduct(
        branchStocks: {'branch_1': -2, 'branch_2': 0},
      );
      final inStockProd = MockProductData.createProduct(
        branchStocks: {'branch_1': 1, 'branch_2': 0},
      );

      expect(outOfStockProd.isOutOfStock, isTrue);
      expect(outOfStockProd.hasStock, isFalse);

      expect(negativeStockProd.isOutOfStock, isTrue);
      expect(negativeStockProd.hasStock, isFalse);

      expect(inStockProd.isOutOfStock, isFalse);
      expect(inStockProd.hasStock, isTrue);
    });

    test('isLowStock evaluates correctly against explicit minStock', () {
      final lowStockProd = MockProductData.createProduct(
        branchStocks: {'branch_1': 4, 'branch_2': 1}, // Total: 5
        minStock: 10,
      );
      final exactMinProd = MockProductData.createProduct(
        branchStocks: {'branch_1': 5, 'branch_2': 5}, // Total: 10
        minStock: 10,
      );
      final safeStockProd = MockProductData.createProduct(
        branchStocks: {'branch_1': 6, 'branch_2': 5}, // Total: 11
        minStock: 10,
      );
      final outOfStockProd = MockProductData.createProduct(
        branchStocks: {'branch_1': 0, 'branch_2': 0}, // Total: 0
        minStock: 10,
      );

      expect(lowStockProd.isLowStock(), isTrue,
          reason: 'Stock 5 <= minStock 10 and > 0');
      expect(exactMinProd.isLowStock(), isTrue,
          reason: 'Stock 10 == minStock 10 and > 0');
      expect(safeStockProd.isLowStock(), isFalse,
          reason: 'Stock 11 > minStock 10');
      expect(outOfStockProd.isLowStock(), isFalse,
          reason: 'Stock 0 is out of stock, not low stock');
    });

    test('isLowStock falls back to fallbackMin when minStock is null', () {
      final productWithoutMinStock = MockProductData.createProduct(
        branchStocks: {'branch_1': 3, 'branch_2': 1}, // Total: 4
        minStock: null,
      );
      final productWithStock6 = MockProductData.createProduct(
        branchStocks: {'branch_1': 3, 'branch_2': 3}, // Total: 6
        minStock: null,
      );

      // Default fallbackMin is 5
      expect(productWithoutMinStock.isLowStock(), isTrue,
          reason: 'Stock 4 <= default fallback 5');
      expect(productWithStock6.isLowStock(), isFalse,
          reason: 'Stock 6 > default fallback 5');

      // Custom fallbackMin
      expect(productWithStock6.isLowStock(8), isTrue,
          reason: 'Stock 6 <= custom fallback 8');
    });

    test('copyWith properly updates all new fields including units, minStock, maxStock', () {
      final initialProduct = MockProductData.createProduct(
        id: 'prod_test',
        name: 'Initial Name',
        code: 'INIT01',
        price: 50000.0,
        costPrice: 30000.0,
        branchStocks: {'branch_1': 10},
        category: 'Test Category',
        minStock: 5,
        maxStock: 50,
        units: const [],
      );

      const newUnit = ProductUnit(
        id: 'unit_hop',
        unitName: 'Hộp',
        conversionRate: 10,
        price: 450000.0,
        costPrice: 280000.0,
      );

      final updatedProduct = initialProduct.copyWith(
        name: 'Updated Name',
        minStock: 20,
        maxStock: 100,
        units: [newUnit],
        branchStocks: {'branch_1': 15, 'branch_2': 10},
      );

      expect(updatedProduct.id, equals('prod_test'));
      expect(updatedProduct.name, equals('Updated Name'));
      expect(updatedProduct.code, equals('INIT01'));
      expect(updatedProduct.minStock, equals(20));
      expect(updatedProduct.maxStock, equals(100));
      expect(updatedProduct.units.length, equals(1));
      expect(updatedProduct.units.first.unitName, equals('Hộp'));
      expect(updatedProduct.stock, equals(25));
    });

    test('Product supports combo items and multiple units simultaneously', () {
      final sampleUnits = MockProductData.sampleBeverageUnits();
      const comboComp = ComboComponent(
        productId: 'comp_01',
        productCode: 'CP01',
        productName: 'Component Product',
        quantity: 2,
        costPrice: 5000.0,
      );

      final product = Product(
        id: 'prod_combo_units',
        name: 'Special Combo Box',
        code: 'SCB01',
        price: 120000.0,
        costPrice: 80000.0,
        branchStocks: const {'branch_1': 10},
        category: 'Combo',
        isCombo: true,
        comboComponents: const [comboComp],
        minStock: 5,
        maxStock: 50,
        units: sampleUnits,
      );

      expect(product.isCombo, isTrue);
      expect(product.comboComponents.length, equals(1));
      expect(product.units.length, equals(3));
      expect(product.units[1].conversionRate, equals(6));
      expect(product.units[2].conversionRate, equals(24));
    });
  });
}
