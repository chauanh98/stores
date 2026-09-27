import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/product_unit.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/add_product_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
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

class _FakeProductRepository implements ProductRepository {
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
    final idx = products.indexWhere((p) => p.id == product.id);
    if (idx >= 0) {
      products[idx] = product;
    } else {
      products.add(product);
    }
  }

  @override
  Future<void> delete(String id) async {
    products.removeWhere((p) => p.id == id);
  }

  @override
  Future<void> updateStock(String id, int newStock) async {
    final idx = products.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      products[idx] = products[idx].copyWith(
        branchStocks: {'branch_1': newStock},
      );
    }
  }
}

final _defaultBranches = [
  const Branch('branch_1', 'Chi nhánh Đông Thắng'),
  const Branch('branch_2', 'Chi nhánh Thời Bình'),
  const Branch('branch_3', 'Chi nhánh Cần Thơ'),
  const Branch('branch_4', 'Chi nhánh Đà Nẵng'),
  const Branch('branch_5', 'Chi nhánh Hà Nội'),
];

Widget _buildAdversarialApp({
  required Widget child,
  required UserAccount user,
  required List<Product> products,
  _FakeAuthNotifier? authNotifier,
  _FakeProductRepository? repo,
  List<Category>? categories,
  List<InventoryTransaction> transactions = const [],
}) {
  final effectiveAuth = authNotifier ?? _FakeAuthNotifier(user);
  final effectiveRepo = repo ?? _FakeProductRepository(products);
  final cats = categories ??
      [
        const Category(id: 'cat_beverage', name: 'Đồ uống'),
        const Category(id: 'cat_snack', name: 'Bánh kẹo'),
        const Category(id: 'cat_home', name: 'Gia dụng'),
        const Category(id: 'cat_fashion', name: 'Thời trang'),
        const Category(id: 'cat_tech', name: 'Công nghệ'),
      ];

  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => effectiveAuth),
      currentStoreIdProvider.overrideWith((ref) => 'store_001'),
      branchesProvider.overrideWithValue(_defaultBranches),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': 'Chi nhánh Đông Thắng',
            'store_002': 'Chi nhánh Thời Bình',
            'store_003': 'Chi nhánh Cần Thơ',
            'store_004': 'Chi nhánh Đà Nẵng',
            'store_005': 'Chi nhánh Hà Nội',
          }),
      productRepositoryProvider.overrideWithValue(effectiveRepo),
      productListProvider.overrideWith((ref) => Stream.value(products)),
      categoryListProvider.overrideWith((ref) => Stream.value(cats)),
      for (final p in products)
        transactionsByProductProvider(p.id)
            .overrideWith((ref) => Stream.value(transactions)),
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
  TestWidgetsFlutterBinding.ensureInitialized();

  const supervisorUser = UserAccount(
    username: 'supervisor_01',
    displayName: 'Quản lý Hệ thống',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Quản trị viên Chi nhánh',
    role: 'admin',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên Bán hàng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  group('Adversarial Test 1: 500+ Items Catalog Pagination, Reactive Search & Filter Stress', () {
    // Generate 550 distinct items
    final largeCatalog = List<Product>.generate(550, (index) {
      final idNum = index.toString().padLeft(4, '0');
      final catIndex = index % 5;
      final categories = [
        'Đồ uống',
        'Bánh kẹo',
        'Gia dụng',
        'Thời trang',
        'Công nghệ'
      ];
      final brands = ['Sabeco', 'Glico', 'Paseo', 'Anker', 'Vinamilk'];
      final category = categories[catIndex];
      final brand = brands[catIndex];

      // Distribute stock patterns: out of stock (multiples of 10), low stock (multiples of 7), in stock (rest)
      final int stockVal;
      const minLimit = 10;
      if (index % 10 == 0) {
        stockVal = 0; // Out of stock
      } else if (index % 7 == 0) {
        stockVal = 4; // Low stock (<= minStock 10)
      } else {
        stockVal = 50 + (index % 50); // In stock
      }

      final price = 10000.0 + (index * 1000.0);
      final costPrice = 7000.0 + (index * 700.0);

      return Product(
        id: 'prod_$idNum',
        name: 'Sản phẩm thử nghiệm $idNum ($category)',
        code: 'SKU-$idNum',
        barcode: '893${idNum.padLeft(9, '0')}',
        brand: brand,
        price: price,
        costPrice: costPrice,
        branchStocks: {'branch_1': stockVal, 'branch_2': stockVal > 0 ? 5 : 0},
        category: category,
        unit: 'Cái',
        minStock: minLimit,
        maxStock: 500,
      );
    });

    testWidgets('Renders 550+ items catalog, validates pagination and summary calculations',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildAdversarialApp(
          child: const ProductsPage(),
          user: supervisorUser,
          products: largeCatalog,
        ),
      );
      await tester.pumpAndSettle();

      // Verify Summary Card under 550 products
      expect(find.textContaining('550 mặt hàng'), findsOneWidget);

      // Verify ProductTiles are rendered in lazy ListView
      expect(find.byType(ProductTile), findsWidgets);

      // Drag list vertically to scroll down and trigger pagination expansion
      await tester.drag(find.byType(ProductTile).first, const Offset(0, -800));
      await tester.pumpAndSettle();

      // Ensure scrolling is smooth and more tiles are rendered
      expect(find.byType(ProductTile), findsWidgets);
    });

    testWidgets('Rapid reactive search queries across 550+ items',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildAdversarialApp(
          child: const ProductsPage(),
          user: supervisorUser,
          products: largeCatalog,
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);

      // 1. Search for unique SKU
      await tester.enterText(searchField, 'SKU-0499');
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Sản phẩm thử nghiệm 0499 (Công nghệ)'), findsOneWidget);
      expect(find.textContaining('1 mặt hàng'), findsOneWidget);

      // 2. Search for Barcode
      await tester.enterText(searchField, '893000000350');
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Sản phẩm thử nghiệm 0350 (Đồ uống)'), findsOneWidget);

      // 3. Clear search query
      final clearBtn = find.byIcon(Icons.clear);
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('550 mặt hàng'), findsOneWidget);
    });

    testWidgets('Filters 550+ items by stock status and category with accurate aggregation',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildAdversarialApp(
          child: const ProductsPage(),
          user: supervisorUser,
          products: largeCatalog,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Filter: Hết hàng (= 0)
      await tester.tap(find.byType(DropdownButton<StockStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hết hàng (= 0)').last);
      await tester.pumpAndSettle();

      // 550 items with index % 10 == 0 => exactly 55 items out of stock
      expect(find.textContaining('55 mặt hàng'), findsOneWidget);

      // 2. Filter: Dưới định mức
      await tester.tap(find.byType(DropdownButton<StockStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dưới định mức').last);
      await tester.pumpAndSettle();

      // Low stock: index % 7 == 0 (excluding those where stock = 0)
      final lowStockCount = largeCatalog.where((p) => p.isLowStock()).length;
      expect(find.textContaining('$lowStockCount mặt hàng'), findsOneWidget);

      // 3. Filter: Còn hàng (> 0)
      await tester.tap(find.byType(DropdownButton<StockStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Còn hàng (> 0)').last);
      await tester.pumpAndSettle();

      final inStockCount = largeCatalog.where((p) => p.stock > 0).length;
      expect(find.textContaining('$inStockCount mặt hàng'), findsOneWidget);

      // 4. Return to Tất cả
      await tester.tap(find.byType(DropdownButton<StockStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tất cả').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('550 mặt hàng'), findsOneWidget);
    });
  });

  group('Adversarial Test 2: Negative Stock, Zero Stock & Multi-Branch Edge Cases', () {
    final edgeProducts = [
      // 1. Negative stock on all branches (e.g. overselling / data corruption)
      const Product(
        id: 'p_neg_01',
        name: 'Sản phẩm Âm Kho Toàn Phần',
        code: 'NEG-01',
        barcode: '893999111001',
        brand: 'EdgeCorp',
        price: 50000,
        costPrice: 30000,
        branchStocks: {'branch_1': -25, 'branch_2': -15}, // Total: -40
        category: 'Gia dụng',
        minStock: 5,
      ),
      // 2. Zero stock on 5 branches
      const Product(
        id: 'p_zero_02',
        name: 'Sản phẩm Hết Kho Đa Chi Nhánh',
        code: 'ZERO-02',
        barcode: '893999111002',
        brand: 'EdgeCorp',
        price: 75000,
        costPrice: 45000,
        branchStocks: {
          'branch_1': 0,
          'branch_2': 0,
          'branch_3': 0,
          'branch_4': 0,
          'branch_5': 0,
        },
        category: 'Gia dụng',
        minStock: 10,
      ),
      // 3. Multi-branch with 5 branches, phantom keys and mixed negative/positive values
      const Product(
        id: 'p_multi_03',
        name: 'Sản phẩm Đa Chi Nhánh Kèm Phantom Key',
        code: 'MULTI-03',
        barcode: '893999111003',
        brand: 'EdgeCorp',
        price: 120000,
        costPrice: 80000,
        branchStocks: {
          'branch_1': -5,
          'branch_2': 0,
          'branch_3': 20,
          'branch_4': 50,
          'branch_5': 100,
          'phantom_branch_999': -10,
          'unknown_branch_xyz': 5,
        }, // Total = -5 + 0 + 20 + 50 + 100 + -10 + 5 = 160
        category: 'Gia dụng',
        minStock: 15,
      ),
    ];

    test('Domain helper getters handle negative and zero stocks correctly', () {
      final negProduct = edgeProducts[0];
      final zeroProduct = edgeProducts[1];
      final multiProduct = edgeProducts[2];

      // Stock sums
      expect(negProduct.stock, equals(-40));
      expect(zeroProduct.stock, equals(0));
      expect(multiProduct.stock, equals(160));

      // isOutOfStock should be true for <= 0
      expect(negProduct.isOutOfStock, isTrue);
      expect(zeroProduct.isOutOfStock, isTrue);
      expect(multiProduct.isOutOfStock, isFalse);

      // isLowStock should be false for <= 0 (it is out of stock, not low stock)
      expect(negProduct.isLowStock(), isFalse);
      expect(zeroProduct.isLowStock(), isFalse);
      expect(multiProduct.isLowStock(), isFalse); // 160 > minStock (15)
    });

    testWidgets('ProductsPage renders negative and zero stock products safely with warning chips',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildAdversarialApp(
          child: const ProductsPage(),
          user: supervisorUser,
          products: edgeProducts,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsNWidgets(3));
      expect(find.text('Sản phẩm Âm Kho Toàn Phần'), findsOneWidget);
      expect(find.text('Sản phẩm Hết Kho Đa Chi Nhánh'), findsOneWidget);
      expect(find.text('Sản phẩm Đa Chi Nhánh Kèm Phantom Key'), findsOneWidget);

      // Filter: Hết hàng (= 0) includes negative and zero stocks
      await tester.tap(find.byType(DropdownButton<StockStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hết hàng (= 0)').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsNWidgets(2));
      expect(find.text('Sản phẩm Âm Kho Toàn Phần'), findsOneWidget);
      expect(find.text('Sản phẩm Hết Kho Đa Chi Nhánh'), findsOneWidget);
      expect(find.text('Sản phẩm Đa Chi Nhánh Kèm Phantom Key'), findsNothing);
    });

    testWidgets('ProductDetailPage renders 5 branches and phantom keys without crashing',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final multiProduct = edgeProducts[2];

      await tester.pumpWidget(
        _buildAdversarialApp(
          child: ProductDetailPage(product: multiProduct),
          user: supervisorUser,
          products: edgeProducts,
        ),
      );
      await tester.pumpAndSettle();

      // Branch allocation table
      expect(find.text('Phân bổ tồn kho theo chi nhánh'), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.text('-5'), findsOneWidget);
      expect(find.text('Chi nhánh Thời Bình'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('Chi nhánh Cần Thơ'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(find.text('Chi nhánh Đà Nẵng'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('Chi nhánh Hà Nội'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);

      // Total row sums all branch stocks including phantom keys (-5 + 0 + 20 + 50 + 100 - 10 + 5 = 160)
      expect(find.text('Tổng tồn toàn chuỗi'), findsOneWidget);
      expect(find.text('160'), findsWidgets);
    });
  });

  group('Adversarial Test 3: Vietnamese Diacritics Search & SKU / Barcode Collisions', () {
    final vietnameseCatalog = [
      const Product(
        id: 'vi_01',
        name: 'Đầm dạ hội cao cấp sang trọng',
        code: 'DAM-DAHOI-01',
        barcode: '893555001',
        brand: 'Thiết Kế Đẹp',
        price: 850000,
        costPrice: 500000,
        branchStocks: {'branch_1': 10},
        category: 'Thời trang nữ',
      ),
      const Product(
        id: 'vi_02',
        name: 'Sữa tươi tiệt trùng Vinamilk ít đường 1L',
        code: 'SUA-TUOI-01',
        barcode: '893555002',
        brand: 'Vinamilk',
        price: 38000,
        costPrice: 29000,
        branchStocks: {'branch_1': 45},
        category: 'Sữa & Thực phẩm',
      ),
      const Product(
        id: 'vi_03',
        name: 'Bánh tráng trộn Sa Tế tôm cay nồng Tây Ninh',
        code: 'BANH-TRANG-01',
        barcode: '893555003',
        brand: 'Đặc Sản Tây Ninh',
        price: 20000,
        costPrice: 12000,
        branchStocks: {'branch_1': 30},
        category: 'Ăn vặt',
      ),
      // Colliding SKUs and Barcodes
      const Product(
        id: 'col_01',
        name: 'Cà phê Arabica Cầu Đất Hạt Rang Mộc',
        code: 'CF-ARA',
        barcode: '893888001',
        brand: 'Cầu Đất',
        price: 160000,
        costPrice: 110000,
        branchStocks: {'branch_1': 20},
        category: 'Cà phê',
      ),
      const Product(
        id: 'col_02',
        name: 'Cà phê Arabica Cầu Đất Xay Pha Phin',
        code: 'CF-ARA-PHIN',
        barcode: '893888001-PHIN',
        brand: 'Cầu Đất',
        price: 170000,
        costPrice: 115000,
        branchStocks: {'branch_1': 15},
        category: 'Cà phê',
      ),
      const Product(
        id: 'col_03',
        name: 'Cà phê Arabica Cầu Đất Hộp Quà Tết 2026',
        code: 'CF-ARA-GIFT',
        barcode: '89388800100',
        brand: 'Cầu Đất',
        price: 350000,
        costPrice: 240000,
        branchStocks: {'branch_1': 8},
        category: 'Cà phê',
      ),
    ];

    testWidgets('Searches Vietnamese diacritics with mixed tone marks, uppercase Đ, and spaces',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildAdversarialApp(
          child: const ProductsPage(),
          user: supervisorUser,
          products: vietnameseCatalog,
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);

      // 1. Lowercase "đầm dạ hội"
      await tester.enterText(searchField, 'đầm dạ hội');
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Đầm dạ hội cao cấp sang trọng'), findsOneWidget);

      // 2. Uppercase "ĐẦM DẠ HỘI"
      await tester.enterText(searchField, 'ĐẦM DẠ HỘI');
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Đầm dạ hội cao cấp sang trọng'), findsOneWidget);

      // 3. Search "Sữa tươi tiệt trùng"
      await tester.enterText(searchField, '  Sữa tươi tiệt trùng  ');
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Sữa tươi tiệt trùng Vinamilk ít đường 1L'), findsOneWidget);

      // 4. Search "Bánh tráng trộn"
      await tester.enterText(searchField, 'bánh tráng trộn');
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Bánh tráng trộn Sa Tế tôm cay nồng Tây Ninh'), findsOneWidget);
    });

    testWidgets('Handles SKU and Barcode prefix collisions and substring queries',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildAdversarialApp(
          child: const ProductsPage(),
          user: supervisorUser,
          products: vietnameseCatalog,
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);

      // Substring search "CF-ARA" matches all 3 colliding products
      await tester.enterText(searchField, 'CF-ARA');
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsNWidgets(3));

      // Specific search "CF-ARA-PHIN" matches only 1 product
      await tester.enterText(searchField, 'CF-ARA-PHIN');
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Cà phê Arabica Cầu Đất Xay Pha Phin'), findsOneWidget);

      // Specific Barcode search "89388800100"
      await tester.enterText(searchField, '89388800100');
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Cà phê Arabica Cầu Đất Hộp Quà Tết 2026'), findsOneWidget);
    });
  });

  group('Adversarial Test 4: Extreme Unit Conversions, Massive Numbers & Stock Bounds', () {
    final extremeUnits = [
      const ProductUnit(
        id: 'u_loc_6',
        unitName: 'Lốc (6 lon)',
        conversionRate: 6,
        price: 88000,
        costPrice: 60000,
        barcode: '893999000006',
        code: 'BSG-LOC6',
      ),
      const ProductUnit(
        id: 'u_thung_24',
        unitName: 'Thùng (24 lon)',
        conversionRate: 24,
        price: 345000,
        costPrice: 240000,
        barcode: '893999000024',
        code: 'BSG-THUNG24',
      ),
      const ProductUnit(
        id: 'u_pallet_24k',
        unitName: 'Pallet (24000 lon = 1000 Thùng)',
        conversionRate: 24000,
        price: 340000000,
        costPrice: 230000000,
        barcode: '893999024000',
        code: 'BSG-PALLET',
      ),
      const ProductUnit(
        id: 'u_cont_480k',
        unitName: 'Container (480000 lon = 20 Pallet)',
        conversionRate: 480000,
        price: 6800000000,
        costPrice: 4500000000,
        barcode: '893999480000',
        code: 'BSG-CONTAINER',
      ),
    ];

    final extremeProduct = Product(
      id: 'prod_extreme_01',
      name: 'Bia Saigon Xuất Khẩu Đại Lô',
      code: 'BSG-EXPORT',
      barcode: '893999000001',
      brand: 'Sabeco',
      price: 15000,
      costPrice: 10000,
      branchStocks: const {
        'branch_1': 500000000,
        'branch_2': 499999999,
      }, // Total stock: 999,999,999 units
      category: 'Đồ uống',
      unit: 'Lon',
      minStock: 0,
      maxStock: 999999999,
      units: extremeUnits,
    );

    test('Unit conversion rates and stock bound helper behaviors', () {
      expect(extremeProduct.stock, equals(999999999));
      expect(extremeProduct.isOutOfStock, isFalse);
      // With minStock: 0, isLowStock() is false because stock (999999999) is not <= 0
      expect(extremeProduct.isLowStock(), isFalse);

      // Product with null minStock falls back to 5
      const nullMinProduct = Product(
        id: 'p_null_min',
        name: 'Product Null Min',
        code: 'P-NULL',
        price: 10000,
        costPrice: 5000,
        category: 'Test',
        branchStocks: {'branch_1': 4},
        minStock: null,
      );
      expect(nullMinProduct.isLowStock(), isTrue);

      // Product with extreme minStock (999999999)
      final hugeMinProduct = extremeProduct.copyWith(minStock: 999999999, branchStocks: {'branch_1': 500});
      expect(hugeMinProduct.isLowStock(), isTrue);
    });

    testWidgets('ProductDetailPage renders extreme unit conversion table and massive stock safely',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildAdversarialApp(
          child: ProductDetailPage(product: extremeProduct),
          user: supervisorUser,
          products: [extremeProduct],
        ),
      );
      await tester.pumpAndSettle();

      // Check product details
      expect(find.text('Bia Saigon Xuất Khẩu Đại Lô'), findsWidgets);
      expect(find.text('Còn hàng (999999999)'), findsOneWidget);

      // Check all 4 extreme units in table
      expect(find.text('4 đơn vị'), findsOneWidget);
      expect(find.text('Lốc (6 lon)'), findsOneWidget);
      expect(find.text('Thùng (24 lon)'), findsOneWidget);
      expect(find.text('Pallet (24000 lon = 1000 Thùng)'), findsOneWidget);
      expect(find.text('1 Pallet (24000 lon = 1000 Thùng) = 24000 Lon'), findsOneWidget);
      expect(find.text('Container (480000 lon = 20 Pallet)'), findsOneWidget);
      expect(find.text('1 Container (480000 lon = 20 Pallet) = 480000 Lon'), findsOneWidget);

      // Reveal cost prices
      final eyeButton = find.byTooltip('Ẩn / Hiện giá vốn');
      await tester.tap(eyeButton);
      await tester.pumpAndSettle();

      final currency = NumberFormat('#,###', 'vi_VN');
      expect(find.text('Vốn: ${currency.format(230000000)} đ'), findsOneWidget);
      expect(find.text('Vốn: ${currency.format(4500000000)} đ'), findsOneWidget);
    });

    testWidgets('AddProductPage saves extreme stock bounds and multi-unit conversions without precision loss',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = _FakeProductRepository([extremeProduct]);

      await tester.pumpWidget(
        _buildAdversarialApp(
          child: AddProductPage(product: extremeProduct),
          user: supervisorUser,
          products: [extremeProduct],
          repo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Ensure all 4 extreme units are present in the form
      expect(find.text('Pallet (24000 lon = 1000 Thùng)'), findsOneWidget);
      expect(find.text('Container (480000 lon = 20 Pallet)'), findsOneWidget);

      // Save form
      await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
      await tester.pumpAndSettle();

      expect(fakeRepo.lastUpsertedProduct, isNotNull);
      final saved = fakeRepo.lastUpsertedProduct!;
      expect(saved.minStock, equals(0));
      expect(saved.maxStock, equals(999999999));
      expect(saved.units.length, equals(4));
      expect(saved.units[2].conversionRate, equals(24000));
      expect(saved.units[3].conversionRate, equals(480000));
    });
  });

  group('Adversarial Test 5: Live Role Switching During Active Screen Viewing', () {
    final sampleCatalog = [
      const Product(
        id: 'p_role_01',
        name: 'Bia Saigon Special 330ml',
        code: 'BSG01',
        barcode: '893111111001',
        brand: 'Sabeco',
        price: 15000,
        costPrice: 11000,
        branchStocks: {'branch_1': 60, 'branch_2': 40}, // Total: 100
        category: 'Đồ uống',
        unit: 'Lon',
        minStock: 20,
        units: [
          ProductUnit(
            id: 'u1',
            unitName: 'Lốc (6 lon)',
            conversionRate: 6,
            price: 88000,
            costPrice: 65000,
          ),
        ],
      ),
      const Product(
        id: 'p_role_02',
        name: 'Cáp sạc Anker Type-C',
        code: 'ANK01',
        barcode: '893222222001',
        brand: 'Anker',
        price: 180000,
        costPrice: 100000,
        branchStocks: {'branch_1': 3, 'branch_2': 1}, // Total: 4
        category: 'Phụ kiện',
        unit: 'Sợi',
        minStock: 5,
      ),
    ];

    testWidgets(
        'ProductsPage live role transition: Staff -> Supervisor -> Admin updates summary card and FAB without state leakage',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final authNotifier = _FakeAuthNotifier(staffUser);

      await tester.pumpWidget(
        _buildAdversarialApp(
          child: const ProductsPage(),
          user: staffUser,
          authNotifier: authNotifier,
          products: sampleCatalog,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial Staff State:
      // Valuation is MASKED (***)
      expect(find.text('***'), findsOneWidget);
      expect(find.textContaining('1.500.000 đ'), findsNothing);
      // FAB is HIDDEN
      expect(find.byType(FloatingActionButton), findsNothing);

      // 2. LIVE SWITCH -> Supervisor
      authNotifier.state = supervisorUser;
      await tester.pumpAndSettle();

      // Supervisor State:
      // Valuation is REVEALED: (100 * 11,000) + (4 * 100,000) = 1,500,000 đ
      expect(find.textContaining('1.500.000 đ'), findsOneWidget);
      expect(find.text('***'), findsNothing);
      // FAB is VISIBLE
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // 3. LIVE SWITCH -> Admin
      authNotifier.state = adminUser;
      await tester.pumpAndSettle();

      // Admin State:
      // Valuation is VISIBLE for Admin (canViewCostPrice is true for Admin / Store Owner)
      expect(find.textContaining('1.500.000 đ'), findsOneWidget);
      expect(find.text('***'), findsNothing);
      // FAB REMAINS VISIBLE (canManageProducts is true for Admin)
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets(
        'ProductDetailPage live role transition: Staff -> Supervisor -> Admin toggles cost security without widget teardown',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final targetProduct = sampleCatalog[0];
      final authNotifier = _FakeAuthNotifier(staffUser);

      await tester.pumpWidget(
        _buildAdversarialApp(
          child: ProductDetailPage(product: targetProduct),
          user: staffUser,
          authNotifier: authNotifier,
          products: sampleCatalog,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Staff State:
      expect(find.text('Giá vốn'), findsNothing);
      expect(find.text('11.000 đ'), findsNothing);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
      expect(find.textContaining('Vốn:'), findsNothing);

      // Staff taps [Chỉnh sửa] -> blocked
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Bạn không có quyền chỉnh sửa sản phẩm'), findsOneWidget);

      // 2. LIVE SWITCH -> Supervisor
      authNotifier.state = supervisorUser;
      await tester.pumpAndSettle();

      // Supervisor State:
      expect(find.text('Giá vốn'), findsOneWidget);
      expect(find.text('••••••'), findsWidgets); // initially masked
      final eyeBtn = find.byTooltip('Ẩn / Hiện giá vốn');
      expect(eyeBtn, findsOneWidget);

      // Reveal cost price
      await tester.tap(eyeBtn);
      await tester.pumpAndSettle();
      expect(find.text('11.000 đ'), findsWidgets);
      expect(find.text('Vốn: 65.000 đ'), findsOneWidget);

      // 3. LIVE SWITCH -> Admin
      authNotifier.state = adminUser;
      await tester.pumpAndSettle();

      // Admin State:
      // Cost price is VISIBLE for Admin (as store owner)
      expect(find.text('Giá vốn'), findsOneWidget);
      expect(find.text('11.000 đ'), findsWidgets);

      // Admin taps [Chỉnh sửa] -> Allowed (enters edit mode)
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Thông tin cơ bản'), findsOneWidget);
      expect(find.text('Lưu'), findsOneWidget);

      // Cancel edit mode
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // 4. LIVE SWITCH BACK -> Staff (Cost price must be masked and removed)
      authNotifier.state = staffUser;
      await tester.pumpAndSettle();
      expect(find.text('Giá vốn'), findsNothing);
      expect(find.text('11.000 đ'), findsNothing);
    });
  });
}
