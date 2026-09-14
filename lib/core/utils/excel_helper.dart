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
import '../../domain/entities/product.dart';


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

  /// Export Customers to Excel file and return path
  static Future<File> exportCustomers(List<Customer> customers) async {
    final excel = Excel.createExcel();
    const sheetName = 'Danh sách khách hàng';
    excel.rename(excel.getDefaultSheet()!, sheetName);
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

    final bytes = excel.encode();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/DanhSachKhachHang_Export.xlsx');
    await file.writeAsBytes(bytes!);
    return file;
  }

  /// Export Products to Excel file and return path
  static Future<File> exportProducts(List<Product> products) async {
    final excel = Excel.createExcel();
    const sheetName = 'Danh sách sản phẩm';
    excel.rename(excel.getDefaultSheet()!, sheetName);
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

    final bytes = excel.encode();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Products_Export.xlsx');
    await file.writeAsBytes(bytes!);
    return file;
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
      final subtotal = o.items.fold<double>(
          0.0, (sum, item) => sum + (item.price * item.quantity));
      final discount = (subtotal - o.total).clamp(0.0, double.infinity);
      totalSubtotal += subtotal;
      totalDiscount += discount;
      totalAmount += o.total;
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
    final storeLabel =
        storeName != null && storeName.isNotEmpty ? storeName : 'Tất cả chi nhánh';
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
          (order.customerId == 'khach_le' || order.customerId == 'walk_in'
              ? 'Khách lẻ'
              : (order.customerId.isNotEmpty ? order.customerId : 'Khách lẻ'));
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

      final subtotal = order.items.fold<double>(
          0.0, (sum, item) => sum + (item.price * item.quantity));
      final discount = (subtotal - order.total).clamp(0.0, double.infinity);

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
        subtotal, // Tiền hàng
        discount, // Giảm giá
        order.total, // Tổng cộng
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
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: totalRowIndex))
      ..value = DoubleCellValue(totalSubtotal)
      ..cellStyle = CellStyle(bold: true);

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: totalRowIndex))
      ..value = DoubleCellValue(totalDiscount)
      ..cellStyle = CellStyle(bold: true);

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: totalRowIndex))
      ..value = DoubleCellValue(totalAmount)
      ..cellStyle = CellStyle(bold: true);

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: totalRowIndex))
      ..value = DoubleCellValue(totalPaid)
      ..cellStyle = CellStyle(bold: true);

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: totalRowIndex))
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
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(exportDate ?? DateTime.now());
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
