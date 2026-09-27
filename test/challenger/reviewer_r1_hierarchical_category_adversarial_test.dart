import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/products/pages/categories_management_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/products/widgets/category_filter_bottom_sheet.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mockAdmin = UserAccount(
    username: 'admin_test',
    displayName: 'Admin Test',
    role: 'admin',
    storeId: 'store_001',
  );

  group('Adversarial Test 1: Circular Category Hierarchy & Self-Loops', () {
    test('processedProductsProvider handles category cycle without StackOverflow', () async {
      final cyclicCategories = <Category>[
        const Category(id: 'cat_a', name: 'Category A', parentId: 'cat_b'),
        const Category(id: 'cat_b', name: 'Category B', parentId: 'cat_a'),
      ];

      final products = <Product>[
        const Product(
          id: 'p1',
          code: 'SP01',
          name: 'Product 1',
          category: 'Category A',
          price: 10000,
          costPrice: 5000,
          branchStocks: {'branch_1': 10},
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          categoryListProvider.overrideWith((ref) => Stream.value(cyclicCategories)),
          productListProvider.overrideWith((ref) => Stream.value(products)),
          allStoresProductsProvider.overrideWith((ref) => Stream.value(products)),
        ],
      );
      addTearDown(container.dispose);

      // Select Category A which participates in a cycle
      container.read(productCategoryFilterProvider.notifier).state = 'Category A';

      final asyncData = await container.read(productListProvider.future);
      expect(asyncData.length, 1);

      final processed = container.read(processedProductsProvider);
      expect(processed.value?.filteredProducts.length, 1);
    });

    test('processedProductsProvider handles self-loop (cat.parentId == cat.id)', () async {
      final selfLoopCategories = <Category>[
        const Category(id: 'cat_self', name: 'Self Loop', parentId: 'cat_self'),
      ];

      final products = <Product>[
        const Product(
          id: 'p1',
          code: 'SP01',
          name: 'Product 1',
          category: 'Self Loop',
          price: 10000,
          costPrice: 5000,
          branchStocks: {'branch_1': 10},
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          categoryListProvider.overrideWith((ref) => Stream.value(selfLoopCategories)),
          productListProvider.overrideWith((ref) => Stream.value(products)),
          allStoresProductsProvider.overrideWith((ref) => Stream.value(products)),
        ],
      );
      addTearDown(container.dispose);

      container.read(productCategoryFilterProvider.notifier).state = 'Self Loop';

      await container.read(productListProvider.future);
      final processed = container.read(processedProductsProvider);
      expect(processed.value?.filteredProducts.length, 1);
    });
  });

  group('Adversarial Test 2: Vietnamese Search without Diacritics', () {
    testWidgets('CategoryFilterBottomSheet finds "Nước giải khát" when searching "nuoc"', (tester) async {
      final categories = <Category>[
        const Category(id: 'c1', name: 'Nước giải khát'),
        const Category(id: 'c2', name: 'Bánh kẹo'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryListProvider.overrideWith((ref) => Stream.value(categories)),
            productListProvider.overrideWith((ref) => Stream.value(const <Product>[])),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CategoryFilterBottomSheet(
                currentSelectedCategory: 'All',
                onCategorySelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Type "nuoc" without diacritics
      await tester.enterText(find.byKey(const Key('category_search_field')), 'nuoc');
      await tester.pumpAndSettle();

      // Expect to find "Nước giải khát"
      expect(find.text('Nước giải khát'), findsOneWidget);
    });
  });

  group('Adversarial Test 3: Deep Nesting Layout on 320px Screen', () {
    testWidgets('CategoriesManagementPage does not overflow on 320px viewport with 6 levels of nesting', (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final deepCategories = <Category>[
        const Category(id: 'lvl1', name: 'Level 1 Root'),
        const Category(id: 'lvl2', name: 'Level 2 Child', parentId: 'lvl1'),
        const Category(id: 'lvl3', name: 'Level 3 Child', parentId: 'lvl2'),
        const Category(id: 'lvl4', name: 'Level 4 Child', parentId: 'lvl3'),
        const Category(id: 'lvl5', name: 'Level 5 Child', parentId: 'lvl4'),
        const Category(id: 'lvl6', name: 'Level 6 Long Deep Subcategory', parentId: 'lvl5'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryListProvider.overrideWith((ref) => Stream.value(deepCategories)),
            productListProvider.overrideWith((ref) => Stream.value(const <Product>[])),
          ],
          child: const MaterialApp(
            home: CategoriesManagementPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expand all levels with scroll visibility
      for (final id in ['lvl1', 'lvl2', 'lvl3', 'lvl4', 'lvl5']) {
        final toggle = find.byKey(Key('toggle_category_$id'));
        if (toggle.evaluate().isNotEmpty) {
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
        }
      }

      // Check that tester.takeException() is null (no RenderFlex overflow)
      expect(tester.takeException(), isNull);
    });
  });

  group('Adversarial Test 4: Subcategory Filter Name on ProductsPage Filter Bar', () {
    testWidgets('ProductsPage filter bar displays subcategory name instead of "Tất cả nhóm hàng"', (tester) async {
      final categories = <Category>[
        const Category(id: 'parent_c', name: 'Đồ uống'),
        const Category(id: 'child_c', name: 'Nước ngọt', parentId: 'parent_c'),
      ];

      final products = <Product>[
        const Product(
          id: 'p1',
          code: 'SP01',
          name: 'Coca Cola',
          category: 'Đồ uống',
          category3Levels: 'Đồ uống >> Nước ngọt',
          price: 10000,
          costPrice: 5000,
          branchStocks: {'branch_1': 10},
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdmin)),
            categoryListProvider.overrideWith((ref) => Stream.value(categories)),
            allStoresProductsProvider.overrideWith((ref) => Stream.value(products)),
            productListProvider.overrideWith((ref) => Stream.value(products)),
            productCategoryFilterProvider.overrideWith((ref) => 'Nước ngọt'),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: ProductsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Filter bar should display "Nước ngọt", NOT fallback to "Tất cả nhóm hàng"
      expect(find.text('Nước ngọt'), findsAtLeastNWidgets(1));
    });
  });

  group('Adversarial Test 5: Cyclic categories in UI Search and Management', () {
    testWidgets('CategoriesManagementPage renders and searches without hanging on cyclic parentId', (tester) async {
      final cyclicCategories = <Category>[
        const Category(id: 'cat_x', name: 'Cycle Cat X', parentId: 'cat_y'),
        const Category(id: 'cat_y', name: 'Cycle Cat Y', parentId: 'cat_x'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryListProvider.overrideWith((ref) => Stream.value(cyclicCategories)),
            productListProvider.overrideWith((ref) => Stream.value(const <Product>[])),
          ],
          child: const MaterialApp(
            home: CategoriesManagementPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Because of orphan-safety, both nodes are displayed as roots
      expect(find.text('Cycle Cat X'), findsOneWidget);
      expect(find.text('Cycle Cat Y'), findsOneWidget);

      // Search field should safely build category path without hanging in while loop
      await tester.enterText(find.byType(TextField), 'Cycle');
      await tester.pumpAndSettle();

      expect(find.text('Cycle Cat X'), findsOneWidget);
      expect(find.text('Cycle Cat Y'), findsOneWidget);
    });

    testWidgets('CategoryFilterBottomSheet renders and searches without hanging on cyclic parentId', (tester) async {
      final cyclicCategories = <Category>[
        const Category(id: 'cat_x', name: 'Cycle Cat X', parentId: 'cat_y'),
        const Category(id: 'cat_y', name: 'Cycle Cat Y', parentId: 'cat_x'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryListProvider.overrideWith((ref) => Stream.value(cyclicCategories)),
            productListProvider.overrideWith((ref) => Stream.value(const <Product>[])),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CategoryFilterBottomSheet(
                currentSelectedCategory: 'All',
                onCategorySelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cycle Cat X'), findsOneWidget);
      expect(find.text('Cycle Cat Y'), findsOneWidget);

      // Search in bottom sheet
      await tester.enterText(find.byKey(const Key('category_search_field')), 'Cycle');
      await tester.pumpAndSettle();

      expect(find.text('Cycle Cat X'), findsOneWidget);
    });
  });

  group('Adversarial Test 6: Performance & Memoization with Large Scale Dataset', () {
    testWidgets('Tree and product counts compute fast for 200 categories and 1000 products', (tester) async {
      final largeCategories = List<Category>.generate(200, (i) {
        final parentId = i > 10 ? 'cat_${i % 10}' : null;
        return Category(id: 'cat_$i', name: 'Nhóm hàng $i', parentId: parentId);
      });

      final largeProducts = List<Product>.generate(1000, (i) {
        return Product(
          id: 'p_$i',
          code: 'SP_$i',
          name: 'Sản phẩm $i',
          category: 'Nhóm hàng ${i % 200}',
          category3Levels: 'Nhóm hàng ${i % 10} >> Nhóm hàng ${i % 200}',
          price: 50000,
          costPrice: 30000,
          branchStocks: {'branch_1': 10},
        );
      });

      final stopwatch = Stopwatch()..start();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryListProvider.overrideWith((ref) => Stream.value(largeCategories)),
            productListProvider.overrideWith((ref) => Stream.value(largeProducts)),
          ],
          child: const MaterialApp(
            home: CategoriesManagementPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      stopwatch.stop();
      // Should easily build and render within 1 second
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
      expect(find.text('Nhóm hàng 0'), findsOneWidget);

      // Keystroke typing should be fast and not freeze UI
      stopwatch.reset();
      stopwatch.start();
      await tester.enterText(find.byType(TextField), 'Nhóm hàng 5');
      await tester.pumpAndSettle();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      expect(find.text('Nhóm hàng 5'), findsWidgets);
    });
  });
}
