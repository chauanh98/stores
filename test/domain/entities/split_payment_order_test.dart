import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/invoice_print_helper.dart';
import 'package:stores/data/models/order_model.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/store_payment_config.dart';

void main() {
  group('Split Payment & Order Notes Tests', () {
    final testDate = DateTime(2026, 8, 19, 10, 0);
    final testItems = [
      OrderItem(
        productId: 'prod_1',
        productName: 'iPhone 17 Pro Max',
        quantity: 1,
        price: 34000000,
        warrantyMonths: 12,
        purchaseDate: testDate,
      ),
      OrderItem(
        productId: 'prod_2',
        productName: 'Củ sạc nhanh 30W',
        quantity: 1,
        price: 500000,
        warrantyMonths: 12,
        purchaseDate: testDate,
      ),
    ];

    test('Order entity supports split payment fields and note', () {
      final order = Order(
        id: 'HD000099',
        customerId: 'khach_le',
        createdAt: testDate,
        items: testItems,
        total: 34500000,
        status: 'completed',
        amountPaid: 34500000,
        debtAmount: 0,
        paymentMethod: 'split',
        cashAmount: 14500000,
        transferAmount: 20000000,
        note: 'Khách yêu cầu hóa đơn VAT',
        storeId: 'store_001',
      );

      expect(order.id, 'HD000099');
      expect(order.paymentMethod, 'split');
      expect(order.cashAmount, 14500000.0);
      expect(order.transferAmount, 20000000.0);
      expect(order.note, 'Khách yêu cầu hóa đơn VAT');
      expect(order.amountPaid, 34500000.0);
      expect(order.remainingDebt, 0.0);

      // copyWith test
      final updated = order.copyWith(
        cashAmount: 10000000,
        transferAmount: 24500000,
        note: 'Đã xuất VAT',
      );
      expect(updated.cashAmount, 10000000.0);
      expect(updated.transferAmount, 24500000.0);
      expect(updated.note, 'Đã xuất VAT');
    });

    test('OrderModel toMap and fromMap serialization preserves split payment and note', () {
      final model = OrderModel(
        id: 'HD000100',
        customerId: 'CUST_VIP',
        createdAt: testDate,
        items: [],
        total: 5000000,
        status: 'completed',
        amountPaid: 5000000,
        debtAmount: 0,
        paymentMethod: 'split',
        cashAmount: 2000000,
        transferAmount: 3000000,
        note: 'Giao hàng sau 17h',
        storeId: 'store_002',
      );

      final map = model.toMap();
      expect(map['id'], 'HD000100');
      expect(map['paymentMethod'], 'split');
      expect(map['cashAmount'], 2000000.0);
      expect(map['transferAmount'], 3000000.0);
      expect(map['note'], 'Giao hàng sau 17h');

      final deserialized = OrderModel.fromMap(map);
      expect(deserialized.id, 'HD000100');
      expect(deserialized.paymentMethod, 'split');
      expect(deserialized.cashAmount, 2000000.0);
      expect(deserialized.transferAmount, 3000000.0);
      expect(deserialized.note, 'Giao hàng sau 17h');
      expect(deserialized.storeId, 'store_002');
    });

    test('InvoicePrintHelper.buildPdf builds PDF with split payment and note without error', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final order = Order(
        id: 'HD_PRINT_TEST',
        customerId: 'khach_le',
        createdAt: testDate,
        items: testItems,
        total: 34500000,
        status: 'completed',
        amountPaid: 34500000,
        debtAmount: 0,
        paymentMethod: 'split',
        cashAmount: 14500000,
        transferAmount: 20000000,
        note: 'Khách quen chi nhánh Đông Thắng',
      );

      const config = StorePaymentConfig(
        storeId: 'store_001',
        storeName: 'Cửa hàng Đông Thắng',
        address: '123 Đông Thắng',
        phone: '0901234567',
        bankName: 'Vietcombank',
        bankId: 'vietcombank',
        accountNo: '123456789',
        accountName: 'NGUYEN VAN A',
        footerNote: 'Cảm ơn quý khách và hẹn gặp lại!',
      );

      final pdfBytes = await InvoicePrintHelper.buildPdf(
        order: order,
        config: config,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(0));
    });
  });
}
