import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/customers/widgets/customer_list_tile.dart';

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
    username: 'admin_test',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff_test',
    displayName: 'Nhân viên',
    role: 'staff',
    storeId: 'store_001',
  );

  final adversarialCustomers = [
    const Customer(
      id: 'cust_micro_debt',
      name: 'Khách Nợ Siêu Nhỏ',
      phone: '0900000001',
      email: 'micro@test.com',
      address: 'Hà Nội',
      purchases: [],
      currentDebt: 0.0001,
      totalSales: 100000.0,
      createdAt: '2026-09-01 10:00:00',
      branch: 'store_001',
    ),
    const Customer(
      id: 'cust_zero_debt',
      name: 'Khách Nợ Bằng Không',
      phone: '0900000002',
      email: 'zero@test.com',
      address: 'Hà Nội',
      purchases: [],
      currentDebt: 0.0,
      totalSales: 500000.0,
      createdAt: '2026-09-02 10:00:00',
      branch: 'store_001',
    ),
    const Customer(
      id: 'cust_neg_zero_debt',
      name: 'Khách Nợ Âm Không',
      phone: '0900000003',
      email: 'negzero@test.com',
      address: 'Đà Nẵng',
      purchases: [],
      currentDebt: -0.0,
      totalSales: 200000.0,
      createdAt: '2026-09-03 10:00:00',
      branch: 'store_001',
    ),
    const Customer(
      id: 'cust_prepayment',
      name: 'Khách Trả Trước Nợ Âm',
      phone: '0900000004',
      email: 'prepayment@test.com',
      address: 'Hải Phòng',
      purchases: [],
      currentDebt: -500.0,
      totalSales: 300000.0,
      createdAt: '2026-09-04 10:00:00',
      branch: 'store_001',
    ),
    const Customer(
      id: 'cust_tie_1',
      name: 'Khách Đồng Hạng 1',
      phone: '0900000005',
      email: 'tie1@test.com',
      address: 'Cần Thơ',
      purchases: [],
      currentDebt: 2000000.0,
      totalSales: 4000000.0,
      createdAt: '2026-09-05 10:00:00',
      branch: 'store_001',
    ),
    const Customer(
      id: 'cust_tie_2',
      name: 'Khách Đồng Hạng 2',
      phone: '0900000006',
      email: 'tie2@test.com',
      address: 'TP.HCM',
      purchases: [],
      currentDebt: 2000000.0,
      totalSales: 6000000.0,
      createdAt: '2026-09-06 10:00:00',
      branch: 'store_001',
    ),
    const Customer(
      id: 'cust_large_debt',
      name: 'Khách Nợ Cực Lớn',
      phone: '0900000007',
      email: 'large@test.com',
      address: 'Bình Dương',
      purchases: [],
      currentDebt: 50000000.0,
      totalSales: 100000000.0,
      createdAt: '2026-09-07 10:00:00',
      branch: 'store_001',
    ),
    const Customer(
      id: 'cust_other_store',
      name: 'Khách Chi Nhánh Khác',
      phone: '0900000008',
      email: 'other@test.com',
      address: 'Huế',
      purchases: [],
      currentDebt: 10000000.0,
      totalSales: 20000000.0,
      createdAt: '2026-09-08 10:00:00',
      branch: 'store_002',
    ),
  ];

  List<Override> overridesFor({
    required UserAccount user,
    List<Customer>? customers,
  }) {
    final custList = customers ?? adversarialCustomers;
    return [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
      customerListNotifierProvider
          .overrideWith(() => _FakeCustomerListNotifier(custList)),
      for (final c in custList) ...[
        customerOrdersProvider(c.id)
            .overrideWith((ref) => Stream.value(<Order>[])),
        customerDebtTransactionsProvider(c.id)
            .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
      ],
    ];
  }

  group('Adversarial Challenge 1: Debt Boundary Edge Cases', () {
    test('debt = 0.0001 is categorized as inDebt', () async {
      final container = ProviderContainer(
        overrides: overridesFor(user: adminUser),
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);

      container.read(customerDebtFilterProvider.notifier).state =
          CustomerDebtFilter.inDebt;
      final processed = container.read(processedCustomersProvider);
      final list = processed.value?.whereType<Customer>().toList() ?? [];

      expect(list.any((c) => c.id == 'cust_micro_debt'), isTrue);
    });

    test('debt = 0.0 and debt = -0.0 are categorized as cleared', () async {
      final container = ProviderContainer(
        overrides: overridesFor(user: adminUser),
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);

      container.read(customerDebtFilterProvider.notifier).state =
          CustomerDebtFilter.cleared;
      final processed = container.read(processedCustomersProvider);
      final list = processed.value?.whereType<Customer>().toList() ?? [];

      expect(list.any((c) => c.id == 'cust_zero_debt'), isTrue);
      expect(list.any((c) => c.id == 'cust_neg_zero_debt'), isTrue);

      container.read(customerDebtFilterProvider.notifier).state =
          CustomerDebtFilter.inDebt;
      final inDebtList =
          container.read(processedCustomersProvider).value?.whereType<Customer>().toList() ?? [];

      expect(inDebtList.any((c) => c.id == 'cust_zero_debt'), isFalse);
      expect(inDebtList.any((c) => c.id == 'cust_neg_zero_debt'), isFalse);
    });

    test('debt = -500 (prepayment) is categorized as cleared, excluded from inDebt',
        () async {
      final container = ProviderContainer(
        overrides: overridesFor(user: adminUser),
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);

      final counts = container.read(customerDebtCountsProvider);
      // In debt customers: micro (0.0001), tie1 (2M), tie2 (2M), large (50M), otherStore (10M) = 5
      expect(counts[CustomerDebtFilter.inDebt], equals(5));
      // Cleared customers: zero (0), neg_zero (-0.0), prepayment (-500) = 3
      expect(counts[CustomerDebtFilter.cleared], equals(3));
      expect(counts[CustomerDebtFilter.all], equals(8));

      // Check cleared list
      container.read(customerDebtFilterProvider.notifier).state =
          CustomerDebtFilter.cleared;
      final clearedList =
          container.read(processedCustomersProvider).value?.whereType<Customer>().toList() ?? [];
      expect(clearedList.any((c) => c.id == 'cust_prepayment'), isTrue);

      // Check inDebt list
      container.read(customerDebtFilterProvider.notifier).state =
          CustomerDebtFilter.inDebt;
      final inDebtList =
          container.read(processedCustomersProvider).value?.whereType<Customer>().toList() ?? [];
      expect(inDebtList.any((c) => c.id == 'cust_prepayment'), isFalse);
    });
  });

  group('Adversarial Challenge 2: Identical Debt Sorting Stability', () {
    test('Customers with identical debt amounts do not crash sorting and maintain ordering',
        () async {
      final container = ProviderContainer(
        overrides: overridesFor(user: adminUser),
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);

      container.read(customerDebtFilterProvider.notifier).state =
          CustomerDebtFilter.inDebt;
      final processed = container.read(processedCustomersProvider);
      final list = processed.value?.whereType<Customer>().toList() ?? [];

      // Largest debt is first (50M)
      expect(list.first.id, equals('cust_large_debt'));
      // Smallest debt is last (0.0001)
      expect(list.last.id, equals('cust_micro_debt'));

      // Find indices of tie 1 and tie 2
      final idx1 = list.indexWhere((c) => c.id == 'cust_tie_1');
      final idx2 = list.indexWhere((c) => c.id == 'cust_tie_2');
      expect(idx1, isNot(equals(-1)));
      expect(idx2, isNot(equals(-1)));
      expect(list[idx1].displayCurrentDebt, equals(list[idx2].displayCurrentDebt));

      // Stability: Repeated reads must produce identical order
      final processedSecond = container.read(processedCustomersProvider);
      final listSecond = processedSecond.value?.whereType<Customer>().toList() ?? [];
      expect(listSecond.map((c) => c.id).toList(), equals(list.map((c) => c.id).toList()));
    });
  });

  group('Adversarial Challenge 3: Searching & Filtering Combined with Debt Tabs', () {
    testWidgets(
        'Searching inside "Còn nợ" filters only matching indebted customers and excludes cleared matching customers',
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
          overrides: overridesFor(user: adminUser),
        ),
      );
      await tester.pumpAndSettle();

      // In "Còn nợ" tab initially:
      expect(find.text('Khách Nợ Cực Lớn'), findsOneWidget);
      expect(find.text('Khách Đồng Hạng 1'), findsOneWidget);
      expect(find.text('Khách Trả Trước Nợ Âm'), findsNothing);
      expect(find.text('Khách Nợ Bằng Không'), findsNothing);

      // Search for "Không" (matches 'Khách Nợ Bằng Không' who has debt = 0)
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'Không');
      await tester.pumpAndSettle();

      // Even though name matches "Không", they must NOT appear because debt is 0!
      expect(find.text('Khách Nợ Bằng Không'), findsNothing);
      expect(find.text('Khách Nợ Cực Lớn'), findsNothing);
      // Empty state shown
      expect(find.text('Không tìm thấy'), findsOneWidget);

      // Now search for "Đồng Hạng"
      await tester.enterText(searchField, 'Đồng Hạng');
      await tester.pumpAndSettle();

      // Should find Khách Đồng Hạng 1 and Khách Đồng Hạng 2
      expect(find.text('Khách Đồng Hạng 1'), findsOneWidget);
      expect(find.text('Khách Đồng Hạng 2'), findsOneWidget);
      expect(find.text('Khách Nợ Cực Lớn'), findsNothing);

      // Live total debt text should reflect ONLY the filtered customers:
      // 2,000,000 + 2,000,000 = 4,000,000
      final totalDebtFinder = find.byKey(const Key('total_debt_summary_text'));
      expect(
        (tester.widget(totalDebtFinder) as Text).data,
        equals(currencyFormat.format(4000000.0)),
      );

      // Tab count for "Còn nợ" badge should reflect search result (2)
      final inDebtTab = find.byKey(const Key('debt_filter_tab_inDebt'));
      expect(
        find.descendant(of: inDebtTab, matching: find.text('2')),
        findsOneWidget,
      );

      // Clear search
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // Full inDebt list restored
      expect(find.text('Khách Nợ Cực Lớn'), findsOneWidget);
    });

    testWidgets(
        'Searching phone number inside "Còn nợ" isolates debtor and updates live total debt',
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
          overrides: overridesFor(user: adminUser),
        ),
      );
      await tester.pumpAndSettle();

      // Enter phone '0900000007' (Khách Nợ Cực Lớn: 50,000,000)
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, '0900000007');
      await tester.pumpAndSettle();

      expect(find.text('Khách Nợ Cực Lớn'), findsOneWidget);
      expect(find.text('Khách Đồng Hạng 1'), findsNothing);

      final totalDebtFinder = find.byKey(const Key('total_debt_summary_text'));
      expect(
        (tester.widget(totalDebtFinder) as Text).data,
        equals(currencyFormat.format(50000000.0)),
      );
    });
  });

  group('Adversarial Challenge 4: Live Total Debt Math Precision', () {
    testWidgets('Live total debt ignores negative debt (prepayments)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Only customers with negative or zero debt
      final nonIndebted = [
        adversarialCustomers[1], // 0.0
        adversarialCustomers[2], // -0.0
        adversarialCustomers[3], // -500.0
      ];

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(
            initialDebtFilter: CustomerDebtFilter.all,
          ),
          overrides: overridesFor(user: adminUser, customers: nonIndebted),
        ),
      );
      await tester.pumpAndSettle();

      final totalDebtFinder = find.byKey(const Key('total_debt_summary_text'));
      expect(
        (tester.widget(totalDebtFinder) as Text).data,
        equals(currencyFormat.format(0.0)),
      );
    });

    testWidgets('Live total debt in "Hết nợ" tab is strictly zero',
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
          overrides: overridesFor(user: adminUser),
        ),
      );
      await tester.pumpAndSettle();

      final totalDebtFinder = find.byKey(const Key('total_debt_summary_text'));
      expect(
        (tester.widget(totalDebtFinder) as Text).data,
        equals(currencyFormat.format(0.0)),
      );
    });
  });

  group('Adversarial Challenge 5: Staff Store Scoping Isolation with Customer Debt RBAC', () {
    testWidgets('Staff user does not see other store customers and debt summary/filter are hidden',
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
          overrides: overridesFor(user: staffUser),
        ),
      );
      await tester.pumpAndSettle();

      // Staff is store_001. Khách Chi Nhánh Khác is store_002 with debt 10,000,000.
      // It must NOT appear!
      expect(find.text('Khách Chi Nhánh Khác'), findsNothing);

      // Under Customer Debt RBAC, total debt summary and debt filter bar are strictly hidden for Staff:
      expect(find.byKey(const Key('total_debt_summary_text')), findsNothing);
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsNothing);
      expect(find.byKey(const Key('debt_filter_tab_cleared')), findsNothing);
    });
  });

  group('Adversarial Challenge 6: Micro-Debt Badge Rendering', () {
    testWidgets('Micro-debt (0.0001) tile displays badge correctly',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: CustomerListTile(customer: adversarialCustomers[0]),
          overrides: overridesFor(user: adminUser),
        ),
      );
      await tester.pumpAndSettle();

      final badgeFinder =
          find.byKey(Key('debt_badge_${adversarialCustomers[0].id}'));
      expect(badgeFinder, findsOneWidget);
    });

    testWidgets('Negative debt (-500.0) tile does NOT display badge',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: CustomerListTile(customer: adversarialCustomers[3]),
          overrides: overridesFor(user: adminUser),
        ),
      );
      await tester.pumpAndSettle();

      final badgeFinder =
          find.byKey(Key('debt_badge_${adversarialCustomers[3].id}'));
      expect(badgeFinder, findsNothing);
    });
  });
}
