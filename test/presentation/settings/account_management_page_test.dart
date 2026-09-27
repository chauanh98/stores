import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/settings/pages/account_management_page.dart';

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

Widget _buildTestApp({
  required Widget child,
  required List<Override> overrides,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('vi')],
      locale: const Locale('vi'),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const adminUser = UserAccount(
    username: 'admin1',
    displayName: 'Admin Chủ Shop',
    role: 'admin',
    storeId: 'all',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor1',
    displayName: 'Quản Lý Cửa Hàng',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const staffStore1 = UserAccount(
    username: 'staff1',
    displayName: 'Nhân Viên ĐT',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const staffStore2 = UserAccount(
    username: 'staff2',
    displayName: 'Nhân Viên TB',
    role: 'nhanvien',
    storeId: 'store_002',
  );

  final testAccounts = [
    adminUser,
    supervisorUser,
    staffStore1,
    staffStore2,
  ];

  final mockStores = {
    'store_001': 'Chi nhánh Đông Thắng',
    'store_002': 'Chi nhánh Thới Bình',
  };

  group('AccountManagementPage - Role Scoping & UI Tests', () {
    testWidgets(
        'Admin views all accounts with role badges and "Toàn bộ chi nhánh (Toàn hệ thống)"',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const AccountManagementPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider
                .overrideWith((ref) => Stream.value(testAccounts)),
            availableStoresProvider.overrideWith((ref) async => mockStores),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Page Title
      expect(find.text('Quản lý tài khoản'), findsOneWidget);

      // All 4 accounts are visible for Admin
      expect(find.text('Admin Chủ Shop'), findsOneWidget);
      expect(find.text('Quản Lý Cửa Hàng'), findsOneWidget);
      expect(find.text('Nhân Viên ĐT'), findsOneWidget);
      expect(find.text('Nhân Viên TB'), findsOneWidget);

      // Role Badges
      expect(find.text('👑 Quản trị viên (Chủ shop)'), findsOneWidget);
      expect(find.text('👔 Cửa hàng trưởng'), findsOneWidget);
      expect(find.text('🧑‍💼 Nhân viên'), findsNWidgets(2));

      // Admin has 'Toàn bộ chi nhánh (Toàn hệ thống)' badge
      expect(find.text('Toàn bộ chi nhánh (Toàn hệ thống)'), findsOneWidget);

      // Store names for branch-bound accounts
      expect(find.text('Chi nhánh Đông Thắng'), findsNWidgets(2));
      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);

      // Floating Action Button to add account is visible for Admin
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets(
        'Supervisor views only Admin and staff in their assigned store (store_001)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const AccountManagementPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            accountsListProvider
                .overrideWith((ref) => Stream.value(testAccounts)),
            availableStoresProvider.overrideWith((ref) async => mockStores),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Supervisor sees self, admin, and staff in store_001
      expect(find.text('Admin Chủ Shop'), findsOneWidget);
      expect(find.text('Quản Lý Cửa Hàng'), findsOneWidget);
      expect(find.text('Nhân Viên ĐT'), findsOneWidget);

      // Staff in store_002 MUST be hidden from Supervisor
      expect(find.text('Nhân Viên TB'), findsNothing);
    });

    testWidgets(
        'Account Form Dialog: selecting Admin role displays "Toàn bộ chi nhánh" info card',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const AccountManagementPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider
                .overrideWith((ref) => Stream.value(testAccounts)),
            availableStoresProvider.overrideWith((ref) async => mockStores),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap FAB to add new account
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Dialog is open
      expect(find.text('Thêm tài khoản mới'), findsOneWidget);

      // Thêm mới: "Thông tin hiện tại" KHÔNG được hiển thị
      expect(find.text('Thông tin hiện tại'), findsNothing);

      // Default role is 'nhanvien', so Chi nhánh dropdown is visible
      expect(find.text('Chi nhánh làm việc *'), findsOneWidget);

      // Tap role dropdown to select 'Quản trị viên (Chủ shop - Toàn chuỗi)'
      await tester.tap(find.text('Nhân viên (Thu ngân / Bán hàng)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quản trị viên (Chủ shop - Toàn chuỗi)').last);
      await tester.pumpAndSettle();

      // Now Chi nhánh dropdown is replaced with the system-wide banner
      expect(find.text('Chi nhánh làm việc *'), findsNothing);
      expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Toàn bộ chi nhánh (Toàn hệ thống)'),
          ),
          findsOneWidget);
      expect(
          find.text(
              'Chủ shop / Quản trị viên có quyền truy cập và quản lý toàn bộ chi nhánh.'),
          findsOneWidget);
    });

    testWidgets(
        'Peer-Admin Protection: Admin cannot edit or delete another Admin; only edits self and subordinates',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const peerAdmin = UserAccount(
        username: 'admin2',
        displayName: 'Admin Đối Tác',
        role: 'admin',
        storeId: 'all',
      );

      final multiAdminAccounts = [
        adminUser, // admin1 (currentUser)
        peerAdmin, // admin2 (peer admin)
        supervisorUser,
        staffStore1,
      ];

      await tester.pumpWidget(
        _buildTestApp(
          child: const AccountManagementPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider
                .overrideWith((ref) => Stream.value(multiAdminAccounts)),
            availableStoresProvider.overrideWith((ref) async => mockStores),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Helper to find action buttons inside a specific account card
      Finder accountCard(String displayName) {
        return find.ancestor(
          of: find.text(displayName),
          matching: find.byType(Container),
        ).first;
      }

      // 1. Peer Admin (admin2): NO edit and NO delete icons
      final peerCard = accountCard('Admin Đối Tác');
      expect(
        find.descendant(of: peerCard, matching: find.byIcon(Icons.edit_outlined)),
        findsNothing,
      );
      expect(
        find.descendant(of: peerCard, matching: find.byIcon(Icons.delete_outline)),
        findsNothing,
      );

      // 2. Self Admin (admin1): Has edit icon, but NO delete icon
      final selfCard = accountCard('Admin Chủ Shop');
      expect(
        find.descendant(of: selfCard, matching: find.byIcon(Icons.edit_outlined)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: selfCard, matching: find.byIcon(Icons.delete_outline)),
        findsNothing,
      );

      // 3. Subordinates (supervisor, staff): Have BOTH edit and delete icons
      final supervisorCard = accountCard('Quản Lý Cửa Hàng');
      expect(
        find.descendant(of: supervisorCard, matching: find.byIcon(Icons.edit_outlined)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: supervisorCard, matching: find.byIcon(Icons.delete_outline)),
        findsOneWidget,
      );
    });

    testWidgets(
        'Editing Account: displays "Thông tin hiện tại" card with accurate branch and role',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const AccountManagementPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider
                .overrideWith((ref) => Stream.value(testAccounts)),
            availableStoresProvider.overrideWith((ref) async => mockStores),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Find edit button for staff2 (Nhân Viên TB, store_002)
      final staff2Card = find.ancestor(
        of: find.text('Nhân Viên TB'),
        matching: find.byType(Container),
      ).first;

      final editButton = find.descendant(
        of: staff2Card,
        matching: find.byIcon(Icons.edit_outlined),
      );
      expect(editButton, findsOneWidget);

      await tester.tap(editButton);
      await tester.pumpAndSettle();

      // Dialog is open in Edit mode
      expect(find.text('Chỉnh sửa tài khoản'), findsOneWidget);

      // "Thông tin hiện tại" card is visible
      expect(find.text('Thông tin hiện tại'), findsOneWidget);
      expect(find.text('Vai trò hiện tại: '), findsOneWidget);
      expect(find.text('Nhân viên'), findsWidgets);
      expect(find.text('Chi nhánh hiện tại: '), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình'), findsWidgets);
    });

    testWidgets(
        'Editing Admin Account: displays "Toàn bộ chi nhánh (Toàn hệ thống)" with Icons.hub_outlined and system-wide banner',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const AccountManagementPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider
                .overrideWith((ref) => Stream.value(testAccounts)),
            availableStoresProvider.overrideWith((ref) async => mockStores),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Find self admin card (Admin Chủ Shop)
      final adminCard = find.ancestor(
        of: find.text('Admin Chủ Shop'),
        matching: find.byType(Container),
      ).first;

      final editButton = find.descendant(
        of: adminCard,
        matching: find.byIcon(Icons.edit_outlined),
      );
      expect(editButton, findsOneWidget);

      await tester.tap(editButton);
      await tester.pumpAndSettle();

      // Dialog is open in Edit mode
      expect(find.text('Chỉnh sửa tài khoản'), findsOneWidget);

      // "Thông tin hiện tại" displays Toàn bộ chi nhánh (Toàn hệ thống)
      expect(find.text('Thông tin hiện tại'), findsOneWidget);
      expect(find.text('Chi nhánh hiện tại: '), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Toàn bộ chi nhánh (Toàn hệ thống)'),
        ),
        findsNWidgets(2), // 1 in current info card, 1 in system-wide banner
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byIcon(Icons.hub_outlined),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets(
        'Editing Owner Account: safely normalizes role to admin without dropdown assertion error',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const ownerAccount = UserAccount(
        username: 'owner_boss',
        displayName: 'Chủ Doanh Nghiệp',
        role: 'owner',
        storeId: 'store_001',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const AccountManagementPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(ownerAccount)),
            accountsListProvider
                .overrideWith((ref) => Stream.value([ownerAccount])),
            availableStoresProvider.overrideWith((ref) async => mockStores),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // List card displays 'Toàn bộ chi nhánh (Toàn hệ thống)'
      expect(find.text('Toàn bộ chi nhánh (Toàn hệ thống)'), findsOneWidget);

      // Tap edit button
      final editButton = find.byIcon(Icons.edit_outlined);
      expect(editButton, findsOneWidget);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      // Dialog is open without any dropdown assertion errors
      expect(find.text('Chỉnh sửa tài khoản'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Toàn bộ chi nhánh (Toàn hệ thống)'),
        ),
        findsNWidgets(2),
      );
    });
  });
}
