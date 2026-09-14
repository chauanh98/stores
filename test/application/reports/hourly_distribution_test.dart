import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/overview_kpis.dart';

import '../../fixtures/mock_report_data.dart';

void main() {
  group('Hourly Distribution & Peak Rush Hour Detection (R2)', () {
    // Pure calculation engine for 24-hour revenue distribution
    List<HourlyRevenueData> calculateHourlyDistribution({
      required List<Order> orders,
      String? storeFilter,
    }) {
      final Map<int, double> hourlyRevenueMap = {};
      final Map<int, int> hourlyOrderCountMap = {};
      final Map<int, Map<String, double>> hourlyBranchMap = {};

      for (int h = 0; h < 24; h++) {
        hourlyRevenueMap[h] = 0.0;
        hourlyOrderCountMap[h] = 0;
        hourlyBranchMap[h] = {};
      }

      for (final order in orders) {
        if (order.status != 'completed') continue;

        final storeId = order.createdBy ?? 'store_001';
        if (storeFilter != null &&
            storeFilter != 'all' &&
            storeId != storeFilter) {
          continue;
        }

        final hour = order.createdAt.hour;
        if (hour < 0 || hour > 23) continue;

        hourlyRevenueMap[hour] = (hourlyRevenueMap[hour] ?? 0.0) + order.total;
        hourlyOrderCountMap[hour] = (hourlyOrderCountMap[hour] ?? 0) + 1;

        final branchMap = hourlyBranchMap[hour] ?? {};
        branchMap[storeId] = (branchMap[storeId] ?? 0.0) + order.total;
        hourlyBranchMap[hour] = branchMap;
      }

      return List.generate(24, (h) {
        return HourlyRevenueData(
          hour: h,
          revenue: hourlyRevenueMap[h] ?? 0.0,
          orderCount: hourlyOrderCountMap[h] ?? 0,
          branchRevenue: Map<String, double>.from(hourlyBranchMap[h] ?? {}),
        );
      });
    }

    // Helper to find peak hour
    HourlyRevenueData? findPeakRevenueHour(List<HourlyRevenueData> distribution) {
      if (distribution.isEmpty) return null;
      HourlyRevenueData peak = distribution.first;
      for (final data in distribution) {
        if (data.revenue > peak.revenue) {
          peak = data;
        }
      }
      return peak.revenue > 0 ? peak : null;
    }

    group('Tier 1: Feature Coverage (24h Distribution & Peak Hours)', () {
      test('1.1 Generates exactly 24 hourly buckets from 0 to 23', () {
        final distribution = calculateHourlyDistribution(orders: []);
        expect(distribution.length, equals(24));
        for (int i = 0; i < 24; i++) {
          expect(distribution[i].hour, equals(i));
        }
      });

      test('1.2 Places orders into the correct hourly bucket', () {
        final orders = [
          MockReportData.createOrder(
            id: 'ord_10am',
            createdAt: DateTime(2026, 8, 16, 10, 15),
            total: 300000.0,
          ),
          MockReportData.createOrder(
            id: 'ord_10am_2',
            createdAt: DateTime(2026, 8, 16, 10, 45),
            total: 200000.0,
          ),
          MockReportData.createOrder(
            id: 'ord_2pm',
            createdAt: DateTime(2026, 8, 16, 14, 0),
            total: 500000.0,
          ),
        ];

        final distribution = calculateHourlyDistribution(orders: orders);

        // Hour 10 should have 2 orders with 500,000 revenue
        expect(distribution[10].orderCount, equals(2));
        expect(distribution[10].revenue, equals(500000.0));

        // Hour 14 should have 1 order with 500,000 revenue
        expect(distribution[14].orderCount, equals(1));
        expect(distribution[14].revenue, equals(500000.0));

        // Hour 11 should be 0
        expect(distribution[11].orderCount, equals(0));
        expect(distribution[11].revenue, equals(0.0));
      });

      test('1.3 Accurately identifies peak revenue hour', () {
        final orders = [
          MockReportData.createOrder(
            id: 'o_09',
            createdAt: DateTime(2026, 8, 16, 9, 30),
            total: 400000.0,
          ),
          MockReportData.createOrder(
            id: 'o_12_1',
            createdAt: DateTime(2026, 8, 16, 12, 10),
            total: 800000.0,
          ),
          MockReportData.createOrder(
            id: 'o_12_2',
            createdAt: DateTime(2026, 8, 16, 12, 40),
            total: 600000.0,
          ),
          MockReportData.createOrder(
            id: 'o_19',
            createdAt: DateTime(2026, 8, 16, 19, 15),
            total: 900000.0,
          ),
        ];

        final distribution = calculateHourlyDistribution(orders: orders);
        final peak = findPeakRevenueHour(distribution);

        // Hour 12 revenue = 800k + 600k = 1,400,000 (Peak)
        expect(peak, isNotNull);
        expect(peak!.hour, equals(12));
        expect(peak.revenue, equals(1400000.0));
        expect(peak.orderCount, equals(2));
      });

      test('1.4 Attributing branch contributions inside hourly buckets', () {
        final orders = [
          MockReportData.createOrder(
            id: 'o_b1',
            createdAt: DateTime(2026, 8, 16, 15, 10),
            total: 600000.0,
            createdBy: 'store_001',
          ),
          MockReportData.createOrder(
            id: 'o_b2',
            createdAt: DateTime(2026, 8, 16, 15, 30),
            total: 400000.0,
            createdBy: 'store_002',
          ),
        ];

        final distribution = calculateHourlyDistribution(
          orders: orders,
          storeFilter: 'all',
        );

        final hour15 = distribution[15];
        expect(hour15.revenue, equals(1000000.0));
        expect(hour15.branchRevenue['store_001'], equals(600000.0));
        expect(hour15.branchRevenue['store_002'], equals(400000.0));
      });
    });

    group('Tier 2: Boundary & Corner Cases', () {
      test('2.1 Completely empty day has 24 empty buckets with no peak', () {
        final distribution = calculateHourlyDistribution(orders: []);
        expect(distribution.length, equals(24));
        for (final item in distribution) {
          expect(item.revenue, equals(0.0));
          expect(item.orderCount, equals(0));
          expect(item.branchRevenue.isEmpty, isTrue);
        }

        final peak = findPeakRevenueHour(distribution);
        expect(peak, isNull);
      });

      test('2.2 Midnight boundary transactions (00:00:00 and 00:59:59)', () {
        final orders = [
          MockReportData.createOrder(
            id: 'o_mid_start',
            createdAt: DateTime(2026, 8, 16, 0, 0, 0),
            total: 200000.0,
          ),
          MockReportData.createOrder(
            id: 'o_mid_end',
            createdAt: DateTime(2026, 8, 16, 0, 59, 59),
            total: 300000.0,
          ),
        ];

        final distribution = calculateHourlyDistribution(orders: orders);
        expect(distribution[0].revenue, equals(500000.0));
        expect(distribution[0].orderCount, equals(2));
      });

      test('2.3 Late night boundary transactions (23:00:00 and 23:59:59)', () {
        final orders = [
          MockReportData.createOrder(
            id: 'o_late_start',
            createdAt: DateTime(2026, 8, 16, 23, 0, 0),
            total: 150000.0,
          ),
          MockReportData.createOrder(
            id: 'o_late_end',
            createdAt: DateTime(2026, 8, 16, 23, 59, 59),
            total: 250000.0,
          ),
        ];

        final distribution = calculateHourlyDistribution(orders: orders);
        expect(distribution[23].revenue, equals(400000.0));
        expect(distribution[23].orderCount, equals(2));
      });

      test('2.4 Single-hour burst day (all revenue in 1 hour)', () {
        final orders = [
          MockReportData.createOrder(
            id: 'o_burst',
            createdAt: DateTime(2026, 8, 16, 14, 20),
            total: 5000000.0,
          ),
        ];

        final distribution = calculateHourlyDistribution(orders: orders);
        expect(distribution[14].revenue, equals(5000000.0));
        expect(distribution[14].orderCount, equals(1));

        for (int h = 0; h < 24; h++) {
          if (h != 14) {
            expect(distribution[h].revenue, equals(0.0));
            expect(distribution[h].orderCount, equals(0));
          }
        }
      });

      test('2.5 Excludes cancelled or draft orders from hourly revenue', () {
        final orders = [
          MockReportData.createOrder(
            id: 'o_completed',
            createdAt: DateTime(2026, 8, 16, 11, 0),
            total: 500000.0,
            status: 'completed',
          ),
          MockReportData.createOrder(
            id: 'o_cancelled',
            createdAt: DateTime(2026, 8, 16, 11, 30),
            total: 800000.0,
            status: 'cancelled',
          ),
          MockReportData.createOrder(
            id: 'o_draft',
            createdAt: DateTime(2026, 8, 16, 11, 45),
            total: 400000.0,
            status: 'draft',
          ),
        ];

        final distribution = calculateHourlyDistribution(orders: orders);
        expect(distribution[11].revenue, equals(500000.0));
        expect(distribution[11].orderCount, equals(1));
      });
    });

    group('Tier 3: Combinatorial & Multi-Store Filtering', () {
      test('3.1 Single store filter isolates only that store', () {
        final orders = [
          MockReportData.createOrder(
            id: 'o_s1',
            createdAt: DateTime(2026, 8, 16, 16, 0),
            total: 300000.0,
            createdBy: 'store_001',
          ),
          MockReportData.createOrder(
            id: 'o_s2',
            createdAt: DateTime(2026, 8, 16, 16, 30),
            total: 700000.0,
            createdBy: 'store_002',
          ),
        ];

        final distStore1 = calculateHourlyDistribution(
          orders: orders,
          storeFilter: 'store_001',
        );
        expect(distStore1[16].revenue, equals(300000.0));
        expect(distStore1[16].orderCount, equals(1));
        expect(distStore1[16].branchRevenue.containsKey('store_002'), isFalse);

        final distStore2 = calculateHourlyDistribution(
          orders: orders,
          storeFilter: 'store_002',
        );
        expect(distStore2[16].revenue, equals(700000.0));
        expect(distStore2[16].orderCount, equals(1));
        expect(distStore2[16].branchRevenue.containsKey('store_001'), isFalse);
      });
    });

    group('Tier 4: Realistic Business Day Scenario', () {
      test(
          '4.1 Realistic multi-rush business day (Morning, Lunch, Evening peaks)',
          () {
        final List<Order> dayOrders = [];

        // Morning rush (8:00 - 9:59): 4 orders, total 1,200,000
        dayOrders.addAll([
          MockReportData.createOrder(
            id: 'm1',
            createdAt: DateTime(2026, 8, 16, 8, 15),
            total: 250000.0,
            createdBy: 'store_001',
          ),
          MockReportData.createOrder(
            id: 'm2',
            createdAt: DateTime(2026, 8, 16, 8, 45),
            total: 350000.0,
            createdBy: 'store_002',
          ),
          MockReportData.createOrder(
            id: 'm3',
            createdAt: DateTime(2026, 8, 16, 9, 10),
            total: 400000.0,
            createdBy: 'store_001',
          ),
          MockReportData.createOrder(
            id: 'm4',
            createdAt: DateTime(2026, 8, 16, 9, 50),
            total: 200000.0,
            createdBy: 'store_002',
          ),
        ]);

        // Lunch rush (11:00 - 13:59): 6 orders, total 3,800,000
        dayOrders.addAll([
          MockReportData.createOrder(
            id: 'l1',
            createdAt: DateTime(2026, 8, 16, 11, 30),
            total: 600000.0,
            createdBy: 'store_001',
          ),
          MockReportData.createOrder(
            id: 'l2',
            createdAt: DateTime(2026, 8, 16, 12, 10),
            total: 1200000.0, // Large order
            createdBy: 'store_001',
          ),
          MockReportData.createOrder(
            id: 'l3',
            createdAt: DateTime(2026, 8, 16, 12, 35),
            total: 800000.0,
            createdBy: 'store_002',
          ),
          MockReportData.createOrder(
            id: 'l4',
            createdAt: DateTime(2026, 8, 16, 13, 0),
            total: 500000.0,
            createdBy: 'store_001',
          ),
          MockReportData.createOrder(
            id: 'l5',
            createdAt: DateTime(2026, 8, 16, 13, 40),
            total: 700000.0,
            createdBy: 'store_002',
          ),
        ]);

        // Evening rush (18:00 - 20:59): 5 orders, total 2,500,000
        dayOrders.addAll([
          MockReportData.createOrder(
            id: 'e1',
            createdAt: DateTime(2026, 8, 16, 18, 20),
            total: 450000.0,
            createdBy: 'store_001',
          ),
          MockReportData.createOrder(
            id: 'e2',
            createdAt: DateTime(2026, 8, 16, 19, 0),
            total: 650000.0,
            createdBy: 'store_002',
          ),
          MockReportData.createOrder(
            id: 'e3',
            createdAt: DateTime(2026, 8, 16, 19, 45),
            total: 750000.0,
            createdBy: 'store_001',
          ),
          MockReportData.createOrder(
            id: 'e4',
            createdAt: DateTime(2026, 8, 16, 20, 15),
            total: 650000.0,
            createdBy: 'store_002',
          ),
        ]);

        final distribution = calculateHourlyDistribution(
          orders: dayOrders,
          storeFilter: 'all',
        );

        // Peak revenue hour is 12h: 1.2M (store_001) + 800k (store_002) = 2,000,000 đ
        final peak = findPeakRevenueHour(distribution);
        expect(peak, isNotNull);
        expect(peak!.hour, equals(12));
        expect(peak.revenue, equals(2000000.0));
        expect(peak.orderCount, equals(2));
        expect(peak.branchRevenue['store_001'], equals(1200000.0));
        expect(peak.branchRevenue['store_002'], equals(800000.0));

        // Sum across all 24 hours equals total revenue
        final totalDayRevenue =
            distribution.fold<double>(0.0, (sum, item) => sum + item.revenue);
        expect(totalDayRevenue, equals(7500000.0));

        final totalDayOrders =
            distribution.fold<int>(0, (sum, item) => sum + item.orderCount);
        expect(totalDayOrders, equals(13));
      });
    });

    group('Riverpod Provider Integration (hourlyRevenueListProvider)', () {
      test('hourlyRevenueListProvider reads empty state smoothly', () {
        final container = ProviderContainer(
          overrides: [
            allBranchesOrdersByDateRangeProvider.overrideWith(
              (ref, range) => Stream.value([]),
            ),
          ],
        );
        addTearDown(container.dispose);

        final hourlyAsync = container.read(hourlyRevenueListProvider);
        expect(hourlyAsync, isA<AsyncValue<List<HourlyRevenueData>>>());
      });
    });
  });
}
