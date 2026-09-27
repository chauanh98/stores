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
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const customer1 = Customer(
    id: 'cust_001',
    name: 'Khách hàng VIP 1',
    phone: '0901111111',
    email: '',
    address: '',
    purchases: [],
  );

  final testOrders = [
    Order(
      id: 'HD000101',
      customerId: 'cust_001',
      createdAt: DateTime(2026, 9, 26, 15, 30),
      items: [
        OrderItem(
          productId: 'p1',
          productName: 'Nệm cao su non 1m6',
          quantity: 1,
          price: 2500000.0,
          warrantyMonths: 24,
          purchaseDate: DateTime(2026, 9, 26),
        ),
        OrderItem(
          productId: 'p2',
          productName: 'Gối ôm bông gòn',
          quantity: 2,
          price: 150000.0,
          warrantyMonths: 0,
          purchaseDate: DateTime(2026, 9, 26),
        ),
      ],
      total: 2800000.0,
      amountPaid: 2800000.0,
      status: 'completed',
      paymentMethod: 'cash',
    ),
    Order(
      id: 'HD000102',
      customerId: 'cust_001',
      createdAt: DateTime(2026, 9, 26, 14, 15),
      items: [
        OrderItem(
          productId: 'p3',
          productName: 'Bàn trà gỗ sồi',
          quantity: 1,
          price: 1200000.0,
          warrantyMonths: 12,
          purchaseDate: DateTime(2026, 9, 26),
        ),
      ],
      total: 1200000.0,
      amountPaid: 1200000.0,
      status: 'completed',
      paymentMethod: 'transfer',
    ),
  ];

  testWidgets(
      'InvoicesPage displays summary header bar and expandable items preview',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      _buildTestApp(
        child: const InvoicesPage(),
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
          allBranchesOrdersByDateRangeProvider
              .overrideWith((ref, range) => Stream.value(testOrders)),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier([customer1])),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify summary header bar appears
    expect(find.byKey(const Key('invoices_items_summary_bar')), findsOneWidget);
    expect(find.text('2 đơn'), findsOneWidget);
    expect(find.text('4 sp'), findsOneWidget); // 1 + 2 + 1 = 4 products
    expect(find.text('4.000.000 đ'), findsOneWidget);

    // 2. Verify invoice card item count badges
    expect(find.text('2 mặt hàng • 3 sp'), findsOneWidget); // Order 1
    expect(find.text('1 mặt hàng • 1 sp'), findsOneWidget); // Order 2

    // 3. Verify single-line preview text in collapsed state
    expect(find.textContaining('Nệm cao su non 1m6 (x1)'), findsOneWidget);
    expect(find.textContaining('Bàn trà gỗ sồi (x1)'), findsOneWidget);

    // 4. Expand individual card for HD000101 (newest, so it is first)
    final expandFirstCardBtn = find.text('Xem chi tiết món').first;
    await tester.tap(expandFirstCardBtn);
    await tester.pumpAndSettle();

    // Now detailed item view is visible for Order 1
    expect(find.text('Thu gọn'), findsOneWidget);
    expect(find.text('x1'), findsOneWidget);
    expect(find.text('x2'), findsOneWidget);
    expect(find.text('2.500.000 đ'), findsOneWidget);
    expect(find.text('300.000 đ'), findsOneWidget);

    // 5. Collapse card back
    await tester.tap(find.text('Thu gọn'));
    await tester.pumpAndSettle();
    expect(find.text('Thu gọn'), findsNothing);

    // 6. Test expand all toggle from header bar
    final toggleAllBtn = find.byKey(const Key('invoices_toggle_expand_all_button'));
    expect(toggleAllBtn, findsOneWidget);
    await tester.tap(toggleAllBtn);
    await tester.pumpAndSettle();

    // Both cards should now be expanded
    expect(find.text('Gọn'), findsOneWidget);
    expect(find.text('Thu gọn'), findsNWidgets(2));
    expect(find.text('x1'), findsNWidgets(2)); // p1 and p3 both have qty 1
    expect(find.text('x2'), findsOneWidget);

    // Toggle collapse all
    await tester.tap(toggleAllBtn);
    await tester.pumpAndSettle();
    expect(find.text('Xem món'), findsOneWidget);
    expect(find.text('Thu gọn'), findsNothing);
  });
}
