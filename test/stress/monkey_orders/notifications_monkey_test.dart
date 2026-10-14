import 'package:stores/presentation/notifications/pages/notifications_page.dart';

import '../support/monkey.dart';
import '../support/orders_support.dart';

void main() {
  final data = StressData.generate(envInt('STRESS_SEED', 20261014),
      nOrders: 10, nProducts: 50, nCustomers: 10, nNotifications: 500);

  monkeyTest(
    'Notifications (open / mark read / filter)',
    data: () => data,
    home: (d) => const NotificationsPage(),
    overrides: (u, d) => notificationOverrides(u, d),
    keywords: const ['Đánh dấu', 'Tất cả', 'Chưa đọc', 'Chuyển hàng', 'Xóa'],
  );

  monkeyTest(
    'Notifications (staff, narrow web)',
    data: () => data,
    home: (d) => const NotificationsPage(),
    overrides: (u, d) => notificationOverrides(u, d),
    user: staffUser,
    device: const Device('browser-narrow 480x800', 480, 800, web: true),
    seedOffset: 4,
  );
}
