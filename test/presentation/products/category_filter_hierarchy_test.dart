import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
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
  final List<Category> _list;
  _FakeCategoryRepo(this._list);

  @override
  Stream<List<Category>> watchAll() => Stream.value(_list);

  @override
  Future<List<Category>> fetchAll() async => _list;

  @override
  Future<void> upsert(Category category) async {}

  @override
  Future<void> delete(String id) async {}
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
    username: 'test_user',
    displayName: 'Người Dùng Test',
    role: 'admin',
    storeId: 'store_001',
  );

  final testCategories = [
    const Category(id: 'cat_beverage', name: 'Bia, Nước ngọt'),
    const Category(
        id: 'cat_soda', name: 'Nước ngọt có ga', parentId: 'cat_beverage'),
    const Category(
        id: 'cat_water', name: 'Nước khoáng', parentId: 'cat_beverage'),
    const Category(id: 'cat_food', name: 'Thực phẩm khô'),
  ];

  final testProducts = [
    const Product(
      id: 'p_parent',
      name: 'Bia Heineken Silver',
      code: 'BEER01',
      price: 20000,
      costPrice: 15000,
      branchStocks: {'b1': 50},
      category: 'Bia, Nước ngọt',
      category3Levels: 'Bia, Nước ngọt',
    ),
    const Product(
      id: 'p_child1',
      name: 'Coca Cola Sleek 330ml',
      code: 'COKE01',
      price: 10000,
      costPrice: 7000,
      branchStocks: {'b1': 30},
      category: 'Nước ngọt có ga',
      category3Levels: 'Bia, Nước ngọt >> Nước ngọt có ga',
    ),
    const Product(
      id: 'p_child2',
      name: 'Nước suối Aquafina 500ml',
      code: 'AQUA01',
      price: 6000,
      costPrice: 4000,
      branchStocks: {'b1': 40},
      category: 'Nước khoáng',
      category3Levels: 'Bia, Nước ngọt >> Nước khoáng',
    ),
    const Product(
      id: 'p_food',
      name: 'Mì gói Hảo Hảo Tôm Chua Cay',
      code: 'MIGOI01',
      price: 4500,
      costPrice: 3500,
      branchStocks: {'b1': 100},
      category: 'Thực phẩm khô',
      category3Levels: 'Thực phẩm khô',
    ),
  ];

  Widget buildTestApp({List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
        currentStoreIdProvider.overrideWith((ref) => 'store_001'),
        categoryRepositoryProvider
            .overrideWithValue(_FakeCategoryRepo(testCategories)),
        categoryListProvider
            .overrideWith((ref) => Stream.value(testCategories)),
        productListProvider.overrideWith((ref) => Stream.value(testProducts)),
        productRepositoryProvider.overrideWithValue(_FakeProductRepo()),
        ...overrides,
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('vi'),
        home: ProductsPage(),
      ),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'R1: Selecting Parent Category filters parent and all child products',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    // All 4 products initially visible
    expect(find.byType(ProductTile), findsNWidgets(4));

    // Tap category filter
    final catDropdown = find.byKey(const Key('product_category_dropdown'));
    await tester.tap(catDropdown);
    await tester.pumpAndSettle();

    // Bottom sheet is displayed
    expect(find.byType(CategoryFilterBottomSheet), findsOneWidget);
    expect(find.text('Chọn nhóm hàng'), findsOneWidget);

    // Tap Parent Category: 'Bia, Nước ngọt'
    await tester.tap(find.text('Bia, Nước ngọt').last);
    await tester.pumpAndSettle();

    // Should display Heineken (parent), Coca (child1), and Aquafina (child2), but NOT Mì gói
    expect(find.byType(ProductTile), findsNWidgets(3));
    expect(find.text('Bia Heineken Silver'), findsOneWidget);
    expect(find.text('Coca Cola Sleek 330ml'), findsOneWidget);
    expect(find.text('Nước suối Aquafina 500ml'), findsOneWidget);
    expect(find.text('Mì gói Hảo Hảo Tôm Chua Cay'), findsNothing);
  });

  testWidgets(
      'R1: Selecting Specific Child Category filters only products belonging to that child',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    final catDropdown = find.byKey(const Key('product_category_dropdown'));
    await tester.tap(catDropdown);
    await tester.pumpAndSettle();

    // Expand tree to show child categories
    await tester.tap(find.byKey(const Key('expand_all_categories_button')));
    await tester.pumpAndSettle();

    // Select Child: 'Nước ngọt có ga'
    await tester.tap(find.text('Nước ngọt có ga').last);
    await tester.pumpAndSettle();

    // Only Coca Cola is shown
    expect(find.byType(ProductTile), findsOneWidget);
    expect(find.text('Coca Cola Sleek 330ml'), findsOneWidget);
    expect(find.text('Nước suối Aquafina 500ml'), findsNothing);
    expect(find.text('Bia Heineken Silver'), findsNothing);
  });

  testWidgets(
      'R1: Tapping "Tất cả nhóm hàng" in Bottom Sheet shows all products',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'filter_prefs_test_user_products': jsonEncode({
        'category': 'Nước khoáng',
        'stockStatus': 'all',
      }),
    });

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    // Initially only 1 product (Aquafina)
    expect(find.byType(ProductTile), findsOneWidget);

    // Open bottom sheet
    await tester.tap(find.byKey(const Key('product_category_dropdown')));
    await tester.pumpAndSettle();

    // Tap "Tất cả nhóm hàng"
    await tester.tap(find.byKey(const Key('category_item_all')));
    await tester.pumpAndSettle();

    // All 4 products visible
    expect(find.byType(ProductTile), findsNWidgets(4));
  });

  testWidgets(
      'R1: Clear "X" button on horizontal filter bar resets category filter to All',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'filter_prefs_test_user_products': jsonEncode({
        'category': 'Nước ngọt có ga',
        'stockStatus': 'all',
      }),
    });

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(find.byType(ProductTile), findsOneWidget);

    // Tap clear "X" button
    final clearBtn = find.byKey(const Key('clear_category_filter_button'));
    expect(clearBtn, findsOneWidget);
    await tester.tap(clearBtn);
    await tester.pumpAndSettle();

    // All 4 products visible
    expect(find.byType(ProductTile), findsNWidgets(4));

    // Storage is updated with All
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('filter_prefs_test_user_products');
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['category'], 'All');
  });

  testWidgets(
      'R1: Shortcut button "Quản lý" in Bottom Sheet navigates to CategoriesManagementPage',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('product_category_dropdown')));
    await tester.pumpAndSettle();

    final manageBtn = find.byKey(const Key('manage_categories_button'));
    expect(manageBtn, findsOneWidget);
    await tester.tap(manageBtn);
    await tester.pumpAndSettle();

    expect(find.byType(CategoriesManagementPage), findsOneWidget);
  });
}
