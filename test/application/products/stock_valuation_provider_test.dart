import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/product.dart';

void main() {
  group('Stock Valuation & Product Summary Metrics Tests', () {
    late List<Product> testCatalog;

    setUp(() {
      testCatalog = [
        // Standard Product 1: Stock = 100, CostPrice = 11,000 -> Value = 1,100,000
        const Product(
          id: 'p1',
          name: 'Bia Saigon Special',
          code: 'BSG01',
          barcode: '893001',
          brand: 'Sabeco',
          price: 15000.0,
          costPrice: 11000.0,
          branchStocks: {'b1': 60, 'b2': 40},
          category: 'Đồ uống',
          isCombo: false,
        ),
        // Standard Product 2: Stock = 4, CostPrice = 100,000 -> Value = 400,000
        const Product(
          id: 'p2',
          name: 'Cáp sạc Anker Type-C',
          code: 'ANK01',
          barcode: '893002',
          brand: 'Anker',
          price: 180000.0,
          costPrice: 100000.0,
          branchStocks: {'b1': 3, 'b2': 1},
          category: 'Phụ kiện',
          isCombo: false,
        ),
        // Standard Product 3: Stock = 0, CostPrice = 8,000 -> Value = 0
        const Product(
          id: 'p3',
          name: 'Bánh que Pocky',
          code: 'PK01',
          barcode: '893003',
          brand: 'Glico',
          price: 12000.0,
          costPrice: 8000.0,
          branchStocks: {'b1': 0, 'b2': 0},
          category: 'Bánh kẹo',
          isCombo: false,
        ),
        // Standard Product 4: Stock = 200, CostPrice = 15,000 -> Value = 3,000,000
        const Product(
          id: 'p4',
          name: 'Khăn giấy Paseo',
          code: 'PS01',
          barcode: '893004',
          brand: 'Paseo',
          price: 25000.0,
          costPrice: 15000.0,
          branchStocks: {'b1': 120, 'b2': 80},
          category: 'Gia dụng',
          isCombo: false,
        ),
        // Combo Product: Stock = 10, CostPrice = 50,000 (Combo should be EXCLUDED from physical inventory cost)
        const Product(
          id: 'p_combo',
          name: 'Combo Tiệc Nhẹ',
          code: 'CB01',
          barcode: '893005',
          brand: null,
          price: 80000.0,
          costPrice: 50000.0,
          branchStocks: {'b1': 6, 'b2': 4}, // Stock = 10
          category: 'Combo',
          isCombo: true,
          comboComponents: [
            ComboComponent(
              productId: 'p1',
              productCode: 'BSG01',
              productName: 'Bia Saigon Special',
              quantity: 2,
              costPrice: 11000.0,
            ),
          ],
        ),
      ];
    });

    ProviderContainer createContainer({List<Product>? products}) {
      final catalog = products ?? testCatalog;
      final container = ProviderContainer(
        overrides: [
          productListProvider.overrideWith((ref) => Stream.value(catalog)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('Total products count calculation', () async {
      final container = createContainer();
      container.listen(processedProductsProvider, (_, __) {});
      await Future.microtask(() {});

      final data = container.read(processedProductsProvider).value!;
      expect(data.totalProducts, equals(5));
    });

    test('Total stock accurately sums all items across branches', () async {
      final container = createContainer();
      container.listen(processedProductsProvider, (_, __) {});
      await Future.microtask(() {});

      final data = container.read(processedProductsProvider).value!;
      // p1: 100 + p2: 4 + p3: 0 + p4: 200 + p_combo: 10 = 314
      expect(data.totalStock, equals(314));
    });

    test('Physical stock cost value calculation STRICTLY excludes Combo products', () async {
      final container = createContainer();
      container.listen(processedProductsProvider, (_, __) {});
      await Future.microtask(() {});

      final data = container.read(processedProductsProvider).value!;
      // Expected valuation:
      // p1: 100 * 11,000 = 1,100,000
      // p2: 4 * 100,000   = 400,000
      // p3: 0 * 8,000     = 0
      // p4: 200 * 15,000  = 3,000,000
      // p_combo (isCombo == true): EXCLUDED (would have added 10 * 50,000 = 500,000)
      // Total = 1,100,000 + 400,000 + 0 + 3,000,000 = 4,500,000.0
      expect(data.totalCostValue, equals(4500000.0));
    });

    test('All Combo catalog yields 0.0 inventory cost value', () async {
      final onlyCombos = [
        const Product(
          id: 'combo_1',
          name: 'Combo A',
          code: 'CBA',
          price: 100000.0,
          costPrice: 70000.0,
          branchStocks: {'b1': 5},
          category: 'Combo',
          isCombo: true,
        ),
        const Product(
          id: 'combo_2',
          name: 'Combo B',
          code: 'CBB',
          price: 150000.0,
          costPrice: 90000.0,
          branchStocks: {'b1': 10},
          category: 'Combo',
          isCombo: true,
        ),
      ];

      final container = createContainer(products: onlyCombos);
      container.listen(processedProductsProvider, (_, __) {});
      await Future.microtask(() {});

      final data = container.read(processedProductsProvider).value!;
      expect(data.totalProducts, equals(2));
      expect(data.totalStock, equals(15));
      expect(data.totalCostValue, equals(0.0));
    });

    test('Dynamic categories extraction retains "All" as first entry and unique sorted list', () async {
      final container = createContainer();
      container.listen(processedProductsProvider, (_, __) {});
      await Future.microtask(() {});

      final data = container.read(processedProductsProvider).value!;
      // Categories in test catalog: 'Đồ uống', 'Phụ kiện', 'Bánh kẹo', 'Gia dụng', 'Combo'
      expect(data.categories.first, equals('All'));
      expect(data.categories, containsAll(['All', 'Bánh kẹo', 'Combo', 'Gia dụng', 'Phụ kiện', 'Đồ uống']));
      // Verify sorted order (excluding 'All' at index 0)
      final subList = data.categories.sublist(1);
      final sortedSubList = List<String>.from(subList)..sort();
      expect(subList, equals(sortedSubList));
    });

    test('Dynamic brands extraction extracts unique sorted non-empty brands', () async {
      final container = createContainer();
      container.listen(processedProductsProvider, (_, __) {});
      await Future.microtask(() {});

      final data = container.read(processedProductsProvider).value!;
      // Brands in test catalog: 'Sabeco', 'Anker', 'Glico', 'Paseo' (combo has null brand)
      expect(data.brands, equals(['Anker', 'Glico', 'Paseo', 'Sabeco']));
    });

    test('Metrics dynamically recalculate when filter is applied', () async {
      final container = createContainer();
      container.listen(processedProductsProvider, (_, __) {});
      await Future.microtask(() {});

      // Filter by category 'Đồ uống'
      container.read(productCategoryFilterProvider.notifier).state = 'Đồ uống';
      await Future.microtask(() {});

      final data = container.read(processedProductsProvider).value!;
      expect(data.totalProducts, equals(1));
      expect(data.totalStock, equals(100));
      expect(data.totalCostValue, equals(1100000.0));

      // Filter options remain complete for the dropdowns
      expect(data.categories, containsAll(['All', 'Đồ uống', 'Phụ kiện']));
      expect(data.brands, containsAll(['Anker', 'Sabeco']));
    });

    test('showCostPriceProvider initial state is false and toggles reactively', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Default state is false
      expect(container.read(showCostPriceProvider), isFalse);

      // Toggle state to true
      container.read(showCostPriceProvider.notifier).state = true;
      expect(container.read(showCostPriceProvider), isTrue);

      // Toggle back to false
      container.read(showCostPriceProvider.notifier).state = false;
      expect(container.read(showCostPriceProvider), isFalse);
    });

    test('Empty catalog handles metrics safely without divide-by-zero or crash', () async {
      final container = createContainer(products: const []);
      container.listen(processedProductsProvider, (_, __) {});
      await Future.microtask(() {});

      final data = container.read(processedProductsProvider).value!;
      expect(data.totalProducts, equals(0));
      expect(data.totalStock, equals(0));
      expect(data.totalCostValue, equals(0.0));
      expect(data.categories, equals(['All']));
      expect(data.brands, isEmpty);
      expect(data.filteredProducts, isEmpty);
    });
  });
}
