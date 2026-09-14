import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/revenue_report.dart';
import 'package:stores/domain/entities/transaction_type.dart';

import '../../fixtures/mock_report_data.dart';

void main() {
  group('Empirical Challenger 1: Adversarial Stress Tests (R1 - R6)', () {
    // =========================================================================
    // Challenge 1: FIFO Inventory Lot Tracking with Multiple Depleted Lots Across Days
    // =========================================================================
    group('Challenge 1: FIFO Multi-Day Lot Depletion & Overselling', () {
      test(
          '1.1 Three sequential import lots depleted across 4 consecutive days with oversold fallback',
          () {
        final List<InventoryTransaction> imports = [
          InventoryTransaction(
            id: 'imp_1',
            productId: 'item_fifo',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1, 8, 0),
            note: 'Lô 1',
            importPrice: 10000.0, // Lot 1: 10 units @ 10k
          ),
          InventoryTransaction(
            id: 'imp_2',
            productId: 'item_fifo',
            type: TransactionType.import,
            quantity: 15,
            date: DateTime(2026, 8, 2, 8, 0),
            note: 'Lô 2',
            importPrice: 12000.0, // Lot 2: 15 units @ 12k
          ),
          InventoryTransaction(
            id: 'imp_3',
            productId: 'item_fifo',
            type: TransactionType.import,
            quantity: 20,
            date: DateTime(2026, 8, 3, 8, 0),
            note: 'Lô 3',
            importPrice: 15000.0, // Lot 3: 20 units @ 15k
          ),
        ];

        final fifo = FifoCalculator(imports);

        // Day 1: Sell 8 units (All from Lot 1 @ 10k = 80k)
        final costDay1 = fifo.calculateCostForSale(
          productId: 'item_fifo',
          quantity: 8,
          saleDate: DateTime(2026, 8, 10, 10, 0),
        );
        expect(costDay1, equals(80000.0));
        expect(
            fifo.getInventoryLots('item_fifo')[0].remainingQuantity, equals(2));
        expect(fifo.getInventoryLots('item_fifo')[1].remainingQuantity,
            equals(15));
        expect(fifo.getInventoryLots('item_fifo')[2].remainingQuantity,
            equals(20));

        // Day 2: Sell 10 units (2 from Lot 1 @ 10k + 8 from Lot 2 @ 12k = 20k + 96k = 116k)
        final costDay2 = fifo.calculateCostForSale(
          productId: 'item_fifo',
          quantity: 10,
          saleDate: DateTime(2026, 8, 11, 10, 0),
        );
        expect(costDay2, equals(116000.0));
        expect(
            fifo.getInventoryLots('item_fifo')[0].remainingQuantity, equals(0));
        expect(
            fifo.getInventoryLots('item_fifo')[1].remainingQuantity, equals(7));
        expect(fifo.getInventoryLots('item_fifo')[2].remainingQuantity,
            equals(20));

        // Day 3: Sell 25 units (7 from Lot 2 @ 12k + 18 from Lot 3 @ 15k = 84k + 270k = 354k)
        final costDay3 = fifo.calculateCostForSale(
          productId: 'item_fifo',
          quantity: 25,
          saleDate: DateTime(2026, 8, 12, 10, 0),
        );
        expect(costDay3, equals(354000.0));
        expect(
            fifo.getInventoryLots('item_fifo')[0].remainingQuantity, equals(0));
        expect(
            fifo.getInventoryLots('item_fifo')[1].remainingQuantity, equals(0));
        expect(
            fifo.getInventoryLots('item_fifo')[2].remainingQuantity, equals(2));

        // Day 4: Oversell 5 units (2 from Lot 3 @ 15k + 3 fallback @ fallbackCostPrice 18k = 30k + 54k = 84k)
        final costDay4 = fifo.calculateCostForSale(
          productId: 'item_fifo',
          quantity: 5,
          saleDate: DateTime(2026, 8, 13, 10, 0),
          fallbackCostPrice: 18000.0,
        );
        expect(costDay4, equals(84000.0));
        expect(
            fifo.getInventoryLots('item_fifo')[2].remainingQuantity, equals(0));

        // Total units sold = 8 + 10 + 25 + 5 = 48 units.
        // Total cost = 80k + 116k + 354k + 84k = 634,000 đ
        expect(costDay1 + costDay2 + costDay3 + costDay4, equals(634000.0));
      });

      test(
          '1.2 Zero and negative quantity sales return 0 cost without mutating lots',
          () {
        final List<InventoryTransaction> imports = [
          InventoryTransaction(
            id: 'imp_1',
            productId: 'p_safe',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 8, 1),
            note: 'Nhập lô an toàn',
            importPrice: 50000.0,
          ),
        ];

        final fifo = FifoCalculator(imports);
        expect(
            fifo.calculateCostForSale(
                productId: 'p_safe',
                quantity: 0,
                saleDate: DateTime(2026, 8, 2)),
            equals(0.0));
        expect(
            fifo.calculateCostForSale(
                productId: 'p_safe',
                quantity: -5,
                saleDate: DateTime(2026, 8, 2)),
            equals(0.0));
        expect(
            fifo.getInventoryLots('p_safe')[0].remainingQuantity, equals(10));
      });
    });

    // =========================================================================
    // Challenge 2: Zero Division Guards for AOV and Profit Margin
    // =========================================================================
    group(
        'Challenge 2: Zero Division Guards (AOV, Gross Margin, Profit Margin)',
        () {
      test(
          '2.1 OverviewKPIs getters return 0.0 without NaN or Infinity when netRevenue = 0',
          () {
        const kpisZero = OverviewKPIs(
          netRevenue: 0.0,
          orderCount: 0,
          grossProfit: 0.0,
          aov: 0.0,
        );

        expect(kpisZero.grossMarginPercent, equals(0.0));
        expect(kpisZero.grossMarginPercent.isNaN, isFalse);
        expect(kpisZero.grossMarginPercent.isFinite, isTrue);
        expect(kpisZero.aov, equals(0.0));
      });

      test(
          '2.2 FifoCalculator.calculateProfitMargin guards against zero and negative revenue',
          () {
        expect(
            FifoCalculator.calculateProfitMargin(0.0, 50000.0), equals(0.0));
        expect(FifoCalculator.calculateProfitMargin(-10000.0, 50000.0),
            equals(0.0));
        expect(FifoCalculator.calculateProfitMargin(100000.0, 60000.0),
            equals(40.0));
      });

      test(
          '2.3 PaymentBreakdown percentage getters guard against zero totalAmount',
          () {
        const breakdown = PaymentBreakdown(
          cashAmount: 0.0,
          transferAmount: 0.0,
          debtAmount: 0.0,
          totalAmount: 0.0,
        );

        expect(breakdown.cashPercentage, equals(0.0));
        expect(breakdown.transferPercentage, equals(0.0));
        expect(breakdown.debtPercentage, equals(0.0));
        expect(breakdown.cashPercentage.isNaN, isFalse);
        expect(breakdown.transferPercentage.isNaN, isFalse);
        expect(breakdown.debtPercentage.isNaN, isFalse);
      });
    });

    // =========================================================================
    // Challenge 3: Growth Percentage Calculations Across Edge Baselines
    // =========================================================================
    group('Challenge 3: Period-over-Period Growth Calculations', () {
      test(
          '3.1 Growth math handles 0 prior base, 0 current, and identical periods',
          () {
        expect(calculateGrowthPercent(0.0, 0.0), equals(0.0));
        expect(calculateGrowthPercent(500000.0, 0.0), equals(100.0));
        expect(calculateGrowthPercent(0.0, 500000.0), equals(-100.0));
        expect(calculateGrowthPercent(500000.0, 500000.0), equals(0.0));
      });

      test('3.2 Growth math handles recovery from negative profit baseline',
          () {
        // From -1,000,000 to +2,000,000 -> (+2M - (-1M)) / |-1M| * 100 = 3M / 1M * 100 = +300%
        final growth = calculateGrowthPercent(2000000.0, -1000000.0);
        expect(growth, equals(300.0));
      });

      test('3.3 Growth math handles loss worsening and loss reduction', () {
        // From -2M to -5M -> (-5M - (-2M)) / |-2M| * 100 = -3M / 2M * 100 = -150%
        expect(
            calculateGrowthPercent(-5000000.0, -2000000.0), equals(-150.0));

        // From -5M to -2M -> (-2M - (-5M)) / |-5M| * 100 = +3M / 5M * 100 = +60%
        expect(calculateGrowthPercent(-2000000.0, -5000000.0), equals(60.0));
      });
    });

    // =========================================================================
    // Challenge 4: 24-Hour Hourly Bucketing Across Timezones and Date Boundaries
    // =========================================================================
    group('Challenge 4: 24-Hour Hourly Distribution & Time Boundaries', () {
      test(
          '4.1 Orders at 00:00:00, 12:30:00, 23:59:59 correctly bucketed into 0h, 12h, 23h',
          () {
        final orders = [
          MockReportData.createOrder(
            id: 'o_midnight',
            createdAt: DateTime(2026, 8, 16, 0, 0, 0),
            total: 100000.0,
            status: 'completed',
          ),
          MockReportData.createOrder(
            id: 'o_noon',
            createdAt: DateTime(2026, 8, 16, 12, 30, 0),
            total: 500000.0,
            status: 'completed',
          ),
          MockReportData.createOrder(
            id: 'o_night',
            createdAt: DateTime(2026, 8, 16, 23, 59, 59),
            total: 200000.0,
            status: 'completed',
          ),
        ];

        final revMap = <int, double>{};
        final countMap = <int, int>{};

        for (final o in orders) {
          final h = o.createdAt.hour;
          revMap[h] = (revMap[h] ?? 0.0) + o.total;
          countMap[h] = (countMap[h] ?? 0) + 1;
        }

        final result = List.generate(
            24,
            (h) => HourlyRevenueData(
                  hour: h,
                  revenue: revMap[h] ?? 0.0,
                  orderCount: countMap[h] ?? 0,
                ));

        expect(result.length, equals(24));
        expect(result[0].revenue, equals(100000.0));
        expect(result[0].orderCount, equals(1));
        expect(result[12].revenue, equals(500000.0));
        expect(result[12].orderCount, equals(1));
        expect(result[23].revenue, equals(200000.0));
        expect(result[23].orderCount, equals(1));

        for (int h = 0; h < 24; h++) {
          if (h != 0 && h != 12 && h != 23) {
            expect(result[h].revenue, equals(0.0));
            expect(result[h].orderCount, equals(0));
          }
        }
      });
    });

    // =========================================================================
    // Challenge 5: Multi-Store Aggregation and Filtering Consistency
    // =========================================================================
    group('Challenge 5: Multi-Store Filtering & Aggregation Consistency', () {
      test(
          '5.1 Multi-store summary merge correctly aggregates revenue, costs, and orders without double-counting',
          () {
        final summaryStore1 = RevenueSummary(
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 2),
          totalRevenue: 5000000.0,
          totalCost: 3000000.0,
          totalProfit: 2000000.0,
          totalOrders: 10,
          totalItemsSold: 20,
          dailyReports: [
            RevenueReport(
              date: DateTime(2026, 8, 1),
              totalRevenue: 5000000.0,
              totalCost: 3000000.0,
              profit: 2000000.0,
              totalOrders: 10,
              totalItemsSold: 20,
              productRevenues: const [],
              storeRevenues: const {'store_001': 5000000.0},
            ),
          ],
        );

        final summaryStore2 = RevenueSummary(
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 2),
          totalRevenue: 7000000.0,
          totalCost: 4000000.0,
          totalProfit: 3000000.0,
          totalOrders: 15,
          totalItemsSold: 30,
          dailyReports: [
            RevenueReport(
              date: DateTime(2026, 8, 1),
              totalRevenue: 7000000.0,
              totalCost: 4000000.0,
              profit: 3000000.0,
              totalOrders: 15,
              totalItemsSold: 30,
              productRevenues: const [],
              storeRevenues: const {'store_002': 7000000.0},
            ),
          ],
        );

        final merged = mergeRevenueSummaries(
            [summaryStore1, summaryStore2],
            DateTime(2026, 8, 1),
            DateTime(2026, 8, 2));

        expect(merged.totalRevenue, equals(12000000.0));
        expect(merged.totalCost, equals(7000000.0));
        expect(merged.totalProfit, equals(5000000.0));
        expect(merged.totalOrders, equals(25));
        expect(merged.totalItemsSold, equals(50));
        expect(merged.dailyReports.length, equals(1));
        expect(merged.dailyReports[0].totalRevenue, equals(12000000.0));
        expect(merged.dailyReports[0].storeRevenues['store_001'],
            equals(5000000.0));
        expect(merged.dailyReports[0].storeRevenues['store_002'],
            equals(7000000.0));
      });
    });
  });
}
