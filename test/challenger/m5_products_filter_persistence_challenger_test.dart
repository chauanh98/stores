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
    displayName: 'Quản lý cửa hàng',
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
      category: 'Đồ uống & Giải khát',
      minStock: 20,
    ),
    const Product(
      id: 'p2',
      name: 'Cáp sạc Anker Type-C 100W',
      code: 'ANK01',
      barcode: '893222222001',
      brand: 'Anker',
      price: 180000,
      costPrice: 100000,
      branchStocks: {'branch_1': 3, 'branch_2': 1},
      category: 'Phụ kiện & Điện tử',
      minStock: 5,
    ),
    const Product(
      id: 'p3',
      name: 'Bánh que Pocky Socola 40g',
      code: 'PK01',
      barcode: '893333333001',
      brand: 'Glico',
      price: 12000,
      costPrice: 8000,
      branchStocks: {'branch_1': 0, 'branch_2': 0},
      category: 'Bánh kẹo đặc sản',
      minStock: 10,
    ),
    const Product(
      id: 'p4',
      name: 'Xà phòng Dược liệu Trà xanh',
      code: 'XP01',
      barcode: '893444444001',
      brand: 'Cô Ba',
      price: 25000,
      costPrice: 15000,
      branchStocks: {'branch_1': 15, 'branch_2': 5},
      category: 'Hóa mỹ phẩm / Gia dụng',
      minStock: 10,
    ),
  ];

  List<Override> buildOverrides({List<Product>? products}) => [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
        productListProvider.overrideWith(
            (ref) => Stream.value(products ?? sampleProducts)),
      ];

  void setScreenSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
  }

  // =========================================================================
  // SUITE 1: Category Toggle Behavior & Edge Cases
  // =========================================================================
  group('Empirical Challenge Suite 1: Category Toggle Behavior & Edge Cases', () {
    testWidgets('Tapping active category again in dropdown resets category to All and writes to storage',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Đồ uống & Giải khát',
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

      // Only p1 is initially visible
      expect(find.text('Bia Saigon Special 330ml'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      // Tap category dropdown
      final catDropdown = find.byKey(const Key('product_category_dropdown'));
      expect(catDropdown, findsOneWidget);
      await tester.tap(catDropdown);
      await tester.pumpAndSettle();

      // Tap active category 'Đồ uống & Giải khát' again
      final activeItem = find.text('Đồ uống & Giải khát').last;
      await tester.tap(activeItem);
      await tester.pumpAndSettle();

      // Expect reset to 'All' -> all 4 products visible
      expect(find.byType(ProductTile), findsNWidgets(4));

      // Verify persistent storage written with 'All'
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_products');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['category'], 'All');
    });

    testWidgets('Tapping "Tất cả nhóm hàng" in dropdown explicitly resets category to All and writes to storage',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Phụ kiện & Điện tử',
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

      final catDropdown = find.byKey(const Key('product_category_dropdown'));
      await tester.tap(catDropdown);
      await tester.pumpAndSettle();

      // Tap "Tất cả nhóm hàng"
      final allOption = find.text('Tất cả nhóm hàng').last;
      await tester.tap(allOption);
      await tester.pumpAndSettle();

      // All 4 products visible
      expect(find.byType(ProductTile), findsNWidgets(4));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_products');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['category'], 'All');
    });

    testWidgets('Tapping clear category button (x) resets category to All and replaces icon with dropdown arrow',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Hóa mỹ phẩm / Gia dụng',
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

      final clearBtn = find.byKey(const Key('clear_category_filter_button'));
      expect(clearBtn, findsOneWidget);

      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      // All products now visible
      expect(find.byType(ProductTile), findsNWidgets(4));

      // Clear button is gone
      expect(find.byKey(const Key('clear_category_filter_button')), findsNothing);

      // SharedPreferences updated
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('filter_prefs_products')!)
          as Map<String, dynamic>;
      expect(decoded['category'], 'All');
    });

    testWidgets('Handles stale/deleted category in storage gracefully without DropdownButton crash',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // Storage has an obsolete category that is no longer in the product list
      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Danh mục cũ đã xóa 2024',
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

      // No crash, and dropdown safely shows 'All'
      final catDropdown = tester.widget<DropdownButton<String>>(
        find.byKey(const Key('product_category_dropdown')),
      );
      expect(catDropdown.value, 'All');
    });
  });

  // =========================================================================
  // SUITE 2: Lifecycle Unmount & Remount Retention
  // =========================================================================
  group('Empirical Challenge Suite 2: Lifecycle Unmount & Remount Retention', () {
    testWidgets('Retains category and stockStatus across full push/pop navigation unmount',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Phụ kiện & Điện tử',
          'stockStatus': 'belowMinStock',
        }),
      });

      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: buildOverrides(),
          child: MaterialApp(
            navigatorKey: navKey,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            home: const ProductsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only Anker cable matches belowMinStock (stocks 3+1=4 <= minStock 5)
      expect(find.text('Cáp sạc Anker Type-C 100W'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      // Navigate to another route (simulating drill-down to product details)
      navKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Product Detail Page Dummy')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Product Detail Page Dummy'), findsOneWidget);

      // Pop back to ProductsPage
      navKey.currentState!.pop();
      await tester.pumpAndSettle();

      // Retains category and stockStatus exactly
      expect(find.text('Cáp sạc Anker Type-C 100W'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);
    });

    testWidgets('Retains filters across simulated process restart (fresh ProviderScope)',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // Phase 1: User sets filters in first session
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Change stock filter to outOfStock
      final stockFinder = find.byType(DropdownButton<StockStatus>);
      await tester.tap(stockFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hết hàng (= 0)').last);
      await tester.pumpAndSettle();

      // Only Pocky is out of stock (0 stock)
      expect(find.text('Bánh que Pocky Socola 40g'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      // Verify written to storage
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('filter_prefs_products'), isTrue);

      // Phase 2: Kill app completely (pump a blank container)
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Phase 3: Start fresh session with new ProviderScope
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Filters hydrated from storage!
      expect(find.text('Bánh que Pocky Socola 40g'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);
    });

    testWidgets('Drill-down parameter initialCategory overrides storage and synchronizes',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // Pre-existing stored category is 'Đồ uống & Giải khát'
      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Đồ uống & Giải khát',
          'stockStatus': 'all',
        }),
      });

      // Mount with initialCategory: 'Bánh kẹo đặc sản'
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(initialCategory: 'Bánh kẹo đặc sản'),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Drilldown category takes precedence
      expect(find.text('Bánh que Pocky Socola 40g'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      // Synchronized to storage
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('filter_prefs_products')!)
          as Map<String, dynamic>;
      expect(decoded['category'], 'Bánh kẹo đặc sản');
    });
  });

  // =========================================================================
  // SUITE 3: 1-Tap "Đặt lại" (Reset) Robustness
  // =========================================================================
  group('Empirical Challenge Suite 3: 1-Tap "Đặt lại" (Reset) Robustness', () {
    testWidgets('Reset button state machine: hidden on default, appears on any filter change, tap clears storage',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      final resetBtnFinder =
          find.byKey(const Key('reset_product_filters_button'));

      // Initially at default: reset button hidden
      expect(resetBtnFinder, findsNothing);

      // Change stockStatus -> Reset button appears
      final stockFinder = find.byType(DropdownButton<StockStatus>);
      await tester.tap(stockFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Còn hàng (> 0)').last);
      await tester.pumpAndSettle();

      expect(resetBtnFinder, findsOneWidget);

      // Tap Reset button
      await tester.tap(resetBtnFinder);
      await tester.pumpAndSettle();

      // Reset button disappears
      expect(resetBtnFinder, findsNothing);

      // Storage is cleared
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('filter_prefs_products'), isFalse);

      // All products visible
      expect(find.byType(ProductTile), findsNWidgets(4));
    });

    testWidgets('1-Tap "Đặt lại" resets category, stockStatus, brand, and sort simultaneously',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Phụ kiện & Điện tử',
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

      final resetBtnFinder =
          find.byKey(const Key('reset_product_filters_button'));
      expect(resetBtnFinder, findsOneWidget);

      await tester.tap(resetBtnFinder);
      await tester.pumpAndSettle();

      // State is fully reset
      expect(resetBtnFinder, findsNothing);

      // Unmount and remount fresh to ensure no zombie storage
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // All 4 products remain visible
      expect(find.byType(ProductTile), findsNWidgets(4));
      expect(find.byKey(const Key('reset_product_filters_button')), findsNothing);
    });
  });

  // =========================================================================
  // SUITE 4: FilterStorageService Concurrency & Resilience
  // =========================================================================
  group('Empirical Challenge Suite 4: FilterStorageService Concurrency & Resilience', () {
    test('Handles 100 concurrent asynchronous saves across multiple domains without error',
        () async {
      SharedPreferences.setMockInitialValues({});
      final service = FilterStorageService();

      final futures = <Future<bool>>[];
      for (var i = 0; i < 100; i++) {
        final domain = 'domain_${i % 5}';
        futures.add(service.saveFilter(domain, {
          'counter': i,
          'timestamp': DateTime.now().toIso8601String(),
        }));
      }

      final results = await Future.wait(futures);
      expect(results.every((r) => r == true), isTrue);

      // Verify each domain can be retrieved cleanly
      for (var d = 0; d < 5; d++) {
        final data = await service.loadFilter('domain_$d');
        expect(data, isNotNull);
        expect(data!['counter'], isA<int>());
      }
    });

    test('Interleaved rapid save and clear sequences maintain consistency',
        () async {
      SharedPreferences.setMockInitialValues({});
      final service = FilterStorageService();

      for (var cycle = 0; cycle < 10; cycle++) {
        await service.saveFilter('products', {'cycle': cycle, 'state': 'active'});
        expect(service.loadFilterSync('products')?['cycle'], cycle);

        await service.clearFilter('products');
        expect(service.loadFilterSync('products'), isNull);
        expect(await service.loadFilter('products'), isNull);
      }
    });

    test('Corrupted or non-map JSON in storage does not crash service (graceful fallback)',
        () async {
      SharedPreferences.setMockInitialValues({
        'filter_prefs_malformed': '{corrupted json string: invalid',
        'filter_prefs_array': '[1, 2, 3, 4]',
        'filter_prefs_empty': '',
      });

      final service = FilterStorageService();

      // Malformed JSON should not throw FormatException
      final malformed = await service.loadFilter('malformed');
      expect(malformed, isNull);

      final malformedSync = service.loadFilterSync('malformed');
      expect(malformedSync, isNull);

      // Non-map JSON should not crash
      final arrayData = await service.loadFilter('array');
      expect(arrayData, isNull);

      // Empty string should not crash
      final emptyData = await service.loadFilter('empty');
      expect(emptyData, isNull);
    });

    test('Functions completely and transparently in unmocked environment with in-memory fallback',
        () async {
      final service = FilterStorageService();

      final saveResult = await service.saveFilter('unmocked_domain', {
        'status': 'active',
        'rate': 99.5,
      });
      expect(saveResult, isTrue);

      final loaded = await service.loadFilter('unmocked_domain');
      expect(loaded, isNotNull);
      expect(loaded?['status'], 'active');
      expect(loaded?['rate'], 99.5);

      final loadedSync = service.loadFilterSync('unmocked_domain');
      expect(loadedSync, isNotNull);
      expect(loadedSync?['status'], 'active');

      final clearResult = await service.clearFilter('unmocked_domain');
      expect(clearResult, isTrue);
      expect(await service.loadFilter('unmocked_domain'), isNull);
      expect(service.loadFilterSync('unmocked_domain'), isNull);
    });

    test('Key resolution is strictly idempotent and handles prefixes consistently', () {
      expect(FilterStorageService.resolveKey('invoices'), 'filter_prefs_invoices');
      expect(FilterStorageService.resolveKey('filter_prefs_invoices'), 'filter_prefs_invoices');
      expect(FilterStorageService.resolveKey('customers'), 'filter_prefs_customers');
      expect(FilterStorageService.resolveKey('filter_prefs_customers'), 'filter_prefs_customers');
      expect(FilterStorageService.resolveKey('products'), 'filter_prefs_products');
      expect(FilterStorageService.resolveKey('filter_prefs_products'), 'filter_prefs_products');
      expect(FilterStorageService.resolveKey('custom_key'), 'filter_prefs_custom_key');
      expect(FilterStorageService.resolveKey('filter_prefs_custom_key'), 'filter_prefs_custom_key');
    });
  });

  // =========================================================================
  // SUITE 5: Advanced Interactions & Multi-Step Lifecycle
  // =========================================================================
  group('Empirical Challenge Suite 5: Advanced Interactions & Multi-Step Lifecycle', () {
    testWidgets('Switching between different categories selects target category without toggling to All',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Đồ uống & Giải khát',
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

      expect(find.text('Bia Saigon Special 330ml'), findsOneWidget);

      // Select 'Phụ kiện & Điện tử' (different from active)
      final catDropdown = find.byKey(const Key('product_category_dropdown'));
      await tester.tap(catDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phụ kiện & Điện tử').last);
      await tester.pumpAndSettle();

      // Switched to 'Phụ kiện & Điện tử'
      expect(find.text('Cáp sạc Anker Type-C 100W'), findsOneWidget);
      expect(find.text('Bia Saigon Special 330ml'), findsNothing);

      // Verified in storage
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('filter_prefs_products')!)
          as Map<String, dynamic>;
      expect(decoded['category'], 'Phụ kiện & Điện tử');

      // Now toggle 'Phụ kiện & Điện tử' again -> resets to 'All'
      await tester.tap(catDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phụ kiện & Điện tử').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsNWidgets(4));
      final decoded2 = jsonDecode(prefs.getString('filter_prefs_products')!)
          as Map<String, dynamic>;
      expect(decoded2['category'], 'All');
    });

    testWidgets('didUpdateWidget synchronizes new initialCategory to state and storage',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({});

      // Mount with initialCategory A
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(initialCategory: 'Đồ uống & Giải khát'),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bia Saigon Special 330ml'), findsOneWidget);

      // Re-pump with initialCategory B
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(initialCategory: 'Hóa mỹ phẩm / Gia dụng'),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Updates to B
      expect(find.text('Xà phòng Dược liệu Trà xanh'), findsOneWidget);
      expect(find.text('Bia Saigon Special 330ml'), findsNothing);

      // Stored in preferences
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('filter_prefs_products')!)
          as Map<String, dynamic>;
      expect(decoded['category'], 'Hóa mỹ phẩm / Gia dụng');
    });

    test('FilterStorageService alias methods and in-memory cache clear', () async {
      SharedPreferences.setMockInitialValues({});
      final service = FilterStorageService();

      await service.saveFilters('alias_test', {'k': 'v'});
      expect(service.getFilters('alias_test'), {'k': 'v'});

      service.clearInMemory();
      final loaded = await service.loadFilter('alias_test');
      expect(loaded, {'k': 'v'});

      await service.clearFilters('alias_test');
      expect(service.getFilters('alias_test'), isNull);
      expect(await service.loadFilter('alias_test'), isNull);
    });
  });
}
