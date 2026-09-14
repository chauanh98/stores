import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_adjustment_notifier.dart';
import 'package:stores/domain/attendance/attendance_adjustment.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'fake_attendance_repository.dart';

void main() {
  group('AttendanceAdjustmentNotifier Tests', () {
    late FakeAttendanceRepository fakeRepo;

    const supervisorUser = UserAccount(
      username: 'supervisor_1',
      displayName: 'Giám sát viên',
      role: 'supervisor',
      storeId: 'store_001',
    );

    setUp(() {
      fakeRepo = FakeAttendanceRepository();

      // Seed an attendance record that needs adjustment (e.g. missed check-out)
      fakeRepo.attendances.add(
        AttendanceRecord(
          id: 'att_target',
          userId: 'staff_1',
          userName: 'Nhân viên 1',
          storeId: 'store_001',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: DateTime(2026, 9, 10),
          checkInTime: DateTime(2026, 9, 10, 8, 0),
          checkOutTime: null, // Missed check-out
          checkInGpsLat: 10.035,
          checkInGpsLng: 105.788,
          isGpsValid: true,
          totalWorkHours: 0.0,
        ),
      );
    });

    test('Staff submits adjustment request, supervisor approves and updates record', () async {
      final notifier = AttendanceAdjustmentNotifier(fakeRepo, supervisorUser);

      final adjustment = AttendanceAdjustment(
        id: 'adj_01',
        attendanceId: 'att_target',
        userId: 'staff_1',
        userName: 'Nhân viên 1',
        storeId: 'store_001',
        requestedCheckIn: DateTime(2026, 9, 10, 8, 0),
        requestedCheckOut: DateTime(2026, 9, 10, 12, 0),
        reason: 'Quên bấm máy khi về ca sáng',
        submittedAt: DateTime(2026, 9, 10, 12, 30),
      );

      final submitted = await notifier.submitRequest(adjustment);
      expect(submitted, isTrue);

      final stateAfterSubmit = notifier.state;
      expect(stateAfterSubmit.adjustments.length, 1);
      expect(stateAfterSubmit.adjustments.first.status, AdjustmentStatus.pending);

      // Supervisor approves
      final approved = await notifier.approve(
        adjustmentId: 'adj_01',
        reviewedBy: 'supervisor_1',
        reviewNote: 'Đã xác nhận với trưởng ca',
      );
      expect(approved, isTrue);

      final stateAfterApproval = notifier.state;
      expect(stateAfterApproval.adjustments.first.status, AdjustmentStatus.approved);
      expect(stateAfterApproval.adjustments.first.reviewedBy, 'supervisor_1');

      // Check underlying attendance record was updated
      final updatedAttendance = fakeRepo.attendances.firstWhere((a) => a.id == 'att_target');
      expect(updatedAttendance.isAdjusted, isTrue);
      expect(updatedAttendance.checkOutTime, DateTime(2026, 9, 10, 12, 0));
      expect(updatedAttendance.totalWorkHours, 4.0);
    });

    test('Supervisor rejects adjustment request', () async {
      final notifier = AttendanceAdjustmentNotifier(fakeRepo, supervisorUser);

      final adjustment = AttendanceAdjustment(
        id: 'adj_02',
        attendanceId: 'att_target',
        userId: 'staff_1',
        userName: 'Nhân viên 1',
        storeId: 'store_001',
        requestedCheckIn: DateTime(2026, 9, 10, 8, 0),
        requestedCheckOut: DateTime(2026, 9, 10, 14, 0),
        reason: 'Yêu cầu tính thêm giờ',
        submittedAt: DateTime(2026, 9, 10, 15, 0),
      );

      await notifier.submitRequest(adjustment);

      final rejected = await notifier.reject(
        adjustmentId: 'adj_02',
        reviewedBy: 'supervisor_1',
        reviewNote: 'Không có bằng chứng làm thêm giờ',
      );
      expect(rejected, isTrue);

      final state = notifier.state;
      expect(state.adjustments.first.status, AdjustmentStatus.rejected);
      expect(state.adjustments.first.reviewedBy, 'supervisor_1');
      expect(state.adjustments.first.reviewNote, 'Không có bằng chứng làm thêm giờ');
    });
  });
}
