import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/product.dart';

void main() {
  group('Product Filters, Search & Sorting Provider Tests', () {
    late List<Product> testCatalog;

    setUp(() {
      testCatalog = [
        // 1. In stock, Category: Đồ uống, Brand: Sabeco, Stock: 100, Price: 15000, Cost: 11000, Min: 20
        const Product(
          id: 'prod_bsg',
          name: 'Bia Saigon Special 330ml',
          code: 'BSG01',
          barcode: '893111111001',
          brand: 'Sabeco',
          model: 'Can 330ml',
          price: 15000.0,
          costPrice: 11000.0,
          branchStocks: {'branch_1': 60, 'branch_2': 40}, // Total: 100
          category: 'Đồ uống',
          category3Levels: 'Thực phẩm > Đồ uống > Bia',
          minStock: 20,
          maxStock: 300,
        ),
        // 2. Low stock (stock <= minStock), Category: Phụ kiện, Brand: Anker, Stock: 4, Price: 180000, Cost: 100000, Min: 5
        const Product(
          id: 'prod_anker',
          name: 'Cáp sạc Type-C Anker PowerLine 60W',
          code: 'ANK-CC01',
          barcode: '893222222001',
          brand: 'Anker',
          model: 'A8168',
          price: 180000.0,
          costPrice: 100000.0,
          branchStocks: {'branch_1': 3, 'branch_2': 1}, // Total: 4 <= minStock (5)
          category: 'Phụ kiện',
          category3Levels: 'Công nghệ > Phụ kiện > Dây cáp',
          minStock: 5,
          maxStock: 50,
        ),
        // 3. Out of stock (stock = 0), Category: Bánh kẹo, Brand: Glico, Stock: 0, Price: 12000, Cost: 8000, Min: 10
        const Product(
          id: 'prod_pocky',
          name: 'Bánh que Pocky Socola Hộp 40g',
          code: 'PK-SOC01',
          barcode: '893333333001',
          brand: 'Glico',
          model: 'Hộp 40g',
          price: 12000.0,
          costPrice: 8000.0,
          branchStocks: {'branch_1': 0, 'branch_2': 0}, // Total: 0
          category: 'Bánh kẹo',
          category3Levels: 'Thực phẩm > Bánh kẹo > Bánh que',
          minStock: 10,
          maxStock: 100,
        ),
        // 4. In stock, Category: Gia dụng, Brand: Paseo, Stock: 250, Price: 25000, Cost: 16000, Min: 20
        const Product(
          id: 'prod_paseo',
          name: 'Khăn giấy lụa Paseo Luxury 3 lớp',
          code: 'PS-KG01',
          barcode: '893444444001',
          brand: 'Paseo',
          model: '3 lớp 130 tờ',
          price: 25000.0,
          costPrice: 16000.0,
          branchStocks: {'branch_1': 150, 'branch_2': 100}, // Total: 250
          category: 'Gia dụng',
          category3Levels: 'Gia dụng > Giấy vệ sinh > Khăn lụa',
          minStock: 20,
          maxStock: 200,
        ),
        // 5. In stock, Category: Đồ uống, Brand: Coca-Cola, Stock: 15, Price: 10000, Cost: 7000, Min: 10
        const Product(
          id: 'prod_coke',
          name: 'Nước ngọt Coca-Cola vị nguyên bản 320ml',
          code: 'COKE-ORIG',
          barcode: '893555555001',
          brand: 'Coca-Cola',
          price: 10000.0,
          costPrice: 7000.0,
          branchStocks: {'branch_1': 10, 'branch_2': 5}, // Total: 15
          category: 'Đồ uống',
          category3Levels: 'Thực phẩm > Đồ uống > Nước ngọt có ga',
          minStock: 10,
          maxStock: 150,
        ),
        // 6. Combo product, Category: Combo, Stock: 8, Price: 80000, Cost: 55000
        const Product(
          id: 'prod_combo',
          name: 'Combo Tiệc Nhẹ (Bia + Bánh)',
          code: 'CB-PARTY01',
          barcode: '893666666001',
          brand: null,
          price: 80000.0,
          costPrice: 55000.0,
          branchStocks: {'branch_1': 5, 'branch_2': 3}, // Total: 8
          category: 'Combo',
          isCombo: true,
          comboComponents: [
            ComboComponent(
              productId: 'prod_bsg',
              productCode: 'BSG01',
              productName: 'Bia Saigon Special 330ml',
              quantity: 4,
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

    test('Initial processedProductsProvider returns all products with stockDesc sort', () async {
      final container = createContainer();

      // Listen to keep provider alive
      final sub = container.listen(processedProductsProvider, (_, __) {});
      await Future.microtask(() {});

      final data = container.read(processedProductsProvider).value!;
      expect(data.totalProducts, equals(6));
      expect(data.filteredProducts.length, equals(6));

      // Default sort is stockDesc: 250 (Paseo), 100 (Bia), 15 (Coke), 8 (Combo), 4 (Anker), 0 (Pocky)
      expect(data.filteredProducts[0].code, equals('PS-KG01'));
      expect(data.filteredProducts[1].code, equals('BSG01'));
      expect(data.filteredProducts[2].code, equals('COKE-ORIG'));
      expect(data.filteredProducts[3].code, equals('CB-PARTY01'));
      expect(data.filteredProducts[4].code, equals('ANK-CC01'));
      expect(data.filteredProducts[5].code, equals('PK-SOC01'));

      sub.close();
    });

    group('Stock Status Filter Tests', () {
      test('StockStatus.all returns all products including out-of-stock and low-stock', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productStockStatusFilterProvider.notifier).state = StockStatus.all;
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(6));
      });

      test('StockStatus.inStock filters strictly products with stock > 0', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productStockStatusFilterProvider.notifier).state = StockStatus.inStock;
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(5));
        expect(data.filteredProducts.any((p) => p.code == 'PK-SOC01'), isFalse);
        for (final p in data.filteredProducts) {
          expect(p.stock, greaterThan(0));
        }
      });

      test('StockStatus.outOfStock filters strictly products with stock <= 0', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productStockStatusFilterProvider.notifier).state = StockStatus.outOfStock;
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.code, equals('PK-SOC01'));
        expect(data.filteredProducts.first.stock, equals(0));
      });

      test('StockStatus.belowMinStock filters products with stock > 0 and stock <= minStock', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productStockStatusFilterProvider.notifier).state = StockStatus.belowMinStock;
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        // Anker has stock: 4, minStock: 5 -> isLowStock() is true
        // Bia Saigon has stock: 100, minStock: 20 -> false
        // Coke has stock: 15, minStock: 10 -> false
        // Paseo has stock: 250, minStock: 20 -> false
        // Pocky has stock: 0 -> isLowStock() is false (isOutOfStock)
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.code, equals('ANK-CC01'));
      });
    });

    group('Category Filter Tests', () {
      test('Category "All" returns all categories', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productCategoryFilterProvider.notifier).state = 'All';
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(6));
      });

      test('Category filter by exact category name', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productCategoryFilterProvider.notifier).state = 'Đồ uống';
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(2));
        expect(data.filteredProducts.map((p) => p.code), containsAll(['BSG01', 'COKE-ORIG']));
      });

      test('Category filter matches multi-level category3Levels', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        // 'Bia' is inside 'Thực phẩm > Đồ uống > Bia' for BSG01
        container.read(productCategoryFilterProvider.notifier).state = 'Bia';
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.code, equals('BSG01'));
      });
    });

    group('Brand Filter Tests', () {
      test('Brand filter null returns all brands', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productBrandFilterProvider.notifier).state = null;
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(6));
      });

      test('Brand filter by specific brand name', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productBrandFilterProvider.notifier).state = 'Sabeco';
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.code, equals('BSG01'));
      });

      test('Brand filter with non-existent brand returns empty list', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productBrandFilterProvider.notifier).state = 'Heineken';
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts, isEmpty);
        expect(data.totalProducts, equals(0));
      });
    });

    group('Sorting Option Tests', () {
      test('ProductSortOption.stockAsc sorts lowest stock first', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productSortOptionProvider.notifier).state = ProductSortOption.stockAsc;
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        final stocks = data.filteredProducts.map((p) => p.stock).toList();
        expect(stocks, equals([0, 4, 8, 15, 100, 250]));
      });

      test('ProductSortOption.nameAsc sorts alphabetically A-Z case-insensitively', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productSortOptionProvider.notifier).state = ProductSortOption.nameAsc;
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        final names = data.filteredProducts.map((p) => p.name).toList();
        final expectedNames = List<String>.from(names)
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        expect(names, equals(expectedNames));
        expect(names.length, equals(6));
      });

      test('ProductSortOption.nameDesc sorts alphabetically Z-A case-insensitively', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productSortOptionProvider.notifier).state = ProductSortOption.nameDesc;
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        final names = data.filteredProducts.map((p) => p.name).toList();
        final expectedNames = List<String>.from(names)
          ..sort((a, b) => b.toLowerCase().compareTo(a.toLowerCase()));
        expect(names, equals(expectedNames));
        expect(names.length, equals(6));
      });

      test('ProductSortOption.priceAsc sorts lowest price first', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productSortOptionProvider.notifier).state = ProductSortOption.priceAsc;
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        final prices = data.filteredProducts.map((p) => p.price).toList();
        expect(prices, equals([10000.0, 12000.0, 15000.0, 25000.0, 80000.0, 180000.0]));
      });

      test('ProductSortOption.priceDesc sorts highest price first', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productSortOptionProvider.notifier).state = ProductSortOption.priceDesc;
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        final prices = data.filteredProducts.map((p) => p.price).toList();
        expect(prices, equals([180000.0, 80000.0, 25000.0, 15000.0, 12000.0, 10000.0]));
      });
    });

    group('Smart Search Query Tests', () {
      test('Instant search by product name', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productSearchQueryProvider.notifier).state = 'saigon';
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.code, equals('BSG01'));
      });

      test('Instant search by SKU code', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productSearchQueryProvider.notifier).state = 'ank-cc01';
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.name, contains('Anker'));
      });

      test('Instant search by Barcode', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productSearchQueryProvider.notifier).state = '893444444001';
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.code, equals('PS-KG01'));
      });

      test('Instant search by Model or Brand', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        // Search by model
        container.read(productSearchQueryProvider.notifier).state = 'A8168';
        await Future.microtask(() {});

        var data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.code, equals('ANK-CC01'));

        // Search by brand
        container.read(productSearchQueryProvider.notifier).state = 'Glico';
        await Future.microtask(() {});

        data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.code, equals('PK-SOC01'));
      });

      test('Search with leading and trailing spaces is trimmed', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productSearchQueryProvider.notifier).state = '   Paseo   ';
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.code, equals('PS-KG01'));
      });
    });

    group('Multi-Filter Compound Combination Tests', () {
      test('Filter by Category + StockStatus.inStock + Sort by Price Desc', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productCategoryFilterProvider.notifier).state = 'Đồ uống';
        container.read(productStockStatusFilterProvider.notifier).state = StockStatus.inStock;
        container.read(productSortOptionProvider.notifier).state = ProductSortOption.priceDesc;
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(2));
        // BSG01 (15,000) > COKE-ORIG (10,000)
        expect(data.filteredProducts[0].code, equals('BSG01'));
        expect(data.filteredProducts[1].code, equals('COKE-ORIG'));
      });

      test('Filter by Brand + Search + StockStatus.all', () async {
        final container = createContainer();
        container.listen(processedProductsProvider, (_, __) {});
        await Future.microtask(() {});

        container.read(productBrandFilterProvider.notifier).state = 'Sabeco';
        container.read(productSearchQueryProvider.notifier).state = 'Special';
        container.read(productStockStatusFilterProvider.notifier).state = StockStatus.all;
        await Future.microtask(() {});

        final data = container.read(processedProductsProvider).value!;
        expect(data.filteredProducts.length, equals(1));
        expect(data.filteredProducts.first.code, equals('BSG01'));
      });
    });
  });
}
