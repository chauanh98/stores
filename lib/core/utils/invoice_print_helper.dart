import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:stores/core/theme/app_colors.dart';

import '../../domain/entities/customer.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/store_payment_config.dart';
import 'vietqr_helper.dart';

class InvoicePrintHelper {
  /// Tạo tài liệu PDF Hóa Đơn Bán Hàng dựa trên thông tin Đơn hàng và Cấu hình Cửa hàng
  static Future<Uint8List> buildPdf({
    required Order order,
    Customer? customer,
    required StorePaymentConfig config,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    final subtotal = order.items.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
    final discount = (subtotal - order.total) > 0.5 ? (subtotal - order.total) : 0.0;
    final remainingAmount = (order.total - order.amountPaid).clamp(0.0, double.infinity);

    final customerName = customer?.name ?? (order.customerId == 'khach_le' || order.customerId.isEmpty ? 'Khách lẻ' : order.customerId);
    final customerCode = customer?.id ?? (order.customerId == 'khach_le' ? '' : order.customerId);
    final customerPhone = customer?.phone ?? '';
    final customerAddress = customer?.address ?? '';

    // Tạo VietQR Quick Link URL
    final qrUrl = VietQRHelper.buildVietQRImageUrl(
      bankId: config.bankId,
      accountNo: config.accountNo,
      accountName: config.accountName,
      amount: remainingAmount > 0 ? remainingAmount : order.total,
      addInfo: order.id,
    );

    pw.ImageProvider? qrImage;
    try {
      qrImage = await networkImage(qrUrl);
    } catch (_) {
      // Bỏ qua nếu lỗi nạp ảnh QR mạng
    }

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 1. HEADER SECTION
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Mã đơn hàng góc trái
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Mã đơn: ${order.id}',
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tên Shop & Thông tin liên hệ giữa
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          config.storeName,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 14,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Địa chỉ: ${config.address}',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(font: font, fontSize: 9),
                        ),
                        pw.Text(
                          'SĐT: ${config.phone}',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(font: font, fontSize: 9),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '${config.accountNo} - ${config.bankName} - ${config.accountName}',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(font: fontBold, fontSize: 8),
                        ),
                      ],
                    ),
                  ),

                  // Mã QR ngân hàng góc phải
                  pw.Expanded(
                    flex: 2,
                    child: pw.Align(
                      alignment: pw.Alignment.topRight,
                      child: qrImage != null
                          ? pw.Image(qrImage, width: 70, height: 70)
                          : pw.Container(
                              width: 70,
                              height: 70,
                              decoration: pw.BoxDecoration(
                                border: pw.Border.all(color: PdfColors.grey),
                              ),
                              child: pw.Center(
                                child: pw.Text(
                                  'QR Payment',
                                  textAlign: pw.TextAlign.center,
                                  style: pw.TextStyle(font: font, fontSize: 8),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 12),

              // 2. TITLE
              pw.Center(
                child: pw.Text(
                  'HÓA ĐƠN BÁN HÀNG',
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 16,
                  ),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(
                  dateFormat.format(order.createdAt),
                  style: pw.TextStyle(font: font, fontSize: 10),
                ),
              ),

              pw.SizedBox(height: 12),

              // 3. KHÁCH HÀNG
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Khách hàng: $customerName',
                      style: pw.TextStyle(font: fontBold, fontSize: 10)),
                  if (customerCode.isNotEmpty)
                    pw.Text('Mã KH: $customerCode',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                ],
              ),
              if (customerPhone.isNotEmpty)
                pw.Text('SĐT: $customerPhone',
                    style: pw.TextStyle(font: font, fontSize: 10)),
              if (customerAddress.isNotEmpty)
                pw.Text('Địa chỉ: $customerAddress',
                    style: pw.TextStyle(font: font, fontSize: 10)),

              pw.SizedBox(height: 10),

              // 4. BẢNG CHI TIẾT SẢN PHẨM
              pw.TableHelper.fromTextArray(
                context: context,
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                headerStyle: pw.TextStyle(font: fontBold, fontSize: 9),
                cellStyle: pw.TextStyle(font: font, fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                columnWidths: {
                  0: const pw.FixedColumnWidth(25), // TT
                  1: const pw.FlexColumnWidth(4),   // Tên hàng
                  2: const pw.FixedColumnWidth(35), // SL
                  3: const pw.FlexColumnWidth(2),   // Đơn giá
                  4: const pw.FlexColumnWidth(2),   // Thành tiền
                },
                cellAlignment: pw.Alignment.centerLeft,
                headers: <String>['TT', 'Tên hàng', 'SL', 'Đơn giá', 'Thành tiền'],
                data: List<List<String>>.generate(order.items.length, (index) {
                  final item = order.items[index];
                  return [
                    '${index + 1}',
                    item.productName,
                    '${item.quantity}',
                    currencyFormat.format(item.price),
                    currencyFormat.format(item.price * item.quantity),
                  ];
                }),
              ),

              pw.SizedBox(height: 10),

              // 5. PHẦN TỔNG KẾT & CÒN LẠI
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'Ghi chú:',
                      style: pw.TextStyle(font: font, fontSize: 9),
                    ),
                  ),
                  pw.Container(
                    width: 220,
                    child: pw.Column(
                      children: [
                        if (discount > 0) ...[
                          _buildSummaryPdfRow('Tổng cộng:',
                              '${currencyFormat.format(subtotal)} đ', font),
                          pw.SizedBox(height: 2),
                          _buildSummaryPdfRow('Giảm giá:',
                              '${currencyFormat.format(discount)} đ', font),
                          pw.SizedBox(height: 2),
                          _buildSummaryPdfRow('Sau giảm:',
                              '${currencyFormat.format(order.total)} đ', fontBold),
                        ] else ...[
                          _buildSummaryPdfRow('Tổng cộng:',
                              '${currencyFormat.format(order.total)} đ', fontBold),
                        ],
                        pw.SizedBox(height: 2),
                        _buildSummaryPdfRow('Đã thanh toán:',
                            '${currencyFormat.format(order.amountPaid)} đ', font),
                        pw.SizedBox(height: 2),
                        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                        _buildSummaryPdfRow('Còn lại:',
                            '${currencyFormat.format(remainingAmount)} đ', fontBold,
                            fontSize: 11),
                      ],
                    ),
                  ),
                ],
              ),

              pw.Spacer(),

              // 6. FOOTER BẢO HÀNH
              pw.Center(
                child: pw.Text(
                  config.footerNote,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildSummaryPdfRow(
    String label,
    String value,
    pw.Font font, {
    double fontSize = 9,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: fontSize)),
        pw.Text(value, style: pw.TextStyle(font: font, fontSize: fontSize)),
      ],
    );
  }

  /// In trực tiếp hoặc xem trước hóa đơn qua hộp thoại in của hệ thống
  static Future<void> printInvoice(
    BuildContext context,
    Order order,
    Customer? customer,
    StorePaymentConfig config,
  ) async {
    // Hiển thị dialog Loading ngăn người dùng bấm thao tác khác
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text(
                    'Đang khởi tạo hóa đơn...',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final pdfBytes = await buildPdf(
        order: order,
        customer: customer,
        config: config,
      );

      // Đóng dialog loading trước khi mở giao diện in
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'HoaDon_${order.id}',
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi khởi tạo hóa đơn: $e')),
        );
      }
    }
  }

  /// Chia sẻ hoặc xuất file PDF hóa đơn
  static Future<void> shareInvoice(
    BuildContext context,
    Order order,
    Customer? customer,
    StorePaymentConfig config,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text(
                    'Đang tạo file PDF...',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final pdfBytes = await buildPdf(
        order: order,
        customer: customer,
        config: config,
      );

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'HoaDon_${order.id}.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất file PDF: $e')),
        );
      }
    }
  }
}
