import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/common/widgets/product_image_thumbnail.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

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
  const inStockProduct = Product(
    id: 'prod_instock',
    name: 'Bia Saigon Special 330ml',
    code: 'BSG01',
    barcode: '893111111001',
    price: 15000,
    costPrice: 11000,
    branchStocks: {'branch_1': 30, 'branch_2': 20}, // Total: 50
    category: 'Đồ uống',
    minStock: 10,
    maxStock: 200,
  );

  const lowStockProduct = Product(
    id: 'prod_lowstock',
    name: 'Cáp sạc Type-C 60W',
    code: 'ANK01',
    barcode: '893222222001',
    price: 180000,
    costPrice: 100000,
    branchStocks: {'branch_1': 2, 'branch_2': 1}, // Total: 3 <= minStock (5)
    category: 'Phụ kiện',
    minStock: 5,
  );

  const outOfStockProduct = Product(
    id: 'prod_outstock',
    name: 'Bánh que Pocky Socola',
    code: 'PK01',
    barcode: '893333333001',
    price: 12000,
    costPrice: 8000,
    branchStocks: {'branch_1': 0, 'branch_2': 0}, // Total: 0
    category: 'Bánh kẹo',
    minStock: 10,
  );

  const comboProduct = Product(
    id: 'prod_combo',
    name: 'Combo Tiệc Nhẹ',
    code: 'CB01',
    price: 80000,
    costPrice: 55000,
    branchStocks: {'branch_1': 10, 'branch_2': 5},
    category: 'Combo',
    isCombo: true,
    comboComponents: [
      ComboComponent(
        productId: 'prod_instock',
        productCode: 'BSG01',
        productName: 'Bia Saigon Special',
        quantity: 2,
        costPrice: 11000,
      ),
      ComboComponent(
        productId: 'prod_outstock',
        productCode: 'PK01',
        productName: 'Bánh que Pocky',
        quantity: 1,
        costPrice: 8000,
      ),
    ],
  );

  group('ProductTile Widget Tests (M3)', () {
    testWidgets('Renders in-stock product with green badge and branch breakdown',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: inStockProduct),
          overrides: [
            productListProvider
                .overrideWith((ref) => Stream.value([inStockProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Product basic info
      expect(find.text('Bia Saigon Special 330ml'), findsOneWidget);
      expect(find.text('Mã: BSG01'), findsOneWidget);

      // In stock badge
      expect(find.text('Còn hàng'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);

      // Stock and price
      expect(find.text('Tồn: 50'), findsOneWidget);
      expect(find.textContaining('15.000'), findsOneWidget);

      // Branch distribution: ĐT: 30 | TB: 20
      expect(find.textContaining('ĐT: 30 | TB: 20'), findsOneWidget);
    });

    testWidgets('Renders low-stock product with orange/amber badge',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: lowStockProduct),
          overrides: [
            productListProvider
                .overrideWith((ref) => Stream.value([lowStockProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cáp sạc Type-C 60W'), findsOneWidget);
      expect(find.text('Mã: ANK01'), findsOneWidget);

      // Low stock warning badge
      expect(find.text('Dưới định mức'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsNothing);

      // Total stock and price
      expect(find.text('Tồn: 3'), findsOneWidget);
      expect(find.textContaining('180.000'), findsOneWidget);

      // Branch breakdown: ĐT: 2 | TB: 1
      expect(find.textContaining('ĐT: 2 | TB: 1'), findsOneWidget);
    });

    testWidgets('Renders out-of-stock product with red warning badge',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: outOfStockProduct),
          overrides: [
            productListProvider
                .overrideWith((ref) => Stream.value([outOfStockProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bánh que Pocky Socola'), findsOneWidget);
      expect(find.text('Mã: PK01'), findsOneWidget);

      // Out of stock warning badge
      expect(find.text('Hết hàng'), findsOneWidget);
      expect(find.byIcon(Icons.warning), findsNothing);

      // Total stock 0
      expect(find.text('Tồn: 0'), findsOneWidget);
      expect(find.textContaining('12.000'), findsOneWidget);
    });

    testWidgets('Renders combo product with COMBO tag and components summary',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: comboProduct),
          overrides: [
            productListProvider.overrideWith((ref) =>
                Stream.value([inStockProduct, outOfStockProduct, comboProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Combo product name and COMBO badge
      expect(find.text('Combo Tiệc Nhẹ'), findsOneWidget);
      expect(find.text('COMBO'), findsOneWidget);

      // Components summary
      expect(
          find.textContaining('2x Bia Saigon Special, 1x Bánh que Pocky'),
          findsOneWidget);

      // Effective combo stock label (Tồn bộ: 0 because Pocky is out of stock)
      expect(find.text('Tồn bộ: 0'), findsOneWidget);
      expect(find.text('Hết hàng'), findsOneWidget);
    });

    testWidgets('Triggers custom onTap callback when tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _buildTestApp(
          child: ProductTile(
            product: inStockProduct,
            onTap: () {
              tapped = true;
            },
          ),
          overrides: [
            productListProvider
                .overrideWith((ref) => Stream.value([inStockProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ProductTile));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('Renders product with custom branch names and negative stock correctly',
        (tester) async {
      const negativeStockProduct = Product(
        id: 'prod_neg',
        name: 'Sản phẩm tồn âm',
        code: 'NEG01',
        price: 50000,
        costPrice: 30000,
        branchStocks: {'Chi nhánh Thới Bình': -2, 'Kho tổng': 0},
        category: 'Gia dụng',
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

      expect(find.text('Sản phẩm tồn âm'), findsOneWidget);
      expect(find.text('Hết hàng'), findsOneWidget);
      expect(find.text('Tồn: -2'), findsOneWidget);
      expect(find.textContaining('TB: -2 | Kho tổng: 0'), findsOneWidget);
    });

    testWidgets('Renders product with exactly minStock as low stock',
        (tester) async {
      const exactMinProduct = Product(
        id: 'prod_exact_min',
        name: 'Sản phẩm chạm đáy minStock',
        code: 'MIN01',
        price: 25000,
        costPrice: 15000,
        branchStocks: {'branch_1': 5},
        category: 'Văn phòng phẩm',
        minStock: 5,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: exactMinProduct),
          overrides: [
            productListProvider
                .overrideWith((ref) => Stream.value([exactMinProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dưới định mức'), findsOneWidget);
      expect(find.text('Tồn: 5'), findsOneWidget);
    });

    testWidgets('Renders canonical store_001 and store_002 as ĐT and TB badges',
        (tester) async {
      const canonicalProduct = Product(
        id: 'prod_canon',
        name: 'Sữa tươi ít đường',
        code: 'MILK01',
        price: 32000,
        costPrice: 22000,
        branchStocks: {'store_001': 15, 'store_002': 8},
        category: 'Đồ uống',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: canonicalProduct),
          overrides: [
            productListProvider
                .overrideWith((ref) => Stream.value([canonicalProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tồn: 23'), findsOneWidget);
      expect(find.textContaining('ĐT: 15 | TB: 8'), findsOneWidget);
    });

    testWidgets('Renders branch stock even when one branch has 0 quantity',
        (tester) async {
      const oneZeroProduct = Product(
        id: 'prod_one_zero',
        name: 'Nước suối Aquafina',
        code: 'AQUA01',
        price: 5000,
        costPrice: 3000,
        branchStocks: {'store_001': 20, 'store_002': 0},
        category: 'Đồ uống',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: oneZeroProduct),
          overrides: [
            productListProvider
                .overrideWith((ref) => Stream.value([oneZeroProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tồn: 20'), findsOneWidget);
      expect(find.textContaining('ĐT: 20 | TB: 0'), findsOneWidget);
    });

    testWidgets('Renders dynamic short code for multi-branch expanded network',
        (tester) async {
      const multiBranchProduct = Product(
        id: 'prod_multi',
        name: 'Dầu ăn Simply 1L',
        code: 'SIMP01',
        price: 65000,
        costPrice: 48000,
        branchStocks: {
          'store_001': 10,
          'store_002': 5,
          'Chi nhánh Cần Thơ': 8,
          'store_004': 4,
        },
        category: 'Gia vị',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: multiBranchProduct),
          overrides: [
            productListProvider
                .overrideWith((ref) => Stream.value([multiBranchProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tồn: 27'), findsOneWidget);
      expect(find.textContaining('ĐT: 10 | TB: 5 | CT: 8 | CN4: 4'), findsOneWidget);
    });

    testWidgets(
        'Standard non-combo product does not watch productListProvider and uses product.stock directly',
        (tester) async {
      // Even if productListProvider is an error stream, standard products should render fine
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: inStockProduct),
          overrides: [
            productListProvider.overrideWith(
              (ref) => Stream<List<Product>>.error(Exception('Should not be watched')),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bia Saigon Special 330ml'), findsOneWidget);
      expect(find.text('Tồn: 50'), findsOneWidget);
      expect(find.text('Còn hàng'), findsOneWidget);
    });

    testWidgets(
        'Combo product watches productListProvider via select and updates displayStock dynamically',
        (tester) async {
      final controller = StreamController<List<Product>>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: comboProduct),
          overrides: [
            productListProvider.overrideWith((ref) => controller.stream),
          ],
        ),
      );

      // Initial state: Pocky has 0 stock -> combo stock = 0
      controller.add([
        inStockProduct,
        outOfStockProduct,
        comboProduct,
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Tồn bộ: 0'), findsOneWidget);

      // Update component stock: Pocky has 10 stock -> combo requires 2 Bia (50/2=25) & 1 Pocky (10/1=10) -> stock = 10
      controller.add([
        inStockProduct,
        outOfStockProduct.copyWith(
          branchStocks: {'branch_1': 10},
        ),
        comboProduct,
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Tồn bộ: 10'), findsOneWidget);
    });

    testWidgets(
        'ProductTile configures ProductImageThumbnail with 150x150 cacheWidth and cacheHeight',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductTile(product: inStockProduct),
          overrides: [
            productListProvider
                .overrideWith((ref) => Stream.value([inStockProduct])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final thumbnailFinder = find.byType(ProductImageThumbnail);
      expect(thumbnailFinder, findsOneWidget);
      final thumbnail = tester.widget<ProductImageThumbnail>(thumbnailFinder);
      expect(thumbnail.cacheWidth, equals(150));
      expect(thumbnail.cacheHeight, equals(150));
    });
  });
}
