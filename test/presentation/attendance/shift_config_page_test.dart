import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/attendance/pages/shift_config_page.dart';

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
  group('ShiftConfigPage Widget Tests', () {
    late FakeAttendanceRepository fakeRepo;
    late FakeLocationService fakeLocation;

    const adminUser = UserAccount(
      username: 'admin_1',
      displayName: 'Quản trị viên',
      role: 'admin',
      storeId: 'store_001',
    );

    setUp(() {
      fakeRepo = FakeAttendanceRepository();
      fakeLocation = FakeLocationService();
    });

    Widget createWidgetUnderTest({UserAccount user = adminUser}) {
      return ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
          attendanceRepositoryProvider.overrideWithValue(fakeRepo),
          locationServiceProvider.overrideWithValue(fakeLocation),
          currentStoreIdProvider.overrideWithValue('store_001'),
          availableStoresProvider.overrideWith(
            (ref) => Future.value({'store_001': 'Chi nhánh Đông Thắng'}),
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

    testWidgets('Renders ShiftConfigPage with shifts tab and allows viewing GPS tab', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Cấu hình Ca làm việc & GPS Chi nhánh'), findsOneWidget);
      expect(find.text('DANH SÁCH CA LÀM'), findsOneWidget);
      expect(find.text('TỌA ĐỘ GPS CHI NHÁNH'), findsOneWidget);

      // Default shifts
      expect(find.text('Ca Sáng'), findsOneWidget);
      expect(find.text('Ca Chiều'), findsOneWidget);

      // Switch to GPS Tab
      await tester.tap(find.text('TỌA ĐỘ GPS CHI NHÁNH'));
      await tester.pumpAndSettle();

      expect(find.text('Cấu hình Geofence GPS Chi nhánh'), findsOneWidget);
      expect(find.text('LƯU CẤU HÌNH GPS'), findsOneWidget);
    });

    testWidgets('Supervisor can see FAB, edit/delete actions, and Clean White styling', (tester) async {
      const supervisorUser = UserAccount(
        username: 'supervisor_1',
        displayName: 'Giám sát viên',
        role: 'supervisor',
        storeId: 'store_001',
      );

      await tester.pumpWidget(createWidgetUnderTest(user: supervisorUser));
      await tester.pumpAndSettle();

      // Clean White AppBar
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.white);
      expect(appBar.foregroundColor, AppColors.textPrimary);

      // High-contrast TabBar
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.labelColor, AppColors.primary);
      expect(tabBar.unselectedLabelColor, AppColors.textSecondary);
      expect(tabBar.indicatorColor, AppColors.primary);
      expect(tabBar.indicatorWeight, 3);

      // FAB is visible for Supervisor
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Edit and delete icons are visible
      expect(find.byIcon(Icons.edit_outlined), findsWidgets);
      expect(find.byIcon(Icons.delete_outline), findsWidgets);
    });

    testWidgets('Staff user has read-only access: no FAB, no edit/delete buttons, read-only GPS', (tester) async {
      const staffUser = UserAccount(
        username: 'staff_1',
        displayName: 'Nhân viên 1',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      await tester.pumpWidget(createWidgetUnderTest(user: staffUser));
      await tester.pumpAndSettle();

      // FAB is hidden for staff
      expect(find.byType(FloatingActionButton), findsNothing);

      // Edit and delete buttons are hidden for staff
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      // Switch to GPS Tab
      await tester.tap(find.text('TỌA ĐỘ GPS CHI NHÁNH'));
      await tester.pumpAndSettle();

      expect(find.text('Cấu hình Geofence GPS Chi nhánh'), findsOneWidget);
      expect(find.text('LƯU CẤU HÌNH GPS'), findsOneWidget);

      // GPS Save button should be disabled for staff
      final saveButtonFinder = find.ancestor(
        of: find.text('LƯU CẤU HÌNH GPS'),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      );
      final saveButton = tester.widget<ElevatedButton>(saveButtonFinder);
      expect(saveButton.onPressed, isNull);
    });
  });
}
