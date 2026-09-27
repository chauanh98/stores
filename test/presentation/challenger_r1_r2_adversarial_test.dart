import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/widgets/return_order_detail_bottom_sheet.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

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
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const supervisorUser = UserAccount(
    username: 'supervisor_01',
    displayName: 'Quản lý Chuỗi',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên A',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  final complexProducts = [
    // 1. In stock, Category: Nội thất, Brand: IKEA, Price: 2.500.000, Stock: 50, Min: 10
    const Product(
      id: 'prod_k_desk',
      name: 'Bàn chữ K gaming Pro chân sắt',
      code: 'DESK-K-01',
      barcode: '893001',
      brand: 'IKEA',
      price: 2500000,
      costPrice: 1800000,
      branchStocks: {'branch_1': 30, 'branch_2': 20},
      category: 'Nội thất',
      minStock: 10,
    ),
    // 2. Low stock, Category: Nội thất, Brand: IKEA, Price: 1.200.000, Stock: 4, Min: 5
    const Product(
      id: 'prod_chair',
      name: 'Ghế xoay văn phòng công thái học',
      code: 'CHAIR-01',
      barcode: '893002',
      brand: 'IKEA',
      price: 1200000,
      costPrice: 800000,
      branchStocks: {'branch_1': 3, 'branch_2': 1},
      category: 'Nội thất',
      minStock: 5,
    ),
    // 3. Out of stock, Category: Phụ kiện, Brand: Logitech, Price: 350.000, Stock: 0, Min: 10
    const Product(
      id: 'prod_mousepad',
      name: 'Lót chuột cỡ lớn RGB',
      code: 'PAD-RGB-01',
      barcode: '893003',
      brand: 'Logitech',
      price: 350000,
      costPrice: 200000,
      branchStocks: {'branch_1': 0, 'branch_2': 0},
      category: 'Phụ kiện',
      minStock: 10,
    ),
    // 4. In stock, Category: Phụ kiện, Brand: Logitech, Price: 2.100.000, Stock: 15, Min: 5
    const Product(
      id: 'prod_mouse_mx',
      name: 'Chuột không dây Logitech MX Master 3S',
      code: 'MOUSE-MX-01',
      barcode: '893004',
      brand: 'Logitech',
      price: 2100000,
      costPrice: 1600000,
      branchStocks: {'branch_1': 10, 'branch_2': 5},
      category: 'Phụ kiện',
      minStock: 5,
    ),
    // 5. In stock, Category: Đồ uống, Brand: Sabeco, Price: 15.000, Stock: 100, Min: 20
    const Product(
      id: 'prod_beer',
      name: 'Bia Saigon Special 330ml',
      code: 'BEER-01',
      barcode: '893005',
      brand: 'Sabeco',
      price: 15000,
      costPrice: 11000,
      branchStocks: {'branch_1': 60, 'branch_2': 40},
      category: 'Đồ uống',
      minStock: 20,
    ),
  ];

  group('Challenger R1: Products Filter Bar Stress & Layout Tests', () {
    testWidgets('R1.1: Small screen viewport (320px width) horizontal scroll and dropdown rendering',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Verify horizontal SingleChildScrollView exists
      final horizontalScrollFinder = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      expect(horizontalScrollFinder, findsOneWidget);

      // Verify Stock Status dropdown is visible on 320px
      expect(find.byType(DropdownButton<StockStatus>), findsOneWidget);

      // Drag horizontally to inspect other dropdowns
      await tester.drag(horizontalScrollFinder, const Offset(-200, 0));
      await tester.pumpAndSettle();

      // Sắp xếp dropdown should be visible after scrolling
      expect(find.byType(DropdownButton<ProductSortOption>), findsOneWidget);
    });

    testWidgets('R1.2: Ultra-narrow screen viewport (280px width) resilience',
        (tester) async {
      tester.view.physicalSize = const Size(280, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('R1.3: Multi-filter permutations (Stock + Category + Brand + Sort) and 1-tap Reset',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value(complexProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Initial: All 5 products rendered, Reset button is hidden
      expect(find.byType(ProductTile), findsNWidgets(5));
      expect(find.byIcon(Icons.refresh), findsNothing);

      // Step 1: Filter Category = 'Nội thất' (matches K-Desk & Chair)
      final catDropdown = find.byType(DropdownButton<String>);
      await tester.ensureVisible(catDropdown);
      await tester.tap(catDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nội thất').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsNWidgets(2));
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // Step 2: Filter Brand = 'IKEA'
      final brandDropdown = find.byType(DropdownButton<String?>);
      await tester.ensureVisible(brandDropdown);
      await tester.tap(brandDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('IKEA').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsNWidgets(2));

      // Step 3: Filter Stock = 'Dưới định mức' (only Chair is stock 4 <= minStock 5)
      final stockDropdown = find.byType(DropdownButton<StockStatus>);
      await tester.ensureVisible(stockDropdown);
      await tester.tap(stockDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dưới định mức').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);
      expect(find.text('Ghế xoay văn phòng công thái học'), findsOneWidget);
      expect(find.text('Bàn chữ K gaming Pro chân sắt'), findsNothing);

      // Step 4: Change Sort = 'Giá: Cao → Thấp'
      final sortDropdown = find.byType(DropdownButton<ProductSortOption>);
      await tester.ensureVisible(sortDropdown);
      await tester.tap(sortDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Giá: Cao → Thấp').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProductTile), findsOneWidget);

      // Step 5: Tap 1-tap Reset Button
      final resetBtn = find.byIcon(Icons.refresh);
      expect(resetBtn, findsOneWidget);
      await tester.ensureVisible(resetBtn);
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      // Verify all 5 products restored, all dropdowns back to default, reset button hidden
      expect(find.byType(ProductTile), findsNWidgets(5));
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Tất cả nhóm hàng'), findsOneWidget);
      expect(find.text('Tất cả thương hiệu'), findsOneWidget);
      expect(find.text('Tồn kho: Cao → Thấp'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
    });

    testWidgets('R1.4: Sorting permutations across all 6 sort options',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value(complexProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final sortDropdown = find.byType(DropdownButton<ProductSortOption>);
      await tester.ensureVisible(sortDropdown);

      // 1. Price Ascending (Thấp → Cao)
      await tester.tap(sortDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Giá: Thấp → Cao').last);
      await tester.pumpAndSettle();

      var tiles = tester.widgetList<ProductTile>(find.byType(ProductTile)).toList();
      expect(tiles.first.product.name, 'Bia Saigon Special 330ml'); // 15.000 đ
      expect(tiles.last.product.name, 'Bàn chữ K gaming Pro chân sắt'); // 2.500.000 đ

      // 2. Name Ascending (A → Z) - in Dart string compare, 'Bia' (105) < 'Bàn' (224)
      await tester.tap(sortDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tên: A → Z').last);
      await tester.pumpAndSettle();

      tiles = tester.widgetList<ProductTile>(find.byType(ProductTile)).toList();
      expect(tiles.first.product.name, 'Bia Saigon Special 330ml');
      expect(tiles.last.product.name, 'Lót chuột cỡ lớn RGB');

      // 3. Name Descending (Z → A)
      await tester.tap(sortDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tên: Z → A').last);
      await tester.pumpAndSettle();

      tiles = tester.widgetList<ProductTile>(find.byType(ProductTile)).toList();
      expect(tiles.first.product.name, 'Lót chuột cỡ lớn RGB');
      expect(tiles.last.product.name, 'Bia Saigon Special 330ml');
    });
  });

  group('Challenger R2: Return Orders Management & KPI Isolation Stress', () {
    final testDate = DateTime(2026, 8, 23, 10, 0);

    const customerA = Customer(
      id: 'cust_a',
      name: 'Công ty Alpha',
      phone: '0901234567',
      email: 'alpha@example.com',
      address: 'Hà Nội',
      purchases: [],
    );

    const customerB = Customer(
      id: 'cust_b',
      name: 'Công ty Beta',
      phone: '0907654321',
      email: 'beta@example.com',
      address: 'TP.HCM',
      purchases: [],
    );

    final adversarialOrders = [
      // 1. Order 1: Full return with status == 'returned', total: 0, items returned
      Order(
        id: 'HD_RET_01',
        customerId: 'cust_a',
        createdAt: testDate.subtract(const Duration(minutes: 10)),
        items: [
          OrderItem(
            productId: 'P_DESK',
            productName: 'Bàn làm việc chữ Z 1m2',
            quantity: 2,
            price: 1500000.0,
            warrantyMonths: 12,
            purchaseDate: testDate,
            returnedQuantity: 2,
          ),
        ],
        total: 0.0,
        amountPaid: 0.0,
        debtAmount: 0.0,
        status: 'returned',
        paymentMethod: 'cash',
        createdBy: 'staff_01',
        createdByName: 'Nhân viên A',
        cancelReason: 'Hàng lỗi cong vênh',
      ),
      // 2. Order 2: Partial return, status == 'completed', original total 5.000.000, 1 item returned (1.000.000), remaining debt 500.000
      Order(
        id: 'HD_PART_02',
        customerId: 'cust_b',
        createdAt: testDate.subtract(const Duration(minutes: 20)),
        items: [
          OrderItem(
            productId: 'P_CHAIR_1',
            productName: 'Ghế xoay văn phòng',
            quantity: 3,
            price: 1000000.0,
            warrantyMonths: 12,
            purchaseDate: testDate,
            returnedQuantity: 1, // 1 * 1.000.000 = 1.000.000 đ returned
          ),
          OrderItem(
            productId: 'P_CABINET',
            productName: 'Tủ tài liệu 3 ngăn',
            quantity: 1,
            price: 2000000.0,
            warrantyMonths: 24,
            purchaseDate: testDate,
            returnedQuantity: 0,
          ),
        ],
        total: 4000000.0, // After return
        amountPaid: 3500000.0,
        debtAmount: 500000.0, // Remaining debt = 500.000
        status: 'completed',
        paymentMethod: 'transfer',
        createdBy: 'admin_01',
        createdByName: 'Quản trị viên',
      ),
      // 3. Order 3: Standard completed order (No returns at all)
      Order(
        id: 'HD_COMP_03',
        customerId: 'cust_a',
        createdAt: testDate.subtract(const Duration(minutes: 30)),
        items: [
          OrderItem(
            productId: 'P_BEER',
            productName: 'Bia Saigon Special',
            quantity: 10,
            price: 15000.0,
            warrantyMonths: 0,
            purchaseDate: testDate,
            returnedQuantity: 0,
          ),
        ],
        total: 150000.0,
        amountPaid: 150000.0,
        debtAmount: 0.0,
        status: 'completed',
        paymentMethod: 'cash',
        createdBy: 'staff_01',
      ),
      // 4. Order 4: Cancelled order (No returns)
      Order(
        id: 'HD_CANC_04',
        customerId: 'khach_le',
        createdAt: testDate.subtract(const Duration(minutes: 40)),
        items: [
          OrderItem(
            productId: 'P_MOUSE',
            productName: 'Chuột Logitech',
            quantity: 1,
            price: 2000000.0,
            warrantyMonths: 12,
            purchaseDate: testDate,
          ),
        ],
        total: 2000000.0,
        amountPaid: 0.0,
        debtAmount: 0.0,
        status: 'cancelled',
        cancelReason: 'Khách đổi ý',
        paymentMethod: 'cash',
        createdBy: 'admin_01',
      ),
      // 5. Order 5: Draft order (No returns)
      Order(
        id: 'HD_DRAFT_05',
        customerId: 'khach_le',
        createdAt: testDate.subtract(const Duration(minutes: 50)),
        items: [
          OrderItem(
            productId: 'P_PAD',
            productName: 'Lót chuột',
            quantity: 2,
            price: 100000.0,
            warrantyMonths: 0,
            purchaseDate: testDate,
          ),
        ],
        total: 200000.0,
        amountPaid: 0.0,
        debtAmount: 0.0,
        status: 'draft',
        paymentMethod: 'cash',
        createdBy: 'staff_01',
      ),
    ];

    testWidgets('R2.1: Return status filter isolation matches both full and partial returns while excluding standard orders',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider.overrideWith((ref) => Stream.value([adminUser, staffUser])),
            allBranchesOrdersByDateRangeProvider.overrideWith((ref, range) => Stream.value(adversarialOrders)),
            customerListNotifierProvider.overrideWith(() => _FakeCustomerListNotifier([customerA, customerB])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Initial: Default status is 'completed' (R2) and orange KPI summary card is hidden (R3)
      expect(find.text('Mã đơn: HD_COMP_03'), findsOneWidget);
      expect(find.text('Mã đơn: HD_RET_01'), findsNothing);

      // Select 'Đơn trả hàng' ChoiceChip
      await tester.tap(find.widgetWithText(ChoiceChip, 'Đơn trả hàng'));
      await tester.pumpAndSettle();

      // Isolation check: Only HD_RET_01 (full return) and HD_PART_02 (partial return) are shown
      expect(find.text('Mã đơn: HD_RET_01'), findsOneWidget);
      expect(find.text('Mã đơn: HD_PART_02'), findsOneWidget);
      expect(find.text('Mã đơn: HD_COMP_03'), findsNothing);
      expect(find.text('Mã đơn: HD_CANC_04'), findsNothing);
      expect(find.text('Mã đơn: HD_DRAFT_05'), findsNothing);

      // Verify status badges
      expect(find.text('Đã trả hàng'), findsOneWidget);
      expect(find.text('Trả 1 phần'), findsOneWidget);
    });

    testWidgets('R2.2.1: Empty return list KPI calculation', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider.overrideWith((ref, range) => Stream.value([adversarialOrders[2]])),
            customerListNotifierProvider.overrideWith(() => _FakeCustomerListNotifier([customerA])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Đơn trả hàng'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('return_kpi_summary_card')), findsOneWidget);
      expect(find.text('Số đơn trả: 0'), findsOneWidget);
      expect(find.text('Tổng hoàn trả: 0 đ'), findsOneWidget);
      expect(find.text('Tiền hoàn lại: 0 đ'), findsOneWidget);
      expect(find.text('Cấn trừ nợ: 0 đ'), findsOneWidget);
      expect(find.text('Không tìm thấy hóa đơn nào'), findsOneWidget);
    });

    testWidgets('R2.2.2: Single return order KPI calculation', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider.overrideWith((ref, range) => Stream.value([adversarialOrders[0]])),
            customerListNotifierProvider.overrideWith(() => _FakeCustomerListNotifier([customerA])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Đơn trả hàng'));
      await tester.pumpAndSettle();

      expect(find.text('Số đơn trả: 1'), findsOneWidget);
      expect(find.text('Tổng hoàn trả: 3.000.000 đ'), findsOneWidget);
      expect(find.text('Tiền hoàn lại: 3.000.000 đ'), findsOneWidget);
      expect(find.text('Cấn trừ nợ: 0 đ'), findsOneWidget);
    });

    testWidgets('R2.2.3: Multiple return orders KPI calculation with debt deduction', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider.overrideWith((ref, range) => Stream.value(adversarialOrders)),
            customerListNotifierProvider.overrideWith(() => _FakeCustomerListNotifier([customerA, customerB])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Đơn trả hàng'));
      await tester.pumpAndSettle();

      expect(find.text('Số đơn trả: 2'), findsOneWidget);
      expect(find.text('Tổng hoàn trả: 4.000.000 đ'), findsOneWidget);
      expect(find.text('Tiền hoàn lại: 3.500.000 đ'), findsOneWidget);
      expect(find.text('Cấn trừ nợ: 500.000 đ'), findsOneWidget);
    });

    testWidgets('R2.3: ReturnOrderDetailBottomSheet layout, refund breakdown, and navigation callbacks',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final customReturnOrder = ReturnOrder(
        id: 'TH_CUSTOM_999',
        orderId: 'HD_RET_01',
        customerId: 'cust_a',
        storeId: 'store_001',
        createdAt: testDate,
        items: const [
          ReturnOrderItem(
            productId: 'P_DESK',
            productName: 'Bàn làm việc chữ Z 1m2',
            price: 1500000.0,
            quantity: 2,
            unit: 'cái',
          ),
        ],
        totalReturnAmount: 3000000.0,
        debtDeducted: 500000.0,
        cashRefunded: 2500000.0,
        reason: 'Khách hàng đổi màu sắc',
        createdBy: 'staff_01',
        createdByName: 'Nhân viên A',
        refundPaymentMethod: 'transfer',
      );

      bool topCallbackInvoked = false;
      bool bottomCallbackInvoked = false;

      // 1. Test top "Xem chi tiết" navigation button
      await tester.pumpWidget(
        _buildTestApp(
          child: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  ReturnOrderDetailBottomSheet.show(
                    context,
                    order: adversarialOrders[0],
                    returnOrder: customReturnOrder,
                    customer: customerA,
                    onViewOriginalInvoice: () {
                      topCallbackInvoked = true;
                    },
                  );
                },
                child: const Text('Mở phiếu trả hàng Top'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mở phiếu trả hàng Top'));
      await tester.pumpAndSettle();

      // Verify UI contents
      expect(find.text('Phiếu trả hàng: TH_CUSTOM_999'), findsOneWidget);
      expect(find.text('Hóa đơn gốc: #HD_RET_01'), findsOneWidget);
      expect(find.text('Khách hàng: Công ty Alpha'), findsOneWidget);
      expect(find.text('Bàn làm việc chữ Z 1m2'), findsOneWidget);
      expect(find.text('2 cái x 1.500.000 đ'), findsOneWidget);
      expect(find.text('Tổng tiền hàng trả'), findsOneWidget);
      expect(find.text('3.000.000 đ'), findsWidgets);
      expect(find.text('Cấn trừ công nợ'), findsOneWidget);
      expect(find.text('- 500.000 đ'), findsOneWidget);
      expect(find.text('Tiền hoàn lại cho khách'), findsOneWidget);
      expect(find.text('2.500.000 đ'), findsOneWidget);
      expect(find.text('Chuyển khoản'), findsOneWidget);
      expect(find.text('Khách hàng đổi màu sắc'), findsOneWidget);
      expect(find.text('Nhân viên A'), findsOneWidget);

      // Tap top button
      await tester.tap(find.byKey(const Key('view_original_invoice_button')));
      await tester.pumpAndSettle();
      expect(topCallbackInvoked, isTrue);

      // 2. Test bottom "Xem lại Hóa đơn gốc" navigation button
      await tester.pumpWidget(
        _buildTestApp(
          child: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  ReturnOrderDetailBottomSheet.show(
                    context,
                    order: adversarialOrders[0],
                    returnOrder: customReturnOrder,
                    customer: customerA,
                    onViewOriginalInvoice: () {
                      bottomCallbackInvoked = true;
                    },
                  );
                },
                child: const Text('Mở phiếu trả hàng Bottom'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mở phiếu trả hàng Bottom'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('view_original_invoice_bottom_button')));
      await tester.pumpAndSettle();
      expect(bottomCallbackInvoked, isTrue);
    });

    testWidgets('R2.4: ReturnOrderDetailBottomSheet on standard viewport (800x1600) renders cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: ReturnOrderDetailBottomSheet(
            order: adversarialOrders[0],
            customer: customerA,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Phiếu trả hàng: TH_HD_RET_01'), findsOneWidget);
      expect(find.text('Hóa đơn gốc: #HD_RET_01'), findsOneWidget);
      expect(find.text('Khách hàng: Công ty Alpha'), findsOneWidget);
    });
  });
}
