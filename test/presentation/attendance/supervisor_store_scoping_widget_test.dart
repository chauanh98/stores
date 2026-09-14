import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/application/auth/auth_providers.dart';
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
  group('Supervisor vs Admin Store Scoping Widget Tests', () {
    late FakeAttendanceRepository fakeRepo;

    const supervisorUser = UserAccount(
      username: 'supervisor_1',
      displayName: 'Giám sát viên ĐT',
      role: 'supervisor',
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
    });

    Widget createWidgetWithUser(UserAccount user) {
      return ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
          attendanceRepositoryProvider.overrideWithValue(fakeRepo),
          currentStoreIdProvider.overrideWithValue('store_001'),
          availableStoresProvider.overrideWith(
            (ref) => Future.value({
              'store_001': 'Chi nhánh Đông Thắng',
              'store_002': 'Chi nhánh Thới Bình',
            }),
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

    testWidgets('Admin user sees store dropdown selector to switch stores', (tester) async {
      await tester.pumpWidget(createWidgetWithUser(adminUser));
      await tester.pumpAndSettle();

      // DropdownButton should be visible for Admin
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    testWidgets('Supervisor user must NOT see store dropdown selector (must be locked to assigned store)', (tester) async {
      await tester.pumpWidget(createWidgetWithUser(supervisorUser));
      await tester.pumpAndSettle();

      // According to ORIGINAL_REQUEST.md §R4:
      // "Supervisor chỉ giám sát chi nhánh mình phụ trách; Admin có thể giám sát tất cả chi nhánh."
      // Supervisor must NOT see DropdownButton to switch stores!
      expect(
        find.byType(DropdownButton<String>),
        findsNothing,
        reason: 'Supervisor must not have a store switcher dropdown; they are locked to assigned branch',
      );
    });
  });
}
