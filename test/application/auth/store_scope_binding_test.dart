import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/user_account.dart';

void main() {
  group('SelectedBranchesNotifier Unit Tests', () {
    test('Staff user: auto-binds to single branch and locks mutations', () {
      const staffUser = UserAccount(
        username: 'staff_1',
        displayName: 'Nhân viên 1',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      final notifierProvider =
          StateNotifierProvider<SelectedBranchesNotifier, List<String>>(
        (ref) => SelectedBranchesNotifier(staffUser),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(notifierProvider), equals(['store_001']));

      // Attempting to toggle branch should have no effect
      container.read(notifierProvider.notifier).toggleBranch('store_002');
      expect(container.read(notifierProvider), equals(['store_001']));

      container.read(notifierProvider.notifier).toggleBranch('store_001');
      expect(container.read(notifierProvider), equals(['store_001']));

      // Attempting to select all should have no effect
      container.read(notifierProvider.notifier).selectAll();
      expect(container.read(notifierProvider), equals(['store_001']));

      // Attempting to clear all should have no effect
      container.read(notifierProvider.notifier).clearAll();
      expect(container.read(notifierProvider), equals(['store_001']));
    });

    test('Supervisor user: initialized with all branches and allows mutations', () {
      const supervisorUser = UserAccount(
        username: 'sup_1',
        displayName: 'Giám sát viên',
        role: 'supervisor',
        storeId: 'store_001',
      );

      final notifierProvider =
          StateNotifierProvider<SelectedBranchesNotifier, List<String>>(
        (ref) => SelectedBranchesNotifier(supervisorUser),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(notifierProvider), equals(['store_001', 'store_002']));

      // Toggle off store_002
      container.read(notifierProvider.notifier).toggleBranch('store_002');
      expect(container.read(notifierProvider), equals(['store_001']));

      // Toggle off store_001 when it is the only selected branch: should keep at least 1 branch
      container.read(notifierProvider.notifier).toggleBranch('store_001');
      expect(container.read(notifierProvider), equals(['store_001']));

      // Toggle store_002 back on
      container.read(notifierProvider.notifier).toggleBranch('store_002');
      expect(container.read(notifierProvider), containsAll(['store_001', 'store_002']));

      // Clear all resets to first branch
      container.read(notifierProvider.notifier).clearAll();
      expect(container.read(notifierProvider), equals(['store_001']));

      // Select all selects all branches
      container.read(notifierProvider.notifier).selectAll();
      expect(container.read(notifierProvider), equals(['store_001', 'store_002']));
    });

    test('Admin user: initialized with all branches and allows mutations', () {
      const adminUser = UserAccount(
        username: 'admin_1',
        displayName: 'Quản trị viên',
        role: 'admin',
        storeId: 'store_001',
      );

      final notifierProvider =
          StateNotifierProvider<SelectedBranchesNotifier, List<String>>(
        (ref) => SelectedBranchesNotifier(adminUser),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(notifierProvider), equals(['store_001', 'store_002']));

      // Toggle off store_002
      container.read(notifierProvider.notifier).toggleBranch('store_002');
      expect(container.read(notifierProvider), equals(['store_001']));

      // Toggle store_002 back on
      container.read(notifierProvider.notifier).toggleBranch('store_002');
      expect(container.read(notifierProvider), containsAll(['store_001', 'store_002']));

      // Clear all resets to first branch
      container.read(notifierProvider.notifier).clearAll();
      expect(container.read(notifierProvider), equals(['store_001']));

      // Select all selects all branches
      container.read(notifierProvider.notifier).selectAll();
      expect(container.read(notifierProvider), equals(['store_001', 'store_002']));
    });

    test('Null user (unauthenticated / default): full access and mutations allowed', () {
      final notifierProvider =
          StateNotifierProvider<SelectedBranchesNotifier, List<String>>(
        (ref) => SelectedBranchesNotifier(null),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(notifierProvider), equals(['store_001', 'store_002']));

      container.read(notifierProvider.notifier).toggleBranch('store_002');
      expect(container.read(notifierProvider), equals(['store_001']));

      container.read(notifierProvider.notifier).selectAll();
      expect(container.read(notifierProvider), equals(['store_001', 'store_002']));
    });
  });

  group('selectedBranchesProvider with Riverpod ProviderContainer', () {
    test('Reads locked branch for staff user via authProvider override', () {
      const staffUser = UserAccount(
        username: 'staff_pos',
        displayName: 'Thu ngân',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
        ],
      );
      addTearDown(container.dispose);

      final selected = container.read(selectedBranchesProvider);
      expect(selected, equals(['store_001']));

      // Notifier operations should be locked
      container.read(selectedBranchesProvider.notifier).toggleBranch('store_002');
      expect(container.read(selectedBranchesProvider), equals(['store_001']));
    });

    test('Reads all branches for supervisor user via authProvider override', () {
      const supervisorUser = UserAccount(
        username: 'supervisor_admin',
        displayName: 'Giám sát hệ thống',
        role: 'supervisor',
        storeId: 'store_001',
      );

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
        ],
      );
      addTearDown(container.dispose);

      final selected = container.read(selectedBranchesProvider);
      expect(selected, equals(['store_001', 'store_002']));

      // Notifier operations should work
      container.read(selectedBranchesProvider.notifier).toggleBranch('store_002');
      expect(container.read(selectedBranchesProvider), equals(['store_001']));
    });

    test('Reads all branches for admin user via authProvider override', () {
      const adminUser = UserAccount(
        username: 'admin_store_manager',
        displayName: 'Quản trị viên',
        role: 'admin',
        storeId: 'store_001',
      );

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        ],
      );
      addTearDown(container.dispose);

      final selected = container.read(selectedBranchesProvider);
      expect(selected, equals(['store_001', 'store_002']));

      // Notifier operations should work
      container.read(selectedBranchesProvider.notifier).toggleBranch('store_002');
      expect(container.read(selectedBranchesProvider), equals(['store_001']));
    });
  });
}

class _FakeAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _FakeAuthNotifier(super.initialState);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}
