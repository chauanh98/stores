import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/domain/entities/combo_component.dart';
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
  const staffUser = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên A',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Quản trị viên B',
    role: 'admin',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor_01',
    displayName: 'Chủ chuỗi C',
    role: 'supervisor',
    storeId: 'store_001',
  );

  final sampleProducts = [
    // 1. In-stock product
    const Product(
      id: 'p1',
      name: 'Bia Saigon Special 330ml',
      code: 'BSG01',
      barcode: '893111111001',
      brand: 'Sabeco',
      price: 15000,
      costPrice: 11000,
      branchStocks: {'branch_1': 60, 'branch_2': 40}, // Total: 100
      category: 'Đồ uống',
      minStock: 20,
    ),
    // 2. Low-stock product (stock <= minStock)
    const Product(
      id: 'p2',
      name: 'Cáp sạc Anker Type-C',
      code: 'ANK01',
      barcode: '893222222001',
      brand: 'Anker',
      price: 180000,
      costPrice: 100000,
      branchStocks: {'branch_1': 3, 'branch_2': 1}, // Total: 4 <= minStock (5)
      category: 'Phụ kiện',
      minStock: 5,
    ),
    // 3. Out-of-stock product (stock = 0)
    const Product(
      id: 'p3',
      name: 'Bánh que Pocky Socola',
      code: 'PK01',
      barcode: '893333333001',
      brand: 'Glico',
      price: 12000,
      costPrice: 8000,
      branchStocks: {'branch_1': 0, 'branch_2': 0}, // Total: 0
      category: 'Bánh kẹo',
      minStock: 10,
    ),
    // 4. Combo product
    const Product(
      id: 'p4',
      name: 'Combo Giải Khát',
      code: 'CB01',
      price: 85000,
      costPrice: 60000,
      branchStocks: {'branch_1': 10, 'branch_2': 5},
      category: 'Combo',
      isCombo: true,
      comboComponents: [
        ComboComponent(
          productId: 'p1',
          productCode: 'BSG01',
          productName: 'Bia Saigon Special 330ml',
          quantity: 4,
          costPrice: 11000,
        ),
      ],
    ),
  ];

  group('ProductsPage UI & Filtering Tests (M3 - R1 & R2)', () {
    testWidgets('Renders compact filter bar dropdowns and initial product catalog',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Check compact filter bar dropdowns
      expect(find.byType(DropdownButton<StockStatus>), findsOneWidget);
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Tất cả nhóm hàng'), findsOneWidget);
      expect(find.text('Tất cả thương hiệu'), findsOneWidget);
      expect(find.text('Tồn kho: Cao → Thấp'), findsOneWidget);

      // Check all 4 products rendered
      expect(find.byType(ProductTile), findsNWidgets(4));
      expect(find.text('Bia Saigon Special 330ml'), findsOneWidget);
      expect(find.text('Cáp sạc Anker Type-C'), findsOneWidget);
      expect(find.text('Bánh que Pocky Socola'), findsOneWidget);
      expect(find.text('Combo Giải Khát'), findsOneWidget);
    });

    testWidgets('Filters products by stock status dropdown', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // 1. Select "Hết hàng (= 0)"
      await tester.tap(find.byType(DropdownButton<StockStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hết hàng (= 0)').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Bánh que Pocky Socola'), findsOneWidget);
      expect(find.text('Bia Saigon Special 330ml'), findsNothing);

      // 2. Select "Dưới định mức"
      await tester.tap(find.byType(DropdownButton<StockStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dưới định mức').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Cáp sạc Anker Type-C'), findsOneWidget);
      expect(find.text('Bánh que Pocky Socola'), findsNothing);

      // 3. Select "Còn hàng (> 0)"
      await tester.tap(find.byType(DropdownButton<StockStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Còn hàng (> 0)').last);
      await tester.pumpAndSettle();

      // In stock: Bia Saigon (stock 100), Cáp sạc (stock 4), Combo (stock 15)
      expect(find.byType(ProductTile), findsNWidgets(3));
      expect(find.text('Bánh que Pocky Socola'), findsNothing);

      // 4. Select "Tất cả"
      await tester.tap(find.byType(DropdownButton<StockStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tất cả').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsNWidgets(4));
    });

    testWidgets('Instant reactive search filters products by Name, SKU, Brand',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Search by Name
      await tester.enterText(find.byType(TextField), 'Anker');
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Cáp sạc Anker Type-C'), findsOneWidget);
      expect(find.text('Bia Saigon Special 330ml'), findsNothing);

      // Search by SKU code
      await tester.enterText(find.byType(TextField), 'BSG01');
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Bia Saigon Special 330ml'), findsOneWidget);

      // Clear search query with clear button
      final clearButton = find.byIcon(Icons.clear);
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsNWidgets(4));
    });

    testWidgets('Shows not found empty state when search query matches nothing',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'NonExistentProductXYZ');
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsNothing);
      expect(find.text('Không tìm thấy'), findsOneWidget);
    });

    testWidgets('Category dropdown filters products', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap category dropdown
      final catFinder = find.byType(DropdownButton<String>);
      await tester.ensureVisible(catFinder);
      await tester.pumpAndSettle();
      await tester.tap(catFinder);
      await tester.pumpAndSettle();

      // Select 'Đồ uống'
      await tester.tap(find.text('Đồ uống').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Bia Saigon Special 330ml'), findsOneWidget);
    });

    testWidgets('Brand dropdown filters products', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap brand dropdown
      final brandFinder = find.byType(DropdownButton<String?>);
      await tester.ensureVisible(brandFinder);
      await tester.pumpAndSettle();
      await tester.tap(brandFinder);
      await tester.pumpAndSettle();

      // Select 'Glico'
      await tester.tap(find.text('Glico').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Bánh que Pocky Socola'), findsOneWidget);
    });

    testWidgets('Sorting dropdown sorts products by price descending',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap sort dropdown
      final sortFinder = find.byType(DropdownButton<ProductSortOption>);
      await tester.ensureVisible(sortFinder);
      await tester.pumpAndSettle();
      await tester.tap(sortFinder);
      await tester.pumpAndSettle();

      // Select 'Giá: Cao → Thấp'
      await tester.tap(find.text('Giá: Cao → Thấp').last);
      await tester.pumpAndSettle();

      final tiles =
          tester.widgetList<ProductTile>(find.byType(ProductTile)).toList();
      expect(tiles.first.product.name, 'Cáp sạc Anker Type-C'); // 180,000 đ
      expect(tiles.last.product.name, 'Bánh que Pocky Socola'); // 12,000 đ
    });

    testWidgets(
        'Compact filter bar renders without RenderFlex overflow on narrow viewport (320px)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Verify no RenderFlex overflow exception on narrow screen
      expect(tester.takeException(), isNull);

      // Verify filter bar has horizontal SingleChildScrollView
      final horizontalScroll = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      expect(horizontalScroll, findsOneWidget);

      // Scroll horizontally without issues
      await tester.drag(horizontalScroll, const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Applies active visual highlight style when filter is selected',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final stockDropdownFinder = find.byType(DropdownButton<StockStatus>);
      expect(stockDropdownFinder, findsOneWidget);

      // Initially default state (border is AppColors.border)
      final initialStockContainer = find.ancestor(
        of: stockDropdownFinder,
        matching: find.byType(Container),
      );
      final initialDecoration = tester
          .widget<Container>(initialStockContainer.first)
          .decoration as BoxDecoration;
      expect((initialDecoration.border as Border).top.color, AppColors.border);

      // Select 'Còn hàng (> 0)'
      await tester.tap(stockDropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Còn hàng (> 0)').last);
      await tester.pumpAndSettle();

      // Active state (border is AppColors.primary and background has primary tint)
      final activeStockContainer = find.ancestor(
        of: stockDropdownFinder,
        matching: find.byType(Container),
      );
      final activeDecoration = tester
          .widget<Container>(activeStockContainer.first)
          .decoration as BoxDecoration;
      expect((activeDecoration.border as Border).top.color, AppColors.primary);
      expect(activeDecoration.color, AppColors.primary.withOpacity(0.08));
    });

    testWidgets(
        'Conditional Reset Filters button resets all filters when active',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Initially all filters are default => Reset button is hidden
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byType(ProductTile), findsNWidgets(4));

      // 1. Activate Stock Filter ('Hết hàng (= 0)')
      await tester.tap(find.byType(DropdownButton<StockStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hết hàng (= 0)').last);
      await tester.pumpAndSettle();

      // Reset button appears
      final resetBtnFinder = find.byIcon(Icons.refresh);
      expect(resetBtnFinder, findsOneWidget);
      expect(find.byType(ProductTile), findsOneWidget); // Only Pocky

      // 2. Scroll reset button into view if needed and tap
      await tester.ensureVisible(resetBtnFinder);
      await tester.pumpAndSettle();
      await tester.tap(resetBtnFinder);
      await tester.pumpAndSettle();

      // All filters reset to default
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Tất cả nhóm hàng'), findsOneWidget);
      expect(find.text('Tất cả thương hiệu'), findsOneWidget);
      expect(find.text('Tồn kho: Cao → Thấp'), findsOneWidget);

      // All products rendered again and reset button is hidden
      expect(find.byType(ProductTile), findsNWidgets(4));
      expect(find.byIcon(Icons.refresh), findsNothing);
    });
  });

  group('Role-Guarded Stock Summary Card & Permissions (M3 - R2)', () {
    testWidgets(
        'Supervisor sees total valuation amount in summary card and has FAB',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Summary product count & physical stock
      expect(find.textContaining('4 mặt hàng'), findsOneWidget);
      expect(find.textContaining('119'),
          findsOneWidget); // 100 + 4 + 0 + 15 = 119

      // Supervisor sees real cost valuation: (100 * 11,000) + (4 * 100,000) + (0 * 8,000) = 1,500,000 đ
      expect(find.textContaining('Giá trị kho:'), findsOneWidget);
      expect(find.textContaining('1.500.000 đ'), findsOneWidget);
      expect(find.text('***'), findsNothing);

      // FAB is visible for Supervisor
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('Admin has masked valuation (***) in summary card and has FAB',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Admin sees product count & physical stock
      expect(find.textContaining('4 mặt hàng'), findsOneWidget);
      expect(find.textContaining('119'), findsOneWidget);

      // Valuation amount is strictly MASKED for Admin (canViewCostPrice is false)
      expect(find.textContaining('Giá trị kho:'), findsOneWidget);
      expect(find.text('***'), findsOneWidget);
      expect(find.textContaining('1.500.000 đ'), findsNothing);

      // FAB is visible for Admin (canManageProducts is true)
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('Staff has masked valuation (***) in summary card and NO FAB',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Staff sees product count & physical stock
      expect(find.textContaining('4 mặt hàng'), findsOneWidget);
      expect(find.textContaining('119'), findsOneWidget);

      // Valuation is strictly MASKED for Staff
      expect(find.textContaining('Giá trị kho:'), findsOneWidget);
      expect(find.text('***'), findsOneWidget);
      expect(find.textContaining('1.500.000 đ'), findsNothing);

      // FAB is HIDDEN for Staff (canManageProducts is false)
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });
}
