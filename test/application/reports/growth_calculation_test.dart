import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/reports/overview_providers.dart';

void main() {
  group('Growth Calculation & Prior Period Comparison (R1)', () {
    // Pure calculation helper for percentage growth
    double calculateGrowthPercent(double current, double prior) {
      if (prior == 0.0) {
        if (current > 0.0) return 100.0;
        if (current < 0.0) return -100.0;
        return 0.0;
      }
      return ((current - prior) / prior.abs()) * 100.0;
    }

    // Helper to compute prior date range given current range type
    DateTimeRange getPriorPeriodDateRange({
      required OverviewTimeRange timeRange,
      DateTimeRange? customRange,
      DateTime? referenceNow,
    }) {
      final now = referenceNow ?? DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      switch (timeRange) {
        case OverviewTimeRange.today:
          final yesterday = today.subtract(const Duration(days: 1));
          return DateTimeRange(
            start: yesterday,
            end: DateTime(yesterday.year, yesterday.month, yesterday.day, 23,
                59, 59, 999),
          );

        case OverviewTimeRange.yesterday:
          final twoDaysAgo = today.subtract(const Duration(days: 2));
          return DateTimeRange(
            start: twoDaysAgo,
            end: DateTime(twoDaysAgo.year, twoDaysAgo.month, twoDaysAgo.day, 23,
                59, 59, 999),
          );

        case OverviewTimeRange.last7Days:
          final endOfPrior = today.subtract(const Duration(days: 7));
          final startOfPrior = today.subtract(const Duration(days: 13));
          return DateTimeRange(
            start: startOfPrior,
            end: DateTime(endOfPrior.year, endOfPrior.month, endOfPrior.day, 23,
                59, 59, 999),
          );

        case OverviewTimeRange.thisMonth:
          // Prior month: 1st to same day of prior month or full prior month
          final firstOfThisMonth = DateTime(now.year, now.month, 1);
          final lastOfPriorMonth =
              firstOfThisMonth.subtract(const Duration(days: 1));
          final firstOfPriorMonth =
              DateTime(lastOfPriorMonth.year, lastOfPriorMonth.month, 1);
          return DateTimeRange(
            start: firstOfPriorMonth,
            end: DateTime(lastOfPriorMonth.year, lastOfPriorMonth.month,
                lastOfPriorMonth.day, 23, 59, 59, 999),
          );

        case OverviewTimeRange.lastMonth:
          // Month before last
          final firstOfThisMonth = DateTime(now.year, now.month, 1);
          final lastOfPriorMonth =
              firstOfThisMonth.subtract(const Duration(days: 1));
          final firstOfPriorMonth =
              DateTime(lastOfPriorMonth.year, lastOfPriorMonth.month, 1);
          final lastOfTwoMonthsAgo =
              firstOfPriorMonth.subtract(const Duration(days: 1));
          final firstOfTwoMonthsAgo =
              DateTime(lastOfTwoMonthsAgo.year, lastOfTwoMonthsAgo.month, 1);
          return DateTimeRange(
            start: firstOfTwoMonthsAgo,
            end: DateTime(lastOfTwoMonthsAgo.year, lastOfTwoMonthsAgo.month,
                lastOfTwoMonthsAgo.day, 23, 59, 59, 999),
          );

        case OverviewTimeRange.custom:
          if (customRange == null) {
            return DateTimeRange(start: today, end: today);
          }
          final durationDays =
              customRange.end.difference(customRange.start).inDays + 1;
          final startOfPrior =
              customRange.start.subtract(Duration(days: durationDays));
          final endOfPrior =
              customRange.start.subtract(const Duration(days: 1));
          return DateTimeRange(
            start: DateTime(
                startOfPrior.year, startOfPrior.month, startOfPrior.day),
            end: DateTime(endOfPrior.year, endOfPrior.month, endOfPrior.day, 23,
                59, 59, 999),
          );
      }
    }

    group('Tier 1: Feature Coverage (Growth Formulas & Date Pairing)', () {
      test('1.1 Positive revenue growth formula', () {
        final growth =
            calculateGrowthPercent(15000000.0, 10000000.0); // +5M on 10M
        expect(growth, equals(50.0));
      });

      test('1.2 Negative revenue growth formula', () {
        final growth =
            calculateGrowthPercent(7500000.0, 10000000.0); // -2.5M on 10M
        expect(growth, equals(-25.0));
      });

      test('1.3 Zero change growth formula', () {
        final growth = calculateGrowthPercent(10000000.0, 10000000.0);
        expect(growth, equals(0.0));
      });

      test('1.4 Order count growth formula', () {
        final growth = calculateGrowthPercent(50.0, 40.0); // +10 on 40
        expect(growth, equals(25.0));
      });

      test('1.5 Profit growth formula', () {
        final growth =
            calculateGrowthPercent(4000000.0, 2500000.0); // +1.5M on 2.5M
        expect(growth, equals(60.0));
      });

      test('1.6 Date Range Pairing: Today vs Yesterday', () {
        final refDate = DateTime(2026, 8, 16, 11, 0);
        final priorRange = getPriorPeriodDateRange(
          timeRange: OverviewTimeRange.today,
          referenceNow: refDate,
        );

        expect(priorRange.start, equals(DateTime(2026, 8, 15)));
        expect(priorRange.end.day, equals(15));
        expect(priorRange.end.hour, equals(23));
        expect(priorRange.end.minute, equals(59));
      });

      test('1.7 Date Range Pairing: Last 7 Days vs Preceding 7 Days', () {
        final refDate = DateTime(2026, 8, 16, 11, 0);
        final priorRange = getPriorPeriodDateRange(
          timeRange: OverviewTimeRange.last7Days,
          referenceNow: refDate,
        );

        // Today is Aug 16. Last 7 days = Aug 10 to Aug 16 (7 days).
        // Preceding 7 days = Aug 3 to Aug 9 (7 days).
        expect(priorRange.start, equals(DateTime(2026, 8, 3)));
        expect(priorRange.end.day, equals(9));
      });

      test('1.8 Date Range Pairing: This Month vs Last Month', () {
        final refDate = DateTime(2026, 8, 16, 11, 0);
        final priorRange = getPriorPeriodDateRange(
          timeRange: OverviewTimeRange.thisMonth,
          referenceNow: refDate,
        );

        // August -> July (July 1 to July 31)
        expect(priorRange.start, equals(DateTime(2026, 7, 1)));
        expect(priorRange.end.month, equals(7));
        expect(priorRange.end.day, equals(31));
      });
    });

    group('Tier 2: Boundary & Corner Cases', () {
      test('2.1 Zero prior baseline with positive current value returns +100%',
          () {
        final growth = calculateGrowthPercent(5000000.0, 0.0);
        expect(growth, equals(100.0));
      });

      test('2.2 Zero current value with positive prior baseline returns -100%',
          () {
        final growth = calculateGrowthPercent(0.0, 10000000.0);
        expect(growth, equals(-100.0));
      });

      test('2.3 Zero in both periods returns 0.0% without NaN', () {
        final growth = calculateGrowthPercent(0.0, 0.0);
        expect(growth, equals(0.0));
        expect(growth.isNaN, isFalse);
        expect(growth.isFinite, isTrue);
      });

      test(
          '2.4 Profit recovery: From negative profit to positive profit (-2M -> +3M)',
          () {
        // Growth = (3M - (-2M)) / |-2M| * 100 = 5M / 2M * 100 = +250%
        final growth = calculateGrowthPercent(3000000.0, -2000000.0);
        expect(growth, equals(250.0));
      });

      test(
          '2.5 Profit loss: From positive profit to negative profit (+2M -> -1M)',
          () {
        // Growth = (-1M - 2M) / |2M| * 100 = -3M / 2M * 100 = -150%
        final growth = calculateGrowthPercent(-1000000.0, 2000000.0);
        expect(growth, equals(-150.0));
      });

      test('2.6 Profit worsening: From -1M to -3M', () {
        // Growth = (-3M - (-1M)) / |-1M| * 100 = -2M / 1M * 100 = -200%
        final growth = calculateGrowthPercent(-3000000.0, -1000000.0);
        expect(growth, equals(-200.0));
      });

      test('2.7 Profit improvement: From -3M to -1M', () {
        // Growth = (-1M - (-3M)) / |-3M| * 100 = +2M / 3M * 100 = +66.67%
        final growth = calculateGrowthPercent(-1000000.0, -3000000.0);
        expect(growth, closeTo(66.67, 0.01));
      });

      test('2.8 Extreme growth values (> 1000%) calculate accurately', () {
        final growth = calculateGrowthPercent(50000000.0, 500000.0); // 100x
        expect(growth, equals(9900.0));
      });
    });

    group('Tier 3: Combinatorial & Calendar Edge Cases', () {
      test('3.1 Month-end transition: March to February in Leap Year (2024)',
          () {
        final marchDate = DateTime(2024, 3, 15);
        final priorRange = getPriorPeriodDateRange(
          timeRange: OverviewTimeRange.thisMonth,
          referenceNow: marchDate,
        );

        // 2024 is a leap year -> February has 29 days
        expect(priorRange.start, equals(DateTime(2024, 2, 1)));
        expect(priorRange.end.month, equals(2));
        expect(priorRange.end.day, equals(29));
      });

      test(
          '3.2 Month-end transition: March to February in Non-Leap Year (2025)',
          () {
        final marchDate = DateTime(2025, 3, 15);
        final priorRange = getPriorPeriodDateRange(
          timeRange: OverviewTimeRange.thisMonth,
          referenceNow: marchDate,
        );

        // 2025 is not a leap year -> February has 28 days
        expect(priorRange.start, equals(DateTime(2025, 2, 1)));
        expect(priorRange.end.month, equals(2));
        expect(priorRange.end.day, equals(28));
      });

      test('3.3 Custom Date Range: 10-day range correctly shifts 10 days back',
          () {
        final customRange = DateTimeRange(
          start: DateTime(2026, 8, 11),
          end: DateTime(2026, 8, 20), // 10 days
        );

        final priorRange = getPriorPeriodDateRange(
          timeRange: OverviewTimeRange.custom,
          customRange: customRange,
        );

        // Prior range should be Aug 1 to Aug 10 (10 days)
        expect(priorRange.start, equals(DateTime(2026, 8, 1)));
        expect(priorRange.end.day, equals(10));
      });
    });

    group('Tier 4: Real-world Business Scenario', () {
      test('4.1 Monthly Performance Review with mixed growth indicators', () {
        // Month 1 (July):
        // Revenue: 45,000,000 đ, Orders: 90, Profit: 15,000,000 đ
        const double julyRev = 45000000.0;
        const int julyOrders = 90;
        const double julyProfit = 15000000.0;

        // Month 2 (August):
        // Revenue: 54,000,000 đ, Orders: 80, Profit: 20,000,000 đ
        const double augRev = 54000000.0;
        const int augOrders = 80;
        const double augProfit = 20000000.0;

        final revGrowth = calculateGrowthPercent(augRev, julyRev);
        final orderGrowth =
            calculateGrowthPercent(augOrders.toDouble(), julyOrders.toDouble());
        final profitGrowth = calculateGrowthPercent(augProfit, julyProfit);

        // Revenue increased by 20%
        expect(revGrowth, equals(20.0));
        // Order count decreased by 11.11%
        expect(orderGrowth, closeTo(-11.11, 0.01));
        // Profit increased by 33.33% (higher margin products sold)
        expect(profitGrowth, closeTo(33.33, 0.01));

        // AOV comparison
        const aovJuly = julyRev / julyOrders; // 500,000 đ
        const aovAug = augRev / augOrders; // 675,000 đ
        final aovGrowth = calculateGrowthPercent(aovAug, aovJuly);
        expect(aovGrowth, equals(35.0)); // AOV grew +35%
      });
    });
  });
}
