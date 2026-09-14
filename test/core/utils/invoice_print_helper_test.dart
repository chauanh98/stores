import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:stores/core/utils/invoice_print_helper.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/store_payment_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InvoicePrintHelper Tests', () {
    final sampleOrder = Order(
      id: 'HD000001',
      customerId: 'KH000001',
      createdAt: DateTime(2026, 8, 19, 10, 30),
      items: [
        OrderItem(
          productId: 'SP001',
          productName: 'Bàn làm việc gỗ sồi',
          quantity: 2,
          price: 1200000.0,
          warrantyMonths: 12,
          purchaseDate: DateTime(2026, 8, 19),
        ),
        OrderItem(
          productId: 'SP002',
          productName: 'Ghế xoay văn phòng',
          quantity: 1,
          price: 600000.0,
          warrantyMonths: 6,
          purchaseDate: DateTime(2026, 8, 19),
        ),
      ],
      total: 2900000.0, // 2*1.2M + 600k = 3M, discount 100k
      amountPaid: 2000000.0,
      debtAmount: 900000.0,
      paymentMethod: 'split',
      cashAmount: 1000000.0,
      transferAmount: 1000000.0,
      note: 'Giao hàng trước 5h chiều',
    );

    const sampleCustomer = Customer(
      id: 'KH000001',
      name: 'Nguyễn Văn Minh',
      phone: '0901234567',
      email: 'minh@example.com',
      address: 'Ninh Kiều, Cần Thơ',
      purchases: [],
    );

    const baseConfig = StorePaymentConfig(
      storeId: 'store_001',
      storeName: 'NỘI THẤT CAO CẤP KHÁNH ĐĂNG',
      address: 'Chợ Cờ Đỏ, Cần Thơ',
      phone: '0917.865 300',
      bankName: 'VIETINBANK',
      bankId: 'vietinbank',
      accountNo: '0917865300',
      accountName: 'Huỳnh Lê Khánh Đăng',
      footerNote: 'HÀNG ĐẢM BẢO ĐÚNG CHẤT LƯỢNG',
    );

    test('buildPdf generates valid PDF bytes for K80 roll format', () async {
      final configK80 = baseConfig.copyWith(paperSize: 'k80', showVietQR: true);

      final pdfBytes = await InvoicePrintHelper.buildPdf(
        order: sampleOrder,
        customer: sampleCustomer,
        config: configK80,
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('buildPdf generates valid PDF bytes for K58 roll format', () async {
      final configK58 = baseConfig.copyWith(paperSize: 'k58', showVietQR: true);

      final pdfBytes = await InvoicePrintHelper.buildPdf(
        order: sampleOrder,
        customer: sampleCustomer,
        config: configK58,
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('buildPdf generates valid PDF bytes for A4 standard format', () async {
      final configA4 = baseConfig.copyWith(paperSize: 'a4', showVietQR: true);

      final pdfBytes = await InvoicePrintHelper.buildPdf(
        order: sampleOrder,
        customer: sampleCustomer,
        config: configA4,
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('buildPdf with showVietQR=false generates PDF without throwing', () async {
      final configNoQR = baseConfig.copyWith(paperSize: 'k80', showVietQR: false);

      final pdfBytes = await InvoicePrintHelper.buildPdf(
        order: sampleOrder,
        customer: sampleCustomer,
        config: configNoQR,
      );

      expect(pdfBytes, isNotEmpty);
    });

    test('buildPdf with explicit pageFormat parameter override', () async {
      final pdfBytes = await InvoicePrintHelper.buildPdf(
        order: sampleOrder,
        customer: sampleCustomer,
        config: baseConfig,
        pageFormat: PdfPageFormat.a4,
      );

      expect(pdfBytes, isNotEmpty);
    });

    test('buildPdf handles retail customer without phone/address gracefully', () async {
      final retailOrder = Order(
        id: 'HD000002',
        customerId: 'khach_le',
        createdAt: DateTime(2026, 8, 19, 11, 0),
        items: [
          OrderItem(
            productId: 'SP003',
            productName: 'Ly thủy tinh cao cấp',
            quantity: 1,
            price: 50000.0,
            warrantyMonths: 0,
            purchaseDate: DateTime(2026, 8, 19),
          ),
        ],
        total: 50000.0,
        amountPaid: 50000.0,
        paymentMethod: 'cash',
      );

      final pdfBytes = await InvoicePrintHelper.buildPdf(
        order: retailOrder,
        customer: null,
        config: baseConfig.copyWith(paperSize: 'k58'),
      );

      expect(pdfBytes, isNotEmpty);
    });
  });
}
