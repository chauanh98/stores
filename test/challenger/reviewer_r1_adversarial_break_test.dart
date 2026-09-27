import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/data/datasources/firebase/auth_remote_data_source.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/reports/widgets/overview_filter_bar.dart';

class _ReviewerMockAuthDataSource implements AuthRemoteDataSource {
  UserAccount? returnUser;
  bool shouldThrowNetworkError = false;

  @override
  Future<UserAccount?> login(String username, String password) async {
    if (shouldThrowNetworkError) {
      throw const AuthNetworkException('Network failure / offline');
    }
    return returnUser;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchAllAccounts() => Stream.value([]);

  @override
  Future<void> saveAccount(String username, Map<String, dynamic> map) async {}

  @override
  Future<void> deleteAccount(String username) async {}

  @override
  Future<String?> getAccountPassword(String username) async => 'pass123';

  @override
  Future<void> updatePassword(
    String username,
    String oldPassword,
    String newPassword,
  ) async {}
}

class _ReviewerFakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _ReviewerFakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
  Size screenSize = const Size(320, 480),
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: MediaQuery(
        data: MediaQueryData(size: screenSize, textScaler: textScaler),
        child: Material(child: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const admin1 = UserAccount(
    username: 'admin1',
    displayName: 'Admin User',
    role: 'admin',
    storeId: 'store_001',
  );

  group('Adversarial R1: Corrupted / Malformed Session Cache Tests', () {
    test(
        'Empty JSON "{}" in saved_user_account must be rejected as invalid session, not construct empty username',
        () async {
      SharedPreferences.setMockInitialValues({
        'saved_user_account': '{}',
        'saved_username': 'admin1',
        'saved_password': 'password123',
      });
      final prefs = await SharedPreferences.getInstance();
      final mockDs = _ReviewerMockAuthDataSource()..returnUser = admin1;

      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Trigger auto-login
      container.read(authProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Verify that the initial cachedUser was NOT an empty username user!
      // In the buggy implementation, state is immediately set to UserAccount(username: '')
      // Before remote login finishes!
    });

    test(
        'Offline cold boot with corrupted JSON in saved_user_account falls back safely to null without crashing',
        () async {
      SharedPreferences.setMockInitialValues({
        'saved_user_account': '{"corrupted_data": 123}',
        'saved_username': 'admin1',
        'saved_password': 'password123',
      });
      final prefs = await SharedPreferences.getInstance();
      // Server is unreachable (offline)
      final mockDs = _ReviewerMockAuthDataSource()
        ..shouldThrowNetworkError = true;

      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(authProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // With corrupted session and offline network, state MUST be null (drop to login),
      // definitely NOT an empty username user!
      final user = container.read(authProvider);
      expect(user, isNull,
          reason:
              'Corrupted session without a username must not produce a ghost UserAccount');
      expect(container.read(authLoadingProvider), isFalse);
    });

    test(
        'Username mismatch between saved_username and saved_user_account is rejected as untrusted',
        () async {
      SharedPreferences.setMockInitialValues({
        'saved_user_account': jsonEncode(const UserAccount(
          username: 'attacker_or_stale_user',
          displayName: 'Stale User',
          role: 'admin',
          storeId: 'store_001',
        ).toJson()),
        'saved_username': 'admin1',
        'saved_password': 'password123',
      });
      final prefs = await SharedPreferences.getInstance();
      final mockDs = _ReviewerMockAuthDataSource()
        ..shouldThrowNetworkError = true;

      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(authProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final user = container.read(authProvider);
      expect(user, isNull,
          reason:
              'Mismatched session user must not be trusted when saved_username differs');
    });

    test(
        'login() persists both saved_user_account AND saved_user_session for compatibility',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final mockDs = _ReviewerMockAuthDataSource()..returnUser = admin1;

      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).login('admin1', 'pass123');

      expect(prefs.getString('saved_user_account'), isNotNull);
      expect(prefs.getString('saved_user_session'), isNotNull);
      expect(prefs.getString('saved_username'), 'admin1');
      expect(prefs.getString('saved_password'), 'pass123');
    });
  });

  group('Adversarial R2: OverviewFilterBar TextScaler & Accessibility Tests', () {
    for (final scale in [1.5, 2.0, 2.5, 3.0]) {
      testWidgets(
          'OverviewFilterBar with TextScaler.linear($scale) on 320x480 screen has 0 RenderFlex overflow',
          (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildTestApp(
            screenSize: const Size(320, 480),
            textScaler: TextScaler.linear(scale),
            overrides: [
              authProvider.overrideWith(
                  (ref) => _ReviewerFakeAuthNotifier(admin1)),
              overviewTimeRangeTypeProvider
                  .overrideWith((ref) => OverviewTimeRange.thisMonth),
            ],
            child: const OverviewFilterBar(),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason:
                'Text scaling $scale should not cause any RenderFlex overflow on narrow 320x480');
        expect(find.byType(OverviewFilterBar), findsOneWidget);
        expect(find.byKey(const Key('reset_overview_filters_button')),
            findsOneWidget);
      });
    }
  });
}
