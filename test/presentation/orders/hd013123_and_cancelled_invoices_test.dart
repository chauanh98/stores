import 'dart:io';

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

class _FakeCustomerListNotifier extends AutoDisposeAsyncNotifier<List<Customer>>
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

  group(
      'R1. Sửa lỗi trừ giảm giá 2 lần (Double Discount Deduction) trong OrderModel.fromMap & Order',
      () {
    test(
        'HD013123: Gross 8.500.000đ, Giảm giá 200.000đ -> Khách cần trả 8.300.000đ (không phải 8.100.000đ)',
        () {
      final hd013123Map = {
        'id': 'HD013123',
        'customerId': 'KH006900',
        'customerName': 'Anh Nghĩa',
        'createdAt': '2026-09-01T14:29:08.000',
        'total': 8300000.0, // Legacy/raw net total in JSON
        'subtotal': 8500000.0,
        'discount': 200000.0,
        'status': 'cancelled',
        'amountPaid': 0.0,
        'debtAmount': 8300000.0,
        'paymentMethod': 'cash',
        'storeId': 'store_002',
        'items': [
          {
            'productId': 'GL22',
            'productName': 'Giường tây trụ thao lao (nhà) DÀY - 1m8',
            'quantity': 1,
            'price': 8500000.0,
            'warrantyMonths': 0,
            'purchaseDate': '2026-09-01T14:29:08.000',
            'returnedQuantity': 0,
          },
        ],
      };

      final orderModel = OrderModel.fromMap(hd013123Map);
      expect(orderModel.total, equals(8500000.0),
          reason: 'Gross Total must be 8.500.000đ');
      expect(orderModel.discount, equals(200000.0),
          reason: 'Discount must be 200.000đ');
      expect(orderModel.debtAmount, equals(0.0),
          reason: 'Cancelled order in OrderModel must have debtAmount == 0.0');
      expect(orderModel.toMap()['debtAmount'], equals(0.0),
          reason: 'Serialized debtAmount must be 0.0');

      final order = Order(
        id: orderModel.id,
        customerId: orderModel.customerId,
        customerName: orderModel.customerName,
        createdAt: orderModel.createdAt,
        total: orderModel.total,
        discount: orderModel.discount,
        status: orderModel.status,
        amountPaid: orderModel.amountPaid,
        debtAmount: orderModel.debtAmount,
        paymentMethod: orderModel.paymentMethod,
        storeId: orderModel.storeId,
        items: orderModel.items
            .map((i) => OrderItem(
                  productId: i.productId,
                  productName: i.productName,
                  quantity: i.quantity,
                  price: i.price,
                  warrantyMonths: i.warrantyMonths,
                  purchaseDate: i.purchaseDate,
                ))
            .toList(),
      );

      // Verify no double discount deduction
      expect(order.total, equals(8500000.0));
      expect(order.discount, equals(200000.0));
      expect(order.netPayable, equals(8300000.0),
          reason: 'Khách cần trả must be 8.300.000đ, NOT 8.100.000đ');
      expect(order.remainingDebt, equals(0.0),
          reason: 'Cancelled order must have 0.0 remaining debt');
      expect(order.hasDebt, isFalse);
    });

    test(
        'HD013123_01: Gross 10.700.000đ, Giảm giá 400.000đ -> Khách cần trả 10.300.000đ, nợ 9.300.000đ',
        () {
      final hd01312301Map = {
        'id': 'HD013123_01',
        'customerId': 'KH006900',
        'customerName': 'Anh Nghĩa',
        'createdAt': '2026-09-01T14:29:08.000',
        'total': 10300000.0,
        'subtotal': 10700000.0,
        'discount': 400000.0,
        'status': 'completed',
        'amountPaid': 1000000.0,
        'debtAmount': 9300000.0,
        'paymentMethod': 'cash',
        'storeId': 'store_002',
        'items': [
          {
            'productId': 'GL21',
            'productName': 'Giường tây trụ thao lao (nhà) DÀY - 1m6',
            'quantity': 1,
            'price': 8100000.0,
            'warrantyMonths': 0,
            'purchaseDate': '2026-09-01T14:29:08.000',
            'returnedQuantity': 0,
          },
          {
            'productId': 'VG8',
            'productName': 'Giá võng gỗ thao lao - trụ',
            'quantity': 1,
            'price': 2600000.0,
            'warrantyMonths': 0,
            'purchaseDate': '2026-09-01T14:29:08.000',
            'returnedQuantity': 0,
          },
        ],
      };

      final orderModel = OrderModel.fromMap(hd01312301Map);
      expect(orderModel.total, equals(10700000.0));
      expect(orderModel.discount, equals(400000.0));

      final order = Order(
        id: orderModel.id,
        customerId: orderModel.customerId,
        customerName: orderModel.customerName,
        createdAt: orderModel.createdAt,
        total: orderModel.total,
        discount: orderModel.discount,
        status: orderModel.status,
        amountPaid: orderModel.amountPaid,
        debtAmount: orderModel.debtAmount,
        paymentMethod: orderModel.paymentMethod,
        storeId: orderModel.storeId,
        items: orderModel.items
            .map((i) => OrderItem(
                  productId: i.productId,
                  productName: i.productName,
                  quantity: i.quantity,
                  price: i.price,
                  warrantyMonths: i.warrantyMonths,
                  purchaseDate: i.purchaseDate,
                ))
            .toList(),
      );

      expect(order.netPayable, equals(10300000.0));
      expect(order.amountPaid, equals(1000000.0));
      expect(order.remainingDebt, equals(9300000.0));
      expect(order.hasDebt, isTrue);
    });

    test(
        'Defensive check: backfills discount if discount is 0 and itemsSum > rawTotal',
        () {
      final mapWithoutExplicitDiscount = {
        'id': 'HD_NO_DISC',
        'customerId': 'KH01',
        'createdAt': '2026-09-01T10:00:00.000',
        'total': 450000.0,
        'discount': 0.0,
        'status': 'completed',
        'amountPaid': 450000.0,
        'items': [
          {
            'productId': 'P1',
            'productName': 'Item 1',
            'quantity': 1,
            'price': 500000.0
          },
        ],
      };

      final om = OrderModel.fromMap(mapWithoutExplicitDiscount);
      expect(om.total, equals(500000.0));
      expect(om.discount, equals(50000.0));
    });
  });

  group(
      'R2. Sửa triệt để logic công nợ cho hóa đơn Đã hủy (Cancelled Invoices Debt)',
      () {
    test(
        'Order.remainingDebt is strictly 0.0 when isCancelled == true, regardless of debtAmount',
        () {
      final now = DateTime.now();

      // Even if debtAmount is 8.300.000, isCancelled must force remainingDebt to 0.0
      final cancelledWithExplicitDebt = Order(
        id: 'HD013123',
        customerId: 'KH006900',
        createdAt: now,
        items: const [],
        total: 8500000.0,
        discount: 200000.0,
        debtAmount: 8300000.0,
        amountPaid: 0.0,
        status: 'cancelled',
      );

      expect(cancelledWithExplicitDebt.isCancelled, isTrue);
      expect(cancelledWithExplicitDebt.remainingDebt, equals(0.0));
      expect(cancelledWithExplicitDebt.hasDebt, isFalse);
    });

    test(
        'Order.remainingDebt preserves debt for non-cancelled completed orders',
        () {
      final now = DateTime.now();

      final activeOrder = Order(
        id: 'HD_ACTIVE',
        customerId: 'KH001',
        createdAt: now,
        items: const [],
        total: 5000000.0,
        discount: 500000.0,
        debtAmount: 2500000.0,
        amountPaid: 2000000.0,
        status: 'completed',
      );

      expect(activeOrder.isCancelled, isFalse);
      expect(activeOrder.remainingDebt, equals(2500000.0));
      expect(activeOrder.hasDebt, isTrue);
    });
  });

  group(
      'R3. Kiểm tra và rà soát đồng bộ toàn bộ 100 hóa đơn Chi nhánh Thới Bình',
      () {
    final excelFile = File('DanhSachChiTietHoaDon_KV20092026-185010-522.xlsx');
    List<Order> parsedOrders = [];

    setUpAll(() {
      if (!excelFile.existsSync()) return;
      final bytes = excelFile.readAsBytesSync();
      parsedOrders =
          ExcelHelper.parseInvoices(bytes, defaultStoreId: 'store_002');
    });

    test(
        'All 100 invoices: exactly 59 with discount, Khách cần trả = Tổng tiền hàng - Giảm giá',
        () {
      if (!excelFile.existsSync()) return;
      expect(parsedOrders.length, equals(100));

      final discountedOrders =
          parsedOrders.where((o) => o.discount > 0.01).toList();
      expect(discountedOrders.length, equals(59),
          reason: 'Exactly 59 invoices have discount in Thới Bình');

      for (final order in parsedOrders) {
        final expectedNet =
            (order.total - order.discount).clamp(0.0, double.infinity);
        expect(order.netPayable, equals(expectedNet),
            reason:
                'Invoice ${order.id}: netPayable (${order.netPayable}) must equal total (${order.total}) - discount (${order.discount})');
        expect(
            order.netPayable < (order.total - order.discount - 0.01), isFalse,
            reason:
                'Invoice ${order.id} must NEVER have double discount deduction');
      }
    });

    test('All 6 cancelled invoices: remainingDebt == 0.0 and hasDebt == false',
        () {
      if (!excelFile.existsSync()) return;
      final cancelledOrders = parsedOrders.where((o) => o.isCancelled).toList();
      expect(cancelledOrders.length, equals(6),
          reason: 'Exactly 6 invoices are cancelled');

      final expectedCancelledIds = {
        'HD013218',
        'HD013204',
        'HD013201',
        'HD013146',
        'HD013144',
        'HD013123',
      };

      final actualCancelledIds = cancelledOrders.map((o) => o.id).toSet();
      expect(actualCancelledIds, equals(expectedCancelledIds),
          reason: 'The 6 cancelled invoices must match target IDs');

      for (final order in cancelledOrders) {
        expect(order.remainingDebt, equals(0.0),
            reason:
                'Cancelled invoice ${order.id} must have remainingDebt == 0.0');
        expect(order.debtAmount, equals(0.0),
            reason:
                'Cancelled invoice ${order.id} must have debtAmount == 0.0');
        expect(order.hasDebt, isFalse,
            reason:
                'Cancelled invoice ${order.id} must not report hasDebt == true');
      }
    });

    test(
        'Customer Anh Nghĩa (KH006900) does not have phantom debt from cancelled HD013123',
        () {
      if (!excelFile.existsSync() || parsedOrders.isEmpty) return;
      const customer = Customer(
        id: 'KH006900',
        name: 'Anh Nghĩa',
        phone: '0765029203',
        email: '',
        address: '',
        purchases: [],
        currentDebt: 9300000.0,
        // Matches replacement order HD013123_01
        totalSales: 10300000.0,
        netSales: 10300000.0,
      );

      final customerOrders =
          parsedOrders.where((o) => o.customerId == 'KH006900').toList();
      expect(customerOrders.length, equals(2),
          reason: 'KH006900 has HD013123 and HD013123_01');

      final effectiveDebt = customer.effectiveCurrentDebt(customerOrders, []);
      expect(effectiveDebt, equals(9300000.0),
          reason:
              'Customer debt must reflect only active order HD013123_01 (9.300.000đ), NOT including cancelled HD013123');

      final effectiveSales = customer.effectiveTotalSales(customerOrders);
      expect(effectiveSales, equals(10700000.0),
          reason:
              'Effective total sales must reflect gross total of active order HD013123_01');
    });

    testWidgets(
        'InvoicesPage UI: HD013123 bottom sheet displays Tổng tiền hàng 8.500.000đ, Giảm giá 200.000đ, Khách cần trả 8.300.000đ, Còn nợ 0đ',
        (tester) async {
      if (!excelFile.existsSync() || parsedOrders.isEmpty) return;
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

      // Search or filter by 'Đã hủy'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Đã hủy'));
      await tester.pumpAndSettle();

      // Find HD013123 in the list
      final hdTile = find.textContaining('HD013123');
      expect(hdTile, findsOneWidget);

      // Tap to open bottom sheet
      await tester.tap(hdTile);
      await tester.pumpAndSettle();

      // Verify bottom sheet content
      expect(find.text('Chi tiết hóa đơn đã hủy'), findsOneWidget);
      expect(find.text('Tổng tiền hàng'), findsOneWidget);
      expect(find.text('8.500.000 đ'), findsWidgets);
      expect(find.text('Giảm giá'), findsOneWidget);
      expect(find.text('200.000 đ'), findsOneWidget);
      expect(find.text('Khách cần trả'), findsOneWidget);
      expect(find.text('8.300.000 đ'), findsOneWidget);
      expect(find.text('Còn nợ'), findsOneWidget);
      expect(find.text('0 đ'),
          findsWidgets); // Both 'Đã thanh toán: 0 đ' and 'Còn nợ: 0 đ'
      expect(find.text('Không áp dụng (Đã hủy)'), findsOneWidget);

      // Verify no debt collection button is present
      expect(find.textContaining('Thu nợ'), findsNothing);
    });
  });
}
