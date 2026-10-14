import 'package:flutter/material.dart';
import 'package:stores/presentation/products/pages/add_category_page.dart';
import 'package:stores/presentation/products/pages/add_product_page.dart';
import 'package:stores/presentation/products/pages/categories_management_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/products/pages/select_brand_page.dart';
import 'package:stores/presentation/products/pages/select_category_page.dart';

import '../ui_matrix_other/products_matrix_test.dart' as pm;
import 'monkey_kit.dart';

void main() {
  monkeyTest('ProductsPage(5000)', () => const ProductsPage(), (u) => pm.ov(u));
  monkeyTest('AddProductPage', () => const AddProductPage(), (u) => pm.ov(u));
  monkeyTest('AddCategoryPage', () => const AddCategoryPage(), (u) => pm.ov(u));
  monkeyTest('CategoriesManagementPage', () => const CategoriesManagementPage(),
      (u) => pm.ov(u));
  monkeyTest('SelectBrandPage', () => const SelectBrandPage(), (u) => pm.ov(u));
  monkeyTest(
      'SelectCategoryPage', () => const SelectCategoryPage(), (u) => pm.ov(u));
  monkeyTest('ProductDetailPage',
      () => ProductDetailPage(product: Gen(7).products(3)[1]), (u) => pm.ov(u));
}
