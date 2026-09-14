import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/monthly_timesheet_notifier.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'fake_attendance_repository.dart';

void main() {
  group('MonthlyTimesheetNotifier Tests', () {
    late FakeAttendanceRepository fakeRepo;

    const staff1 = UserAccount(
      username: 'staff_1',
      displayName: 'Nguyễn Văn A',
      role: 'nhanvien',
      storeId: 'store_001',
    );

    setUp(() {
      fakeRepo = FakeAttendanceRepository();

      // Add 2 records in September 2026 for staff_1
      fakeRepo.attendances.add(
        AttendanceRecord(
          id: 'att_01',
          userId: 'staff_1',
          userName: 'Nguyễn Văn A',
          storeId: 'store_001',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: DateTime(2026, 9, 1),
          checkInTime: DateTime(2026, 9, 1, 8, 0),
          checkOutTime: DateTime(2026, 9, 1, 12, 0),
          checkInGpsLat: 10.035,
          checkInGpsLng: 105.788,
          isGpsValid: true,
          status: AttendanceStatus.onTime,
          totalWorkHours: 4.0,
        ),
      );

      fakeRepo.attendances.add(
        AttendanceRecord(
          id: 'att_02',
          userId: 'staff_1',
          userName: 'Nguyễn Văn A',
          storeId: 'store_001',
          shiftId: 'shift_afternoon',
          shiftName: 'Ca Chiều',
          date: DateTime(2026, 9, 2),
          checkInTime: DateTime(2026, 9, 2, 13, 20),
          checkOutTime: DateTime(2026, 9, 2, 17, 30),
          checkInGpsLat: 10.035,
          checkInGpsLng: 105.788,
          isGpsValid: true,
          status: AttendanceStatus.late,
          lateMinutes: 20,
          totalWorkHours: 4.17,
        ),
      );

      // Add 1 record for staff_2
      fakeRepo.attendances.add(
        AttendanceRecord(
          id: 'att_03',
          userId: 'staff_2',
          userName: 'Trần Thị B',
          storeId: 'store_001',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: DateTime(2026, 9, 3),
          checkInTime: DateTime(2026, 9, 3, 8, 0),
          checkOutTime: DateTime(2026, 9, 3, 11, 40),
          checkInGpsLat: 10.035,
          checkInGpsLng: 105.788,
          isGpsValid: true,
          status: AttendanceStatus.earlyLeave,
          earlyLeaveMinutes: 20,
          totalWorkHours: 3.67,
        ),
      );
    });

    test('Aggregates staff monthly timesheets and KPI statistics', () async {
      final notifier = MonthlyTimesheetNotifier(
        fakeRepo,
        staff1,
        initialStoreId: 'store_001',
        initialYear: 2026,
        initialMonth: 9,
      );

      await notifier.loadTimesheet();

      final state = notifier.state;
      expect(state.records.length, 3);
      expect(state.staffSummaries.length, 2);

      final summaryStaff1 = state.staffSummaries.firstWhere((s) => s.userId == 'staff_1');
      expect(summaryStaff1.shiftsCompleted, 2);
      expect(summaryStaff1.lateCount, 1);
      expect(summaryStaff1.totalHoursWorked, 8.17);

      final summaryStaff2 = state.staffSummaries.firstWhere((s) => s.userId == 'staff_2');
      expect(summaryStaff2.shiftsCompleted, 1);
      expect(summaryStaff2.earlyLeaveCount, 1);
      expect(summaryStaff2.totalHoursWorked, 3.67);

      // Personal summary for staff1
      expect(state.personalSummary, isNotNull);
      expect(state.personalSummary!.userId, 'staff_1');
      expect(state.personalSummary!.shiftsCompleted, 2);
    });
  });
}
