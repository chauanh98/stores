import 'package:stores/presentation/orders/pages/create_order_page.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';

import '../support/monkey.dart';
import '../support/orders_screens.dart';
import '../support/orders_support.dart';

void main() {
  final data = StressData.generate(envInt('STRESS_SEED', 20261014),
      nOrders: 400, nProducts: 800, nCustomers: 200);

  // POS flow: search/add to cart, qty, discount, checkout, split payment, finish.
  monkeyTest(
    'POS flow (cart -> checkout -> payment)',
    data: () => data,
    home: (d) => const POSPage(),
    overrides: (u, d) => ordersOverrides(u, d),
    setup: (c, d) => fillCart(c, d, 3),
    keywords: const [
      'Thêm',
      'Tiếp tục',
      'Thanh toán',
      'Hoàn tất',
      'Xác nhận',
      'Giảm giá',
      'Kết hợp',
      'Chuyển',
      'Lưu tạm',
      'Khách hàng',
    ],
  );

  monkeyTest(
    'POS flow (staff, small phone)',
    data: () => data,
    home: (d) => const POSPage(),
    overrides: (u, d) => ordersOverrides(u, d),
    setup: (c, d) => fillCart(c, d, 6),
    user: staffUser,
    device: const Device('small 320x568', 320, 568),
    seedOffset: 11,
    keywords: const ['Thanh toán', 'Hoàn tất', 'Tiếp tục', 'Thêm'],
  );

  // Invoices: filter, open, return, cancel, collect debt.
  monkeyTest(
    'Invoices (filter/open/return/cancel)',
    data: () => data,
    home: (d) => const InvoicesPage(),
    overrides: (u, d) => ordersOverrides(u, d),
    keywords: const [
      'Đã hoàn thành',
      'Đơn trả hàng',
      'Đã hủy',
      'Lưu tạm',
      'Xem món',
      'Trả hàng',
      'Hủy hóa đơn',
      'Hủy',
      'Thu nợ',
      'Xem chi tiết',
      'Xác nhận',
    ],
  );

  monkeyTest(
    'Invoices (tablet landscape)',
    data: () => data,
    home: (d) => const InvoicesPage(),
    overrides: (u, d) => ordersOverrides(u, d),
    device: const Device('tablet-l 1024x768', 1024, 768),
    seedOffset: 5,
    keywords: const ['Trả hàng', 'Hủy', 'Thu nợ', 'Xác nhận', 'Xem'],
  );

  monkeyTest(
    'CreateOrderPage',
    data: () => data,
    home: (d) => const CreateOrderPage(selectedCustomerId: 'c1'),
    overrides: (u, d) => ordersOverrides(u, d),
    seedOffset: 3,
    keywords: const ['Thêm', 'Lưu', 'Tạo'],
  );
}
