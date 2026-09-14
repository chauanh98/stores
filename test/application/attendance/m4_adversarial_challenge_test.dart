import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_adjustment_notifier.dart';
import 'package:stores/application/attendance/attendance_notifier.dart';
import 'package:stores/application/attendance/live_attendance_dashboard_provider.dart';
import 'package:stores/application/attendance/monthly_timesheet_notifier.dart';
import 'package:stores/data/datasources/firebase/attendance_remote_data_source.dart';
import 'package:stores/domain/attendance/attendance_adjustment.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/attendance/geo_distance_helper.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'fake_attendance_repository.dart';

void main() {
  group('Milestone 4 Adversarial Stress Tests', () {
    late FakeAttendanceRepository fakeRepo;
    late FakeLocationService fakeLocation;

    const testShift = Shift(
      id: 'shift_morning',
      name: 'Ca Sáng',
      startTime: '08:00',
      endTime: '12:00',
      gracePeriodMinutes: 15,
      type: 'morning',
      standardWorkHours: 4.0,
    );

    const testShiftAfternoon = Shift(
      id: 'shift_afternoon',
      name: 'Ca Chiều',
      startTime: '13:00',
      endTime: '17:30',
      gracePeriodMinutes: 15,
      type: 'afternoon',
      standardWorkHours: 4.5,
    );

    const staffUser = UserAccount(
      username: 'nhanvien_01',
      displayName: 'Nguyễn Văn A',
      role: 'nhanvien',
      storeId: 'store_001',
    );

    const supervisorUser = UserAccount(
      username: 'supervisor_01',
      displayName: 'Trần Giám Sát',
      role: 'supervisor',
      storeId: 'store_001',
    );

    const adminUser = UserAccount(
      username: 'admin_01',
      displayName: 'Lê Quản Trị',
      role: 'admin',
      storeId: 'store_001',
    );

    final today = DateTime.now();

    setUp(() {
      fakeRepo = FakeAttendanceRepository();
      fakeLocation = FakeLocationService();
    });

    // =========================================================================
    // 1. HAVERSINE & GEOFENCE BOUNDARIES
    // =========================================================================
    group('1. Haversine & Geofence Boundaries', () {
      const storeLat = 10.035000;
      const storeLon = 105.788000;
      const R = GeoDistanceHelper.earthRadiusMeters;

      test('Boundary exactly 150.0m is valid (true)', () {
        const dLat = (150.0 / R) * (180.0 / 3.141592653589793);
        final isWithin = GeoDistanceHelper.isWithinRadius(
          staffLat: storeLat + dLat,
          staffLon: storeLon,
          storeLat: storeLat,
          storeLon: storeLon,
          allowedRadiusMeters: 150.0,
        );
        expect(isWithin, isTrue);
      });

      test('Boundary just inside 149.9m is valid (true)', () {
        const dLat = (149.9 / R) * (180.0 / 3.141592653589793);
        final isWithin = GeoDistanceHelper.isWithinRadius(
          staffLat: storeLat + dLat,
          staffLon: storeLon,
          storeLat: storeLat,
          storeLon: storeLon,
          allowedRadiusMeters: 150.0,
        );
        expect(isWithin, isTrue);
      });

      test('Boundary just outside 150.1m is invalid (false)', () {
        const dLat = (150.1 / R) * (180.0 / 3.141592653589793);
        final isWithin = GeoDistanceHelper.isWithinRadius(
          staffLat: storeLat + dLat,
          staffLon: storeLon,
          storeLat: storeLat,
          storeLon: storeLon,
          allowedRadiusMeters: 150.0,
        );
        expect(isWithin, isFalse);
      });

      test('Zero coordinates: (0,0) to (0,0) returns 0.0m', () {
        final d = GeoDistanceHelper.haversineDistance(0.0, 0.0, 0.0, 0.0);
        expect(d, 0.0);
      });

      test('Antipode coordinates: (0,0) to (0,180) returns ~20015 km without NaN', () {
        final d = GeoDistanceHelper.haversineDistance(0.0, 0.0, 0.0, 180.0);
        expect(d.isNaN, isFalse);
        expect(d, closeTo(20015086.8, 1.0));
      });

      test('Extreme latitudes: (90,0) to (-90,0) returns ~20015 km without NaN', () {
        final d = GeoDistanceHelper.haversineDistance(90.0, 0.0, -90.0, 0.0);
        expect(d.isNaN, isFalse);
        expect(d, closeTo(20015086.8, 1.0));
      });
    });

    // =========================================================================
    // 2. CHECK-IN / CHECK-OUT EDGE CASES
    // =========================================================================
    group('2. Check-in / Check-out Edge Cases', () {
      test('Check-in exactly at start time (08:00) -> lateMinutes = 0, status = onTime', () async {
        final notifier = AttendanceNotifier(fakeRepo, fakeLocation);
        await notifier.init(storeId: 'store_001', userId: staffUser.username, initialShift: testShift);

        final checkInTime = DateTime(today.year, today.month, today.day, 8, 0, 0);
        final success = await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          checkInTimestamp: checkInTime,
        );

        expect(success, isTrue);
        final record = notifier.state.todayAttendance;
        expect(record, isNotNull);
        expect(record!.lateMinutes, 0);
        expect(record.status, AttendanceStatus.onTime);
      });

      test('Check-in at grace period limit (08:15) -> lateMinutes = 0, status = onTime', () async {
        final notifier = AttendanceNotifier(fakeRepo, fakeLocation);
        await notifier.init(storeId: 'store_001', userId: staffUser.username, initialShift: testShift);

        final checkInTime = DateTime(today.year, today.month, today.day, 8, 15, 0);
        final success = await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          checkInTimestamp: checkInTime,
        );

        expect(success, isTrue);
        final record = notifier.state.todayAttendance;
        expect(record, isNotNull);
        expect(record!.lateMinutes, 0);
        expect(record.status, AttendanceStatus.onTime);
      });

      test('Check-in 1 minute late (08:16) -> lateMinutes = 16, status = late', () async {
        final notifier = AttendanceNotifier(fakeRepo, fakeLocation);
        await notifier.init(storeId: 'store_001', userId: staffUser.username, initialShift: testShift);

        final checkInTime = DateTime(today.year, today.month, today.day, 8, 16, 0);
        final success = await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          checkInTimestamp: checkInTime,
        );

        expect(success, isTrue);
        final record = notifier.state.todayAttendance;
        expect(record, isNotNull);
        expect(record!.lateMinutes, 16);
        expect(record.status, AttendanceStatus.late);
      });

      test('Check-out exactly at end time (12:00) -> earlyLeave = 0, overtime = 0', () async {
        final notifier = AttendanceNotifier(fakeRepo, fakeLocation);
        await notifier.init(storeId: 'store_001', userId: staffUser.username, initialShift: testShift);

        await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          checkInTimestamp: DateTime(today.year, today.month, today.day, 8, 0),
        );

        final checkOutTime = DateTime(today.year, today.month, today.day, 12, 0, 0);
        final success = await notifier.checkOut(
          user: staffUser,
          storeId: 'store_001',
          checkOutTimestamp: checkOutTime,
        );

        expect(success, isTrue);
        final record = notifier.state.todayAttendance;
        expect(record!.earlyLeaveMinutes, 0);
        expect(record.overtimeMinutes, 0);
        expect(record.totalWorkHours, 4.0);
      });

      test('Check-out 1 minute early (11:59) -> earlyLeave = 1, status = earlyLeave', () async {
        final notifier = AttendanceNotifier(fakeRepo, fakeLocation);
        await notifier.init(storeId: 'store_001', userId: staffUser.username, initialShift: testShift);

        await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          checkInTimestamp: DateTime(today.year, today.month, today.day, 8, 0),
        );

        final checkOutTime = DateTime(today.year, today.month, today.day, 11, 59, 0);
        final success = await notifier.checkOut(
          user: staffUser,
          storeId: 'store_001',
          checkOutTimestamp: checkOutTime,
        );

        expect(success, isTrue);
        final record = notifier.state.todayAttendance;
        expect(record!.earlyLeaveMinutes, 1);
        expect(record.status, AttendanceStatus.earlyLeave);
        expect(record.totalWorkHours, 3.98); // 239 mins / 60 = 3.98h
      });

      test('Check-out overtime (12:45) -> overtime = 45, status = overtime', () async {
        final notifier = AttendanceNotifier(fakeRepo, fakeLocation);
        await notifier.init(storeId: 'store_001', userId: staffUser.username, initialShift: testShift);

        await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          checkInTimestamp: DateTime(today.year, today.month, today.day, 8, 0),
        );

        final checkOutTime = DateTime(today.year, today.month, today.day, 12, 45, 0);
        final success = await notifier.checkOut(
          user: staffUser,
          storeId: 'store_001',
          checkOutTimestamp: checkOutTime,
        );

        expect(success, isTrue);
        final record = notifier.state.todayAttendance;
        expect(record!.overtimeMinutes, 45);
        expect(record.status, AttendanceStatus.overtime);
        expect(record.totalWorkHours, 4.75); // 285 mins / 60 = 4.75h
      });

      test('Attempting check-in > 150m without explanation reason (null or empty or whitespace) MUST be blocked', () async {
        final notifier = AttendanceNotifier(fakeRepo, fakeLocation);
        // Position staff ~330m away
        fakeLocation.setSimulatedPosition(const GeoPoint(10.038000, 105.788000, 'Ngoại vi xa'));
        await notifier.init(storeId: 'store_001', userId: staffUser.username, initialShift: testShift);

        // 1. null explanation
        final failNull = await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          explanationReason: null,
        );
        expect(failNull, isFalse);
        expect(notifier.state.errorMessage, contains('ngoài bán kính'));

        // 2. empty string explanation
        final failEmpty = await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          explanationReason: '',
        );
        expect(failEmpty, isFalse);
        expect(notifier.state.errorMessage, contains('ngoài bán kính'));

        // 3. whitespace-only explanation
        final failWhitespace = await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          explanationReason: '   \n  \t  ',
        );
        expect(failWhitespace, isFalse);
        expect(notifier.state.errorMessage, contains('ngoài bán kính'));
      });

      test('Multiple check-ins in the same shift are blocked', () async {
        final notifier = AttendanceNotifier(fakeRepo, fakeLocation);
        await notifier.init(storeId: 'store_001', userId: staffUser.username, initialShift: testShift);

        final firstSuccess = await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          checkInTimestamp: DateTime(today.year, today.month, today.day, 8, 0),
        );
        expect(firstSuccess, isTrue);

        // Attempt second check-in to same shift
        final secondAttempt = await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          checkInTimestamp: DateTime(today.year, today.month, today.day, 8, 5),
        );
        expect(secondAttempt, isFalse);
        expect(notifier.state.errorMessage, contains('Bạn đã chấm công vào ca này hôm nay.'));
      });

      test('Check-in to different shift on the same day is permitted', () async {
        final notifier = AttendanceNotifier(fakeRepo, fakeLocation);
        await notifier.init(storeId: 'store_001', userId: staffUser.username, initialShift: testShift);

        // 1. Complete Morning Shift
        await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          checkInTimestamp: DateTime(today.year, today.month, today.day, 8, 0),
        );
        await notifier.checkOut(
          user: staffUser,
          storeId: 'store_001',
          checkOutTimestamp: DateTime(today.year, today.month, today.day, 12, 0),
        );
        expect(notifier.state.isCompletedToday, isTrue);

        // 2. Select Afternoon Shift
        await notifier.selectShift(
          testShiftAfternoon,
          storeId: 'store_001',
          userId: staffUser.username,
        );
        expect(notifier.state.canCheckIn, isTrue);

        // 3. Check-in to Afternoon Shift succeeds
        final afternoonSuccess = await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          checkInTimestamp: DateTime(today.year, today.month, today.day, 13, 0),
        );
        expect(afternoonSuccess, isTrue);
        expect(notifier.state.todayAttendance?.shiftId, testShiftAfternoon.id);
      });
    });

    // =========================================================================
    // 3. ROLE & STORE SCOPING
    // =========================================================================
    group('3. Role & Store Scoping', () {
      test('Admin can switch store and monitor all stores', () async {
        fakeRepo.attendances.add(
          AttendanceRecord(
            id: 'att_st2',
            userId: 'staff_store2',
            userName: 'Nhân viên kho 2',
            storeId: 'store_002',
            shiftId: 'shift_morning',
            shiftName: 'Ca Sáng',
            date: today,
            checkInTime: DateTime(today.year, today.month, today.day, 8, 0),
            checkInGpsLat: 10.123,
            checkInGpsLng: 105.654,
            isGpsValid: true,
          ),
        );

        final notifier = LiveAttendanceDashboardNotifier(
          fakeRepo,
          adminUser,
          initialStoreId: 'store_001',
        );
        await notifier.loadDashboard();
        expect(notifier.state.storeId, 'store_001');

        // Admin switches to store_002
        await notifier.changeStore('store_002');
        expect(notifier.state.storeId, 'store_002');
        expect(notifier.state.allRecords.length, 1);
        expect(notifier.state.allRecords.first.userId, 'staff_store2');

        notifier.dispose();
      });

      test('Supervisor store scoping: supervisor cannot switch to or monitor unauthorized stores', () async {
        // According to ORIGINAL_REQUEST.md §R4:
        // "Supervisor chỉ giám sát chi nhánh mình phụ trách; Admin có thể giám sát tất cả chi nhánh."
        final notifier = LiveAttendanceDashboardNotifier(
          fakeRepo,
          supervisorUser,
          initialStoreId: 'store_001',
        );
        await notifier.loadDashboard();
        expect(notifier.state.storeId, 'store_001');

        // Supervisor attempts to switch to unauthorized store_002
        await notifier.changeStore('store_002');

        // Must remain locked to assigned store
        expect(
          notifier.state.storeId,
          'store_001',
          reason: 'Supervisor must only monitor assigned store and cannot switch to unauthorized stores',
        );

        notifier.dispose();
      });

      test('Supervisor adjustment scoping: supervisor must only see adjustments for assigned store', () async {
        // Seed adjustment for store_001 and store_002
        fakeRepo.adjustments.addAll([
          AttendanceAdjustment(
            id: 'adj_s1',
            attendanceId: 'att_s1',
            userId: 'staff_1',
            userName: 'Nhân viên 1',
            storeId: 'store_001',
            requestedCheckIn: DateTime(today.year, today.month, today.day, 8, 0),
            requestedCheckOut: DateTime(today.year, today.month, today.day, 12, 0),
            reason: 'Giải trình store 1',
          ),
          AttendanceAdjustment(
            id: 'adj_s2',
            attendanceId: 'att_s2',
            userId: 'staff_2',
            userName: 'Nhân viên 2',
            storeId: 'store_002',
            requestedCheckIn: DateTime(today.year, today.month, today.day, 8, 0),
            requestedCheckOut: DateTime(today.year, today.month, today.day, 12, 0),
            reason: 'Giải trình store 2',
          ),
        ]);

        final notifier = AttendanceAdjustmentNotifier(fakeRepo, supervisorUser);
        await notifier.loadAdjustments();

        // Supervisor should only see store_001 adjustments (1 record), not store_002
        expect(
          notifier.state.adjustments.every((a) => a.storeId == 'store_001'),
          isTrue,
          reason: 'Supervisor must only see adjustments for assigned store_001, but saw cross-store adjustments due to canSwitchStore == true leak',
        );

        notifier.dispose();
      });
    });

    // =========================================================================
    // 4. TIMESHEET AGGREGATION & ADJUSTMENTS
    // =========================================================================
    group('4. Timesheet Aggregation & Adjustments', () {
      test('Decimal hours calculation for fractional minutes', () {
        final t0 = DateTime(2026, 9, 13, 8, 0);

        // 4h 0m
        expect(AttendanceRecord.calculateWorkHours(t0, DateTime(2026, 9, 13, 12, 0)), 4.00);

        // 4h 15m -> 4.25
        expect(AttendanceRecord.calculateWorkHours(t0, DateTime(2026, 9, 13, 12, 15)), 4.25);

        // 4h 30m -> 4.50
        expect(AttendanceRecord.calculateWorkHours(t0, DateTime(2026, 9, 13, 12, 30)), 4.50);

        // 4h 45m -> 4.75
        expect(AttendanceRecord.calculateWorkHours(t0, DateTime(2026, 9, 13, 12, 45)), 4.75);

        // 4h 20m -> 4.33
        expect(AttendanceRecord.calculateWorkHours(t0, DateTime(2026, 9, 13, 12, 20)), 4.33);

        // 1h 10m -> 1.17
        expect(AttendanceRecord.calculateWorkHours(t0, DateTime(2026, 9, 13, 9, 10)), 1.17);

        // CheckOut before CheckIn -> 0.00
        expect(AttendanceRecord.calculateWorkHours(t0, DateTime(2026, 9, 13, 7, 0)), 0.00);

        // CheckOut null -> 0.00
        expect(AttendanceRecord.calculateWorkHours(t0, null), 0.00);
      });

      test('Approved adjustment recalculates timesheet work hours', () async {
        // 1. Initial record: 2 hours worked (08:00 -> 10:00)
        final initialRecord = AttendanceRecord(
          id: 'att_record_adj_01',
          userId: staffUser.username,
          userName: staffUser.name,
          storeId: 'store_001',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: today,
          checkInTime: DateTime(today.year, today.month, today.day, 8, 0),
          checkOutTime: DateTime(today.year, today.month, today.day, 10, 0),
          totalWorkHours: 2.0,
          checkInGpsLat: 10.035,
          checkInGpsLng: 105.788,
          isGpsValid: true,
        );
        fakeRepo.attendances.add(initialRecord);

        // 2. Load monthly timesheet: verify initial 2.0 hours
        final timesheetNotifier = MonthlyTimesheetNotifier(
          fakeRepo,
          staffUser,
          initialStoreId: 'store_001',
          initialYear: today.year,
          initialMonth: today.month,
        );
        await timesheetNotifier.loadTimesheet();

        expect(timesheetNotifier.state.personalSummary!.totalHoursWorked, 2.0);

        // 3. Staff submits adjustment request: correct checkout to 12:00 (4.0 hours)
        final adjNotifier = AttendanceAdjustmentNotifier(fakeRepo, staffUser);
        final adjRequest = AttendanceAdjustment(
          id: 'adj_001',
          attendanceId: initialRecord.id,
          userId: staffUser.username,
          userName: staffUser.name,
          storeId: 'store_001',
          requestedCheckIn: DateTime(today.year, today.month, today.day, 8, 0),
          requestedCheckOut: DateTime(today.year, today.month, today.day, 12, 0),
          reason: 'Quên chấm công ra lúc 12:00 do hỗ trợ kiểm kho',
          submittedAt: DateTime.now(),
        );

        final submitSuccess = await adjNotifier.submitRequest(adjRequest);
        expect(submitSuccess, isTrue);

        // 4. Admin / Supervisor approves the adjustment
        final adminAdjNotifier = AttendanceAdjustmentNotifier(fakeRepo, adminUser);
        await adminAdjNotifier.loadAdjustments();
        final approveSuccess = await adminAdjNotifier.approve(
          adjustmentId: 'adj_001',
          reviewedBy: adminUser.username,
          reviewNote: 'Đã xác nhận với trưởng ca',
        );
        expect(approveSuccess, isTrue);

        // 5. Verify underlying attendance record was updated
        final updatedAtt = fakeRepo.attendances.firstWhere((a) => a.id == initialRecord.id);
        expect(updatedAtt.isAdjusted, isTrue);
        expect(updatedAtt.adjustmentId, 'adj_001');
        expect(updatedAtt.totalWorkHours, 4.0);

        // 6. Verify timesheet reflects recalculated hours (4.0h)
        await timesheetNotifier.loadTimesheet();
        expect(timesheetNotifier.state.personalSummary!.totalHoursWorked, 4.0);

        timesheetNotifier.dispose();
        adjNotifier.dispose();
        adminAdjNotifier.dispose();
      });
    });
  });
}
