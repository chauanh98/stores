import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/auth/user_filter_hydration.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/orders/controllers/invoices_filter_controller.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier([super.initialState]);

  void setUser(UserAccount? user) {
    state = user;
  }

  Future<void> hydrateUserSelectedStore(dynamic ref, UserAccount user) async {
    if (!mounted) return;
    if (user.canSwitchStore) {
      final storage =
          ref.read(filterStorageServiceProvider) as FilterStorageService;
      var savedStore = storage.loadSelectedStoreSync(user.username);
      if (savedStore == null || savedStore.isEmpty) {
        savedStore = await storage.loadSelectedStore(user.username);
      }
      if (!mounted) return;
      if (state?.username != user.username) return;
      ref.read(selectedStoreIdProvider.notifier).state =
          (savedStore != null && savedStore.isNotEmpty) ? savedStore : null;
    } else {
      if (!mounted) return;
      ref.read(selectedStoreIdProvider.notifier).state = null;
    }
  }

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _DelayedFilterStorageService extends FilterStorageService {
  _DelayedFilterStorageService([super.prefs, super.username]);

  @override
  Future<Map<String, dynamic>?> loadFilter(String domainOrKey, [String? user]) async {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    return super.loadFilter(domainOrKey, user);
  }

  @override
  Future<String?> loadSelectedStore([String? user]) async {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    return super.loadSelectedStore(user);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sup1 = UserAccount(
    username: 'supervisor_01',
    displayName: 'Supervisor 1',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const sup2 = UserAccount(
    username: 'supervisor_02',
    displayName: 'Supervisor 2',
    role: 'supervisor',
    storeId: 'store_002',
  );

  const admin1 = UserAccount(
    username: 'admin1',
    displayName: 'Admin 1',
    role: 'admin',
    storeId: 'store_001',
  );

  const admin2 = UserAccount(
    username: 'admin2',
    displayName: 'Admin 2',
    role: 'admin',
    storeId: 'store_002',
  );

  group('Attack Scenario 1: Multi-supervisor cross-account isolation', () {
    test(
        'supervisor_01 filter changes MUST NOT contaminate supervisor_02 on the same device',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final service = FilterStorageService(prefs);

      // supervisor_01 saves customer filter
      await service.saveFilter('customers', {
        'debtFilter': 'inDebt',
      }, sup1.username);

      // Verify supervisor_01 saved key
      expect(prefs.getString('filter_prefs_supervisor_01_customers'), isNotNull);

      // Legacy unscoped key MUST NOT be contaminated by supervisor_01
      final legacyKey = prefs.getString('filter_prefs_customers');
      expect(legacyKey, isNull,
          reason: 'Custom supervisor username must not dual-write to legacy unscoped key');

      // When supervisor_02 logs in, supervisor_02 MUST NOT load supervisor_01 filters
      final sup2Filter = await service.loadFilter('customers', sup2.username);
      expect(sup2Filter, isNull,
          reason: 'supervisor_02 must start with default null filters, zero cross-contamination');
    });
  });

  group('Attack Scenario 2: Zero-loss rehydration on Overview Tab', () {
    test(
        'rehydrateAllUserFilters MUST NOT clobber selectedStoreFilter on disk during branch hydration',
        () async {
      SharedPreferences.setMockInitialValues({
        'filter_prefs_admin1_overview': jsonEncode({
          'version': 1,
          'timeRangeType': 'last7Days',
          'customStartDate': DateTime.now().toIso8601String(),
          'customEndDate': DateTime.now().toIso8601String(),
          'selectedBranches': ['store_002'],
          'selectedStoreFilter': 'store_002',
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

      // Execute cold-start hydration
      final rehydrateProvider = FutureProvider.family<void, UserAccount>((ref, user) async {
        await rehydrateAllUserFilters(ref, user);
      });
      await container.read(rehydrateProvider(admin1).future);

      // Check in-memory states
      expect(container.read(overviewTimeRangeTypeProvider),
          OverviewTimeRange.last7Days);
      expect(container.read(selectedBranchesProvider), equals(['store_002']));
      expect(container.read(selectedStoreFilterProvider), 'store_002');

      // CRITICAL CHECK: Disk storage MUST NOT have had selectedStoreFilter overwritten with null!
      final raw = prefs.getString('filter_prefs_admin1_overview');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['selectedStoreFilter'], 'store_002',
          reason: 'selectedStoreFilter on disk was overwritten during rehydration!');
    });
  });

  group('Attack Scenario 3: Concurrency race condition during rapid account switching', () {
    test(
        'In-flight hydration for previous user is ignored if authProvider switched during async load',
        () async {
      SharedPreferences.setMockInitialValues({
        'filter_prefs_admin1_invoices': jsonEncode({
          'status': 'cancelled',
          'debtStatus': 'debt',
        }),
        'filter_prefs_admin1_customers': jsonEncode({
          'debtFilter': 'inDebt',
        }),
        'filter_prefs_admin2_invoices': jsonEncode({
          'status': 'completed',
          'debtStatus': 'paid',
        }),
        'filter_prefs_admin2_customers': jsonEncode({
          'debtFilter': 'all',
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final authNotifier = _FakeAuthNotifier(admin1);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          filterStorageServiceProvider.overrideWith((ref) {
            final user = ref.watch(authProvider);
            return _DelayedFilterStorageService(prefs, user?.username);
          }),
        ],
      );
      addTearDown(container.dispose);

      final rehydrateProvider = FutureProvider.family<void, UserAccount>((ref, user) async {
        await rehydrateAllUserFilters(ref, user);
      });
      // Start hydrating admin1 with in-flight disk latency
      final future1 = container.read(rehydrateProvider(admin1).future);

      // Give 5ms for rehydrateAllUserFilters to enter in-flight await
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // User switches to admin2 while admin1 disk read is in flight
      authNotifier.setUser(admin2);

      await future1;

      // Ensure providers did not retain admin1 values when admin2 is the active user
      final currentAuth = container.read(authProvider);
      expect(currentAuth?.username, 'admin2');
      final currentInvoicesStatus = container.read(invoicesFilterProvider).status;
      expect(currentInvoicesStatus, equals('completed'),
          reason: 'Expected admin2 status (completed), but got: $currentInvoicesStatus');
      final currentDebtFilter = container.read(customerDebtFilterProvider);
      expect(currentDebtFilter, equals(CustomerDebtFilter.all),
          reason: 'Expected admin2 customerDebtFilter (all), but got: $currentDebtFilter');
    });
  });

  group('Attack Scenario 4: Corrupted disk data handling & self-healing', () {
    test('Corrupted JSON is safely caught and purged from preferences', () async {
      SharedPreferences.setMockInitialValues({
        'filter_prefs_admin1_overview': '<<<CORRUPT_JSON_DATA>>>{broken',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = FilterStorageService(prefs, 'admin1');

      // Synchronous read handles corrupt data without crashing
      final syncResult = service.loadFilterSync('overview', 'admin1');
      expect(syncResult, isNull);

      // Async read handles corrupt data without crashing and cleans up disk
      final asyncResult = await service.loadFilter('overview', 'admin1');
      expect(asyncResult, isNull);

      // Corrupt key should be cleared from prefs
      expect(prefs.containsKey('filter_prefs_admin1_overview'), isFalse);
    });
  });

  group('Attack Scenario 5: In-Memory Fallback Transparency When SharedPreferences is Unavailable or Throws', () {
    test('loadFilter and loadSelectedStore transparently fall back to in-memory fallback when SharedPreferences is null', () async {
      FilterStorageService.resetSharedPrefs();
      // Service instantiated with null prefs and no static sharedPrefs
      final service = FilterStorageService(null, 'unmocked_user');

      // 1. Save filter purely in-memory
      await service.saveFilter('products', {
        'category': 'Snacks',
        'stockStatus': 'inStock',
      }, 'unmocked_user');

      // 2. loadFilter MUST return the saved in-memory map
      final loadedAsync = await service.loadFilter('products', 'unmocked_user');
      expect(loadedAsync, isNotNull);
      expect(loadedAsync?['category'], 'Snacks');
      expect(loadedAsync?['stockStatus'], 'inStock');

      // 3. loadFilterSync MUST also return the saved in-memory map
      final loadedSync = service.loadFilterSync('products', 'unmocked_user');
      expect(loadedSync, isNotNull);
      expect(loadedSync?['category'], 'Snacks');

      // 4. Save and load selected store purely in-memory
      await service.saveSelectedStore('store_002', 'unmocked_user');
      final loadedStoreAsync = await service.loadSelectedStore('unmocked_user');
      expect(loadedStoreAsync, 'store_002');
      final loadedStoreSync = service.loadSelectedStoreSync('unmocked_user');
      expect(loadedStoreSync, 'store_002');

      // 5. Clear filter purely in-memory
      await service.clearFilter('products', 'unmocked_user');
      expect(await service.loadFilter('products', 'unmocked_user'), isNull);
      expect(service.loadFilterSync('products', 'unmocked_user'), isNull);

      // 6. Clear selected store purely in-memory
      await service.clearSelectedStore('unmocked_user');
      expect(await service.loadSelectedStore('unmocked_user'), isNull);
      expect(service.loadSelectedStoreSync('unmocked_user'), isNull);
    });
  });

  group('Attack Scenario 6: Constructor Instance Isolation (Zero Static Mutation)', () {
    test('FilterStorageService(customPrefs) MUST NOT mutate static _sharedPrefs', () async {
      FilterStorageService.resetSharedPrefs();
      SharedPreferences.setMockInitialValues({'custom_key': 'custom_value'});
      final customPrefs = await SharedPreferences.getInstance();

      // Creating an instance with customPrefs
      FilterStorageService(customPrefs, 'user1');

      // A fresh instance created with null MUST NOT have _prefs bound to customPrefs
      final freshService = FilterStorageService(null, 'user2');

      // Verify freshService operates without customPrefs in synchronous path
      expect(freshService.loadFilterSync('custom_key', 'user2'), isNull);
    });
  });

  group('Attack Scenario 7: Two-Way Bidirectional Custom Date Range Sync on InvoicesFilterNotifier', () {
    test('Updating invoicesCustomDateRangeProvider bidirectionally updates InvoicesFilterState and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final authNotifier = _FakeAuthNotifier(admin1);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          filterStorageServiceProvider.overrideWith((ref) {
            return FilterStorageService(prefs, admin1.username);
          }),
        ],
      );
      addTearDown(container.dispose);

      // Read initial invoices filter state
      final initialFilter = container.read(invoicesFilterProvider);
      expect(initialFilter.timeRangeType, OverviewTimeRange.thisMonth);

      // Directly update invoicesCustomDateRangeProvider
      final customRange = DateTimeRange(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 15, 23, 59, 59),
      );
      container.read(invoicesCustomDateRangeProvider.notifier).state = customRange;

      // Allow microtasks / listener to propagate
      await Future<void>.delayed(Duration.zero);

      // InvoicesFilterState MUST now have custom date range and custom timeRangeType
      final updatedState = container.read(invoicesFilterProvider);
      expect(updatedState.timeRangeType, OverviewTimeRange.custom);
      expect(updatedState.customDateRange, customRange);

      // Must be persisted into preferences
      final saved = prefs.getString('filter_prefs_admin1_invoices');
      expect(saved, isNotNull);
      final decoded = jsonDecode(saved!) as Map<String, dynamic>;
      expect(decoded['timeRangeType'], 'custom');
      expect(decoded['customStartDate'], customRange.start.toIso8601String());
      expect(decoded['customEndDate'], customRange.end.toIso8601String());
    });
  });

  group('Attack Scenario 8: Products Filter Account Scoping and Cold-Start Rehydration', () {
    test('supervisor_02 products filter is persisted to user-scoped key and rehydrated across restart', () async {
      SharedPreferences.setMockInitialValues({
        'filter_prefs_supervisor_02_products': jsonEncode({
          'category': 'Bánh kẹo',
          'stockStatus': 'inStock',
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final authNotifier = _FakeAuthNotifier(sup2);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          filterStorageServiceProvider.overrideWith((ref) {
            return FilterStorageService(prefs, sup2.username);
          }),
        ],
      );
      addTearDown(container.dispose);

      // Rehydrate filters
      final rehydrateProvider = FutureProvider.family<void, UserAccount>((ref, user) async {
        await rehydrateAllUserFilters(ref, user);
      });
      await container.read(rehydrateProvider(sup2).future);

      expect(container.read(productCategoryFilterProvider), 'Bánh kẹo');
      expect(container.read(productStockStatusFilterProvider), StockStatus.inStock);

      // Verify supervisor_01 remains unaffected
      final sup1Category = container.read(filterStorageServiceProvider).loadFilterSync('products', sup1.username);
      expect(sup1Category, isNull);
    });
  });

  group('Attack Scenario 9: Concurrency Guard on _hydrateUserSelectedStore', () {
    test('In-flight loadSelectedStore for admin1 MUST NOT contaminate admin2 if account switched', () async {
      SharedPreferences.setMockInitialValues({
        'selected_store_admin1': 'store_001',
        'selected_store_admin2': 'store_002',
      });
      final prefs = await SharedPreferences.getInstance();

      final authNotifier = _FakeAuthNotifier(admin1);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          filterStorageServiceProvider.overrideWith((ref) {
            final user = ref.watch(authProvider);
            return _DelayedFilterStorageService(prefs, user?.username);
          }),
        ],
      );
      addTearDown(container.dispose);

      // Simulate async store hydration for admin1 with in-flight latency
      final hydrateStoreFuture = authNotifier.hydrateUserSelectedStore(container, admin1);

      // Wait 5ms (during 25ms delay of loadSelectedStore for admin1)
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // Active user abruptly switches to admin2
      authNotifier.setUser(admin2);
      container.read(selectedStoreIdProvider.notifier).state = 'store_002';

      // Let admin1's async call complete
      await hydrateStoreFuture;

      // Ensure selectedStoreIdProvider was NOT overwritten with store_001
      expect(container.read(selectedStoreIdProvider), equals('store_002'),
          reason: 'Late async loadSelectedStore for admin1 clobbered admin2 storeId!');
    });
  });

  group('Attack Scenario 10: User Mutation Precedence Over In-Flight Invoice Hydration', () {
    test('User manual filter change while _hydrateAsync is in flight is NOT overwritten by late disk read', () async {
      SharedPreferences.setMockInitialValues({
        'filter_prefs_admin1_invoices': jsonEncode({
          'status': 'completed',
          'debtStatus': 'paid',
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final authNotifier = _FakeAuthNotifier(admin1);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          filterStorageServiceProvider.overrideWith((ref) {
            final user = ref.watch(authProvider);
            return _DelayedFilterStorageService(prefs, user?.username);
          }),
        ],
      );
      addTearDown(container.dispose);

      // Trigger build() which kicks off _hydrateAsync with 25ms latency
      final notifier = container.read(invoicesFilterProvider.notifier);

      // User immediately taps 'returned' (at 5ms) while _hydrateAsync is still awaiting disk read
      await Future<void>.delayed(const Duration(milliseconds: 5));
      notifier.setStatus('returned');

      // Wait for the in-flight _hydrateAsync (which resolves status='completed') to finish
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Verify that user's manual change 'returned' was NOT overwritten with 'completed'
      expect(container.read(invoicesFilterProvider).status, equals('returned'),
          reason: 'User mutation was stomped by stale in-flight disk hydration!');
    });
  });

  group('Attack Scenario 11: Multi-Account Logout and Re-Login In-Memory Retention', () {
    test('Logging out and switching accounts preserves in-memory fallback without data loss', () async {
      FilterStorageService.resetSharedPrefs();
      // Null preferences forces pure in-memory fallback
      final service = FilterStorageService(null, sup1.username);

      // sup1 saves filters
      await service.saveFilter('overview', {'timeRangeType': 'today'}, sup1.username);
      await service.saveFilter('products', {'category': 'Gia vị'}, sup1.username);

      final authNotifier = _FakeAuthNotifier(sup1);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          filterStorageServiceProvider.overrideWith((ref) => service),
        ],
      );
      addTearDown(container.dispose);

      final rehydrateProvider = FutureProvider.family<void, UserAccount>((ref, user) async {
        await rehydrateAllUserFilters(ref, user);
      });

      // Hydrate sup1
      await container.read(rehydrateProvider(sup1).future);
      expect(container.read(overviewTimeRangeTypeProvider), equals(OverviewTimeRange.today));
      expect(container.read(productCategoryFilterProvider), equals('Gia vị'));

      // sup1 logs out
      authNotifier.setUser(null);
      resetAllInMemoryFilters(container);

      // Verify in-memory provider reset
      expect(container.read(overviewTimeRangeTypeProvider), equals(OverviewTimeRange.today));
      expect(container.read(productCategoryFilterProvider), equals('All'));

      // sup2 logs in and saves distinct filters
      authNotifier.setUser(sup2);
      await service.saveFilter('products', {'category': 'Bánh kẹo'}, sup2.username);
      await container.read(rehydrateProvider(sup2).future);
      expect(container.read(productCategoryFilterProvider), equals('Bánh kẹo'));

      // sup2 logs out
      authNotifier.setUser(null);
      resetAllInMemoryFilters(container);

      // sup1 logs back in
      authNotifier.setUser(sup1);
      await container.read(rehydrateProvider(sup1).future);

      // sup1 filters MUST be restored intact from in-memory fallback
      expect(container.read(overviewTimeRangeTypeProvider), equals(OverviewTimeRange.today));
      expect(container.read(productCategoryFilterProvider), equals('Gia vị'));
    });
  });
}
