import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/reports/widgets/kpi_metrics_section.dart';
import 'package:stores/presentation/reports/widgets/quick_actions_bar.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _FakeCustomerListNotifier
    extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _FakeCustomerListNotifier(this._customers);

  final List<Customer> _customers;

  @override
  Future<List<Customer>> build() async => _customers;

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_customers);
  }
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Material(
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final currencyFormat = NumberFormat('#,###', 'vi_VN');

  const adminUser = UserAccount(
    username: 'admin_lifecycle',
    displayName: 'Admin Tester',
    role: 'admin',
    storeId: 'store_001',
  );

  final lifecycleCustomers = [
    const Customer(
      id: 'cust_debt_10m',
      name: 'Khách Nợ Mười Triệu',
      phone: '0911000001',
      email: 'debt10m@test.com',
      address: 'Hà Nội',
      purchases: [],
      currentDebt: 10000000.0,
      totalSales: 25000000.0,
      createdAt: '2026-09-01 10:00:00',
    ),
    const Customer(
      id: 'cust_debt_3m',
      name: 'Khách Nợ Ba Triệu',
      phone: '0911000002',
      email: 'debt3m@test.com',
      address: 'Đà Nẵng',
      purchases: [],
      currentDebt: 3000000.0,
      totalSales: 15000000.0,
      createdAt: '2026-09-02 10:00:00',
    ),
    const Customer(
      id: 'cust_cleared_zero',
      name: 'Khách Nợ Không Đồng',
      phone: '0911000003',
      email: 'cleared0@test.com',
      address: 'TP.HCM',
      purchases: [],
      currentDebt: 0.0,
      totalSales: 8000000.0,
      createdAt: '2026-09-03 10:00:00',
    ),
    const Customer(
      id: 'cust_cleared_null',
      name: 'Khách Nợ Null',
      phone: '0911000004',
      email: 'clearednull@test.com',
      address: 'Cần Thơ',
      purchases: [],
      currentDebt: null,
      totalSales: 4000000.0,
      createdAt: '2026-09-04 10:00:00',
    ),
  ];

  List<Override> commonOverrides({
    List<Customer>? customers,
  }) {
    final list = customers ?? lifecycleCustomers;
    return [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
      customerListNotifierProvider
          .overrideWith(() => _FakeCustomerListNotifier(list)),
      for (final c in list) ...[
        customerOrdersProvider(c.id)
            .overrideWith((ref) => Stream.value(<Order>[])),
        customerDebtTransactionsProvider(c.id)
            .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
      ],
    ];
  }

  group('Adversarial Challenge: Initial Filter Parameter Resolution', () {
    testWidgets(
        'CustomersPage(initialDebtFilter: CustomerDebtFilter.inDebt) settles to inDebt filter',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(
            initialDebtFilter: CustomerDebtFilter.inDebt,
          ),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Indebted customers are visible and sorted descending
      expect(find.text('Khách Nợ Mười Triệu'), findsOneWidget);
      expect(find.text('Khách Nợ Ba Triệu'), findsOneWidget);
      // Cleared customers are hidden
      expect(find.text('Khách Nợ Không Đồng'), findsNothing);
      expect(find.text('Khách Nợ Null'), findsNothing);

      // Verify Total Debt Calculation = 10,000,000 + 3,000,000 = 13,000,000
      final totalDebtFinder = find.byKey(const Key('total_debt_summary_text'));
      expect(
        (tester.widget(totalDebtFinder) as Text).data,
        equals(currencyFormat.format(13000000.0)),
      );
    });

    testWidgets('CustomersPage() default parameter settles to all filter',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // All 4 customers visible
      expect(find.text('Khách Nợ Mười Triệu'), findsOneWidget);
      expect(find.text('Khách Nợ Ba Triệu'), findsOneWidget);
      expect(find.text('Khách Nợ Không Đồng'), findsOneWidget);
      expect(find.text('Khách Nợ Null'), findsOneWidget);
    });

    testWidgets(
        'CustomersPage(initialDebtFilter: CustomerDebtFilter.cleared) settles to cleared filter',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(
            initialDebtFilter: CustomerDebtFilter.cleared,
          ),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Only cleared customers visible
      expect(find.text('Khách Nợ Không Đồng'), findsOneWidget);
      expect(find.text('Khách Nợ Null'), findsOneWidget);
      expect(find.text('Khách Nợ Mười Triệu'), findsNothing);
      expect(find.text('Khách Nợ Ba Triệu'), findsNothing);

      // Total debt in cleared tab is 0
      final totalDebtFinder = find.byKey(const Key('total_debt_summary_text'));
      expect(
        (tester.widget(totalDebtFinder) as Text).data,
        equals(currencyFormat.format(0.0)),
      );
    });
  });

  group('Adversarial Challenge: Navigation from Overview Widgets', () {
    testWidgets(
        'QuickActionsBar: Tap "Sổ nợ khách" -> Pop -> Tap again re-initializes inDebt cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const Scaffold(
            body: QuickActionsBar(),
          ),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Tap "Sổ nợ khách"
      await tester.tap(find.text('Sổ nợ khách'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.text('Khách Nợ Mười Triệu'), findsOneWidget);
      expect(find.text('Khách Nợ Không Đồng'), findsNothing);

      // Switch to "Hết nợ" tab while inside
      await tester.tap(find.byKey(const Key('debt_filter_tab_cleared')));
      await tester.pumpAndSettle();
      expect(find.text('Khách Nợ Không Đồng'), findsOneWidget);

      // 2. Pop the page via back button
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      // We are back at QuickActionsBar, CustomersPage unmounted
      expect(find.byType(CustomersPage), findsNothing);
      expect(find.text('Sổ nợ khách'), findsOneWidget);

      // 3. Tap "Sổ nợ khách" again
      await tester.tap(find.text('Sổ nợ khách'));
      await tester.pumpAndSettle();

      // Should open inDebt AGAIN, not stale "cleared"!
      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.text('Khách Nợ Mười Triệu'), findsOneWidget);
      expect(find.text('Khách Nợ Không Đồng'), findsNothing);
    });

    testWidgets(
        'KPIMetricsSection: Tap "Công nợ khách hàng cần thu" -> CustomersPage with inDebt',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const fakeKpis = OverviewKPIs(
        netRevenue: 50000000,
        orderCount: 50,
        grossProfit: 20000000,
        aov: 1000000,
        customerDebt: 13000000,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const Scaffold(
            body: SingleChildScrollView(
              child: KPIMetricsSection(),
            ),
          ),
          overrides: [
            ...commonOverrides(),
            overviewKPIsProvider
                .overrideWith((ref) => const AsyncValue.data(fakeKpis)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final kpiCardFinder = find.text('Công nợ khách hàng cần thu');
      expect(kpiCardFinder, findsOneWidget);

      await tester.tap(kpiCardFinder);
      await tester.pumpAndSettle();

      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.text('Khách Nợ Mười Triệu'), findsOneWidget);
      expect(find.text('Khách Nợ Không Đồng'), findsNothing);

      // Pop back
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.byType(CustomersPage), findsNothing);
      expect(kpiCardFinder, findsOneWidget);
    });
  });

  group('Adversarial Challenge: autoDispose & Stale State Cleanup', () {
    testWidgets(
        'Pop CustomersPage with altered tab and search query -> Reopen default CustomersPage has clean state',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Setup a test host that can push CustomersPage with custom initial filter or default
      await tester.pumpWidget(
        _buildTestApp(
          child: Scaffold(
            body: Builder(
              builder: (ctx) => Column(
                children: [
                  ElevatedButton(
                    key: const Key('btn_open_in_debt'),
                    onPressed: () {
                      Navigator.of(ctx).push(
                        MaterialPageRoute(
                          builder: (_) => const CustomersPage(
                            initialDebtFilter: CustomerDebtFilter.inDebt,
                          ),
                        ),
                      );
                    },
                    child: const Text('Open inDebt'),
                  ),
                  ElevatedButton(
                    key: const Key('btn_open_default'),
                    onPressed: () {
                      Navigator.of(ctx).push(
                        MaterialPageRoute(
                          builder: (_) => const CustomersPage(),
                        ),
                      );
                    },
                    child: const Text('Open Default'),
                  ),
                ],
              ),
            ),
          ),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Open CustomersPage with inDebt
      await tester.tap(find.byKey(const Key('btn_open_in_debt')));
      await tester.pumpAndSettle();

      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.text('Khách Nợ Mười Triệu'), findsOneWidget);

      // Switch to "Hết nợ"
      await tester.tap(find.byKey(const Key('debt_filter_tab_cleared')));
      await tester.pumpAndSettle();
      expect(find.text('Khách Nợ Không Đồng'), findsOneWidget);

      // Type a search query into the search box
      final searchBox = find.byType(TextField);
      await tester.enterText(searchBox, 'Không Đồng');
      await tester.pumpAndSettle();
      expect(find.text('Khách Nợ Không Đồng'), findsOneWidget);
      expect(find.text('Khách Nợ Null'), findsNothing);

      // 2. Pop CustomersPage
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.byType(CustomersPage), findsNothing);

      // 3. Now open CustomersPage with default (all)
      await tester.tap(find.byKey(const Key('btn_open_default')));
      await tester.pumpAndSettle();

      // Verify:
      // a) Search text is EMPTY (no stale "Không Đồng")
      final newSearchBox = find.byType(TextField);
      expect((tester.widget(newSearchBox) as TextField).controller?.text,
          isEmpty);

      // b) All customers are visible (tab reset to "Tất cả", NOT stale "Hết nợ" or "Còn nợ")
      expect(find.text('Khách Nợ Mười Triệu'), findsOneWidget);
      expect(find.text('Khách Nợ Ba Triệu'), findsOneWidget);
      expect(find.text('Khách Nợ Không Đồng'), findsOneWidget);
      expect(find.text('Khách Nợ Null'), findsOneWidget);
    });
  });

  group('Adversarial Challenge: Rapid Tapping & Edge Lifecycles', () {
    testWidgets('Rapid tab switching does not crash and converges to final tap',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      final tabAll = find.byKey(const Key('debt_filter_tab_all'));
      final tabInDebt = find.byKey(const Key('debt_filter_tab_inDebt'));
      final tabCleared = find.byKey(const Key('debt_filter_tab_cleared'));

      // Rapidly fire taps without waiting for settling
      await tester.tap(tabInDebt);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(tabCleared);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(tabAll);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(tabInDebt);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(tabCleared);

      // Now let animations and microtasks settle
      await tester.pumpAndSettle();

      // Final tab was tabCleared
      expect(find.text('Khách Nợ Không Đồng'), findsOneWidget);
      expect(find.text('Khách Nợ Null'), findsOneWidget);
      expect(find.text('Khách Nợ Mười Triệu'), findsNothing);
      expect(find.text('Khách Nợ Ba Triệu'), findsNothing);
    });

    testWidgets('Rapid push and immediate pop before frame callback survives',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late BuildContext hostContext;

      await tester.pumpWidget(
        _buildTestApp(
          child: Scaffold(
            body: Builder(
              builder: (ctx) {
                hostContext = ctx;
                return const Text('Host Screen');
              },
            ),
          ),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Push CustomersPage
      Navigator.of(hostContext).push(
        MaterialPageRoute(
          builder: (_) => const CustomersPage(
            initialDebtFilter: CustomerDebtFilter.inDebt,
          ),
        ),
      );

      // Pop immediately in the next microtick without settling
      await tester.pump();
      Navigator.of(hostContext).pop();
      await tester.pumpAndSettle();

      // Must be cleanly back at Host Screen with zero exceptions
      expect(find.text('Host Screen'), findsOneWidget);
      expect(find.byType(CustomersPage), findsNothing);
    });

    testWidgets(
        'didUpdateWidget dynamically switches active tab if parent alters initialDebtFilter',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      CustomerDebtFilter dynamicFilter = CustomerDebtFilter.all;
      late StateSetter parentSetState;

      await tester.pumpWidget(
        _buildTestApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              parentSetState = setState;
              return CustomersPage(initialDebtFilter: dynamicFilter);
            },
          ),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Initially all
      expect(find.text('Khách Nợ Mười Triệu'), findsOneWidget);
      expect(find.text('Khách Nợ Không Đồng'), findsOneWidget);

      // Dynamically change filter to inDebt
      parentSetState(() {
        dynamicFilter = CustomerDebtFilter.inDebt;
      });
      await tester.pumpAndSettle();

      // Now only inDebt should be visible
      expect(find.text('Khách Nợ Mười Triệu'), findsOneWidget);
      expect(find.text('Khách Nợ Không Đồng'), findsNothing);
    });

    testWidgets(
        'Navigation to inDebt when zero customers have debt displays empty state gracefully',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final zeroDebtCustomers = [
        lifecycleCustomers[2], // currentDebt: 0.0
        lifecycleCustomers[3], // currentDebt: null
      ];

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(
            initialDebtFilter: CustomerDebtFilter.inDebt,
          ),
          overrides: commonOverrides(customers: zeroDebtCustomers),
        ),
      );
      await tester.pumpAndSettle();

      // Tab count for inDebt should be 0
      final inDebtTab = find.byKey(const Key('debt_filter_tab_inDebt'));
      expect(
        find.descendant(of: inDebtTab, matching: find.text('0')),
        findsOneWidget,
      );

      // Empty state icons/text rendered
      expect(find.byIcon(Icons.people_outline), findsOneWidget);
      expect(find.text('Chưa có khách hàng nào'), findsOneWidget);

      // Total debt is 0
      final totalDebtFinder = find.byKey(const Key('total_debt_summary_text'));
      expect(
        (tester.widget(totalDebtFinder) as Text).data,
        equals(currencyFormat.format(0.0)),
      );

      // Switching to "Tất cả" shows the 2 zero-debt customers
      await tester.tap(find.byKey(const Key('debt_filter_tab_all')));
      await tester.pumpAndSettle();

      expect(find.text('Khách Nợ Không Đồng'), findsOneWidget);
      expect(find.text('Khách Nợ Null'), findsOneWidget);
    });
  });
}
