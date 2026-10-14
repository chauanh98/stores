import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/pages/stock_in_receipts_page.dart';
import 'package:stores/presentation/inventories/pages/stock_transfer_create_page.dart';
import 'package:stores/presentation/inventories/pages/stock_transfers_page.dart';
import 'package:stores/presentation/inventories/pages/imports_page.dart';
import 'package:stores/presentation/inventories/pages/inter_store_transfer_page.dart';

import '../support/monkey.dart';
import '../support/orders_support.dart';

void main() {
  final data = StressData.generate(envInt('STRESS_SEED', 20261014),
      nOrders: 50, nProducts: 800, nCustomers: 50, nReceipts: 200);

  // Stock-in wizard: add lines, edit sheet, step 2 (payment), save/complete.
  monkeyTest(
    'Stock-in wizard (2 steps)',
    data: () => data,
    home: (d) => const ImportInventoryPage(),
    overrides: (u, d) => inventoryOverrides(u, d),
    keywords: const [
      'Tiếp tục',
      'Hoàn thành',
      'Lưu tạm',
      'Trả đủ',
      'Ghi nợ',
      'Nhà cung cấp',
      'Xong',
      'Xác nhận',
    ],
  );

  monkeyTest(
    'Stock-in wizard (resumed 40-line draft, tiny)',
    data: () => data,
    home: (d) => ImportInventoryPage(
        initialReceipt: d.g.receipt(31, lines: 40, status: 'draft')),
    overrides: (u, d) => inventoryOverrides(u, d),
    device: const Device('tiny 240x320', 240, 320),
    seedOffset: 7,
    keywords: const ['Tiếp tục', 'Hoàn thành', 'Lưu tạm', 'Xác nhận'],
  );

  monkeyTest(
    'Stock-in receipts list/detail/cancel',
    data: () => data,
    home: (d) => const StockInReceiptsPage(),
    overrides: (u, d) => inventoryOverrides(u, d),
    keywords: const ['PN_', 'Hủy phiếu', 'Xác nhận', 'Xóa', 'Đóng'],
  );

  monkeyTest(
    'Stock transfers (list -> create -> detail -> receive)',
    data: () => data,
    home: (d) => const StockTransfersPage(),
    overrides: (u, d) => inventoryOverrides(u, d),
    keywords: const [
      'TRF',
      'Tạo phiếu',
      'Nhận hàng',
      'Nhận tất cả',
      'Hoàn thành',
      'Hủy phiếu',
      'Xác nhận',
      'Thêm hàng',
    ],
  );

  monkeyTest(
    'Stock transfer create',
    data: () => data,
    home: (d) => StockTransferCreatePage(product: d.products[3]),
    overrides: (u, d) => inventoryOverrides(u, d),
    seedOffset: 9,
    keywords: const ['Thêm hàng', 'Hoàn thành', 'Lưu tạm', 'Xác nhận'],
  );

  monkeyTest(
    'Inter-store transfer + imports pages',
    data: () => data,
    home: (d) => const InterStoreTransferPage(),
    overrides: (u, d) => inventoryOverrides(u, d),
    seedOffset: 13,
    keywords: const ['Chuyển', 'Xác nhận', 'Chọn'],
  );

  monkeyTest(
    'ImportsPage',
    data: () => data,
    home: (d) => const ImportsPage(),
    overrides: (u, d) => inventoryOverrides(u, d),
    seedOffset: 17,
  );
}
