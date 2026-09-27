import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_notifier.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/attendance/widgets/shift_selector_card.dart';

import '../application/attendance/fake_attendance_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const morningShift = Shift(
    id: 'shift_morning',
    name: 'Ca Sáng',
    startTime: '08:00',
    endTime: '12:00',
    gracePeriodMinutes: 15,
    type: 'morning',
    standardWorkHours: 4.0,
  );

  const overnightShift22to06 = Shift(
    id: 'shift_overnight_22_06',
    name: 'Ca Đêm 22-06',
    startTime: '22:00',
    endTime: '06:00',
    gracePeriodMinutes: 15,
    type: 'night',
    standardWorkHours: 8.0,
  );

  const overnightShift20to04 = Shift(
    id: 'shift_overnight_20_04',
    name: 'Ca Đêm 20-04',
    startTime: '20:00',
    endTime: '04:00',
    gracePeriodMinutes: 15,
    type: 'night',
    standardWorkHours: 8.0,
  );

  const overnightShift2330to0730 = Shift(
    id: 'shift_overnight_2330_0730',
    name: 'Ca Đêm 23:30-07:30',
    startTime: '23:30',
    endTime: '07:30',
    gracePeriodMinutes: 15,
    type: 'night',
    standardWorkHours: 8.0,
  );

  const testUser = UserAccount(
    username: 'challenger_staff_01',
    displayName: 'Empirical Challenger Staff',
    role: 'staff',
    storeId: 'store_m2_it2',
  );

  group('VERIFICATION 1: Cross-midnight shift window at 01:00 AM on overnight shift without passing date', () {
    test('Overnight shift (22:00 - 06:00) evaluated at 01:00 AM without passing date MUST be OPEN', () {
      final at0100 = DateTime(2026, 9, 20, 1, 0, 0);

      // Call without passing date argument (defaults to DateTime(checkTime.year, checkTime.month, checkTime.day))
      final status = overnightShift22to06.getWindowStatus(at0100);
      expect(status, ShiftWindowStatus.open);
      expect(overnightShift22to06.isCheckInWindowOpen(at0100), isTrue);
    });

    test('Overnight shift (20:00 - 04:00) evaluated at 01:00 AM without passing date MUST be OPEN', () {
      final at0100 = DateTime(2026, 9, 20, 1, 0, 0);
      final status = overnightShift20to04.getWindowStatus(at0100);
      expect(status, ShiftWindowStatus.open);
      expect(overnightShift20to04.isCheckInWindowOpen(at0100), isTrue);
    });

    test('Overnight shift (23:30 - 07:30) evaluated at 01:00 AM without passing date MUST be OPEN', () {
      final at0100 = DateTime(2026, 9, 20, 1, 0, 0);
      final status = overnightShift2330to0730.getWindowStatus(at0100);
      expect(status, ShiftWindowStatus.open);
      expect(overnightShift2330to0730.isCheckInWindowOpen(at0100), isTrue);
    });

    test('Overnight shift (22:00 - 06:00) boundary check: 05:59:59 AM (OPEN) vs 06:00:00 AM (OPEN) vs 06:00:01 AM (UPCOMING) without passing date', () {
      final at055959 = DateTime(2026, 9, 20, 5, 59, 59);
      expect(overnightShift22to06.getWindowStatus(at055959), ShiftWindowStatus.open);

      final at060000 = DateTime(2026, 9, 20, 6, 0, 0);
      expect(overnightShift22to06.getWindowStatus(at060000), ShiftWindowStatus.open);

      final at060001 = DateTime(2026, 9, 20, 6, 0, 1);
      expect(overnightShift22to06.getWindowStatus(at060001), ShiftWindowStatus.upcoming);
    });

    test('Shift.findBestShiftForTime at 01:00 AM automatically picks open overnight shift', () {
      final at0100 = DateTime(2026, 9, 20, 1, 0, 0);
      final shifts = [morningShift, overnightShift22to06];

      final bestShift = Shift.findBestShiftForTime(shifts, at0100);
      expect(bestShift, isNotNull);
      expect(bestShift!.id, 'shift_overnight_22_06');
    });

    test('AttendanceNotifier checkIn at 01:00 AM for overnight shift without passing date SUCCEEDS', () async {
      final repo = FakeAttendanceRepository();
      final locationService = FakeLocationService();
      final container = ProviderContainer(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(repo),
          locationServiceProvider.overrideWithValue(locationService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_m2_it2',
        userId: testUser.username,
        initialShift: overnightShift22to06,
      );

      final at0100 = DateTime(2026, 9, 20, 1, 0, 0);
      final result = await notifier.checkIn(
        user: testUser,
        storeId: 'store_m2_it2',
        checkInTimestamp: at0100,
      );

      expect(result, isTrue);
      final state = container.read(attendanceNotifierProvider);
      expect(state.errorMessage, isNull);
      expect(state.todayAttendance, isNotNull);
      expect(state.todayAttendance!.shiftId, 'shift_overnight_22_06');
      expect(state.todayAttendance!.checkInTime, at0100);
      expect(repo.attendances.length, 1);
    });
  });

  group('VERIFICATION 2: Upcoming shift check-in attempt (05:00 AM for 08:00 AM Ca Sáng) is unconditionally BLOCKED', () {
    late FakeAttendanceRepository repo;
    late FakeLocationService locationService;
    late ProviderContainer container;

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

    test('Check-in attempt at 05:00 AM for 08:00 AM shift MUST return false and block record creation', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_m2_it2',
        userId: testUser.username,
        initialShift: morningShift,
      );

      final at0500 = DateTime(2026, 9, 20, 5, 0, 0);
      final result = await notifier.checkIn(
        user: testUser,
        storeId: 'store_m2_it2',
        checkInTimestamp: at0500,
      );

      expect(result, isFalse, reason: 'Check-in must be unconditionally blocked 3 hours before start');
      final state = container.read(attendanceNotifierProvider);
      expect(
        state.errorMessage,
        'Ca Ca Sáng chưa mở chấm công. Cổng chấm công mở lúc 07:00 (trước giờ bắt đầu 60 phút).',
      );
      expect(state.todayAttendance, isNull);
      expect(repo.attendances, isEmpty, reason: 'No DB record should be written when check-in is blocked');
    });

    test('Check-in attempts across early hours (00:00, 02:00, 05:00, 06:00, 06:59:59) are ALL blocked with exact error message', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);

      final timestamps = [
        DateTime(2026, 9, 20, 0, 0, 0),
        DateTime(2026, 9, 20, 2, 30, 0),
        DateTime(2026, 9, 20, 5, 0, 0),
        DateTime(2026, 9, 20, 6, 0, 0),
        DateTime(2026, 9, 20, 6, 30, 0),
        DateTime(2026, 9, 20, 6, 59, 0),
        DateTime(2026, 9, 20, 6, 59, 59),
      ];

      for (final ts in timestamps) {
        await notifier.init(
          storeId: 'store_m2_it2',
          userId: testUser.username,
          initialShift: morningShift,
        );

        final result = await notifier.checkIn(
          user: testUser,
          storeId: 'store_m2_it2',
          checkInTimestamp: ts,
        );

        expect(
          result,
          isFalse,
          reason: 'Check-in at $ts must be rejected because window opens at 07:00',
        );

        final state = container.read(attendanceNotifierProvider);
        expect(
          state.errorMessage,
          'Ca Ca Sáng chưa mở chấm công. Cổng chấm công mở lúc 07:00 (trước giờ bắt đầu 60 phút).',
        );
        expect(state.todayAttendance, isNull);
        expect(repo.attendances, isEmpty);
      }
    });

    test('Historical / extreme timestamp (>60 min early) CANNOT bypass window validation (No bypass exists)', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_m2_it2',
        userId: testUser.username,
        initialShift: morningShift,
      );

      // Even a timestamp 12 hours or days earlier must be rejected as upcoming for that base date
      final extremePastTimestamp = DateTime(2026, 9, 20, 1, 0, 0);
      final result = await notifier.checkIn(
        user: testUser,
        storeId: 'store_m2_it2',
        checkInTimestamp: extremePastTimestamp,
      );

      expect(result, isFalse);
      final state = container.read(attendanceNotifierProvider);
      expect(
        state.errorMessage,
        'Ca Ca Sáng chưa mở chấm công. Cổng chấm công mở lúc 07:00 (trước giờ bắt đầu 60 phút).',
      );
      expect(repo.attendances, isEmpty);
    });
  });

  group('VERIFICATION 3: Closed shift check-in attempt (at 12:00:01 PM or 13:00 PM for Ca Sáng) is unconditionally BLOCKED', () {
    late FakeAttendanceRepository repo;
    late FakeLocationService locationService;
    late ProviderContainer container;

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

    test('Check-in attempt at 12:00:01 PM for Ca Sáng MUST be BLOCKED with exact error message', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_m2_it2',
        userId: testUser.username,
        initialShift: morningShift,
      );

      final at120001 = DateTime(2026, 9, 20, 12, 0, 1);
      final result = await notifier.checkIn(
        user: testUser,
        storeId: 'store_m2_it2',
        checkInTimestamp: at120001,
      );

      expect(result, isFalse);
      final state = container.read(attendanceNotifierProvider);
      expect(
        state.errorMessage,
        'Ca Ca Sáng đã kết thúc lúc 12:00. Bạn không thể chấm công vào ca đã qua. Vui lòng chọn ca kế tiếp.',
      );
      expect(state.todayAttendance, isNull);
      expect(repo.attendances, isEmpty);
    });

    test('Check-in attempt at 13:00:00 PM for Ca Sáng MUST be BLOCKED with exact error message', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);
      await notifier.init(
        storeId: 'store_m2_it2',
        userId: testUser.username,
        initialShift: morningShift,
      );

      final at1300 = DateTime(2026, 9, 20, 13, 0, 0);
      final result = await notifier.checkIn(
        user: testUser,
        storeId: 'store_m2_it2',
        checkInTimestamp: at1300,
      );

      expect(result, isFalse);
      final state = container.read(attendanceNotifierProvider);
      expect(
        state.errorMessage,
        'Ca Ca Sáng đã kết thúc lúc 12:00. Bạn không thể chấm công vào ca đã qua. Vui lòng chọn ca kế tiếp.',
      );
      expect(state.todayAttendance, isNull);
      expect(repo.attendances, isEmpty);
    });

    test('Check-in attempts in late afternoon and evening (14:00, 17:00, 23:59) are ALL blocked with exact error message', () async {
      final notifier = container.read(attendanceNotifierProvider.notifier);

      final timestamps = [
        DateTime(2026, 9, 20, 14, 0, 0),
        DateTime(2026, 9, 20, 17, 30, 0),
        DateTime(2026, 9, 20, 23, 59, 59),
      ];

      for (final ts in timestamps) {
        await notifier.init(
          storeId: 'store_m2_it2',
          userId: testUser.username,
          initialShift: morningShift,
        );

        final result = await notifier.checkIn(
          user: testUser,
          storeId: 'store_m2_it2',
          checkInTimestamp: ts,
        );

        expect(result, isFalse);
        final state = container.read(attendanceNotifierProvider);
        expect(
          state.errorMessage,
          'Ca Ca Sáng đã kết thúc lúc 12:00. Bạn không thể chấm công vào ca đã qua. Vui lòng chọn ca kế tiếp.',
        );
        expect(repo.attendances, isEmpty);
      }
    });
  });

  group('VERIFICATION 4: ShiftSelectorCard Tag Rendering for Time Windows', () {
    testWidgets('At 01:00 AM, overnight shift renders [Đang mở ca] and morning shift renders [Chưa mở (07:00)]', (tester) async {
      final at0100 = DateTime(2026, 9, 20, 1, 0, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftSelectorCard(
              shifts: const [morningShift, overnightShift22to06],
              selectedShift: overnightShift22to06,
              currentTime: at0100,
              onShiftSelected: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Đang mở ca'), findsOneWidget);
      expect(find.text('Chưa mở - Mở lúc 07:00'), findsOneWidget);
      expect(find.text('Ca Đêm 22-06'), findsOneWidget);
      expect(find.text('Ca Sáng'), findsOneWidget);
    });

    testWidgets('At 13:00 PM, morning shift renders [Đã kết thúc]', (tester) async {
      final at1300 = DateTime(2026, 9, 20, 13, 0, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftSelectorCard(
              shifts: const [morningShift],
              selectedShift: morningShift,
              currentTime: at1300,
              onShiftSelected: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Đã kết thúc'), findsOneWidget);
    });
  });
}
