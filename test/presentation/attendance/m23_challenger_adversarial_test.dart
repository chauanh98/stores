import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_notifier.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/application/attendance/store_gps_config_notifier.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/attendance/store_gps_config.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/attendance/pages/attendance_check_in_page.dart';
import 'package:stores/presentation/attendance/widgets/shift_selector_card.dart';

import '../../application/attendance/fake_attendance_repository.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

void main() {
  group('CHALLENGER 2: Milestone M2 - Shift Time-Window Validation & UI Adversarial Suite', () {
    const morningShift = Shift(
      id: 'shift_morning',
      name: 'Ca Sáng',
      startTime: '08:00',
      endTime: '12:00',
      type: 'morning',
      standardWorkHours: 4.0,
      gracePeriodMinutes: 15,
    );

    const afternoonShift = Shift(
      id: 'shift_afternoon',
      name: 'Ca Chiều',
      startTime: '13:00',
      endTime: '17:30',
      type: 'afternoon',
      standardWorkHours: 4.5,
      gracePeriodMinutes: 15,
    );

    const eveningShift = Shift(
      id: 'shift_evening',
      name: 'Ca Tối',
      startTime: '18:00',
      endTime: '22:00',
      type: 'evening',
      standardWorkHours: 4.0,
      gracePeriodMinutes: 15,
    );

    const flexibleShift = Shift(
      id: 'shift_flexible',
      name: 'Ca Linh hoạt',
      startTime: '08:00',
      endTime: '22:00',
      type: 'flexible',
      standardWorkHours: 8.0,
      gracePeriodMinutes: 60,
    );

    test('Empirical: Shift.findBestShiftForTime at 12:00:00 selects Ca Chiều over Ca Sáng and flexible shift', () {
      final shifts = [morningShift, afternoonShift, eveningShift, flexibleShift];
      final at1200 = DateTime(2026, 9, 19, 12, 0, 0);

      final selected = Shift.findBestShiftForTime(shifts, at1200);

      expect(selected, isNotNull);
      expect(selected!.id, 'shift_afternoon');
      expect(selected.name, 'Ca Chiều');
    });

    test('Empirical: Shift.findBestShiftForTime at 12:00:01 and 12:30:00 selects Ca Chiều', () {
      final shifts = [morningShift, afternoonShift, eveningShift, flexibleShift];

      final at120001 = DateTime(2026, 9, 19, 12, 0, 1);
      final selected01 = Shift.findBestShiftForTime(shifts, at120001);
      expect(selected01!.id, 'shift_afternoon');

      final at1230 = DateTime(2026, 9, 19, 12, 30, 0);
      final selected30 = Shift.findBestShiftForTime(shifts, at1230);
      expect(selected30!.id, 'shift_afternoon');
    });

    test('Empirical: Shift.findBestShiftForTime at 11:59:59 selects Ca Sáng (Ca Chiều window not open yet)', () {
      final shifts = [morningShift, afternoonShift, eveningShift, flexibleShift];
      final at1159 = DateTime(2026, 9, 19, 11, 59, 59);

      final selected = Shift.findBestShiftForTime(shifts, at1159);
      expect(selected!.id, 'shift_morning');
    });

    testWidgets('Empirical: ShiftSelectorCard renders [Đã kết thúc] badge and 0.6 opacity for ended shift at 12:01', (tester) async {
      final evalTime = DateTime(2026, 9, 19, 12, 1);
      Shift? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftSelectorCard(
              shifts: const [morningShift, afternoonShift, eveningShift],
              selectedShift: afternoonShift,
              currentTime: evalTime,
              onShiftSelected: (s) => selected = s,
            ),
          ),
        ),
      );

      // Verify badges
      expect(find.text('Đã kết thúc'), findsOneWidget); // Morning shift
      expect(find.text('Đang mở ca'), findsOneWidget); // Afternoon shift
      expect(find.text('Chưa mở - Mở lúc 17:00'), findsOneWidget); // Evening shift

      // Verify Opacity values
      final opacities = tester
          .widgetList<Opacity>(find.descendant(
            of: find.byType(ShiftSelectorCard),
            matching: find.byType(Opacity),
          ))
          .toList();

      expect(opacities.length, 3);
      expect(opacities[0].opacity, 0.6); // Ca Sáng (closed) -> dimmed at 0.6
      expect(opacities[1].opacity, 1.0); // Ca Chiều (open) -> full 1.0 opacity
      expect(opacities[2].opacity, 0.6); // Ca Tối (upcoming) -> dimmed at 0.6

      // Verify tapping ended shift still fires selection callback (allows user to select and test check-in blocking)
      await tester.tap(find.text('Ca Sáng'));
      expect(selected?.id, 'shift_morning');
    });

    testWidgets('Empirical: AttendanceCheckInPage auto-selects open shift over ended shift upon opening', (tester) async {
      final fakeRepo = FakeAttendanceRepository();
      final fakeLocation = FakeLocationService();

      final now = DateTime.now();
      // Construct shifts relative to DateTime.now() so that:
      // Shift 1 ended 10 minutes ago (simulating ended Ca Sáng)
      final pastStart = now.subtract(const Duration(hours: 4));
      final pastEnd = now.subtract(const Duration(minutes: 10));
      final endedShift = Shift(
        id: 'shift_sim_ended',
        name: 'Ca Sáng Kết Thúc',
        startTime: '${pastStart.hour.toString().padLeft(2, '0')}:${pastStart.minute.toString().padLeft(2, '0')}',
        endTime: '${pastEnd.hour.toString().padLeft(2, '0')}:${pastEnd.minute.toString().padLeft(2, '0')}',
        type: 'morning',
      );

      // Shift 2 is currently open (simulating open Ca Chiều, started or starting soon)
      final openStart = now.add(const Duration(minutes: 30)); // window opened 30m ago (now - 30m)
      final openEnd = now.add(const Duration(hours: 4));
      final openShift = Shift(
        id: 'shift_sim_open',
        name: 'Ca Chiều Đang Mở',
        startTime: '${openStart.hour.toString().padLeft(2, '0')}:${openStart.minute.toString().padLeft(2, '0')}',
        endTime: '${openEnd.hour.toString().padLeft(2, '0')}:${openEnd.minute.toString().padLeft(2, '0')}',
        type: 'afternoon',
      );

      fakeRepo.shifts = [endedShift, openShift];

      const testStaff = UserAccount(
        username: 'staff_challenger',
        displayName: 'Trần Thị Thử Thách',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testStaff)),
            attendanceRepositoryProvider.overrideWithValue(fakeRepo),
            locationServiceProvider.overrideWithValue(fakeLocation),
            currentStoreIdProvider.overrideWithValue('store_001'),
            currentStoreNameProvider.overrideWith((ref) => Future.value('Chi nhánh Đông Thắng')),
            shiftRepositoryProvider.overrideWithValue(fakeRepo),
            shiftListNotifierProvider.overrideWith((ref) =>
                ShiftListNotifier(fakeRepo)..state = ShiftListState(shifts: [endedShift, openShift])),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: AttendanceCheckInPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify that ShiftSelectorCard auto-selected the open shift ('Ca Chiều Đang Mở')
      // and NOT the ended shift ('Ca Sáng Kết Thúc')
      final openShiftRadio = find.descendant(
        of: find.widgetWithText(Container, 'Ca Chiều Đang Mở'),
        matching: find.byIcon(Icons.radio_button_checked),
      );
      expect(openShiftRadio, findsOneWidget);

      final endedShiftRadio = find.descendant(
        of: find.widgetWithText(Container, 'Ca Sáng Kết Thúc'),
        matching: find.byIcon(Icons.radio_button_off),
      );
      expect(endedShiftRadio, findsOneWidget);

      // Verify badges
      expect(find.text('Đã kết thúc'), findsOneWidget);
      expect(find.text('Đang mở ca'), findsOneWidget);
    });

    testWidgets('Empirical: Tapping ended shift and tapping check-in is BLOCKED, shows error banner, and writes NO DB record', (tester) async {
      final fakeRepo = FakeAttendanceRepository();
      final fakeLocation = FakeLocationService();

      final now = DateTime.now();
      final pastStart = now.subtract(const Duration(hours: 4));
      final pastEnd = now.subtract(const Duration(minutes: 5));
      final pastEndStr = '${pastEnd.hour.toString().padLeft(2, '0')}:${pastEnd.minute.toString().padLeft(2, '0')}';
      final pastStartStr = '${pastStart.hour.toString().padLeft(2, '0')}:${pastStart.minute.toString().padLeft(2, '0')}';

      final endedShift = Shift(
        id: 'shift_adversarial_ended',
        name: 'Ca Sáng Thử Nghiệm',
        startTime: pastStartStr,
        endTime: pastEndStr,
        type: 'morning',
      );

      fakeRepo.shifts = [endedShift];

      const testStaff = UserAccount(
        username: 'staff_challenger',
        displayName: 'Trần Thị Thử Thách',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testStaff)),
            attendanceRepositoryProvider.overrideWithValue(fakeRepo),
            locationServiceProvider.overrideWithValue(fakeLocation),
            currentStoreIdProvider.overrideWithValue('store_001'),
            currentStoreNameProvider.overrideWith((ref) => Future.value('Chi nhánh Đông Thắng')),
            shiftRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: AttendanceCheckInPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on ended shift to select it
      await tester.tap(find.text('Ca Sáng Thử Nghiệm'));
      await tester.pumpAndSettle();

      // Tap Check-in
      final checkInBtn = find.text('CHẤM CÔNG VÀO');
      await tester.ensureVisible(checkInBtn);
      await tester.tap(checkInBtn);
      await tester.pumpAndSettle();

      // 1. Verify exact error message in UI
      final expectedError =
          'Ca Ca Sáng Thử Nghiệm đã kết thúc lúc $pastEndStr. Bạn không thể chấm công vào ca đã qua. Vui lòng chọn ca kế tiếp.';
      expect(find.text(expectedError), findsOneWidget);

      // 2. Verify check-in button did NOT transition to CHẤM CÔNG RA
      expect(find.text('CHẤM CÔNG VÀO'), findsOneWidget);
      expect(find.text('CHẤM CÔNG RA'), findsNothing);

      // 3. Verify DATABASE RECORD IS NOT CREATED
      expect(fakeRepo.attendances, isEmpty);
    });

    testWidgets('Empirical: Tapping upcoming shift (>60m early) and tapping check-in is BLOCKED and writes NO DB record', (tester) async {
      final fakeRepo = FakeAttendanceRepository();
      final fakeLocation = FakeLocationService();

      final now = DateTime.now();
      // Upcoming shift starting 2 hours from now
      final futureStart = now.add(const Duration(hours: 2));
      final futureEnd = now.add(const Duration(hours: 6));
      final futureStartStr = '${futureStart.hour.toString().padLeft(2, '0')}:${futureStart.minute.toString().padLeft(2, '0')}';
      final futureEndStr = '${futureEnd.hour.toString().padLeft(2, '0')}:${futureEnd.minute.toString().padLeft(2, '0')}';

      final upcomingShift = Shift(
        id: 'shift_adversarial_upcoming',
        name: 'Ca Chiều Thử Nghiệm',
        startTime: futureStartStr,
        endTime: futureEndStr,
        type: 'afternoon',
      );

      final openGateTime = futureStart.subtract(const Duration(minutes: 60));
      final openGateStr = '${openGateTime.hour.toString().padLeft(2, '0')}:${openGateTime.minute.toString().padLeft(2, '0')}';

      fakeRepo.shifts = [upcomingShift];

      const testStaff = UserAccount(
        username: 'staff_challenger',
        displayName: 'Trần Thị Thử Thách',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testStaff)),
            attendanceRepositoryProvider.overrideWithValue(fakeRepo),
            locationServiceProvider.overrideWithValue(fakeLocation),
            currentStoreIdProvider.overrideWithValue('store_001'),
            currentStoreNameProvider.overrideWith((ref) => Future.value('Chi nhánh Đông Thắng')),
            shiftRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: AttendanceCheckInPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on upcoming shift to select it
      await tester.tap(find.text('Ca Chiều Thử Nghiệm'));
      await tester.pumpAndSettle();

      // Tap Check-in
      final checkInBtn = find.text('CHẤM CÔNG VÀO');
      await tester.ensureVisible(checkInBtn);
      await tester.tap(checkInBtn);
      await tester.pumpAndSettle();

      // 1. Verify error message
      final expectedError =
          'Ca Ca Chiều Thử Nghiệm chưa mở chấm công. Cổng chấm công mở lúc $openGateStr (trước giờ bắt đầu 60 phút).';
      expect(find.text(expectedError), findsOneWidget);

      // 2. Verify check-in button did NOT transition
      expect(find.text('CHẤM CÔNG VÀO'), findsOneWidget);
      expect(find.text('CHẤM CÔNG RA'), findsNothing);

      // 3. Verify DATABASE RECORD IS NOT CREATED
      expect(fakeRepo.attendances, isEmpty);
    });

    testWidgets('VULNERABILITY PROOF: AttendanceCheckInPage fails to select best store shift when repository shifts arrive asynchronously', (tester) async {
      final fakeRepo = FakeAttendanceRepository();
      final fakeLocation = FakeLocationService();

      // Store only has 2 custom shifts:
      const customShiftA = Shift(
        id: 'custom_shift_a',
        name: 'Ca Chi Nhánh A',
        startTime: '06:00',
        endTime: '11:00',
        type: 'morning',
      );
      const customShiftB = Shift(
        id: 'custom_shift_b',
        name: 'Ca Chi Nhánh B',
        startTime: '11:00',
        endTime: '16:00',
        type: 'afternoon',
      );
      fakeRepo.shifts = [customShiftA, customShiftB];

      const testStaff = UserAccount(
        username: 'staff_challenger',
        displayName: 'Trần Thị Thử Thách',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(testStaff)),
            attendanceRepositoryProvider.overrideWithValue(fakeRepo),
            locationServiceProvider.overrideWithValue(fakeLocation),
            currentStoreIdProvider.overrideWithValue('store_001'),
            currentStoreNameProvider.overrideWith((ref) => Future.value('Chi nhánh Đông Thắng')),
            shiftRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            home: Consumer(
              builder: (context, ref, child) {
                capturedRef = ref;
                return const AttendanceCheckInPage();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final selectedShift = capturedRef.read(attendanceNotifierProvider).selectedShift;
      final storeShifts = capturedRef.read(shiftListNotifierProvider).shifts;

      // Notice: storeShifts has customShiftA and customShiftB
      expect(storeShifts.map((s) => s.id), containsAll(['custom_shift_a', 'custom_shift_b']));

      // DEFECT: selectedShift was pre-selected from Shift.defaultShifts() during _initAttendance,
      // and ref.listen skipped re-selection because selectedShift != null!
      // Therefore selectedShift is an orphan shift NOT found in the store's configured shifts list:
      final isOrphanShift = !storeShifts.any((s) => s.id == selectedShift?.id);
      expect(
        isOrphanShift,
        isTrue,
        reason: 'CRITICAL DEFECT: selectedShift ($selectedShift) is not present in the store shifts list ($storeShifts)!',
      );
    });
  });

  group('CHALLENGER 2: Milestone M3 - StoreGpsConfigNotifier Dispose Safety Stress Suite', () {
    late FakeLocationService fakeLocation;

    setUp(() {
      fakeLocation = FakeLocationService();
    });

    test('Empirical: Rapid mount-unmount stress loop with in-flight asynchronous operations causes zero crash', () async {
      for (int i = 0; i < 20; i++) {
        final completer = Completer<StoreGpsConfig?>();
        final customRepo = _ControllableRepo(completer);

        final notifier = StoreGpsConfigNotifier(
          customRepo,
          fakeLocation,
          initialStoreId: 'store_stress_$i',
        );

        expect(notifier.mounted, isTrue);

        // Immediately unmount before async I/O returns
        notifier.dispose();
        expect(notifier.mounted, isFalse);

        // Complete the future post-dispose
        if (i % 2 == 0) {
          completer.complete(const StoreGpsConfig(
            storeId: 'store_stress',
            latitude: 10.1,
            longitude: 105.1,
          ));
        } else {
          completer.completeError(TimeoutException('Async connection aborted'));
        }

        await Future<void>.delayed(const Duration(milliseconds: 5));
        // Verify notifier remains safely disposed without uncaught StateError
        expect(notifier.mounted, isFalse);
      }
    });

    test('Empirical: Concurrent saveConfig and loadConfig followed by disposal before completion', () async {
      final saveCompleter = Completer<void>();
      final customRepo = _ControllableSaveRepo(saveCompleter);

      final notifier = StoreGpsConfigNotifier(
        customRepo,
        fakeLocation,
        initialStoreId: 'store_001',
      );

      // Trigger saveConfig
      final saveFuture = notifier.saveConfig(const StoreGpsConfig(
        storeId: 'store_001',
        latitude: 10.5,
        longitude: 105.5,
      ));

      // Dispose while save is in-flight
      notifier.dispose();
      expect(notifier.mounted, isFalse);

      // Complete save with error
      saveCompleter.completeError(Exception('Firebase network error post-dispose'));

      final result = await saveFuture;
      // Should return false and not crash
      expect(result, isFalse);
      expect(notifier.mounted, isFalse);
    });
  });
}

class _ControllableRepo extends FakeAttendanceRepository {
  final Completer<StoreGpsConfig?> completer;
  _ControllableRepo(this.completer);

  @override
  Future<StoreGpsConfig?> getStoreGpsConfig(String storeId) => completer.future;
}

class _ControllableSaveRepo extends FakeAttendanceRepository {
  final Completer<void> completer;
  _ControllableSaveRepo(this.completer);

  @override
  Future<void> saveStoreGpsConfig(StoreGpsConfig config) => completer.future;
}
