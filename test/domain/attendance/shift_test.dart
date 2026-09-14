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
  });
}
