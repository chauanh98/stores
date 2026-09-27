import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/attendance/shift.dart';

void main() {
  group('Shift Entity Tests', () {
    const shift = Shift(
      id: 'shift_morning',
      name: 'Ca Sáng',
      startTime: '08:00',
      endTime: '12:00',
      gracePeriodMinutes: 15,
      type: 'morning',
      standardWorkHours: 4.0,
    );

    final testDate = DateTime(2026, 9, 13);

    test('getStartDateTime and getEndDateTime return correct DateTimes', () {
      final start = shift.getStartDateTime(testDate);
      final end = shift.getEndDateTime(testDate);

      expect(start, DateTime(2026, 9, 13, 8, 0));
      expect(end, DateTime(2026, 9, 13, 12, 0));
    });

    test('calculateLateMinutes: returns 0 if check in exactly at or before start time', () {
      final onTimeCheckIn = DateTime(2026, 9, 13, 8, 0);
      expect(shift.calculateLateMinutes(onTimeCheckIn, testDate), 0);

      final earlyCheckIn = DateTime(2026, 9, 13, 7, 55);
      expect(shift.calculateLateMinutes(earlyCheckIn, testDate), 0);
    });

    test('calculateLateMinutes: returns 0 if within grace period (e.g. 08:14 with 15min grace)', () {
      final graceCheckIn = DateTime(2026, 9, 13, 8, 14);
      expect(shift.calculateLateMinutes(graceCheckIn, testDate), 0);
    });

    test('calculateLateMinutes: returns actual late minutes if past grace period (e.g. 08:25 -> 25 min late)', () {
      final lateCheckIn = DateTime(2026, 9, 13, 8, 25);
      expect(shift.calculateLateMinutes(lateCheckIn, testDate), 25);
    });

    test('calculateEarlyLeaveMinutes: returns 0 if checkout at or after scheduled end', () {
      final exactCheckOut = DateTime(2026, 9, 13, 12, 0);
      expect(shift.calculateEarlyLeaveMinutes(exactCheckOut, testDate), 0);

      final lateCheckOut = DateTime(2026, 9, 13, 12, 10);
      expect(shift.calculateEarlyLeaveMinutes(lateCheckOut, testDate), 0);
    });

    test('calculateEarlyLeaveMinutes: returns positive minutes if left before scheduled end', () {
      final earlyCheckOut = DateTime(2026, 9, 13, 11, 40);
      expect(shift.calculateEarlyLeaveMinutes(earlyCheckOut, testDate), 20);
    });

    test('calculateOvertimeMinutes: returns minutes worked past end time', () {
      final normalCheckOut = DateTime(2026, 9, 13, 12, 0);
      expect(shift.calculateOvertimeMinutes(normalCheckOut, testDate), 0);

      final otCheckOut = DateTime(2026, 9, 13, 12, 45);
      expect(shift.calculateOvertimeMinutes(otCheckOut, testDate), 45);
    });

    test('Flexible shift calculates 0 for late, early leave, and overtime', () {
      const flexShift = Shift(
        id: 'shift_flex',
        name: 'Ca Linh hoạt',
        startTime: '08:00',
        endTime: '22:00',
        type: 'flexible',
      );

      final lateTime = DateTime(2026, 9, 13, 9, 30);
      final earlyTime = DateTime(2026, 9, 13, 16, 0);

      expect(flexShift.calculateLateMinutes(lateTime, testDate), 0);
      expect(flexShift.calculateEarlyLeaveMinutes(earlyTime, testDate), 0);
      expect(flexShift.calculateOvertimeMinutes(lateTime, testDate), 0);
    });

    group('Standardized Overtime Calculation (R1)', () {
      test('Shift 08:00 - 12:00, check-in 12:00, check-out 14:00 (worked 2h) -> 0 min overtime (2h worked bug fix)', () {
        final checkIn = DateTime(2026, 9, 13, 12, 0);
        final checkOut = DateTime(2026, 9, 13, 14, 0);
        expect(shift.calculateOvertimeMinutes(checkOut, testDate, checkInTime: checkIn), 0);
      });

      test('Shift 08:00 - 12:00, check-in 08:00, check-out 12:45 (worked 4h45) -> 45 min overtime', () {
        final checkIn = DateTime(2026, 9, 13, 8, 0);
        final checkOut = DateTime(2026, 9, 13, 12, 45);
        expect(shift.calculateOvertimeMinutes(checkOut, testDate, checkInTime: checkIn), 45);
      });

      test('Shift 08:00 - 12:00, check-in 09:00 (1h late), check-out 13:00 (worked 4h) -> 0 min overtime (Late arrival compensated)', () {
        final checkIn = DateTime(2026, 9, 13, 9, 0);
        final checkOut = DateTime(2026, 9, 13, 13, 0);
        expect(shift.calculateOvertimeMinutes(checkOut, testDate, checkInTime: checkIn), 0);
      });

      test('Shift 08:00 - 12:00, check-in 09:00 (1h late), check-out 13:30 (worked 4h30) -> 30 min overtime', () {
        final checkIn = DateTime(2026, 9, 13, 9, 0);
        final checkOut = DateTime(2026, 9, 13, 13, 30);
        expect(shift.calculateOvertimeMinutes(checkOut, testDate, checkInTime: checkIn), 30);
      });

      test('Shift 08:00 - 12:00, check-in 08:00, check-out 11:30 -> 0 min overtime', () {
        final checkIn = DateTime(2026, 9, 13, 8, 0);
        final checkOut = DateTime(2026, 9, 13, 11, 30);
        expect(shift.calculateOvertimeMinutes(checkOut, testDate, checkInTime: checkIn), 0);
      });

      test('Shift 08:00 - 12:00, check-in 07:30 (early), check-out 12:00 -> 0 min overtime (not past scheduled end)', () {
        final checkIn = DateTime(2026, 9, 13, 7, 30);
        final checkOut = DateTime(2026, 9, 13, 12, 0);
        expect(shift.calculateOvertimeMinutes(checkOut, testDate, checkInTime: checkIn), 0);
      });

      test('Shift 08:00 - 12:00, check-in 07:30 (early), check-out 12:15 -> 15 min overtime (capped by past scheduled end)', () {
        final checkIn = DateTime(2026, 9, 13, 7, 30);
        final checkOut = DateTime(2026, 9, 13, 12, 15);
        expect(shift.calculateOvertimeMinutes(checkOut, testDate, checkInTime: checkIn), 15);
      });

      test('Flexible shift (standardWorkHours = 8.0): check-in 08:00, check-out 18:00 (worked 10h) -> 120 min overtime', () {
        const flexibleShift = Shift(
          id: 'shift_flexible',
          name: 'Ca Linh hoạt',
          startTime: '08:00',
          endTime: '22:00',
          type: 'flexible',
          standardWorkHours: 8.0,
        );
        final checkIn = DateTime(2026, 9, 13, 8, 0);
        final checkOut = DateTime(2026, 9, 13, 18, 0);
        expect(flexibleShift.calculateOvertimeMinutes(checkOut, testDate, checkInTime: checkIn), 120);
      });

      test('Flexible shift (standardWorkHours = 8.0): check-in 08:00, check-out 15:00 (worked 7h) -> 0 min overtime', () {
        const flexibleShift = Shift(
          id: 'shift_flexible',
          name: 'Ca Linh hoạt',
          startTime: '08:00',
          endTime: '22:00',
          type: 'flexible',
          standardWorkHours: 8.0,
        );
        final checkIn = DateTime(2026, 9, 13, 8, 0);
        final checkOut = DateTime(2026, 9, 13, 15, 0);
        expect(flexibleShift.calculateOvertimeMinutes(checkOut, testDate, checkInTime: checkIn), 0);
      });

      test('Backward compatibility: calculateOvertimeMinutes without checkInTime uses start time', () {
        final normalCheckOut = DateTime(2026, 9, 13, 12, 0);
        expect(shift.calculateOvertimeMinutes(normalCheckOut, testDate), 0);

        final otCheckOut = DateTime(2026, 9, 13, 12, 45);
        expect(shift.calculateOvertimeMinutes(otCheckOut, testDate), 45);
      });
    });

    group('Shift Time-Window Validation & Auto-Selection (R2)', () {
      final testDate = DateTime(2026, 9, 13);

      test('getCheckInWindowStart opens 60 minutes before startTime', () {
        expect(shift.getCheckInWindowStart(testDate), DateTime(2026, 9, 13, 7, 0));
      });

      test('getCheckInWindowEnd matches endTime', () {
        expect(shift.getCheckInWindowEnd(testDate), DateTime(2026, 9, 13, 12, 0));
      });

      test('Cross-midnight shift correctly resolves getEndDateTime to next day', () {
        const overnightShift = Shift(
          id: 'shift_night',
          name: 'Ca Đêm',
          startTime: '22:00',
          endTime: '06:00',
          type: 'evening',
        );

        final start = overnightShift.getStartDateTime(testDate);
        final end = overnightShift.getEndDateTime(testDate);

        expect(start, DateTime(2026, 9, 13, 22, 0));
        expect(end, DateTime(2026, 9, 14, 6, 0));
        expect(overnightShift.getCheckInWindowStart(testDate), DateTime(2026, 9, 13, 21, 0));
        expect(overnightShift.getCheckInWindowEnd(testDate), DateTime(2026, 9, 14, 6, 0));

        // In window on next day
        final at1am = DateTime(2026, 9, 14, 1, 0);
        expect(overnightShift.getWindowStatus(at1am, testDate), ShiftWindowStatus.open);
        // Verify without explicit yesterday date (defaults to baseDate DateTime(2026, 9, 14))
        expect(overnightShift.getWindowStatus(at1am), ShiftWindowStatus.open);

        // After end on next day
        final at601am = DateTime(2026, 9, 14, 6, 1);
        expect(overnightShift.getWindowStatus(at601am, testDate), ShiftWindowStatus.closed);
      });

      test('getWindowStatus transitions accurately across boundaries for fixed shift', () {
        // Before 07:00 -> upcoming
        final at659 = DateTime(2026, 9, 13, 6, 59, 59);
        expect(shift.getWindowStatus(at659, testDate), ShiftWindowStatus.upcoming);
        expect(shift.isCheckInWindowOpen(at659, testDate), isFalse);

        // At 07:00:00 -> open
        final at700 = DateTime(2026, 9, 13, 7, 0, 0);
        expect(shift.getWindowStatus(at700, testDate), ShiftWindowStatus.open);
        expect(shift.isCheckInWindowOpen(at700, testDate), isTrue);

        // At 08:00 (start time) -> open
        final at800 = DateTime(2026, 9, 13, 8, 0, 0);
        expect(shift.getWindowStatus(at800, testDate), ShiftWindowStatus.open);

        // At 12:00:00 (exact end time) -> open
        final at1200 = DateTime(2026, 9, 13, 12, 0, 0);
        expect(shift.getWindowStatus(at1200, testDate), ShiftWindowStatus.open);

        // At 12:00:01 / 12:01 (past end time) -> closed
        final at1201 = DateTime(2026, 9, 13, 12, 1, 0);
        expect(shift.getWindowStatus(at1201, testDate), ShiftWindowStatus.closed);
        expect(shift.isCheckInWindowOpen(at1201, testDate), isFalse);
      });

      test('getWindowStatus handles flexible shifts', () {
        const flexShift = Shift(
          id: 'shift_flex',
          name: 'Ca Linh hoạt',
          startTime: '08:00',
          endTime: '22:00',
          type: 'flexible',
        );

        final upcoming = DateTime(2026, 9, 13, 6, 50);
        final open = DateTime(2026, 9, 13, 14, 0);
        final closed = DateTime(2026, 9, 13, 22, 5);

        expect(flexShift.getWindowStatus(upcoming, testDate), ShiftWindowStatus.upcoming);
        expect(flexShift.getWindowStatus(open, testDate), ShiftWindowStatus.open);
        expect(flexShift.getWindowStatus(closed, testDate), ShiftWindowStatus.closed);
      });

      group('findBestShiftForTime', () {
        final shifts = Shift.defaultShifts();

        test('At 07:15 AM selects Ca Sáng (open fixed shift prioritized over flexible)', () {
          final now = DateTime(2026, 9, 13, 7, 15);
          final best = Shift.findBestShiftForTime(shifts, now);
          expect(best?.id, 'shift_morning');
        });

        test('At 08:15 AM selects Ca Sáng', () {
          final now = DateTime(2026, 9, 13, 8, 15);
          final best = Shift.findBestShiftForTime(shifts, now);
          expect(best?.id, 'shift_morning');
        });

        test('At 12:30 PM selects Ca Chiều (morning shift closed, afternoon window open)', () {
          final now = DateTime(2026, 9, 13, 12, 30);
          final best = Shift.findBestShiftForTime(shifts, now);
          expect(best?.id, 'shift_afternoon');
        });

        test('At 16:45 PM selects Ca Tối (closer to Ca Tối start at 17:30 than Ca Chiều start at 13:00)', () {
          final now = DateTime(2026, 9, 13, 16, 45);
          final best = Shift.findBestShiftForTime(shifts, now);
          expect(best?.id, 'shift_evening');
        });

        test('At 23:00 PM falls back to first active shift when all shifts closed', () {
          final now = DateTime(2026, 9, 13, 23, 0);
          final best = Shift.findBestShiftForTime(shifts, now);
          expect(best?.id, 'shift_morning');
        });

        test('Returns null when shifts list is empty', () {
          final now = DateTime(2026, 9, 13, 12, 0);
          expect(Shift.findBestShiftForTime([], now), isNull);
        });

        test('Upcoming shift selected if no shift is currently open', () {
          const shift1 = Shift(
            id: 'shift_1',
            name: 'Ca 1',
            startTime: '10:00',
            endTime: '12:00',
            type: 'morning',
          );
          const shift2 = Shift(
            id: 'shift_2',
            name: 'Ca 2',
            startTime: '14:00',
            endTime: '18:00',
            type: 'afternoon',
          );

          // At 08:30 (shift1 window opens at 09:00, so neither is open)
          final now = DateTime(2026, 9, 13, 8, 30);
          final best = Shift.findBestShiftForTime([shift1, shift2], now);
          expect(best?.id, 'shift_1');
        });
      });
    });
  });
}
