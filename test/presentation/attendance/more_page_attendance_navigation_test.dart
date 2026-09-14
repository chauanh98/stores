import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/attendance/pages/attendance_check_in_page.dart';
import 'package:stores/presentation/attendance/pages/live_attendance_dashboard_page.dart';
import 'package:stores/presentation/attendance/pages/shift_config_page.dart';
import 'package:stores/presentation/settings/pages/more_page.dart';

import '../../application/attendance/fake_attendance_repository.dart';

class _DynamicAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _DynamicAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _FakeCustomerListNotifier extends CustomerListNotifier {
  @override
  Future<List<Customer>> build() async => [];
}

class _FakeSupplierListNotifier extends SupplierListNotifier {
  @override
  Future<List<Supplier>> build() async => [];
}

void main() {
  group('MorePage Attendance Navigation Tests', () {
    late FakeAttendanceRepository fakeRepo;
    late FakeLocationService fakeLocation;

    const staffUser = UserAccount(
      username: 'nhanvien_1',
      displayName: 'Nhân viên A',
      role: 'nhanvien',
      storeId: 'store_001',
    );

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

    Widget createWidgetUnderTest(UserAccount user) {
      return ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _DynamicAuthNotifier(user)),
          currentStoreIdProvider.overrideWithValue(user.storeId),
          availableStoresProvider.overrideWith(
            (ref) => Future.value({'store_001': 'Chi nhánh Đông Thắng'}),
          ),
          customerListNotifierProvider.overrideWith(_FakeCustomerListNotifier.new),
          supplierListNotifierProvider.overrideWith(_FakeSupplierListNotifier.new),
          attendanceRepositoryProvider.overrideWithValue(fakeRepo),
          locationServiceProvider.overrideWithValue(fakeLocation),
          shiftRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: MorePage(),
        ),
      );
    }

    testWidgets('Staff user sees "Chấm công nhân viên" and can navigate to AttendanceCheckInPage', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(staffUser));
      await tester.pumpAndSettle();

      // Attendance block header
      final attendanceBlock = find.text('QUẢN LÝ CA & CHẤM CÔNG');
      expect(attendanceBlock, findsOneWidget);

      final checkInTile = find.text('Chấm công nhân viên');
      expect(checkInTile, findsOneWidget);

      // Supervisor/Admin options are hidden for staff
      expect(find.text('Giám sát chấm công & Bảng công'), findsNothing);

      // Scroll and tap "Chấm công nhân viên"
      await tester.ensureVisible(checkInTile);
      await tester.pumpAndSettle();
      await tester.tap(checkInTile);
      await tester.pumpAndSettle();

      expect(find.byType(AttendanceCheckInPage), findsOneWidget);
    });

    testWidgets('Admin user sees management tiles, MUST NOT see "Chấm công nhân viên", and navigates to LiveAttendanceDashboardPage', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(adminUser));
      await tester.pumpAndSettle();

      // Attendance block header
      expect(find.text('QUẢN LÝ CA & CHẤM CÔNG'), findsOneWidget);

      // Staff check-in tile MUST NOT be visible for Admin
      expect(find.text('Chấm công nhân viên'), findsNothing);

      final monitorTile = find.text('Giám sát chấm công & Bảng công');
      expect(monitorTile, findsOneWidget);

      final configTile = find.text('Cấu hình Ca làm việc & GPS');
      expect(configTile, findsOneWidget);

      await tester.ensureVisible(monitorTile);
      await tester.pumpAndSettle();
      await tester.tap(monitorTile);
      await tester.pumpAndSettle();

      expect(find.byType(LiveAttendanceDashboardPage), findsOneWidget);
    });

    testWidgets('Supervisor user sees management tiles, MUST NOT see "Chấm công nhân viên", and navigates to ShiftConfigPage', (tester) async {
      const supervisorUser = UserAccount(
        username: 'supervisor_1',
        displayName: 'Cửa hàng trưởng',
        role: 'supervisor',
        storeId: 'store_001',
      );

      await tester.pumpWidget(createWidgetUnderTest(supervisorUser));
      await tester.pumpAndSettle();

      // Attendance block header
      expect(find.text('QUẢN LÝ CA & CHẤM CÔNG'), findsOneWidget);

      // Staff check-in tile MUST NOT be visible for Supervisor
      expect(find.text('Chấm công nhân viên'), findsNothing);

      final monitorTile = find.text('Giám sát chấm công & Bảng công');
      expect(monitorTile, findsOneWidget);

      final configTile = find.text('Cấu hình Ca làm việc & GPS');
      expect(configTile, findsOneWidget);

      await tester.ensureVisible(configTile);
      await tester.pumpAndSettle();
      await tester.tap(configTile);
      await tester.pumpAndSettle();

      expect(find.byType(ShiftConfigPage), findsOneWidget);
    });
  });
}
