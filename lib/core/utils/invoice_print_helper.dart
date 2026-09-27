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
  /// Tạo tài liệu PDF Hóa Đơn Bán Hàng dựa trên thông tin Đơn hàng và Cấu hình Cửa hàng.
  /// Nếu không truyền `pageFormat`, định dạng sẽ tự động phân giải từ `config.resolvedPageFormat`.
  static Future<Uint8List> buildPdf({
    required Order order,
    Customer? customer,
    required StorePaymentConfig config,
    PdfPageFormat? pageFormat,
  }) async {
    final effectiveFormat = pageFormat ?? config.resolvedPageFormat;
    final doc = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    final subtotal = order.items
        .fold(0.0, (sum, item) => sum + (item.price * item.quantity));
    final discount =
        (subtotal - order.total) > 0.5 ? (subtotal - order.total) : 0.0;
    final remainingAmount =
        (order.total - order.amountPaid).clamp(0.0, double.infinity);

    final customerName = customer?.name ??
        (order.customerId == 'khach_le' || order.customerId.isEmpty
            ? 'Khách lẻ'
            : order.customerId);
    final customerCode = customer?.id ??
        (order.customerId == 'khach_le' ? '' : order.customerId);
    final customerPhone = customer?.phone ?? '';
    final customerAddress = customer?.address ?? '';

    // Tạo VietQR Image nếu được kích hoạt
    pw.ImageProvider? qrImage;
    if (config.showVietQR) {
      try {
        final qrUrl = VietQRHelper.buildVietQRImageUrl(
          bankId: config.bankId,
          accountNo: config.accountNo,
          accountName: config.accountName,
          amount: remainingAmount > 0 ? remainingAmount : order.total,
          addInfo: order.id,
        );
        qrImage = await networkImage(qrUrl);
      } catch (_) {
        // Fallback an toàn nếu lỗi mạng/offline hoặc trong test
      }
    }

    if (effectiveFormat == PdfPageFormat.a4) {
      _buildA4Pdf(
        doc: doc,
        pageFormat: effectiveFormat,
        order: order,
        customerName: customerName,
        customerCode: customerCode,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        config: config,
        font: font,
        fontBold: fontBold,
        currencyFormat: currencyFormat,
        dateFormat: dateFormat,
        subtotal: subtotal,
        discount: discount,
        remainingAmount: remainingAmount,
        qrImage: qrImage,
      );
    } else if (effectiveFormat == PdfPageFormat.roll57) {
      _buildK58Pdf(
        doc: doc,
        pageFormat: effectiveFormat,
        order: order,
        customerName: customerName,
        customerCode: customerCode,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        config: config,
        font: font,
        fontBold: fontBold,
        currencyFormat: currencyFormat,
        dateFormat: dateFormat,
        subtotal: subtotal,
        discount: discount,
        remainingAmount: remainingAmount,
        qrImage: qrImage,
      );
    } else {
      // Mặc định hoặc K80 (PdfPageFormat.roll80)
      _buildK80Pdf(
        doc: doc,
        pageFormat: effectiveFormat,
        order: order,
        customerName: customerName,
        customerCode: customerCode,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        config: config,
        font: font,
        fontBold: fontBold,
        currencyFormat: currencyFormat,
        dateFormat: dateFormat,
        subtotal: subtotal,
        discount: discount,
        remainingAmount: remainingAmount,
        qrImage: qrImage,
      );
    }

    return doc.save();
  }

  /// Bố cục Khổ A4 (Trang in tiêu chuẩn 3 cột header)
  static void _buildA4Pdf({
    required pw.Document doc,
    required PdfPageFormat pageFormat,
    required Order order,
    required String customerName,
    required String customerCode,
    required String customerPhone,
    required String customerAddress,
    required StorePaymentConfig config,
    required pw.Font font,
    required pw.Font fontBold,
    required NumberFormat currencyFormat,
    required DateFormat dateFormat,
    required double subtotal,
    required double discount,
    required double remainingAmount,
    required pw.ImageProvider? qrImage,
  }) {
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 1. HEADER SECTION (3 cột)
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
                          style: pw.TextStyle(font: fontBold, fontSize: 10),
                        ),
                        pw.Text(
                          dateFormat.format(order.createdAt),
                          style: pw.TextStyle(font: font, fontSize: 8),
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
                          style: pw.TextStyle(font: fontBold, fontSize: 14),
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
                        if (config.accountNo.isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            '${config.accountNo} - ${config.bankName} - ${config.accountName}',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(font: fontBold, fontSize: 8),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Mã QR ngân hàng góc phải (nếu showVietQR == true)
                  pw.Expanded(
                    flex: 2,
                    child: config.showVietQR
                        ? pw.Align(
                            alignment: pw.Alignment.topRight,
                            child: qrImage != null
                                ? pw.Image(qrImage, width: 70, height: 70)
                                : pw.Container(
                                    width: 70,
                                    height: 70,
                                    decoration: pw.BoxDecoration(
                                      border:
                                          pw.Border.all(color: PdfColors.grey),
                                    ),
                                    child: pw.Center(
                                      child: pw.Text(
                                        'VietQR Payment',
                                        textAlign: pw.TextAlign.center,
                                        style: pw.TextStyle(
                                            font: font, fontSize: 8),
                                      ),
                                    ),
                                  ),
                          )
                        : pw.SizedBox(width: 70),
                  ),
                ],
              ),

              pw.SizedBox(height: 12),

              // 2. TITLE
              pw.Center(
                child: pw.Text(
                  'HÓA ĐƠN BÁN HÀNG',
                  style: pw.TextStyle(font: fontBold, fontSize: 16),
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
                border:
                    pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                headerStyle: pw.TextStyle(font: fontBold, fontSize: 9),
                cellStyle: pw.TextStyle(font: font, fontSize: 9),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                columnWidths: {
                  0: const pw.FixedColumnWidth(25), // TT
                  1: const pw.FlexColumnWidth(4), // Tên hàng
                  2: const pw.FixedColumnWidth(35), // SL
                  3: const pw.FlexColumnWidth(2), // Đơn giá
                  4: const pw.FlexColumnWidth(2), // Thành tiền
                },
                cellAlignment: pw.Alignment.centerLeft,
                headers: <String>[
                  'TT',
                  'Tên hàng',
                  'SL',
                  'Đơn giá',
                  'Thành tiền'
                ],
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
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (order.note != null &&
                            order.note!.trim().isNotEmpty) ...[
                          pw.Text(
                            'Ghi chú: ${order.note!.trim()}',
                            style: pw.TextStyle(font: font, fontSize: 9),
                          ),
                          pw.SizedBox(height: 4),
                        ],
                        pw.Text(
                          'Phương thức TT: ${_getPaymentMethodLabel(order)}',
                          style: pw.TextStyle(font: font, fontSize: 9),
                        ),
                      ],
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
                          _buildSummaryPdfRow(
                              'Sau giảm:',
                              '${currencyFormat.format(order.total)} đ',
                              fontBold),
                        ] else ...[
                          _buildSummaryPdfRow(
                              'Tổng cộng:',
                              '${currencyFormat.format(order.total)} đ',
                              fontBold),
                        ],
                        pw.SizedBox(height: 2),
                        _buildSummaryPdfRow(
                            'Đã thanh toán:',
                            '${currencyFormat.format(order.amountPaid)} đ',
                            font),
                        if (order.paymentMethod == 'split') ...[
                          pw.SizedBox(height: 1),
                          _buildSummaryPdfRow(
                              '  - Tiền mặt:',
                              '${currencyFormat.format(order.cashAmount ?? 0.0)} đ',
                              font,
                              fontSize: 8),
                          pw.SizedBox(height: 1),
                          _buildSummaryPdfRow(
                              '  - Chuyển khoản:',
                              '${currencyFormat.format(order.transferAmount ?? 0.0)} đ',
                              font,
                              fontSize: 8),
                        ],
                        pw.SizedBox(height: 2),
                        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                        _buildSummaryPdfRow(
                            'Còn lại:',
                            '${currencyFormat.format(remainingAmount)} đ',
                            fontBold,
                            fontSize: 11),
                      ],
                    ),
                  ),
                ],
              ),

              pw.Spacer(),

              // 6. FOOTER
              pw.Center(
                child: pw.Text(
                  config.footerNote,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: fontBold, fontSize: 9),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Bố cục Khổ K80 (Cuộn nhiệt 80mm - Single Column Vertical Ticket)
  static void _buildK80Pdf({
    required pw.Document doc,
    required PdfPageFormat pageFormat,
    required Order order,
    required String customerName,
    required String customerCode,
    required String customerPhone,
    required String customerAddress,
    required StorePaymentConfig config,
    required pw.Font font,
    required pw.Font fontBold,
    required NumberFormat currencyFormat,
    required DateFormat dateFormat,
    required double subtotal,
    required double discount,
    required double remainingAmount,
    required pw.ImageProvider? qrImage,
  }) {
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header Cửa Hàng
              pw.Center(
                child: pw.Text(
                  config.storeName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: fontBold, fontSize: 11),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(
                  config.address,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: font, fontSize: 8),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'Hotline: ${config.phone}',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: font, fontSize: 8),
                ),
              ),
              if (config.accountNo.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    '${config.bankName} - ${config.accountNo} - ${config.accountName}',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: fontBold, fontSize: 7.5),
                  ),
                ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.5, color: PdfColors.grey500),

              // Tiêu đề Hóa đơn
              pw.Center(
                child: pw.Text(
                  'HÓA ĐƠN BÁN HÀNG',
                  style: pw.TextStyle(font: fontBold, fontSize: 13),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'Số HĐ: ${order.id} | ${dateFormat.format(order.createdAt)}',
                  style: pw.TextStyle(font: font, fontSize: 8),
                ),
              ),
              pw.SizedBox(height: 4),

              // Thông tin Khách hàng
              pw.Text('Khách hàng: $customerName',
                  style: pw.TextStyle(font: fontBold, fontSize: 8.5)),
              if (customerPhone.isNotEmpty)
                pw.Text('SĐT: $customerPhone',
                    style: pw.TextStyle(font: font, fontSize: 8)),
              if (customerAddress.isNotEmpty)
                pw.Text('Địa chỉ: $customerAddress',
                    style: pw.TextStyle(font: font, fontSize: 8)),
              pw.SizedBox(height: 6),

              // Bảng món hàng
              pw.TableHelper.fromTextArray(
                context: context,
                border:
                    pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                headerStyle: pw.TextStyle(font: fontBold, fontSize: 8),
                cellStyle: pw.TextStyle(font: font, fontSize: 7.5),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                columnWidths: {
                  0: const pw.FixedColumnWidth(16), // TT
                  1: const pw.FlexColumnWidth(3.5), // Tên hàng
                  2: const pw.FixedColumnWidth(20), // SL
                  3: const pw.FlexColumnWidth(2.2), // Đơn giá
                  4: const pw.FlexColumnWidth(2.3), // Thành tiền
                },
                headers: <String>['TT', 'Tên hàng', 'SL', 'Đ.Giá', 'T.Tiền'],
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
              pw.SizedBox(height: 6),

              // Tổng kết thanh toán
              if (discount > 0) ...[
                _buildSummaryPdfRow('Tổng tiền hàng:',
                    '${currencyFormat.format(subtotal)} đ', font,
                    fontSize: 8),
                pw.SizedBox(height: 2),
                _buildSummaryPdfRow(
                    'Giảm giá:', '-${currencyFormat.format(discount)} đ', font,
                    fontSize: 8),
                pw.SizedBox(height: 2),
                _buildSummaryPdfRow('Khách cần trả:',
                    '${currencyFormat.format(order.total)} đ', fontBold,
                    fontSize: 9),
              ] else ...[
                _buildSummaryPdfRow('Tổng cộng:',
                    '${currencyFormat.format(order.total)} đ', fontBold,
                    fontSize: 9),
              ],
              pw.SizedBox(height: 2),
              _buildSummaryPdfRow('Đã thanh toán:',
                  '${currencyFormat.format(order.amountPaid)} đ', font,
                  fontSize: 8),
              if (order.paymentMethod == 'split') ...[
                pw.SizedBox(height: 1),
                _buildSummaryPdfRow('  - Tiền mặt:',
                    '${currencyFormat.format(order.cashAmount ?? 0.0)} đ', font,
                    fontSize: 7.5),
                pw.SizedBox(height: 1),
                _buildSummaryPdfRow(
                    '  - Chuyển khoản:',
                    '${currencyFormat.format(order.transferAmount ?? 0.0)} đ',
                    font,
                    fontSize: 7.5),
              ],
              pw.SizedBox(height: 2),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              _buildSummaryPdfRow('Còn nợ:',
                  '${currencyFormat.format(remainingAmount)} đ', fontBold,
                  fontSize: 9.5),

              if (order.note != null && order.note!.trim().isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text('Ghi chú: ${order.note!.trim()}',
                    style: pw.TextStyle(font: font, fontSize: 7.5)),
              ],

              // VietQR nếu được bật
              if (config.showVietQR) ...[
                pw.SizedBox(height: 8),
                pw.Center(
                  child: qrImage != null
                      ? pw.Image(qrImage, width: 85, height: 85)
                      : pw.Container(
                          width: 85,
                          height: 85,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.grey),
                          ),
                          child: pw.Center(
                            child: pw.Text('VietQR Payment',
                                style: pw.TextStyle(font: font, fontSize: 7.5)),
                          ),
                        ),
                ),
                pw.SizedBox(height: 2),
                pw.Center(
                  child: pw.Text(
                    'Quét mã VietQR để thanh toán',
                    style: pw.TextStyle(font: font, fontSize: 7.5),
                  ),
                ),
                if (config.bankName.isNotEmpty)
                  pw.Center(
                    child: pw.Text(
                      '${config.bankName} - ${config.accountNo}',
                      style: pw.TextStyle(font: fontBold, fontSize: 7.5),
                    ),
                  ),
              ],

              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.5, color: PdfColors.grey500),
              pw.Center(
                child: pw.Text(
                  config.footerNote,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: fontBold, fontSize: 7.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Bố cục Khổ K58 (Cuộn nhiệt compact 58mm)
  static void _buildK58Pdf({
    required pw.Document doc,
    required PdfPageFormat pageFormat,
    required Order order,
    required String customerName,
    required String customerCode,
    required String customerPhone,
    required String customerAddress,
    required StorePaymentConfig config,
    required pw.Font font,
    required pw.Font fontBold,
    required NumberFormat currencyFormat,
    required DateFormat dateFormat,
    required double subtotal,
    required double discount,
    required double remainingAmount,
    required pw.ImageProvider? qrImage,
  }) {
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header Cửa hàng
              pw.Center(
                child: pw.Text(
                  config.storeName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: fontBold, fontSize: 9.5),
                ),
              ),
              pw.SizedBox(height: 1),
              pw.Center(
                child: pw.Text(
                  '${config.address} - ${config.phone}',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: font, fontSize: 7),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Divider(thickness: 0.5, color: PdfColors.grey500),

              // Tiêu đề
              pw.Center(
                child: pw.Text(
                  'HÓA ĐƠN BÁN HÀNG',
                  style: pw.TextStyle(font: fontBold, fontSize: 11),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'HD: ${order.id} | ${dateFormat.format(order.createdAt)}',
                  style: pw.TextStyle(font: font, fontSize: 7),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text('Khách: $customerName',
                  style: pw.TextStyle(font: fontBold, fontSize: 7.5)),
              if (customerPhone.isNotEmpty)
                pw.Text('SĐT: $customerPhone',
                    style: pw.TextStyle(font: font, fontSize: 6.5)),
              pw.SizedBox(height: 4),

              // Bảng món
              pw.TableHelper.fromTextArray(
                context: context,
                border:
                    pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                headerStyle: pw.TextStyle(font: fontBold, fontSize: 6.5),
                cellStyle: pw.TextStyle(font: font, fontSize: 6.5),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                columnWidths: {
                  0: const pw.FixedColumnWidth(12), // TT
                  1: const pw.FlexColumnWidth(3), // Tên hàng
                  2: const pw.FixedColumnWidth(16), // SL
                  3: const pw.FlexColumnWidth(2), // Đơn giá
                  4: const pw.FlexColumnWidth(2.2), // Thành tiền
                },
                headers: <String>['TT', 'Tên', 'SL', 'Giá', 'T.Tiền'],
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
              pw.SizedBox(height: 4),

              // Tổng tiền
              if (discount > 0) ...[
                _buildSummaryPdfRow(
                    'Tổng tiền:', '${currencyFormat.format(subtotal)} đ', font,
                    fontSize: 7),
                pw.SizedBox(height: 1),
                _buildSummaryPdfRow(
                    'Giảm giá:', '-${currencyFormat.format(discount)} đ', font,
                    fontSize: 7),
                pw.SizedBox(height: 1),
                _buildSummaryPdfRow('Cần trả:',
                    '${currencyFormat.format(order.total)} đ', fontBold,
                    fontSize: 8),
              ] else ...[
                _buildSummaryPdfRow('Tổng cộng:',
                    '${currencyFormat.format(order.total)} đ', fontBold,
                    fontSize: 8),
              ],
              pw.SizedBox(height: 1),
              _buildSummaryPdfRow('Đã thanh toán:',
                  '${currencyFormat.format(order.amountPaid)} đ', font,
                  fontSize: 7),
              if (order.paymentMethod == 'split') ...[
                pw.SizedBox(height: 1),
                _buildSummaryPdfRow('  - TM:',
                    '${currencyFormat.format(order.cashAmount ?? 0.0)} đ', font,
                    fontSize: 6.5),
                pw.SizedBox(height: 1),
                _buildSummaryPdfRow(
                    '  - CK:',
                    '${currencyFormat.format(order.transferAmount ?? 0.0)} đ',
                    font,
                    fontSize: 6.5),
              ],
              pw.SizedBox(height: 1),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              _buildSummaryPdfRow('Còn nợ:',
                  '${currencyFormat.format(remainingAmount)} đ', fontBold,
                  fontSize: 8.5),

              if (order.note != null && order.note!.trim().isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text('Ghi chú: ${order.note!.trim()}',
                    style: pw.TextStyle(font: font, fontSize: 6.5)),
              ],

              // VietQR nếu được bật
              if (config.showVietQR) ...[
                pw.SizedBox(height: 6),
                pw.Center(
                  child: qrImage != null
                      ? pw.Image(qrImage, width: 65, height: 65)
                      : pw.Container(
                          width: 65,
                          height: 65,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.grey),
                          ),
                          child: pw.Center(
                            child: pw.Text('VietQR Payment',
                                style: pw.TextStyle(font: font, fontSize: 6.5)),
                          ),
                        ),
                ),
                pw.SizedBox(height: 2),
                pw.Center(
                  child: pw.Text(
                    'Quét mã VietQR thanh toán',
                    style: pw.TextStyle(font: font, fontSize: 6.5),
                  ),
                ),
                if (config.bankName.isNotEmpty)
                  pw.Center(
                    child: pw.Text(
                      '${config.bankName} - ${config.accountNo}',
                      style: pw.TextStyle(font: fontBold, fontSize: 6.5),
                    ),
                  ),
              ],

              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5, color: PdfColors.grey500),
              pw.Center(
                child: pw.Text(
                  config.footerNote,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: fontBold, fontSize: 6.5),
                ),
              ),
            ],
          );
        },
      ),
    );
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

  static String _getPaymentMethodLabel(Order order) {
    if (order.paymentMethod == 'split') {
      return 'Kết hợp (TM + CK)';
    } else if (order.paymentMethod == 'transfer') {
      return 'Chuyển khoản';
    } else {
      return 'Tiền mặt';
    }
  }

  /// In trực tiếp hoặc xem trước hóa đơn qua hộp thoại in của hệ thống
  static Future<void> printInvoice(
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
