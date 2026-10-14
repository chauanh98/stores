import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/domain/attendance/attendance_adjustment.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/attendance/pages/attendance_check_in_page.dart';
import 'package:stores/presentation/attendance/pages/live_attendance_dashboard_page.dart';
import 'package:stores/presentation/attendance/pages/monthly_timesheet_page.dart';
import 'package:stores/presentation/attendance/pages/shift_config_page.dart';

import '../application/attendance/fake_attendance_repository.dart';
import 'sweep_harness.dart';

const _longName = 'Nguyễn Thị Thanh Thảo Hoàng Gia Bảo Châu Quận Bình Thạnh';

FakeAttendanceRepository _repo(int records) {
  final now = DateTime.now();
  final repo = FakeAttendanceRepository();
  repo.shifts = [
    ...Shift.defaultShifts(),
    const Shift(
      id: 'shift_long',
      name:
          'Ca làm việc có tên rất dài để kiểm tra tràn dòng trên màn hình nhỏ',
      startTime: '00:00',
      endTime: '23:59',
      type: 'flexible',
    ),
  ];
  for (var i = 0; i < records; i++) {
    final user = i == 0 ? 's' : 'staff_$i';
    repo.attendances.add(AttendanceRecord(
      id: 'att_$i',
      userId: user,
      userName: _longName,
      storeId: 'store_001',
      shiftId: i.isEven ? 'shift_morning' : 'shift_long',
      shiftName: 'Ca làm việc có tên rất dài để kiểm tra tràn dòng',
      date: now,
      checkInTime: DateTime(now.year, now.month, now.day, 8, i % 60),
      checkOutTime:
          i % 3 == 0 ? null : DateTime(now.year, now.month, now.day, 12),
      checkInGpsLat: 10.035,
      checkInGpsLng: 105.788,
      isGpsValid: i % 4 != 0,
      status: AttendanceStatus.values[i % AttendanceStatus.values.length],
      lateMinutes: 1234,
      totalWorkHours: 99.5,
      explanationReason: 'Lý do giải trình rất dài ' * 8,
    ));
  }
  repo.adjustments.add(AttendanceAdjustment(
    id: 'adj',
    attendanceId: 'att_0',
    userId: 's',
    userName: _longName,
    storeId: 'store_001',
    requestedCheckIn: DateTime(now.year, now.month, now.day, 8),
    requestedCheckOut: DateTime(now.year, now.month, now.day, 12, 30),
    reason: 'Bổ sung giờ bàn giao ca vì quên chấm công ' * 5,
    status: AdjustmentStatus.pending,
    submittedAt: now,
  ));
  return repo;
}

List<Override> _ov(UserAccount user, {int records = 30}) {
  final repo = _repo(records);
  return [
    authProvider.overrideWith((ref) => SweepAuth(user)),
    attendanceRepositoryProvider.overrideWithValue(repo),
    shiftRepositoryProvider.overrideWithValue(repo),
    locationServiceProvider.overrideWithValue(FakeLocationService()),
    currentStoreIdProvider.overrideWithValue('store_001'),
    currentStoreNameProvider.overrideWith((ref) async => sweepLongStore),
    availableStoresProvider.overrideWith((ref) async => {
          'store_001': sweepLongStore,
          'store_002': 'Chi nhánh Thới Bình',
        }),
  ];
}

void main() {
  final small = {'320x568': sweepScreens['320x568']!};
  sweepMatrix('AttendanceCheckInPage', () => const AttendanceCheckInPage(),
      (u) => _ov(u));
  sweepMatrix('LiveAttendanceDashboardPage(30)',
      () => const LiveAttendanceDashboardPage(), (u) => _ov(u));
  sweepMatrix('LiveAttendanceDashboardPage(empty)',
      () => const LiveAttendanceDashboardPage(), (u) => _ov(u, records: 0),
      screens: small);
  sweepMatrix('MonthlyTimesheetPage(personal)',
      () => const MonthlyTimesheetPage(isPersonalOnly: true), (u) => _ov(u));
  sweepMatrix('MonthlyTimesheetPage(all)', () => const MonthlyTimesheetPage(),
      (u) => _ov(u));
  sweepMatrix('MonthlyTimesheetPage(empty)', () => const MonthlyTimesheetPage(),
      (u) => _ov(u, records: 0),
      screens: small);
  sweepMatrix('ShiftConfigPage', () => const ShiftConfigPage(), (u) => _ov(u));

  testWidgets('LiveAttendanceDashboardPage with 400 records builds lazily',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(sweepHost(
        const LiveAttendanceDashboardPage(), _ov(sweepAdmin, records: 400)));
    await tester.pumpAndSettle();
    expectNoException(tester);
    expect(find.text(_longName).evaluate().length, lessThan(60));
  });
}
