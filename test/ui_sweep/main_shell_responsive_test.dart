import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/notification_item.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/revenue_report.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/main.dart';

import 'sweep_harness.dart';

class _Customers extends CustomerListNotifier {
  @override
  Future<List<Customer>> build() async => [];
}

List<Override> _ov(UserAccount user) => [
      authProvider.overrideWith((ref) => SweepAuth(user)),
      currentStoreIdProvider.overrideWithValue('store_001'),
      currentStoreNameProvider.overrideWith((ref) async => sweepLongStore),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': sweepLongStore,
            'store_002': 'Chi nhánh Thới Bình',
          }),
      productListProvider
          .overrideWith((ref) => Stream.value(sweepProducts(60))),
      allStoresProductsProvider
          .overrideWith((ref) => Stream.value(sweepProducts(60))),
      categoryListProvider.overrideWith((ref) => Stream.value(<Category>[])),
      customerListNotifierProvider.overrideWith(() => _Customers()),
      allBranchesOrdersByDateRangeProvider
          .overrideWith((ref, r) => Stream.value(<Order>[])),
      allBranchesReturnOrdersByDateRangeProvider
          .overrideWith((ref, r) => Stream.value([])),
      posDraftOrdersProvider.overrideWith((ref) => Stream.value(<Order>[])),
      notificationStreamProvider
          .overrideWith((ref) => Stream.value(<NotificationItem>[])),
      popupNotificationStreamProvider
          .overrideWith((ref) => Stream.value(<NotificationItem>[])),
      revenueByDateRangeProvider.overrideWith((ref, r) => Stream.value(
          RevenueSummary(
              startDate: r.start,
              endDate: r.end,
              totalRevenue: 0,
              totalCost: 0,
              totalProfit: 0,
              totalOrders: 0,
              totalItemsSold: 0,
              dailyReports: const []))),
      overviewKPIsProvider
          .overrideWith((ref) => const AsyncValue.data(OverviewKPIs.empty)),
    ];

void main() {
  for (final s in sweepScreens.entries) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('AdaptiveScaffold shell @ ${s.key} x$scale', (tester) async {
        tester.view.physicalSize = s.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        debugSweepErrors();
        await tester.pumpWidget(sweepHost(
            const AdaptiveScaffold(), _ov(sweepStaff),
            textScale: scale));
        await tester.pump(const Duration(milliseconds: 500));
        expectNoException(tester);
        // switch through every tab
        final tapTargets = s.value.width > 600
            ? find.byType(NavigationRail)
            : find.byType(NavigationBar);
        expect(tapTargets, findsOneWidget);
        for (final icon in [
          Icons.inventory_2_outlined,
          Icons.receipt_long_outlined,
          Icons.menu,
          Icons.trending_up,
        ]) {
          await tester.tap(find
              .descendant(of: tapTargets, matching: find.byIcon(icon))
              .first);
          await tester.pump(const Duration(milliseconds: 500));
          expectNoException(tester);
        }
      });
    }
  }
}
