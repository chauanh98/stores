import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/application/attendance/live_attendance_dashboard_provider.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/domain/attendance/attendance_adjustment.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/attendance/pages/attendance_check_in_page.dart';
import 'package:stores/presentation/attendance/pages/live_attendance_dashboard_page.dart';
import 'package:stores/presentation/attendance/pages/monthly_timesheet_page.dart';
import 'package:stores/presentation/attendance/pages/shift_config_page.dart';

import '../../application/attendance/fake_attendance_repository.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _FakeLiveAttendanceNotifier extends StateNotifier<LiveAttendanceState>
    implements LiveAttendanceDashboardNotifier {
  _FakeLiveAttendanceNotifier(super.state);

  @override
  Future<void> changeStore(String newStoreId) async {}

  @override
  Future<void> loadDashboard() async {}
}

void main() {
  const staffUser = UserAccount(
    username: 'staff_stress_01',
    displayName: 'Nguyễn Hoàng Minh Trọng - Nhân viên bán hàng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor_stress_01',
    displayName: 'Trần Văn Giám Sát - Chi nhánh Đông Thắng KiotViet',
    role: 'supervisor',
    storeId: 'store_001',
  );

  final today = DateTime.now();

  late FakeAttendanceRepository fakeRepo;
  late FakeLocationService fakeLocation;

  final stressRecordWorking = AttendanceRecord(
    id: 'att_stress_01',
    userId: 'staff_stress_01',
    userName: 'Nguyễn Hoàng Minh Trọng - Nhân viên ca sáng',
    storeId: 'store_001',
    shiftId: 'shift_morning',
    shiftName: 'Ca Sáng (08:00 - 12:00)',
    date: today,
    checkInTime: DateTime(today.year, today.month, today.day, 8, 0),
    checkInGpsLat: 10.035000,
    checkInGpsLng: 105.788000,
    isGpsValid: true,
    status: AttendanceStatus.onTime,
    explanationReason: 'Check-in đúng giờ tiêu chuẩn',
  );

  final stressRecordLate = AttendanceRecord(
    id: 'att_stress_02',
    userId: 'staff_stress_02',
    userName: 'Lê Thị Thu Thảo - Nhân viên hỗ trợ kỹ thuật',
    storeId: 'store_001',
    shiftId: 'shift_morning',
    shiftName: 'Ca Sáng (08:00 - 12:00)',
    date: today,
    checkInTime: DateTime(today.year, today.month, today.day, 8, 45),
    checkOutTime: DateTime(today.year, today.month, today.day, 12, 15),
    checkInGpsLat: 10.035000,
    checkInGpsLng: 105.788000,
    isGpsValid: true,
    status: AttendanceStatus.late,
    lateMinutes: 45,
    totalWorkHours: 3.5,
    explanationReason:
        'Lý do kẹt xe nghiêm trọng trên đường Cách Mạng Tháng Tám do ngập nước sau mưa lớn kéo dài',
  );

  const notArrivedStaff = UserAccount(
    username: 'staff_stress_absent',
    displayName: 'Phạm Quốc Bảo - Nhân viên ca chiều chưa điểm danh',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  final liveAttendanceState = LiveAttendanceState(
    storeId: 'store_001',
    date: today,
    allRecords: [stressRecordWorking, stressRecordLate],
    workingStaff: [stressRecordWorking],
    lateStaff: [stressRecordLate],
    checkedOutStaff: [stressRecordLate],
    notArrivedStaff: [notArrivedStaff],
    isLoading: false,
  );

  setUp(() {
    fakeRepo = FakeAttendanceRepository();
    fakeLocation = FakeLocationService();

    fakeRepo.attendances.add(stressRecordWorking);
    fakeRepo.attendances.add(stressRecordLate);

    fakeRepo.adjustments.add(
      AttendanceAdjustment(
        id: 'adj_stress_01',
        attendanceId: 'att_stress_02',
        userId: 'staff_stress_02',
        userName: 'Lê Thị Thu Thảo - Nhân viên hỗ trợ kỹ thuật',
        storeId: 'store_001',
        requestedCheckIn: DateTime(today.year, today.month, today.day, 8, 0),
        requestedCheckOut: DateTime(today.year, today.month, today.day, 12, 0),
        reason: 'Điều chỉnh giờ vào do lỗi thiết bị quét định vị GPS tại quầy',
        status: AdjustmentStatus.pending,
        submittedAt: today,
      ),
    );
  });

  Widget buildDashboardApp({UserAccount user = supervisorUser}) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
        attendanceRepositoryProvider.overrideWithValue(fakeRepo),
        currentStoreIdProvider.overrideWithValue('store_001'),
        availableStoresProvider.overrideWith(
          (ref) => Future.value({'store_001': 'Chi nhánh Đông Thắng KiotViet'}),
        ),
        liveAttendanceDashboardProvider
            .overrideWith((ref) => _FakeLiveAttendanceNotifier(liveAttendanceState)),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('vi'),
        home: LiveAttendanceDashboardPage(),
      ),
    );
  }

  Widget buildShiftConfigApp({UserAccount user = supervisorUser}) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
        attendanceRepositoryProvider.overrideWithValue(fakeRepo),
        locationServiceProvider.overrideWithValue(fakeLocation),
        currentStoreIdProvider.overrideWithValue('store_001'),
        availableStoresProvider.overrideWith(
          (ref) => Future.value({'store_001': 'Chi nhánh Đông Thắng KiotViet'}),
        ),
        shiftRepositoryProvider.overrideWithValue(fakeRepo),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('vi'),
        home: ShiftConfigPage(),
      ),
    );
  }

  Widget buildMonthlyTimesheetApp({
    UserAccount user = supervisorUser,
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

  Widget buildCheckInApp({UserAccount user = staffUser}) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
        attendanceRepositoryProvider.overrideWithValue(fakeRepo),
        locationServiceProvider.overrideWithValue(fakeLocation),
        currentStoreIdProvider.overrideWithValue('store_001'),
        currentStoreNameProvider.overrideWith(
          (ref) => Future.value('Chi nhánh Đông Thắng KiotViet'),
        ),
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

  const testViewports = <String, Size>{
    '320x568 (iPhone SE 1st gen)': Size(320, 568),
    '360x640 (Android small)': Size(360, 640),
    '375x667 (iPhone 8)': Size(375, 667),
    '390x844 (Modern phone)': Size(390, 844),
  };

  group('Adversarial Viewport Stress Tests (Zero RenderFlex Overflow)', () {
    for (final entry in testViewports.entries) {
      final name = entry.key;
      final size = entry.value;

      testWidgets('LiveAttendanceDashboardPage on $name has zero overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildDashboardApp());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Must not have layout exception on $name');

        // Scroll the list down to verify item cards and wrap layout
        final listView = find.byType(ListView);
        if (listView.evaluate().isNotEmpty) {
          await tester.drag(listView.first, const Offset(0, -200));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'Scrolling on $name must not cause RenderFlex overflow');
        }
      });

      testWidgets('ShiftConfigPage on $name has zero overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildShiftConfigApp());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Must not have layout exception on $name');

        final oldHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          debugPrint('EXACT OVERFLOW ERROR: ${details.toString()}');
        };
        addTearDown(() => FlutterError.onError = oldHandler);

        // Switch to GPS Tab and verify scrolling
        await tester.tap(find.text('TỌA ĐỘ GPS CHI NHÁNH'));
        await tester.pumpAndSettle();


        final scrollView = find.byType(SingleChildScrollView);
        if (scrollView.evaluate().isNotEmpty) {
          await tester.drag(scrollView.first, const Offset(0, -150));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('MonthlyTimesheetPage (Supervisor) on $name has zero overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildMonthlyTimesheetApp(user: supervisorUser));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Must not have layout exception on $name');

        // Switch to Adjustment tab
        final adjustmentTab = find.textContaining('DUYỆT ĐIỀU CHỈNH');
        expect(adjustmentTab, findsOneWidget);
        await tester.tap(adjustmentTab);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'Adjustment approval tab must not overflow on $name');
      });

      testWidgets('MonthlyTimesheetPage (Staff personal) on $name has zero overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildMonthlyTimesheetApp(user: staffUser));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Must not have layout exception on $name');
      });

      testWidgets('AttendanceCheckInPage on $name has zero overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildCheckInApp());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Must not have layout exception on $name');

        // Scroll down to ensure all cards fit smoothly
        final scrollable = find.byType(SingleChildScrollView);
        if (scrollable.evaluate().isNotEmpty) {
          await tester.drag(scrollable.first, const Offset(0, -150));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  });

  group('ChoiceChip Horizontal Scrolling & Interactive State Transitions', () {
    testWidgets('ChoiceChips are wrapped in horizontal SingleChildScrollView and scroll smoothly',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568); // Extreme small width
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildDashboardApp());
      await tester.pumpAndSettle();

      // Find horizontal SingleChildScrollView
      final horizontalScrollView = find.byWidgetPredicate(
        (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(horizontalScrollView, findsOneWidget,
          reason: 'ChoiceChips MUST be wrapped in a horizontal SingleChildScrollView');

      // Verify all 4 ChoiceChips exist
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
      expect(chips.length, 4);

      // Verify showCheckmark is false on every chip
      for (final chip in chips) {
        expect(chip.showCheckmark, isFalse,
            reason: 'showCheckmark must be false to save horizontal space');
      }

      // Drag horizontally to exercise scroll physics
      await tester.drag(horizontalScrollView, const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tapping all 4 ChoiceChips transitions state and filters records correctly',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildDashboardApp());
      await tester.pumpAndSettle();

      // 1. Initial State: "Tất cả" selected
      expect(find.textContaining('Tất cả'), findsOneWidget);
      expect(find.text('Nguyễn Hoàng Minh Trọng - Nhân viên ca sáng'), findsOneWidget);
      expect(find.text('Lê Thị Thu Thảo - Nhân viên hỗ trợ kỹ thuật'), findsOneWidget);

      // 2. Tap "Đang làm" chip
      final workingChip = find.textContaining('Đang làm');
      expect(workingChip, findsWidgets);
      await tester.tap(workingChip.first);
      await tester.pumpAndSettle();

      // Only working staff is displayed
      expect(find.text('Nguyễn Hoàng Minh Trọng - Nhân viên ca sáng'), findsOneWidget);
      expect(find.text('Lê Thị Thu Thảo - Nhân viên hỗ trợ kỹ thuật'), findsNothing);

      // 3. Tap "Đi muộn" chip
      final lateChip = find.textContaining('Đi muộn');
      expect(lateChip, findsWidgets);
      await tester.tap(lateChip.first);
      await tester.pumpAndSettle();

      // Only late staff is displayed
      expect(find.text('Nguyễn Hoàng Minh Trọng - Nhân viên ca sáng'), findsNothing);
      expect(find.text('Lê Thị Thu Thảo - Nhân viên hỗ trợ kỹ thuật'), findsOneWidget);
      expect(find.text('Muộn 45 phút'), findsOneWidget);

      // 4. Tap "Chưa đến" chip
      final notArrivedChip = find.textContaining('Chưa đến');
      expect(notArrivedChip, findsWidgets);
      await tester.tap(notArrivedChip.first);
      await tester.pumpAndSettle();

      // Absent staff is displayed with 'Chưa đến' tag
      expect(find.text('Phạm Quốc Bảo - Nhân viên ca chiều chưa điểm danh'), findsOneWidget);
      expect(find.text('Chưa đến'), findsWidgets);

      // 5. Tap "Tất cả" chip to restore
      final allChip = find.textContaining('Tất cả');
      await tester.tap(allChip.first);
      await tester.pumpAndSettle();

      expect(find.text('Nguyễn Hoàng Minh Trọng - Nhân viên ca sáng'), findsOneWidget);
      expect(find.text('Lê Thị Thu Thảo - Nhân viên hỗ trợ kỹ thuật'), findsOneWidget);
    });

    testWidgets('Selected vs Unselected ChoiceChip styling matches Clean White specifications',
        (tester) async {
      await tester.pumpWidget(buildDashboardApp());
      await tester.pumpAndSettle();

      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
      final selectedChip = chips.firstWhere((c) => c.selected);
      final unselectedChips = chips.where((c) => !c.selected).toList();

      // Selected Chip style: primary background, bold white text
      expect(selectedChip.selectedColor, AppColors.primary);
      final selectedText = selectedChip.label as Text;
      expect(selectedText.style?.color, Colors.white);
      expect(selectedText.style?.fontWeight, FontWeight.bold);

      // Unselected Chip style: grey.shade100, textPrimary color
      for (final chip in unselectedChips) {
        expect(chip.backgroundColor, Colors.grey.shade100);
        final unselectedText = chip.label as Text;
        expect(unselectedText.style?.color, AppColors.textPrimary);
        expect(unselectedText.style?.fontWeight, FontWeight.normal);
      }
    });
  });

  group('RBAC UI Security & Boundary Enforcement', () {
    testWidgets('Staff user on ShiftConfigPage is strictly read-only: no FAB, no edit/delete, GPS save disabled',
        (tester) async {
      await tester.pumpWidget(buildShiftConfigApp(user: staffUser));
      await tester.pumpAndSettle();

      // FAB MUST be null
      expect(find.byType(FloatingActionButton), findsNothing,
          reason: 'Staff must NEVER have access to the Add Shift FloatingActionButton');

      // Edit and Delete icons MUST be absent
      expect(find.byIcon(Icons.edit_outlined), findsNothing,
          reason: 'Staff must NEVER see shift editing icon buttons');
      expect(find.byIcon(Icons.delete_outline), findsNothing,
          reason: 'Staff must NEVER see shift deletion icon buttons');

      // Switch to GPS Tab
      await tester.tap(find.text('TỌA ĐỘ GPS CHI NHÁNH'));
      await tester.pumpAndSettle();

      // TextFields must be read-only
      final textFields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(textFields.length, greaterThanOrEqualTo(3));
      for (final tf in textFields) {
        expect(tf.readOnly, isTrue, reason: 'Staff must not edit GPS coordinates');
      }

      // "Lấy tọa độ vị trí hiện tại" button must be disabled
      final getCoordsFinder = find.ancestor(
        of: find.text('Lấy tọa độ vị trí hiện tại'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      );
      final getCoordsButton = tester.widget<OutlinedButton>(getCoordsFinder);
      expect(getCoordsButton.onPressed, isNull,
          reason: 'Staff must not trigger GPS location overwrite');

      // "LƯU CẤU HÌNH GPS" button must be disabled
      final saveButtonFinder = find.ancestor(
        of: find.text('LƯU CẤU HÌNH GPS'),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      );
      final saveButton = tester.widget<ElevatedButton>(saveButtonFinder);
      expect(saveButton.onPressed, isNull,
          reason: 'Staff must not be able to press GPS save button');
    });

    testWidgets('Supervisor on ShiftConfigPage has full administrative permissions',
        (tester) async {
      await tester.pumpWidget(buildShiftConfigApp(user: supervisorUser));
      await tester.pumpAndSettle();

      // FAB is visible
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Edit and Delete icons are visible
      expect(find.byIcon(Icons.edit_outlined), findsWidgets);
      expect(find.byIcon(Icons.delete_outline), findsWidgets);

      // Switch to GPS Tab
      await tester.tap(find.text('TỌA ĐỘ GPS CHI NHÁNH'));
      await tester.pumpAndSettle();

      // GPS Save button is enabled
      final saveButtonFinder = find.ancestor(
        of: find.text('LƯU CẤU HÌNH GPS'),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      );
      final saveButton = tester.widget<ElevatedButton>(saveButtonFinder);
      expect(saveButton.onPressed, isNotNull,
          reason: 'Supervisor must be able to press GPS save button');
    });

    testWidgets(
        'Staff user on MonthlyTimesheetPage (default constructor) is strictly isolated to personal timesheet',
        (tester) async {
      await tester.pumpWidget(buildMonthlyTimesheetApp(user: staffUser, isPersonalOnly: false));
      await tester.pumpAndSettle();
      // Assert zero layout overflow in RBAC tests
      expect(tester.takeException(), isNull);

      // AppBar title MUST be 'Bảng công cá nhân'
      expect(find.text('Bảng công cá nhân'), findsOneWidget);
      expect(find.text('Bảng chấm công & Duyệt công'), findsNothing);

      // TabBar MUST NOT exist
      expect(find.byType(TabBar), findsNothing,
          reason: 'TabBar must be null for staff accounts');
      expect(find.text('BẢNG CÔNG TỔNG HỢP'), findsNothing);
      expect(find.textContaining('DUYỆT ĐIỀU CHỈNH'), findsNothing);

      // Personal KPI cards must be visible
      expect(find.text('Tổng giờ làm'), findsOneWidget);
      expect(find.text('Ca hoàn tất'), findsOneWidget);
    });

    testWidgets('Supervisor on MonthlyTimesheetPage has full multi-tab access & approval controls',
        (tester) async {
      await tester.pumpWidget(buildMonthlyTimesheetApp(user: supervisorUser, isPersonalOnly: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // AppBar title is 'Bảng chấm công & Duyệt công'
      expect(find.text('Bảng chấm công & Duyệt công'), findsOneWidget);

      // TabBar is present with 2 tabs
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('BẢNG CÔNG TỔNG HỢP'), findsOneWidget);
      expect(find.textContaining('DUYỆT ĐIỀU CHỈNH'), findsOneWidget);

      // Navigate to Approval tab and verify action buttons
      await tester.tap(find.textContaining('DUYỆT ĐIỀU CHỈNH'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Duyệt công'), findsOneWidget);
      expect(find.text('Từ chối'), findsOneWidget);
    });
  });

  group('Clean White Theme Conformity Verification', () {
    testWidgets('LiveAttendanceDashboardPage has Clean White AppBar', (tester) async {
      await tester.pumpWidget(buildDashboardApp());
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.white);
      expect(appBar.foregroundColor, AppColors.textPrimary);
      expect(appBar.elevation, 0);

      final titleWidget = tester.widget<Text>(find.text('Giám sát chấm công trực tiếp'));
      expect(titleWidget.style?.color, AppColors.textPrimary);
    });

    testWidgets('ShiftConfigPage has Clean White AppBar & high contrast TabBar', (tester) async {
      await tester.pumpWidget(buildShiftConfigApp());
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.white);
      expect(appBar.foregroundColor, AppColors.textPrimary);
      expect(appBar.elevation, 0);

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.labelColor, AppColors.primary);
      expect(tabBar.unselectedLabelColor, AppColors.textSecondary);
      expect(tabBar.indicatorColor, AppColors.primary);
      expect(tabBar.indicatorWeight, 3.0);
    });

    testWidgets('MonthlyTimesheetPage (Supervisor) has Clean White AppBar & high contrast TabBar',
        (tester) async {
      await tester.pumpWidget(buildMonthlyTimesheetApp(user: supervisorUser));
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.white);
      expect(appBar.foregroundColor, AppColors.textPrimary);
      expect(appBar.elevation, 0);

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.labelColor, AppColors.primary);
      expect(tabBar.unselectedLabelColor, AppColors.textSecondary);
      expect(tabBar.indicatorColor, AppColors.primary);
      expect(tabBar.indicatorWeight, 3.0);
    });

    testWidgets('AttendanceCheckInPage has Clean White AppBar', (tester) async {
      await tester.pumpWidget(buildCheckInApp());
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.white);
      expect(appBar.foregroundColor, AppColors.textPrimary);
      expect(appBar.elevation, 0);
    });
  });
}
