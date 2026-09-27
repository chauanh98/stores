import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_adjustment_notifier.dart';
import 'package:stores/application/attendance/attendance_notifier.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/application/attendance/live_attendance_dashboard_provider.dart';
import 'package:stores/domain/attendance/attendance_adjustment.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'fake_attendance_repository.dart';

// =============================================================================
// FAKE FIREBASE DATABASE FOR EMPIRICAL STRESS TESTING
// =============================================================================

class FakeDataSnapshot extends Fake implements DataSnapshot {
  final bool _exists;
  final dynamic _value;

  FakeDataSnapshot({required bool exists, dynamic value})
      : _exists = exists,
        _value = value;

  @override
  bool get exists => _exists;

  @override
  dynamic get value => _value;
}

class FakeDatabaseReference extends Fake implements DatabaseReference {
  final DataSnapshot _snapshot;

  FakeDatabaseReference(this._snapshot);

  @override
  Future<DataSnapshot> get() async => _snapshot;
}

class FakeFirebaseDatabase extends Fake implements FirebaseDatabase {
  final dynamic _accountsData;
  final bool _exists;

  FakeFirebaseDatabase({dynamic accountsData, bool exists = true})
      : _accountsData = accountsData,
        _exists = exists;

  @override
  DatabaseReference ref([String? path]) {
    return FakeDatabaseReference(
      FakeDataSnapshot(exists: _exists, value: _accountsData),
    );
  }
}

// =============================================================================
// MAIN TEST SUITE
// =============================================================================

void main() {
  // ---------------------------------------------------------------------------
  // GROUP 1: UserAccount RBAC & Permission Getters Stress Testing
  // ---------------------------------------------------------------------------
  group('1. UserAccount Permission Getters Permutation & Edge-Case Stress Tests', () {
    test('Staff variations (casing, whitespace) always map to staff and require attendance', () {
      final variations = [
        'nhanvien',
        'NhanVien',
        'NHANVIEN',
        '  nhanvien  ',
        '\tnhanvien\n',
        'Nhanvien',
      ];

      for (final role in variations) {
        final account = UserAccount(
          username: 'user_${role.trim()}',
          role: role,
          storeId: 'store_001',
        );

        expect(account.isSupervisor, isFalse, reason: 'Failed for role: "$role"');
        expect(account.isAdmin, isFalse, reason: 'Failed for role: "$role"');
        expect(account.isStaff, isTrue, reason: 'Failed for role: "$role"');
        expect(account.requiresAttendance, isTrue, reason: 'Failed for role: "$role"');
        expect(account.canManageShifts, isFalse, reason: 'Failed for role: "$role"');
        expect(account.canAdjustAttendance, isFalse, reason: 'Failed for role: "$role"');
      }
    });

    test('Admin variations (casing, whitespace) grant management and exempt from attendance', () {
      final variations = [
        'admin',
        'Admin',
        'ADMIN',
        '  admin  ',
        '\tADMIN\n',
        'AdMiN',
      ];

      for (final role in variations) {
        final account = UserAccount(
          username: 'admin_${role.trim()}',
          role: role,
          storeId: 'store_001',
        );

        expect(account.isSupervisor, isFalse, reason: 'Failed for role: "$role"');
        expect(account.isAdmin, isTrue, reason: 'Failed for role: "$role"');
        expect(account.isStaff, isFalse, reason: 'Failed for role: "$role"');
        expect(account.requiresAttendance, isFalse, reason: 'Failed for role: "$role"');
        expect(account.canManageShifts, isTrue, reason: 'Failed for role: "$role"');
        expect(account.canAdjustAttendance, isTrue, reason: 'Failed for role: "$role"');
        expect(account.canSwitchStore, isTrue, reason: 'Failed for role: "$role"');
      }
    });

    test('Supervisor variations (casing, whitespace) grant management and exempt from attendance', () {
      final variations = [
        'supervisor',
        'Supervisor',
        'SUPERVISOR',
        '  supervisor  ',
        '\tsupervisor\n',
        'SuPeRvIsOr',
      ];

      for (final role in variations) {
        final account = UserAccount(
          username: 'sup_${role.trim()}',
          role: role,
          storeId: 'store_001',
        );

        expect(account.isSupervisor, isTrue, reason: 'Failed for role: "$role"');
        expect(account.isAdmin, isFalse, reason: 'Supervisor is branch manager, not system admin');
        expect(account.isStaff, isFalse, reason: 'Failed for role: "$role"');
        expect(account.requiresAttendance, isFalse, reason: 'Failed for role: "$role"');
        expect(account.canManageShifts, isTrue, reason: 'Failed for role: "$role"');
        expect(account.canAdjustAttendance, isTrue, reason: 'Failed for role: "$role"');
      }
    });

    test('Unknown or empty roles fail closed to staff privileges (least privilege principle)', () {
      final variations = [
        '',
        '   ',
        'unknown',
        'GUEST',
        'random_role_123',
        'manager',
      ];

      for (final role in variations) {
        final account = UserAccount(
          username: 'user_${role.trim()}',
          role: role,
          storeId: 'store_001',
        );

        // Security assertion: Unknown roles must NEVER obtain management or bypass attendance
        expect(account.isSupervisor, isFalse, reason: 'Privilege leak for role: "$role"');
        expect(account.isAdmin, isFalse, reason: 'Privilege leak for role: "$role"');
        expect(account.canManageShifts, isFalse, reason: 'Privilege leak for role: "$role"');
        expect(account.canAdjustAttendance, isFalse, reason: 'Privilege leak for role: "$role"');
        expect(account.isStaff, isTrue, reason: 'Fallback to least privilege');
        expect(account.requiresAttendance, isTrue, reason: 'Fallback to least privilege');
      }
    });

    test('UserAccount.fromMap handles nulls, missing keys, and non-string types safely', () {
      // 1. Missing role -> defaults to 'nhanvien'
      final acc1 = UserAccount.fromMap('user1', {'storeId': 'store_001'});
      expect(acc1.role, 'nhanvien');
      expect(acc1.requiresAttendance, isTrue);

      // 2. Missing storeId -> defaults to ''
      final acc2 = UserAccount.fromMap('user2', {'role': 'supervisor'});
      expect(acc2.storeId, '');
      expect(acc2.requiresAttendance, isFalse);

      // 3. Null displayName -> falls back to username
      final acc3 = UserAccount.fromMap('user3', {'role': 'nhanvien'});
      expect(acc3.displayName, isNull);
      expect(acc3.name, 'user3');

      // 4. Empty map -> all safe defaults
      final acc4 = UserAccount.fromMap('user4', {});
      expect(acc4.role, 'nhanvien');
      expect(acc4.storeId, '');
      expect(acc4.name, 'user4');

      // 5. Non-string types in map (int, bool)
      final acc5 = UserAccount.fromMap('user5', {
        'role': 12345,
        'storeId': 999,
        'displayName': true,
      });
      expect(acc5.role, '12345');
      expect(acc5.storeId, '999');
      expect(acc5.displayName, 'true');
      expect(acc5.requiresAttendance, isTrue); // Unknown role fails closed to staff
    });
  });

  // ---------------------------------------------------------------------------
  // GROUP 2: LiveAttendanceDashboardNotifier Staff Filtering & Exclusion Tests
  // ---------------------------------------------------------------------------
  group('2. LiveAttendanceDashboardNotifier _fetchStaffForStore & notArrivedStaff Stress Tests', () {
    late FakeAttendanceRepository fakeRepo;

    final mockAccountsMap = {
      'admin_001': {
        'displayName': 'Tổng Quản Trị',
        'role': 'admin',
        'storeId': 'store_001',
      },
      'admin_caps': {
        'displayName': 'ADMIN CAPS',
        'role': ' ADMIN ',
        'storeId': 'store_001',
      },
      'sup_001': {
        'displayName': 'Giám Sát Chi Nhánh 1',
        'role': 'supervisor',
        'storeId': 'store_001',
      },
      'sup_caps': {
        'displayName': 'SUPERVISOR CAPS',
        'role': ' SUPERVISOR ',
        'storeId': 'store_001',
      },
      'staff_001': {
        'displayName': 'Nhân Viên 1',
        'role': 'nhanvien',
        'storeId': 'store_001',
      },
      'staff_002': {
        'displayName': 'Nhân Viên 2',
        'role': 'NhanVien',
        'storeId': 'store_001',
      },
      'staff_003': {
        'displayName': 'Nhân Viên 3 (Whitespace)',
        'role': '  nhanvien  ',
        'storeId': 'store_001',
      },
      'staff_store2': {
        'displayName': 'Nhân Viên Kho 2',
        'role': 'nhanvien',
        'storeId': 'store_002',
      },
      'sup_store2': {
        'displayName': 'Giám Sát Kho 2',
        'role': 'supervisor',
        'storeId': 'store_002',
      },
      'corrupt_entry': 'this_is_not_a_map',
    };

    setUp(() {
      fakeRepo = FakeAttendanceRepository();
    });

    test('Supervisor and Admin NEVER appear in notArrivedStaff when 0 attendances recorded', () async {
      final fakeDb = FakeFirebaseDatabase(accountsData: mockAccountsMap);
      const supervisorUser = UserAccount(
        username: 'sup_001',
        role: 'supervisor',
        storeId: 'store_001',
      );

      final notifier = LiveAttendanceDashboardNotifier(
        fakeRepo,
        supervisorUser,
        db: fakeDb,
        initialStoreId: 'store_001',
      );

      await notifier.loadDashboard();

      final state = notifier.state;
      expect(state.isLoading, isFalse);
      expect(state.allRecords, isEmpty);

      // Verify notArrivedStaff
      final notArrivedUsernames =
          state.notArrivedStaff.map((u) => u.username).toList();

      // STRICT EXCLUSION ASSERTIONS:
      expect(notArrivedUsernames, isNot(contains('admin_001')));
      expect(notArrivedUsernames, isNot(contains('admin_caps')));
      expect(notArrivedUsernames, isNot(contains('sup_001')));
      expect(notArrivedUsernames, isNot(contains('sup_caps')));
      expect(notArrivedUsernames, isNot(contains('sup_store2')));

      // Cross-store exclusion
      expect(notArrivedUsernames, isNot(contains('staff_store2')));

      // Staff inclusion assertions:
      expect(notArrivedUsernames, containsAll(['staff_001', 'staff_002', 'staff_003']));
      expect(state.notArrivedStaff.length, 3);
    });

    test('Staff who check in are properly removed from notArrivedStaff (case-insensitive)', () async {
      final fakeDb = FakeFirebaseDatabase(accountsData: mockAccountsMap);
      final today = DateTime.now();

      // staff_001 checks in with uppercase userId 'STAFF_001'
      fakeRepo.attendances.add(
        AttendanceRecord(
          id: 'att_01',
          userId: 'STAFF_001',
          userName: 'Nhân Viên 1',
          storeId: 'store_001',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: today,
          checkInTime: DateTime(today.year, today.month, today.day, 8, 0),
          checkInGpsLat: 10.035,
          checkInGpsLng: 105.788,
          isGpsValid: true,
        ),
      );

      const supervisorUser = UserAccount(
        username: 'sup_001',
        role: 'supervisor',
        storeId: 'store_001',
      );

      final notifier = LiveAttendanceDashboardNotifier(
        fakeRepo,
        supervisorUser,
        db: fakeDb,
        initialStoreId: 'store_001',
      );

      await notifier.loadDashboard();

      final state = notifier.state;
      expect(state.workingStaff.length, 1);
      expect(state.workingStaff.first.userId, 'STAFF_001');

      final notArrivedUsernames =
          state.notArrivedStaff.map((u) => u.username).toList();

      // staff_001 was matched case-insensitively and removed from notArrived
      expect(notArrivedUsernames, isNot(contains('staff_001')));
      expect(notArrivedUsernames, containsAll(['staff_002', 'staff_003']));
      expect(state.notArrivedStaff.length, 2);

      // Supervisor and Admin STILL never appear
      expect(notArrivedUsernames, isNot(contains('admin_001')));
      expect(notArrivedUsernames, isNot(contains('sup_001')));
    });

    test('Empty database or null snapshot handles gracefully with empty notArrivedStaff', () async {
      final emptyDb = FakeFirebaseDatabase(accountsData: null, exists: false);
      const supervisorUser = UserAccount(
        username: 'sup_001',
        role: 'supervisor',
        storeId: 'store_001',
      );

      final notifier = LiveAttendanceDashboardNotifier(
        fakeRepo,
        supervisorUser,
        db: emptyDb,
        initialStoreId: 'store_001',
      );

      await notifier.loadDashboard();

      final state = notifier.state;
      expect(state.notArrivedStaff, isEmpty);
      expect(state.errorMessage, isNull);
    });

    test('Store change scoping: pure admin can switch stores, supervisor is rejected', () async {
      final fakeDb = FakeFirebaseDatabase(accountsData: mockAccountsMap);

      // 1. Supervisor attempt to change store
      const supervisorUser = UserAccount(
        username: 'sup_001',
        role: 'supervisor',
        storeId: 'store_001',
      );
      final supNotifier = LiveAttendanceDashboardNotifier(
        fakeRepo,
        supervisorUser,
        db: fakeDb,
        initialStoreId: 'store_001',
      );
      await supNotifier.changeStore('store_002');
      expect(supNotifier.state.storeId, 'store_001',
          reason: 'Supervisor must be locked to store_001');

      // 2. Pure Admin can change store
      const adminUser = UserAccount(
        username: 'admin_001',
        role: 'admin',
        storeId: 'store_001',
      );
      final adminNotifier = LiveAttendanceDashboardNotifier(
        fakeRepo,
        adminUser,
        db: fakeDb,
        initialStoreId: 'store_001',
      );
      await adminNotifier.changeStore('store_002');
      expect(adminNotifier.state.storeId, 'store_002',
          reason: 'Admin must be permitted to change store');
    });
  });

  // ---------------------------------------------------------------------------
  // GROUP 3: AttendanceNotifier checkIn / checkOut RBAC Enforcement Stress Tests
  // ---------------------------------------------------------------------------
  group('3. AttendanceNotifier checkIn / checkOut RBAC Enforcement Stress Tests', () {
    final morningShift = Shift.defaultShifts().first;

    test('Admin accounts (casing permutations) are STRICTLY rejected on checkIn', () async {
      final adminRoles = ['admin', 'ADMIN', '  admin  ', 'Admin'];

      for (final role in adminRoles) {
        final fakeRepo = FakeAttendanceRepository();
        final fakeLocation = FakeLocationService();
        final container = ProviderContainer(
          overrides: [
            attendanceRepositoryProvider.overrideWithValue(fakeRepo),
            locationServiceProvider.overrideWithValue(fakeLocation),
          ],
        );
        addTearDown(container.dispose);

        final adminUser = UserAccount(
          username: 'admin_user',
          role: role,
          storeId: 'store_001',
        );

        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: adminUser.username,
          initialShift: morningShift,
        );

        final success = await notifier.checkIn(
          user: adminUser,
          storeId: 'store_001',
        );

        expect(success, isFalse, reason: 'Admin role "$role" should be rejected from checkIn');
        final state = container.read(attendanceNotifierProvider);
        expect(state.errorMessage, 'Tài khoản quản lý không thuộc đối tượng chấm công.');
        expect(state.todayAttendance, isNull);
        expect(fakeRepo.attendances, isEmpty);
      }
    });

    test('Supervisor accounts (casing permutations) are STRICTLY rejected on checkIn', () async {
      final supervisorRoles = ['supervisor', 'SUPERVISOR', '  supervisor  ', 'Supervisor'];

      for (final role in supervisorRoles) {
        final fakeRepo = FakeAttendanceRepository();
        final fakeLocation = FakeLocationService();
        final container = ProviderContainer(
          overrides: [
            attendanceRepositoryProvider.overrideWithValue(fakeRepo),
            locationServiceProvider.overrideWithValue(fakeLocation),
          ],
        );
        addTearDown(container.dispose);

        final supUser = UserAccount(
          username: 'sup_user',
          role: role,
          storeId: 'store_001',
        );

        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: supUser.username,
          initialShift: morningShift,
        );

        final success = await notifier.checkIn(
          user: supUser,
          storeId: 'store_001',
        );

        expect(success, isFalse, reason: 'Supervisor role "$role" should be rejected from checkIn');
        final state = container.read(attendanceNotifierProvider);
        expect(state.errorMessage, 'Tài khoản quản lý không thuộc đối tượng chấm công.');
        expect(state.todayAttendance, isNull);
        expect(fakeRepo.attendances, isEmpty);
      }
    });

    test('Admin and Supervisor accounts are STRICTLY rejected on checkOut', () async {
      final fakeRepo = FakeAttendanceRepository();
      final fakeLocation = FakeLocationService();
      final container = ProviderContainer(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(fakeRepo),
          locationServiceProvider.overrideWithValue(fakeLocation),
        ],
      );
      addTearDown(container.dispose);

      const adminUser = UserAccount(
        username: 'admin_user',
        role: 'admin',
        storeId: 'store_001',
      );
      const supUser = UserAccount(
        username: 'sup_user',
        role: 'supervisor',
        storeId: 'store_001',
      );

      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: adminUser.username,
        initialShift: morningShift,
      );

      // Admin checkOut
      final adminCheckOut = await notifier.checkOut(
        user: adminUser,
        storeId: 'store_001',
      );
      expect(adminCheckOut, isFalse);
      expect(container.read(attendanceNotifierProvider).errorMessage,
          'Tài khoản quản lý không thuộc đối tượng chấm công.');

      // Supervisor checkOut
      final supCheckOut = await notifier.checkOut(
        user: supUser,
        storeId: 'store_001',
      );
      expect(supCheckOut, isFalse);
      expect(container.read(attendanceNotifierProvider).errorMessage,
          'Tài khoản quản lý không thuộc đối tượng chấm công.');
    });

    test('Staff accounts (casing permutations) pass RBAC check and can check in', () async {
      final staffRoles = ['nhanvien', 'NhanVien', '  nhanvien  '];

      for (final role in staffRoles) {
        final fakeRepo = FakeAttendanceRepository();
        final fakeLocation = FakeLocationService();
        final container = ProviderContainer(
          overrides: [
            attendanceRepositoryProvider.overrideWithValue(fakeRepo),
            locationServiceProvider.overrideWithValue(fakeLocation),
          ],
        );
        addTearDown(container.dispose);

        final staffUser = UserAccount(
          username: 'staff_${role.trim()}',
          role: role,
          storeId: 'store_001',
        );

        final notifier = container.read(attendanceNotifierProvider.notifier);
        await notifier.init(
          storeId: 'store_001',
          userId: staffUser.username,
          initialShift: morningShift,
        );

        final success = await notifier.checkIn(
          user: staffUser,
          storeId: 'store_001',
          checkInTimestamp: DateTime(2026, 9, 14, 8, 5),
        );

        expect(success, isTrue, reason: 'Staff role "$role" must pass RBAC checkIn');
        final state = container.read(attendanceNotifierProvider);
        expect(state.errorMessage, isNull);
        expect(state.todayAttendance, isNotNull);
        expect(state.todayAttendance!.userId, staffUser.username);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // GROUP 4: AttendanceAdjustmentNotifier RBAC & Mutation Protection Stress Tests
  // ---------------------------------------------------------------------------
  group('4. AttendanceAdjustmentNotifier RBAC & Mutation Protection Stress Tests', () {
    late FakeAttendanceRepository fakeRepo;

    setUp(() {
      fakeRepo = FakeAttendanceRepository();

      // Seed an attendance record
      fakeRepo.attendances.add(
        AttendanceRecord(
          id: 'att_target_1',
          userId: 'staff_01',
          userName: 'Nhân Viên 1',
          storeId: 'store_001',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: DateTime(2026, 9, 14),
          checkInTime: DateTime(2026, 9, 14, 8, 0),
          checkInGpsLat: 10.035,
          checkInGpsLng: 105.788,
          isGpsValid: true,
          isAdjusted: false,
        ),
      );

      // Seed a pending adjustment
      fakeRepo.adjustments.add(
        AttendanceAdjustment(
          id: 'adj_target_1',
          attendanceId: 'att_target_1',
          userId: 'staff_01',
          userName: 'Nhân Viên 1',
          storeId: 'store_001',
          requestedCheckIn: DateTime(2026, 9, 14, 8, 0),
          requestedCheckOut: DateTime(2026, 9, 14, 12, 0),
          reason: 'Quên bấm giờ về',
          status: AdjustmentStatus.pending,
          submittedAt: DateTime(2026, 9, 14, 12, 30),
        ),
      );
    });

    test('Staff accounts (casing permutations) are STRICTLY REJECTED from approve', () async {
      final staffRoles = ['nhanvien', 'NhanVien', '  nhanvien  ', 'NHANVIEN'];

      for (final role in staffRoles) {
        final staffUser = UserAccount(
          username: 'staff_${role.trim()}',
          role: role,
          storeId: 'store_001',
        );

        final notifier = AttendanceAdjustmentNotifier(fakeRepo, staffUser);
        // Wait for async loadAdjustments triggered in constructor to settle
        await pumpEventQueue();

        final result = await notifier.approve(
          adjustmentId: 'adj_target_1',
          reviewedBy: staffUser.username,
          reviewNote: 'Tự duyệt công của mình',
        );

        expect(result, isFalse, reason: 'Staff role "$role" must not approve adjustments');
        expect(notifier.state.errorMessage, 'Bạn không có quyền duyệt điều chỉnh chấm công.');

        // Verify underlying database/repo was NOT modified
        final adj = fakeRepo.adjustments.firstWhere((a) => a.id == 'adj_target_1');
        expect(adj.status, AdjustmentStatus.pending, reason: 'Database status must remain pending');
        expect(adj.reviewedBy, isNull);

        final att = fakeRepo.attendances.firstWhere((a) => a.id == 'att_target_1');
        expect(att.isAdjusted, isFalse);
      }
    });

    test('Staff accounts (casing permutations) are STRICTLY REJECTED from reject', () async {
      final staffRoles = ['nhanvien', 'NhanVien', '  nhanvien  ', 'NHANVIEN'];

      for (final role in staffRoles) {
        final staffUser = UserAccount(
          username: 'staff_${role.trim()}',
          role: role,
          storeId: 'store_001',
        );

        final notifier = AttendanceAdjustmentNotifier(fakeRepo, staffUser);
        // Wait for async loadAdjustments triggered in constructor to settle
        await pumpEventQueue();

        final result = await notifier.reject(
          adjustmentId: 'adj_target_1',
          reviewedBy: staffUser.username,
          reviewNote: 'Từ chối trái phép',
        );

        expect(result, isFalse, reason: 'Staff role "$role" must not reject adjustments');
        expect(notifier.state.errorMessage, 'Bạn không có quyền duyệt điều chỉnh chấm công.');

        // Verify underlying database/repo was NOT modified
        final adj = fakeRepo.adjustments.firstWhere((a) => a.id == 'adj_target_1');
        expect(adj.status, AdjustmentStatus.pending, reason: 'Database status must remain pending');
        expect(adj.reviewedBy, isNull);
      }
    });

    test('Supervisor accounts (casing permutations) CAN approve and update underlying record', () async {
      final supRoles = ['supervisor', 'Supervisor', 'SUPERVISOR', '  supervisor  '];

      for (final role in supRoles) {
        // Reset adjustment to pending
        final index = fakeRepo.adjustments.indexWhere((a) => a.id == 'adj_target_1');
        fakeRepo.adjustments[index] = fakeRepo.adjustments[index].copyWith(
          status: AdjustmentStatus.pending,
          reviewedBy: null,
        );

        final supUser = UserAccount(
          username: 'sup_${role.trim()}',
          role: role,
          storeId: 'store_001',
        );

        final notifier = AttendanceAdjustmentNotifier(fakeRepo, supUser);
        await pumpEventQueue();

        final result = await notifier.approve(
          adjustmentId: 'adj_target_1',
          reviewedBy: supUser.username,
          reviewNote: 'Duyệt bởi giám sát',
        );

        expect(result, isTrue, reason: 'Supervisor role "$role" should be authorized to approve');
        expect(notifier.state.errorMessage, isNull);

        final adj = fakeRepo.adjustments.firstWhere((a) => a.id == 'adj_target_1');
        expect(adj.status, AdjustmentStatus.approved);
        expect(adj.reviewedBy, supUser.username);
      }
    });

    test('Admin accounts CAN approve and reject adjustments', () async {
      const adminUser = UserAccount(
        username: 'admin_01',
        role: 'admin',
        storeId: 'store_001',
      );

      final notifier = AttendanceAdjustmentNotifier(fakeRepo, adminUser);
      await pumpEventQueue();

      final result = await notifier.approve(
        adjustmentId: 'adj_target_1',
        reviewedBy: adminUser.username,
        reviewNote: 'Admin duyệt',
      );

      expect(result, isTrue);
      expect(fakeRepo.adjustments.first.status, AdjustmentStatus.approved);

      // Now test reject on another adjustment
      fakeRepo.adjustments.add(
        AttendanceAdjustment(
          id: 'adj_target_2',
          attendanceId: 'att_target_1',
          userId: 'staff_01',
          userName: 'Nhân Viên 1',
          storeId: 'store_001',
          requestedCheckIn: DateTime(2026, 9, 14, 8, 0),
          requestedCheckOut: DateTime(2026, 9, 14, 18, 0),
          reason: 'Xin tăng ca',
          status: AdjustmentStatus.pending,
        ),
      );

      final rejectResult = await notifier.reject(
        adjustmentId: 'adj_target_2',
        reviewedBy: adminUser.username,
        reviewNote: 'Không duyệt tăng ca',
      );

      expect(rejectResult, isTrue);
      final adj2 = fakeRepo.adjustments.firstWhere((a) => a.id == 'adj_target_2');
      expect(adj2.status, AdjustmentStatus.rejected);
    });

    test('Unauthenticated user (currentUser == null) fails closed and is STRICTLY REJECTED from approve and reject', () async {
      final unauthNotifier = AttendanceAdjustmentNotifier(fakeRepo, null);
      await pumpEventQueue();

      final unauthApprove = await unauthNotifier.approve(
        adjustmentId: 'adj_target_1',
        reviewedBy: 'anonymous_intruder',
      );

      expect(unauthApprove, isFalse,
          reason: 'Fail-closed security: null currentUser must not approve adjustments');
      expect(unauthNotifier.state.errorMessage, 'Bạn không có quyền duyệt điều chỉnh chấm công.');
      expect(fakeRepo.adjustments.first.reviewedBy, isNull);
      expect(fakeRepo.adjustments.first.status, AdjustmentStatus.pending);

      final unauthReject = await unauthNotifier.reject(
        adjustmentId: 'adj_target_1',
        reviewedBy: 'anonymous_intruder',
      );

      expect(unauthReject, isFalse,
          reason: 'Fail-closed security: null currentUser must not reject adjustments');
      expect(unauthNotifier.state.errorMessage, 'Bạn không có quyền duyệt điều chỉnh chấm công.');
      expect(fakeRepo.adjustments.first.reviewedBy, isNull);
      expect(fakeRepo.adjustments.first.status, AdjustmentStatus.pending);
    });

    test('State integrity: copyWith preserves errorMessage when async load settles', () async {
      const staffUser = UserAccount(
        username: 'staff_immediate',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      // Construct notifier and DO NOT await pumpEventQueue - call approve immediately
      final notifier = AttendanceAdjustmentNotifier(fakeRepo, staffUser);
      final rejectedImmediately = await notifier.approve(
        adjustmentId: 'adj_target_1',
        reviewedBy: staffUser.username,
      );
      expect(rejectedImmediately, isFalse);
      expect(notifier.state.errorMessage, 'Bạn không có quyền duyệt điều chỉnh chấm công.');

      // Let the constructor's loadAdjustments complete
      await pumpEventQueue();

      // Verify errorMessage is PRESERVED and not wiped by load completion
      expect(notifier.state.errorMessage, 'Bạn không có quyền duyệt điều chỉnh chấm công.',
          reason: 'State integrity: errorMessage must be preserved across async load settlements');
      expect(notifier.state.isLoading, isFalse);
    });

    test('State integrity: copyWith preserves errorMessage when unauth caller rejects immediately before async load settles', () async {
      // Construct notifier without currentUser and call reject immediately before load settles
      final notifier = AttendanceAdjustmentNotifier(fakeRepo, null);
      final rejectedImmediately = await notifier.reject(
        adjustmentId: 'adj_target_1',
        reviewedBy: 'anonymous_intruder',
      );
      expect(rejectedImmediately, isFalse);
      expect(notifier.state.errorMessage, 'Bạn không có quyền duyệt điều chỉnh chấm công.');

      // Settle background loadAdjustments
      await pumpEventQueue();

      expect(notifier.state.errorMessage, 'Bạn không có quyền duyệt điều chỉnh chấm công.',
          reason: 'State integrity: unauth reject error must be preserved after async load');
      expect(notifier.state.isLoading, isFalse);
      expect(fakeRepo.adjustments.first.status, AdjustmentStatus.pending);
      expect(fakeRepo.adjustments.first.reviewedBy, isNull);
    });

    test('Concurrent unauthorized attempts: rapid fire approve/reject calls preserve error and leave DB unmutated', () async {
      final unauthNotifier = AttendanceAdjustmentNotifier(fakeRepo, null);
      const staffUser = UserAccount(username: 'staff_rapid', role: 'nhanvien', storeId: 'store_001');
      final staffNotifier = AttendanceAdjustmentNotifier(fakeRepo, staffUser);

      // Fire multiple concurrent unauthorized review requests
      final results = await Future.wait([
        unauthNotifier.approve(adjustmentId: 'adj_target_1', reviewedBy: 'anon1'),
        unauthNotifier.reject(adjustmentId: 'adj_target_1', reviewedBy: 'anon2'),
        staffNotifier.approve(adjustmentId: 'adj_target_1', reviewedBy: 'staff_rapid'),
        staffNotifier.reject(adjustmentId: 'adj_target_1', reviewedBy: 'staff_rapid'),
      ]);

      expect(results, [false, false, false, false]);
      expect(unauthNotifier.state.errorMessage, 'Bạn không có quyền duyệt điều chỉnh chấm công.');
      expect(staffNotifier.state.errorMessage, 'Bạn không có quyền duyệt điều chỉnh chấm công.');

      await pumpEventQueue();

      // Check preservation after all events settle
      expect(unauthNotifier.state.errorMessage, 'Bạn không có quyền duyệt điều chỉnh chấm công.');
      expect(staffNotifier.state.errorMessage, 'Bạn không có quyền duyệt điều chỉnh chấm công.');
      expect(fakeRepo.adjustments.first.status, AdjustmentStatus.pending);
      expect(fakeRepo.adjustments.first.reviewedBy, isNull);
    });
  });
}

