import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customer_detail_page.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/orders/pages/pos_checkout_page.dart';

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
      home: child,
    ),
  );
}

void main() {
  // Diverse user accounts
  const staffStore1 = UserAccount(
    username: 'staff_store1',
    displayName: 'Nhân viên Đông Thắng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const staffStore2 = UserAccount(
    username: 'staff_store2',
    displayName: 'Nhân viên Thới Bình',
    role: 'nhanvien',
    storeId: 'store_002',
  );

  const staffStore3 = UserAccount(
    username: 'staff_store3',
    displayName: 'Nhân viên Ô Môn',
    role: 'nhanvien',
    storeId: 'store_003',
  );

  const adminUser = UserAccount(
    username: 'admin_sys',
    displayName: 'Quản trị viên Hệ Thống',
    role: 'admin',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor_sys',
    displayName: 'Giám sát viên Hệ Thống',
    role: 'supervisor',
    storeId: 'store_002',
  );

  // Adversarial multi-store customer dataset covering all edge cases
  const List<Customer> adversarialCustomerDataset = [
    // Store 1 variations (store_001 = Chi nhánh Đông Thắng)
    Customer(
      id: 'c_s1_exact',
      name: 'Khách ĐT ID Chuẩn',
      phone: '0901000001',
      email: 's1_1@test.com',
      address: 'Đông Thắng 1',
      purchases: [],
      branch: 'store_001',
      createdAt: '2026-08-01 08:00:00',
      totalSales: 1000000.0,
      currentDebt: 500000.0,
    ),
    Customer(
      id: 'c_s1_uppercase',
      name: 'Khách ĐT Uppercase',
      phone: '0901000002',
      email: 's1_2@test.com',
      address: 'Đông Thắng 2',
      purchases: [],
      branch: 'STORE_001',
      createdAt: '2026-08-02 09:00:00',
      totalSales: 2000000.0,
    ),
    Customer(
      id: 'c_s1_alias',
      name: 'Khách ĐT Alias Key',
      phone: '0901000003',
      email: 's1_3@test.com',
      address: 'Đông Thắng 3',
      purchases: [],
      branch: 'branch_1',
      createdAt: '2026-08-03 10:00:00',
      totalSales: 3000000.0,
    ),
    Customer(
      id: 'c_s1_vn_accent',
      name: 'Khách ĐT Tiếng Việt',
      phone: '0901000004',
      email: 's1_4@test.com',
      address: 'Đông Thắng 4',
      purchases: [],
      branch: 'Chi nhánh Đông Thắng',
      createdAt: '2026-08-04 11:00:00',
      totalSales: 4000000.0,
    ),
    Customer(
      id: 'c_s1_vn_no_accent',
      name: 'Khách ĐT Khong Dau',
      phone: '0901000005',
      email: 's1_5@test.com',
      address: 'Đông Thắng 5',
      purchases: [],
      branch: 'chi nhanh dong thang',
      createdAt: '2026-08-05 12:00:00',
      totalSales: 5000000.0,
    ),
    Customer(
      id: 'c_s1_null_branch',
      name: 'Khách Vãng Lai Null Branch',
      phone: '0901000006',
      email: 's1_6@test.com',
      address: 'Cần Thơ',
      purchases: [],
      branch: null,
      createdAt: '2026-08-06 13:00:00',
      totalSales: 600000.0,
    ),
    Customer(
      id: 'c_s1_empty_branch',
      name: 'Khách Vãng Lai Empty Branch',
      phone: '0901000007',
      email: 's1_7@test.com',
      address: 'Cần Thơ',
      purchases: [],
      branch: '   ',
      createdAt: '2026-08-07 14:00:00',
      totalSales: 700000.0,
    ),

    // Store 2 variations (store_002 = Chi nhánh Thới Bình)
    Customer(
      id: 'c_s2_exact',
      name: 'Khách TB ID Chuẩn',
      phone: '0902000001',
      email: 's2_1@test.com',
      address: 'Thới Bình 1',
      purchases: [],
      branch: 'store_002',
      createdAt: '2026-08-08 15:00:00',
      totalSales: 1500000.0,
      currentDebt: 800000.0,
    ),
    Customer(
      id: 'c_s2_alias',
      name: 'Khách TB Alias Key',
      phone: '0902000002',
      email: 's2_2@test.com',
      address: 'Thới Bình 2',
      purchases: [],
      branch: 'branch_2',
      createdAt: '2026-08-09 16:00:00',
      totalSales: 2500000.0,
    ),
    Customer(
      id: 'c_s2_vn_accent',
      name: 'Khách TB Tiếng Việt',
      phone: '0902000003',
      email: 's2_3@test.com',
      address: 'Thới Bình 3',
      purchases: [],
      branch: 'Chi nhánh Thới Bình',
      createdAt: '2026-08-10 17:00:00',
      totalSales: 3500000.0,
    ),
    Customer(
      id: 'c_s2_vn_no_accent',
      name: 'Khách TB Khong Dau',
      phone: '0902000004',
      email: 's2_4@test.com',
      address: 'Thới Bình 4',
      purchases: [],
      branch: 'chi nhanh thoi binh',
      createdAt: '2026-08-11 18:00:00',
      totalSales: 4500000.0,
    ),

    // Store 3 custom store
    Customer(
      id: 'c_s3_custom',
      name: 'Khách Ô Môn Store 3',
      phone: '0903000001',
      email: 's3_1@test.com',
      address: 'Ô Môn',
      purchases: [],
      branch: 'store_003',
      createdAt: '2026-08-12 19:00:00',
      totalSales: 8000000.0,
      currentDebt: 1200000.0,
    ),

    // Adversarial prefix collision customers (must NOT leak to store_001 / store_002)
    Customer(
      id: 'c_collision_0010',
      name: 'Khách Branch store_0010',
      phone: '0909000010',
      email: 'col10@test.com',
      address: 'Hậu Giang',
      purchases: [],
      branch: 'store_0010',
      createdAt: '2026-08-13 20:00:00',
      totalSales: 900000.0,
    ),
    Customer(
      id: 'c_collision_0020',
      name: 'Khách Branch store_0020',
      phone: '0909000020',
      email: 'col20@test.com',
      address: 'Sóc Trăng',
      purchases: [],
      branch: 'store_0020',
      createdAt: '2026-08-14 21:00:00',
      totalSales: 950000.0,
    ),
    Customer(
      id: 'c_foreign',
      name: 'Khách Ngoại Lai Branch Khác',
      phone: '0909999999',
      email: 'foreign@test.com',
      address: 'Đà Nẵng',
      purchases: [],
      branch: 'foreign_branch_xyz',
      createdAt: '2026-08-15 22:00:00',
      totalSales: 300000.0,
    ),
  ];

  group('Adversarial processedCustomersProvider Store Scoping & Leakage Tests', () {
    test('Staff at store_001 receives strictly store_001 variants with zero cross-store leakage', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier(adversarialCustomerDataset)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);
      final result = container.read(processedCustomersProvider);
      expect(result.hasValue, isTrue);

      final scopedCustomers = result.value!.whereType<Customer>().toList();
      final scopedIds = scopedCustomers.map((c) => c.id).toSet();

      // Expected Store 1 set: exact, uppercase, alias, vn_accent, vn_no_accent, null_branch, empty_branch
      final expectedStore1Ids = {
        'c_s1_exact',
        'c_s1_uppercase',
        'c_s1_alias',
        'c_s1_vn_accent',
        'c_s1_vn_no_accent',
        'c_s1_null_branch',
        'c_s1_empty_branch',
      };

      expect(scopedIds, equals(expectedStore1Ids));

      // Rigorous Zero-Leakage Checks:
      // Store 2 customers
      expect(scopedIds.intersection({'c_s2_exact', 'c_s2_alias', 'c_s2_vn_accent', 'c_s2_vn_no_accent'}), isEmpty);
      // Store 3 customers
      expect(scopedIds.contains('c_s3_custom'), isFalse);
      // Collision branches
      expect(scopedIds.contains('c_collision_0010'), isFalse);
      expect(scopedIds.contains('c_collision_0020'), isFalse);
      // Foreign branch
      expect(scopedIds.contains('c_foreign'), isFalse);
    });

    test('Staff at store_002 receives strictly store_002 variants with zero cross-store leakage', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore2)),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier(adversarialCustomerDataset)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);
      final result = container.read(processedCustomersProvider);
      expect(result.hasValue, isTrue);

      final scopedCustomers = result.value!.whereType<Customer>().toList();
      final scopedIds = scopedCustomers.map((c) => c.id).toSet();

      // Expected Store 2 set: exact, alias, vn_accent, vn_no_accent
      final expectedStore2Ids = {
        'c_s2_exact',
        'c_s2_alias',
        'c_s2_vn_accent',
        'c_s2_vn_no_accent',
      };

      expect(scopedIds, equals(expectedStore2Ids));

      // Rigorous Zero-Leakage Checks:
      expect(scopedIds.intersection({
        'c_s1_exact',
        'c_s1_uppercase',
        'c_s1_alias',
        'c_s1_vn_accent',
        'c_s1_vn_no_accent',
        'c_s1_null_branch',
        'c_s1_empty_branch',
      }), isEmpty);
      expect(scopedIds.contains('c_s3_custom'), isFalse);
      expect(scopedIds.contains('c_collision_0010'), isFalse);
      expect(scopedIds.contains('c_collision_0020'), isFalse);
      expect(scopedIds.contains('c_foreign'), isFalse);
    });

    test('Staff at store_003 receives strictly store_003 customers with zero cross-store leakage', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore3)),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier(adversarialCustomerDataset)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);
      final result = container.read(processedCustomersProvider);
      expect(result.hasValue, isTrue);

      final scopedCustomers = result.value!.whereType<Customer>().toList();
      final scopedIds = scopedCustomers.map((c) => c.id).toSet();

      expect(scopedIds, equals({'c_s3_custom'}));
      expect(scopedIds.contains('c_s1_exact'), isFalse);
      expect(scopedIds.contains('c_s2_exact'), isFalse);
      expect(scopedIds.contains('c_s1_null_branch'), isFalse);
    });

    test('Admin has universal access to 100% of customers across all stores', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier(adversarialCustomerDataset)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);
      final result = container.read(processedCustomersProvider);
      expect(result.hasValue, isTrue);

      final allCustomers = result.value!.whereType<Customer>().toList();
      expect(allCustomers.length, equals(adversarialCustomerDataset.length));
      expect(allCustomers.map((c) => c.id).toSet(),
          equals(adversarialCustomerDataset.map((c) => c.id).toSet()));
    });

    test('Supervisor has universal access to 100% of customers across all stores', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier(adversarialCustomerDataset)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);
      final result = container.read(processedCustomersProvider);
      expect(result.hasValue, isTrue);

      final allCustomers = result.value!.whereType<Customer>().toList();
      expect(allCustomers.length, equals(adversarialCustomerDataset.length));
    });

    test('Staff search filtering never leaks customers from another store matching same keyword', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier(adversarialCustomerDataset)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);

      // Search keyword 'Khách' exists in almost all customers in store 1, 2, 3
      container.read(customerSearchQueryProvider.notifier).state = 'Khách';

      final result = container.read(processedCustomersProvider);
      expect(result.hasValue, isTrue);

      final matchedCustomers = result.value!.whereType<Customer>().toList();
      final matchedIds = matchedCustomers.map((c) => c.id).toSet();

      // All returned customers must strictly be from store 1
      for (final id in matchedIds) {
        expect(id.startsWith('c_s1_'), isTrue,
            reason: 'Customer $id leaked into Staff 1 search results');
      }
    });

    test('Staff date range filtering maintains store isolation', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore2)),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier(adversarialCustomerDataset)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);

      // Filter for date range 2026-08-08 to 2026-08-10
      container.read(customerCustomDateRangeProvider.notifier).state =
          DateTimeRange(
        start: DateTime(2026, 8, 8),
        end: DateTime(2026, 8, 10, 23, 59, 59),
      );
      container.read(customerTimeRangeTypeProvider.notifier).state =
          OverviewTimeRange.custom;

      final result = container.read(processedCustomersProvider);
      expect(result.hasValue, isTrue);

      final dateFiltered = result.value!.whereType<Customer>().toList();
      final dateFilteredIds = dateFiltered.map((c) => c.id).toSet();

      expect(dateFilteredIds, equals({'c_s2_exact', 'c_s2_alias', 'c_s2_vn_accent'}));
      expect(dateFilteredIds.contains('c_s2_vn_no_accent'), isFalse); // Date is 2026-08-11
      expect(dateFilteredIds.contains('c_s1_exact'), isFalse); // From store 1
    });
  });

  group('CustomersPage & CustomerDetailPage Security Action Guards Tests (R3)', () {
    testWidgets('CustomersPage for Staff hides Excel popup menu and scopes total revenue metrics',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier(adversarialCustomerDataset)),
            for (final c in adversarialCustomerDataset) ...[
              customerOrdersProvider(c.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(c.id)
                  .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
            ],
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Excel popup menu button in AppBar must be ABSENT for staff
      expect(find.byIcon(Icons.more_vert), findsNothing);

      // FAB to add customer should still be present
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Store 1 visible customers check (top item in list)
      expect(find.text('Khách Vãng Lai Empty Branch'), findsOneWidget);
      expect(find.text('Khách TB ID Chuẩn'), findsNothing);
      expect(find.text('Khách Ô Môn Store 3'), findsNothing);

      // Total revenue metric is hidden for Staff, customer count is visible
      expect(find.text('16.300.000'), findsNothing);
      expect(find.text('Tổng cộng (7 khách hàng)'), findsOneWidget);
    });

    testWidgets('CustomerDetailPage for Staff strictly omits Delete Customer option',
        (tester) async {
      final targetCustomer = adversarialCustomerDataset.first;
      await tester.pumpWidget(
        _buildTestApp(
          child: CustomerDetailPage(customer: targetCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
            customerOrdersProvider(targetCustomer.id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(targetCustomer.id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap AppBar popup menu
      final moreOptionsFinder = find.byIcon(Icons.more_vert);
      expect(moreOptionsFinder, findsOneWidget);
      await tester.tap(moreOptionsFinder);
      await tester.pumpAndSettle();

      // Delete option is HIDDEN for staff
      expect(find.widgetWithText(PopupMenuItem<String>, 'Xóa'), findsNothing);
      expect(find.widgetWithText(PopupMenuItem<String>, 'Chỉnh sửa'), findsOneWidget);
      expect(find.widgetWithText(PopupMenuItem<String>, 'Tạo đơn hàng'), findsOneWidget);
    });

    testWidgets('CustomerDetailPage for Admin permits Delete Customer option',
        (tester) async {
      final targetCustomer = adversarialCustomerDataset.first;
      await tester.pumpWidget(
        _buildTestApp(
          child: CustomerDetailPage(customer: targetCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(targetCustomer.id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(targetCustomer.id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap AppBar popup menu
      final moreOptionsFinder = find.byIcon(Icons.more_vert);
      expect(moreOptionsFinder, findsOneWidget);
      await tester.tap(moreOptionsFinder);
      await tester.pumpAndSettle();

      // Delete option is VISIBLE for admin
      expect(find.widgetWithText(PopupMenuItem<String>, 'Xóa'), findsOneWidget);
    });
  });

  group('POS Checkout Customer Search & Multi-Balance Scenario Tests (R3)', () {
    const custPositiveDebt = Customer(
      id: 'pos_c_pos_debt',
      name: 'Vũ Thị Phương',
      phone: '0911223344',
      email: 'phuong@test.com',
      address: 'Ninh Kiều, Cần Thơ',
      purchases: [],
      totalSales: 12000000.0,
      currentDebt: 5450000.0, // Positive debt
    );

    const custZeroDebt = Customer(
      id: 'pos_c_zero_debt',
      name: 'Đặng Quốc Huy',
      phone: '0922334455',
      email: 'huy@test.com',
      address: 'Bình Thủy, Cần Thơ',
      purchases: [],
      totalSales: 6000000.0,
      currentDebt: 0.0, // Zero debt
    );

    const custNegativeDebt = Customer(
      id: 'pos_c_negative_debt',
      name: 'Lê Hoàng Yến',
      phone: '0933445566',
      email: 'yen@test.com',
      address: 'Cái Răng, Cần Thơ',
      purchases: [],
      totalSales: 9000000.0,
      currentDebt: -350000.0, // Prepaid / Negative debt
    );

    const custNullDebt = Customer(
      id: 'pos_c_null_debt',
      name: 'Phạm Minh Trí',
      phone: '0944556677',
      email: 'tri@test.com',
      address: 'Ô Môn, Cần Thơ',
      purchases: [],
      totalSales: 3000000.0,
      currentDebt: null, // Null debt
    );

    testWidgets('POS Checkout selector card with positive debt customer shows badge',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const POSCheckoutPage(
            key: ValueKey('pos_test_pos_debt'),
            initialCustomer: custPositiveDebt,
          ),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
            availableStoresProvider.overrideWith((ref) async => {'store_001': 'Chi nhánh Thới Bình'}),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Vũ Thị Phương'), findsOneWidget);
      expect(find.text('Nợ hiện tại: 5.450.000đ'), findsOneWidget);
    });

    testWidgets('POS Checkout selector card with zero debt customer omits badge',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const POSCheckoutPage(
            key: ValueKey('pos_test_zero_debt'),
            initialCustomer: custZeroDebt,
          ),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
            availableStoresProvider.overrideWith((ref) async => {'store_001': 'Chi nhánh Thới Bình'}),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đặng Quốc Huy'), findsOneWidget);
      expect(find.textContaining('Nợ hiện tại:'), findsNothing);
    });

    testWidgets('POS Checkout selector card with negative debt customer omits badge',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const POSCheckoutPage(
            key: ValueKey('pos_test_neg_debt'),
            initialCustomer: custNegativeDebt,
          ),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
            availableStoresProvider.overrideWith((ref) async => {'store_001': 'Chi nhánh Thới Bình'}),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lê Hoàng Yến'), findsOneWidget);
      expect(find.textContaining('Nợ hiện tại:'), findsNothing);
    });

    testWidgets('POS Checkout selector card with null debt customer omits badge',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const POSCheckoutPage(
            key: ValueKey('pos_test_null_debt'),
            initialCustomer: custNullDebt,
          ),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
            availableStoresProvider.overrideWith((ref) async => {'store_001': 'Chi nhánh Thới Bình'}),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Phạm Minh Trí'), findsOneWidget);
      expect(find.textContaining('Nợ hiện tại:'), findsNothing);
    });

    testWidgets('POS Customer Search bottom sheet filters dynamically and displays debt labels conditionally',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const POSCheckoutPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
            customerListNotifierProvider.overrideWith(() => _FakeCustomerListNotifier([
                  custPositiveDebt,
                  custZeroDebt,
                  custNegativeDebt,
                  custNullDebt,
                ])),
            availableStoresProvider.overrideWith((ref) async => {'store_001': 'Chi nhánh Thới Bình'}),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Open customer selection sheet
      await tester.tap(find.text('Thay đổi'));
      await tester.pumpAndSettle();

      // All 4 customers visible initially
      expect(find.text('Vũ Thị Phương'), findsOneWidget);
      expect(find.text('Đặng Quốc Huy'), findsOneWidget);
      expect(find.text('Lê Hoàng Yến'), findsOneWidget);
      expect(find.text('Phạm Minh Trí'), findsOneWidget);

      // Only positive debt customer has trailing debt indicator
      expect(find.text('Nợ: 5.450.000đ'), findsOneWidget);
      expect(find.textContaining('Nợ: -'), findsNothing);
      expect(find.textContaining('Nợ: 0'), findsNothing);

      // Search by phone number
      final searchField = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(searchField, '0933445566'); // Phone of custNegativeDebt
      await tester.pumpAndSettle();

      // Filtered down to custNegativeDebt only
      expect(find.text('Lê Hoàng Yến'), findsOneWidget);
      expect(find.text('Vũ Thị Phương'), findsNothing);
      expect(find.text('Đặng Quốc Huy'), findsNothing);
      expect(find.text('Phạm Minh Trí'), findsNothing);

      // Select Lê Hoàng Yến
      await tester.tap(find.text('Lê Hoàng Yến'));
      await tester.pumpAndSettle();

      // Back on checkout page: Selected customer displayed, no misleading debt badge
      expect(find.text('Lê Hoàng Yến'), findsOneWidget);
      expect(find.textContaining('Nợ hiện tại:'), findsNothing);
    });
  });
}
