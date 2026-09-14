import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/domain/attendance/attendance_adjustment.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/attendance/pages/monthly_timesheet_page.dart';

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
  group('MonthlyTimesheetPage Widget Tests', () {
    late FakeAttendanceRepository fakeRepo;

    const staffUser = UserAccount(
      username: 'staff_1',
      displayName: 'Nguyễn Văn A',
      role: 'nhanvien',
      storeId: 'store_001',
    );

    const supervisorUser = UserAccount(
      username: 'supervisor_1',
      displayName: 'Giám sát viên',
      role: 'supervisor',
      storeId: 'store_001',
    );

    final now = DateTime.now();

    setUp(() {
      fakeRepo = FakeAttendanceRepository();

      // Add 1 record
      fakeRepo.attendances.add(
        AttendanceRecord(
          id: 'att_01',
          userId: 'staff_1',
          userName: 'Nguyễn Văn A',
          storeId: 'store_001',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: now,
          checkInTime: DateTime(now.year, now.month, now.day, 8, 0),
          checkOutTime: DateTime(now.year, now.month, now.day, 12, 0),
          checkInGpsLat: 10.035,
          checkInGpsLng: 105.788,
          isGpsValid: true,
          status: AttendanceStatus.onTime,
          totalWorkHours: 4.0,
        ),
      );

      // Add 1 pending adjustment
      fakeRepo.adjustments.add(
        AttendanceAdjustment(
          id: 'adj_01',
          attendanceId: 'att_01',
          userId: 'staff_1',
          userName: 'Nguyễn Văn A',
          storeId: 'store_001',
          requestedCheckIn: DateTime(now.year, now.month, now.day, 8, 0),
          requestedCheckOut: DateTime(now.year, now.month, now.day, 12, 30),
          reason: 'Bổ sung giờ bàn giao ca',
          status: AdjustmentStatus.pending,
          submittedAt: now,
        ),
      );
    });

    Widget createWidgetUnderTest({
      required UserAccount user,
      bool isPersonalOnly = false,
    }) {
      return ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
          attendanceRepositoryProvider.overrideWithValue(fakeRepo),
          currentStoreIdProvider.overrideWithValue('store_001'),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('vi'),
          home: MonthlyTimesheetPage(isPersonalOnly: isPersonalOnly),
        ),
      );
    }

    testWidgets('Personal mode: Renders personal monthly timesheet with KPI cards', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(user: staffUser, isPersonalOnly: true));
      await tester.pumpAndSettle();

      expect(find.text('Bảng công cá nhân'), findsOneWidget);
      expect(find.text('Tổng giờ làm'), findsOneWidget);
      expect(find.text('Ca hoàn tất'), findsOneWidget);
      expect(find.text('4.0h'), findsWidgets);
      expect(find.text('Ca Sáng (08:00 - 12:00)'), findsOneWidget);
    });

    testWidgets('Supervisor mode: Renders tabs, employee summary, and adjustment approval actions', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(user: supervisorUser, isPersonalOnly: false));
      await tester.pumpAndSettle();

      expect(find.text('Bảng chấm công & Duyệt công'), findsOneWidget);
      expect(find.text('BẢNG CÔNG TỔNG HỢP'), findsOneWidget);
      expect(find.textContaining('DUYỆT ĐIỀU CHỈNH'), findsOneWidget);

      // In summary tab: shows staff item
      expect(find.text('Nguyễn Văn A'), findsOneWidget);
      expect(find.textContaining('4.0 giờ'), findsOneWidget);

      // Switch to adjustment tab
      final adjustmentTab = find.textContaining('DUYỆT ĐIỀU CHỈNH');
      await tester.tap(adjustmentTab);
      await tester.pumpAndSettle();

      // Check pending adjustment item and actions
      expect(find.textContaining('Bổ sung giờ bàn giao ca'), findsOneWidget);
      expect(find.text('Duyệt công'), findsOneWidget);
      expect(find.text('Từ chối'), findsOneWidget);

      // Tap "Duyệt công"
      await tester.tap(find.text('Duyệt công'));
      await tester.pumpAndSettle();

      // Now status is "Đã duyệt"
      expect(find.text('Đã duyệt'), findsOneWidget);
    });

    testWidgets('Staff user accessing default constructor (isPersonalOnly: false) is restricted to personal timesheet only', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(user: staffUser, isPersonalOnly: false));
      await tester.pumpAndSettle();

      // Title MUST be personal
      expect(find.text('Bảng công cá nhân'), findsOneWidget);

      // TabBar MUST NOT be rendered
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('BẢNG CÔNG TỔNG HỢP'), findsNothing);
      expect(find.textContaining('DUYỆT ĐIỀU CHỈNH'), findsNothing);

      // Personal view KPI cards are shown
      expect(find.text('Tổng giờ làm'), findsOneWidget);
    });

    testWidgets('Supervisor can reject an adjustment request with "Từ chối"', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(user: supervisorUser, isPersonalOnly: false));
      await tester.pumpAndSettle();

      // Switch to adjustment tab
      final adjustmentTab = find.textContaining('DUYỆT ĐIỀU CHỈNH');
      await tester.tap(adjustmentTab);
      await tester.pumpAndSettle();

      expect(find.text('Từ chối'), findsOneWidget);

      // Tap "Từ chối"
      await tester.tap(find.text('Từ chối'));
      await tester.pumpAndSettle();

      expect(find.text('Từ chối'), findsOneWidget);
      expect(fakeRepo.adjustments.first.isRejected, isTrue);
    });

    testWidgets('Clean White AppBar and high-contrast TabBar styling on MonthlyTimesheetPage', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(user: supervisorUser, isPersonalOnly: false));
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.white);
      expect(appBar.foregroundColor, AppColors.textPrimary);

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.labelColor, AppColors.primary);
      expect(tabBar.unselectedLabelColor, AppColors.textSecondary);
      expect(tabBar.indicatorColor, AppColors.primary);
      expect(tabBar.indicatorWeight, 3);
    });
  });
}
