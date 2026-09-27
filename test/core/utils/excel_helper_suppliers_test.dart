import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/excel_helper.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      return Directory.systemTemp.path;
    },
  );

  group('ExcelHelper Supplier Tests', () {
    final sampleSuppliers = [
      const Supplier(
        id: 'NCC001',
        code: 'NCC001',
        name: 'Công ty Cổ phần Gỗ Việt',
        phone: '0912345678',
        email: 'goviet@example.com',
        address: '123 Đường 3/2, Q. Ninh Kiều, Cần Thơ',
        taxCode: '1801234567',
        totalPurchase: 550000000.0,
        currentDebt: 120000000.0,
        note: 'Ưu tiên nhập hàng đầu tháng',
        status: 'active',
        branch: 'store_001',
        createdAt: '2026-01-15T08:30:00.000',
        createdBy: 'admin',
      ),
      const Supplier(
        id: 'NCC002',
        code: 'NCC002',
        name: 'Xưởng Mộc Bình Minh',
        phone: '0987654321',
        email: 'binhminh@example.com',
        address: 'Thới Bình, Cà Mau',
        taxCode: '2000987654',
        totalPurchase: 80000000.0,
        currentDebt: 0.0,
        note: null,
        status: 'inactive',
        branch: 'store_002',
        createdAt: '2026-03-20T10:15:00.000',
        createdBy: 'manager',
      ),
    ];

    test('exportSuppliers returns valid Uint8List and creates correct Excel sheet', () async {
      final bytes = await ExcelHelper.exportSuppliers(sampleSuppliers);
      expect(bytes, isA<Uint8List>());
      expect(bytes, isNotEmpty);

      final excel = Excel.decodeBytes(bytes);
      expect(excel.tables.containsKey('Danh sách nhà cung cấp'), isTrue);

      final sheet = excel.tables['Danh sách nhà cung cấp']!;
      expect(sheet.maxRows, greaterThanOrEqualTo(3)); // 1 header + 2 data rows

      // Check header values
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
        expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value.toString(), headers[i]);
      }

      // Check Row 1 data
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value.toString(), 'NCC001');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value.toString(), 'Công ty Cổ phần Gỗ Việt');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1)).value.toString(), '0912345678');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 1)).value.toString(), '1801234567');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 1)).value.toString(), anyOf('550000000', '550000000.0'));
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 1)).value.toString(), anyOf('120000000', '120000000.0'));
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 1)).value.toString(), 'Ưu tiên nhập hàng đầu tháng');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: 1)).value.toString(), 'active');

      // Check Row 2 data
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value.toString(), 'NCC002');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)).value.toString(), 'Xưởng Mộc Bình Minh');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: 2)).value.toString(), 'inactive');
    });

    test('parseSuppliers parses exported bytes back into Supplier list with fidelity', () async {
      final bytes = await ExcelHelper.exportSuppliers(sampleSuppliers);
      final parsed = ExcelHelper.parseSuppliers(bytes);

      expect(parsed.length, equals(2));

      final s1 = parsed[0];
      expect(s1.code, equals('NCC001'));
      expect(s1.name, equals('Công ty Cổ phần Gỗ Việt'));
      expect(s1.phone, equals('0912345678'));
      expect(s1.email, equals('goviet@example.com'));
      expect(s1.address, equals('123 Đường 3/2, Q. Ninh Kiều, Cần Thơ'));
      expect(s1.taxCode, equals('1801234567'));
      expect(s1.totalPurchase, equals(550000000.0));
      expect(s1.currentDebt, equals(120000000.0));
      expect(s1.note, equals('Ưu tiên nhập hàng đầu tháng'));
      expect(s1.status, equals('active'));
      expect(s1.branch, equals('store_001'));

      final s2 = parsed[1];
      expect(s2.code, equals('NCC002'));
      expect(s2.name, equals('Xưởng Mộc Bình Minh'));
      expect(s2.phone, equals('0987654321'));
      expect(s2.currentDebt, equals(0.0));
      expect(s2.status, equals('inactive'));
      expect(s2.branch, equals('store_002'));
    });

    test('parseSuppliers handles KiotViet variations: group, alternate headers, phone normalization', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      // KiotViet headers
      final headers = [
        'Mã nhà cung cấp',
        'Tên nhà cung cấp',
        'Số điện thoại',
        'Email',
        'Địa chỉ',
        'MST',
        'Nhóm nhà cung cấp',
        'Ghi chú',
        'Nợ cần trả hiện tại',
        'Tổng mua',
        'Trạng thái',
      ];

      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      // Row 1: phone as 9 digits without leading 0, group specified
      final r1 = [
        'NCC_KV_01',
        'Công ty TNHH Nhập Khẩu Sắt',
        '939123456', // 9 digits -> should be normalized to 0939123456
        'satnhapkhau@gmail.com',
        'Thới Bình',
        '1800112233',
        'Nhà cung cấp kim khí',
        'Giao hàng tận nơi',
        15000000,
        50000000,
        '1', // active
      ];

      for (int col = 0; col < r1.length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 1));
        final val = r1[col];
        if (val is int) {
          cell.value = IntCellValue(val);
        } else {
          cell.value = TextCellValue(val.toString());
        }
      }

      // Row 2: inactive status text and phone ending in .0
      final r2 = [
        'NCC_KV_02',
        'Cửa hàng Phụ kiện Cũ',
        '0949888999.0', // float string
        '',
        '',
        '',
        '',
        '',
        0,
        1000000,
        'Ngừng hoạt động',
      ];

      for (int col = 0; col < r2.length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 2));
        final val = r2[col];
        if (val is int) {
          cell.value = IntCellValue(val);
        } else {
          cell.value = TextCellValue(val.toString());
        }
      }

      final bytes = excel.encode()!;
      final parsed = ExcelHelper.parseSuppliers(bytes);

      expect(parsed.length, equals(2));

      expect(parsed[0].code, equals('NCC_KV_01'));
      expect(parsed[0].name, equals('Công ty TNHH Nhập Khẩu Sắt'));
      expect(parsed[0].phone, equals('0939123456'));
      expect(parsed[0].note, equals('[Nhà cung cấp kim khí] Giao hàng tận nơi'));
      expect(parsed[0].currentDebt, equals(15000000.0));
      expect(parsed[0].totalPurchase, equals(50000000.0));
      expect(parsed[0].status, equals('active'));

      expect(parsed[1].code, equals('NCC_KV_02'));
      expect(parsed[1].phone, equals('0949888999'));
      expect(parsed[1].status, equals('inactive'));
    });

    test('parseSuppliers returns empty list on invalid or empty bytes', () {
      expect(ExcelHelper.parseSuppliers([]), isEmpty);
      expect(ExcelHelper.parseSuppliers([1, 2, 3, 4, 5]), isEmpty);
    });

    test('exportSuppliersToFile writes file to disk and alias works', () async {
      final file = await ExcelHelper.exportSuppliersToFile(sampleSuppliers);
      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(0));

      final bytes = await ExcelHelper.exportSuppliersBytes(sampleSuppliers);
      expect(bytes, isNotEmpty);
    });
  });

  group('ExcelHelper Customer and Product Export Uint8List Tests', () {
    test('exportCustomers returns Uint8List and can be parsed back', () async {
      final customers = [
        const Customer(
          id: 'KH001',
          name: 'Nguyễn Văn An',
          phone: '0901234567',
          email: 'an@example.com',
          address: 'Cần Thơ',
          currentDebt: 500000.0,
          totalSales: 2000000.0,
          group: 'Khách VIP',
          notes: 'Khách quen',
          purchases: [],
        ),
      ];

      final bytes = await ExcelHelper.exportCustomers(customers);
      expect(bytes, isA<Uint8List>());
      expect(bytes, isNotEmpty);

      // Verify parseCustomers can parse the exported bytes
      final parsed = ExcelHelper.parseCustomers(bytes);
      expect(parsed.length, equals(1));
      expect(parsed.first.id, equals('KH001'));
      expect(parsed.first.name, equals('Nguyễn Văn An'));
      expect(parsed.first.phone, equals('0901234567'));
      expect(parsed.first.currentDebt, equals(500000.0));

      // Test exportCustomersToFile and exportCustomersBytes
      final file = await ExcelHelper.exportCustomersToFile(customers);
      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(0));

      final bytesAlias = await ExcelHelper.exportCustomersBytes(customers);
      expect(bytesAlias, isNotEmpty);
    });

    test('exportProducts returns Uint8List and can be parsed back', () async {
      final products = [
        const Product(
          id: 'SP001',
          code: 'SP001',
          name: 'Bàn ăn 6 ghế gỗ xoan',
          price: 8500000.0,
          costPrice: 5000000.0,
          branchStocks: {'store_001': 12},
          unit: 'Bộ',
          category: 'Bàn ăn',
          category3Levels: 'Bàn ăn>>Bàn ăn gỗ>>6 ghế',
          type: 'Hàng hóa',
          description: 'Gỗ xoan đào tự nhiên',
        ),
      ];

      final bytes = await ExcelHelper.exportProducts(products);
      expect(bytes, isA<Uint8List>());
      expect(bytes, isNotEmpty);

      // Verify parseProducts can parse the exported bytes
      final parsed = ExcelHelper.parseProducts(bytes);
      expect(parsed.length, equals(1));
      expect(parsed.first.code, equals('SP001'));
      expect(parsed.first.name, equals('Bàn ăn 6 ghế gỗ xoan'));
      expect(parsed.first.price, equals(8500000.0));
      expect(parsed.first.costPrice, equals(5000000.0));
      expect(parsed.first.stock, equals(12));
      expect(parsed.first.category3Levels, equals('Bàn ăn>>Bàn ăn gỗ>>6 ghế'));

      // Test exportProductsToFile and exportProductsBytes
      final file = await ExcelHelper.exportProductsToFile(products);
      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(0));

      final bytesAlias = await ExcelHelper.exportProductsBytes(products);
      expect(bytesAlias, isNotEmpty);
    });
  });

  group('ExcelHelper Invoice Parser Tests', () {
    test('parseInvoices parses round-trip from exportInvoices (Summary format)', () async {
      final now = DateTime(2026, 8, 20, 10, 0);
      final orders = [
        Order(
          id: 'HD_SUM_01',
          customerId: 'KH001',
          createdAt: now,
          items: [
            OrderItem(
              productId: 'SP01',
              productName: 'Tủ áo 3 cánh',
              quantity: 1,
              price: 4500000,
              warrantyMonths: 12,
              purchaseDate: now,
            ),
          ],
          total: 4500000,
          amountPaid: 4500000,
          debtAmount: 0,
          paymentMethod: 'cash',
          storeId: 'store_001',
        ),
        Order(
          id: 'HD_SUM_02',
          customerId: 'KH002',
          createdAt: now.add(const Duration(hours: 1)),
          items: [
            OrderItem(
              productId: 'SP02',
              productName: 'Bàn trà sofa',
              quantity: 2,
              price: 1500000,
              warrantyMonths: 6,
              purchaseDate: now,
            ),
          ],
          total: 3000000,
          amountPaid: 1000000,
          debtAmount: 2000000,
          paymentMethod: 'transfer',
          storeId: 'store_002',
        ),
      ];

      final bytes = await ExcelHelper.exportInvoices(orders);
      final parsed = ExcelHelper.parseInvoices(bytes);

      expect(parsed.length, equals(2));

      final o1 = parsed[0];
      expect(o1.id, equals('HD_SUM_01'));
      expect(o1.customerId, equals('KH001'));
      expect(o1.total, equals(4500000.0));
      expect(o1.amountPaid, equals(4500000.0));
      expect(o1.debtAmount, equals(0.0));
      expect(o1.paymentMethod, equals('cash'));
      expect(o1.storeId, equals('store_001'));
      expect(o1.items.length, equals(1)); // Single summary fallback item
      expect(o1.items.first.price, equals(4500000.0));

      final o2 = parsed[1];
      expect(o2.id, equals('HD_SUM_02'));
      expect(o2.customerId, equals('KH002'));
      expect(o2.total, equals(3000000.0));
      expect(o2.amountPaid, equals(1000000.0));
      expect(o2.debtAmount, equals(2000000.0));
      expect(o2.paymentMethod, equals('transfer'));
      expect(o2.storeId, equals('store_002'));
    });

    test('parseInvoices parses detailed multi-line KiotViet format (multiple items per invoice)', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      final headers = [
        'Mã hóa đơn',
        'Thời gian',
        'Mã khách hàng',
        'Tên khách hàng',
        'Người bán',
        'Chi nhánh',
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

      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      // Order 1: 2 line items
      // Line 1
      final row1 = [
        'HD_DET_001',
        '2026-09-01T14:20:00.000',
        'KH005',
        'Lê Thị Mai',
        'admin',
        'Chi nhánh Thới Bình',
        7000000, // Subtotal
        500000,  // Discount
        6500000, // Total
        6500000, // Paid
        3500000, // Cash
        3000000, // Transfer -> split
        'Đã hoàn thành',
        'SP_GHE',
        'Ghế tựa gỗ căm xe',
        4,       // qty
        1000000, // price
        4000000, // total
      ];

      // Line 2
      final row2 = [
        'HD_DET_001',
        '2026-09-01T14:20:00.000',
        'KH005',
        'Lê Thị Mai',
        'admin',
        'Chi nhánh Thới Bình',
        7000000,
        500000,
        6500000,
        6500000,
        3500000,
        3000000,
        'Đã hoàn thành',
        'SP_BAN',
        'Bàn vuông căm xe',
        1,       // qty
        3000000, // price
        3000000, // total
      ];

      // Order 2: 1 line item, debt, cancelled
      final row3 = [
        'HD_DET_002',
        '2026-09-02T09:10:00.000',
        'KH008{DEL}', // Deleted customer tag
        'Trần Văn Nam',
        'staff1',
        'Chi nhánh Đông Thắng',
        2000000,
        0,
        2000000,
        500000,  // Paid
        500000,  // Cash
        0,       // Transfer
        'Đã hủy',
        'SP_KE',
        'Kệ sách gỗ sồi',
        1,
        2000000,
        2000000,
      ];

      final rows = [row1, row2, row3];
      for (int r = 0; r < rows.length; r++) {
        final rowData = rows[r];
        for (int c = 0; c < rowData.length; c++) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
          final val = rowData[c];
          if (val is int) {
            cell.value = IntCellValue(val);
          } else if (val is double) {
            cell.value = DoubleCellValue(val);
          } else {
            cell.value = TextCellValue(val.toString());
          }
        }
      }

      final bytes = excel.encode()!;
      final parsed = ExcelHelper.parseInvoices(bytes);

      // Must be grouped into exactly 2 orders!
      expect(parsed.length, equals(2));

      // Order 1 verification
      final o1 = parsed[0];
      expect(o1.id, equals('HD_DET_001'));
      expect(o1.customerId, equals('KH005'));
      expect(o1.total, equals(7000000.0));
      expect(o1.discount, equals(500000.0));
      expect(o1.netPayable, equals(6500000.0));
      expect(o1.amountPaid, equals(6500000.0));
      expect(o1.debtAmount, equals(0.0));
      expect(o1.paymentMethod, equals('split'));
      expect(o1.status, equals('completed'));
      expect(o1.storeId, equals('store_002'));
      expect(o1.items.length, equals(2));

      expect(o1.items[0].productId, equals('SP_GHE'));
      expect(o1.items[0].productName, equals('Ghế tựa gỗ căm xe'));
      expect(o1.items[0].quantity, equals(4));
      expect(o1.items[0].price, equals(1000000.0));

      expect(o1.items[1].productId, equals('SP_BAN'));
      expect(o1.items[1].productName, equals('Bàn vuông căm xe'));
      expect(o1.items[1].quantity, equals(1));
      expect(o1.items[1].price, equals(3000000.0));

      // Order 2 verification
      final o2 = parsed[1];
      expect(o2.id, equals('HD_DET_002'));
      expect(o2.customerId, equals('KH008')); // {DEL} removed
      expect(o2.total, equals(2000000.0));
      expect(o2.debtAmount, equals(0.0));
      expect(o2.remainingDebt, equals(0.0));
      expect(o2.hasDebt, isFalse);
      expect(o2.paymentMethod, equals('cash'));
      expect(o2.status, equals('cancelled'));
      expect(o2.storeId, equals('store_001'));
      expect(o2.items.length, equals(1));
      expect(o2.items[0].productId, equals('SP_KE'));
    });

    test('parseInvoices handles empty and malformed bytes gracefully', () {
      expect(ExcelHelper.parseInvoices([]), isEmpty);
      expect(ExcelHelper.parseInvoices([1, 2, 3]), isEmpty);
    });
  });
}
