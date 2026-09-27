import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/orders/controllers/invoices_filter_controller.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';

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

class _FakeCustomerListNotifier extends AutoDisposeAsyncNotifier<List<Customer>>
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
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  final now = DateTime.now();

  final customer1 = Customer(
    id: 'cust_001',
    name: 'Nguyễn Văn Nợ',
    phone: '0901111111',
    email: 'no@example.com',
    address: 'Hà Nội',
    purchases: const [],
    currentDebt: 5000000,
    createdAt: now.toIso8601String(),
  );

  final customer2 = Customer(
    id: 'cust_002',
    name: 'Trần Thị Hết Nợ',
    phone: '0902222222',
    email: 'hetno@example.com',
    address: 'Đà Nẵng',
    purchases: const [],
    currentDebt: 0,
    createdAt: now.toIso8601String(),
  );

  final sampleCustomers = [customer1, customer2];

  final sampleOrders = [
    // Order 1: Perfect match for 5 filters (today, completed, transfer, debt, staff_01)
    Order(
      id: 'HD_MATCH_ALL_5',
      customerId: 'cust_001',
      createdAt: now.subtract(const Duration(minutes: 10)),
      items: [
        OrderItem(
          productId: 'P1',
          productName: 'Áo thun nam',
          price: 200000,
          quantity: 1,
          warrantyMonths: 0,
          purchaseDate: now,
        ),
      ],
      total: 200000,
      amountPaid: 50000,
      // debt: 150000
      paymentMethod: 'transfer',
      status: 'completed',
      createdBy: 'staff_01',
      createdByName: 'Nhân viên 1',
    ),
    // Order 2: Wrong staff (admin)
    Order(
      id: 'HD_WRONG_STAFF',
      customerId: 'cust_001',
      createdAt: now.subtract(const Duration(minutes: 15)),
      items: [
        OrderItem(
          productId: 'P1',
          productName: 'Áo sơ mi',
          price: 200000,
          quantity: 1,
          warrantyMonths: 0,
          purchaseDate: now,
        ),
      ],
      total: 200000,
      amountPaid: 50000,
      paymentMethod: 'transfer',
      status: 'completed',
      createdBy: 'admin',
      createdByName: 'Quản trị viên',
    ),
    // Order 3: Wrong paymentMethod (cash)
    Order(
      id: 'HD_WRONG_PAYMENT',
      customerId: 'cust_001',
      createdAt: now.subtract(const Duration(minutes: 20)),
      items: [
        OrderItem(
          productId: 'P1',
          productName: 'Quần bò',
          price: 200000,
          quantity: 1,
          warrantyMonths: 0,
          purchaseDate: now,
        ),
      ],
      total: 200000,
      amountPaid: 50000,
      paymentMethod: 'cash',
      status: 'completed',
      createdBy: 'staff_01',
      createdByName: 'Nhân viên 1',
    ),
    // Order 4: Wrong debt status (paid in full, debt = 0)
    Order(
      id: 'HD_WRONG_DEBT',
      customerId: 'cust_001',
      createdAt: now.subtract(const Duration(minutes: 25)),
      items: [
        OrderItem(
          productId: 'P1',
          productName: 'Nón kết',
          price: 200000,
          quantity: 1,
          warrantyMonths: 0,
          purchaseDate: now,
        ),
      ],
      total: 200000,
      amountPaid: 200000,
      paymentMethod: 'transfer',
      status: 'completed',
      createdBy: 'staff_01',
      createdByName: 'Nhân viên 1',
    ),
    // Order 5: Wrong status (cancelled)
    Order(
      id: 'HD_WRONG_STATUS',
      customerId: 'cust_001',
      createdAt: now.subtract(const Duration(minutes: 30)),
      items: [
        OrderItem(
          productId: 'P1',
          productName: 'Tất vớ',
          price: 200000,
          quantity: 1,
          warrantyMonths: 0,
          purchaseDate: now,
        ),
      ],
      total: 200000,
      amountPaid: 50000,
      paymentMethod: 'transfer',
      status: 'cancelled',
      createdBy: 'staff_01',
      createdByName: 'Nhân viên 1',
    ),
    // Order 6: Wrong date (created 5 days ago)
    Order(
      id: 'HD_WRONG_DATE',
      customerId: 'cust_001',
      createdAt: now.subtract(const Duration(days: 5)),
      items: [
        OrderItem(
          productId: 'P1',
          productName: 'Áo khoác',
          price: 200000,
          quantity: 1,
          warrantyMonths: 0,
          purchaseDate: now,
        ),
      ],
      total: 200000,
      amountPaid: 50000,
      paymentMethod: 'transfer',
      status: 'completed',
      createdBy: 'staff_01',
      createdByName: 'Nhân viên 1',
    ),
  ];

  List<Override> buildInvoicesOverrides() => [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
        allBranchesOrdersByDateRangeProvider.overrideWith((ref, range) {
          return Stream.value(sampleOrders.where((o) {
            return !o.createdAt.isBefore(range.start) &&
                !o.createdAt.isAfter(range.end);
          }).toList());
        }),
        customerListNotifierProvider
            .overrideWith(() => _FakeCustomerListNotifier(sampleCustomers)),
      ];

  List<Override> buildCustomersOverrides() => [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        customerListNotifierProvider
            .overrideWith(() => _FakeCustomerListNotifier(sampleCustomers)),
        for (final c in sampleCustomers) ...[
          customerOrdersProvider(c.id)
              .overrideWith((ref) => Stream.value(<Order>[])),
          customerDebtTransactionsProvider(c.id)
              .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
        ],
      ];

  void setTestScreenSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
  }

  // =========================================================================
  // SUITE 1: InvoicesPage 5-Dimension Retention Across Unmount/Remount & Restart
  // =========================================================================
  group(
      'Challenger Suite 1: InvoicesPage 5-Dimension Retention Across Unmount/Remount',
      () {
    testWidgets('Retains all 5 dimensions across simulated unmount and remount',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // 1. Setup mock SharedPreferences with all 5 non-default dimensions
      SharedPreferences.setMockInitialValues({
        'filter_prefs_invoices': jsonEncode({
          'version': 1,
          'timeRangeType': 'today',
          'status': 'completed',
          'paymentMethod': 'transfer',
          'debtStatus': 'debt',
          'staff': 'staff_01',
        }),
      });

      // 2. Mount InvoicesPage inside a switcher widget to facilitate unmount/remount
      bool showInvoicesPage = true;
      late StateSetter triggerRebuild;

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildInvoicesOverrides(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            home: StatefulBuilder(
              builder: (context, setState) {
                triggerRebuild = setState;
                return showInvoicesPage
                    ? const InvoicesPage()
                    : const Scaffold(body: Text('Page Unmounted Placeholder'));
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 3. Verify badge displays "Lọc (4)" (status is completed by default)
      final badgeFinder =
          find.byKey(const Key('invoices_reset_filter_badge_button'));
      expect(badgeFinder, findsOneWidget);
      expect(find.text('Lọc (4)'), findsOneWidget);

      // 4. Verify only HD_MATCH_ALL_5 matches all 5 dimensions
      expect(find.text('Mã đơn: HD_MATCH_ALL_5'), findsOneWidget);
      expect(find.text('Mã đơn: HD_WRONG_STAFF'), findsNothing);
      expect(find.text('Mã đơn: HD_WRONG_PAYMENT'), findsNothing);
      expect(find.text('Mã đơn: HD_WRONG_DEBT'), findsNothing);
      expect(find.text('Mã đơn: HD_WRONG_STATUS'), findsNothing);
      expect(find.text('Mã đơn: HD_WRONG_DATE'), findsNothing);

      // 5. Simulate page unmount (navigate away)
      triggerRebuild(() {
        showInvoicesPage = false;
      });
      await tester.pumpAndSettle();

      expect(find.text('Page Unmounted Placeholder'), findsOneWidget);
      expect(find.byType(InvoicesPage), findsNothing);

      // 6. Simulate returning to InvoicesPage (remount)
      triggerRebuild(() {
        showInvoicesPage = true;
      });
      await tester.pumpAndSettle();

      // 7. Verify all dimensions are completely retained
      expect(find.byKey(const Key('invoices_reset_filter_badge_button')),
          findsOneWidget);
      expect(find.text('Lọc (4)'), findsOneWidget);
      expect(find.text('Mã đơn: HD_MATCH_ALL_5'), findsOneWidget);
      expect(find.text('Mã đơn: HD_WRONG_STAFF'), findsNothing);
      expect(find.text('Mã đơn: HD_WRONG_PAYMENT'), findsNothing);
      expect(find.text('Mã đơn: HD_WRONG_DEBT'), findsNothing);
      expect(find.text('Mã đơn: HD_WRONG_STATUS'), findsNothing);
      expect(find.text('Mã đơn: HD_WRONG_DATE'), findsNothing);
    });

    testWidgets(
        'Retains all 5 dimensions across simulated full app restart (fresh ProviderScope)',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_invoices': jsonEncode({
          'version': 1,
          'timeRangeType': 'today',
          'status': 'completed',
          'paymentMethod': 'transfer',
          'debtStatus': 'debt',
          'staff': 'staff_01',
        }),
      });

      // App Run 1
      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: buildInvoicesOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lọc (4)'), findsOneWidget);
      expect(find.text('Mã đơn: HD_MATCH_ALL_5'), findsOneWidget);

      // Simulate App termination and restart with completely fresh ProviderScope
      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: buildInvoicesOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // State is recovered from SharedPreferences
      expect(find.text('Lọc (4)'), findsOneWidget);
      expect(find.text('Mã đơn: HD_MATCH_ALL_5'), findsOneWidget);
      expect(find.text('Mã đơn: HD_WRONG_STAFF'), findsNothing);
    });
  });

  // =========================================================================
  // SUITE 2: Corrupted JSON, Malformed Keys, and Extreme Type Fallback
  // =========================================================================
  group(
      'Challenger Suite 2: Corrupted JSON, Malformed Keys, and Crash Resilience',
      () {
    testWidgets(
        'InvoicesPage handles corrupted syntax in SharedPreferences gracefully',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // Completely broken JSON string
      SharedPreferences.setMockInitialValues({
        'filter_prefs_invoices': '<<<NOT_JSON_SYNTAX>>>{invalid: true',
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: buildInvoicesOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Does not crash, defaults to 0 active filters, badge is absent
      expect(find.byKey(const Key('invoices_reset_filter_badge_button')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('InvoicesPage handles non-Map JSON primitives gracefully',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      for (final nonMap in ['"a string"', '12345', 'true', '[1, 2, 3]']) {
        SharedPreferences.setMockInitialValues({
          'filter_prefs_invoices': nonMap,
        });

        await tester.pumpWidget(
          _buildTestApp(
            child: const InvoicesPage(),
            overrides: buildInvoicesOverrides(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('invoices_reset_filter_badge_button')),
            findsNothing);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'InvoicesPage handles empty JSON map (missing all keys) gracefully',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_invoices': jsonEncode({}),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: buildInvoicesOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('invoices_reset_filter_badge_button')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    test(
        'InvoicesFilterState.fromJson sanitizes invalid enum values and corrupt types',
        () {
      // JSON with invalid enum names, dates, and non-string fields
      final corruptedJson = <String, dynamic>{
        'version': '1',
        'timeRangeType': 'non_existent_range_123',
        'customStartDate': 'not-a-date',
        'customEndDate': 99999.toString(),
        'status': 'UNKNOWN_STATUS_XYZ',
        'paymentMethod': 'crypto',
        'debtStatus': 'bankrupt',
        'staff': '   ',
      };

      final state = InvoicesFilterState.fromJson(corruptedJson);

      // Must fall back to safe defaults (status defaults to completed)
      expect(state.timeRangeType, OverviewTimeRange.thisMonth);
      expect(state.status, 'completed');
      expect(state.paymentMethod, 'all');
      expect(state.debtStatus, 'all');
      expect(state.staff, 'all');
      expect(state.activeFilterCount, 0);
      expect(state.hasActiveFilters, isFalse);
    });

    testWidgets(
        'CustomersPage handles corrupted syntax and invalid types gracefully',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // Broken JSON in Customers prefs
      SharedPreferences.setMockInitialValues({
        'filter_prefs_customers': '{bad json: true<<<',
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: buildCustomersOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Must not crash, both customers visible under default CustomerDebtFilter.all
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsOneWidget);
      expect(
          find.byKey(const Key('reset_customer_filters_button')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'CustomersPage handles invalid enum values in storage gracefully',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // JSON with unrecognized enum strings
      SharedPreferences.setMockInitialValues({
        'filter_prefs_customers': jsonEncode({
          'debtFilter': 'ILLEGAL_DEBT_TAB_123',
          'timeRangeType': 'UNKNOWN_TIME_RANGE_999',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: buildCustomersOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Falls back to defaults without crash, both customers visible
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'CustomersPage handles empty JSON map (missing all keys) gracefully',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_customers': jsonEncode({}),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: buildCustomersOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsOneWidget);
      expect(
          find.byKey(const Key('reset_customer_filters_button')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // SUITE 3: 1-Tap "Đặt lại" Synchronization Between State and Storage
  // =========================================================================
  group(
      'Challenger Suite 3: 1-Tap "Đặt lại" Memory & SharedPreferences Synchronization',
      () {
    testWidgets(
        'InvoicesPage 1-tap reset clears memory state and removes storage key',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_invoices': jsonEncode({
          'version': 1,
          'status': 'completed',
          'paymentMethod': 'transfer',
          'debtStatus': 'debt',
          'staff': 'all',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: buildInvoicesOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      final badgeFinder =
          find.byKey(const Key('invoices_reset_filter_badge_button'));
      expect(badgeFinder, findsOneWidget);
      expect(find.text('Lọc (2)'), findsOneWidget);

      // Tap 1-tap reset badge
      await tester.tap(badgeFinder);
      await tester.pumpAndSettle();

      // Badge must disappear
      expect(find.byKey(const Key('invoices_reset_filter_badge_button')),
          findsNothing);

      // SharedPreferences key must be removed
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('filter_prefs_invoices'), isFalse);

      // In-memory fallback in FilterStorageService should be empty
      final container =
          ProviderScope.containerOf(tester.element(find.byType(InvoicesPage)));
      final storage = container.read(filterStorageServiceProvider);
      expect(storage.loadFilterSync('invoices'), isNull);
    });

    testWidgets(
        'CustomersPage 1-tap reset clears debt filter and time range and removes storage key',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_customers': jsonEncode({
          'debtFilter': 'inDebt',
          'timeRangeType': 'thisMonth',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: buildCustomersOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Reset button displays with count 2
      final resetBtn = find.byKey(const Key('reset_customer_filters_button'));
      expect(resetBtn, findsOneWidget);
      expect(find.text('Đặt lại (2)'), findsOneWidget);

      // Tap 1-tap reset button
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      // Reset button disappears
      expect(
          find.byKey(const Key('reset_customer_filters_button')), findsNothing);

      // Both customers visible
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsOneWidget);

      // SharedPreferences key removed
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('filter_prefs_customers'), isFalse);
    });
  });

  // =========================================================================
  // SUITE 4: CustomersPage Retains Debt Tab and Time Range Across Push/Pop
  // =========================================================================
  group(
      'Challenger Suite 4: CustomersPage Retains Filters Across Push/Pop Navigation',
      () {
    testWidgets('Retains debt tab across route push and pop', (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({});

      late BuildContext navContext;

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildCustomersOverrides(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            home: Builder(
              builder: (context) {
                navContext = context;
                return const CustomersPage();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initially both customers visible
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsOneWidget);

      // 2. Tap "Còn nợ" tab
      final inDebtTab = find.byKey(const Key('debt_filter_tab_inDebt'));
      expect(inDebtTab, findsOneWidget);
      await tester.tap(inDebtTab);
      await tester.pumpAndSettle();

      // 3. Only inDebt customer visible
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsNothing);

      // 4. Push a new subpage onto the navigation stack
      Navigator.of(navContext).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Subpage Details')),
            body: const Center(child: Text('Customer Detail Content')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Subpage Details'), findsOneWidget);
      expect(find.text('Customer Detail Content'), findsOneWidget);

      // 5. Pop back to CustomersPage
      Navigator.of(navContext).pop();
      await tester.pumpAndSettle();

      // 6. Verify CustomersPage is restored with debt tab "Còn nợ" retained
      expect(find.text('Customer Detail Content'), findsNothing);
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsNothing);
      expect(find.byKey(const Key('reset_customer_filters_button')),
          findsOneWidget);
    });

    testWidgets('Retains selected time range across route push and pop',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'filter_prefs_customers': jsonEncode({
          'debtFilter': 'all',
          'timeRangeType': 'thisMonth',
        }),
      });

      late BuildContext navContext;

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildCustomersOverrides(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            home: Builder(
              builder: (context) {
                navContext = context;
                return const CustomersPage();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Tháng này'), findsOneWidget);

      // Push subpage
      Navigator.of(navContext).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Subpage')),
            body: const Center(child: Text('Content')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pop back
      Navigator.of(navContext).pop();
      await tester.pumpAndSettle();

      // Time range is retained
      expect(find.textContaining('Tháng này'), findsOneWidget);
    });
  });

  // =========================================================================
  // SUITE 5: Overview KPI Drilldown Override Precedence and Storage Cache
  // =========================================================================
  group(
      'Challenger Suite 5: Overview KPI Drilldown Override Precedence & Cache Update',
      () {
    testWidgets(
        'KPI drilldown parameter overrides existing stored preference and updates cache',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // 1. SharedPreferences has 'cleared' stored from past session
      SharedPreferences.setMockInitialValues({
        'filter_prefs_customers': jsonEncode({
          'debtFilter': 'cleared',
        }),
      });

      // 2. User navigates from Overview KPI with initialDebtFilter = inDebt
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(
            initialDebtFilter: CustomerDebtFilter.inDebt,
          ),
          overrides: buildCustomersOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // 3. initialDebtFilter: inDebt MUST win over stored 'cleared'
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsNothing);

      // 4. Storage cache MUST be immediately updated to 'inDebt'
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_customers');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['debtFilter'], 'inDebt');
    });

    testWidgets(
        'Subsequent standard navigation inherits the state updated by KPI drilldown',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      // Pre-set 'cleared'
      SharedPreferences.setMockInitialValues({
        'filter_prefs_customers': jsonEncode({
          'debtFilter': 'cleared',
        }),
      });

      // Step A: Drilldown with inDebt
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(
            initialDebtFilter: CustomerDebtFilter.inDebt,
          ),
          overrides: buildCustomersOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);

      // Step B: User leaves and returns normally (initialDebtFilter == null)
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: buildCustomersOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // The new persisted state from drilldown ('inDebt') must be active
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsNothing);
    });

    testWidgets(
        'Dynamic widget rebuild with new initialDebtFilter updates provider and storage',
        (tester) async {
      setTestScreenSize(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({});

      CustomerDebtFilter? activeInitial = CustomerDebtFilter.inDebt;
      late StateSetter triggerRebuild;

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildCustomersOverrides(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            home: StatefulBuilder(
              builder: (context, setState) {
                triggerRebuild = setState;
                return CustomersPage(initialDebtFilter: activeInitial);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsNothing);

      // Now simulate a drilldown from Overview to 'cleared'
      triggerRebuild(() {
        activeInitial = CustomerDebtFilter.cleared;
      });
      await tester.pumpAndSettle();

      // didUpdateWidget triggers and synchronizes
      expect(find.text('Trần Thị Hết Nợ'), findsOneWidget);
      expect(find.text('Nguyễn Văn Nợ'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_customers');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['debtFilter'], 'cleared');
    });
  });
}
