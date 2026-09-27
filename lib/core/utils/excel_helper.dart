import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import '../../domain/entities/customer.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/order_item.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/stock_in_receipt.dart';
import '../../domain/entities/supplier.dart';

class ExcelHelper {
  // Mapping headers of Customers to index
  static final Map<String, String> _customerHeaderMap = {
    'loại khách': 'type',
    'chi nhánh tạo': 'branch',
    'mã khách hàng': 'id',
    'tên khách hàng': 'name',
    'điện thoại': 'phone',
    'địa chỉ': 'address',
    'khu vực giao hàng': 'deliveryArea',
    'phường/xã': 'ward',
    'công ty': 'company',
    'mã số thuế': 'taxCode',
    'số cmnd/cccd': 'identityCard',
    'ngày sinh': 'dob',
    'giới tính': 'gender',
    'email': 'email',
    'facebook': 'facebook',
    'nhóm khách hàng': 'group',
    'ghi chú': 'notes',
    'người tạo': 'createdBy',
    'ngày tạo': 'createdAt',
    'ngày giao dịch cuối': 'lastTransactionDate',
    'nợ cần thu hiện tại': 'currentDebt',
    'tổng bán': 'totalSales',
    'tổng bán trừ trả hàng': 'netSales',
    'trạng thái': 'status',
  };

  // Mapping headers of Products to index
  static final Map<String, String> _productHeaderMap = {
    'loại hàng': 'type',
    'nhóm hàng(3 cấp)': 'category3Levels',
    'mã hàng': 'code',
    'mã vạch': 'barcode',
    'tên hàng': 'name',
    'giá bán': 'price',
    'giá vốn': 'costPrice',
    'tồn kho': 'stock',
    'đvt': 'unit',
    'mô tả': 'description',
    'mẫu ghi chú': 'noteTemplate',
    'hàng thành phần': 'components',
    'hình ảnh': 'imageUrl',
    'ảnh': 'imageUrl',
    'image': 'imageUrl',
    'imageurl': 'imageUrl',
    'link ảnh': 'imageUrl',
    'hinh anh': 'imageUrl',
    'anh': 'imageUrl',
    'ảnh sản phẩm': 'imageUrl',
  };

  // Mapping headers of Suppliers to field names
  static final Map<String, String> _supplierHeaderMap = {
    'mã nhà cung cấp': 'code',
    'mã ncc': 'code',
    'tên nhà cung cấp': 'name',
    'tên ncc': 'name',
    'điện thoại': 'phone',
    'sđt': 'phone',
    'số điện thoại': 'phone',
    'email': 'email',
    'địa chỉ': 'address',
    'mã số thuế': 'taxCode',
    'mst': 'taxCode',
    'nhóm nhà cung cấp': 'group',
    'nhóm ncc': 'group',
    'nhóm': 'group',
    'ghi chú': 'note',
    'nợ cần trả hiện tại': 'currentDebt',
    'nợ hiện tại': 'currentDebt',
    'nợ cần trả': 'currentDebt',
    'tổng mua': 'totalPurchase',
    'trạng thái': 'status',
    'chi nhánh': 'branch',
    'chi nhánh tạo': 'branch',
    'người tạo': 'createdBy',
    'ngày tạo': 'createdAt',
  };

  // Mapping headers of Invoices to field names
  static final Map<String, String> _invoiceHeaderMap = {
    'mã hóa đơn': 'id',
    'mã hđ': 'id',
    'thời gian': 'orderDate',
    'ngày tạo': 'orderDate',
    'ngày bán': 'orderDate',
    'thời gian tạo': 'createdTime',
    'ngày cập nhật': 'updatedTime',
    'mã khách hàng': 'customerId',
    'mã kh': 'customerId',
    'tên khách hàng': 'customerName',
    'tên kh': 'customerName',
    'khách hàng': 'customerName',
    'điện thoại': 'phone',
    'sđt': 'phone',
    'số điện thoại': 'phone',
    'người bán': 'seller',
    'người tạo': 'seller',
    'chi nhánh': 'branch',
    'tiền hàng': 'subtotal',
    'tổng tiền hàng': 'subtotal',
    'tổng hàng': 'subtotal',
    'giảm giá': 'discount',
    'chiết khấu': 'discount',
    'ck': 'discount',
    'giảm giá hóa đơn': 'invoiceDiscount',
    'chiết khấu hóa đơn': 'invoiceDiscount',
    'giảm giá hđ': 'invoiceDiscount',
    'chiết khấu hđ': 'invoiceDiscount',
    'ck hóa đơn': 'invoiceDiscount',
    'ck hđ': 'invoiceDiscount',
    'tổng cộng': 'total',
    'khách cần trả': 'netPayable',
    'cần trả': 'netPayable',
    'phải thanh toán': 'netPayable',
    'tổng cần trả': 'netPayable',
    'tổng tiền': 'total',
    'đã thanh toán': 'amountPaid',
    'khách đã trả': 'amountPaid',
    'đã trả': 'amountPaid',
    'còn nợ': 'debtAmount',
    'tiền nợ': 'debtAmount',
    'nợ': 'debtAmount',
    'tiền mặt': 'cash',
    'chuyển khoản': 'transfer',
    'phương thức tt': 'paymentMethod',
    'phương thức thanh toán': 'paymentMethod',
    'hình thức thanh toán': 'paymentMethod',
    'trạng thái': 'status',
    'ghi chú': 'note',
    // Line item columns for detailed invoice exports
    'mã hàng': 'itemCode',
    'mã sản phẩm': 'itemCode',
    'mã sp': 'itemCode',
    'tên hàng': 'itemName',
    'tên sản phẩm': 'itemName',
    'tên sp': 'itemName',
    'số lượng': 'itemQuantity',
    'sl': 'itemQuantity',
    'giá bán': 'itemSellingPrice',
    'đơn giá': 'itemUnitPrice',
    'thành tiền': 'itemTotal',
  };

  // Mapping headers of Stock-In Receipts to field names
  static final Map<String, String> _stockInReceiptHeaderMap = {
    // Receipt header fields
    'chi nhánh': 'branch',
    'chi nhánh tạo': 'branch',
    'tên chi nhánh': 'branch',
    'mã nhập hàng': 'importCode',
    'mã phiếu': 'importCode',
    'mã phiếu nhập': 'importCode',
    'thời gian': 'date',
    'ngày nhập': 'date',
    'thời gian tạo': 'createdAt',
    'ngày tạo': 'createdAt',
    'ngày cập nhật': 'updatedAt',
    'thời gian cập nhật': 'updatedAt',
    'mã nhà cung cấp': 'supplierId',
    'mã ncc': 'supplierId',
    'tên nhà cung cấp': 'supplierName',
    'tên ncc': 'supplierName',
    'điện thoại': 'supplierPhone',
    'sđt': 'supplierPhone',
    'số điện thoại': 'supplierPhone',
    'địa chỉ': 'supplierAddress',
    'người nhập': 'importedBy',
    'người tạo': 'createdBy',
    'tổng tiền hàng': 'totalAmount',
    'tiền hàng': 'totalAmount',
    'tổng hàng': 'totalAmount',
    'giảm giá phiếu nhập': 'discount',
    'cần trả ncc': 'netPayable',
    'tổng cần trả': 'netPayable',
    'khách cần trả': 'netPayable',
    'tiền đã trả ncc': 'paidAmount',
    'đã trả ncc': 'paidAmount',
    'đã trả': 'paidAmount',
    'ghi chú': 'note',
    'số hóa đơn đầu vào': 'invoiceNumber',
    'tổng số lượng': 'totalQuantity',
    'tổng số mặt hàng': 'totalItemLines',
    'trạng thái': 'status',

    // Line item fields
    'mã hàng': 'productId',
    'mã sản phẩm': 'productId',
    'mã sp': 'productId',
    'mã vạch': 'barcode',
    'tên hàng': 'productName',
    'tên sản phẩm': 'productName',
    'tên sp': 'productName',
    'thương hiệu': 'brand',
    'đvt': 'unit',
    'đơn vị tính': 'unit',
    'ghi chú hàng hóa': 'itemNote',
    'đơn giá': 'originalPrice',
    'giảm giá %': 'discountPercentage',
    'giá nhập': 'unitPrice',
    'thành tiền': 'totalPrice',
    'số lượng': 'quantity',
    'sl': 'quantity',
  };

  static String _parseCleanString(dynamic cellValue) {
    if (cellValue == null) return '';
    if (cellValue is CellValue) {
      if (cellValue is TextCellValue) {
        return cellValue.value.toString().trim();
      }
      if (cellValue is IntCellValue) {
        return cellValue.value.toString().trim();
      }
      if (cellValue is DoubleCellValue) {
        final d = cellValue.value;
        if (d == d.roundToDouble() && !d.isInfinite && !d.isNaN) {
          return BigInt.from(d).toString();
        }
        return d.toStringAsFixed(0);
      }
      return cellValue.toString().trim();
    }
    if (cellValue is int) return cellValue.toString();
    if (cellValue is double) {
      if (cellValue == cellValue.roundToDouble() &&
          !cellValue.isInfinite &&
          !cellValue.isNaN) {
        return BigInt.from(cellValue).toString();
      }
      return cellValue.toStringAsFixed(0);
    }
    String s = cellValue.toString().trim();
    if (s.contains('e+') ||
        s.contains('E+') ||
        s.contains('e-') ||
        s.contains('E-')) {
      final parsed = double.tryParse(s);
      if (parsed != null &&
          parsed == parsed.roundToDouble() &&
          !parsed.isInfinite &&
          !parsed.isNaN) {
        return BigInt.from(parsed).toString();
      }
    }
    if (s.endsWith('.0')) {
      s = s.substring(0, s.length - 2);
    }
    return s;
  }

  static String _cleanPhoneNumber(dynamic cellValue) {
    var p = _parseCleanString(cellValue);
    if (p.endsWith('.0')) {
      p = p.substring(0, p.length - 2);
    }
    if (p.length == 9 && !p.startsWith('0') && RegExp(r'^\d{9}$').hasMatch(p)) {
      p = '0$p';
    }
    return p;
  }

  static double? _parseDoubleStrict(dynamic value) {
    if (value == null) return null;
    if (value is DoubleCellValue) return value.value;
    if (value is IntCellValue) return value.value.toDouble();
    if (value is num) return value.toDouble();

    final raw =
        (value is TextCellValue) ? value.value.toString() : value.toString();
    final s = raw
        .replaceAll(',', '')
        .replaceAll('đ', '')
        .replaceAll('Đ', '')
        .replaceAll(RegExp(r'vnd', caseSensitive: false), '')
        .replaceAll('\u00A0', ' ')
        .trim();
    return double.tryParse(s);
  }

  static String _mapBranchToStoreId(String branchName, String? defaultStoreId) {
    final lower = branchName.toLowerCase().trim();
    if (lower.contains('thới bình') ||
        lower.contains('thoi binh') ||
        lower == 'store_002') {
      return 'store_002';
    }
    if (lower.contains('đông thắng') ||
        lower.contains('dong thang') ||
        lower == 'store_001') {
      return 'store_001';
    }
    return defaultStoreId ?? 'store_001';
  }

  static DateTime _parseExcelDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is CellValue) {
      if (value is DateCellValue) {
        return value.asDateTimeUtc();
      }
      if (value is DateTimeCellValue) {
        return value.asDateTimeUtc();
      }
      if (value is DoubleCellValue) {
        return DateTime(1899, 12, 30)
            .add(Duration(milliseconds: (value.value * 86400000).round()));
      }
      if (value is IntCellValue) {
        return DateTime(1899, 12, 30).add(Duration(
            milliseconds: (value.value.toDouble() * 86400000).round()));
      }
      value = value.toString();
    }
    if (value is DateTime) return value;
    if (value is num) {
      return DateTime(1899, 12, 30)
          .add(Duration(milliseconds: (value.toDouble() * 86400000).round()));
    }
    final str = value.toString().trim();
    if (str.isEmpty) return DateTime.now();

    final parsedIso = DateTime.tryParse(str);
    if (parsedIso != null) return parsedIso;

    final numVal = double.tryParse(str);
    if (numVal != null && numVal > 20000 && numVal < 100000) {
      return DateTime(1899, 12, 30)
          .add(Duration(milliseconds: (numVal * 86400000).round()));
    }

    try {
      if (str.contains('/')) {
        final parts = str.split(' ');
        final dateParts = parts[0].split('/');
        if (dateParts.length == 3) {
          final day = int.parse(dateParts[0]);
          final month = int.parse(dateParts[1]);
          final year = int.parse(dateParts[2]);
          int hour = 0;
          int minute = 0;
          int second = 0;
          if (parts.length > 1) {
            final timeParts = parts[1].split(':');
            if (timeParts.isNotEmpty) hour = int.parse(timeParts[0]);
            if (timeParts.length > 1) minute = int.parse(timeParts[1]);
            if (timeParts.length > 2) second = int.parse(timeParts[2]);
          }
          return DateTime(year, month, day, hour, minute, second);
        }
      }
    } catch (_) {}

    return DateTime.now();
  }

  static String _normalizePhone(String rawPhone) {
    var p = rawPhone.trim();
    if (p.endsWith('.0')) {
      p = p.substring(0, p.length - 2);
    }
    if (p.length == 9 && !p.startsWith('0') && RegExp(r'^\d{9}$').hasMatch(p)) {
      p = '0$p';
    }
    return p;
  }

  static String _cellValueToString(dynamic cellValue) {
    if (cellValue == null) return '';
    if (cellValue is CellValue) {
      return cellValue.toString();
    }
    return cellValue.toString();
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is CellValue) {
      if (value is DoubleCellValue) {
        return value.value;
      }
      if (value is IntCellValue) {
        return value.value.toDouble();
      }
      return double.tryParse(value.toString().replaceAll(',', ''));
    }
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', ''));
  }

  static DateTime _dateTimeFromSerial(double serial) {
    final baseDate = DateTime(1899, 12, 30);
    final days = serial.floor();
    final fraction = serial - days;
    final date = baseDate.add(Duration(days: days));
    final seconds = (fraction * 86400).round();
    return date.add(Duration(seconds: seconds));
  }

  static String? _parseDateToString(dynamic value) {
    if (value == null) return null;
    if (value is CellValue) {
      if (value is DateCellValue) {
        return value.asDateTimeUtc().toIso8601String();
      }
      if (value is DateTimeCellValue) {
        return value.asDateTimeUtc().toIso8601String();
      }
      if (value is DoubleCellValue) {
        return _dateTimeFromSerial(value.value).toIso8601String();
      }
      if (value is IntCellValue) {
        return _dateTimeFromSerial(value.value.toDouble()).toIso8601String();
      }
      return value.toString();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is num) {
      return _dateTimeFromSerial(value.toDouble()).toIso8601String();
    }
    return value.toString();
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is CellValue) {
      if (value is DateCellValue) {
        return value.asDateTimeUtc();
      }
      if (value is DateTimeCellValue) {
        return value.asDateTimeUtc();
      }
      if (value is DoubleCellValue) {
        return _dateTimeFromSerial(value.value);
      }
      if (value is IntCellValue) {
        return _dateTimeFromSerial(value.value.toDouble());
      }
      value = value.toString();
    }
    if (value is DateTime) return value;
    if (value is num) return _dateTimeFromSerial(value.toDouble());

    final str = value.toString().trim();
    if (str.isEmpty) return null;

    final parsedIso = DateTime.tryParse(str);
    if (parsedIso != null) return parsedIso;

    try {
      if (str.contains('/')) {
        final parts = str.split(' ');
        final dateParts = parts[0].split('/');
        if (dateParts.length == 3) {
          final day = int.parse(dateParts[0]);
          final month = int.parse(dateParts[1]);
          final year = int.parse(dateParts[2]);
          int hour = 0;
          int minute = 0;
          int second = 0;
          if (parts.length > 1) {
            final timeParts = parts[1].split(':');
            if (timeParts.isNotEmpty) hour = int.parse(timeParts[0]);
            if (timeParts.length > 1) minute = int.parse(timeParts[1]);
            if (timeParts.length > 2) second = int.parse(timeParts[2]);
          }
          return DateTime(year, month, day, hour, minute, second);
        }
      }
    } catch (_) {}

    return null;
  }

  /// Parse Customers from Excel file
  static List<Customer> parseCustomers(List<int> bytes) {
    final fixedBytes = fixExcelPrefixesAndRels(bytes);
    final excel = Excel.decodeBytes(fixedBytes);
    if (excel.tables.isEmpty) return [];

    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName];
    if (sheet == null || sheet.maxRows <= 0) return [];

    // Identify header positions
    final headerRow = sheet.rows.first;
    final headerToIndex = <String, int>{};
    for (int i = 0; i < headerRow.length; i++) {
      final val = _cellValueToString(headerRow[i]?.value).trim().toLowerCase();
      final field = _customerHeaderMap[val];
      if (field != null) {
        headerToIndex[field] = i;
      }
    }

    final customers = <Customer>[];

    // Read subsequent rows
    for (int r = 1; r < sheet.maxRows; r++) {
      final row = sheet.rows[r];
      if (row.isEmpty) continue;

      String getValue(String field) {
        final idx = headerToIndex[field];
        if (idx == null || idx >= row.length) return '';
        return _cellValueToString(row[idx]?.value).trim();
      }

      double? getDoubleValue(String field) {
        final idx = headerToIndex[field];
        if (idx == null || idx >= row.length) return null;
        return _parseDouble(row[idx]?.value);
      }

      String? getDateString(String field) {
        final idx = headerToIndex[field];
        if (idx == null || idx >= row.length) return null;
        return _parseDateToString(row[idx]?.value);
      }

      final id = getValue('id');
      final name = getValue('name');

      // Basic validation: must have at least ID or Name
      if (id.isEmpty && name.isEmpty) continue;

      final actualId = id.isNotEmpty
          ? id
          : 'customer_${DateTime.now().microsecondsSinceEpoch}';

      customers.add(Customer(
        id: actualId,
        name: name.isNotEmpty ? name : 'Khách hàng không tên',
        phone: getValue('phone'),
        email: getValue('email'),
        address: getValue('address'),
        purchases: const [],
        // Empty initially on import
        type: getValue('type'),
        branch: getValue('branch'),
        deliveryArea: getValue('deliveryArea'),
        ward: getValue('ward'),
        company: getValue('company'),
        taxCode: getValue('taxCode'),
        identityCard: getValue('identityCard'),
        dob: getValue('dob'),
        gender: getValue('gender'),
        facebook: getValue('facebook'),
        group: getValue('group'),
        notes: getValue('notes'),
        createdBy: getValue('createdBy'),
        createdAt: getDateString('createdAt'),
        lastTransactionDate: getDateString('lastTransactionDate'),
        currentDebt: getDoubleValue('currentDebt'),
        totalSales: getDoubleValue('totalSales'),
        netSales: getDoubleValue('netSales'),
        status: getValue('status'),
      ));
    }

    return customers;
  }

  /// Parse Products from Excel file
  static List<Product> parseProducts(List<int> bytes) {
    final fixedBytes = fixExcelPrefixesAndRels(bytes);
    final excel = Excel.decodeBytes(fixedBytes);
    if (excel.tables.isEmpty) return [];

    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName];
    if (sheet == null || sheet.maxRows <= 0) return [];

    // Identify header positions
    final headerRow = sheet.rows.first;
    final headerToIndex = <String, int>{};
    for (int i = 0; i < headerRow.length; i++) {
      final val = _cellValueToString(headerRow[i]?.value).trim().toLowerCase();
      final field = _productHeaderMap[val];
      if (field != null) {
        headerToIndex[field] = i;
      }
    }

    final products = <Product>[];

    for (int r = 1; r < sheet.maxRows; r++) {
      final row = sheet.rows[r];
      if (row.isEmpty) continue;

      String getValue(String field) {
        final idx = headerToIndex[field];
        if (idx == null || idx >= row.length) return '';
        return _cellValueToString(row[idx]?.value).trim();
      }

      double getDoubleValue(String field, double fallback) {
        final idx = headerToIndex[field];
        if (idx == null || idx >= row.length) return fallback;
        return _parseDouble(row[idx]?.value) ?? fallback;
      }

      int getIntValue(String field, int fallback) {
        final idx = headerToIndex[field];
        if (idx == null || idx >= row.length) return fallback;
        final d = _parseDouble(row[idx]?.value);
        return d != null ? d.round() : fallback;
      }

      final code = getValue('code');
      final name = getValue('name');

      if (code.isEmpty && name.isEmpty) continue;

      final actualCode = code.isNotEmpty
          ? code
          : 'prod_${DateTime.now().microsecondsSinceEpoch}';
      final actualId =
          actualCode; // Map code directly to id for matching KiotViet standard

      final category = getValue('category3Levels');
      final rootCategory = category.split('>>').first;
      final rawImageUrl = getValue('imageUrl');

      products.add(Product(
        id: actualId,
        code: actualCode,
        name: name.isNotEmpty ? name : 'Sản phẩm không tên',
        barcode: getValue('barcode'),
        brand: 'Khác',
        // Default since Excel lacks brand
        model: 'Khác',
        // Default since Excel lacks model
        price: getDoubleValue('price', 0.0),
        costPrice: getDoubleValue('costPrice', 0.0),
        branchStocks: {
          'store_001': getIntValue('stock', 0),
          'store_002': 0,
        },
        // Excel default stock goes to canonical store_001 (Chi nhánh Đông Thắng)
        category: rootCategory.isNotEmpty ? rootCategory : 'Khác',
        type: getValue('type'),
        category3Levels: category,
        unit: getValue('unit'),
        description: getValue('description'),
        noteTemplate: getValue('noteTemplate'),
        components: getValue('components'),
        imageUrl: rawImageUrl.isNotEmpty ? rawImageUrl : null,
      ));
    }

    return products;
  }

  /// Export Customers to Excel byte array
  static Future<Uint8List> exportCustomers(List<Customer> customers) async {
    final excel = Excel.createExcel();
    const sheetName = 'Danh sách khách hàng';
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null) {
      excel.rename(defaultSheet, sheetName);
    }
    final sheet = excel[sheetName];

    // Write Headers
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
      'Trạng thái'
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // Write Data
    for (int r = 0; r < customers.length; r++) {
      final c = customers[r];
      final values = [
        c.type ?? 'Cá nhân',
        c.branch ?? '',
        c.id,
        c.name,
        c.phone,
        c.address,
        c.deliveryArea ?? '',
        c.ward ?? '',
        c.company ?? '',
        c.taxCode ?? '',
        c.identityCard ?? '',
        c.dob ?? '',
        c.gender ?? '',
        c.email,
        c.facebook ?? '',
        c.group ?? '',
        c.notes ?? '',
        c.createdBy ?? '',
        c.createdAt ?? '',
        c.lastTransactionDate ?? '',
        c.currentDebt ?? 0.0,
        c.totalSales ?? 0.0,
        c.netSales ?? 0.0,
        c.status ?? '1'
      ];

      for (int col = 0; col < values.length; col++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: r + 1));
        final val = values[col];
        if (val is double) {
          cell.value = DoubleCellValue(val);
        } else if (val is int) {
          cell.value = IntCellValue(val);
        } else {
          cell.value = TextCellValue(val.toString());
        }
      }
    }

    final bytes = excel.encode()!;
    return Uint8List.fromList(bytes);
  }

  /// Export Customers to Excel file on disk for sharing
  static Future<File> exportCustomersToFile(List<Customer> customers) async {
    final bytes = await exportCustomers(customers);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/DanhSachKhachHang_Export.xlsx');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Convenient alias for exportCustomers
  static Future<Uint8List> exportCustomersBytes(List<Customer> customers) =>
      exportCustomers(customers);

  /// Export Products to Excel byte array
  static Future<Uint8List> exportProducts(List<Product> products) async {
    final excel = Excel.createExcel();
    const sheetName = 'Danh sách sản phẩm';
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null) {
      excel.rename(defaultSheet, sheetName);
    }
    final sheet = excel[sheetName];

    // Write Headers
    final headers = [
      'Loại hàng',
      'Nhóm hàng(3 Cấp)',
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
      'Hình ảnh'
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // Write Data
    for (int r = 0; r < products.length; r++) {
      final p = products[r];
      final values = [
        p.type ?? 'Hàng hóa',
        p.category3Levels ?? p.category,
        p.code,
        p.barcode ?? '',
        p.name,
        p.price,
        p.costPrice,
        p.stock,
        p.unit ?? 'Cái',
        p.description ?? '',
        p.noteTemplate ?? '',
        p.components ?? '',
        p.imageUrl ?? ''
      ];

      for (int col = 0; col < values.length; col++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: r + 1));
        final val = values[col];
        if (val is double) {
          cell.value = DoubleCellValue(val);
        } else if (val is int) {
          cell.value = IntCellValue(val);
        } else {
          cell.value = TextCellValue(val.toString());
        }
      }
    }

    final bytes = excel.encode()!;
    return Uint8List.fromList(bytes);
  }

  /// Export Products to Excel file on disk for sharing
  static Future<File> exportProductsToFile(List<Product> products) async {
    final bytes = await exportProducts(products);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Products_Export.xlsx');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Convenient alias for exportProducts
  static Future<Uint8List> exportProductsBytes(List<Product> products) =>
      exportProducts(products);

  /// Parse Suppliers from Excel file
  static List<Supplier> parseSuppliers(List<int> bytes) {
    try {
      final fixedBytes = fixExcelPrefixesAndRels(bytes);
      final excel = Excel.decodeBytes(fixedBytes);
      if (excel.tables.isEmpty) return [];

      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null || sheet.maxRows <= 0) return [];

      // Find header row (search first 15 rows)
      int headerRowIndex = 0;
      for (int r = 0; r < sheet.maxRows && r < 15; r++) {
        final row = sheet.rows[r];
        final hasHeader = row.any((cell) {
          final val = _cellValueToString(cell?.value).trim().toLowerCase();
          return val == 'mã nhà cung cấp' ||
              val == 'mã ncc' ||
              val == 'tên ncc' ||
              val == 'tên nhà cung cấp';
        });
        if (hasHeader) {
          headerRowIndex = r;
          break;
        }
      }

      final headerRow = sheet.rows[headerRowIndex];
      final headerToIndex = <String, int>{};
      for (int i = 0; i < headerRow.length; i++) {
        final val =
            _cellValueToString(headerRow[i]?.value).trim().toLowerCase();
        final field = _supplierHeaderMap[val];
        if (field != null) {
          headerToIndex[field] = i;
        }
      }

      final suppliers = <Supplier>[];

      for (int r = headerRowIndex + 1; r < sheet.maxRows; r++) {
        final row = sheet.rows[r];
        if (row.isEmpty) continue;

        String getValue(String field) {
          final idx = headerToIndex[field];
          if (idx == null || idx >= row.length) return '';
          return _cellValueToString(row[idx]?.value).trim();
        }

        double? getDoubleValue(String field) {
          final idx = headerToIndex[field];
          if (idx == null || idx >= row.length) return null;
          return _parseDouble(row[idx]?.value);
        }

        String? getDateString(String field) {
          final idx = headerToIndex[field];
          if (idx == null || idx >= row.length) return null;
          return _parseDateToString(row[idx]?.value);
        }

        final code = getValue('code');
        final name = getValue('name');

        if (code.isEmpty && name.isEmpty) continue;

        final actualId = code.isNotEmpty
            ? code
            : 'supplier_${DateTime.now().microsecondsSinceEpoch}_$r';
        final actualCode = code.isNotEmpty ? code : actualId;

        final group = getValue('group');
        final rawNote = getValue('note');
        String? note;
        if (group.isNotEmpty) {
          note = rawNote.isNotEmpty ? '[$group] $rawNote' : '[$group]';
        } else if (rawNote.isNotEmpty) {
          note = rawNote;
        }

        final statusRaw = getValue('status');
        final status = (statusRaw == '0' ||
                statusRaw.toLowerCase() == 'inactive' ||
                statusRaw.toLowerCase() == 'ngừng hoạt động')
            ? 'inactive'
            : 'active';

        suppliers.add(Supplier(
          id: actualId,
          code: actualCode,
          name: name.isNotEmpty ? name : 'Nhà cung cấp không tên',
          phone: _normalizePhone(getValue('phone')),
          email: getValue('email'),
          address: getValue('address'),
          taxCode: getValue('taxCode').isNotEmpty ? getValue('taxCode') : null,
          totalPurchase: getDoubleValue('totalPurchase') ?? 0.0,
          currentDebt: getDoubleValue('currentDebt') ?? 0.0,
          note: note,
          status: status,
          branch: getValue('branch').isNotEmpty ? getValue('branch') : null,
          createdAt: getDateString('createdAt'),
          createdBy:
              getValue('createdBy').isNotEmpty ? getValue('createdBy') : null,
        ));
      }

      return suppliers;
    } catch (_) {
      return [];
    }
  }

  /// Export Suppliers to Excel byte array
  static Future<Uint8List> exportSuppliers(List<Supplier> suppliers) async {
    final excel = Excel.createExcel();
    const sheetName = 'Danh sách nhà cung cấp';
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null) {
      excel.rename(defaultSheet, sheetName);
    }
    final sheet = excel[sheetName];

    final headers = [
      'Mã NCC',
      'Tên NCC',
      'Điện thoại',
      'Email',
      'Địa chỉ',
      'Mã số thuế',
      'Tổng mua',
      'Nợ hiện tại',
      'Ghi chú',
      'Trạng thái',
      'Chi nhánh',
      'Ngày tạo',
      'Người tạo',
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    for (int r = 0; r < suppliers.length; r++) {
      final s = suppliers[r];
      final values = [
        s.code.isNotEmpty ? s.code : s.id,
        s.name,
        s.phone,
        s.email,
        s.address,
        s.taxCode ?? '',
        s.totalPurchase,
        s.currentDebt,
        s.note ?? '',
        s.status,
        s.branch ?? '',
        s.createdAt ?? '',
        s.createdBy ?? '',
      ];

      for (int col = 0; col < values.length; col++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: r + 1));
        final val = values[col];
        if (val is double) {
          cell.value = DoubleCellValue(val);
        } else if (val is int) {
          cell.value = IntCellValue(val);
        } else {
          cell.value = TextCellValue(val.toString());
        }
      }
    }

    final bytes = excel.encode()!;
    return Uint8List.fromList(bytes);
  }

  /// Export Suppliers to Excel file on disk for sharing
  static Future<File> exportSuppliersToFile(List<Supplier> suppliers) async {
    final bytes = await exportSuppliers(suppliers);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/DanhSachNhaCungCap_Export.xlsx');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Convenient alias for exportSuppliers
  static Future<Uint8List> exportSuppliersBytes(List<Supplier> suppliers) =>
      exportSuppliers(suppliers);

  /// Parse Invoices/Orders from Excel file (supports both multi-line detailed and summary exports)
  static List<Order> parseInvoices(List<int> bytes, {String? defaultStoreId}) {
    try {
      final fixedBytes = fixExcelPrefixesAndRels(bytes);
      final excel = Excel.decodeBytes(fixedBytes);
      if (excel.tables.isEmpty) return [];

      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null || sheet.maxRows <= 0) return [];

      // Find header row (search first 15 rows for invoice ID header)
      int headerRowIndex = 0;
      for (int r = 0; r < sheet.maxRows && r < 15; r++) {
        final row = sheet.rows[r];
        final hasHeader = row.any((cell) {
          final val = _cellValueToString(cell?.value).trim().toLowerCase();
          return val == 'mã hóa đơn' || val == 'mã hđ' || val == 'mã hd';
        });
        if (hasHeader) {
          headerRowIndex = r;
          break;
        }
      }

      final headerRow = sheet.rows[headerRowIndex];
      final headerToIndex = <String, int>{};
      for (int i = 0; i < headerRow.length; i++) {
        final val = _cellValueToString(headerRow[i]?.value)
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ');
        final field = _invoiceHeaderMap[val];
        if (field != null) {
          headerToIndex[field] = i;
        }
      }

      final ordersMap = <String, _RawOrderData>{};
      final orderSequence = <String>[];

      for (int r = headerRowIndex + 1; r < sheet.maxRows; r++) {
        final row = sheet.rows[r];
        if (row.isEmpty) continue;

        String getValue(String field) {
          final idx = headerToIndex[field];
          if (idx == null || idx >= row.length) return '';
          return _cellValueToString(row[idx]?.value).trim();
        }

        double? getDoubleValue(String field) {
          final idx = headerToIndex[field];
          if (idx == null || idx >= row.length) return null;
          return _parseDouble(row[idx]?.value);
        }

        final rawId = getValue('id').trim();
        if (rawId.isEmpty ||
            rawId.toLowerCase().startsWith('tổng') ||
            rawId.toLowerCase().startsWith('cộng') ||
            rawId.toLowerCase() == 'total') {
          continue;
        }

        final orderId = rawId.replaceAll('.', '_');

        var customerId = getValue('customerId');
        if (customerId.contains('{DEL}')) {
          customerId = customerId.replaceAll('{DEL}', '').trim();
        }
        if (customerId.isEmpty || customerId.toLowerCase() == 'khách lẻ') {
          customerId = 'khach_le';
        }

        final orderDateCell = headerToIndex['orderDate'] != null &&
                headerToIndex['orderDate']! < row.length
            ? row[headerToIndex['orderDate']!]?.value
            : null;
        final createdTimeCell = headerToIndex['createdTime'] != null &&
                headerToIndex['createdTime']! < row.length
            ? row[headerToIndex['createdTime']!]?.value
            : null;
        final createdAtCell = headerToIndex['createdAt'] != null &&
                headerToIndex['createdAt']! < row.length
            ? row[headerToIndex['createdAt']!]?.value
            : null;

        final createdAt =
            _parseDateTime(orderDateCell ?? createdTimeCell ?? createdAtCell) ??
                DateTime.now();

        final rawStatus = getValue('status').trim().toLowerCase();
        String status;
        if (rawStatus.contains('hủy') ||
            rawStatus.contains('huỷ') ||
            rawStatus.contains('cancel') ||
            rawStatus.contains('huy')) {
          status = 'cancelled';
        } else if (rawStatus.contains('trả hàng') ||
            rawStatus.contains('tra hang') ||
            rawStatus.contains('return') ||
            rawStatus.contains('đổi trả') ||
            rawStatus.contains('doi tra')) {
          status = 'returned';
        } else if (rawStatus.contains('lưu tạm') ||
            rawStatus.contains('luu tam') ||
            rawStatus.contains('draft') ||
            rawStatus == 'tạm' ||
            rawStatus == 'tam') {
          status = 'draft';
        } else {
          status = 'completed';
        }

        final rawSubtotal = getDoubleValue('subtotal');
        final rawTotal = getDoubleValue('total');
        final rawDiscount = headerToIndex.containsKey('invoiceDiscount')
            ? (getDoubleValue('invoiceDiscount') ?? 0.0)
            : (getDoubleValue('discount') ?? 0.0);
        final rawNetPayable = getDoubleValue('netPayable');

        // Total reflects gross merchandise value ("Tổng tiền hàng")
        final total = rawSubtotal ??
            (rawNetPayable != null
                ? (rawNetPayable + rawDiscount)
                : (rawTotal ?? 0.0));

        // Discount reflects invoice discount ("Giảm giá hóa đơn")
        final discount = rawDiscount > 0
            ? rawDiscount
            : (rawSubtotal != null &&
                    rawNetPayable != null &&
                    rawSubtotal > rawNetPayable
                ? (rawSubtotal - rawNetPayable)
                : (rawSubtotal != null &&
                        rawTotal != null &&
                        rawSubtotal > rawTotal
                    ? (rawSubtotal - rawTotal)
                    : 0.0));

        // Net payable reflects "Khách cần trả"
        final netPayable = rawNetPayable ??
            (rawSubtotal != null && rawTotal != null
                ? rawTotal
                : (total - discount).clamp(0.0, double.infinity));

        final amountPaid = getDoubleValue('amountPaid') ??
            (status == 'cancelled' ? 0.0 : netPayable);
        final debtAmount = status == 'cancelled'
            ? 0.0
            : (getDoubleValue('debtAmount') ??
                (netPayable - amountPaid).clamp(0.0, double.infinity));
        final cash = getDoubleValue('cash') ?? 0.0;
        final transfer = getDoubleValue('transfer') ?? 0.0;

        final rawMethod = getValue('paymentMethod').trim().toLowerCase();
        String paymentMethod;
        if (rawMethod.contains('kết hợp') ||
            rawMethod.contains('ket hop') ||
            rawMethod == 'split' ||
            (cash > 0 && transfer > 0)) {
          paymentMethod = 'split';
        } else if (rawMethod.contains('chuyển khoản') ||
            rawMethod.contains('chuyen khoan') ||
            rawMethod.contains('banking') ||
            rawMethod == 'transfer' ||
            rawMethod == 'ck' ||
            transfer > 0) {
          paymentMethod = 'transfer';
        } else {
          paymentMethod = 'cash';
        }

        final rawBranch = getValue('branch').toLowerCase();
        String storeId = defaultStoreId ?? 'store_001';
        if (rawBranch.contains('đông thắng') || rawBranch == 'store_001') {
          storeId = 'store_001';
        } else if (rawBranch.contains('thới bình') ||
            rawBranch == 'store_002') {
          storeId = 'store_002';
        }

        final seller = getValue('seller');
        final note = getValue('note');
        final customerName = getValue('customerName');

        if (!ordersMap.containsKey(orderId)) {
          orderSequence.add(orderId);
          ordersMap[orderId] = _RawOrderData(
            id: orderId,
            customerId: customerId,
            customerName: customerName.isNotEmpty ? customerName : null,
            createdAt: createdAt,
            total: total,
            discount: discount,
            netPayable: netPayable,
            amountPaid: amountPaid,
            debtAmount: debtAmount,
            paymentMethod: paymentMethod,
            status: status,
            storeId: storeId,
            seller: seller.isNotEmpty ? seller : null,
            note: note.isNotEmpty ? note : null,
            cashAmount: cash > 0 ? cash : null,
            transferAmount: transfer > 0 ? transfer : null,
            items: [],
          );
        }

        // Check if this row has line item details
        final itemCode = getValue('itemCode');
        final itemName = getValue('itemName');
        final itemQty = getDoubleValue('itemQuantity')?.round() ??
            (int.tryParse(getValue('itemQuantity')) ?? 0);
        final itemTotal = getDoubleValue('itemTotal');
        final itemSellingPrice = getDoubleValue('itemSellingPrice');
        final itemUnitPrice = getDoubleValue('itemUnitPrice');
        double itemPrice = itemSellingPrice ?? itemUnitPrice ?? 0.0;
        if (itemPrice == 0.0 && itemTotal != null && itemQty > 0) {
          itemPrice = itemTotal / itemQty;
        }

        if (itemCode.isNotEmpty || itemName.isNotEmpty) {
          final existingItems = ordersMap[orderId]!.items;
          existingItems.add(OrderItem(
            productId: itemCode.isNotEmpty
                ? itemCode
                : 'item_${orderId}_${existingItems.length + 1}',
            productName: itemName.isNotEmpty ? itemName : 'Hàng hóa',
            quantity: itemQty > 0 ? itemQty : 1,
            price: itemPrice >= 0 ? itemPrice : 0.0,
            warrantyMonths: 0,
            purchaseDate: createdAt,
          ));
        }
      }

      final result = <Order>[];
      for (final orderId in orderSequence) {
        final raw = ordersMap[orderId]!;
        var items = raw.items;
        if (items.isEmpty) {
          // Fallback for summary-only exports
          items = [
            OrderItem(
              productId: 'inv_item_${raw.id}',
              productName: 'Hàng hóa theo hóa đơn ${raw.id}',
              quantity: 1,
              price: raw.total,
              warrantyMonths: 0,
              purchaseDate: raw.createdAt,
            ),
          ];
        }

        var orderTotal = raw.total;
        var orderDiscount = raw.discount;
        if (items.isNotEmpty) {
          final itemsSum =
              items.fold<double>(0.0, (sum, i) => sum + (i.price * i.quantity));
          if (itemsSum > orderTotal + 0.01) {
            orderTotal = itemsSum;
            if (orderDiscount <= 0.01) {
              orderDiscount = itemsSum - raw.total;
            }
          }
        }

        result.add(Order(
          id: raw.id,
          customerId: raw.customerId,
          customerName: raw.customerName,
          createdAt: raw.createdAt,
          items: items,
          total: orderTotal,
          discount: orderDiscount,
          status: raw.status,
          amountPaid: raw.amountPaid,
          debtAmount: raw.status == 'cancelled' ? 0.0 : raw.debtAmount,
          paymentMethod: raw.paymentMethod,
          createdBy: raw.seller,
          createdByName: raw.seller,
          storeId: raw.storeId,
          cashAmount: raw.cashAmount,
          transferAmount: raw.transferAmount,
          note: raw.note,
        ));
      }

      return result;
    } catch (_) {
      return [];
    }
  }

  /// Parse Stock-In Receipts from Excel file (supports 32-column KiotViet export).
  ///
  /// Features:
  /// - XML pre-repair via [fixExcelPrefixesAndRels]
  /// - Automatic 32-column header row detection within first 15 rows
  /// - Groups item rows by `Mã nhập hàng` (e.g. PN001737) into a consolidated [StockInReceipt]
  /// - Maps branch names ("Chi nhánh Thới Bình" -> 'store_002', "Chi nhánh Đông Thắng" -> 'store_001', fallback to [defaultStoreId] ?? 'store_001')
  /// - Date parsing supporting both Excel serial numbers and ISO/formatted strings
  /// - String handling preventing scientific notation and preserving leading zeros
  static List<StockInReceipt> parseStockInReceipts(
    List<int> bytes, {
    String? defaultStoreId,
  }) {
    try {
      final fixedBytes = fixExcelPrefixesAndRels(bytes);
      final excel = Excel.decodeBytes(fixedBytes);
      if (excel.tables.isEmpty) return [];

      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null || sheet.maxRows <= 0) return [];

      // 1. Scan for header row (check first 15 rows)
      int headerRowIndex = 0;
      for (int r = 0; r < sheet.maxRows && r < 15; r++) {
        final row = sheet.rows[r];
        final hasHeader = row.any((cell) {
          final val = _cellValueToString(cell?.value).trim().toLowerCase();
          return val == 'mã nhập hàng' ||
              val == 'mã phiếu nhập' ||
              val == 'mã phiếu';
        });
        if (hasHeader) {
          headerRowIndex = r;
          break;
        }
      }

      // 2. Map header columns to indices
      final headerRow = sheet.rows[headerRowIndex];
      final headerToIndex = <String, int>{};
      for (int i = 0; i < headerRow.length; i++) {
        final val = _cellValueToString(headerRow[i]?.value)
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ');

        // Disambiguate receipt-level discount (Col 12/M) vs item-level discount (Col 28/AC)
        if (val == 'giảm giá phiếu nhập' ||
            val == 'giảm giá phiếu' ||
            val == 'giảm giá hđ' ||
            val == 'chiết khấu hđ') {
          headerToIndex['discount'] = i;
        } else if (val == 'giảm giá %' ||
            val == '% giảm giá' ||
            val == 'chiết khấu %') {
          headerToIndex['discountPercentage'] = i;
        } else if (val == 'giảm giá' || val == 'chiết khấu') {
          if (i < 20 && !headerToIndex.containsKey('discount')) {
            headerToIndex['discount'] = i;
          } else {
            headerToIndex['itemDiscount'] = i;
          }
        } else {
          final field = _stockInReceiptHeaderMap[val];
          if (field != null) {
            headerToIndex[field] = i;
          }
        }
      }

      final receiptsMap = <String, StockInReceipt>{};
      final receiptOrder = <String>[];

      for (int r = headerRowIndex + 1; r < sheet.maxRows; r++) {
        final row = sheet.rows[r];
        if (row.isEmpty) continue;

        String getValue(String field) {
          final idx = headerToIndex[field];
          if (idx == null || idx >= row.length) return '';
          return _parseCleanString(row[idx]?.value);
        }

        double? getDouble(String field) {
          final idx = headerToIndex[field];
          if (idx == null || idx >= row.length) return null;
          return _parseDoubleStrict(row[idx]?.value);
        }

        final rawImportCode = getValue('importCode').trim();
        if (rawImportCode.isEmpty ||
            rawImportCode.toLowerCase().startsWith('tổng') ||
            rawImportCode.toLowerCase().startsWith('cộng') ||
            rawImportCode.toLowerCase() == 'total') {
          continue;
        }

        // Line item fields
        final rawProductId = getValue('productId').trim();
        final rawProductName = getValue('productName').trim();
        final rawBarcode = getValue('barcode').trim();
        final rawUnit = getValue('unit').trim();
        final rawItemNote = getValue('itemNote').trim();
        final rawOrigPrice = getDouble('originalPrice');
        final rawDiscPct = getDouble('discountPercentage') ?? 0.0;
        final rawItemDisc = getDouble('itemDiscount') ?? 0.0;
        final rawUnitPrice = getDouble('unitPrice');
        final rawTotalPrice = getDouble('totalPrice');
        final rawQty = getDouble('quantity')?.round() ??
            int.tryParse(getValue('quantity')) ??
            1;

        // Skip completely empty item rows
        if (rawProductId.isEmpty && rawProductName.isEmpty) {
          continue;
        }

        final double originalPrice = rawOrigPrice ??
            (rawUnitPrice != null ? rawUnitPrice + rawItemDisc : 0.0);
        final double unitPrice = rawUnitPrice ??
            (originalPrice - rawItemDisc).clamp(0.0, double.infinity);
        final int quantity = rawQty > 0 ? rawQty : 1;
        final double lineTotal = rawTotalPrice ?? (quantity * unitPrice);

        final item = StockInReceiptItem(
          transactionId: 'item_${rawImportCode}_$r',
          productId: rawProductId.isNotEmpty ? rawProductId : 'prod_$r',
          productCode: rawProductId.isNotEmpty ? rawProductId : null,
          productName: rawProductName.isNotEmpty ? rawProductName : 'Hàng hóa',
          barcode: rawBarcode.isNotEmpty ? rawBarcode : null,
          unit: rawUnit.isNotEmpty ? rawUnit : null,
          quantity: quantity,
          originalPrice: originalPrice > 0 ? originalPrice : unitPrice,
          discountPercentage: rawDiscPct,
          discount: rawItemDisc,
          unitPrice: unitPrice,
          importPrice: unitPrice,
          note: rawItemNote,
        );

        if (!receiptsMap.containsKey(rawImportCode)) {
          receiptOrder.add(rawImportCode);

          final branchName = getValue('branch').trim();
          final storeId = _mapBranchToStoreId(branchName, defaultStoreId);

          final rawDateCell = headerToIndex['date'] != null &&
                  headerToIndex['date']! < row.length
              ? row[headerToIndex['date']!]?.value
              : null;
          final date = _parseExcelDate(rawDateCell);

          final rawCreatedAtCell = headerToIndex['createdAt'] != null &&
                  headerToIndex['createdAt']! < row.length
              ? row[headerToIndex['createdAt']!]?.value
              : null;
          final createdAt = rawCreatedAtCell != null
              ? _parseExcelDate(rawCreatedAtCell)
              : date;

          final rawUpdatedAtCell = headerToIndex['updatedAt'] != null &&
                  headerToIndex['updatedAt']! < row.length
              ? row[headerToIndex['updatedAt']!]?.value
              : null;
          final updatedAt = rawUpdatedAtCell != null
              ? _parseExcelDate(rawUpdatedAtCell)
              : null;

          final supplierId = getValue('supplierId').trim();
          final supplierName = getValue('supplierName').trim();
          final supplierPhone = _cleanPhoneNumber(
            headerToIndex['supplierPhone'] != null &&
                    headerToIndex['supplierPhone']! < row.length
                ? row[headerToIndex['supplierPhone']!]?.value
                : null,
          );
          final createdBy = getValue('createdBy').trim().isNotEmpty
              ? getValue('createdBy').trim()
              : getValue('importedBy').trim();
          final status = getValue('status').trim().isNotEmpty
              ? getValue('status').trim()
              : 'Đã nhập hàng';
          final note = getValue('note').trim();

          final totalAmount = getDouble('totalAmount');
          final discount = getDouble('discount') ?? 0.0;
          final netPayable = getDouble('netPayable');
          final paidAmount = getDouble('paidAmount') ?? 0.0;
          final effectiveNet =
              netPayable ?? ((totalAmount ?? lineTotal) - discount);
          final debtAmount =
              (effectiveNet - paidAmount).clamp(0.0, double.infinity);

          receiptsMap[rawImportCode] = StockInReceipt(
            id: rawImportCode,
            importCode: rawImportCode,
            date: date,
            storeId: storeId,
            branchName: branchName.isNotEmpty ? branchName : null,
            supplierId: supplierId.isNotEmpty ? supplierId : null,
            supplierName: supplierName.isNotEmpty ? supplierName : null,
            supplierPhone: supplierPhone.isNotEmpty ? supplierPhone : null,
            createdBy: createdBy.isNotEmpty ? createdBy : null,
            createdByName: createdBy.isNotEmpty ? createdBy : null,
            note: note,
            items: [item],
            totalAmount: totalAmount,
            discount: discount,
            netPayable: netPayable ?? effectiveNet,
            paidAmount: paidAmount,
            debtAmount: debtAmount,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
          );
        } else {
          final existing = receiptsMap[rawImportCode]!;
          receiptsMap[rawImportCode] = existing.copyWith(
            items: [...existing.items, item],
          );
        }
      }

      return receiptOrder.map((code) => receiptsMap[code]!).toList();
    } catch (_) {
      return [];
    }
  }

  /// Export Invoices to Excel byte array
  static Future<Uint8List> exportInvoices(
    List<Order> orders, {
    String? storeName,
    String? filterDescription,
    DateTime? exportDate,
    Map<String, Customer>? customerMap,
    Map<String, String>? storeNames,
    String? exportedBy,
  }) async {
    final excel = Excel.createExcel();
    const sheetName = 'Danh sách hóa đơn';
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null) {
      excel.rename(defaultSheet, sheetName);
    }
    final sheet = excel[sheetName];

    final now = exportDate ?? DateTime.now();
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final numFmt = NumberFormat('#,###', 'vi_VN');

    // 1. Calculate Aggregate KPI Totals
    double totalSubtotal = 0.0;
    double totalDiscount = 0.0;
    double totalAmount = 0.0;
    double totalPaid = 0.0;
    double totalDebt = 0.0;

    for (final o in orders) {
      final subtotal = o.items
          .fold<double>(0.0, (sum, item) => sum + (item.price * item.quantity));
      final baseSubtotal = subtotal > 0 ? subtotal : o.total;
      final discount = o.discount > 0
          ? o.discount
          : (baseSubtotal - o.netPayable).clamp(0.0, double.infinity);
      final orderAmount = o.netPayable;
      totalSubtotal += baseSubtotal;
      totalDiscount += discount;
      totalAmount += orderAmount;
      totalPaid += o.amountPaid;
      totalDebt += o.remainingDebt;
    }

    int currentRow = 0;

    // 2. Report Header Block
    // Row 0: Title
    final titleCell = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
    titleCell.value = TextCellValue('BÁO CÁO DANH SÁCH HÓA ĐƠN');
    titleCell.cellStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );
    currentRow++;

    // Row 1: Store & Export Time
    final storeLabel = storeName != null && storeName.isNotEmpty
        ? storeName
        : 'Tất cả chi nhánh';
    final metaRow1 = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
    metaRow1.value = TextCellValue(
        'Chi nhánh: $storeLabel | Ngày xuất: ${dateFmt.format(now)}${exportedBy != null ? ' | Người xuất: $exportedBy' : ''}');
    currentRow++;

    // Row 2: Filter Description if any
    if (filterDescription != null && filterDescription.isNotEmpty) {
      final metaRow2 = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
      metaRow2.value = TextCellValue('Bộ lọc: $filterDescription');
      currentRow++;
    }

    // Row 3: KPI Summary
    final kpiCell = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
    kpiCell.value = TextCellValue(
        'Tổng HĐ: ${orders.length} | Tiền hàng: ${numFmt.format(totalSubtotal)} đ | Giảm giá: ${numFmt.format(totalDiscount)} đ | Tổng cộng: ${numFmt.format(totalAmount)} đ | Đã thanh toán: ${numFmt.format(totalPaid)} đ | Còn nợ: ${numFmt.format(totalDebt)} đ');
    currentRow += 2; // Add blank line before table

    // 3. Table Column Headers
    final headers = [
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
      'Trạng thái'
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: currentRow));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );
    }
    currentRow++;

    // 4. Data Rows
    for (int r = 0; r < orders.length; r++) {
      final order = orders[r];
      final customer = customerMap?[order.customerId];
      final customerName = customer?.name ??
          (order.customerName != null && order.customerName!.trim().isNotEmpty
              ? order.customerName!
              : (order.customerId == 'khach_le' || order.customerId == 'walk_in'
                  ? 'Khách lẻ'
                  : (order.customerId.isNotEmpty
                      ? order.customerId
                      : 'Khách lẻ')));
      final customerPhone = customer?.phone ?? '';

      final sellerName = (order.createdByName != null &&
              order.createdByName!.trim().isNotEmpty)
          ? order.createdByName!
          : (order.createdBy ?? '');

      String branchName = '';
      if (storeNames != null &&
          order.storeId != null &&
          storeNames.containsKey(order.storeId)) {
        branchName = storeNames[order.storeId]!;
      } else if (order.storeId == 'store_001' || order.storeId == 'branch_1') {
        branchName = 'Chi nhánh Đông Thắng';
      } else if (order.storeId == 'store_002' || order.storeId == 'branch_2') {
        branchName = 'Chi nhánh Thới Bình';
      } else {
        branchName = order.storeId ?? storeName ?? '';
      }

      final subtotal = order.items
          .fold<double>(0.0, (sum, item) => sum + (item.price * item.quantity));
      final baseSubtotal = subtotal > 0 ? subtotal : order.total;
      final discount = order.discount > 0
          ? order.discount
          : (baseSubtotal - order.netPayable).clamp(0.0, double.infinity);

      final paymentMethodLabel = order.paymentMethod == 'split'
          ? 'Kết hợp'
          : (order.paymentMethod == 'transfer' ? 'Chuyển khoản' : 'Tiền mặt');

      String statusLabel;
      if (order.isCancelled) {
        statusLabel = 'Đã hủy';
      } else if (order.status == 'returned') {
        statusLabel = 'Đã trả hàng';
      } else if (order.status == 'draft') {
        statusLabel = 'Lưu tạm';
      } else {
        statusLabel = 'Đã thanh toán';
      }

      final rowValues = [
        r + 1, // STT
        order.id, // Mã HĐ
        dateFmt.format(order.createdAt), // Thời gian
        order.customerId, // Mã KH
        customerName, // Tên KH
        customerPhone, // SĐT
        sellerName, // Người bán
        branchName, // Chi nhánh
        baseSubtotal, // Tiền hàng
        discount, // Giảm giá
        order.netPayable, // Tổng cộng
        order.amountPaid, // Đã thanh toán
        order.remainingDebt, // Còn nợ
        paymentMethodLabel, // Phương thức TT
        statusLabel, // Trạng thái
      ];

      for (int col = 0; col < rowValues.length; col++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: currentRow));
        final val = rowValues[col];
        if (val is double) {
          cell.value = DoubleCellValue(val);
        } else if (val is int) {
          cell.value = IntCellValue(val);
        } else {
          cell.value = TextCellValue(val.toString());
        }
      }
      currentRow++;
    }

    // 5. Grand Total Summary Row
    final totalRowIndex = currentRow;
    final totalLabelCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRowIndex));
    totalLabelCell.value = TextCellValue('TỔNG CỘNG');
    totalLabelCell.cellStyle = CellStyle(bold: true);

    // Sum columns: 8 (Tiền hàng), 9 (Giảm giá), 10 (Tổng cộng), 11 (Đã thanh toán), 12 (Còn nợ)
    sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: totalRowIndex))
      ..value = DoubleCellValue(totalSubtotal)
      ..cellStyle = CellStyle(bold: true);

    sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: totalRowIndex))
      ..value = DoubleCellValue(totalDiscount)
      ..cellStyle = CellStyle(bold: true);

    sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: totalRowIndex))
      ..value = DoubleCellValue(totalAmount)
      ..cellStyle = CellStyle(bold: true);

    sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: totalRowIndex))
      ..value = DoubleCellValue(totalPaid)
      ..cellStyle = CellStyle(bold: true);

    sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: totalRowIndex))
      ..value = DoubleCellValue(totalDebt)
      ..cellStyle = CellStyle(bold: true);

    final encoded = excel.encode();
    return Uint8List.fromList(encoded ?? []);
  }

  /// Export Invoices to Excel file on disk for sharing
  static Future<File> exportInvoicesToFile(
    List<Order> orders, {
    String? storeName,
    String? filterDescription,
    DateTime? exportDate,
    Map<String, Customer>? customerMap,
    Map<String, String>? storeNames,
    String? exportedBy,
  }) async {
    final bytes = await exportInvoices(
      orders,
      storeName: storeName,
      filterDescription: filterDescription,
      exportDate: exportDate,
      customerMap: customerMap,
      storeNames: storeNames,
      exportedBy: exportedBy,
    );
    final dir = await getTemporaryDirectory();
    final timestamp =
        DateFormat('yyyyMMdd_HHmmss').format(exportDate ?? DateTime.now());
    final file = File('${dir.path}/DanhSachHoaDon_$timestamp.xlsx');
    await file.writeAsBytes(bytes);
    return file;
  }

  static String fixWorksheetXml(String xmlString) {
    try {
      final doc = XmlDocument.parse(xmlString);
      final cells = doc.findAllElements('c');
      bool modified = false;

      for (final cell in cells) {
        final type = cell.getAttribute('t');
        if (type == 's' || type == 'b' || type == 'e' || type == 'str') {
          final vNode = cell.findElements('v');
          if (vNode.isEmpty) {
            cell.children.add(XmlElement(XmlName('v'), [], [XmlText('')]));
            modified = true;
          }
        }
      }

      if (modified) {
        return doc.toXmlString();
      }
    } catch (e) {
      // Silently ignore parsing issues to fallback
    }
    return xmlString;
  }

  static List<int> fixExcelPrefixesAndRels(List<int> bytes) {
    try {
      final decoder = ZipDecoder();
      final archive = decoder.decodeBytes(bytes);

      bool modified = false;

      for (final file in archive.files) {
        if (file.name.endsWith('.xml') || file.name.endsWith('.xml.rels')) {
          var content = utf8.decode(file.content as List<int>);
          bool fileModified = false;

          // 1) Fix workbook.xml.rels Target="/xl/..."
          if (file.name == 'xl/_rels/workbook.xml.rels' &&
              content.contains('Target="/xl/')) {
            content = content.replaceAll('Target="/xl/', 'Target="');
            fileModified = true;
          }

          // 2) Map custom number formats in styles.xml from range [50, 163] to [164, 277] to bypass package:excel checks
          if (file.name == 'xl/styles.xml') {
            final original = content;
            content =
                content.replaceAllMapped(RegExp(r'numFmtId="(\d+)"'), (match) {
              final originalId = int.parse(match.group(1)!);
              if (originalId >= 50 && originalId < 164) {
                final newId = 164 + (originalId - 50);
                return 'numFmtId="$newId"';
              }
              return match.group(0)!;
            });
            if (content != original) {
              fileModified = true;
            }
          }

          // 3) Strip namespace prefix 'x:'
          if (content.contains('<x:') || content.contains('</x:')) {
            content = content.replaceAll('<x:', '<');
            content = content.replaceAll('</x:', '</');
            content = content.replaceAll(
              RegExp(r'xmlns:x="[^"]*"'),
              'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"',
            );
            fileModified = true;
          }

          // 4) Fix cells of type s, b, e, str that lack a <v> element
          if (file.name.contains('xl/worksheets/sheet')) {
            final original = content;
            content = fixWorksheetXml(content);
            if (content != original) {
              fileModified = true;
            }
          }

          if (fileModified) {
            final newFile = ArchiveFile(
              file.name,
              utf8.encode(content).length,
              utf8.encode(content),
            );
            archive.addFile(newFile);
            modified = true;
          }
        }
      }

      if (modified) {
        final encoder = ZipEncoder();
        return encoder.encode(archive)!;
      }
    } catch (e) {
      // Fail-safe: return original bytes on error
    }
    return bytes;
  }
}

class _RawOrderData {
  final String id;
  final String customerId;
  final String? customerName;
  final DateTime createdAt;
  final double total;
  final double discount;
  final double netPayable;
  final double amountPaid;
  final double debtAmount;
  final String paymentMethod;
  final String status;
  final String storeId;
  final String? seller;
  final String? note;
  final double? cashAmount;
  final double? transferAmount;
  final List<OrderItem> items;

  _RawOrderData({
    required this.id,
    required this.customerId,
    this.customerName,
    required this.createdAt,
    required this.total,
    this.discount = 0.0,
    this.netPayable = 0.0,
    required this.amountPaid,
    required this.debtAmount,
    required this.paymentMethod,
    required this.status,
    required this.storeId,
    this.seller,
    this.note,
    this.cashAmount,
    this.transferAmount,
    required this.items,
  });
}

/// Backward compatibility extension for callers that access `.path` on Uint8List during transition.
extension ExcelBytesLegacyCompat on Uint8List {
  String get path => '';
}
