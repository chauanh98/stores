import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inter_store_transfer_service.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/utils/combo_helper.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/products/pages/add_product_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

// --- Mocks & Fakes ---

class FakeProductRepository implements ProductRepository {
  final List<Product> products;
  Product? lastUpsertedProduct;
  String? lastDeletedId;

  FakeProductRepository([List<Product>? initial])
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

  @override
  Future<void> delete(String id) async {
    lastDeletedId = id;
    products.removeWhere((p) => p.id == id);
  }

  @override
  Future<void> updateStock(String id, int newStock) async {
    final index = products.indexWhere((p) => p.id == id);
    if (index >= 0) {
      products[index] = products[index].copyWith(
        branchStocks: {'store_001': newStock, 'store_002': 0},
      );
    }
  }
}

class FakeInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  Stream<List<InventoryTransaction>> watchAll() => Stream.value(transactions);

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(transactions.where((t) => t.productId == productId).toList());

  @override
  Future<void> record(InventoryTransaction transaction) async {
    transactions.add(transaction);
  }

  Future<List<InventoryTransaction>> fetchByProduct(String productId) async =>
      transactions.where((t) => t.productId == productId).toList();

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
      DateTime startDate, DateTime endDate) {
    return Stream.value(transactions
        .where((t) =>
            t.date.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
            t.date.isBefore(endDate.add(const Duration(seconds: 1))))
        .toList());
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

Widget _wrapWithApp({
  required Widget child,
  required UserAccount user,
  required String currentStoreId,
  FakeProductRepository? productRepo,
  FakeInventoryRepository? inventoryRepo,
  List<Category>? categories,
  List<Branch>? branches,
  Map<String, String>? availableStores,
}) {
  final pRepo = productRepo ?? FakeProductRepository();
  final iRepo = inventoryRepo ?? FakeInventoryRepository();
  final cats = categories ??
      [
        const Category(id: 'cat_01', name: 'Đồ uống'),
        const Category(id: 'cat_02', name: 'Bánh kẹo'),
      ];
  final brs = branches ??
      const [
        Branch('store_001', 'Chi nhánh Đông Thắng'),
        Branch('store_002', 'Chi nhánh Thới Bình'),
        Branch('store_003', 'Chi nhánh Cần Thơ'),
      ];
  final stores = availableStores ??
      {
        'store_001': 'Chi nhánh Đông Thắng',
        'store_002': 'Chi nhánh Thới Bình',
        'store_003': 'Chi nhánh Cần Thơ',
      };

  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
      currentStoreIdProvider.overrideWithValue(currentStoreId),
      productRepositoryProvider.overrideWithValue(pRepo),
      productListProvider.overrideWith((ref) => Stream.value(pRepo.products)),
      categoryListProvider.overrideWith((ref) => Stream.value(cats)),
      branchesProvider.overrideWithValue(brs),
      availableStoresProvider.overrideWith((ref) => Future.value(stores)),
      inventoryRepositoryProvider.overrideWithValue(iRepo),
      transactionsByProductProvider.overrideWith((ref, id) =>
          Stream.value(iRepo.transactions.where((t) => t.productId == id).toList())),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: child,
    ),
  );
}

void main() {
  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản Lý Hệ Thống',
    role: 'supervisor',
    storeId: 'store_001',
  );

  group('Adversarial Multi-Store Consistency Harness — M1-2', () {
    // =========================================================================
    // 1. AddProductPage: Scoping stock on product creation
    // =========================================================================
    testWidgets('AddProductPage creates product scoped to active store_001',
        (tester) async {
      final repo = FakeProductRepository();

      await tester.pumpWidget(_wrapWithApp(
        child: const AddProductPage(),
        user: adminUser,
        currentStoreId: 'store_001',
        productRepo: repo,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Trà Sữa Oolong');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chọn nhóm hàng *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đồ uống').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Giá bán'), '35000');
      await tester.enterText(find.widgetWithText(TextFormField, 'Tồn kho'), '45');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      expect(repo.lastUpsertedProduct, isNotNull);
      final created = repo.lastUpsertedProduct!;
      expect(created.name, equals('Trà Sữa Oolong'));
      expect(created.branchStocks['store_001'], equals(45));
      expect(created.branchStocks['store_002'], equals(0));
      expect(created.stockInBranch('store_001'), equals(45));
      expect(created.stockInBranch('store_002'), equals(0));
      expect(created.stock, equals(45));
    });

    testWidgets('AddProductPage creates product scoped to active store_002',
        (tester) async {
      final repo = FakeProductRepository();

      await tester.pumpWidget(_wrapWithApp(
        child: const AddProductPage(),
        user: adminUser,
        currentStoreId: 'store_002',
        productRepo: repo,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Bánh Pía Sóc Trăng');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chọn nhóm hàng *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bánh kẹo').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Giá bán'), '60000');
      await tester.enterText(find.widgetWithText(TextFormField, 'Tồn kho'), '80');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      expect(repo.lastUpsertedProduct, isNotNull);
      final created = repo.lastUpsertedProduct!;
      expect(created.name, equals('Bánh Pía Sóc Trăng'));
      expect(created.branchStocks['store_002'], equals(80));
      expect(created.branchStocks['store_001'], equals(0));
      expect(created.stockInBranch('store_002'), equals(80));
      expect(created.stockInBranch('store_001'), equals(0));
      expect(created.stock, equals(80));
    });

    testWidgets('AddProductPage creates product scoped to custom store_003',
        (tester) async {
      final repo = FakeProductRepository();

      await tester.pumpWidget(_wrapWithApp(
        child: const AddProductPage(),
        user: adminUser,
        currentStoreId: 'store_003',
        productRepo: repo,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Nước Tăng Lực RedBull');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chọn nhóm hàng *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đồ uống').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Giá bán'), '15000');
      await tester.enterText(find.widgetWithText(TextFormField, 'Tồn kho'), '100');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      expect(repo.lastUpsertedProduct, isNotNull);
      final created = repo.lastUpsertedProduct!;
      expect(created.branchStocks['store_003'], equals(100));
      expect(created.stockInBranch('store_003'), equals(100));
    });

    // =========================================================================
    // 2. AddProductPage: Multi-store stock preservation when editing
    // =========================================================================
    testWidgets('AddProductPage preserves other branches when editing in store_001',
        (tester) async {
      const initialProduct = Product(
        id: 'p_multi_edit',
        name: 'Sữa Tươi TH True Milk',
        code: 'TH01',
        price: 36000,
        costPrice: 28000,
        branchStocks: {
          'store_001': 10,
          'store_002': 25,
          'store_003': 15,
        },
        category: 'Đồ uống',
      );

      final repo = FakeProductRepository([initialProduct]);

      await tester.pumpWidget(_wrapWithApp(
        child: const AddProductPage(product: initialProduct),
        user: adminUser,
        currentStoreId: 'store_001',
        productRepo: repo,
      ));
      await tester.pumpAndSettle();

      // Modify price and stock for store_001
      await tester.enterText(find.widgetWithText(TextFormField, 'Giá bán'), '38000');
      await tester.enterText(find.widgetWithText(TextFormField, 'Tồn kho'), '30');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      final updated = repo.lastUpsertedProduct!;
      expect(updated.price, equals(38000));
      expect(updated.branchStocks['store_001'], equals(30));
      expect(updated.branchStocks['store_002'], equals(25));
      expect(updated.branchStocks['store_003'], equals(15));
      expect(updated.stock, equals(70)); // 30 + 25 + 15
    });

    // =========================================================================
    // 3. ProductDetailPage: Branch Stock Table rendering & dynamic resolution
    // =========================================================================
    testWidgets('ProductDetailPage renders dynamic multi-branch stock table accurately',
        (tester) async {
      const product = Product(
        id: 'p_detail_stock',
        name: 'Bia Heineken Sleek',
        code: 'KEN01',
        price: 22000,
        costPrice: 17000,
        branchStocks: {
          'store_001': 50,
          'store_002': 30,
          'store_003': 10,
        },
        category: 'Đồ uống',
      );

      await tester.pumpWidget(_wrapWithApp(
        child: const ProductDetailPage(product: product),
        user: adminUser,
        currentStoreId: 'store_001',
      ));
      await tester.pumpAndSettle();

      expect(find.text('Phân bổ tồn kho theo chi nhánh'), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.text('Chi nhánh Cần Thơ'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('Tổng: 90'), findsOneWidget);
      expect(find.text('Tổng tồn toàn chuỗi'), findsOneWidget);
      expect(find.text('90'), findsWidgets);
    });

    testWidgets('ProductDetailPage preserves other branch stocks when saving in store_002',
        (tester) async {
      const initialProduct = Product(
        id: 'p_detail_edit',
        name: 'Bánh Quy Oreo',
        code: 'OREO01',
        price: 18000,
        costPrice: 12000,
        branchStocks: {
          'store_001': 40,
          'store_002': 20,
          'store_003': 5,
        },
        category: 'Bánh kẹo',
      );

      final repo = FakeProductRepository([initialProduct]);

      await tester.pumpWidget(_wrapWithApp(
        child: const ProductDetailPage(product: initialProduct),
        user: adminUser,
        currentStoreId: 'store_002',
        productRepo: repo,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              ((w.decoration?.labelText?.contains('tồn kho') == true) ||
                  (w.decoration?.prefixIcon is Icon &&
                      (w.decoration!.prefixIcon as Icon).icon ==
                          Icons.inventory_2))),
          '55');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      final updated = repo.lastUpsertedProduct!;
      expect(updated.branchStocks['store_002'], equals(55));
      expect(updated.branchStocks['store_001'], equals(40));
      expect(updated.branchStocks['store_003'], equals(5));
      expect(updated.stock, equals(100)); // 40 + 55 + 5
    });

    // =========================================================================
    // 4. ImportInventoryPage: Dynamic Store Scoping & Stock Isolation
    // =========================================================================
    testWidgets('ImportInventoryPage increments stock only in active store_001',
        (tester) async {
      const product = Product(
        id: 'p_import_1',
        name: 'Nước Khoáng Lavie 500ml',
        code: 'LAVIE01',
        price: 6000,
        costPrice: 3500,
        branchStocks: {
          'store_001': 20,
          'store_002': 50,
        },
        category: 'Đồ uống',
      );

      final repo = FakeProductRepository([product]);
      final invRepo = FakeInventoryRepository();

      await tester.pumpWidget(_wrapWithApp(
        child: const ImportInventoryPage(),
        user: adminUser,
        currentStoreId: 'store_001',
        productRepo: repo,
        inventoryRepo: invRepo,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm'), 'Lavie');
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Nước Khoáng Lavie 500ml').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Số lượng'), '15');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      final updated = repo.lastUpsertedProduct!;
      expect(updated.branchStocks['store_001'], equals(35));
      expect(updated.branchStocks['store_002'], equals(50));
      expect(updated.stock, equals(85));
      expect(invRepo.transactions.length, equals(1));
      expect(invRepo.transactions.first.quantity, equals(15));
    });

    testWidgets('ImportInventoryPage increments stock in active store_002 without touching store_001',
        (tester) async {
      const product = Product(
        id: 'p_import_2',
        name: 'Nước Ngọt Pepsi 330ml',
        code: 'PEP01',
        price: 10000,
        costPrice: 6500,
        branchStocks: {
          'store_001': 100,
          'store_002': 40,
        },
        category: 'Đồ uống',
      );

      final repo = FakeProductRepository([product]);
      final invRepo = FakeInventoryRepository();

      await tester.pumpWidget(_wrapWithApp(
        child: const ImportInventoryPage(),
        user: adminUser,
        currentStoreId: 'store_002',
        productRepo: repo,
        inventoryRepo: invRepo,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm'), 'Pepsi');
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Nước Ngọt Pepsi 330ml').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Số lượng'), '25');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      final updated = repo.lastUpsertedProduct!;
      expect(updated.branchStocks['store_001'], equals(100));
      expect(updated.branchStocks['store_002'], equals(65));
      expect(updated.stock, equals(165));
    });

    testWidgets('ImportInventoryPage dynamically handles legacy branch_1 key when importing in store_001',
        (tester) async {
      const legacyProduct = Product(
        id: 'p_legacy_import',
        name: 'Kẹo Dẻo Chupa Chups',
        code: 'CC01',
        price: 8000,
        costPrice: 5000,
        branchStocks: {
          'branch_1': 30,
          'branch_2': 20,
        },
        category: 'Bánh kẹo',
      );

      final repo = FakeProductRepository([legacyProduct]);
      final invRepo = FakeInventoryRepository();

      await tester.pumpWidget(_wrapWithApp(
        child: const ImportInventoryPage(),
        user: adminUser,
        currentStoreId: 'store_001',
        productRepo: repo,
        inventoryRepo: invRepo,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm'), 'Chupa');
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Kẹo Dẻo Chupa Chups').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Số lượng'), '10');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      final updated = repo.lastUpsertedProduct!;
      expect(updated.branchStocks['branch_1'], equals(40));
      expect(updated.branchStocks['branch_2'], equals(20));
      expect(updated.stockInBranch('store_001'), equals(40));
      expect(updated.stockInBranch('store_002'), equals(20));
    });

    // =========================================================================
    // 5. ProductTile multi-branch badge formatting tests
    // =========================================================================
    testWidgets('ProductTile renders ĐT: X | TB: Y badge properly for canonical keys',
        (tester) async {
      const p = Product(
        id: 'p_tile_1',
        name: 'Bánh Gạo One One',
        code: 'OO01',
        price: 25000,
        costPrice: 18000,
        branchStocks: {'store_001': 14, 'store_002': 8},
        category: 'Bánh kẹo',
      );

      await tester.pumpWidget(_wrapWithApp(
        child: const Scaffold(body: ProductTile(product: p)),
        user: adminUser,
        currentStoreId: 'store_001',
      ));
      await tester.pumpAndSettle();

      expect(find.text('ĐT: 14 | TB: 8'), findsOneWidget);
    });

    testWidgets('ProductTile renders 0 stock on branch without hiding it',
        (tester) async {
      const p = Product(
        id: 'p_tile_zero',
        name: 'Bánh Tráng Nướng',
        code: 'BT01',
        price: 15000,
        costPrice: 10000,
        branchStocks: {'store_001': 0, 'store_002': 12},
        category: 'Bánh kẹo',
      );

      await tester.pumpWidget(_wrapWithApp(
        child: const Scaffold(body: ProductTile(product: p)),
        user: adminUser,
        currentStoreId: 'store_001',
      ));
      await tester.pumpAndSettle();

      expect(find.text('ĐT: 0 | TB: 12'), findsOneWidget);
    });

    testWidgets('ProductTile renders dynamic short codes for 3+ branches',
        (tester) async {
      const p = Product(
        id: 'p_tile_3',
        name: 'Bánh Mì Tươi Kinh Đô',
        code: 'KD01',
        price: 12000,
        costPrice: 8000,
        branchStocks: {
          'store_001': 20,
          'store_002': 15,
          'store_003': 10,
        },
        category: 'Bánh kẹo',
      );

      await tester.pumpWidget(_wrapWithApp(
        child: const Scaffold(body: ProductTile(product: p)),
        user: adminUser,
        currentStoreId: 'store_001',
      ));
      await tester.pumpAndSettle();

      expect(find.text('ĐT: 20 | TB: 15 | CN3: 10'), findsOneWidget);
    });

    // =========================================================================
    // 6. Adversarial stockInBranch stress tests
    // =========================================================================
    test('Product.stockInBranch stress test with varied diacritics and aliases', () {
      const product = Product(
        id: 'p_stress',
        name: 'Test Product',
        code: 'TEST',
        price: 10000,
        costPrice: 7000,
        branchStocks: {
          'store_001': 100,
          'store_002': 200,
          'store_danang': 300,
        },
        category: 'Test',
      );

      // Canonical and aliases for store_001
      expect(product.stockInBranch('store_001'), equals(100));
      expect(product.stockInBranch('STORE_001'), equals(100));
      expect(product.stockInBranch('branch_1'), equals(100));
      expect(product.stockInBranch('BRANCH_1'), equals(100));
      expect(product.stockInBranch('ĐT'), equals(100));
      expect(product.stockInBranch('đt'), equals(100));
      expect(product.stockInBranch('DT'), equals(100));
      expect(product.stockInBranch('dt'), equals(100));
      expect(product.stockInBranch('Chi nhánh Đông Thắng'), equals(100));
      expect(product.stockInBranch('chi nhánh đông thắng'), equals(100));
      expect(product.stockInBranch('Dong Thang'), equals(100));

      // Canonical and aliases for store_002
      expect(product.stockInBranch('store_002'), equals(200));
      expect(product.stockInBranch('STORE_002'), equals(200));
      expect(product.stockInBranch('branch_2'), equals(200));
      expect(product.stockInBranch('BRANCH_2'), equals(200));
      expect(product.stockInBranch('TB'), equals(200));
      expect(product.stockInBranch('tb'), equals(200));
      expect(product.stockInBranch('Chi nhánh Thới Bình'), equals(200));
      expect(product.stockInBranch('Chi nhánh Thời Bình'), equals(200));
      expect(product.stockInBranch('Thoi Binh'), equals(200));

      // Custom branch
      expect(product.stockInBranch('store_danang'), equals(300));
      expect(product.stockInBranch('STORE_DANANG'), equals(300));
      expect(product.stockInBranch(' store_danang '), equals(300));

      // Invalid / edge cases
      expect(product.stockInBranch(''), equals(0));
      expect(product.stockInBranch('   '), equals(0));
      expect(product.stockInBranch('unknown_branch'), equals(0));
    });

    // =========================================================================
    // 7. ProductModel Serialization with Varied Numeric Types
    // =========================================================================
    test('ProductModel parses string and double numbers in branchStocks safely', () {
      final jsonMap = {
        'id': 'p_safe_model',
        'name': 'Test Safe Model',
        'code': 'TSM',
        'price': 50000,
        'costPrice': 30000,
        'branchStocks': {
          'store_001': '55', // String numeric
          'store_002': 40.0, // Double
          'store_003': 25, // Int
        },
        'category': 'Test',
      };

      final model = ProductModel.fromMap(jsonMap);
      expect(model.branchStocks['store_001'], equals(55));
      expect(model.branchStocks['store_002'], equals(40));
      expect(model.branchStocks['store_003'], equals(25));
    });

    // =========================================================================
    // 8. ComboHelper multi-branch availability calculation
    // =========================================================================
    test('ComboHelper accurately computes multi-branch combo availability limits', () {
      const c1 = Product(
        id: 'c1',
        name: 'Component 1',
        code: 'C1',
        price: 10000,
        costPrice: 7000,
        branchStocks: {'store_001': 10, 'store_002': 5},
        category: 'Part',
      );
      const c2 = Product(
        id: 'c2',
        name: 'Component 2',
        code: 'C2',
        price: 15000,
        costPrice: 10000,
        branchStocks: {'store_001': 20, 'store_002': 4},
        category: 'Part',
      );
      const c3 = Product(
        id: 'c3',
        name: 'Component 3',
        code: 'C3',
        price: 5000,
        costPrice: 3000,
        branchStocks: {'store_001': 15, 'store_002': 8},
        category: 'Part',
      );

      const combo = Product(
        id: 'combo_all',
        name: 'Super Combo',
        code: 'SC01',
        price: 50000,
        costPrice: 35000,
        branchStocks: {'store_001': 0, 'store_002': 0},
        category: 'Combo',
        isCombo: true,
        comboComponents: [
          ComboComponent(productId: 'c1', productCode: 'C1', productName: 'C1', quantity: 2, costPrice: 7000),
          ComboComponent(productId: 'c2', productCode: 'C2', productName: 'C2', quantity: 1, costPrice: 10000),
          ComboComponent(productId: 'c3', productCode: 'C3', productName: 'C3', quantity: 3, costPrice: 3000),
        ],
      );

      final allProducts = [c1, c2, c3, combo];

      // At store_001:
      // c1: 10 / 2 = 5
      // c2: 20 / 1 = 20
      // c3: 15 / 3 = 5
      // Limit = min(5, 20, 5) = 5
      expect(ComboHelper.getAvailableStock(product: combo, branchId: 'store_001', allProducts: allProducts), equals(5));

      // At store_002:
      // c1: 5 / 2 = 2
      // c2: 4 / 1 = 4
      // c3: 8 / 3 = 2
      // Limit = min(2, 4, 2) = 2
      expect(ComboHelper.getAvailableStock(product: combo, branchId: 'store_002', allProducts: allProducts), equals(2));

      // Total network combo stock = 5 + 2 = 7
      expect(ComboHelper.getTotalAvailableStock(product: combo, allProducts: allProducts, branchIds: ['store_001', 'store_002']), equals(7));
    });

    // =========================================================================
    // 9. InterStoreTransfer validation stress tests
    // =========================================================================
    test('InterStoreTransferService rejects invalid transfer requests gracefully', () async {
      final transferService = InterStoreTransferService(null);
      const product = Product(
        id: 'p_tx_stress',
        name: 'Transfer Test Product',
        code: 'TTP',
        price: 20000,
        costPrice: 15000,
        branchStocks: {'store_001': 10, 'store_002': 5},
        category: 'Test',
      );

      // Same store
      final resSameStore = await transferService.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_001',
        product: product,
        quantity: 5,
      );
      expect(resSameStore, equals('Không thể chuyển cùng kho'));

      // Zero quantity
      final resZero = await transferService.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: product,
        quantity: 0,
      );
      expect(resZero, equals('Số lượng phải lớn hơn 0'));

      // Insufficient stock (product total stock is 15, requesting 20)
      final resInsufficient = await transferService.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: product,
        quantity: 20,
      );
      expect(resInsufficient, equals('Không đủ số lượng trong kho'));

      // Empty store ID
      final resEmptyStore = await transferService.transferProduct(
        sourceStoreId: '',
        targetStoreId: 'store_002',
        product: product,
        quantity: 5,
      );
      expect(resEmptyStore, equals('Chi nhánh không hợp lệ'));
    });
  });
}
