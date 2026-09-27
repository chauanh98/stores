import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_notifier.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/data/datasources/firebase/attendance_remote_data_source.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'fake_attendance_repository.dart';

void main() {
  group('AttendanceNotifier Tests', () {
    late FakeAttendanceRepository fakeRepo;
    late FakeLocationService fakeLocation;
    late ProviderContainer container;

    const testUser = UserAccount(
      username: 'nhanvien_01',
      displayName: 'Nguyễn Văn An',
      role: 'nhanvien',
      storeId: 'store_001',
    );

    final morningShift = Shift.defaultShifts().first; // 08:00 - 12:00, grace: 15

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

    test('Initializes state with store GPS and calculates distance <= 150m', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      final state = container.read(attendanceNotifierProvider);
      expect(state.selectedShift?.id, morningShift.id);
      expect(state.isWithinRadius, isTrue);
      expect(state.distanceToStoreMeters, lessThan(150.0));
      expect(state.canCheckIn, isTrue);
    });

    test('Check-in within 150m succeeds without requiring explanation', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      // On time check-in: 08:05 on today's date
      final checkInTime = DateTime(2026, 9, 13, 8, 5);
      final success = await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        checkInTimestamp: checkInTime,
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      expect(state.todayAttendance, isNotNull);
      expect(state.todayAttendance!.isGpsValid, isTrue);
      expect(state.todayAttendance!.status, AttendanceStatus.onTime);
      expect(state.todayAttendance!.lateMinutes, 0);
      expect(state.canCheckOut, isTrue);
    });

    test('Check-in outside 150m fails when explanation is missing', () async {
      // Simulate position ~350m away
      fakeLocation.setSimulatedPosition(const GeoPoint(10.038500, 105.788000));

      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      final stateBefore = container.read(attendanceNotifierProvider);
      expect(stateBefore.isWithinRadius, isFalse);
      expect(stateBefore.distanceToStoreMeters, greaterThan(150.0));

      // Attempt check-in without explanation
      final success = await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        explanationReason: null,
      );

      expect(success, isFalse);
      final stateAfter = container.read(attendanceNotifierProvider);
      expect(stateAfter.errorMessage, contains('lý do giải trình'));
      expect(stateAfter.todayAttendance, isNull);
    });

    test('Check-in outside 150m succeeds when explanation reason is provided', () async {
      fakeLocation.setSimulatedPosition(const GeoPoint(10.038500, 105.788000));

      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      final success = await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        explanationReason: 'Đi giao hàng cho khách ghé qua điểm bán',
        checkInTimestamp: DateTime(2026, 9, 13, 8, 10),
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      expect(state.todayAttendance, isNotNull);
      expect(state.todayAttendance!.isGpsValid, isFalse);
      expect(state.todayAttendance!.explanationReason, 'Đi giao hàng cho khách ghé qua điểm bán');
    });

    test('Check-in calculates lateMinutes when check-in is past grace period', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      // Morning shift starts at 08:00, grace is 15 min (threshold 08:15).
      // Check in at 08:35 -> 35 minutes late!
      final lateTime = DateTime(2026, 9, 13, 8, 35);
      final success = await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        checkInTimestamp: lateTime,
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      expect(state.todayAttendance!.status, AttendanceStatus.late);
      expect(state.todayAttendance!.lateMinutes, 35);
    });

    test('Check-out detects early leave when checked out before shift end', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        checkInTimestamp: DateTime(2026, 9, 13, 8, 0),
      );

      // Shift ends at 12:00. Check out at 11:30 -> 30 min early leave!
      final earlyCheckOut = DateTime(2026, 9, 13, 11, 30);
      final success = await notifier.checkOut(
        user: testUser,
        storeId: 'store_001',
        checkOutTimestamp: earlyCheckOut,
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      expect(state.todayAttendance!.status, AttendanceStatus.earlyLeave);
      expect(state.todayAttendance!.earlyLeaveMinutes, 30);
      expect(state.todayAttendance!.totalWorkHours, 3.5);
      expect(state.isCompletedToday, isTrue);
    });

    test('Check-out detects overtime when checked out past shift end', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        checkInTimestamp: DateTime(2026, 9, 13, 8, 0),
      );

      // Shift ends at 12:00. Check out at 12:45 -> 45 min overtime!
      final otCheckOut = DateTime(2026, 9, 13, 12, 45);
      final success = await notifier.checkOut(
        user: testUser,
        storeId: 'store_001',
        checkOutTimestamp: otCheckOut,
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      expect(state.todayAttendance!.status, AttendanceStatus.overtime);
      expect(state.todayAttendance!.overtimeMinutes, 45);
      expect(state.todayAttendance!.totalWorkHours, 4.75);
    });

    test('Check-out: late check-in (12:00) and check-out (14:00) yields 0 overtime minutes (fixes 2h worked bug)', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        checkInTimestamp: DateTime(2026, 9, 13, 12, 0),
      );

      final checkOutTime = DateTime(2026, 9, 13, 14, 0);
      final success = await notifier.checkOut(
        user: testUser,
        storeId: 'store_001',
        checkOutTimestamp: checkOutTime,
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      expect(state.todayAttendance!.overtimeMinutes, 0);
      expect(state.todayAttendance!.status, AttendanceStatus.late);
      expect(state.todayAttendance!.totalWorkHours, 2.0);
    });

    test('Check-out: late check-in (09:00) and check-out (13:00) compensates late arrival and yields 0 overtime', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        checkInTimestamp: DateTime(2026, 9, 13, 9, 0),
      );

      final checkOutTime = DateTime(2026, 9, 13, 13, 0);
      final success = await notifier.checkOut(
        user: testUser,
        storeId: 'store_001',
        checkOutTimestamp: checkOutTime,
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      expect(state.todayAttendance!.overtimeMinutes, 0);
      expect(state.todayAttendance!.status, AttendanceStatus.late);
      expect(state.todayAttendance!.totalWorkHours, 4.0);
    });

    test('Check-out: late check-in (09:00) and check-out (13:30) yields 30 min overtime', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        checkInTimestamp: DateTime(2026, 9, 13, 9, 0),
      );

      final checkOutTime = DateTime(2026, 9, 13, 13, 30);
      final success = await notifier.checkOut(
        user: testUser,
        storeId: 'store_001',
        checkOutTimestamp: checkOutTime,
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      expect(state.todayAttendance!.overtimeMinutes, 30);
      expect(state.todayAttendance!.status, AttendanceStatus.overtime);
      expect(state.todayAttendance!.totalWorkHours, 4.5);
    });

    test('Check-out: flexible shift records overtime when worked hours exceed standardWorkHours', () async {
      final flexibleShift = Shift.defaultShifts().firstWhere((s) => s.type == 'flexible');
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: flexibleShift,
      );

      await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        checkInTimestamp: DateTime(2026, 9, 13, 8, 0),
      );

      final checkOutTime = DateTime(2026, 9, 13, 18, 0);
      final success = await notifier.checkOut(
        user: testUser,
        storeId: 'store_001',
        checkOutTimestamp: checkOutTime,
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      expect(state.todayAttendance!.overtimeMinutes, 120);
      expect(state.todayAttendance!.status, AttendanceStatus.overtime);
      expect(state.todayAttendance!.totalWorkHours, 10.0);
    });

    test('Non-staff accounts (admin, supervisor) are blocked from check-in and check-out', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: 'admin_user',
        initialShift: morningShift,
      );

      const adminUser = UserAccount(
        username: 'admin_01',
        role: 'admin',
        storeId: 'store_001',
      );

      const supervisorUser = UserAccount(
        username: 'supervisor_01',
        role: 'supervisor',
        storeId: 'store_001',
      );

      // Admin check-in blocked
      final adminCheckIn = await notifier.checkIn(
        user: adminUser,
        storeId: 'store_001',
      );
      expect(adminCheckIn, isFalse);
      expect(container.read(attendanceNotifierProvider).errorMessage,
          contains('Tài khoản quản lý không thuộc đối tượng chấm công'));

      // Supervisor check-in blocked
      final supervisorCheckIn = await notifier.checkIn(
        user: supervisorUser,
        storeId: 'store_001',
      );
      expect(supervisorCheckIn, isFalse);
      expect(container.read(attendanceNotifierProvider).errorMessage,
          contains('Tài khoản quản lý không thuộc đối tượng chấm công'));

      // Admin check-out blocked
      final adminCheckOut = await notifier.checkOut(
        user: adminUser,
        storeId: 'store_001',
      );
      expect(adminCheckOut, isFalse);
      expect(container.read(attendanceNotifierProvider).errorMessage,
          contains('Tài khoản quản lý không thuộc đối tượng chấm công'));
    });

    group('Shift Window Validation Integration Tests (R2)', () {
      test('Check-in to closed shift (e.g. 12:01 PM for Ca Sáng 08:00 - 12:00) is rejected with exact message', () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testUser.username,
          initialShift: morningShift,
        );

        // Attempt check-in at 12:01 (1 minute past Ca Sáng end time 12:00)
        final checkInTime = DateTime(2026, 9, 13, 12, 1);
        final success = await notifier.checkIn(
          user: testUser,
          storeId: 'store_001',
          checkInTimestamp: checkInTime,
        );

        expect(success, isFalse);
        final state = container.read(attendanceNotifierProvider);
        expect(
          state.errorMessage,
          'Ca Ca Sáng đã kết thúc lúc 12:00. Bạn không thể chấm công vào ca đã qua. Vui lòng chọn ca kế tiếp.',
        );
        expect(state.todayAttendance, isNull);
        expect(fakeRepo.attendances, isEmpty);
      });

      test('Check-in in the afternoon (e.g. 14:00) for morning shift is rejected and does not mutate database', () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testUser.username,
          initialShift: morningShift,
        );

        // Attempt check-in at 14:00 PM for morning shift
        final checkInTime = DateTime(2026, 9, 13, 14, 0);
        final success = await notifier.checkIn(
          user: testUser,
          storeId: 'store_001',
          checkInTimestamp: checkInTime,
        );

        expect(success, isFalse);
        final state = container.read(attendanceNotifierProvider);
        expect(
          state.errorMessage,
          'Ca Ca Sáng đã kết thúc lúc 12:00. Bạn không thể chấm công vào ca đã qua. Vui lòng chọn ca kế tiếp.',
        );
        expect(state.todayAttendance, isNull);
        expect(fakeRepo.attendances, isEmpty);
      });

      test('Check-in to upcoming shift (e.g. 06:45 AM for Ca Sáng 08:00 - 12:00) is rejected with exact message', () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testUser.username,
          initialShift: morningShift,
        );

        // Attempt check-in at 06:45 AM (gate opens at 07:00, 60m before 08:00 start)
        final checkInTime = DateTime(2026, 9, 13, 6, 45);
        final success = await notifier.checkIn(
          user: testUser,
          storeId: 'store_001',
          checkInTimestamp: checkInTime,
        );

        expect(success, isFalse);
        final state = container.read(attendanceNotifierProvider);
        expect(
          state.errorMessage,
          'Ca Ca Sáng chưa mở chấm công. Cổng chấm công mở lúc 07:00 (trước giờ bắt đầu 60 phút).',
        );
        expect(state.todayAttendance, isNull);
        expect(fakeRepo.attendances, isEmpty);
      });

      test('Check-in within open window (e.g. 07:30 AM or 11:59 AM) succeeds and writes record to repository', () async {
        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: testUser.username,
          initialShift: morningShift,
        );

        // Check-in at 07:30 AM (between 07:00 and 12:00)
        final checkInTime = DateTime(2026, 9, 13, 7, 30);
        final success = await notifier.checkIn(
          user: testUser,
          storeId: 'store_001',
          checkInTimestamp: checkInTime,
        );

        expect(success, isTrue);
        final state = container.read(attendanceNotifierProvider);
        expect(state.errorMessage, isNull);
        expect(state.todayAttendance, isNotNull);
        expect(state.todayAttendance!.shiftId, morningShift.id);
        expect(fakeRepo.attendances.length, 1);
        expect(fakeRepo.attendances.first.shiftId, morningShift.id);
      });
    });
  });
}
