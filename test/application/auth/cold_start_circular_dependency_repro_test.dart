import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/data/datasources/firebase/auth_remote_data_source.dart';
import 'package:stores/domain/entities/user_account.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cold Start & 2nd Launch Persistence Verification (No CircularDependencyError)', () {
    const adminUser = UserAccount(
      username: 'admin',
      displayName: 'Chủ cửa hàng',
      role: 'admin',
      storeId: 'store_001',
    );

    test('Frame 1 instant hydration and no CircularDependencyError with real AuthNotifier', () async {
      SharedPreferences.setMockInitialValues({
        'saved_username': 'admin',
        'saved_password': '123',
        'saved_user_account': jsonEncode(adminUser.toJson()),
        'selected_store_admin': 'store_002',
        'filter_prefs_admin_overview': jsonEncode({
          'timeRangeType': 'today',
          'selectedStoreFilter': 'store_002',
        }),
        'filter_prefs_admin_products': jsonEncode({
          'category': 'Đồ uống',
          'stockStatus': 'inStock',
        }),
        'filter_prefs_admin_customers': jsonEncode({
          'debtFilter': 'inDebt',
        }),
      });

      final prefs = await SharedPreferences.getInstance();
      FilterStorageService.setSharedPrefs(prefs);
      setupFilterStorageResolver();

      // Uses exact same setup as main.dart
      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(AuthRemoteDataSource()),
          filterStorageServiceProvider.overrideWith((ref) {
            return FilterStorageService(
              prefs,
              null,
              () {
                try {
                  return ref.read(authProvider)?.username;
                } catch (_) {
                  return null;
                }
              },
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      // 1. Frame 1 synchronous user session load
      final frame1User = container.read(authProvider);
      expect(frame1User, isNotNull, reason: 'User must be authenticated on Frame 1');
      expect(frame1User?.username, 'admin');

      // 2. Frame 1 synchronous store selection load
      final frame1Store = container.read(selectedStoreIdProvider);
      expect(frame1Store, 'store_002', reason: 'Store must be hydrated synchronously');

      final frame1CurrentStore = container.read(currentStoreIdProvider);
      expect(frame1CurrentStore, 'store_002');

      // 3. Frame 1 synchronous filter hydration across all tabs
      expect(container.read(overviewTimeRangeTypeProvider), OverviewTimeRange.today);
      expect(container.read(productCategoryFilterProvider), 'Đồ uống');
      expect(container.read(productStockStatusFilterProvider), StockStatus.inStock);
      expect(container.read(customerDebtFilterProvider), CustomerDebtFilter.inDebt);

      // 4. Wait for microtasks and background _tryAutoLogin
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 5. Ensure states remain intact after background auto-login completes
      expect(container.read(authProvider)?.username, 'admin');
      expect(container.read(selectedStoreIdProvider), 'store_002');
      expect(container.read(currentStoreIdProvider), 'store_002');
      expect(container.read(overviewTimeRangeTypeProvider), OverviewTimeRange.today);
      expect(container.read(productCategoryFilterProvider), 'Đồ uống');
      expect(container.read(productStockStatusFilterProvider), StockStatus.inStock);
      expect(container.read(customerDebtFilterProvider), CustomerDebtFilter.inDebt);
      expect(container.read(authLoadingProvider), isFalse);
    });

    test('Hot-restart / re-instantiation simulation does NOT trigger circular dependency', () async {
      SharedPreferences.setMockInitialValues({
        'saved_username': 'admin',
        'saved_password': '123',
        'saved_user_account': jsonEncode(adminUser.toJson()),
        'selected_store_admin': 'store_002',
      });

      final prefs = await SharedPreferences.getInstance();
      FilterStorageService.setSharedPrefs(prefs);
      setupFilterStorageResolver();

      for (int i = 0; i < 5; i++) {
        final container = ProviderContainer(
          overrides: [
            authRemoteDataSourceProvider.overrideWithValue(AuthRemoteDataSource()),
            filterStorageServiceProvider.overrideWith((ref) {
              return FilterStorageService(
                prefs,
                null,
                () {
                  try {
                    return ref.read(authProvider)?.username;
                  } catch (_) {
                    return null;
                  }
                },
              );
            }),
          ],
        );

        // Read all interconnected providers in varying order
        if (i % 2 == 0) {
          expect(container.read(currentStoreIdProvider), 'store_002');
          expect(container.read(authProvider)?.username, 'admin');
        } else {
          expect(container.read(authProvider)?.username, 'admin');
          expect(container.read(selectedStoreIdProvider), 'store_002');
          expect(container.read(currentStoreIdProvider), 'store_002');
        }

        await Future<void>.delayed(const Duration(milliseconds: 10));
        container.dispose();
      }
    });
  });
}
