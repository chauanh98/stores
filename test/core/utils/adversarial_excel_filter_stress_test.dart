import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/excel_helper.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/invoice_filter.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      return Directory.systemTemp.path;
    },
  );

  group('Adversarial Excel Export Stress Tests (R2)', () {
    test('1. Empty list export produces valid xlsx structure with zero totals', () async {
      final exportDate = DateTime(2026, 8, 17, 10, 0, 0);
      final bytes = await ExcelHelper.exportInvoices(
        [],
        storeName: 'Tất cả chi nhánh',
        filterDescription: 'Không có hóa đơn',
        exportDate: exportDate,
        exportedBy: 'Admin Test',
      );

      expect(bytes, isA<Uint8List>());
      expect(bytes.length, greaterThan(0));

      final excel = Excel.decodeBytes(bytes);
      expect(excel.tables.containsKey('Danh sách hóa đơn'), isTrue);

      final sheet = excel.tables['Danh sách hóa đơn']!;
      expect(sheet.maxRows, greaterThan(0));

      // Title
      expect(
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value.toString(),
        contains('BÁO CÁO DANH SÁCH HÓA ĐƠN'),
      );

      // Meta & KPI row check
      final kpiCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3)).value.toString();
      expect(kpiCell, contains('Tổng HĐ: 0'));
      expect(kpiCell, contains('Tiền hàng: 0 đ'));
      expect(kpiCell, contains('Giảm giá: 0 đ'));
      expect(kpiCell, contains('Tổng cộng: 0 đ'));
      expect(kpiCell, contains('Đã thanh toán: 0 đ'));
      expect(kpiCell, contains('Còn nợ: 0 đ'));

      // Header row
      int headerRow = -1;
      for (int r = 0; r < sheet.maxRows; r++) {
        final v = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value.toString();
        if (v == 'STT') {
          headerRow = r;
          break;
        }
      }
      expect(headerRow, isNonNegative);

      // Grand total row right after header row since orders is empty
      final totalRow = headerRow + 1;
      expect(
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow)).value.toString(),
        'TỔNG CỘNG',
      );
      // Double check sums are 0.0
      for (int col in [8, 9, 10, 11, 12]) {
        final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: totalRow)).value;
        if (val is DoubleCellValue) {
          expect(val.value, 0.0);
        } else if (val is IntCellValue) {
          expect(val.value, 0);
        }
      }
    });

    test('2. Complex edge-case orders: Null customer IDs, Vietnamese diacritics, emojis, decimals, trillion-scale amounts', () async {
      final exportDate = DateTime(2026, 8, 17, 14, 30, 0);

      const customerSpecial = Customer(
        id: 'KH_VIP_999',
        name: 'Bà Nguyễn Thị Diệu Hiền (Đại lý Út Đẹp 🌾🌾)',
        phone: '0988776655',
        email: 'dieu.hien@mienday.vn',
        address: 'Ấp 4, Xã Đông Thắng, Cờ Đỏ, TP Cần Thơ',
        purchases: [],
      );

      final adversarialOrders = [
        // Order 1: Extreme Vietnamese diacritics & combo characters
        Order(
          id: 'HĐ-ĐẶC-BIỆT-001',
          customerId: 'KH_VIP_999',
          createdAt: DateTime(2026, 8, 1, 8, 15),
          items: [
            OrderItem(
              productId: 'SP_GHE_01',
              productName: 'Ghế massage trị liệu toàn thân nhập khẩu Nhật Bản 🇯🇵 (Màu Nâu Cát)',
              quantity: 2,
              price: 45500000.50,
              warrantyMonths: 36,
              purchaseDate: DateTime(2026, 8, 1),
            ),
            OrderItem(
              productId: 'SP_PHUKIEN_02',
              productName: 'Áo trùm chống bụi & Dầu bảo dưỡng da cao cấp',
              quantity: 5,
              price: 350000.25,
              warrantyMonths: 12,
              purchaseDate: DateTime(2026, 8, 1),
            ),
          ],
          total: 90000000.0, // Subtotal = (45500000.5*2)+(350000.25*5) = 91000001 + 1750001.25 = 92750002.25. Discount = 2750002.25
          amountPaid: 50000000.0,
          debtAmount: 40000000.0,
          paymentMethod: 'transfer',
          createdBy: 'admin_dieu',
          createdByName: 'Đặng Thái Khánh Đăng (Quản trị viên 👑)',
          storeId: 'store_001',
        ),

        // Order 2: Walk-in / empty customer ID, unknown store, zero items (degenerate case)
        Order(
          id: 'HD_EMPTY_CUST',
          customerId: '',
          createdAt: DateTime(2026, 8, 2, 9, 30),
          items: const [],
          total: 0.0,
          amountPaid: 0.0,
          debtAmount: 0.0,
          paymentMethod: 'cash',
          createdBy: null,
          createdByName: null,
          storeId: 'store_unknown_99',
        ),

        // Order 3: Trillion-scale numbers & massive quantities
        Order(
          id: 'HD_TRILLION_003',
          customerId: 'khach_le',
          createdAt: DateTime(2026, 8, 3, 11, 45),
          items: [
            OrderItem(
              productId: 'BULK_CHIP',
              productName: 'Lô vi xử lý AI 3nm thế hệ mới (Đợt 1)',
              quantity: 1000000,
              price: 1500000.0, // 1.5 Trillion VND
              warrantyMonths: 60,
              purchaseDate: DateTime(2026, 8, 3),
            ),
          ],
          total: 1500000000000.0,
          amountPaid: 1000000000000.0,
          debtAmount: 500000000000.0,
          paymentMethod: 'transfer',
          createdBy: 'truong_phong_kd',
          createdByName: 'Võ Hoài Nam',
          storeId: 'store_002',
        ),

        // Order 4: Cancelled Order with fractional amounts
        Order(
          id: 'HD_CANCELLED_004',
          customerId: 'CUST_CANCEL',
          createdAt: DateTime(2026, 8, 4, 16, 20),
          items: [
            OrderItem(
              productId: 'ITEM_DEC',
              productName: 'Mặt hàng tính theo lạng/gam lẻ',
              quantity: 3,
              price: 12345.67,
              warrantyMonths: 0,
              purchaseDate: DateTime(2026, 8, 4),
            ),
          ],
          total: 37037.01,
          amountPaid: 37037.01,
          debtAmount: 0.0,
          paymentMethod: 'cash',
          status: 'cancelled',
          cancelReason: 'Đơn hàng bị hủy do sai sót thông tin',
          cancelledBy: 'admin',
          cancelledByName: 'Admin Hệ Thống',
          storeId: 'store_001',
        ),

        // Order 5: Returned Order with status 'returned'
        Order(
          id: 'HD_RETURNED_005',
          customerId: 'walk_in',
          createdAt: DateTime(2026, 8, 5, 14, 0),
          items: [
            OrderItem(
              productId: 'PROD_RET',
              productName: 'Sản phẩm hoàn trả 100%',
              quantity: 1,
              returnedQuantity: 1,
              price: 500000.0,
              warrantyMonths: 12,
              purchaseDate: DateTime(2026, 8, 5),
            ),
          ],
          total: 500000.0,
          amountPaid: 500000.0,
          debtAmount: 0.0,
          paymentMethod: 'cash',
          status: 'returned',
          storeId: 'store_001',
        ),

        // Order 6: Draft Order with status 'draft'
        Order(
          id: 'HD_DRAFT_006',
          customerId: 'khach_le',
          createdAt: DateTime(2026, 8, 6, 17, 0),
          items: [
            OrderItem(
              productId: 'PROD_DRAFT',
              productName: 'Đơn hàng lưu tạm chưa thanh toán',
              quantity: 2,
              price: 250000.0,
              warrantyMonths: 6,
              purchaseDate: DateTime(2026, 8, 6),
            ),
          ],
          total: 500000.0,
          amountPaid: 0.0,
          debtAmount: 500000.0,
          paymentMethod: 'cash',
          status: 'draft',
          storeId: 'store_002',
        ),
      ];

      final customerMap = {'KH_VIP_999': customerSpecial};
      final storeNames = {
        'store_001': 'Chi nhánh Đông Thắng',
        'store_002': 'Chi nhánh Thới Bình',
        'store_unknown_99': 'Chi nhánh Miền Tây Mới',
      };

      final bytes = await ExcelHelper.exportInvoices(
        adversarialOrders,
        storeName: 'Toàn hệ thống Cửa hàng',
        filterDescription: 'Bộ lọc: Đa chiều nâng cao & Kiểm thử tải',
        exportDate: exportDate,
        customerMap: customerMap,
        storeNames: storeNames,
        exportedBy: 'Khanh Dang (Audit Specialist 🛡️)',
      );

      expect(bytes, isNotEmpty);

      // Decode & Deep Verify Excel
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables['Danh sách hóa đơn']!;

      // Verify Header Block
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value.toString(),
          'BÁO CÁO DANH SÁCH HÓA ĐƠN');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value.toString(),
          contains('Toàn hệ thống Cửa hàng'));
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value.toString(),
          contains('Khanh Dang (Audit Specialist 🛡️)'));
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value.toString(),
          contains('Bộ lọc: Đa chiều nâng cao & Kiểm thử tải'));

      // Find Table Header Row
      int headerRow = -1;
      for (int r = 0; r < sheet.maxRows; r++) {
        final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value.toString();
        if (val == 'STT') {
          headerRow = r;
          break;
        }
      }
      expect(headerRow, 5); // Row index 5 due to blank separator row after KPI header

      final expectedHeaders = [
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

      for (int c = 0; c < expectedHeaders.length; c++) {
        final headerVal = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: headerRow)).value.toString();
        expect(headerVal, expectedHeaders[c], reason: 'Mismatch at header column $c');
      }

      // Verify Row 1: Special Vietnamese diacritics & seller emojis
      final r1 = headerRow + 1;
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r1)).value.toString(), '1');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r1)).value.toString(), 'HĐ-ĐẶC-BIỆT-001');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r1)).value.toString(), 'KH_VIP_999');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r1)).value.toString(),
          'Bà Nguyễn Thị Diệu Hiền (Đại lý Út Đẹp 🌾🌾)');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r1)).value.toString(), '0988776655');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r1)).value.toString(),
          'Đặng Thái Khánh Đăng (Quản trị viên 👑)');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r1)).value.toString(), 'Chi nhánh Đông Thắng');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: r1)).value.toString(), 'Chuyển khoản');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: r1)).value.toString(), 'Đã thanh toán');

      // Verify Row 2: Empty customer ID fallback
      final r2 = headerRow + 2;
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r2)).value.toString(), 'HD_EMPTY_CUST');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r2)).value.toString(), 'Khách lẻ');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r2)).value.toString(), 'Chi nhánh Miền Tây Mới');

      // Verify Row 3: Trillion-scale amount
      final r3 = headerRow + 3;
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r3)).value.toString(), 'HD_TRILLION_003');
      final r3TotalVal = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: r3)).value;
      if (r3TotalVal is DoubleCellValue) {
        expect(r3TotalVal.value, 1500000000000.0);
      } else if (r3TotalVal is IntCellValue) {
        expect(r3TotalVal.value, 1500000000000);
      }

      // Verify Row 4: Cancelled order status
      final r4 = headerRow + 4;
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r4)).value.toString(), 'HD_CANCELLED_004');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: r4)).value.toString(), 'Đã hủy');

      // Verify Row 5: Returned order status
      final r5 = headerRow + 5;
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r5)).value.toString(), 'HD_RETURNED_005');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: r5)).value.toString(), 'Đã trả hàng');

      // Verify Row 6: Draft order status
      final r6 = headerRow + 6;
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r6)).value.toString(), 'HD_DRAFT_006');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: r6)).value.toString(), 'Lưu tạm');

      // Verify Grand Total Row & Mathematical Sums
      final grandTotalRow = headerRow + 7;
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: grandTotalRow)).value.toString(), 'TỔNG CỘNG');

      // Calculate expected sums mathematically:
      double expectedSubtotal = 0.0;
      double expectedDiscount = 0.0;
      double expectedTotal = 0.0;
      double expectedPaid = 0.0;
      double expectedDebt = 0.0;

      for (final o in adversarialOrders) {
        final sub = o.items.fold<double>(0.0, (s, i) => s + (i.price * i.quantity));
        final disc = (sub - o.total).clamp(0.0, double.infinity);
        expectedSubtotal += sub;
        expectedDiscount += disc;
        expectedTotal += o.total;
        expectedPaid += o.amountPaid;
        expectedDebt += o.remainingDebt;
      }

      double numFromCell(CellValue? v) {
        if (v == null) return 0.0;
        if (v is DoubleCellValue) return v.value;
        if (v is IntCellValue) return v.value.toDouble();
        return double.tryParse(v.toString().replaceAll(',', '')) ?? 0.0;
      }

      final cellSubtotal = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: grandTotalRow)).value;
      final cellDiscount = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: grandTotalRow)).value;
      final cellTotal = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: grandTotalRow)).value;
      final cellPaid = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: grandTotalRow)).value;
      final cellDebt = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: grandTotalRow)).value;

      expect(numFromCell(cellSubtotal), closeTo(expectedSubtotal, 0.01));
      expect(numFromCell(cellDiscount), closeTo(expectedDiscount, 0.01));
      expect(numFromCell(cellTotal), closeTo(expectedTotal, 0.01));
      expect(numFromCell(cellPaid), closeTo(expectedPaid, 0.01));
      expect(numFromCell(cellDebt), closeTo(expectedDebt, 0.01));
    });

    test('3. exportInvoicesToFile writes valid .xlsx file to disk and decodes accurately', () async {
      final order = Order(
        id: 'HD_DISK_TEST',
        customerId: 'khach_le',
        createdAt: DateTime(2026, 8, 17, 12, 0),
        items: [
          OrderItem(
            productId: 'P_TEST',
            productName: 'Sản phẩm lưu file',
            quantity: 1,
            price: 100000,
            warrantyMonths: 1,
            purchaseDate: DateTime(2026, 8, 17),
          ),
        ],
        total: 100000,
        amountPaid: 100000,
        debtAmount: 0,
        paymentMethod: 'cash',
        storeId: 'store_001',
      );

      final file = await ExcelHelper.exportInvoicesToFile(
        [order],
        storeName: 'Chi nhánh Đông Thắng',
        exportDate: DateTime(2026, 8, 17, 12, 0),
      );

      expect(await file.exists(), isTrue);
      final readBytes = await file.readAsBytes();
      expect(readBytes, isNotEmpty);

      final excel = Excel.decodeBytes(readBytes);
      expect(excel.tables.containsKey('Danh sách hóa đơn'), isTrue);
    });
  });

  group('Adversarial Multi-dimensional Filtering & Reactive KPIs Stress Tests (R4)', () {
    final t0 = DateTime(2026, 8, 1, 10, 0);
    final t1 = DateTime(2026, 8, 5, 15, 0);
    final t2 = DateTime(2026, 8, 10, 18, 0);
    final t3 = DateTime(2026, 8, 15, 8, 30);
    final t4 = DateTime(2026, 8, 20, 20, 0);

    const cust1 = Customer(
      id: 'CUST_A',
      name: 'Nguyễn Văn An',
      phone: '0912345678',
      email: 'an.nguyen@test.com',
      address: 'Hà Nội',
      purchases: [],
    );

    const cust2 = Customer(
      id: 'CUST_B',
      name: 'Trần Thị Bích Ngọc',
      phone: '0987654321',
      email: 'ngoc.tran@test.com',
      address: 'Đà Nẵng',
      purchases: [],
    );

    const cust3 = Customer(
      id: 'CUST_C',
      name: 'Lê Hoàng Long',
      phone: '0909112233',
      email: 'long.le@test.com',
      address: 'TP.HCM',
      purchases: [],
    );

    final customerList = [cust1, cust2, cust3];
    final customerMap = {for (final c in customerList) c.id: c};

    final testOrders = [
      // Order 0: Completed, Cash, Paid, Staff 1, Customer A
      Order(
        id: 'HD_001',
        customerId: 'CUST_A',
        createdAt: t0,
        items: [
          OrderItem(
            productId: 'P_IPHONE',
            productName: 'iPhone 17 Pro 256GB Titan Tự Nhiên',
            quantity: 1,
            price: 30000000,
            warrantyMonths: 12,
            purchaseDate: t0,
          ),
        ],
        total: 30000000,
        amountPaid: 30000000,
        debtAmount: 0,
        paymentMethod: 'cash',
        status: 'completed',
        createdBy: 'staff_1',
        createdByName: 'Vũ Thị Hằng',
        storeId: 'store_001',
      ),

      // Order 1: Completed, Transfer, Debt, Staff 1, Customer B
      Order(
        id: 'HD_002',
        customerId: 'CUST_B',
        createdAt: t1,
        items: [
          OrderItem(
            productId: 'P_MACBOOK',
            productName: 'MacBook Air M3 16GB',
            quantity: 1,
            price: 28000000,
            warrantyMonths: 12,
            purchaseDate: t1,
          ),
        ],
        total: 28000000,
        amountPaid: 10000000,
        debtAmount: 18000000,
        paymentMethod: 'transfer',
        status: 'completed',
        createdBy: 'staff_1',
        createdByName: 'Vũ Thị Hằng',
        storeId: 'store_001',
      ),

      // Order 2: Completed, Transfer, Debt, Staff 2, Customer C
      Order(
        id: 'HD_003',
        customerId: 'CUST_C',
        createdAt: t2,
        items: [
          OrderItem(
            productId: 'P_AIRPODS',
            productName: 'AirPods Pro 2 USB-C Chống ồn',
            quantity: 2,
            price: 5500000,
            warrantyMonths: 12,
            purchaseDate: t2,
          ),
        ],
        total: 11000000,
        amountPaid: 5000000,
        debtAmount: 6000000,
        paymentMethod: 'transfer',
        status: 'completed',
        createdBy: 'staff_2',
        createdByName: 'Phạm Minh Tuấn',
        storeId: 'store_002',
      ),

      // Order 3: Cancelled, Transfer, Debt, Staff 2, Customer B
      Order(
        id: 'HD_004',
        customerId: 'CUST_B',
        createdAt: t3,
        items: [
          OrderItem(
            productId: 'P_WATCH',
            productName: 'Apple Watch Ultra 2 Dây Alpine',
            quantity: 1,
            price: 21000000,
            warrantyMonths: 12,
            purchaseDate: t3,
          ),
        ],
        total: 21000000,
        amountPaid: 0,
        debtAmount: 21000000,
        paymentMethod: 'transfer',
        status: 'cancelled',
        cancelReason: 'Hủy theo yêu cầu của khách hàng',
        createdBy: 'staff_2',
        createdByName: 'Phạm Minh Tuấn',
        storeId: 'store_002',
      ),

      // Order 4: Draft, Cash, Debt, Staff 3, Walk-in
      Order(
        id: 'HD_005',
        customerId: 'khach_le',
        createdAt: t4,
        items: [
          OrderItem(
            productId: 'P_CASE',
            productName: 'Ốp lưng Silicon dẻo trong suốt',
            quantity: 3,
            price: 150000,
            warrantyMonths: 0,
            purchaseDate: t4,
          ),
        ],
        total: 450000,
        amountPaid: 0,
        debtAmount: 450000,
        paymentMethod: 'cash',
        status: 'draft',
        createdBy: 'staff_3',
        createdByName: 'Hoàng Lan',
        storeId: 'store_001',
      ),
    ];

    // Helper to run filter logic matching InvoicesPage / InvoiceFilter implementation
    List<Order> applyFiltersAdversarial(
      List<Order> orders, {
      String status = 'all',
      String paymentMethod = 'all',
      String debtStatus = 'all',
      String staff = 'all',
      String searchQuery = '',
      DateTime? startDate,
      DateTime? endDate,
    }) {
      return orders.where((order) {
        // Status filter
        if (status != 'all') {
          if (status == 'completed') {
            if (order.status != 'completed' || order.isCancelled) return false;
          } else if (status == 'draft') {
            if (order.status != 'draft') return false;
          } else if (status == 'cancelled') {
            if (!order.isCancelled) return false;
          } else if (order.status != status) {
            return false;
          }
        }

        // Payment Method filter
        if (paymentMethod != 'all') {
          if (order.paymentMethod != paymentMethod) return false;
        }

        // Debt status filter
        if (debtStatus != 'all') {
          if (debtStatus == 'paid') {
            if (order.remainingDebt > 0.001) return false;
          } else if (debtStatus == 'debt') {
            if (order.remainingDebt <= 0.001) return false;
          }
        }

        // Staff filter
        if (staff != 'all') {
          final creator = (order.createdBy ?? '').trim().toLowerCase();
          final creatorName = (order.createdByName ?? '').trim().toLowerCase();
          final target = staff.trim().toLowerCase();
          if (creator != target && creatorName != target) return false;
        }

        // Date range filter
        if (startDate != null) {
          final s = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0, 0);
          if (order.createdAt.isBefore(s)) return false;
        }
        if (endDate != null) {
          final e = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
          if (order.createdAt.isAfter(e)) return false;
        }

        // Search query
        if (searchQuery.trim().isNotEmpty) {
          final q = searchQuery.toLowerCase().trim();
          final cust = customerMap[order.customerId];
          final cName = (cust?.name ?? (order.customerId == 'khach_le' ? 'khách lẻ' : order.customerId)).toLowerCase();
          final cPhone = (cust?.phone ?? '').toLowerCase();
          final cCode = (cust?.id ?? '').toLowerCase();
          final orderId = order.id.toLowerCase();
          final staffName = (order.createdByName ?? order.createdBy ?? '').toLowerCase();
          final itemMatch = order.items.any((i) =>
              i.productName.toLowerCase().contains(q) || i.productId.toLowerCase().contains(q));

          if (!orderId.contains(q) &&
              !cName.contains(q) &&
              !cPhone.contains(q) &&
              !cCode.contains(q) &&
              !staffName.contains(q) &&
              !itemMatch) {
            return false;
          }
        }

        return true;
      }).toList();
    }

    // Helper to calculate reactive KPIs as in InvoicesPage
    Map<String, num> computeReactiveKPIs(List<Order> filteredOrders) {
      final totalInvoices = filteredOrders.length;
      final activeOrders = filteredOrders.where((o) => !o.isCancelled).toList();
      final totalRevenue = activeOrders.fold(0.0, (s, o) => s + o.total);
      final totalPaid = activeOrders.fold(0.0, (s, o) => s + o.amountPaid);
      final totalDebt = activeOrders.fold(0.0, (s, o) => s + o.remainingDebt);
      return {
        'totalInvoices': totalInvoices,
        'activeCount': activeOrders.length,
        'totalRevenue': totalRevenue,
        'totalPaid': totalPaid,
        'totalDebt': totalDebt,
      };
    }

    test('4. Complex filter: status=cancelled + paymentMethod=transfer (cancelled orders have 0 debt)', () {
      // Cancelled orders have remainingDebt == 0, so debtStatus == 'debt' matches 0 orders
      final filteredDebt = applyFiltersAdversarial(
        testOrders,
        status: 'cancelled',
        paymentMethod: 'transfer',
        debtStatus: 'debt',
      );
      expect(filteredDebt, isEmpty, reason: 'Cancelled orders must have 0 debt and cannot match debt filter');

      // With debtStatus == 'all', cancelled order is found and has remainingDebt == 0.0
      final filtered = applyFiltersAdversarial(
        testOrders,
        status: 'cancelled',
        paymentMethod: 'transfer',
      );

      expect(filtered.length, 1);
      expect(filtered.first.id, 'HD_004');
      expect(filtered.first.isCancelled, isTrue);
      expect(filtered.first.paymentMethod, 'transfer');
      expect(filtered.first.remainingDebt, equals(0.0));

      // Check reactive KPI calculation for cancelled orders:
      // totalInvoices counts cancelled, but totalRevenue/totalPaid/totalDebt EXCLUDE cancelled orders
      final kpis = computeReactiveKPIs(filtered);
      expect(kpis['totalInvoices'], 1);
      expect(kpis['activeCount'], 0);
      expect(kpis['totalRevenue'], 0.0);
      expect(kpis['totalPaid'], 0.0);
      expect(kpis['totalDebt'], 0.0);
    });

    test('5. Complex filter: status=completed + paymentMethod=transfer + debtStatus=debt', () {
      final filtered = applyFiltersAdversarial(
        testOrders,
        status: 'completed',
        paymentMethod: 'transfer',
        debtStatus: 'debt',
      );

      expect(filtered.length, 2);
      expect(filtered.map((o) => o.id), containsAll(['HD_002', 'HD_003']));

      final kpis = computeReactiveKPIs(filtered);
      expect(kpis['totalInvoices'], 2);
      expect(kpis['activeCount'], 2);
      expect(kpis['totalRevenue'], 39000000.0); // 28M + 11M
      expect(kpis['totalPaid'], 15000000.0); // 10M + 5M
      expect(kpis['totalDebt'], 24000000.0); // 18M + 6M
    });

    test('6. Multi-criteria search query & staff filtering permutation matrix', () {
      // Search by partial product name in Vietnamese
      final filteredByProduct = applyFiltersAdversarial(testOrders, searchQuery: 'Titan Tự Nhiên');
      expect(filteredByProduct.length, 1);
      expect(filteredByProduct.first.id, 'HD_001');

      // Search by customer name with Vietnamese diacritics
      final filteredByName = applyFiltersAdversarial(testOrders, searchQuery: 'Bích Ngọc');
      expect(filteredByName.length, 2); // HD_002, HD_004
      expect(filteredByName.map((o) => o.id), containsAll(['HD_002', 'HD_004']));

      // Search by phone number
      final filteredByPhone = applyFiltersAdversarial(testOrders, searchQuery: '0909112233');
      expect(filteredByPhone.length, 1);
      expect(filteredByPhone.first.id, 'HD_003');

      // Filter by staff displayName
      final filteredByStaff = applyFiltersAdversarial(testOrders, staff: 'Phạm Minh Tuấn');
      expect(filteredByStaff.length, 2); // HD_003, HD_004

      // Filter by staff username
      final filteredByStaffId = applyFiltersAdversarial(testOrders, staff: 'staff_1');
      expect(filteredByStaffId.length, 2); // HD_001, HD_002

      // Combined Staff + Date Range
      final filteredStaffDate = applyFiltersAdversarial(
        testOrders,
        staff: 'staff_1',
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 3),
      );
      expect(filteredStaffDate.length, 1);
      expect(filteredStaffDate.first.id, 'HD_001');
    });

    test('7. Entity level InvoiceFilter.matches comprehensive unit assertion', () {
      const filter1 = InvoiceFilter(
        status: 'completed',
        paymentMethod: 'cash',
        debtStatus: 'paid',
        staffId: 'staff_1',
      );

      expect(filter1.matches(testOrders[0]), isTrue);
      expect(filter1.matches(testOrders[1]), isFalse);
      expect(filter1.matches(testOrders[2]), isFalse);
      expect(filter1.matches(testOrders[3]), isFalse);
      expect(filter1.matches(testOrders[4]), isFalse);

      // Status 'has_debt' and 'paid' special keyword checks in InvoiceFilter
      const filterHasDebt = InvoiceFilter(status: 'has_debt');
      expect(filterHasDebt.matches(testOrders[0]), isFalse); // paid
      expect(filterHasDebt.matches(testOrders[1]), isTrue); // has 18M debt
      expect(filterHasDebt.matches(testOrders[2]), isTrue); // has 6M debt

      const filterPaidStatus = InvoiceFilter(status: 'paid');
      expect(filterPaidStatus.matches(testOrders[0]), isTrue);
      expect(filterPaidStatus.matches(testOrders[1]), isFalse);

      // DebtStatus 'has_debt'
      const filterDebtStatus = InvoiceFilter(debtStatus: 'has_debt');
      expect(filterDebtStatus.matches(testOrders[0]), isFalse);
      expect(filterDebtStatus.matches(testOrders[1]), isTrue);
    });

    test('8. Edge case: Zero matching results produce zeroed reactive KPI metrics', () {
      final noMatches = applyFiltersAdversarial(
        testOrders,
        status: 'cancelled',
        paymentMethod: 'cash',
        debtStatus: 'paid',
        searchQuery: 'Non-existent item 12345',
      );

      expect(noMatches, isEmpty);

      final kpis = computeReactiveKPIs(noMatches);
      expect(kpis['totalInvoices'], 0);
      expect(kpis['activeCount'], 0);
      expect(kpis['totalRevenue'], 0.0);
      expect(kpis['totalPaid'], 0.0);
      expect(kpis['totalDebt'], 0.0);
    });
  });
}
