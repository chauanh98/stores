import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/common/widgets/date_grouped_list_view.dart';
import 'package:stores/presentation/customers/pages/customer_transactions_page.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/settings/pages/more_page.dart';

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

class _EmptyCustomerListNotifier extends CustomerListNotifier {
  @override
  Future<List<Customer>> build() async => [];
}

class _EmptySupplierListNotifier extends SupplierListNotifier {
  @override
  Future<List<Supplier>> build() async => [];
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
  double textScaleFactor = 1.0,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      builder: (context, widget) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScaleFactor),
          ),
          child: widget!,
        );
      },
      home: Material(child: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final currencyFormat = NumberFormat('#,###', 'vi_VN');

  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const testCustomer = Customer(
    id: 'cust_001',
    name: 'Khách hàng A',
    phone: '0901234567',
    email: '',
    address: 'Cần Thơ',
    purchases: [],
  );

  final testDate = DateTime(2026, 9, 27, 10, 00);

  // Order 1: total = 1,000,000; discount = 200,000 -> netPayable = 800,000
  final orderWithDiscount1 = Order(
    id: 'HD001',
    customerId: 'cust_001',
    customerName: 'Khách hàng A',
    createdAt: testDate,
    items: [
      OrderItem(
        productId: 'P1',
        productName: 'Bàn học thông minh',
        quantity: 1,
        price: 1000000.0,
        warrantyMonths: 12,
        purchaseDate: testDate,
      ),
    ],
    total: 1000000.0,
    discount: 200000.0,
    amountPaid: 800000.0,
    debtAmount: 0.0,
    status: 'completed',
    paymentMethod: 'cash',
    storeId: 'store_001',
    createdByName: 'Nhân viên 1',
  );

  // Order 2: total = 500,000; discount = 50,000 -> netPayable = 450,000
  final orderWithDiscount2 = Order(
    id: 'HD002',
    customerId: 'cust_001',
    customerName: 'Khách hàng A',
    createdAt: testDate.subtract(const Duration(minutes: 30)),
    items: [
      OrderItem(
        productId: 'P2',
        productName: 'Ghế xoay',
        quantity: 2,
        price: 250000.0,
        warrantyMonths: 6,
        purchaseDate: testDate,
      ),
    ],
    total: 500000.0,
    discount: 50000.0,
    amountPaid: 450000.0,
    debtAmount: 0.0,
    status: 'completed',
    paymentMethod: 'transfer',
    storeId: 'store_001',
    createdByName: 'Nhân viên 2',
  );

  // Order 3: Cancelled order total = 2,000,000 (should NOT be counted in gross total)
  final cancelledOrder = Order(
    id: 'HD003',
    customerId: 'cust_001',
    customerName: 'Khách hàng A',
    createdAt: testDate.subtract(const Duration(hours: 1)),
    items: [
      OrderItem(
        productId: 'P3',
        productName: 'Tủ quần áo',
        quantity: 1,
        price: 2000000.0,
        warrantyMonths: 12,
        purchaseDate: testDate,
      ),
    ],
    total: 2000000.0,
    discount: 0.0,
    amountPaid: 0.0,
    debtAmount: 0.0,
    status: 'cancelled',
    paymentMethod: 'cash',
    storeId: 'store_001',
    createdByName: 'Nhân viên 1',
  );

  group('R1: InvoicesPage - Tổng Tiền Hàng Trước Khi Giảm Giá', () {
    testWidgets(
        'Displays "Tổng tiền hàng" label and calculates order.total sum before discount',
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
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value([orderWithDiscount1, orderWithDiscount2, cancelledOrder])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([testCustomer])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Show all status
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tất cả trạng thái'));
      await tester.pumpAndSettle();

      // 1. Verify summary header bar appears with "Tổng tiền hàng"
      expect(find.byKey(const Key('invoices_items_summary_bar')), findsOneWidget);
      expect(find.text('Tổng tiền hàng'), findsOneWidget);
      expect(find.text('Doanh thu'), findsNothing);

      // Total gross: 1,000,000 (HD001) + 500,000 (HD002) = 1,500,000 đ
      // (Cancelled order 2,000,000 is excluded; netPayable 800k+450k=1.250.000 is NOT used)
      expect(find.text('${currencyFormat.format(1500000.0)} đ'), findsWidgets);

      // sp count and invoice count intact: 3 invoices, 3 products (1 + 2)
      expect(find.text('3 đơn'), findsOneWidget);
      expect(find.text('3 sp'), findsOneWidget);

      // 2. DateGroupHeader reflects total gross (1.500.000 đ)
      final dateHeader = find.byType(DateGroupHeader);
      expect(dateHeader, findsOneWidget);
      final dateHeaderWidget = tester.widget<DateGroupHeader>(dateHeader);
      expect(dateHeaderWidget.totalAmount, 1500000.0);
    });

    testWidgets('InvoicesPage on narrow viewport (320x640) with all cancelled orders',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value([cancelledOrder])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([testCustomer])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Show all status so cancelled order is visible
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tất cả trạng thái'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('invoices_items_summary_bar')), findsOneWidget);
      expect(find.text('Tổng tiền hàng'), findsOneWidget);
      // Cancelled order gross should be 0 đ
      expect(find.text('${currencyFormat.format(0.0)} đ'), findsWidgets);
      expect(find.text('1 đơn'), findsOneWidget);
      expect(find.text('0 sp'), findsOneWidget);
    });

    testWidgets(
        'InvoicesPage on 280x560 with TextScaler 1.5 and multi-billion discount/debt',
        (tester) async {
      tester.view.physicalSize = const Size(280, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final hugeDiscountOrder = Order(
        id: 'HD-LONG-CAN-THO-001',
        customerId: 'cust_001',
        customerName: 'Khách hàng VIP Doanh Nghiệp Lớn',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P1',
            productName: 'Hệ thống năng lượng mặt trời công nghiệp',
            quantity: 1,
            price: 50000000000.0,
            warrantyMonths: 60,
            purchaseDate: testDate,
          ),
        ],
        total: 50000000000.0,
        discount: 25000000000.0,
        amountPaid: 15000000000.0,
        debtAmount: 10000000000.0,
        status: 'completed',
        paymentMethod: 'transfer',
        storeId: 'store_001',
        createdByName: 'Kế toán trưởng',
      );

      await tester.pumpWidget(
        _buildTestApp(
          textScaleFactor: 1.5,
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value([hugeDiscountOrder])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([testCustomer])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('invoices_items_summary_bar')), findsOneWidget);
      expect(find.text('Tổng tiền hàng'), findsOneWidget);
      expect(find.textContaining('50.000.000.000'), findsWidgets);
      expect(find.textContaining('25.000.000.000'), findsWidgets);
      expect(find.textContaining('10.000.000.000'), findsWidgets);
    });
  });

  group('R2: CustomerTransactionsPage - Hiển Thị Số Tiền Trước Giảm Giá', () {
    testWidgets(
        'Header totalSum, DateGroupHeader and Card display order.total and discount badge',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([orderWithDiscount1, orderWithDiscount2, cancelledOrder]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // 1. Header summary reflects gross total (1,000,000 + 500,000 = 1,500,000 đ)
      expect(find.text(currencyFormat.format(1500000.0)), findsOneWidget);

      // 2. DateGroupHeader in DateGroupedListView reflects gross total (1,500,000 đ)
      final dateHeader = find.byType(DateGroupHeader);
      expect(dateHeader, findsOneWidget);
      final dateHeaderWidget = tester.widget<DateGroupHeader>(dateHeader);
      expect(dateHeaderWidget.totalAmount, 1500000.0);

      // 3. Order cards display gross total before discount
      expect(find.text(currencyFormat.format(1000000.0)), findsOneWidget);
      expect(find.text(currencyFormat.format(500000.0)), findsOneWidget);

      // 4. Discount badges are displayed
      expect(find.text('Giảm: -${currencyFormat.format(200000.0)} đ'), findsOneWidget);
      expect(find.text('Giảm: -${currencyFormat.format(50000.0)} đ'), findsOneWidget);
    });

    testWidgets(
        'Narrow viewport (320x640) renders extreme order IDs, multi-billion discounts, cancelled badge, and store badge without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final extremeOrder = Order(
        id: 'HD9999999999999',
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        createdAt: DateTime(2026, 9, 27, 14, 0),
        items: [
          OrderItem(
            productId: 'P_EXTREME',
            productName: 'Sản phẩm nội thất thông minh cỡ lớn',
            quantity: 10,
            price: 1000000000.0,
            warrantyMonths: 24,
            purchaseDate: DateTime(2026, 9, 27),
          ),
        ],
        total: 10000000000.0,
        discount: 2500000000.0,
        amountPaid: 7500000000.0,
        debtAmount: 0.0,
        status: 'cancelled',
        paymentMethod: 'transfer',
        storeId: 'store_001',
        createdByName: 'Nhân viên quản trị hệ thống siêu dài',
      );

      final zeroItemOrder = Order(
        id: 'HD_DRAFT_ZERO',
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        createdAt: DateTime(2026, 9, 27, 9, 0),
        items: const [],
        total: 0.0,
        discount: 0.0,
        amountPaid: 0.0,
        debtAmount: 0.0,
        status: 'draft',
        paymentMethod: 'cash',
        storeId: 'store_001',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([extremeOrder, zeroItemOrder]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Đã hủy'), findsOneWidget);
      expect(find.text('Giảm: -${currencyFormat.format(2500000000.0)} đ'), findsOneWidget);
      expect(find.text('HD_DRAFT_ZERO'), findsOneWidget);
    });

    testWidgets(
        'CustomerTransactionsPage on 280x560 with TextScaler 1.5, combined cancelled + discount + store badges + long ID',
        (tester) async {
      tester.view.physicalSize = const Size(280, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final extremeCombinedOrder = Order(
        id: 'HD-LONG-ORDER-ID-999999999999999999999999',
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P1',
            productName: 'Sản phẩm kích thước siêu dài',
            quantity: 5,
            price: 1000000000.0,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 5000000000.0,
        discount: 1500000000.0,
        amountPaid: 3500000000.0,
        debtAmount: 0.0,
        status: 'cancelled',
        paymentMethod: 'transfer',
        storeId: 'store_001',
        createdByName: 'Nhân viên',
      );

      await tester.pumpWidget(
        _buildTestApp(
          textScaleFactor: 1.5,
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([extremeCombinedOrder]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Đã hủy'), findsOneWidget);
      expect(find.text('Giảm: -${currencyFormat.format(1500000000.0)} đ'), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
    });
  });

  group('R3: MorePage - Loại Bỏ Dòng Chữ Chi Nhánh Thừa', () {
    testWidgets(
        'Displays "CHUYỂN ĐỔI CỬA HÀNG" without "Chi nhánh đang làm việc:" subtitle',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const MorePage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(<Order>[])),
            customerListNotifierProvider
                .overrideWith(() => _EmptyCustomerListNotifier()),
            supplierListNotifierProvider
                .overrideWith(() => _EmptySupplierListNotifier()),
            productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
            allStoresProductsProvider.overrideWith((ref) => Stream.value(<Product>[])),
            accountsListProvider
                .overrideWith((ref) => Stream.value(<UserAccount>[adminUser])),
            rawImportTransactionsStreamProvider
                .overrideWith((ref) => Stream.value(<InventoryTransaction>[])),
            allSupplierDebtTransactionsProvider
                .overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Title remains visible
      expect(find.text('CHUYỂN ĐỔI CỬA HÀNG'), findsOneWidget);

      // Subtitle is completely removed
      expect(find.textContaining('Chi nhánh đang làm việc:'), findsNothing);

      // Dropdown exists and contains store options
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });
  });
}
