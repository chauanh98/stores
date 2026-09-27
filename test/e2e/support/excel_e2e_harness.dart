import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';

// ============================================================================
// 1. DOMAIN CONTRACT: ImportResult
// ============================================================================

/// Represents the structured outcome of an Excel batch import operation.
class ImportResult {
  final int total;
  final int added;
  final int updated;
  final int skipped;
  final int errors;
  final List<String> errorMessages;

  const ImportResult({
    this.total = 0,
    this.added = 0,
    this.updated = 0,
    this.skipped = 0,
    this.errors = 0,
    this.errorMessages = const [],
  });

  bool get hasErrors => errors > 0 || errorMessages.isNotEmpty;

  bool get isSuccess => errors == 0;

  /// Formats the summary dialog string strictly according to R2 specification:
  /// "Tổng số dòng: X | Thêm mới: A | Cập nhật: B | Bỏ qua: C | Lỗi: D"
  String toSummaryString() {
    return 'Tổng số dòng: $total | Thêm mới: $added | Cập nhật: $updated | Bỏ qua: $skipped | Lỗi: $errors';
  }

  @override
  String toString() => toSummaryString();
}

// ============================================================================
// 2. EXCEL TEST WORKBOOK BUILDER (Dynamic In-Memory OpenXML Generator)
// ============================================================================

/// Helper to generate valid in-memory Excel (`.xlsx`) bytes with standard headers.
class ExcelTestWorkbookBuilder {
  /// Builds a Product sheet matching KiotViet `DanhSachSanPham` headers.
  static List<int> buildProductSheet(List<Map<String, dynamic>> rows) {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];

    final headers = [
      'Loại hàng',
      'Nhóm hàng(3 cấp)',
      'Mã hàng',
      'Mã vạch',
      'Tên hàng',
      'Giá bán',
      'Giá vốn',
      'Tồn kho',
      'ĐVT',
      'Mô tả',
      'Mẫu ghi chú',
      'Hàng thành phần',
      'Hình ảnh',
    ];

    for (var c = 0; c < headers.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value = TextCellValue(headers[c]);
    }

    for (var r = 0; r < rows.length; r++) {
      final rowData = rows[r];
      final values = [
        rowData['type'] ?? 'Hàng hóa',
        rowData['category3Levels'] ?? '',
        rowData['code'] ?? '',
        rowData['barcode'] ?? '',
        rowData['name'] ?? '',
        rowData['price'] != null
            ? DoubleCellValue((rowData['price'] as num).toDouble())
            : null,
        rowData['costPrice'] != null
            ? DoubleCellValue((rowData['costPrice'] as num).toDouble())
            : null,
        rowData['stock'] != null
            ? DoubleCellValue((rowData['stock'] as num).toDouble())
            : null,
        rowData['unit'] ?? 'Cái',
        rowData['description'] ?? '',
        rowData['noteTemplate'] ?? '',
        rowData['components'] ?? '',
        rowData['imageUrl'] ?? '',
      ];

      for (var c = 0; c < values.length; c++) {
        final val = values[c];
        if (val != null) {
          if (val is CellValue) {
            sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
                .value = val;
          } else {
            sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
                .value = TextCellValue(val.toString());
          }
        }
      }
    }

    return excel.encode() ?? <int>[];
  }

  /// Builds a Customer sheet matching KiotViet `DanhSachKhachHang` 24 columns.
  static List<int> buildCustomerSheet(List<Map<String, dynamic>> rows) {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];

    final headers = [
      'Loại khách',
      'Chi nhánh tạo',
      'Mã khách hàng',
      'Tên khách hàng',
      'Điện thoại',
      'Địa chỉ',
      'Khu vực giao hàng',
      'Phường/Xã',
      'Công ty',
      'Mã số thuế',
      'Số CMND/CCCD',
      'Ngày sinh',
      'Giới tính',
      'Email',
      'Facebook',
      'Nhóm khách hàng',
      'Ghi chú',
      'Người tạo',
      'Ngày tạo',
      'Ngày giao dịch cuối',
      'Nợ cần thu hiện tại',
      'Tổng bán',
      'Tổng bán trừ trả hàng',
      'Trạng thái',
    ];

    for (var c = 0; c < headers.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value = TextCellValue(headers[c]);
    }

    for (var r = 0; r < rows.length; r++) {
      final rowData = rows[r];
      final values = [
        rowData['type'] ?? 'Cá nhân',
        rowData['branch'] ?? 'Chi nhánh Đông Thắng',
        rowData['id'] ?? '',
        rowData['name'] ?? '',
        rowData['phone'] ?? '',
        rowData['address'] ?? '',
        rowData['deliveryArea'] ?? '',
        rowData['ward'] ?? '',
        rowData['company'] ?? '',
        rowData['taxCode'] ?? '',
        rowData['identityCard'] ?? '',
        rowData['dob'] ?? '',
        rowData['gender'] ?? '',
        rowData['email'] ?? '',
        rowData['facebook'] ?? '',
        rowData['group'] ?? '',
        rowData['notes'] ?? '',
        rowData['createdBy'] ?? 'admin',
        rowData['createdAt'] ?? '2026-09-01T10:00:00Z',
        rowData['lastTransactionDate'] ?? '',
        rowData['currentDebt'] != null
            ? DoubleCellValue((rowData['currentDebt'] as num).toDouble())
            : null,
        rowData['totalSales'] != null
            ? DoubleCellValue((rowData['totalSales'] as num).toDouble())
            : null,
        rowData['netSales'] != null
            ? DoubleCellValue((rowData['netSales'] as num).toDouble())
            : null,
        rowData['status'] ?? 'Đang hoạt động',
      ];

      for (var c = 0; c < values.length; c++) {
        final val = values[c];
        if (val != null) {
          if (val is CellValue) {
            sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
                .value = val;
          } else {
            sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
                .value = TextCellValue(val.toString());
          }
        }
      }
    }

    return excel.encode() ?? <int>[];
  }

  /// Builds a Supplier sheet matching KiotViet `DanhSachNhaCungCap` 18 columns.
  static List<int> buildSupplierSheet(List<Map<String, dynamic>> rows) {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];

    final headers = [
      'Mã nhà cung cấp',
      'Tên nhà cung cấp',
      'Email',
      'Điện thoại',
      'Địa chỉ',
      'Khu vực',
      'Phường/Xã',
      'Tổng mua',
      'Nợ cần trả hiện tại',
      'Mã số thuế',
      'Số CMND/CCCD',
      'Ghi chú',
      'Nhóm nhà cung cấp',
      'Trạng thái',
      'Tổng mua trừ trả hàng',
      'Công ty',
      'Người tạo',
      'Ngày tạo',
    ];

    for (var c = 0; c < headers.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value = TextCellValue(headers[c]);
    }

    for (var r = 0; r < rows.length; r++) {
      final rowData = rows[r];
      final values = [
        rowData['code'] ?? rowData['id'] ?? '',
        rowData['name'] ?? '',
        rowData['email'] ?? '',
        rowData['phone'] ?? '',
        rowData['address'] ?? '',
        rowData['area'] ?? '',
        rowData['ward'] ?? '',
        rowData['totalPurchase'] != null
            ? DoubleCellValue((rowData['totalPurchase'] as num).toDouble())
            : null,
        rowData['currentDebt'] != null
            ? DoubleCellValue((rowData['currentDebt'] as num).toDouble())
            : null,
        rowData['taxCode'] ?? '',
        rowData['identityCard'] ?? '',
        rowData['note'] ?? '',
        rowData['group'] ?? '',
        rowData['status'] ?? '1',
        rowData['netPurchase'] != null
            ? DoubleCellValue((rowData['netPurchase'] as num).toDouble())
            : null,
        rowData['company'] ?? '',
        rowData['createdBy'] ?? 'admin',
        rowData['createdAt'] ?? '2026-09-01T08:00:00Z',
      ];

      for (var c = 0; c < values.length; c++) {
        final val = values[c];
        if (val != null) {
          if (val is CellValue) {
            sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
                .value = val;
          } else {
            sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
                .value = TextCellValue(val.toString());
          }
        }
      }
    }

    return excel.encode() ?? <int>[];
  }

  /// Builds an Invoice sheet supporting both detailed line-item rows and flat summary rows.
  static List<int> buildInvoiceSheet(List<Map<String, dynamic>> rows,
      {bool isDetailed = true}) {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];

    List<String> headers;
    if (isDetailed) {
      headers = [
        'Mã hóa đơn',
        'Thời gian',
        'Mã khách hàng',
        'Tên khách hàng',
        'Điện thoại',
        'Người bán',
        'Tổng tiền hàng',
        'Giảm giá hóa đơn',
        'Khách cần trả',
        'Khách đã trả',
        'Tiền mặt',
        'Chuyển khoản',
        'Trạng thái',
        'Mã hàng',
        'Tên hàng',
        'Số lượng',
        'Giá bán',
        'Thành tiền',
      ];
    } else {
      headers = [
        'STT',
        'Mã HĐ',
        'Thời gian',
        'Mã KH',
        'Tên khách hàng',
        'SĐT',
        'Người bán',
        'Chi nhánh',
        'Tiền hàng',
        'Giảm giá',
        'Tổng cộng',
        'Đã thanh toán',
        'Còn nợ',
        'Phương thức TT',
        'Trạng thái',
      ];
    }

    for (var c = 0; c < headers.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value = TextCellValue(headers[c]);
    }

    for (var r = 0; r < rows.length; r++) {
      final d = rows[r];
      List<dynamic> values;
      if (isDetailed) {
        values = [
          d['orderId'] ?? d['id'] ?? '',
          d['createdAt'] ?? '2026-09-01 10:00:00',
          d['customerId'] ?? '',
          d['customerName'] ?? '',
          d['phone'] ?? '',
          d['createdBy'] ?? 'admin1',
          d['subtotal'] != null
              ? DoubleCellValue((d['subtotal'] as num).toDouble())
              : null,
          d['discount'] != null
              ? DoubleCellValue((d['discount'] as num).toDouble())
              : null,
          d['total'] != null
              ? DoubleCellValue((d['total'] as num).toDouble())
              : null,
          d['amountPaid'] != null
              ? DoubleCellValue((d['amountPaid'] as num).toDouble())
              : null,
          d['cashAmount'] != null
              ? DoubleCellValue((d['cashAmount'] as num).toDouble())
              : null,
          d['transferAmount'] != null
              ? DoubleCellValue((d['transferAmount'] as num).toDouble())
              : null,
          d['status'] ?? 'Hoàn thành',
          d['productId'] ?? '',
          d['productName'] ?? '',
          d['quantity'] != null
              ? DoubleCellValue((d['quantity'] as num).toDouble())
              : null,
          d['price'] != null
              ? DoubleCellValue((d['price'] as num).toDouble())
              : null,
          d['lineTotal'] != null
              ? DoubleCellValue((d['lineTotal'] as num).toDouble())
              : null,
        ];
      } else {
        values = [
          r + 1,
          d['orderId'] ?? d['id'] ?? '',
          d['createdAt'] ?? '2026-09-01 10:00:00',
          d['customerId'] ?? '',
          d['customerName'] ?? '',
          d['phone'] ?? '',
          d['createdBy'] ?? 'admin1',
          d['storeId'] ?? 'store_001',
          d['subtotal'] != null
              ? DoubleCellValue((d['subtotal'] as num).toDouble())
              : null,
          d['discount'] != null
              ? DoubleCellValue((d['discount'] as num).toDouble())
              : null,
          d['total'] != null
              ? DoubleCellValue((d['total'] as num).toDouble())
              : null,
          d['amountPaid'] != null
              ? DoubleCellValue((d['amountPaid'] as num).toDouble())
              : null,
          d['debtAmount'] != null
              ? DoubleCellValue((d['debtAmount'] as num).toDouble())
              : null,
          d['paymentMethod'] ?? 'Tiền mặt',
          d['status'] ?? 'Hoàn thành',
        ];
      }

      for (var c = 0; c < values.length; c++) {
        final val = values[c];
        if (val != null) {
          if (val is CellValue) {
            sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
                .value = val;
          } else {
            sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
                .value = TextCellValue(val.toString());
          }
        }
      }
    }

    return excel.encode() ?? <int>[];
  }

  /// Builds a workbook with only headers and 0 data rows.
  static List<int> buildHeaderOnlySheet(List<String> headers) {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];
    for (var c = 0; c < headers.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value = TextCellValue(headers[c]);
    }
    return excel.encode() ?? <int>[];
  }

  /// Builds an empty workbook.
  static List<int> buildEmptySheet() {
    final excel = Excel.createExcel();
    return excel.encode() ?? <int>[];
  }
}

// ============================================================================
// 3. PURE REFERENCE PARSERS FOR SUPPLIERS & INVOICES
// ============================================================================

/// Reference parser for Supplier entities conforming to the 18 KiotViet columns.
class SupplierExcelParser {
  static final Map<String, String> _supplierHeaderMap = {
    'mã nhà cung cấp': 'code',
    'mã ncc': 'code',
    'tên nhà cung cấp': 'name',
    'tên ncc': 'name',
    'email': 'email',
    'điện thoại': 'phone',
    'sđt': 'phone',
    'số điện thoại': 'phone',
    'địa chỉ': 'address',
    'tổng mua': 'totalPurchase',
    'nợ cần trả hiện tại': 'currentDebt',
    'nợ hiện tại': 'currentDebt',
    'mã số thuế': 'taxCode',
    'mst': 'taxCode',
    'số cmnd/cccd': 'identityCard',
    'ghi chú': 'note',
    'nhóm nhà cung cấp': 'group',
    'nhóm ncc': 'group',
    'nhóm': 'group',
    'trạng thái': 'status',
    'công ty': 'company',
    'người tạo': 'createdBy',
    'ngày tạo': 'createdAt',
  };

  static String _cellValueToString(dynamic cellValue) {
    if (cellValue == null) return '';
    if (cellValue is TextCellValue) return cellValue.value.toString().trim();
    if (cellValue is FormulaCellValue) return cellValue.formula.trim();
    if (cellValue is IntCellValue) return cellValue.value.toString();
    if (cellValue is DoubleCellValue) return cellValue.value.toString();
    if (cellValue is DateCellValue) return cellValue.year.toString();
    if (cellValue is DateTimeCellValue) return cellValue.year.toString();
    return cellValue.toString().trim();
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is DoubleCellValue) return value.value;
    if (value is IntCellValue) return value.value.toDouble();
    if (value is num) return value.toDouble();
    final str =
        _cellValueToString(value).replaceAll(',', '').replaceAll(' ', '');
    return double.tryParse(str);
  }

  static List<Supplier> parseSuppliers(List<int> bytes) {
    if (bytes.isEmpty) return [];
    final excel = Excel.decodeBytes(bytes);
    final suppliers = <Supplier>[];

    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null || sheet.maxRows == 0) continue;

      final headerIndexMap = <String, int>{};
      final firstRow = sheet.rows.first;

      for (var col = 0; col < firstRow.length; col++) {
        final headerText =
            _cellValueToString(firstRow[col]?.value).toLowerCase();
        if (_supplierHeaderMap.containsKey(headerText)) {
          headerIndexMap[_supplierHeaderMap[headerText]!] = col;
        }
      }

      for (var r = 1; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        if (row.isEmpty) continue;

        String getValue(String fieldKey) {
          final colIndex = headerIndexMap[fieldKey];
          if (colIndex != null && colIndex < row.length) {
            return _cellValueToString(row[colIndex]?.value);
          }
          return '';
        }

        double? getDouble(String fieldKey) {
          final colIndex = headerIndexMap[fieldKey];
          if (colIndex != null && colIndex < row.length) {
            return _parseDouble(row[colIndex]?.value);
          }
          return null;
        }

        final code = getValue('code');
        final name = getValue('name');
        final phone = getValue('phone');

        // Ignore empty rows
        if (code.isEmpty && name.isEmpty && phone.isEmpty) continue;

        final supplierId = code.isNotEmpty
            ? code
            : 'ncc_${DateTime.now().millisecondsSinceEpoch}_$r';
        final totalPurchase = getDouble('totalPurchase') ?? 0.0;
        final currentDebt = getDouble('currentDebt') ?? 0.0;
        final group = getValue('group');
        var note = getValue('note');
        if (group.isNotEmpty) {
          note = note.isNotEmpty ? '[Nhóm: $group] $note' : '[Nhóm: $group]';
        }

        suppliers.add(Supplier(
          id: supplierId,
          code: code.isNotEmpty ? code : supplierId,
          name: name.isNotEmpty ? name : 'Nhà cung cấp $supplierId',
          phone: phone,
          email: getValue('email'),
          address: getValue('address'),
          taxCode: getValue('taxCode'),
          totalPurchase: totalPurchase,
          currentDebt: currentDebt,
          note: note,
          status: getValue('status').isEmpty || getValue('status') == '1'
              ? 'active'
              : 'inactive',
          createdAt: getValue('createdAt').isNotEmpty
              ? getValue('createdAt')
              : DateTime.now().toIso8601String(),
          createdBy: getValue('createdBy').isNotEmpty
              ? getValue('createdBy')
              : 'admin',
        ));
      }
    }

    return suppliers;
  }

  static Future<Uint8List> exportSuppliers(List<Supplier> suppliers) async {
    final excel = Excel.createExcel();
    const sheetName = 'DanhSachNhaCungCap';
    excel.rename(excel.getDefaultSheet() ?? 'Sheet1', sheetName);
    final sheet = excel[sheetName];

    final headers = [
      'Mã nhà cung cấp',
      'Tên nhà cung cấp',
      'Điện thoại',
      'Email',
      'Địa chỉ',
      'Mã số thuế',
      'Tổng mua',
      'Nợ cần trả hiện tại',
      'Ghi chú',
      'Trạng thái',
      'Ngày tạo',
    ];

    for (var c = 0; c < headers.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value = TextCellValue(headers[c]);
    }

    for (var r = 0; r < suppliers.length; r++) {
      final s = suppliers[r];
      final values = [
        s.code,
        s.name,
        s.phone,
        s.email,
        s.address,
        s.taxCode,
        DoubleCellValue(s.totalPurchase),
        DoubleCellValue(s.currentDebt),
        s.note,
        s.status,
        s.createdAt,
      ];

      for (var c = 0; c < values.length; c++) {
        final val = values[c];
        if (val != null) {
          if (val is CellValue) {
            sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
                .value = val;
          } else {
            sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
                .value = TextCellValue(val.toString());
          }
        }
      }
    }

    final encoded = excel.encode();
    return Uint8List.fromList(encoded ?? []);
  }
}

/// Reference parser for Invoices supporting detailed item grouping & summary rows.
class InvoiceExcelParser {
  static List<Order> parseInvoices(List<int> bytes,
      {String defaultStoreId = 'store_001'}) {
    if (bytes.isEmpty) return [];
    final excel = Excel.decodeBytes(bytes);
    final orderMap = <String, Map<String, dynamic>>{};
    final orderKeys = <String>[];

    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null || sheet.maxRows == 0) continue;

      final headerIndexMap = <String, int>{};
      final firstRow = sheet.rows.first;

      for (var col = 0; col < firstRow.length; col++) {
        final headerText =
            firstRow[col]?.value?.toString().trim().toLowerCase() ?? '';
        if (headerText == 'mã hóa đơn' || headerText == 'mã hđ') {
          headerIndexMap['orderId'] = col;
        } else if (headerText == 'thời gian' || headerText == 'ngày tạo') {
          headerIndexMap['createdAt'] = col;
        } else if (headerText == 'mã khách hàng' || headerText == 'mã kh') {
          headerIndexMap['customerId'] = col;
        } else if (headerText == 'tên khách hàng') {
          headerIndexMap['customerName'] = col;
        } else if (headerText == 'điện thoại' || headerText == 'sđt') {
          headerIndexMap['phone'] = col;
        } else if (headerText == 'người bán') {
          headerIndexMap['createdBy'] = col;
        } else if (headerText == 'khách cần trả' || headerText == 'tổng cộng') {
          headerIndexMap['total'] = col;
        } else if (headerText == 'khách đã trả' ||
            headerText == 'đã thanh toán') {
          headerIndexMap['amountPaid'] = col;
        } else if (headerText == 'tiền mặt') {
          headerIndexMap['cashAmount'] = col;
        } else if (headerText == 'chuyển khoản') {
          headerIndexMap['transferAmount'] = col;
        } else if (headerText == 'trạng thái') {
          headerIndexMap['status'] = col;
        } else if (headerText == 'mã hàng') {
          headerIndexMap['productId'] = col;
        } else if (headerText == 'tên hàng') {
          headerIndexMap['productName'] = col;
        } else if (headerText == 'số lượng') {
          headerIndexMap['quantity'] = col;
        } else if (headerText == 'giá bán') {
          headerIndexMap['price'] = col;
        } else if (headerText == 'chi nhánh') {
          headerIndexMap['storeId'] = col;
        }
      }

      if (!headerIndexMap.containsKey('orderId')) continue;

      for (var r = 1; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        if (row.isEmpty) continue;

        String getVal(String key) {
          final c = headerIndexMap[key];
          if (c != null && c < row.length) {
            final cell = row[c]?.value;
            if (cell is TextCellValue) return cell.value.toString().trim();
            return cell?.toString().trim() ?? '';
          }
          return '';
        }

        double getDbl(String key, [double def = 0.0]) {
          final c = headerIndexMap[key];
          if (c != null && c < row.length) {
            final cell = row[c]?.value;
            if (cell is DoubleCellValue) return cell.value;
            if (cell is IntCellValue) return cell.value.toDouble();
            final str = cell?.toString().replaceAll(',', '').trim() ?? '';
            return double.tryParse(str) ?? def;
          }
          return def;
        }

        final orderId = getVal('orderId');
        if (orderId.isEmpty) continue;

        if (!orderMap.containsKey(orderId)) {
          orderKeys.add(orderId);
          final rawStore = getVal('storeId');
          String storeId = defaultStoreId;
          if (rawStore.toLowerCase().contains('thới bình') ||
              rawStore == 'store_002') {
            storeId = 'store_002';
          }

          final statusStr = getVal('status').toLowerCase();
          String status = 'completed';
          if (statusStr.contains('hủy') || statusStr.contains('cancel')) {
            status = 'cancelled';
          } else if (statusStr.contains('trả') ||
              statusStr.contains('return')) {
            status = 'returned';
          } else if (statusStr.contains('tạm') || statusStr.contains('draft')) {
            status = 'draft';
          }

          final cash = getDbl('cashAmount');
          final transfer = getDbl('transferAmount');
          String paymentMethod = 'cash';
          if (cash > 0 && transfer > 0) {
            paymentMethod = 'split';
          } else if (transfer > 0) {
            paymentMethod = 'transfer';
          }

          final total = getDbl('total');
          final amountPaid = getDbl('amountPaid', total);
          final debtAmount = (total - amountPaid).clamp(0.0, double.infinity);

          DateTime createdAt;
          final dateStr = getVal('createdAt');
          try {
            createdAt = DateTime.parse(dateStr);
          } catch (_) {
            createdAt = DateTime.now();
          }

          orderMap[orderId] = {
            'id': orderId,
            'customerId': getVal('customerId').isNotEmpty
                ? getVal('customerId')
                : 'khach_le',
            'customerName': getVal('customerName'),
            'phone': getVal('phone'),
            'createdBy':
                getVal('createdBy').isNotEmpty ? getVal('createdBy') : 'admin',
            'total': total,
            'amountPaid': amountPaid,
            'debtAmount': debtAmount,
            'status': status,
            'paymentMethod': paymentMethod,
            'storeId': storeId,
            'createdAt': createdAt,
            'items': <OrderItem>[],
          };
        }

        final pId = getVal('productId');
        final pName = getVal('productName');
        final qty = getDbl('quantity', 1.0).toInt();
        final price = getDbl('price');

        if (pId.isNotEmpty || pName.isNotEmpty) {
          final items = orderMap[orderId]!['items'] as List<OrderItem>;
          items.add(OrderItem(
            productId: pId.isNotEmpty ? pId : 'item_${items.length + 1}',
            productName: pName.isNotEmpty ? pName : 'Hàng hóa $pId',
            quantity: qty > 0 ? qty : 1,
            price: price,
            warrantyMonths: 0,
            purchaseDate: orderMap[orderId]!['createdAt'] as DateTime,
          ));
        }
      }
    }

    final result = <Order>[];
    for (final k in orderKeys) {
      final d = orderMap[k]!;
      final items = d['items'] as List<OrderItem>;
      if (items.isEmpty) {
        items.add(OrderItem(
          productId: 'item_summary_$k',
          productName: 'Hàng hóa theo hóa đơn $k',
          quantity: 1,
          price: d['total'] != null ? (d['total'] as num).toDouble() : 0.0,
          warrantyMonths: 0,
          purchaseDate: d['createdAt'] as DateTime,
        ));
      }

      result.add(Order(
        id: d['id'] as String,
        customerId: d['customerId'] as String,
        createdAt: d['createdAt'] as DateTime,
        items: items,
        total: d['total'] as double,
        amountPaid: d['amountPaid'] as double,
        debtAmount: d['debtAmount'] as double,
        paymentMethod: d['paymentMethod'] as String,
        status: d['status'] as String,
        createdBy: d['createdBy'] as String,
        storeId: d['storeId'] as String,
      ));
    }

    return result;
  }
}

// ============================================================================
// 4. PERMISSION GUARD EVALUATOR (Double-Lock UI & Execution RBAC)
// ============================================================================

class ExcelPermissionGuardEvaluator {
  /// Presentation Layer Guard: only shows Excel actions when kIsWeb && user?.isAdmin == true.
  static bool shouldShowExcelActions(
      {required bool isWeb, required UserAccount? user}) {
    return isWeb && (user?.isAdmin == true);
  }

  /// Execution Layer Guard: returns true only if execution is allowed.
  static bool canExecuteExcelAction(
      {required bool isWeb, required UserAccount? user}) {
    if (!isWeb || (user?.isAdmin != true)) {
      return false;
    }
    return true;
  }
}

// ============================================================================
// 5. WEB FILE SAVER MOCK (Cross-Platform Uint8List Download Simulator)
// ============================================================================

class WebFileSaverMock {
  Uint8List? lastSavedBytes;
  String? lastFileName;
  String? lastMimeType;
  bool isTriggered = false;

  Future<void> saveExcelFile(Uint8List bytes, String fileName) async {
    if (bytes.isEmpty) {
      throw ArgumentError('Dữ liệu file Excel không được rỗng.');
    }
    final normalizedFileName =
        fileName.endsWith('.xlsx') ? fileName : '$fileName.xlsx';
    lastSavedBytes = bytes;
    lastFileName = normalizedFileName;
    lastMimeType =
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    isTriggered = true;
  }

  void reset() {
    lastSavedBytes = null;
    lastFileName = null;
    lastMimeType = null;
    isTriggered = false;
  }
}

// ============================================================================
// 6. DEDUPLICATION ENGINES (Clean Invariant Preservers)
// ============================================================================

class ProductDeduplicationEngine {
  final Map<String, Product> _database = {};
  final List<InventoryTransaction> _inventoryTransactions = [];

  Map<String, Product> get database => Map.unmodifiable(_database);

  List<InventoryTransaction> get transactions =>
      List.unmodifiable(_inventoryTransactions);

  void seedProducts(List<Product> products) {
    for (final p in products) {
      _database[p.id.toLowerCase()] = p;
      if (p.code.isNotEmpty) {
        _database[p.code.toLowerCase()] = p;
      }
    }
  }

  Future<ImportResult> importProducts({
    required List<Product> importedProducts,
    required String targetStoreId,
  }) async {
    int added = 0;
    int updated = 0;
    int errors = 0;
    final errorMessages = <String>[];

    for (var i = 0; i < importedProducts.length; i++) {
      final imp = importedProducts[i];
      try {
        if (imp.code.isEmpty && imp.id.isEmpty) {
          errors++;
          errorMessages
              .add('Dòng ${i + 1}: Mã hàng và ID không được để trống.');
          continue;
        }

        final matchKeyId = imp.id.toLowerCase();
        final matchKeyCode = imp.code.toLowerCase();
        final existing = _database[matchKeyId] ?? _database[matchKeyCode];

        if (existing != null) {
          // UPDATE: Update basic metadata, PRESERVE branchStocks and imageUrl!
          final merged = existing.copyWith(
            name: imp.name.isNotEmpty ? imp.name : existing.name,
            price: imp.price > 0 ? imp.price : existing.price,
            costPrice: imp.costPrice > 0 ? imp.costPrice : existing.costPrice,
            unit: (imp.unit != null && imp.unit!.isNotEmpty)
                ? imp.unit
                : existing.unit,
            category:
                imp.category.isNotEmpty ? imp.category : existing.category,
            category3Levels: imp.category3Levels ?? existing.category3Levels,
            description:
                (imp.description != null && imp.description!.isNotEmpty)
                    ? imp.description
                    : existing.description,
            // CRITICAL: Branch stocks and images must be preserved!
            branchStocks: existing.branchStocks,
            imageUrl:
                (existing.imageUrl != null && existing.imageUrl!.isNotEmpty)
                    ? existing.imageUrl
                    : imp.imageUrl,
          );
          _database[merged.id.toLowerCase()] = merged;
          if (merged.code.isNotEmpty) {
            _database[merged.code.toLowerCase()] = merged;
          }
          updated++;
        } else {
          // INSERT: Add new product with initial stock in targetStoreId
          final initialStock = imp.branchStocks[targetStoreId] ?? imp.stock;
          final newBranchStocks = <String, int>{targetStoreId: initialStock};
          final newProduct = imp.copyWith(
            branchStocks: newBranchStocks,
          );
          _database[newProduct.id.toLowerCase()] = newProduct;
          if (newProduct.code.isNotEmpty) {
            _database[newProduct.code.toLowerCase()] = newProduct;
          }

          if (initialStock > 0) {
            _inventoryTransactions.add(InventoryTransaction(
              id: 'tx_init_${newProduct.id}_$targetStoreId',
              productId: newProduct.id,
              type: TransactionType.import,
              quantity: initialStock,
              storeId: targetStoreId,
              note: 'Nhập tồn đầu kỳ từ file Excel ($targetStoreId)',
              date: DateTime.now(),
            ));
          }
          added++;
        }
      } catch (e) {
        errors++;
        errorMessages
            .add('Dòng ${i + 1}: Lỗi xử lý sản phẩm (${e.toString()})');
      }
    }

    return ImportResult(
      total: importedProducts.length,
      added: added,
      updated: updated,
      skipped: 0,
      errors: errors,
      errorMessages: errorMessages,
    );
  }
}

class CustomerDeduplicationEngine {
  final Map<String, Customer> _idMap = {};
  final Map<String, Customer> _phoneMap = {};

  List<Customer> get allCustomers => _idMap.values.toList();

  static String normalizePhone(String? phone) {
    if (phone == null) return '';
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('84') && digits.length >= 10) {
      digits = '0${digits.substring(2)}';
    } else if (digits.length == 9 && !digits.startsWith('0')) {
      digits = '0$digits';
    }
    return digits;
  }

  void seedCustomers(List<Customer> customers) {
    for (final c in customers) {
      _idMap[c.id.toLowerCase()] = c;
      final normPhone = normalizePhone(c.phone);
      if (normPhone.length >= 9) {
        _phoneMap[normPhone] = c;
      }
    }
  }

  Future<ImportResult> importCustomers(List<Customer> imported) async {
    int added = 0;
    int updated = 0;
    int errors = 0;
    final errorMessages = <String>[];

    for (var i = 0; i < imported.length; i++) {
      final imp = imported[i];
      try {
        final normPhone = normalizePhone(imp.phone);
        if (imp.id.isEmpty && normPhone.isEmpty) {
          errors++;
          errorMessages.add(
              'Dòng ${i + 1}: Mã KH và Số điện thoại không được để trống.');
          continue;
        }

        final existingById =
            imp.id.isNotEmpty ? _idMap[imp.id.toLowerCase()] : null;
        final existingByPhone =
            normPhone.length >= 9 ? _phoneMap[normPhone] : null;
        final existing = existingById ?? existingByPhone;

        if (existing != null) {
          // UPDATE: Update contact details, PRESERVE purchases and currentDebt!
          final merged = existing.copyWith(
            name: imp.name.isNotEmpty ? imp.name : existing.name,
            phone: normPhone.isNotEmpty ? normPhone : existing.phone,
            address: imp.address.isNotEmpty ? imp.address : existing.address,
            email: imp.email.isNotEmpty ? imp.email : existing.email,
            group: (imp.group != null && imp.group!.isNotEmpty)
                ? imp.group
                : existing.group,
            notes: (imp.notes != null && imp.notes!.isNotEmpty)
                ? imp.notes
                : existing.notes,
            // CRITICAL: Purchases and debt are strictly preserved!
            purchases: existing.purchases,
            currentDebt: existing.currentDebt,
            totalSales: existing.totalSales,
            netSales: existing.netSales,
          );
          _idMap[merged.id.toLowerCase()] = merged;
          final mPhone = normalizePhone(merged.phone);
          if (mPhone.length >= 9) {
            _phoneMap[mPhone] = merged;
          }
          updated++;
        } else {
          // INSERT: Add new customer
          _idMap[imp.id.toLowerCase()] = imp;
          if (normPhone.length >= 9) {
            _phoneMap[normPhone] = imp;
          }
          added++;
        }
      } catch (e) {
        errors++;
        errorMessages
            .add('Dòng ${i + 1}: Lỗi xử lý khách hàng (${e.toString()})');
      }
    }

    return ImportResult(
      total: imported.length,
      added: added,
      updated: updated,
      skipped: 0,
      errors: errors,
      errorMessages: errorMessages,
    );
  }
}

class SupplierDeduplicationEngine {
  final Map<String, Supplier> _suppliers = {};

  List<Supplier> get allSuppliers => _suppliers.values.toList();

  static String normalizePhone(String? phone) {
    if (phone == null) return '';
    return phone.replaceAll(RegExp(r'\D'), '');
  }

  void seedSuppliers(List<Supplier> suppliers) {
    for (final s in suppliers) {
      _suppliers[s.id.toLowerCase()] = s;
      if (s.code.isNotEmpty) {
        _suppliers[s.code.toLowerCase()] = s;
      }
      final normPhone = normalizePhone(s.phone);
      if (normPhone.length >= 9) {
        _suppliers['phone_$normPhone'] = s;
      }
    }
  }

  Future<ImportResult> importSuppliers(List<Supplier> imported) async {
    int added = 0;
    int updated = 0;
    int errors = 0;
    final errorMessages = <String>[];

    for (var i = 0; i < imported.length; i++) {
      final imp = imported[i];
      try {
        final normPhone = normalizePhone(imp.phone);
        if (imp.id.isEmpty && imp.code.isEmpty && normPhone.isEmpty) {
          errors++;
          errorMessages.add(
              'Dòng ${i + 1}: Mã NCC và Số điện thoại không được để trống.');
          continue;
        }

        Supplier? existing = _suppliers[imp.id.toLowerCase()] ??
            (imp.code.isNotEmpty ? _suppliers[imp.code.toLowerCase()] : null) ??
            (normPhone.length >= 9 ? _suppliers['phone_$normPhone'] : null);

        if (existing != null) {
          // UPDATE: Update contact details, PRESERVE currentDebt and totalPurchase!
          final merged = existing.copyWith(
            name: imp.name.isNotEmpty ? imp.name : existing.name,
            phone: imp.phone.isNotEmpty ? imp.phone : existing.phone,
            email: imp.email.isNotEmpty ? imp.email : existing.email,
            address: imp.address.isNotEmpty ? imp.address : existing.address,
            taxCode: (imp.taxCode != null && imp.taxCode!.isNotEmpty)
                ? imp.taxCode
                : existing.taxCode,
            note: (imp.note != null && imp.note!.isNotEmpty)
                ? imp.note
                : existing.note,
            // CRITICAL: Debt and purchases are strictly preserved!
            currentDebt: existing.currentDebt,
            totalPurchase: existing.totalPurchase,
          );
          _suppliers[merged.id.toLowerCase()] = merged;
          if (merged.code.isNotEmpty) {
            _suppliers[merged.code.toLowerCase()] = merged;
          }
          updated++;
        } else {
          // INSERT: Add new supplier
          _suppliers[imp.id.toLowerCase()] = imp;
          if (imp.code.isNotEmpty) {
            _suppliers[imp.code.toLowerCase()] = imp;
          }
          if (normPhone.length >= 9) {
            _suppliers['phone_$normPhone'] = imp;
          }
          added++;
        }
      } catch (e) {
        errors++;
        errorMessages.add('Dòng ${i + 1}: Lỗi xử lý NCC (${e.toString()})');
      }
    }

    return ImportResult(
      total: imported.length,
      added: added,
      updated: updated,
      skipped: 0,
      errors: errors,
      errorMessages: errorMessages,
    );
  }
}

class InvoiceDeduplicationEngine {
  final Map<String, Order> _orders = {};
  final Map<String, Product> _products = {};
  final Map<String, Customer> _customers = {};
  final List<InventoryTransaction> _inventoryTransactions = [];

  Map<String, Order> get orders => Map.unmodifiable(_orders);

  Map<String, Product> get products => Map.unmodifiable(_products);

  Map<String, Customer> get customers => Map.unmodifiable(_customers);

  List<InventoryTransaction> get transactions =>
      List.unmodifiable(_inventoryTransactions);

  void seedOrders(List<Order> orders) {
    for (final o in orders) {
      _orders[o.id.toLowerCase()] = o;
    }
  }

  void seedProducts(List<Product> products) {
    for (final p in products) {
      _products[p.id.toLowerCase()] = p;
    }
  }

  void seedCustomers(List<Customer> customers) {
    for (final c in customers) {
      _customers[c.id.toLowerCase()] = c;
    }
  }

  Future<ImportResult> importInvoices({
    required List<Order> importedOrders,
    required String targetStoreId,
  }) async {
    int added = 0;
    int skipped = 0;
    int errors = 0;
    final errorMessages = <String>[];

    for (var i = 0; i < importedOrders.length; i++) {
      final imp = importedOrders[i];
      try {
        if (imp.id.isEmpty) {
          errors++;
          errorMessages.add('Dòng ${i + 1}: Mã hóa đơn không được để trống.');
          continue;
        }

        final matchKey = imp.id.toLowerCase();

        // 1. DUPLICATE CHECK: IDEMPOTENT SKIP!
        if (_orders.containsKey(matchKey)) {
          // STRICT SKIP: Never overwrite, never double-deduct inventory, never re-accrue debt!
          skipped++;
          continue;
        }

        // 2. NEW INVOICE:
        _orders[matchKey] = imp;

        // A. Deduct branch inventory & record transactions
        for (final item in imp.items) {
          final pKey = item.productId.toLowerCase();
          final prod = _products[pKey];
          if (prod != null) {
            final currentStoreStock =
                prod.branchStocks[targetStoreId] ?? prod.stock;
            final newStoreStock =
                (currentStoreStock - item.quantity).clamp(0, 999999);
            final updatedBranchStocks =
                Map<String, int>.from(prod.branchStocks);
            updatedBranchStocks[targetStoreId] = newStoreStock;

            _products[pKey] = prod.copyWith(
              branchStocks: updatedBranchStocks,
            );

            _inventoryTransactions.add(InventoryTransaction(
              id: 'tx_inv_export_${imp.id}_${item.productId}',
              productId: item.productId,
              type: TransactionType.export,
              quantity: item.quantity,
              storeId: targetStoreId,
              note: imp.id,
              date: DateTime.now(),
            ));
          }
        }

        // B. Link customer & adjust debt if credit was extended
        final cKey = imp.customerId.toLowerCase();
        final cust = _customers[cKey];
        if (cust != null) {
          final newTotalSales = (cust.totalSales ?? 0.0) + imp.total;
          final newDebt = (cust.currentDebt ?? 0.0) + imp.debtAmount;
          _customers[cKey] = cust.copyWith(
            totalSales: newTotalSales,
            netSales: (cust.netSales ?? 0.0) + imp.total,
            currentDebt: newDebt,
          );
        }

        added++;
      } catch (e) {
        errors++;
        errorMessages.add('Dòng ${i + 1}: Lỗi xử lý hóa đơn (${e.toString()})');
      }
    }

    return ImportResult(
      total: importedOrders.length,
      added: added,
      updated: 0,
      skipped: skipped,
      errors: errors,
      errorMessages: errorMessages,
    );
  }
}
