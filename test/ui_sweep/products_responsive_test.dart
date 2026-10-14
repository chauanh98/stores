import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/products/pages/add_category_page.dart';
import 'package:stores/presentation/products/pages/add_product_page.dart';
import 'package:stores/presentation/products/pages/categories_management_page.dart';
import 'package:stores/presentation/products/pages/select_brand_page.dart';
import 'package:stores/presentation/products/pages/select_category_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

import 'sweep_harness.dart';

List<Override> _base(user, Stream<List<Product>> Function() products) => [
      authProvider.overrideWith((ref) => SweepAuth(user)),
      currentStoreIdProvider.overrideWithValue('store_001'),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': sweepLongStore,
            'store_002': 'Chi nhánh Thới Bình',
          }),
      productListProvider.overrideWith((ref) => products()),
      categoryListProvider.overrideWith((ref) => Stream.value(_cats(60))),
    ];

List<Category> _cats(int n) => [
      for (var i = 0; i < n; i++)
        Category(
            id: 'c$i',
            name: i % 4 == 0
                ? 'Bia, Rượu, Nước giải khát nhập khẩu rất dài $i'
                : 'Nhóm $i',
            parentId: i % 4 == 0 || i < 4 ? null : 'c${(i ~/ 4) * 4}'),
    ];

void main() {
  sweepMatrix('ProductsPage(40 long)', () => const ProductsPage(),
      (u) => _base(u, () => Stream.value(sweepProducts(40))));
  sweepMatrix('ProductsPage(empty)', () => const ProductsPage(),
      (u) => _base(u, () => Stream.value(<Product>[])),
      screens: {'320x568': sweepScreens['320x568']!});
  sweepMatrix('ProductsPage(error)', () => const ProductsPage(),
      (u) => _base(u, () => Stream<List<Product>>.error('boom')),
      screens: {'320x568': sweepScreens['320x568']!});
  sweepMatrix(
      'ProductDetailPage',
      () => ProductDetailPage(product: sweepProducts(1).first),
      (u) => _base(u, () => Stream.value(sweepProducts(1))));

  final prods = (u) => _base(u, () => Stream.value(sweepProducts(40)));
  sweepMatrix('CategoriesManagementPage',
      () => const CategoriesManagementPage(), prods);
  sweepMatrix('SelectCategoryPage', () => const SelectCategoryPage(), prods);
  sweepMatrix('SelectBrandPage', () => const SelectBrandPage(), prods);
  sweepMatrix('AddCategoryPage', () => const AddCategoryPage(), prods);
  sweepMatrix('AddProductPage', () => const AddProductPage(), prods);
  sweepMatrix('AddProductPage(edit)',
      () => AddProductPage(product: sweepProducts(1).first), prods);

  testWidgets('ProductsPage with 600 products builds lazily', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(sweepHost(const ProductsPage(),
        _base(sweepAdmin, () => Stream.value(sweepProducts(600)))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ProductTile).evaluate().length, lessThan(60));
  });

  testWidgets('typing in search over 3000 products stays responsive',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(sweepHost(const ProductsPage(),
        _base(sweepAdmin, () => Stream.value(sweepProducts(3000)))));
    await tester.pumpAndSettle();
    final sw = Stopwatch()..start();
    for (final q in ['S', 'Sả', 'Sản', 'Sản p', 'Sản ph', 'Sản phẩm 12']) {
      await tester.enterText(find.byType(TextField).first, q);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    sw.stop();
    expectNoException(tester);
    expect(find.textContaining('Sản phẩm 12'), findsWidgets);
    // 6 keystrokes incl. re-filter/sort of 3000 items; generous CI bound.
    expect(sw.elapsedMilliseconds, lessThan(4000));
    debugPrint(
        'search 6 keystrokes @3000 products: ${sw.elapsedMilliseconds}ms');
  });
}
