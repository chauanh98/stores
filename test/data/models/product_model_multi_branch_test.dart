import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/data/repositories/product_repository_impl.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

class FakeProductRemoteDataSource extends Fake implements ProductRemoteDataSource {
  FakeProductRemoteDataSource(this.storeId, this.mockData);

  @override
  final String storeId;
  final List<Map> mockData;

  @override
  Future<List<Map>> fetchAll() async => mockData;

  @override
  Future<Map?> fetchById(String id) async {
    for (final item in mockData) {
      if (item['id']?.toString() == id) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<Map?> getById(String id) => fetchById(id);

  @override
  Stream<List<Map>> watchAll() => Stream.value(mockData);
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
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  group('R2: ProductModel Multi-Branch Context-Aware Stock Mapping Tests', () {
    test('Default/store_001 context: maps branch_1 to store_001 and branch_2 to store_002', () {
      final map = {
        'id': 'prod_001',
        'name': 'Sản phẩm Đông Thắng',
        'price': 100000,
        'branchStocks': {
          'branch_1': 10,
          'branch_2': 5,
        },
      };

      final modelDefault = ProductModel.fromMap(map);
      expect(modelDefault.branchStocks['store_001'], equals(10));
      expect(modelDefault.branchStocks['store_002'], equals(5));

      final modelExplicitStore1 = ProductModel.fromMap(map, 'store_001');
      expect(modelExplicitStore1.branchStocks['store_001'], equals(10));
      expect(modelExplicitStore1.branchStocks['store_002'], equals(5));

      final entity = modelExplicitStore1.toEntity();
      expect(entity.stockInBranch('store_001'), equals(10));
      expect(entity.stockInBranch('store_002'), equals(5));
      expect(entity.stockInBranch('ĐT'), equals(10));
      expect(entity.stockInBranch('TB'), equals(5));
      expect(entity.stock, equals(15));
    });

    test('store_002 context: maps branch_1 to store_002 and branch_2 to store_001', () {
      final map = {
        'id': '1782636691862',
        'name': 'iPhone 17',
        'code': 'IPH',
        'price': 21000000,
        'costPrice': 14333333.33,
        'branchStocks': {
          'branch_1': 4,
          'branch_2': 0,
        },
      };

      final modelStore2 = ProductModel.fromMap(map, 'store_002');
      expect(modelStore2.branchStocks['store_001'], equals(0));
      expect(modelStore2.branchStocks['store_002'], equals(4));

      final entity = modelStore2.toEntity();
      expect(entity.stockInBranch('store_001'), equals(0));
      expect(entity.stockInBranch('store_002'), equals(4));
      expect(entity.stockInBranch('ĐT'), equals(0));
      expect(entity.stockInBranch('TB'), equals(4));
      expect(entity.stock, equals(4));
    });

    test('store_002 context recognizes all Thới Bình storeId aliases', () {
      final aliases = [
        'store_002',
        'STORE_002',
        'branch_2',
        'BRANCH_2',
        'tb',
        'TB',
        'thới bình',
        'THỚI BÌNH',
        'thoi binh',
        'thời bình',
        'Chi nhánh Thới Bình',
      ];

      final map = {
        'id': 'p101',
        'name': 'iPad Air M2',
        'branchStocks': {
          'branch_1': 15,
          'branch_2': 0,
        },
      };

      for (final alias in aliases) {
        final model = ProductModel.fromMap(map, alias);
        expect(
          model.branchStocks['store_001'],
          equals(0),
          reason: 'Failed for alias: $alias on store_001',
        );
        expect(
          model.branchStocks['store_002'],
          equals(15),
          reason: 'Failed for alias: $alias on store_002',
        );
      }
    });

    test('Legacy single stock fallback is context-aware', () {
      final legacyMap = {
        'id': 'legacy_prod',
        'name': 'Sản phẩm cũ',
        'price': 50000,
        'stock': 25,
      };

      // store_001 context: stock assigned to store_001
      final modelStore1 = ProductModel.fromMap(legacyMap, 'store_001');
      expect(modelStore1.branchStocks['store_001'], equals(25));
      expect(modelStore1.branchStocks['store_002'], equals(0));

      // store_002 context: stock assigned to store_002
      final modelStore2 = ProductModel.fromMap(legacyMap, 'store_002');
      expect(modelStore2.branchStocks['store_001'], equals(0));
      expect(modelStore2.branchStocks['store_002'], equals(25));
    });

    test('Explicit canonical keys in raw JSON take precedence over relative aliases', () {
      final explicitMap = {
        'id': 'explicit_prod',
        'name': 'Explicit Canonical Keys',
        'price': 100000,
        'branchStocks': {
          'store_001': 30,
          'store_002': 70,
          'store_003': 15,
        },
      };

      final modelStore1 = ProductModel.fromMap(explicitMap, 'store_001');
      expect(modelStore1.branchStocks['store_001'], equals(30));
      expect(modelStore1.branchStocks['store_002'], equals(70));
      expect(modelStore1.branchStocks['store_003'], equals(15));

      final modelStore2 = ProductModel.fromMap(explicitMap, 'store_002');
      expect(modelStore2.branchStocks['store_001'], equals(30));
      expect(modelStore2.branchStocks['store_002'], equals(70));
      expect(modelStore2.branchStocks['store_003'], equals(15));
    });

    test('All 16 products from data_mau.json map 100% accurately to ĐT and TB stocks', () {
      final file = File('data_mau.json');
      expect(file.existsSync(), isTrue, reason: 'data_mau.json must exist in project root');

      final jsonContent = file.readAsStringSync();
      final data = jsonDecode(jsonContent) as Map<String, dynamic>;
      final stores = data['stores'] as Map<String, dynamic>;

      // 1. Verify all 11 products in store_001 (Đông Thắng)
      final store001Products = stores['store_001']['products'] as Map<String, dynamic>;
      expect(store001Products.length, equals(11));

      final expectedStore001 = <String, Map<String, dynamic>>{
        '1784349357357': {'name': 'acd', 'dt': 10, 'tb': 0, 'total': 10},
        '1784349709944': {'name': 'Hihi sadasdasd', 'dt': 0, 'tb': 0, 'total': 0},
        '1784735675190': {'name': 'Combo huy diet', 'dt': 0, 'tb': 0, 'total': 0},
        '1784736817596': {'name': 'Combo tao lao', 'dt': 11, 'tb': 0, 'total': 11},
        'GCG08': {'name': 'Ghế bậc thang đốt nhang - 1m2', 'dt': 11, 'tb': 0, 'total': 11},
        'GCG09': {'name': 'Ghế bậc thang đốt nhang -1m4', 'dt': 11, 'tb': 0, 'total': 11},
        'GCG10': {'name': 'Ghế bậc thang đốt nhang -1m6', 'dt': 0, 'tb': 0, 'total': 0},
        'KY29': {'name': 'Kỷ xếp thao lao - 1m4', 'dt': 2, 'tb': 0, 'total': 2},
        'THOL17': {'name': 'Tủ thờ thao lao - chạm - 1m4', 'dt': 2, 'tb': 0, 'total': 2},
        'VP88': {'name': 'Bàn chữ K mặt MDF - kệ trên dưới - 1m2', 'dt': 0, 'tb': 0, 'total': 0},
        'XD15': {'name': 'Xích đu trứng - đôi 1 trụ - tai thỏ 1', 'dt': 11, 'tb': 0, 'total': 11},
      };

      for (final entry in store001Products.entries) {
        final rawMap = entry.value as Map<String, dynamic>;
        final model = ProductModel.fromMap(rawMap, 'store_001');
        final entity = model.toEntity();

        final expected = expectedStore001[entry.key];
        expect(expected, isNotNull, reason: 'Unexpected product ID: ${entry.key}');
        expect(entity.stockInBranch('store_001'), equals(expected!['dt']),
            reason: '${expected['name']} stock at store_001');
        expect(entity.stockInBranch('store_002'), equals(expected['tb']),
            reason: '${expected['name']} stock at store_002');
        expect(entity.stock, equals(expected['total']),
            reason: '${expected['name']} total stock');
      }

      // 2. Verify all 5 products in store_002 (Thới Bình)
      final store002Products = stores['store_002']['products'] as Map<String, dynamic>;
      expect(store002Products.length, equals(5));

      final expectedStore002 = <String, Map<String, dynamic>>{
        '1782636691862': {'name': 'iPhone 17', 'dt': 0, 'tb': 4, 'total': 4},
        '1784390108938': {'name': 'ip 17 pro max', 'dt': 0, 'tb': 10, 'total': 10},
        'VP88': {'name': 'Bàn chữ K mặt MDF - kệ trên dưới - 1m2', 'dt': 0, 'tb': 5, 'total': 5},
        'p101': {'name': 'iPad Air M2', 'dt': 0, 'tb': 15, 'total': 15},
        'p102': {'name': 'ThinkPad X1 Carbon', 'dt': 0, 'tb': 4, 'total': 4},
      };

      for (final entry in store002Products.entries) {
        final rawMap = entry.value as Map<String, dynamic>;
        final model = ProductModel.fromMap(rawMap, 'store_002');
        final entity = model.toEntity();

        final expected = expectedStore002[entry.key];
        expect(expected, isNotNull, reason: 'Unexpected product ID: ${entry.key}');
        expect(entity.stockInBranch('store_001'), equals(expected!['dt']),
            reason: '${expected['name']} stock at store_001');
        expect(entity.stockInBranch('store_002'), equals(expected['tb']),
            reason: '${expected['name']} stock at store_002');
        expect(entity.stock, equals(expected['total']),
            reason: '${expected['name']} total stock');
      }
    });
  });

  group('R2: ProductRepositoryImpl Multi-Branch Stock Deserialization Tests', () {
    final store002RawProducts = <Map<String, dynamic>>[
      {
        'id': '1782636691862',
        'name': 'iPhone 17',
        'code': 'IPH',
        'price': 21000000,
        'costPrice': 14333333.33,
        'branchStocks': {'branch_1': 4, 'branch_2': 0},
      },
      {
        'id': 'p101',
        'name': 'iPad Air M2',
        'code': 'p101',
        'price': 15990000,
        'costPrice': 11193000,
        'branchStocks': {'branch_1': 15, 'branch_2': 0},
      },
      {
        'id': 'p102',
        'name': 'ThinkPad X1 Carbon',
        'code': 'p102',
        'price': 42990000,
        'costPrice': 30092999,
        'branchStocks': {'branch_1': 4, 'branch_2': 0},
      },
    ];

    test('ProductRepositoryImpl bound to store_002 maps branchStocks to store_002 via fetchAll()', () async {
      final ds = FakeProductRemoteDataSource('store_002', store002RawProducts);
      final repo = ProductRepositoryImpl(ds);

      final products = await repo.fetchAll();
      expect(products.length, equals(3));

      final iphone17 = products.firstWhere((p) => p.id == '1782636691862');
      expect(iphone17.stockInBranch('store_001'), equals(0));
      expect(iphone17.stockInBranch('store_002'), equals(4));

      final ipadAir = products.firstWhere((p) => p.id == 'p101');
      expect(ipadAir.stockInBranch('store_001'), equals(0));
      expect(ipadAir.stockInBranch('store_002'), equals(15));
    });

    test('ProductRepositoryImpl bound to store_002 maps branchStocks to store_002 via fetchById()', () async {
      final ds = FakeProductRemoteDataSource('store_002', store002RawProducts);
      final repo = ProductRepositoryImpl(ds);

      final product = await repo.fetchById('1782636691862');
      expect(product, isNotNull);
      expect(product!.name, equals('iPhone 17'));
      expect(product.stockInBranch('store_001'), equals(0));
      expect(product.stockInBranch('store_002'), equals(4));
    });

    test('ProductRepositoryImpl bound to store_002 maps branchStocks to store_002 via watchAll()', () async {
      final ds = FakeProductRemoteDataSource('store_002', store002RawProducts);
      final repo = ProductRepositoryImpl(ds);

      final streamProducts = await repo.watchAll().first;
      expect(streamProducts.length, equals(3));

      final thinkpad = streamProducts.firstWhere((p) => p.id == 'p102');
      expect(thinkpad.stockInBranch('store_001'), equals(0));
      expect(thinkpad.stockInBranch('store_002'), equals(4));
    });
  });

  group('R2: UI ProductTile Multi-Branch Stock Formatting Verification', () {
    testWidgets('ProductTile displays "ĐT: 0 | TB: 4" for iPhone 17 (store_002)', (tester) async {
      const iphone17 = Product(
        id: '1782636691862',
        name: 'iPhone 17',
        code: 'IPH',
        price: 21000000,
        costPrice: 14333333.33,
        branchStocks: {'store_001': 0, 'store_002': 4},
        category: 'Smartphone',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: iphone17),
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value([iphone17])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('iPhone 17'), findsOneWidget);
      expect(find.text('Tồn: 4'), findsOneWidget);
      expect(find.textContaining('ĐT: 0 | TB: 4'), findsOneWidget);
    });

    testWidgets('ProductTile displays "ĐT: 10 | TB: 0" for acd (store_001)', (tester) async {
      const acd = Product(
        id: '1784349357357',
        name: 'acd',
        code: 'ACD',
        price: 0,
        costPrice: 0,
        branchStocks: {'store_001': 10, 'store_002': 0},
        category: 'Xích đu sắt',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: acd),
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value([acd])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('acd'), findsOneWidget);
      expect(find.text('Tồn: 10'), findsOneWidget);
      expect(find.textContaining('ĐT: 10 | TB: 0'), findsOneWidget);
    });

    testWidgets('ProductTile displays "ĐT: 0 | TB: 15" for iPad Air M2 (store_002)', (tester) async {
      const ipadAir = Product(
        id: 'p101',
        name: 'iPad Air M2',
        code: 'p101',
        price: 15990000,
        costPrice: 11193000,
        branchStocks: {'store_001': 0, 'store_002': 15},
        category: 'Tablet',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: ipadAir),
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value([ipadAir])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('iPad Air M2'), findsOneWidget);
      expect(find.text('Tồn: 15'), findsOneWidget);
      expect(find.textContaining('ĐT: 0 | TB: 15'), findsOneWidget);
    });
  });
}
