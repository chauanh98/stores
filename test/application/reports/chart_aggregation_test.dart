import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/revenue_report.dart';

RevenueReport _createReport({
  required DateTime date,
  required double totalRevenue,
  required double totalCost,
  double? profit,
  int totalOrders = 1,
  int totalItemsSold = 1,
  Map<String, double> storeRevenues = const {},
}) {
  return RevenueReport(
    date: date,
    totalRevenue: totalRevenue,
    totalCost: totalCost,
    profit: profit ?? (totalRevenue - totalCost),
    totalOrders: totalOrders,
    totalItemsSold: totalItemsSold,
    productRevenues: const [],
    storeRevenues: storeRevenues,
  );
}

void main() {
  group('Smart Chart Aggregation Interval Classification Tests (R3)', () {
    test('Classifies <= 1 day as hourly', () {
      final today = DateTime(2026, 8, 16);
      final singleDayRange = DateTimeRange(
        start: today,
        end: DateTime(2026, 8, 16, 23, 59, 59),
      );

      final interval = getChartAggregationInterval(singleDayRange);
      expect(interval, equals(ChartAggregationInterval.hourly));
      expect(interval.isHourly, isTrue);
      expect(interval.isDaily, isFalse);
      expect(interval.isWeekly, isFalse);
      expect(interval.isMonthly, isFalse);
    });

    test('Classifies 2..31 days as daily', () {
      // 7 days
      final range7d = DateTimeRange(
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 16),
      );
      expect(getChartAggregationInterval(range7d),
          equals(ChartAggregationInterval.daily));

      // 30 days
      final range30d = DateTimeRange(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 30),
      );
      expect(getChartAggregationInterval(range30d),
          equals(ChartAggregationInterval.daily));

      // 31 days
      final range31d = DateTimeRange(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 31),
      );
      expect(getChartAggregationInterval(range31d),
          equals(ChartAggregationInterval.daily));
    });

    test('Classifies 32..60 days as weekly', () {
      // 32 days
      final range32d = DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 8, 1),
      );
      expect(getChartAggregationInterval(range32d),
          equals(ChartAggregationInterval.weekly));

      // 45 days
      final range45d = DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 8, 14),
      );
      expect(getChartAggregationInterval(range45d),
          equals(ChartAggregationInterval.weekly));

      // 60 days
      final range60d = DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 8, 29),
      );
      expect(getChartAggregationInterval(range60d),
          equals(ChartAggregationInterval.weekly));
    });

    test('Classifies > 60 days as monthly', () {
      // 61 days
      final range61d = DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 8, 30),
      );
      expect(getChartAggregationInterval(range61d),
          equals(ChartAggregationInterval.monthly));

      // 90 days (3 months)
      final range90d = DateTimeRange(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 8, 29),
      );
      expect(getChartAggregationInterval(range90d),
          equals(ChartAggregationInterval.monthly));

      // 365 days (1 year)
      final range365d = DateTimeRange(
        start: DateTime(2025, 8, 17),
        end: DateTime(2026, 8, 16),
      );
      expect(getChartAggregationInterval(range365d),
          equals(ChartAggregationInterval.monthly));
    });
  });

  group('aggregateRevenueReports Function Tests (R3)', () {
    test('Returns empty list when dailyReports is empty', () {
      final range = DateTimeRange(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 15),
      );
      final result =
          aggregateRevenueReports(dailyReports: <RevenueReport>[], range: range);
      expect(result, isEmpty);
    });

    test('Returns empty list for hourly interval (<= 1 day)', () {
      final range = DateTimeRange(
        start: DateTime(2026, 8, 16),
        end: DateTime(2026, 8, 16),
      );
      final reports = [
        _createReport(
          date: DateTime(2026, 8, 16),
          totalRevenue: 1000000,
          totalCost: 600000,
          totalOrders: 5,
        ),
      ];
      final result =
          aggregateRevenueReports(dailyReports: reports, range: range);
      expect(result, isEmpty);
    });

    test('Maps daily reports accurately for 2..31 days interval', () {
      final range = DateTimeRange(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 3),
      );
      final reports = [
        _createReport(
          date: DateTime(2026, 8, 1),
          totalRevenue: 1000000,
          totalCost: 600000,
          profit: 400000,
          totalOrders: 5,
          totalItemsSold: 12,
          storeRevenues: {'store_001': 700000, 'store_002': 300000},
        ),
        _createReport(
          date: DateTime(2026, 8, 2),
          totalRevenue: 2000000,
          totalCost: 1200000,
          profit: 800000,
          totalOrders: 8,
          totalItemsSold: 20,
          storeRevenues: {'store_001': 1200000, 'store_002': 800000},
        ),
        _createReport(
          date: DateTime(2026, 8, 3),
          totalRevenue: 1500000,
          totalCost: 900000,
          profit: 600000,
          totalOrders: 6,
          totalItemsSold: 15,
          storeRevenues: {'store_001': 1500000},
        ),
      ];

      final buckets =
          aggregateRevenueReports(dailyReports: reports, range: range);

      expect(buckets.length, equals(3));
      expect(buckets[0].label, equals('01/08'));
      expect(buckets[0].fullLabel, equals('01/08/2026'));
      expect(buckets[0].totalRevenue, equals(1000000));
      expect(buckets[0].profit, equals(400000));
      expect(buckets[0].totalOrders, equals(5));
      expect(buckets[0].totalItemsSold, equals(12));
      expect(buckets[0].storeRevenues['store_001'], equals(700000));
      expect(buckets[0].storeRevenues['store_002'], equals(300000));

      expect(buckets[1].label, equals('02/08'));
      expect(buckets[1].fullLabel, equals('02/08/2026'));
      expect(buckets[1].totalRevenue, equals(2000000));

      expect(buckets[2].label, equals('03/08'));
      expect(buckets[2].fullLabel, equals('03/08/2026'));
      expect(buckets[2].totalRevenue, equals(1500000));
    });

    test('Aggregates by calendar weeks for 32..60 days interval', () {
      final range = DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 8, 14), // 45 days
      );

      final reports = [
        // July Week 1 (Days 1..7)
        _createReport(
          date: DateTime(2026, 7, 2),
          totalRevenue: 1000000,
          totalCost: 600000,
          profit: 400000,
          totalOrders: 4,
          storeRevenues: {'s1': 600000, 's2': 400000},
        ),
        _createReport(
          date: DateTime(2026, 7, 5),
          totalRevenue: 2000000,
          totalCost: 1000000,
          profit: 1000000,
          totalOrders: 6,
          storeRevenues: {'s1': 1000000, 's2': 1000000},
        ),
        // July Week 2 (Days 8..14)
        _createReport(
          date: DateTime(2026, 7, 10),
          totalRevenue: 3000000,
          totalCost: 1800000,
          profit: 1200000,
          totalOrders: 10,
          storeRevenues: {'s1': 2000000, 's2': 1000000},
        ),
        // August Week 1 (Days 1..7)
        _createReport(
          date: DateTime(2026, 8, 3),
          totalRevenue: 4000000,
          totalCost: 2000000,
          profit: 2000000,
          totalOrders: 12,
          storeRevenues: {'s1': 2500000, 's2': 1500000},
        ),
      ];

      final buckets =
          aggregateRevenueReports(dailyReports: reports, range: range);

      expect(buckets.length, equals(3));

      // 1. July Week 1
      expect(buckets[0].label, equals('T1 Th07'));
      expect(buckets[0].fullLabel, equals('Tuần 1 - Tháng 07/2026'));
      expect(buckets[0].totalRevenue, equals(3000000));
      expect(buckets[0].totalCost, equals(1600000));
      expect(buckets[0].profit, equals(1400000));
      expect(buckets[0].totalOrders, equals(10));
      expect(buckets[0].storeRevenues['s1'], equals(1600000));
      expect(buckets[0].storeRevenues['s2'], equals(1400000));

      // 2. July Week 2
      expect(buckets[1].label, equals('T2 Th07'));
      expect(buckets[1].fullLabel, equals('Tuần 2 - Tháng 07/2026'));
      expect(buckets[1].totalRevenue, equals(3000000));
      expect(buckets[1].totalOrders, equals(10));

      // 3. August Week 1
      expect(buckets[2].label, equals('T1 Th08'));
      expect(buckets[2].fullLabel, equals('Tuần 1 - Tháng 08/2026'));
      expect(buckets[2].totalRevenue, equals(4000000));
      expect(buckets[2].totalOrders, equals(12));
      expect(buckets[2].storeRevenues['s1'], equals(2500000));
      expect(buckets[2].storeRevenues['s2'], equals(1500000));
    });

    test('Aggregates by calendar months for > 60 days interval', () {
      final range = DateTimeRange(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 8, 16), // > 100 days
      );

      final reports = [
        // May
        _createReport(
          date: DateTime(2026, 5, 10),
          totalRevenue: 10000000,
          totalCost: 6000000,
          profit: 4000000,
          totalOrders: 30,
          storeRevenues: {'s1': 6000000, 's2': 4000000},
        ),
        _createReport(
          date: DateTime(2026, 5, 25),
          totalRevenue: 5000000,
          totalCost: 3000000,
          profit: 2000000,
          totalOrders: 15,
          storeRevenues: {'s1': 3000000, 's2': 2000000},
        ),
        // June
        _createReport(
          date: DateTime(2026, 6, 15),
          totalRevenue: 20000000,
          totalCost: 12000000,
          profit: 8000000,
          totalOrders: 60,
          storeRevenues: {'s1': 12000000, 's2': 8000000},
        ),
        // July
        _createReport(
          date: DateTime(2026, 7, 20),
          totalRevenue: 25000000,
          totalCost: 15000000,
          profit: 10000000,
          totalOrders: 75,
          storeRevenues: {'s1': 15000000, 's2': 10000000},
        ),
        // August
        _createReport(
          date: DateTime(2026, 8, 12),
          totalRevenue: 30000000,
          totalCost: 18000000,
          profit: 12000000,
          totalOrders: 90,
          storeRevenues: {'s1': 18000000, 's2': 12000000},
        ),
      ];

      final buckets =
          aggregateRevenueReports(dailyReports: reports, range: range);

      expect(buckets.length, equals(4));

      // May
      expect(buckets[0].label, equals('Th05'));
      expect(buckets[0].fullLabel, equals('Tháng 05/2026'));
      expect(buckets[0].totalRevenue, equals(15000000));
      expect(buckets[0].profit, equals(6000000));
      expect(buckets[0].totalOrders, equals(45));
      expect(buckets[0].storeRevenues['s1'], equals(9000000));
      expect(buckets[0].storeRevenues['s2'], equals(6000000));

      // June
      expect(buckets[1].label, equals('Th06'));
      expect(buckets[1].fullLabel, equals('Tháng 06/2026'));
      expect(buckets[1].totalRevenue, equals(20000000));
      expect(buckets[1].totalOrders, equals(60));

      // July
      expect(buckets[2].label, equals('Th07'));
      expect(buckets[2].fullLabel, equals('Tháng 07/2026'));
      expect(buckets[2].totalRevenue, equals(25000000));
      expect(buckets[2].totalOrders, equals(75));

      // August
      expect(buckets[3].label, equals('Th08'));
      expect(buckets[3].fullLabel, equals('Tháng 08/2026'));
      expect(buckets[3].totalRevenue, equals(30000000));
      expect(buckets[3].totalOrders, equals(90));
    });
  });
}
