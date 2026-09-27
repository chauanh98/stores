import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/attendance/pages/attendance_check_in_page.dart';

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
  group('AttendanceCheckInPage Widget Tests', () {
    late FakeAttendanceRepository fakeRepo;
    late FakeLocationService fakeLocation;

    const testStaff = UserAccount(
      username: 'staff_1',
      displayName: 'Nguyễn Văn A',
      role: 'nhanvien',
      storeId: 'store_001',
    );

    setUp(() {
      fakeRepo = FakeAttendanceRepository();
      fakeRepo.shifts = [
        ...Shift.defaultShifts(),
        const Shift(
          id: 'shift_allday',
          name: 'Ca Suốt',
          startTime: '00:00',
          endTime: '23:59',
          type: 'flexible',
        ),
      ];
      fakeLocation = FakeLocationService();
    });

    Widget createWidgetUnderTest() {
      return ProviderScope(
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
      );
    }

    testWidgets('Renders all main sections: GPS Card, Shift Selector, Check-in Button, and Timesheet Summary', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // App bar
      expect(find.text('Chấm công GPS & Quản lý Ca'), findsOneWidget);

      // Staff and Store info
      expect(find.text('Nguyễn Văn A'), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng'), findsWidgets);

      // GPS Card
      expect(find.text('Vị trí GPS & Chi nhánh'), findsOneWidget);
      expect(find.textContaining('Hợp lệ'), findsOneWidget);

      // Shift selector card
      expect(find.text('Chọn ca làm việc hôm nay'), findsOneWidget);
      expect(find.text('Ca Sáng'), findsOneWidget);

      // Action button
      expect(find.text('CHẤM CÔNG VÀO'), findsOneWidget);

      // Personal timesheet card
      expect(find.text('Bảng công tháng này'), findsOneWidget);
      expect(find.text('Tổng giờ làm'), findsOneWidget);
      expect(find.text('Ca hoàn thành'), findsOneWidget);
    });

    testWidgets('Tapping CHẤM CÔNG VÀO triggers check-in and updates button to CHẤM CÔNG RA', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final checkInButton = find.text('CHẤM CÔNG VÀO');
      expect(checkInButton, findsOneWidget);

      await tester.ensureVisible(checkInButton);
      await tester.pumpAndSettle();

      await tester.tap(checkInButton);
      await tester.pumpAndSettle();

      // Button should now transition to "CHẤM CÔNG RA"
      expect(find.text('CHẤM CÔNG RA'), findsOneWidget);
      expect(fakeRepo.attendances.length, 1);
      expect(fakeRepo.attendances.first.userId, 'staff_1');
      expect(fakeRepo.attendances.first.isWorking, isTrue);
    });

    testWidgets('Renders Clean White AppBar with proper background and foreground styling', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.white);
      expect(appBar.foregroundColor, AppColors.textPrimary);
      expect(appBar.elevation, 0);
    });

    testWidgets('ShiftSelectorCard renders status tags: Đang mở ca or Đã kết thúc', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Ensure at least one status tag is rendered on the shifts list
      final hasOpenTag = find.text('Đang mở ca').evaluate().isNotEmpty;
      final hasEndedTag = find.text('Đã kết thúc').evaluate().isNotEmpty;
      final hasUpcomingTag = find.textContaining('Chưa mở').evaluate().isNotEmpty;

      expect(hasOpenTag || hasEndedTag || hasUpcomingTag, isTrue);
    });

    testWidgets('Attempting check-in to a closed shift shows error banner and blocks check-in', (tester) async {
      const closedShift = Shift(
        id: 'shift_closed_test',
        name: 'Ca Hôm Qua',
        startTime: '01:00',
        endTime: '02:00',
        type: 'morning',
      );
      fakeRepo.shifts = [closedShift];

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Ca Hôm Qua'), findsOneWidget);
      expect(find.text('Đã kết thúc'), findsOneWidget);

      await tester.tap(find.text('Ca Hôm Qua'));
      await tester.pumpAndSettle();

      final checkInButton = find.text('CHẤM CÔNG VÀO');
      await tester.ensureVisible(checkInButton);
      await tester.tap(checkInButton);
      await tester.pumpAndSettle();

      // Error banner must appear with the exact rejection message
      expect(
        find.text('Ca Ca Hôm Qua đã kết thúc lúc 02:00. Bạn không thể chấm công vào ca đã qua. Vui lòng chọn ca kế tiếp.'),
        findsOneWidget,
      );
      expect(fakeRepo.attendances, isEmpty);
    });
  });
}
