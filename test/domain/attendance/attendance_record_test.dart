import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/attendance/attendance_record.dart';

void main() {
  group('AttendanceRecord & AttendanceStatus Tests', () {
    test('AttendanceStatus.fromString parses values and handles defaults', () {
      expect(AttendanceStatus.fromString('on_time'), AttendanceStatus.onTime);
      expect(AttendanceStatus.fromString('late'), AttendanceStatus.late);
      expect(AttendanceStatus.fromString('early_leave'), AttendanceStatus.earlyLeave);
      expect(AttendanceStatus.fromString('overtime'), AttendanceStatus.overtime);
      expect(AttendanceStatus.fromString('UNKNOWN'), AttendanceStatus.onTime);
      expect(AttendanceStatus.fromString(null), AttendanceStatus.onTime);
    });

    test('calculateWorkHours computes decimal hours properly', () {
      final inTime = DateTime(2026, 9, 13, 8, 0);
      final outTime = DateTime(2026, 9, 13, 12, 30);
      expect(AttendanceRecord.calculateWorkHours(inTime, outTime), 4.5);

      expect(AttendanceRecord.calculateWorkHours(inTime, null), 0.0);
    });

    test('AttendanceRecord properties and aliases work as expected', () {
      final record = AttendanceRecord(
        id: 'att_001',
        userId: 'user_01',
        userName: 'Nguyen Van A',
        storeId: 'store_001',
        shiftId: 'shift_morning',
        shiftName: 'Ca Sáng',
        date: DateTime(2026, 9, 13),
        checkInTime: DateTime(2026, 9, 13, 8, 5),
        checkInGpsLat: 10.035,
        checkInGpsLng: 105.788,
        isGpsValid: true,
      );

      expect(record.isWorking, isTrue);
      expect(record.checkInLat, 10.035);
      expect(record.checkInLng, 105.788);

      final checkedOut = record.copyWith(
        checkOutTime: DateTime(2026, 9, 13, 12, 0),
        totalWorkHours: 3.92,
      );
      expect(checkedOut.isWorking, isFalse);
      expect(checkedOut.totalWorkHours, 3.92);
    });
  });
}
