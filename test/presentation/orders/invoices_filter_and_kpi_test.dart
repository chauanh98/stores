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

class _FakeCustomerListNotifier extends AutoDisposeAsyncNotifier<List<Customer>>
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
  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const staffUser1 = UserAccount(
    username: 'staff_01',
    displayName: 'Nguyễn Văn A',
    role: 'nhanvien',
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

  const customer2 = Customer(
    id: 'cust_002',
    name: 'Khách hàng VIP 2',
    phone: '0902222222',
    email: '',
    address: '',
    purchases: [],
  );

  final sampleOrders = [
    // Order 1: Completed, Cash, Paid in full, Staff 1, 1.000.000đ
    Order(
      id: 'HD000001',
      customerId: 'cust_001',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      items: [
        OrderItem(
          productId: 'prod_001',
          productName: 'Ốp lưng iPhone 15',
          quantity: 2,
          price: 500000.0,
          warrantyMonths: 0,
          purchaseDate: DateTime.now(),
        ),
      ],
      total: 1000000.0,
      amountPaid: 1000000.0,
      debtAmount: 0.0,
      status: 'completed',
      paymentMethod: 'cash',
      createdBy: 'staff_01',
      createdByName: 'Nguyễn Văn A',
    ),
    // Order 2: Completed, Transfer, Remaining debt 500.000đ, Staff 2, 2.000.000đ
    Order(
      id: 'HD000002',
      customerId: 'cust_002',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      items: [
        OrderItem(
          productId: 'prod_002',
          productName: 'Củ sạc 65W GaN',
          quantity: 2,
          price: 1000000.0,
          warrantyMonths: 12,
          purchaseDate: DateTime.now(),
        ),
      ],
      total: 2000000.0,
      amountPaid: 1500000.0,
      debtAmount: 500000.0,
      status: 'completed',
      paymentMethod: 'transfer',
      createdBy: 'admin',
      createdByName: 'Quản trị viên',
    ),
    // Order 3: Draft order, 300.000đ
    Order(
      id: 'HD000003',
      customerId: 'cust_001',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      items: [
        OrderItem(
          productId: 'prod_003',
          productName: 'Cáp sạc Type-C',
          quantity: 1,
          price: 300000.0,
          warrantyMonths: 6,
          purchaseDate: DateTime.now(),
        ),
      ],
      total: 300000.0,
      amountPaid: 0.0,
      debtAmount: 0.0,
      status: 'draft',
      paymentMethod: 'cash',
      createdBy: 'staff_01',
      createdByName: 'Nguyễn Văn A',
    ),
    // Order 4: Cancelled order, 5.000.000đ (Should not be counted in active revenue)
    Order(
      id: 'HD000004',
      customerId: 'cust_002',
      createdAt: DateTime.now().subtract(const Duration(hours: 4)),
      items: [
        OrderItem(
          productId: 'prod_004',
          productName: 'Màn hình 4K',
          quantity: 1,
          price: 5000000.0,
          warrantyMonths: 24,
          purchaseDate: DateTime.now(),
        ),
      ],
      total: 5000000.0,
      amountPaid: 0.0,
      debtAmount: 0.0,
      status: 'cancelled',
      cancelReason: 'Khách hàng đổi ý',
      cancelledBy: 'admin',
      cancelledByName: 'Quản trị viên',
      cancelledAt: DateTime.now(),
      paymentMethod: 'transfer',
      createdBy: 'admin',
    ),
    // Order 5: Returned order, 800.000đ (2 items @ 400.000đ, fully returned)
    Order(
      id: 'HD000005',
      customerId: 'cust_001',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      items: [
        OrderItem(
          productId: 'prod_005',
          productName: 'Tai nghe Bluetooth Pro',
          quantity: 2,
          price: 400000.0,
          warrantyMonths: 12,
          purchaseDate: DateTime.now(),
          returnedQuantity: 2,
        ),
      ],
      total: 0.0,
      amountPaid: 0.0,
      debtAmount: 0.0,
      status: 'returned',
      paymentMethod: 'cash',
      createdBy: 'staff_01',
      createdByName: 'Nguyễn Văn A',
    ),
  ];

  group('InvoicesPage Multi-dimensional Filtering & Reactive KPI Tests', () {
    testWidgets(
        'Default status is completed and orange summary card is hidden (R2 & R3)',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider
                .overrideWith((ref) => Stream.value([adminUser, staffUser1])),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(sampleOrders)),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier([customer1, customer2])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Orange KPI summary card is completely hidden (R3)
      expect(
          find.byKey(const Key('invoices_total_summary_card')), findsNothing);
      expect(find.text('Doanh thu gộp:'), findsNothing);

      // Default status is "Đã hoàn thành" (R2): displays completed orders only
      expect(find.text('Mã đơn: HD000001'), findsOneWidget);
      expect(find.text('Mã đơn: HD000002'), findsOneWidget);
      expect(find.text('Mã đơn: HD000003'), findsNothing);
      expect(find.text('Mã đơn: HD000004'), findsNothing);
      expect(find.text('Mã đơn: HD000005'), findsNothing);

      // Tapping 'Tất cả trạng thái' shows all orders
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tất cả trạng thái'));
      await tester.pumpAndSettle();
      expect(find.text('Mã đơn: HD000001'), findsOneWidget);
      expect(find.text('Mã đơn: HD000002'), findsOneWidget);
      expect(find.text('Mã đơn: HD000003'), findsOneWidget);
      expect(find.text('Mã đơn: HD000004'), findsOneWidget);
      expect(find.text('Mã đơn: HD000005'), findsOneWidget);
    });

    testWidgets(
        'Filters orders by Status (Đã hoàn thành, Đơn trả hàng, Lưu tạm, Đã hủy)',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider
                .overrideWith((ref) => Stream.value([adminUser, staffUser1])),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(sampleOrders)),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier([customer1, customer2])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Filter by 'Đã hoàn thành' ChoiceChip
      await tester.tap(find.widgetWithText(ChoiceChip, 'Đã hoàn thành'));
      await tester.pumpAndSettle();

      expect(find.text('Mã đơn: HD000001'), findsOneWidget);
      expect(find.text('Mã đơn: HD000002'), findsOneWidget);
      expect(find.text('Mã đơn: HD000003'), findsNothing);
      expect(find.text('Mã đơn: HD000004'), findsNothing);
      expect(find.text('Mã đơn: HD000005'), findsNothing);

      // Filter by 'Đơn trả hàng' ChoiceChip
      await tester.tap(find.widgetWithText(ChoiceChip, 'Đơn trả hàng'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('return_kpi_summary_card')), findsOneWidget);
      expect(find.text('Số đơn trả: 1'), findsOneWidget);
      expect(find.text('Tổng hoàn trả: 800.000 đ'), findsOneWidget);
      expect(find.text('Tiền hoàn lại: 800.000 đ'), findsOneWidget);
      expect(find.text('Cấn trừ nợ: 0 đ'), findsOneWidget);

      expect(find.text('Mã đơn: HD000005'), findsOneWidget);
      expect(find.text('Đã trả hàng'), findsWidgets);
      expect(find.text('Mã đơn: HD000001'), findsNothing);

      // Filter by 'Lưu tạm' ChoiceChip
      await tester.tap(find.widgetWithText(ChoiceChip, 'Lưu tạm'));
      await tester.pumpAndSettle();

      expect(find.text('Mã đơn: HD000003'), findsOneWidget);
      expect(find.text('Mã đơn: HD000001'), findsNothing);

      // Filter by 'Đã hủy' ChoiceChip
      await tester.tap(find.widgetWithText(ChoiceChip, 'Đã hủy'));
      await tester.pumpAndSettle();

      expect(find.text('Mã đơn: HD000004'), findsOneWidget);

      // Verify reset button appears when filters are active
      final resetBtn = find.byKey(const Key('invoices_reset_filter_button'));
      expect(resetBtn, findsOneWidget);

      // Tap reset button -> restores default status to "Đã hoàn thành" (R2)
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      expect(find.text('Mã đơn: HD000001'), findsOneWidget);
      expect(find.text('Mã đơn: HD000002'), findsOneWidget);
      expect(find.text('Mã đơn: HD000004'), findsNothing);
      expect(
          find.byKey(const Key('invoices_reset_filter_button')), findsNothing);
    });

    testWidgets('Tapping returned order opens ReturnOrderDetailBottomSheet',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider
                .overrideWith((ref) => Stream.value([adminUser, staffUser1])),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(sampleOrders)),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier([customer1, customer2])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Filter by 'Đơn trả hàng'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Đơn trả hàng'));
      await tester.pumpAndSettle();

      // Tap on the returned order tile
      await tester.tap(find.text('Mã đơn: HD000005'));
      await tester.pumpAndSettle();

      // Verify ReturnOrderDetailBottomSheet is opened
      expect(
          find.textContaining('Phiếu trả hàng: TH_HD000005'), findsOneWidget);
      expect(find.text('Đã hoàn tiền'), findsOneWidget);
      expect(find.text('Hóa đơn gốc: #HD000005'), findsOneWidget);
      expect(find.text('Tai nghe Bluetooth Pro'), findsOneWidget);
      expect(find.byKey(const Key('view_original_invoice_button')),
          findsOneWidget);
      expect(find.byKey(const Key('view_original_invoice_bottom_button')),
          findsOneWidget);
    });

    testWidgets(
        'Search query filters across invoice ID, customer name and phone',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider
                .overrideWith((ref) => Stream.value([adminUser, staffUser1])),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(sampleOrders)),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier([customer1, customer2])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Type search query
      await tester.enterText(find.byType(TextField).first, 'HD000002');
      await tester.pumpAndSettle();

      expect(find.text('Mã đơn: HD000002'), findsOneWidget);
      expect(find.text('Mã đơn: HD000001'), findsNothing);

      // Search across all statuses
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tất cả trạng thái'));
      await tester.pumpAndSettle();

      // Search by customer name
      await tester.enterText(find.byType(TextField).first, 'VIP 1');
      await tester.pumpAndSettle();

      expect(find.text('Mã đơn: HD000001'), findsOneWidget);
      expect(find.text('Mã đơn: HD000003'), findsOneWidget);
      expect(find.text('Mã đơn: HD000005'), findsOneWidget);
    });
  });
}
