import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/pages/stock_in_receipts_page.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_receipt_card.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_receipt_detail_bottom_sheet.dart';

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

class _FakeSupplierListNotifier extends SupplierListNotifier {
  final List<Supplier> _suppliers;
  _FakeSupplierListNotifier([this._suppliers = const []]);

  @override
  Future<List<Supplier>> build() async => _suppliers;
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
  TestWidgetsFlutterBinding.ensureInitialized();

  final currencyFormat = NumberFormat('#,###', 'vi_VN');

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor_01',
    displayName: 'Giám sát viên',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const sampleSupplier1 = Supplier(
    id: 'sup_001',
    name: 'Công ty Dược Phẩm ABC',
    phone: '0901234567',
    code: 'NCC001',
    address: 'Hà Nội',
  );

  const sampleSupplier2 = Supplier(
    id: 'sup_002',
    name: 'Nhà Phân Phối XYZ',
    phone: '0912345678',
    code: 'NCC002',
    address: 'TP.HCM',
  );

  final sampleReceipt1 = StockInReceipt(
    id: 'rec_001',
    importCode: 'PN_20260921_001',
    date: DateTime(2026, 9, 21, 10, 30),
    storeId: 'store_001',
    supplierId: 'sup_001',
    supplierName: 'Công ty Dược Phẩm ABC',
    createdBy: 'admin_01',
    createdByName: 'Quản trị viên',
    note: 'Lô hàng nhập đầu tuần',
    items: const [
      StockInReceiptItem(
        transactionId: 'tx_01',
        productId: 'prod_01',
        quantity: 10,
        importPrice: 100000,
        productName: 'Panadol Extra',
        productCode: 'PANA',
        unit: 'Hộp',
      ),
      StockInReceiptItem(
        transactionId: 'tx_02',
        productId: 'prod_02',
        quantity: 5,
        importPrice: 100000,
        productName: 'Berberin 100mg',
        productCode: 'BERB',
        unit: 'Lọ',
      ),
    ],
    paidAmount: 1000000,
    debtAmount: 500000,
  );

  final sampleReceipt2 = StockInReceipt(
    id: 'rec_002',
    importCode: 'PN_20260920_002',
    date: DateTime(2026, 9, 20, 14, 15),
    storeId: 'store_002',
    supplierId: 'sup_002',
    supplierName: 'Nhà Phân Phối XYZ',
    createdBy: 'staff_01',
    createdByName: 'Nhân viên B',
    note: '',
    items: const [
      StockInReceiptItem(
        transactionId: 'tx_03',
        productId: 'prod_03',
        quantity: 20,
        importPrice: 50000,
        productName: 'Khẩu trang Y tế 4 lớp',
        productCode: 'KT4L',
        unit: 'Hộp',
      ),
    ],
    paidAmount: 1000000,
    debtAmount: 0,
  );

  final commonOverrides = [
    authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
    supplierListNotifierProvider.overrideWith(
      () => _FakeSupplierListNotifier([sampleSupplier1, sampleSupplier2]),
    ),
    availableStoresProvider.overrideWith((ref) async => {
          'store_001': 'Chi nhánh Đông Thắng',
          'store_002': 'Chi nhánh Thới Bình',
        }),
    currentStoreIdProvider.overrideWith((ref) => 'store_001'),
    productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
    allStoresProductsProvider.overrideWith((ref) => Stream.value(<Product>[])),
    rawImportTransactionsStreamProvider
        .overrideWith((ref) => Stream.value(<InventoryTransaction>[])),
    allSupplierDebtTransactionsProvider
        .overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
  ];

  group('StockInReceiptsPage - Empty State Tests', () {
    testWidgets(
        'Renders empty state with illustration and create button when receipts list is empty and no active filters',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => const AsyncValue.data([]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
      expect(find.text('Chưa có phiếu nhập kho nào'), findsOneWidget);
      expect(
        find.text('Hãy tạo phiếu nhập kho đầu tiên để theo dõi xuất nhập tồn'),
        findsOneWidget,
      );
      // R1: Duplicate button inside empty state is eliminated
      expect(find.text('Tạo phiếu nhập mới'), findsNothing);
      // R1: Single FAB at bottom right remains present
      expect(find.text('Tạo phiếu nhập'), findsOneWidget);
    });

    testWidgets(
        'Empty state has no duplicate button; FAB "Tạo phiếu nhập" navigates to ImportInventoryPage',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => const AsyncValue.data([]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tạo phiếu nhập mới'), findsNothing);
      expect(find.text('Tạo phiếu nhập'), findsOneWidget);

      await tester.tap(find.text('Tạo phiếu nhập'));
      await tester.pumpAndSettle();

      expect(find.byType(ImportInventoryPage), findsOneWidget);
    });

    testWidgets(
        'Renders filter-specific empty state and reset button when active filters yield no results',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1, sampleReceipt2]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Enter a search query that matches nothing
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'MaPhieuKhongTonTai999');
      await tester.pumpAndSettle();

      expect(find.text('Chưa có phiếu nhập kho nào'), findsOneWidget);
      expect(
        find.text(
            'Không tìm thấy kết quả phù hợp với các tiêu chí lọc hiện tại'),
        findsOneWidget,
      );
      expect(find.text('Đặt lại bộ lọc'), findsWidgets);

      // Tap reset filters button
      await tester.tap(find.text('Đặt lại bộ lọc').first);
      await tester.pumpAndSettle();

      // Both receipts reappear
      expect(find.text('#PN_20260921_001'), findsOneWidget);
      expect(find.text('#PN_20260920_002'), findsOneWidget);
    });
  });

  group('StockInReceiptsPage - Loading and Error State Tests', () {
    testWidgets('Renders skeleton shimmer cards when state is loading',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            filteredStockInReceiptsAsyncProvider.overrideWith(
              (ref) => const AsyncValue.loading(),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pump();

      // Skeleton cards are generated via ListView.builder with 5 items
      expect(find.byType(Card), findsNWidgets(5));
    });

    testWidgets(
        'Renders error state with retry button when error occurs',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            filteredStockInReceiptsAsyncProvider.overrideWith(
              (ref) => const AsyncValue.error(
                'Lỗi kết nối Firebase',
                StackTrace.empty,
              ),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(
        find.text('Lỗi tải dữ liệu: Lỗi kết nối Firebase'),
        findsOneWidget,
      );
      expect(find.text('Thử lại'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });

  group('StockInReceiptsPage - Receipts List Rendering Tests', () {
    testWidgets(
        'Renders receipt cards with code, supplier, items badge, creator, and store badge',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1, sampleReceipt2]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Receipts count header
      expect(find.text('2 phiếu nhập'), findsOneWidget);

      // Receipt 1 content
      expect(find.text('#PN_20260921_001'), findsOneWidget);
      expect(find.text('Công ty Dược Phẩm ABC'), findsOneWidget);
      expect(find.text('2 mặt hàng • 15 sp'), findsOneWidget);
      expect(find.text('Người nhập: Quản trị viên'), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng'), findsWidgets);
      expect(find.text('Lô hàng nhập đầu tuần'), findsOneWidget);

      // Receipt 2 content
      expect(find.text('#PN_20260920_002'), findsOneWidget);
      expect(find.text('Nhà Phân Phối XYZ'), findsOneWidget);
      expect(find.text('1 mặt hàng • 20 sp'), findsOneWidget);
      expect(find.text('Người nhập: Nhân viên B'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình'), findsWidgets);

      // Debt badges with formatted currency
      expect(
        find.text('Nợ NCC: ${currencyFormat.format(500000)} đ'),
        findsOneWidget,
      );
      expect(find.text('Đã thanh toán đủ'), findsOneWidget);
    });
  });

  group('StockInReceiptsPage - Cost Price Security (canViewCostPrice) Tests', () {
    testWidgets(
        'Staff user (canViewCostPrice == false) sees masked monetary amounts (••••••) and masked debt',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sampleReceipt1B = sampleReceipt2.copyWith(
        id: 'rec_002_store1',
        storeId: 'store_001',
      );

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1, sampleReceipt1B]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Masked dots appear for each receipt card in staff's store
      expect(find.text('••••••'), findsNWidgets(2));

      // Monetary amount keys should NOT be rendered
      expect(find.byKey(const Key('receipt_total_amount_rec_001')), findsNothing);
      expect(find.byKey(const Key('receipt_total_amount_rec_002_store1')), findsNothing);

      // Total sum in list header should NOT be rendered for staff
      expect(find.textContaining('Tổng:'), findsNothing);

      // Debt status badge is masked to 'Ghi nợ NCC' instead of numeric amount
      expect(find.text('Ghi nợ NCC'), findsOneWidget);
      expect(
        find.textContaining('Nợ NCC: ${currencyFormat.format(500000)} đ'),
        findsNothing,
      );
    });

    testWidgets(
        'Staff user only sees receipts belonging to their assigned storeId (store isolation)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1, sampleReceipt2]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Receipt 1 (store_001) is displayed
      expect(find.text('#PN_20260921_001'), findsOneWidget);
      // Receipt 2 (store_002) is excluded by staff store isolation
      expect(find.text('#PN_20260920_002'), findsNothing);
      expect(find.text('1 phiếu nhập'), findsOneWidget);
    });

    testWidgets(
        'Admin user (canViewCostPrice == true) sees formatted currency amounts and summary total',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1, sampleReceipt2]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Masked dots must NOT appear
      expect(find.text('••••••'), findsNothing);

      // Card amounts are visible with formatted currency
      expect(find.byKey(const Key('receipt_total_amount_rec_001')), findsOneWidget);
      expect(
        find.text('${currencyFormat.format(1500000)} đ'),
        findsOneWidget,
      );
      expect(
        find.text('${currencyFormat.format(1000000)} đ'),
        findsOneWidget,
      );

      // Summary total in list header: 1.5M + 1M = 2.5M
      expect(
        find.text('Tổng: ${currencyFormat.format(2500000)} đ'),
        findsOneWidget,
      );

      // Numeric debt amount visible
      expect(
        find.text('Nợ NCC: ${currencyFormat.format(500000)} đ'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Supervisor user (canViewCostPrice == true) also sees formatted currency amounts',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('••••••'), findsNothing);
      expect(
        find.text('${currencyFormat.format(1500000)} đ'),
        findsOneWidget,
      );
      expect(
        find.text('Tổng: ${currencyFormat.format(1500000)} đ'),
        findsOneWidget,
      );
    });
  });

  group('StockInReceiptsPage - Search & Filter Interactions Tests', () {
    testWidgets('Search query filters receipts by SKU, code, or product name',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1, sampleReceipt2]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Both receipts initially visible
      expect(find.text('#PN_20260921_001'), findsOneWidget);
      expect(find.text('#PN_20260920_002'), findsOneWidget);

      // Search by SKU 'BERB' belonging to receipt 1
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'BERB');
      await tester.pumpAndSettle();

      expect(find.text('#PN_20260921_001'), findsOneWidget);
      expect(find.text('#PN_20260920_002'), findsNothing);

      // Clear search via clear icon
      expect(find.byIcon(Icons.clear), findsOneWidget);
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // Both receipts visible again
      expect(find.text('#PN_20260921_001'), findsOneWidget);
      expect(find.text('#PN_20260920_002'), findsOneWidget);
    });

    testWidgets('Time range filter chip opens modal and selects time range',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1, sampleReceipt2]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Default label is 'Tháng này'
      expect(find.text('Tháng này'), findsOneWidget);

      // Tap time range chip
      await tester.tap(find.text('Tháng này'));
      await tester.pumpAndSettle();

      // Modal options
      expect(find.text('Chọn thời gian'), findsOneWidget);
      expect(find.text('Hôm nay'), findsOneWidget);
      expect(find.text('Hôm qua'), findsOneWidget);
      expect(find.text('7 ngày qua'), findsOneWidget);

      // Select 'Hôm nay' via ListTile
      await tester.tap(find.widgetWithText(ListTile, 'Hôm nay'));
      await tester.pumpAndSettle();

      // Filter chip now displays 'Hôm nay'
      expect(find.text('Hôm nay'), findsOneWidget);
    });

    testWidgets('Supplier filter chip opens modal and selects specific supplier',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1, sampleReceipt2]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Supplier chip
      await tester.tap(find.text('Nhà cung cấp'));
      await tester.pumpAndSettle();

      // Supplier modal opens
      expect(find.text('Lọc theo Nhà cung cấp'), findsOneWidget);
      expect(find.text('Tất cả nhà cung cấp'), findsOneWidget);

      // Select 'Công ty Dược Phẩm ABC' via ListTile in modal
      await tester.tap(
        find.widgetWithText(ListTile, 'Công ty Dược Phẩm ABC'),
      );
      await tester.pumpAndSettle();

      // Only receipt 1 from ABC should be visible
      expect(find.text('#PN_20260921_001'), findsOneWidget);
      expect(find.text('#PN_20260920_002'), findsNothing);
    });

    testWidgets('Branch filter chip is shown for Admin and hidden for Staff',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Admin user sees branch filter chip
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1, sampleReceipt2]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tất cả chi nhánh'), findsOneWidget);

      // Tap branch chip
      await tester.tap(find.text('Tất cả chi nhánh'));
      await tester.pumpAndSettle();

      expect(find.text('Lọc theo Chi nhánh'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Chi nhánh Thới Bình'));
      await tester.pumpAndSettle();

      // Only receipt 2 is for store_002 (Thới Bình)
      expect(find.text('#PN_20260921_001'), findsNothing);
      expect(find.text('#PN_20260920_002'), findsOneWidget);

      // 2. Staff user does NOT see branch filter chip
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1, sampleReceipt2]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tất cả chi nhánh'), findsNothing);
    });

    testWidgets('Active filters show "Xóa lọc" button which resets filters',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1, sampleReceipt2]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no 'Xóa lọc' chip
      expect(find.text('Xóa lọc'), findsNothing);

      // Filter by supplier
      await tester.tap(find.text('Nhà cung cấp'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Nhà Phân Phối XYZ'));
      await tester.pumpAndSettle();

      // Now 'Xóa lọc' chip and AppBar icon appear
      expect(find.text('Xóa lọc'), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);

      // Tap 'Xóa lọc'
      await tester.tap(find.text('Xóa lọc'));
      await tester.pumpAndSettle();

      // Restored back to default
      expect(find.text('Xóa lọc'), findsNothing);
      expect(find.text('#PN_20260921_001'), findsOneWidget);
      expect(find.text('#PN_20260920_002'), findsOneWidget);
    });
  });

  group('StockInReceiptsPage - Navigation and Detail Modal Tests', () {
    testWidgets('Tapping FAB "Tạo phiếu nhập" navigates to ImportInventoryPage',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tạo phiếu nhập'), findsOneWidget);
      await tester.tap(find.text('Tạo phiếu nhập'));
      await tester.pumpAndSettle();

      expect(find.byType(ImportInventoryPage), findsOneWidget);
    });

    testWidgets('Tapping a receipt card opens StockInReceiptDetailBottomSheet',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([sampleReceipt1]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap card
      await tester.tap(find.byType(StockInReceiptCard).first);
      await tester.pumpAndSettle();

      // Detail bottom sheet opens
      expect(find.byType(StockInReceiptDetailBottomSheet), findsOneWidget);
      expect(find.text('Chi tiết phiếu nhập kho'), findsOneWidget);
    });
  });

  group('StockInReceiptsPage - Mobile UI Tests', () {
    testWidgets(
        'Does NOT render "Nhập Excel" action button on mobile StockInReceiptsPage',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => const AsyncValue.data([]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Nhập Excel'), findsNothing);
      expect(find.byIcon(Icons.upload_file), findsNothing);
      expect(
        find.byKey(const Key('stock_in_receipts_import_excel_button')),
        findsNothing,
      );
    });
  });

  group('StockInReceiptsPage - Milestone 4 3-State Filter & Draft Management', () {
    final completedRec = StockInReceipt(
      id: 'rec_m4_completed',
      importCode: 'PN_M4_COMPLETED',
      status: 'completed',
      date: DateTime(2026, 9, 21, 10, 30),
      storeId: 'store_001',
      supplierId: 'sup_001',
      supplierName: 'Công ty Dược Phẩm ABC',
      createdBy: 'admin_01',
      items: const [
        StockInReceiptItem(
          transactionId: 'tx_c1',
          productId: 'prod_01',
          quantity: 10,
          importPrice: 100000,
          productName: 'Panadol Extra',
        ),
      ],
    );

    final draftRec = StockInReceipt(
      id: 'rec_m4_draft',
      importCode: 'PN_M4_DRAFT',
      status: 'draft',
      date: DateTime(2026, 9, 22, 11, 0),
      storeId: 'store_001',
      supplierId: 'sup_001',
      supplierName: 'Công ty Dược Phẩm ABC',
      createdBy: 'admin_01',
      items: const [
        StockInReceiptItem(
          transactionId: 'tx_d1',
          productId: 'prod_02',
          quantity: 5,
          importPrice: 50000,
          productName: 'Berberin 100mg',
        ),
      ],
    );

    final cancelledRec = StockInReceipt(
      id: 'rec_m4_cancelled',
      importCode: 'PN_M4_CANCELLED',
      status: 'cancelled',
      cancelReason: 'Hàng không đạt chuẩn kiểm nghiệm',
      date: DateTime(2026, 9, 23, 14, 0),
      storeId: 'store_001',
      supplierId: 'sup_001',
      supplierName: 'Công ty Dược Phẩm ABC',
      createdBy: 'admin_01',
      items: const [
        StockInReceiptItem(
          transactionId: 'tx_x1',
          productId: 'prod_03',
          quantity: 8,
          importPrice: 30000,
          productName: 'Bông y tế',
        ),
      ],
    );

    testWidgets(
        'Filters receipts accurately across All, Completed, Draft, and Cancelled status states',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([completedRec, draftRec, cancelledRec]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Initially 'all' status: all 3 receipts are visible
      expect(find.text('#PN_M4_COMPLETED'), findsOneWidget);
      expect(find.text('#PN_M4_DRAFT'), findsOneWidget);
      expect(find.text('#PN_M4_CANCELLED'), findsOneWidget);
      expect(find.text('3 phiếu nhập'), findsOneWidget);

      // Filter: 'completed'
      await tester.tap(find.byKey(const Key('filter_completed')));
      await tester.pumpAndSettle();

      expect(find.text('#PN_M4_COMPLETED'), findsOneWidget);
      expect(find.text('#PN_M4_DRAFT'), findsNothing);
      expect(find.text('#PN_M4_CANCELLED'), findsNothing);
      expect(find.text('1 phiếu nhập'), findsOneWidget);

      // Filter: 'draft'
      await tester.tap(find.byKey(const Key('filter_draft')));
      await tester.pumpAndSettle();

      expect(find.text('#PN_M4_COMPLETED'), findsNothing);
      expect(find.text('#PN_M4_DRAFT'), findsOneWidget);
      expect(find.text('#PN_M4_CANCELLED'), findsNothing);
      expect(find.text('1 phiếu nhập'), findsOneWidget);

      // Filter: 'cancelled'
      await tester.tap(find.byKey(const Key('filter_cancelled')));
      await tester.pumpAndSettle();

      expect(find.text('#PN_M4_COMPLETED'), findsNothing);
      expect(find.text('#PN_M4_DRAFT'), findsNothing);
      expect(find.text('#PN_M4_CANCELLED'), findsOneWidget);
      expect(find.text('1 phiếu nhập'), findsOneWidget);

      // Filter: 'all'
      await tester.tap(find.byKey(const Key('filter_all')));
      await tester.pumpAndSettle();

      expect(find.text('#PN_M4_COMPLETED'), findsOneWidget);
      expect(find.text('#PN_M4_DRAFT'), findsOneWidget);
      expect(find.text('#PN_M4_CANCELLED'), findsOneWidget);
      expect(find.text('3 phiếu nhập'), findsOneWidget);
    });

    testWidgets(
        'Tapping a draft card opens ImportInventoryPage with initialReceipt for resuming',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([draftRec]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Find draft card and tap
      expect(find.text('#PN_M4_DRAFT'), findsOneWidget);
      await tester.tap(find.text('#PN_M4_DRAFT'));
      await tester.pumpAndSettle();

      // Opens ImportInventoryPage
      expect(find.byType(ImportInventoryPage), findsOneWidget);
      expect(find.byType(StockInReceiptDetailBottomSheet), findsNothing);
    });

    testWidgets(
        'Deleting a draft directly prompts confirmation dialog and calls deleteStockInReceiptUseCaseProvider',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeDeleteUseCase = _FakeDeleteStockInReceiptUseCase();

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            deleteStockInReceiptUseCaseProvider.overrideWithValue(fakeDeleteUseCase),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([draftRec]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Draft card has delete icon
      final deleteIcon = find.byKey(Key('btn_delete_draft_${draftRec.id}'));
      expect(deleteIcon, findsOneWidget);

      // Tap delete icon -> opens confirmation dialog
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      expect(find.text('Xóa phiếu tạm này?'), findsOneWidget);
      expect(find.byKey(const Key('btn_cancel_delete_draft')), findsOneWidget);
      expect(find.byKey(const Key('btn_confirm_delete_draft')), findsOneWidget);

      // Tap Cancel -> does not delete
      await tester.tap(find.byKey(const Key('btn_cancel_delete_draft')));
      await tester.pumpAndSettle();

      expect(fakeDeleteUseCase.executed, isFalse);
      expect(find.text('#PN_M4_DRAFT'), findsOneWidget);

      // Tap delete again, and confirm
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_confirm_delete_draft')));
      await tester.pumpAndSettle();

      expect(fakeDeleteUseCase.executed, isTrue);
      expect(fakeDeleteUseCase.deletedReceiptId, equals(draftRec.id));
      expect(fakeDeleteUseCase.deletedStoreId, equals('store_001'));
      expect(find.text('Đã xóa phiếu tạm thành công'), findsOneWidget);
    });
  });
}

class _FakeStockInReceiptRepository implements StockInReceiptRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDeleteStockInReceiptUseCase extends DeleteStockInReceiptUseCase {
  bool executed = false;
  String? deletedStoreId;
  String? deletedReceiptId;

  _FakeDeleteStockInReceiptUseCase() : super(_FakeStockInReceiptRepository());

  @override
  Future<void> execute({
    required String storeId,
    required StockInReceipt receipt,
  }) async {
    executed = true;
    deletedStoreId = storeId;
    deletedReceiptId = receipt.id;
  }
}
