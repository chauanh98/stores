import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';
import 'package:stores/presentation/orders/widgets/pos_category_bar.dart';

void main() {
  final sampleCategories = [
    const Category(id: 'phone', name: 'Smartphone'),
    const Category(id: 'laptop', name: 'Laptop'),
    const Category(id: 'tablet', name: 'Tablet'),
  ];

  final sampleProducts = [
    const Product(
      id: 'p1',
      name: 'iPhone 17 Pro',
      code: 'IP17P',
      price: 30000000,
      costPrice: 25000000,
      category: 'Smartphone',
      branchStocks: {'store_001': 10, 'store_002': 5},
      allowSale: true,
      minStock: 3,
    ),
    const Product(
      id: 'p2',
      name: 'Samsung Galaxy S25',
      code: 'S25',
      price: 22000000,
      costPrice: 18000000,
      category: 'Smartphone',
      branchStocks: {'store_001': 2, 'store_002': 0}, // Low stock
      allowSale: true,
      minStock: 5,
    ),
    const Product(
      id: 'p3',
      name: 'MacBook Pro M4',
      code: 'MBPM4',
      price: 45000000,
      costPrice: 38000000,
      category: 'Laptop',
      branchStocks: {'store_001': 0, 'store_002': 0}, // Out of stock
      allowSale: true,
      minStock: 2,
    ),
    const Product(
      id: 'p4',
      name: 'iPad Air M2',
      code: 'IPADAIR',
      price: 15000000,
      costPrice: 12000000,
      category: 'Tablet',
      branchStocks: {'store_001': 8, 'store_002': 8},
      allowSale: true,
      minStock: 2,
    ),
  ];

  group('PosCategoryBar Widget Tests', () {
    testWidgets('Renders Tat ca and dynamic categories with correct product counts', (tester) async {
      String? selectedId;
      String? selectedName;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryListProvider.overrideWith((ref) => Stream.value(sampleCategories)),
            productListProvider.overrideWith((ref) => Stream.value(sampleProducts)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PosCategoryBar(
                selectedCategoryId: 'all',
                onCategorySelected: (id, name) {
                  selectedId = id;
                  selectedName = name;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check chips
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Smartphone'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('Tablet'), findsOneWidget);

      // Check count badges
      expect(find.text('4'), findsOneWidget); // 4 total products in 'all'
      expect(find.text('2'), findsOneWidget); // 2 in Smartphone
      expect(find.text('1'), findsNWidgets(2)); // 1 in Laptop, 1 in Tablet

      // Tap on Smartphone
      await tester.tap(find.text('Smartphone'));
      await tester.pumpAndSettle();

      expect(selectedId, 'phone');
      expect(selectedName, 'Smartphone');
    });
  });

  group('POSPage Category Filter & Stock Tags Integration Tests', () {
    Widget buildPOSPage() {
      return ProviderScope(
        overrides: [
          categoryListProvider.overrideWith((ref) => Stream.value(sampleCategories)),
          productListProvider.overrideWith((ref) => Stream.value(sampleProducts)),
          currentStoreNameProvider.overrideWith((ref) => 'Đông Thắng Store'),
          selectedPOSBranchProvider.overrideWith((ref) => 'store_001'),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: POSPage(),
        ),
      );
    }

    testWidgets('POSPage displays category bar, branch stocks, and stock badges', (tester) async {
      await tester.pumpWidget(buildPOSPage());
      await tester.pumpAndSettle();

      // Category bar is visible
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Smartphone'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);

      // All 4 products initially visible
      expect(find.text('iPhone 17 Pro'), findsOneWidget);
      expect(find.text('Samsung Galaxy S25'), findsOneWidget);
      expect(find.text('MacBook Pro M4'), findsOneWidget);
      expect(find.text('iPad Air M2'), findsOneWidget);

      // Branch stock tags
      expect(find.textContaining('ĐT: 10 | TB: 5'), findsOneWidget);
      expect(find.textContaining('ĐT: 2 | TB: 0'), findsOneWidget);

      // Stock status badges
      expect(find.text('Còn hàng'), findsNWidgets(2)); // iPhone 17 (10) & iPad Air (8)
      expect(find.text('Sắp hết'), findsOneWidget); // Samsung S25 (2 <= minStock 5)
      expect(find.text('Hết hàng'), findsOneWidget); // MacBook (0)
    });

    testWidgets('POSPage filters list when a category chip is tapped', (tester) async {
      await tester.pumpWidget(buildPOSPage());
      await tester.pumpAndSettle();

      // Tap 'Laptop' chip
      await tester.tap(find.text('Laptop'));
      await tester.pumpAndSettle();

      // Only MacBook Pro M4 should remain
      expect(find.text('MacBook Pro M4'), findsOneWidget);
      expect(find.text('iPhone 17 Pro'), findsNothing);
      expect(find.text('Samsung Galaxy S25'), findsNothing);
      expect(find.text('iPad Air M2'), findsNothing);

      // Tap 'Smartphone' chip
      await tester.tap(find.text('Smartphone'));
      await tester.pumpAndSettle();

      expect(find.text('iPhone 17 Pro'), findsOneWidget);
      expect(find.text('Samsung Galaxy S25'), findsOneWidget);
      expect(find.text('MacBook Pro M4'), findsNothing);
      expect(find.text('iPad Air M2'), findsNothing);

      // Tap 'Tất cả' chip
      await tester.tap(find.text('Tất cả'));
      await tester.pumpAndSettle();

      expect(find.text('iPhone 17 Pro'), findsOneWidget);
      expect(find.text('MacBook Pro M4'), findsOneWidget);
      expect(find.text('iPad Air M2'), findsOneWidget);
    });

    testWidgets('POSPage combined search query and category filter', (tester) async {
      await tester.pumpWidget(buildPOSPage());
      await tester.pumpAndSettle();

      // Filter by Smartphone
      await tester.tap(find.text('Smartphone'));
      await tester.pumpAndSettle();

      // Enter search text 'S25'
      await tester.enterText(find.byType(TextField).first, 'S25');
      await tester.pumpAndSettle();

      expect(find.text('Samsung Galaxy S25'), findsOneWidget);
      expect(find.text('iPhone 17 Pro'), findsNothing);
    });
  });
}
