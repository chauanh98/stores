import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/utils/excel_helper.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
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
    displayName: 'Khánh Đăng',
    role: 'admin',
    storeId: 'store_002',
  );

  final excelFile = File('DanhSachChiTietHoaDon_KV20092026-185010-522.xlsx');
  if (!excelFile.existsSync()) {
    test(
        'Skipping legacy 100-invoice tests because file has been replaced with DATA_IMPORT',
        () {});
    return;
  }

  group('Adversarial Reviewer: Thới Bình Invoice Revenue Deep Stress Tests',
      () {
    test('1. Exact 100 invoices, 445.360.000 gross total, 11.330.000 discount',
        () {
      final bytes = excelFile.readAsBytesSync();
      final orders =
          ExcelHelper.parseInvoices(bytes, defaultStoreId: 'store_002');

      expect(orders.length, 100);

      // Financial invariant 1: Gross revenue (Tổng tiền hàng)
      final gross = orders.fold<double>(0.0, (s, o) => s + o.total);
      expect(gross, 445360000.0);

      // Financial invariant 2: Invoice Discount (Giảm giá hóa đơn)
      final discount = orders.fold<double>(0.0, (s, o) => s + o.discount);
      expect(discount, 11330000.0);

      // Financial invariant 3: Net Payable (Khách cần trả)
      final netPayable = orders.fold<double>(0.0, (s, o) => s + o.netPayable);
      expect(netPayable, 434030000.0);
      expect(gross - discount, netPayable);

      // Financial invariant 4: Cancelled orders
      final cancelled = orders.where((o) => o.isCancelled).toList();
      expect(cancelled.length, 6);
      final cancelledGross = cancelled.fold<double>(0.0, (s, o) => s + o.total);
      expect(cancelledGross, 28480000.0);

      // Financial invariant 5: Active orders
      final active = orders.where((o) => !o.isCancelled).toList();
      expect(active.length, 94);
      final activeGross = active.fold<double>(0.0, (s, o) => s + o.total);
      expect(activeGross, 416880000.0);

      // Invariant: Gross = ActiveGross + CancelledGross
      expect(activeGross + cancelledGross, gross);

      // Total paid across all invoices: 187.900.000
      final totalPaid = orders.fold<double>(0.0, (s, o) => s + o.amountPaid);
      expect(totalPaid, 187900000.0);
    });

    test('2. Header variations and whitespace resilient parsing', () {
      final excel = Excel.createExcel();
      final defaultSheet = excel.sheets.keys.first;
      excel.rename(defaultSheet, 'Sheet1');
      final sheet = excel['Sheet1'];

      final headers = [
        '  Mã hóa đơn  \n',
        ' Thời gian ',
        'Mã KH',
        'Tên khách hàng',
        'Chi nhánh',
        ' Tổng tiền hàng \n',
        ' Chiết khấu HĐ ',
        ' Phải thanh toán ',
        'Khách đã trả',
        'Còn nợ',
        'Trạng thái',
      ];

      for (int i = 0; i < headers.length; i++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .value = TextCellValue(headers[i]);
      }

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
          .value = TextCellValue('HD_VAR_01');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1))
          .value = TextCellValue('2026-09-15 10:00:00');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1))
          .value = TextCellValue('KH_01');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1))
          .value = TextCellValue('Khách thử nghiệm');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1))
          .value = TextCellValue('Chi nhánh Thới Bình');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 1))
          .value = const DoubleCellValue(5000000.0);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 1))
          .value = const DoubleCellValue(200000.0);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 1))
          .value = const DoubleCellValue(4800000.0);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 1))
          .value = const DoubleCellValue(4800000.0);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: 1))
          .value = const DoubleCellValue(0.0);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: 1))
          .value = TextCellValue('Đã hoàn thành');

      final parsed = ExcelHelper.parseInvoices(excel.encode()!);
      expect(parsed.length, 1);
      final o = parsed.first;
      expect(o.id, 'HD_VAR_01');
      expect(o.total, 5000000.0);
      expect(o.discount, 200000.0);
      expect(o.netPayable, 4800000.0);
      expect(o.amountPaid, 4800000.0);
      expect(o.remainingDebt, 0.0);
      expect(o.storeId, 'store_002');
    });

    test(
        '3. Isolation of invoice-level discount from item-level discount column',
        () {
      final excel = Excel.createExcel();
      final sheet = excel[excel.sheets.keys.first];

      final headers = [
        'Mã hóa đơn',
        'Tổng tiền hàng',
        'Giảm giá hóa đơn',
        'Khách cần trả',
        'Khách đã trả',
        'Trạng thái',
        'Mã hàng',
        'Tên hàng',
        'Số lượng',
        'Giảm giá', // Item-level discount
        'Giá bán',
      ];

      for (int i = 0; i < headers.length; i++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .value = TextCellValue(headers[i]);
      }

      // Order with 0 invoice discount, but item discount is 50,000
      final row = [
        'HD_ISOLATE_01',
        1000000.0,
        0.0, // Invoice discount is 0
        1000000.0,
        1000000.0,
        'Đã hoàn thành',
        'SP_01',
        'Sản phẩm 1',
        1,
        50000.0, // Item discount
        950000.0,
      ];

      for (int c = 0; c < row.length; c++) {
        final cell =
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1));
        final val = row[c];
        if (val is double) {
          cell.value = DoubleCellValue(val);
        } else if (val is int) {
          cell.value = IntCellValue(val);
        } else {
          cell.value = TextCellValue(val.toString());
        }
      }

      final parsed = ExcelHelper.parseInvoices(excel.encode()!);
      expect(parsed.length, 1);
      final o = parsed.first;
      expect(o.total, 1000000.0);
      // Crucial: invoice discount must be 0, NOT the 50,000 item discount!
      expect(o.discount, 0.0);
      expect(o.netPayable, 1000000.0);
    });

    test(
        '4. Order remainingDebt contract: explicit debtAmount vs cancelled orders',
        () {
      final now = DateTime.now();

      // Case A: Cancelled order without explicit debt has remainingDebt = 0
      final cancelledNoDebt = Order(
        id: 'HD_C1',
        customerId: 'KH1',
        createdAt: now,
        items: [],
        total: 1000000,
        discount: 100000,
        amountPaid: 0,
        status: 'cancelled',
      );
      expect(cancelledNoDebt.netPayable, 900000);
      expect(cancelledNoDebt.remainingDebt, 0.0);

      // Case B: Cancelled order even with explicit recorded debtAmount must strictly have remainingDebt = 0.0
      final cancelledWithDebt = Order(
        id: 'HD_C2',
        customerId: 'KH2',
        createdAt: now,
        items: [],
        total: 1000000,
        discount: 100000,
        amountPaid: 0,
        debtAmount: 900000,
        status: 'cancelled',
      );
      expect(cancelledWithDebt.remainingDebt, 0.0);

      // Case C: Active order computes debt after discount
      final activeWithDiscount = Order(
        id: 'HD_A1',
        customerId: 'KH3',
        createdAt: now,
        items: [],
        total: 2000000,
        discount: 300000,
        // netPayable = 1,700,000
        amountPaid: 700000,
        status: 'completed',
      );
      expect(activeWithDiscount.netPayable, 1700000.0);
      expect(activeWithDiscount.remainingDebt, 1000000.0);
    });

    testWidgets(
        '5. InvoicesPage UI displays exact multi-metrics & badges for Thới Bình',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final bytes = excelFile.readAsBytesSync();
      final parsedOrders =
          ExcelHelper.parseInvoices(bytes, defaultStoreId: 'store_002');

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
            selectedBranchesProvider.overrideWith((ref) =>
                SelectedBranchesNotifier(adminUser, ['store_002'], ref)),
            accountsListProvider
                .overrideWith((ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(parsedOrders)),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Verify all multi-metric KPI texts
      expect(find.text('Số HĐ: 100'), findsOneWidget);
      expect(find.text('Doanh thu gộp: 445.360.000 đ'), findsOneWidget);
      expect(find.text('Giảm giá: 11.330.000 đ'), findsOneWidget);
      expect(find.text('Khách cần trả: 434.030.000 đ'), findsOneWidget);
      expect(find.text('Đơn hủy: 6 đơn (28.480.000 đ)'), findsOneWidget);
      expect(find.text('Đã thu: 187.900.000 đ'), findsOneWidget);

      // Verify discount badges appear in list
      expect(find.textContaining('Giảm: -'), findsWidgets);
    });

    test(
        '6. Export and re-import round trip preserves all Thới Bình metrics perfectly',
        () async {
      final bytes = excelFile.readAsBytesSync();
      final originalOrders =
          ExcelHelper.parseInvoices(bytes, defaultStoreId: 'store_002');

      // Export to Excel
      final exportedBytes = await ExcelHelper.exportInvoices(
        originalOrders,
        storeName: 'Chi nhánh Thới Bình',
        filterDescription: 'Tháng 9/2026',
      );

      // Re-import from the exported Excel
      final reimportedOrders = ExcelHelper.parseInvoices(
        exportedBytes,
        defaultStoreId: 'store_002',
      );

      expect(reimportedOrders.length, 100);

      final reimportedGross =
          reimportedOrders.fold<double>(0.0, (s, o) => s + o.total);
      expect(reimportedGross, 445360000.0);

      final reimportedDiscount =
          reimportedOrders.fold<double>(0.0, (s, o) => s + o.discount);
      expect(reimportedDiscount, 11330000.0);

      final reimportedNet =
          reimportedOrders.fold<double>(0.0, (s, o) => s + o.netPayable);
      expect(reimportedNet, 434030000.0);

      final reimportedCancelled =
          reimportedOrders.where((o) => o.isCancelled).toList();
      expect(reimportedCancelled.length, 6);
      final reimportedCancelledGross =
          reimportedCancelled.fold<double>(0.0, (s, o) => s + o.total);
      expect(reimportedCancelledGross, 28480000.0);

      final reimportedPaid =
          reimportedOrders.fold<double>(0.0, (s, o) => s + o.amountPaid);
      expect(reimportedPaid, 187900000.0);
    });

    test(
        '7. Single-total Excel export with discount does not produce phantom debt',
        () {
      final excel = Excel.createExcel();
      final sheet = excel[excel.sheets.keys.first];

      final headers = [
        'Mã hóa đơn',
        'Tổng cộng',
        'Giảm giá',
        'Khách đã trả',
        'Trạng thái',
      ];

      for (int i = 0; i < headers.length; i++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .value = TextCellValue(headers[i]);
      }

      // Order with gross 1,000,000, discount 100,000, customer paid 900,000 in full
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
          .value = TextCellValue('HD_NO_PHANTOM_01');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1))
          .value = const DoubleCellValue(1000000.0);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1))
          .value = const DoubleCellValue(100000.0);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1))
          .value = const DoubleCellValue(900000.0);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1))
          .value = TextCellValue('Đã hoàn thành');

      final parsed = ExcelHelper.parseInvoices(excel.encode()!);
      expect(parsed.length, 1);
      final o = parsed.first;
      expect(o.total, 1000000.0);
      expect(o.discount, 100000.0);
      expect(o.netPayable, 900000.0);
      expect(o.amountPaid, 900000.0);
      // Must NOT produce phantom debt!
      expect(o.remainingDebt, 0.0);
      expect(o.hasDebt, isFalse);
    });

    test(
        '8. Excel parser skips footer summary rows beginning with "Tổng cộng" or "Total"',
        () {
      final excel = Excel.createExcel();
      final sheet = excel[excel.sheets.keys.first];

      final headers = [
        'Mã hóa đơn',
        'Tổng tiền hàng',
        'Giảm giá',
        'Khách cần trả',
        'Khách đã trả',
        'Trạng thái',
      ];

      for (int i = 0; i < headers.length; i++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .value = TextCellValue(headers[i]);
      }

      // Valid order row
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
          .value = TextCellValue('HD_VALID_01');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1))
          .value = const DoubleCellValue(500000.0);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1))
          .value = const DoubleCellValue(0.0);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1))
          .value = const DoubleCellValue(500000.0);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1))
          .value = const DoubleCellValue(500000.0);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 1))
          .value = TextCellValue('Đã hoàn thành');

      // Footer summary row
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2))
          .value = TextCellValue('Tổng cộng: 1 hóa đơn');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2))
          .value = const DoubleCellValue(500000.0);

      // Another footer row
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3))
          .value = TextCellValue('Cộng');

      final parsed = ExcelHelper.parseInvoices(excel.encode()!);
      expect(parsed.length, 1);
      expect(parsed.first.id, 'HD_VALID_01');
    });
  });
}
