import 'package:flutter/material.dart';
import 'package:stores/presentation/reports/pages/overview_page.dart';
import 'package:stores/presentation/reports/pages/revenue_statistics_page.dart';
import 'package:stores/presentation/settings/pages/account_management_page.dart';
import 'package:stores/presentation/settings/pages/more_page.dart';
import 'package:stores/presentation/settings/pages/store_payment_settings_page.dart';

import '../ui_matrix_other/reports_matrix_test.dart' as rp;
import '../ui_matrix_other/settings_attendance_auth_shell_matrix_test.dart'
    as sa;
import 'monkey_kit.dart';

void main() {
  monkeyTest('OverviewPage(365d)', () => const OverviewPage(), (u) => rp.ov(u));
  monkeyTest('OverviewPage(nan)', () => const OverviewPage(),
      (u) => rp.ov(u, mode: 'nan'),
      salt: 1);
  monkeyTest('OverviewPage(outlier)', () => const OverviewPage(),
      (u) => rp.ov(u, mode: 'outlier'),
      salt: 2);
  monkeyTest('RevenueStatisticsPage', () => const RevenueStatisticsPage(),
      (u) => rp.ov(u));
  monkeyTest('RevenueStatisticsPage(zeros)',
      () => const RevenueStatisticsPage(), (u) => rp.ov(u, mode: 'zeros'),
      salt: 3);

  monkeyTest('MorePage', () => const MorePage(), (u) => sa.ov(u));
  monkeyTest('AccountManagementPage(2000)', () => const AccountManagementPage(),
      (u) => sa.ov(u));
  monkeyTest('StorePaymentSettingsPage', () => const StorePaymentSettingsPage(),
      (u) => sa.ov(u));
}
