import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

Widget _buildChallengerApp({
  required Widget child,
  required String currentStoreId,
  List<Branch>? branches,
  Map<String, String>? availableStores,
  UserAccount? user,
  List<Product>? products,
}) {
  final canonicalBranches = branches ??
      const [
        Branch('store_001', 'Chi nhánh Đông Thắng'),
        Branch('store_002', 'Chi nhánh Thới Bình'),
      ];

  final storesMap = availableStores ??
      {
        'store_001': 'Chi nhánh Đông Thắng',
        'store_002': 'Chi nhánh Thới Bình',
      };

  final testUser = user ??
      const UserAccount(
        username: 'supervisor_test',
        displayName: 'Giám Sát Viên',
        role: 'supervisor',
        storeId: 'store_001',
      );

  return ProviderScope(
    overrides: [
      currentStoreIdProvider.overrideWithValue(currentStoreId),
      branchesProvider.overrideWithValue(canonicalBranches),
      availableStoresProvider.overrideWith((ref) => Future.value(storesMap)),
      authProvider.overrideWith((ref) => _SimpleAuthNotifier(testUser)),
      if (products != null)
        productListProvider.overrideWith((ref) => Stream.value(products)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Scaffold(body: child),
    ),
  );
}

class _SimpleAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _SimpleAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Challenger 1 Adversarial Suite: Canonical Store Mapping & Stock Parity (M1)', () {
    // =========================================================================
    // SECTION 1: Exhaustive Legacy Alias Normalization Matrix in ProductModel
    // =========================================================================
    group('1. ProductModel.fromMap Alias Normalization Exhaustive Matrix', () {
      test('Normalizes legacy branch_1 variations to store_001', () {
        final variations = [
          'branch_1',
          'BRANCH_1',
          'Branch_1',
          '  branch_1  ',
          'đt',
          'ĐT',
          'dt',
          'DT',
          '  ĐT  ',
          '  dt  ',
          'đông thắng',
          'ĐÔNG THẮNG',
          'Đông Thắng',
          'dong thang',
          'DONG THANG',
          '  đông thắng  ',
          'Chi nhánh Đông Thắng',
          'CHI NHÁNH ĐÔNG THẮNG',
          'chi nhánh đông thắng',
        ];

        for (final alias in variations) {
          final rawMap = {
            'id': 'prod_$alias',
            'name': 'Product Alias Test',
            'price': 10000.0,
            'branchStocks': {
              alias: 77,
            },
          };

          final model = ProductModel.fromMap(rawMap);
          expect(
            model.branchStocks['store_001'],
            equals(77),
            reason: 'Alias "$alias" failed to normalize to store_001',
          );
        }
      });

      test('Normalizes legacy branch_2 variations to store_002', () {
        final variations = [
          'branch_2',
          'BRANCH_2',
          'Branch_2',
          '  branch_2  ',
          'tb',
          'TB',
          '  TB  ',
          '  tb  ',
          'thới bình',
          'THỚI BÌNH',
          'Thới Bình',
          'thoi binh',
          'THOI BINH',
          'thời bình',
          'THỜI BÌNH',
          '  thới bình  ',
          'Chi nhánh Thới Bình',
          'CHI NHÁNH THỚI BÌNH',
          'chi nhánh thới bình',
        ];

        for (final alias in variations) {
          final rawMap = {
            'id': 'prod_$alias',
            'name': 'Product Alias Test 2',
            'price': 20000.0,
            'branchStocks': {
              alias: 88,
            },
          };

          final model = ProductModel.fromMap(rawMap);
          expect(
            model.branchStocks['store_002'],
            equals(88),
            reason: 'Alias "$alias" failed to normalize to store_002',
          );
        }
      });

      test('Precedence: canonical store_001 overrides legacy branch_1 if both present', () {
        final mixedMap = {
          'id': 'prod_precedence',
          'name': 'Precedence Product',
          'price': 15000.0,
          'branchStocks': {
            'store_001': 100,
            'branch_1': 50,
            'store_002': 200,
            'branch_2': 75,
          },
        };

        final model = ProductModel.fromMap(mixedMap);
        expect(model.branchStocks['store_001'], equals(100));
        expect(model.branchStocks['store_002'], equals(200));
      });

      test('Null, stringified, floating-point, and negative values normalization', () {
        final edgeMap = {
          'id': 'prod_edge_types',
          'name': 'Edge Types Product',
          'price': 50000.0,
          'branchStocks': {
            'branch_1': null,
            'branch_2': '45',
            'store_003': 30.9,
            'store_004': -15,
          },
        };

        final model = ProductModel.fromMap(edgeMap);
        expect(model.branchStocks['store_001'], equals(0));
        expect(model.branchStocks['store_002'], equals(45));
        expect(model.branchStocks['store_003'], equals(30));
        expect(model.branchStocks['store_004'], equals(-15));
      });

      test('Empty map, missing branchStocks, and non-map fallback behavior', () {
        // Case A: Explicit empty map -> stays empty
        final emptyMap = {
          'id': 'p_empty',
          'name': 'Empty',
          'branchStocks': <String, dynamic>{},
        };
        expect(ProductModel.fromMap(emptyMap).branchStocks, isEmpty);

        // Case B: Null branchStocks with legacy single stock field -> {'store_001': stock, 'store_002': 0}
        final singleStockMap = {
          'id': 'p_single',
          'name': 'Single Stock',
          'stock': 42,
        };
        final singleModel = ProductModel.fromMap(singleStockMap);
        expect(singleModel.branchStocks['store_001'], equals(42));
        expect(singleModel.branchStocks['store_002'], equals(0));

        // Case C: Missing both branchStocks and stock -> {'store_001': 0, 'store_002': 0}
        final missingAllMap = {
          'id': 'p_none',
          'name': 'No Stocks',
        };
        final noneModel = ProductModel.fromMap(missingAllMap);
        expect(noneModel.branchStocks['store_001'], equals(0));
        expect(noneModel.branchStocks['store_002'], equals(0));

        // Case D: Non-map corrupted branchStocks with stock field
        final corruptedMap = {
          'id': 'p_corrupt',
          'name': 'Corrupt',
          'branchStocks': 12345,
          'stock': 99,
        };
        final corruptModel = ProductModel.fromMap(corruptedMap);
        expect(corruptModel.branchStocks['store_001'], equals(99));
        expect(corruptModel.branchStocks['store_002'], equals(0));
      });
    });

    // =========================================================================
    // SECTION 2: Product.stockInBranch Resolution Matrix
    // =========================================================================
    group('2. Product.stockInBranch Resolution Matrix', () {
      const canonicalProduct = Product(
        id: 'p_matrix',
        name: 'Matrix Product',
        code: 'MAT01',
        price: 30000,
        costPrice: 20000,
        branchStocks: {
          'store_001': 120,
          'store_002': 250,
          'store_can_tho': 80,
        },
        category: 'Test',
      );

      test('Resolves store_001 queries through all alias permutations', () {
        final aliases = [
          'store_001', 'STORE_001', 'Store_001', '  store_001  ',
          'branch_1', 'BRANCH_1', 'Branch_1', '  branch_1  ',
          'ĐT', 'đt', 'DT', 'dt', '  ĐT  ',
          'Đông Thắng', 'đông thắng', 'ĐÔNG THẮNG',
          'Dong Thang', 'dong thang', 'DONG THANG',
          'Chi nhánh Đông Thắng', 'CHI NHÁNH ĐÔNG THẮNG',
        ];

        for (final alias in aliases) {
          expect(
            canonicalProduct.stockInBranch(alias),
            equals(120),
            reason: 'Query with "$alias" should return 120',
          );
        }
      });

      test('Resolves store_002 queries through all alias permutations', () {
        final aliases = [
          'store_002', 'STORE_002', 'Store_002', '  store_002  ',
          'branch_2', 'BRANCH_2', 'Branch_2', '  branch_2  ',
          'TB', 'tb', '  TB  ',
          'Thới Bình', 'thới bình', 'THỚI BÌNH',
          'Thoi Binh', 'thoi binh', 'THOI BINH',
          'Thời Bình', 'thời bình', 'THỜI BÌNH',
          'Chi nhánh Thới Bình', 'CHI NHÁNH THỚI BÌNH',
        ];

        for (final alias in aliases) {
          expect(
            canonicalProduct.stockInBranch(alias),
            equals(250),
            reason: 'Query with "$alias" should return 250',
          );
        }
      });

      test('Resolves custom store queries and invalid inputs safely', () {
        expect(canonicalProduct.stockInBranch('store_can_tho'), equals(80));
        expect(canonicalProduct.stockInBranch('STORE_CAN_THO'), equals(80));
        expect(canonicalProduct.stockInBranch('  store_can_tho  '), equals(80));

        // Unknown stores
        expect(canonicalProduct.stockInBranch('unknown_store'), equals(0));
        expect(canonicalProduct.stockInBranch(''), equals(0));
        expect(canonicalProduct.stockInBranch('   '), equals(0));
      });
    });

    // =========================================================================
    // SECTION 3: Store Switching Dynamics & UI Parity between Tile & Detail Page
    // =========================================================================
    group('3. Store Switching Dynamics & UI Parity (ProductTile vs ProductDetailPage)', () {
      const syncProduct = Product(
        id: 'p_sync_01',
        name: 'Nước Tăng Lực Sting Dâu 330ml',
        code: 'STING01',
        barcode: '893456789012',
        brand: 'PepsiCo',
        price: 12000,
        costPrice: 8500,
        branchStocks: {
          'store_001': 45,
          'store_002': 70,
        },
        category: 'Đồ uống',
      );

      testWidgets('Store Switching Parity: store_001 vs store_002 retains exact stock values',
          (tester) async {
        // --- Step 1: Render in store_001 context ---
        await tester.pumpWidget(
          _buildChallengerApp(
            currentStoreId: 'store_001',
            products: const [syncProduct],
            child: const Column(
              children: [
                ProductTile(product: syncProduct),
                Expanded(child: ProductDetailPage(product: syncProduct)),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Check ProductTile displays ĐT: 45 | TB: 70 and Tồn: 115
        expect(find.text('ĐT: 45 | TB: 70'), findsOneWidget);
        expect(find.text('Tồn: 115'), findsOneWidget);

        // Check ProductDetailPage branch table has Chi nhánh Đông Thắng: 45 and Chi nhánh Thới Bình: 70
        expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
        expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
        expect(find.text('45'), findsOneWidget);
        expect(find.text('70'), findsOneWidget);
        expect(find.text('Tổng: 115'), findsOneWidget);

        // --- Step 2: Switch context to store_002 ---
        await tester.pumpWidget(
          _buildChallengerApp(
            currentStoreId: 'store_002',
            products: const [syncProduct],
            child: const Column(
              children: [
                ProductTile(product: syncProduct),
                Expanded(child: ProductDetailPage(product: syncProduct)),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // ProductTile must still display ĐT: 45 | TB: 70 with zero inversion or corruption
        expect(find.text('ĐT: 45 | TB: 70'), findsOneWidget);
        expect(find.text('Tồn: 115'), findsOneWidget);

        // ProductDetailPage must maintain canonical row order (Row 1: Đông Thắng 45, Row 2: Thới Bình 70)
        expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
        expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
        expect(find.text('45'), findsOneWidget);
        expect(find.text('70'), findsOneWidget);
        expect(find.text('Tổng: 115'), findsOneWidget);
      });

      testWidgets('Store Switching Pre-fill in Edit Form: pre-fills active store stock accurately',
          (tester) async {
        // Under store_001
        await tester.pumpWidget(
          _buildChallengerApp(
            currentStoreId: 'store_001',
            products: [syncProduct],
            child: const ProductDetailPage(product: syncProduct),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Under store_001, stock field should pre-fill with store_001 stock (45)
        final stockFieldStore1 = tester.widget<TextField>(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              ((w.decoration?.labelText?.contains('tồn kho') == true) ||
                  (w.decoration?.prefixIcon is Icon &&
                      (w.decoration!.prefixIcon as Icon).icon ==
                          Icons.inventory_2))),
        );
        expect(stockFieldStore1.controller?.text, equals('45'));

        // Cancel edit
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Under store_002
        await tester.pumpWidget(
          _buildChallengerApp(
            currentStoreId: 'store_002',
            products: [syncProduct],
            child: const ProductDetailPage(product: syncProduct),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Under store_002, stock field should pre-fill with store_002 stock (70)
        final stockFieldStore2 = tester.widget<TextField>(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              ((w.decoration?.labelText?.contains('tồn kho') == true) ||
                  (w.decoration?.prefixIcon is Icon &&
                      (w.decoration!.prefixIcon as Icon).icon ==
                          Icons.inventory_2))),
        );
        expect(stockFieldStore2.controller?.text, equals('70'));
      });
    });

    // =========================================================================
    // SECTION 4: Multi-Branch Extended Network (3+ branches)
    // =========================================================================
    group('4. Extended Multi-Branch Network (3+ Branches)', () {
      const multiProduct = Product(
        id: 'p_multi_network',
        name: 'Dầu Ăn Neptune Light 1L',
        code: 'NEP01',
        price: 55000,
        costPrice: 42000,
        branchStocks: {
          'store_001': 15,
          'store_002': 25,
          'store_003': 35,
          'store_004': 10,
        },
        category: 'Gia vị',
      );

      final customBranches = [
        const Branch('store_001', 'Chi nhánh Đông Thắng'),
        const Branch('store_002', 'Chi nhánh Thới Bình'),
        const Branch('store_003', 'Chi nhánh Cần Thơ'),
        const Branch('store_004', 'Chi nhánh Vĩnh Long'),
      ];

      testWidgets('ProductTile and ProductDetailPage correctly handle 4 branches simultaneously',
          (tester) async {
        await tester.pumpWidget(
          _buildChallengerApp(
            currentStoreId: 'store_001',
            branches: customBranches,
            products: const [multiProduct],
            child: const Column(
              children: [
                ProductTile(product: multiProduct),
                Expanded(child: ProductDetailPage(product: multiProduct)),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // ProductTile badge: ĐT: 15 | TB: 25 | CN3: 35 | CN4: 10
        expect(
          find.textContaining('ĐT: 15 | TB: 25 | CN3: 35 | CN4: 10'),
          findsOneWidget,
        );
        expect(find.text('Tồn: 85'), findsOneWidget);

        // ProductDetailPage breakdown
        expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
        expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
        expect(find.text('Chi nhánh Cần Thơ'), findsOneWidget);
        expect(find.text('Chi nhánh Vĩnh Long'), findsOneWidget);
        expect(find.text('15'), findsOneWidget);
        expect(find.text('25'), findsOneWidget);
        expect(find.text('35'), findsOneWidget);
        expect(find.text('10'), findsOneWidget);
        expect(find.text('Tổng: 85'), findsOneWidget);
      });
    });

    // =========================================================================
    // SECTION 5: Combo Product Branch Stock Parity
    // =========================================================================
    group('5. Combo Product Multi-Branch Stock Dynamics', () {
      const child1 = Product(
        id: 'child_1',
        name: 'Gạo ST25 5kg',
        code: 'GAO01',
        price: 180000,
        costPrice: 140000,
        branchStocks: {'store_001': 10, 'store_002': 20},
        category: 'Lương thực',
      );

      const child2 = Product(
        id: 'child_2',
        name: 'Nước mắm Phú Quốc 500ml',
        code: 'MAM01',
        price: 45000,
        costPrice: 32000,
        branchStocks: {'store_001': 30, 'store_002': 10},
        category: 'Gia vị',
      );

      const comboProd = Product(
        id: 'combo_bundle',
        name: 'Combo Gia Đình Ấm Áp',
        code: 'CBGA01',
        price: 220000,
        costPrice: 172000,
        branchStocks: {'store_001': 0, 'store_002': 0},
        category: 'Combo',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'child_1',
            productCode: 'GAO01',
            productName: 'Gạo ST25 5kg',
            quantity: 1,
            costPrice: 140000,
          ),
          ComboComponent(
            productId: 'child_2',
            productCode: 'MAM01',
            productName: 'Nước mắm Phú Quốc 500ml',
            quantity: 2,
            costPrice: 32000,
          ),
        ],
      );

      testWidgets('ProductTile computes available combo stock dynamically per branch',
          (tester) async {
        // store_001: child1=10, child2=30/2=15 -> min=10
        // store_002: child1=20, child2=10/2=5  -> min=5
        // total combo stock = 10 + 5 = 15

        await tester.pumpWidget(
          _buildChallengerApp(
            currentStoreId: 'store_001',
            products: [child1, child2, comboProd],
            child: const ProductTile(product: comboProd),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('COMBO'), findsOneWidget);
        expect(find.text('Tồn bộ: 15'), findsOneWidget);
      });
    });
  });
}
