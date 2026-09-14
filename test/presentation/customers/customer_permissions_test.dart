import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customer_detail_page.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';

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
  const staffStore1 = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên Thới Bình',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const List<Customer> sampleCustomers = [
    Customer(
      id: 'cust_01',
      name: 'Khách Chi Nhánh 1',
      phone: '0901111111',
      email: 'c1@test.com',
      address: 'Thới Bình',
      purchases: [],
      branch: 'store_001',
      createdAt: '2026-08-01 10:00:00',
      totalSales: 1500000,
    ),
    Customer(
      id: 'cust_02',
      name: 'Khách Chi Nhánh 2',
      phone: '0902222222',
      email: 'c2@test.com',
      address: 'Đông Thắng',
      purchases: [],
      branch: 'store_002',
      createdAt: '2026-08-02 10:00:00',
      totalSales: 2500000,
    ),
  ];

  group('CustomersPage Permissions & Action Guards Tests (R3)', () {
    testWidgets('Staff cannot see Excel action menu and only sees scoped customers',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier(sampleCustomers)),
            customerOrdersProvider(sampleCustomers[0].id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerOrdersProvider(sampleCustomers[1].id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(sampleCustomers[0].id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
            customerDebtTransactionsProvider(sampleCustomers[1].id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Excel popup menu button should be HIDDEN for Staff
      expect(find.byIcon(Icons.more_vert), findsNothing);

      // Staff at store_001 only sees cust_01
      expect(find.text('Khách Chi Nhánh 1'), findsOneWidget);
      expect(find.text('Khách Chi Nhánh 2'), findsNothing);
    });

    testWidgets('Admin sees all customers',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier(sampleCustomers)),
            customerOrdersProvider(sampleCustomers[0].id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerOrdersProvider(sampleCustomers[1].id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(sampleCustomers[0].id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
            customerDebtTransactionsProvider(sampleCustomers[1].id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Admin sees both customers
      expect(find.text('Khách Chi Nhánh 1'), findsOneWidget);
      expect(find.text('Khách Chi Nhánh 2'), findsOneWidget);
    });
  });

  group('CustomerDetailPage Action Guards Tests (R3)', () {
    testWidgets('Staff cannot delete customer on CustomerDetailPage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: CustomerDetailPage(customer: sampleCustomers.first),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
            customerOrdersProvider(sampleCustomers.first.id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(sampleCustomers.first.id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap on more options menu
      final moreOptionsFinder = find.byIcon(Icons.more_vert);
      expect(moreOptionsFinder, findsOneWidget);
      await tester.tap(moreOptionsFinder);
      await tester.pumpAndSettle();

      // PopupMenuItem 'Xóa' is HIDDEN for staff
      expect(find.widgetWithText(PopupMenuItem<String>, 'Xóa'), findsNothing);
      expect(find.widgetWithText(PopupMenuItem<String>, 'Tạo đơn hàng'),
          findsOneWidget);
    });

    testWidgets('Admin can see delete customer option on CustomerDetailPage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: CustomerDetailPage(customer: sampleCustomers.first),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(sampleCustomers.first.id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(sampleCustomers.first.id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap on more options menu
      final moreOptionsFinder = find.byIcon(Icons.more_vert);
      expect(moreOptionsFinder, findsOneWidget);
      await tester.tap(moreOptionsFinder);
      await tester.pumpAndSettle();

      // Delete option is VISIBLE for admin
      expect(find.widgetWithText(PopupMenuItem<String>, 'Xóa'), findsOneWidget);
    });
  });
}
