import 'package:flutter/material.dart';
import 'package:stores/main.dart';
import 'package:stores/presentation/attendance/pages/attendance_check_in_page.dart';
import 'package:stores/presentation/attendance/pages/live_attendance_dashboard_page.dart';
import 'package:stores/presentation/attendance/pages/monthly_timesheet_page.dart';
import 'package:stores/presentation/attendance/pages/shift_config_page.dart';
import 'package:stores/presentation/auth/pages/login_page.dart';

import '../ui_matrix_other/settings_attendance_auth_shell_matrix_test.dart'
    as sa;
import 'monkey_kit.dart';

void main() {
  monkeyTest('AttendanceCheckInPage', () => const AttendanceCheckInPage(),
      (u) => sa.ov(u));
  monkeyTest('LiveAttendanceDashboardPage(3100)',
      () => const LiveAttendanceDashboardPage(), (u) => sa.ov(u));
  monkeyTest('MonthlyTimesheetPage(100x31)', () => const MonthlyTimesheetPage(),
      (u) => sa.ov(u));
  monkeyTest('MonthlyTimesheetPage(personal)',
      () => const MonthlyTimesheetPage(isPersonalOnly: true), (u) => sa.ov(u),
      salt: 1);
  monkeyTest('ShiftConfigPage', () => const ShiftConfigPage(), (u) => sa.ov(u));
  monkeyTest('LoginPage', () => const LoginPage(), (u) => [],
      allowLogout: true);
  monkeyTest('AdaptiveScaffold shell', () => const AdaptiveScaffold(),
      (u) => sa.ov(u));
}
