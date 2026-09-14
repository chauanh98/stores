import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/excel_helper.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';

void main() {
  group('ExcelHelper Invoice Export Tests', () {
    final testDate = DateTime(2026, 8, 17, 15, 30);

    const customer1 = Customer(
      id: '433',
      name: 'A Tâm ( Nhựt xd)',
      phone: '0906636382',
      email: '',
      address: 'Cần Thơ',
      purchases: [],
    );


    final orders = [
      Order(
        id: 'HD000001',
        customerId: '433',
        createdAt: DateTime(2026, 8, 3, 23, 7),
        items: [
          OrderItem(
            productId: 'GCG10',
            productName: 'Ghế bậc thang cao cấp',
            quantity: 1,
            price: 3150000,
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 8, 3),
          ),
        ],
        total: 3150000,
        amountPaid: 3150000,
        debtAmount: 0,
        paymentMethod: 'cash',
        createdBy: 'admin1',
        createdByName: 'Khanh Dang',
        storeId: 'store_001',
      ),
      Order(
        id: 'HD000002',
        customerId: '433',
        createdAt: DateTime(2026, 8, 3, 23, 9),
        items: [
          OrderItem(
            productId: 'GCG10',
            productName: 'Ghế bậc thang cao cấp',
            quantity: 1,
            price: 3150000,
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 8, 3),
          ),
        ],
        total: 3000000, // 150k discount
        amountPaid: 150000,
        debtAmount: 2850000,
        paymentMethod: 'transfer',
        createdBy: 'admin1',
        createdByName: 'Khanh Dang',
        storeId: 'store_001',
      ),
      Order(
        id: 'HD000003',
        customerId: 'khach_le',
        createdAt: DateTime(2026, 8, 4, 10, 0),
        items: [
          OrderItem(
            productId: 'P_MOUSE',
            productName: 'Chuột không dây',
            quantity: 2,
            price: 500000,
            warrantyMonths: 6,
            purchaseDate: DateTime(2026, 8, 4),
          ),
        ],
        total: 1000000,
        amountPaid: 1000000,
        debtAmount: 0,
        paymentMethod: 'cash',
        status: 'cancelled',
        cancelReason: 'Khách đổi ý',
        storeId: 'store_002',
      ),
    ];

    test('exportInvoices creates valid Excel bytes with correct sheet and rows', () async {
      final bytes = await ExcelHelper.exportInvoices(
        orders,
        storeName: 'Chi nhánh Đông Thắng',
        filterDescription: 'Tháng 8/2026 | Tất cả trạng thái',
        exportDate: testDate,
        customerMap: {'433': customer1},
        storeNames: {
          'store_001': 'Chi nhánh Đông Thắng',
          'store_002': 'Chi nhánh Thới Bình',
        },
        exportedBy: 'Khanh Dang (admin)',
      );

      expect(bytes, isNotEmpty);

      // Decode and verify structure using package:excel
      final excel = Excel.decodeBytes(bytes);
      expect(excel.tables.containsKey('Danh sách hóa đơn'), true);

      final sheet = excel.tables['Danh sách hóa đơn']!;
      expect(sheet.maxRows, greaterThanOrEqualTo(8)); // Title, metadata, headers, 3 rows, summary

      // Check title
      final titleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
      expect(titleCell.value.toString(), contains('BÁO CÁO DANH SÁCH HÓA ĐƠN'));

      // Check headers row (Row 4)
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

      // Find header row index
      int headerRowIndex = -1;
      for (int r = 0; r < sheet.maxRows; r++) {
        final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value.toString();
        if (val == 'STT') {
          headerRowIndex = r;
          break;
        }
      }
      expect(headerRowIndex, greaterThan(0));

      for (int c = 0; c < expectedHeaders.length; c++) {
        final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: headerRowIndex)).value.toString();
        expect(val, expectedHeaders[c]);
      }

      // Check Data Row 1 (HD000001)
      final row1Index = headerRowIndex + 1;
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row1Index)).value.toString(), 'HD000001');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row1Index)).value.toString(), 'A Tâm ( Nhựt xd)');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row1Index)).value.toString(), '0906636382');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: row1Index)).value.toString(), 'Tiền mặt');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: row1Index)).value.toString(), 'Đã thanh toán');

      // Check Cancelled Order Row (HD000003)
      final row3Index = headerRowIndex + 3;
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row3Index)).value.toString(), 'HD000003');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row3Index)).value.toString(), 'Khách lẻ');
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: row3Index)).value.toString(), 'Đã hủy');

      // Check Grand Total row
      final totalRowIndex = headerRowIndex + 4;
      expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRowIndex)).value.toString(), 'TỔNG CỘNG');
    });
  });
}
