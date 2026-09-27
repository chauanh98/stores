import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/user_account.dart';

void main() {
  group('Adversarial Stress Testing: UserAccount Domain Entity', () {
    test('Role casing variations correctly evaluate permissions', () {
      final rolesToTest = {
        'ADMIN': (isAdmin: true, isSupervisor: false, isStaff: false, canSwitch: true, canDebt: true),
        'Admin': (isAdmin: true, isSupervisor: false, isStaff: false, canSwitch: true, canDebt: true),
        'aDmIn': (isAdmin: true, isSupervisor: false, isStaff: false, canSwitch: true, canDebt: true),
        'SUPERVISOR': (isAdmin: false, isSupervisor: true, isStaff: false, canSwitch: false, canDebt: true),
        'Supervisor': (isAdmin: false, isSupervisor: true, isStaff: false, canSwitch: false, canDebt: true),
        'sUpErViSoR': (isAdmin: false, isSupervisor: true, isStaff: false, canSwitch: false, canDebt: true),
        'NHANVIEN': (isAdmin: false, isSupervisor: false, isStaff: true, canSwitch: false, canDebt: false),
        'NhanVien': (isAdmin: false, isSupervisor: false, isStaff: true, canSwitch: false, canDebt: false),
        'nhanvien': (isAdmin: false, isSupervisor: false, isStaff: true, canSwitch: false, canDebt: false),
      };

      for (final entry in rolesToTest.entries) {
        final user = UserAccount(
          username: 'test_user',
          role: entry.key,
          storeId: 'store_001',
        );

        final expected = entry.value;
        expect(user.isAdmin, equals(expected.isAdmin), reason: 'Failed isAdmin for role: "${entry.key}"');
        expect(user.isSupervisor, equals(expected.isSupervisor), reason: 'Failed isSupervisor for role: "${entry.key}"');
        expect(user.isStaff, equals(expected.isStaff), reason: 'Failed isStaff for role: "${entry.key}"');
        expect(user.canSwitchStore, equals(expected.canSwitch), reason: 'Failed canSwitchStore for role: "${entry.key}"');
        expect(user.canViewDebtSummary, equals(expected.canDebt), reason: 'Failed canViewDebtSummary for role: "${entry.key}"');
      }
    });

    test('Whitespace and newline padding in roles are safely trimmed', () {
      final paddedRoles = [
        ('  admin  ', true, false, true, true),
        ('\t\nsupervisor\r\n ', false, true, false, true),
        ('  nhanvien \n', false, false, false, false),
      ];

      for (final (roleStr, expAdmin, expSup, expSwitch, expDebt) in paddedRoles) {
        final user = UserAccount(
          username: 'padded_user',
          role: roleStr,
          storeId: 'store_001',
        );

        expect(user.isAdmin, equals(expAdmin), reason: 'Failed isAdmin on "$roleStr"');
        expect(user.isSupervisor, equals(expSup), reason: 'Failed isSupervisor on "$roleStr"');
        expect(user.canSwitchStore, equals(expSwitch), reason: 'Failed canSwitchStore on "$roleStr"');
        expect(user.canViewDebtSummary, equals(expDebt), reason: 'Failed canViewDebtSummary on "$roleStr"');
      }
    });

    test('Untrusted, malformed, and injection role payloads default to safe Staff permissions', () {
      final untrustedRoles = [
        '',
        '   ',
        'root',
        'guest',
        'superuser',
        'admin; DROP TABLE users;--',
        '<script>alert("xss")</script>',
        'role_admin',
        'admin_fake',
        'super_visor',
        'nhan_vien',
      ];

      for (final maliciousRole in untrustedRoles) {
        final user = UserAccount(
          username: 'attacker',
          role: maliciousRole,
          storeId: 'store_001',
        );

        expect(user.isAdmin, isFalse, reason: 'Untrusted role "$maliciousRole" gained admin privilege');
        expect(user.isSupervisor, isFalse, reason: 'Untrusted role "$maliciousRole" gained supervisor privilege');
        expect(user.isStaff, isTrue, reason: 'Untrusted role "$maliciousRole" failed closed to staff');
        expect(user.canSwitchStore, isFalse, reason: 'Untrusted role "$maliciousRole" gained store switching');
        expect(user.canViewDebtSummary, isFalse, reason: 'Untrusted role "$maliciousRole" gained debt summary visibility');
        expect(user.canManagePaymentConfig, isFalse);
        expect(user.canManageProducts, isFalse);
        expect(user.canDeleteInvoice, isFalse);
        expect(user.canDeleteCustomer, isFalse);
        expect(user.canEditPriceAndDiscount, isFalse);
        expect(user.canViewCostPrice, isFalse);
      }
    });

    test('fromMap with missing, null, and non-string types fails closed safely', () {
      final malformedMaps = [
        <dynamic, dynamic>{},
        <dynamic, dynamic>{'role': null, 'storeId': null},
        <dynamic, dynamic>{'role': 12345, 'storeId': 67890},
        <dynamic, dynamic>{'role': true, 'storeId': false},
        <dynamic, dynamic>{'role': ['admin'], 'storeId': {'id': 'store_001'}},
      ];

      for (final map in malformedMaps) {
        final user = UserAccount.fromMap('malformed_user', map);

        expect(user.username, equals('malformed_user'));
        expect(user.isAdmin, isFalse);
        expect(user.isSupervisor, isFalse);
        expect(user.isStaff, isTrue);
        expect(user.canSwitchStore, isFalse);
        expect(user.canViewDebtSummary, isFalse);
      }
    });
  });

  group('Adversarial Stress Testing: SelectedBranchesNotifier Invariants', () {
    test('Staff account cannot bypass scope restrictions via any notifier method', () {
      const staff = UserAccount(
        username: 'staff_locked',
        role: 'nhanvien',
        storeId: 'store_002',
      );

      final notifier = SelectedBranchesNotifier(staff);

      // Initial state is strictly locked to staff storeId
      expect(notifier.state, equals(['store_002']));

      // Attempt 1: toggle other branch
      notifier.toggleBranch('store_001');
      expect(notifier.state, equals(['store_002']));

      // Attempt 2: toggle current branch (attempting to create empty state)
      notifier.toggleBranch('store_002');
      expect(notifier.state, equals(['store_002']));

      // Attempt 3: toggle non-existent / malicious branch
      notifier.toggleBranch('all');
      notifier.toggleBranch('*');
      notifier.toggleBranch('store_999');
      expect(notifier.state, equals(['store_002']));

      // Attempt 4: selectAll
      notifier.selectAll();
      expect(notifier.state, equals(['store_002']));

      // Attempt 5: clearAll
      notifier.clearAll();
      expect(notifier.state, equals(['store_002']));
    });

    test('Admin account can switch branches and select all like supervisor', () {
      const adminUser = UserAccount(
        username: 'store_admin',
        role: 'admin',
        storeId: 'store_001',
      );

      final notifier = SelectedBranchesNotifier(adminUser);

      // Admin has full branch switching access because canSwitchStore == isAdmin
      expect(notifier.state, equals(['store_001', 'store_002']));

      notifier.toggleBranch('store_002');
      expect(notifier.state, equals(['store_001']));

      notifier.selectAll();
      expect(notifier.state, equals(['store_001', 'store_002']));

      notifier.clearAll();
      expect(notifier.state, equals(['store_001']));
    });

    test('Supervisor account: rapid toggling maintains list invariants (never empty)', () {
      const supervisor = UserAccount(
        username: 'super_stress',
        role: 'supervisor',
        storeId: 'store_001',
      );

      final notifier = SelectedBranchesNotifier(supervisor);
      expect(notifier.state, equals(['store_001', 'store_002']));

      // Stress toggle 200 times
      for (var i = 0; i < 200; i++) {
        notifier.toggleBranch(i.isEven ? 'store_001' : 'store_002');
        expect(notifier.state, isNotEmpty, reason: 'State became empty at iteration $i');
        expect(notifier.state.length, inInclusiveRange(1, 2));
      }

      // Repeated clearAll should always leave exactly 1 fallback branch
      for (var i = 0; i < 20; i++) {
        notifier.clearAll();
        expect(notifier.state, equals(['store_001']));
      }

      // Repeated selectAll should always return all branches
      for (var i = 0; i < 20; i++) {
        notifier.selectAll();
        expect(notifier.state, equals(['store_001', 'store_002']));
      }
    });

    test('Null / unauthenticated user: state invariants hold under rapid operations', () {
      final notifier = SelectedBranchesNotifier(null);
      expect(notifier.state, equals(['store_001', 'store_002']));

      // Toggling down to 1 branch
      notifier.toggleBranch('store_002');
      expect(notifier.state, equals(['store_001']));

      // Attempting to deselect the last remaining branch
      notifier.toggleBranch('store_001');
      expect(notifier.state, equals(['store_001']), reason: 'Should prevent deselecting the sole remaining branch');

      // ClearAll resets to fallback branch
      notifier.clearAll();
      expect(notifier.state, equals(['store_001']));

      // SelectAll restores all branches
      notifier.selectAll();
      expect(notifier.state, equals(['store_001', 'store_002']));
    });
  });

  group('Adversarial Stress Testing: Riverpod Provider Lifecycle & Auth Transitions', () {
    test('Dynamic auth transitions enforce instant scoping locks and re-evaluations', () {
      final authNotifier = _MutableAuthNotifier(null);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
        ],
      );
      addTearDown(container.dispose);

      // Phase 1: Unauthenticated -> full access
      expect(container.read(selectedBranchesProvider), equals(['store_001', 'store_002']));

      // Phase 2: Log in as Supervisor -> full access & mutable
      authNotifier.setUser(const UserAccount(
        username: 'sup_user',
        role: 'SUPERVISOR',
        storeId: 'store_001',
      ));
      expect(container.read(selectedBranchesProvider), equals(['store_001', 'store_002']));
      container.read(selectedBranchesProvider.notifier).toggleBranch('store_002');
      expect(container.read(selectedBranchesProvider), equals(['store_001']));

      // Phase 3: Switch user to Staff (e.g. session handover) -> immediately locked to single branch
      authNotifier.setUser(const UserAccount(
        username: 'staff_user',
        role: 'nhanvien',
        storeId: 'store_001',
      ));
      expect(container.read(selectedBranchesProvider), equals(['store_001']));

      // Malicious attempt to mutate state while staff
      container.read(selectedBranchesProvider.notifier).toggleBranch('store_002');
      container.read(selectedBranchesProvider.notifier).selectAll();
      expect(container.read(selectedBranchesProvider), equals(['store_001']));

      // Phase 4: User with whitespace/casing role '  NHANVIEN\n'
      authNotifier.setUser(const UserAccount(
        username: 'staff_padded',
        role: '  NHANVIEN\n',
        storeId: 'store_001',
      ));
      expect(container.read(selectedBranchesProvider), equals(['store_001']));
      container.read(selectedBranchesProvider.notifier).selectAll();
      expect(container.read(selectedBranchesProvider), equals(['store_001']));

      // Phase 5: Logout -> unauthenticated fallback
      authNotifier.setUser(null);
      expect(container.read(selectedBranchesProvider), equals(['store_001', 'store_002']));
    });
  });
}

class _MutableAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _MutableAuthNotifier(super.initialState);

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
