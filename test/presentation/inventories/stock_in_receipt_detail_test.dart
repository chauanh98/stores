import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';
import 'package:stores/presentation/common/widgets/product_image_thumbnail.dart';
import 'package:stores/presentation/inventories/widgets/cancel_stock_in_receipt_dialog.dart';
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
    key: UniqueKey(),
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

  const sampleSupplier = Supplier(
    id: 'sup_001',
    name: 'Công ty Cổ Phần Dược Phẩm Trung Ương',
    phone: '02838383838',
    code: 'TW3_PHARMA',
    address: 'Quận 1, TP.HCM',
  );

  final sampleReceiptWithDebtAndNote = StockInReceipt(
    id: 'rec_detail_001',
    importCode: 'PN_20260921_DETAIL',
    date: DateTime(2026, 9, 21, 10, 30),
    storeId: 'store_001',
    supplierId: 'sup_001',
    supplierName: 'Công ty Cổ Phần Dược Phẩm Trung Ương',
    createdBy: 'admin_01',
    createdByName: 'Quản trị viên',
    note: 'Lô hàng nhập có điều kiện bảo quản nhiệt độ mát',
    items: const [
      StockInReceiptItem(
        transactionId: 'tx_d1',
        productId: 'prod_d1',
        quantity: 10,
        importPrice: 100000,
        productName: 'Panadol Extra Đỏ',
        productCode: 'PANA_RED',
        unit: 'Hộp',
      ),
      StockInReceiptItem(
        transactionId: 'tx_d2',
        productId: 'prod_d2',
        quantity: 5,
        importPrice: 100000,
        productName: 'Berberin Mộc Hoa Trắng',
        productCode: 'BERB_W',
        unit: 'Lọ',
      ),
    ],
    paidAmount: 800000,
    debtAmount: 700000,
  );

  final sampleReceiptPaidInFullNoNote = StockInReceipt(
    id: 'rec_detail_002',
    importCode: 'PN_20260920_PAID',
    date: DateTime(2026, 9, 20, 15, 0),
    storeId: 'store_002',
    supplierId: null,
    supplierName: null,
    createdBy: 'staff_01',
    createdByName: 'Nhân viên A',
    note: '',
    items: const [
      StockInReceiptItem(
        transactionId: 'tx_d3',
        productId: 'prod_d3',
        quantity: 20,
        importPrice: 50000,
        productName: 'Khẩu trang Y tế Kháng khuẩn',
        productCode: 'KT_KB',
        unit: 'Hộp',
      ),
    ],
    paidAmount: 1000000,
    debtAmount: 0,
  );

  final sampleTransaction = InventoryTransaction(
    id: 'tx_standalone_001',
    productId: 'prod_stand',
    type: TransactionType.import,
    quantity: 12,
    date: DateTime(2026, 9, 19, 8, 45),
    note: 'Import - Cồn Y tế 70 độ 500ml',
    importPrice: 25000,
    createdBy: 'supervisor_01',
    createdByName: 'Giám sát viên',
    storeId: 'store_001',
    importCode: 'PN_STANDALONE_001',
  );

  List<Override> buildCommonOverrides({UserAccount? user}) => [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(user ?? adminUser)),
        supplierListNotifierProvider.overrideWith(
          () => _FakeSupplierListNotifier([sampleSupplier]),
        ),
        availableStoresProvider.overrideWith((ref) async => {
              'store_001': 'Chi nhánh Đông Thắng',
              'store_002': 'Chi nhánh Thới Bình',
            }),
        currentStoreIdProvider.overrideWith((ref) => 'store_001'),
        stockInReceiptsProvider.overrideWith((ref) => const AsyncValue.data([])),
        rawImportTransactionsStreamProvider
            .overrideWith((ref) => Stream.value(<InventoryTransaction>[])),
        storedStockInReceiptsStreamProvider
            .overrideWith((ref) => Stream.value(<StockInReceipt>[])),
        allSupplierDebtTransactionsProvider
            .overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
      ];

  final commonOverrides = buildCommonOverrides();

  group('StockInReceiptDetailBottomSheet - General Info Tests', () {
    testWidgets(
        'Renders header, receipt code, branch badge, date, creator, and full supplier details',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: commonOverrides,
          child: StockInReceiptDetailBottomSheet(
            receipt: sampleReceiptWithDebtAndNote,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Top Header
      expect(find.text('Chi tiết phiếu nhập kho'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      // Receipt Code and Store Badge
      expect(find.text('#PN_20260921_DETAIL'), findsOneWidget);
      expect(find.byType(StoreBadge), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);

      // Date & Creator
      expect(find.text('Ngày nhập:'), findsOneWidget);
      expect(find.text('21/09/2026 10:30'), findsOneWidget);
      expect(find.text('Người nhập:'), findsOneWidget);
      expect(find.text('Quản trị viên'), findsOneWidget);

      // Supplier Info
      expect(find.text('Nhà cung cấp:'), findsOneWidget);
      expect(
        find.text('Công ty Cổ Phần Dược Phẩm Trung Ương'),
        findsOneWidget,
      );
      expect(find.text('Số điện thoại:'), findsOneWidget);
      expect(find.text('02838383838'), findsOneWidget);
      expect(find.text('Mã NCC:'), findsOneWidget);
      expect(find.text('TW3_PHARMA'), findsOneWidget);
    });

    testWidgets(
        'Renders fallback "Nhà cung cấp lẻ" and "Người nhập: —" when creator/supplier are absent',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final minimalReceipt = StockInReceipt(
        id: 'rec_minimal',
        importCode: 'PN_MINIMAL',
        date: DateTime(2026, 9, 20, 15, 0),
        items: const [],
      );

      await tester.pumpWidget(
        _buildTestApp(
          overrides: commonOverrides,
          child: StockInReceiptDetailBottomSheet(
            receipt: minimalReceipt,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nhà cung cấp lẻ'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });
  });

  group('StockInReceiptDetailBottomSheet - Items Breakdown Section Tests', () {
    testWidgets(
        'Renders items count header, thumbnails, SKU, unit, and quantities',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: commonOverrides,
          child: StockInReceiptDetailBottomSheet(
            receipt: sampleReceiptWithDebtAndNote,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Section header: 2 items, total 15 units
      expect(find.text('Danh sách sản phẩm (2)'), findsOneWidget);
      expect(find.text('Tổng 15 sp'), findsOneWidget);

      // Product 1
      expect(find.text('Panadol Extra Đỏ'), findsOneWidget);
      expect(find.text('PANA_RED'), findsOneWidget);
      expect(find.text('ĐVT: Hộp'), findsOneWidget);
      expect(find.text('SL: 10'), findsOneWidget);

      // Product 2
      expect(find.text('Berberin Mộc Hoa Trắng'), findsOneWidget);
      expect(find.text('BERB_W'), findsOneWidget);
      expect(find.text('ĐVT: Lọ'), findsOneWidget);
      expect(find.text('SL: 5'), findsOneWidget);

      // Thumbnails
      expect(find.byType(ProductImageThumbnail), findsNWidgets(2));
    });
  });

  group('StockInReceiptDetailBottomSheet - Financial Summary & Note Tests', () {
    testWidgets(
        'Renders total amount, paid amount, debt amount, and note card when present',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: commonOverrides,
          child: StockInReceiptDetailBottomSheet(
            receipt: sampleReceiptWithDebtAndNote,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tổng kết tài chính'), findsOneWidget);
      expect(find.text('Tổng tiền hàng:'), findsOneWidget);
      expect(
        find.text('${currencyFormat.format(1500000)} đ'),
        findsOneWidget,
      );
      expect(find.text('Đã thanh toán:'), findsOneWidget);
      expect(
        find.text('${currencyFormat.format(800000)} đ'),
        findsOneWidget,
      );
      expect(find.text('Nợ NCC:'), findsOneWidget);
      expect(
        find.text('${currencyFormat.format(700000)} đ'),
        findsOneWidget,
      );

      // Note card
      expect(find.text('Ghi chú lô hàng:'), findsOneWidget);
      expect(
        find.text('Lô hàng nhập có điều kiện bảo quản nhiệt độ mát'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Renders "0 đ (Đã trả đủ)" and hides note card when debt is 0 and note is empty',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: commonOverrides,
          child: StockInReceiptDetailBottomSheet(
            receipt: sampleReceiptPaidInFullNoNote,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 đ (Đã trả đủ)'), findsOneWidget);
      expect(find.text('Ghi chú lô hàng:'), findsNothing);
    });
  });

  group('StockInReceiptDetailBottomSheet - Cost Price Security (canViewCostPrice) Tests', () {
    testWidgets(
        'Staff user (canViewCostPrice == false) has unit prices, totals, and financial summary masked',
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
          ],
          child: StockInReceiptDetailBottomSheet(
            receipt: sampleReceiptWithDebtAndNote,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Unit prices ('Đơn giá: ...') must NOT be displayed
      expect(find.textContaining('Đơn giá:'), findsNothing);

      // Masked dots '••••••' appear for:
      // - Product 1 line total
      // - Product 2 line total
      // - Financial summary 'Tổng tiền hàng'
      // - Financial summary 'Đã thanh toán'
      expect(find.text('••••••'), findsNWidgets(4));

      // Financial summary debt shows 'Ghi nợ NCC' instead of numeric debt
      expect(find.text('Ghi nợ NCC'), findsOneWidget);
      expect(
        find.text('${currencyFormat.format(700000)} đ'),
        findsNothing,
      );

      // Security notice banner is displayed
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(
        find.text(
            'Giá trị tiền hàng được bảo mật cho tài khoản nhân viên'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Admin user (canViewCostPrice == true) sees all unit prices, line totals, and financial values',
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
          ],
          child: StockInReceiptDetailBottomSheet(
            receipt: sampleReceiptWithDebtAndNote,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Unit prices are displayed
      expect(
        find.text('Đơn giá: ${currencyFormat.format(100000)} đ'),
        findsNWidgets(2),
      );

      // Line totals and financial values are displayed uniquely
      expect(
        find.text('${currencyFormat.format(1000000)} đ'),
        findsOneWidget, // Product 1 line total
      );
      expect(
        find.text('${currencyFormat.format(500000)} đ'),
        findsOneWidget, // Product 2 line total
      );
      expect(
        find.text('${currencyFormat.format(800000)} đ'),
        findsOneWidget, // Paid amount
      );
      expect(
        find.text('${currencyFormat.format(700000)} đ'),
        findsOneWidget, // Debt amount
      );

      // Total goods value in financial summary
      expect(
        find.text('${currencyFormat.format(1500000)} đ'),
        findsOneWidget,
      );

      // No masked dots
      expect(find.text('••••••'), findsNothing);

      // Security notice banner is NOT displayed
      expect(
        find.text(
            'Giá trị tiền hàng được bảo mật cho tài khoản nhân viên'),
        findsNothing,
      );
    });

    testWidgets(
        'Supervisor user (canViewCostPrice == true) also sees all monetary values without masking',
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
          ],
          child: StockInReceiptDetailBottomSheet(
            receipt: sampleReceiptWithDebtAndNote,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('••••••'), findsNothing);
      expect(
        find.text('${currencyFormat.format(1500000)} đ'),
        findsOneWidget,
      );
    });
  });

  group('StockInReceiptDetailBottomSheet - Dismissal and Fallback Synthesis Tests', () {
    testWidgets('Tapping bottom "Đóng" button dismisses the bottom sheet',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: commonOverrides,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => StockInReceiptDetailBottomSheet.show(
                context,
                receipt: sampleReceiptWithDebtAndNote,
              ),
              child: const Text('Open Modal'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(StockInReceiptDetailBottomSheet), findsOneWidget);

      // Tap bottom 'Đóng' button
      await tester.tap(find.widgetWithText(ElevatedButton, 'Đóng'));
      await tester.pumpAndSettle();

      expect(find.byType(StockInReceiptDetailBottomSheet), findsNothing);
    });

    testWidgets('Tapping top close icon dismisses the bottom sheet',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: commonOverrides,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => StockInReceiptDetailBottomSheet.show(
                context,
                receipt: sampleReceiptWithDebtAndNote,
              ),
              child: const Text('Open Modal'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(StockInReceiptDetailBottomSheet), findsOneWidget);

      // Tap top close icon
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(StockInReceiptDetailBottomSheet), findsNothing);
    });

    testWidgets(
        'Synthesizes receipt when receipt is null but transaction is provided',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: commonOverrides,
          child: StockInReceiptDetailBottomSheet(
            transaction: sampleTransaction,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Synthesized code
      expect(find.text('#PN_STANDALONE_001'), findsOneWidget);
      // Synthesized product name from note "Import - Cồn Y tế 70 độ 500ml"
      expect(find.text('Cồn Y tế 70 độ 500ml'), findsOneWidget);
      expect(find.text('SL: 12'), findsOneWidget);
      // Total price: 12 * 25,000 = 300,000
      expect(
        find.text('${currencyFormat.format(300000)} đ'),
        findsWidgets,
      );
    });

    testWidgets(
        'Renders error fallback when neither receipt nor valid transaction can be found',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: commonOverrides,
          child: const StockInReceiptDetailBottomSheet(
            importCode: 'PN_UNKNOWN_999',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Không tìm thấy thông tin phiếu nhập kho'),
        findsOneWidget,
      );
      expect(find.text('Mã phiếu: PN_UNKNOWN_999'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Đóng'), findsOneWidget);
    });

    testWidgets(
        'Resolves receipt by importCode via stockInReceiptByIdProvider when receipt parameter is null',
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
              (ref) => AsyncValue.data([sampleReceiptWithDebtAndNote]),
            ),
          ],
          child: const StockInReceiptDetailBottomSheet(
            importCode: 'PN_20260921_DETAIL',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Successfully resolved receipt by importCode
      expect(find.text('#PN_20260921_DETAIL'), findsOneWidget);
      expect(find.text('Panadol Extra Đỏ'), findsOneWidget);
    });
  });

  group('StockInReceiptDetailBottomSheet - Milestone 4 Cancellation & Status Badge Tests', () {
    final completedReceipt = StockInReceipt(
      id: 'rec_m4_detail_completed',
      importCode: 'PN_M4_DET_COMPLETED',
      status: 'completed',
      date: DateTime(2026, 9, 21, 10, 30),
      storeId: 'store_001',
      supplierId: 'sup_001',
      supplierName: 'Công ty Cổ Phần Dược Phẩm Trung Ương',
      createdBy: 'admin_01',
      items: const [
        StockInReceiptItem(
          transactionId: 'tx_c1',
          productId: 'prod_01',
          quantity: 10,
          importPrice: 100000,
          productName: 'Panadol Extra Đỏ',
        ),
      ],
      paidAmount: 1000000,
      debtAmount: 0,
    );

    final draftReceipt = StockInReceipt(
      id: 'rec_m4_detail_draft',
      importCode: 'PN_M4_DET_DRAFT',
      status: 'draft',
      date: DateTime(2026, 9, 22, 11, 0),
      storeId: 'store_001',
      supplierId: 'sup_001',
      supplierName: 'Công ty Cổ Phần Dược Phẩm Trung Ương',
      createdBy: 'admin_01',
      items: const [
        StockInReceiptItem(
          transactionId: 'tx_d1',
          productId: 'prod_02',
          quantity: 5,
          importPrice: 50000,
          productName: 'Berberin Mộc Hoa Trắng',
        ),
      ],
      paidAmount: 0,
      debtAmount: 250000,
    );

    final cancelledReceipt = StockInReceipt(
      id: 'rec_m4_detail_cancelled',
      importCode: 'PN_M4_DET_CANCELLED',
      status: 'cancelled',
      cancelReason: 'Sản phẩm giao sai quy cách đóng gói',
      cancelledAt: DateTime(2026, 9, 23, 15, 30),
      cancelledBy: 'Quản trị viên',
      date: DateTime(2026, 9, 23, 14, 0),
      storeId: 'store_001',
      supplierId: 'sup_001',
      supplierName: 'Công ty Cổ Phần Dược Phẩm Trung Ương',
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
      paidAmount: 240000,
      debtAmount: 0,
    );

    testWidgets(
        'RBAC: "Hủy phiếu nhập" button is visible for Admin and Supervisor, but hidden for Staff',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Admin sees "Hủy phiếu nhập"
      await tester.pumpWidget(
        _buildTestApp(
          overrides: buildCommonOverrides(user: adminUser),
          child: StockInReceiptDetailBottomSheet(receipt: completedReceipt),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('btn_cancel_receipt')), findsOneWidget);
      expect(find.text('Hủy phiếu nhập'), findsOneWidget);

      // 2. Supervisor sees "Hủy phiếu nhập"
      await tester.pumpWidget(
        _buildTestApp(
          overrides: buildCommonOverrides(user: supervisorUser),
          child: StockInReceiptDetailBottomSheet(receipt: completedReceipt),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('btn_cancel_receipt')), findsOneWidget);

      // 3. Staff does NOT see "Hủy phiếu nhập"
      await tester.pumpWidget(
        _buildTestApp(
          overrides: buildCommonOverrides(user: staffUser),
          child: StockInReceiptDetailBottomSheet(receipt: completedReceipt),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('btn_cancel_receipt')), findsNothing);
      expect(find.byKey(const Key('btn_close_detail')), findsOneWidget);
    });

    testWidgets(
        'Tapping "Hủy phiếu nhập" opens CancelStockInReceiptDialog with mandatory reason validation',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: buildCommonOverrides(user: adminUser),
          child: StockInReceiptDetailBottomSheet(receipt: completedReceipt),
        ),
      );
      await tester.pumpAndSettle();

      // Tap cancel button
      await tester.tap(find.byKey(const Key('btn_cancel_receipt')));
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.byType(CancelStockInReceiptDialog), findsOneWidget);
      expect(find.text('Hủy phiếu nhập kho'), findsOneWidget);
      expect(
        find.text(
          'Hủy phiếu nhập sẽ tự động hoàn trả số lượng tồn kho và công nợ nhà cung cấp.',
        ),
        findsOneWidget,
      );

      // Submit empty reason -> validation error
      await tester.tap(find.byKey(const Key('btn_confirm_cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Vui lòng nhập lý do hủy'), findsOneWidget);

      // Close dialog via "Đóng"
      await tester.tap(find.byKey(const Key('btn_cancel_dialog_close')));
      await tester.pumpAndSettle();

      expect(find.byType(CancelStockInReceiptDialog), findsNothing);
    });

    testWidgets(
        'Submitting cancellation reason executes CancelStockInReceiptUseCase and shows snackbar',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeCancelUseCase = _FakeCancelStockInReceiptUseCase();

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...buildCommonOverrides(user: adminUser),
            cancelStockInReceiptUseCaseProvider.overrideWithValue(fakeCancelUseCase),
          ],
          child: StockInReceiptDetailBottomSheet(receipt: completedReceipt),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_cancel_receipt')));
      await tester.pumpAndSettle();

      // Enter valid reason
      final reasonField = find.byKey(const Key('input_cancel_reason'));
      await tester.enterText(reasonField, 'Hàng bị rách bao bì và ẩm mốc');
      await tester.pumpAndSettle();

      // Confirm cancel
      await tester.tap(find.byKey(const Key('btn_confirm_cancel')));
      await tester.pump();

      expect(fakeCancelUseCase.executed, isTrue);
      expect(fakeCancelUseCase.cancelledReceiptId, equals(completedReceipt.id));
      expect(fakeCancelUseCase.cancelReason, equals('Hàng bị rách bao bì và ẩm mốc'));
      expect(find.text('Đã hủy phiếu nhập kho thành công'), findsOneWidget);
    });

    testWidgets(
        'Renders distinct status badges and audit fields for Completed, Draft, and Cancelled receipts',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Completed Receipt
      await tester.pumpWidget(
        _buildTestApp(
          overrides: commonOverrides,
          child: StockInReceiptDetailBottomSheet(receipt: completedReceipt),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('badge_completed')), findsOneWidget);
      expect(find.text('Đã hoàn thành'), findsOneWidget);

      // 2. Draft Receipt
      await tester.pumpWidget(
        _buildTestApp(
          overrides: commonOverrides,
          child: StockInReceiptDetailBottomSheet(receipt: draftReceipt),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('badge_draft')), findsOneWidget);
      expect(find.text('Phiếu tạm'), findsOneWidget);

      // 3. Cancelled Receipt
      await tester.pumpWidget(
        _buildTestApp(
          overrides: commonOverrides,
          child: StockInReceiptDetailBottomSheet(receipt: cancelledReceipt),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('badge_cancelled')), findsOneWidget);
      expect(find.text('Đã hủy'), findsOneWidget);

      // Cancelled Audit Details
      expect(find.text('Lý do hủy:'), findsOneWidget);
      expect(find.text('Sản phẩm giao sai quy cách đóng gói'), findsOneWidget);
      expect(find.text('Người hủy:'), findsOneWidget);
      expect(find.text('Quản trị viên'), findsOneWidget);
      expect(find.text('Thời gian hủy:'), findsOneWidget);
      expect(find.text('23/09/2026 15:30'), findsOneWidget);
    });
  });
}

class _FakeProductRepo implements ProductRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSupplierRepo implements SupplierRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStockInReceiptRepo implements StockInReceiptRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCancelStockInReceiptUseCase extends CancelStockInReceiptUseCase {
  bool executed = false;
  String? cancelledStoreId;
  String? cancelledReceiptId;
  String? cancelReason;
  String? cancelledBy;

  _FakeCancelStockInReceiptUseCase()
      : super(
          productRepository: _FakeProductRepo(),
          inventoryRepository: _FakeInventoryRepo(),
          supplierRepository: _FakeSupplierRepo(),
          receiptRepository: _FakeStockInReceiptRepo(),
        );

  @override
  Future<void> execute({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {
    executed = true;
    cancelledStoreId = storeId;
    cancelledReceiptId = receipt.id;
    cancelReason = reason;
    this.cancelledBy = cancelledBy;
  }
}
