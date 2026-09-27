import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/user_account.dart';
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

  const staffUser = UserAccount(
    username: 'staff_cashier',
    displayName: 'Nhân viên thu ngân',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const adminUser = UserAccount(
    username: 'admin_boss',
    displayName: 'Chủ cửa hàng',
    role: 'admin',
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

  group('Customer Debt Visibility & POS Preservation Tests', () {
    testWidgets(
        'Preserves and displays individual customer debt for Staff (cashier) role when debt > 0',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerListTile(customer: customerWithDebt),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            customerOrdersProvider(customerWithDebt.id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(customerWithDebt.id).overrideWith(
                (ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Customer name visible, but total sales hidden for Staff
      expect(find.text('Nguyễn Văn Nam'), findsOneWidget);
      expect(
          find.text(currencyFormat.format(customerWithDebt.totalSales)),
          findsNothing);

      // Customer debt is preserved and visible to staff cashiers
      expect(
          find.text('Công nợ: ${currencyFormat.format(2500000.0)}'),
          findsOneWidget);
    });

    testWidgets(
        'Hides debt indicator when customer current debt is 0 (Staff sees name and chevron, no sales/debt)',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerListTile(customer: customerWithoutDebt),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            customerOrdersProvider(customerWithoutDebt.id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(customerWithoutDebt.id)
                .overrideWith(
                    (ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trần Thị Mai'), findsOneWidget);
      expect(
          find.text(currencyFormat.format(customerWithoutDebt.totalSales)),
          findsNothing);

      // No debt text
      expect(find.textContaining('Công nợ:'), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets(
        'Admin account sees total sales and debt on CustomerListTile',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerListTile(customer: customerWithDebt),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(customerWithDebt.id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(customerWithDebt.id).overrideWith(
                (ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nguyễn Văn Nam'), findsOneWidget);
      expect(
          find.text(currencyFormat.format(customerWithDebt.totalSales)),
          findsOneWidget);
      expect(
          find.text('Công nợ: ${currencyFormat.format(2500000.0)}'),
          findsOneWidget);
    });
  });
}
