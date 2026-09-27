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

  void setUser(UserAccount? user) {
    state = user;
  }
}

class _FakeSupplierListNotifier extends SupplierListNotifier {
  final List<Supplier> _suppliers;
  _FakeSupplierListNotifier([this._suppliers = const []]);

  @override
  Future<List<Supplier>> build() async => _suppliers;
}

Widget _wrapWithApp({
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

  final currencyFormat = NumberFormat('#,###', 'vi_VN');

  const adminUser = UserAccount(
    username: 'admin_test',
    displayName: 'Quản trị viên Hệ thống',
    role: 'admin',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor_test',
    displayName: 'Giám sát viên Kho',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff_test',
    displayName: 'Nhân viên Bán hàng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const warehouseStaffUser = UserAccount(
    username: 'warehouse_staff_test',
    displayName: 'Nhân viên Kho',
    role: 'kho',
    storeId: 'store_001',
  );

  const extremeSupplier = Supplier(
    id: 'sup_extreme_999',
    name:
        'Tập Đoàn Tổng Công Ty Cổ Phần Thương Mại Xuất Nhập Khẩu Dược Phẩm Và Trang Thiết Bị Y Tế Toàn Cầu Chi Nhánh Miền Nam',
    phone: '0987654321098765',
    code: 'SUP_EXTREMELY_LONG_CODE_INTERNATIONAL_CORP_999999999',
    address: 'Địa chỉ siêu dài số 123456789 đường Nguyễn Trãi, Quận 5, TP.HCM',
  );

  final extremeReceipt = StockInReceipt(
    id: 'rec_extreme_999999999',
    importCode:
        'PN_20260921_CHI_NHANH_DONG_THANG_EXTREMELY_LONG_CODE_123456789_SPECIAL_BATCH',
    date: DateTime(2026, 9, 21, 14, 45),
    storeId: 'store_001',
    supplierId: 'sup_extreme_999',
    supplierName: extremeSupplier.name,
    createdBy: 'staff_test',
    createdByName: 'Nhân viên Kiểm nghiệm Lô hàng Dược phẩm Cấp cao',
    note:
        'Ghi chú siêu dài: Lô hàng nhập khẩu đặc biệt cần bảo quản trong kho lạnh âm 20 độ C, kiểm tra niêm phong hải quan 3 lớp trước khi bàn giao cho bộ phận kiểm kê, có biên bản bàn giao số 99999/BB-HQ kèm theo hóa đơn giá trị gia tăng số 00987654.',
    items: const [
      StockInReceiptItem(
        transactionId: 'tx_ext_01',
        productId: 'prod_ext_01',
        quantity: 99999,
        importPrice: 999999999.0, // 999.999.999 đ / sp
        productName:
            'Thuốc kháng sinh đặc trị viêm phổi và phế quản cấp tính nâng cao thế hệ mới nhất hộp 100 vỉ x 10 viên nén bao phim đặc biệt chất lượng cao quốc tế',
        productCode:
            'SKU_EXTREMELY_LONG_CODE_PHARMACEUTICAL_PRODUCT_BATCH_1234567890_XYZ',
        unit: 'Thùng 50 hộp x 20 vỉ x 10 viên',
      ),
      StockInReceiptItem(
        transactionId: 'tx_ext_02',
        productId: 'prod_ext_02',
        quantity: 12345,
        importPrice: 888888888.0,
        productName:
            'Dung dịch tiêm truyền tĩnh mạch cân bằng điện giải tái tạo mô khẩn cấp chai 500ml y tế chuẩn GSP',
        productCode: 'SOL_INFUSION_500ML_GSP_EMERGENCY_REGEN_99',
        unit: 'Chai thủy tinh 500ml',
      ),
    ],
    paidAmount: 555555555000.0,
    debtAmount: 444444444000.0, // Debt 444.444.444.000 đ
  );

  final standardReceipt = StockInReceipt(
    id: 'rec_std_001',
    importCode: 'PN_20260921_001',
    date: DateTime(2026, 9, 21, 10, 30),
    storeId: 'store_001',
    supplierId: 'sup_001',
    supplierName: 'Công ty Dược Liệu Á Châu',
    createdBy: 'admin_test',
    createdByName: 'Quản trị viên',
    note: 'Lô hàng chuẩn',
    items: const [
      StockInReceiptItem(
        transactionId: 'tx_std_01',
        productId: 'prod_01',
        quantity: 10,
        importPrice: 123456789.0,
        productName: 'Panadol Extra',
        productCode: 'PANA',
        unit: 'Hộp',
      ),
    ],
    paidAmount: 1000000000.0,
    debtAmount: 234567890.0,
  );

  group('SECURITY CHALLENGE 1: canViewCostPrice Rigorous Tree Boundary', () {
    testWidgets(
        'Staff account (nhanvien) NEVER has any cost prices, unit prices, line totals, or monetary debt numbers rendered in StockInReceiptCard',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
          ],
          child: StockInReceiptCard(receipt: standardReceipt),
        ),
      );
      await tester.pumpAndSettle();

      // Mask bullets should appear
      expect(find.text('••••••'), findsOneWidget);

      // Total amount (1,234,567,890) MUST NOT appear in any Text widget
      final formattedTotal = currencyFormat.format(standardReceipt.totalAmount);
      expect(find.textContaining(formattedTotal), findsNothing);
      expect(find.textContaining('123456789'), findsNothing);

      // Debt badge should NOT display the debt amount number
      final formattedDebt = currencyFormat.format(standardReceipt.debtAmount!);
      expect(find.textContaining(formattedDebt), findsNothing);
      expect(find.text('Ghi nợ NCC'), findsOneWidget);
      expect(find.textContaining('Nợ NCC:'), findsNothing);

      // Verify no raw unformatted or formatted numbers leaked into any Text widget
      for (final element in find.byType(Text).evaluate()) {
        final textWidget = element.widget as Text;
        final data = textWidget.data ?? textWidget.textSpan?.toPlainText() ?? '';
        expect(
          data.contains('123.456.789'),
          isFalse,
          reason: 'Cost price leaked into Text: "$data"',
        );
        expect(
          data.contains('234.567.890'),
          isFalse,
          reason: 'Debt amount leaked into Text: "$data"',
        );
      }
    });

    testWidgets(
        'Warehouse Staff (role: kho) also has canViewCostPrice == false and strictly masks prices',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(warehouseStaffUser)),
          ],
          child: StockInReceiptCard(receipt: standardReceipt),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('••••••'), findsOneWidget);
      expect(find.text('Ghi nợ NCC'), findsOneWidget);
      expect(find.textContaining(currencyFormat.format(standardReceipt.totalAmount)), findsNothing);
    });

    testWidgets(
        'StockInReceiptDetailBottomSheet strictly masks all unit prices, line totals, totalAmount, paidAmount, and debtAmount for staff',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            supplierListNotifierProvider.overrideWith(
              () => _FakeSupplierListNotifier([extremeSupplier]),
            ),
          ],
          child: StockInReceiptDetailBottomSheet(receipt: standardReceipt),
        ),
      );
      await tester.pumpAndSettle();

      // Mask bullets must be present for total amount, paid amount, and line item price
      expect(find.text('••••••'), findsWidgets);

      // Confidentiality badge must be displayed
      expect(
        find.text('Giá trị tiền hàng được bảo mật cho tài khoản nhân viên'),
        findsOneWidget,
      );

      // Unit price must not be visible
      expect(find.textContaining('Đơn giá:'), findsNothing);

      // Debt status must show label only, no currency amount
      expect(find.text('Ghi nợ NCC'), findsOneWidget);
      expect(find.textContaining('Nợ NCC: ${currencyFormat.format(standardReceipt.debtAmount!)} đ'), findsNothing);

      // Exhaustively check every Text widget
      final forbiddenSubstrings = [
        currencyFormat.format(standardReceipt.totalAmount),
        currencyFormat.format(standardReceipt.paidAmount!),
        currencyFormat.format(standardReceipt.debtAmount!),
        currencyFormat.format(standardReceipt.items.first.importPrice),
        currencyFormat.format(standardReceipt.items.first.totalPrice),
      ];

      for (final element in find.byType(Text).evaluate()) {
        final textWidget = element.widget as Text;
        final data = textWidget.data ?? textWidget.textSpan?.toPlainText() ?? '';
        for (final forbidden in forbiddenSubstrings) {
          expect(
            data.contains(forbidden),
            isFalse,
            reason: 'Confidential financial value "$forbidden" leaked into widget: "$data"',
          );
        }
      }
    });

    testWidgets(
        'Header total amount on StockInReceiptsPage is completely omitted for staff accounts',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([standardReceipt]),
            ),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            rawImportTransactionsStreamProvider
                .overrideWith((ref) => Stream.value(<InventoryTransaction>[])),
            allSupplierDebtTransactionsProvider
                .overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
            productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
            allStoresProductsProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
            supplierListNotifierProvider.overrideWith(
              () => _FakeSupplierListNotifier([]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Item count header is visible
      expect(find.text('1 phiếu nhập'), findsOneWidget);

      // But "Tổng: ... đ" must NOT be rendered at all
      expect(find.textContaining('Tổng:'), findsNothing);
      expect(find.textContaining('đ'), findsNothing);
    });
  });

  group('SECURITY CHALLENGE 2: Dynamic Role Switching & Residual Leak Check', () {
    testWidgets(
        'Switching dynamically from Admin to Staff immediately masks all values without residual leaks',
        (tester) async {
      final fakeAuth = _FakeAuthNotifier(adminUser);

      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            authProvider.overrideWith((ref) => fakeAuth),
          ],
          child: StockInReceiptCard(receipt: standardReceipt),
        ),
      );
      await tester.pumpAndSettle();

      // Initially as Admin: total amount and debt are visible
      expect(find.text('••••••'), findsNothing);
      final formattedTotal =
          '${currencyFormat.format(standardReceipt.totalAmount)} đ';
      expect(find.text(formattedTotal), findsOneWidget);
      expect(
        find.text('Nợ NCC: ${currencyFormat.format(standardReceipt.debtAmount!)} đ'),
        findsOneWidget,
      );

      // DYNAMIC SWITCH TO STAFF:
      fakeAuth.setUser(staffUser);
      await tester.pumpAndSettle();

      // Immediately masked!
      expect(find.text('••••••'), findsOneWidget);
      expect(find.text(formattedTotal), findsNothing);
      expect(
        find.text('Nợ NCC: ${currencyFormat.format(standardReceipt.debtAmount!)} đ'),
        findsNothing,
      );
      expect(find.text('Ghi nợ NCC'), findsOneWidget);

      // DYNAMIC SWITCH TO SUPERVISOR:
      fakeAuth.setUser(supervisorUser);
      await tester.pumpAndSettle();

      // Immediately revealed again!
      expect(find.text('••••••'), findsNothing);
      expect(find.text(formattedTotal), findsOneWidget);

      // DYNAMIC LOGOUT (null user):
      fakeAuth.setUser(null);
      await tester.pumpAndSettle();

      // Immediately masked when no user logged in!
      expect(find.text('••••••'), findsOneWidget);
      expect(find.text(formattedTotal), findsNothing);
    });

    testWidgets(
        'Explicit canViewCostPrice parameter override always wins over Provider role',
        (tester) async {
      // Even if provider says Admin, if widget explicitly passed canViewCostPrice: false, it MUST mask!
      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          ],
          child: StockInReceiptCard(
            receipt: standardReceipt,
            canViewCostPrice: false, // Explicit override
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('••••••'), findsOneWidget);
      expect(
        find.text('${currencyFormat.format(standardReceipt.totalAmount)} đ'),
        findsNothing,
      );
    });
  });

  group('UI RESILIENCE CHALLENGE 1: Extreme Values on Narrow Viewports (320, 360, 390, 412px)', () {
    final viewports = <String, Size>{
      '320px (iPhone SE 1st gen)': const Size(320, 640),
      '360px (Budget Android)': const Size(360, 800),
      '390px (iPhone 12/13/14)': const Size(390, 844),
      '412px (Android Standard Large)': const Size(412, 915),
    };

    for (final entry in viewports.entries) {
      final name = entry.key;
      final size = entry.value;

      testWidgets(
          'StockInReceiptCard on $name with extreme strings and 12-digit currency does NOT trigger RenderFlex overflow',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _wrapWithApp(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            ],
            child: StockInReceiptCard(receipt: extremeReceipt),
          ),
        );
        await tester.pumpAndSettle();
      });

      testWidgets(
          'StockInReceiptDetailBottomSheet on $name with extreme data does NOT trigger RenderFlex overflow',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _wrapWithApp(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              supplierListNotifierProvider.overrideWith(
                () => _FakeSupplierListNotifier([extremeSupplier]),
              ),
            ],
            child: StockInReceiptDetailBottomSheet(receipt: extremeReceipt),
          ),
        );
        await tester.pumpAndSettle();
      });

      testWidgets(
          'StockInReceiptsPage on $name with extreme data does NOT trigger RenderFlex overflow',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _wrapWithApp(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              stockInReceiptsProvider.overrideWith(
                (ref) => AsyncValue.data([extremeReceipt, standardReceipt]),
              ),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng Rất Dài Lắm Cơ',
                  }),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              rawImportTransactionsStreamProvider
                  .overrideWith((ref) => Stream.value(<InventoryTransaction>[])),
              allSupplierDebtTransactionsProvider
                  .overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
              productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
              allStoresProductsProvider
                  .overrideWith((ref) => Stream.value(<Product>[])),
              supplierListNotifierProvider.overrideWith(
                () => _FakeSupplierListNotifier([extremeSupplier]),
              ),
            ],
            child: const StockInReceiptsPage(),
          ),
        );
        await tester.pumpAndSettle();
      });
    }
  });

  group('UI RESILIENCE CHALLENGE 2: Rapid Multi-Tap & Interaction Stress', () {
    testWidgets('Rapid 10-tap on StockInReceiptCard does not crash or corrupt UI',
        (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          ],
          child: StockInReceiptCard(
            receipt: standardReceipt,
            onTap: () {
              tapCount++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cardFinder = find.byType(StockInReceiptCard);
      expect(cardFinder, findsOneWidget);

      for (int i = 0; i < 10; i++) {
        await tester.tap(cardFinder);
      }
      await tester.pumpAndSettle();

      expect(tapCount, equals(10));
    });

    testWidgets(
        'Rapid multi-tap on FAB ("Tạo phiếu nhập") navigates cleanly to ImportInventoryPage without crashing',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([standardReceipt]),
            ),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            rawImportTransactionsStreamProvider
                .overrideWith((ref) => Stream.value(<InventoryTransaction>[])),
            allSupplierDebtTransactionsProvider
                .overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
            productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
            allStoresProductsProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
            supplierListNotifierProvider.overrideWith(
              () => _FakeSupplierListNotifier([]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);

      // Tap FAB multiple times rapidly
      await tester.tap(fab, warnIfMissed: false);
      await tester.tap(fab, warnIfMissed: false);
      await tester.tap(fab, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(ImportInventoryPage), findsOneWidget);
    });

    testWidgets('Rapid text entry and clearing in Search input maintains stable UI state',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([standardReceipt, extremeReceipt]),
            ),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            rawImportTransactionsStreamProvider
                .overrideWith((ref) => Stream.value(<InventoryTransaction>[])),
            allSupplierDebtTransactionsProvider
                .overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
            productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
            allStoresProductsProvider
                .overrideWith((ref) => Stream.value(<Product>[])),
            supplierListNotifierProvider.overrideWith(
              () => _FakeSupplierListNotifier([]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField).first;

      for (int i = 0; i < 5; i++) {
        await tester.enterText(searchField, 'Query_$i');
        await tester.pump(const Duration(milliseconds: 50));
        await tester.enterText(searchField, '');
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // Both receipts remain intact
      expect(find.text('#PN_20260921_001'), findsOneWidget);
    });
  });
}
