import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/data/datasources/firebase/auth_remote_data_source.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/reports/widgets/overview_filter_bar.dart';
import 'package:stores/presentation/settings/pages/more_page.dart';

class _ControllableAuthDataSource extends AuthRemoteDataSource {
  Completer<UserAccount?>? nextLoginCompleter;
  Duration? loginDelay;
  UserAccount? returnUser;
  bool shouldThrowNetwork = false;
  String? currentDbPassword;
  String? updatedOldPassword;
  String? updatedNewPassword;
  String? updatedUsername;

  @override
  Future<UserAccount?> login(String username, String password) async {
    if (loginDelay != null) {
      await Future<void>.delayed(loginDelay!);
    }
    if (nextLoginCompleter != null) {
      return await nextLoginCompleter!.future;
    }
    if (shouldThrowNetwork) {
      throw const AuthNetworkException('Network down');
    }
    if (currentDbPassword != null && password != currentDbPassword) {
      return null;
    }
    return returnUser;
  }

  @override
  Future<void> updatePassword(
      String username, String oldPassword, String newPassword) async {
    updatedUsername = username;
    updatedOldPassword = oldPassword;
    updatedNewPassword = newPassword;
    currentDbPassword = newPassword;
  }
}

class _DelayableFilterStorageService extends FilterStorageService {
  _DelayableFilterStorageService(super.prefs);
  Duration? loadDelay;

  @override
  Future<Map<String, dynamic>?> loadFilter(String feature, [String? username]) async {
    if (loadDelay != null) {
      await Future<void>.delayed(loadDelay!);
    }
    return super.loadFilter(feature, username);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const admin1 = UserAccount(
    username: 'admin1',
    displayName: 'Admin One',
    role: 'admin',
    storeId: 'store_001',
  );

  const user2 = UserAccount(
    username: 'user2',
    displayName: 'User Two',
    role: 'nhanvien',
    storeId: 'store_002',
  );

  group('Reviewer R3 Adversarial: Auth & Session Persistence Edge Cases', () {
    test(
        'R3-Bug1: Calling logout() while login() is in-flight must NOT persist credentials or resurrect session',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final mockDs = _ControllableAuthDataSource();
      final loginCompleter = Completer<UserAccount?>();
      mockDs.nextLoginCompleter = loginCompleter;

      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);

      final authNotifier = container.read(authProvider.notifier);

      // Start login for admin1
      final loginFuture = authNotifier.login('admin1', 'pass123');

      // While login is waiting for server response, user decides to logout / cancel
      await authNotifier.logout();

      // Now server completes login
      loginCompleter.complete(admin1);
      await loginFuture;

      // State and SharedPreferences must NOT be resurrected
      expect(container.read(authProvider), isNull,
          reason: 'State must remain null after logout()');
      expect(prefs.getString('saved_username'), isNull,
          reason: 'saved_username must not be written if logout() was called');
      expect(prefs.getString('saved_password'), isNull,
          reason: 'saved_password must not be written if logout() was called');
      expect(prefs.getString('saved_user_account'), isNull,
          reason: 'saved_user_account must not be written if logout() was called');
      expect(prefs.getString('saved_user_session'), isNull,
          reason: 'saved_user_session must not be written if logout() was called');
    });

    test(
        'R3-Bug1b: Calling logout() while login() is awaiting filter rehydration must NOT persist credentials to SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final mockDs = _ControllableAuthDataSource()..returnUser = admin1;
      final delayableStorage = _DelayableFilterStorageService(prefs)
        ..loadDelay = const Duration(milliseconds: 50);

      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(delayableStorage),
        ],
      );
      addTearDown(container.dispose);

      final authNotifier = container.read(authProvider.notifier);

      // Start login
      final loginFuture = authNotifier.login('admin1', 'pass123');

      // Wait 10ms so _hydrateUserSelectedStore completes and execution is inside rehydrateAllUserFilters
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // User triggers logout
      await authNotifier.logout();

      // Wait for login to complete
      await loginFuture;

      // State and SharedPreferences must NOT be resurrected
      expect(container.read(authProvider), isNull,
          reason: 'State must remain null after logout()');
      expect(prefs.getString('saved_username'), isNull,
          reason: 'saved_username must not be persisted if logout() occurred during rehydration');
      expect(prefs.getString('saved_password'), isNull,
          reason: 'saved_password must not be persisted if logout() occurred during rehydration');
      expect(prefs.getString('saved_user_account'), isNull,
          reason: 'saved_user_account must not be persisted if logout() occurred during rehydration');
      expect(prefs.getString('saved_user_session'), isNull,
          reason: 'saved_user_session must not be persisted if logout() occurred during rehydration');
    });

    test(
        'R3-Bug2: Account deactivation in _tryAutoLogin() must NOT clobber a subsequent login() by another user',
        () async {
      // Setup initial session for admin1
      SharedPreferences.setMockInitialValues({
        'saved_user_account': jsonEncode(admin1.toJson()),
        'saved_user_session': jsonEncode(admin1.toJson()),
        'saved_username': 'admin1',
        'saved_password': 'old_password',
      });
      final prefs = await SharedPreferences.getInstance();

      final mockDs = _ControllableAuthDataSource();
      // admin1 revalidation will be delayed and return null (account deactivated or password changed remotely)
      final autoLoginCompleter = Completer<UserAccount?>();
      mockDs.nextLoginCompleter = autoLoginCompleter;

      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);

      final authNotifier = container.read(authProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Instant startup restores admin1
      expect(container.read(authProvider)?.username, 'admin1');

      // Now user switches accounts to user2 before admin1 auto-login finishes
      mockDs.nextLoginCompleter = null;
      mockDs.returnUser = user2;
      final loginUser2Future = authNotifier.login('user2', 'new_pass');
      await loginUser2Future;

      expect(container.read(authProvider)?.username, 'user2');
      expect(prefs.getString('saved_username'), 'user2');

      // Now admin1's delayed revalidation finishes returning null
      autoLoginCompleter.complete(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // user2 session must NOT be clobbered or wiped by admin1's auto-login completion
      expect(container.read(authProvider)?.username, 'user2',
          reason: 'user2 must remain active even after admin1 background revalidation returns null');
      expect(prefs.getString('saved_username'), 'user2');
      expect(prefs.getString('saved_user_account'), isNotNull);
    });

    test(
        'R3-Bug3: Changing password in app must keep saved_password in SharedPreferences in sync so session is not wiped on 2nd launch',
        () async {
      SharedPreferences.setMockInitialValues({
        'saved_user_account': jsonEncode(admin1.toJson()),
        'saved_user_session': jsonEncode(admin1.toJson()),
        'saved_username': 'admin1',
        'saved_password': 'initial_password',
      });
      final prefs = await SharedPreferences.getInstance();

      final mockDs = _ControllableAuthDataSource()
        ..currentDbPassword = 'initial_password'
        ..returnUser = admin1;

      // When app starts 1st time, auto-login revalidates successfully
      final container1 = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      final authNotifier1 = container1.read(authProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container1.read(authProvider)?.username, 'admin1');

      // User changes password in app (both remote DB and local saved_password)
      await mockDs.updatePassword('admin1', 'initial_password', 'brand_new_secret_password');
      await authNotifier1.updateSavedPassword('brand_new_secret_password');
      // When app reboots:
      container1.dispose();

      final container2 = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container2.dispose);

      // Start auto-login on 2nd launch
      container2.read(authProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // User should remain logged in, NOT wiped out!
      expect(container2.read(authProvider)?.username, 'admin1',
          reason: 'User session must survive password change across app restarts');
      expect(prefs.getString('saved_password'), 'brand_new_secret_password');
    });

    test(
        'R3-EdgeCase: Username with different casing or leading/trailing whitespace restores successfully',
        () async {
      SharedPreferences.setMockInitialValues({
        'saved_user_account': jsonEncode(admin1.toJson()),
        'saved_user_session': jsonEncode(admin1.toJson()),
        'saved_username': '  ADMIN1  ',
        'saved_password': 'password123',
      });
      final prefs = await SharedPreferences.getInstance();

      final mockDs = _ControllableAuthDataSource()
        ..shouldThrowNetwork = true; // offline scenario

      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Start auto-login
      container.read(authProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(authProvider)?.username, 'admin1',
          reason: 'Casing differences and whitespace in saved_username should not reject valid cached session');
    });

    test(
        'R3-EdgeCase: Rapid double login() invocation completes cleanly without corruption',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final mockDs = _ControllableAuthDataSource()
        ..loginDelay = const Duration(milliseconds: 20)
        ..returnUser = admin1;

      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);

      final authNotifier = container.read(authProvider.notifier);

      // Fire two logins concurrently (rapid double tap)
      final f1 = authNotifier.login('admin1', 'pass1');
      final f2 = authNotifier.login('admin1', 'pass1');

      await Future.wait([f1, f2]);

      expect(container.read(authProvider)?.username, 'admin1');
      expect(prefs.getString('saved_username'), 'admin1');
      expect(prefs.getString('saved_user_account'), isNotNull);
    });
  });

  group('Reviewer R3 Adversarial: OverviewFilterBar Layout & Accessibility Stress', () {
    testWidgets(
        'R3-UI1: OverviewFilterBar at extreme font scale (textScaler = 2.5) on 320px width has 0 overflow',
        (tester) async {
      final mockDs = _ControllableAuthDataSource()..returnUser = admin1;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRemoteDataSourceProvider.overrideWithValue(mockDs),
            authProvider.overrideWith((ref) {
              final n = AuthNotifier(mockDs, ref);
              n.state = admin1;
              return n;
            }),
            filterStorageServiceProvider.overrideWithValue(
              FilterStorageService(prefs),
            ),
            overviewTimeRangeTypeProvider
                .overrideWith((ref) => OverviewTimeRange.today),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('vi')],
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(320, 600),
                textScaler: TextScaler.linear(2.5), // High accessibility font scale
              ),
              child: Scaffold(
                body: OverviewFilterBar(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'OverviewFilterBar must not throw overflow or render exceptions under 2.5x font scale on 320px width');
      expect(find.byType(OverviewFilterBar), findsOneWidget);
    });

    testWidgets(
        'R3-UI2: OverviewFilterBar with custom date range and active filters has 0 overflow across multiple widths',
        (tester) async {
      final mockDs = _ControllableAuthDataSource()..returnUser = admin1;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final widths = [280.0, 320.0, 360.0, 375.0, 390.0, 412.0];

      for (final w in widths) {
        tester.view.physicalSize = Size(w, 600);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRemoteDataSourceProvider.overrideWithValue(mockDs),
              authProvider.overrideWith((ref) {
                final n = AuthNotifier(mockDs, ref);
                n.state = admin1;
                return n;
              }),
              filterStorageServiceProvider.overrideWithValue(
                FilterStorageService(prefs),
              ),
              overviewTimeRangeTypeProvider
                  .overrideWith((ref) => OverviewTimeRange.custom),
              overviewCustomDateRangeProvider.overrideWith(
                (ref) => DateTimeRange(
                  start: DateTime(2026, 1, 1),
                  end: DateTime(2026, 12, 31),
                ),
              ),
              selectedBranchesProvider.overrideWith(
                (ref) => SelectedBranchesNotifier(admin1, ['store_001'], ref),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('vi')],
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(w, 600),
                  textScaler: const TextScaler.linear(1.3),
                ),
                child: const Scaffold(
                  body: OverviewFilterBar(),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'OverviewFilterBar must not overflow at width $w with custom date range');
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets(
        'R3-UI3: Changing password in MorePage updates saved_password in SharedPreferences for subsequent auto-login',
        (tester) async {
      final mockDs = _ControllableAuthDataSource()..returnUser = admin1;
      SharedPreferences.setMockInitialValues({
        'saved_user_account': jsonEncode(admin1.toJson()),
        'saved_user_session': jsonEncode(admin1.toJson()),
        'saved_username': 'admin1',
        'saved_password': 'old_password',
      });
      final prefs = await SharedPreferences.getInstance();

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRemoteDataSourceProvider.overrideWithValue(mockDs),
            authProvider.overrideWith((ref) {
              final n = AuthNotifier(mockDs, ref);
              n.state = admin1;
              return n;
            }),
            filterStorageServiceProvider.overrideWithValue(
              FilterStorageService(prefs),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('vi')],
            home: MorePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Ensure "Đổi mật khẩu" tile is visible and tap it
      await tester.ensureVisible(find.text('Đổi mật khẩu'));
      await tester.tap(find.text('Đổi mật khẩu'));
      await tester.pumpAndSettle();

      expect(find.text('Đổi Mật Khẩu'), findsOneWidget);

      final oldPassField = find.widgetWithText(TextFormField, 'Mật khẩu hiện tại');
      final newPassField = find.widgetWithText(TextFormField, 'Mật khẩu mới');
      final confirmPassField = find.widgetWithText(TextFormField, 'Xác nhận mật khẩu mới');

      await tester.enterText(oldPassField, 'old_password');
      await tester.enterText(newPassField, 'new_super_secret');
      await tester.enterText(confirmPassField, 'new_super_secret');

      await tester.tap(find.text('Lưu mật khẩu'));
      await tester.pumpAndSettle();

      expect(mockDs.updatedNewPassword, 'new_super_secret');
      expect(prefs.getString('saved_password'), 'new_super_secret',
          reason: 'saved_password must be updated in SharedPreferences by MorePage password change');
    });
  });
}
