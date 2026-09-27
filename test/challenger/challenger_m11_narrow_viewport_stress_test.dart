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
  Stream<List<Product>> watchAll() => Stream.value(const []);

  @override
  Future<List<Product>> fetchAll() async => const [];

  @override
  Future<void> upsert(Product product) async {}

  @override
  Future<Product?> fetchById(String id) async => null;
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

  final stressCategories = <Category>[
    const Category(id: 'root_furniture', name: 'Đồ gỗ & Nội thất'),
    const Category(
        id: 'child_living',
        name: 'Bàn ghế phòng khách',
        parentId: 'root_furniture'),
    const Category(
        id: 'child_sofa', name: 'Sofa hiện đại', parentId: 'child_living'),
    const Category(id: 'root_tech', name: 'Thiết bị điện tử'),
    const Category(
        id: 'child_laptop', name: 'Máy tính xách tay', parentId: 'root_tech'),
  ];

  final stressProducts = <Product>[
    const Product(
      id: 'prod_sofa',
      name: 'Sofa góc L',
      code: 'SOFA01',
      category: 'Sofa hiện đại',
      price: 15000000,
      costPrice: 10000000,
      branchStocks: {'store_001': 5},
      type: 'Hàng hóa thường',
    ),
    const Product(
      id: 'prod_laptop',
      name: 'Laptop Gaming',
      code: 'LAP01',
      category: 'Máy tính xách tay',
      price: 25000000,
      costPrice: 20000000,
      branchStocks: {'store_001': 8},
      type: 'Hàng hóa thường',
    ),
    const Product(
      id: 'prod_combo_living',
      name: 'Combo Nội thất',
      code: 'COMBO01',
      category: 'Bàn ghế phòng khách',
      price: 30000000,
      costPrice: 22000000,
      branchStocks: {'store_001': 2},
      isCombo: true,
      type: 'Combo - đóng gói',
    ),
    const Product(
      id: 'prod_service_clean',
      name: 'Dịch vụ bảo dưỡng',
      code: 'SRV01',
      category: 'Đồ gỗ & Nội thất',
      price: 500000,
      costPrice: 200000,
      branchStocks: {'store_001': 99},
      type: 'dịch vụ',
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
        locale: const Locale('vi'),
        home: child,
      ),
    );
  }

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

  group('CHALLENGER M11: Narrow Viewport (320px) Rapid Stress Harness', () {
    // =========================================================================
    // 1. CategoryFilterBottomSheet: Rapid expand/collapse cycles (30x)
    // =========================================================================
    testWidgets(
        'CategoryFilterBottomSheet: 30 rapid expand/collapse toggles on 320px viewport without overflow or crash',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryRepositoryProvider
              .overrideWithValue(_FakeCategoryRepo(List.of(stressCategories))),
          categoryListProvider
              .overrideWith((ref) => Stream.value(stressCategories)),
          productListProvider
              .overrideWith((ref) => Stream.value(stressProducts)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => CategoryFilterBottomSheet.show(ctx),
              child: const Text('Open Sheet'),
            ),
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      final expandBtn = find.byKey(const Key('expand_all_categories_button'));
      final collapseBtn =
          find.byKey(const Key('collapse_all_categories_button'));

      expect(expandBtn, findsOneWidget);
      expect(collapseBtn, findsOneWidget);

      // Perform 30 rapid alternating expand/collapse clicks
      for (int i = 0; i < 30; i++) {
        await tester.ensureVisible(expandBtn);
        await tester.pumpAndSettle();
        await tester.tap(expandBtn);
        await tester.pump(const Duration(milliseconds: 16));

        await tester.ensureVisible(collapseBtn);
        await tester.pumpAndSettle();
        await tester.tap(collapseBtn);
        await tester.pump(const Duration(milliseconds: 16));
      }

      await tester.pumpAndSettle();

      // Ensure zero unhandled exceptions and zero overflows
      expect(tester.takeException(), isNull);

      // Verify that after a final expand, child categories are rendered correctly
      await tester.ensureVisible(expandBtn);
      await tester.pumpAndSettle();
      await tester.tap(expandBtn);
      await tester.pumpAndSettle();

      expect(find.text('Bàn ghế phòng khách'), findsOneWidget);
      expect(find.text('Máy tính xách tay'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // =========================================================================
    // 2. CategoryFilterBottomSheet: Rapid multi-select toggling while expanding/collapsing
    // =========================================================================
    testWidgets(
        'CategoryFilterBottomSheet: Rapid multi-select toggling + expand/collapse on 320px yields exact selection',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryRepositoryProvider
              .overrideWithValue(_FakeCategoryRepo(List.of(stressCategories))),
          categoryListProvider
              .overrideWith((ref) => Stream.value(stressCategories)),
          productListProvider
              .overrideWith((ref) => Stream.value(stressProducts)),
        ],
      );
      addTearDown(container.dispose);

      Set<String>? capturedSelection;

      await tester.pumpWidget(
        buildApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => CategoryFilterBottomSheet.show(
                ctx,
                onCategoriesSelected: (cats) {
                  capturedSelection = cats;
                },
              ),
              child: const Text('Open Sheet'),
            ),
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      final expandBtn = find.byKey(const Key('expand_all_categories_button'));
      final collapseBtn =
          find.byKey(const Key('collapse_all_categories_button'));

      // Expand all to expose all checkboxes
      await tester.ensureVisible(expandBtn);
      await tester.pumpAndSettle();
      await tester.tap(expandBtn);
      await tester.pumpAndSettle();

      final cbFurniture =
          find.byKey(const Key('checkbox_category_root_furniture'));
      final cbLiving = find.byKey(const Key('checkbox_category_child_living'));
      final resetBtn = find.byKey(const Key('reset_category_filter_button'));

      // Rapidly toggle checkboxes back and forth
      for (int i = 0; i < 5; i++) {
        await tester.ensureVisible(cbFurniture);
        await tester.tap(cbFurniture);
        await tester.pump(const Duration(milliseconds: 16));

        await tester.ensureVisible(cbLiving);
        await tester.tap(cbLiving);
        await tester.pump(const Duration(milliseconds: 16));

        await tester.ensureVisible(cbFurniture);
        await tester.tap(cbFurniture); // uncheck
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Tap "Bỏ chọn" to clear all individual selections without closing sheet
      await tester.ensureVisible(resetBtn);
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      // Now toggle specific categories
      await tester.ensureVisible(cbFurniture);
      await tester.tap(cbFurniture);
      await tester.pumpAndSettle();

      await tester.ensureVisible(cbLiving);
      await tester.tap(cbLiving);
      await tester.pumpAndSettle();

      // Rapidly collapse and expand while keeping selections intact
      await tester.ensureVisible(collapseBtn);
      await tester.pumpAndSettle();
      await tester.tap(collapseBtn);
      await tester.pump(const Duration(milliseconds: 16));

      await tester.ensureVisible(expandBtn);
      await tester.pumpAndSettle();
      await tester.tap(expandBtn);
      await tester.pumpAndSettle();

      // Tap Apply
      final applyBtn = find.byKey(const Key('apply_category_filter_button'));
      await tester.ensureVisible(applyBtn);
      await tester.tap(applyBtn);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(capturedSelection, isNotNull);
      expect(capturedSelection, contains('Đồ gỗ & Nội thất'));
      expect(capturedSelection, contains('Bàn ghế phòng khách'));
      expect(capturedSelection!.length, 2);
    });

    // =========================================================================
    // 3. Extreme Narrow Viewport (280px x 560px) Stress Test
    // =========================================================================
    testWidgets(
        'CategoryFilterBottomSheet: Extreme narrow 280px viewport renders without overflow and remains accessible',
        (tester) async {
      tester.view.physicalSize = const Size(280, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryRepositoryProvider
              .overrideWithValue(_FakeCategoryRepo(List.of(stressCategories))),
          categoryListProvider
              .overrideWith((ref) => Stream.value(stressCategories)),
          productListProvider
              .overrideWith((ref) => Stream.value(stressProducts)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => CategoryFilterBottomSheet.show(ctx),
              child: const Text('Open Sheet'),
            ),
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      final expandBtn = find.byKey(const Key('expand_all_categories_button'));
      await tester.ensureVisible(expandBtn);
      await tester.pumpAndSettle();
      await tester.tap(expandBtn);
      await tester.pumpAndSettle();

      // Verify no overflow exception occurred on 280px screen
      expect(tester.takeException(), isNull);

      // Verify reset button and apply button
      final resetBtn = find.byKey(const Key('reset_category_filter_button'));
      final applyBtn = find.byKey(const Key('apply_category_filter_button'));
      expect(resetBtn, findsOneWidget);
      expect(applyBtn, findsOneWidget);

      await tester.tap(resetBtn);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // =========================================================================
    // 4. CategoriesManagementPage: Rapid expand/collapse cycles on 320px viewport
    // =========================================================================
    testWidgets(
        'CategoriesManagementPage: 30 rapid expand/collapse cycles and search on 320px viewport',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryRepositoryProvider
              .overrideWithValue(_FakeCategoryRepo(List.of(stressCategories))),
          categoryListProvider
              .overrideWith((ref) => Stream.value(stressCategories)),
          productListProvider
              .overrideWith((ref) => Stream.value(stressProducts)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildApp(
          child: const CategoriesManagementPage(), container: container));
      await tester.pumpAndSettle();

      final expandBtn = find.byKey(const Key('expand_all_categories_button'));
      final collapseBtn =
          find.byKey(const Key('collapse_all_categories_button'));

      expect(expandBtn, findsOneWidget);
      expect(collapseBtn, findsOneWidget);

      // Perform 30 rapid expand/collapse clicks
      for (int i = 0; i < 30; i++) {
        await tester.tap(expandBtn);
        await tester.pump(const Duration(milliseconds: 16));
        await tester.tap(collapseBtn);
        await tester.pump(const Duration(milliseconds: 16));
      }

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Search interaction under 320px
      final searchInput = find.byType(TextField);
      expect(searchInput, findsOneWidget);
      await tester.enterText(searchInput, 'sofa');
      await tester.pumpAndSettle();
      expect(find.text('Sofa hiện đại'), findsOneWidget);

      await tester.enterText(searchInput, '');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // =========================================================================
    // 5. ProductsPage: Rapid filter interactions and detection of 320px overflows
    // =========================================================================
    testWidgets(
        'ProductsPage: Rapid category multi-filter and clear on 320px viewport',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryRepositoryProvider
              .overrideWithValue(_FakeCategoryRepo(List.of(stressCategories))),
          categoryListProvider
              .overrideWith((ref) => Stream.value(stressCategories)),
          productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
          productRepositoryProvider.overrideWithValue(_FakeProductRepo()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
          buildApp(child: const ProductsPage(), container: container));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // 1. Scroll filter bar horizontally to category button and tap it
      final catDropdown = find.byKey(const Key('product_category_dropdown'));
      await tester.ensureVisible(catDropdown);
      await tester.pumpAndSettle();
      await tester.tap(catDropdown);
      await tester.pumpAndSettle();

      final expandBtn = find.byKey(const Key('expand_all_categories_button'));
      await tester.ensureVisible(expandBtn);
      await tester.pumpAndSettle();
      await tester.tap(expandBtn);
      await tester.pumpAndSettle();

      final cbRoot = find.byKey(const Key('checkbox_category_root_furniture'));
      await tester.ensureVisible(cbRoot);
      await tester.tap(cbRoot);
      await tester.pumpAndSettle();

      final applyBtn = find.byKey(const Key('apply_category_filter_button'));
      await tester.ensureVisible(applyBtn);
      await tester.tap(applyBtn);
      await tester.pumpAndSettle();

      final clearCatBtn = find.byKey(const Key('clear_category_filter_button'));
      await tester.ensureVisible(clearCatBtn);
      expect(clearCatBtn, findsOneWidget);

      // 2. Clear category filter via quick clear 'X' button
      await tester.tap(clearCatBtn);
      await tester.pumpAndSettle();

      // 3. Test "Đặt lại" button
      container.read(productSelectedCategoriesProvider.notifier).state = {
        'Bàn ghế phòng khách'
      };
      await tester.pumpAndSettle();
      final resetBtn = find.text('Đặt lại');
      await tester.ensureVisible(resetBtn);
      expect(resetBtn, findsOneWidget);

      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      expect(container.read(productSelectedCategoriesProvider), isEmpty);
      expect(tester.takeException(), isNull);
    });

    // =========================================================================
    // 6. Verification of ProductTypeFilterBottomSheet header on 320px with zero overflow
    // =========================================================================
    testWidgets(
        'ProductTypeFilterBottomSheet: Renders cleanly on 320px viewport with zero overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          filterStorageServiceProvider
              .overrideWithValue(FilterStorageService(prefs)),
          categoryRepositoryProvider
              .overrideWithValue(_FakeCategoryRepo(List.of(stressCategories))),
          categoryListProvider
              .overrideWith((ref) => Stream.value(stressCategories)),
          productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
          productRepositoryProvider.overrideWithValue(_FakeProductRepo()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
          buildApp(child: const ProductsPage(), container: container));
      await tester.pumpAndSettle();

      final typeBtn = find.byKey(const Key('product_type_filter_button'));
      await tester.ensureVisible(typeBtn);
      await tester.pumpAndSettle();
      await tester.tap(typeBtn);
      await tester.pumpAndSettle();

      // Verify zero overflow exceptions
      expect(tester.takeException(), isNull);
      expect(find.text('Chọn loại hàng'), findsOneWidget);
      expect(find.byKey(const Key('product_type_checkbox_standard')),
          findsOneWidget);
      expect(
          find.byKey(const Key('product_type_checkbox_combo')), findsOneWidget);
      expect(find.byKey(const Key('product_type_checkbox_service')),
          findsOneWidget);

      // Toggle standard checkbox
      await tester.tap(find.byKey(const Key('product_type_checkbox_standard')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Tap Tất cả button
      await tester
          .tap(find.byKey(const Key('select_all_product_types_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
