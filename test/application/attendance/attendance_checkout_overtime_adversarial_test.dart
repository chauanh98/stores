import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_notifier.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'fake_attendance_repository.dart';

void main() {
  group('Adversarial Check-Out Flow & Overtime State Transition Tests (M1/R1)',
      () {
    late FakeAttendanceRepository fakeRepo;
    late FakeLocationService fakeLocation;
    late ProviderContainer container;

    const testStaff = UserAccount(
      username: 'staff_adv_01',
      displayName: 'Empirical Tester',
      role: 'nhanvien',
      storeId: 'store_001',
    );

    final morningShift =
        Shift.defaultShifts().first; // 08:00 - 12:00, 4.0h, grace 15min
    final flexibleShift =
        Shift.defaultShifts().firstWhere((s) => s.type == 'flexible'); // 8.0h

    setUp(() {
      fakeRepo = FakeAttendanceRepository();
      fakeLocation = FakeLocationService();
      container = ProviderContainer(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(fakeRepo),
          locationServiceProvider.overrideWithValue(fakeLocation),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    // =========================================================================
    // VERIFICATION AREA 1: AttendanceStatus transitions when overtimeMinutes > 0
    // =========================================================================
    group('1. AttendanceStatus transition to overtime', () {
      test(
          'On-time check-in (08:00) + check-out past shift end (12:45) -> status becomes overtime',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: morningShift,
        );

        // Check in on time
        final checkInTime = DateTime(2026, 9, 15, 8, 0);
        final inOk = await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: checkInTime,
        );
        expect(inOk, isTrue);
        expect(
            container.read(attendanceNotifierProvider).todayAttendance!.status,
            AttendanceStatus.onTime);

        // Check out at 12:45 (45 min past scheduled 12:00 end, worked 4h45)
        final checkOutTime = DateTime(2026, 9, 15, 12, 45);
        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: checkOutTime,
        );
        expect(outOk, isTrue);

        final state = container.read(attendanceNotifierProvider);
        final record = state.todayAttendance!;
        expect(record.overtimeMinutes, 45);
        expect(record.earlyLeaveMinutes, 0);
        expect(record.status, AttendanceStatus.overtime,
            reason:
                'Status must transition to AttendanceStatus.overtime when overtimeMinutes > 0');
        expect(record.totalWorkHours, 4.75);
      });

      test(
          'Late check-in (09:00) + work past shift end with net excess (13:30) -> status becomes overtime',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: morningShift,
        );

        // Check in late: 09:00 (60 min late)
        final checkInTime = DateTime(2026, 9, 15, 9, 0);
        await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: checkInTime,
        );
        expect(
            container.read(attendanceNotifierProvider).todayAttendance!.status,
            AttendanceStatus.late);
        expect(
            container
                .read(attendanceNotifierProvider)
                .todayAttendance!
                .lateMinutes,
            60);

        // Check out at 13:30 (worked 4h30m = 270m, standard = 240m, excess = 30m, past end = 90m -> OT = 30m)
        final checkOutTime = DateTime(2026, 9, 15, 13, 30);
        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: checkOutTime,
        );
        expect(outOk, isTrue);

        final state = container.read(attendanceNotifierProvider);
        final record = state.todayAttendance!;
        expect(record.overtimeMinutes, 30);
        expect(record.status, AttendanceStatus.overtime,
            reason:
                'Late check-in that earns net overtime must transition to AttendanceStatus.overtime');
        expect(record.totalWorkHours, 4.5);
      });

      test(
          'Flexible shift: check-in 08:00, check-out 18:00 (10h worked, 8h std) -> status becomes overtime',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: flexibleShift,
        );

        final checkInTime = DateTime(2026, 9, 15, 8, 0);
        await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: checkInTime,
        );

        final checkOutTime = DateTime(2026, 9, 15, 18, 0);
        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: checkOutTime,
        );
        expect(outOk, isTrue);

        final state = container.read(attendanceNotifierProvider);
        final record = state.todayAttendance!;
        expect(record.overtimeMinutes, 120);
        expect(record.status, AttendanceStatus.overtime);
        expect(record.totalWorkHours, 10.0);
      });

      test(
          'Boundary: minimal overtime (1 minute past scheduled end, 12:01) -> status becomes overtime',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: morningShift,
        );

        await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: DateTime(2026, 9, 15, 8, 0),
        );

        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: DateTime(2026, 9, 15, 12, 1),
        );
        expect(outOk, isTrue);

        final record =
            container.read(attendanceNotifierProvider).todayAttendance!;
        expect(record.overtimeMinutes, 1);
        expect(record.status, AttendanceStatus.overtime);
      });

      test(
          'Late check-in (09:00) + check-out (13:00) compensating late arrival: overtime == 0 -> status remains late',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: morningShift,
        );

        await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: DateTime(2026, 9, 15, 9, 0),
        );

        // Worked exactly 4h (13:00 - 09:00). Compensated 1h late deficit, net overtime is 0.
        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: DateTime(2026, 9, 15, 13, 0),
        );
        expect(outOk, isTrue);

        final record =
            container.read(attendanceNotifierProvider).todayAttendance!;
        expect(record.overtimeMinutes, 0);
        expect(record.status, AttendanceStatus.late,
            reason:
                'When overtimeMinutes is 0, status must NOT become overtime; it remains late');
      });

      test(
          'Worked 2h defect scenario (in: 12:00, out: 14:00): overtime == 0 -> status remains late',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: morningShift,
        );

        await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: DateTime(2026, 9, 15, 12, 0),
        );

        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: DateTime(2026, 9, 15, 14, 0),
        );
        expect(outOk, isTrue);

        final record =
            container.read(attendanceNotifierProvider).todayAttendance!;
        expect(record.overtimeMinutes, 0);
        expect(record.status, AttendanceStatus.late);
      });

      test(
          'Exact shift end checkout (08:00 to 12:00): overtime == 0 -> status remains onTime',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: morningShift,
        );

        await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: DateTime(2026, 9, 15, 8, 0),
        );

        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: DateTime(2026, 9, 15, 12, 0),
        );
        expect(outOk, isTrue);

        final record =
            container.read(attendanceNotifierProvider).todayAttendance!;
        expect(record.overtimeMinutes, 0);
        expect(record.earlyLeaveMinutes, 0);
        expect(record.status, AttendanceStatus.onTime);
        expect(record.totalWorkHours, 4.0);
      });
    });

    // =========================================================================
    // VERIFICATION AREA 2: earlyLeaveMinutes > 0 takes precedence over overtime
    // =========================================================================
    group('2. Early leave precedence over overtime', () {
      test(
          'On-time check-in (08:00) + early check-out (11:30) -> status becomes earlyLeave',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: morningShift,
        );

        await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: DateTime(2026, 9, 15, 8, 0),
        );

        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: DateTime(2026, 9, 15, 11, 30),
        );
        expect(outOk, isTrue);

        final record =
            container.read(attendanceNotifierProvider).todayAttendance!;
        expect(record.earlyLeaveMinutes, 30);
        expect(record.overtimeMinutes, 0);
        expect(record.status, AttendanceStatus.earlyLeave);
        expect(record.totalWorkHours, 3.5);
      });

      test(
          'Late check-in (08:35) + early check-out (11:30) -> status becomes earlyLeave',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: morningShift,
        );

        // Arrive late: status is late at check-in
        await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: DateTime(2026, 9, 15, 8, 35),
        );
        expect(
            container.read(attendanceNotifierProvider).todayAttendance!.status,
            AttendanceStatus.late);

        // Leave early at 11:30 (30 min before 12:00)
        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: DateTime(2026, 9, 15, 11, 30),
        );
        expect(outOk, isTrue);

        final record =
            container.read(attendanceNotifierProvider).todayAttendance!;
        expect(record.earlyLeaveMinutes, 30);
        expect(record.overtimeMinutes, 0);
        expect(record.status, AttendanceStatus.earlyLeave,
            reason:
                'earlyLeaveMinutes > 0 takes precedence and updates status to earlyLeave');
      });

      test(
          'Boundary: 1 minute early leave (11:59:00) -> earlyLeaveMinutes == 1, status is earlyLeave',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: morningShift,
        );

        await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: DateTime(2026, 9, 15, 8, 0),
        );

        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: DateTime(2026, 9, 15, 11, 59),
        );
        expect(outOk, isTrue);

        final record =
            container.read(attendanceNotifierProvider).todayAttendance!;
        expect(record.earlyLeaveMinutes, 1);
        expect(record.overtimeMinutes, 0);
        expect(record.status, AttendanceStatus.earlyLeave);
      });

      test(
          'Extreme early arrival (05:00) + early leave (11:30): worked 6.5h (> 4h std) but left before 12:00 -> earlyLeave takes precedence',
          () async {
        const earlyShift = Shift(
          id: 'shift_early',
          name: 'Ca Sớm',
          startTime: '05:00',
          endTime: '12:00',
          gracePeriodMinutes: 15,
          type: 'morning',
          standardWorkHours: 4.0,
        );

        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: earlyShift,
        );

        // Arrive at 05:00 (valid check-in for early shift starting at 05:00)
        await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: DateTime(2026, 9, 15, 5, 0),
        );
        expect(
            container.read(attendanceNotifierProvider).todayAttendance!.status,
            AttendanceStatus.onTime);

        // Leave early at 11:30 (worked 6.5 hours, but before 12:00 scheduledEnd)
        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: DateTime(2026, 9, 15, 11, 30),
        );
        expect(outOk, isTrue);

        final record =
            container.read(attendanceNotifierProvider).todayAttendance!;
        expect(record.earlyLeaveMinutes, 30);
        expect(record.overtimeMinutes, 0,
            reason:
                'No overtime on fixed shift when leaving before scheduledEnd');
        expect(record.status, AttendanceStatus.earlyLeave,
            reason:
                'Leaving before scheduled end must yield earlyLeave status');
        expect(record.totalWorkHours, 6.5);
      });
    });

    // =========================================================================
    // VERIFICATION AREA 3: Check-out timestamp recording in AttendanceRecord
    // =========================================================================
    group('3. Check-out timestamp recording & persistence', () {
      test(
          'Exact checkOutTimestamp is recorded in AttendanceRecord and repository',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: morningShift,
        );

        final checkInTime = DateTime(2026, 9, 15, 8, 0);
        await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: checkInTime,
        );

        final checkOutTime = DateTime(2026, 9, 15, 12, 45, 30);
        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: checkOutTime,
        );
        expect(outOk, isTrue);

        // Verify in-memory state
        final stateRecord =
            container.read(attendanceNotifierProvider).todayAttendance!;
        expect(stateRecord.checkOutTime, equals(checkOutTime));
        expect(stateRecord.updatedAt, equals(checkOutTime));
        expect(stateRecord.isWorking, isFalse);
        expect(stateRecord.checkInTime, equals(checkInTime));

        // Verify repository persistence
        final repoRecord =
            fakeRepo.attendances.firstWhere((r) => r.id == stateRecord.id);
        expect(repoRecord.checkOutTime, equals(checkOutTime));
        expect(repoRecord.updatedAt, equals(checkOutTime));
        expect(repoRecord.isWorking, isFalse);
      });

      test('Default timestamp (null checkOutTimestamp) uses current DateTime',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: morningShift,
        );

        await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: DateTime(2026, 9, 15, 8, 0),
        );

        final beforeCheckout =
            DateTime.now().subtract(const Duration(seconds: 1));
        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          // checkOutTimestamp omitted -> defaults to DateTime.now()
        );
        final afterCheckout = DateTime.now().add(const Duration(seconds: 1));

        expect(outOk, isTrue);
        final record =
            container.read(attendanceNotifierProvider).todayAttendance!;
        expect(record.checkOutTime, isNotNull);
        expect(record.checkOutTime!.isAfter(beforeCheckout), isTrue);
        expect(record.checkOutTime!.isBefore(afterCheckout), isTrue);
      });

      test(
          'Duplicate check-out attempt is blocked and timestamp remains unmodified',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: morningShift,
        );

        await notifier.checkIn(
          user: testStaff,
          storeId: 'store_001',
          checkInTimestamp: DateTime(2026, 9, 15, 8, 0),
        );

        final firstCheckOut = DateTime(2026, 9, 15, 12, 30);
        final firstOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: firstCheckOut,
        );
        expect(firstOk, isTrue);

        // Attempt second check-out
        final secondCheckOut = DateTime(2026, 9, 15, 13, 0);
        final secondOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: secondCheckOut,
        );

        expect(secondOk, isFalse);
        final state = container.read(attendanceNotifierProvider);
        expect(state.errorMessage,
            contains('Bạn đã hoàn tất chấm công ra ca này rồi.'));
        expect(state.todayAttendance!.checkOutTime, equals(firstCheckOut),
            reason:
                'Check-out timestamp must NOT be overwritten by a subsequent checkOut call');
      });

      test('Check-out without prior check-in fails gracefully', () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testStaff.username,
          initialShift: morningShift,
        );

        final outOk = await notifier.checkOut(
          user: testStaff,
          storeId: 'store_001',
          checkOutTimestamp: DateTime(2026, 9, 15, 12, 0),
        );

        expect(outOk, isFalse);
        final state = container.read(attendanceNotifierProvider);
        expect(state.errorMessage,
            contains('Không tìm thấy bản ghi vào ca để chấm công ra.'));
        expect(state.todayAttendance, isNull);
      });

      test('Admin/Supervisor roles are strictly blocked from check-out',
          () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: 'admin_test',
          initialShift: morningShift,
        );

        const admin =
            UserAccount(username: 'admin', role: 'admin', storeId: 'store_001');
        const supervisor = UserAccount(
            username: 'sup', role: 'supervisor', storeId: 'store_001');

        final adminResult =
            await notifier.checkOut(user: admin, storeId: 'store_001');
        expect(adminResult, isFalse);
        expect(container.read(attendanceNotifierProvider).errorMessage,
            contains('Tài khoản quản lý không thuộc đối tượng'));

        final supResult =
            await notifier.checkOut(user: supervisor, storeId: 'store_001');
        expect(supResult, isFalse);
        expect(container.read(attendanceNotifierProvider).errorMessage,
            contains('Tài khoản quản lý không thuộc đối tượng'));
      });
    });
  });
}
