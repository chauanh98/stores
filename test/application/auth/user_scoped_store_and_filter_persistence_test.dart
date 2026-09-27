import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/core/utils/store_resolver_helper.dart';
import 'package:stores/data/datasources/firebase/auth_remote_data_source.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/orders/controllers/invoices_filter_controller.dart';
import 'package:stores/presentation/reports/widgets/overview_header.dart';
import 'package:stores/presentation/settings/pages/more_page.dart';

class _MockAuthRemoteDataSource implements AuthRemoteDataSource {
  UserAccount? returnUser;
  bool shouldThrowNetworkError = false;
  String? lastLoginUsername;
  String? lastLoginPassword;

  @override
  Future<UserAccount?> login(String username, String password) async {
    lastLoginUsername = username;
    lastLoginPassword = password;
    if (shouldThrowNetworkError) {
      throw const AuthNetworkException('Mất kết nối mạng / timeout');
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

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier([super.initialState]);

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

class _FakeCustomerListNotifier extends CustomerListNotifier {
  @override
  Future<List<Customer>> build() async => [];
}

class _FakeSupplierListNotifier extends SupplierListNotifier {
  @override
  Future<List<Supplier>> build() async => [];
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Material(child: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const admin1 = UserAccount(
    username: 'admin1',
    displayName: 'Quản trị viên 1',
    role: 'admin',
    storeId: 'store_001',
  );

  const staff1 = UserAccount(
    username: 'staff1',
    displayName: 'Nhân viên 1',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const supervisor1 = UserAccount(
    username: 'sup1',
    displayName: 'Giám sát 1',
    role: 'supervisor',
    storeId: 'store_001',
  );

  final commonOverrides = [
    availableStoresProvider.overrideWith((ref) async => {
          'store_001': 'Chi nhánh Đông Thắng',
          'store_002': 'Chi nhánh Thới Bình',
        }),
    currentStoreNameProvider.overrideWith((ref) async {
      final id = ref.watch(currentStoreIdProvider);
      if (id == 'store_002') return 'Chi nhánh Thới Bình';
      return 'Chi nhánh Đông Thắng';
    }),
    allBranchesOrdersByDateRangeProvider
        .overrideWith((ref, range) => Stream.value(<Order>[])),
    customerListNotifierProvider
        .overrideWith(() => _FakeCustomerListNotifier()),
    supplierListNotifierProvider
        .overrideWith(() => _FakeSupplierListNotifier()),
    productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
    accountsListProvider
        .overrideWith((ref) => Stream.value(<UserAccount>[admin1])),
  ];

  group('Acceptance Criteria: Persistent Store Selection', () {
    testWidgets(
        'Admin switches store to store_002 at MorePage, persists to SharedPreferences, '
        'and survives fresh app restart (fresh ProviderScope)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final authNotifier = _FakeAuthNotifier(admin1);

      // Phase 1: Mount MorePage with admin1
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => authNotifier),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify currently store_001
      expect(find.text('Chi nhánh Đông Thắng'), findsWidgets);

      // Find Dropdown and select store_002 (Chi nhánh Thới Bình)
      final dropdownFinder = find.byType(DropdownButtonFormField<String>);
      expect(dropdownFinder, findsOneWidget);

      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chi nhánh Thới Bình').last);
      await tester.pumpAndSettle();

      // SnackBar displayed
      expect(find.text('Đã chuyển sang Chi nhánh Thới Bình'), findsOneWidget);

      // Verify SharedPreferences has selected_store_admin1 = 'store_002'
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_store_admin1'), 'store_002');

      // Phase 2: Simulate complete app exit & restart with a fresh ProviderScope
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _FakeAuthNotifier(admin1)),
          ],
          child: const Column(
            children: [
              OverviewHeader(),
              Expanded(child: MorePage()),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header and MorePage automatically display store_002 (Thới Bình) without resetting to store_001!
      expect(find.text('Chi nhánh Thới Bình'), findsWidgets);
    });

    test(
        'currentStoreIdProvider and selectedStoreIdProvider automatically hydrate store_002 on fresh container',
        () async {
      SharedPreferences.setMockInitialValues({
        'selected_store_admin1': 'store_002',
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(admin1)),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs, admin1.username),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Verify synchronous / microtask hydration
      expect(container.read(selectedStoreIdProvider), 'store_002');
      expect(container.read(currentStoreIdProvider), 'store_002');
      expect(container.read(selectedBranchesProvider), equals(['store_002']));
    });
  });

  group('Acceptance Criteria: Multi-Account Isolation Scenario', () {
    test(
        'Step 1 -> Step 2 -> Step 3: admin1, staff1, admin1 isolation with Zero cross-account contamination',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final authNotifier = _FakeAuthNotifier(null);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          filterStorageServiceProvider.overrideWith((ref) {
            final user = ref.watch(authProvider);
            return FilterStorageService(prefs, user?.username);
          }),
        ],
      );
      addTearDown(container.dispose);

      // -------------------------------------------------------------
      // BƯỚC 1: admin1 đăng nhập, chuyển cửa hàng sang store_002, đặt bộ lọc hóa đơn "debt"
      // -------------------------------------------------------------
      authNotifier.setUser(admin1);
      container.read(filterStorageServiceProvider); // initializes resolver

      // Admin switches store to store_002
      container.read(selectedStoreIdProvider.notifier).state = 'store_002';
      await container
          .read(filterStorageServiceProvider)
          .saveSelectedStore('store_002', 'admin1');

      expect(container.read(currentStoreIdProvider), 'store_002');

      // Admin sets invoice filter to debt
      container.read(invoicesFilterProvider.notifier).setDebtStatus('debt');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(invoicesFilterProvider).debtStatus, 'debt');

      // Verify SharedPreferences has admin1's keys
      expect(prefs.getString('selected_store_admin1'), 'store_002');
      expect(prefs.getString('filter_prefs_admin1_invoices'), isNotNull);

      // -------------------------------------------------------------
      // BƯỚC 2: admin1 đăng xuất; staff1 (thuộc store_001) đăng nhập
      // -------------------------------------------------------------
      // Admin logs out
      authNotifier.logout();
      container.read(selectedStoreIdProvider.notifier).state = null;

      // Staff1 logs in
      authNotifier.setUser(staff1);

      // Chi nhánh hoạt động của staff1 bắt buộc là store_001 (không bị nhiễm store_002)
      expect(container.read(currentStoreIdProvider), 'store_001');

      // Bộ lọc hóa đơn của staff1 là bộ lọc riêng của staff1 (mặc định "all")
      expect(container.read(invoicesFilterProvider).debtStatus, 'all');
      expect(container.read(invoicesFilterProvider).hasActiveFilters, isFalse);

      // -------------------------------------------------------------
      // BƯỚC 3: staff1 đăng xuất; admin1 đăng nhập lại
      // -------------------------------------------------------------
      // Staff1 logs out
      authNotifier.logout();
      container.read(selectedStoreIdProvider.notifier).state = null;

      // Admin1 logs back in
      authNotifier.setUser(admin1);

      // Chi nhánh của admin1 được phục hồi chính xác là store_002
      expect(container.read(currentStoreIdProvider), 'store_002');

      // Bộ lọc hóa đơn phục hồi chính xác "debt" ("Còn ghi nợ")
      expect(container.read(invoicesFilterProvider).debtStatus, 'debt');
    });

    test(
        'Supervisor is locked to assigned storeId and cannot be affected by admin stored selection',
        () async {
      SharedPreferences.setMockInitialValues({
        'selected_store_admin1': 'store_002',
      });

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisor1)),
        ],
      );
      addTearDown(container.dispose);

      // Supervisor primary store is store_001
      expect(container.read(currentStoreIdProvider), 'store_001');

      // Attempting to change selectedStoreIdProvider does not affect supervisor operating store
      container.read(selectedStoreIdProvider.notifier).state = 'store_002';
      expect(container.read(currentStoreIdProvider), 'store_001');
    });

    test(
        'Logout resets in-memory providers without deleting stored account preferences',
        () async {
      SharedPreferences.setMockInitialValues({
        'selected_store_admin1': 'store_002',
        'filter_prefs_admin1_invoices': jsonEncode({
          'version': 1,
          'debtStatus': 'debt',
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final authNotifier = _FakeAuthNotifier(admin1);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          filterStorageServiceProvider.overrideWith((ref) {
            final user = ref.watch(authProvider);
            return FilterStorageService(prefs, user?.username);
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentStoreIdProvider), 'store_002');
      expect(container.read(invoicesFilterProvider).debtStatus, 'debt');

      // Logout
      authNotifier.logout();
      container.read(selectedStoreIdProvider.notifier).state = null;

      // In-memory state reset
      expect(container.read(selectedStoreIdProvider), isNull);
      expect(container.read(currentStoreIdProvider), 'store_001');

      // SharedPreferences remains intact for admin1
      expect(prefs.getString('selected_store_admin1'), 'store_002');
      expect(prefs.getString('filter_prefs_admin1_invoices'), isNotNull);
    });

    test(
        'Automatic in-memory reset across Invoices, Customers, and Products filters upon logout',
        () async {
      SharedPreferences.setMockInitialValues({
        'filter_prefs_admin1_invoices': jsonEncode({
          'version': 1,
          'debtStatus': 'debt',
        }),
        'filter_prefs_admin1_customers': jsonEncode({
          'debtFilter': 'inDebt',
        }),
        'filter_prefs_admin1_products': jsonEncode({
          'category': 'Smartphones',
          'stockStatus': 'inStock',
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final authNotifier = _FakeAuthNotifier(admin1);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          filterStorageServiceProvider.overrideWith((ref) {
            final user = ref.watch(authProvider);
            return FilterStorageService(prefs, user?.username);
          }),
        ],
      );
      addTearDown(container.dispose);

      // Verify admin1 active filters hydrated
      expect(container.read(invoicesFilterProvider).debtStatus, 'debt');
      expect(container.read(customerDebtFilterProvider), CustomerDebtFilter.inDebt);
      expect(container.read(productCategoryFilterProvider), 'Smartphones');
      expect(container.read(productStockStatusFilterProvider), StockStatus.inStock);

      // Admin1 logs out
      authNotifier.logout();

      // All in-memory filters cleanly reset to defaults
      expect(container.read(invoicesFilterProvider).debtStatus, 'all');
      expect(container.read(customerDebtFilterProvider), CustomerDebtFilter.all);
      expect(container.read(productCategoryFilterProvider), 'All');
      expect(container.read(productStockStatusFilterProvider), StockStatus.all);

      // Disk caches for admin1 remain intact
      expect(prefs.getString('filter_prefs_admin1_invoices'), isNotNull);
      expect(prefs.getString('filter_prefs_admin1_customers'), isNotNull);
      expect(prefs.getString('filter_prefs_admin1_products'), isNotNull);
    });

    test(
        'Ordering robustness: reading filterStorageServiceProvider first registers reactive listener on login',
        () async {
      final prefs = await SharedPreferences.getInstance();
      setupFilterStorageResolver();

      final authNotifier = _FakeAuthNotifier(null);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          filterStorageServiceProvider.overrideWith((ref) {
            final user = ref.watch(authProvider);
            return FilterStorageService(prefs, user?.username);
          }),
        ],
      );
      addTearDown(container.dispose);

      // Read filter storage before login
      final storageBefore = container.read(filterStorageServiceProvider);
      expect(storageBefore.username, isNull);

      // User logs in
      authNotifier.setUser(admin1);

      // Storage reactively updates to admin1
      final storageAfter = container.read(filterStorageServiceProvider);
      expect(storageAfter.username, 'admin1');
    });

    test(
        'Adversarial edge case: Admin account with whitespace or special characters',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      const specialAdmin = UserAccount(
        username: 'admin/01 branch',
        displayName: 'Special Admin',
        role: 'admin',
        storeId: 'store_001',
      );

      final authNotifier = _FakeAuthNotifier(specialAdmin);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          filterStorageServiceProvider.overrideWith((ref) {
            final user = ref.watch(authProvider);
            return FilterStorageService(prefs, user?.username);
          }),
        ],
      );
      addTearDown(container.dispose);

      // Special admin switches store
      await container
          .read(filterStorageServiceProvider)
          .saveSelectedStore('store_002', specialAdmin.username);
      container.read(selectedStoreIdProvider.notifier).state = 'store_002';

      expect(container.read(currentStoreIdProvider), 'store_002');

      // Key was sanitized safely without raw slashes or unescaped spaces
      final expectedKey = FilterStorageService.resolveStoreKey(specialAdmin.username);
      expect(expectedKey, 'selected_store_admin%2F01%20branch');
      expect(prefs.getString(expectedKey), 'store_002');
    });

    test(
        'Overview Tab: Selected branches and revenue target store scope to store_002 upon Admin store switch',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final authNotifier = _FakeAuthNotifier(admin1);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          filterStorageServiceProvider.overrideWith((ref) {
            final user = ref.watch(authProvider);
            return FilterStorageService(prefs, user?.username);
          }),
        ],
      );
      addTearDown(container.dispose);

      // Initially, admin1 has not chosen a store -> defaults to all branches
      expect(container.read(selectedBranchesProvider), equals(['store_001', 'store_002']));

      // Admin1 switches store to store_002
      container.read(selectedStoreIdProvider.notifier).state = 'store_002';
      await container
          .read(filterStorageServiceProvider)
          .saveSelectedStore('store_002', admin1.username);

      // selectedBranchesProvider automatically re-scopes to ['store_002']
      expect(container.read(selectedBranchesProvider), equals(['store_002']));

      // Target store resolution for overview revenue report resolves strictly to ['store_002']
      final targetStoreIds = StoreResolverHelper.resolveTargetStoreIds(
        container.read(selectedBranchesProvider),
        currentStoreId: container.read(currentStoreIdProvider),
        user: container.read(authProvider),
        storeFilter: container.read(selectedStoreFilterProvider),
      );
      expect(targetStoreIds, equals(['store_002']));
    });

    test(
        'Multi-admin isolation: admin1 with store_002 does not contaminate new admin2 with no selection',
        () async {
      SharedPreferences.setMockInitialValues({
        'selected_store_admin1': 'store_002',
      });
      final prefs = await SharedPreferences.getInstance();

      const admin2 = UserAccount(
        username: 'admin2',
        displayName: 'Quản trị viên 2',
        role: 'admin',
        storeId: 'store_001',
      );

      final authNotifier = _FakeAuthNotifier(admin1);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          filterStorageServiceProvider.overrideWith((ref) {
            final user = ref.watch(authProvider);
            return FilterStorageService(prefs, user?.username);
          }),
        ],
      );
      addTearDown(container.dispose);

      // admin1 has store_002
      expect(container.read(currentStoreIdProvider), 'store_002');
      expect(container.read(selectedBranchesProvider), equals(['store_002']));

      // admin1 logs out
      authNotifier.logout();
      container.read(selectedStoreIdProvider.notifier).state = null;

      // admin2 logs in (has no stored store)
      authNotifier.setUser(admin2);

      // admin2 must NOT inherit admin1's store_002; defaults to store_001 & all branches
      expect(container.read(selectedStoreIdProvider), isNull);
      expect(container.read(currentStoreIdProvider), 'store_001');
      expect(container.read(selectedBranchesProvider), equals(['store_001', 'store_002']));
    });

    test(
        'Legacy migration: admin hydrates from legacy selected_store key if user-scoped key is absent',
        () async {
      SharedPreferences.setMockInitialValues({
        'selected_store': 'store_002',
      });
      final prefs = await SharedPreferences.getInstance();

      const legacyAdmin = UserAccount(
        username: 'admin',
        displayName: 'Legacy Admin',
        role: 'admin',
        storeId: 'store_001',
      );

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(legacyAdmin)),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs, legacyAdmin.username),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(selectedStoreIdProvider), 'store_002');
      expect(container.read(currentStoreIdProvider), 'store_002');
      expect(container.read(selectedBranchesProvider), equals(['store_002']));
    });
  });

  group('Acceptance Criteria: Auto-Login Session Persistence & Resilient Startup (R1)', () {
    test(
        'login() persists saved_user_account JSON along with saved_username and saved_password',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final mockDs = _MockAuthRemoteDataSource()..returnUser = admin1;

      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result =
          await container.read(authProvider.notifier).login('admin1', 'pass123');
      expect(result, isNull);

      expect(prefs.getString('saved_username'), 'admin1');
      expect(prefs.getString('saved_password'), 'pass123');
      final savedJson = prefs.getString('saved_user_account');
      expect(savedJson, isNotNull);

      final decoded = jsonDecode(savedJson!) as Map<String, dynamic>;
      expect(decoded['username'], 'admin1');
      expect(decoded['displayName'], 'Quản trị viên 1');
      expect(decoded['role'], 'admin');
      expect(decoded['storeId'], 'store_001');

      final user = container.read(authProvider);
      expect(user, isNotNull);
      expect(user!.username, 'admin1');
      expect(user.isAdmin, isTrue);
    });

    test(
        'Instant Startup Session: App startup restores UserAccount immediately from saved_user_account',
        () async {
      SharedPreferences.setMockInitialValues({
        'saved_user_account': jsonEncode(admin1.toJson()),
        'saved_username': 'admin1',
        'saved_password': 'pass123',
      });
      final prefs = await SharedPreferences.getInstance();
      final mockDs = _MockAuthRemoteDataSource()..returnUser = admin1;

      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Trigger lazy provider instantiation
      container.read(authProvider.notifier);

      // Microtask pump to let _tryAutoLogin restore cachedUser
      await Future<void>.delayed(Duration.zero);

      final user = container.read(authProvider);
      expect(user, isNotNull);
      expect(user!.username, 'admin1');
      expect(user.isAdmin, isTrue);
      expect(container.read(authLoadingProvider), isFalse);
    });

    test(
        'Resilient Auto-Login: Offline or network handshake timeout preserves saved session and credentials',
        () async {
      SharedPreferences.setMockInitialValues({
        'saved_user_account': jsonEncode(admin1.toJson()),
        'saved_username': 'admin1',
        'saved_password': 'pass123',
      });
      final prefs = await SharedPreferences.getInstance();
      final mockDs = _MockAuthRemoteDataSource()
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

      // Local session is preserved
      final user = container.read(authProvider);
      expect(user, isNotNull);
      expect(user!.username, 'admin1');

      // Credentials and saved_user_account are strictly NEVER wiped on network error
      expect(prefs.getString('saved_username'), 'admin1');
      expect(prefs.getString('saved_password'), 'pass123');
      expect(prefs.getString('saved_user_account'), isNotNull);
    });

    test(
        'Remote Auth Failure: When server explicitly rejects credentials (password changed / user deleted), wipes session',
        () async {
      SharedPreferences.setMockInitialValues({
        'saved_user_account': jsonEncode(admin1.toJson()),
        'saved_username': 'admin1',
        'saved_password': 'old_password',
      });
      final prefs = await SharedPreferences.getInstance();
      // Server responds with null (wrong password / account disabled)
      final mockDs = _MockAuthRemoteDataSource()..returnUser = null;

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

      // User session is wiped
      expect(container.read(authProvider), isNull);

      // SharedPreferences cleared of login credentials and session
      expect(prefs.getString('saved_username'), isNull);
      expect(prefs.getString('saved_password'), isNull);
      expect(prefs.getString('saved_user_account'), isNull);
    });

    test(
        'Active Logout: Explicit logout cleans up saved_user_account, username, and password from SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues({
        'saved_user_account': jsonEncode(admin1.toJson()),
        'saved_username': 'admin1',
        'saved_password': 'pass123',
      });
      final prefs = await SharedPreferences.getInstance();
      final mockDs = _MockAuthRemoteDataSource()..returnUser = admin1;

      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(authProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(authProvider), isNotNull);

      // User actively logs out
      await notifier.logout();

      expect(container.read(authProvider), isNull);
      expect(prefs.getString('saved_username'), isNull);
      expect(prefs.getString('saved_password'), isNull);
      expect(prefs.getString('saved_user_account'), isNull);
    });

    test(
        'Cold Start Frame 1: Synchronous user restoration on startup without waiting for async auto-login',
        () async {
      SharedPreferences.setMockInitialValues({
        'saved_user_account': jsonEncode(admin1.toJson()),
        'saved_user_session': jsonEncode(admin1.toJson()),
        'saved_username': 'admin1',
        'saved_password': 'pass123',
      });
      final prefs = await SharedPreferences.getInstance();
      FilterStorageService.setSharedPrefs(prefs);

      final container = ProviderContainer(
        overrides: [
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);

      // On the exact first microtask / frame 1, user is immediately non-null and loading is false!
      final immediateUser = container.read(authProvider);
      expect(immediateUser, isNotNull,
          reason: 'Cached user must be restored synchronously on frame 1');
      expect(immediateUser?.username, 'admin1');
      expect(container.read(authLoadingProvider), isFalse,
          reason: 'authLoadingProvider must be false on frame 1 when cached user exists');
    });

    test(
        'Immediate Login Commit: login() persists credentials to SharedPreferences immediately before store/filter hydration',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      FilterStorageService.setSharedPrefs(prefs);

      final mockDs = _MockAuthRemoteDataSource()..returnUser = admin1;
      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(mockDs),
          filterStorageServiceProvider.overrideWithValue(
            FilterStorageService(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(authProvider.notifier);
      final loginFuture = notifier.login('admin1', 'pass123');
      await loginFuture;

      // Ensure credentials were saved to disk
      expect(prefs.getString('saved_username'), 'admin1');
      expect(prefs.getString('saved_password'), 'pass123');
      expect(prefs.getString('saved_user_account'), isNotNull);
      expect(prefs.getString('saved_user_session'), isNotNull);
    });
  });
}
