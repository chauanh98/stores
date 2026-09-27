import 'dart:async';

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
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/presentation/customers/pages/customer_debt_page.dart';
import 'package:stores/presentation/customers/pages/customer_detail_page.dart';
import 'package:stores/presentation/customers/pages/customer_transactions_page.dart';
import 'package:stores/presentation/reports/widgets/top_rankings_section.dart';

import '../../support/firebase_test_harness.dart';

// =============================================================================
// Mocks & Test Helpers
// =============================================================================

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

class _FakeCustomerListNotifier extends CustomerListNotifier {
  final List<Customer> _initial;
  _FakeCustomerListNotifier(this._initial);

  @override
  Future<List<Customer>> build() async => _initial;
}

class _MockCustomerRepository implements CustomerRepository {
  final Map<String, Customer> customers = {};

  _MockCustomerRepository([List<Customer> initial = const []]) {
    for (final c in initial) {
      customers[c.id] = c;
    }
  }

  @override
  Future<Customer?> fetchById(String id) async => customers[id];

  @override
  Stream<List<Customer>> watchAll() => Stream.value(customers.values.toList());

  @override
  Future<void> upsert(Customer customer) async {
    customers[customer.id] = customer;
  }

  @override
  Future<void> delete(String id) async {
    customers.remove(id);
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

// =============================================================================
// Test Suite
// =============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final currencyFormat = NumberFormat('#,###', 'vi_VN');

  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const staffStore1 = UserAccount(
    username: 'staff_dt',
    displayName: 'Nhân viên Đông Thắng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const staffStore2 = UserAccount(
    username: 'staff_tb',
    displayName: 'Nhân viên Thới Bình',
    role: 'nhanvien',
    storeId: 'store_002',
  );

  const testCustomer = Customer(
    id: 'CUST_001',
    name: 'Nguyễn Văn Test',
    phone: '0901234567',
    email: 'test@example.com',
    address: 'Cần Thơ',
    branch: 'Chi nhánh Đông Thắng',
    totalSales: 0.0,
    currentDebt: null,
    purchases: [],
  );

  final baseDate1 = DateTime(2026, 9, 15, 10, 0);
  final baseDate2 = DateTime(2026, 9, 16, 14, 30);

  final orderStore1 = Order(
    id: 'HD_DT_01',
    customerId: 'CUST_001',
    createdAt: baseDate1,
    items: [
      OrderItem(
        productId: 'SP001',
        productName: 'Ghế cao gỗ sồi',
        quantity: 1,
        price: 500000.0,
        warrantyMonths: 12,
        purchaseDate: baseDate1,
      ),
    ],
    total: 500000.0,
    storeId: 'store_001',
    createdByName: 'Nhân viên Đông Thắng',
    paymentMethod: 'cash',
    status: 'completed',
  );

  final orderStore2 = Order(
    id: 'HD_TB_01',
    customerId: 'CUST_001',
    createdAt: baseDate2,
    items: [
      OrderItem(
        productId: 'SP002',
        productName: 'Bàn trà xoan đào',
        quantity: 1,
        price: 1200000.0,
        warrantyMonths: 24,
        purchaseDate: baseDate2,
      ),
    ],
    total: 1200000.0,
    storeId: 'store_002',
    createdByName: 'Nhân viên Thới Bình',
    paymentMethod: 'transfer',
    status: 'completed',
  );

  final defaultOverrides = [
    authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
    currentStoreIdProvider.overrideWith((ref) => 'store_001'),
    availableStoresProvider.overrideWith((ref) async => {
          'store_001': 'Chi nhánh Đông Thắng',
          'store_002': 'Chi nhánh Thới Bình',
        }),
    customerListNotifierProvider
        .overrideWith(() => _FakeCustomerListNotifier([testCustomer])),
    customerRepositoryProvider
        .overrideWithValue(_MockCustomerRepository([testCustomer])),
    customerOrdersProvider(testCustomer.id)
        .overrideWith((ref) => Stream.value([orderStore2, orderStore1])),
    customerDebtTransactionsProvider(testCustomer.id)
        .overrideWith((ref) => Stream.value([])),
    topSellingProductsRankingProvider
        .overrideWith((ref) => const AsyncValue.data([])),
    topCustomersRankingProvider.overrideWith(
      (ref) => const AsyncValue.data([
        CustomerRankingItem(
          customerId: 'CUST_001',
          customerName: 'Nguyễn Văn Test',
          phoneNumber: '0901234567',
          orderCount: 2,
          totalSpent: 1700000.0,
        ),
      ]),
    ),
  ];

  // ===========================================================================
  // SECTION 1: Overview Drill-Down Flow (Admin)
  // ===========================================================================
  group('Cross-Branch Customer Sync - Overview Drill-Down Flow (Admin)', () {
    testWidgets(
      'Admin on store_001 drills down from TopRankingsSection -> CustomerDetailPage -> CustomerTransactionsPage -> CustomerDebtPage',
      (tester) async {
        // Set standard viewport
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildTestApp(
            child: const Scaffold(
              body: SingleChildScrollView(
                child: TopRankingsSection(),
              ),
            ),
            overrides: defaultOverrides,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Verify Top spending customers ranking reflects combined spend (1.7M)
        expect(find.text('Nguyễn Văn Test'), findsOneWidget);
        expect(find.text('1.700.000 đ'), findsOneWidget);

        // 2. Tap customer item to navigate to CustomerDetailPage
        final customerItem = find.text('Nguyễn Văn Test');
        await tester.ensureVisible(customerItem);
        await tester.tap(customerItem);
        await tester.pumpAndSettle();

        // Verify CustomerDetailPage is opened
        expect(find.byType(CustomerDetailPage), findsOneWidget);
        expect(find.text('Nguyễn Văn Test'), findsWidgets);

        // Verify displayTotalSales / effectiveTotalSales reflects 1.7M in transaction history tile
        final txTile = find.ancestor(
          of: find.text('Lịch sử giao dịch'),
          matching: find.byType(InkWell),
        );
        expect(
          find.descendant(
            of: txTile,
            matching: find.text(currencyFormat.format(1700000.0)),
          ),
          findsOneWidget,
        );

        // 3. Tap "Lịch sử giao dịch" to navigate to CustomerTransactionsPage
        final txHistoryTile = find.text('Lịch sử giao dịch');
        await tester.ensureVisible(txHistoryTile);
        await tester.tap(txHistoryTile);
        await tester.pumpAndSettle();

        // Verify CustomerTransactionsPage opened
        expect(find.byType(CustomerTransactionsPage), findsOneWidget);

        // Both orders from store_001 and store_002 are displayed with StoreBadges
        expect(find.text('HD_DT_01'), findsOneWidget);
        expect(find.text('HD_TB_01'), findsOneWidget);

        // StoreBadges: both branches present
        expect(find.byType(StoreBadge), findsNWidgets(2));
        expect(find.text('Chi nhánh Đông Thắng'), findsWidgets);
        expect(find.text('Chi nhánh Thới Bình'), findsWidgets);

        // Filter chips show counts: Tất cả (2), Đông Thắng (1), Thới Bình (1)
        expect(find.text('Tất cả chi nhánh (2)'), findsOneWidget);
        expect(find.text('Chi nhánh Đông Thắng (1)'), findsOneWidget);
        expect(find.text('Chi nhánh Thới Bình (1)'), findsOneWidget);

        // 4. Tap "Chi nhánh Thới Bình" ChoiceChip filters to only the 1.2M order
        final thoiBinhChip =
            find.byKey(const ValueKey('store_filter_store_002'));
        await tester.ensureVisible(thoiBinhChip);
        await tester.tap(thoiBinhChip);
        await tester.pumpAndSettle();

        // Verify only the 1.2M order is displayed
        expect(find.text('HD_TB_01'), findsOneWidget);
        expect(find.text('HD_DT_01'), findsNothing);
        // Header summary and order card both display 1.200.000
        expect(find.text(currencyFormat.format(1200000.0)), findsNWidgets(2));

        // 5. Pop back to CustomerDetailPage
        final backButton = find.byType(BackButton);
        if (backButton.evaluate().isNotEmpty) {
          await tester.tap(backButton);
        } else {
          Navigator.of(tester.element(find.byType(CustomerTransactionsPage)))
              .pop();
        }
        await tester.pumpAndSettle();

        expect(find.byType(CustomerDetailPage), findsOneWidget);

        // 6. Tap "Công nợ" to navigate to CustomerDebtPage
        final debtTile = find.text('Công nợ');
        await tester.ensureVisible(debtTile);
        await tester.tap(debtTile);
        await tester.pumpAndSettle();

        // Verify CustomerDebtPage opened
        expect(find.byType(CustomerDebtPage), findsOneWidget);

        // Header displays the synchronized effectiveCurrentDebt (1.700.000 đ)
        expect(find.text('Nợ cần thu'), findsOneWidget);
        expect(find.text('1.700.000 đ'), findsOneWidget);

        // Both invoices HD_DT_01 and HD_TB_01 are listed in ledger
        expect(find.text('HD_DT_01'), findsOneWidget);
        expect(find.text('HD_TB_01'), findsOneWidget);
      },
    );

    test(
      'topCustomersRankingProvider combines cross-branch spend for customer across store_001 and store_002',
      () async {
        const cust2 = Customer(
          id: 'CUST_002',
          name: 'Trần Thị B',
          phone: '0987654321',
          email: '',
          address: '',
          purchases: [],
        );

        final orderCust2Store1 = Order(
          id: 'HD_DT_02',
          customerId: 'CUST_002',
          createdAt: baseDate1,
          items: const [],
          total: 800000.0,
          storeId: 'store_001',
          paymentMethod: 'cash',
          status: 'completed',
        );

        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier([testCustomer, cust2])),
            allBranchesOrdersByDateRangeProvider.overrideWith(
              (ref, range) => Stream.value([
                orderStore1,
                orderStore2,
                orderCust2Store1,
              ]),
            ),
          ],
        );
        addTearDown(container.dispose);

        final completer = Completer<List<CustomerRankingItem>>();
        final sub = container.listen(
          topCustomersRankingProvider,
          (previous, next) {
            next.whenData((rankings) {
              if (rankings.isNotEmpty && !completer.isCompleted) {
                completer.complete(rankings);
              }
            });
          },
          fireImmediately: true,
        );
        addTearDown(sub.close);

        final rankings =
            await completer.future.timeout(const Duration(seconds: 3));

        expect(rankings.length, equals(2));
        // #1 is CUST_001 with combined spend 1.7M (500k at store_001 + 1.2M at store_002)
        expect(rankings[0].customerId, equals('CUST_001'));
        expect(rankings[0].customerName, equals('Nguyễn Văn Test'));
        expect(rankings[0].totalSpent, equals(1700000.0));
        expect(rankings[0].orderCount, equals(2));

        // #2 is CUST_002 with 800k at store_001
        expect(rankings[1].customerId, equals('CUST_002'));
        expect(rankings[1].customerName, equals('Trần Thị B'));
        expect(rankings[1].totalSpent, equals(800000.0));
        expect(rankings[1].orderCount, equals(1));
      },
    );
  });

  // ===========================================================================
  // SECTION 2: Staff Isolation Flow
  // ===========================================================================
  group('Cross-Branch Customer Sync - Staff Isolation Flow', () {
    testWidgets(
      'Staff assigned to store_001 only sees store_001 order (500k) and filter is locked',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomerTransactionsPage(customer: testCustomer),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                    'store_002': 'Chi nhánh Thới Bình',
                  }),
              // In production, customerOrdersProvider will only return store_001 orders for staff,
              // and CustomerTransactionsPage also isolates activeFilter to staffStoreId.
              customerOrdersProvider(testCustomer.id).overrideWith(
                (ref) => Stream.value([orderStore1]),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Only HD_DT_01 (500k) is displayed
        expect(find.text('HD_DT_01'), findsOneWidget);
        expect(find.text('HD_TB_01'), findsNothing);

        // Summary total and order card both reflect the 500k order
        expect(find.text(currencyFormat.format(500000.0)), findsNWidgets(2));
        expect(find.text('1 giao dịch'), findsOneWidget);

        // Store filter chip shows ONLY staff assigned store: store_001
        expect(find.byKey(const ValueKey('store_filter_store_001')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('store_filter_store_002')),
            findsNothing);
        expect(find.byKey(const ValueKey('store_filter_all')), findsNothing);

        // Store filter chip is locked (onSelected is null)
        final chipWidget = tester.widget<ChoiceChip>(
          find.byKey(const ValueKey('store_filter_store_001')),
        );
        expect(chipWidget.onSelected, isNull,
            reason: 'Staff must not be allowed to switch store filter');
      },
    );

    testWidgets(
      'Staff assigned to store_002 only sees store_002 order (1.2M) and filter is locked',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomerTransactionsPage(customer: testCustomer),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore2)),
              currentStoreIdProvider.overrideWith((ref) => 'store_002'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                    'store_002': 'Chi nhánh Thới Bình',
                  }),
              customerOrdersProvider(testCustomer.id).overrideWith(
                (ref) => Stream.value([orderStore2]),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Only HD_TB_01 (1.2M) is displayed
        expect(find.text('HD_TB_01'), findsOneWidget);
        expect(find.text('HD_DT_01'), findsNothing);

        // Summary total and order card both reflect 1.2M
        expect(find.text(currencyFormat.format(1200000.0)), findsNWidgets(2));

        // Locked to store_002
        expect(find.byKey(const ValueKey('store_filter_store_002')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('store_filter_store_001')),
            findsNothing);
        expect(find.byKey(const ValueKey('store_filter_all')), findsNothing);

        final chipWidget = tester.widget<ChoiceChip>(
          find.byKey(const ValueKey('store_filter_store_002')),
        );
        expect(chipWidget.onSelected, isNull);
      },
    );
  });

  // ===========================================================================
  // SECTION 3: Local Store Filter & StoreBadges Deep Verification
  // ===========================================================================
  group('CustomerTransactionsPage - Local Store Filter Interactive Switching', () {
    testWidgets(
      'Admin toggles between Tất cả -> Đông Thắng -> Thới Bình -> Tất cả smoothly',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomerTransactionsPage(customer: testCustomer),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                    'store_002': 'Chi nhánh Thới Bình',
                  }),
              customerOrdersProvider(testCustomer.id).overrideWith(
                (ref) => Stream.value([orderStore2, orderStore1]),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Initial state: Tất cả chi nhánh
        expect(find.text('HD_DT_01'), findsOneWidget);
        expect(find.text('HD_TB_01'), findsOneWidget);
        expect(find.text(currencyFormat.format(1700000.0)), findsOneWidget);

        // Switch to store_001
        final store1Chip = find.byKey(const ValueKey('store_filter_store_001'));
        await tester.ensureVisible(store1Chip);
        await tester.tap(store1Chip);
        await tester.pumpAndSettle();

        expect(find.text('HD_DT_01'), findsOneWidget);
        expect(find.text('HD_TB_01'), findsNothing);
        expect(find.text(currencyFormat.format(500000.0)), findsNWidgets(2));

        // Switch to store_002
        final store2Chip = find.byKey(const ValueKey('store_filter_store_002'));
        await tester.ensureVisible(store2Chip);
        await tester.tap(store2Chip);
        await tester.pumpAndSettle();

        expect(find.text('HD_TB_01'), findsOneWidget);
        expect(find.text('HD_DT_01'), findsNothing);
        expect(find.text(currencyFormat.format(1200000.0)), findsNWidgets(2));

        // Switch back to all
        final allChip = find.byKey(const ValueKey('store_filter_all'));
        await tester.ensureVisible(allChip);
        await tester.tap(allChip);
        await tester.pumpAndSettle();

        expect(find.text('HD_DT_01'), findsOneWidget);
        expect(find.text('HD_TB_01'), findsOneWidget);
        expect(find.text(currencyFormat.format(1700000.0)), findsOneWidget);
      },
    );

    testWidgets('StoreBadge renders distinct styling for store_001 vs store_002',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                StoreBadge(storeId: 'store_001'),
                StoreBadge(storeId: 'store_002'),
                StoreBadge(storeId: 'store_003', storeName: 'Chi nhánh Quận 7'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.text('Chi nhánh Quận 7'), findsOneWidget);

      expect(find.byIcon(Icons.storefront_outlined), findsNWidgets(2));
      expect(find.byIcon(Icons.store_outlined), findsOneWidget);
    });
  });

  // ===========================================================================
  // SECTION 4: Debt & Total Sales Calculation Synchronization
  // ===========================================================================
  group('Cross-Branch Calculations Synchronization', () {
    testWidgets(
      'CustomerDetailPage displays dynamic effectiveTotalSales calculated from multi-branch orders',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomerDetailPage(customer: testCustomer),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              customerListNotifierProvider
                  .overrideWith(() => _FakeCustomerListNotifier([testCustomer])),
              customerOrdersProvider(testCustomer.id).overrideWith(
                (ref) => Stream.value([orderStore1, orderStore2]),
              ),
              customerDebtTransactionsProvider(testCustomer.id).overrideWith(
                (ref) => Stream.value([]),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // 500k + 1.2M = 1.7M in transaction history row
        final txRow = find.ancestor(
          of: find.text('Lịch sử giao dịch'),
          matching: find.byType(InkWell),
        );
        expect(
          find.descendant(
            of: txRow,
            matching: find.text(currencyFormat.format(1700000.0)),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'CustomerDebtPage reflects synced effectiveCurrentDebt considering payments across branches',
      (tester) async {
        final paymentTx = CustomerDebtTransaction(
          id: 'PAY_001',
          code: 'PAY_001',
          customerId: testCustomer.id,
          date: DateTime(2026, 9, 17, 10, 0),
          amount: 700000.0,
          remainingDebt: 1000000.0, // 1.7M - 700k = 1.0M
          type: DebtTransactionType.payment,
          note: 'Khách thanh toán một phần nợ',
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomerDebtPage(customer: testCustomer),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              customerListNotifierProvider
                  .overrideWith(() => _FakeCustomerListNotifier([testCustomer])),
              customerOrdersProvider(testCustomer.id).overrideWith(
                (ref) => Stream.value([orderStore1, orderStore2]),
              ),
              customerDebtTransactionsProvider(testCustomer.id).overrideWith(
                (ref) => Stream.value([paymentTx]),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Header displays remaining debt: 1.000.000 đ
        expect(find.text('Nợ cần thu'), findsOneWidget);
        expect(find.text('1.000.000 đ'), findsOneWidget);

        // Ledger includes the payment transaction
        expect(find.text('Khách thanh toán một phần nợ'), findsOneWidget);
      },
    );
  });

  // ===========================================================================
  // SECTION 5: Backend & Stream Provider Cross-Branch Integration
  // ===========================================================================
  group('customerOrdersProvider - Real Backend Stream Aggregation', () {
    late MockFirebaseDatabase mockDb;

    setUp(() {
      mockDb = MockFirebaseDatabase();
    });

    test('Admin queries customerOrdersProvider and combines orders from store_001 & store_002',
        () async {
      mockDb.seedData('stores/store_001/orders', {
        'ord_001': {
          'id': 'ord_001',
          'customerId': 'CUST_001',
          'total': 500000.0,
          'createdAt': '2026-09-15T10:00:00.000Z',
          'status': 'completed',
        },
      });

      mockDb.seedData('stores/store_002/orders', {
        'ord_002': {
          'id': 'ord_002',
          'customerId': 'CUST_001',
          'total': 1200000.0,
          'createdAt': '2026-09-16T14:30:00.000Z',
          'status': 'completed',
          'storeId': 'store_002',
        },
      });

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          availableStoresProvider.overrideWith((ref) async => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
              }),
          firebaseDatabaseProvider.overrideWithValue(mockDb),
        ],
      );
      addTearDown(container.dispose);

      final completer = Completer<List<Order>>();
      final sub = container.listen(
        customerOrdersProvider('CUST_001'),
        (previous, next) {
          next.whenData((orders) {
            if (orders.length == 2 && !completer.isCompleted) {
              completer.complete(orders);
            }
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final orders = await completer.future.timeout(const Duration(seconds: 3));

      expect(orders.length, equals(2));
      // Sorted newest first
      expect(orders[0].id, equals('ord_002'));
      expect(orders[0].total, equals(1200000.0));
      expect(orders[0].storeId, equals('store_002'));

      expect(orders[1].id, equals('ord_001'));
      expect(orders[1].total, equals(500000.0));
      // Stamped storeId
      expect(orders[1].storeId, equals('store_001'));
    });

    test('Staff on store_001 receives ONLY store_001 orders from customerOrdersProvider',
        () async {
      mockDb.seedData('stores/store_001/orders', {
        'ord_001': {
          'id': 'ord_001',
          'customerId': 'CUST_001',
          'total': 500000.0,
          'createdAt': '2026-09-15T10:00:00.000Z',
          'status': 'completed',
        },
      });

      mockDb.seedData('stores/store_002/orders', {
        'ord_002': {
          'id': 'ord_002',
          'customerId': 'CUST_001',
          'total': 1200000.0,
          'createdAt': '2026-09-16T14:30:00.000Z',
          'status': 'completed',
        },
      });

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          availableStoresProvider.overrideWith((ref) async => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
              }),
          firebaseDatabaseProvider.overrideWithValue(mockDb),
        ],
      );
      addTearDown(container.dispose);

      final completer = Completer<List<Order>>();
      final sub = container.listen(
        customerOrdersProvider('CUST_001'),
        (previous, next) {
          next.whenData((orders) {
            if (orders.isNotEmpty && !completer.isCompleted) {
              completer.complete(orders);
            }
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final orders = await completer.future.timeout(const Duration(seconds: 3));

      // Staff receives ONLY 1 order from store_001
      expect(orders.length, equals(1));
      expect(orders.first.id, equals('ord_001'));
      expect(orders.first.total, equals(500000.0));
    });
  });

  // ===========================================================================
  // SECTION 6: Adversarial & Edge Cases
  // ===========================================================================
  group('Cross-Branch Customer Sync - Adversarial & Edge Cases', () {
    test('Cancelled order at store_002 is excluded from effectiveTotalSales', () {
      final cancelledOrderStore2 = orderStore2.copyWith(status: 'cancelled');
      final effectiveSales =
          testCustomer.effectiveTotalSales([orderStore1, cancelledOrderStore2]);

      // Only the 500k active order is counted
      expect(effectiveSales, equals(500000.0));
    });

    testWidgets(
      'Admin active on store_001 views customer with orders ONLY at store_002 without being hidden',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomerTransactionsPage(customer: testCustomer),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                    'store_002': 'Chi nhánh Thới Bình',
                  }),
              customerOrdersProvider(testCustomer.id).overrideWith(
                (ref) => Stream.value([orderStore2]),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // The order from store_002 is fully visible with Thới Bình badge
        expect(find.text('HD_TB_01'), findsOneWidget);
        expect(find.text('Chi nhánh Thới Bình'), findsWidgets);
        expect(find.text(currencyFormat.format(1200000.0)), findsNWidgets(2));
      },
    );

    testWidgets(
      'Narrow viewport (360x640) renders CustomerTransactionsPage with zero overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomerTransactionsPage(customer: testCustomer),
            overrides: defaultOverrides,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(CustomerTransactionsPage), findsOneWidget);
      },
    );
  });
}
