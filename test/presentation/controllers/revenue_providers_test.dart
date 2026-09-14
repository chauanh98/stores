import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/core/utils/store_resolver_helper.dart';
import 'package:stores/domain/entities/revenue_report.dart';
import 'package:stores/domain/entities/user_account.dart';

class FakeAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  FakeAuthNotifier([super.initialUser]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Revenue Providers & Aggregations Unit & Provider Tests', () {
    // -------------------------------------------------------------------------
    // 1. mergeRevenueSummaries Logic & Multi-Store Aggregation
    // -------------------------------------------------------------------------
    group('1. mergeRevenueSummaries Logic', () {
      test('Merges multiple store RevenueSummary objects accurately', () {
        final start = DateTime(2026, 6, 1);
        final end = DateTime(2026, 6, 30);

        final summaryStore1 = RevenueSummary(
          startDate: start,
          endDate: end,
          totalRevenue: 104361000.0,
          totalCost: 70000000.0,
          totalProfit: 34361000.0,
          totalOrders: 3,
          totalItemsSold: 3,
          dailyReports: [
            RevenueReport(
              date: DateTime(2026, 6, 14),
              totalRevenue: 61980000.0,
              totalCost: 40000000.0,
              profit: 21980000.0,
              totalOrders: 1,
              totalItemsSold: 2,
              productRevenues: const [
                ProductRevenue(
                  productId: 'p102',
                  productName: 'ThinkPad X1 Carbon',
                  quantitySold: 1,
                  revenue: 42990000.0,
                  cost: 30092999.0,
                  profit: 12897001.0,
                  profitMargin: 29.99,
                ),
              ],
              storeRevenues: const {'store_001': 61980000.0},
            ),
            RevenueReport(
              date: DateTime(2026, 6, 28),
              totalRevenue: 23391000.0,
              totalCost: 15000000.0,
              profit: 8391000.0,
              totalOrders: 1,
              totalItemsSold: 1,
              productRevenues: const [
                ProductRevenue(
                  productId: 'p001',
                  productName: 'iPhone 15',
                  quantitySold: 1,
                  revenue: 23391000.0,
                  cost: 15000000.0,
                  profit: 8391000.0,
                  profitMargin: 35.87,
                ),
              ],
              storeRevenues: const {'store_001': 23391000.0},
            ),
          ],
        );

        final summaryStore2 = RevenueSummary(
          startDate: start,
          endDate: end,
          totalRevenue: 231000000.0,
          totalCost: 157666666.0,
          totalProfit: 73333334.0,
          totalOrders: 2,
          totalItemsSold: 11,
          dailyReports: [
            RevenueReport(
              date: DateTime(2026, 6, 28),
              totalRevenue: 231000000.0,
              totalCost: 157666666.0,
              profit: 73333334.0,
              totalOrders: 2,
              totalItemsSold: 11,
              productRevenues: const [
                ProductRevenue(
                  productId: '1782636691862',
                  productName: 'iPhone 17',
                  quantitySold: 11,
                  revenue: 231000000.0,
                  cost: 157666666.0,
                  profit: 73333334.0,
                  profitMargin: 31.74,
                ),
              ],
              storeRevenues: const {'store_002': 231000000.0},
            ),
          ],
        );

        final merged = mergeRevenueSummaries([summaryStore1, summaryStore2], start, end);

        expect(merged.totalRevenue, equals(335361000.0),
            reason: '104,361,000 + 231,000,000 = 335,361,000 VND');
        expect(merged.totalOrders, equals(5));
        expect(merged.totalItemsSold, equals(14));
        expect(merged.totalProfit, closeTo(107694334.0, 0.01));

        // Combined daily reports: June 14 and June 28
        expect(merged.dailyReports.length, equals(2));

        // Check June 28 combined daily report (contains both store_001 and store_002 revenues)
        final june28Report = merged.dailyReports.firstWhere(
            (r) => r.date.year == 2026 && r.date.month == 6 && r.date.day == 28);
        expect(june28Report.totalRevenue, equals(254391000.0),
            reason: '23,391,000 (store_001) + 231,000,000 (store_002) = 254,391,000 VND');
        expect(june28Report.totalOrders, equals(3));
        expect(june28Report.storeRevenues['store_001'], equals(23391000.0));
        expect(june28Report.storeRevenues['store_002'], equals(231000000.0));
        expect(june28Report.productRevenues.length, equals(2));
      });

      test('Merges duplicate product revenues on the same day across stores', () {
        final date = DateTime(2026, 7, 26);
        final report1 = RevenueReport(
          date: date,
          totalRevenue: 1150000.0,
          totalCost: 2500.0,
          profit: 1147500.0,
          totalOrders: 1,
          totalItemsSold: 1,
          productRevenues: const [
            ProductRevenue(
              productId: 'VP88',
              productName: 'Bàn chữ K MDF',
              quantitySold: 1,
              revenue: 1150000.0,
              cost: 2500.0,
              profit: 1147500.0,
              profitMargin: 99.78,
            ),
          ],
          storeRevenues: const {'store_001': 1150000.0},
        );

        final report2 = RevenueReport(
          date: date,
          totalRevenue: 2300000.0,
          totalCost: 5000.0,
          profit: 2295000.0,
          totalOrders: 2,
          totalItemsSold: 2,
          productRevenues: const [
            ProductRevenue(
              productId: 'VP88',
              productName: 'Bàn chữ K MDF',
              quantitySold: 2,
              revenue: 2300000.0,
              cost: 5000.0,
              profit: 2295000.0,
              profitMargin: 99.78,
            ),
          ],
          storeRevenues: const {'store_002': 2300000.0},
        );

        final summary1 = RevenueSummary(
          startDate: date,
          endDate: date,
          totalRevenue: 1150000.0,
          totalCost: 2500.0,
          totalProfit: 1147500.0,
          totalOrders: 1,
          totalItemsSold: 1,
          dailyReports: [report1],
        );

        final summary2 = RevenueSummary(
          startDate: date,
          endDate: date,
          totalRevenue: 2300000.0,
          totalCost: 5000.0,
          totalProfit: 2295000.0,
          totalOrders: 2,
          totalItemsSold: 2,
          dailyReports: [report2],
        );

        final merged = mergeRevenueSummaries([summary1, summary2], date, date);
        expect(merged.totalRevenue, equals(3450000.0));
        expect(merged.dailyReports.length, equals(1));

        final mergedProducts = merged.dailyReports.first.productRevenues;
        expect(mergedProducts.length, equals(1));
        expect(mergedProducts.first.productId, equals('VP88'));
        expect(mergedProducts.first.quantitySold, equals(3));
        expect(mergedProducts.first.revenue, equals(3450000.0));
        expect(mergedProducts.first.cost, equals(7500.0));
      });
    });

    // -------------------------------------------------------------------------
    // 2. Multi-Branch Store Resolution in Provider Context
    // -------------------------------------------------------------------------
    group('2. Store Resolution in Provider Context', () {
      test('Canonical store IDs in selectedBranchesProvider resolve to both stores', () {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => FakeAuthNotifier(const UserAccount(
                  username: 'admin',
                  displayName: 'Admin',
                  role: 'admin',
                  storeId: 'store_001',
                ))),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          ],
        );

        final selected = container.read(selectedBranchesProvider);
        expect(selected, containsAll(['store_001', 'store_002']));

        final resolved = StoreResolverHelper.resolveTargetStoreIds(
          selected,
          currentStoreId: container.read(currentStoreIdProvider),
          user: container.read(authProvider),
        );
        expect(resolved, containsAll(['store_001', 'store_002']));
        expect(resolved.length, equals(2));
      });

      test('Branch toggling updates resolved targetStoreIds correctly', () {
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

        // Toggle off store_002 -> only store_001 remains
        notifier.toggleBranch('store_002');
        final singleSelected = container.read(selectedBranchesProvider);
        expect(singleSelected, equals(['store_001']));

        final resolvedSingle = StoreResolverHelper.resolveTargetStoreIds(
          singleSelected,
          user: container.read(authProvider),
        );
        expect(resolvedSingle, equals(['store_001']));

        // Select all
        notifier.selectAll();
        final allSelected = container.read(selectedBranchesProvider);
        expect(allSelected, containsAll(['store_001', 'store_002']));

        final resolvedAll = StoreResolverHelper.resolveTargetStoreIds(
          allSelected,
          user: container.read(authProvider),
        );
        expect(resolvedAll, containsAll(['store_001', 'store_002']));
      });
    });
  });
}
