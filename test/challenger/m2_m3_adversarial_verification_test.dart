import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_notifier.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/application/attendance/store_gps_config_notifier.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/attendance/store_gps_config.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../application/attendance/fake_attendance_repository.dart';

class SlowControllableAttendanceRepository extends FakeAttendanceRepository {
  Completer<StoreGpsConfig?>? getGpsCompleter;
  Completer<void>? saveGpsCompleter;
  bool shouldThrowOnGet = false;
  bool shouldThrowOnSave = false;

  @override
  Future<StoreGpsConfig?> getStoreGpsConfig(String storeId) async {
    if (shouldThrowOnGet) throw Exception('Simulated network failure on get');
    if (getGpsCompleter != null) return getGpsCompleter!.future;
    return super.getStoreGpsConfig(storeId);
  }

  @override
  Future<void> saveStoreGpsConfig(StoreGpsConfig config) async {
    if (shouldThrowOnSave) throw Exception('Simulated network failure on save');
    if (saveGpsCompleter != null) return saveGpsCompleter!.future;
    return super.saveStoreGpsConfig(config);
  }
}

class _TestAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _TestAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Requirement 1: Shift Time-Window Boundary Conditions', () {
    const morningShift = Shift(
      id: 'shift_morning',
      name: 'Ca Sáng',
      startTime: '08:00',
      endTime: '12:00',
      gracePeriodMinutes: 15,
      type: 'morning',
      standardWorkHours: 4.0,
    );

    final baseDate = DateTime(2026, 9, 19);

    test('Boundary 1: Exactly at startTime - 60 min (07:00:00) MUST be open', () {
      final exactOpenTime = DateTime(2026, 9, 19, 7, 0, 0);
      final status = morningShift.getWindowStatus(exactOpenTime, baseDate);
      expect(status, ShiftWindowStatus.open);
      expect(morningShift.isCheckInWindowOpen(exactOpenTime, baseDate), isTrue);
    });

    test('Boundary 2: Exactly at startTime - 61 min (06:59:00) MUST be upcoming', () {
      final oneMinuteBeforeOpen = DateTime(2026, 9, 19, 6, 59, 0);
      final status = morningShift.getWindowStatus(oneMinuteBeforeOpen, baseDate);
      expect(status, ShiftWindowStatus.upcoming);
      expect(morningShift.isCheckInWindowOpen(oneMinuteBeforeOpen, baseDate), isFalse);
    });

    test('Boundary 2b: 1 second before window opens (06:59:59) MUST be upcoming', () {
      final oneSecondBeforeOpen = DateTime(2026, 9, 19, 6, 59, 59);
      final status = morningShift.getWindowStatus(oneSecondBeforeOpen, baseDate);
      expect(status, ShiftWindowStatus.upcoming);
      expect(morningShift.isCheckInWindowOpen(oneSecondBeforeOpen, baseDate), isFalse);
    });

    test('Boundary 3: Exactly at endTime (12:00:00) MUST be open / not closed', () {
      final exactEndTime = DateTime(2026, 9, 19, 12, 0, 0);
      final status = morningShift.getWindowStatus(exactEndTime, baseDate);
      expect(status, ShiftWindowStatus.open);
      expect(morningShift.isCheckInWindowOpen(exactEndTime, baseDate), isTrue);
    });

    test('Boundary 4: 1 second after endTime (12:00:01) MUST be closed', () {
      final oneSecondAfterEnd = DateTime(2026, 9, 19, 12, 0, 1);
      final status = morningShift.getWindowStatus(oneSecondAfterEnd, baseDate);
      expect(status, ShiftWindowStatus.closed);
      expect(morningShift.isCheckInWindowOpen(oneSecondAfterEnd, baseDate), isFalse);
    });

    test('Boundary 4b: 1 minute after endTime (12:01:00) MUST be closed', () {
      final oneMinuteAfterEnd = DateTime(2026, 9, 19, 12, 1, 0);
      final status = morningShift.getWindowStatus(oneMinuteAfterEnd, baseDate);
      expect(status, ShiftWindowStatus.closed);
      expect(morningShift.isCheckInWindowOpen(oneMinuteAfterEnd, baseDate), isFalse);
    });
  });

  group('Requirement 1 (cont): Cross-Midnight Shifts', () {
    const nightShift22 = Shift(
      id: 'shift_night_22',
      name: 'Ca Đêm 22h',
      startTime: '22:00',
      endTime: '06:00',
      gracePeriodMinutes: 15,
      type: 'evening',
      standardWorkHours: 8.0,
    );

    const nightShift2230 = Shift(
      id: 'shift_night_2230',
      name: 'Ca Đêm 22h30',
      startTime: '22:30',
      endTime: '06:00',
      gracePeriodMinutes: 15,
      type: 'evening',
      standardWorkHours: 7.5,
    );

    final shiftStartDate = DateTime(2026, 9, 19);

    test('Cross-midnight shift (22:00 to 06:00) evaluated with shift start date (2026-09-19)', () {
      // 20:59 (61 min before start) -> upcoming
      final at2059 = DateTime(2026, 9, 19, 20, 59);
      expect(nightShift22.getWindowStatus(at2059, shiftStartDate), ShiftWindowStatus.upcoming);

      // 21:00 (exact start - 60 min) -> open
      final at2100 = DateTime(2026, 9, 19, 21, 0);
      expect(nightShift22.getWindowStatus(at2100, shiftStartDate), ShiftWindowStatus.open);

      // 21:30 -> open
      final at2130 = DateTime(2026, 9, 19, 21, 30);
      expect(nightShift22.getWindowStatus(at2130, shiftStartDate), ShiftWindowStatus.open);

      // 23:00 -> open
      final at2300 = DateTime(2026, 9, 19, 23, 0);
      expect(nightShift22.getWindowStatus(at2300, shiftStartDate), ShiftWindowStatus.open);

      // 05:59 next day -> open
      final at0559 = DateTime(2026, 9, 20, 5, 59);
      expect(nightShift22.getWindowStatus(at0559, shiftStartDate), ShiftWindowStatus.open);

      // 06:00 next day (exact end) -> open
      final at0600 = DateTime(2026, 9, 20, 6, 0);
      expect(nightShift22.getWindowStatus(at0600, shiftStartDate), ShiftWindowStatus.open);

      // 06:01 next day (after end) -> closed
      final at0601 = DateTime(2026, 9, 20, 6, 1);
      expect(nightShift22.getWindowStatus(at0601, shiftStartDate), ShiftWindowStatus.closed);
    });

    test('Cross-midnight shift (22:30 to 06:00) matches literal prompt specification: 21:00 (upcoming), 21:30 (open), 23:00 (open), 05:59 (open), 06:01 (closed)', () {
      // For a shift starting at 22:30:
      // startTime - 60 min = 21:30 (opens at 21:30)
      // At 21:00: 90 min before startTime -> upcoming
      final at2100 = DateTime(2026, 9, 19, 21, 0);
      expect(nightShift2230.getWindowStatus(at2100, shiftStartDate), ShiftWindowStatus.upcoming);

      // At 21:30: exactly 60 min before startTime -> open
      final at2130 = DateTime(2026, 9, 19, 21, 30);
      expect(nightShift2230.getWindowStatus(at2130, shiftStartDate), ShiftWindowStatus.open);

      // At 23:00: shift in progress -> open
      final at2300 = DateTime(2026, 9, 19, 23, 0);
      expect(nightShift2230.getWindowStatus(at2300, shiftStartDate), ShiftWindowStatus.open);

      // At 05:59 next day: shift in progress -> open
      final at0559 = DateTime(2026, 9, 20, 5, 59);
      expect(nightShift2230.getWindowStatus(at0559, shiftStartDate), ShiftWindowStatus.open);

      // At 06:01 next day: shift ended -> closed
      final at0601 = DateTime(2026, 9, 20, 6, 1);
      expect(nightShift2230.getWindowStatus(at0601, shiftStartDate), ShiftWindowStatus.closed);
    });

    test('Cross-midnight getWindowStatus without passing baseDate on next morning (05:59 and 06:01)', () {
      // When checkTime is next morning (2026-09-20 05:59), date is not passed:
      // Correct cross-midnight logic matches yesterday's window -> open!
      final at0559 = DateTime(2026, 9, 20, 5, 59);
      final statusDefaultDate = nightShift22.getWindowStatus(at0559);
      expect(statusDefaultDate, ShiftWindowStatus.open);

      // At 06:01 (after yesterday's shift ended):
      // Falls outside yesterday's window, evaluates against today's window (opens at 21:00) -> upcoming!
      final at0601 = DateTime(2026, 9, 20, 6, 1);
      final statusAfterEnd = nightShift22.getWindowStatus(at0601);
      expect(statusAfterEnd, ShiftWindowStatus.upcoming);
    });
  });

  group('Requirement 1 (cont): AttendanceNotifier Check-in Boundary Enforcement', () {
    late FakeAttendanceRepository repo;
    late FakeLocationService locationService;
    late ProviderContainer container;

    const testUser = UserAccount(
      username: 'challenger_staff',
      displayName: 'Adversarial Staff',
      role: 'staff',
      storeId: 'store_001',
    );

    const morningShift = Shift(
      id: 'shift_morning',
      name: 'Ca Sáng',
      startTime: '08:00',
      endTime: '12:00',
      gracePeriodMinutes: 15,
      type: 'morning',
      standardWorkHours: 4.0,
    );

    setUp(() {
      repo = FakeAttendanceRepository();
      locationService = FakeLocationService();
      container = ProviderContainer(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(repo),
          locationServiceProvider.overrideWithValue(locationService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('At startTime - 60 min (07:00:00) exactly: checkIn SUCCEEDS', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      final exactOpenTime = DateTime(2026, 9, 19, 7, 0, 0);
      final success = await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        checkInTimestamp: exactOpenTime,
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      expect(state.errorMessage, isNull);
      expect(state.todayAttendance, isNotNull);
    });

    test('At startTime - 61 min (06:59:00): checkIn FAILS with exact upcoming Vietnamese message', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      final tooEarlyTime = DateTime(2026, 9, 19, 6, 59, 0);
      final success = await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        checkInTimestamp: tooEarlyTime,
      );

      expect(success, isFalse);
      final state = container.read(attendanceNotifierProvider);
      expect(
        state.errorMessage,
        'Ca Ca Sáng chưa mở chấm công. Cổng chấm công mở lúc 07:00 (trước giờ bắt đầu 60 phút).',
      );
      expect(state.todayAttendance, isNull);
    });

    test('At exact endTime (12:00:00): checkIn SUCCEEDS (not closed yet)', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      final exactEndTime = DateTime(2026, 9, 19, 12, 0, 0);
      final success = await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        checkInTimestamp: exactEndTime,
      );

      expect(success, isTrue);
      final state = container.read(attendanceNotifierProvider);
      expect(state.errorMessage, isNull);
      expect(state.todayAttendance, isNotNull);
    });

    test('At 1 second after endTime (12:00:01): checkIn FAILS with exact closed Vietnamese message', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      final oneSecAfter = DateTime(2026, 9, 19, 12, 0, 1);
      final success = await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        checkInTimestamp: oneSecAfter,
      );

      expect(success, isFalse);
      final state = container.read(attendanceNotifierProvider);
      expect(
        state.errorMessage,
        'Ca Ca Sáng đã kết thúc lúc 12:00. Bạn không thể chấm công vào ca đã qua. Vui lòng chọn ca kế tiếp.',
      );
      expect(state.todayAttendance, isNull);
    });

    test('In afternoon (14:00:00): checkIn into Ca Sáng FAILS and prevents DB record creation', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_001',
        userId: testUser.username,
        initialShift: morningShift,
      );

      final afternoonTime = DateTime(2026, 9, 19, 14, 0, 0);
      final success = await notifier.checkIn(
        user: testUser,
        storeId: 'store_001',
        checkInTimestamp: afternoonTime,
      );

      expect(success, isFalse);
      final state = container.read(attendanceNotifierProvider);
      expect(
        state.errorMessage,
        'Ca Ca Sáng đã kết thúc lúc 12:00. Bạn không thể chấm công vào ca đã qua. Vui lòng chọn ca kế tiếp.',
      );
      expect(repo.attendances, isEmpty);
    });
  });

  group('Requirement 2: Stress Testing StoreGpsConfigNotifier Dispose Safety', () {
    late SlowControllableAttendanceRepository repo;
    late FakeLocationService locationService;

    const sampleConfig = StoreGpsConfig(
      storeId: 'store_stress_1',
      latitude: 10.035,
      longitude: 105.788,
      allowedRadiusMeters: 100.0,
      storeName: 'Test Branch',
    );

    setUp(() {
      repo = SlowControllableAttendanceRepository();
      locationService = FakeLocationService();
    });

    test('Dispose while loadConfig is waiting on slow repository (success response) -> 0 StateError', () async {
      final completer = Completer<StoreGpsConfig?>();
      repo.getGpsCompleter = completer;

      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_stress_1',
      );

      expect(notifier.mounted, isTrue);
      expect(notifier.state.isLoading, isTrue);

      // Dispose while request is waiting on slow network
      notifier.dispose();
      expect(notifier.mounted, isFalse);

      // Now slow network completes
      completer.complete(sampleConfig);

      // Allow event loop to process
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Verify no StateError thrown and notifier remains unmounted
      expect(notifier.mounted, isFalse);
    });

    test('Dispose while loadConfig is waiting on slow repository (error response) -> 0 StateError', () async {
      final completer = Completer<StoreGpsConfig?>();
      repo.getGpsCompleter = completer;

      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_stress_1',
      );

      expect(notifier.mounted, isTrue);

      // Dispose while waiting
      notifier.dispose();
      expect(notifier.mounted, isFalse);

      // Slow network throws error
      completer.completeError(TimeoutException('Slow network timeout'));

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.mounted, isFalse);
    });

    test('Dispose while saveConfig is waiting on slow repository (success response) -> 0 StateError, returns false', () async {
      final saveCompleter = Completer<void>();
      repo.saveGpsCompleter = saveCompleter;

      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_stress_1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Start saving
      final saveFuture = notifier.saveConfig(sampleConfig);
      expect(notifier.state.isSaving, isTrue);

      // Dispose while save is waiting on slow network
      notifier.dispose();
      expect(notifier.mounted, isFalse);

      // Complete slow network save
      saveCompleter.complete();
      final result = await saveFuture;

      expect(result, isFalse);
      expect(notifier.mounted, isFalse);
    });

    test('Dispose while saveConfig is waiting on slow repository (error response) -> 0 StateError, returns false', () async {
      final saveCompleter = Completer<void>();
      repo.saveGpsCompleter = saveCompleter;

      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_stress_1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Start saving
      final saveFuture = notifier.saveConfig(sampleConfig);

      // Dispose while waiting
      notifier.dispose();
      expect(notifier.mounted, isFalse);

      // Complete with error
      saveCompleter.completeError(Exception('Network disconnected'));
      final result = await saveFuture;

      expect(result, isFalse);
      expect(notifier.mounted, isFalse);
    });

    test('Rapid consecutive unmounts and remounts under Riverpod container lifecycle', () async {
      for (var i = 0; i < 20; i++) {
        final loadCompleter = Completer<StoreGpsConfig?>();
        final saveCompleter = Completer<void>();
        repo.getGpsCompleter = loadCompleter;
        repo.saveGpsCompleter = saveCompleter;

        final container = ProviderContainer(
          overrides: [
            attendanceRepositoryProvider.overrideWithValue(repo),
            locationServiceProvider.overrideWithValue(locationService),
            currentStoreIdProvider.overrideWithValue('store_$i'),
            authProvider.overrideWith((ref) => _TestAuthNotifier(null)),
          ],
        );

        final sub = container.listen(storeGpsConfigNotifierProvider, (_, __) {});
        final notifier = container.read(storeGpsConfigNotifierProvider.notifier);

        final saveFuture = notifier.saveConfig(sampleConfig);

        // Immediate unmount while both load and save are in-flight
        sub.close();
        container.dispose();

        // Complete both async operations after dispose
        loadCompleter.complete(sampleConfig);
        saveCompleter.complete();

        final saveResult = await saveFuture;
        expect(saveResult, isFalse);
        expect(notifier.mounted, isFalse);
      }
    });
  });
}
