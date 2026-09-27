import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../../fixtures/mock_report_data.dart';

/// Mutable fake auth notifier for dynamic transition testing
class MutableAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  MutableAuthNotifier([super.initialState]);

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

void main() {
  group('Empirical Challenger 2: Provider Reactivity & Scope Isolation Stress Tests', () {
    const supervisorUser = UserAccount(
      username: 'sup_master',
      displayName: 'Tổng giám sát',
      role: 'supervisor',
      storeId: 'store_001',
    );

    const staffUserStore1 = UserAccount(
      username: 'staff_hanoi',
      displayName: 'Thu ngân HN',
      role: 'nhanvien',
      storeId: 'store_001',
    );

    const staffUserStore2 = UserAccount(
      username: 'staff_hcm',
      displayName: 'Thu ngân HCM',
      role: 'nhanvien',
      storeId: 'store_002',
    );

    const adminUserStore1 = UserAccount(
      username: 'admin_branch1',
      displayName: 'Quản lý Chi nhánh 1',
      role: 'admin',
      storeId: 'store_001',
    );

    // =========================================================================
    // Stress Test Suite 1: Dynamic Auth State Transitions in Running Container
    // =========================================================================
    group('1. Dynamic Auth State Transitions in Running Container', () {
      test(
          '1.1 Switching auth from Supervisor to Staff dynamically resets and locks selectedBranchesProvider',
          () {
        final authNotifier = MutableAuthNotifier(supervisorUser);
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
          ],
        );
        addTearDown(container.dispose);

        // Initial supervisor state: full branch access
        expect(container.read(selectedBranchesProvider),
            containsAll(['store_001', 'store_002']));

        // Dynamic transition in running container: Supervisor -> Staff
        authNotifier.setUser(staffUserStore1);

        // Reactivity check: selectedBranchesProvider should immediately update to locked store_001
        expect(container.read(selectedBranchesProvider), equals(['store_001']));

        // Adversarial mutation attempts on Staff
        final notifier = container.read(selectedBranchesProvider.notifier);
        notifier.toggleBranch('store_002');
        expect(container.read(selectedBranchesProvider), equals(['store_001']),
            reason: 'Staff must not be able to toggle other branches');

        notifier.selectAll();
        expect(container.read(selectedBranchesProvider), equals(['store_001']),
            reason: 'Staff selectAll must be a no-op');

        notifier.clearAll();
        expect(container.read(selectedBranchesProvider), equals(['store_001']),
            reason: 'Staff clearAll must be a no-op');
      });

      test(
          '1.2 Switching auth from Staff to Supervisor unlocks branch toggling dynamically',
          () {
        final authNotifier = MutableAuthNotifier(staffUserStore1);
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
          ],
        );
        addTearDown(container.dispose);

        // Initial staff state: locked to store_001
        expect(container.read(selectedBranchesProvider), equals(['store_001']));

        // Dynamic transition: Staff -> Supervisor
        authNotifier.setUser(supervisorUser);

        // Reactivity check: state expands to all branches
        expect(container.read(selectedBranchesProvider),
            containsAll(['store_001', 'store_002']));

        // Supervisor can now mutate state
        final notifier = container.read(selectedBranchesProvider.notifier);
        notifier.toggleBranch('store_002');
        expect(container.read(selectedBranchesProvider), equals(['store_001']));

        notifier.toggleBranch('store_002');
        expect(container.read(selectedBranchesProvider),
            containsAll(['store_001', 'store_002']));
      });

      test(
          '1.3 Logging out from Staff resets to default unauthenticated state',
          () async {
        final authNotifier = MutableAuthNotifier(staffUserStore1);
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(selectedBranchesProvider), equals(['store_001']));

        // Logout
        await authNotifier.logout();

        // Unauthenticated fallback provides full mock branch list
        expect(container.read(selectedBranchesProvider),
            containsAll(['store_001', 'store_002']));
      });

      test(
          '1.4 Logging in as Staff from null state locks selected branches',
          () {
        final authNotifier = MutableAuthNotifier(null);
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(selectedBranchesProvider),
            containsAll(['store_001', 'store_002']));

        authNotifier.setUser(staffUserStore2);

        expect(container.read(selectedBranchesProvider), equals(['store_002']));
      });
    });

    // =========================================================================
    // Stress Test Suite 2: Downstream Provider Isolation (stockAlertSummaryProvider)
    // =========================================================================
    group('2. Downstream Provider Isolation & Alert Reactivity (stockAlertSummaryProvider)', () {
      final stressCatalog = [
        // Product 1: Out of stock at Branch 1 (0), but plentiful at Branch 2 (10)
        MockReportData.createProduct(
          id: 'prod_b1_zero_b2_ten',
          name: 'Áo thun Hà Nội hết hàng',
          costPrice: 100000.0,
          branchStocks: {'store_001': 0, 'store_002': 10},
        ),
        // Product 2: Low stock at Branch 1 (3 <= 5), but plentiful at Branch 2 (20)
        MockReportData.createProduct(
          id: 'prod_b1_low_b2_high',
          name: 'Quần Jeans Hà Nội sắp hết',
          costPrice: 200000.0,
          branchStocks: {'store_001': 3, 'store_002': 20},
        ),
        // Product 3: Plentiful at Branch 1 (20), but 0 at Branch 2
        MockReportData.createProduct(
          id: 'prod_b1_high_b2_zero',
          name: 'Váy Đầm Hà Nội còn nhiều',
          costPrice: 300000.0,
          branchStocks: {'store_001': 20, 'store_002': 0},
        ),
      ];

      test(
          '2.1 stockAlertSummaryProvider recomputes alerts reactively when auth switches from Supervisor to Staff',
          () async {
        final authNotifier = MutableAuthNotifier(supervisorUser);
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
            allStoresProductsProvider
                .overrideWith((ref) => Stream.value(stressCatalog)),
          ],
        );
        addTearDown(container.dispose);

        // Keep provider alive via subscription
        final sub = container.listen(stockAlertSummaryProvider, (_, __) {});
        addTearDown(sub.close);

        // Await stream data resolution
        await container.read(allStoresProductsProvider.future);

        // 1. Initial check as Supervisor (both store_001 and store_002 active)
        // Aggregated stocks:
        // prod 1: 0 + 10 = 10 (In stock)
        // prod 2: 3 + 20 = 23 (In stock)
        // prod 3: 20 + 0 = 20 (In stock)
        // Expected: outOfStock = 0, lowStock = 0, totalItems = 53
        final supervisorAlerts =
            container.read(stockAlertSummaryProvider).value!;
        expect(supervisorAlerts.outOfStockCount, equals(0));
        expect(supervisorAlerts.lowStockCount, equals(0));
        expect(supervisorAlerts.totalItemCount, equals(53));
        expect(
          supervisorAlerts.totalInventoryCost,
          equals((10 * 100000.0) + (23 * 200000.0) + (20 * 300000.0)),
        );

        // 2. Dynamic transition to Staff (locked to store_001 only)
        authNotifier.setUser(staffUserStore1);

        // 3. Reactivity check for Staff:
        // Branch 1 stocks:
        // prod 1: 0 (Out of stock!)
        // prod 2: 3 (Low stock! <= 5)
        // prod 3: 20 (In stock)
        // Expected: outOfStock = 1 (prod 1), lowStock = 1 (prod 2), totalItems = 23
        final staffAlerts = container.read(stockAlertSummaryProvider).value!;
        expect(staffAlerts.outOfStockCount, equals(1),
            reason: 'prod_b1_zero_b2_ten is out of stock in store_001');
        expect(staffAlerts.outOfStockProductIds,
            contains('prod_b1_zero_b2_ten'));
        expect(staffAlerts.lowStockCount, equals(1),
            reason: 'prod_b1_low_b2_high is low stock in store_001');
        expect(staffAlerts.lowStockProductIds,
            contains('prod_b1_low_b2_high'));
        expect(staffAlerts.totalItemCount, equals(23)); // 0 + 3 + 20
        expect(
          staffAlerts.totalInventoryCost,
          equals((0 * 100000.0) + (3 * 200000.0) + (20 * 300000.0)),
        );
      });

      test(
          '2.2 Hostile mutation attempts on selectedBranchesNotifier do not leak store_002 stock to Staff',
          () async {
        final authNotifier = MutableAuthNotifier(staffUserStore1);
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
            allStoresProductsProvider
                .overrideWith((ref) => Stream.value(stressCatalog)),
          ],
        );
        addTearDown(container.dispose);

        final sub = container.listen(stockAlertSummaryProvider, (_, __) {});
        addTearDown(sub.close);

        await container.read(allStoresProductsProvider.future);

        // Verify initial staff alert summary
        var staffAlerts = container.read(stockAlertSummaryProvider).value!;
        expect(staffAlerts.outOfStockCount, equals(1));
        expect(staffAlerts.lowStockCount, equals(1));
        expect(staffAlerts.totalItemCount, equals(23));

        // Attack: Rogue call to toggle store_002
        container
            .read(selectedBranchesProvider.notifier)
            .toggleBranch('store_002');

        staffAlerts = container.read(stockAlertSummaryProvider).value!;
        expect(staffAlerts.outOfStockCount, equals(1),
            reason: 'Data from store_002 must not leak into staff stock alerts');
        expect(staffAlerts.totalItemCount, equals(23));

        // Attack: Rogue call to selectAll
        container.read(selectedBranchesProvider.notifier).selectAll();

        staffAlerts = container.read(stockAlertSummaryProvider).value!;
        expect(staffAlerts.outOfStockCount, equals(1));
        expect(staffAlerts.totalItemCount, equals(23));
      });

      test(
          '2.3 Out-of-stock boundary and multi-branch isolation',
          () async {
        final boundaryCatalog = [
          MockReportData.createProduct(
            id: 'p_isolated_b1_zero',
            name: 'Sản phẩm hết hàng chi nhánh 1',
            costPrice: 50000.0,
            branchStocks: {'store_001': 0, 'store_002': 100},
          ),
          MockReportData.createProduct(
            id: 'p_isolated_b1_boundary5',
            name: 'Sản phẩm ngưỡng 5 tại chi nhánh 1',
            costPrice: 50000.0,
            branchStocks: {'store_001': 5, 'store_002': 100},
          ),
          MockReportData.createProduct(
            id: 'p_isolated_b1_boundary6',
            name: 'Sản phẩm ngưỡng 6 tại chi nhánh 1',
            costPrice: 50000.0,
            branchStocks: {'store_001': 6, 'store_002': 100},
          ),
        ];

        final authNotifier = MutableAuthNotifier(staffUserStore1);
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
            allStoresProductsProvider
                .overrideWith((ref) => Stream.value(boundaryCatalog)),
          ],
        );
        addTearDown(container.dispose);

        final sub = container.listen(stockAlertSummaryProvider, (_, __) {});
        addTearDown(sub.close);

        await container.read(allStoresProductsProvider.future);

        final alerts = container.read(stockAlertSummaryProvider).value!;
        expect(alerts.outOfStockCount, equals(1)); // p_isolated_b1_zero
        expect(alerts.lowStockCount, equals(1)); // p_isolated_b1_boundary5
        expect(alerts.totalItemCount, equals(11)); // 0 + 5 + 6
        expect(alerts.totalInventoryCost, equals(11 * 50000.0));
      });
    });

    // =========================================================================
    // Stress Test Suite 3: Current Store ID Scoping & Security Enforcement
    // =========================================================================
    group('3. Current Store ID Scoping & Security Enforcement', () {
      test('3.1 Staff with custom storeId enforces currentStoreIdProvider and resists store switcher', () {
        final authNotifier = MutableAuthNotifier(staffUserStore2);
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
          ],
        );
        addTearDown(container.dispose);

        // Staff user has storeId == 'store_002'
        expect(container.read(currentStoreIdProvider), equals('store_002'));

        // Attack: Trying to override selectedStoreIdProvider
        container.read(selectedStoreIdProvider.notifier).state = 'store_001';

        // currentStoreIdProvider must ignore selectedStoreIdProvider for staff (!canSwitchStore)
        expect(container.read(currentStoreIdProvider), equals('store_002'),
            reason: 'Staff must be strictly locked to their assigned storeId');
      });

      test('3.2 Admin with canSwitchStore obeys store switcher and accesses all branches', () {
        final authNotifier = MutableAuthNotifier(adminUserStore1);
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(currentStoreIdProvider), equals('store_001'));
        expect(container.read(selectedBranchesProvider), equals(['store_001', 'store_002']));

        // Admin can switch store via selectedStoreIdProvider
        container.read(selectedStoreIdProvider.notifier).state = 'store_002';
        expect(container.read(currentStoreIdProvider), equals('store_002'));
      });

      test('3.3 Supervisor with canSwitchStore obeys store switcher', () {
        final authNotifier = MutableAuthNotifier(supervisorUser);
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
          ],
        );
        addTearDown(container.dispose);

        // Default to user's primary store
        expect(container.read(currentStoreIdProvider), equals('store_001'));

        // Switch to store_002 affects supervisor since canSwitchStore == true
        container.read(selectedStoreIdProvider.notifier).state = 'store_002';
        expect(container.read(currentStoreIdProvider), equals('store_002'));

        // Reset to null
        container.read(selectedStoreIdProvider.notifier).state = null;
        expect(container.read(currentStoreIdProvider), equals('store_001'));
      });
    });

    // =========================================================================
    // Stress Test Suite 4: Domain Permissions Matrix & Pure Dart Invariants
    // =========================================================================
    group('4. Domain Permissions Matrix & Pure Dart Invariants', () {
      test('4.1 Role sanitization: handles irregular casing and whitespace', () {
        const adminWithSpaces = UserAccount(
          username: 'admin1',
          role: '  ADMIN  ',
          storeId: 'store_001',
        );
        expect(adminWithSpaces.isAdmin, isTrue);
        expect(adminWithSpaces.isStaff, isFalse);
        expect(adminWithSpaces.canViewDebtSummary, isTrue);
        expect(adminWithSpaces.canSwitchStore, isTrue);

        const supervisorMixed = UserAccount(
          username: 'sup1',
          role: 'SuperVisor',
          storeId: 'store_001',
        );
        expect(supervisorMixed.isSupervisor, isTrue);
        expect(supervisorMixed.isAdmin, isFalse);
        expect(supervisorMixed.isStaff, isFalse);
        expect(supervisorMixed.canViewDebtSummary, isTrue);
        expect(supervisorMixed.canSwitchStore, isTrue);

        const staffIrregular = UserAccount(
          username: 'staff1',
          role: ' NhanVien ',
          storeId: 'store_001',
        );
        expect(staffIrregular.isAdmin, isFalse);
        expect(staffIrregular.isStaff, isTrue);
        expect(staffIrregular.canViewDebtSummary, isFalse);
        expect(staffIrregular.canSwitchStore, isFalse);
      });

      test('4.2 canViewDebtSummary getter is strictly coupled to isAdmin', () {
        const staff = UserAccount(
          username: 'cashier',
          role: 'nhanvien',
          storeId: 'store_001',
        );
        expect(staff.canViewDebtSummary, isFalse);

        const admin = UserAccount(
          username: 'manager',
          role: 'admin',
          storeId: 'store_001',
        );
        expect(admin.canViewDebtSummary, isTrue);

        const supervisor = UserAccount(
          username: 'owner',
          role: 'supervisor',
          storeId: 'store_001',
        );
        expect(supervisor.canViewDebtSummary, isTrue);
      });
    });
  });
}
