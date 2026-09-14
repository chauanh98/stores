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
import 'package:stores/presentation/customers/widgets/customer_list_tile.dart';
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
  _FakeCustomerListNotifier(this._initialCustomers);

  final List<Customer> _initialCustomers;

  @override
  Future<List<Customer>> build() async {
    return _initialCustomers;
  }

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_initialCustomers);
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
    username: 'admin_test',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const sampleCustomers = [
    Customer(
      id: 'cust_01',
      name: 'Khách Nợ Nhiều',
      phone: '0901111111',
      email: 'khach1@test.com',
      address: 'Hà Nội',
      purchases: [],
      currentDebt: 5000000.0,
      totalSales: 12000000.0,
      createdAt: '2026-09-01 10:00:00',
    ),
    Customer(
      id: 'cust_02',
      name: 'Khách Nợ Vừa',
      phone: '0902222222',
      email: 'khach2@test.com',
      address: 'Đà Nẵng',
      purchases: [],
      currentDebt: 1200000.0,
      totalSales: 8000000.0,
      createdAt: '2026-09-02 10:00:00',
    ),
    Customer(
      id: 'cust_03',
      name: 'Khách Hết Nợ',
      phone: '0903333333',
      email: 'khach3@test.com',
      address: 'TP.HCM',
      purchases: [],
      currentDebt: 0.0,
      totalSales: 5000000.0,
      createdAt: '2026-09-03 10:00:00',
    ),
    Customer(
      id: 'cust_04',
      name: 'Khách Không Nợ',
      phone: '0904444444',
      email: 'khach4@test.com',
      address: 'Cần Thơ',
      purchases: [],
      currentDebt: null,
      totalSales: 3000000.0,
      createdAt: '2026-09-04 10:00:00',
    ),
  ];

  List<Override> commonOverrides({
    List<Customer> customers = sampleCustomers,
  }) {
    return [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
      customerListNotifierProvider
          .overrideWith(() => _FakeCustomerListNotifier(customers)),
      for (final c in customers) ...[
        customerOrdersProvider(c.id)
            .overrideWith((ref) => Stream.value(<Order>[])),
        customerDebtTransactionsProvider(c.id)
            .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
      ],
    ];
  }

  group('Customer Debt Filter - Provider Unit Tests', () {
    test('CustomerDebtFilter.all returns all customers', () async {
      final container = ProviderContainer(
        overrides: commonOverrides(),
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);

      container.read(customerDebtFilterProvider.notifier).state =
          CustomerDebtFilter.all;

      final processed = container.read(processedCustomersProvider);
      final customers = processed.value?.whereType<Customer>().toList() ?? [];

      expect(customers.length, equals(4));
    });

    test('CustomerDebtFilter.inDebt filters debt > 0 and sorts descending',
        () async {
      final container = ProviderContainer(
        overrides: commonOverrides(),
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);

      container.read(customerDebtFilterProvider.notifier).state =
          CustomerDebtFilter.inDebt;

      final processed = container.read(processedCustomersProvider);
      final customers = processed.value?.whereType<Customer>().toList() ?? [];

      expect(customers.length, equals(2));
      expect(customers[0].id, equals('cust_01')); // 5,000,000
      expect(customers[1].id, equals('cust_02')); // 1,200,000
      expect(customers[0].displayCurrentDebt,
          greaterThan(customers[1].displayCurrentDebt));
    });

    test('CustomerDebtFilter.cleared filters debt <= 0 or null', () async {
      final container = ProviderContainer(
        overrides: commonOverrides(),
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);

      container.read(customerDebtFilterProvider.notifier).state =
          CustomerDebtFilter.cleared;

      final processed = container.read(processedCustomersProvider);
      final customers = processed.value?.whereType<Customer>().toList() ?? [];

      expect(customers.length, equals(2));
      expect(customers.any((c) => c.id == 'cust_03'), isTrue);
      expect(customers.any((c) => c.id == 'cust_04'), isTrue);
    });

    test('customerDebtCountsProvider returns correct breakdown counts',
        () async {
      final container = ProviderContainer(
        overrides: commonOverrides(),
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);

      final counts = container.read(customerDebtCountsProvider);

      expect(counts[CustomerDebtFilter.all], equals(4));
      expect(counts[CustomerDebtFilter.inDebt], equals(2));
      expect(counts[CustomerDebtFilter.cleared], equals(2));
    });
  });

  group('Customer Debt Filter - UI & Widget Tests', () {
    testWidgets('Tab switching filters list correctly across all 3 tabs',
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

      // 1. Initial tab is "Tất cả": shows all 4 customers
      expect(find.text('Khách Nợ Nhiều'), findsOneWidget);
      expect(find.text('Khách Nợ Vừa'), findsOneWidget);
      expect(find.text('Khách Hết Nợ'), findsOneWidget);
      expect(find.text('Khách Không Nợ'), findsOneWidget);

      // Verify tab counts
      expect(find.byKey(const Key('debt_filter_tab_all')), findsOneWidget);
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsOneWidget);
      expect(find.byKey(const Key('debt_filter_tab_cleared')), findsOneWidget);

      // 2. Tap "Còn nợ" tab
      await tester.tap(find.byKey(const Key('debt_filter_tab_inDebt')));
      await tester.pumpAndSettle();

      // Indebted customers are visible
      expect(find.text('Khách Nợ Nhiều'), findsOneWidget);
      expect(find.text('Khách Nợ Vừa'), findsOneWidget);
      // Cleared customers are hidden
      expect(find.text('Khách Hết Nợ'), findsNothing);
      expect(find.text('Khách Không Nợ'), findsNothing);

      // 3. Tap "Hết nợ" tab
      await tester.tap(find.byKey(const Key('debt_filter_tab_cleared')));
      await tester.pumpAndSettle();

      // Cleared customers are visible
      expect(find.text('Khách Hết Nợ'), findsOneWidget);
      expect(find.text('Khách Không Nợ'), findsOneWidget);
      // Indebted customers are hidden
      expect(find.text('Khách Nợ Nhiều'), findsNothing);
      expect(find.text('Khách Nợ Vừa'), findsNothing);

      // 4. Tap "Tất cả" tab back
      await tester.tap(find.byKey(const Key('debt_filter_tab_all')));
      await tester.pumpAndSettle();

      expect(find.text('Khách Nợ Nhiều'), findsOneWidget);
      expect(find.text('Khách Nợ Vừa'), findsOneWidget);
      expect(find.text('Khách Hết Nợ'), findsOneWidget);
      expect(find.text('Khách Không Nợ'), findsOneWidget);
    });

    testWidgets(
        'Initial debt filter activates "Còn nợ" automatically on mount',
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

      // Should automatically be filtered to inDebt
      expect(find.text('Khách Nợ Nhiều'), findsOneWidget);
      expect(find.text('Khách Nợ Vừa'), findsOneWidget);
      expect(find.text('Khách Hết Nợ'), findsNothing);
      expect(find.text('Khách Không Nợ'), findsNothing);
    });

    testWidgets('Live total debt calculation is accurate and updates with tabs',
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

      // In "Tất cả" tab: Total debt = 5,000,000 + 1,200,000 = 6,200,000
      final totalDebtTextFinder =
          find.byKey(const Key('total_debt_summary_text'));
      expect(totalDebtTextFinder, findsOneWidget);
      expect(
        (tester.widget(totalDebtTextFinder) as Text).data,
        equals(currencyFormat.format(6200000.0)),
      );

      // Switch to "Còn nợ": Total debt still 6,200,000
      await tester.tap(find.byKey(const Key('debt_filter_tab_inDebt')));
      await tester.pumpAndSettle();
      expect(
        (tester.widget(totalDebtTextFinder) as Text).data,
        equals(currencyFormat.format(6200000.0)),
      );

      // Switch to "Hết nợ": Total debt is 0
      await tester.tap(find.byKey(const Key('debt_filter_tab_cleared')));
      await tester.pumpAndSettle();
      expect(
        (tester.widget(totalDebtTextFinder) as Text).data,
        equals(currencyFormat.format(0.0)),
      );
    });

    testWidgets('Debt badge is prominently rendered for indebted customers',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: CustomerListTile(customer: sampleCustomers[0]),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Check debt badge container
      final badgeFinder =
          find.byKey(Key('debt_badge_${sampleCustomers[0].id}'));
      expect(badgeFinder, findsOneWidget);

      // Check warning icon inside badge
      expect(
        find.descendant(
            of: badgeFinder,
            matching: find.byIcon(Icons.warning_amber_rounded)),
        findsOneWidget,
      );

      // Check debt amount text formatted
      expect(
        find.descendant(
          of: badgeFinder,
          matching: find.textContaining(currencyFormat.format(5000000.0)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Debt badge is NOT rendered for customers without debt',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: CustomerListTile(customer: sampleCustomers[2]),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      final badgeFinder =
          find.byKey(Key('debt_badge_${sampleCustomers[2].id}'));
      expect(badgeFinder, findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets(
        'QuickActionsBar "Sổ nợ khách" navigates to CustomersPage with inDebt filter',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const QuickActionsBar(),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Sổ nợ khách" button
      await tester.tap(find.text('Sổ nợ khách'));
      await tester.pumpAndSettle();

      // Verify CustomersPage pushed with inDebt filter active
      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.text('Khách Nợ Nhiều'), findsOneWidget);
      expect(find.text('Khách Nợ Vừa'), findsOneWidget);
      expect(find.text('Khách Hết Nợ'), findsNothing);
    });

    testWidgets(
        'KPIMetricsSection customer debt card navigates to CustomersPage with inDebt filter',
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
        customerDebt: 6200000,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const SingleChildScrollView(
            child: KPIMetricsSection(),
          ),
          overrides: [
            ...commonOverrides(),
            overviewKPIsProvider.overrideWith((ref) => const AsyncValue.data(fakeKpis)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap the customer debt card
      final debtCardFinder = find.text('Công nợ khách hàng cần thu');
      expect(debtCardFinder, findsOneWidget);
      await tester.tap(debtCardFinder);
      await tester.pumpAndSettle();

      // Verify CustomersPage pushed with inDebt filter active
      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.text('Khách Nợ Nhiều'), findsOneWidget);
      expect(find.text('Khách Nợ Vừa'), findsOneWidget);
      expect(find.text('Khách Hết Nợ'), findsNothing);
    });
  });
}
