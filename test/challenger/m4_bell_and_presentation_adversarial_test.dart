import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/notifications/pages/notifications_page.dart';
import 'package:stores/presentation/notifications/utils/notification_navigation_handler.dart';
import 'package:stores/presentation/notifications/widgets/notification_bell_action.dart';

/// Test navigator observer to monitor route push events and stack integrity
class _TestNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;
  int popCount = 0;
  final List<Route<dynamic>> routes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    pushCount++;
    routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    popCount++;
    routes.remove(route);
  }
}

/// Dynamic mock AuthNotifier allowing role mutation during tests
class _DynamicAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _DynamicAuthNotifier([super.state]);

  void setUser(UserAccount? user) {
    state = user;
  }

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

/// Dynamic unread count notifier for reactivity tests
class _DynamicCountNotifier extends StateNotifier<int> {
  _DynamicCountNotifier([super.state = 0]);

  void setCount(int val) {
    state = val;
  }
}

final _testCountNotifierProvider =
    StateNotifierProvider<_DynamicCountNotifier, int>(
        (ref) => _DynamicCountNotifier(0));

/// Fake NotificationRepository for stress-testing navigation handler and mutations
class _FakeNotificationRepository implements NotificationRepository {
  int markAsReadCount = 0;
  final List<String> markedReadIds = [];
  final List<NotificationItem> items = [];

  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
      {int limit = 50}) {
    return Stream.value(items);
  }

  @override
  Future<void> addNotification(NotificationItem notification) async {
    items.add(notification);
  }

  @override
  Future<void> markAsRead(
      {required String storeId, required String id}) async {
    markAsReadCount++;
    markedReadIds.add(id);
  }

  @override
  Future<void> markAllAsRead(String storeId) async {
    for (int i = 0; i < items.length; i++) {
      items[i] = items[i].copyWith(isRead: true);
    }
  }

  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {
    items.removeWhere((item) => item.id == id);
  }
}

/// Reusable helper to build test widget tree cleanly without const lint noise
Widget _buildTestApp({
  required List<dynamic> overrides,
  Widget? body,
  List<Widget>? actions,
  Map<String, WidgetBuilder>? routes,
  List<NavigatorObserver>? navigatorObservers,
  Locale locale = const Locale('vi'),
}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      navigatorObservers: navigatorObservers ?? const <NavigatorObserver>[],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      routes: routes ?? const <String, WidgetBuilder>{},
      home: Scaffold(
        appBar: actions != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: AppBar(
                  actions: actions,
                ),
              )
            : null,
        body: body,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M4 Bell & Presentation Adversarial Tests', () {
    // -------------------------------------------------------------------------
    // GROUP 1: MULTI-ROLE RBAC SUPPRESSION
    // -------------------------------------------------------------------------
    group('1. Multi-role bell visibility (all authenticated roles)', () {
      final nonAdminRoles = [
        {'role': 'nhanvien', 'name': 'Staff'},
        {'role': 'thungan', 'name': 'Cashier'},
        {'role': 'thukho', 'name': 'Warehouse keeper'},
        {'role': 'guest', 'name': 'Guest'},
        {'role': 'supervisor', 'name': 'Supervisor'},
        {'role': 'giamsat', 'name': 'Branch monitor'},
        {'role': 'cuahangtruong', 'name': 'Store manager'},
        {'role': '', 'name': 'Empty role'},
        {'role': 'unknown_role_xyz', 'name': 'Arbitrary unauthorized role'},
      ];

      for (final item in nonAdminRoles) {
        final role = item['role']!;
        final name = item['name']!;

        testWidgets(
            'RBAC: role "$role" ($name) sees the bell with unread badge',
            (tester) async {
          final user = UserAccount(
            username: 'user_${role.isEmpty ? "empty" : role}',
            role: role,
            storeId: 'store_001',
          );

          await tester.pumpWidget(
            _buildTestApp(
              overrides: [
                authProvider.overrideWith((ref) => _DynamicAuthNotifier(user)),
                unreadNotificationCountProvider.overrideWithValue(10),
              ],
              body: const Center(
                child: NotificationBellAction(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Every authenticated role (staff included) now sees the bell;
          // only unauthenticated sessions are suppressed.
          expect(find.byKey(const Key('notification_bell_action_button')),
              findsOneWidget,
              reason: 'Role $role must see the bell');
          expect(find.byType(Badge), findsOneWidget);
          expect(find.text('10'), findsOneWidget);
        });
      }

      testWidgets(
          'RBAC suppression: Unauthenticated (null user) renders strictly as SizedBox.shrink (zero size, zero IconButton)',
          (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith((ref) => _DynamicAuthNotifier(null)),
              unreadNotificationCountProvider.overrideWithValue(99),
            ],
            body: const Center(
              child: NotificationBellAction(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(IconButton), findsNothing);
        expect(find.byKey(const Key('notification_bell_action_button')),
            findsNothing);
        expect(find.byIcon(Icons.notifications), findsNothing);
        expect(find.byIcon(Icons.notifications_outlined), findsNothing);

        final bellFinder = find.byType(NotificationBellAction);
        expect(bellFinder, findsOneWidget);
        expect(tester.getSize(bellFinder), equals(Size.zero));

        final sizedBox = tester.widget<SizedBox>(
          find.descendant(of: bellFinder, matching: find.byType(SizedBox)),
        );
        expect(sizedBox.width, equals(0.0));
        expect(sizedBox.height, equals(0.0));
      });
    });

    // -------------------------------------------------------------------------
    // GROUP 2: ADMIN / OWNER BADGE THRESHOLDS
    // -------------------------------------------------------------------------
    group('2. Admin and Owner badge threshold boundaries', () {
      final adminRoles = ['admin', 'owner', 'ADMIN', 'Owner '];

      for (final adminRole in adminRoles) {
        testWidgets(
            'Role "$adminRole": Badge completely hidden when count = 0 (outline bell icon)',
            (tester) async {
          final user = UserAccount(
            username: 'super_user',
            role: adminRole,
            storeId: 'store_001',
          );

          await tester.pumpWidget(
            _buildTestApp(
              overrides: [
                authProvider.overrideWith((ref) => _DynamicAuthNotifier(user)),
                unreadNotificationCountProvider.overrideWithValue(0),
              ],
              actions: const [NotificationBellAction()],
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('notification_bell_action_button')),
              findsOneWidget);
          // Label is hidden
          final badge = tester.widget<Badge>(find.byType(Badge));
          expect(badge.isLabelVisible, isFalse);
          expect(find.text('0'), findsNothing);
          // Icon is outlined
          expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
          expect(find.byIcon(Icons.notifications), findsNothing);
        });

        testWidgets(
            'Role "$adminRole": Badge completely hidden when count < 0 (defensive negative count)',
            (tester) async {
          final user = UserAccount(
            username: 'super_user',
            role: adminRole,
            storeId: 'store_001',
          );

          await tester.pumpWidget(
            _buildTestApp(
              overrides: [
                authProvider.overrideWith((ref) => _DynamicAuthNotifier(user)),
                unreadNotificationCountProvider.overrideWithValue(-5),
              ],
              actions: const [NotificationBellAction()],
            ),
          );
          await tester.pumpAndSettle();

          final badge = tester.widget<Badge>(find.byType(Badge));
          expect(badge.isLabelVisible, isFalse);
          expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
        });
      }

      final exactCountCases = [1, 9, 99];
      for (final count in exactCountCases) {
        testWidgets('Admin badge renders exact count text "$count"',
            (tester) async {
          const user = UserAccount(
            username: 'admin',
            role: 'admin',
            storeId: 'store_001',
          );

          await tester.pumpWidget(
            _buildTestApp(
              overrides: [
                authProvider.overrideWith((ref) => _DynamicAuthNotifier(user)),
                unreadNotificationCountProvider.overrideWithValue(count),
              ],
              actions: const [NotificationBellAction()],
            ),
          );
          await tester.pumpAndSettle();

          final badge = tester.widget<Badge>(find.byType(Badge));
          expect(badge.isLabelVisible, isTrue);
          expect(find.text('$count'), findsOneWidget);
          expect(find.byIcon(Icons.notifications), findsOneWidget);
          expect(find.byIcon(Icons.notifications_outlined), findsNothing);
        });
      }

      final overflowCountCases = [100, 1000, 99999];
      for (final count in overflowCountCases) {
        testWidgets(
            'Admin/Owner badge renders "99+" for count = $count (caps properly)',
            (tester) async {
          const user = UserAccount(
            username: 'owner',
            role: 'owner',
            storeId: 'store_001',
          );

          await tester.pumpWidget(
            _buildTestApp(
              overrides: [
                authProvider.overrideWith((ref) => _DynamicAuthNotifier(user)),
                unreadNotificationCountProvider.overrideWithValue(count),
              ],
              actions: const [NotificationBellAction()],
            ),
          );
          await tester.pumpAndSettle();

          final badge = tester.widget<Badge>(find.byType(Badge));
          expect(badge.isLabelVisible, isTrue);
          expect(find.text('99+'), findsOneWidget);
          expect(find.text('$count'), findsNothing,
              reason: 'Raw count $count must not be displayed when > 99');
          expect(find.byIcon(Icons.notifications), findsOneWidget);
        });
      }
    });

    // -------------------------------------------------------------------------
    // GROUP 3: DYNAMIC ROLE MUTATION & REACTIVITY
    // -------------------------------------------------------------------------
    group('3. Dynamic role mutation in widget tree', () {
      testWidgets(
          'Dynamic transition: staff -> admin -> owner -> cashier -> null',
          (tester) async {
        final authNotifier = _DynamicAuthNotifier(
          const UserAccount(
            username: 'staff1',
            role: 'nhanvien',
            storeId: 'store_001',
          ),
        );

        final countNotifier = _DynamicCountNotifier(5);

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith((ref) => authNotifier),
              _testCountNotifierProvider.overrideWith((ref) => countNotifier),
              unreadNotificationCountProvider.overrideWith(
                  (ref) => ref.watch(_testCountNotifierProvider)),
            ],
            actions: const [NotificationBellAction()],
          ),
        );
        await tester.pumpAndSettle();

        // 1. Initial State: Staff -> Bell visible too
        expect(find.byKey(const Key('notification_bell_action_button')),
            findsOneWidget);
        expect(find.text('5'), findsOneWidget);

        // 2. Promote to Admin -> Bell immediately appears with unread count 5
        authNotifier.setUser(const UserAccount(
          username: 'admin1',
          role: 'admin',
          storeId: 'store_001',
        ));
        await tester.pump();
        expect(find.byKey(const Key('notification_bell_action_button')),
            findsOneWidget);
        expect(find.text('5'), findsOneWidget);

        // 3. Dynamically update unread count from 5 to 120 -> updates to 99+
        countNotifier.setCount(120);
        await tester.pump();
        expect(find.text('5'), findsNothing);
        expect(find.text('99+'), findsOneWidget);

        // 4. Update count to 0 -> badge hidden
        countNotifier.setCount(0);
        await tester.pump();
        expect(find.text('99+'), findsNothing);
        final badge = tester.widget<Badge>(find.byType(Badge));
        expect(badge.isLabelVisible, isFalse);
        expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);

        // 5. Change to Owner -> Bell remains visible
        authNotifier.setUser(const UserAccount(
          username: 'owner1',
          role: 'owner',
          storeId: 'store_001',
        ));
        await tester.pump();
        expect(find.byKey(const Key('notification_bell_action_button')),
            findsOneWidget);

        // 6. Demote to Cashier (thungan) -> Bell stays (all roles are notified)
        authNotifier.setUser(const UserAccount(
          username: 'cashier1',
          role: 'thungan',
          storeId: 'store_001',
        ));
        await tester.pump();
        expect(find.byKey(const Key('notification_bell_action_button')),
            findsOneWidget);

        // 7. Demote to null (logout) -> Bell remains hidden
        authNotifier.setUser(null);
        await tester.pump();
        expect(find.byKey(const Key('notification_bell_action_button')),
            findsNothing);
        expect(find.byType(IconButton), findsNothing);
      });
    });

    // -------------------------------------------------------------------------
    // GROUP 4: RAPID TAP STRESS & NAVIGATION INTEGRITY
    // -------------------------------------------------------------------------
    group('4. Rapid tap stress and navigation robustness', () {
      testWidgets(
          'Rapid tap stress: tapping bell 20 times rapidly does not crash or corrupt navigator',
          (tester) async {
        final navObserver = _TestNavigatorObserver();
        final fakeRepo = _FakeNotificationRepository();
        const adminUser = UserAccount(
          username: 'admin1',
          role: 'admin',
          storeId: 'store_001',
        );

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith((ref) => _DynamicAuthNotifier(adminUser)),
              unreadNotificationCountProvider.overrideWithValue(3),
              notificationRepositoryProvider.overrideWithValue(fakeRepo),
              currentStoreIdProvider.overrideWithValue('store_001'),
            ],
            navigatorObservers: [navObserver],
            actions: const [NotificationBellAction()],
            routes: {
              '/notifications': (context) => const NotificationsPage(),
            },
          ),
        );
        await tester.pumpAndSettle();

        final bellFinder =
            find.byKey(const Key('notification_bell_action_button'));
        expect(bellFinder, findsOneWidget);

        // Stress: Rapid taps 20 times with warnIfMissed: false
        for (int i = 0; i < 20; i++) {
          await tester.tap(bellFinder, warnIfMissed: false);
          // Micro pump simulating rapid finger burst within 1-5ms
          await tester.pump(const Duration(milliseconds: 2));
        }

        // Settle all route transitions
        await tester.pumpAndSettle();

        // Verification:
        // 1. NotificationsPage is successfully mounted and active
        expect(find.byType(NotificationsPage), findsOneWidget);

        // 2. Navigator must not crash
        expect(tester.takeException(), isNull);

        // 3. Pushed routes: initial route '/' + exactly one '/notifications' route
        final notifRoutes = navObserver.routes
            .where((r) => r.settings.name == '/notifications')
            .toList();
        expect(notifRoutes.length, equals(1),
            reason:
                'Rapid tapping must not double-push or spawn corrupt duplicate notification routes');
      });

      testWidgets(
          'Rapid concurrent invocations on NotificationNavigationHandler do not crash',
          (tester) async {
        final fakeRepo = _FakeNotificationRepository();
        final unreadNotification = NotificationItem(
          id: 'notif_rapid_1',
          storeId: 'store_001',
          title: 'Đơn hàng mới',
          body: 'Đơn #HD001',
          type: NotificationType.orderCreated,
          isRead: false,
          createdAt: DateTime.now(),
          targetRoute: 'invoice_detail',
          targetId: 'HD001',
        );

        late BuildContext capturedContext;
        late WidgetRef capturedRef;

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              notificationRepositoryProvider
                  .overrideWithValue(fakeRepo),
              currentStoreIdProvider.overrideWithValue('store_001'),
            ],
            body: Consumer(
              builder: (context, ref, _) {
                capturedContext = context;
                capturedRef = ref;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Trigger 20 concurrent invocations
        final futures = List.generate(
          20,
          (_) => NotificationNavigationHandler.handleTap(
            context: capturedContext,
            ref: capturedRef,
            notification: unreadNotification,
          ),
        );

        // All 20 must resolve safely without unhandled exceptions
        await expectLater(Future.wait(futures), completes);
        await tester.pumpAndSettle();

        // Repository markAsRead must have been called without database collision
        expect(fakeRepo.markAsReadCount, greaterThanOrEqualTo(1));
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'Fallback route handling: Bell falls back to MaterialPageRoute if named route fails',
          (tester) async {
        const adminUser = UserAccount(
          username: 'admin1',
          role: 'admin',
          storeId: 'store_001',
        );

        // MaterialApp WITHOUT '/notifications' in routes table
        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith((ref) => _DynamicAuthNotifier(adminUser)),
              unreadNotificationCountProvider.overrideWithValue(0),
            ],
            actions: const [NotificationBellAction()],
          ),
        );
        await tester.pumpAndSettle();

        final bellFinder =
            find.byKey(const Key('notification_bell_action_button'));
        expect(bellFinder, findsOneWidget);

        // Tap bell
        await tester.tap(bellFinder);
        await tester.pumpAndSettle();

        // Must still navigate to NotificationsPage via fallback MaterialPageRoute
        expect(find.byType(NotificationsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    // -------------------------------------------------------------------------
    // GROUP 5: TOOLTIP, THEMING, AND CUSTOM COLOR
    // -------------------------------------------------------------------------
    group('5. Theming, icon color, and tooltip', () {
      testWidgets(
          'Custom iconColor is respected when provided to NotificationBellAction',
          (tester) async {
        const adminUser = UserAccount(
          username: 'admin1',
          role: 'admin',
          storeId: 'store_001',
        );

        const customColor = Colors.amber;

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith((ref) => _DynamicAuthNotifier(adminUser)),
              unreadNotificationCountProvider.overrideWithValue(0),
            ],
            actions: const [
              NotificationBellAction(iconColor: customColor),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final iconWidget =
            tester.widget<Icon>(find.byIcon(Icons.notifications_outlined));
        expect(iconWidget.color, equals(customColor));
      });

      testWidgets(
          'Localized tooltip displays correctly in Vietnamese and English',
          (tester) async {
        const adminUser = UserAccount(
          username: 'admin1',
          role: 'admin',
          storeId: 'store_001',
        );

        // Vietnamese
        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith((ref) => _DynamicAuthNotifier(adminUser)),
              unreadNotificationCountProvider.overrideWithValue(0),
            ],
            locale: const Locale('vi'),
            actions: const [NotificationBellAction()],
          ),
        );
        await tester.pumpAndSettle();

        final iconButtonVi = tester.widget<IconButton>(
            find.byKey(const Key('notification_bell_action_button')));
        expect(iconButtonVi.tooltip, equals('Thông báo'));

        // English
        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith((ref) => _DynamicAuthNotifier(adminUser)),
              unreadNotificationCountProvider.overrideWithValue(0),
            ],
            locale: const Locale('en'),
            actions: const [NotificationBellAction()],
          ),
        );
        await tester.pumpAndSettle();

        final iconButtonEn = tester.widget<IconButton>(
            find.byKey(const Key('notification_bell_action_button')));
        expect(iconButtonEn.tooltip, equals('Notifications'));
      });
    });
  });
}
