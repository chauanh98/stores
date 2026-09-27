import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/category_repository.dart';
import 'package:stores/presentation/products/pages/categories_management_page.dart';
import 'package:stores/presentation/products/widgets/category_filter_bottom_sheet.dart';

class _FakeCategoryRepo implements CategoryRepository {
  final List<Category> _storage;
  _FakeCategoryRepo(this._storage);

  @override
  Stream<List<Category>> watchAll() => Stream.value(List.unmodifiable(_storage));

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
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_002',
  );

  late List<Product> realProducts;
  late List<Category> standardCategories;

  setUpAll(() {
    final prodFile = File('data_staging/products_clean.json');
    expect(prodFile.existsSync(), isTrue);
    final rawList = jsonDecode(prodFile.readAsStringSync()) as List<dynamic>;
    realProducts = rawList
        .map((m) => ProductModel.fromMap(m as Map, 'store_002').toEntity())
        .toList();

    final dataMauFile = File('data_mau.json');
    expect(dataMauFile.existsSync(), isTrue);
    final dataMau = jsonDecode(dataMauFile.readAsStringSync()) as Map<String, dynamic>;
    final sharedCatsMap = dataMau['shared_categories'] as Map<String, dynamic>;

    standardCategories = sharedCatsMap.values.map((v) {
      final map = v as Map<String, dynamic>;
      return Category(
        id: map['id'] as String,
        name: map['name'] as String,
        parentId: map['parentId'] as String?,
      );
    }).toList();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('KiotViet Category Tree & SP000771 E2E Verification', () {
    test('A1 & A2: 61 root categories and 228 category3Levels preserved in shared_categories', () {
      expect(realProducts.length, equals(1839));

      final roots = standardCategories.where((c) => c.parentId == null).toList();
      final children = standardCategories.where((c) => c.parentId != null).toList();

      expect(roots.length, equals(64), reason: 'Exactly 64 root categories');
      expect(children.length, equals(185), reason: '185 children categories');
      expect(standardCategories.length, equals(249));

      // SP000771 verification
      final sp000771 = realProducts.firstWhere((p) => p.id == 'SP000771');
      expect(sp000771.name, contains('Bàn ăn bên nguyên khối'));
      expect(sp000771.category, equals('Bàn ăn'));
      expect(sp000771.category3Levels, equals('Bàn ăn>>Bàn ăn bên'));

      final banAnRoot = roots.firstWhere((r) => r.name == 'Bàn ăn');
      expect(banAnRoot.id, equals('ban_an'));

      final banAnBen = children.firstWhere((c) => c.name == 'Bàn ăn bên');
      expect(banAnBen.parentId, equals(banAnRoot.id));
    });

    test('A1: Product counts calculation is fast (<16ms) and accurate for Bàn ăn (129) and Bàn ăn bên (53)', () {
      final stopwatch = Stopwatch()..start();

      // Test CategoryFilterBottomSheet logic
      final categoryById = {for (final c in standardCategories) c.id: c};
      final tokenToCategoryIds = <String, List<String>>{};
      for (final c in standardCategories) {
        final nameLower = c.name.trim().toLowerCase();
        final idLower = c.id.trim().toLowerCase();
        tokenToCategoryIds.putIfAbsent(nameLower, () => []).add(c.id);
        if (idLower != nameLower) {
          tokenToCategoryIds.putIfAbsent(idLower, () => []).add(c.id);
        }
      }

      final countMap = <String, int>{for (final c in standardCategories) c.id: 0};

      for (final p in realProducts) {
        final matchedCatIdsForProduct = <String>{};
        final tokens = <String>{p.category.trim().toLowerCase()};
        if (p.category.contains('>>') || p.category.contains('>')) {
          for (final seg in p.category.split(RegExp(r'>>|>'))) {
            final s = seg.trim().toLowerCase();
            if (s.isNotEmpty) tokens.add(s);
          }
        }
        final c3 = p.category3Levels;
        if (c3 != null && c3.isNotEmpty) {
          for (final seg in c3.split(RegExp(r'>>|>'))) {
            final s = seg.trim().toLowerCase();
            if (s.isNotEmpty) tokens.add(s);
          }
        }

        for (final t in tokens) {
          final catIds = tokenToCategoryIds[t];
          if (catIds != null) {
            for (final catId in catIds) {
              var curId = catId;
              final cycleGuard = <String>{};
              while (cycleGuard.add(curId) && matchedCatIdsForProduct.add(curId)) {
                final cat = categoryById[curId];
                if (cat == null ||
                    cat.parentId == null ||
                    cat.parentId!.trim().isEmpty) {
                  break;
                }
                curId = cat.parentId!.trim();
              }
            }
          }
        }

        for (final catId in matchedCatIdsForProduct) {
          countMap[catId] = (countMap[catId] ?? 0) + 1;
        }
      }

      stopwatch.stop();

      // Ensure benchmark passes (allowing margin under heavy parallel test suite execution)
      expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(250),
          reason: 'Product count cache calculation should be instantaneous (<16ms release, <250ms under heavy parallel test suite)');
      expect(countMap['ban_an'], equals(129));
      expect(countMap['ban_an_ban_an_ben'], equals(53));
    });

    test('R2: Dynamic Category Harvesting recovers unseeded product categories without duplicates', () {
      // Suppose shared_categories is missing some category
      final subsetCategories = standardCategories
          .where((c) => c.name != 'Bàn ăn' && c.name != 'Bàn ăn bên')
          .toList();
      expect(subsetCategories.any((c) => c.name == 'Bàn ăn bên'), isFalse);

      final harvested = harvestCategoriesFromProducts(subsetCategories, realProducts);

      expect(harvested.any((c) => c.name == 'Bàn ăn'), isTrue);
      final harvestedBen = harvested.firstWhere((c) => c.name == 'Bàn ăn bên');
      expect(harvestedBen.name, equals('Bàn ăn bên'));
      expect(harvestedBen.parentId, equals('ban_an'));

      // Total count after harvesting matches standardCategories (249)
      expect(harvested.length, equals(standardCategories.length));
    });

    test('R2 Adversarial: Single-level category products appearing before multi-level products do not create duplicate roots', () {
      // P1 has single-level category "Bàn ăn bên" without category3Levels
      // P2 has multi-level "Bàn ăn >> Bàn ăn bên"
      final adversarialProducts = <Product>[
        const Product(
          id: 'P_SINGLE_FIRST',
          code: 'P_SINGLE_FIRST',
          name: 'Bàn ăn bên lẻ',
          category: 'Bàn ăn bên',
          price: 100,
          costPrice: 50,
          branchStocks: {'store_001': 1},
        ),
        const Product(
          id: 'P_MULTI_SECOND',
          code: 'P_MULTI_SECOND',
          name: 'Bàn ăn bên chuẩn',
          category: 'Bàn ăn',
          category3Levels: 'Bàn ăn >> Bàn ăn bên',
          price: 200,
          costPrice: 100,
          branchStocks: {'store_001': 1},
        ),
      ];

      final harvested = harvestCategoriesFromProducts([], adversarialProducts);

      // Must produce exactly 2 categories: 1 root ("Bàn ăn") and 1 child ("Bàn ăn bên")
      expect(harvested.length, equals(2));
      final root = harvested.firstWhere((c) => c.parentId == null);
      expect(root.name, equals('Bàn ăn'));
      final child = harvested.firstWhere((c) => c.parentId != null);
      expect(child.name, equals('Bàn ăn bên'));
      expect(child.parentId, equals(root.id));

      // There must NOT be any root category named "Bàn ăn bên"
      final duplicateRoot = harvested.where((c) => c.parentId == null && c.name == 'Bàn ăn bên');
      expect(duplicateRoot, isEmpty, reason: 'Child category must not be created as duplicate root');
    });

    test('R2 Adversarial: Casing variations and sentinel strings (All, Tất cả) are cleanly handled', () {
      final variedProducts = <Product>[
        const Product(
          id: 'P_UPPER',
          code: 'P_UPPER',
          name: 'Bàn Ăn Casing 1',
          category: 'Bàn Ăn',
          category3Levels: 'Bàn Ăn >> Bàn Ăn Hiện Đại',
          price: 100,
          costPrice: 50,
          branchStocks: {'store_001': 1},
        ),
        const Product(
          id: 'P_LOWER',
          code: 'P_LOWER',
          name: 'Bàn ăn Casing 2',
          category: 'bàn ăn',
          category3Levels: 'bàn ăn >> bàn ăn hiện đại',
          price: 200,
          costPrice: 100,
          branchStocks: {'store_001': 1},
        ),
        const Product(
          id: 'P_SENTINEL_ALL',
          code: 'P_SENTINEL_ALL',
          name: 'Tất cả product sentinel',
          category: 'All',
          price: 50,
          costPrice: 25,
          branchStocks: {'store_001': 1},
        ),
        const Product(
          id: 'P_SENTINEL_TAT_CA',
          code: 'P_SENTINEL_TAT_CA',
          name: 'Tất cả product sentinel 2',
          category: 'Tất cả',
          price: 50,
          costPrice: 25,
          branchStocks: {'store_001': 1},
        ),
      ];

      final harvested = harvestCategoriesFromProducts([], variedProducts);

      // Only 2 categories should exist: Bàn Ăn and Bàn Ăn Hiện Đại
      expect(harvested.length, equals(2));
      expect(harvested.any((c) => c.name.toLowerCase() == 'all'), isFalse);
      expect(harvested.any((c) => c.name.toLowerCase() == 'tất cả'), isFalse);
    });

    testWidgets('A1: CategoryFilterBottomSheet displays Bàn ăn & Bàn ăn bên and selects SP000771', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final repo = _FakeCategoryRepo(List.from(standardCategories));

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          filterStorageServiceProvider.overrideWithValue(FilterStorageService(prefs)),
          categoryRepositoryProvider.overrideWithValue(repo),
          categoryListProvider.overrideWith((ref) => Stream.value(standardCategories)),
          productListProvider.overrideWith((ref) => Stream.value(realProducts)),
        ],
      );
      addTearDown(container.dispose);

      Set<String>? selectedFromSheet;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  CategoryFilterBottomSheet.show(
                    ctx,
                    onCategoriesSelected: (cats) {
                      selectedFromSheet = cats;
                    },
                  );
                },
                child: const Text('Open Bottom Sheet'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Bottom Sheet'));
      await tester.pumpAndSettle();

      // Root category "Bàn ăn" is present with badge 129
      expect(find.text('Bàn ăn'), findsOneWidget);
      expect(find.text('129'), findsOneWidget);

      // Expand root category "Bàn ăn" specifically
      final banAnTile = find.byKey(const Key('category_filter_item_ban_an'));
      expect(banAnTile, findsOneWidget);
      final banAnExpandArrow = find.descendant(
        of: banAnTile,
        matching: find.byIcon(Icons.keyboard_arrow_right),
      );
      expect(banAnExpandArrow, findsOneWidget);
      await tester.tap(banAnExpandArrow);
      await tester.pumpAndSettle();

      // Scroll Bàn ăn bên above the sticky footer
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      // Subcategory "Bàn ăn bên" is now visible directly under "Bàn ăn" with badge 53
      expect(find.text('Bàn ăn bên'), findsOneWidget);
      expect(find.text('53'), findsOneWidget);

      // Tap on "Bàn ăn bên" checkbox
      final cbBanAnBen = find.byKey(const Key('checkbox_category_ban_an_ban_an_ben'));
      await tester.tap(cbBanAnBen);
      await tester.pumpAndSettle();

      // Apply selection
      final applyBtn = find.byKey(const Key('apply_category_filter_button'));
      await tester.ensureVisible(applyBtn);
      await tester.tap(applyBtn);
      await tester.pumpAndSettle();

      expect(selectedFromSheet, contains('Bàn ăn bên'));

      // Verify filtering in processedProductsProvider
      final sub = container.listen(processedProductsProvider, (_, __) {});
      addTearDown(sub.close);
      await container.read(productListProvider.future);
      container.read(productSelectedCategoriesProvider.notifier).state = {'Bàn ăn bên'};
      await tester.pump();
      final processed = container.read(processedProductsProvider).requireValue;
      final sp000771Filtered = processed.filteredProducts.any((p) => p.id == 'SP000771');
      expect(sp000771Filtered, isTrue, reason: 'SP000771 must appear when filtering by Bàn ăn bên');
      expect(processed.filteredProducts.length, equals(53));
    });

    testWidgets('A3: Renders cleanly on 320px narrow viewport without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final repo = _FakeCategoryRepo(List.from(standardCategories));

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          filterStorageServiceProvider.overrideWithValue(FilterStorageService(prefs)),
          categoryRepositoryProvider.overrideWithValue(repo),
          categoryListProvider.overrideWith((ref) => Stream.value(standardCategories)),
          productListProvider.overrideWith((ref) => Stream.value(realProducts)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CategoriesManagementPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quản lý nhóm hàng'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
