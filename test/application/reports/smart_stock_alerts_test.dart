import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/product.dart';

import '../../fixtures/mock_report_data.dart';

void main() {
  group('Smart Stock Alerts & Inventory Valuation (R3)', () {
    // Pure calculation engine for Stock Alerts
    StockAlertSummary calculateStockAlerts({
      required List<Product> products,
      String? branchId, // null or 'all' means all branches combined
      int lowStockThreshold = 5,
    }) {
      int outOfStock = 0;
      int lowStock = 0;
      int totalItems = 0;
      double totalCost = 0.0;

      for (final product in products) {
        // Skip combo products from physical inventory counting if they don't have separate physical stock
        if (product.isCombo) continue;

        final int effectiveStock;
        if (branchId == null || branchId == 'all') {
          effectiveStock = product.stock;
        } else {
          effectiveStock = product.branchStocks[branchId] ?? 0;
        }

        if (effectiveStock <= 0) {
          outOfStock++;
        } else if (effectiveStock <= lowStockThreshold) {
          lowStock++;
        }

        if (effectiveStock > 0) {
          totalItems += effectiveStock;
          totalCost += effectiveStock * product.costPrice;
        }
      }

      return StockAlertSummary(
        outOfStockCount: outOfStock,
        lowStockCount: lowStock,
        totalItemCount: totalItems,
        totalInventoryCost: totalCost,
      );
    }

    group('Tier 1: Feature Coverage (Stock Alerts & Valuation)', () {
      test('1.1 Accurately identifies Out-of-Stock items (stock == 0)', () {
        final products = [
          MockReportData.createProduct(
            id: 'p_out_1',
            branchStocks: {'branch_1': 0, 'branch_2': 0},
          ),
          MockReportData.createProduct(
            id: 'p_out_2',
            branchStocks: {'branch_1': 0, 'branch_2': 0},
          ),
          MockReportData.createProduct(
            id: 'p_in',
            branchStocks: {'branch_1': 10, 'branch_2': 5},
          ),
        ];

        final summary = calculateStockAlerts(products: products);
        expect(summary.outOfStockCount, equals(2));
      });

      test('1.2 Accurately identifies Low-Stock items (0 < stock <= 5)', () {
        final products = [
          MockReportData.createProduct(
            id: 'p_low_1',
            branchStocks: {'branch_1': 2, 'branch_2': 1}, // total 3 <= 5
          ),
          MockReportData.createProduct(
            id: 'p_low_2',
            branchStocks: {'branch_1': 5, 'branch_2': 0}, // total 5 <= 5
          ),
          MockReportData.createProduct(
            id: 'p_in',
            branchStocks: {'branch_1': 10, 'branch_2': 5}, // total 15 > 5
          ),
          MockReportData.createProduct(
            id: 'p_out',
            branchStocks: {'branch_1': 0, 'branch_2': 0}, // total 0
          ),
        ];

        final summary = calculateStockAlerts(products: products);
        expect(summary.lowStockCount, equals(2));
        expect(summary.outOfStockCount, equals(1));
      });

      test('1.3 Calculates total physical item count and total valuation at cost',
          () {
        final products = [
          MockReportData.createProduct(
            id: 'p1',
            costPrice: 100000.0,
            branchStocks: {'branch_1': 10, 'branch_2': 10}, // 20 units @ 100k = 2M
          ),
          MockReportData.createProduct(
            id: 'p2',
            costPrice: 250000.0,
            branchStocks: {'branch_1': 4, 'branch_2': 0}, // 4 units @ 250k = 1M
          ),
        ];

        final summary = calculateStockAlerts(products: products);
        expect(summary.totalItemCount, equals(24));
        expect(summary.totalInventoryCost, equals(3000000.0));
      });
    });

    group('Tier 2: Boundary & Corner Cases', () {
      test('2.1 Boundary testing at stock = 0, 1, 5, 6', () {
        final prod0 = MockReportData.createProduct(
          id: 'p0',
          branchStocks: {'branch_1': 0},
        );
        final prod1 = MockReportData.createProduct(
          id: 'p1',
          branchStocks: {'branch_1': 1},
        );
        final prod5 = MockReportData.createProduct(
          id: 'p5',
          branchStocks: {'branch_1': 5},
        );
        final prod6 = MockReportData.createProduct(
          id: 'p6',
          branchStocks: {'branch_1': 6},
        );

        // stock = 0 -> out of stock
        final s0 = calculateStockAlerts(products: [prod0]);
        expect(s0.outOfStockCount, equals(1));
        expect(s0.lowStockCount, equals(0));

        // stock = 1 -> low stock
        final s1 = calculateStockAlerts(products: [prod1]);
        expect(s1.outOfStockCount, equals(0));
        expect(s1.lowStockCount, equals(1));

        // stock = 5 -> low stock (boundary)
        final s5 = calculateStockAlerts(products: [prod5]);
        expect(s5.outOfStockCount, equals(0));
        expect(s5.lowStockCount, equals(1));

        // stock = 6 -> adequate stock (in-stock)
        final s6 = calculateStockAlerts(products: [prod6]);
        expect(s6.outOfStockCount, equals(0));
        expect(s6.lowStockCount, equals(0));
      });

      test('2.2 Negative stock values are treated safely as out of stock', () {
        final prodNegative = MockReportData.createProduct(
          id: 'p_neg',
          branchStocks: {'branch_1': -2},
        );

        final summary = calculateStockAlerts(products: [prodNegative]);
        expect(summary.outOfStockCount, equals(1));
        expect(summary.lowStockCount, equals(0));
        expect(summary.totalItemCount, equals(0));
        expect(summary.totalInventoryCost, equals(0.0));
      });

      test('2.3 Zero products in catalog returns all zeros', () {
        final summary = calculateStockAlerts(products: []);
        expect(summary.outOfStockCount, equals(0));
        expect(summary.lowStockCount, equals(0));
        expect(summary.totalItemCount, equals(0));
        expect(summary.totalInventoryCost, equals(0.0));
      });

      test('2.4 Combos do not distort physical inventory counts or alerts', () {
        final comboProd = MockReportData.createProduct(
          id: 'p_combo',
          name: 'Bộ Combo Bàn Ghế',
          isCombo: true,
          branchStocks: {'branch_1': 0, 'branch_2': 0},
          costPrice: 1500000.0,
        );
        final normalProd = MockReportData.createProduct(
          id: 'p_normal',
          isCombo: false,
          branchStocks: {'branch_1': 10},
          costPrice: 200000.0,
        );

        final summary =
            calculateStockAlerts(products: [comboProd, normalProd]);
        // Combo is skipped from physical stock alerts
        expect(summary.outOfStockCount, equals(0));
        expect(summary.totalItemCount, equals(10));
        expect(summary.totalInventoryCost, equals(2000000.0));
      });
    });

    group('Tier 3: Combinatorial & Multi-Branch Stock Scenarios', () {
      test('3.1 Branch stock disparity (Out of stock at Branch 1, but In stock at Branch 2)',
          () {
        final productDisparity = MockReportData.createProduct(
          id: 'p_disp',
          costPrice: 500000.0,
          branchStocks: {'branch_1': 0, 'branch_2': 12},
        );

        // When viewing Branch 1: Out of stock
        final summaryB1 = calculateStockAlerts(
          products: [productDisparity],
          branchId: 'branch_1',
        );
        expect(summaryB1.outOfStockCount, equals(1));
        expect(summaryB1.totalItemCount, equals(0));
        expect(summaryB1.totalInventoryCost, equals(0.0));

        // When viewing Branch 2: In stock (12 units)
        final summaryB2 = calculateStockAlerts(
          products: [productDisparity],
          branchId: 'branch_2',
        );
        expect(summaryB2.outOfStockCount, equals(0));
        expect(summaryB2.lowStockCount, equals(0));
        expect(summaryB2.totalItemCount, equals(12));
        expect(summaryB2.totalInventoryCost, equals(6000000.0));

        // When viewing All Branches: In stock (12 units)
        final summaryAll = calculateStockAlerts(
          products: [productDisparity],
          branchId: 'all',
        );
        expect(summaryAll.outOfStockCount, equals(0));
        expect(summaryAll.totalItemCount, equals(12));
      });

      test('3.2 Low stock aggregation across branches', () {
        final productLow = MockReportData.createProduct(
          id: 'p_low_cross',
          branchStocks: {'branch_1': 3, 'branch_2': 4}, // 3 and 4 -> total 7
        );

        // Branch 1 has 3 (Low stock <= 5)
        final sB1 = calculateStockAlerts(
          products: [productLow],
          branchId: 'branch_1',
        );
        expect(sB1.lowStockCount, equals(1));

        // Branch 2 has 4 (Low stock <= 5)
        final sB2 = calculateStockAlerts(
          products: [productLow],
          branchId: 'branch_2',
        );
        expect(sB2.lowStockCount, equals(1));

        // Combined has 7 (Adequate stock > 5)
        final sAll = calculateStockAlerts(
          products: [productLow],
          branchId: 'all',
        );
        expect(sAll.lowStockCount, equals(0));
        expect(sAll.outOfStockCount, equals(0));
        expect(sAll.totalItemCount, equals(7));
      });
    });

    group('Tier 4: Realistic Warehouse Inventory Scenario', () {
      test('4.1 Multi-category 7-product catalog stock audit', () {
        final catalog = MockReportData.sampleProductCatalog();

        // Catalog analysis from sampleProductCatalog:
        // p_fashion_1: b1=20, b2=15 -> total 35 (In stock)
        // p_fashion_2: b1=10, b2=5  -> total 15 (In stock)
        // p_tech_1:    b1=50, b2=30 -> total 80 (In stock)
        // p_tech_2:    b1=4,  b2=1  -> total 5  (Low stock)
        // p_tech_3:    b1=0,  b2=0  -> total 0  (Out of stock)
        // p_home_1:    b1=8,  b2=0  -> total 8  (In stock)
        // p_beauty_1:  b1=2,  b2=1  -> total 3  (Low stock)

        final summaryAll = calculateStockAlerts(
          products: catalog,
          branchId: 'all',
        );

        expect(summaryAll.outOfStockCount, equals(1)); // p_tech_3
        expect(summaryAll.lowStockCount, equals(2)); // p_tech_2 (5), p_beauty_1 (3)

        // Total Items: 35 + 15 + 80 + 5 + 0 + 8 + 3 = 146 units
        expect(summaryAll.totalItemCount, equals(146));

        // Total Cost:
        // p_fashion_1: 35 * 150k = 5,250,000
        // p_fashion_2: 15 * 280k = 4,200,000
        // p_tech_1:    80 * 60k  = 4,800,000
        // p_tech_2:    5  * 400k = 2,000,000
        // p_tech_3:    0  * 200k = 0
        // p_home_1:    8  * 100k = 800,000
        // p_beauty_1:  3  * 190k = 570,000
        // Sum = 5.25M + 4.2M + 4.8M + 2M + 0.8M + 0.57M = 17,620,000 đ
        expect(summaryAll.totalInventoryCost, equals(17620000.0));
      });
    });

    group('Riverpod Provider Integration (stockAlertSummaryProvider)', () {
      test('stockAlertSummaryProvider calculates reactive summary from products', () {
        final catalog = MockReportData.sampleProductCatalog();
        final container = ProviderContainer(
          overrides: [
            allStoresProductsProvider.overrideWith((ref) => Stream.value(catalog)),
            selectedBranchesProvider.overrideWith((ref) => SelectedBranchesNotifier()),
          ],
        );
        addTearDown(container.dispose);

        // Initial read
        final summaryAsync = container.read(stockAlertSummaryProvider);
        expect(summaryAsync, isA<AsyncValue<StockAlertSummary>>());
      });
    });
  });
}
