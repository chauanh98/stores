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
    displayName: 'Cửa hàng trưởng',
    role: 'supervisor',
    storeId: 'store_001',
  );

  final stressProducts = [
    const Product(
      id: 'sp_1',
      name: 'Bia Heineken Sleek 330ml',
      code: 'HNK01',
      barcode: '893500000001',
      brand: 'Heineken',
      price: 22000,
      costPrice: 17000,
      branchStocks: {'branch_1': 100, 'branch_2': 50},
      category: 'Bia & Rượu',
      minStock: 30,
    ),
    const Product(
      id: 'sp_2',
      name: 'Nước ngọt Coca-Cola 320ml',
      code: 'COCA01',
      barcode: '893500000002',
      brand: 'Coca Cola',
      price: 10000,
      costPrice: 7500,
      branchStocks: {'branch_1': 10, 'branch_2': 5},
      category: 'Giải khát',
      minStock: 25, // low stock: 15 <= 25
    ),
    const Product(
      id: 'sp_3',
      name: 'Bánh gạo One One Vị ngọt 150g',
      code: 'ONE01',
      barcode: '893500000003',
      brand: 'One One',
      price: 28000,
      costPrice: 20000,
      branchStocks: {'branch_1': 0, 'branch_2': 0},
      // out of stock
      category: 'Bánh kẹo',
      minStock: 10,
    ),
    const Product(
      id: 'sp_4',
      name: 'Cáp sạc Baseus 65W GaN',
      code: 'BAS01',
      barcode: '893500000004',
      brand: 'Baseus',
      price: 320000,
      costPrice: 210000,
      branchStocks: {'branch_1': 2, 'branch_2': 1},
      category: 'Phụ kiện',
      minStock: 5, // low stock: 3 <= 5
    ),
  ];

  List<Override> buildOverrides() => [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
        productListProvider.overrideWith((ref) => Stream.value(stressProducts)),
      ];

  void setScreenSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 2800);
    tester.view.devicePixelRatio = 1.0;
  }

  group('Challenger 2 Empirical Tests: Category Toggle and Reset Semantics',
      () {
    testWidgets(
        'Tapping active category in dropdown resets category to "All" and updates persistent storage',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Bia & Rượu',
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

      // Only 'Bia Heineken Sleek 330ml' is displayed initially
      expect(find.text('Bia Heineken Sleek 330ml'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      // Open category dropdown
      final catDropdown = find.byKey(const Key('product_category_dropdown'));
      expect(catDropdown, findsOneWidget);
      await tester.tap(catDropdown);
      await tester.pumpAndSettle();

      // Tap active item again: 'Bia & Rượu'
      final activeItem = find.text('Bia & Rượu').last;
      await tester.tap(activeItem);
      await tester.pumpAndSettle();

      // Category resets to 'All' -> All 4 products now visible
      expect(find.byType(ProductTile), findsNWidgets(4));

      // SharedPreferences updated to 'All'
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_products');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['category'], 'All');
    });

    testWidgets(
        'Tapping "Tất cả nhóm hàng" in dropdown resets category to "All" and preserves stockStatus',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Giải khát',
          'stockStatus': 'belowMinStock',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Initially matches 'Giải khát' AND belowMinStock -> Coca Cola only
      expect(find.text('Nước ngọt Coca-Cola 320ml'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      // Tap category dropdown
      final catDropdown = find.byKey(const Key('product_category_dropdown'));
      await tester.tap(catDropdown);
      await tester.pumpAndSettle();

      // Tap "Tất cả nhóm hàng"
      await tester.tap(find.text('Tất cả nhóm hàng').last);
      await tester.pumpAndSettle();

      // Now all belowMinStock items are visible (Coca Cola + Baseus cable: 2 products)
      expect(find.text('Nước ngọt Coca-Cola 320ml'), findsOneWidget);
      expect(find.text('Cáp sạc Baseus 65W GaN'), findsOneWidget);
      expect(find.byType(ProductTile), findsNWidgets(2));

      // SharedPreferences has category 'All' while maintaining stockStatus 'belowMinStock'
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_products');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['category'], 'All');
      expect(decoded['stockStatus'], 'belowMinStock');
    });

    testWidgets(
        'Tapping "X" clear icon resets category to "All" and removes X icon',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

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

      expect(find.text('Cáp sạc Baseus 65W GaN'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      // Clear icon must exist
      final clearIcon = find.byKey(const Key('clear_category_filter_button'));
      expect(clearIcon, findsOneWidget);

      await tester.tap(clearIcon);
      await tester.pumpAndSettle();

      // All 4 products now visible
      expect(find.byType(ProductTile), findsNWidgets(4));

      // Clear icon no longer present, replaced by normal arrow
      expect(
          find.byKey(const Key('clear_category_filter_button')), findsNothing);

      // SharedPreferences updated to 'All'
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('filter_prefs_products')!)
          as Map<String, dynamic>;
      expect(decoded['category'], 'All');
    });
  });

  group('Challenger 2 Empirical Tests: Unmount and Remount Retention', () {
    testWidgets(
        'Complex filter combination survives full widget unmount and remount lifecycle',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({});

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

      // Select 'Bánh kẹo' from category dropdown
      final catDropdown = find.byKey(const Key('product_category_dropdown'));
      await tester.tap(catDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bánh kẹo').last);
      await tester.pumpAndSettle();

      // Select 'Hết hàng (= 0)' from stock dropdown
      final stockDropdown = find.byType(DropdownButton<StockStatus>);
      await tester.tap(stockDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hết hàng (= 0)').last);
      await tester.pumpAndSettle();

      // Verify matching product
      expect(find.text('Bánh gạo One One Vị ngọt 150g'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      // Unmount ProductsPage by pushing another route
      navKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Another Sub-page')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Another Sub-page'), findsOneWidget);
      expect(find.byType(ProductsPage), findsNothing);

      // Pop back to remount ProductsPage
      navKey.currentState!.pop();
      await tester.pumpAndSettle();

      // Retains category 'Bánh kẹo' and stockStatus 'outOfStock'
      expect(find.text('Bánh gạo One One Vị ngọt 150g'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      // Reset button still visible
      expect(find.byKey(const Key('reset_product_filters_button')),
          findsOneWidget);
    });

    testWidgets(
        'Remounting in a completely fresh ProviderScope hydrates preserved state',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // Pre-seed storage
      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Giải khát',
          'stockStatus': 'belowMinStock',
        }),
      });

      // Mount session 1
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nước ngọt Coca-Cola 320ml'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      // Destroy session completely
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Mount session 2 with brand new ProviderScope
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Still displays preserved state
      expect(find.text('Nước ngọt Coca-Cola 320ml'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);
    });
  });

  group('Challenger 2 Empirical Tests: 1-Tap "Đặt lại" Reset Behavior', () {
    testWidgets(
        '1-Tap "Đặt lại" resets all filters, clears storage key, and hides reset button',
        (tester) async {
      setScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_products': jsonEncode({
          'category': 'Phụ kiện',
          'stockStatus': 'belowMinStock',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Only Baseus cable
      expect(find.text('Cáp sạc Baseus 65W GaN'), findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget);

      final resetBtn = find.byKey(const Key('reset_product_filters_button'));
      expect(resetBtn, findsOneWidget);

      // Tap reset
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      // All 4 products now shown
      expect(find.byType(ProductTile), findsNWidgets(4));

      // Reset button disappears
      expect(
          find.byKey(const Key('reset_product_filters_button')), findsNothing);

      // Storage key completely removed
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('filter_prefs_products'), isFalse);

      // Remounting confirms blank slate defaults
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsNWidgets(4));
      expect(
          find.byKey(const Key('reset_product_filters_button')), findsNothing);
    });
  });

  group(
      'Challenger 2 Empirical Tests: FilterStorageService Concurrency and Robustness',
      () {
    test(
        'Concurrent saves across multiple domains maintain isolation and integrity',
        () async {
      SharedPreferences.setMockInitialValues({});
      final service = FilterStorageService();

      final domains = ['products', 'invoices', 'customers', 'reports'];
      final futures = <Future<bool>>[];

      for (var round = 0; round < 50; round++) {
        for (final domain in domains) {
          futures.add(service.saveFilter(domain, {
            'domain': domain,
            'round': round,
            'timestamp': DateTime.now().microsecondsSinceEpoch,
          }));
        }
      }

      final results = await Future.wait(futures);
      expect(results.every((r) => r == true), isTrue);

      // Verify each domain has its final round data intact
      for (final domain in domains) {
        final data = await service.loadFilter(domain);
        expect(data, isNotNull);
        expect(data!['domain'], domain);
        expect(data['round'], isA<int>());
      }

      // Verify clearing one domain does not affect others
      await service.clearFilter('products');
      expect(await service.loadFilter('products'), isNull);
      expect(service.loadFilterSync('products'), isNull);

      // Invoices, customers, reports remain untouched
      expect(await service.loadFilter('invoices'), isNotNull);
      expect(await service.loadFilter('customers'), isNotNull);
      expect(await service.loadFilter('reports'), isNotNull);
    });

    test(
        'Read-your-writes consistency: loadFilterSync immediately reflects saveFilter without waiting for disk I/O',
        () async {
      SharedPreferences.setMockInitialValues({});
      final service = FilterStorageService();

      // Call saveFilter asynchronously without await
      final saveFuture = service.saveFilter('products', {
        'category': 'InstantCategory',
        'stockStatus': 'inStock',
      });

      // Synchronous read should immediately return the value via in-memory fallback
      final immediateSync = service.loadFilterSync('products');
      expect(immediateSync, isNotNull);
      expect(immediateSync?['category'], 'InstantCategory');

      await saveFuture;

      final postSaveSync = service.loadFilterSync('products');
      expect(postSaveSync?['category'], 'InstantCategory');
    });

    test(
        'Unmocked environment fallback: service operates seamlessly even if SharedPreferences throws',
        () async {
      // In this test, no SharedPreferences mock is configured and service operates on fallback
      final service = FilterStorageService();

      expect(await service.saveFilter('offline_key', {'status': 'offline_ok'}),
          isTrue);
      expect(await service.loadFilter('offline_key'), {'status': 'offline_ok'});
      expect(service.loadFilterSync('offline_key'), {'status': 'offline_ok'});

      expect(await service.clearFilter('offline_key'), isTrue);
      expect(await service.loadFilter('offline_key'), isNull);
      expect(service.loadFilterSync('offline_key'), isNull);
    });

    test('clearFilter is safe and idempotent on non-existent keys', () async {
      SharedPreferences.setMockInitialValues({});
      final service = FilterStorageService();

      expect(await service.clearFilter('non_existent_key'), isTrue);
      expect(
          await service.clearFilter('filter_prefs_non_existent_key'), isTrue);
      expect(await service.loadFilter('non_existent_key'), isNull);
    });
  });
}
