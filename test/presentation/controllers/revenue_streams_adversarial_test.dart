import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/domain/entities/revenue_report.dart';
import 'package:stores/domain/entities/user_account.dart';

class FakeAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  FakeAuthNotifier([super.initialUser]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Revenue Streams & Boundary Timestamps Adversarial Tests', () {
    // =========================================================================
    // 1. Boundary Timestamps & Date Range Inclusivity
    // =========================================================================
    group('1. Boundary Timestamps & Inclusivity', () {
      test('End-of-month boundary: 2026-08-31 23:59:59.999', () {
        final start = DateTime(2026, 8, 1, 0, 0, 0, 0);
        final end = DateTime(2026, 8, 31, 23, 59, 59, 999);

        final rep1 = RevenueReport(
          date: DateTime(2026, 8, 1),
          totalRevenue: 1000000.0,
          totalCost: 500000.0,
          profit: 500000.0,
          totalOrders: 1,
          totalItemsSold: 1,
          productRevenues: const [],
        );

        final repLastMinute = RevenueReport(
          date: DateTime(2026, 8, 31),
          totalRevenue: 2000000.0,
          totalCost: 1200000.0,
          profit: 800000.0,
          totalOrders: 2,
          totalItemsSold: 2,
          productRevenues: const [],
        );

        final summary = RevenueSummary(
          startDate: start,
          endDate: end,
          totalRevenue: 3000000.0,
          totalCost: 1700000.0,
          totalProfit: 1300000.0,
          totalOrders: 3,
          totalItemsSold: 3,
          dailyReports: [rep1, repLastMinute],
        );

        final merged = mergeRevenueSummaries([summary], start, end);
        expect(merged.startDate, equals(start));
        expect(merged.endDate, equals(end));
        expect(merged.totalRevenue, equals(3000000.0));
        expect(merged.dailyReports.length, equals(2));
        expect(merged.dailyReports.last.date, equals(DateTime(2026, 8, 31)));
      });

      test('Leap Year Boundary: 2024-02-28 to 2024-03-01 spanning leap day 2024-02-29', () {
        final start = DateTime(2024, 2, 28);
        final end = DateTime(2024, 3, 1, 23, 59, 59, 999);

        final repFeb28 = RevenueReport(
          date: DateTime(2024, 2, 28),
          totalRevenue: 500000.0,
          totalCost: 200000.0,
          profit: 300000.0,
          totalOrders: 1,
          totalItemsSold: 1,
          productRevenues: const [],
        );

        final repFeb29 = RevenueReport(
          date: DateTime(2024, 2, 29), // Leap Day!
          totalRevenue: 1500000.0,
          totalCost: 800000.0,
          profit: 700000.0,
          totalOrders: 2,
          totalItemsSold: 3,
          productRevenues: const [],
        );

        final repMar01 = RevenueReport(
          date: DateTime(2024, 3, 1),
          totalRevenue: 750000.0,
          totalCost: 350000.0,
          profit: 400000.0,
          totalOrders: 1,
          totalItemsSold: 1,
          productRevenues: const [],
        );

        final summary1 = RevenueSummary(
          startDate: start,
          endDate: end,
          totalRevenue: 2000000.0,
          totalCost: 1000000.0,
          totalProfit: 1000000.0,
          totalOrders: 3,
          totalItemsSold: 4,
          dailyReports: [repFeb28, repFeb29],
        );

        final summary2 = RevenueSummary(
          startDate: start,
          endDate: end,
          totalRevenue: 750000.0,
          totalCost: 350000.0,
          totalProfit: 400000.0,
          totalOrders: 1,
          totalItemsSold: 1,
          dailyReports: [repMar01],
        );

        final merged = mergeRevenueSummaries([summary1, summary2], start, end);
        expect(merged.totalRevenue, equals(2750000.0));
        expect(merged.dailyReports.length, equals(3));
        expect(merged.dailyReports[0].date, equals(DateTime(2024, 2, 28)));
        expect(merged.dailyReports[1].date, equals(DateTime(2024, 2, 29)));
        expect(merged.dailyReports[2].date, equals(DateTime(2024, 3, 1)));
      });

      test('Non-Leap Year February Boundary: 2026-02-28 23:59:59.999', () {
        final start = DateTime(2026, 2, 1);
        final end = DateTime(2026, 2, 28, 23, 59, 59, 999);

        final repFeb28 = RevenueReport(
          date: DateTime(2026, 2, 28),
          totalRevenue: 1200000.0,
          totalCost: 600000.0,
          profit: 600000.0,
          totalOrders: 1,
          totalItemsSold: 1,
          productRevenues: const [],
        );

        final summary = RevenueSummary(
          startDate: start,
          endDate: end,
          totalRevenue: 1200000.0,
          totalCost: 600000.0,
          totalProfit: 600000.0,
          totalOrders: 1,
          totalItemsSold: 1,
          dailyReports: [repFeb28],
        );

        final merged = mergeRevenueSummaries([summary], start, end);
        expect(merged.dailyReports.first.date, equals(DateTime(2026, 2, 28)));
      });

      test('Year Transition Boundary: 2026-12-31 to 2027-01-01', () {
        final start = DateTime(2026, 12, 31);
        final end = DateTime(2027, 1, 1, 23, 59, 59, 999);

        final repDec31 = RevenueReport(
          date: DateTime(2026, 12, 31),
          totalRevenue: 5000000.0,
          totalCost: 3000000.0,
          profit: 2000000.0,
          totalOrders: 5,
          totalItemsSold: 10,
          productRevenues: const [],
        );

        final repJan01 = RevenueReport(
          date: DateTime(2027, 1, 1),
          totalRevenue: 3000000.0,
          totalCost: 1500000.0,
          profit: 1500000.0,
          totalOrders: 3,
          totalItemsSold: 5,
          productRevenues: const [],
        );

        final merged = mergeRevenueSummaries([
          RevenueSummary(
            startDate: start,
            endDate: end,
            totalRevenue: 5000000.0,
            totalCost: 3000000.0,
            totalProfit: 2000000.0,
            totalOrders: 5,
            totalItemsSold: 10,
            dailyReports: [repDec31],
          ),
          RevenueSummary(
            startDate: start,
            endDate: end,
            totalRevenue: 3000000.0,
            totalCost: 1500000.0,
            totalProfit: 1500000.0,
            totalOrders: 3,
            totalItemsSold: 5,
            dailyReports: [repJan01],
          ),
        ], start, end);

        expect(merged.totalRevenue, equals(8000000.0));
        expect(merged.dailyReports.length, equals(2));
        expect(merged.dailyReports[0].date, equals(DateTime(2026, 12, 31)));
        expect(merged.dailyReports[1].date, equals(DateTime(2027, 1, 1)));
      });

      test('Single-Day Filter (start 00:00:00 to end 23:59:59.999)', () {
        final singleDay = DateTime(2026, 8, 17);
        final start = DateTime(singleDay.year, singleDay.month, singleDay.day);
        final end = DateTime(singleDay.year, singleDay.month, singleDay.day, 23, 59, 59, 999);

        final rep = RevenueReport(
          date: DateTime(2026, 8, 17),
          totalRevenue: 7150000.0,
          totalCost: 4000000.0,
          profit: 3150000.0,
          totalOrders: 3,
          totalItemsSold: 5,
          productRevenues: const [],
        );

        final summary = RevenueSummary(
          startDate: start,
          endDate: end,
          totalRevenue: 7150000.0,
          totalCost: 4000000.0,
          totalProfit: 3150000.0,
          totalOrders: 3,
          totalItemsSold: 5,
          dailyReports: [rep],
        );

        final merged = mergeRevenueSummaries([summary], start, end);
        expect(merged.dailyReports.length, equals(1));
        // Normalizes to date only (00:00:00)
        expect(merged.dailyReports.first.date, equals(DateTime(2026, 8, 17)));
      });
    });

    // =========================================================================
    // 2. Multi-Store Revenue Aggregation & Edge Cases
    // =========================================================================
    group('2. Multi-Store Revenue Aggregation & Edge Cases', () {
      test('Zero-cost product division-by-zero protection in mergeProductRevenues', () {
        final date = DateTime(2026, 8, 10);
        final giftProductReport = RevenueReport(
          date: date,
          totalRevenue: 100000.0,
          totalCost: 0.0, // Zero Cost (Free promotional gift sold or zero COGS)
          profit: 100000.0,
          totalOrders: 1,
          totalItemsSold: 1,
          productRevenues: const [
            ProductRevenue(
              productId: 'PROMO_GIFT',
              productName: 'Tặng phẩm',
              quantitySold: 1,
              revenue: 100000.0,
              cost: 0.0, // 0 cost
              profit: 100000.0,
              profitMargin: 100.0,
            ),
          ],
        );

        final store2Report = RevenueReport(
          date: date,
          totalRevenue: 200000.0,
          totalCost: 0.0,
          profit: 200000.0,
          totalOrders: 2,
          totalItemsSold: 2,
          productRevenues: const [
            ProductRevenue(
              productId: 'PROMO_GIFT',
              productName: 'Tặng phẩm',
              quantitySold: 2,
              revenue: 200000.0,
              cost: 0.0,
              profit: 200000.0,
              profitMargin: 100.0,
            ),
          ],
        );

        final summary1 = RevenueSummary(
          startDate: date,
          endDate: date,
          totalRevenue: 100000.0,
          totalCost: 0.0,
          totalProfit: 100000.0,
          totalOrders: 1,
          totalItemsSold: 1,
          dailyReports: [giftProductReport],
        );

        final summary2 = RevenueSummary(
          startDate: date,
          endDate: date,
          totalRevenue: 200000.0,
          totalCost: 0.0,
          totalProfit: 200000.0,
          totalOrders: 2,
          totalItemsSold: 2,
          dailyReports: [store2Report],
        );

        // Must not throw division by zero or produce NaN/Infinity
        final merged = mergeRevenueSummaries([summary1, summary2], date, date);
        expect(merged.totalRevenue, equals(300000.0));
        expect(merged.totalCost, equals(0.0));
        expect(merged.totalProfit, equals(300000.0));

        final prod = merged.dailyReports.first.productRevenues.first;
        expect(prod.quantitySold, equals(3));
        expect(prod.revenue, equals(300000.0));
        expect(prod.cost, equals(0.0));
        expect(prod.profitMargin.isFinite, isTrue);
      });

      test('Asymmetric store activity: Store 1 has orders, Store 2 has zero orders', () {
        final start = DateTime(2026, 8, 1);
        final end = DateTime(2026, 8, 31);

        final activeStore = RevenueSummary(
          startDate: start,
          endDate: end,
          totalRevenue: 5000000.0,
          totalCost: 2000000.0,
          totalProfit: 3000000.0,
          totalOrders: 4,
          totalItemsSold: 8,
          dailyReports: [
            RevenueReport(
              date: DateTime(2026, 8, 5),
              totalRevenue: 5000000.0,
              totalCost: 2000000.0,
              profit: 3000000.0,
              totalOrders: 4,
              totalItemsSold: 8,
              productRevenues: const [],
            ),
          ],
        );

        final emptyStore = RevenueSummary(
          startDate: start,
          endDate: end,
          totalRevenue: 0.0,
          totalCost: 0.0,
          totalProfit: 0.0,
          totalOrders: 0,
          totalItemsSold: 0,
          dailyReports: const [],
        );

        final merged = mergeRevenueSummaries([activeStore, emptyStore], start, end);
        expect(merged.totalRevenue, equals(5000000.0));
        expect(merged.totalOrders, equals(4));
        expect(merged.dailyReports.length, equals(1));
      });

      test('Disordered daily reports from multiple stores are sorted chronologically', () {
        final start = DateTime(2026, 8, 1);
        final end = DateTime(2026, 8, 31);

        final store1 = RevenueSummary(
          startDate: start,
          endDate: end,
          totalRevenue: 2000.0,
          totalCost: 1000.0,
          totalProfit: 1000.0,
          totalOrders: 2,
          totalItemsSold: 2,
          dailyReports: [
            RevenueReport(date: DateTime(2026, 8, 20), totalRevenue: 1000.0, totalCost: 500.0, profit: 500.0, totalOrders: 1, totalItemsSold: 1, productRevenues: const []),
            RevenueReport(date: DateTime(2026, 8, 5), totalRevenue: 1000.0, totalCost: 500.0, profit: 500.0, totalOrders: 1, totalItemsSold: 1, productRevenues: const []),
          ],
        );

        final store2 = RevenueSummary(
          startDate: start,
          endDate: end,
          totalRevenue: 2000.0,
          totalCost: 1000.0,
          totalProfit: 1000.0,
          totalOrders: 2,
          totalItemsSold: 2,
          dailyReports: [
            RevenueReport(date: DateTime(2026, 8, 25), totalRevenue: 1000.0, totalCost: 500.0, profit: 500.0, totalOrders: 1, totalItemsSold: 1, productRevenues: const []),
            RevenueReport(date: DateTime(2026, 8, 1), totalRevenue: 1000.0, totalCost: 500.0, profit: 500.0, totalOrders: 1, totalItemsSold: 1, productRevenues: const []),
          ],
        );

        final merged = mergeRevenueSummaries([store1, store2], start, end);
        expect(merged.dailyReports.length, equals(4));
        expect(merged.dailyReports[0].date, equals(DateTime(2026, 8, 1)));
        expect(merged.dailyReports[1].date, equals(DateTime(2026, 8, 5)));
        expect(merged.dailyReports[2].date, equals(DateTime(2026, 8, 20)));
        expect(merged.dailyReports[3].date, equals(DateTime(2026, 8, 25)));
      });
    });

    // =========================================================================
    // 3. Riverpod Stream & Provider Reactivity
    // =========================================================================
    group('3. Riverpod Stream & Provider Reactivity', () {
      test('selectedBranchesProvider toggling updates active selections', () {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => FakeAuthNotifier(const UserAccount(
                  username: 'admin',
                  displayName: 'Admin',
                  role: 'admin',
                  storeId: 'store_001',
                ))),
          ],
        );

        final notifier = container.read(selectedBranchesProvider.notifier);
        expect(container.read(selectedBranchesProvider), containsAll(['store_001', 'store_002']));

        // Toggle store_001 off -> only store_002
        notifier.toggleBranch('store_001');
        expect(container.read(selectedBranchesProvider), equals(['store_002']));

        // Toggling the last remaining branch is prevented (at least 1 must remain)
        notifier.toggleBranch('store_002');
        expect(container.read(selectedBranchesProvider), equals(['store_002']));

        // Toggle store_001 back on -> both stores
        notifier.toggleBranch('store_001');
        expect(container.read(selectedBranchesProvider), containsAll(['store_001', 'store_002']));

        // clearAll resets to first branch (store_001)
        notifier.clearAll();
        expect(container.read(selectedBranchesProvider), equals(['store_001']));

        // selectAll restores all branches
        notifier.selectAll();
        expect(container.read(selectedBranchesProvider), containsAll(['store_001', 'store_002']));
      });

      test('Staff account cannot toggle or clear branches in selectedBranchesProvider', () {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => FakeAuthNotifier(const UserAccount(
                  username: 'nhanvien',
                  displayName: 'Nhân Viên',
                  role: 'nhanvien',
                  storeId: 'store_002',
                ))),
          ],
        );

        final notifier = container.read(selectedBranchesProvider.notifier);
        expect(container.read(selectedBranchesProvider), equals(['store_002']));

        // Attempting toggle has no effect for staff
        notifier.toggleBranch('store_001');
        expect(container.read(selectedBranchesProvider), equals(['store_002']));

        notifier.selectAll();
        expect(container.read(selectedBranchesProvider), equals(['store_002']));

        notifier.clearAll();
        expect(container.read(selectedBranchesProvider), equals(['store_002']));
      });
    });
  });
}
