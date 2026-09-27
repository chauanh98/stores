import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/category_repository.dart';
import 'package:stores/presentation/products/pages/categories_management_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/products/pages/select_category_page.dart';
import 'package:stores/presentation/products/widgets/category_filter_bottom_sheet.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _FakeAuthNotifier(super.state);
  @override
  Future<String?> login(String u, String p) async => null;
  @override
  Future<void> logout() async {
    state = null;
  }
}

class _MockCategoryRepo implements CategoryRepository {
  final List<Category> _storage;
  _MockCategoryRepo(this._storage);

  final List<String> deletedIds = [];
  final List<Category> savedCategories = [];

  @override
  Future<List<Category>> fetchAll() async => List.unmodifiable(_storage);

  @override
  Stream<List<Category>> watchAll() => Stream.value(List.unmodifiable(_storage));

  @override
  Future<void> upsert(Category category) async {
    savedCategories.add(category);
    _storage.removeWhere((c) => c.id == category.id);
    _storage.add(category);
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    _storage.removeWhere((c) => c.id == id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = UserAccount(
    username: 'r3_tester',
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
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('vi', '')],
        locale: const Locale('vi'),
        home: child,
      ),
    );
  }

  group('Reviewer R3 Adversarial Probes: Category Hierarchy, Hit-Test, & 320px Overflows', () {

    // -------------------------------------------------------------------------
    // PROBE-01: Zero Hit-Test Warnings on product_category_dropdown
    // -------------------------------------------------------------------------
    testWidgets('PROBE-01: Fatal hit-test verification on product_category_dropdown', (tester) async {
      final oldFatal = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = oldFatal);

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          filterStorageServiceProvider.overrideWithValue(FilterStorageService(prefs)),
          categoryListProvider.overrideWith((ref) => Stream.value([
            const Category(id: 'c1', name: 'Đồ uống'),
            const Category(id: 'c2', name: 'Bia', parentId: 'c1'),
          ])),
          productListProvider.overrideWith((ref) => Stream.value([
            const Product(
              id: 'p1',
              name: 'Bia Tiger',
              code: 'TIG01',
              price: 18000,
              costPrice: 12000,
              category: 'Bia',
              branchStocks: {'store_001': 20},
            ),
          ])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildApp(child: const ProductsPage(), container: container));
      await tester.pumpAndSettle();

      final dropdownFinder = find.byKey(const Key('product_category_dropdown'));
      expect(dropdownFinder, findsOneWidget);

      // Verify widget is DropdownButton<String>
      final catDropdown = tester.widget<DropdownButton<String>>(dropdownFinder);
      expect(catDropdown.value, 'All');

      // Tapping must hit the target with NO warning (fatal would throw if missed)
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Bottom sheet is now open
      expect(find.byType(CategoryFilterBottomSheet), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // PROBE-02: Real-time Multi-tenant Concurrent Category Deletion
    // -------------------------------------------------------------------------
    testWidgets('PROBE-02: Concurrent remote category deletion self-heals to All without crash', (tester) async {
      SharedPreferences.setMockInitialValues({
        'filter_prefs_r3_tester_products': jsonEncode({
          'category': 'Đặc sản Tây Bắc',
          'stockStatus': 'all',
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final categoryController = StreamController<List<Category>>.broadcast();
      addTearDown(categoryController.close);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          filterStorageServiceProvider.overrideWithValue(FilterStorageService(prefs)),
          categoryListProvider.overrideWith((ref) => categoryController.stream),
          productListProvider.overrideWith((ref) => Stream.value([
            const Product(
              id: 'p_beef',
              name: 'Thịt trâu gác bếp',
              code: 'TB01',
              price: 250000,
              costPrice: 180000,
              category: 'Đặc sản Tây Bắc',
              branchStocks: {'store_001': 5},
            ),
            const Product(
              id: 'p_water',
              name: 'Nước suối LaVie',
              code: 'LV01',
              price: 10000,
              costPrice: 6000,
              category: 'Đồ uống',
              branchStocks: {'store_001': 50},
            ),
          ])),
        ],
      );
      addTearDown(container.dispose);

      // Initially, category exists
      categoryController.add([
        const Category(id: 'cat_dac_san', name: 'Đặc sản Tây Bắc'),
        const Category(id: 'cat_beverage', name: 'Đồ uống'),
      ]);

      await tester.pumpWidget(buildApp(child: const ProductsPage(), container: container));
      await tester.pumpAndSettle();

      // Should show only "Thịt trâu gác bếp"
      expect(find.text('Thịt trâu gác bếp'), findsOneWidget);
      expect(find.text('Nước suối LaVie'), findsNothing);

      // Remote user deletes "Đặc sản Tây Bắc" from Firebase
      categoryController.add([
        const Category(id: 'cat_beverage', name: 'Đồ uống'),
      ]);
      await tester.pumpAndSettle();

      // processedProductsProvider should self-heal to 'All'
      final processed = container.read(processedProductsProvider).valueOrNull;
      expect(processed, isNotNull);
      expect(processed!.filteredProducts.length, 2);
    });

    // -------------------------------------------------------------------------
    // PROBE-03: Combo Product Detail on 320px with Extreme Component Cost
    // -------------------------------------------------------------------------
    testWidgets('PROBE-03: 320px compact viewport with 120 billion VND combo cost has 0 RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const comboProduct = Product(
        id: 'combo_999',
        name: 'Combo Trọn Gói Siêu Dự Án Công Trình Biệt Thự Nghỉ Dưỡng',
        code: 'CB-MEGA-01',
        price: 150000000000,
        costPrice: 120000000000,
        category: 'Dịch vụ xây dựng >> Thi công trọn gói >> Biệt thự cao cấp',
        category3Levels: 'Dịch vụ xây dựng >> Thi công trọn gói >> Biệt thự cao cấp',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'comp_1',
            productCode: 'KC-01',
            productName: 'Gói Kết Cấu Khung Thép & Móng Cọc Dự Ứng Lực',
            quantity: 100,
            costPrice: 1200000000.0,
          ),
        ],
        branchStocks: {'store_001': 1},
      );

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          branchesProvider.overrideWithValue([
            const Branch('store_001', 'Chi nhánh Trung Tâm Quận 1'),
          ]),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          availableStoresProvider.overrideWith((ref) async => {'store_001': 'Chi nhánh Trung Tâm Quận 1'}),
          productListProvider.overrideWith((ref) => Stream.value([
            comboProduct,
            const Product(
              id: 'comp_1',
              name: 'Gói Kết Cấu Khung Thép & Móng Cọc Dự Ứng Lực',
              code: 'KC-01',
              price: 1300000000,
              costPrice: 1200000000,
              category: 'Vật liệu',
              branchStocks: {'store_001': 100},
            ),
          ])),
          showCostPriceProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildApp(
          child: const ProductDetailPage(product: comboProduct),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      // Must render without any RenderFlex overflow
      expect(tester.takeException(), isNull);
      expect(find.text('Tổng giá vốn gợi ý linh kiện:'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // PROBE-04: Deep Category Nesting (12 levels) on 320px in SelectCategoryPage
    // -------------------------------------------------------------------------
    testWidgets('PROBE-04: SelectCategoryPage with 12 nested levels clamps depth and has 0 overflow on 320px', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final deepCategories = <Category>[
        const Category(id: 'cat_0', name: 'Ngành Hàng Cấp 0 Gốc'),
      ];
      for (int i = 1; i <= 12; i++) {
        deepCategories.add(
          Category(
            id: 'cat_$i',
            name: 'Phân cấp sâu mức $i của danh mục dài',
            parentId: 'cat_${i - 1}',
          ),
        );
      }

      final container = ProviderContainer(
        overrides: [
          categoryListProvider.overrideWith((ref) => Stream.value(deepCategories)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildApp(
          child: const SelectCategoryPage(),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      // Expand nodes ensuring visible within viewport
      for (int i = 0; i < 6; i++) {
        final arrowFinder = find.byIcon(Icons.keyboard_arrow_right);
        if (arrowFinder.evaluate().isNotEmpty) {
          await tester.ensureVisible(arrowFinder.first);
          await tester.tap(arrowFinder.first);
          await tester.pumpAndSettle();
        }
      }

      // Assert no RenderFlex overflow
      expect(tester.takeException(), isNull);
    });

    // -------------------------------------------------------------------------
    // PROBE-05: Rapid Concurrent Category Search with IME and Diacritics
    // -------------------------------------------------------------------------
    testWidgets('PROBE-05: CategoryFilterBottomSheet search with Vietnamese diacritics and IME spaces', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final testCategories = [
        const Category(id: 'c1', name: 'Nước giải khát'),
        const Category(id: 'c2', name: 'Nước khoáng có ga', parentId: 'c1'),
        const Category(id: 'c3', name: 'Bia & Rượu ngoại'),
      ];

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
          productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
        ],
      );
      addTearDown(container.dispose);

      String? selectedCat;
      await tester.pumpWidget(
        buildApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                CategoryFilterBottomSheet.show(
                  ctx,
                  currentCategory: 'All',
                  onSelected: (c) => selectedCat = c,
                );
              },
              child: const Text('Mở Filter'),
            ),
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mở Filter'));
      await tester.pumpAndSettle();

      final searchField = find.byKey(const Key('category_search_field'));
      expect(searchField, findsOneWidget);

      // Search unaccented "nuoc khoang"
      await tester.enterText(searchField, 'nuoc khoang');
      await tester.pumpAndSettle();

      expect(find.text('Nước khoáng có ga'), findsOneWidget);
      expect(find.text('Bia & Rượu ngoại'), findsNothing);

      // Search with trailing space (IME in-progress typing)
      await tester.enterText(searchField, 'bia  ');
      await tester.pumpAndSettle();

      expect(find.text('Bia & Rượu ngoại'), findsOneWidget);
      expect(find.text('Nước khoáng có ga'), findsNothing);

      // Select category
      await tester.tap(find.text('Bia & Rượu ngoại').last);
      await tester.pumpAndSettle();

      expect(selectedCat, 'Bia & Rượu ngoại');
    });

    // -------------------------------------------------------------------------
    // PROBE-06: Tree View with Orphaned Subtree Re-parenting
    // -------------------------------------------------------------------------
    testWidgets('PROBE-06: Orphaned categories (parentId deleted) render at root without being lost', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Parent "deleted_root" is missing from list
      final categoriesWithOrphan = [
        const Category(id: 'c_child', name: 'Nhóm Mồ Côi B', parentId: 'deleted_root'),
        const Category(id: 'c_grandchild', name: 'Nhóm Con Của Mồ Côi', parentId: 'c_child'),
      ];

      final repo = _MockCategoryRepo(List.from(categoriesWithOrphan));
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          categoryRepositoryProvider.overrideWithValue(repo),
          categoryListProvider.overrideWith((ref) => Stream.value(categoriesWithOrphan)),
          productListProvider.overrideWith((ref) => Stream.value([
            const Product(
              id: 'p_orphan',
              name: 'Sản phẩm mồ côi',
              code: 'ORPH-01',
              price: 50000,
              costPrice: 30000,
              category: 'Nhóm Mồ Côi B',
              branchStocks: {'store_001': 10},
            ),
          ])),
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

      // Orphan category must be visible at root
      expect(find.text('Nhóm Mồ Côi B'), findsOneWidget);
      expect(find.text('1 sản phẩm'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // PROBE-07: Category Delete Dialog Warning Boundaries
    // -------------------------------------------------------------------------
    testWidgets('PROBE-07: Delete category dialog shows child and product warnings', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final categories = [
        const Category(id: 'cat_parent', name: 'Nhóm Cha Có Con'),
        const Category(id: 'cat_child', name: 'Nhóm Con Trực Thuộc', parentId: 'cat_parent'),
      ];

      final repo = _MockCategoryRepo(List.from(categories));
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          categoryRepositoryProvider.overrideWithValue(repo),
          categoryListProvider.overrideWith((ref) => Stream.value(categories)),
          productListProvider.overrideWith((ref) => Stream.value([
            const Product(
              id: 'p_1',
              name: 'Sản phẩm mẫu',
              code: 'SP-01',
              price: 10000,
              costPrice: 7000,
              category: 'Nhóm Cha Có Con',
              branchStocks: {'store_001': 5},
            ),
          ])),
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

      // Tap delete on cat_parent
      final deleteBtn = find.byKey(const Key('delete_category_cat_parent'));
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Dialog opens with warnings
      expect(find.text('Xóa nhóm hàng'), findsOneWidget);
      expect(find.text('Cảnh báo: Có 1 nhóm con trực thuộc!'), findsOneWidget);
      expect(find.text('Cảnh báo: Có 1 sản phẩm đang thuộc nhóm này!'), findsOneWidget);

      // Confirm delete
      final confirmBtn = find.byKey(const Key('confirm_delete_category_button'));
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(repo.deletedIds, contains('cat_parent'));
    });

    // -------------------------------------------------------------------------
    // PROBE-08: Cold Start Persistence and Clear Roundtrip
    // -------------------------------------------------------------------------
    testWidgets('PROBE-08: User scoped filter persists across cold start and resets via Clear button', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final categories = [
        const Category(id: 'cat_drink', name: 'Đồ uống'),
        const Category(id: 'cat_tea', name: 'Trà chanh', parentId: 'cat_drink'),
      ];

      final products = [
        const Product(
          id: 'p_tea_1',
          name: 'Trà chanh giã tay',
          code: 'TC01',
          price: 25000,
          costPrice: 10000,
          category: 'Trà chanh',
          branchStocks: {'store_001': 30},
        ),
        const Product(
          id: 'p_beer_1',
          name: 'Bia Saigon',
          code: 'BS01',
          price: 15000,
          costPrice: 11000,
          category: 'Đồ uống',
          branchStocks: {'store_001': 50},
        ),
      ];

      // Session 1: User filters by 'Trà chanh'
      final container1 = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          filterStorageServiceProvider.overrideWithValue(FilterStorageService(prefs)),
          categoryListProvider.overrideWith((ref) => Stream.value(categories)),
          productListProvider.overrideWith((ref) => Stream.value(products)),
        ],
      );

      await tester.pumpWidget(buildApp(child: const ProductsPage(), container: container1));
      await tester.pumpAndSettle();

      // Open bottom sheet and select 'Trà chanh'
      await tester.tap(find.byKey(const Key('product_category_dropdown')));
      await tester.pumpAndSettle();

      // Expand categories tree
      await tester.tap(find.byKey(const Key('expand_all_categories_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trà chanh').last);
      await tester.pumpAndSettle();

      // Verify Session 1 shows only Trà chanh
      expect(find.text('Trà chanh giã tay'), findsOneWidget);
      expect(find.text('Bia Saigon'), findsNothing);

      // Verify persistent storage written
      final raw = prefs.getString('filter_prefs_r3_tester_products');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['category'], 'Trà chanh');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      container1.dispose();

      // Session 2: Cold start with fresh ProviderContainer
      final container2 = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          filterStorageServiceProvider.overrideWithValue(FilterStorageService(prefs)),
          categoryListProvider.overrideWith((ref) => Stream.value(categories)),
          productListProvider.overrideWith((ref) => Stream.value(products)),
        ],
      );
      addTearDown(container2.dispose);

      await tester.pumpWidget(buildApp(child: const ProductsPage(), container: container2));
      await tester.pumpAndSettle();

      // Filter restored from cold start
      expect(find.text('Trà chanh giã tay'), findsOneWidget);
      expect(find.text('Bia Saigon'), findsNothing);

      // Clear button is visible on horizontal filter bar
      final clearBtn = find.byKey(const Key('clear_category_filter_button'));
      expect(clearBtn, findsOneWidget);

      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      // Both products now visible
      expect(find.text('Trà chanh giã tay'), findsOneWidget);
      expect(find.text('Bia Saigon'), findsOneWidget);

      // Storage updated to All
      final rawAfterClear = prefs.getString('filter_prefs_r3_tester_products');
      final decodedAfterClear = jsonDecode(rawAfterClear!) as Map<String, dynamic>;
      expect(decodedAfterClear['category'], 'All');
    });
  });
}
