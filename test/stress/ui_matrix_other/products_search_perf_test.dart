import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/presentation/products/pages/products_page.dart';

import 'stress_kit.dart';

void main() {
  final products = Gen().products(5000);
  final cats = [
    for (var i = 0; i < 300; i++) Category(id: 'c$i', name: 'Nhóm $i')
  ];
  final ov = <Override>[
    authProvider.overrideWith((ref) => SweepAuth(sweepAdmin)),
    currentStoreIdProvider.overrideWithValue('store_001'),
    productListProvider.overrideWith((ref) => Stream.value(products)),
    categoryListProvider.overrideWith((ref) => Stream.value(cats)),
  ];

  test('provider: 40 keystrokes over 5000 products', () async {
    final c = ProviderContainer(overrides: ov);
    addTearDown(c.dispose);
    c.listen(processedProductsProvider, (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.read(processedProductsProvider).requireValue; // warm caches
    final queries = [
      for (final w in ['Sản phẩm 12', 'brand 7', 'nhom 3 con'])
        for (var i = 1; i <= w.length; i++) w.substring(0, i)
    ];
    final sw = Stopwatch()..start();
    for (final q in queries) {
      c.read(productSearchQueryProvider.notifier).state = q;
      c.read(processedProductsProvider).requireValue;
    }
    sw.stop();
    final per = sw.elapsedMicroseconds / queries.length / 1000;
    debugPrint('PERF provider ${queries.length} keystrokes: '
        '${sw.elapsedMilliseconds}ms total, ${per.toStringAsFixed(1)}ms/keystroke');
    expect(per, lessThan(150));
  });

  testWidgets('UI: typing 5000-product search (pump per key)', (t) async {
    setDevice(t, devices[5]);
    addTearDown(t.view.reset);
    await t.pumpWidget(stressHost(const ProductsPage(), ov));
    await t.pumpAndSettle();
    final sw = Stopwatch()..start();
    var q = '';
    for (final ch in 'Sản phẩm 123'.split('')) {
      q += ch;
      await t.enterText(find.byType(TextField).first, q);
      await t.pump();
    }
    await t.pumpAndSettle();
    sw.stop();
    expectClean(t, 'search');
    debugPrint('PERF ui 12 keystrokes: ${sw.elapsedMilliseconds}ms');
    // ~0.8s idle machine; generous bound for loaded CI boxes.
    expect(sw.elapsedMilliseconds, lessThan(3000));
  });
}
