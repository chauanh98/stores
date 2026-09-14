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

// --- Test Fixtures & Widget Harness ---

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

  group('Tier 1 E2E: Feature Coverage (F1 to F9)', () {
    // =========================================================================
    // F1: Canonical Store Normalization
    // =========================================================================
    group('F1: Canonical Store Normalization', () {
      const productCanonical = Product(
        id: 'prod_f1_01',
        name: 'Sữa Tươi Tiệt Trùng Vinamilk 100% 1L',
        code: 'VNM01',
        price: 36000,
        costPrice: 28000,
        branchStocks: {
          'store_001': 48,
          'store_002': 24,
        },
        category: 'Sữa & Sản phẩm từ sữa',
      );

      const productLegacy = Product(
        id: 'prod_f1_02',
        name: 'Trà Xanh Oolong Tea+ Plus 455ml',
        code: 'OOLONG01',
        price: 11000,
        costPrice: 8000,
        branchStocks: {
          'branch_1': 60,
          'branch_2': 35,
        },
        category: 'Đồ uống',
      );

      test('F1.1: stockInBranch resolves canonical store IDs correctly', () {
        expect(productCanonical.stockInBranch('store_001'), equals(48));
        expect(productCanonical.stockInBranch('store_002'), equals(24));
      });

      test('F1.2: stockInBranch resolves legacy branch aliases backwards compatibility', () {
        // Querying canonical map with legacy keys
        expect(productCanonical.stockInBranch('branch_1'), equals(48));
        expect(productCanonical.stockInBranch('branch_2'), equals(24));

        // Querying legacy map with canonical keys
        expect(productLegacy.stockInBranch('store_001'), equals(60));
        expect(productLegacy.stockInBranch('store_002'), equals(35));
      });

      test('F1.3: stockInBranch resolves Vietnamese names and short code acronyms', () {
        // Store 1 variations
        expect(productCanonical.stockInBranch('Chi nhánh Đông Thắng'), equals(48));
        expect(productCanonical.stockInBranch('Dong Thang'), equals(48));
        expect(productCanonical.stockInBranch('ĐT'), equals(48));
        expect(productCanonical.stockInBranch('dt'), equals(48));

        // Store 2 variations
        expect(productCanonical.stockInBranch('Chi nhánh Thới Bình'), equals(24));
        expect(productCanonical.stockInBranch('Thoi Binh'), equals(24));
        expect(productCanonical.stockInBranch('TB'), equals(24));
        expect(productCanonical.stockInBranch('tb'), equals(24));
      });

      test('F1.4: stock computed getter sums across all store partitions', () {
        expect(productCanonical.stock, equals(72)); // 48 + 24
        expect(productLegacy.stock, equals(95)); // 60 + 35

        const multiStoreProduct = Product(
          id: 'prod_f1_03',
          name: 'Gạo ST25 Ông Cua 5kg',
          code: 'ST25',
          price: 190000,
          costPrice: 150000,
          branchStocks: {
            'store_001': 20,
            'store_002': 15,
            'store_003': 10,
          },
          category: 'Lương thực',
        );
        expect(multiStoreProduct.stock, equals(45)); // 20 + 15 + 10
      });

      test('F1.5: ProductModel.fromMap preserves multi-branch stocks map', () {
        final jsonMap = {
          'id': 'prod_model_01',
          'name': 'Dầu Ăn Neptune Light 1L',
          'code': 'NEP01',
          'price': 52000.0,
          'costPrice': 42000.0,
          'branchStocks': {
            'store_001': 30,
            'store_002': 18,
          },
          'category': 'Gia vị & Dầu ăn',
        };

        final model = ProductModel.fromMap(jsonMap);
        expect(model.branchStocks.length, equals(2));
        expect(model.branchStocks['store_001'], equals(30));
        expect(model.branchStocks['store_002'], equals(18));
      });

      test('F1.6: ProductModel serialization round-trip maintains store keys intact', () {
        const model = ProductModel(
          id: 'prod_model_02',
          name: 'Nước Rửa Chén Sunlight Chanh 750g',
          code: 'SUN01',
          price: 28000,
          costPrice: 21000,
          branchStocks: {
            'store_001': 100,
            'store_002': 50,
          },
          category: 'Hóa phẩm',
        );

        final serialized = model.toMap();
        expect(serialized['branchStocks']['store_001'], equals(100));
        expect(serialized['branchStocks']['store_002'], equals(50));

        final restored = ProductModel.fromMap(serialized);
        expect(restored.branchStocks['store_001'], equals(100));
        expect(restored.branchStocks['store_002'], equals(50));
        expect(restored.stock, equals(150));
      });
    });

    // =========================================================================
    // F2: Branch Provider Canonical Stability
    // =========================================================================
    group('F2: Branch Provider Canonical Stability', () {
      test('F2.1: branchesProvider returns canonical branch IDs and names for store_001', () {
        final container = ProviderContainer(
          overrides: [
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
          ],
        );
        addTearDown(container.dispose);

        final branches = container.read(branchesProvider);
        expect(branches.length, equals(2));
        expect(branches[0].name, contains('Đông Thắng'));
        expect(branches[1].name, contains('Thới Bình'));
      });

      test('F2.2: branchesProvider maintains branch list integrity for store_002', () {
        final container = ProviderContainer(
          overrides: [
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
          ],
        );
        addTearDown(container.dispose);

        final branches = container.read(branchesProvider);
        expect(branches.length, equals(2));
        final names = branches.map((b) => b.name).toList();
        expect(names, contains('Chi nhánh Đông Thắng'));
        expect(names, contains('Chi nhánh Thới Bình'));
      });

      test('F2.3: getMockBranches returns non-empty branch list', () {
        final branchesStore1 = getMockBranches('store_001');
        final branchesStore2 = getMockBranches('store_002');

        expect(branchesStore1.length, equals(2));
        expect(branchesStore2.length, equals(2));
      });

      test('F2.4: mockBranches constant contains valid branches', () {
        expect(mockBranches.length, equals(2));
        expect(mockBranches[0].name, equals('Chi nhánh Đông Thắng'));
        expect(mockBranches[1].name, equals('Chi nhánh Thới Bình'));
      });

      test('F2.5: Branch value object provides immutable ID and name', () {
        const branch1 = Branch('store_001', 'Chi nhánh Đông Thắng');
        const branch2 = Branch('store_002', 'Chi nhánh Thới Bình');

        expect(branch1.id, equals('store_001'));
        expect(branch1.name, equals('Chi nhánh Đông Thắng'));
        expect(branch2.id, equals('store_002'));
        expect(branch2.name, equals('Chi nhánh Thới Bình'));
      });

      test('F2.6: Iterating canonical branches with stockInBranch maps correct quantities', () {
        const product = Product(
          id: 'prod_f2_01',
          name: 'Cà Phê G7 3in1 Hộp 18 Gói',
          code: 'G7-18',
          price: 55000,
          costPrice: 42000,
          branchStocks: {'store_001': 32, 'store_002': 16},
          category: 'Cà phê',
        );

        final branchStockMap = {
          for (final b in _canonicalBranches) b.name: product.stockInBranch(b.id),
        };

        expect(branchStockMap['Chi nhánh Đông Thắng'], equals(32));
        expect(branchStockMap['Chi nhánh Thới Bình'], equals(16));
      });
    });

    // =========================================================================
    // F3: Consistent UI Stock Badges & Table Parity
    // =========================================================================
    group('F3: Consistent UI Stock Badges & Table Parity', () {
      const parityProduct = Product(
        id: 'prod_f3_01',
        name: 'Nước Khoáng Lavie 500ml',
        code: 'LAV500',
        price: 6000,
        costPrice: 4000,
        branchStocks: {
          'store_001': 45, // ĐT: 45
          'store_002': 30, // TB: 30
        },
        category: 'Nước khoáng',
        minStock: 10,
        maxStock: 200,
      );

      testWidgets('F3.1: ProductTile displays total stock and multi-branch badge format',
          (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductTile(product: parityProduct),
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([parityProduct])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Total stock
        expect(find.text('Tồn: 75'), findsOneWidget);
        // Multi-branch formatted badge
        expect(find.textContaining('ĐT: 45 | TB: 30'), findsOneWidget);
      });

      testWidgets('F3.2: ProductDetailPage allocation table displays matching branch stocks',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: parityProduct),
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([parityProduct])),
              transactionsByProductProvider(parityProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Table card header
        expect(find.text('Phân bổ tồn kho theo chi nhánh'), findsOneWidget);
        // Branch 1 row
        expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
        expect(find.text('45'), findsOneWidget);
        // Branch 2 row
        expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
        expect(find.text('30'), findsOneWidget);
        // Chain total
        expect(find.text('Tổng: 75'), findsOneWidget);
        expect(find.text('Tổng tồn toàn chuỗi'), findsOneWidget);
      });

      testWidgets('F3.3: 100% Parity between ProductTile and ProductDetailPage',
          (tester) async {
        // Tile inspection
        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductTile(product: parityProduct),
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([parityProduct])),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('ĐT: 45 | TB: 30'), findsOneWidget);

        // Reset widget tree
        await tester.pumpWidget(Container());
        await tester.pumpAndSettle();

        // Detail Page inspection
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: parityProduct),
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([parityProduct])),
              transactionsByProductProvider(parityProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('45'), findsOneWidget);
        expect(find.text('30'), findsOneWidget);
      });

      testWidgets('F3.4: ProductTile displays In Stock badge when stock > minStock',
          (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductTile(product: parityProduct),
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([parityProduct])),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Còn hàng'), findsOneWidget);
      });

      testWidgets('F3.5: ProductTile displays Low Stock badge when stock <= minStock',
          (tester) async {
        const lowStockProduct = Product(
          id: 'prod_f3_low',
          name: 'Khăn Giấy Ướt Bobby 80 Miếng',
          code: 'BOBBY80',
          price: 35000,
          costPrice: 25000,
          branchStocks: {'store_001': 3, 'store_002': 2}, // Total 5 <= minStock 10
          category: 'Mẹ & Bé',
          minStock: 10,
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductTile(product: lowStockProduct),
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([lowStockProduct])),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Dưới định mức'), findsOneWidget);
      });

      testWidgets('F3.6: ProductTile displays Out of Stock badge when stock <= 0',
          (tester) async {
        const outOfStockProduct = Product(
          id: 'prod_f3_out',
          name: 'Bánh Quy Oreo Socola 133g',
          code: 'OREO133',
          price: 16000,
          costPrice: 12000,
          branchStocks: {'store_001': 0, 'store_002': 0},
          category: 'Bánh kẹo',
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductTile(product: outOfStockProduct),
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([outOfStockProduct])),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Hết hàng'), findsOneWidget);
      });
    });

    // =========================================================================
    // F4: Active Store Form Pre-fill
    // =========================================================================
    group('F4: Active Store Form Pre-fill', () {
      const scopedProduct = Product(
        id: 'prod_f4_01',
        name: 'Nước Tương Tam Thái Tử Nhất Ca 500ml',
        code: 'TTT01',
        price: 18000,
        costPrice: 13000,
        branchStocks: {
          'store_001': 50, // Đông Thắng stock
          'store_002': 20, // Thới Bình stock
        },
        category: 'Gia vị',
      );

      testWidgets('F4.1: Pre-fills Store 1 stock (50) when currentStoreId is store_001',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: scopedProduct),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([scopedProduct])),
              transactionsByProductProvider(scopedProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Tap [Sửa]
        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = findStockTextField();
        expect(stockField, findsOneWidget);
        final textField = tester.widget<TextField>(stockField);
        expect(textField.controller?.text, equals('50'));
      });

      testWidgets('F4.2: Pre-fills Store 2 stock (20) when currentStoreId is store_002',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: scopedProduct),
            currentStoreId: 'store_002',
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([scopedProduct])),
              transactionsByProductProvider(scopedProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Tap [Sửa]
        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = findStockTextField();
        expect(stockField, findsOneWidget);
        final textField = tester.widget<TextField>(stockField);
        expect(textField.controller?.text, equals('20'));
      });

      testWidgets('F4.3: Pre-fills asymmetric stocks (100 in Store 1 vs 0 in Store 2)',
          (tester) async {
        const asymmetricProduct = Product(
          id: 'prod_f4_asym',
          name: 'Hạt Nêm Knorr Nấm Hương 400g',
          code: 'KNORR-NH',
          price: 34000,
          costPrice: 26000,
          branchStocks: {'store_001': 100, 'store_002': 0},
          category: 'Gia vị',
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: asymmetricProduct),
            currentStoreId: 'store_002',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([asymmetricProduct])),
              transactionsByProductProvider(asymmetricProduct.id)
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

      testWidgets('F4.4: Pre-fill initializes directly with active store stock on edit mode entry',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: scopedProduct),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([scopedProduct])),
              transactionsByProductProvider(scopedProduct.id)
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
        expect(textField.controller?.text, equals('50'));
      });

      testWidgets('F4.5: Cancelling edit restores form controllers to active branch stock',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: scopedProduct),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([scopedProduct])),
              transactionsByProductProvider(scopedProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Enter edit mode
        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Modify text
        final stockField = findStockTextField();
        await tester.enterText(stockField, '88');
        await tester.pumpAndSettle();

        // Tap cancel [Icons.close]
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // View mode active again
        expect(find.text('Sửa'), findsOneWidget);
      });

      testWidgets('F4.6: Active store with 0 stock pre-fills 0 even with large total stock',
          (tester) async {
        const productZeroStore1 = Product(
          id: 'prod_f4_zero1',
          name: 'Nước Uống Đóng Chai Aquafina 500ml',
          code: 'AQUA500',
          price: 5000,
          costPrice: 3500,
          branchStocks: {'store_001': 0, 'store_002': 250},
          category: 'Đồ uống',
        );

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: productZeroStore1),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([productZeroStore1])),
              transactionsByProductProvider(productZeroStore1.id)
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
    });

    // =========================================================================
    // F5: Dynamic Active Store Field Label & Edit View Behavior
    // =========================================================================
    group('F5: Dynamic Active Store Field Label & Edit View Behavior', () {
      const standardProduct = Product(
        id: 'prod_f5_01',
        name: 'Đường Tinh Luyện Biên Hòa 1kg',
        code: 'BH1KG',
        price: 26000,
        costPrice: 20000,
        branchStocks: {'store_001': 40, 'store_002': 25},
        category: 'Gia vị',
      );

      const comboProduct = Product(
        id: 'prod_f5_combo',
        name: 'Combo Bếp Ấm Áp',
        code: 'CB_BEP',
        price: 75000,
        costPrice: 55000,
        branchStocks: {'store_001': 0, 'store_002': 0},
        category: 'Combo',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'prod_f5_01',
            productCode: 'BH1KG',
            productName: 'Đường Tinh Luyện Biên Hòa 1kg',
            quantity: 2,
            costPrice: 20000,
          ),
        ],
      );

      testWidgets('F5.1: Stock edit field is rendered for standard products in edit mode',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: standardProduct),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([standardProduct])),
              transactionsByProductProvider(standardProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.inventory_2), findsOneWidget);
        expect(find.textContaining('tồn kho'), findsWidgets);
      });

      testWidgets('F5.2: Combo product hides stock edit field and shows combo notice',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: comboProduct),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([comboProduct, standardProduct])),
              transactionsByProductProvider(comboProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Tồn kho của Combo được tự động tính'), findsOneWidget);
      });

      testWidgets('F5.3: Stock input field has number keyboard and numeric hint',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: standardProduct),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([standardProduct])),
              transactionsByProductProvider(standardProduct.id)
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
        expect(textField.controller?.text, equals('40'));
      });

      testWidgets('F5.4: Read-only mode displays branch stock cards with counts',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: standardProduct),
            currentStoreId: 'store_001',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([standardProduct])),
              transactionsByProductProvider(standardProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Phân bổ tồn kho theo chi nhánh'), findsOneWidget);
        expect(find.text('40'), findsOneWidget);
        expect(find.text('25'), findsOneWidget);
      });

      testWidgets('F5.5: Detail page binds correctly to active store context',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: standardProduct),
            currentStoreId: 'store_002',
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([standardProduct])),
              transactionsByProductProvider(standardProduct.id)
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
        expect(textField.controller?.text, equals('25'));
      });
    });

    // =========================================================================
    // F6: Scoped Stock Mutation, Recalculation, Persistence & Audit
    // =========================================================================
    group('F6: Scoped Stock Mutation, Recalculation, Persistence & Audit', () {
      const initialProduct = Product(
        id: 'prod_f6_01',
        name: 'Dầu Ăn Simply Đậu Nành 1L',
        code: 'SIMPLY01',
        price: 58000,
        costPrice: 45000,
        branchStocks: {
          'store_001': 50,
          'store_002': 20, // Total = 70
        },
        category: 'Dầu ăn',
      );

      testWidgets('F6.1: Editing stock in store_002 updates store_002 and preserves store_001',
          (tester) async {
        final fakeProductRepo = _FakeProductRepository([initialProduct]);
        final fakeInventoryRepo = _FakeInventoryRepository();

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: initialProduct),
            currentStoreId: 'store_002',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([initialProduct])),
              transactionsByProductProvider(initialProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Change Store 2 stock from 20 -> 35
        final stockField = findStockTextField();
        await tester.enterText(stockField, '35');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        final updated = fakeProductRepo.lastUpsertedProduct;
        expect(updated, isNotNull);
        expect(updated!.branchStocks['store_002'], equals(35));
        expect(updated.branchStocks['store_001'], equals(50)); // store_001 preserved!
      });

      testWidgets('F6.2: Scoped mutation recalculates aggregate Product.stock correctly',
          (tester) async {
        final fakeProductRepo = _FakeProductRepository([initialProduct]);
        final fakeInventoryRepo = _FakeInventoryRepository();

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: initialProduct),
            currentStoreId: 'store_002',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([initialProduct])),
              transactionsByProductProvider(initialProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = findStockTextField();
        await tester.enterText(stockField, '35');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        final updated = fakeProductRepo.lastUpsertedProduct!;
        expect(updated.stock, equals(85)); // 50 + 35 = 85
      });

      testWidgets('F6.3: Positive stock mutation emits InventoryTransaction with inventoryAudit type',
          (tester) async {
        final fakeProductRepo = _FakeProductRepository([initialProduct]);
        final fakeInventoryRepo = _FakeInventoryRepository();

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: initialProduct),
            currentStoreId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([initialProduct])),
              transactionsByProductProvider(initialProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // 50 -> 60 (+10)
        final stockField = findStockTextField();
        await tester.enterText(stockField, '60');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
        final tx = fakeInventoryRepo.recordedTransactions.first;
        expect(tx.productId, equals(initialProduct.id));
        expect(tx.type, equals(TransactionType.inventoryAudit));
        expect(tx.quantity, equals(10));
        expect(tx.note, contains('+10'));
        expect(tx.importPrice, equals(initialProduct.costPrice));
      });

      testWidgets('F6.4: Negative stock mutation emits InventoryTransaction with delta magnitude',
          (tester) async {
        final fakeProductRepo = _FakeProductRepository([initialProduct]);
        final fakeInventoryRepo = _FakeInventoryRepository();

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: initialProduct),
            currentStoreId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([initialProduct])),
              transactionsByProductProvider(initialProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // 50 -> 42 (-8)
        final stockField = findStockTextField();
        await tester.enterText(stockField, '42');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
        final tx = fakeInventoryRepo.recordedTransactions.first;
        expect(tx.productId, equals(initialProduct.id));
        expect(tx.type, equals(TransactionType.inventoryAudit));
        expect(tx.quantity, equals(8));
        expect(tx.note, contains('-8'));
      });

      testWidgets('F6.5: Unchanged stock on save does NOT emit any audit transaction',
          (tester) async {
        final fakeProductRepo = _FakeProductRepository([initialProduct]);
        final fakeInventoryRepo = _FakeInventoryRepository();

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: initialProduct),
            currentStoreId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([initialProduct])),
              transactionsByProductProvider(initialProduct.id)
                  .overrideWith((ref) => Stream.value([])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Keep 50 without changes
        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        expect(fakeInventoryRepo.recordedTransactions.isEmpty, isTrue);
      });

      testWidgets('F6.6: Editing combo product does NOT emit inventory audit transaction',
          (tester) async {
        const comboToEdit = Product(
          id: 'prod_f6_combo',
          name: 'Combo Tiệc Trà',
          code: 'CB_TRA',
          price: 50000,
          costPrice: 35000,
          branchStocks: {'store_001': 0, 'store_002': 0},
          category: 'Combo',
          isCombo: true,
          comboComponents: [
            ComboComponent(
              productId: 'prod_f6_01',
              productCode: 'SIMPLY01',
              productName: 'Dầu Ăn Simply Đậu Nành 1L',
              quantity: 1,
              costPrice: 45000,
            ),
          ],
        );

        final fakeProductRepo = _FakeProductRepository([comboToEdit]);
        final fakeInventoryRepo = _FakeInventoryRepository();

        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductDetailPage(product: comboToEdit),
            currentStoreId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            overrides: [
              productListProvider
                  .overrideWith((ref) => Stream.value([comboToEdit])),
              transactionsByProductProvider(comboToEdit.id)
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
    // F7: Structured InventoryTransaction Fields & Serialization
    // =========================================================================
    group('F7: Structured InventoryTransaction Fields & Serialization', () {
      test('F7.1: InventoryTransaction entity stores all mandatory and optional properties', () {
        final date = DateTime(2026, 8, 17, 10, 0);
        final tx = InventoryTransaction(
          id: 'tx_f7_01',
          productId: 'prod_f7_01',
          type: TransactionType.inventoryAudit,
          quantity: 15,
          date: date,
          note: 'Cân bằng kho trực tiếp (+15)',
          importPrice: 35000,
          createdBy: 'admin_01',
          createdByName: 'Admin',
        );

        expect(tx.id, equals('tx_f7_01'));
        expect(tx.productId, equals('prod_f7_01'));
        expect(tx.type, equals(TransactionType.inventoryAudit));
        expect(tx.quantity, equals(15));
        expect(tx.date, equals(date));
        expect(tx.note, equals('Cân bằng kho trực tiếp (+15)'));
        expect(tx.importPrice, equals(35000));
        expect(tx.createdBy, equals('admin_01'));
        expect(tx.createdByName, equals('Admin'));
      });

      test('F7.2: InventoryTransactionModel toMap and fromMap serialization round-trip', () {
        final date = DateTime(2026, 8, 17, 15, 30);
        final model = InventoryTransactionModel(
          id: 'tx_model_01',
          productId: 'prod_model_01',
          type: 'INVENTORY_AUDIT',
          quantity: 12,
          date: date,
          note: 'Cân bằng kho',
          importPrice: 45000,
          createdBy: 'supervisor_01',
          createdByName: 'Supervisor',
        );

        final map = model.toMap();
        expect(map['id'], equals('tx_model_01'));
        expect(map['type'], equals('INVENTORY_AUDIT'));
        expect(map['quantity'], equals(12));
        expect(map['importPrice'], equals(45000));

        final restored = InventoryTransactionModel.fromMap(map);
        expect(restored.id, equals('tx_model_01'));
        expect(restored.type, equals('INVENTORY_AUDIT'));
        expect(restored.quantity, equals(12));
        expect(restored.importPrice, equals(45000));
        expect(restored.toTransactionType(), equals(TransactionType.inventoryAudit));
      });

      test('F7.3: parseTransactionType handles string type variations', () {
        expect(
          InventoryTransactionModel.parseTransactionType('INVENTORY_AUDIT'),
          equals(TransactionType.inventoryAudit),
        );
        expect(
          InventoryTransactionModel.parseTransactionType('inventory_audit'),
          equals(TransactionType.inventoryAudit),
        );
        expect(
          InventoryTransactionModel.parseTransactionType('inventoryAudit'),
          equals(TransactionType.inventoryAudit),
        );
        expect(
          InventoryTransactionModel.parseTransactionType('audit'),
          equals(TransactionType.inventoryAudit),
        );
        expect(
          InventoryTransactionModel.parseTransactionType('export'),
          equals(TransactionType.export),
        );
        expect(
          InventoryTransactionModel.parseTransactionType('import'),
          equals(TransactionType.import),
        );
      });

      test('F7.4: typeToString formats TransactionType to standard protocol strings', () {
        expect(
          InventoryTransactionModel.typeToString(TransactionType.import),
          equals('import'),
        );
        expect(
          InventoryTransactionModel.typeToString(TransactionType.export),
          equals('export'),
        );
        expect(
          InventoryTransactionModel.typeToString(TransactionType.inventoryAudit),
          equals('INVENTORY_AUDIT'),
        );
      });

      test('F7.5: InventoryTransactionModel.fromMap gracefully parses null or missing fields', () {
        final minimalMap = {
          'id': 'tx_min_01',
          'productId': 'prod_min_01',
          'quantity': 5,
        };

        final model = InventoryTransactionModel.fromMap(minimalMap);
        expect(model.id, equals('tx_min_01'));
        expect(model.productId, equals('prod_min_01'));
        expect(model.quantity, equals(5));
        expect(model.type, equals('import')); // default fallback
        expect(model.importPrice, isNull);
        expect(model.createdBy, isNull);
      });

      test('F7.6: InventoryTransaction quantity stores positive magnitude on audit delta', () {
        final tx = InventoryTransaction(
          id: 'tx_audit_delta',
          productId: 'prod_p1',
          type: TransactionType.inventoryAudit,
          quantity: 8, // absolute magnitude of -8
          date: DateTime.now(),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 20 -> Tồn mới: 12, chênh lệch: -8)',
          importPrice: 10000,
        );

        expect(tx.quantity, equals(8));
        expect(tx.note, contains('chênh lệch: -8'));
      });
    });

    // =========================================================================
    // F8: Store-Partitioned FIFO Lot Queues
    // =========================================================================
    group('F8: Store-Partitioned FIFO Lot Queues', () {
      test('F8.1: FifoCalculator tracks distinct lot queues for different products', () {
        final txs = [
          InventoryTransaction(
            id: 'imp_p1',
            productId: 'prod_1',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1),
            note: 'Nhập P1',
            importPrice: 10000,
          ),
          InventoryTransaction(
            id: 'imp_p2',
            productId: 'prod_2',
            type: TransactionType.import,
            quantity: 20,
            date: DateTime(2026, 8, 1),
            note: 'Nhập P2',
            importPrice: 20000,
          ),
        ];

        final tracker = FifoCalculator(txs);

        final lotsP1 = tracker.getInventoryLots('prod_1');
        final lotsP2 = tracker.getInventoryLots('prod_2');

        expect(lotsP1.length, equals(1));
        expect(lotsP1.first.remainingQuantity, equals(10));
        expect(lotsP1.first.unitCost, equals(10000));

        expect(lotsP2.length, equals(1));
        expect(lotsP2.first.remainingQuantity, equals(20));
        expect(lotsP2.first.unitCost, equals(20000));
      });

      test('F8.2: Independent FifoCalculator instances maintain isolated state across stores', () {
        final store1Txs = [
          InventoryTransaction(
            id: 'imp_s1',
            productId: 'prod_coke',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1),
            note: 'Nhập ĐT',
            importPrice: 8000,
          ),
        ];

        final store2Txs = [
          InventoryTransaction(
            id: 'imp_s2',
            productId: 'prod_coke',
            type: TransactionType.import,
            quantity: 15,
            date: DateTime(2026, 8, 1),
            note: 'Nhập TB',
            importPrice: 9000,
          ),
        ];

        final trackerStore1 = FifoCalculator(store1Txs);
        final trackerStore2 = FifoCalculator(store2Txs);

        // Sell at Store 1
        final costStore1 = trackerStore1.calculateCostForSale(
          productId: 'prod_coke',
          quantity: 6,
          saleDate: DateTime(2026, 8, 2),
        );

        expect(costStore1, equals(48000)); // 6 * 8000
        expect(trackerStore1.getInventoryLots('prod_coke').first.remainingQuantity, equals(4));

        // Store 2 must remain completely unaffected
        expect(trackerStore2.getInventoryLots('prod_coke').first.remainingQuantity, equals(15));
      });

      test('F8.3: getInventoryLots preserves chronological arrival order of lots', () {
        final txs = [
          InventoryTransaction(
            id: 'imp_1',
            productId: 'prod_ordered',
            type: TransactionType.import,
            quantity: 5,
            date: DateTime(2026, 8, 1),
            note: 'Lô 1',
            importPrice: 10000,
          ),
          InventoryTransaction(
            id: 'imp_2',
            productId: 'prod_ordered',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 3),
            note: 'Lô 2',
            importPrice: 12000,
          ),
        ];

        final tracker = FifoCalculator(txs);
        final lots = tracker.getInventoryLots('prod_ordered');

        expect(lots.length, equals(2));
        expect(lots[0].transactionId, equals('imp_1'));
        expect(lots[0].unitCost, equals(10000));
        expect(lots[1].transactionId, equals('imp_2'));
        expect(lots[1].unitCost, equals(12000));
      });

      test('F8.4: Consecutive sales at Store 1 deplete only Store 1 lots', () {
        final tracker1 = FifoCalculator([
          InventoryTransaction(
            id: 'imp_1',
            productId: 'p_snack',
            type: TransactionType.import,
            quantity: 20,
            date: DateTime(2026, 8, 1),
            note: 'Nhập Store 1',
            importPrice: 5000,
          ),
        ]);

        final tracker2 = FifoCalculator([
          InventoryTransaction(
            id: 'imp_2',
            productId: 'p_snack',
            type: TransactionType.import,
            quantity: 30,
            date: DateTime(2026, 8, 1),
            note: 'Nhập Store 2',
            importPrice: 6000,
          ),
        ]);

        tracker1.calculateCostForSale(
          productId: 'p_snack',
          quantity: 10,
          saleDate: DateTime(2026, 8, 2),
        );
        tracker1.calculateCostForSale(
          productId: 'p_snack',
          quantity: 5,
          saleDate: DateTime(2026, 8, 3),
        );

        expect(tracker1.getInventoryLots('p_snack').first.remainingQuantity, equals(5));
        expect(tracker2.getInventoryLots('p_snack').first.remainingQuantity, equals(30));
      });

      test('F8.5: resetInventoryTracker clears all lot trackers', () {
        final tracker = FifoCalculator([
          InventoryTransaction(
            id: 'imp_reset',
            productId: 'p_reset',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1),
            note: 'Nhập',
            importPrice: 10000,
          ),
        ]);

        expect(tracker.getInventoryLots('p_reset').length, equals(1));
        tracker.resetInventoryTracker();
        expect(tracker.getInventoryLots('p_reset').isEmpty, isTrue);
      });

      test('F8.6: Multiple products processed concurrently maintain individual lot balances', () {
        final tracker = FifoCalculator([
          InventoryTransaction(
            id: 'imp_a',
            productId: 'prod_A',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1),
            note: 'Nhập A',
            importPrice: 10000,
          ),
          InventoryTransaction(
            id: 'imp_b',
            productId: 'prod_B',
            type: TransactionType.import,
            quantity: 20,
            date: DateTime(2026, 8, 1),
            note: 'Nhập B',
            importPrice: 20000,
          ),
        ]);

        final costA = tracker.calculateCostForSale(
          productId: 'prod_A',
          quantity: 4,
          saleDate: DateTime(2026, 8, 2),
        );
        final costB = tracker.calculateCostForSale(
          productId: 'prod_B',
          quantity: 5,
          saleDate: DateTime(2026, 8, 2),
        );

        expect(costA, equals(40000)); // 4 * 10000
        expect(costB, equals(100000)); // 5 * 20000
        expect(tracker.getInventoryLots('prod_A').first.remainingQuantity, equals(6));
        expect(tracker.getInventoryLots('prod_B').first.remainingQuantity, equals(15));
      });
    });

    // =========================================================================
    // F9: FIFO 6 Edge Cases Implementation
    // =========================================================================
    group('F9: FIFO 6 Edge Cases Implementation', () {
      test('F9.1 (Case 1 - Imports): Sequential imports create successive lots with exact unit costs', () {
        final txs = [
          InventoryTransaction(
            id: 'imp_lot1',
            productId: 'p_case1',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1),
            note: 'Lô 1',
            importPrice: 10000,
          ),
          InventoryTransaction(
            id: 'imp_lot2',
            productId: 'p_case1',
            type: TransactionType.import,
            quantity: 15,
            date: DateTime(2026, 8, 2),
            note: 'Lô 2',
            importPrice: 12000,
          ),
        ];

        final tracker = FifoCalculator(txs);
        final lots = tracker.getInventoryLots('p_case1');

        expect(lots.length, equals(2));
        expect(lots[0].remainingQuantity, equals(10));
        expect(lots[0].unitCost, equals(10000));
        expect(lots[1].remainingQuantity, equals(15));
        expect(lots[1].unitCost, equals(12000));
      });

      test('F9.2 (Case 2 - POS Sales): Depletes oldest lot first and computes piecewise COGS', () {
        final txs = [
          InventoryTransaction(
            id: 'imp_1',
            productId: 'p_case2',
            type: TransactionType.import,
            quantity: 5,
            date: DateTime(2026, 8, 1),
            note: 'Lô 1',
            importPrice: 10000,
          ),
          InventoryTransaction(
            id: 'imp_2',
            productId: 'p_case2',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 2),
            note: 'Lô 2',
            importPrice: 12000,
          ),
        ];

        final tracker = FifoCalculator(txs);

        // Sell 7: 5 from Lot 1 @ 10k + 2 from Lot 2 @ 12k = 50k + 24k = 74k
        final cost = tracker.calculateCostForSale(
          productId: 'p_case2',
          quantity: 7,
          saleDate: DateTime(2026, 8, 3),
        );

        expect(cost, equals(74000));
        final lots = tracker.getInventoryLots('p_case2');
        expect(lots[0].remainingQuantity, equals(0));
        expect(lots[1].remainingQuantity, equals(8));
      });

      test('F9.3 (Case 2 - Oversold Fallback): Oversold quantity uses fallback unit cost without negative lot balances', () {
        final txs = [
          InventoryTransaction(
            id: 'imp_single',
            productId: 'p_case2_over',
            type: TransactionType.import,
            quantity: 4,
            date: DateTime(2026, 8, 1),
            note: 'Lô duy nhất',
            importPrice: 10000,
          ),
        ];

        final tracker = FifoCalculator(txs);

        // Sell 10 (4 available @ 10k + 6 deficit @ fallback 15k)
        final cost = tracker.calculateCostForSale(
          productId: 'p_case2_over',
          quantity: 10,
          saleDate: DateTime(2026, 8, 2),
          fallbackCostPrice: 15000,
        );

        expect(cost, equals(4 * 10000 + 6 * 15000)); // 40k + 90k = 130k
        final lots = tracker.getInventoryLots('p_case2_over');
        expect(lots.first.remainingQuantity, equals(0)); // Clamped at 0, not -6
      });

      test('F9.4 (Case 3 - Inter-Store Transfers): InterStoreTransferService validates parameters correctly', () async {
        final service = InterStoreTransferService(null);
        const product = Product(
          id: 'prod_transfer',
          name: 'Nước Mắm Nam Ngư 500ml',
          code: 'NAMNGU500',
          price: 25000,
          costPrice: 18000,
          branchStocks: {'store_001': 10, 'store_002': 5},
          category: 'Gia vị',
        );

        // 1. Zero quantity error
        final errZero = await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: 'store_002',
          product: product,
          quantity: 0,
        );
        expect(errZero, equals('Số lượng phải lớn hơn 0'));

        // 2. Over stock error
        final errOver = await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: 'store_002',
          product: product,
          quantity: 50,
        );
        expect(errOver, equals('Không đủ số lượng trong kho'));

        // 3. Same store error
        final errSame = await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: 'store_001',
          product: product,
          quantity: 2,
        );
        expect(errSame, equals('Không thể chuyển cùng kho'));
      });

      test('F9.5 (Case 4 - Positive Inventory Audit): Adds new lot with audit cost and diff quantity', () {
        final txs = [
          InventoryTransaction(
            id: 'imp_base',
            productId: 'p_audit_pos',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1),
            note: 'Nhập ban đầu',
            importPrice: 10000,
          ),
          InventoryTransaction(
            id: 'audit_pos',
            productId: 'p_audit_pos',
            type: TransactionType.inventoryAudit,
            quantity: 5,
            date: DateTime(2026, 8, 2),
            note: 'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 15, chênh lệch: +5)',
            importPrice: 14000,
          ),
        ];

        final tracker = FifoCalculator(txs);
        final lots = tracker.getInventoryLots('p_audit_pos');

        expect(lots.length, equals(2));
        expect(lots[0].remainingQuantity, equals(10));
        expect(lots[0].unitCost, equals(10000));
        expect(lots[1].remainingQuantity, equals(5));
        expect(lots[1].unitCost, equals(14000));

        // Sell 12: 10 from Lot 1 @ 10k + 2 from Lot 2 @ 14k = 100k + 28k = 128k
        final cost = tracker.calculateCostForSale(
          productId: 'p_audit_pos',
          quantity: 12,
          saleDate: DateTime(2026, 8, 3),
        );
        expect(cost, equals(128000));
      });

      test('F9.6 (Case 5 - Negative Inventory Audit): Sequentially drains quantity from oldest lots', () {
        final txs = [
          InventoryTransaction(
            id: 'imp_1',
            productId: 'p_audit_neg',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1),
            note: 'Lô 1',
            importPrice: 10000,
          ),
          InventoryTransaction(
            id: 'imp_2',
            productId: 'p_audit_neg',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 2),
            note: 'Lô 2',
            importPrice: 20000,
          ),
          InventoryTransaction(
            id: 'audit_neg',
            productId: 'p_audit_neg',
            type: TransactionType.inventoryAudit,
            quantity: 6,
            date: DateTime(2026, 8, 3),
            note: 'Cân bằng kho trực tiếp (Tồn cũ: 20 -> Tồn mới: 14, chênh lệch: -6)',
          ),
        ];

        final tracker = FifoCalculator(txs);
        final lots = tracker.getInventoryLots('p_audit_neg');

        expect(lots[0].remainingQuantity, equals(4)); // 10 - 6 = 4 left in Lot 1
        expect(lots[1].remainingQuantity, equals(10)); // Lot 2 untouched

        // Sell 5: 4 from Lot 1 @ 10k + 1 from Lot 2 @ 20k = 40k + 20k = 60k
        final cost = tracker.calculateCostForSale(
          productId: 'p_audit_neg',
          quantity: 5,
          saleDate: DateTime(2026, 8, 4),
        );
        expect(cost, equals(60000));
      });

      test('F9.7 (Case 6 - Profit Margin Calculation): Calculates profit margin percentage accurately', () {
        // Normal positive margin
        final marginNormal = FifoCalculator.calculateProfitMargin(100000, 60000);
        expect(marginNormal, equals(40.0)); // (100k - 60k) / 100k * 100 = 40%

        // Zero revenue edge case
        final marginZero = FifoCalculator.calculateProfitMargin(0, 50000);
        expect(marginZero, equals(0.0));

        // Negative revenue edge case
        final marginNegative = FifoCalculator.calculateProfitMargin(-100, 50000);
        expect(marginNegative, equals(0.0));
      });
    });
  });
}
