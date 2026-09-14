import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inter_store_transfer_service.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/data/models/inventory_transaction_model.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

// --- Test Fakes & Mock Repositories ---

class _FakeProductRepository extends Fake implements ProductRepository {
  final List<Product> products;
  Product? lastUpsertedProduct;

  _FakeProductRepository([List<Product>? initial])
      : products = initial != null ? List<Product>.from(initial) : [];

  @override
  Stream<List<Product>> watchAll() => Stream.value(products);

  @override
  Future<List<Product>> fetchAll() async => products;

  @override
  Future<Product?> fetchById(String id) async {
    try {
      return products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> upsert(Product product) async {
    lastUpsertedProduct = product;
    final index = products.indexWhere((p) => p.id == product.id);
    if (index >= 0) {
      products[index] = product;
    } else {
      products.add(product);
    }
  }
}

class _FakeInventoryRepository extends Fake implements InventoryRepository {
  final List<InventoryTransaction> recordedTransactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async {
    recordedTransactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(recordedTransactions.where((t) => t.productId == productId).toList());
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

// --- Test Fixtures & Harness ---

final _canonicalBranches = [
  const Branch('store_001', 'Chi nhánh Đông Thắng'),
  const Branch('store_002', 'Chi nhánh Thới Bình'),
];

const _adminUser = UserAccount(
  username: 'admin_test',
  displayName: 'Quản trị viên',
  role: 'admin',
  storeId: 'store_001',
);

Widget _buildTestApp({
  required Widget child,
  String currentStoreId = 'store_001',
  List<Branch>? branches,
  ProductRepository? productRepo,
  InventoryRepository? inventoryRepo,
  UserAccount? user,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      currentStoreIdProvider.overrideWith((ref) => currentStoreId),
      branchesProvider.overrideWithValue(branches ?? _canonicalBranches),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': 'Chi nhánh Đông Thắng',
            'store_002': 'Chi nhánh Thới Bình',
          }),
      productListProvider.overrideWith((ref) => Stream.value([])),
      if (productRepo != null)
        productRepositoryProvider.overrideWithValue(productRepo),
      if (inventoryRepo != null)
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
      authProvider.overrideWith((ref) => _FakeAuthNotifier(user ?? _adminUser)),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Scaffold(body: child),
    ),
  );
}

Finder findStockTextField() {
  return find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        w.decoration?.prefixIcon is Icon &&
        (w.decoration!.prefixIcon as Icon).icon == Icons.inventory_2,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tier 2 E2E: Boundary & Corner Cases (F1 to F9)', () {
    // =========================================================================
    // F1: Boundary & Corner Cases (Canonical Store Normalization)
    // =========================================================================
    group('F1: Boundary & Corner Cases', () {
      test('F1.1: stockInBranch returns 0 when branchStocks is empty map', () {
        const productEmptyStocks = Product(
          id: 'prod_b_f1_01',
          name: 'Sản phẩm chưa phân bổ kho',
          code: 'NO_STOCK_01',
          price: 10000,
          costPrice: 7000,
          branchStocks: {},
          category: 'Chưa phân loại',
        );

        expect(productEmptyStocks.stockInBranch('store_001'), equals(0));
        expect(productEmptyStocks.stockInBranch('store_002'), equals(0));
        expect(productEmptyStocks.stockInBranch('branch_1'), equals(0));
        expect(productEmptyStocks.stock, equals(0));
      });

      test('F1.2: stockInBranch query strings with whitespaces and newlines', () {
        const product = Product(
          id: 'prod_b_f1_02',
          name: 'Nước Ngọt Sprite 330ml',
          code: 'SPRITE',
          price: 10000,
          costPrice: 7500,
          branchStocks: {'store_001': 50, 'store_002': 25},
          category: 'Đồ uống',
        );

        // Leading/trailing whitespace trimmed
        expect(product.stockInBranch('  store_001  '), equals(50));
        expect(product.stockInBranch('\tstore_002\n'), equals(25));
        expect(product.stockInBranch('  ĐT  '), equals(50));
        expect(product.stockInBranch('  TB  '), equals(25));

        // Empty string or only whitespaces return 0
        expect(product.stockInBranch(''), equals(0));
        expect(product.stockInBranch('   '), equals(0));
        expect(product.stockInBranch('\t\n'), equals(0));
      });

      test('F1.3: stockInBranch handles diacritics variations, typos, and mixed case', () {
        const product = Product(
          id: 'prod_b_f1_03',
          name: 'Bánh Mì Sandwich Kinh Đô',
          code: 'SW_KD',
          price: 22000,
          costPrice: 16000,
          branchStocks: {'store_001': 40, 'store_002': 30},
          category: 'Bánh tươi',
        );

        // Accent typo "Thời Bình" vs "Thới Bình"
        expect(product.stockInBranch('Chi nhánh Thời Bình'), equals(30));
        expect(product.stockInBranch('chi nhanh thoi binh'), equals(30));
        expect(product.stockInBranch('THOI BINH'), equals(30));

        // Unaccented "Dong Thang" vs "Đông Thắng"
        expect(product.stockInBranch('chi nhanh dong thang'), equals(40));
        expect(product.stockInBranch('DONG THANG'), equals(40));

        // Uppercase and lowercase short codes
        expect(product.stockInBranch('DT'), equals(40));
        expect(product.stockInBranch('Tb'), equals(30));
      });

      test('F1.4: Extreme stock numbers (0, large integer, negative values) sum accurately', () {
        const extremeProduct = Product(
          id: 'prod_b_f1_04',
          name: 'Kho Báu Sản Phẩm',
          code: 'EXTREME',
          price: 1000000,
          costPrice: 800000,
          branchStocks: {
            'store_001': 9999999,
            'store_002': -500,
            'store_003': 0,
          },
          category: 'Đặc biệt',
        );

        expect(extremeProduct.stockInBranch('store_001'), equals(9999999));
        expect(extremeProduct.stockInBranch('store_002'), equals(-500));
        expect(extremeProduct.stockInBranch('store_003'), equals(0));
        expect(extremeProduct.stock, equals(9999999 - 500 + 0));
      });

      test('F1.5: ProductModel.fromMap parses string and double numbers in branchStocks safely', () {
        final rawMap = {
          'id': 'prod_b_f1_05',
          'name': 'Gạo Nàng Thơm Chợ Đào',
          'code': 'G_NANGTHOM',
          'price': 140000,
          'costPrice': 110000,
          'branchStocks': {
            'store_001': '35', // String integer
            'store_002': 20.0, // Double numeric
            'store_003': 15, // Standard int
          },
          'category': 'Gạo',
        };

        final model = ProductModel.fromMap(rawMap);
        expect(model.branchStocks['store_001'], equals(35));
        expect(model.branchStocks['store_002'], equals(20));
        expect(model.branchStocks['store_003'], equals(15));
        expect(model.stock, equals(70));
      });

      test('F1.6: Querying unregistered store ID returns 0 safely without error', () {
        const product = Product(
          id: 'prod_b_f1_06',
          name: 'Khăn Lau Đa Năng 3M',
          code: '3M_CLOTH',
          price: 45000,
          costPrice: 30000,
          branchStocks: {'store_001': 10, 'store_002': 5},
          category: 'Đồ gia dụng',
        );

        expect(product.stockInBranch('store_999'), equals(0));
        expect(product.stockInBranch('branch_unknown'), equals(0));
        expect(product.stockInBranch('non_existent_id'), equals(0));
      });
    });

    // =========================================================================
    // F2: Boundary & Corner Cases (Branch Provider Stability)
    // =========================================================================
    group('F2: Boundary & Corner Cases', () {
      test('F2.1: branchesProvider handles empty availableStores with fallback names', () {
        final container = ProviderContainer(
          overrides: [
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider.overrideWith((ref) async => {}), // Empty map
          ],
        );
        addTearDown(container.dispose);

        final branches = container.read(branchesProvider);
        expect(branches.length, equals(2));
        expect(branches[0].name, isNotEmpty);
        expect(branches[1].name, isNotEmpty);
      });

      test('F2.2: branchesProvider dynamically adopts custom store names from provider', () {
        final container = ProviderContainer(
          overrides: [
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            branchesProvider.overrideWithValue([
              const Branch('store_001', 'Siêu thị Đông Thắng Plaza'),
              const Branch('store_002', 'Đại lý Thới Bình Center'),
            ]),
          ],
        );
        addTearDown(container.dispose);

        final branches = container.read(branchesProvider);
        expect(branches.length, equals(2));
        final names = branches.map((b) => b.name).toList();
        expect(names, contains('Siêu thị Đông Thắng Plaza'));
        expect(names, contains('Đại lý Thới Bình Center'));
      });

      test('F2.3: getMockBranches with unknown store ID returns fallback branch list', () {
        final branchesUnknown = getMockBranches('store_random_999');
        expect(branchesUnknown.length, equals(2));
        expect(branchesUnknown[0].id, isNotEmpty);
        expect(branchesUnknown[1].id, isNotEmpty);
      });

      test('F2.4: Branch value object handles Unicode symbols, emojis, and punctuation', () {
        const branchSpecial = Branch(
          'store_special',
          '🏪 Cửa Hàng Tiện Lợi (24/7) - #01 @ ĐT!',
        );

        expect(branchSpecial.id, equals('store_special'));
        expect(branchSpecial.name, contains('🏪 Cửa Hàng Tiện Lợi (24/7)'));
      });

      test('F2.5: mockBranches list contains distinct IDs', () {
        final ids = mockBranches.map((b) => b.id).toList();
        expect(ids.toSet().length, equals(ids.length));
      });

      test('F2.6: Independent ProviderContainers maintain separate branch states', () {
        final containerA = ProviderContainer(
          overrides: [
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          ],
        );
        final containerB = ProviderContainer(
          overrides: [
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
          ],
        );
        addTearDown(containerA.dispose);
        addTearDown(containerB.dispose);

        expect(containerA.read(currentStoreIdProvider), equals('store_001'));
        expect(containerB.read(currentStoreIdProvider), equals('store_002'));
      });
    });

    // =========================================================================
    // F3: Boundary & Corner Cases (UI Badges & Table Parity)
    // =========================================================================
    group('F3: Boundary & Corner Cases', () {
      testWidgets('F3.1: Product with all 0 branch stocks renders ĐT: 0 | TB: 0 and Out of Stock',
          (tester) async {
        const zeroStockProduct = Product(
          id: 'prod_b_f3_01',
          name: 'Nước Tăng Lực Compact 250ml',
          code: 'COMPACT',
          price: 10000,
          costPrice: 7000,
          branchStocks: {'store_001': 0, 'store_002': 0},
          category: 'Đồ uống',
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductTile(product: zeroStockProduct),
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([zeroStockProduct])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('ĐT: 0 | TB: 0'), findsOneWidget);
        expect(find.text('Hết hàng'), findsOneWidget);
      });

      testWidgets('F3.2: Product with negative stock in one branch renders formatted badge and sum',
          (tester) async {
        const negativeStockProduct = Product(
          id: 'prod_b_f3_02',
          name: 'Bật Lửa Cricket',
          code: 'CRICKET',
          price: 8000,
          costPrice: 5000,
          branchStocks: {'store_001': 15, 'store_002': -5}, // Total = 10
          category: 'Tạp hóa',
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductTile(product: negativeStockProduct),
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([negativeStockProduct])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('ĐT: 15 | TB: -5'), findsOneWidget);
        expect(find.text('Tồn: 10'), findsOneWidget);
      });

      testWidgets('F3.3: Product with extreme large stock renders without overflow',
          (tester) async {
        const largeStockProduct = Product(
          id: 'prod_b_f3_03',
          name: 'Tăm Tre Tiệt Trùng',
          code: 'TAM_TRE',
          price: 3000,
          costPrice: 1500,
          branchStocks: {'store_001': 500000, 'store_002': 500000},
          category: 'Tạp hóa',
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductTile(product: largeStockProduct),
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([largeStockProduct])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tồn: 1000000'), findsOneWidget);
        expect(find.textContaining('ĐT: 500000 | TB: 500000'), findsOneWidget);
      });

      testWidgets('F3.4: Product with single branch entry formats single badge item',
          (tester) async {
        const singleBranchProduct = Product(
          id: 'prod_b_f3_04',
          name: 'Bánh Trung Thu Kinh Đô Thập Cẩm',
          code: 'TT_TC',
          price: 85000,
          costPrice: 60000,
          branchStocks: {'store_001': 42},
          category: 'Bánh trung thu',
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductTile(product: singleBranchProduct),
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([singleBranchProduct])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('ĐT: 42'), findsOneWidget);
        expect(find.text('Tồn: 42'), findsOneWidget);
      });

      testWidgets('F3.5: Combo product with zero component stock renders Out of Stock and 0 stock',
          (tester) async {
        const compInStock = Product(
          id: 'comp_1',
          name: 'Trà Sữa Matcha 330ml',
          code: 'TS_MATCHA',
          price: 25000,
          costPrice: 18000,
          branchStocks: {'store_001': 10, 'store_002': 5},
          category: 'Đồ uống',
        );

        const compZeroStock = Product(
          id: 'comp_2',
          name: 'Trân Châu Đen 500g',
          code: 'TC_DEN',
          price: 30000,
          costPrice: 20000,
          branchStocks: {'store_001': 0, 'store_002': 0},
          category: 'Topping',
        );

        const combo = Product(
          id: 'combo_ts',
          name: 'Combo Trà Sữa Trân Châu Tự Pha',
          code: 'CB_TS',
          price: 50000,
          costPrice: 38000,
          branchStocks: {'store_001': 0, 'store_002': 0},
          category: 'Combo',
          isCombo: true,
          comboComponents: [
            ComboComponent(
              productId: 'comp_1',
              productCode: 'TS_MATCHA',
              productName: 'Trà Sữa Matcha 330ml',
              quantity: 1,
              costPrice: 18000,
            ),
            ComboComponent(
              productId: 'comp_2',
              productCode: 'TC_DEN',
              productName: 'Trân Châu Đen 500g',
              quantity: 1,
              costPrice: 20000,
            ),
          ],
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductTile(product: combo),
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([compInStock, compZeroStock, combo])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Hết hàng'), findsOneWidget);
        expect(find.text('Tồn bộ: 0'), findsOneWidget);
      });

      testWidgets('F3.6: ProductDetailPage handles empty branchStocks map gracefully',
          (tester) async {
        const emptyStockProduct = Product(
          id: 'prod_b_f3_06',
          name: 'Sản Phẩm Thử Nghiệm Không Kho',
          code: 'TEST_NO_STOCK',
          price: 15000,
          costPrice: 10000,
          branchStocks: {},
          category: 'Thử nghiệm',
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: emptyStockProduct),
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([emptyStockProduct])),
              transactionsByProductProvider(emptyStockProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Phân bổ tồn kho theo chi nhánh'), findsOneWidget);
        expect(find.text('0'), findsWidgets);
      });
    });

    // =========================================================================
    // F4: Boundary & Corner Cases (Active Store Form Pre-fill)
    // =========================================================================
    group('F4: Boundary & Corner Cases', () {
      testWidgets('F4.1: Pre-fills 0 when product has empty branchStocks',
          (tester) async {
        const productEmpty = Product(
          id: 'prod_b_f4_01',
          name: 'Khăn Lau Kính',
          code: 'KLK01',
          price: 15000,
          costPrice: 10000,
          branchStocks: {},
          category: 'Phụ kiện',
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: productEmpty),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([productEmpty])),
              transactionsByProductProvider(productEmpty.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = findStockTextField();
        expect(stockField, findsOneWidget);
        final textField = tester.widget<TextField>(stockField);
        expect(textField.controller?.text, equals('0'));
      });

      testWidgets('F4.2: Pre-fills 0 when active store explicitly has 0 stock',
          (tester) async {
        const productExplicitZero = Product(
          id: 'prod_b_f4_02',
          name: 'Nước Lau Sàn Sunlight Hương Quế 1kg',
          code: 'SUN_QUE',
          price: 32000,
          costPrice: 24000,
          branchStocks: {'store_001': 0, 'store_002': 40},
          category: 'Hóa phẩm',
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: productExplicitZero),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([productExplicitZero])),
              transactionsByProductProvider(productExplicitZero.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = findStockTextField();
        expect(stockField, findsOneWidget);
        final textField = tester.widget<TextField>(stockField);
        expect(textField.controller?.text, equals('0'));
      });

      testWidgets('F4.3: Pre-fills negative stock string when active store has negative stock',
          (tester) async {
        const productNeg = Product(
          id: 'prod_b_f4_03',
          name: 'Túi Rác Tự Hủy Cuộn 3',
          code: 'TR_3C',
          price: 28000,
          costPrice: 20000,
          branchStocks: {'store_001': -5, 'store_002': 15},
          category: 'Đồ gia dụng',
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: productNeg),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([productNeg])),
              transactionsByProductProvider(productNeg.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = findStockTextField();
        expect(stockField, findsOneWidget);
        final textField = tester.widget<TextField>(stockField);
        expect(textField.controller?.text, equals('-5'));
      });

      testWidgets('F4.4: Pre-fills extreme large stock number correctly',
          (tester) async {
        const productExtreme = Product(
          id: 'prod_b_f4_04',
          name: 'Ghim Bấm Số 10 Plus',
          code: 'GB_10',
          price: 5000,
          costPrice: 3000,
          branchStocks: {'store_001': 99999, 'store_002': 5000},
          category: 'Văn phòng phẩm',
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: productExtreme),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([productExtreme])),
              transactionsByProductProvider(productExtreme.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = findStockTextField();
        expect(stockField, findsOneWidget);
        final textField = tester.widget<TextField>(stockField);
        expect(textField.controller?.text, equals('99999'));
      });

      testWidgets('F4.5: Pre-fills 0 when currentStoreId is unknown identifier',
          (tester) async {
        const product = Product(
          id: 'prod_b_f4_05',
          name: 'Kẹp Bướm 19mm',
          code: 'KB_19',
          price: 18000,
          costPrice: 12000,
          branchStocks: {'store_001': 30, 'store_002': 20},
          category: 'Văn phòng phẩm',
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: product),
            currentStoreId: 'store_unknown_999',
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([product])),
              transactionsByProductProvider(product.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = findStockTextField();
        expect(stockField, findsOneWidget);
        final textField = tester.widget<TextField>(stockField);
        expect(textField.controller?.text, equals('0'));
      });

      testWidgets('F4.6: Pre-fills correctly when product record contains legacy branch_1 key',
          (tester) async {
        const productLegacy = Product(
          id: 'prod_b_f4_06',
          name: 'Bút Bi Thiên Long TL-027',
          code: 'TL027',
          price: 4000,
          costPrice: 2800,
          branchStocks: {'branch_1': 120, 'branch_2': 80},
          category: 'Văn phòng phẩm',
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: productLegacy),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([productLegacy])),
              transactionsByProductProvider(productLegacy.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = findStockTextField();
        expect(stockField, findsOneWidget);
        final textField = tester.widget<TextField>(stockField);
        expect(textField.controller?.text, equals('120'));
      });
    });

    // =========================================================================
    // F5: Boundary & Corner Cases (Dynamic Label & Edit View)
    // =========================================================================
    group('F5: Boundary & Corner Cases', () {
      testWidgets('F5.1: Out of stock product shows status in view mode',
          (tester) async {
        const outProduct = Product(
          id: 'prod_b_f5_01',
          name: 'Dầu Gội Rejoice Siêu Mượt 650g',
          code: 'REJ650',
          price: 135000,
          costPrice: 95000,
          branchStocks: {'store_001': 0, 'store_002': 0},
          category: 'Chăm sóc cá nhân',
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: outProduct),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([outProduct])),
              transactionsByProductProvider(outProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Hết hàng'), findsWidgets);
      });

      testWidgets('F5.2: Combo with multiple components displays combo notice in edit mode',
          (tester) async {
        const compA = Product(
          id: 'comp_a',
          name: 'Nước Tẩy Trang Garnier 400ml',
          code: 'GAR400',
          price: 150000,
          costPrice: 110000,
          branchStocks: {'store_001': 10, 'store_002': 5},
          category: 'Mỹ phẩm',
        );

        const compB = Product(
          id: 'comp_b',
          name: 'Bông Tẩy Trang Silcot 82 Miếng',
          code: 'SILCOT82',
          price: 38000,
          costPrice: 28000,
          branchStocks: {'store_001': 20, 'store_002': 15},
          category: 'Phụ kiện làm đẹp',
        );

        const combo = Product(
          id: 'combo_skincare',
          name: 'Combo Làm Sạch Sâu Skincare',
          code: 'CB_SKIN',
          price: 175000,
          costPrice: 138000,
          branchStocks: {'store_001': 0, 'store_002': 0},
          category: 'Combo',
          isCombo: true,
          comboComponents: [
            ComboComponent(
              productId: 'comp_a',
              productCode: 'GAR400',
              productName: 'Nước Tẩy Trang Garnier 400ml',
              quantity: 1,
              costPrice: 110000,
            ),
            ComboComponent(
              productId: 'comp_b',
              productCode: 'SILCOT82',
              productName: 'Bông Tẩy Trang Silcot 82 Miếng',
              quantity: 1,
              costPrice: 28000,
            ),
          ],
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: combo),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([compA, compB, combo])),
              transactionsByProductProvider(combo.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Tồn kho của Combo được tự động tính'), findsOneWidget);
      });

      testWidgets('F5.3: Switching current store context updates active store in UI',
          (tester) async {
        const product = Product(
          id: 'prod_b_f5_03',
          name: 'Bột Giặt OMO Đỏ 6kg',
          code: 'OMO6KG',
          price: 245000,
          costPrice: 195000,
          branchStocks: {'store_001': 18, 'store_002': 9},
          category: 'Chăm sóc nhà cửa',
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // Render at Store 1
        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: product),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([product])),
              transactionsByProductProvider(product.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField1 = findStockTextField();
        expect(stockField1, findsOneWidget);
        expect(tester.widget<TextField>(stockField1).controller?.text, equals('18'));

        // Reset widget tree
        await tester.pumpWidget(Container());
        await tester.pumpAndSettle();

        // Re-render at Store 2
        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: product),
            currentStoreId: 'store_002',
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([product])),
              transactionsByProductProvider(product.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField2 = findStockTextField();
        expect(stockField2, findsOneWidget);
        expect(tester.widget<TextField>(stockField2).controller?.text, equals('9'));
      });

      testWidgets('F5.4: Detail page renders product name with special characters and quotes',
          (tester) async {
        const specialProduct = Product(
          id: 'prod_b_f5_04',
          name: 'Kẹo Dẻo Trolli "Burger" [10g x 60 cái] (Special Edition!) 🔥',
          code: 'TROLLI_BURGER',
          price: 120000,
          costPrice: 85000,
          branchStocks: {'store_001': 15, 'store_002': 10},
          category: 'Bánh kẹo',
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: specialProduct),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([specialProduct])),
              transactionsByProductProvider(specialProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Trolli "Burger"'), findsWidgets);
      });

      testWidgets('F5.5: Detail page renders product with 0 price and 0 cost price safely',
          (tester) async {
        const freeProduct = Product(
          id: 'prod_b_f5_05',
          name: 'Quà Tặng Kèm Không Bán',
          code: 'GIFT01',
          price: 0,
          costPrice: 0,
          branchStocks: {'store_001': 50, 'store_002': 50},
          category: 'Quà tặng',
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: freeProduct),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([freeProduct])),
              transactionsByProductProvider(freeProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Quà Tặng Kèm Không Bán'), findsWidgets);
      });
    });

    // =========================================================================
    // F6: Boundary & Corner Cases (Mutation, Persistence & Ledger Audit)
    // =========================================================================
    group('F6: Boundary & Corner Cases', () {
      testWidgets('F6.1: Mutation from 0 to 100 sets stock to 100 and emits audit +100',
          (tester) async {
        const productFromZero = Product(
          id: 'prod_b_f6_01',
          name: 'Nước Tẩy Quần Áo Javel 1L',
          code: 'JAVEL1L',
          price: 15000,
          costPrice: 10000,
          branchStocks: {'store_001': 0, 'store_002': 10},
          category: 'Hóa phẩm',
        );

        final fakeProductRepo = _FakeProductRepository([productFromZero]);
        final fakeInventoryRepo = _FakeInventoryRepository();

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: productFromZero),
            currentStoreId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([productFromZero])),
              transactionsByProductProvider(productFromZero.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = findStockTextField();
        await tester.enterText(stockField, '100');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        final updated = fakeProductRepo.lastUpsertedProduct!;
        expect(updated.branchStocks['store_001'], equals(100));
        expect(updated.stock, equals(110)); // 100 + 10 = 110

        expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
        final tx = fakeInventoryRepo.recordedTransactions.first;
        expect(tx.quantity, equals(100));
        expect(tx.note, contains('+100'));
      });

      testWidgets('F6.2: Mutation from 100 to 0 sets stock to 0 and emits audit -100',
          (tester) async {
        const productToZero = Product(
          id: 'prod_b_f6_02',
          name: 'Nước Rửa Tay Lifebuoy 500g',
          code: 'LB500',
          price: 68000,
          costPrice: 50000,
          branchStocks: {'store_001': 100, 'store_002': 20},
          category: 'Vệ sinh cá nhân',
        );

        final fakeProductRepo = _FakeProductRepository([productToZero]);
        final fakeInventoryRepo = _FakeInventoryRepository();

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: productToZero),
            currentStoreId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([productToZero])),
              transactionsByProductProvider(productToZero.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = findStockTextField();
        await tester.enterText(stockField, '0');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        final updated = fakeProductRepo.lastUpsertedProduct!;
        expect(updated.branchStocks['store_001'], equals(0));
        expect(updated.stock, equals(20)); // 0 + 20 = 20

        expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
        final tx = fakeInventoryRepo.recordedTransactions.first;
        expect(tx.quantity, equals(100));
        expect(tx.note, contains('-100'));
      });

      testWidgets('F6.3: Mutation with identical stock does NOT emit audit transaction',
          (tester) async {
        const productSame = Product(
          id: 'prod_b_f6_03',
          name: 'Nước Súc Miệng Listerine 750ml',
          code: 'LIST750',
          price: 125000,
          costPrice: 90000,
          branchStocks: {'store_001': 25, 'store_002': 15},
          category: 'Chăm sóc răng miệng',
        );

        final fakeProductRepo = _FakeProductRepository([productSame]);
        final fakeInventoryRepo = _FakeInventoryRepository();

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: productSame),
            currentStoreId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([productSame])),
              transactionsByProductProvider(productSame.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Re-enter 25 unchanged
        final stockField = findStockTextField();
        await tester.enterText(stockField, '25');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        expect(fakeInventoryRepo.recordedTransactions.isEmpty, isTrue);
      });

      testWidgets('F6.4: Mutation for product with legacy branch_1 key updates target stock',
          (tester) async {
        const productLegacy = Product(
          id: 'prod_b_f6_04',
          name: 'Kem Đánh Răng Colgate Total 180g',
          code: 'COL180',
          price: 48000,
          costPrice: 35000,
          branchStocks: {'branch_1': 40, 'branch_2': 20},
          category: 'Chăm sóc răng miệng',
        );

        final fakeProductRepo = _FakeProductRepository([productLegacy]);
        final fakeInventoryRepo = _FakeInventoryRepository();

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: productLegacy),
            currentStoreId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([productLegacy])),
              transactionsByProductProvider(productLegacy.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = findStockTextField();
        await tester.enterText(stockField, '55'); // +15
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
        final tx = fakeInventoryRepo.recordedTransactions.first;
        expect(tx.quantity, equals(15));
        expect(tx.note, contains('+15'));
      });

      testWidgets('F6.5: Mutation in 3-store network mutates only active store and leaves others intact',
          (tester) async {
        const product3Stores = Product(
          id: 'prod_b_f6_05',
          name: 'Bàn Chải Đánh Răng PS Than Hoạt Tính',
          code: 'PS_CHAR',
          price: 25000,
          costPrice: 16000,
          branchStocks: {
            'store_001': 30,
            'store_002': 20,
            'store_003': 10,
          },
          category: 'Chăm sóc cá nhân',
        );

        final fakeProductRepo = _FakeProductRepository([product3Stores]);
        final fakeInventoryRepo = _FakeInventoryRepository();

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: product3Stores),
            currentStoreId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([product3Stores])),
              transactionsByProductProvider(product3Stores.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = findStockTextField();
        await tester.enterText(stockField, '45');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        final updated = fakeProductRepo.lastUpsertedProduct!;
        expect(updated.branchStocks['store_001'], equals(45));
        expect(updated.branchStocks['store_002'], equals(20)); // Intact!
        expect(updated.branchStocks['store_003'], equals(10)); // Intact!
        expect(updated.stock, equals(75)); // 45 + 20 + 10
      });

      testWidgets('F6.6: Combo product save never records audit transaction',
          (tester) async {
        const combo = Product(
          id: 'prod_b_f6_06',
          name: 'Combo Chăm Sóc Nụ Cười',
          code: 'CB_SMILE',
          price: 70000,
          costPrice: 50000,
          branchStocks: {'store_001': 0, 'store_002': 0},
          category: 'Combo',
          isCombo: true,
          comboComponents: [
            ComboComponent(
              productId: 'colgate_id',
              productCode: 'COL180',
              productName: 'Kem Đánh Răng Colgate Total 180g',
              quantity: 1,
              costPrice: 35000,
            ),
          ],
        );

        final fakeProductRepo = _FakeProductRepository([combo]);
        final fakeInventoryRepo = _FakeInventoryRepository();

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: combo),
            currentStoreId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([combo])),
              transactionsByProductProvider(combo.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        expect(fakeInventoryRepo.recordedTransactions.isEmpty, isTrue);
      });
    });

    // =========================================================================
    // F7: Boundary & Corner Cases (Structured InventoryTransaction Serialization)
    // =========================================================================
    group('F7: Boundary & Corner Cases', () {
      test('F7.1: InventoryTransactionModel serializes with null optional fields safely', () {
        final tx = InventoryTransactionModel(
          id: 'tx_b_f7_01',
          productId: 'prod_null_opt',
          type: 'import',
          quantity: 10,
          date: DateTime(2026, 8, 17),
          note: 'Nhập hàng không ghi chú giá',
          importPrice: null,
          createdBy: null,
          createdByName: null,
        );

        final map = tx.toMap();
        expect(map['importPrice'], isNull);
        expect(map.containsKey('createdBy'), isFalse);
        expect(map.containsKey('createdByName'), isFalse);

        final restored = InventoryTransactionModel.fromMap(map);
        expect(restored.importPrice, isNull);
        expect(restored.createdBy, isNull);
        expect(restored.createdByName, isNull);
      });

      test('F7.2: InventoryTransaction with quantity 0 is handled safely', () {
        final txZero = InventoryTransaction(
          id: 'tx_zero',
          productId: 'p_zero',
          type: TransactionType.inventoryAudit,
          quantity: 0,
          date: DateTime.now(),
          note: 'Kiểm kê không chênh lệch (0)',
        );

        expect(txZero.quantity, equals(0));
      });

      test('F7.3: InventoryTransactionModel.fromMap with corrupted date string falls back to current time', () {
        final corruptedMap = {
          'id': 'tx_corrupt_date',
          'productId': 'prod_p1',
          'type': 'import',
          'quantity': 5,
          'date': 'INVALID_NON_ISO_DATE_STRING',
          'note': 'Lỗi ngày',
        };

        final model = InventoryTransactionModel.fromMap(corruptedMap);
        expect(model.date, isNotNull);
      });

      test('F7.4: parseTransactionType with unknown type string defaults to import', () {
        expect(
          InventoryTransactionModel.parseTransactionType('UNKNOWN_CUSTOM_TYPE'),
          equals(TransactionType.import),
        );
        expect(
          InventoryTransactionModel.parseTransactionType(''),
          equals(TransactionType.import),
        );
      });

      test('F7.5: InventoryTransactionModel handles decimal prices accurately', () {
        final txDecimal = InventoryTransactionModel(
          id: 'tx_dec',
          productId: 'prod_dec',
          type: 'import',
          quantity: 10,
          date: DateTime(2026, 8, 17),
          note: 'Nhập giá lẻ',
          importPrice: 12345.67,
        );

        final map = txDecimal.toMap();
        expect(map['importPrice'], equals(12345.67));

        final restored = InventoryTransactionModel.fromMap(map);
        expect(restored.importPrice, equals(12345.67));
      });

      test('F7.6: InventoryTransactionModel handles extreme large quantity without overflow', () {
        final txLarge = InventoryTransactionModel(
          id: 'tx_large_qty',
          productId: 'prod_large_qty',
          type: 'import',
          quantity: 10000000,
          date: DateTime(2026, 8, 17),
          note: 'Nhập số lượng lớn',
        );

        final map = txLarge.toMap();
        expect(map['quantity'], equals(10000000));

        final restored = InventoryTransactionModel.fromMap(map);
        expect(restored.quantity, equals(10000000));
      });
    });

    // =========================================================================
    // F8: Boundary & Corner Cases (Store-Partitioned FIFO Lot Queues)
    // =========================================================================
    group('F8: Boundary & Corner Cases', () {
      test('F8.1: FifoCalculator initialized with empty list returns empty lots', () {
        final tracker = FifoCalculator([]);
        expect(tracker.getInventoryLots('unknown_prod').isEmpty, isTrue);

        final cost = tracker.calculateCostForSale(
          productId: 'unknown_prod',
          quantity: 5,
          saleDate: DateTime.now(),
        );
        expect(cost, equals(0.0));
      });

      test('F8.2: calculateCostForSale with quantity 0 returns 0.0 and leaves lots untouched', () {
        final tracker = FifoCalculator([
          InventoryTransaction(
            id: 'imp_0',
            productId: 'prod_qty0',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1),
            note: 'Nhập',
            importPrice: 15000,
          ),
        ]);

        final cost = tracker.calculateCostForSale(
          productId: 'prod_qty0',
          quantity: 0,
          saleDate: DateTime(2026, 8, 2),
        );

        expect(cost, equals(0.0));
        expect(tracker.getInventoryLots('prod_qty0').first.remainingQuantity, equals(10));
      });

      test('F8.3: calculateCostForSale with negative quantity returns 0.0', () {
        final tracker = FifoCalculator([
          InventoryTransaction(
            id: 'imp_neg',
            productId: 'prod_neg',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1),
            note: 'Nhập',
            importPrice: 15000,
          ),
        ]);

        final cost = tracker.calculateCostForSale(
          productId: 'prod_neg',
          quantity: -5,
          saleDate: DateTime(2026, 8, 2),
        );

        expect(cost, equals(0.0));
        expect(tracker.getInventoryLots('prod_neg').first.remainingQuantity, equals(10));
      });

      test('F8.4: calculateCostForSale with empty lot queue computes cost via fallback price', () {
        final tracker = FifoCalculator();

        final cost = tracker.calculateCostForSale(
          productId: 'prod_fallback_only',
          quantity: 8,
          saleDate: DateTime.now(),
          fallbackCostPrice: 25000,
        );

        expect(cost, equals(8 * 25000)); // 200,000
      });

      test('F8.5: calculateCostForSale with empty queue and null fallback returns 0.0', () {
        final tracker = FifoCalculator();

        final cost = tracker.calculateCostForSale(
          productId: 'prod_no_fallback',
          quantity: 5,
          saleDate: DateTime.now(),
          fallbackCostPrice: null,
        );

        expect(cost, equals(0.0));
      });

      test('F8.6: getInventoryLots for non-existent product returns empty list', () {
        final tracker = FifoCalculator();
        expect(tracker.getInventoryLots('non_existent_prod_123'), equals([]));
      });
    });

    // =========================================================================
    // F9: Boundary & Corner Cases for 6 FIFO Edge Cases
    // =========================================================================
    group('F9: Boundary & Corner Cases for 6 FIFO Edge Cases', () {
      test('F9.1 (Case 1 - Imports): Import with 0 price creates lot with unitCost 0.0', () {
        final tracker = FifoCalculator([
          InventoryTransaction(
            id: 'imp_free',
            productId: 'p_free',
            type: TransactionType.import,
            quantity: 20,
            date: DateTime(2026, 8, 1),
            note: 'Hàng tặng miễn phí',
            importPrice: 0.0,
          ),
        ]);

        final lots = tracker.getInventoryLots('p_free');
        expect(lots.first.unitCost, equals(0.0));
        expect(lots.first.remainingQuantity, equals(20));

        final cost = tracker.calculateCostForSale(
          productId: 'p_free',
          quantity: 10,
          saleDate: DateTime(2026, 8, 2),
        );
        expect(cost, equals(0.0));
        expect(lots.first.remainingQuantity, equals(10));
      });

      test('F9.2 (Case 2 - POS Sales Extreme Oversold): Oversold 1000 units on 5 units lot clamps lot to 0', () {
        final tracker = FifoCalculator([
          InventoryTransaction(
            id: 'imp_tiny',
            productId: 'p_tiny',
            type: TransactionType.import,
            quantity: 5,
            date: DateTime(2026, 8, 1),
            note: 'Lô nhỏ',
            importPrice: 10000,
          ),
        ]);

        // Sell 1000 with fallback 20,000: 5 @ 10k + 995 @ 20k = 50,000 + 19,900,000 = 19,950,000
        final cost = tracker.calculateCostForSale(
          productId: 'p_tiny',
          quantity: 1000,
          saleDate: DateTime(2026, 8, 2),
          fallbackCostPrice: 20000,
        );

        expect(cost, equals(5 * 10000 + 995 * 20000));
        final lots = tracker.getInventoryLots('p_tiny');
        expect(lots.first.remainingQuantity, equals(0)); // Never negative
      });

      test('F9.3 (Case 3 - Transfers Validation): Validates all transfer boundary error states', () async {
        final service = InterStoreTransferService(null);
        const product = Product(
          id: 'p_transfer_b',
          name: 'Bánh Gạo One One 150g',
          code: 'ONEONE',
          price: 28000,
          costPrice: 20000,
          branchStocks: {'store_001': 10, 'store_002': 10},
          category: 'Bánh kẹo',
        );

        // Empty store ID
        final errEmptySource = await service.transferProduct(
          sourceStoreId: '',
          targetStoreId: 'store_002',
          product: product,
          quantity: 5,
        );
        expect(errEmptySource, equals('Chi nhánh không hợp lệ'));

        // Negative quantity
        final errNegQty = await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: 'store_002',
          product: product,
          quantity: -3,
        );
        expect(errNegQty, equals('Số lượng phải lớn hơn 0'));

        // Self transfer
        final errSelf = await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: 'store_001',
          product: product,
          quantity: 5,
        );
        expect(errSelf, equals('Không thể chuyển cùng kho'));
      });

      test('F9.4 (Case 4 - Positive Audit on Empty Inventory): Initializes first lot properly', () {
        final tracker = FifoCalculator([
          InventoryTransaction(
            id: 'audit_init',
            productId: 'p_audit_empty',
            type: TransactionType.inventoryAudit,
            quantity: 15,
            date: DateTime(2026, 8, 1),
            note: 'Cân bằng kho ban đầu (+15)',
            importPrice: 22000,
          ),
        ]);

        final lots = tracker.getInventoryLots('p_audit_empty');
        expect(lots.length, equals(1));
        expect(lots.first.remainingQuantity, equals(15));
        expect(lots.first.unitCost, equals(22000));
      });

      test('F9.5 (Case 5 - Negative Audit Excess Drain): Excess drainage clamps all lots to 0', () {
        final tracker = FifoCalculator([
          InventoryTransaction(
            id: 'imp_1',
            productId: 'p_excess_drain',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1),
            note: 'Lô 1',
            importPrice: 10000,
          ),
          InventoryTransaction(
            id: 'imp_2',
            productId: 'p_excess_drain',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 2),
            note: 'Lô 2',
            importPrice: 15000,
          ),
          InventoryTransaction(
            id: 'audit_huge_loss',
            productId: 'p_excess_drain',
            type: TransactionType.inventoryAudit,
            quantity: 500, // Much larger than total stock (20)
            date: DateTime(2026, 8, 3),
            note: 'Cân bằng kho trực tiếp (Tồn cũ: 20 -> Tồn mới: 0, chênh lệch: -500)',
          ),
        ]);

        final lots = tracker.getInventoryLots('p_excess_drain');
        expect(lots[0].remainingQuantity, equals(0));
        expect(lots[1].remainingQuantity, equals(0));

        // Subsequent sale should use fallback cost
        final cost = tracker.calculateCostForSale(
          productId: 'p_excess_drain',
          quantity: 5,
          saleDate: DateTime(2026, 8, 4),
          fallbackCostPrice: 30000,
        );
        expect(cost, equals(5 * 30000));
      });

      test('F9.6 (Case 6 - Profit Margin Boundary Values): Handles zero cost, loss sale, and zero revenue', () {
        // Free cost -> 100% margin
        final margin100 = FifoCalculator.calculateProfitMargin(50000, 0);
        expect(margin100, equals(100.0));

        // Loss sale (cost > revenue) -> negative margin
        final marginLoss = FifoCalculator.calculateProfitMargin(80000, 100000);
        expect(marginLoss, equals(-25.0)); // (80k - 100k) / 80k * 100 = -25%

        // Zero revenue -> 0.0
        final marginZeroRev = FifoCalculator.calculateProfitMargin(0, 100000);
        expect(marginZeroRev, equals(0.0));
      });

      test('F9.7 (Complex FIFO Lifecycle): Full multi-transaction sequence with imports, audits, sales', () {
        final txs = [
          // 1. Initial import 10 @ 10k
          InventoryTransaction(
            id: 'tx_1',
            productId: 'p_lifecycle',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1, 8, 0),
            note: 'Nhập đợt 1',
            importPrice: 10000,
          ),
          // 2. Second import 10 @ 12k
          InventoryTransaction(
            id: 'tx_2',
            productId: 'p_lifecycle',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1, 12, 0),
            note: 'Nhập đợt 2',
            importPrice: 12000,
          ),
          // 3. Positive audit +5 @ 14k
          InventoryTransaction(
            id: 'tx_3',
            productId: 'p_lifecycle',
            type: TransactionType.inventoryAudit,
            quantity: 5,
            date: DateTime(2026, 8, 2, 9, 0),
            note: 'Cân bằng kho (+5)',
            importPrice: 14000,
          ),
          // 4. Negative audit -3 (drains from Lot 1)
          InventoryTransaction(
            id: 'tx_4',
            productId: 'p_lifecycle',
            type: TransactionType.inventoryAudit,
            quantity: 3,
            date: DateTime(2026, 8, 2, 15, 0),
            note: 'Cân bằng kho (-3)',
          ),
        ];

        final tracker = FifoCalculator(txs);

        // State after setup:
        // Lot 1: 10 - 3 = 7 remaining @ 10k
        // Lot 2: 10 remaining @ 12k
        // Lot 3 (Audit +): 5 remaining @ 14k
        // Total available = 22

        // Sell 12: 7 from Lot 1 @ 10k + 5 from Lot 2 @ 12k = 70k + 60k = 130k
        final cost = tracker.calculateCostForSale(
          productId: 'p_lifecycle',
          quantity: 12,
          saleDate: DateTime(2026, 8, 3),
        );

        expect(cost, equals(130000));

        final lots = tracker.getInventoryLots('p_lifecycle');
        expect(lots[0].remainingQuantity, equals(0)); // Lot 1 depleted
        expect(lots[1].remainingQuantity, equals(5)); // Lot 2 has 5 left
        expect(lots[2].remainingQuantity, equals(5)); // Lot 3 has 5 left
      });
    });
  });
}
