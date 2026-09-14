import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/live_attendance_dashboard_provider.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'fake_attendance_repository.dart';

void main() {
  group('LiveAttendanceDashboard Scoping & Logic Tests', () {
    late FakeAttendanceRepository fakeRepo;

    const staff1 = UserAccount(
      username: 'staff_1',
      displayName: 'Nhân viên 1',
      role: 'nhanvien',
      storeId: 'store_001',
    );

    const supervisorUser = UserAccount(
      username: 'supervisor_1',
      displayName: 'Giám sát viên ĐT',
      role: 'supervisor',
      storeId: 'store_001',
    );

    const adminUser = UserAccount(
      username: 'admin_1',
      displayName: 'Quản trị viên',
      role: 'admin',
      storeId: 'store_001',
    );

    final today = DateTime.now();

    setUp(() {
      fakeRepo = FakeAttendanceRepository();

      // Seed records for today
      // Record 1: Store 001, working now, on-time
      fakeRepo.attendances.add(
        AttendanceRecord(
          id: 'att_01',
          userId: staff1.username,
          userName: staff1.name,
          storeId: 'store_001',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: today,
          checkInTime: DateTime(today.year, today.month, today.day, 8, 2),
          checkInGpsLat: 10.035,
          checkInGpsLng: 105.788,
          isGpsValid: true,
          status: AttendanceStatus.onTime,
        ),
      );

      // Record 2: Store 001, checked out, late
      fakeRepo.attendances.add(
        AttendanceRecord(
          id: 'att_02',
          userId: 'staff_2',
          userName: 'Nhân viên 2',
          storeId: 'store_001',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: today,
          checkInTime: DateTime(today.year, today.month, today.day, 8, 30),
          checkOutTime: DateTime(today.year, today.month, today.day, 12, 0),
          checkInGpsLat: 10.035,
          checkInGpsLng: 105.788,
          isGpsValid: true,
          status: AttendanceStatus.late,
          lateMinutes: 30,
          totalWorkHours: 3.5,
        ),
      );

      // Record 3: Store 002
      fakeRepo.attendances.add(
        AttendanceRecord(
          id: 'att_03',
          userId: 'staff_3',
          userName: 'Nhân viên 3 (TB)',
          storeId: 'store_002',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: today,
          checkInTime: DateTime(today.year, today.month, today.day, 8, 0),
          checkInGpsLat: 10.123,
          checkInGpsLng: 105.654,
          isGpsValid: true,
          status: AttendanceStatus.onTime,
        ),
      );
    });

    test('Categorizes working, late, and checked-out staff accurately for store', () async {
      final notifier = LiveAttendanceDashboardNotifier(
        fakeRepo,
        adminUser,
        initialStoreId: 'store_001',
      );
      await notifier.loadDashboard();

      final state = notifier.state;
      expect(state.storeId, 'store_001');
      expect(state.allRecords.length, 2);
      expect(state.workingCount, 1);
      expect(state.workingStaff.first.userId, 'staff_1');
      expect(state.lateCount, 1);
      expect(state.lateStaff.first.userId, 'staff_2');
      expect(state.checkedOutCount, 1);
      expect(state.checkedOutStaff.first.userId, 'staff_2');

      notifier.dispose();
    });

    test('Staff user: locked to assigned storeId and cannot change store', () async {
      final notifier = LiveAttendanceDashboardNotifier(
        fakeRepo,
        staff1,
        initialStoreId: 'store_001',
      );
      await notifier.loadDashboard();

      expect(notifier.state.storeId, 'store_001');

      // Attempt to change store
      await notifier.changeStore('store_002');
      // Must remain locked to store_001
      expect(notifier.state.storeId, 'store_001');

      notifier.dispose();
    });

    test('Admin user: can change store to store_002', () async {
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
      expect(notifier.state.allRecords.first.userId, 'staff_3');

      notifier.dispose();
    });

    test('Supervisor user: initialized with assigned storeId and can monitor store', () async {
      final notifier = LiveAttendanceDashboardNotifier(
        fakeRepo,
        supervisorUser,
        initialStoreId: 'store_001',
      );
      await notifier.loadDashboard();

      expect(notifier.state.storeId, 'store_001');
      expect(notifier.state.allRecords.length, 2);

      notifier.dispose();
    });
  });
}
