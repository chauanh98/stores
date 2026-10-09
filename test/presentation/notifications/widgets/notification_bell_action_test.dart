import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/notifications/pages/notifications_page.dart';
import 'package:stores/presentation/notifications/widgets/notification_bell_action.dart';

class _MockAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _MockAuthNotifier([super.state]);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestWidget({
    UserAccount? user,
    int unreadCount = 0,
  }) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _MockAuthNotifier(user)),
        unreadNotificationCountProvider.overrideWithValue(unreadCount),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('vi'),
        home: Scaffold(
          appBar: AppBar(
            actions: const [
              NotificationBellAction(),
            ],
          ),
        ),
        routes: {
          '/notifications': (context) => const NotificationsPage(),
        },
      ),
    );
  }

  group('NotificationBellAction Widget Tests', () {
    testWidgets('1. RBAC Guard: Completely hidden when user is null',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(user: null));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_action_button')),
          findsNothing);
      expect(find.byIcon(Icons.notifications_outlined), findsNothing);
      expect(find.byIcon(Icons.notifications), findsNothing);
    });

    testWidgets(
        '2. RBAC Guard: Completely hidden when user is staff (role: nhanvien)',
        (tester) async {
      const staffUser = UserAccount(
        username: 'staff1',
        role: 'nhanvien',
        storeId: 'store_001',
      );
      await tester.pumpWidget(buildTestWidget(user: staffUser));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_action_button')),
          findsNothing);
      expect(find.byIcon(Icons.notifications_outlined), findsNothing);
    });

    testWidgets(
        '3. RBAC Guard: Completely hidden when user is supervisor without admin',
        (tester) async {
      const supervisorUser = UserAccount(
        username: 'sup1',
        role: 'supervisor',
        storeId: 'store_001',
      );
      await tester.pumpWidget(buildTestWidget(user: supervisorUser));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_action_button')),
          findsNothing);
    });

    testWidgets(
        '4. Admin role renders bell icon without badge when unreadCount == 0',
        (tester) async {
      const adminUser = UserAccount(
        username: 'admin1',
        role: 'admin',
        storeId: 'store_001',
      );
      await tester.pumpWidget(buildTestWidget(user: adminUser, unreadCount: 0));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_action_button')),
          findsOneWidget);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets(
        '5. Reactive badge displays exact count when unreadCount > 0',
        (tester) async {
      const adminUser = UserAccount(
        username: 'admin1',
        role: 'admin',
        storeId: 'store_001',
      );
      await tester.pumpWidget(buildTestWidget(user: adminUser, unreadCount: 7));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_action_button')),
          findsOneWidget);
      expect(find.byIcon(Icons.notifications), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('6. Reactive badge caps at 99+ when unreadCount > 99',
        (tester) async {
      const ownerUser = UserAccount(
        username: 'owner1',
        role: 'owner',
        storeId: 'store_001',
      );
      await tester
          .pumpWidget(buildTestWidget(user: ownerUser, unreadCount: 150));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_action_button')),
          findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('7. Tapping bell action pushes /notifications route',
        (tester) async {
      const adminUser = UserAccount(
        username: 'admin1',
        role: 'admin',
        storeId: 'store_001',
      );
      await tester.pumpWidget(buildTestWidget(user: adminUser, unreadCount: 3));
      await tester.pumpAndSettle();

      final bellButton =
          find.byKey(const Key('notification_bell_action_button'));
      expect(bellButton, findsOneWidget);

      await tester.tap(bellButton);
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsPage), findsOneWidget);
    });
  });
}
