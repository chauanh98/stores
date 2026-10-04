import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
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
}

class _FakeCustomerRepository implements CustomerRepository {
  final Map<String, Customer> customers = {};
  final List<String> deletedCustomerIds = [];
  final StreamController<List<Customer>> _controller =
      StreamController<List<Customer>>.broadcast();

  _FakeCustomerRepository(List<Customer> initial) {
    for (final c in initial) {
      customers[c.id] = c;
    }
  }

  void emitCurrent() {
    _controller.add(customers.values.toList());
  }

  @override
  Stream<List<Customer>> watchAll() => _controller.stream;

  @override
  Future<Customer?> fetchById(String id) async => customers[id];

  @override
  Future<void> upsert(Customer customer) async {
    customers[customer.id] = customer;
    emitCurrent();
  }

  bool shouldThrowOnDelete = false;
  int deleteDelayMs = 0;

  @override
  Future<void> delete(String id) async {
    if (deleteDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: deleteDelayMs));
    }
    if (shouldThrowOnDelete) {
      throw Exception('Network connection timed out');
    }
    deletedCustomerIds.add(id);
    customers.remove(id);
    emitCurrent();
  }
}

class _FakeCustomerListNotifier
    extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _FakeCustomerListNotifier(this.customers);

  List<Customer> customers;

  @override
  Future<List<Customer>> build() async {
    return customers;
  }

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(customers);
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
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const customerWithDebt = Customer(
    id: 'cust_indebt',
    name: 'Nguyễn Văn Nợ',
    phone: '0901112233',
    email: 'no@example.com',
    address: 'Hà Nội',
    purchases: [],
    totalSales: 10000000.0,
    currentDebt: 3500000.0,
  );

  const customerWithoutDebt = Customer(
    id: 'cust_clean',
    name: 'Lê Thị Sạch Nợ',
    phone: '0909998877',
    email: 'clean@example.com',
    address: 'Đà Nẵng',
    purchases: [],
    totalSales: 8000000.0,
    currentDebt: 0.0,
  );

  group('Customer Swipe-To-Delete & Debt Guard Tests (R2)', () {
    testWidgets(
      'Vuốt khách hàng đang có công nợ (totalDebt > 0) -> bị chặn xóa và hiển thị cảnh báo công nợ',
      (tester) async {
        final fakeRepo = _FakeCustomerRepository([customerWithDebt]);

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomerListTile(customer: customerWithDebt),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              customerRepositoryProvider.overrideWithValue(fakeRepo),
              customerOrdersProvider(customerWithDebt.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(customerWithDebt.id)
                  .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);

        // Swipe horizontal to delete
        final dismissible =
            find.byKey(const Key('dismissible_customer_cust_indebt'));
        expect(dismissible, findsOneWidget);

        await tester.drag(dismissible, const Offset(-500, 0));
        await tester.pumpAndSettle();

        // Warning snackbar must be displayed
        expect(
          find.textContaining('Không được phép xóa khách hàng đang nợ (công nợ tồn đọng: 3.500.000 đ)'),
          findsOneWidget,
        );

        // Delete confirmation dialog is NOT shown
        expect(find.byType(AlertDialog), findsNothing);

        // Customer is NOT deleted from repository
        expect(fakeRepo.deletedCustomerIds, isEmpty);

        // Customer tile remains visible on screen
        expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      },
    );

    testWidgets(
      'Vuốt khách hàng không có công nợ -> hiển thị dialog xác nhận -> hủy thì không xóa',
      (tester) async {
        final fakeRepo = _FakeCustomerRepository([customerWithoutDebt]);

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomerListTile(customer: customerWithoutDebt),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              customerRepositoryProvider.overrideWithValue(fakeRepo),
              customerOrdersProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Lê Thị Sạch Nợ'), findsOneWidget);

        // Swipe horizontal
        final dismissible =
            find.byKey(const Key('dismissible_customer_cust_clean'));
        expect(dismissible, findsOneWidget);

        await tester.drag(dismissible, const Offset(-500, 0));
        await tester.pumpAndSettle();

        // Confirmation dialog is shown
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Xoá khách hàng'), findsOneWidget);
        expect(
          find.text('Bạn có chắc chắn muốn xoá khách hàng "Lê Thị Sạch Nợ"?'),
          findsOneWidget,
        );

        // Tap cancel button (TextButton in dialog)
        await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        ));
        await tester.pumpAndSettle();

        // Dialog closed
        expect(find.byType(AlertDialog), findsNothing);

        // Customer is NOT deleted
        expect(fakeRepo.deletedCustomerIds, isEmpty);
        expect(find.text('Lê Thị Sạch Nợ'), findsOneWidget);
      },
    );

    testWidgets(
      'Vuốt khách hàng không có công nợ -> hiển thị dialog xác nhận -> xác nhận xóa thành công',
      (tester) async {
        final fakeRepo = _FakeCustomerRepository([customerWithoutDebt]);

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomerListTile(customer: customerWithoutDebt),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              customerRepositoryProvider.overrideWithValue(fakeRepo),
              customerOrdersProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Lê Thị Sạch Nợ'), findsOneWidget);

        // Swipe horizontal
        final dismissible =
            find.byKey(const Key('dismissible_customer_cust_clean'));
        await tester.drag(dismissible, const Offset(-500, 0));
        await tester.pumpAndSettle();

        // Dialog is shown
        expect(find.byType(AlertDialog), findsOneWidget);

        // Tap delete (Xóa)
        await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
        await tester.pumpAndSettle();

        // Customer is deleted in repository
        expect(fakeRepo.deletedCustomerIds, contains('cust_clean'));

        // Success snackbar is shown
        expect(find.text('Đã xoá khách hàng'), findsOneWidget);

        // Tile is removed
        expect(find.text('Lê Thị Sạch Nợ'), findsNothing);
      },
    );

    testWidgets(
      'Swipe background displays AppColors.danger and delete icon when configured',
      (tester) async {
        final fakeRepo = _FakeCustomerRepository([customerWithoutDebt]);

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomerListTile(customer: customerWithoutDebt),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              customerRepositoryProvider.overrideWithValue(fakeRepo),
              customerOrdersProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final dismissibleWidget =
            tester.widget<Dismissible>(find.byType(Dismissible).first);

        expect(dismissibleWidget.direction, DismissDirection.horizontal);
        expect(dismissibleWidget.background, isNotNull);
        expect(dismissibleWidget.secondaryBackground, isNotNull);

        final bg = dismissibleWidget.background as Container;
        final bgDecoration = bg.decoration as BoxDecoration;
        expect(bgDecoration.color, AppColors.danger);

        final secondaryBg = dismissibleWidget.secondaryBackground as Container;
        final secondaryBgDecoration = secondaryBg.decoration as BoxDecoration;
        expect(secondaryBgDecoration.color, AppColors.danger);
      },
    );

    testWidgets(
      'Full CustomersPage integration: swiping indebted customer is blocked, non-indebted customer deleted successfully',
      (tester) async {
        final initialCustomers = [customerWithDebt, customerWithoutDebt];
        final fakeRepo = _FakeCustomerRepository(initialCustomers);
        final fakeNotifier = _FakeCustomerListNotifier(List.from(initialCustomers));

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomersPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              customerRepositoryProvider.overrideWithValue(fakeRepo),
              customerListNotifierProvider.overrideWith(() => fakeNotifier),
              customerOrdersProvider(customerWithDebt.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerOrdersProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(customerWithDebt.id)
                  .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
              customerDebtTransactionsProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
        expect(find.text('Lê Thị Sạch Nợ'), findsOneWidget);

        // 1. Try swiping indebted customer
        final indebtedFinder =
            find.byKey(const Key('dismissible_customer_cust_indebt'));
        await tester.drag(indebtedFinder, const Offset(-500, 0));
        await tester.pumpAndSettle();

        // Warning shown, indebted customer still there
        expect(
          find.textContaining('Không được phép xóa khách hàng đang nợ'),
          findsOneWidget,
        );
        expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
        expect(fakeRepo.deletedCustomerIds, isEmpty);

        // 2. Swipe clean customer and confirm delete
        final cleanFinder =
            find.byKey(const Key('dismissible_customer_cust_clean'));
        await tester.drag(cleanFinder, const Offset(-500, 0));
        await tester.pumpAndSettle();

        // Confirm in dialog
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
        await tester.pumpAndSettle();

        // Clean customer removed from page
        expect(find.text('Lê Thị Sạch Nợ'), findsNothing);
        // Indebted customer remains
        expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
        expect(fakeRepo.deletedCustomerIds, contains('cust_clean'));
        expect(find.text('Đã xoá khách hàng'), findsOneWidget);
        expect(find.text('Tổng cộng (1 khách hàng)'), findsOneWidget);
        expect(find.text('10.000.000'), findsNWidgets(2));
        expect(find.text('18.000.000'), findsNothing);
      },
    );

    testWidgets(
      'Xóa toàn bộ khách hàng trên trang -> Hiển thị empty view không có khách hàng, không còn header ngày',
      (tester) async {
        final initialCustomers = [customerWithoutDebt];
        final fakeRepo = _FakeCustomerRepository(initialCustomers);
        final fakeNotifier =
            _FakeCustomerListNotifier(List.from(initialCustomers));

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomersPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              customerRepositoryProvider.overrideWithValue(fakeRepo),
              customerListNotifierProvider.overrideWith(() => fakeNotifier),
              customerOrdersProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(customerWithoutDebt.id)
                  .overrideWith(
                      (ref) => Stream.value(<CustomerDebtTransaction>[])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Lê Thị Sạch Nợ'), findsOneWidget);

        // Swipe clean customer and confirm delete
        final cleanFinder =
            find.byKey(const Key('dismissible_customer_cust_clean'));
        await tester.drag(cleanFinder, const Offset(-500, 0));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
        await tester.pumpAndSettle();

        // Customer is gone
        expect(find.text('Lê Thị Sạch Nợ'), findsNothing);
        // Empty state is displayed
        expect(find.text('Chưa có khách hàng nào'), findsOneWidget);
        // Summary card shows 0 customers
        expect(find.text('Tổng cộng (0 khách hàng)'), findsOneWidget);
      },
    );

    testWidgets(
      'Khi repository.delete ném ngoại lệ -> hiển thị SnackBar cảnh báo lỗi thay vì báo thành công',
      (tester) async {
        final fakeRepo = _FakeCustomerRepository([customerWithoutDebt]);
        fakeRepo.shouldThrowOnDelete = true;

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomerListTile(customer: customerWithoutDebt),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              customerRepositoryProvider.overrideWithValue(fakeRepo),
              customerOrdersProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(customerWithoutDebt.id)
                  .overrideWith(
                      (ref) => Stream.value(<CustomerDebtTransaction>[])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final dismissible =
            find.byKey(const Key('dismissible_customer_cust_clean'));
        await tester.drag(dismissible, const Offset(-500, 0));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
        await tester.pumpAndSettle();

        // Error snackbar appears
        expect(
          find.textContaining('Lỗi khi xóa khách hàng:'),
          findsOneWidget,
        );
        // Success snackbar is NOT displayed
        expect(find.text('Đã xoá khách hàng'), findsNothing);
        // Customer tile is restored back into the tree
        expect(find.text('Lê Thị Sạch Nợ'), findsOneWidget);
      },
    );

    testWidgets(
      'Vuốt khách hàng nhẹ dưới ngưỡng (drag offset nhỏ) -> huỷ thao tác, không mở dialog xác nhận',
      (tester) async {
        final fakeRepo = _FakeCustomerRepository([customerWithoutDebt]);

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomerListTile(customer: customerWithoutDebt),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              customerRepositoryProvider.overrideWithValue(fakeRepo),
              customerOrdersProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(customerWithoutDebt.id)
                  .overrideWith(
                      (ref) => Stream.value(<CustomerDebtTransaction>[])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final dismissible =
            find.byKey(const Key('dismissible_customer_cust_clean'));
        // Tiny drag that does not cross dismiss threshold
        await tester.drag(dismissible, const Offset(-30, 0));
        await tester.pumpAndSettle();

        // Dialog does not appear
        expect(find.byType(AlertDialog), findsNothing);
        // Customer tile remains visible
        expect(find.text('Lê Thị Sạch Nợ'), findsOneWidget);
        expect(fakeRepo.deletedCustomerIds, isEmpty);
      },
    );

    testWidgets(
      'Full CustomersPage: Khi remote delete ném ngoại lệ -> khôi phục khách hàng về danh sách, cập nhật lại summary card và báo lỗi',
      (tester) async {
        final initialCustomers = [customerWithoutDebt];
        final fakeRepo = _FakeCustomerRepository(initialCustomers);
        fakeRepo.shouldThrowOnDelete = true;
        final fakeNotifier =
            _FakeCustomerListNotifier(List.from(initialCustomers));

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomersPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              customerRepositoryProvider.overrideWithValue(fakeRepo),
              customerListNotifierProvider.overrideWith(() => fakeNotifier),
              customerOrdersProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(customerWithoutDebt.id)
                  .overrideWith(
                      (ref) => Stream.value(<CustomerDebtTransaction>[])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Lê Thị Sạch Nợ'), findsOneWidget);
        expect(find.text('Tổng cộng (1 khách hàng)'), findsOneWidget);

        // Swipe clean customer and confirm delete
        final cleanFinder =
            find.byKey(const Key('dismissible_customer_cust_clean'));
        await tester.drag(cleanFinder, const Offset(-500, 0));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
        await tester.pumpAndSettle();

        // Remote deletion threw an error -> customer MUST be restored to page!
        expect(find.text('Lê Thị Sạch Nợ'), findsOneWidget);
        expect(find.text('Tổng cộng (1 khách hàng)'), findsOneWidget);
        // Error snackbar is shown
        expect(find.textContaining('Lỗi khi xóa khách hàng:'), findsOneWidget);
        expect(fakeRepo.deletedCustomerIds, isEmpty);
      },
    );

    testWidgets(
      'Full CustomersPage: Remote delete có độ trễ bất đồng bộ (async delay) -> SnackBar thành công vẫn hiển thị đầy đủ dù tile đã unmount',
      (tester) async {
        final initialCustomers = [customerWithoutDebt];
        final fakeRepo = _FakeCustomerRepository(initialCustomers);
        fakeRepo.deleteDelayMs = 50; // Simulate network roundtrip
        final fakeNotifier =
            _FakeCustomerListNotifier(List.from(initialCustomers));

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomersPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              customerRepositoryProvider.overrideWithValue(fakeRepo),
              customerListNotifierProvider.overrideWith(() => fakeNotifier),
              customerOrdersProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(customerWithoutDebt.id)
                  .overrideWith(
                      (ref) => Stream.value(<CustomerDebtTransaction>[])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Lê Thị Sạch Nợ'), findsOneWidget);

        // Swipe clean customer and confirm delete
        final cleanFinder =
            find.byKey(const Key('dismissible_customer_cust_clean'));
        await tester.drag(cleanFinder, const Offset(-500, 0));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
        await tester.pumpAndSettle();
        // Advance the 50ms async network delay
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Customer is deleted in repository
        expect(fakeRepo.deletedCustomerIds, contains('cust_clean'));
        // Success snackbar is visibly shown even with async delay
        expect(find.text('Đã xoá khách hàng'), findsOneWidget);
      },
    );

    testWidgets(
      'Full CustomersPage: Vuốt xóa xong thực hiện tìm kiếm rồi xóa tìm kiếm -> Khách hàng đã xóa không bị hiện lại bất thường trước khi backend phản hồi',
      (tester) async {
        const customerC = Customer(
          id: 'cust_c',
          name: 'Phạm Văn C',
          phone: '0903334455',
          email: 'c@example.com',
          address: 'HCM',
          purchases: [],
          currentDebt: 0.0,
          totalSales: 5000000.0,
        );
        final initialCustomers = [customerWithoutDebt, customerC];
        final fakeRepo = _FakeCustomerRepository(initialCustomers);
        fakeRepo.deleteDelayMs = 1000; // In-flight network
        final fakeNotifier =
            _FakeCustomerListNotifier(List.from(initialCustomers));

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomersPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              customerRepositoryProvider.overrideWithValue(fakeRepo),
              customerListNotifierProvider.overrideWith(() => fakeNotifier),
              customerOrdersProvider(customerWithoutDebt.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerOrdersProvider(customerC.id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(customerWithoutDebt.id)
                  .overrideWith(
                      (ref) => Stream.value(<CustomerDebtTransaction>[])),
              customerDebtTransactionsProvider(customerC.id)
                  .overrideWith(
                      (ref) => Stream.value(<CustomerDebtTransaction>[])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Lê Thị Sạch Nợ'), findsOneWidget);
        expect(find.text('Phạm Văn C'), findsOneWidget);

        // 1. Swipe delete Lê Thị Sạch Nợ
        final cleanFinder =
            find.byKey(const Key('dismissible_customer_cust_clean'));
        await tester.drag(cleanFinder, const Offset(-500, 0));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
        await tester.pumpAndSettle();

        // Lê Thị Sạch Nợ is gone locally
        expect(find.text('Lê Thị Sạch Nợ'), findsNothing);

        // 2. Type "Phạm" in search box
        await tester.enterText(find.byType(TextField), 'Phạm');
        await tester.pump();

        expect(find.text('Phạm Văn C'), findsOneWidget);
        expect(find.text('Lê Thị Sạch Nợ'), findsNothing);

        // 3. Clear search query
        await tester.enterText(find.byType(TextField), '');
        await tester.pump();

        // Lê Thị Sạch Nợ must STILL be hidden (not resurrect prematurely)
        expect(find.text('Lê Thị Sạch Nợ'), findsNothing);
        expect(find.text('Phạm Văn C'), findsOneWidget);

        // Settle the delayed network delete
        await tester.pump(const Duration(milliseconds: 1000));
        await tester.pumpAndSettle();
        expect(fakeRepo.deletedCustomerIds, contains('cust_clean'));
      },
    );
  });
}
