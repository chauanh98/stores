import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/revenue_report.dart';

import '../../fixtures/mock_report_data.dart';

void main() {
  group('OverviewKPIs - Business KPIs & Formulas (R1)', () {
    // Helper function calculating KPIs from raw orders, products, debts
    OverviewKPIs calculateKPIs({
      required List<Order> orders,
      required List<Product> products,
      List<CustomerDebtTransaction> debtTxs = const [],
      double returnGoodsValue = 0.0,
      double priorRevenue = 0.0,
      int priorOrders = 0,
      double priorProfit = 0.0,
    }) {
      final completedOrders =
          orders.where((o) => o.status == 'completed').toList();

      final int orderCount = completedOrders.length;
      final double netRevenue =
          completedOrders.fold<double>(0.0, (sum, o) => sum + o.netPayable);

      // Cost price lookup map
      final costMap = {for (var p in products) p.id: p.costPrice};

      double totalCost = 0.0;
      for (final order in completedOrders) {
        for (final item in order.items) {
          final unitCost = costMap[item.productId] ?? (item.price * 0.7);
          totalCost += unitCost * item.quantity;
        }
      }

      final double grossProfit = netRevenue - totalCost;
      final double aov = orderCount > 0 ? netRevenue / orderCount : 0.0;

      // Growth calculations vs prior period
      final double revenueGrowth = priorRevenue > 0
          ? ((netRevenue - priorRevenue) / priorRevenue) * 100
          : (netRevenue > 0 ? 100.0 : 0.0);

      final double orderGrowth = priorOrders > 0
          ? ((orderCount - priorOrders) / priorOrders) * 100
          : (orderCount > 0 ? 100.0 : 0.0);

      final double profitGrowth = priorProfit != 0
          ? ((grossProfit - priorProfit) / priorProfit.abs()) * 100
          : (grossProfit > 0 ? 100.0 : 0.0);

      // Customer debt total
      final double customerDebt =
          debtTxs.fold<double>(0.0, (sum, tx) => sum + tx.remainingDebt);

      return OverviewKPIs(
        netRevenue: netRevenue,
        orderCount: orderCount,
        grossProfit: grossProfit,
        returnGoodsValue: returnGoodsValue,
        aov: aov,
        revenueGrowthPercent: revenueGrowth,
        orderCountGrowthPercent: orderGrowth,
        profitGrowthPercent: profitGrowth,
        customerDebt: customerDebt,
      );
    }

    group('Tier 1: Feature Coverage (R1 KPIs)', () {
      test('1.1 Computes net revenue accurately from completed orders', () {
        final orders = [
          MockReportData.createOrder(
            id: 'ord_1',
            total: 500000.0,
            status: 'completed',
          ),
          MockReportData.createOrder(
            id: 'ord_2',
            total: 750000.0,
            status: 'completed',
          ),
          MockReportData.createOrder(
            id: 'ord_3',
            total: 250000.0,
            status: 'completed',
          ),
        ];

        final kpis = calculateKPIs(orders: orders, products: []);
        expect(kpis.netRevenue, equals(1500000.0));
      });

      test('1.2 Counts only completed orders for orderCount', () {
        final orders = [
          MockReportData.createOrder(id: 'ord_1', status: 'completed'),
          MockReportData.createOrder(id: 'ord_2', status: 'completed'),
          MockReportData.createOrder(id: 'ord_3', status: 'draft'),
          MockReportData.createOrder(id: 'ord_4', status: 'cancelled'),
        ];

        final kpis = calculateKPIs(orders: orders, products: []);
        expect(kpis.orderCount, equals(2));
      });

      test('1.3 Calculates gross profit as Revenue minus COGS', () {
        final productA = MockReportData.createProduct(
          id: 'prod_A',
          price: 200000.0,
          costPrice: 120000.0,
        );
        final productB = MockReportData.createProduct(
          id: 'prod_B',
          price: 300000.0,
          costPrice: 180000.0,
        );

        final order = MockReportData.createOrder(
          id: 'ord_1',
          items: [
            MockReportData.createOrderItem(
              productId: 'prod_A',
              quantity: 2,
              price: 200000.0,
            ), // Rev: 400k, Cost: 240k
            MockReportData.createOrderItem(
              productId: 'prod_B',
              quantity: 1,
              price: 300000.0,
            ), // Rev: 300k, Cost: 180k
          ],
          total: 700000.0,
        );

        final kpis =
            calculateKPIs(orders: [order], products: [productA, productB]);
        expect(kpis.netRevenue, equals(700000.0));
        // Total cost = 240k + 180k = 420k. Gross profit = 700k - 420k = 280k
        expect(kpis.grossProfit, equals(280000.0));
      });

      test('1.4 Calculates Average Order Value (AOV = netRevenue / orderCount)',
          () {
        final orders = [
          MockReportData.createOrder(id: 'ord_1', total: 300000.0),
          MockReportData.createOrder(id: 'ord_2', total: 600000.0),
          MockReportData.createOrder(id: 'ord_3', total: 900000.0),
        ];

        final kpis = calculateKPIs(orders: orders, products: []);
        expect(kpis.netRevenue, equals(1800000.0));
        expect(kpis.orderCount, equals(3));
        expect(kpis.aov, equals(600000.0));
      });

      test('1.5 Correctly tracks return goods value and customer debt', () {
        final debtTxs = [
          MockReportData.createDebtTransaction(
            id: 'd1',
            customerId: 'c1',
            remainingDebt: 1500000.0,
          ),
          MockReportData.createDebtTransaction(
            id: 'd2',
            customerId: 'c2',
            remainingDebt: 2500000.0,
          ),
        ];

        final kpis = calculateKPIs(
          orders: [],
          products: [],
          debtTxs: debtTxs,
          returnGoodsValue: 350000.0,
        );

        expect(kpis.returnGoodsValue, equals(350000.0));
        expect(kpis.customerDebt, equals(4000000.0));
      });
    });

    group('Tier 2: Boundary & Corner Cases', () {
      test('2.1 Zero orders results in AOV = 0.0 without division by zero', () {
        final kpis = calculateKPIs(orders: [], products: []);
        expect(kpis.orderCount, equals(0));
        expect(kpis.netRevenue, equals(0.0));
        expect(kpis.aov, equals(0.0));
        expect(kpis.aov.isFinite, isTrue);
        expect(kpis.aov.isNaN, isFalse);
      });

      test('2.2 Zero revenue with 0-value promotion orders', () {
        final orders = [
          MockReportData.createOrder(
            id: 'ord_free_1',
            total: 0.0,
            status: 'completed',
          ),
          MockReportData.createOrder(
            id: 'ord_free_2',
            total: 0.0,
            status: 'completed',
          ),
        ];

        final kpis = calculateKPIs(orders: orders, products: []);
        expect(kpis.orderCount, equals(2));
        expect(kpis.netRevenue, equals(0.0));
        expect(kpis.aov, equals(0.0));
      });

      test('2.3 Negative profit when COGS exceeds revenue (loss-leader)', () {
        final productCostHeavy = MockReportData.createProduct(
          id: 'prod_loss',
          price: 100000.0,
          costPrice: 150000.0,
        );

        final order = MockReportData.createOrder(
          id: 'ord_loss_1',
          items: [
            MockReportData.createOrderItem(
              productId: 'prod_loss',
              quantity: 2,
              price: 100000.0,
            ),
          ],
          total: 200000.0,
        );

        final kpis = calculateKPIs(
          orders: [order],
          products: [productCostHeavy],
        );

        expect(kpis.netRevenue, equals(200000.0));
        // Cost = 2 * 150k = 300k. Profit = 200k - 300k = -100k
        expect(kpis.grossProfit, equals(-100000.0));
      });

      test('2.4 Handles negative customer remaining debt (customer overpayment)',
          () {
        final debtTxs = [
          MockReportData.createDebtTransaction(
            id: 'd1',
            customerId: 'c1',
            remainingDebt: -200000.0, // Credit balance / overpaid
          ),
          MockReportData.createDebtTransaction(
            id: 'd2',
            customerId: 'c2',
            remainingDebt: 500000.0,
          ),
        ];

        final kpis = calculateKPIs(
          orders: [],
          products: [],
          debtTxs: debtTxs,
        );

        expect(kpis.customerDebt, equals(300000.0));
      });

      test('2.5 Large financial values (multi-billion VND) maintain precision',
          () {
        final orders = [
          MockReportData.createOrder(
            id: 'ord_huge_1',
            total: 2500000000.0, // 2.5 Billion
          ),
          MockReportData.createOrder(
            id: 'ord_huge_2',
            total: 3500000000.0, // 3.5 Billion
          ),
        ];

        final kpis = calculateKPIs(orders: orders, products: []);
        expect(kpis.netRevenue, equals(6000000000.0));
        expect(kpis.orderCount, equals(2));
        expect(kpis.aov, equals(3000000000.0));
      });
    });

    group('Tier 3: Combinatorial & Cross-Feature Filtering', () {
      test('3.1 Filters by store/branch accurately', () {
        // Orders created by different stores
        final orderBranch1 = MockReportData.createOrder(
          id: 'ord_b1',
          total: 1000000.0,
          createdBy: 'store_001',
        );
        final orderBranch2 = MockReportData.createOrder(
          id: 'ord_b2',
          total: 2000000.0,
          createdBy: 'store_002',
        );

        // Filter Store 1
        final kpisStore1 = calculateKPIs(
          orders: [orderBranch1],
          products: [],
        );
        expect(kpisStore1.netRevenue, equals(1000000.0));
        expect(kpisStore1.orderCount, equals(1));

        // Filter All Stores
        final kpisAllStores = calculateKPIs(
          orders: [orderBranch1, orderBranch2],
          products: [],
        );
        expect(kpisAllStores.netRevenue, equals(3000000.0));
        expect(kpisAllStores.orderCount, equals(2));
      });

      test('3.2 Disregards non-completed order statuses completely', () {
        final mixedOrders = [
          MockReportData.createOrder(
              id: 'o1', total: 500000.0, status: 'completed'),
          MockReportData.createOrder(
              id: 'o2', total: 300000.0, status: 'draft'),
          MockReportData.createOrder(
              id: 'o3', total: 700000.0, status: 'cancelled'),
          MockReportData.createOrder(
              id: 'o4', total: 400000.0, status: 'completed'),
        ];

        final kpis = calculateKPIs(orders: mixedOrders, products: []);
        expect(kpis.netRevenue, equals(900000.0));
        expect(kpis.orderCount, equals(2));
        expect(kpis.aov, equals(450000.0));
      });
    });

    group('Tier 4: Realistic Business Scenario', () {
      test(
          '4.1 Full realistic business day with 10 orders, returns, and debt transactions',
          () {
        final catalog = MockReportData.sampleProductCatalog();
        final customers = MockReportData.sampleCustomerList();

        final realisticOrders = [
          MockReportData.createOrder(
            id: 'ord_01',
            customerId: customers[0].id,
            items: [
              MockReportData.createOrderItem(
                productId: 'p_fashion_1',
                quantity: 2,
                price: 250000.0,
              ), // 500k
            ],
            total: 500000.0,
            status: 'completed',
          ),
          MockReportData.createOrder(
            id: 'ord_02',
            customerId: customers[1].id,
            items: [
              MockReportData.createOrderItem(
                productId: 'p_tech_1',
                quantity: 3,
                price: 120000.0,
              ), // 360k
            ],
            total: 360000.0,
            status: 'completed',
          ),
          MockReportData.createOrder(
            id: 'ord_03',
            customerId: customers[2].id,
            items: [
              MockReportData.createOrderItem(
                productId: 'p_fashion_2',
                quantity: 1,
                price: 450000.0,
              ), // 450k
            ],
            total: 450000.0,
            status: 'completed',
          ),
          MockReportData.createOrder(
            id: 'ord_04_cancelled',
            customerId: customers[3].id,
            items: [
              MockReportData.createOrderItem(
                productId: 'p_tech_2',
                quantity: 1,
                price: 650000.0,
              ),
            ],
            total: 650000.0,
            status: 'cancelled',
          ),
        ];

        final debtTxs = [
          MockReportData.createDebtTransaction(
            id: 'debt_1',
            customerId: customers[1].id,
            remainingDebt: 3500000.0,
          ),
        ];

        final kpis = calculateKPIs(
          orders: realisticOrders,
          products: catalog,
          debtTxs: debtTxs,
          returnGoodsValue: 120000.0,
          priorRevenue: 1000000.0,
          priorOrders: 2,
          priorProfit: 400000.0,
        );

        // Expected Revenue: 500k + 360k + 450k = 1,310,000
        expect(kpis.netRevenue, equals(1310000.0));
        // Expected Order Count: 3
        expect(kpis.orderCount, equals(3));
        // Expected AOV: 1,310,000 / 3 = 436,666.666...
        expect(kpis.aov, closeTo(436666.67, 0.01));

        // Expected Cost:
        // p_fashion_1 cost = 150k * 2 = 300k
        // p_tech_1 cost = 60k * 3 = 180k
        // p_fashion_2 cost = 280k * 1 = 280k
        // Total cost = 760k. Gross profit = 1,310,000 - 760,000 = 550,000
        expect(kpis.grossProfit, equals(550000.0));

        // Growth vs Prior:
        // Revenue Growth = (1,310,000 - 1,000,000) / 1,000,000 * 100 = +31.0%
        expect(kpis.revenueGrowthPercent, closeTo(31.0, 0.01));
        // Order Growth = (3 - 2) / 2 * 100 = +50.0%
        expect(kpis.orderCountGrowthPercent, equals(50.0));
        // Profit Growth = (550,000 - 400,000) / 400,000 * 100 = +37.5%
        expect(kpis.profitGrowthPercent, closeTo(37.5, 0.01));

        // Return goods & debt
        expect(kpis.returnGoodsValue, equals(120000.0));
        expect(kpis.customerDebt, equals(3500000.0));
      });
    });

    group('Riverpod Providers Integration (overview_kpi_providers.dart)', () {
      test('ProviderContainer reads current and prior date ranges correctly', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final currentRange =
            container.read(overviewCurrentDateRangeProvider);
        final priorRange =
            container.read(overviewPriorPeriodDateRangeProvider);

        expect(currentRange, isNotNull);
        expect(priorRange, isNotNull);
        expect(currentRange.start.isAfter(priorRange.start), isTrue);
      });

      test('calculateGrowthPercent helper matches domain expectations', () {
        expect(calculateGrowthPercent(100.0, 50.0), equals(100.0));
        expect(calculateGrowthPercent(50.0, 100.0), equals(-50.0));
        expect(calculateGrowthPercent(0.0, 0.0), equals(0.0));
        expect(calculateGrowthPercent(100.0, 0.0), equals(100.0));
        expect(calculateGrowthPercent(0.0, 100.0), equals(-100.0));
      });

      test('overviewKPIsProvider computes net revenue and profit using netPayable for discounted orders', () async {
        final currentRange = DateTimeRange(
          start: DateTime(2026, 9, 21),
          end: DateTime(2026, 9, 21, 23, 59, 59, 999),
        );

        final currentSummary = RevenueSummary(
          startDate: currentRange.start,
          endDate: currentRange.end,
          totalRevenue: 2000000.0, // net after discount
          totalCost: 1200000.0,
          totalProfit: 800000.0,
          totalOrders: 1,
          totalItemsSold: 2,
          dailyReports: const [],
        );

        final container = ProviderContainer(
          overrides: [
            overviewCurrentDateRangeProvider.overrideWithValue(currentRange),
            revenueByDateRangeProvider(currentRange).overrideWith(
              (ref) => Stream.value(currentSummary),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Await stream completion
        await container.read(revenueByDateRangeProvider(currentRange).future);

        final kpisAsync = container.read(overviewKPIsProvider);
        expect(kpisAsync.hasValue, isTrue);
        final kpis = kpisAsync.value!;
        expect(kpis.netRevenue, equals(2000000.0));
        expect(kpis.grossProfit, equals(800000.0));
        expect(kpis.orderCount, equals(1));
      });
    });
  });
}
