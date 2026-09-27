import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/auth/user_filter_hydration.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/products/widgets/category_filter_bottom_sheet.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }

  void setUser(UserAccount? user) {
    state = user;
  }
}

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
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userAdmin = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const userSupervisor = UserAccount(
    username: 'supervisor',
    displayName: 'Cửa hàng trưởng',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const userAlpha = UserAccount(
    username: 'user_alpha',
    displayName: 'Nhân viên Alpha',
    role: 'cashier',
    storeId: 'store_001',
  );

  const userBeta = UserAccount(
    username: 'user_beta',
    displayName: 'Nhân viên Beta',
    role: 'cashier',
    storeId: 'store_001',
  );

  const userSpecial = UserAccount(
    username: 'manager.special@store-domain.com',
    displayName: 'Quản lý Special',
    role: 'manager',
    storeId: 'store_001',
  );

  // Hierarchy Categories
  final testCategories = [
    const Category(id: 'cat_electronics', name: 'Thiết bị điện tử'),
    const Category(id: 'cat_computers', name: 'Máy tính', parentId: 'cat_electronics'),
    const Category(id: 'cat_accessories', name: 'Phụ kiện', parentId: 'cat_electronics'),
    const Category(id: 'cat_audio', name: 'Âm thanh', parentId: 'cat_electronics'),
    const Category(id: 'cat_services', name: 'Dịch vụ kỹ thuật'),
    const Category(id: 'cat_furniture', name: 'Đồ gỗ & Nội thất'),
  ];

  // Diverse test product dataset
  // Standard products (4):
  const pStd1 = Product(
    id: 'p_std_1',
    name: 'Bàn phím cơ DareU EK87',
    code: 'STD1',
    price: 650000,
    costPrice: 450000,
    branchStocks: {'branch_1': 10},
    category: 'Phụ kiện',
    category3Levels: 'Thiết bị điện tử >> Phụ kiện',
    type: 'Hàng hóa',
    isCombo: false,
  );
  const pStd2 = Product(
    id: 'p_std_2',
    name: 'Chuột không dây Logitech M331',
    code: 'STD2',
    price: 350000,
    costPrice: 240000,
    branchStocks: {'branch_1': 15},
    category: 'Phụ kiện',
    category3Levels: 'Thiết bị điện tử >> Phụ kiện',
    type: null, // null type -> falls back to standard
    isCombo: false,
  );
  const pStd3 = Product(
    id: 'p_std_3',
    name: 'Lót chuột Corsair MM300',
    code: 'STD3',
    price: 150000,
    costPrice: 90000,
    branchStocks: {'branch_1': 20},
    category: 'Phụ kiện',
    category3Levels: 'Thiết bị điện tử >> Phụ kiện',
    type: '', // empty type -> standard
    isCombo: false,
  );
  const pStd4 = Product(
    id: 'p_std_4',
    name: 'Tai nghe Bluetooth Sony WH-1000XM5',
    code: 'STD4',
    price: 6990000,
    costPrice: 5500000,
    branchStocks: {'branch_1': 5},
    category: 'Âm thanh',
    category3Levels: 'Thiết bị điện tử >> Âm thanh',
    type: 'Khác', // arbitrary type -> standard
    isCombo: false,
  );

  // Combo products (3):
  const pCmb1 = Product(
    id: 'p_cmb_1',
    name: 'Bộ PC Gaming Rog Strix + Màn hình ASUS',
    code: 'CMB1',
    price: 28990000,
    costPrice: 22000000,
    branchStocks: {'branch_1': 2},
    category: 'Máy tính',
    category3Levels: 'Thiết bị điện tử >> Máy tính',
    type: 'Combo',
    isCombo: true,
  );
  const pCmb2 = Product(
    id: 'p_cmb_2',
    name: 'Combo Phím Chuột Không Dây Văn Phòng',
    code: 'CMB2',
    price: 490000,
    costPrice: 320000,
    branchStocks: {'branch_1': 8},
    category: 'Phụ kiện',
    category3Levels: 'Thiết bị điện tử >> Phụ kiện',
    type: null,
    isCombo: true,
  );
  const pCmb3 = Product(
    id: 'p_cmb_3',
    name: 'Gói Combo Lắp Đặt Kèm Dịch Vụ',
    code: 'CMB3',
    price: 1500000,
    costPrice: 900000,
    branchStocks: {'branch_1': 4},
    category: 'Dịch vụ kỹ thuật',
    category3Levels: 'Dịch vụ kỹ thuật',
    type: 'Dịch vụ', // has isCombo == true, so it is classified as combo
    isCombo: true,
  );

  // Service products (4):
  const pSrv1 = Product(
    id: 'p_srv_1',
    name: 'Dịch vụ Cài đặt Hệ điều hành Windows & Office',
    code: 'SRV1',
    price: 150000,
    costPrice: 0,
    branchStocks: {'branch_1': 999},
    category: 'Dịch vụ kỹ thuật',
    category3Levels: 'Dịch vụ kỹ thuật',
    type: 'Dịch vụ', // standard capitalization
    isCombo: false,
  );
  const pSrv2 = Product(
    id: 'p_srv_2',
    name: 'Vệ sinh laptop tra keo tản nhiệt',
    code: 'SRV2',
    price: 120000,
    costPrice: 20000,
    branchStocks: {'branch_1': 999},
    category: 'Dịch vụ kỹ thuật',
    category3Levels: 'Dịch vụ kỹ thuật',
    type: 'dịch vụ', // all lowercase
    isCombo: false,
  );
  const pSrv3 = Product(
    id: 'p_srv_3',
    name: 'Nâng cấp RAM & SSD tận nơi',
    code: 'SRV3',
    price: 200000,
    costPrice: 0,
    branchStocks: {'branch_1': 999},
    category: 'Dịch vụ kỹ thuật',
    category3Levels: 'Dịch vụ kỹ thuật',
    type: 'DỊCH VỤ', // all uppercase
    isCombo: false,
  );
  const pSrv4 = Product(
    id: 'p_srv_4',
    name: 'Gói bảo hành vàng 12 tháng tại nhà',
    code: 'SRV4',
    price: 500000,
    costPrice: 100000,
    branchStocks: {'branch_1': 999},
    category: 'Dịch vụ kỹ thuật',
    category3Levels: 'Dịch vụ kỹ thuật',
    type: '  Dịch vụ  ', // with whitespace padding
    isCombo: false,
  );

  final allTestProducts = [
    pStd1,
    pStd2,
    pStd3,
    pStd4,
    pCmb1,
    pCmb2,
    pCmb3,
    pSrv1,
    pSrv2,
    pSrv3,
    pSrv4,
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilterStorageService.resetSharedPrefs();
  });

  tearDown(() {
    FilterStorageService.resetSharedPrefs();
  });

  void setScreenSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 2800);
    tester.view.devicePixelRatio = 1.0;
  }

  // =========================================================================
  // GROUP 1: All 2^3 = 8 Combinations of ProductTypeFilter + Edge Cases
  // =========================================================================
  group('Adversarial Combinatorial ProductTypeFilter Suite (All 8 Subsets)', () {
    Future<ProviderContainer> createContainerWithProductTypes(
      Set<ProductTypeFilter> types, {
      Set<String>? categories,
    }) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(userSupervisor)),
          categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
          productListProvider.overrideWith((ref) => Stream.value(allTestProducts)),
          productTypeFilterProvider.overrideWith((ref) => types),
          if (categories != null)
            productSelectedCategoriesProvider.overrideWith((ref) => categories),
        ],
      );
      addTearDown(container.dispose);
      await container.read(productListProvider.future);
      await container.read(categoryListProvider.future);
      return container;
    }

    test('Combination 1: Empty selection {} displays 0 products', () async {
      final container = await createContainerWithProductTypes({});
      final processed = container.read(processedProductsProvider);
      final products = processed.asData!.value.filteredProducts;

      expect(products, isEmpty);
      expect(products.length, 0);
    });

    test('Combination 2: {standard} returns ONLY standard products', () async {
      final container = await createContainerWithProductTypes({ProductTypeFilter.standard});
      final processed = container.read(processedProductsProvider);
      final products = processed.asData!.value.filteredProducts;

      expect(products.length, 4);
      final productCodes = products.map((p) => p.code).toSet();
      expect(productCodes, equals({'STD1', 'STD2', 'STD3', 'STD4'}));

      // Verify no combo and no service products matched
      expect(products.any((p) => p.isCombo), isFalse);
      expect(
        products.any((p) => p.type?.trim().toLowerCase() == 'dịch vụ'),
        isFalse,
      );
    });

    test('Combination 3: {combo} returns ONLY combo products (including p.isCombo with type="Dịch vụ")', () async {
      final container = await createContainerWithProductTypes({ProductTypeFilter.combo});
      final processed = container.read(processedProductsProvider);
      final products = processed.asData!.value.filteredProducts;

      expect(products.length, 3);
      final productCodes = products.map((p) => p.code).toSet();
      expect(productCodes, equals({'CMB1', 'CMB2', 'CMB3'}));

      // Verify all matched are combos
      expect(products.every((p) => p.isCombo), isTrue);
      // Standard products excluded
      expect(productCodes.intersection({'STD1', 'STD2', 'STD3', 'STD4'}), isEmpty);
    });

    test('Combination 4: {service} returns ONLY service products with diverse casings & whitespaces', () async {
      final container = await createContainerWithProductTypes({ProductTypeFilter.service});
      final processed = container.read(processedProductsProvider);
      final products = processed.asData!.value.filteredProducts;

      expect(products.length, 4);
      final productCodes = products.map((p) => p.code).toSet();
      expect(productCodes, equals({'SRV1', 'SRV2', 'SRV3', 'SRV4'}));

      // None are combos
      expect(products.any((p) => p.isCombo), isFalse);
      // All have type == 'dịch vụ'
      expect(
        products.every((p) => p.type?.trim().toLowerCase() == 'dịch vụ'),
        isTrue,
      );
    });

    test('Combination 5: {standard, combo} returns standard + combo; excludes service', () async {
      final container = await createContainerWithProductTypes({
        ProductTypeFilter.standard,
        ProductTypeFilter.combo,
      });
      final processed = container.read(processedProductsProvider);
      final products = processed.asData!.value.filteredProducts;

      expect(products.length, 7); // 4 standard + 3 combo
      final productCodes = products.map((p) => p.code).toSet();
      expect(
        productCodes,
        equals({'STD1', 'STD2', 'STD3', 'STD4', 'CMB1', 'CMB2', 'CMB3'}),
      );
      // 0 service products
      expect(
        products.any(
            (p) => !p.isCombo && p.type?.trim().toLowerCase() == 'dịch vụ'),
        isFalse,
      );
    });

    test('Combination 6: {standard, service} returns standard + service; excludes combo', () async {
      final container = await createContainerWithProductTypes({
        ProductTypeFilter.standard,
        ProductTypeFilter.service,
      });
      final processed = container.read(processedProductsProvider);
      final products = processed.asData!.value.filteredProducts;

      expect(products.length, 8); // 4 standard + 4 service
      final productCodes = products.map((p) => p.code).toSet();
      expect(
        productCodes,
        equals({'STD1', 'STD2', 'STD3', 'STD4', 'SRV1', 'SRV2', 'SRV3', 'SRV4'}),
      );
      // 0 combo products
      expect(products.any((p) => p.isCombo), isFalse);
    });

    test('Combination 7: {combo, service} returns combo + service; excludes standard', () async {
      final container = await createContainerWithProductTypes({
        ProductTypeFilter.combo,
        ProductTypeFilter.service,
      });
      final processed = container.read(processedProductsProvider);
      final products = processed.asData!.value.filteredProducts;

      expect(products.length, 7); // 3 combo + 4 service
      final productCodes = products.map((p) => p.code).toSet();
      expect(
        productCodes,
        equals({'CMB1', 'CMB2', 'CMB3', 'SRV1', 'SRV2', 'SRV3', 'SRV4'}),
      );
      // 0 standard products
      expect(
        productCodes.intersection({'STD1', 'STD2', 'STD3', 'STD4'}),
        isEmpty,
      );
    });

    test('Combination 8: {standard, combo, service} (all 3) bypasses filtering and returns all 11 products', () async {
      final container = await createContainerWithProductTypes({
        ProductTypeFilter.standard,
        ProductTypeFilter.combo,
        ProductTypeFilter.service,
      });
      final processed = container.read(processedProductsProvider);
      final products = processed.asData!.value.filteredProducts;

      expect(products.length, 11);
      final productCodes = products.map((p) => p.code).toSet();
      expect(
        productCodes,
        equals(allTestProducts.map((p) => p.code).toSet()),
      );
    });

    test('Intersection of multi-category hierarchy + product type filter', () async {
      // Select parent category 'Thiết bị điện tử' which has subcategories 'Máy tính', 'Phụ kiện', 'Âm thanh'
      // And select product type 'combo'
      // Expected matching combos under 'Thiết bị điện tử' or its subcategories:
      // - pCmb1 ('Bộ PC Gaming', under 'Máy tính')
      // - pCmb2 ('Combo Phím Chuột', under 'Phụ kiện')
      // Note: pCmb3 is under 'Dịch vụ kỹ thuật', NOT under 'Thiết bị điện tử', so pCmb3 should NOT match!
      final container = await createContainerWithProductTypes(
        {ProductTypeFilter.combo},
        categories: {'Thiết bị điện tử'},
      );
      final processed = container.read(processedProductsProvider);
      final products = processed.asData!.value.filteredProducts;

      expect(products.length, 2);
      final codes = products.map((p) => p.code).toSet();
      expect(codes, equals({'CMB1', 'CMB2'}));

      // Now test empty intersection: 'Đồ gỗ & Nội thất' has 0 products
      final emptyContainer = await createContainerWithProductTypes(
        {ProductTypeFilter.combo},
        categories: {'Đồ gỗ & Nội thất'},
      );
      final emptyProcessed = emptyContainer.read(processedProductsProvider);
      expect(emptyProcessed.asData!.value.filteredProducts, isEmpty);
    });

    testWidgets('UI interaction: toggling product types through bottom sheet filters list reactively', (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(userSupervisor)),
            categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
            productListProvider.overrideWith((ref) => Stream.value(allTestProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // All 11 products initially displayed
      expect(find.byType(ProductTile), findsNWidgets(11));

      // Open product type bottom sheet
      final typeBtn = find.byKey(const Key('product_type_filter_button'));
      expect(typeBtn, findsOneWidget);
      await tester.tap(typeBtn);
      await tester.pumpAndSettle();

      // Verify bottom sheet title and checkboxes
      expect(find.text('Chọn loại hàng'), findsOneWidget);
      final standardCb = find.byKey(const Key('product_type_checkbox_standard'));
      final comboCb = find.byKey(const Key('product_type_checkbox_combo'));
      final serviceCb = find.byKey(const Key('product_type_checkbox_service'));
      expect(standardCb, findsOneWidget);
      expect(comboCb, findsOneWidget);
      expect(serviceCb, findsOneWidget);

      // Uncheck standard and combo, leaving only service
      await tester.tap(standardCb);
      await tester.pumpAndSettle();
      await tester.tap(comboCb);
      await tester.pumpAndSettle();

      // Close bottom sheet by tapping outside
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Now only 4 service products are visible
      expect(find.byType(ProductTile), findsNWidgets(4));
      expect(find.text('Dịch vụ Cài đặt Hệ điều hành Windows & Office'), findsOneWidget);
      expect(find.text('Vệ sinh laptop tra keo tản nhiệt'), findsOneWidget);

      // Quick clear button 'X' should now appear next to 'Dịch vụ' label
      final clearTypeBtn = find.byKey(const Key('clear_product_type_filter_button'));
      expect(clearTypeBtn, findsOneWidget);

      // Tap 'X' to reset product types to all 3
      await tester.tap(clearTypeBtn);
      await tester.pumpAndSettle();

      // All 11 products reappear
      expect(find.byType(ProductTile), findsNWidgets(11));
      expect(find.byKey(const Key('clear_product_type_filter_button')), findsNothing);
    });
  });

  // =========================================================================
  // GROUP 2: Cold-Start Serialization and Persistence Roundtrip
  // =========================================================================
  group('Cold-Start Serialization & Persistence Roundtrip Suite', () {
    test('Simulate cold-start app restart: providers re-hydrate saved selectedCategories and productTypes', () async {
      // Pre-seed disk storage simulating a prior app session for supervisor
      SharedPreferences.setMockInitialValues({
        'filter_prefs_supervisor_products': jsonEncode({
          'selectedCategories': ['Phụ kiện', 'Âm thanh'],
          'productTypes': ['combo', 'service'],
          'category': 'All',
          'stockStatus': 'inStock',
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      FilterStorageService.setSharedPrefs(prefs);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(userSupervisor)),
          categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
          productListProvider.overrideWith((ref) => Stream.value(allTestProducts)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(productListProvider.future);

      // Verify productSelectedCategoriesProvider hydrates saved categories
      final hydratedCategories = container.read(productSelectedCategoriesProvider);
      expect(hydratedCategories, equals({'Phụ kiện', 'Âm thanh'}));

      // Verify productTypeFilterProvider hydrates saved types
      final hydratedTypes = container.read(productTypeFilterProvider);
      expect(
        hydratedTypes,
        equals({ProductTypeFilter.combo, ProductTypeFilter.service}),
      );

      // Verify stockStatus is hydrated
      final hydratedStock = container.read(productStockStatusFilterProvider);
      expect(hydratedStock, StockStatus.inStock);

      // Verify processed products match the combination:
      // Category: 'Phụ kiện' OR 'Âm thanh'
      // AND ProductType: combo OR service
      // Matching:
      // - pCmb2 ('Combo Phím Chuột Không Dây Văn Phòng', Phụ kiện, Combo)
      final processed = container.read(processedProductsProvider);
      final products = processed.asData!.value.filteredProducts;
      expect(products.length, 1);
      expect(products.first.code, 'CMB2');
    });

    test('Cold start backward compatibility: legacy schema with category only re-hydrates both legacy and multi-select', () async {
      SharedPreferences.setMockInitialValues({
        'filter_prefs_supervisor_products': jsonEncode({
          'category': 'Máy tính',
          'stockStatus': 'all',
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      FilterStorageService.setSharedPrefs(prefs);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(userSupervisor)),
          categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
          productListProvider.overrideWith((ref) => Stream.value(allTestProducts)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(productListProvider.future);

      expect(container.read(productCategoryFilterProvider), 'Máy tính');
      expect(container.read(productSelectedCategoriesProvider), equals({'Máy tính'}));
      // Product types default to all 3
      expect(
        container.read(productTypeFilterProvider),
        equals({
          ProductTypeFilter.standard,
          ProductTypeFilter.combo,
          ProductTypeFilter.service,
        }),
      );
    });

    test('Resilience to corrupted, malformed, and anomalous disk values on cold-start', () async {
      SharedPreferences.setMockInitialValues({
        'filter_prefs_supervisor_products': jsonEncode({
          'selectedCategories': ['All', '   ', '', 'null', 'Phụ kiện'],
          'productTypes': ['invalid_type_abc', 'standard', 9999, 'combo'],
          'stockStatus': 'non_existent_stock_status',
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      FilterStorageService.setSharedPrefs(prefs);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(userSupervisor)),
          categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
          productListProvider.overrideWith((ref) => Stream.value(allTestProducts)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(productListProvider.future);

      // Invalid category tokens ('All', '', 'null') filtered out, leaving only 'Phụ kiện'
      expect(container.read(productSelectedCategoriesProvider), equals({'Phụ kiện'}));

      // Valid product types ('standard', 'combo') preserved; invalid ignored
      expect(
        container.read(productTypeFilterProvider),
        equals({ProductTypeFilter.standard, ProductTypeFilter.combo}),
      );

      // Invalid stock status defaults to StockStatus.all
      expect(container.read(productStockStatusFilterProvider), StockStatus.all);
    });

    test('Corrupted JSON syntax on disk self-heals without unhandled exceptions', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'filter_prefs_supervisor_products',
        '<<<CORRUPTED_NON_JSON_PAYLOAD>>><<>',
      );
      FilterStorageService.setSharedPrefs(prefs);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(userSupervisor)),
          categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
          productListProvider.overrideWith((ref) => Stream.value(allTestProducts)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(productListProvider.future);

      // Safely falls back to clean default states
      expect(container.read(productSelectedCategoriesProvider), isEmpty);
      expect(
        container.read(productTypeFilterProvider),
        equals({
          ProductTypeFilter.standard,
          ProductTypeFilter.combo,
          ProductTypeFilter.service,
        }),
      );
    });

    test('Roundtrip fidelity: saveFilter -> loadFilterSync -> loadFilter retains identical structures', () async {
      final service = FilterStorageService();
      final filtersToSave = {
        'category': 'Phụ kiện',
        'selectedCategories': ['Phụ kiện', 'Âm thanh'],
        'productTypes': ['standard', 'service'],
        'stockStatus': 'belowMinStock',
      };

      final saved = await service.saveFilter('products', filtersToSave, 'supervisor');
      expect(saved, isTrue);

      // Instant synchronous read-your-writes check
      final syncLoaded = service.loadFilterSync('products', 'supervisor');
      expect(syncLoaded, isNotNull);
      expect(syncLoaded!['selectedCategories'], equals(['Phụ kiện', 'Âm thanh']));
      expect(syncLoaded['productTypes'], equals(['standard', 'service']));
      expect(syncLoaded['stockStatus'], 'belowMinStock');

      // Async load check
      final asyncLoaded = await service.loadFilter('products', 'supervisor');
      expect(asyncLoaded, isNotNull);
      expect(asyncLoaded!['selectedCategories'], equals(['Phụ kiện', 'Âm thanh']));
      expect(asyncLoaded['productTypes'], equals(['standard', 'service']));
    });

    test('Centralized rehydrateAllUserFilters hydrates all product filter providers accurately', () async {
      final service = FilterStorageService();
      await service.saveFilter('products', {
        'selectedCategories': ['Phụ kiện'],
        'productTypes': ['service'],
        'stockStatus': 'outOfStock',
      }, 'supervisor');

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(userSupervisor)),
          categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
          productListProvider.overrideWith((ref) => Stream.value(allTestProducts)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(productListProvider.future);

      // Explicitly trigger centralized rehydration
      await rehydrateAllUserFilters(container, userSupervisor);

      expect(container.read(productSelectedCategoriesProvider), equals({'Phụ kiện'}));
      expect(container.read(productTypeFilterProvider), equals({ProductTypeFilter.service}));
      expect(container.read(productStockStatusFilterProvider), StockStatus.outOfStock);
    });
  });

  // =========================================================================
  // GROUP 3: Reset Button Semantics and Verification
  // =========================================================================
  group('1-Tap "Đặt lại" Reset Button Semantics Suite', () {
    testWidgets('Tapping "Đặt lại" resets category to "All", selectedCategories to empty, productTypes to all 3, and purges disk cache', (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // Pre-seed non-default filter preferences
      SharedPreferences.setMockInitialValues({
        'filter_prefs_supervisor_products': jsonEncode({
          'selectedCategories': ['Phụ kiện'],
          'productTypes': ['combo'],
          'category': 'Phụ kiện',
          'stockStatus': 'inStock',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(userSupervisor)),
            categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
            productListProvider.overrideWith((ref) => Stream.value(allTestProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Under initial active filters:
      // Category: 'Phụ kiện' AND Type: combo -> pCmb2 ('Combo Phím Chuột Không Dây Văn Phòng')
      expect(find.text('Combo Phím Chuột Không Dây Văn Phòng'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      // Verify Reset button exists with "Đặt lại" text
      final resetBtn = find.byKey(const Key('reset_product_filters_button'));
      expect(resetBtn, findsOneWidget);
      expect(find.descendant(of: resetBtn, matching: find.text('Đặt lại')), findsOneWidget);

      // Tap Reset button
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      // All 11 products should now be displayed
      expect(find.byType(ProductTile), findsNWidgets(11));

      // Reset button should disappear
      expect(find.byKey(const Key('reset_product_filters_button')), findsNothing);

      // Disk storage key should be deleted
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('filter_prefs_supervisor_products'), isFalse);
    });

    testWidgets('Reset button badge count: hides badge pill when activeFilterCount == 1, displays count pill when activeFilterCount > 1', (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // Scenario A: Only 1 filter active (productTypes = combo)
      SharedPreferences.setMockInitialValues({
        'filter_prefs_supervisor_products': jsonEncode({
          'productTypes': ['combo'],
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(userSupervisor)),
            categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
            productListProvider.overrideWith((ref) => Stream.value(allTestProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final resetBtn = find.byKey(const Key('reset_product_filters_button'));
      expect(resetBtn, findsOneWidget);
      expect(find.descendant(of: resetBtn, matching: find.text('Đặt lại')), findsOneWidget);
      // When activeFilterCount == 1, no count badge pill should exist
      expect(find.descendant(of: resetBtn, matching: find.text('1')), findsNothing);

      // Scenario B: 2 filters active (productTypes = combo AND category = Phụ kiện)
      await tester.tap(find.byKey(const Key('product_category_dropdown')));
      await tester.pumpAndSettle();

      // Open bottom sheet
      expect(find.byType(CategoryFilterBottomSheet), findsOneWidget);
      // Expand all categories to reveal child node 'Phụ kiện'
      await tester.tap(find.byKey(const Key('expand_all_categories_button')));
      await tester.pumpAndSettle();
      // Tap 'Phụ kiện' item to select it
      await tester.tap(find.text('Phụ kiện').last);
      await tester.pumpAndSettle();

      // Now 2 filters are active: badge pill with '2' must appear
      expect(find.descendant(of: resetBtn, matching: find.text('2')), findsOneWidget);
    });

    testWidgets('CategoryFilterBottomSheet: tapping "Bỏ chọn" resets selection and "Áp dụng" updates products', (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // Start with selected category 'Phụ kiện'
      SharedPreferences.setMockInitialValues({
        'filter_prefs_supervisor_products': jsonEncode({
          'selectedCategories': ['Phụ kiện'],
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(userSupervisor)),
            categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
            productListProvider.overrideWith((ref) => Stream.value(allTestProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Open bottom sheet
      await tester.tap(find.byKey(const Key('product_category_dropdown')));
      await tester.pumpAndSettle();

      // Tap "Bỏ chọn" button (reset_category_filter_button)
      final resetCatBtn = find.byKey(const Key('reset_category_filter_button'));
      expect(resetCatBtn, findsOneWidget);
      await tester.tap(resetCatBtn);
      await tester.pumpAndSettle();

      // Tap "Áp dụng" button (apply_category_filter_button)
      final applyCatBtn = find.byKey(const Key('apply_category_filter_button'));
      expect(applyCatBtn, findsOneWidget);
      await tester.tap(applyCatBtn);
      await tester.pumpAndSettle();

      // All 11 products should now be displayed
      expect(find.byType(ProductTile), findsNWidgets(11));
    });

    testWidgets('Cold start after reset confirms clean slate state persists', (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // Pre-seed storage
      SharedPreferences.setMockInitialValues({
        'filter_prefs_supervisor_products': jsonEncode({
          'selectedCategories': ['Máy tính'],
          'productTypes': ['combo'],
          'stockStatus': 'all',
        }),
      });

      // Session 1: Mount and tap Reset
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(userSupervisor)),
            categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
            productListProvider.overrideWith((ref) => Stream.value(allTestProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final resetBtn = find.byKey(const Key('reset_product_filters_button'));
      expect(resetBtn, findsOneWidget);
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reset_product_filters_button')), findsNothing);

      // Unmount completely
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Session 2: Fresh cold-start mount
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(userSupervisor)),
            categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
            productListProvider.overrideWith((ref) => Stream.value(allTestProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Blank slate maintained: all 11 products shown, 0 active filters
      expect(find.byType(ProductTile), findsNWidgets(11));
      expect(find.byKey(const Key('reset_product_filters_button')), findsNothing);
    });
  });

  // =========================================================================
  // GROUP 4: Multi-User Isolation on Same Device
  // =========================================================================
  group('Multi-User Isolation Suite (Same Device / Multi-Tenant)', () {
    test('User A and User B maintain completely isolated filter configurations on disk', () async {
      final service = FilterStorageService();

      // User Alpha saves preferences
      await service.saveFilter('products', {
        'selectedCategories': ['Phụ kiện'],
        'productTypes': ['standard'],
        'stockStatus': 'inStock',
      }, userAlpha.username);

      // User Beta saves completely different preferences
      await service.saveFilter('products', {
        'selectedCategories': ['Máy tính', 'Dịch vụ kỹ thuật'],
        'productTypes': ['combo', 'service'],
        'stockStatus': 'outOfStock',
      }, userBeta.username);

      // Verify User Alpha loads only User Alpha's filters
      final alphaData = await service.loadFilter('products', userAlpha.username);
      expect(alphaData, isNotNull);
      expect(alphaData!['selectedCategories'], equals(['Phụ kiện']));
      expect(alphaData['productTypes'], equals(['standard']));
      expect(alphaData['stockStatus'], 'inStock');

      // Verify User Beta loads only User Beta's filters
      final betaData = await service.loadFilter('products', userBeta.username);
      expect(betaData, isNotNull);
      expect(betaData!['selectedCategories'], equals(['Máy tính', 'Dịch vụ kỹ thuật']));
      expect(betaData['productTypes'], equals(['combo', 'service']));
      expect(betaData['stockStatus'], 'outOfStock');

      // Inspect underlying SharedPreferences keys
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('filter_prefs_user_alpha_products'), isTrue);
      expect(prefs.containsKey('filter_prefs_user_beta_products'), isTrue);

      final rawAlpha = jsonDecode(prefs.getString('filter_prefs_user_alpha_products')!);
      final rawBeta = jsonDecode(prefs.getString('filter_prefs_user_beta_products')!);
      expect(rawAlpha['productTypes'], equals(['standard']));
      expect(rawBeta['productTypes'], equals(['combo', 'service']));
    });

    test('User Alpha clearing filters does NOT delete or pollute User Beta filters', () async {
      final service = FilterStorageService();

      await service.saveFilter('products', {
        'selectedCategories': ['Phụ kiện'],
        'productTypes': ['standard'],
      }, userAlpha.username);

      await service.saveFilter('products', {
        'selectedCategories': ['Máy tính'],
        'productTypes': ['combo'],
      }, userBeta.username);

      // User Alpha resets filters
      await service.clearFilter('products', userAlpha.username);

      // User Alpha filters are gone
      expect(await service.loadFilter('products', userAlpha.username), isNull);
      expect(service.loadFilterSync('products', userAlpha.username), isNull);

      // User Beta filters remain completely intact!
      final betaData = await service.loadFilter('products', userBeta.username);
      expect(betaData, isNotNull);
      expect(betaData!['selectedCategories'], equals(['Máy tính']));
      expect(betaData['productTypes'], equals(['combo']));
    });

    test('Legacy admin user mirroring does NOT contaminate non-legacy cashier user', () async {
      final service = FilterStorageService();

      // Admin (legacy user) saves filter -> mirrors to global filter_prefs_products
      await service.saveFilter('products', {
        'selectedCategories': ['Âm thanh'],
        'productTypes': ['combo'],
      }, userAdmin.username);

      // Cashier (non-legacy user) saves filter
      await service.saveFilter('products', {
        'selectedCategories': ['Phụ kiện'],
        'productTypes': ['service'],
      }, userAlpha.username);

      // Read for Cashier returns Cashier's data, NOT Admin's legacy mirror!
      final cashierData = await service.loadFilter('products', userAlpha.username);
      expect(cashierData!['selectedCategories'], equals(['Phụ kiện']));
      expect(cashierData['productTypes'], equals(['service']));

      // Resetting Cashier filter does NOT affect Admin's saved preferences
      await service.clearFilter('products', userAlpha.username);
      final adminData = await service.loadFilter('products', userAdmin.username);
      expect(adminData, isNotNull);
      expect(adminData!['selectedCategories'], equals(['Âm thanh']));
    });

    test('Switching logged-in user dynamically hydrates corresponding user preferences in Riverpod', () async {
      final service = FilterStorageService();

      await service.saveFilter('products', {
        'selectedCategories': ['Phụ kiện'],
        'productTypes': ['standard'],
        'stockStatus': 'inStock',
      }, userAlpha.username);

      await service.saveFilter('products', {
        'selectedCategories': ['Máy tính'],
        'productTypes': ['combo', 'service'],
        'stockStatus': 'outOfStock',
      }, userBeta.username);

      final authNotifier = _FakeAuthNotifier(userAlpha);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
          productListProvider.overrideWith((ref) => Stream.value(allTestProducts)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(productListProvider.future);

      // User Alpha is active
      expect(container.read(productSelectedCategoriesProvider), equals({'Phụ kiện'}));
      expect(container.read(productTypeFilterProvider), equals({ProductTypeFilter.standard}));

      // Switch active user to User Beta
      authNotifier.setUser(userBeta);
      await rehydrateAllUserFilters(container, userBeta);

      // Providers now reflect User Beta
      expect(container.read(productSelectedCategoriesProvider), equals({'Máy tính'}));
      expect(
        container.read(productTypeFilterProvider),
        equals({ProductTypeFilter.combo, ProductTypeFilter.service}),
      );
      expect(container.read(productStockStatusFilterProvider), StockStatus.outOfStock);

      // Switch back to User Alpha
      authNotifier.setUser(userAlpha);
      await rehydrateAllUserFilters(container, userAlpha);

      // Providers restore User Alpha
      expect(container.read(productSelectedCategoriesProvider), equals({'Phụ kiện'}));
      expect(container.read(productTypeFilterProvider), equals({ProductTypeFilter.standard}));
      expect(container.read(productStockStatusFilterProvider), StockStatus.inStock);
    });

    test('Usernames with dots, special symbols, and email addresses are properly sanitized and isolated', () async {
      final service = FilterStorageService();

      await service.saveFilter('products', {
        'selectedCategories': ['Âm thanh'],
        'productTypes': ['service'],
      }, userSpecial.username);

      // Load for special user
      final specialData = await service.loadFilter('products', userSpecial.username);
      expect(specialData, isNotNull);
      expect(specialData!['selectedCategories'], equals(['Âm thanh']));
      expect(specialData['productTypes'], equals(['service']));

      // Verify sanitized key in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final expectedKey = FilterStorageService.resolveKey('products', userSpecial.username);
      expect(prefs.containsKey(expectedKey), isTrue);

      // Ensure no collision with regular supervisor
      expect(await service.loadFilter('products', userSupervisor.username), isNull);
    });

    test('Concurrent high-volume writes across distinct users maintain data integrity without crosstalk', () async {
      final service = FilterStorageService();
      final futures = <Future<bool>>[];

      for (var i = 0; i < 30; i++) {
        futures.add(service.saveFilter('products', {
          'index': i,
          'user': 'alpha',
          'productTypes': ['combo'],
        }, userAlpha.username));

        futures.add(service.saveFilter('products', {
          'index': i,
          'user': 'beta',
          'productTypes': ['service'],
        }, userBeta.username));
      }

      await Future.wait(futures);

      final alphaFinal = await service.loadFilter('products', userAlpha.username);
      final betaFinal = await service.loadFilter('products', userBeta.username);

      expect(alphaFinal!['user'], 'alpha');
      expect(alphaFinal['productTypes'], equals(['combo']));

      expect(betaFinal!['user'], 'beta');
      expect(betaFinal['productTypes'], equals(['service']));
    });
  });
}
