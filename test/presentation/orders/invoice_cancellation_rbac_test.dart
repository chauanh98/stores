import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/widgets/cancel_invoice_dialog.dart';

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

class _MockCancelInvoiceUseCase implements CancelInvoiceUseCase {
  Order? capturedOrder;
  String? capturedReason;
  UserAccount? capturedUser;
  String? capturedStoreId;
  int executionCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Order> execute({
    required Order order,
    required String cancelReason,
    required UserAccount currentUser,
    required String storeId,
  }) async {
    executionCount++;
    capturedOrder = order;
    capturedReason = cancelReason;
    capturedUser = currentUser;
    capturedStoreId = storeId;
    return order.copyWith(
      status: 'cancelled',
      cancelReason: cancelReason,
      cancelledBy: currentUser.username,
      cancelledByName: currentUser.name,
      cancelledAt: DateTime.now(),
    );
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
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  const adminUser = UserAccount(
    username: 'admin_user',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff_user',
    displayName: 'Nhân viên bán hàng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const customer = Customer(
    id: 'cust_001',
    name: 'Khách hàng A',
    phone: '0909999999',
    email: '',
    address: '',
    purchases: [],
  );

  final completedOrder = Order(
    id: 'HD000088',
    customerId: 'cust_001',
    createdAt: DateTime.now(),
    items: [
      OrderItem(
        productId: 'p1',
        productName: 'iPhone 15 Pro Max',
        quantity: 1,
        price: 30000000.0,
        warrantyMonths: 12,
        purchaseDate: DateTime.now(),
      )
    ],
    total: 30000000.0,
    amountPaid: 30000000.0,
    debtAmount: 0.0,
    status: 'completed',
    paymentMethod: 'cash',
    createdBy: 'staff_user',
    createdByName: 'Nhân viên bán hàng',
  );

  final cancelledOrder = Order(
    id: 'HD000099',
    customerId: 'cust_001',
    createdAt: DateTime.now(),
    items: [
      OrderItem(
        productId: 'p1',
        productName: 'iPhone 15 Pro Max',
        quantity: 1,
        price: 30000000.0,
        warrantyMonths: 12,
        purchaseDate: DateTime.now(),
      )
    ],
    total: 30000000.0,
    amountPaid: 30000000.0,
    debtAmount: 0.0,
    status: 'cancelled',
    cancelReason: 'Sản phẩm lỗi nhà sản xuất',
    cancelledBy: 'admin_user',
    cancelledByName: 'Quản trị viên',
    cancelledAt: DateTime(2026, 8, 17, 15, 30),
    paymentMethod: 'cash',
  );

  group('Invoice Cancellation RBAC & Dialog Interaction Tests (R5)', () {
    testWidgets('Staff user does not see Cancel Invoice action on completed order',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            accountsListProvider.overrideWith(
                (ref) => Stream.value([adminUser, staffUser])),
            productListProvider.overrideWith((ref) => Stream.value([])),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value([completedOrder])),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier([customer])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Open details bottom sheet by tapping order tile
      await tester.tap(find.text('Khách hàng A'));
      await tester.pumpAndSettle();

      // "In Hóa Đơn" and "Trả hàng" should exist
      expect(find.text('In Hóa Đơn'), findsOneWidget);
      expect(find.text('Trả hàng'), findsOneWidget);

      // "Hủy HĐ" action button should NOT exist for staff
      expect(find.byKey(const Key('cancel_invoice_action_button')),
          findsNothing);
    });

    testWidgets('Admin user sees Cancel Invoice action button on completed order',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider.overrideWith(
                (ref) => Stream.value([adminUser, staffUser])),
            productListProvider.overrideWith((ref) => Stream.value([])),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value([completedOrder])),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier([customer])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Open details bottom sheet
      await tester.tap(find.text('Khách hàng A'));
      await tester.pumpAndSettle();

      // "Hủy HĐ" action button must exist for admin
      expect(find.byKey(const Key('cancel_invoice_action_button')),
          findsOneWidget);
    });

    testWidgets(
        'CancelInvoiceDialog validates empty reason and executes usecase upon confirmation',
        (tester) async {
      final mockUseCase = _MockCancelInvoiceUseCase();

      await tester.pumpWidget(
        _buildTestApp(
          child: CancelInvoiceDialog(order: completedOrder, customer: customer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            cancelInvoiceUseCaseProvider.overrideWithValue(mockUseCase),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Warning text exists
      expect(
        find.textContaining('Hủy hóa đơn sẽ tự động hoàn trả số lượng tồn kho'),
        findsOneWidget,
      );

      // Confirm button pressed with empty reason -> validation error
      await tester.tap(find.byKey(const Key('confirm_cancel_invoice_button')));
      await tester.pumpAndSettle();

      expect(find.text('Lý do hủy đơn không được để trống'), findsOneWidget);
      expect(mockUseCase.executionCount, 0);

      // Enter valid reason
      await tester.enterText(
        find.byKey(const Key('cancel_invoice_reason_field')),
        'Khách đổi ý mua dòng khác',
      );
      await tester.pumpAndSettle();

      // Confirm cancellation
      await tester.tap(find.byKey(const Key('confirm_cancel_invoice_button')));
      await tester.pumpAndSettle();

      // Verified use case execution
      expect(mockUseCase.executionCount, 1);
      expect(mockUseCase.capturedReason, 'Khách đổi ý mua dòng khác');
      expect(mockUseCase.capturedUser?.username, 'admin_user');
      expect(mockUseCase.capturedOrder?.id, 'HD000088');
    });

    testWidgets(
        'Cancelled order displays red banner with reason and details in bottom sheet',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider.overrideWith(
                (ref) => Stream.value([adminUser, staffUser])),
            productListProvider.overrideWith((ref) => Stream.value([])),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value([cancelledOrder])),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier([customer])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Open cancelled order details
      await tester.tap(find.text('Khách hàng A'));
      await tester.pumpAndSettle();

      // Red banner should show cancel metadata
      expect(find.text('HÓA ĐƠN ĐÃ HỦY'), findsOneWidget);
      expect(find.text('Lý do hủy: Sản phẩm lỗi nhà sản xuất'), findsOneWidget);
      expect(find.text('Người hủy: Quản trị viên'), findsOneWidget);
      expect(find.text('Thời gian hủy: 17/08/2026 15:30'), findsOneWidget);

      // Return & Debt buttons must not exist for cancelled order
      expect(find.byKey(const Key('return_order_action_button')), findsNothing);
      expect(find.byKey(const Key('collect_debt_action_button')), findsNothing);
    });
  });
}
