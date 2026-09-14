import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/presentation/orders/widgets/return_order_detail_bottom_sheet.dart';

Widget _buildTestApp({required Widget child}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  final testDate = DateTime(2026, 8, 20, 15, 30);

  const customer = Customer(
    id: 'CUST_VIP_1',
    name: 'Trần Văn Nam',
    phone: '0988776655',
    email: 'nam@example.com',
    address: 'Hà Nội',
    purchases: [],
  );

  final order = Order(
    id: 'HD000099',
    customerId: 'CUST_VIP_1',
    createdAt: testDate,
    items: [
      OrderItem(
        productId: 'P_KEYBOARD',
        productName: 'Bàn phím không dây MX Keys',
        quantity: 2,
        price: 2500000.0,
        warrantyMonths: 12,
        purchaseDate: testDate,
        returnedQuantity: 1,
      ),
      OrderItem(
        productId: 'P_MOUSE',
        productName: 'Chuột Logitech MX Master 3S',
        quantity: 1,
        price: 2000000.0,
        warrantyMonths: 24,
        purchaseDate: testDate,
        returnedQuantity: 1,
      ),
    ],
    total: 2500000.0,
    amountPaid: 2500000.0,
    debtAmount: 0.0,
    status: 'completed',
    paymentMethod: 'transfer',
    createdBy: 'staff_01',
    createdByName: 'Nguyễn Thuỳ Dung',
  );

  final returnOrder = ReturnOrder(
    id: 'TH_20260820_001',
    orderId: 'HD000099',
    customerId: 'CUST_VIP_1',
    storeId: 'store_001',
    createdAt: testDate.add(const Duration(hours: 2)),
    items: const [
      ReturnOrderItem(
        productId: 'P_KEYBOARD',
        productName: 'Bàn phím không dây MX Keys',
        price: 2500000.0,
        quantity: 1,
        unit: 'cái',
      ),
      ReturnOrderItem(
        productId: 'P_MOUSE',
        productName: 'Chuột Logitech MX Master 3S',
        price: 2000000.0,
        quantity: 1,
        unit: 'cái',
      ),
    ],
    totalReturnAmount: 4500000.0,
    debtDeducted: 1000000.0,
    cashRefunded: 3500000.0,
    reason: 'Sản phẩm không phù hợp nhu cầu',
    createdBy: 'staff_01',
    createdByName: 'Nguyễn Thuỳ Dung',
    refundPaymentMethod: 'transfer',
  );

  group('ReturnOrderDetailBottomSheet Widget Tests', () {
    testWidgets('Displays complete return order details and breakdown',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: ReturnOrderDetailBottomSheet(
            order: order,
            returnOrder: returnOrder,
            customer: customer,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header & Status
      expect(find.text('Phiếu trả hàng: TH_20260820_001'), findsOneWidget);
      expect(find.text('Đã hoàn tiền'), findsOneWidget);

      // Linked invoice
      expect(find.text('Hóa đơn gốc: #HD000099'), findsOneWidget);
      expect(find.text('Khách hàng: Trần Văn Nam'), findsOneWidget);
      expect(find.byKey(const Key('view_original_invoice_button')),
          findsOneWidget);

      // Returned Items
      expect(find.text('Bàn phím không dây MX Keys'), findsOneWidget);
      expect(find.text('Chuột Logitech MX Master 3S'), findsOneWidget);
      expect(find.text('1 cái x 2.500.000 đ'), findsOneWidget);
      expect(find.text('1 cái x 2.000.000 đ'), findsOneWidget);

      // Financial breakdown
      expect(find.text('Tổng tiền hàng trả'), findsOneWidget);
      expect(find.text('4.500.000 đ'), findsWidgets);
      expect(find.text('Cấn trừ công nợ'), findsOneWidget);
      expect(find.text('- 1.000.000 đ'), findsOneWidget);
      expect(find.text('Tiền hoàn lại cho khách'), findsOneWidget);
      expect(find.text('3.500.000 đ'), findsOneWidget);
      expect(find.text('Chuyển khoản'), findsOneWidget);

      // Metadata
      expect(find.text('Sản phẩm không phù hợp nhu cầu'), findsOneWidget);
      expect(find.text('Nguyễn Thuỳ Dung'), findsOneWidget);
    });

    testWidgets('Triggers onViewOriginalInvoice callbacks correctly',
        (tester) async {
      bool viewInvoiceCallbackCalled = false;

      await tester.pumpWidget(
        _buildTestApp(
          child: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  ReturnOrderDetailBottomSheet.show(
                    context,
                    order: order,
                    returnOrder: returnOrder,
                    customer: customer,
                    onViewOriginalInvoice: () {
                      viewInvoiceCallbackCalled = true;
                    },
                  );
                },
                child: const Text('Mở phiếu trả hàng'),
              );
            },
          ),
        ),
      );

      // Tap open button
      await tester.tap(find.text('Mở phiếu trả hàng'));
      await tester.pumpAndSettle();

      expect(find.text('Phiếu trả hàng: TH_20260820_001'), findsOneWidget);

      // Tap on 'Xem chi tiết' button on linked invoice card
      await tester.tap(find.byKey(const Key('view_original_invoice_button')));
      await tester.pumpAndSettle();

      expect(viewInvoiceCallbackCalled, true);
    });

    testWidgets('Fallbacks to Order items when ReturnOrder is not provided',
        (tester) async {
      final fullyReturnedOrder = Order(
        id: 'HD000088',
        customerId: 'khach_le',
        createdAt: testDate,
        items: [
          OrderItem(
            productId: 'P_CASE',
            productName: 'Vỏ case máy tính Mini ITX',
            quantity: 1,
            price: 1800000.0,
            warrantyMonths: 12,
            purchaseDate: testDate,
            returnedQuantity: 1,
          ),
        ],
        total: 0.0,
        amountPaid: 0.0,
        debtAmount: 0.0,
        status: 'returned',
        createdBy: 'admin',
        createdByName: 'Quản trị viên',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: ReturnOrderDetailBottomSheet(
            order: fullyReturnedOrder,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Phiếu trả hàng: TH_HD000088'), findsOneWidget);
      expect(find.text('Hóa đơn gốc: #HD000088'), findsOneWidget);
      expect(find.text('Khách hàng: Khách lẻ'), findsOneWidget);
      expect(find.text('Vỏ case máy tính Mini ITX'), findsOneWidget);
      expect(find.text('1 cái x 1.800.000 đ'), findsOneWidget);
      expect(find.text('1.800.000 đ'), findsWidgets);
    });

    testWidgets('Renders without overflow on narrow 320px screen',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: ReturnOrderDetailBottomSheet(
            order: order,
            returnOrder: returnOrder,
            customer: customer,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Phiếu trả hàng: TH_20260820_001'), findsOneWidget);
      expect(find.text('Tổng tiền hàng trả'), findsOneWidget);
      expect(find.text('Tiền hoàn lại cho khách'), findsOneWidget);
      expect(find.text('Hình thức hoàn tiền'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
