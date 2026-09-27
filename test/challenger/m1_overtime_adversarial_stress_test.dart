import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_notifier.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../application/attendance/fake_attendance_repository.dart';

void main() {
  const morningShift = Shift(
    id: 'shift_morning',
    name: 'Ca Sáng',
    startTime: '08:00',
    endTime: '12:00',
    gracePeriodMinutes: 15,
    type: 'morning',
    standardWorkHours: 4.0,
  );

  const afternoonShift = Shift(
    id: 'shift_afternoon',
    name: 'Ca Chiều',
    startTime: '13:00',
    endTime: '17:30',
    gracePeriodMinutes: 15,
    type: 'afternoon',
    standardWorkHours: 4.5,
  );

  const flexibleShift8h = Shift(
    id: 'shift_flexible',
    name: 'Ca Linh hoạt',
    startTime: '08:00',
    endTime: '22:00',
    gracePeriodMinutes: 60,
    type: 'flexible',
    standardWorkHours: 8.0,
  );

  final baseDate = DateTime(2026, 9, 13);

  group('Adversarial Challenge 1: Extreme Late Arrival Scenarios', () {
    test('Checked in 3 hours late (11:00), out at 13:00 (1h past shift end) -> 2h worked -> exactly 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 11, 0);
      final checkOut = DateTime(2026, 9, 13, 13, 0);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0, reason: 'Total worked is 2h which is <= standardWorkHours (4h), so OT must be 0');
    });

    test('Checked in 3.5 hours late (11:30), out at 14:00 (2h past shift end) -> 2.5h worked -> exactly 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 11, 30);
      final checkOut = DateTime(2026, 9, 13, 14, 0);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });

    test('Checked in 3h59m late (11:59), out at 12:01 (1m past shift end) -> 2 mins worked -> exactly 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 11, 59);
      final checkOut = DateTime(2026, 9, 13, 12, 1);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });

    test('Checked in at scheduled end (12:00, 4h late), out at 14:00 (2h past shift end) -> 2h worked -> exactly 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 12, 0);
      final checkOut = DateTime(2026, 9, 13, 14, 0);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });

    test('Checked in AFTER scheduled end (13:00), out at 15:00 -> 2h worked -> exactly 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 13, 0);
      final checkOut = DateTime(2026, 9, 13, 15, 0);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });

    test('Checked in 3 hours late (11:00), out at 16:00 (worked 5h total, 4h past shift end) -> exactly 60 mins OT', () {
      final checkIn = DateTime(2026, 9, 13, 11, 0);
      final checkOut = DateTime(2026, 9, 13, 16, 0);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      // Worked 300 min. Standard is 240 min. Excess worked is 60 min. Past end is 240 min. min(240, 60) = 60.
      expect(ot, 60);
    });
  });

  group('Adversarial Challenge 2: Exactly Meeting Standard Shift Duration with Late Checkout', () {
    test('Checked in at 09:00 (1h late), out at 13:00 (1h past end) -> worked exactly 4h00m -> exactly 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 9, 0);
      final checkOut = DateTime(2026, 9, 13, 13, 0);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0, reason: 'Late arrival is compensated first; exactly 4h worked equals standard 4h, so 0 OT');
    });

    test('Checked in at 10:00 (2h late), out at 14:00 (2h past end) -> worked exactly 4h00m -> exactly 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 10, 0);
      final checkOut = DateTime(2026, 9, 13, 14, 0);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });

    test('Checked in at 11:30 (3.5h late), out at 15:30 (3.5h past end) -> worked exactly 4h00m -> exactly 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 11, 30);
      final checkOut = DateTime(2026, 9, 13, 15, 30);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });

    test('Checked in at 11:59 (3h59m late), out at 15:59 (3h59m past end) -> worked exactly 4h00m -> exactly 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 11, 59);
      final checkOut = DateTime(2026, 9, 13, 15, 59);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });

    test('Checked in on time at 08:00, out exactly at 12:00 -> worked exactly 4h00m -> exactly 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 8, 0);
      final checkOut = DateTime(2026, 9, 13, 12, 0);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });

    test('Afternoon shift (4.5h standard = 270 min): in 14:00, out 18:30 -> worked exactly 4.5h -> exactly 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 14, 0);
      final checkOut = DateTime(2026, 9, 13, 18, 30);
      final ot = afternoonShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });
  });

  group('Adversarial Challenge 3: 1 Minute of Overtime Precision', () {
    test('On-time check-in (08:00), out at 12:01 -> exactly 1 min OT', () {
      final checkIn = DateTime(2026, 9, 13, 8, 0);
      final checkOut = DateTime(2026, 9, 13, 12, 1);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 1);
    });

    test('Checked in at 09:00 (1h late), out at 13:01 -> worked 4h01m (241 min), 61 min past end -> min(61, 1) = 1 min OT', () {
      final checkIn = DateTime(2026, 9, 13, 9, 0);
      final checkOut = DateTime(2026, 9, 13, 13, 1);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 1);
    });

    test('Checked in at 10:00 (2h late), out at 14:01 -> worked 4h01m (241 min), 121 min past end -> min(121, 1) = 1 min OT', () {
      final checkIn = DateTime(2026, 9, 13, 10, 0);
      final checkOut = DateTime(2026, 9, 13, 14, 1);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 1);
    });

    test('Checked in at 11:59 (3h59m late), out at 16:00 -> worked 4h01m (241 min), 240 min past end -> min(240, 1) = 1 min OT', () {
      final checkIn = DateTime(2026, 9, 13, 11, 59);
      final checkOut = DateTime(2026, 9, 13, 16, 0);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 1);
    });

    test('Afternoon shift (4.5h standard): in 14:00 (1h late), out at 18:31 -> worked 4h31m (271m) -> exactly 1 min OT', () {
      final checkIn = DateTime(2026, 9, 13, 14, 0);
      final checkOut = DateTime(2026, 9, 13, 18, 31);
      final ot = afternoonShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 1);
    });

    test('Flexible shift (8h standard): in 08:00, out at 16:01 -> worked 8h01m (481m) -> exactly 1 min OT', () {
      final checkIn = DateTime(2026, 9, 13, 8, 0);
      final checkOut = DateTime(2026, 9, 13, 16, 1);
      final ot = flexibleShift8h.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 1);
    });
  });

  group('Adversarial Challenge 4: Early Arrival Scenarios', () {
    test('Checked in at 07:00 (1h early), out at 12:00 (scheduled end) -> worked 5h -> exactly 0 OT (not past scheduledEnd)', () {
      final checkIn = DateTime(2026, 9, 13, 7, 0);
      final checkOut = DateTime(2026, 9, 13, 12, 0);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0, reason: 'Checkout must be strictly after scheduledEnd to qualify for overtime');
    });

    test('Checked in at 07:00 (1h early), out at 12:30 -> worked 5h30m -> exactly 30 mins OT, NOT 90 mins', () {
      final checkIn = DateTime(2026, 9, 13, 7, 0);
      final checkOut = DateTime(2026, 9, 13, 12, 30);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      // Past scheduled end = 30 min. Excess worked = 330 - 240 = 90 min. min(30, 90) = 30 min.
      expect(ot, 30, reason: 'Overtime is capped by post-scheduled-end duration (30m), not unapproved early arrival');
    });

    test('Checked in at 06:00 (2h early), out at 12:00 -> worked 6h -> exactly 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 6, 0);
      final checkOut = DateTime(2026, 9, 13, 12, 0);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });

    test('Checked in at 06:00 (2h early), out at 12:01 -> worked 6h01m -> exactly 1 min OT (capped by past scheduledEnd)', () {
      final checkIn = DateTime(2026, 9, 13, 6, 0);
      final checkOut = DateTime(2026, 9, 13, 12, 1);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 1);
    });

    test('Checked in at 07:45 (15m early), out at 11:45 -> worked 4h00m, but left before scheduledEnd -> exactly 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 7, 45);
      final checkOut = DateTime(2026, 9, 13, 11, 45);
      final ot = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });
  });

  group('Adversarial Challenge 5: Flexible Shift Edge Cases', () {
    test('worked 0h: in 08:00, out 08:00 -> 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 8, 0);
      final checkOut = DateTime(2026, 9, 13, 8, 0);
      final ot = flexibleShift8h.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });

    test('worked 7h59m: in 08:00, out 15:59 (479 min) -> 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 8, 0);
      final checkOut = DateTime(2026, 9, 13, 15, 59);
      final ot = flexibleShift8h.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });

    test('worked 8h00m: in 08:00, out 16:00 (480 min) -> 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 8, 0);
      final checkOut = DateTime(2026, 9, 13, 16, 0);
      final ot = flexibleShift8h.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });

    test('worked 8h01m: in 08:00, out 16:01 (481 min) -> exactly 1 min OT', () {
      final checkIn = DateTime(2026, 9, 13, 8, 0);
      final checkOut = DateTime(2026, 9, 13, 16, 1);
      final ot = flexibleShift8h.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 1);
    });

    test('worked 24h: in 2026-09-13 08:00, out 2026-09-14 08:00 (1440 min) -> 1440 - 480 = 960 min OT (16 hours)', () {
      final checkIn = DateTime(2026, 9, 13, 8, 0);
      final checkOut = DateTime(2026, 9, 14, 8, 0);
      final ot = flexibleShift8h.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 960);
    });

    test('Sub-minute precision: in 08:00:00, out 16:00:59 (480 min + 59 sec) -> 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 8, 0, 0);
      final checkOut = DateTime(2026, 9, 13, 16, 0, 59);
      final ot = flexibleShift8h.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(ot, 0);
    });

    test('Negative / Clock skew: out is before in (e.g. 09:00 in, 08:00 out) -> 0 OT', () {
      final checkIn = DateTime(2026, 9, 13, 9, 0);
      final checkOut = DateTime(2026, 9, 13, 8, 0);
      final otFixed = morningShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      final otFlex = flexibleShift8h.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);
      expect(otFixed, 0);
      expect(otFlex, 0);
    });
  });

  group('Adversarial Challenge 6: AttendanceNotifier End-to-End State Machine Integration', () {
    late FakeAttendanceRepository fakeRepo;
    late FakeLocationService fakeLocation;
    late ProviderContainer container;

    const testStaff = UserAccount(
      username: 'nhanvien_adversarial',
      displayName: 'Adversarial Tester',
      role: 'nhanvien',
      storeId: 'store_001',
    );

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

    test('Integration: Extreme late check-in (11:00) and check-out (13:00) yields 0 OT and preserves late status', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testStaff.username,
        initialShift: morningShift,
      );

      final checkInTime = DateTime(2026, 9, 13, 11, 0);
      await notifier.checkIn(
        user: testStaff,
        storeId: 'store_001',
        checkInTimestamp: checkInTime,
      );

      final checkOutTime = DateTime(2026, 9, 13, 13, 0);
      final success = await notifier.checkOut(
        user: testStaff,
        storeId: 'store_001',
        checkOutTimestamp: checkOutTime,
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      final record = state.todayAttendance!;
      expect(record.overtimeMinutes, 0);
      expect(record.status, AttendanceStatus.late);
      expect(record.totalWorkHours, 2.0);
    });

    test('Integration: Late check-in (09:00) and check-out (13:00) exactly compensates -> 0 OT, preserves late status', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testStaff.username,
        initialShift: morningShift,
      );

      await notifier.checkIn(
        user: testStaff,
        storeId: 'store_001',
        checkInTimestamp: DateTime(2026, 9, 13, 9, 0),
      );

      final success = await notifier.checkOut(
        user: testStaff,
        storeId: 'store_001',
        checkOutTimestamp: DateTime(2026, 9, 13, 13, 0),
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      final record = state.todayAttendance!;
      expect(record.overtimeMinutes, 0);
      expect(record.status, AttendanceStatus.late);
      expect(record.totalWorkHours, 4.0);
    });

    test('Integration: Late check-in (09:00) and check-out (13:01) -> 1 min OT and updates status to overtime', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testStaff.username,
        initialShift: morningShift,
      );

      await notifier.checkIn(
        user: testStaff,
        storeId: 'store_001',
        checkInTimestamp: DateTime(2026, 9, 13, 9, 0),
      );

      final success = await notifier.checkOut(
        user: testStaff,
        storeId: 'store_001',
        checkOutTimestamp: DateTime(2026, 9, 13, 13, 1),
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      final record = state.todayAttendance!;
      expect(record.overtimeMinutes, 1);
      expect(record.status, AttendanceStatus.overtime);
    });

    test('Integration: Early check-in (07:00) and check-out (12:30) -> 30 mins OT (not 90 mins) and status is overtime', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testStaff.username,
        initialShift: morningShift,
      );

      await notifier.checkIn(
        user: testStaff,
        storeId: 'store_001',
        checkInTimestamp: DateTime(2026, 9, 13, 7, 0),
      );

      final success = await notifier.checkOut(
        user: testStaff,
        storeId: 'store_001',
        checkOutTimestamp: DateTime(2026, 9, 13, 12, 30),
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      final record = state.todayAttendance!;
      expect(record.overtimeMinutes, 30);
      expect(record.status, AttendanceStatus.overtime);
      expect(record.totalWorkHours, 5.5);
    });

    test('Integration: Flexible shift with 8h01m -> 1 min OT and status is overtime', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testStaff.username,
        initialShift: flexibleShift8h,
      );

      await notifier.checkIn(
        user: testStaff,
        storeId: 'store_001',
        checkInTimestamp: DateTime(2026, 9, 13, 8, 0),
      );

      final success = await notifier.checkOut(
        user: testStaff,
        storeId: 'store_001',
        checkOutTimestamp: DateTime(2026, 9, 13, 16, 1),
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      final record = state.todayAttendance!;
      expect(record.overtimeMinutes, 1);
      expect(record.status, AttendanceStatus.overtime);
    });
  });

  group('Adversarial Challenge 7: Parametric Invariant Fuzzing (100 Iterations)', () {
    test('Invariant: For any checkIn delay D >= 0 and checkout extra E relative to shift end, OT == max(0, E - D)', () {
      final rng = math.Random(42);
      const testShift = morningShift; // 08:00 - 12:00, standard 4h = 240m

      for (int i = 0; i < 100; i++) {
        // D: checkIn delay from 0 to 240 minutes late (08:00 to 12:00)
        final delayMinutes = rng.nextInt(241);
        // E: checkOut delta from -60 to +180 minutes relative to 12:00 (11:00 to 15:00)
        final extraMinutes = rng.nextInt(241) - 60;

        final checkIn = DateTime(2026, 9, 13, 8, 0).add(Duration(minutes: delayMinutes));
        final checkOut = DateTime(2026, 9, 13, 12, 0).add(Duration(minutes: extraMinutes));

        // Skip invalid cases where checkOut <= checkIn
        if (!checkOut.isAfter(checkIn)) continue;

        final actualOT = testShift.calculateOvertimeMinutes(checkOut, baseDate, checkInTime: checkIn);

        // Mathematical invariant:
        // OT occurs only if checkOut > scheduledEnd (i.e. extraMinutes > 0)
        // and worked > standard (240 + extraMinutes - delayMinutes > 240 => extraMinutes > delayMinutes).
        // Then OT = min(extraMinutes, extraMinutes - delayMinutes) = extraMinutes - delayMinutes.
        final expectedOT = (extraMinutes > 0 && extraMinutes > delayMinutes)
            ? (extraMinutes - delayMinutes)
            : 0;

        expect(
          actualOT,
          expectedOT,
          reason: 'Failed invariant at iteration $i: delay=$delayMinutes, extra=$extraMinutes, actualOT=$actualOT, expectedOT=$expectedOT',
        );
      }
    });
  });
}
