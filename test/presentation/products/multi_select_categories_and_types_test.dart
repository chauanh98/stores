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
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/category_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/products/widgets/category_filter_bottom_sheet.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

class _MockCategoryRepo implements CategoryRepository {
  final List<Category> _list;
  _MockCategoryRepo(this._list);

  @override
  Stream<List<Category>> watchAll() => Stream.value(_list);

  @override
  Future<List<Category>> fetchAll() async => _list;

  @override
  Future<void> upsert(Category category) async {}

  @override
  Future<void> delete(String id) async {}
}

class _MockProductRepo extends Fake implements ProductRepository {
  @override
  Future<void> upsert(Product product) async {}

  @override
  Future<Product?> fetchById(String id) async => null;
}

class _MockAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _MockAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mockUser = UserAccount(
    username: 'store_manager_test',
    displayName: 'Quản Lý Cửa Hàng',
    role: 'manager',
    storeId: 'store_001',
  );

  final mockCategories = [
    const Category(id: 'root_furniture', name: 'Đồ gỗ & Nội thất'),
    const Category(
        id: 'sub_tables', name: 'Bàn ghế phòng khách', parentId: 'root_furniture'),
    const Category(
        id: 'leaf_chair', name: 'Ghế gỗ sồi', parentId: 'sub_tables'),
    const Category(id: 'root_electronics', name: 'Thiết bị điện tử'),
    const Category(
        id: 'sub_laptop', name: 'Máy tính xách tay', parentId: 'root_electronics'),
    const Category(
        id: 'leaf_macbook', name: 'MacBook', parentId: 'sub_laptop'),
  ];

  final mockProducts = [
    const Product(
      id: 'prod_chair',
      name: 'Ghế Gỗ Sồi Tự Nhiên',
      code: 'GHE01',
      price: 1500000,
      costPrice: 1000000,
      branchStocks: {'store_001': 10},
      category: 'Ghế gỗ sồi',
      category3Levels: 'Đồ gỗ & Nội thất >> Bàn ghế phòng khách >> Ghế gỗ sồi',
      type: 'Hàng hóa thường',
    ),
    const Product(
      id: 'prod_table',
      name: 'Bàn Trà Sofa Mặt Kính',
      code: 'BAN01',
      price: 3000000,
      costPrice: 2000000,
      branchStocks: {'store_001': 5},
      category: 'Bàn ghế phòng khách',
      category3Levels: 'Đồ gỗ & Nội thất >> Bàn ghế phòng khách',
      type: 'Hàng hóa thường',
    ),
    const Product(
      id: 'prod_laptop',
      name: 'Laptop Dell Inspiron 15',
      code: 'LAP01',
      price: 18000000,
      costPrice: 15000000,
      branchStocks: {'store_001': 3},
      category: 'Máy tính xách tay',
      category3Levels: 'Thiết bị điện tử >> Máy tính xách tay',
      type: 'Hàng hóa thường',
    ),
    const Product(
      id: 'prod_combo',
      name: 'Combo Nội Thất Trọn Gói',
      code: 'COMBO01',
      price: 4200000,
      costPrice: 3000000,
      branchStocks: {'store_001': 2},
      category: 'Bàn ghế phòng khách',
      category3Levels: 'Đồ gỗ & Nội thất >> Bàn ghế phòng khách',
      isCombo: true,
      comboComponents: [
        ComboComponent(
            productId: 'prod_chair',
            productCode: 'GHE01',
            productName: 'Ghế Gỗ Sồi Tự Nhiên',
            quantity: 2),
        ComboComponent(
            productId: 'prod_table',
            productCode: 'BAN01',
            productName: 'Bàn Trà Sofa Mặt Kính',
            quantity: 1),
      ],
    ),
    const Product(
      id: 'prod_service',
      name: 'Gói Bảo Hành Mở Rộng 12 Tháng',
      code: 'BH01',
      price: 500000,
      costPrice: 0,
      branchStocks: {'store_001': 999},
      category: 'Thiết bị điện tử',
      category3Levels: 'Thiết bị điện tử',
      type: 'Dịch vụ',
    ),
  ];

  Widget buildApp({
    required Widget child,
    required ProviderContainer container,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  group('Multi-Select Categories & Product Types Verification', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      FilterStorageService.resetSharedPrefs();
      FilterStorageService.setSharedPrefs(prefs);
    });

    tearDown(() {
      FilterStorageService.resetSharedPrefs();
    });

    // 1. Multi-category selection and filtering combinations
    testWidgets(
        'CategoryFilterBottomSheet: multi-select checkboxes toggle and apply selection cleanly without collision',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Set<String>? appliedCategories;

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthNotifier(mockUser)),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryListProvider.overrideWith((ref) => Stream.value(mockCategories)),
          productListProvider.overrideWith((ref) => Stream.value(mockProducts)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => CategoryFilterBottomSheet.show(
                ctx,
                onCategoriesSelected: (cats) {
                  appliedCategories = cats;
                },
              ),
              child: const Text('Mở Lọc'),
            ),
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mở Lọc'));
      await tester.pumpAndSettle();

      // Tap expand all
      await tester.tap(find.byKey(const Key('expand_all_categories_button')));
      await tester.pumpAndSettle();

      // Check "Bàn ghế phòng khách" and "Máy tính xách tay"
      final cbTables = find.byKey(const Key('checkbox_category_sub_tables'));
      await tester.ensureVisible(cbTables);
      await tester.tap(cbTables);
      await tester.pumpAndSettle();

      final cbLaptop = find.byKey(const Key('checkbox_category_sub_laptop'));
      await tester.ensureVisible(cbLaptop);
      await tester.tap(cbLaptop);
      await tester.pumpAndSettle();

      // Verify button label
      expect(find.text('Áp dụng (2 nhóm)'), findsOneWidget);

      // Tap "Áp dụng"
      await tester.tap(find.byKey(const Key('apply_category_filter_button')));
      await tester.pumpAndSettle();

      // Verify bottom sheet closed and callback received both categories
      expect(find.byType(CategoryFilterBottomSheet), findsNothing);
      expect(appliedCategories, isNotNull);
      expect(appliedCategories!.length, 2);
      expect(appliedCategories!.contains('Bàn ghế phòng khách'), isTrue);
      expect(appliedCategories!.contains('Máy tính xách tay'), isTrue);
    });

    testWidgets(
        'CategoryFilterBottomSheet: tapping "Tất cả nhóm hàng" clears multi-selection to empty set',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Set<String>? appliedCategories;

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthNotifier(mockUser)),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryListProvider.overrideWith((ref) => Stream.value(mockCategories)),
          productListProvider.overrideWith((ref) => Stream.value(mockProducts)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => CategoryFilterBottomSheet.show(
                ctx,
                initialSelectedCategories: {'Bàn ghế phòng khách'},
                onCategoriesSelected: (cats) {
                  appliedCategories = cats;
                },
              ),
              child: const Text('Mở Lọc'),
            ),
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mở Lọc'));
      await tester.pumpAndSettle();

      // Tap "Tất cả nhóm hàng"
      await tester.tap(find.byKey(const Key('category_item_all')));
      await tester.pumpAndSettle();

      // Bottom sheet closed and empty set returned
      expect(find.byType(CategoryFilterBottomSheet), findsNothing);
      expect(appliedCategories, isNotNull);
      expect(appliedCategories!.isEmpty, isTrue);
    });

    testWidgets(
        'ProductsPage: multi-category selection correctly filters products by union of descendants',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthNotifier(mockUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryRepositoryProvider
              .overrideWithValue(_MockCategoryRepo(mockCategories)),
          categoryListProvider.overrideWith((ref) => Stream.value(mockCategories)),
          productListProvider.overrideWith((ref) => Stream.value(mockProducts)),
          productRepositoryProvider.overrideWithValue(_MockProductRepo()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildApp(child: const ProductsPage(), container: container));
      await tester.pumpAndSettle();

      // Initially all 5 products shown
      expect(find.byType(ProductTile), findsNWidgets(5));

      // Open Category filter
      await tester.tap(find.byKey(const Key('product_category_dropdown')));
      await tester.pumpAndSettle();

      // Expand all
      await tester.tap(find.byKey(const Key('expand_all_categories_button')));
      await tester.pumpAndSettle();

      // Select "Máy tính xách tay"
      final cbLaptop = find.byKey(const Key('checkbox_category_sub_laptop'));
      await tester.ensureVisible(cbLaptop);
      await tester.tap(cbLaptop);
      await tester.pumpAndSettle();

      // Apply
      await tester.tap(find.byKey(const Key('apply_category_filter_button')));
      await tester.pumpAndSettle();

      // Only laptop is shown
      expect(find.byType(ProductTile), findsNWidgets(1));
      expect(find.text('Laptop Dell Inspiron 15'), findsOneWidget);
    });

    // 2. Product type multi-selection (standard, combo, service)
    testWidgets(
        'Product type multi-selection: filtering by combo and service dynamically reflects in list',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthNotifier(mockUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryRepositoryProvider
              .overrideWithValue(_MockCategoryRepo(mockCategories)),
          categoryListProvider.overrideWith((ref) => Stream.value(mockCategories)),
          productListProvider.overrideWith((ref) => Stream.value(mockProducts)),
          productRepositoryProvider.overrideWithValue(_MockProductRepo()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildApp(child: const ProductsPage(), container: container));
      await tester.pumpAndSettle();

      // Open product type filter
      await tester.tap(find.byKey(const Key('product_type_filter_button')));
      await tester.pumpAndSettle();

      // Uncheck "Hàng hóa thường"
      final cbStandard = find.byKey(const Key('product_type_checkbox_standard'));
      await tester.tap(cbStandard);
      await tester.pumpAndSettle();

      // Close bottom sheet
      Navigator.of(tester.element(find.byKey(const Key('product_type_checkbox_combo')))).pop();
      await tester.pumpAndSettle();

      // Only combo and service are displayed (2 products)
      expect(find.byType(ProductTile), findsNWidgets(2));
      expect(find.text('Combo Nội Thất Trọn Gói'), findsOneWidget);
      expect(find.text('Gói Bảo Hành Mở Rộng 12 Tháng'), findsOneWidget);

      // Clear product type filter via quick clear button
      final clearBtn = find.byKey(const Key('clear_product_type_filter_button'));
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      // All 5 products restored
      expect(find.byType(ProductTile), findsNWidgets(5));
      expect(find.byKey(const Key('clear_product_type_filter_button')), findsNothing);
    });

    // 3. Tree controls (collapse all / expand all)
    testWidgets(
        'Category tree controls: default collapsed, expand all and collapse all work correctly',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthNotifier(mockUser)),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryListProvider.overrideWith((ref) => Stream.value(mockCategories)),
          productListProvider.overrideWith((ref) => Stream.value(mockProducts)),
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

      // Root categories are visible
      expect(find.text('Đồ gỗ & Nội thất'), findsOneWidget);
      expect(find.text('Thiết bị điện tử'), findsOneWidget);

      // Children are collapsed initially
      expect(find.text('Bàn ghế phòng khách'), findsNothing);
      expect(find.text('Máy tính xách tay'), findsNothing);

      // Tap expand all
      await tester.tap(find.byKey(const Key('expand_all_categories_button')));
      await tester.pumpAndSettle();

      // Children are now visible
      expect(find.text('Bàn ghế phòng khách'), findsOneWidget);
      expect(find.text('Máy tính xách tay'), findsOneWidget);

      // Tap collapse all
      await tester.tap(find.byKey(const Key('collapse_all_categories_button')));
      await tester.pumpAndSettle();

      // Children are hidden again
      expect(find.text('Bàn ghế phòng khách'), findsNothing);
      expect(find.text('Máy tính xách tay'), findsNothing);
    });

    // 4. Persistence and reset semantics
    testWidgets(
        'Persistence & Reset: "Đặt lại" resets multi-categories, product types, and clears disk storage',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthNotifier(mockUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryRepositoryProvider
              .overrideWithValue(_MockCategoryRepo(mockCategories)),
          categoryListProvider.overrideWith((ref) => Stream.value(mockCategories)),
          productListProvider.overrideWith((ref) => Stream.value(mockProducts)),
          productRepositoryProvider.overrideWithValue(_MockProductRepo()),
        ],
      );
      addTearDown(container.dispose);

      // Pre-seed active multi-category and product type filters
      container.read(productSelectedCategoriesProvider.notifier).state = {
        'Bàn ghế phòng khách',
      };
      container.read(productTypeFilterProvider.notifier).state = {
        ProductTypeFilter.combo,
      };

      await tester.pumpWidget(buildApp(child: const ProductsPage(), container: container));
      await tester.pumpAndSettle();

      // Filtered to 1 product
      expect(find.byType(ProductTile), findsNWidgets(1));
      expect(find.text('Combo Nội Thất Trọn Gói'), findsOneWidget);

      // Reset button visible with 'Đặt lại' and badge count
      expect(find.text('Đặt lại'), findsOneWidget);
      final resetBtn = find.byKey(const Key('reset_product_filters_button'));
      expect(resetBtn, findsOneWidget);

      // Tap 'Đặt lại'
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      // All filters reset: all 5 products visible
      expect(find.byType(ProductTile), findsNWidgets(5));
      expect(container.read(productSelectedCategoriesProvider), isEmpty);
      expect(container.read(productCategoryFilterProvider), 'All');
      expect(container.read(productTypeFilterProvider).length, 3);
    });

    // 5. 320px viewport layout checks without overflow
    testWidgets(
        'CategoryFilterBottomSheet: 320px narrow viewport has 0 RenderFlex overflow and controls are accessible',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthNotifier(mockUser)),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryListProvider.overrideWith((ref) => Stream.value(mockCategories)),
          productListProvider.overrideWith((ref) => Stream.value(mockProducts)),
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

      // Expand all categories
      final expandBtn = find.byKey(const Key('expand_all_categories_button'));
      await tester.ensureVisible(expandBtn);
      await tester.tap(expandBtn);
      await tester.pumpAndSettle();

      // Verify no RenderFlex overflow exception
      expect(tester.takeException(), isNull);
      expect(find.text('Chọn nhóm hàng'), findsOneWidget);
      expect(find.byKey(const Key('collapse_all_categories_button')), findsOneWidget);
    });

    testWidgets(
        'ProductsPage: 320px narrow viewport with active multi-filters renders with 0 RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthNotifier(mockUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryRepositoryProvider
              .overrideWithValue(_MockCategoryRepo(mockCategories)),
          categoryListProvider.overrideWith((ref) => Stream.value(mockCategories)),
          productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
          productRepositoryProvider.overrideWithValue(_MockProductRepo()),
        ],
      );
      addTearDown(container.dispose);

      // Pre-set active multi-filters
      container.read(productSelectedCategoriesProvider.notifier).state = {
        'Bàn ghế phòng khách',
        'Máy tính xách tay',
      };
      container.read(productTypeFilterProvider.notifier).state = {
        ProductTypeFilter.standard,
      };

      await tester.pumpWidget(buildApp(child: const ProductsPage(), container: container));
      await tester.pumpAndSettle();

      // Verify no overflow exception
      expect(tester.takeException(), isNull);
      expect(find.text('Nhóm hàng (2)'), findsOneWidget);
      expect(find.text('Đặt lại'), findsOneWidget);
    });
  });
}
