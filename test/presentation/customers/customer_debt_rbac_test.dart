import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/auth/user_filter_hydration.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
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

  void setUser(UserAccount? user) {
    state = user;
  }
}

class _FakeCustomerListNotifier
    extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _FakeCustomerListNotifier(this._initialCustomers);

  final List<Customer> _initialCustomers;

  @override
  Future<List<Customer>> build() async => _initialCustomers;

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_initialCustomers);
  }
}

class _ControllableCustomerListNotifier
    extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _ControllableCustomerListNotifier(this._initialCustomers);

  final List<Customer> _initialCustomers;
  Completer<List<Customer>>? refreshCompleter;

  @override
  Future<List<Customer>> build() async => _initialCustomers;

  @override
  Future<void> refresh() async {
    if (refreshCompleter != null) {
      final updated = await refreshCompleter!.future;
      state = AsyncValue.data(updated);
    } else {
      state = AsyncValue.data(_initialCustomers);
    }
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

  setUp(() {
    FilterStorageService.resetSharedPrefs();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    FilterStorageService.resetSharedPrefs();
    SharedPreferences.setMockInitialValues({});
  });

  const staffUser = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên Bán hàng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor_01',
    displayName: 'Cửa hàng trưởng',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Chủ cửa hàng',
    role: 'admin',
    storeId: 'store_001',
  );

  const sampleCustomers = [
    Customer(
      id: 'cust_01',
      name: 'Nguyễn Văn Nợ',
      phone: '0901111111',
      email: 'no1@test.com',
      address: 'Đông Thắng',
      branch: 'store_001',
      purchases: [],
      currentDebt: 4500000.0,
      totalSales: 15000000.0,
      createdAt: '2026-09-01 10:00:00',
    ),
    Customer(
      id: 'cust_02',
      name: 'Trần Thị Sạch Nợ',
      phone: '0902222222',
      email: 'sach2@test.com',
      address: 'Đông Thắng',
      branch: 'store_001',
      purchases: [],
      currentDebt: 0.0,
      totalSales: 8000000.0,
      createdAt: '2026-09-02 10:00:00',
    ),
    Customer(
      id: 'cust_03',
      name: 'Lê Văn Trả Trước',
      phone: '0903333333',
      email: 'tratruoc3@test.com',
      address: 'Đông Thắng',
      branch: 'store_001',
      purchases: [],
      currentDebt: -200000.0,
      totalSales: 3000000.0,
      createdAt: '2026-09-03 10:00:00',
    ),
  ];

  List<Override> commonOverrides({
    required UserAccount user,
    List<Customer> customers = sampleCustomers,
    _FakeAuthNotifier? authNotifier,
  }) {
    return [
      authProvider.overrideWith((ref) => authNotifier ?? _FakeAuthNotifier(user)),
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

  group('Customer Debt RBAC - R1: Total Store Debt Summary Visibility', () {
    testWidgets(
        'Staff account strictly hides total debt text, debt label, and "Cần thu" badge in summary card',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(user: staffUser),
        ),
      );
      await tester.pumpAndSettle();

      // Total debt summary widget key must NOT exist
      expect(find.byKey(const Key('total_debt_summary_text')), findsNothing);

      // "Cần thu" badge must NOT exist
      expect(find.text('Cần thu'), findsNothing);

      // Total sales is hidden for Staff, customer count is visible
      expect(find.text(currencyFormat.format(26000000.0)), findsNothing);
      expect(find.text('Tổng cộng (3 khách hàng)'), findsOneWidget);
    });

    testWidgets(
        'Admin account sees full total debt summary text and "Cần thu" badge',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(user: adminUser),
        ),
      );
      await tester.pumpAndSettle();

      // Total debt summary text must be present with formatted amount
      final totalDebtFinder = find.byKey(const Key('total_debt_summary_text'));
      expect(totalDebtFinder, findsOneWidget);
      expect(
        (tester.widget(totalDebtFinder) as Text).data,
        equals(currencyFormat.format(4500000.0)),
      );

      // "Cần thu" badge is visible because totalDebt > 0
      expect(find.text('Cần thu'), findsOneWidget);

      // Total sales and count are visible
      expect(find.text(currencyFormat.format(26000000.0)), findsOneWidget);
      expect(find.text('Tổng cộng (3 khách hàng)'), findsOneWidget);
    });

    testWidgets(
        'Supervisor account sees full total debt summary text and "Cần thu" badge',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(user: supervisorUser),
        ),
      );
      await tester.pumpAndSettle();

      // Total debt summary text is present for Supervisor
      final totalDebtFinder = find.byKey(const Key('total_debt_summary_text'));
      expect(totalDebtFinder, findsOneWidget);
      expect(
        (tester.widget(totalDebtFinder) as Text).data,
        equals(currencyFormat.format(4500000.0)),
      );
      expect(find.text('Cần thu'), findsOneWidget);
    });
  });

  group('Customer Debt RBAC - R2: Debt Filter Bar Visibility & Locking', () {
    testWidgets(
        'Staff account strictly hides debt filter bar (Tất cả, Còn nợ, Hết nợ)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(user: staffUser),
        ),
      );
      await tester.pumpAndSettle();

      // Debt filter tabs must NOT exist for staff
      expect(find.byKey(const Key('debt_filter_tab_all')), findsNothing);
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsNothing);
      expect(find.byKey(const Key('debt_filter_tab_cleared')), findsNothing);

      // All customers are listed (default CustomerDebtFilter.all)
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Sạch Nợ'), findsOneWidget);
      expect(find.text('Lê Văn Trả Trước'), findsOneWidget);
    });

    testWidgets(
        'Staff account with initialDebtFilter ignores filter and defaults to all customers',
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
          overrides: commonOverrides(user: staffUser),
        ),
      );
      await tester.pumpAndSettle();

      // Debt filter bar remains completely hidden
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsNothing);

      // Cleared customers are STILL displayed because staff cannot filter by debt
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Sạch Nợ'), findsOneWidget);
      expect(find.text('Lê Văn Trả Trước'), findsOneWidget);
    });

    testWidgets(
        'Admin account sees debt filter bar and can filter by "Còn nợ" and "Hết nợ"',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(user: adminUser),
        ),
      );
      await tester.pumpAndSettle();

      // Debt filter tabs are present with accurate counts
      expect(find.byKey(const Key('debt_filter_tab_all')), findsOneWidget);
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsOneWidget);
      expect(find.byKey(const Key('debt_filter_tab_cleared')), findsOneWidget);

      // Filter to "Còn nợ"
      await tester.tap(find.byKey(const Key('debt_filter_tab_inDebt')));
      await tester.pumpAndSettle();

      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Sạch Nợ'), findsNothing);
      expect(find.text('Lê Văn Trả Trước'), findsNothing);

      // Filter to "Hết nợ"
      await tester.tap(find.byKey(const Key('debt_filter_tab_cleared')));
      await tester.pumpAndSettle();

      expect(find.text('Nguyễn Văn Nợ'), findsNothing);
      expect(find.text('Trần Thị Sạch Nợ'), findsOneWidget);
      expect(find.text('Lê Văn Trả Trước'), findsOneWidget);
    });
  });

  group('Customer Debt RBAC - R3: Individual Debt Badge Preservation', () {
    testWidgets(
        'Individual customer debt badge remains prominently visible to Staff on CustomerListTile',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: CustomerListTile(customer: sampleCustomers[0]),
          overrides: commonOverrides(user: staffUser),
        ),
      );
      await tester.pumpAndSettle();

      // Individual debt badge is preserved for sales staff
      final debtBadgeFinder =
          find.byKey(Key('debt_badge_${sampleCustomers[0].id}'));
      expect(debtBadgeFinder, findsOneWidget);

      // Shows warning icon and formatted debt
      expect(
        find.descendant(
            of: debtBadgeFinder,
            matching: find.byIcon(Icons.warning_amber_rounded)),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: debtBadgeFinder,
            matching: find.textContaining(currencyFormat.format(4500000.0))),
        findsOneWidget,
      );
    });

    testWidgets(
        'Customer without debt does not show individual debt badge to Staff',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: CustomerListTile(customer: sampleCustomers[1]),
          overrides: commonOverrides(user: staffUser),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(Key('debt_badge_${sampleCustomers[1].id}')),
          findsNothing);
    });
  });

  group('Customer Debt RBAC - Dynamic User Session Switching', () {
    testWidgets(
        'Switching from Admin to Staff dynamically hides debt summary & filter bar',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeAuth = _FakeAuthNotifier(adminUser);

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(user: adminUser, authNotifier: fakeAuth),
        ),
      );
      await tester.pumpAndSettle();

      // Admin sees total debt and tabs
      expect(find.byKey(const Key('total_debt_summary_text')), findsOneWidget);
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsOneWidget);

      // Switch to Staff
      fakeAuth.setUser(staffUser);
      await tester.pumpAndSettle();

      // Staff immediately sees debt summary and tabs removed
      expect(find.byKey(const Key('total_debt_summary_text')), findsNothing);
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsNothing);
      expect(find.byKey(const Key('debt_filter_tab_cleared')), findsNothing);

      // Switch back to Admin
      fakeAuth.setUser(adminUser);
      await tester.pumpAndSettle();

      // Admin sees debt summary and tabs restored
      expect(find.byKey(const Key('total_debt_summary_text')), findsOneWidget);
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsOneWidget);
    });

    testWidgets(
        'Same-username dynamic role demotion (Admin -> Staff) resets debt filter and hides debt metrics',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const dynamicUserAdmin = UserAccount(
        username: 'user_dynamic',
        displayName: 'Người Dùng Đổi Quyền',
        role: 'admin',
        storeId: 'store_001',
      );
      const dynamicUserStaff = UserAccount(
        username: 'user_dynamic',
        displayName: 'Người Dùng Đổi Quyền',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      final fakeAuth = _FakeAuthNotifier(dynamicUserAdmin);

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(
              user: dynamicUserAdmin, authNotifier: fakeAuth),
        ),
      );
      await tester.pumpAndSettle();

      // Filter to inDebt as Admin
      await tester.tap(find.byKey(const Key('debt_filter_tab_inDebt')));
      await tester.pumpAndSettle();

      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Sạch Nợ'), findsNothing);

      // Dynamically demote to Staff with SAME username
      fakeAuth.setUser(dynamicUserStaff);
      await tester.pumpAndSettle();

      // Under staff, debt summary and tabs are gone, and all customers are visible
      expect(find.byKey(const Key('total_debt_summary_text')), findsNothing);
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsNothing);
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Sạch Nợ'), findsOneWidget);
      expect(find.text('Lê Văn Trả Trước'), findsOneWidget);

      // Re-promote to Admin with SAME username
      fakeAuth.setUser(dynamicUserAdmin);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('total_debt_summary_text')), findsOneWidget);
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsOneWidget);
    });
  });

  group('Customer Debt RBAC - Ledger Edge Case: Concurrent Role Switching During Active Async Refresh', () {
    testWidgets(
        'Role switch to Staff during in-flight async customer refresh never renders total debt in intermediate frames',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controllableNotifier =
          _ControllableCustomerListNotifier(sampleCustomers);
      final fakeAuth = _FakeAuthNotifier(adminUser);

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: [
            authProvider.overrideWith((ref) => fakeAuth),
            customerListNotifierProvider.overrideWith(() => controllableNotifier),
            for (final c in sampleCustomers) ...[
              customerOrdersProvider(c.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(c.id)
                  .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
            ],
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Initially Admin sees total debt
      expect(find.byKey(const Key('total_debt_summary_text')), findsOneWidget);

      // Initiate slow async refresh with an incomplete completer
      final completer = Completer<List<Customer>>();
      controllableNotifier.refreshCompleter = completer;

      // Trigger refresh
      final refreshFuture = controllableNotifier.refresh();

      // CONCURRENT EVENT: switch user to Staff while refresh is still pending!
      fakeAuth.setUser(staffUser);

      // Advance single microtask/frame
      await tester.pump();

      // In this INTERMEDIATE frame, total debt summary text and tabs MUST NOT be visible!
      expect(find.byKey(const Key('total_debt_summary_text')), findsNothing);
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsNothing);
      expect(find.text('Cần thu'), findsNothing);

      // Complete the async refresh
      completer.complete(sampleCustomers);
      await refreshFuture;
      await tester.pumpAndSettle();

      // When settled, Staff remains strictly protected from debt summary
      expect(find.byKey(const Key('total_debt_summary_text')), findsNothing);
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsNothing);
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
    });
  });

  group('Customer Debt RBAC - Staff Time Range Storage Hydration Preservation', () {
    testWidgets(
        'Staff user preserves saved timeRangeType hydration while debtFilter is strictly locked to all',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'filter_prefs_staff_01_customers': jsonEncode({
          'version': 1,
          'debtFilter': 'inDebt', // Malicious or stale saved debt filter
          'timeRangeType': 'today',
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: [
            ...commonOverrides(user: staffUser),
            filterStorageServiceProvider.overrideWithValue(
              FilterStorageService(prefs, staffUser.username),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Debt summary is strictly hidden
      expect(find.byKey(const Key('total_debt_summary_text')), findsNothing);
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsNothing);

      // Time range filter WAS restored to 'today'
      expect(find.textContaining('Hôm nay'), findsOneWidget);
    });
  });

  group('Customer Debt RBAC - Defense In Depth & Provider Isolation', () {
    test('customerDebtCountsProvider zeros out inDebt and cleared counts for Staff', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
          customerListNotifierProvider
              .overrideWith(() => _FakeCustomerListNotifier(sampleCustomers)),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(customerDebtCountsProvider, (_, __) {});
      addTearDown(sub.close);
      await container.read(customerListNotifierProvider.future);
      await Future<void>.delayed(Duration.zero);

      final counts = container.read(customerDebtCountsProvider);
      expect(counts[CustomerDebtFilter.all], equals(3));
      // Defense in depth: Staff cannot see inDebt or cleared count numbers
      expect(counts[CustomerDebtFilter.inDebt], equals(0));
      expect(counts[CustomerDebtFilter.cleared], equals(0));
    });

    test('rehydrateAllUserFilters resets customerDebtFilterProvider to all for Staff when customersData is null', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs, staffUser.username),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Pre-set to inDebt (simulating state before rehydration)
      container.read(customerDebtFilterProvider.notifier).state = CustomerDebtFilter.inDebt;

      await rehydrateAllUserFilters(container, staffUser);

      // Must be forced to CustomerDebtFilter.all unconditionally
      expect(container.read(customerDebtFilterProvider), equals(CustomerDebtFilter.all));
    });
  });

  group('Customer Debt RBAC - Narrow Viewport & Extreme Figures Stress', () {
    testWidgets(
        'Admin renders cleanly on narrow viewport (320px) with large figures without RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const largeCustomers = [
        Customer(
          id: 'cust_large_01',
          name: 'Khách Hàng Nợ Cực Lớn',
          phone: '0901111111',
          email: 'large@test.com',
          address: 'Hà Nội',
          branch: 'store_001',
          purchases: [],
          currentDebt: 950000000.0,
          totalSales: 1500000000.0,
          createdAt: '2026-09-01 10:00:00',
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(user: adminUser, customers: largeCustomers),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('total_debt_summary_text')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Staff renders cleanly on narrow viewport (320px) with large sales figures without RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const largeCustomers = [
        Customer(
          id: 'cust_large_01',
          name: 'Khách Hàng Nợ Cực Lớn',
          phone: '0901111111',
          email: 'large@test.com',
          address: 'Hà Nội',
          branch: 'store_001',
          purchases: [],
          currentDebt: 950000000.0,
          totalSales: 1500000000.0,
          createdAt: '2026-09-01 10:00:00',
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(user: staffUser, customers: largeCustomers),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('total_debt_summary_text')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Admin on extreme 280px viewport with 1.25x accessibility text scale renders without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(280, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const multiCustomers = [
        Customer(
          id: 'cust_ext_01',
          name: 'Công ty Cổ phần Công nghệ Toàn Cầu Khách Hàng VIP',
          phone: '0909999999',
          email: 'vip@test.com',
          address: 'TP. Hồ Chí Minh',
          branch: 'store_001',
          purchases: [],
          currentDebt: 8500000000.0,
          totalSales: 12000000000.0,
          createdAt: '2026-09-01 10:00:00',
        ),
        Customer(
          id: 'cust_ext_02',
          name: 'Khách Trả Thừa Tiền Cọc',
          phone: '0908888888',
          email: 'coc@test.com',
          address: 'Hà Nội',
          branch: 'store_001',
          purchases: [],
          currentDebt: -50000000.0,
          totalSales: 300000000.0,
          createdAt: '2026-09-02 10:00:00',
        ),
      ];

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.25)),
          child: _buildTestApp(
            child: const CustomersPage(),
            overrides: commonOverrides(user: adminUser, customers: multiCustomers),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('total_debt_summary_text')), findsOneWidget);
      expect(find.text('Cần thu'), findsOneWidget);
    });

    testWidgets(
        'Staff on extreme 280px viewport with 1.25x accessibility text scale renders without overflow and hides debt summary',
        (tester) async {
      tester.view.physicalSize = const Size(280, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const multiCustomers = [
        Customer(
          id: 'cust_ext_01',
          name: 'Công ty Cổ phần Công nghệ Toàn Cầu Khách Hàng VIP',
          phone: '0909999999',
          email: 'vip@test.com',
          address: 'TP. Hồ Chí Minh',
          branch: 'store_001',
          purchases: [],
          currentDebt: 8500000000.0,
          totalSales: 12000000000.0,
          createdAt: '2026-09-01 10:00:00',
        ),
        Customer(
          id: 'cust_ext_02',
          name: 'Khách Trả Thừa Tiền Cọc',
          phone: '0908888888',
          email: 'coc@test.com',
          address: 'Hà Nội',
          branch: 'store_001',
          purchases: [],
          currentDebt: -50000000.0,
          totalSales: 300000000.0,
          createdAt: '2026-09-02 10:00:00',
        ),
      ];

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.25)),
          child: _buildTestApp(
            child: const CustomersPage(),
            overrides: commonOverrides(user: staffUser, customers: multiCustomers),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('total_debt_summary_text')), findsNothing);
      expect(find.text('Cần thu'), findsNothing);
    });
  });

  group('Customer Debt RBAC - Adversarial Reviewer Stress Scenarios', () {
    testWidgets(
        'Staff searching for debtor updates total sales and count while strictly keeping total debt hidden and individual debt badge visible',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(user: staffUser),
        ),
      );
      await tester.pumpAndSettle();

      // Enter search query for debtor 'Nguyễn Văn Nợ'
      await tester.enterText(find.byType(TextField).first, 'Nguyễn Văn Nợ');
      await tester.pumpAndSettle();

      // Search results isolate to only this 1 customer
      expect(find.widgetWithText(CustomerListTile, 'Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Sạch Nợ'), findsNothing);
      expect(find.text('Lê Văn Trả Trước'), findsNothing);

      // Summary card updates count to 1 and sales is hidden for Staff
      expect(find.text('Tổng cộng (1 khách hàng)'), findsOneWidget);
      expect(find.text(currencyFormat.format(15000000.0)), findsNothing);

      // Total debt line and 'Cần thu' badge remain strictly hidden for Staff
      expect(find.byKey(const Key('total_debt_summary_text')), findsNothing);
      expect(find.text('Cần thu'), findsNothing);

      // But individual customer list tile DOES display their personal debt badge
      final debtBadge = find.byKey(const Key('debt_badge_cust_01'));
      expect(debtBadge, findsOneWidget);
      expect(
        find.descendant(
          of: debtBadge,
          matching: find.textContaining(currencyFormat.format(4500000.0)),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'Admin with zero or only negative debt displays 0 debt without "Cần thu" badge',
        (tester) async {
      const debtFreeCustomers = [
        Customer(
          id: 'cust_free_01',
          name: 'Khách Đã Thanh Toán Hết',
          phone: '0901111111',
          email: 'free@test.com',
          address: 'Hà Nội',
          branch: 'store_001',
          purchases: [],
          currentDebt: 0.0,
          totalSales: 2000000.0,
          createdAt: '2026-09-01 10:00:00',
        ),
        Customer(
          id: 'cust_free_02',
          name: 'Khách Đặt Cọc Thừa',
          phone: '0902222222',
          email: 'deposit@test.com',
          address: 'Hà Nội',
          branch: 'store_001',
          purchases: [],
          currentDebt: -500000.0,
          totalSales: 1000000.0,
          createdAt: '2026-09-02 10:00:00',
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(user: adminUser, customers: debtFreeCustomers),
        ),
      );
      await tester.pumpAndSettle();

      final totalDebtFinder = find.byKey(const Key('total_debt_summary_text'));
      expect(totalDebtFinder, findsOneWidget);
      // Total debt should be 0 because negative prepayments are excluded from debt sum
      expect(
        (tester.widget(totalDebtFinder) as Text).data,
        equals(currencyFormat.format(0.0)),
      );
      // "Cần thu" badge must NOT appear when total debt is 0
      expect(find.text('Cần thu'), findsNothing);
    });

    testWidgets(
        'Untrusted or arbitrary custom role defaults safely to Staff behavior (default-deny)',
        (tester) async {
      const customRoleUser = UserAccount(
        username: 'intern_user',
        displayName: 'Thực tập sinh',
        role: 'intern_auditor',
        storeId: 'store_001',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(user: customRoleUser),
        ),
      );
      await tester.pumpAndSettle();

      // Total debt summary text must be absent
      expect(find.byKey(const Key('total_debt_summary_text')), findsNothing);
      expect(find.text('Cần thu'), findsNothing);

      // Debt filter bar must be absent
      expect(find.byKey(const Key('debt_filter_tab_all')), findsNothing);
      expect(find.byKey(const Key('debt_filter_tab_inDebt')), findsNothing);
      expect(find.byKey(const Key('debt_filter_tab_cleared')), findsNothing);

      // All customers are listed
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Sạch Nợ'), findsOneWidget);
    });

    testWidgets(
        'Supervisor on narrow viewport (320px) with large figures renders cleanly without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const largeCustomers = [
        Customer(
          id: 'cust_sup_large',
          name: 'Khách Hàng Nợ Hàng Tỷ Đồng',
          phone: '0901234567',
          email: 'billion@test.com',
          address: 'TP. Hồ Chí Minh',
          branch: 'store_001',
          purchases: [],
          currentDebt: 1250000000.0,
          totalSales: 3450000000.0,
          createdAt: '2026-09-01 10:00:00',
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: commonOverrides(user: supervisorUser, customers: largeCustomers),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('total_debt_summary_text')), findsOneWidget);
      expect(find.text('Cần thu'), findsOneWidget);
    });
  });
}
