import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/user_account.dart';
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
  const staffUser = UserAccount(
    username: 'staff_cashier',
    displayName: 'Nhân viên thu ngân',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const customerWithDebt = Customer(
    id: 'cust_001',
    name: 'Nguyễn Văn Nam',
    phone: '0901234567',
    email: 'nam@example.com',
    address: 'Hà Nội',
    purchases: [],
    totalSales: 15000000.0,
    currentDebt: 2500000.0,
  );

  const customerWithoutDebt = Customer(
    id: 'cust_002',
    name: 'Trần Thị Mai',
    phone: '0987654321',
    email: 'mai@example.com',
    address: 'TP.HCM',
    purchases: [],
    totalSales: 5000000.0,
    currentDebt: 0.0,
  );

  group('POS Checkout Customer Debt Tests (R3)', () {
    testWidgets(
        'Displays debt badge on customer selector card when customer with debt is selected',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const POSCheckoutPage(initialCustomer: customerWithDebt),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Customer name should be shown
      expect(find.text('Nguyễn Văn Nam'), findsOneWidget);

      // Customer debt badge should be displayed
      expect(find.text('Nợ hiện tại: 2.500.000đ'), findsOneWidget);
    });

    testWidgets(
        'Does not display debt badge on customer selector card for customer with 0 debt',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const POSCheckoutPage(initialCustomer: customerWithoutDebt),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trần Thị Mai'), findsOneWidget);
      expect(find.textContaining('Nợ hiện tại:'), findsNothing);
    });

    testWidgets(
        'Customer search bottom sheet supports search and displays trailing debt',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const POSCheckoutPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            customerListNotifierProvider.overrideWith(() =>
                _FakeCustomerListNotifier(
                    [customerWithDebt, customerWithoutDebt])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Initially retail customer
      expect(find.text('Khách lẻ'), findsOneWidget);

      // Tap "Thay đổi" to open customer selection bottom sheet
      await tester.tap(find.text('Thay đổi'));
      await tester.pumpAndSettle();

      // Bottom sheet title and search input
      expect(find.text('Chọn khách hàng'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);

      // Both customers visible
      expect(find.text('Nguyễn Văn Nam'), findsOneWidget);
      expect(find.text('Trần Thị Mai'), findsOneWidget);

      // Customer with debt has trailing debt label
      expect(find.text('Nợ: 2.500.000đ'), findsOneWidget);

      // Type in search field to filter
      final searchField = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      );
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'Nam');
      await tester.pumpAndSettle();

      // Now only customerWithDebt should be in filtered list
      expect(find.text('Nguyễn Văn Nam'), findsOneWidget);
      expect(find.text('Trần Thị Mai'), findsNothing);

      // Tap on customer to select
      await tester.tap(find.text('Nguyễn Văn Nam'));
      await tester.pumpAndSettle();

      // Back on checkout page, selected customer and debt badge are displayed
      expect(find.text('Nguyễn Văn Nam'), findsOneWidget);
      expect(find.text('Nợ hiện tại: 2.500.000đ'), findsOneWidget);
    });
  });
}
