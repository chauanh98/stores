import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/attendance/pages/live_attendance_dashboard_page.dart';

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
  group('LiveAttendanceDashboardPage Widget Tests', () {
    late FakeAttendanceRepository fakeRepo;

    const supervisorUser = UserAccount(
      username: 'supervisor_1',
      displayName: 'Giám sát viên ĐT',
      role: 'supervisor',
      storeId: 'store_001',
    );

    final today = DateTime.now();

    setUp(() {
      fakeRepo = FakeAttendanceRepository();

      // Seed 2 records
      fakeRepo.attendances.add(
        AttendanceRecord(
          id: 'att_01',
          userId: 'staff_1',
          userName: 'Nhân viên 1',
          storeId: 'store_001',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: today,
          checkInTime: DateTime(today.year, today.month, today.day, 8, 5),
          checkInGpsLat: 10.035,
          checkInGpsLng: 105.788,
          isGpsValid: true,
          status: AttendanceStatus.onTime,
        ),
      );

      fakeRepo.attendances.add(
        AttendanceRecord(
          id: 'att_02',
          userId: 'staff_2',
          userName: 'Nhân viên 2',
          storeId: 'store_001',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: today,
          checkInTime: DateTime(today.year, today.month, today.day, 8, 35),
          checkOutTime: DateTime(today.year, today.month, today.day, 12, 0),
          checkInGpsLat: 10.035,
          checkInGpsLng: 105.788,
          isGpsValid: true,
          status: AttendanceStatus.late,
          lateMinutes: 35,
          totalWorkHours: 3.42,
        ),
      );
    });

    Widget createWidgetUnderTest() {
      return ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
          attendanceRepositoryProvider.overrideWithValue(fakeRepo),
          currentStoreIdProvider.overrideWithValue('store_001'),
          availableStoresProvider.overrideWith(
            (ref) => Future.value({'store_001': 'Chi nhánh Đông Thắng'}),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: LiveAttendanceDashboardPage(),
        ),
      );
    }

    testWidgets('Renders dashboard with title, live counters, and staff list', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Giám sát chấm công trực tiếp'), findsOneWidget);
      expect(find.text('Đang làm việc'), findsWidgets);
      expect(find.text('Đi muộn hôm nay'), findsWidgets);

      // Staff names
      expect(find.text('Nhân viên 1'), findsOneWidget);
      expect(find.text('Nhân viên 2'), findsOneWidget);

      // Status badges
      expect(find.text('Đang làm việc'), findsWidgets);
      expect(find.text('Muộn 35 phút'), findsOneWidget);
    });

    testWidgets('Filter chips allow filtering by status', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Find "Đang làm (1)" chip and tap it
      final workingChip = find.textContaining('Đang làm');
      expect(workingChip, findsWidgets);

      await tester.tap(workingChip.first);
      await tester.pumpAndSettle();

      // After filtering by "Đang làm", staff_1 is visible, staff_2 is not
      expect(find.text('Nhân viên 1'), findsOneWidget);
      expect(find.text('Nhân viên 2'), findsNothing);
    });

    testWidgets('Small phone viewport (360x640) renders without RenderFlex overflow and wraps ChoiceChips in horizontal SingleChildScrollView', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // No RenderFlex overflow exception
      expect(tester.takeException(), isNull);

      // Clean White AppBar
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.white);
      expect(appBar.foregroundColor, AppColors.textPrimary);

      // SingleChildScrollView with horizontal scroll for filter chips
      final horizontalScrollView = find.byWidgetPredicate(
        (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(horizontalScrollView, findsOneWidget);

      // ChoiceChips styling
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
      expect(chips.length, 4);
      for (final chip in chips) {
        expect(chip.showCheckmark, isFalse);
      }

      final selectedChip = chips.firstWhere((c) => c.selected);
      expect(selectedChip.selectedColor, AppColors.primary);

      final unselectedChip = chips.firstWhere((c) => !c.selected);
      expect(unselectedChip.backgroundColor, Colors.grey.shade100);
    });
  });
}
