import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/core/utils/combo_helper.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  group('Empirical Challenge Suite: Dynamic Branch Stocks Mapping (M1)', () {
    // -------------------------------------------------------------
    // Edge Case 1: Empty branchStocks map
    // -------------------------------------------------------------
    group('Edge Case 1: Empty branchStocks map', () {
      const emptyStockProduct = Product(
        id: 'p_empty',
        name: 'Sản phẩm chưa có dữ liệu tồn kho',
        code: 'EMPTY01',
        price: 100000,
        costPrice: 60000,
        branchStocks: {},
        category: 'Gia dụng',
      );

      test('Product.stock returns 0 when branchStocks is empty', () {
        expect(emptyStockProduct.stock, equals(0));
        expect(emptyStockProduct.isOutOfStock, isTrue);
        expect(emptyStockProduct.hasStock, isFalse);
      });

      test('stockInBranch returns 0 for any query when branchStocks is empty',
          () {
        expect(emptyStockProduct.stockInBranch('store_001'), equals(0));
        expect(emptyStockProduct.stockInBranch('store_002'), equals(0));
        expect(emptyStockProduct.stockInBranch('branch_1'), equals(0));
        expect(emptyStockProduct.stockInBranch('branch_2'), equals(0));
        expect(emptyStockProduct.stockInBranch('ĐT'), equals(0));
        expect(emptyStockProduct.stockInBranch('TB'), equals(0));
        expect(
            emptyStockProduct.stockInBranch('Chi nhánh Đông Thắng'), equals(0));
        expect(emptyStockProduct.stockInBranch('store_999'), equals(0));
        expect(emptyStockProduct.stockInBranch(''), equals(0));
        expect(emptyStockProduct.stockInBranch('   '), equals(0));
      });

      test('ProductModel parses empty branchStocks map cleanly', () {
        final rawMap = {
          'id': 'p_empty_json',
          'name': 'Empty Stock Json',
          'price': 50000.0,
          'branchStocks': <String, dynamic>{},
        };
        final model = ProductModel.fromMap(rawMap);
        expect(model.branchStocks, isEmpty);
        final serialized = model.toMap();
        expect(serialized['branchStocks'], isEmpty);
      });
    });

    // -------------------------------------------------------------
    // Edge Case 2: Legacy maps with single 'stock' field
    // -------------------------------------------------------------
    group('Edge Case 2: Legacy maps with single "stock" field fallback', () {
      test('fromMap populates store_001 with old stock and store_002 with 0',
          () {
        final legacyMap = {
          'id': 'p_legacy_single',
          'name': 'Legacy Single Stock Product',
          'code': 'LEG01',
          'price': 200000,
          'stock': 75,
          'category': 'Thiết bị',
        };

        final model = ProductModel.fromMap(legacyMap);
        expect(model.branchStocks.length, equals(2));
        expect(model.branchStocks['store_001'], equals(75));
        expect(model.branchStocks['store_002'], equals(0));

        final product = Product(
          id: model.id,
          name: model.name,
          code: model.code,
          price: model.price,
          costPrice: model.costPrice,
          branchStocks: model.branchStocks,
          category: model.category,
        );

        // Resolves via canonical ID and aliases
        expect(product.stock, equals(75));
        expect(product.stockInBranch('store_001'), equals(75));
        expect(product.stockInBranch('store_002'), equals(0));
        expect(product.stockInBranch('branch_1'), equals(75));
        expect(product.stockInBranch('branch_2'), equals(0));
        expect(product.stockInBranch('ĐT'), equals(75));
        expect(product.stockInBranch('TB'), equals(0));
        expect(product.stockInBranch('Chi nhánh Đông Thắng'), equals(75));
        expect(product.stockInBranch('Chi nhánh Thới Bình'), equals(0));
      });

      test('fromMap handles missing stock field by falling back to 0', () {
        final missingStockMap = {
          'id': 'p_missing_stock',
          'name': 'No stock field at all',
          'price': 10000,
        };
        final model = ProductModel.fromMap(missingStockMap);
        expect(model.branchStocks['store_001'], equals(0));
        expect(model.branchStocks['store_002'], equals(0));
      });
    });

    // -------------------------------------------------------------
    // Edge Case 3: Unknown store IDs & non-existent keys
    // -------------------------------------------------------------
    group('Edge Case 3: Unknown store IDs & Non-existent query keys', () {
      const productNormal = Product(
        id: 'p_norm',
        name: 'Product Normal',
        code: 'NORM01',
        price: 15000,
        costPrice: 10000,
        branchStocks: {'store_001': 10, 'store_002': 20},
        category: 'Thực phẩm',
      );

      test('Querying non-existent store IDs always returns 0', () {
        expect(productNormal.stockInBranch('store_unknown_999'), equals(0));
        expect(productNormal.stockInBranch('store_abc'), equals(0));
        expect(productNormal.stockInBranch('random_branch_key'), equals(0));
        expect(productNormal.stockInBranch(''), equals(0));
        expect(productNormal.stockInBranch('   \t\n  '), equals(0));
        expect(productNormal.stockInBranch('!@#\$%^&*()'), equals(0));
      });

      test(
          'Product containing unknown custom store IDs preserves and resolves them',
          () {
        const productCustom = Product(
          id: 'p_custom',
          name: 'Product with custom branches',
          code: 'CUST01',
          price: 50000,
          costPrice: 30000,
          branchStocks: {
            'store_unknown_999': 15,
            'branch_custom_x': 25,
          },
          category: 'Khác',
        );

        expect(productCustom.stock, equals(40));
        expect(productCustom.stockInBranch('store_unknown_999'), equals(15));
        expect(productCustom.stockInBranch('STORE_UNKNOWN_999'), equals(15));
        expect(productCustom.stockInBranch('  branch_custom_x  '), equals(25));
        // Canonical stores not present -> 0
        expect(productCustom.stockInBranch('store_001'), equals(0));
        expect(productCustom.stockInBranch('store_002'), equals(0));
      });
    });

    // -------------------------------------------------------------
    // Edge Case 4: Arbitrary store IDs (store_999, branch_5, store_abc)
    // -------------------------------------------------------------
    group('Edge Case 4: Arbitrary store IDs & dynamic formatting', () {
      test('ProductModel supports n-branch arbitrary store networks', () {
        final multiStoreMap = {
          'id': 'p_n_stores',
          'name': 'Product N Stores',
          'price': 100000.0,
          'branchStocks': {
            'store_001': 10,
            'store_002': 20,
            'store_003': 30,
            'store_004': 40,
            'store_999': 50,
            'branch_5': 60,
            'warehouse_central': 70,
          },
        };

        final model = ProductModel.fromMap(multiStoreMap);
        expect(model.branchStocks.length, equals(7));
        expect(model.branchStocks['store_999'], equals(50));
        expect(model.branchStocks['branch_5'], equals(60));
        expect(model.branchStocks['warehouse_central'], equals(70));

        final product = Product(
          id: model.id,
          name: model.name,
          code: 'N01',
          price: model.price,
          costPrice: model.costPrice,
          branchStocks: model.branchStocks,
          category: 'Mạng lưới',
        );

        expect(product.stock, equals(280));
        expect(product.stockInBranch('store_999'), equals(50));
        expect(product.stockInBranch('branch_5'), equals(60));
        expect(product.stockInBranch('warehouse_central'), equals(70));
      });
    });

    // -------------------------------------------------------------
    // Edge Case 5: Non-standard Vietnamese branch names & accents
    // -------------------------------------------------------------
    group('Edge Case 5: Non-standard Vietnamese branch names & aliases', () {
      test(
          'Resolves case-insensitive and unaccented variations of standard branches',
          () {
        const product = Product(
          id: 'p_vn',
          name: 'Vietnamese Product',
          code: 'VN01',
          price: 20000,
          costPrice: 12000,
          branchStocks: {
            'store_001': 100,
            'store_002': 200,
          },
          category: 'Việt Nam',
        );

        // Lowercase, uppercase, unaccented variations for store_001
        expect(product.stockInBranch('đông thắng'), equals(100));
        expect(product.stockInBranch('ĐÔNG THẮNG'), equals(100));
        expect(product.stockInBranch('dong thang'), equals(100));
        expect(product.stockInBranch('DONG THANG'), equals(100));
        expect(product.stockInBranch('Chi Nhánh Đông Thắng'), equals(100));
        expect(product.stockInBranch('chi nhánh đông thắng'), equals(100));
        expect(product.stockInBranch('đt'), equals(100));
        expect(product.stockInBranch('ĐT'), equals(100));
        expect(product.stockInBranch('dt'), equals(100));
        expect(product.stockInBranch('DT'), equals(100));

        // Lowercase, uppercase, unaccented, and common typo variations for store_002
        expect(product.stockInBranch('thới bình'), equals(200));
        expect(product.stockInBranch('THỚI BÌNH'), equals(200));
        expect(product.stockInBranch('thoi binh'), equals(200));
        expect(product.stockInBranch('THOI BINH'), equals(200));
        expect(product.stockInBranch('thời bình'),
            equals(200)); // Common tone mark typo
        expect(product.stockInBranch('THỜI BÌNH'), equals(200));
        expect(product.stockInBranch('Chi Nhánh Thới Bình'), equals(200));
        expect(product.stockInBranch('tb'), equals(200));
        expect(product.stockInBranch('TB'), equals(200));
      });

      test(
          'Resolves custom Vietnamese branch names when stored directly as map keys',
          () {
        const customVnProduct = Product(
          id: 'p_custom_vn',
          name: 'Custom VN Branches Product',
          code: 'CVN01',
          price: 50000,
          costPrice: 35000,
          branchStocks: {
            'Chi nhánh Cần Thơ': 30,
            'Kho Tổng Bình Dương': 45,
            'Chi nhánh TP.HCM': 60,
          },
          category: 'Kho vận',
        );

        expect(customVnProduct.stock, equals(135));
        expect(customVnProduct.stockInBranch('Chi nhánh Cần Thơ'), equals(30));
        expect(customVnProduct.stockInBranch('chi nhánh cần thơ'), equals(30));
        expect(customVnProduct.stockInBranch('  Kho Tổng Bình Dương  '),
            equals(45));
        expect(customVnProduct.stockInBranch('Chi nhánh TP.HCM'), equals(60));
        expect(customVnProduct.stockInBranch('chi nhánh tp.hcm'), equals(60));
      });
    });

    // -------------------------------------------------------------
    // Edge Case 6: Negative numbers & extreme bounds
    // -------------------------------------------------------------
    group('Edge Case 6: Negative stock numbers and extreme bounds', () {
      test(
          'Handles negative stock in single branch while total remains positive',
          () {
        const netPositiveProd = Product(
          id: 'p_net_pos',
          name: 'Net Positive Stock',
          code: 'NETP01',
          price: 30000,
          costPrice: 20000,
          branchStocks: {'store_001': -5, 'store_002': 15},
          category: 'Hàng hóa',
        );

        expect(netPositiveProd.stock, equals(10));
        expect(netPositiveProd.stockInBranch('store_001'), equals(-5));
        expect(netPositiveProd.stockInBranch('store_002'), equals(15));
        expect(netPositiveProd.isOutOfStock, isFalse);
        expect(netPositiveProd.hasStock, isTrue);
      });

      test('Handles negative total stock across all branches', () {
        const netNegativeProd = Product(
          id: 'p_net_neg',
          name: 'Net Negative Stock',
          code: 'NETN01',
          price: 30000,
          costPrice: 20000,
          branchStocks: {'store_001': -8, 'store_002': -4},
          category: 'Hàng hóa',
        );

        expect(netNegativeProd.stock, equals(-12));
        expect(netNegativeProd.stockInBranch('store_001'), equals(-8));
        expect(netNegativeProd.stockInBranch('store_002'), equals(-4));
        expect(netNegativeProd.isOutOfStock, isTrue);
        expect(netNegativeProd.hasStock, isFalse);
        expect(netNegativeProd.isLowStock(), isFalse,
            reason: 'Negative stock is considered Out of Stock, not Low Stock');
      });

      test(
          'ComboHelper returns 0 available combo stock if any child component is negative',
          () {
        const comp1 = Product(
          id: 'c1',
          name: 'Component 1',
          code: 'C1',
          price: 10000,
          costPrice: 5000,
          branchStocks: {'store_001': -5, 'store_002': 10},
          category: 'Linh kiện',
        );
        const comp2 = Product(
          id: 'c2',
          name: 'Component 2',
          code: 'C2',
          price: 15000,
          costPrice: 8000,
          branchStocks: {'store_001': 20, 'store_002': 20},
          category: 'Linh kiện',
        );
        const combo = Product(
          id: 'cb_neg',
          name: 'Combo With Negative Child',
          code: 'CBN01',
          price: 30000,
          costPrice: 15000,
          branchStocks: {'store_001': 0, 'store_002': 0},
          category: 'Combo',
          isCombo: true,
          comboComponents: [
            ComboComponent(
              productId: 'c1',
              productCode: 'C1',
              productName: 'Component 1',
              quantity: 1,
              costPrice: 5000,
            ),
            ComboComponent(
              productId: 'c2',
              productCode: 'C2',
              productName: 'Component 2',
              quantity: 1,
              costPrice: 8000,
            ),
          ],
        );

        final allProds = [comp1, comp2, combo];

        // store_001: comp1 is -5, comp2 is 20 -> available combo must be 0 (not negative or crashing)
        final comboStockStore1 = ComboHelper.getAvailableStock(
          product: combo,
          branchId: 'store_001',
          allProducts: allProds,
        );
        expect(comboStockStore1, equals(0));

        // store_002: comp1 is 10, comp2 is 20 -> available combo = 10
        final comboStockStore2 = ComboHelper.getAvailableStock(
          product: combo,
          branchId: 'store_002',
          allProducts: allProds,
        );
        expect(comboStockStore2, equals(10));
      });
    });

    // -------------------------------------------------------------
    // Edge Case 7: Firebase RTDB Malformed & Mixed Data Types
    // -------------------------------------------------------------
    group('Edge Case 7: Firebase RTDB Malformed & Mixed Data Types', () {
      test(
          'ProductModel.fromMap parses stringified numbers, doubles, and ignores invalid types in branchStocks',
          () {
        final dirtyMap = {
          'id': 'p_dirty',
          'name': 'Dirty RTDB Record',
          'price': 45000.0,
          'costPrice': 30000.0,
          'branchStocks': {
            'store_001': '15', // string integer
            'store_002': 22.8, // double
            'store_003': -10, // negative integer
            'store_004': null, // null value
            'store_005': 'invalid_string', // non-numeric string
            'store_006': true, // boolean
          },
        };

        final model = ProductModel.fromMap(dirtyMap);
        expect(model.id, equals('p_dirty'));
        expect(model.branchStocks['store_001'], equals(15));
        expect(model.branchStocks['store_002'], equals(22));
        expect(model.branchStocks['store_003'], equals(-10));
        expect(model.branchStocks['store_004'], equals(0));
        expect(model.branchStocks['store_005'], equals(0));
        expect(model.branchStocks['store_006'], equals(0));
      });

      test('ProductModel.fromMap handles branchStocks being non-Map gracefully',
          () {
        final corruptMap = {
          'id': 'p_corrupt',
          'name': 'Corrupt BranchStocks',
          'price': 10000,
          'stock': 12,
          'branchStocks': 'this is a string, not a map',
        };

        final model = ProductModel.fromMap(corruptMap);
        expect(model.branchStocks['store_001'], equals(12));
        expect(model.branchStocks['store_002'], equals(0));
      });
    });

    // -------------------------------------------------------------
    // Edge Case 8: ProductTile Widget Stress Testing
    // -------------------------------------------------------------
    group('Edge Case 8: ProductTile Widget Stress Testing', () {
      testWidgets(
          'ProductTile handles empty branchStocks without throwing error',
          (tester) async {
        const product = Product(
          id: 'p_ui_empty',
          name: 'Sản phẩm không có kho',
          code: 'UI01',
          price: 50000,
          costPrice: 30000,
          branchStocks: {},
          category: 'Test',
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductTile(product: product),
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([product])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sản phẩm không có kho'), findsOneWidget);
        expect(find.text('Tồn: 0'), findsOneWidget);
        expect(find.text('Hết hàng'), findsOneWidget);
        // Does not show storefront row when branchStocks is empty
        expect(find.byIcon(Icons.storefront_outlined), findsNothing);
      });

      testWidgets(
          'ProductTile formats complex multi-branch network badges correctly',
          (tester) async {
        const product = Product(
          id: 'p_ui_multi',
          name: 'Sản phẩm mạng lưới lớn',
          code: 'UINET01',
          price: 75000,
          costPrice: 50000,
          branchStocks: {
            'store_001': 10,
            'store_002': 20,
            'store_003': 30,
            'store_999': 5,
            'branch_10': 15,
            'Chi nhánh An Giang': 8,
            'Kho Tổng': 50,
          },
          category: 'Mạng lưới',
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductTile(product: product),
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([product])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sản phẩm mạng lưới lớn'), findsOneWidget);
        expect(find.text('Tồn: 138'), findsOneWidget);
        expect(find.text('Còn hàng'), findsOneWidget);

        // Formatted line should contain:
        // ĐT: 10 | TB: 20 | CN3: 30 | CN999: 5 | CN10: 15 | AG: 8 | Kho Tổng: 50
        expect(
          find.textContaining(
              'ĐT: 10 | TB: 20 | CN3: 30 | CN999: 5 | CN10: 15 | AG: 8 | Kho Tổng: 50'),
          findsOneWidget,
        );
      });

      testWidgets(
          'ProductTile renders negative stock and extreme large numbers gracefully',
          (tester) async {
        const product = Product(
          id: 'p_extreme',
          name: 'Sản phẩm số lượng cực hạn',
          code: 'EXT01',
          price: 150000,
          costPrice: 90000,
          branchStocks: {
            'store_001': -12,
            'store_002': 1000000,
          },
          category: 'Cực hạn',
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductTile(product: product),
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([product])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sản phẩm số lượng cực hạn'), findsOneWidget);
        expect(find.text('Tồn: 999988'), findsOneWidget);
        expect(find.text('Còn hàng'), findsOneWidget);
        expect(find.textContaining('ĐT: -12 | TB: 1000000'), findsOneWidget);
      });
    });

    // -------------------------------------------------------------
    // Edge Case 9: Product.copyWith & Map Immutability
    // -------------------------------------------------------------
    group('Edge Case 9: Product.copyWith & Map Immutability', () {
      test('copyWith creates isolated copy of branchStocks', () {
        const original = Product(
          id: 'p_immut',
          name: 'Immutable Product',
          code: 'IMM01',
          price: 10000,
          costPrice: 5000,
          branchStocks: {'store_001': 10, 'store_002': 20},
          category: 'Kiểm thử',
        );

        final updated = original.copyWith(
          branchStocks: {'store_001': 30, 'store_002': 40, 'store_003': 50},
        );

        expect(original.branchStocks['store_001'], equals(10));
        expect(original.branchStocks['store_002'], equals(20));
        expect(original.branchStocks.containsKey('store_003'), isFalse);
        expect(original.stock, equals(30));

        expect(updated.branchStocks['store_001'], equals(30));
        expect(updated.branchStocks['store_002'], equals(40));
        expect(updated.branchStocks['store_003'], equals(50));
        expect(updated.stock, equals(120));
      });
    });

    // -------------------------------------------------------------
    // Edge Case 10: ComboHelper Boundary Conditions
    // -------------------------------------------------------------
    group('Edge Case 10: ComboHelper Boundary Conditions', () {
      test(
          'ComboHelper returns 0 if combo component quantity is <= 0 or child is missing',
          () {
        const combo = Product(
          id: 'cb_invalid_spec',
          name: 'Invalid Combo Spec',
          code: 'CBINV01',
          price: 100000,
          costPrice: 60000,
          branchStocks: {'store_001': 0},
          category: 'Combo',
          isCombo: true,
          comboComponents: [
            ComboComponent(
              productId: 'non_existent_child',
              productCode: 'NONE',
              productName: 'Ghost Component',
              quantity: 2,
              costPrice: 10000,
            ),
          ],
        );

        final available = ComboHelper.getAvailableStock(
          product: combo,
          branchId: 'store_001',
          allProducts: [combo],
        );
        expect(available, equals(0));
      });

      test('ComboHelper returns standard stock if product is not combo', () {
        const nonCombo = Product(
          id: 'p_non_combo',
          name: 'Regular Product',
          code: 'REG01',
          price: 50000,
          costPrice: 30000,
          branchStocks: {'store_001': 42},
          category: 'Thường',
          isCombo: false,
        );

        expect(
            ComboHelper.getAvailableStock(
              product: nonCombo,
              branchId: 'store_001',
              allProducts: [nonCombo],
            ),
            equals(42));

        expect(
            ComboHelper.getTotalAvailableStock(
              product: nonCombo,
              allProducts: [nonCombo],
            ),
            equals(42));
      });
    });
  });
}
