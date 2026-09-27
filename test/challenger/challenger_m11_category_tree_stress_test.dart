import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/category_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/categories_management_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/products/widgets/category_filter_bottom_sheet.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

class _FakeCategoryRepo implements CategoryRepository {
  final List<Category> _storage;

  _FakeCategoryRepo(this._storage);

  @override
  Stream<List<Category>> watchAll() =>
      Stream.value(List.unmodifiable(_storage));

  @override
  Future<List<Category>> fetchAll() async => List.unmodifiable(_storage);

  @override
  Future<void> upsert(Category category) async {
    _storage.removeWhere((c) => c.id == category.id);
    _storage.add(category);
  }

  @override
  Future<void> delete(String id) async {
    _storage.removeWhere((c) => c.id == id);
  }
}

class _FakeProductRepo extends Fake implements ProductRepository {
  @override
  Future<void> upsert(Product product) async {}
}

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

  const testUser = UserAccount(
    username: 'challenger_m11_tester',
    displayName: 'Challenger M11 Tester',
    role: 'admin',
    storeId: 'store_001',
  );

  Widget buildApp({
    required Widget child,
    required ProviderContainer container,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('vi'),
        home: child,
      ),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CHALLENGER M11: Category Tree & Multi-Select Adversarial Stress Tests',
      () {
    // =========================================================================
    // 1. Root category collapse and expansion toggling
    // =========================================================================
    group('1. Root category collapse & expansion toggling', () {
      testWidgets(
          'CategoryFilterBottomSheet: arrow tap toggles root expansion and collapse',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final categories = [
          const Category(id: 'root_furniture', name: 'Đồ gỗ & Nội thất'),
          const Category(
              id: 'child_chair',
              name: 'Ghế cao đốt nhang',
              parentId: 'root_furniture'),
          const Category(
              id: 'child_table', name: 'Trường kỷ', parentId: 'root_furniture'),
        ];

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(categories)),
            productListProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildApp(
            child: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => CategoryFilterBottomSheet.show(ctx),
                child: const Text('Mở BottomSheet'),
              ),
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Mở BottomSheet'));
        await tester.pumpAndSettle();

        // Verification 1: Root category is visible, but child nodes are collapsed by default
        expect(find.text('Đồ gỗ & Nội thất'), findsOneWidget);
        expect(find.text('Ghế cao đốt nhang'), findsNothing);
        expect(find.text('Trường kỷ'), findsNothing);

        // Arrow should be right-arrow (collapsed)
        final rootTileFinder =
            find.byKey(const Key('category_filter_item_root_furniture'));
        expect(rootTileFinder, findsOneWidget);
        final rightArrowFinder = find.descendant(
          of: rootTileFinder,
          matching: find.byIcon(Icons.keyboard_arrow_right),
        );
        expect(rightArrowFinder, findsOneWidget);

        // Tap arrow to EXPAND root node
        await tester.tap(rightArrowFinder);
        await tester.pumpAndSettle();

        // Verification 2: Child nodes are now visible and arrow turned into down-arrow
        expect(find.text('Ghế cao đốt nhang'), findsOneWidget);
        expect(find.text('Trường kỷ'), findsOneWidget);
        final downArrowFinder = find.descendant(
          of: rootTileFinder,
          matching: find.byIcon(Icons.keyboard_arrow_down),
        );
        expect(downArrowFinder, findsOneWidget);

        // Tap down arrow to COLLAPSE root node again
        await tester.tap(downArrowFinder);
        await tester.pumpAndSettle();

        // Verification 3: Child nodes are hidden again and arrow turned back to right-arrow
        expect(find.text('Ghế cao đốt nhang'), findsNothing);
        expect(find.text('Trường kỷ'), findsNothing);
        expect(
          find.descendant(
              of: rootTileFinder,
              matching: find.byIcon(Icons.keyboard_arrow_right)),
          findsOneWidget,
        );
      });

      testWidgets(
          'CategoriesManagementPage: toggle arrow button expands and collapses root node',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final categories = [
          const Category(id: 'root_tech', name: 'Thiết bị điện tử'),
          const Category(
              id: 'child_laptop', name: 'Laptop Gaming', parentId: 'root_tech'),
        ];

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryRepositoryProvider
                .overrideWithValue(_FakeCategoryRepo(categories)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(categories)),
            productListProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildApp(
            child: const CategoriesManagementPage(),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        // Initially collapsed
        expect(find.text('Thiết bị điện tử'), findsOneWidget);
        expect(find.text('Laptop Gaming'), findsNothing);

        final toggleBtn = find.byKey(const Key('toggle_category_root_tech'));
        expect(toggleBtn, findsOneWidget);
        expect(
          find.descendant(
              of: toggleBtn, matching: find.byIcon(Icons.keyboard_arrow_right)),
          findsOneWidget,
        );

        // Tap toggle arrow to expand
        await tester.tap(toggleBtn);
        await tester.pumpAndSettle();

        expect(find.text('Laptop Gaming'), findsOneWidget);
        expect(
          find.descendant(
              of: toggleBtn, matching: find.byIcon(Icons.keyboard_arrow_down)),
          findsOneWidget,
        );

        // Tap toggle arrow to collapse
        await tester.tap(toggleBtn);
        await tester.pumpAndSettle();

        expect(find.text('Laptop Gaming'), findsNothing);
        expect(
          find.descendant(
              of: toggleBtn, matching: find.byIcon(Icons.keyboard_arrow_right)),
          findsOneWidget,
        );
      });
    });

    // =========================================================================
    // 2. Global "Thu gọn tất cả" & "Mở rộng tất cả" on deep trees (5+ levels)
    // =========================================================================
    group(
        '2. Global Expand All & Collapse All Controls on Deep Tree (6 Levels)',
        () {
      final deep6LevelsCategories = <Category>[
        const Category(id: 'l0', name: 'Cấp 0 - Gốc Tổng'),
        const Category(id: 'l1', name: 'Cấp 1 - Phân Nhánh A', parentId: 'l0'),
        const Category(id: 'l2', name: 'Cấp 2 - Phân Nhánh B', parentId: 'l1'),
        const Category(id: 'l3', name: 'Cấp 3 - Phân Nhánh C', parentId: 'l2'),
        const Category(id: 'l4', name: 'Cấp 4 - Phân Nhánh D', parentId: 'l3'),
        const Category(id: 'l5', name: 'Cấp 5 - Lá Tận Cùng', parentId: 'l4'),
      ];

      testWidgets(
          'CategoryFilterBottomSheet: expands all 5+ levels to leaf and collapses all back to root',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(deep6LevelsCategories)),
            productListProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildApp(
            child: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => CategoryFilterBottomSheet.show(ctx),
                child: const Text('Mở BottomSheet'),
              ),
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Mở BottomSheet'));
        await tester.pumpAndSettle();

        // 1. Initially all collapsed: only l0 is visible
        expect(find.text('Cấp 0 - Gốc Tổng'), findsOneWidget);
        expect(find.text('Cấp 1 - Phân Nhánh A'), findsNothing);
        expect(find.text('Cấp 5 - Lá Tận Cùng'), findsNothing);

        final expandAllBtn =
            find.byKey(const Key('expand_all_categories_button'));
        final collapseAllBtn =
            find.byKey(const Key('collapse_all_categories_button'));
        expect(expandAllBtn, findsOneWidget);
        expect(collapseAllBtn, findsOneWidget);

        // 2. Tap "Mở rộng" (Expand all)
        await tester.tap(expandAllBtn);
        await tester.pumpAndSettle();

        // All levels down to Level 5 must be visible in widget tree
        expect(find.text('Cấp 0 - Gốc Tổng'), findsOneWidget);
        expect(find.text('Cấp 1 - Phân Nhánh A'), findsOneWidget);
        expect(find.text('Cấp 2 - Phân Nhánh B'), findsOneWidget);
        expect(find.text('Cấp 3 - Phân Nhánh C'), findsOneWidget);
        expect(find.text('Cấp 4 - Phân Nhánh D'), findsOneWidget);
        expect(find.text('Cấp 5 - Lá Tận Cùng'), findsOneWidget);

        // 3. Tap "Thu gọn" (Collapse all)
        await tester.tap(collapseAllBtn);
        await tester.pumpAndSettle();

        // All intermediate and leaf levels must be hidden again
        expect(find.text('Cấp 0 - Gốc Tổng'), findsOneWidget);
        expect(find.text('Cấp 1 - Phân Nhánh A'), findsNothing);
        expect(find.text('Cấp 2 - Phân Nhánh B'), findsNothing);
        expect(find.text('Cấp 3 - Phân Nhánh C'), findsNothing);
        expect(find.text('Cấp 4 - Phân Nhánh D'), findsNothing);
        expect(find.text('Cấp 5 - Lá Tận Cùng'), findsNothing);
      });

      testWidgets(
          'CategoriesManagementPage: expands all 5+ levels to leaf and collapses all back to root',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryRepositoryProvider
                .overrideWithValue(_FakeCategoryRepo(deep6LevelsCategories)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(deep6LevelsCategories)),
            productListProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildApp(
            child: const CategoriesManagementPage(),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Cấp 0 - Gốc Tổng'), findsOneWidget);
        expect(find.text('Cấp 5 - Lá Tận Cùng'), findsNothing);

        final expandAllBtn =
            find.byKey(const Key('expand_all_categories_button'));
        final collapseAllBtn =
            find.byKey(const Key('collapse_all_categories_button'));

        // Tap expand all
        await tester.tap(expandAllBtn);
        await tester.pumpAndSettle();

        expect(find.text('Cấp 5 - Lá Tận Cùng'), findsOneWidget);

        // Tap collapse all
        await tester.tap(collapseAllBtn);
        await tester.pumpAndSettle();

        expect(find.text('Cấp 5 - Lá Tận Cùng'), findsNothing);
        expect(find.text('Cấp 0 - Gốc Tổng'), findsOneWidget);
      });
    });

    // =========================================================================
    // 3. Multi-select category combinations & exact descendant union filtering
    // =========================================================================
    group(
        '3. Multi-select category combinations & exact descendant union filtering',
        () {
      final multiCategories = [
        const Category(id: 'root_furniture', name: 'Nội thất'),
        const Category(
            id: 'sub_tables_chairs',
            name: 'Bàn ghế',
            parentId: 'root_furniture'),
        const Category(
            id: 'leaf_wood_chair',
            name: 'Ghế gỗ',
            parentId: 'sub_tables_chairs'),
        const Category(
            id: 'leaf_tea_table',
            name: 'Bàn trà',
            parentId: 'sub_tables_chairs'),
        const Category(
            id: 'sub_cabinets', name: 'Tủ kệ', parentId: 'root_furniture'),
        const Category(
            id: 'leaf_wardrobe', name: 'Tủ quần áo', parentId: 'sub_cabinets'),
        const Category(id: 'root_tech', name: 'Điện tử'),
        const Category(
            id: 'sub_phones', name: 'Điện thoại', parentId: 'root_tech'),
        const Category(
            id: 'leaf_smartphone',
            name: 'Smartphone 5G',
            parentId: 'sub_phones'),
        const Category(
            id: 'leaf_laptop', name: 'Laptop', parentId: 'root_tech'),
        const Category(id: 'root_fashion', name: 'Thời trang'),
      ];

      final multiProducts = [
        const Product(
          id: 'p1',
          name: 'Ghế Gỗ Sồi Hoàng Gia',
          code: 'GHE01',
          price: 1500000,
          costPrice: 1000000,
          category: 'Ghế gỗ',
          category3Levels: 'Nội thất >> Bàn ghế >> Ghế gỗ',
          branchStocks: {'store_001': 10},
        ),
        const Product(
          id: 'p2',
          name: 'Bàn Trà Kính Cường Lực',
          code: 'BAN01',
          price: 2500000,
          costPrice: 1800000,
          category: 'Bàn trà',
          category3Levels: 'Nội thất >> Bàn ghế >> Bàn trà',
          branchStocks: {'store_001': 5},
        ),
        const Product(
          id: 'p3',
          name: 'Tủ Quần Áo Gỗ Xoan Đào',
          code: 'TU01',
          price: 4500000,
          costPrice: 3200000,
          category: 'Tủ quần áo',
          category3Levels: 'Nội thất >> Tủ kệ >> Tủ quần áo',
          branchStocks: {'store_001': 3},
        ),
        const Product(
          id: 'p4',
          name: 'iPhone 16 Pro Max 256GB',
          code: 'IP16',
          price: 34000000,
          costPrice: 30000000,
          category: 'Smartphone 5G',
          category3Levels: 'Điện tử >> Điện thoại >> Smartphone 5G',
          branchStocks: {'store_001': 20},
        ),
        const Product(
          id: 'p5',
          name: 'MacBook Pro M3 Max',
          code: 'MAC01',
          price: 65000000,
          costPrice: 58000000,
          category: 'Laptop',
          category3Levels: 'Điện tử >> Laptop',
          branchStocks: {'store_001': 8},
        ),
        const Product(
          id: 'p6',
          name: 'Áo Sơ Mi Lụa Cao Cấp',
          code: 'AO01',
          price: 650000,
          costPrice: 400000,
          category: 'Thời trang',
          category3Levels: 'Thời trang',
          branchStocks: {'store_001': 50},
        ),
      ];

      testWidgets(
          'Direct provider check: processedProductsProvider correctly filters union of branch and leaf descendants',
          (tester) async {
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(multiCategories)),
            productListProvider
                .overrideWith((ref) => Stream.value(multiProducts)),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildApp(
            child: Consumer(
              builder: (ctx, ref, _) {
                final data = ref.watch(processedProductsProvider);
                return Text(data.valueOrNull != null ? 'READY' : 'LOADING');
              },
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        // Set multi-selected categories directly
        container.read(productSelectedCategoriesProvider.notifier).state = {
          'Bàn ghế',
          'Laptop'
        };
        await tester.pumpAndSettle();

        final data = container.read(processedProductsProvider).valueOrNull;
        expect(data, isNotNull);
        expect(
            data!.filteredProducts.map((p) => p.name).toSet(),
            equals({
              'Ghế Gỗ Sồi Hoàng Gia',
              'Bàn Trà Kính Cường Lực',
              'MacBook Pro M3 Max',
            }));
      });

      testWidgets(
          'Combination A: Selecting branch node "Bàn ghế" AND leaf node "Laptop" matches exact union {P1, P2, P5}',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryRepositoryProvider
                .overrideWithValue(_FakeCategoryRepo(multiCategories)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(multiCategories)),
            productListProvider
                .overrideWith((ref) => Stream.value(multiProducts)),
            productRepositoryProvider.overrideWithValue(_FakeProductRepo()),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
            buildApp(child: const ProductsPage(), container: container));
        await tester.pumpAndSettle();

        // Initially 6 products visible
        expect(find.byType(ProductTile), findsNWidgets(6));

        // Open CategoryFilterBottomSheet
        await tester.tap(find.byKey(const Key('product_category_dropdown')));
        await tester.pumpAndSettle();

        // Expand all tree
        await tester.tap(find.byKey(const Key('expand_all_categories_button')));
        await tester.pumpAndSettle();

        // Multi-select Checkboxes:
        // 1. Check "Bàn ghế" (id: sub_tables_chairs)
        final cbTablesChairs =
            find.byKey(const Key('checkbox_category_sub_tables_chairs'));
        await tester.ensureVisible(cbTablesChairs);
        await tester.tap(cbTablesChairs);
        await tester.pumpAndSettle();

        // 2. Check "Laptop" (id: leaf_laptop)
        final cbLaptop = find.byKey(const Key('checkbox_category_leaf_laptop'));
        await tester.ensureVisible(cbLaptop);
        await tester.tap(cbLaptop);
        await tester.pumpAndSettle();

        // Tap "Áp dụng"
        final applyBtn = find.byKey(const Key('apply_category_filter_button'));
        expect(find.text('Áp dụng (2 nhóm)'), findsOneWidget);
        await tester.tap(applyBtn);
        await tester.pumpAndSettle();

        // Sheet closed
        expect(find.byType(CategoryFilterBottomSheet), findsNothing);

        // Products displayed must be EXACTLY:
        // P1 ("Ghế Gỗ Sồi Hoàng Gia" - child of Bàn ghế)
        // P2 ("Bàn Trà Kính Cường Lực" - child of Bàn ghế)
        // P5 ("MacBook Pro M3 Max" - Laptop)
        expect(find.byType(ProductTile), findsNWidgets(3));
        expect(find.text('Ghế Gỗ Sồi Hoàng Gia'), findsOneWidget);
        expect(find.text('Bàn Trà Kính Cường Lực'), findsOneWidget);
        expect(find.text('MacBook Pro M3 Max'), findsOneWidget);

        // Unselected categories' products must NOT be displayed
        expect(find.text('Tủ Quần Áo Gỗ Xoan Đào'), findsNothing);
        expect(find.text('iPhone 16 Pro Max 256GB'), findsNothing);
        expect(find.text('Áo Sơ Mi Lụa Cao Cấp'), findsNothing);
      });

      testWidgets(
          'Combination B: Selecting leaf node "Ghế gỗ" AND branch node "Điện thoại" AND root node "Thời trang" matches exact union {P1, P4, P6}',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryRepositoryProvider
                .overrideWithValue(_FakeCategoryRepo(multiCategories)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(multiCategories)),
            productListProvider
                .overrideWith((ref) => Stream.value(multiProducts)),
            productRepositoryProvider.overrideWithValue(_FakeProductRepo()),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
            buildApp(child: const ProductsPage(), container: container));
        await tester.pumpAndSettle();

        // Open CategoryFilterBottomSheet
        await tester.tap(find.byKey(const Key('product_category_dropdown')));
        await tester.pumpAndSettle();

        // Expand tree
        await tester.tap(find.byKey(const Key('expand_all_categories_button')));
        await tester.pumpAndSettle();

        // Select "Ghế gỗ" (leaf_wood_chair)
        final cbWoodChair =
            find.byKey(const Key('checkbox_category_leaf_wood_chair'));
        await tester.ensureVisible(cbWoodChair);
        await tester.tap(cbWoodChair);
        await tester.pumpAndSettle();

        // Select "Điện thoại" (sub_phones)
        final cbPhones = find.byKey(const Key('checkbox_category_sub_phones'));
        await tester.ensureVisible(cbPhones);
        await tester.tap(cbPhones);
        await tester.pumpAndSettle();

        // Select "Thời trang" (root_fashion)
        final cbFashion =
            find.byKey(const Key('checkbox_category_root_fashion'));
        await tester.ensureVisible(cbFashion);
        await tester.tap(cbFashion);
        await tester.pumpAndSettle();

        // Tap "Áp dụng"
        final applyBtn = find.byKey(const Key('apply_category_filter_button'));
        expect(find.text('Áp dụng (3 nhóm)'), findsOneWidget);
        await tester.tap(applyBtn);
        await tester.pumpAndSettle();

        // Verification: Exactly P1, P4, P6 shown
        expect(find.byType(ProductTile), findsNWidgets(3));
        expect(find.text('Ghế Gỗ Sồi Hoàng Gia'), findsOneWidget);
        expect(find.text('iPhone 16 Pro Max 256GB'), findsOneWidget);
        expect(find.text('Áo Sơ Mi Lụa Cao Cấp'), findsOneWidget);

        expect(find.text('Bàn Trà Kính Cường Lực'), findsNothing);
        expect(find.text('Tủ Quần Áo Gỗ Xoan Đào'), findsNothing);
        expect(find.text('MacBook Pro M3 Max'), findsNothing);
      });
    });

    // =========================================================================
    // 4. Exclusive "Tất cả nhóm hàng" option toggling
    // =========================================================================
    group('4. Exclusive "Tất cả nhóm hàng" option toggling', () {
      testWidgets(
          'Checking individual category unchecks "Tất cả"; clicking "Tất cả" unchecks individual categories',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final categories = [
          const Category(id: 'cat_drink', name: 'Đồ uống'),
          const Category(id: 'cat_snack', name: 'Đồ ăn vặt'),
        ];

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(categories)),
            productListProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildApp(
            child: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => CategoryFilterBottomSheet.show(
                  ctx,
                  onCategoriesSelected: (_) {},
                ),
                child: const Text('Mở BottomSheet'),
              ),
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Mở BottomSheet'));
        await tester.pumpAndSettle();

        final cbAll = find.byKey(const Key('checkbox_category_all'));
        final cbDrink = find.byKey(const Key('checkbox_category_cat_drink'));
        final cbSnack = find.byKey(const Key('checkbox_category_cat_snack'));

        // Step 1: Initially "Tất cả" is checked, individual categories are unchecked
        expect(tester.widget<Checkbox>(cbAll).value, isTrue);
        expect(tester.widget<Checkbox>(cbDrink).value, isFalse);
        expect(tester.widget<Checkbox>(cbSnack).value, isFalse);

        // Step 2: Checking "Đồ uống" unchecks "Tất cả"
        await tester.tap(cbDrink);
        await tester.pumpAndSettle();

        expect(tester.widget<Checkbox>(cbAll).value, isFalse);
        expect(tester.widget<Checkbox>(cbDrink).value, isTrue);
        expect(tester.widget<Checkbox>(cbSnack).value, isFalse);

        // Step 3: Checking "Đồ ăn vặt" keeps "Tất cả" unchecked
        await tester.tap(cbSnack);
        await tester.pumpAndSettle();

        expect(tester.widget<Checkbox>(cbAll).value, isFalse);
        expect(tester.widget<Checkbox>(cbDrink).value, isTrue);
        expect(tester.widget<Checkbox>(cbSnack).value, isTrue);

        // Step 4: Tapping "Tất cả" unchecks both "Đồ uống" and "Đồ ăn vặt"
        await tester.tap(cbAll);
        await tester.pumpAndSettle();

        expect(tester.widget<Checkbox>(cbAll).value, isTrue);
        expect(tester.widget<Checkbox>(cbDrink).value, isFalse);
        expect(tester.widget<Checkbox>(cbSnack).value, isFalse);
      });
    });

    // =========================================================================
    // 5. Footer buttons: "Bỏ chọn" and "Áp dụng"
    // =========================================================================
    group('5. Footer buttons: "Bỏ chọn" and "Áp dụng"', () {
      testWidgets(
          '"Bỏ chọn" resets state to "Tất cả", "Áp dụng" invokes callback with selection and pops sheet',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final categories = [
          const Category(id: 'c1', name: 'Sách giáo khoa'),
          const Category(id: 'c2', name: 'Truyện tranh'),
        ];

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(categories)),
            productListProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
          ],
        );
        addTearDown(container.dispose);

        Set<String>? appliedCategories;
        await tester.pumpWidget(
          buildApp(
            child: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => CategoryFilterBottomSheet.show(
                  ctx,
                  onCategoriesSelected: (cats) => appliedCategories = cats,
                ),
                child: const Text('Mở BottomSheet'),
              ),
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Mở BottomSheet'));
        await tester.pumpAndSettle();

        final resetBtn = find.byKey(const Key('reset_category_filter_button'));
        final applyBtn = find.byKey(const Key('apply_category_filter_button'));

        // Initially: "Bỏ chọn" disabled, "Áp dụng (Tất cả)"
        expect(tester.widget<OutlinedButton>(resetBtn).onPressed, isNull);
        expect(find.text('Áp dụng (Tất cả)'), findsOneWidget);

        // Check C1 and C2
        await tester.tap(find.byKey(const Key('checkbox_category_c1')));
        await tester.tap(find.byKey(const Key('checkbox_category_c2')));
        await tester.pumpAndSettle();

        // "Bỏ chọn" is now enabled, "Áp dụng (2 nhóm)"
        expect(tester.widget<OutlinedButton>(resetBtn).onPressed, isNotNull);
        expect(find.text('Áp dụng (2 nhóm)'), findsOneWidget);

        // Tap "Bỏ chọn" -> resets to Tất cả, bottom sheet remains open
        await tester.tap(resetBtn);
        await tester.pumpAndSettle();

        expect(find.byType(CategoryFilterBottomSheet), findsOneWidget);
        expect(
            tester
                .widget<Checkbox>(
                    find.byKey(const Key('checkbox_category_all')))
                .value,
            isTrue);
        expect(
            tester
                .widget<Checkbox>(find.byKey(const Key('checkbox_category_c1')))
                .value,
            isFalse);
        expect(
            tester
                .widget<Checkbox>(find.byKey(const Key('checkbox_category_c2')))
                .value,
            isFalse);
        expect(tester.widget<OutlinedButton>(resetBtn).onPressed, isNull);
        expect(find.text('Áp dụng (Tất cả)'), findsOneWidget);

        // Now check C1 again
        await tester.tap(find.byKey(const Key('checkbox_category_c1')));
        await tester.pumpAndSettle();

        expect(find.text('Áp dụng (1 nhóm)'), findsOneWidget);

        // Tap "Áp dụng" -> invokes callback and pops sheet
        await tester.tap(applyBtn);
        await tester.pumpAndSettle();

        expect(find.byType(CategoryFilterBottomSheet), findsNothing);
        expect(appliedCategories, equals({'Sách giáo khoa'}));
      });
    });

    // =========================================================================
    // 6. Cyclic parentId references in category hierarchy
    // =========================================================================
    group('6. Cyclic parentId references in category hierarchy', () {
      final cyclicCategories = [
        // Self cycle (1-node cycle)
        const Category(
            id: 'cat_self', name: 'Tự Trỏ Chính Mình', parentId: 'cat_self'),

        // Mutual cycle (2-node cycle: A -> B -> A)
        const Category(
            id: 'cat_cyc_a',
            name: 'Vòng Lặp Nhóm Alpha',
            parentId: 'cat_cyc_b'),
        const Category(
            id: 'cat_cyc_b', name: 'Vòng Lặp Nhóm Beta', parentId: 'cat_cyc_a'),

        // 3-node cycle (X -> Y -> Z -> X)
        const Category(id: 'cat_x', name: 'Vòng 3 Cấp X', parentId: 'cat_z'),
        const Category(id: 'cat_y', name: 'Vòng 3 Cấp Y', parentId: 'cat_x'),
        const Category(id: 'cat_z', name: 'Vòng 3 Cấp Z', parentId: 'cat_y'),

        // Normal tree alongside cycles
        const Category(id: 'cat_norm_root', name: 'Nhóm Bình Thường'),
        const Category(
            id: 'cat_norm_child',
            name: 'Nhóm Con Bình Thường',
            parentId: 'cat_norm_root'),
      ];

      testWidgets(
          'CategoryFilterBottomSheet: cyclic hierarchy builds safely, expands all without infinite recursion or crash',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(cyclicCategories)),
            productListProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildApp(
            child: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => CategoryFilterBottomSheet.show(ctx),
                child: const Text('Mở BottomSheet'),
              ),
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Mở BottomSheet'));
        await tester.pumpAndSettle();

        // Must build with no exceptions
        expect(tester.takeException(), isNull);
        expect(find.byType(CategoryFilterBottomSheet), findsOneWidget);

        // Tap "Mở rộng" on cyclic tree -> must not cause stack overflow or freeze
        final expandAllBtn =
            find.byKey(const Key('expand_all_categories_button'));
        await tester.tap(expandAllBtn);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Cyclic nodes render safely without duplication explosion
        expect(find.text('Tự Trỏ Chính Mình'), findsOneWidget);
        expect(find.text('Vòng Lặp Nhóm Alpha'), findsOneWidget);
        expect(find.text('Vòng Lặp Nhóm Beta'), findsOneWidget);

        // Can select cyclic category and apply
        final cbAlpha = find.byKey(const Key('checkbox_category_cat_cyc_a'));
        await tester.ensureVisible(cbAlpha);
        await tester.tap(cbAlpha);
        await tester.pumpAndSettle();

        final applyBtn = find.byKey(const Key('apply_category_filter_button'));
        await tester.tap(applyBtn);
        await tester.pumpAndSettle();

        // Sheet closed successfully
        expect(find.byType(CategoryFilterBottomSheet), findsNothing);
      });

      testWidgets(
          'CategoriesManagementPage: handles cyclic hierarchy safely without crashing or hanging',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryRepositoryProvider
                .overrideWithValue(_FakeCategoryRepo(cyclicCategories)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(cyclicCategories)),
            productListProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildApp(
            child: const CategoriesManagementPage(),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Tap expand all then collapse all
        await tester.tap(find.byKey(const Key('expand_all_categories_button')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester
            .tap(find.byKey(const Key('collapse_all_categories_button')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'processedProductsProvider: resolves cyclic category descendants safely without StackOverflow',
          (tester) async {
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(cyclicCategories)),
            productListProvider.overrideWith((ref) => Stream.value([
                  const Product(
                    id: 'p_cyc',
                    name: 'Sản phẩm vòng lặp',
                    code: 'CYC01',
                    price: 100000,
                    costPrice: 50000,
                    category: 'Vòng Lặp Nhóm Alpha',
                    category3Levels:
                        'Vòng Lặp Nhóm Beta >> Vòng Lặp Nhóm Alpha',
                    branchStocks: {'store_001': 1},
                  ),
                ])),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildApp(
            child: Consumer(
              builder: (ctx, ref, _) {
                final data = ref.watch(processedProductsProvider);
                return Text(data.valueOrNull != null ? 'READY' : 'LOADING');
              },
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        // Set multi-selected category to cyclic node
        container.read(productSelectedCategoriesProvider.notifier).state = {
          'Vòng Lặp Nhóm Alpha'
        };
        await tester.pumpAndSettle();

        final processed = container.read(processedProductsProvider).valueOrNull;
        expect(processed, isNotNull);
        expect(processed!.filteredProducts.length, 1);
        expect(processed.filteredProducts.first.name, 'Sản phẩm vòng lặp');
      });
    });

    // =========================================================================
    // 7. 320px viewport rendering with zero RenderFlex overflows
    // =========================================================================
    group('7. 320px viewport rendering without RenderFlex overflow', () {
      final deepLongNameCategories = [
        const Category(
            id: 'c_root',
            name:
                'Hệ thống thiết bị văn phòng chuyên dụng chất lượng cực kỳ cao cấp'),
        const Category(
            id: 'c_l1',
            name:
                'Máy móc in ấn đa năng công suất lớn phục vụ doanh nghiệp vừa và nhỏ',
            parentId: 'c_root'),
        const Category(
            id: 'c_l2',
            name:
                'Linh kiện thay thế và phụ tùng cơ khí chính hãng nhập khẩu nguyên chiếc',
            parentId: 'c_l1'),
        const Category(
            id: 'c_l3',
            name:
                'Đầu kim phun nhiệt độ phân giải cao cho bản vẽ kỹ thuật kiến trúc',
            parentId: 'c_l2'),
        const Category(
            id: 'c_l4',
            name:
                'Bộ chuyển đổi áp suất khí nén tự động hóa điều khiển điện tử',
            parentId: 'c_l3'),
        const Category(
            id: 'c_l5',
            name: 'Mạch vi điều khiển tích hợp cảm biến siêu nhạy thông minh',
            parentId: 'c_l4'),
      ];

      testWidgets(
          'CategoryFilterBottomSheet: 320px narrow viewport with deep expanded tree has 0 RenderFlex overflow',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(deepLongNameCategories)),
            productListProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildApp(
            child: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => CategoryFilterBottomSheet.show(ctx),
                child: const Text('Open'),
              ),
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Tap expand all
        await tester.tap(find.byKey(const Key('expand_all_categories_button')));
        await tester.pumpAndSettle();

        // Verify zero overflow exception occurred
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'CategoriesManagementPage: 320px narrow viewport with horizontal toolbar has 0 RenderFlex overflow',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryRepositoryProvider
                .overrideWithValue(_FakeCategoryRepo(deepLongNameCategories)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(deepLongNameCategories)),
            productListProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildApp(
            child: const CategoriesManagementPage(),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        // Ensure visible in horizontal scroll view and tap expand all
        final expandBtn = find.byKey(const Key('expand_all_categories_button'));
        await tester.ensureVisible(expandBtn);
        await tester.tap(expandBtn);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'ProductsPage: 320px narrow viewport with multi-selected category and active filters has 0 RenderFlex overflow',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
            categoryRepositoryProvider
                .overrideWithValue(_FakeCategoryRepo(deepLongNameCategories)),
            categoryListProvider
                .overrideWith((ref) => Stream.value(deepLongNameCategories)),
            productListProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
            productRepositoryProvider.overrideWithValue(_FakeProductRepo()),
          ],
        );
        addTearDown(container.dispose);

        // Pre-set multiple active filters (multi-categories, single type, stock)
        container.read(productSelectedCategoriesProvider.notifier).state = {
          'Hệ thống thiết bị văn phòng chuyên dụng chất lượng cực kỳ cao cấp',
          'Máy móc in ấn đa năng công suất lớn phục vụ doanh nghiệp vừa và nhỏ',
        };
        container.read(productTypeFilterProvider.notifier).state = {
          ProductTypeFilter.standard,
        };
        container.read(productStockStatusFilterProvider.notifier).state =
            StockStatus.inStock;

        await tester.pumpWidget(
            buildApp(child: const ProductsPage(), container: container));
        await tester.pumpAndSettle();

        // Should display filter label "Nhóm hàng (2)" and "Đặt lại" pill without any RenderFlex overflow
        expect(find.text('Nhóm hàng (2)'), findsOneWidget);
        expect(find.text('Đặt lại'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
