import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/data/repositories/product_repository_impl.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

class MockProductRemoteDataSource extends Fake implements ProductRemoteDataSource {
  MockProductRemoteDataSource(this.storeId, this.data);

  @override
  final String storeId;
  final List<Map<dynamic, dynamic>> data;

  @override
  Future<List<Map>> fetchAll() async => data;

  @override
  Future<Map?> fetchById(String id) async {
    for (final item in data) {
      if (item['id']?.toString() == id) {
        return item;
      }
    }
    return null;
  }

  @override
  Stream<List<Map>> watchAll() => Stream.value(data);
}

Widget _wrapWithApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  group('Adversarial Stress Test: ProductModel Multi-Branch Stock Deserialization', () {
    test('1.1. Edge Case: Missing and null branch keys in branchStocks', () {
      // Case A: Only branch_1 present
      final mapBranch1Only = {
        'id': 'p1',
        'name': 'Branch 1 Only',
        'branchStocks': {'branch_1': 12},
      };
      final m1Store1 = ProductModel.fromMap(mapBranch1Only, 'store_001');
      expect(m1Store1.branchStocks['store_001'], equals(12));
      expect(m1Store1.branchStocks['store_002'], equals(0));
      expect(m1Store1.toEntity().stockInBranch('store_001'), equals(12));
      expect(m1Store1.toEntity().stockInBranch('store_002'), equals(0));

      final m1Store2 = ProductModel.fromMap(mapBranch1Only, 'store_002');
      expect(m1Store2.branchStocks['store_001'], equals(12));
      expect(m1Store2.branchStocks['store_002'], equals(0));
      expect(m1Store2.toEntity().stockInBranch('store_001'), equals(12));
      expect(m1Store2.toEntity().stockInBranch('store_002'), equals(0));

      // Case B: Only branch_2 present
      final mapBranch2Only = {
        'id': 'p2',
        'name': 'Branch 2 Only',
        'branchStocks': {'branch_2': 7},
      };
      final m2Store1 = ProductModel.fromMap(mapBranch2Only, 'store_001');
      expect(m2Store1.branchStocks['store_001'], equals(0));
      expect(m2Store1.branchStocks['store_002'], equals(7));
      expect(m2Store1.toEntity().stockInBranch('store_001'), equals(0));
      expect(m2Store1.toEntity().stockInBranch('store_002'), equals(7));

      final m2Store2 = ProductModel.fromMap(mapBranch2Only, 'store_002');
      expect(m2Store2.branchStocks['store_001'], equals(0));
      expect(m2Store2.branchStocks['store_002'], equals(7));
      expect(m2Store2.toEntity().stockInBranch('store_001'), equals(0));
      expect(m2Store2.toEntity().stockInBranch('store_002'), equals(7));

      // Case C: Null values inside branchStocks
      final mapNullValues = {
        'id': 'p3',
        'name': 'Null Values',
        'branchStocks': {'branch_1': null, 'branch_2': null},
      };
      final m3 = ProductModel.fromMap(mapNullValues, 'store_001');
      expect(m3.branchStocks['store_001'], equals(0));
      expect(m3.branchStocks['store_002'], equals(0));
      expect(m3.stock, equals(0));
    });

    test('1.2. Edge Case: Empty branchStocks map vs completely missing branchStocks field', () {
      // Case A: branchStocks is empty map {}
      final mapEmpty = {
        'id': 'p_empty',
        'name': 'Empty map',
        'branchStocks': <String, dynamic>{},
      };
      final mEmpty = ProductModel.fromMap(mapEmpty, 'store_001');
      expect(mEmpty.branchStocks.isEmpty, isTrue);
      expect(mEmpty.stock, equals(0));
      expect(mEmpty.toEntity().stockInBranch('store_001'), equals(0));
      expect(mEmpty.toEntity().stockInBranch('store_002'), equals(0));

      // Case B: No branchStocks or stocks field at all, fallback to stock: 40
      final mapNoBranch = {
        'id': 'p_no_branch',
        'name': 'No branch field',
        'stock': 40,
      };
      final mStore1 = ProductModel.fromMap(mapNoBranch, 'store_001');
      expect(mStore1.branchStocks['store_001'], equals(40));
      expect(mStore1.branchStocks['store_002'], equals(0));
      expect(mStore1.stock, equals(40));

      final mStore2 = ProductModel.fromMap(mapNoBranch, 'store_002');
      expect(mStore2.branchStocks['store_001'], equals(0));
      expect(mStore2.branchStocks['store_002'], equals(40));
      expect(mStore2.stock, equals(40));
    });

    test('1.3. Edge Case: String quantities, num types, doubles, negative quantities, corrupted inputs', () {
      final mapCorrupted = {
        'id': 'p_corrupt',
        'name': 'Corrupted Stocks',
        'branchStocks': {
          'branch_1': '25', // String integer
          'branch_2': '  18  ', // String with spaces
          'store_003': -10, // Negative integer
          'store_004': '-5', // Negative string integer
          'store_005': 14.9, // Floating point double
          'store_006': 'invalid_string', // Malformed string
          'store_007': '', // Empty string
          '': 99, // Empty key (should be ignored)
        },
      };

      final model = ProductModel.fromMap(mapCorrupted, 'store_001');
      expect(model.branchStocks['store_001'], equals(25));
      expect(model.branchStocks['store_002'], equals(18));
      expect(model.branchStocks['store_003'], equals(-10));
      expect(model.branchStocks['store_004'], equals(-5));
      expect(model.branchStocks['store_005'], equals(14));
      expect(model.branchStocks['store_006'], equals(0));
      expect(model.branchStocks['store_007'], equals(0));
      expect(model.branchStocks.containsKey(''), isFalse);
    });

    test('1.4. Edge Case: Key variations, casing, whitespace, and Vietnamese alias keys', () {
      final mapAliases = {
        'id': 'p_alias',
        'name': 'Alias Keys',
        'branchStocks': {
          '  BRANCH_1  ': 15,
          '  Branch_2  ': 8,
          '  đông thắng  ': 100,
          '  THỚI BÌNH  ': 200,
        },
      };

      // store_001 context
      final model1 = ProductModel.fromMap(mapAliases, 'store_001');
      // When Vietnamese keys are present, they resolve to store_001 and store_002
      expect(model1.branchStocks['store_001'], equals(100));
      expect(model1.branchStocks['store_002'], equals(200));

      // When only branch_1 / branch_2 with whitespace and case differences are present:
      final mapTrimmed = {
        'id': 'p_trim',
        'name': 'Trimmed',
        'branchStocks': {
          '  BRANCH_1 ': 33,
          ' branch_2 ': 44,
        },
      };
      final model2 = ProductModel.fromMap(mapTrimmed, 'store_001');
      expect(model2.branchStocks['store_001'], equals(33));
      expect(model2.branchStocks['store_002'], equals(44));

      final model2Store2 = ProductModel.fromMap(mapTrimmed, 'store_002');
      expect(model2Store2.branchStocks['store_001'], equals(33));
      expect(model2Store2.branchStocks['store_002'], equals(44));
    });

    test('1.5. Edge Case: Missing or unknown sourceStoreId fallback behavior', () {
      final map = {
        'id': 'p_fallback',
        'name': 'Fallback Test',
        'branchStocks': {
          'branch_1': 50,
          'branch_2': 20,
        },
      };

      // null sourceStoreId -> defaults to store_001 (Đông Thắng)
      final mNull = ProductModel.fromMap(map, null);
      expect(mNull.branchStocks['store_001'], equals(50));
      expect(mNull.branchStocks['store_002'], equals(20));

      // empty string sourceStoreId -> defaults to store_001
      final mEmptyStr = ProductModel.fromMap(map, '');
      expect(mEmptyStr.branchStocks['store_001'], equals(50));
      expect(mEmptyStr.branchStocks['store_002'], equals(20));

      // unknown store ID (e.g. store_999) -> defaults to store_001
      final mUnknown = ProductModel.fromMap(map, 'store_999');
      expect(mUnknown.branchStocks['store_001'], equals(50));
      expect(mUnknown.branchStocks['store_002'], equals(20));
    });

    test('1.6. Edge Case: Negative stock calculation and out-of-stock getters', () {
      final negativeMap = {
        'id': 'p_neg',
        'name': 'Negative Stock',
        'branchStocks': {
          'store_001': -5,
          'store_002': -2,
        },
      };

      final model = ProductModel.fromMap(negativeMap);
      final entity = model.toEntity();

      expect(entity.stockInBranch('store_001'), equals(-5));
      expect(entity.stockInBranch('store_002'), equals(-2));
      expect(entity.stockInBranch('ĐT'), equals(-5));
      expect(entity.stockInBranch('TB'), equals(-2));
      expect(entity.stock, equals(-7));
      expect(entity.isOutOfStock, isTrue);
      expect(entity.hasStock, isFalse);
      expect(entity.isLowStock(), isFalse); // isLowStock is stock > 0 && stock <= minStock
    });
  });

  group('Adversarial Stress Test: Identical Product ID in Both Stores (The VP88 Challenge)', () {
    test('VP88 in store_001 vs VP88 in store_002 retains separate branch inventory without transposition', () {
      // In data_mau.json:
      // store_001: VP88 has branch_1: 0 (Đông Thắng = 0)
      // store_002: VP88 has branch_1: 5 (Thới Bình = 5)
      final vp88Store001Raw = {
        'id': 'VP88',
        'code': 'VP88',
        'name': 'Bàn chữ K mặt MDF - kệ trên dưới - 1m2',
        'price': 450000,
        'costPrice': 300000,
        'branchStocks': {'branch_1': 0},
      };

      final vp88Store002Raw = {
        'id': 'VP88',
        'code': 'VP88',
        'name': 'Bàn chữ K mặt MDF - kệ trên dưới - 1m2',
        'price': 450000,
        'costPrice': 300000,
        'branchStocks': {'branch_2': 5},
      };

      final vp88InStore1 = ProductModel.fromMap(vp88Store001Raw, 'store_001').toEntity();
      final vp88InStore2 = ProductModel.fromMap(vp88Store002Raw, 'store_002').toEntity();

      // Verify store_001 entity
      expect(vp88InStore1.stockInBranch('store_001'), equals(0));
      expect(vp88InStore1.stockInBranch('store_002'), equals(0));
      expect(vp88InStore1.stockInBranch('ĐT'), equals(0));
      expect(vp88InStore1.stockInBranch('TB'), equals(0));
      expect(vp88InStore1.stock, equals(0));
      expect(vp88InStore1.isOutOfStock, isTrue);

      // Verify store_002 entity
      expect(vp88InStore2.stockInBranch('store_001'), equals(0));
      expect(vp88InStore2.stockInBranch('store_002'), equals(5));
      expect(vp88InStore2.stockInBranch('ĐT'), equals(0));
      expect(vp88InStore2.stockInBranch('TB'), equals(5));
      expect(vp88InStore2.stock, equals(5));
      expect(vp88InStore2.hasStock, isTrue);

      // Stress: 1,000 rapid concurrent deserializations
      for (int i = 0; i < 1000; i++) {
        final s1 = ProductModel.fromMap(vp88Store001Raw, 'store_001').toEntity();
        final s2 = ProductModel.fromMap(vp88Store002Raw, 'store_002').toEntity();

        expect(s1.stockInBranch('store_001'), equals(0));
        expect(s1.stockInBranch('store_002'), equals(0));
        expect(s2.stockInBranch('store_001'), equals(0));
        expect(s2.stockInBranch('store_002'), equals(5));
      }
    });

    test('Repository fetch and watch across isolated and combined queries', () async {
      final store1Data = <Map<dynamic, dynamic>>[
        {
          'id': 'VP88',
          'name': 'Bàn chữ K mặt MDF',
          'branchStocks': {'branch_1': 0},
        },
        {
          'id': 'ACD',
          'name': 'acd',
          'branchStocks': {'branch_1': 10, 'branch_2': 0},
        },
      ];

      final store2Data = <Map<dynamic, dynamic>>[
        {
          'id': 'VP88',
          'name': 'Bàn chữ K mặt MDF',
          'branchStocks': {'branch_2': 5},
        },
        {
          'id': 'IPH',
          'name': 'iPhone 17',
          'branchStocks': {'branch_1': 0, 'branch_2': 4},
        },
      ];

      final ds1 = MockProductRemoteDataSource('store_001', store1Data);
      final ds2 = MockProductRemoteDataSource('store_002', store2Data);

      final repo1 = ProductRepositoryImpl(ds1);
      final repo2 = ProductRepositoryImpl(ds2);

      // 1. Isolated fetchAll()
      final products1 = await repo1.fetchAll();
      final products2 = await repo2.fetchAll();

      expect(products1.length, equals(2));
      expect(products2.length, equals(2));

      final vp88_1 = products1.firstWhere((p) => p.id == 'VP88');
      expect(vp88_1.stockInBranch('store_001'), equals(0));
      expect(vp88_1.stockInBranch('store_002'), equals(0));

      final acd = products1.firstWhere((p) => p.id == 'ACD');
      expect(acd.stockInBranch('store_001'), equals(10));
      expect(acd.stockInBranch('store_002'), equals(0));

      final vp88_2 = products2.firstWhere((p) => p.id == 'VP88');
      expect(vp88_2.stockInBranch('store_001'), equals(0));
      expect(vp88_2.stockInBranch('store_002'), equals(5));

      final iph = products2.firstWhere((p) => p.id == 'IPH');
      expect(iph.stockInBranch('store_001'), equals(0));
      expect(iph.stockInBranch('store_002'), equals(4));

      // 2. Isolated fetchById()
      final fetchedVp88_1 = await repo1.fetchById('VP88');
      final fetchedVp88_2 = await repo2.fetchById('VP88');

      expect(fetchedVp88_1!.stockInBranch('store_001'), equals(0));
      expect(fetchedVp88_1.stockInBranch('store_002'), equals(0));
      expect(fetchedVp88_2!.stockInBranch('store_001'), equals(0));
      expect(fetchedVp88_2.stockInBranch('store_002'), equals(5));
    });
  });

  group('Adversarial Stress Test: Product Entity stockInBranch Robustness', () {
    test('Handles all store aliases, case variations, leading/trailing whitespace, and unknown keys', () {
      const product = Product(
        id: 'stress_p1',
        name: 'Stress Test Product',
        code: 'STRESS1',
        price: 100000,
        costPrice: 70000,
        branchStocks: {
          'store_001': 88,
          'store_002': 99,
          'custom_store': 33,
        },
        category: 'Test',
      );

      // store_001 queries
      expect(product.stockInBranch('store_001'), equals(88));
      expect(product.stockInBranch('STORE_001'), equals(88));
      expect(product.stockInBranch('branch_1'), equals(88));
      expect(product.stockInBranch('BRANCH_1'), equals(88));
      expect(product.stockInBranch('ĐT'), equals(88));
      expect(product.stockInBranch('đt'), equals(88));
      expect(product.stockInBranch('dt'), equals(88));
      expect(product.stockInBranch('Đông Thắng'), equals(88));
      expect(product.stockInBranch('đông thắng'), equals(88));
      expect(product.stockInBranch('dong thang'), equals(88));
      expect(product.stockInBranch('  store_001  '), equals(88));

      // store_002 queries
      expect(product.stockInBranch('store_002'), equals(99));
      expect(product.stockInBranch('STORE_002'), equals(99));
      expect(product.stockInBranch('branch_2'), equals(99));
      expect(product.stockInBranch('BRANCH_2'), equals(99));
      expect(product.stockInBranch('TB'), equals(99));
      expect(product.stockInBranch('tb'), equals(99));
      expect(product.stockInBranch('Thới Bình'), equals(99));
      expect(product.stockInBranch('thới bình'), equals(99));
      expect(product.stockInBranch('thoi binh'), equals(99));
      expect(product.stockInBranch('thời bình'), equals(99));
      expect(product.stockInBranch('  store_002  '), equals(99));

      // Custom store queries
      expect(product.stockInBranch('custom_store'), equals(33));
      expect(product.stockInBranch('CUSTOM_STORE'), equals(33));

      // Non-existent branches
      expect(product.stockInBranch(''), equals(0));
      expect(product.stockInBranch('   '), equals(0));
      expect(product.stockInBranch('store_999'), equals(0));
      expect(product.stockInBranch('non_existent'), equals(0));
    });
  });

  group('Adversarial Stress Test: Widget UI Rendering with Edge Case Stocks', () {
    testWidgets('ProductTile with 0 stock renders Red "Hết hàng" badge', (tester) async {
      const zeroProd = Product(
        id: 'p_zero',
        name: 'Sản phẩm hết hàng',
        code: 'ZERO01',
        price: 50000,
        costPrice: 30000,
        branchStocks: {'store_001': 0, 'store_002': 0},
        category: 'Test',
      );

      await tester.pumpWidget(
        _wrapWithApp(
          child: const ProductTile(product: zeroProd),
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value([zeroProd])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sản phẩm hết hàng'), findsOneWidget);
      expect(find.text('Tồn: 0'), findsOneWidget);
      expect(find.text('Hết hàng'), findsOneWidget);
      expect(find.textContaining('ĐT: 0 | TB: 0'), findsOneWidget);
    });

    testWidgets('ProductTile with negative stock renders Red "Hết hàng" badge and preserves negative quantity', (tester) async {
      const negProd = Product(
        id: 'p_neg',
        name: 'Sản phẩm âm kho',
        code: 'NEG01',
        price: 50000,
        costPrice: 30000,
        branchStocks: {'store_001': -3, 'store_002': 0},
        category: 'Test',
      );

      await tester.pumpWidget(
        _wrapWithApp(
          child: const ProductTile(product: negProd),
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value([negProd])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sản phẩm âm kho'), findsOneWidget);
      expect(find.text('Tồn: -3'), findsOneWidget);
      expect(find.text('Hết hàng'), findsOneWidget);
      expect(find.textContaining('ĐT: -3 | TB: 0'), findsOneWidget);
    });

    testWidgets('ProductTile with low stock renders Orange "Dưới định mức" badge', (tester) async {
      const lowProd = Product(
        id: 'p_low',
        name: 'Sản phẩm sắp hết',
        code: 'LOW01',
        price: 50000,
        costPrice: 30000,
        branchStocks: {'store_001': 2, 'store_002': 0},
        minStock: 5,
        category: 'Test',
      );

      await tester.pumpWidget(
        _wrapWithApp(
          child: const ProductTile(product: lowProd),
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value([lowProd])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sản phẩm sắp hết'), findsOneWidget);
      expect(find.text('Tồn: 2'), findsOneWidget);
      expect(find.text('Dưới định mức'), findsOneWidget);
      expect(find.textContaining('ĐT: 2 | TB: 0'), findsOneWidget);
    });

    testWidgets('ProductTile for Combo Product calculates composite available stock correctly across branches', (tester) async {
      const child1 = Product(
        id: 'c1',
        name: 'Linh kiện A',
        code: 'C1',
        price: 10000,
        costPrice: 7000,
        branchStocks: {'store_001': 10, 'store_002': 0},
        category: 'Components',
      );
      const child2 = Product(
        id: 'c2',
        name: 'Linh kiện B',
        code: 'C2',
        price: 20000,
        costPrice: 15000,
        branchStocks: {'store_001': 4, 'store_002': 0},
        category: 'Components',
      );

      const comboProd = Product(
        id: 'combo_1',
        name: 'Bộ Combo Trọn Gói',
        code: 'COMBO1',
        price: 35000,
        costPrice: 22000,
        branchStocks: {'store_001': 0, 'store_002': 0},
        category: 'Combo',
        isCombo: true,
        comboComponents: [
          ComboComponent(productId: 'c1', productName: 'Linh kiện A', productCode: 'C1', quantity: 2), // needs 2x c1 (10 / 2 = 5 sets)
          ComboComponent(productId: 'c2', productName: 'Linh kiện B', productCode: 'C2', quantity: 1), // needs 1x c2 (4 / 1 = 4 sets)
        ], // Bottleneck is child2: 4 sets available
      );

      await tester.pumpWidget(
        _wrapWithApp(
          child: const ProductTile(product: comboProd),
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value([comboProd, child1, child2])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bộ Combo Trọn Gói'), findsOneWidget);
      expect(find.text('COMBO'), findsOneWidget);
      expect(find.text('Tồn bộ: 4'), findsOneWidget);
    });
  });
}
