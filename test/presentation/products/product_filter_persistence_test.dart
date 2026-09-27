import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
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

  const supervisorUser = UserAccount(
    username: 'supervisor',
    displayName: 'Chủ chuỗi C',
    role: 'supervisor',
    storeId: 'store_001',
  );

  final sampleProducts = [
    const Product(
      id: 'p1',
      name: 'Bia Saigon Special 330ml',
      code: 'BSG01',
      barcode: '893111111001',
      brand: 'Sabeco',
      price: 15000,
      costPrice: 11000,
      branchStocks: {'branch_1': 60, 'branch_2': 40},
      category: 'Đồ uống',
      minStock: 20,
    ),
    const Product(
      id: 'p2',
      name: 'Cáp sạc Anker Type-C',
      code: 'ANK01',
      barcode: '893222222001',
      brand: 'Anker',
      price: 180000,
      costPrice: 100000,
      branchStocks: {'branch_1': 3, 'branch_2': 1},
      category: 'Phụ kiện',
      minStock: 5,
    ),
    const Product(
      id: 'p3',
      name: 'Bánh que Pocky Socola',
      code: 'PK01',
      barcode: '893333333001',
      brand: 'Glico',
      price: 12000,
      costPrice: 8000,
      branchStocks: {'branch_1': 0, 'branch_2': 0},
      category: 'Bánh kẹo',
      minStock: 10,
    ),
  ];

  List<Override> buildOverrides() => [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
        productListProvider.overrideWith((ref) => Stream.value(sampleProducts)),
      ];

  group('ProductsPage Filter State Retention Tests (R4)', () {
    setUp(() {
      FilterStorageService.resetSharedPrefs();
    });

    tearDown(() {
      FilterStorageService.resetSharedPrefs();
    });
    testWidgets('Hydrates category and stockStatus from SharedPreferences on initial build',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Đồ uống',
          'stockStatus': 'inStock',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Only 'Bia Saigon Special 330ml' matches Đồ uống + inStock
      expect(find.text('Bia Saigon Special 330ml'), findsOneWidget);
      expect(find.text('Cáp sạc Anker Type-C'), findsNothing);
      expect(find.text('Bánh que Pocky Socola'), findsNothing);

      // Reset button is visible
      expect(find.byKey(const Key('reset_product_filters_button')),
          findsOneWidget);
      expect(find.text('Đặt lại'), findsOneWidget);
    });

    testWidgets('Persists category and stockStatus when user changes dropdowns',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Select 'Phụ kiện' from Category dropdown
      final catFinder = find.byType(DropdownButton<String>);
      await tester.ensureVisible(catFinder);
      await tester.pumpAndSettle();
      await tester.tap(catFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phụ kiện').last);
      await tester.pumpAndSettle();

      // Verify SharedPreferences updated
      var prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString('filter_prefs_products');
      expect(raw, isNotNull);
      var decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['category'], 'Phụ kiện');

      // Select 'Dưới định mức' from StockStatus dropdown
      final stockFinder = find.byType(DropdownButton<StockStatus>);
      await tester.ensureVisible(stockFinder);
      await tester.pumpAndSettle();
      await tester.tap(stockFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dưới định mức').last);
      await tester.pumpAndSettle();

      // Verify SharedPreferences updated with both
      prefs = await SharedPreferences.getInstance();
      raw = prefs.getString('filter_prefs_products');
      expect(raw, isNotNull);
      decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['category'], 'Phụ kiện');
      expect(decoded['stockStatus'], 'belowMinStock');

      // Only Anker cable is shown
      expect(find.text('Cáp sạc Anker Type-C'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);
    });

    testWidgets('Retains hydrated category and stock filters across unmount / navigation',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Bánh kẹo',
          'stockStatus': 'outOfStock',
        }),
      });

      // Mount app with navigation structure
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: buildOverrides(),
          child: MaterialApp(
            navigatorKey: key,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            home: const ProductsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bánh que Pocky Socola'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      // Push dummy screen
      key.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Dummy Detail Screen')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dummy Detail Screen'), findsOneWidget);

      // Pop back
      key.currentState!.pop();
      await tester.pumpAndSettle();

      // Still filtered to Bánh kẹo & outOfStock
      expect(find.text('Bánh que Pocky Socola'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);
    });

    testWidgets('Category toggle: Tapping active category again resets to All and persists',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Đồ uống',
          'stockStatus': 'all',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget); // Only Bia Saigon

      // Tap category dropdown
      final catFinder = find.byType(DropdownButton<String>);
      await tester.tap(catFinder);
      await tester.pumpAndSettle();

      // Tap 'Đồ uống' again (the active category)
      await tester.tap(find.text('Đồ uống').last);
      await tester.pumpAndSettle();

      // Resets to 'All' -> All 3 products visible
      expect(find.byType(ProductTile), findsNWidgets(3));

      // SharedPreferences updated to 'All'
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_products');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['category'], 'All');
    });

    testWidgets('Category toggle: Tapping "Tất cả nhóm hàng" in dropdown resets category to All and persists',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Đồ uống',
          'stockStatus': 'all',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);

      final catFinder = find.byType(DropdownButton<String>);
      await tester.tap(catFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tất cả nhóm hàng').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsNWidgets(3));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_products');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['category'], 'All');
    });

    testWidgets('Category toggle: Tapping clear button resets category to All',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Phụ kiện',
          'stockStatus': 'all',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);

      // Tap clear button on active category
      final clearBtn = find.byKey(const Key('clear_category_filter_button'));
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      // Resets to 'All'
      expect(find.byType(ProductTile), findsNWidgets(3));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_products');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['category'], 'All');
    });

    testWidgets('1-tap Đặt lại button clears filter_prefs_products and resets filters to defaults',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Bánh kẹo',
          'stockStatus': 'outOfStock',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      final resetBtn = find.byKey(const Key('reset_product_filters_button'));
      expect(resetBtn, findsOneWidget);

      // Tap reset
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      // All 3 products visible
      expect(find.byType(ProductTile), findsNWidgets(3));
      expect(find.byKey(const Key('reset_product_filters_button')),
          findsNothing);

      // SharedPreferences key removed
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('filter_prefs_products'), isFalse);
    });

    testWidgets('Active navigation override (initialCategory != null) updates cache',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Đồ uống',
          'stockStatus': 'all',
        }),
      });

      // Push with initialCategory: 'Phụ kiện'
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(initialCategory: 'Phụ kiện'),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Override takes precedence
      expect(find.text('Cáp sạc Anker Type-C'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      // Cache updated to 'Phụ kiện'
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_products');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['category'], 'Phụ kiện');
    });
  });
}
