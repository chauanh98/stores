import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/domain/entities/overview_kpis.dart';

void main() {
  group('Overview Domain Entities Tests', () {
    test('OverviewKPIs initialization and calculated getters', () {
      const kpis = OverviewKPIs(
        netRevenue: 1000000.0,
        orderCount: 10,
        grossProfit: 400000.0,
        returnGoodsValue: 50000.0,
        aov: 100000.0,
        revenueGrowthPercent: 25.0,
        orderCountGrowthPercent: -10.0,
        profitGrowthPercent: 15.0,
        aovGrowthPercent: 38.89,
        customerDebt: 150000.0,
        previousRevenue: 800000.0,
        previousOrders: 11,
        previousProfit: 347826.0,
        previousAov: 72727.27,
      );

      expect(kpis.netRevenue, equals(1000000.0));
      expect(kpis.orderCount, equals(10));
      expect(kpis.grossProfit, equals(400000.0));
      expect(kpis.returnGoodsValue, equals(50000.0));
      expect(kpis.aov, equals(100000.0));
      expect(kpis.grossMarginPercent, equals(40.0));
      expect(kpis.isRevenueGrowthPositive, isTrue);
      expect(kpis.isOrderCountGrowthPositive, isFalse);
      expect(kpis.isProfitGrowthPositive, isTrue);
      expect(kpis.isAovGrowthPositive, isTrue);
    });

    test('OverviewKPIs empty instance', () {
      const empty = OverviewKPIs.empty;
      expect(empty.netRevenue, equals(0.0));
      expect(empty.orderCount, equals(0));
      expect(empty.grossProfit, equals(0.0));
      expect(empty.grossMarginPercent, equals(0.0));
      expect(empty.aov, equals(0.0));
    });

    test('HourlyRevenueData properties and labels', () {
      const data8 = HourlyRevenueData(
        hour: 8,
        revenue: 500000.0,
        orderCount: 4,
        branchRevenue: {'branch_1': 300000.0, 'branch_2': 200000.0},
      );

      expect(data8.hour, equals(8));
      expect(data8.hourLabel, equals('08:00'));
      expect(data8.shortLabel, equals('8h'));
      expect(data8.revenue, equals(500000.0));
      expect(data8.orderCount, equals(4));
      expect(data8.branchRevenue['branch_1'], equals(300000.0));
    });

    test('PaymentBreakdown percentages and empty state', () {
      const breakdown = PaymentBreakdown(
        cashAmount: 500000.0,
        transferAmount: 300000.0,
        debtAmount: 200000.0,
        totalAmount: 1000000.0,
      );

      expect(breakdown.cashPercentage, equals(50.0));
      expect(breakdown.transferPercentage, equals(30.0));
      expect(breakdown.debtPercentage, equals(20.0));

      const empty = PaymentBreakdown.empty;
      expect(empty.cashPercentage, equals(0.0));
      expect(empty.transferPercentage, equals(0.0));
      expect(empty.debtPercentage, equals(0.0));
    });

    test('CategoryRevenueShare properties', () {
      const catShare = CategoryRevenueShare(
        categoryName: 'Điện thoại & Phụ kiện',
        revenue: 2500000.0,
        percentage: 62.5,
        quantitySold: 15,
      );

      expect(catShare.categoryName, equals('Điện thoại & Phụ kiện'));
      expect(catShare.revenue, equals(2500000.0));
      expect(catShare.percentage, equals(62.5));
      expect(catShare.quantitySold, equals(15));
    });

    test('StockAlertSummary properties and empty state', () {
      const stockSummary = StockAlertSummary(
        outOfStockCount: 3,
        lowStockCount: 7,
        totalItemCount: 142,
        totalInventoryCost: 35000000.0,
        outOfStockProductIds: ['p1', 'p2', 'p3'],
        lowStockProductIds: ['p4', 'p5'],
      );

      expect(stockSummary.outOfStockCount, equals(3));
      expect(stockSummary.lowStockCount, equals(7));
      expect(stockSummary.totalItemCount, equals(142));
      expect(stockSummary.totalInventoryCost, equals(35000000.0));
      expect(stockSummary.outOfStockProductIds.length, equals(3));
      expect(stockSummary.lowStockProductIds.length, equals(2));

      const empty = StockAlertSummary.empty;
      expect(empty.outOfStockCount, equals(0));
      expect(empty.lowStockCount, equals(0));
      expect(empty.totalItemCount, equals(0));
      expect(empty.totalInventoryCost, equals(0.0));
    });

    test('ProductRankingItem and CustomerRankingItem properties', () {
      const prodRank = ProductRankingItem(
        productId: 'prod_1',
        productName: 'Tai nghe Bluetooth Pro',
        quantity: 24,
        revenue: 7200000.0,
        categoryName: 'Phụ kiện',
        imageUrl: 'https://example.com/item.jpg',
      );

      expect(prodRank.productId, equals('prod_1'));
      expect(prodRank.productName, equals('Tai nghe Bluetooth Pro'));
      expect(prodRank.quantity, equals(24));
      expect(prodRank.revenue, equals(7200000.0));
      expect(prodRank.categoryName, equals('Phụ kiện'));

      const custRank = CustomerRankingItem(
        customerId: 'cust_1',
        customerName: 'Nguyễn Văn A',
        totalSpent: 15400000.0,
        orderCount: 6,
        phoneNumber: '0901234567',
      );

      expect(custRank.customerId, equals('cust_1'));
      expect(custRank.customerName, equals('Nguyễn Văn A'));
      expect(custRank.totalSpent, equals(15400000.0));
      expect(custRank.orderCount, equals(6));
      expect(custRank.phoneNumber, equals('0901234567'));
    });
  });

  group('Growth Calculation Math Tests', () {
    test('calculateGrowthPercent edge cases', () {
      // Both zero
      expect(calculateGrowthPercent(0.0, 0.0), equals(0.0));

      // Prior zero, current positive -> 100%
      expect(calculateGrowthPercent(500.0, 0.0), equals(100.0));

      // Prior positive, current zero -> -100%
      expect(calculateGrowthPercent(0.0, 500.0), equals(-100.0));

      // Standard increase: 100k -> 150k = +50%
      expect(calculateGrowthPercent(150000.0, 100000.0), equals(50.0));

      // Standard decrease: 200k -> 150k = -25%
      expect(calculateGrowthPercent(150000.0, 200000.0), equals(-25.0));

      // No change: 100k -> 100k = 0%
      expect(calculateGrowthPercent(100000.0, 100000.0), equals(0.0));
    });
  });
}
