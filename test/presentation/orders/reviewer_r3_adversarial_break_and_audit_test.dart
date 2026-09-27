import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customer_debt_page.dart';
import 'package:stores/presentation/customers/pages/customer_detail_page.dart';
import 'package:stores/presentation/customers/pages/customer_transactions_page.dart';

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
  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Khánh Đăng',
    role: 'admin',
    storeId: 'store_002',
  );

  group('Adversarial Reviewer Round 3: Stress-Testing Edge Cases and Invariants', () {
    test('1. Customer.effectiveCurrentDebt eliminates phantom debt when static currentDebt is stale', () {
      // Customer Anh Nghĩa with an outdated/stale currentDebt (17.6M) that included cancelled HD013123 (8.3M)
      const customerStale = Customer(
        id: 'KH006900',
        name: 'Anh Nghĩa',
        phone: '0765029203',
        email: '',
        address: 'Bờ Bao - Kinh 5',
        purchases: [],
        currentDebt: 17600000.0, // Stale debt before cancellation resolution
        totalSales: 19200000.0,
      );

      final date = DateTime(2026, 9, 1, 14, 29, 8);
      final customerOrders = [
        // Cancelled invoice HD013123: gross 8.5M, discount 200k, debt 0
        Order(
          id: 'HD013123',
          customerId: 'KH006900',
          createdAt: date,
          items: const [],
          total: 8500000.0,
          discount: 200000.0,
          amountPaid: 0.0,
          debtAmount: 0.0,
          status: 'cancelled',
        ),
        // Active replacement invoice HD013123_01: gross 10.7M, discount 400k, paid 1M, debt 9.3M
        Order(
          id: 'HD013123_01',
          customerId: 'KH006900',
          createdAt: date,
          items: const [],
          total: 10700000.0,
          discount: 400000.0,
          amountPaid: 1000000.0,
          debtAmount: 9300000.0,
          status: 'completed',
        ),
      ];

      // Effective debt must calculate from live orders (9.300.000đ), NOT stale currentDebt (17.600.000đ)
      final calculatedDebt = customerStale.effectiveCurrentDebt(customerOrders, []);
      expect(calculatedDebt, equals(9300000.0),
          reason: 'effectiveCurrentDebt must strictly prioritize live orders and exclude cancelled orders');

      // Fallback when no orders exist in memory must still preserve static currentDebt
      final emptyOrdersDebt = customerStale.effectiveCurrentDebt([], []);
      expect(emptyOrdersDebt, equals(17600000.0));
    });

    test('2. Order.isCancelled and copyWith are resilient to case and Vietnamese aliases', () {
      final now = DateTime.now();

      final variations = [
        'cancelled',
        'CANCELLED',
        'canceled',
        'CANCELED',
        'Đã hủy',
        'ĐÃ HỦY',
        'đã huỷ',
        ' Huy ',
        'cancel',
      ];

      for (final v in variations) {
        final order = Order(
          id: 'TEST_$v',
          customerId: 'KH01',
          createdAt: now,
          items: const [],
          total: 5000000.0,
          discount: 500000.0,
          amountPaid: 0.0,
          debtAmount: 4500000.0,
          status: v,
        );

        expect(order.isCancelled, isTrue, reason: 'Status "$v" must be recognized as cancelled');
        expect(order.remainingDebt, equals(0.0), reason: 'Status "$v" must have remainingDebt == 0.0');
        expect(order.hasDebt, isFalse, reason: 'Status "$v" must have hasDebt == false');

        final copied = Order(
          id: 'COPY_$v',
          customerId: 'KH01',
          createdAt: now,
          items: const [],
          total: 5000000.0,
          debtAmount: 4500000.0,
          status: 'completed',
        ).copyWith(status: v);

        expect(copied.isCancelled, isTrue);
        expect(copied.debtAmount, equals(0.0), reason: 'copyWith(status: "$v") must auto-zero debtAmount');
        expect(copied.remainingDebt, equals(0.0));
        expect(copied.hasDebt, isFalse);
      }
    });

    testWidgets('3. CustomerTransactionsPage displays 0đ when customer only has cancelled orders', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const customerWithCancelledOnly = Customer(
        id: 'KH_CANCELLED_ONLY',
        name: 'Khách Đã Hủy Toàn Bộ',
        phone: '0912345678',
        email: '',
        address: 'Thới Bình',
        purchases: [],
        currentDebt: 0.0,
        totalSales: 8500000.0, // Stale sales figure from before cancellation
      );

      final date = DateTime(2026, 9, 1, 14, 29, 8);
      final orders = [
        Order(
          id: 'HD013123',
          customerId: 'KH_CANCELLED_ONLY',
          createdAt: date,
          items: [
            OrderItem(
              productId: 'GL22',
              productName: 'Giường tây trụ thao lao',
              quantity: 1,
              price: 8500000.0,
              warrantyMonths: 0,
              purchaseDate: date,
            ),
          ],
          total: 8500000.0,
          discount: 200000.0,
          status: 'cancelled',
          amountPaid: 0.0,
          debtAmount: 0.0,
          storeId: 'store_002',
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: customerWithCancelledOnly),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
            customerOrdersProvider('KH_CANCELLED_ONLY')
                .overrideWith((ref) => Stream.value(orders)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Top bar "Tổng bán - Tổng trả" must display 0 đ, NOT 8.500.000 đ
      expect(find.text('Tổng bán - Tổng trả'), findsOneWidget);
      expect(find.text('0'), findsWidgets); // Header should display '0'

      // Transaction row displays cancelled badge and strikethrough
      expect(find.text('Đã hủy'), findsOneWidget);
      expect(find.text('HD013123'), findsOneWidget);
    });

    testWidgets('4. CustomerDebtPage ledger lists order with netPayable (10.300.000đ) and remainingDebt (9.300.000đ)', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const customer = Customer(
        id: 'KH006900',
        name: 'Anh Nghĩa',
        phone: '0765029203',
        email: '',
        address: 'Thới Bình',
        purchases: [],
        currentDebt: 9300000.0,
      );

      final date = DateTime(2026, 9, 1, 14, 29, 8);
      final customerOrders = [
        // Cancelled order HD013123: should be skipped in debt ledger
        Order(
          id: 'HD013123',
          customerId: 'KH006900',
          createdAt: date,
          items: const [],
          total: 8500000.0,
          discount: 200000.0,
          amountPaid: 0.0,
          debtAmount: 0.0,
          status: 'cancelled',
        ),
        // Active replacement HD013123_01: Gross 10.7M, discount 400k -> netPayable 10.3M, paid 1M -> remainingDebt 9.3M
        Order(
          id: 'HD013123_01',
          customerId: 'KH006900',
          createdAt: date,
          items: const [],
          total: 10700000.0,
          discount: 400000.0,
          amountPaid: 1000000.0,
          debtAmount: 9300000.0,
          status: 'completed',
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerDebtPage(customer: customer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([customer])),
            customerOrdersProvider('KH006900')
                .overrideWith((ref) => Stream.value(customerOrders)),
            customerDebtTransactionsProvider('KH006900')
                .overrideWith((ref) => Stream.value([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Header displays 9.300.000 đ
      expect(find.text('Nợ cần thu'), findsOneWidget);
      expect(find.text('9.300.000 đ'), findsOneWidget);

      // Cancelled order HD013123 is completely excluded from debt ledger
      expect(find.text('HD013123'), findsNothing);

      // Active replacement HD013123_01 is listed with netPayable (10.300.000) and remaining debt (9.300.000)
      expect(find.text('HD013123_01'), findsOneWidget);
      expect(find.text('10.300.000'), findsOneWidget);
      expect(find.textContaining('9.300.000'), findsWidgets);
    });

    testWidgets('5. CustomerDetailPage reflects synchronized effectiveCurrentDebt (9.300.000đ) and effectiveTotalSales (10.700.000đ)', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const customerWithStaleSnapshot = Customer(
        id: 'KH006900',
        name: 'Anh Nghĩa',
        phone: '0765029203',
        email: '',
        address: 'Thới Bình',
        purchases: [],
        currentDebt: 17600000.0, // Stale snapshot containing cancelled order debt
        totalSales: 19200000.0, // Stale snapshot containing cancelled order sales
      );

      final date = DateTime(2026, 9, 1, 14, 29, 8);
      final orders = [
        Order(
          id: 'HD013123',
          customerId: 'KH006900',
          createdAt: date,
          items: const [],
          total: 8500000.0,
          discount: 200000.0,
          amountPaid: 0.0,
          debtAmount: 0.0,
          status: 'cancelled',
        ),
        Order(
          id: 'HD013123_01',
          customerId: 'KH006900',
          createdAt: date,
          items: const [],
          total: 10700000.0,
          discount: 400000.0,
          amountPaid: 1000000.0,
          debtAmount: 9300000.0,
          status: 'completed',
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerDetailPage(customer: customerWithStaleSnapshot),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([customerWithStaleSnapshot])),
            customerOrdersProvider('KH006900')
                .overrideWith((ref) => Stream.value(orders)),
            customerDebtTransactionsProvider('KH006900')
                .overrideWith((ref) => Stream.value([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Effective total sales displays 10.700.000 (excluding 8.5M cancelled HD013123)
      expect(find.text('10.700.000'), findsOneWidget);
      expect(find.text('19.200.000'), findsNothing);

      // Effective current debt displays 9.300.000 (excluding 8.3M cancelled HD013123)
      expect(find.text('9.300.000'), findsOneWidget);
      expect(find.text('17.600.000'), findsNothing);
    });
  });
}
