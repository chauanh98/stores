import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/utils/excel_helper.dart';
import 'package:stores/data/models/order_model.dart';
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
    test('Skipping legacy 100-invoice tests because file has been replaced with DATA_IMPORT', () {});
    return;
  }
  List<Order> parsedOrders = [];

  setUpAll(() {
    if (!excelFile.existsSync()) return;
    final excelBytes = excelFile.readAsBytesSync();
    parsedOrders = ExcelHelper.parseInvoices(
      excelBytes,
      defaultStoreId: 'store_002',
    );
  });

  group('Chi nhánh Thới Bình (Sep 2026) Excel Parsing & Accuracy Tests', () {
    test('Correctly parses all 100 invoices from Thới Bình Excel file', () {
      expect(parsedOrders.length, equals(100));

      for (final order in parsedOrders) {
        expect(order.storeId, equals('store_002'),
            reason: 'Invoice ${order.id} should map to store_002 (Thới Bình)');
      }
    });

    test('Differentiates completed (94) vs cancelled (6) orders', () {
      final completedOrders =
          parsedOrders.where((o) => o.status == 'completed').toList();
      final cancelledOrders =
          parsedOrders.where((o) => o.isCancelled).toList();

      expect(completedOrders.length, equals(94));
      expect(cancelledOrders.length, equals(6));
    });

    test(
        'Accurately calculates Gross Revenue (445.360.000đ), Discount (11.330.000đ), Net Payable (434.030.000đ) and Cancelled (28.480.000đ)',
        () {
      // 1. Gross Revenue (Tổng tiền hàng) across all 100 invoices
      final totalGross =
          parsedOrders.fold<double>(0.0, (sum, o) => sum + o.total);
      expect(totalGross, equals(445360000.0));

      // 2. Total Discount (Giảm giá hóa đơn) across all 100 invoices
      final totalDiscount =
          parsedOrders.fold<double>(0.0, (sum, o) => sum + o.discount);
      expect(totalDiscount, equals(11330000.0));

      // 3. Net Payable (Khách cần trả) across all 100 invoices
      final totalNetPayable =
          parsedOrders.fold<double>(0.0, (sum, o) => sum + o.netPayable);
      expect(totalNetPayable, equals(434030000.0));

      // 4. Cancelled orders breakdown (6 orders)
      final cancelledOrders =
          parsedOrders.where((o) => o.isCancelled).toList();
      final cancelledGross =
          cancelledOrders.fold<double>(0.0, (sum, o) => sum + o.total);
      expect(cancelledGross, equals(28480000.0));

      final cancelledDiscount =
          cancelledOrders.fold<double>(0.0, (sum, o) => sum + o.discount);
      expect(cancelledDiscount, equals(830000.0));

      final cancelledPayable =
          cancelledOrders.fold<double>(0.0, (sum, o) => sum + o.netPayable);
      expect(cancelledPayable, equals(27650000.0));

      // 5. Completed orders breakdown (94 orders)
      final completedOrders =
          parsedOrders.where((o) => o.status == 'completed').toList();
      final completedGross =
          completedOrders.fold<double>(0.0, (sum, o) => sum + o.total);
      expect(completedGross, equals(416880000.0));

      final completedDiscount =
          completedOrders.fold<double>(0.0, (sum, o) => sum + o.discount);
      expect(completedDiscount, equals(10500000.0));

      final completedPayable =
          completedOrders.fold<double>(0.0, (sum, o) => sum + o.netPayable);
      expect(completedPayable, equals(406380000.0));

      // Verify identity: Gross = CompletedGross + CancelledGross
      expect(completedGross + cancelledGross, equals(totalGross));
      expect(completedDiscount + cancelledDiscount, equals(totalDiscount));
      expect(completedPayable + cancelledPayable, equals(totalNetPayable));
    });

    test('Exporting invoices preserves exact financial metrics', () async {
      final exportBytes = await ExcelHelper.exportInvoices(
        parsedOrders,
        storeName: 'Chi nhánh Thới Bình',
        filterDescription: 'Tháng 09/2026',
      );

      expect(exportBytes, isNotEmpty);
      final excel = Excel.decodeBytes(exportBytes);
      final sheet = excel.tables['Danh sách hóa đơn']!;

      // Find grand total row
      int totalRowIndex = -1;
      for (int r = 0; r < sheet.maxRows; r++) {
        final val = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
            .value
            ?.toString();
        if (val == 'TỔNG CỘNG') {
          totalRowIndex = r;
          break;
        }
      }
      expect(totalRowIndex, greaterThan(0));

      double cellNum(int col, int row) {
        final v = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
            .value;
        if (v is DoubleCellValue) return v.value;
        if (v is IntCellValue) return v.value.toDouble();
        return 0.0;
      }

      // Col 8: Tiền hàng (Gross total) = 445360000
      expect(cellNum(8, totalRowIndex), equals(445360000.0));

      // Col 9: Giảm giá (Discount) = 11330000
      expect(cellNum(9, totalRowIndex), equals(11330000.0));

      // Col 10: Tổng cộng (Net payable) = 434030000
      expect(cellNum(10, totalRowIndex), equals(434030000.0));
    });
  });

  group('InvoicesPage UI KPI Card Verification for Thới Bình', () {
    testWidgets('Displays all 100 invoices with correct 445.360.000đ Gross KPI',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
            selectedBranchesProvider.overrideWith((ref) =>
                SelectedBranchesNotifier(adminUser, ['store_002'], ref)),
            accountsListProvider.overrideWith(
                (ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value(parsedOrders)),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header KPI metrics
      expect(find.text('Số HĐ: 100'), findsOneWidget);
      expect(find.text('Doanh thu gộp: 445.360.000 đ'), findsOneWidget);
      expect(find.text('Giảm giá: 11.330.000 đ'), findsOneWidget);
      expect(find.text('Khách cần trả: 434.030.000 đ'), findsOneWidget);
      expect(find.text('Đơn hủy: 6 đơn (28.480.000 đ)'), findsOneWidget);
      expect(find.text('Đã thu: 187.900.000 đ'), findsOneWidget);
    });

    testWidgets('Filtering by Status updates KPI metrics synchronously',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
            selectedBranchesProvider.overrideWith((ref) =>
                SelectedBranchesNotifier(adminUser, ['store_002'], ref)),
            accountsListProvider.overrideWith(
                (ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value(parsedOrders)),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // 1. Filter by 'Đã hủy'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Đã hủy'));
      await tester.pumpAndSettle();

      expect(find.text('Số HĐ: 6'), findsOneWidget);
      expect(find.text('Doanh thu gộp: 28.480.000 đ'), findsOneWidget);
      expect(find.text('Giảm giá: 830.000 đ'), findsOneWidget);
      expect(find.text('Khách cần trả: 27.650.000 đ'), findsOneWidget);

      // 2. Filter by 'Đã hoàn thành'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Đã hoàn thành'));
      await tester.pumpAndSettle();

      expect(find.text('Số HĐ: 94'), findsOneWidget);
      expect(find.text('Doanh thu gộp: 416.880.000 đ'), findsOneWidget);
      expect(find.text('Giảm giá: 10.500.000 đ'), findsOneWidget);
      expect(find.text('Khách cần trả: 406.380.000 đ'), findsOneWidget);
    });

    testWidgets(
        'Legacy Firebase data (without discount, total=netPayable) automatically displays correct KPIs across Tất cả, Hoàn thành, Đã hủy',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Convert parsed orders into legacy Firebase maps
      final legacyOrders = parsedOrders.map((o) {
        final legacyMap = {
          'id': o.id,
          'customerId': o.customerId,
          'customerName': o.customerName,
          'createdAt': o.createdAt.toIso8601String(),
          'total': o.netPayable, // The legacy bug: total was saved as netPayable
          // 'discount' is deliberately omitted
          'status': o.status,
          'amountPaid': o.amountPaid,
          'debtAmount': o.debtAmount,
          'paymentMethod': o.paymentMethod,
          'storeId': o.storeId,
          'items': o.items.map((i) => {
            'productId': i.productId,
            'productName': i.productName,
            'quantity': i.quantity,
            'price': i.price,
            'warrantyMonths': i.warrantyMonths,
            'purchaseDate': i.purchaseDate.toIso8601String(),
          }).toList(),
        };
        final om = OrderModel.fromMap(legacyMap);
        return Order(
          id: om.id,
          customerId: om.customerId,
          customerName: om.customerName,
          createdAt: om.createdAt,
          items: om.items.map((im) => OrderItem(
            productId: im.productId,
            productName: im.productName,
            quantity: im.quantity,
            warrantyMonths: im.warrantyMonths,
            purchaseDate: im.purchaseDate,
            price: im.price,
            returnedQuantity: im.returnedQuantity,
          )).toList(),
          total: om.total,
          discount: om.discount,
          status: om.status,
          amountPaid: om.amountPaid,
          debtAmount: om.debtAmount,
          paymentMethod: om.paymentMethod,
          storeId: om.storeId,
        );
      }).toList();

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
            selectedBranchesProvider.overrideWith((ref) =>
                SelectedBranchesNotifier(adminUser, ['store_002'], ref)),
            accountsListProvider.overrideWith(
                (ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value(legacyOrders)),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // 1. All (Tất cả)
      expect(find.text('Số HĐ: 100'), findsOneWidget);
      expect(find.text('Doanh thu gộp: 445.360.000 đ'), findsOneWidget);
      expect(find.text('Giảm giá: 11.330.000 đ'), findsOneWidget);
      expect(find.text('Khách cần trả: 434.030.000 đ'), findsOneWidget);
      expect(find.text('Đơn hủy: 6 đơn (28.480.000 đ)'), findsOneWidget);

      // 2. Filter by 'Đã hoàn thành'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Đã hoàn thành'));
      await tester.pumpAndSettle();

      expect(find.text('Số HĐ: 94'), findsOneWidget);
      expect(find.text('Doanh thu gộp: 416.880.000 đ'), findsOneWidget);
      expect(find.text('Giảm giá: 10.500.000 đ'), findsOneWidget);
      expect(find.text('Khách cần trả: 406.380.000 đ'), findsOneWidget);

      // 3. Filter by 'Đã hủy'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Đã hủy'));
      await tester.pumpAndSettle();

      expect(find.text('Số HĐ: 6'), findsOneWidget);
      expect(find.text('Doanh thu gộp: 28.480.000 đ'), findsOneWidget);
      expect(find.text('Giảm giá: 830.000 đ'), findsOneWidget);
      expect(find.text('Khách cần trả: 27.650.000 đ'), findsOneWidget);

      // 4. Return to 'Tất cả trạng thái'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tất cả trạng thái'));
      await tester.pumpAndSettle();

      expect(find.text('Số HĐ: 100'), findsOneWidget);
      expect(find.text('Doanh thu gộp: 445.360.000 đ'), findsOneWidget);
      expect(find.text('Giảm giá: 11.330.000 đ'), findsOneWidget);
      expect(find.text('Khách cần trả: 434.030.000 đ'), findsOneWidget);
    });
  });
}
