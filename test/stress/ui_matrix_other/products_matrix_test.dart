import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/products/pages/add_category_page.dart';
import 'package:stores/presentation/products/pages/add_product_page.dart';
import 'package:stores/presentation/products/pages/categories_management_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/products/pages/select_brand_page.dart';
import 'package:stores/presentation/products/pages/select_category_page.dart';
import 'package:stores/presentation/products/widgets/category_filter_bottom_sheet.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';
import 'package:stores/presentation/products/widgets/sample_image_picker_dialog.dart';

import 'stress_kit.dart';

final _g = Gen();
final _products = _g.products(5000);
final _cats = [
  for (var i = 0; i < 300; i++)
    Category(
        id: 'c$i',
        name: _g.maybeAdv('Nhóm $i', p: .1),
        parentId: i % 10 == 0 || i < 10 ? null : 'c${(i ~/ 10) * 10}'),
];

List<Override> ov(user, {List<Product>? products}) => [
      authProvider.overrideWith((ref) => SweepAuth(user)),
      currentStoreIdProvider.overrideWithValue('store_001'),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': sweepLongStore,
            'store_002': 'Chi nhánh Thới Bình',
            'store_003': 'CN 3',
          }),
      productListProvider
          .overrideWith((ref) => Stream.value(products ?? _products)),
      categoryListProvider.overrideWith((ref) => Stream.value(_cats)),
    ];

void main() {
  stressMatrix('ProductsPage(5000)', () => const ProductsPage(), (u) => ov(u),
      check: (t, d) async {
    final n = built(ProductTile);
    expect(n, lessThan(100), reason: 'built $n tiles of 5000');
    // scroll to the bottom with a big fling then back: no exceptions
    await t.fling(find.byType(Scrollable).first, const Offset(0, -3000), 5000);
    await t.pumpAndSettle();
    expect(built(ProductTile), lessThan(100));
  });
  stressMatrix('ProductsPage(empty)', () => const ProductsPage(),
      (u) => ov(u, products: const []),
      rot: 2);
  stressMatrix(
      'ProductsPage(degenerate)',
      () => const ProductsPage(),
      (u) => ov(u, products: [
            for (final a in adversarial)
              Product(
                  id: 'x${a.hashCode}',
                  name: a,
                  code: a,
                  price: 1e12,
                  costPrice: -5,
                  branchStocks: const {},
                  category: a)
          ]),
      rot: 3);
  stressMatrix('ProductDetailPage',
      () => ProductDetailPage(product: _products[7]), (u) => ov(u),
      rot: 1);
  stressMatrix(
      'ProductDetailPage(adversarial)',
      () => ProductDetailPage(
          product: Product(
              id: 'z',
              name: longWord,
              code: emojiStr,
              brand: rtl,
              price: 1e12,
              costPrice: -1e12,
              branchStocks: const {'store_001': -999999999},
              category: '$combining >> $zeroWidth >> $newlines',
              description: '$newlines$longWord$emojiStr')),
      (u) => ov(u),
      rot: 4);
  stressMatrix('CategoriesManagementPage',
      () => const CategoriesManagementPage(), (u) => ov(u),
      rot: 2);
  stressMatrix(
      'SelectCategoryPage', () => const SelectCategoryPage(), (u) => ov(u),
      rot: 3);
  stressMatrix('SelectBrandPage', () => const SelectBrandPage(), (u) => ov(u),
      rot: 4);
  stressMatrix('AddCategoryPage', () => const AddCategoryPage(), (u) => ov(u));
  stressMatrix(
      'AddProductPage(new)', () => const AddProductPage(), (u) => ov(u),
      rot: 1);
  stressMatrix(
      'AddProductPage(edit adversarial)',
      () => AddProductPage(
          product: Product(
              id: 'z',
              name: longWord,
              code: emojiStr,
              brand: rtl,
              price: 1e12,
              costPrice: -1e12,
              branchStocks: const {'store_001': -999999999},
              category: '$combining >> $zeroWidth',
              description: '$newlines$longWord')),
      (u) => ov(u),
      rot: 2);
  stressMatrix(
      'CategoryFilterBottomSheet',
      () => Scaffold(
          body: CategoryFilterBottomSheet(
              currentSelectedCategory: 'All',
              initialSelectedCategories: const {},
              onCategoriesSelected: (_) {})),
      (u) => ov(u),
      rot: 1);
  stressMatrix(
      'SampleImagePickerDialog',
      () => Scaffold(
          body: SampleImagePickerDialog(
              productName: longWord, category: emojiStr, brand: rtl)),
      (u) => ov(u),
      rot: 3);
}
