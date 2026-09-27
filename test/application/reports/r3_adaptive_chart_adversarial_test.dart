import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/revenue_report.dart';

RevenueReport _makeReport({
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
  group('Empirical Challenge Suite: Requirement R3 Adaptive Chart Aggregation',
      () {
    // =========================================================================
    // 1. INTERVAL BOUNDARY CONDITIONS MATRIX
    // =========================================================================
    group('1. Interval Boundary Conditions (Exhaustive Range Matrix)', () {
      test('1 Day: Exact single day (same date 00:00 to 23:59) -> Hourly', () {
        final range = DateTimeRange(
          start: DateTime(2026, 8, 1, 0, 0, 0),
          end: DateTime(2026, 8, 1, 23, 59, 59, 999),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.hourly));
        expect(getChartAggregationInterval(range).isHourly, isTrue);
      });

      test('1 Day: Single day exact point (start == end at midnight) -> Hourly',
          () {
        final range = DateTimeRange(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 1),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.hourly));
      });

      test('2 Days: (2026-08-01 to 2026-08-02) -> Daily', () {
        final range = DateTimeRange(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 2),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.daily));
        expect(getChartAggregationInterval(range).isDaily, isTrue);
      });

      test('7 Days: (2026-08-01 to 2026-08-07) -> Daily', () {
        final range = DateTimeRange(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 7),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.daily));
      });

      test('30 Days: (2026-08-01 to 2026-08-30) -> Daily', () {
        final range = DateTimeRange(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 30),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.daily));
      });

      test(
          '31 Days: (2026-08-01 to 2026-08-31) -> Daily (Boundary Maximum for Daily)',
          () {
        final range = DateTimeRange(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 31),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.daily));
      });

      test(
          '32 Days: (2026-07-01 to 2026-08-01) -> Weekly (Boundary Minimum for Weekly)',
          () {
        // 31 days in July + 1 day in August = 32 days
        final range = DateTimeRange(
          start: DateTime(2026, 7, 1),
          end: DateTime(2026, 8, 1),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.weekly));
        expect(getChartAggregationInterval(range).isWeekly, isTrue);
      });

      test('45 Days: (2026-07-01 to 2026-08-14) -> Weekly', () {
        final range = DateTimeRange(
          start: DateTime(2026, 7, 1),
          end: DateTime(2026, 8, 14),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.weekly));
      });

      test(
          '60 Days: (2026-07-01 to 2026-08-29) -> Weekly (Boundary Maximum for Weekly)',
          () {
        // 31 in July + 29 in August = 60 days
        final range = DateTimeRange(
          start: DateTime(2026, 7, 1),
          end: DateTime(2026, 8, 29),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.weekly));
      });

      test(
          '61 Days: (2026-07-01 to 2026-08-30) -> Monthly (Boundary Minimum for Monthly)',
          () {
        // 31 in July + 30 in August = 61 days
        final range = DateTimeRange(
          start: DateTime(2026, 7, 1),
          end: DateTime(2026, 8, 30),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.monthly));
        expect(getChartAggregationInterval(range).isMonthly, isTrue);
      });

      test('90 Days (3 Months): (2026-06-01 to 2026-08-29) -> Monthly', () {
        final range = DateTimeRange(
          start: DateTime(2026, 6, 1),
          end: DateTime(2026, 8, 29),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.monthly));
      });

      test('120 Days (4 Months): (2026-05-01 to 2026-08-28) -> Monthly', () {
        final range = DateTimeRange(
          start: DateTime(2026, 5, 1),
          end: DateTime(2026, 8, 28),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.monthly));
      });

      test('365 Days (1 Full Year): (2025-08-17 to 2026-08-16) -> Monthly', () {
        final range = DateTimeRange(
          start: DateTime(2025, 8, 17),
          end: DateTime(2026, 8, 16),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.monthly));
      });

      test('730 Days (2 Years): (2024-08-17 to 2026-08-16) -> Monthly', () {
        final range = DateTimeRange(
          start: DateTime(2024, 8, 17),
          end: DateTime(2026, 8, 16),
        );
        expect(getChartAggregationInterval(range),
            equals(ChartAggregationInterval.monthly));
      });
    });

    // =========================================================================
    // 2. CALENDAR AGGREGATION INTEGRITY
    // =========================================================================
    group(
        '2. Calendar Aggregation Integrity (Transitions, Leap Years, Month-ends)',
        () {
      test('Year Transition (Dec 2025 - Jan 2026) in Monthly Mode (> 60 days)',
          () {
        final range = DateTimeRange(
          start: DateTime(2025, 11, 1),
          end: DateTime(2026, 1, 31), // 92 days
        );

        final reports = [
          _makeReport(
            date: DateTime(2025, 11, 15),
            totalRevenue: 10000000,
            totalCost: 6000000,
            totalOrders: 20,
            storeRevenues: {'s1': 6000000, 's2': 4000000},
          ),
          _makeReport(
            date: DateTime(2025, 12, 20),
            totalRevenue: 20000000,
            totalCost: 12000000,
            totalOrders: 40,
            storeRevenues: {'s1': 12000000, 's2': 8000000},
          ),
          _makeReport(
            date: DateTime(2026, 1, 10),
            totalRevenue: 30000000,
            totalCost: 18000000,
            totalOrders: 60,
            storeRevenues: {'s1': 20000000, 's2': 10000000},
          ),
        ];

        final buckets =
            aggregateRevenueReports(dailyReports: reports, range: range);

        expect(buckets.length, equals(3));

        // Nov 2025
        expect(buckets[0].label, equals('Th11'));
        expect(buckets[0].fullLabel, equals('Tháng 11/2025'));
        expect(buckets[0].startDate, equals(DateTime(2025, 11, 15)));
        expect(buckets[0].totalRevenue, equals(10000000));

        // Dec 2025
        expect(buckets[1].label, equals('Th12'));
        expect(buckets[1].fullLabel, equals('Tháng 12/2025'));
        expect(buckets[1].startDate, equals(DateTime(2025, 12, 20)));
        expect(buckets[1].totalRevenue, equals(20000000));

        // Jan 2026
        expect(buckets[2].label, equals('Th01'));
        expect(buckets[2].fullLabel, equals('Tháng 01/2026'));
        expect(buckets[2].startDate, equals(DateTime(2026, 1, 10)));
        expect(buckets[2].totalRevenue, equals(30000000));
      });

      test(
          'Multi-Year Span (Dec 2024, Dec 2025, Dec 2026) has unique buckets without key collisions',
          () {
        final range = DateTimeRange(
          start: DateTime(2024, 11, 1),
          end: DateTime(2026, 12, 31),
        );

        final reports = [
          _makeReport(
              date: DateTime(2024, 12, 10),
              totalRevenue: 1000000,
              totalCost: 500000),
          _makeReport(
              date: DateTime(2025, 12, 10),
              totalRevenue: 2000000,
              totalCost: 1000000),
          _makeReport(
              date: DateTime(2026, 12, 10),
              totalRevenue: 3000000,
              totalCost: 1500000),
        ];

        final buckets =
            aggregateRevenueReports(dailyReports: reports, range: range);

        expect(buckets.length, equals(3));
        expect(buckets[0].fullLabel, equals('Tháng 12/2024'));
        expect(buckets[0].totalRevenue, equals(1000000));

        expect(buckets[1].fullLabel, equals('Tháng 12/2025'));
        expect(buckets[1].totalRevenue, equals(2000000));

        expect(buckets[2].fullLabel, equals('Tháng 12/2026'));
        expect(buckets[2].totalRevenue, equals(3000000));
      });

      test('Year Transition (Dec 2025 - Jan 2026) in Weekly Mode (32..60 days)',
          () {
        final range = DateTimeRange(
          start: DateTime(2025, 12, 15),
          end: DateTime(2026, 1, 20), // 37 days
        );

        final reports = [
          // Dec Week 3 (15..21)
          _makeReport(
            date: DateTime(2025, 12, 18),
            totalRevenue: 5000000,
            totalCost: 3000000,
            totalOrders: 10,
          ),
          // Dec Week 4 (22..28)
          _makeReport(
            date: DateTime(2025, 12, 25),
            totalRevenue: 8000000,
            totalCost: 4000000,
            totalOrders: 16,
          ),
          // Dec Week 5 (29..31)
          _makeReport(
            date: DateTime(2025, 12, 31),
            totalRevenue: 12000000,
            totalCost: 6000000,
            totalOrders: 25,
          ),
          // Jan Week 1 (1..7)
          _makeReport(
            date: DateTime(2026, 1, 2),
            totalRevenue: 6000000,
            totalCost: 3000000,
            totalOrders: 12,
          ),
          // Jan Week 2 (8..14)
          _makeReport(
            date: DateTime(2026, 1, 10),
            totalRevenue: 9000000,
            totalCost: 4500000,
            totalOrders: 18,
          ),
        ];

        final buckets =
            aggregateRevenueReports(dailyReports: reports, range: range);

        expect(buckets.length, equals(5));

        expect(buckets[0].label, equals('T3 Th12'));
        expect(buckets[0].fullLabel, equals('Tuần 3 - Tháng 12/2025'));
        expect(buckets[0].totalRevenue, equals(5000000));

        expect(buckets[1].label, equals('T4 Th12'));
        expect(buckets[1].fullLabel, equals('Tuần 4 - Tháng 12/2025'));
        expect(buckets[1].totalRevenue, equals(8000000));

        expect(buckets[2].label, equals('T5 Th12'));
        expect(buckets[2].fullLabel, equals('Tuần 5 - Tháng 12/2025'));
        expect(buckets[2].totalRevenue, equals(12000000));

        expect(buckets[3].label, equals('T1 Th01'));
        expect(buckets[3].fullLabel, equals('Tuần 1 - Tháng 01/2026'));
        expect(buckets[3].totalRevenue, equals(6000000));

        expect(buckets[4].label, equals('T2 Th01'));
        expect(buckets[4].fullLabel, equals('Tuần 2 - Tháng 01/2026'));
        expect(buckets[4].totalRevenue, equals(9000000));
      });

      test('Leap Year (2024-02-29) Weekly aggregation maps Day 29 to Week 5',
          () {
        final range = DateTimeRange(
          start: DateTime(2024, 2, 1),
          end: DateTime(2024, 3, 10), // 39 days (Weekly)
        );

        final reports = [
          // Feb 28 (Day 28 -> Week 4)
          _makeReport(
            date: DateTime(2024, 2, 28),
            totalRevenue: 1000000,
            totalCost: 600000,
            totalOrders: 2,
          ),
          // Feb 29 (Day 29 -> Week 5 in Leap Year)
          _makeReport(
            date: DateTime(2024, 2, 29),
            totalRevenue: 2500000,
            totalCost: 1500000,
            totalOrders: 5,
          ),
        ];

        final buckets =
            aggregateRevenueReports(dailyReports: reports, range: range);

        expect(buckets.length, equals(2));

        expect(buckets[0].label, equals('T4 Th02'));
        expect(buckets[0].fullLabel, equals('Tuần 4 - Tháng 02/2024'));
        expect(buckets[0].totalRevenue, equals(1000000));

        expect(buckets[1].label, equals('T5 Th02'));
        expect(buckets[1].fullLabel, equals('Tuần 5 - Tháng 02/2024'));
        expect(buckets[1].totalRevenue, equals(2500000));
      });

      test(
          'Non-Leap Year (2026-02-28) Weekly aggregation has only Week 4, no Week 5',
          () {
        final range = DateTimeRange(
          start: DateTime(2026, 2, 1),
          end: DateTime(2026, 3, 10), // 38 days (Weekly)
        );

        final reports = [
          _makeReport(
            date: DateTime(2026, 2, 28),
            totalRevenue: 1000000,
            totalCost: 600000,
            totalOrders: 2,
          ),
          _makeReport(
            date: DateTime(2026, 3, 1),
            totalRevenue: 2000000,
            totalCost: 1200000,
            totalOrders: 4,
          ),
        ];

        final buckets =
            aggregateRevenueReports(dailyReports: reports, range: range);

        expect(buckets.length, equals(2));
        expect(buckets[0].label, equals('T4 Th02'));
        expect(buckets[0].fullLabel, equals('Tuần 4 - Tháng 02/2026'));
        expect(buckets[1].label, equals('T1 Th03'));
        expect(buckets[1].fullLabel, equals('Tuần 1 - Tháng 03/2026'));
      });

      test(
          'Month-end Boundary: 31-day months (Day 29, 30, 31) properly merged into Week 5',
          () {
        final range = DateTimeRange(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 9, 10), // 41 days (Weekly)
        );

        final reports = [
          _makeReport(
              date: DateTime(2026, 8, 29),
              totalRevenue: 1000000,
              totalCost: 500000,
              totalOrders: 2),
          _makeReport(
              date: DateTime(2026, 8, 30),
              totalRevenue: 2000000,
              totalCost: 1000000,
              totalOrders: 4),
          _makeReport(
              date: DateTime(2026, 8, 31),
              totalRevenue: 3000000,
              totalCost: 1500000,
              totalOrders: 6),
        ];

        final buckets =
            aggregateRevenueReports(dailyReports: reports, range: range);

        expect(buckets.length, equals(1));
        expect(buckets[0].label, equals('T5 Th08'));
        expect(buckets[0].fullLabel, equals('Tuần 5 - Tháng 08/2026'));
        expect(buckets[0].totalRevenue, equals(6000000));
        expect(buckets[0].totalCost, equals(3000000));
        expect(buckets[0].profit, equals(3000000));
        expect(buckets[0].totalOrders, equals(12));
        expect(buckets[0].startDate, equals(DateTime(2026, 8, 29)));
        expect(buckets[0].endDate, equals(DateTime(2026, 8, 31)));
      });

      test(
          'Month-end Boundary: 30-day month (April 29 & 30) properly merged into Week 5',
          () {
        final range = DateTimeRange(
          start: DateTime(2026, 4, 1),
          end: DateTime(2026, 5, 10), // 40 days (Weekly)
        );

        final reports = [
          _makeReport(
              date: DateTime(2026, 4, 29),
              totalRevenue: 1500000,
              totalCost: 800000,
              totalOrders: 3),
          _makeReport(
              date: DateTime(2026, 4, 30),
              totalRevenue: 2500000,
              totalCost: 1200000,
              totalOrders: 5),
        ];

        final buckets =
            aggregateRevenueReports(dailyReports: reports, range: range);

        expect(buckets.length, equals(1));
        expect(buckets[0].label, equals('T5 Th04'));
        expect(buckets[0].fullLabel, equals('Tuần 5 - Tháng 04/2026'));
        expect(buckets[0].totalRevenue, equals(4000000));
        expect(buckets[0].totalOrders, equals(8));
        expect(buckets[0].startDate, equals(DateTime(2026, 4, 29)));
        expect(buckets[0].endDate, equals(DateTime(2026, 4, 30)));
      });
    });

    // =========================================================================
    // 3. MULTI-STORE REVENUE SUMMATION ACCURACY & CONSERVATION
    // =========================================================================
    group('3. Multi-Store Revenue Summation Accuracy & Conservation Laws', () {
      test('Multi-store summation conservation across Weekly aggregation', () {
        final range = DateTimeRange(
          start: DateTime(2026, 7, 1),
          end: DateTime(2026, 8, 15), // 46 days (Weekly)
        );

        final reports = List.generate(45, (i) {
          final date = DateTime(2026, 7, 1).add(Duration(days: i));
          final rev1 = 100000.0 * (i + 1);
          final rev2 = 150000.0 * (i + 1);
          final rev3 = 200000.0 * (i + 1);
          final totalRev = rev1 + rev2 + rev3;
          final totalCost = totalRev * 0.6;
          final profit = totalRev - totalCost;
          final orders = (i % 5) + 1;
          final items = orders * 3;

          return _makeReport(
            date: date,
            totalRevenue: totalRev,
            totalCost: totalCost,
            profit: profit,
            totalOrders: orders,
            totalItemsSold: items,
            storeRevenues: {
              'store_001': rev1,
              'store_002': rev2,
              'store_003': rev3,
            },
          );
        });

        // Compute expected global totals from raw daily reports
        final expectedTotalRevenue =
            reports.fold(0.0, (s, r) => s + r.totalRevenue);
        final expectedTotalCost = reports.fold(0.0, (s, r) => s + r.totalCost);
        final expectedTotalProfit = reports.fold(0.0, (s, r) => s + r.profit);
        final expectedTotalOrders =
            reports.fold(0, (s, r) => s + r.totalOrders);
        final expectedTotalItems =
            reports.fold(0, (s, r) => s + r.totalItemsSold);
        final expectedStore1Rev = reports.fold(
            0.0, (s, r) => s + (r.storeRevenues['store_001'] ?? 0));
        final expectedStore2Rev = reports.fold(
            0.0, (s, r) => s + (r.storeRevenues['store_002'] ?? 0));
        final expectedStore3Rev = reports.fold(
            0.0, (s, r) => s + (r.storeRevenues['store_003'] ?? 0));

        final buckets =
            aggregateRevenueReports(dailyReports: reports, range: range);

        // Sum across buckets
        final actualTotalRevenue =
            buckets.fold(0.0, (s, b) => s + b.totalRevenue);
        final actualTotalCost = buckets.fold(0.0, (s, b) => s + b.totalCost);
        final actualTotalProfit = buckets.fold(0.0, (s, b) => s + b.profit);
        final actualTotalOrders = buckets.fold(0, (s, b) => s + b.totalOrders);
        final actualTotalItems =
            buckets.fold(0, (s, b) => s + b.totalItemsSold);
        final actualStore1Rev = buckets.fold(
            0.0, (s, b) => s + (b.storeRevenues['store_001'] ?? 0));
        final actualStore2Rev = buckets.fold(
            0.0, (s, b) => s + (b.storeRevenues['store_002'] ?? 0));
        final actualStore3Rev = buckets.fold(
            0.0, (s, b) => s + (b.storeRevenues['store_003'] ?? 0));

        // Verify conservation
        expect(actualTotalRevenue, equals(expectedTotalRevenue));
        expect(actualTotalCost, closeTo(expectedTotalCost, 0.0001));
        expect(actualTotalProfit, closeTo(expectedTotalProfit, 0.0001));
        expect(actualTotalOrders, equals(expectedTotalOrders));
        expect(actualTotalItems, equals(expectedTotalItems));
        expect(actualStore1Rev, equals(expectedStore1Rev));
        expect(actualStore2Rev, equals(expectedStore2Rev));
        expect(actualStore3Rev, equals(expectedStore3Rev));

        // Verify intra-bucket consistency: bucket total revenue == sum of its storeRevenues
        for (final bucket in buckets) {
          final bucketStoreSum =
              bucket.storeRevenues.values.fold(0.0, (s, v) => s + v);
          expect(bucket.totalRevenue, closeTo(bucketStoreSum, 0.0001));
        }
      });

      test('Multi-store summation conservation across Monthly aggregation', () {
        final range = DateTimeRange(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 6, 30), // 181 days (Monthly)
        );

        final reports = List.generate(180, (i) {
          final date = DateTime(2026, 1, 1).add(Duration(days: i));
          return _makeReport(
            date: date,
            totalRevenue: 500000.0,
            totalCost: 300000.0,
            profit: 200000.0,
            totalOrders: 10,
            totalItemsSold: 25,
            storeRevenues: {
              'store_A': 300000.0,
              'store_B': 200000.0,
            },
          );
        });

        final buckets =
            aggregateRevenueReports(dailyReports: reports, range: range);

        expect(buckets.length, equals(6)); // Jan to Jun

        final actualTotalRevenue =
            buckets.fold(0.0, (s, b) => s + b.totalRevenue);
        final actualTotalOrders = buckets.fold(0, (s, b) => s + b.totalOrders);
        final actualStoreARev =
            buckets.fold(0.0, (s, b) => s + (b.storeRevenues['store_A'] ?? 0));
        final actualStoreBRev =
            buckets.fold(0.0, (s, b) => s + (b.storeRevenues['store_B'] ?? 0));

        expect(actualTotalRevenue, equals(180 * 500000.0));
        expect(actualTotalOrders, equals(180 * 10));
        expect(actualStoreARev, equals(180 * 300000.0));
        expect(actualStoreBRev, equals(180 * 200000.0));

        for (final bucket in buckets) {
          final storeSum = bucket.storeRevenues['store_A']! +
              bucket.storeRevenues['store_B']!;
          expect(bucket.totalRevenue, equals(storeSum));
        }
      });
    });

    // =========================================================================
    // 4. EMPTY REPORTS, ZERO REVENUE, NEGATIVE VALUES & DIVISION BY ZERO SAFETY
    // =========================================================================
    group(
        '4. Robustness & Fault Tolerance (Empty, Zero, Negative, Missing Fields)',
        () {
      test(
          'Empty dailyReports list returns empty buckets without crashing in all intervals',
          () {
        final emptyReports = <RevenueReport>[];

        // Daily range
        expect(
          aggregateRevenueReports(
            dailyReports: emptyReports,
            range: DateTimeRange(
                start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 10)),
          ),
          isEmpty,
        );

        // Weekly range
        expect(
          aggregateRevenueReports(
            dailyReports: emptyReports,
            range: DateTimeRange(
                start: DateTime(2026, 7, 1), end: DateTime(2026, 8, 15)),
          ),
          isEmpty,
        );

        // Monthly range
        expect(
          aggregateRevenueReports(
            dailyReports: emptyReports,
            range: DateTimeRange(
                start: DateTime(2026, 1, 1), end: DateTime(2026, 6, 30)),
          ),
          isEmpty,
        );
      });

      test(
          'Zero-revenue days with zero orders aggregate without NaN or DivisionByZero',
          () {
        final range = DateTimeRange(
          start: DateTime(2026, 7, 1),
          end: DateTime(2026, 8, 15), // Weekly
        );

        final reports = [
          _makeReport(
            date: DateTime(2026, 7, 5),
            totalRevenue: 0.0,
            totalCost: 0.0,
            profit: 0.0,
            totalOrders: 0,
            totalItemsSold: 0,
            storeRevenues: {},
          ),
          _makeReport(
            date: DateTime(2026, 7, 6),
            totalRevenue: 0.0,
            totalCost: 0.0,
            profit: 0.0,
            totalOrders: 0,
            totalItemsSold: 0,
            storeRevenues: {},
          ),
        ];

        final buckets =
            aggregateRevenueReports(dailyReports: reports, range: range);

        expect(buckets.length, equals(1));
        expect(buckets[0].totalRevenue, equals(0.0));
        expect(buckets[0].totalCost, equals(0.0));
        expect(buckets[0].profit, equals(0.0));
        expect(buckets[0].totalOrders, equals(0));
        expect(buckets[0].totalItemsSold, equals(0));
        expect(buckets[0].totalRevenue.isNaN, isFalse);
        expect(buckets[0].totalRevenue.isInfinite, isFalse);
      });

      test(
          'Negative revenue (sales returns/refunds exceeding sales) aggregate accurately',
          () {
        final range = DateTimeRange(
          start: DateTime(2026, 7, 1),
          end: DateTime(2026, 8, 15), // Weekly
        );

        final reports = [
          _makeReport(
            date: DateTime(2026, 7, 2),
            totalRevenue: -2000000.0,
            // Refund
            totalCost: -1200000.0,
            profit: -800000.0,
            totalOrders: 1,
            storeRevenues: {'store_001': -2000000.0},
          ),
          _makeReport(
            date: DateTime(2026, 7, 3),
            totalRevenue: 5000000.0,
            totalCost: 3000000.0,
            profit: 2000000.0,
            totalOrders: 3,
            storeRevenues: {'store_001': 5000000.0},
          ),
        ];

        final buckets =
            aggregateRevenueReports(dailyReports: reports, range: range);

        expect(buckets.length, equals(1));
        expect(buckets[0].totalRevenue, equals(3000000.0));
        expect(buckets[0].totalCost, equals(1800000.0));
        expect(buckets[0].profit, equals(1200000.0));
        expect(buckets[0].totalOrders, equals(4));
        expect(buckets[0].storeRevenues['store_001'], equals(3000000.0));
      });

      test('Daily reports with disjoint store IDs merge properly in buckets',
          () {
        final range = DateTimeRange(
          start: DateTime(2026, 7, 1),
          end: DateTime(2026, 8, 15), // Weekly
        );

        final reports = [
          _makeReport(
            date: DateTime(2026, 7, 2),
            totalRevenue: 1000000,
            totalCost: 500000,
            storeRevenues: {'store_A': 1000000},
          ),
          _makeReport(
            date: DateTime(2026, 7, 3),
            totalRevenue: 2000000,
            totalCost: 1000000,
            storeRevenues: {'store_B': 2000000},
          ),
          _makeReport(
            date: DateTime(2026, 7, 4),
            totalRevenue: 3000000,
            totalCost: 1500000,
            storeRevenues: {'store_C': 3000000},
          ),
        ];

        final buckets =
            aggregateRevenueReports(dailyReports: reports, range: range);

        expect(buckets.length, equals(1));
        expect(buckets[0].storeRevenues.keys.length, equals(3));
        expect(buckets[0].storeRevenues['store_A'], equals(1000000));
        expect(buckets[0].storeRevenues['store_B'], equals(2000000));
        expect(buckets[0].storeRevenues['store_C'], equals(3000000));
        expect(buckets[0].totalRevenue, equals(6000000));
      });
    });
  });
}
