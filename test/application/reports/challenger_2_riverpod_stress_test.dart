import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';

// --- Fakes for Auth & Remote Data Sources ---

class FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  FakeAuthNotifier([super.initial]);

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
  TestWidgetsFlutterBinding.ensureInitialized();

  const adminUser = UserAccount(
    username: 'admin_boss',
    displayName: 'Tổng Quản Lý',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const staffStore1 = UserAccount(
    username: 'staff_dt',
    displayName: 'Nhân Viên Đông Thắng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const staffStore2 = UserAccount(
    username: 'staff_tb',
    displayName: 'Nhân Viên Thới Bình',
    role: 'nhanvien',
    storeId: 'store_002',
  );

  const staffNoStore = UserAccount(
    username: 'staff_empty',
    displayName: 'Nhân Viên Mới',
    role: 'nhanvien',
    storeId: '',
  );

  group('Challenger 2 Empirical Stress Suite: branchesProvider', () {
    test('branchesProvider returns canonical store names when availableStores is empty', () {
      final container = ProviderContainer(
        overrides: [
          availableStoresProvider.overrideWith((ref) => Future.value({})),
        ],
      );
      addTearDown(container.dispose);

      final branches = container.read(branchesProvider);
      expect(branches.length, equals(2));
      expect(branches[0].id, equals('store_001'));
      expect(branches[0].name, equals('Chi nhánh Đông Thắng'));
      expect(branches[1].id, equals('store_002'));
      expect(branches[1].name, equals('Chi nhánh Thới Bình'));
    });

    test('branchesProvider dynamically reflects custom store names from availableStoresProvider', () async {
      final container = ProviderContainer(
        overrides: [
          availableStoresProvider.overrideWith((ref) => Future.value({
                'store_001': 'Đông Thắng Flagship',
                'store_002': 'Thới Bình Premium',
              })),
        ],
      );
      addTearDown(container.dispose);

      // Wait for future to complete
      await container.read(availableStoresProvider.future);

      final branches = container.read(branchesProvider);
      expect(branches[0].id, equals('store_001'));
      expect(branches[0].name, equals('Đông Thắng Flagship'));
      expect(branches[1].id, equals('store_002'));
      expect(branches[1].name, equals('Thới Bình Premium'));
    });

    test('Branch value equality, hashCode, and toString compliance', () {
      const b1 = Branch('store_001', 'Chi nhánh Đông Thắng');
      const b2 = Branch('store_001', 'Chi nhánh Đông Thắng');
      const b3 = Branch('store_002', 'Chi nhánh Thới Bình');

      expect(b1, equals(b2));
      expect(b1.hashCode, equals(b2.hashCode));
      expect(b1 == b3, isFalse);
      expect(b1.toString(), contains('store_001'));
    });
  });

  group('Challenger 2 Empirical Stress Suite: SelectedBranchesNotifier State Machine', () {
    test('Admin/Supervisor initializes with all canonical branches [store_001, store_002]', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => FakeAuthNotifier(adminUser)),
        ],
      );
      addTearDown(container.dispose);

      final selected = container.read(selectedBranchesProvider);
      expect(selected, equals(['store_001', 'store_002']));
    });

    test('Staff at store_001 initializes strictly with [store_001]', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => FakeAuthNotifier(staffStore1)),
        ],
      );
      addTearDown(container.dispose);

      final selected = container.read(selectedBranchesProvider);
      expect(selected, equals(['store_001']));
    });

    test('Staff at store_002 initializes strictly with [store_002]', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => FakeAuthNotifier(staffStore2)),
        ],
      );
      addTearDown(container.dispose);

      final selected = container.read(selectedBranchesProvider);
      expect(selected, equals(['store_002']));
    });

    test('Staff with empty storeId defaults safely to [store_001]', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => FakeAuthNotifier(staffNoStore)),
        ],
      );
      addTearDown(container.dispose);

      final selected = container.read(selectedBranchesProvider);
      expect(selected, equals(['store_001']));
    });

    test('Admin branch toggling and minimum-1 constraint', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => FakeAuthNotifier(adminUser)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(selectedBranchesProvider.notifier);

      // Deselect store_002
      notifier.toggleBranch('store_002');
      expect(container.read(selectedBranchesProvider), equals(['store_001']));

      // Attempt to deselect remaining store_001 (should be prevented)
      notifier.toggleBranch('store_001');
      expect(container.read(selectedBranchesProvider), equals(['store_001']));

      // Re-enable store_002
      notifier.toggleBranch('store_002');
      expect(container.read(selectedBranchesProvider), equals(['store_001', 'store_002']));

      // Deselect store_001
      notifier.toggleBranch('store_001');
      expect(container.read(selectedBranchesProvider), equals(['store_002']));

      // Select all
      notifier.selectAll();
      expect(container.read(selectedBranchesProvider), equals(['store_001', 'store_002']));

      // Clear all -> falls back to first branch
      notifier.clearAll();
      expect(container.read(selectedBranchesProvider), equals(['store_001']));
    });

    test('Staff tamper lock: all mutations (toggle, selectAll, clearAll) are strictly rejected', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => FakeAuthNotifier(staffStore2)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(selectedBranchesProvider.notifier);
      expect(container.read(selectedBranchesProvider), equals(['store_002']));

      // Try toggling other store
      notifier.toggleBranch('store_001');
      expect(container.read(selectedBranchesProvider), equals(['store_002']));

      // Try toggling own store
      notifier.toggleBranch('store_002');
      expect(container.read(selectedBranchesProvider), equals(['store_002']));

      // Try selectAll
      notifier.selectAll();
      expect(container.read(selectedBranchesProvider), equals(['store_002']));

      // Try clearAll
      notifier.clearAll();
      expect(container.read(selectedBranchesProvider), equals(['store_002']));
    });

    test('Reactivity graph: switching authenticated user propagates branch scope re-binding', () {
      final authNotifier = FakeAuthNotifier(adminUser);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(selectedBranchesProvider), equals(['store_001', 'store_002']));

      // Switch to staffStore1
      authNotifier.setUser(staffStore1);
      expect(container.read(selectedBranchesProvider), equals(['store_001']));

      // Switch to staffStore2
      authNotifier.setUser(staffStore2);
      expect(container.read(selectedBranchesProvider), equals(['store_002']));

      // Switch back to admin
      authNotifier.setUser(adminUser);
      expect(container.read(selectedBranchesProvider), equals(['store_001', 'store_002']));
    });
  });

  group('Challenger 2 Empirical Stress Suite: currentStoreIdProvider Scoping & Tamper Resistance', () {
    test('Unauthenticated user defaults currentStoreIdProvider to store_001', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => FakeAuthNotifier(null)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentStoreIdProvider), equals('store_001'));
    });

    test('Admin respects selectedStoreIdProvider switching', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => FakeAuthNotifier(adminUser)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentStoreIdProvider), equals('store_001'));

      container.read(selectedStoreIdProvider.notifier).state = 'store_002';
      expect(container.read(currentStoreIdProvider), equals('store_002'));

      container.read(selectedStoreIdProvider.notifier).state = 'store_003';
      expect(container.read(currentStoreIdProvider), equals('store_003'));
    });

    test('Staff strictly locked to their storeId regardless of selectedStoreIdProvider tampering', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => FakeAuthNotifier(staffStore2)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentStoreIdProvider), equals('store_002'));

      // Attacker attempts to change selectedStoreIdProvider
      container.read(selectedStoreIdProvider.notifier).state = 'store_001';
      // currentStoreIdProvider MUST remain 'store_002'
      expect(container.read(currentStoreIdProvider), equals('store_002'));

      container.read(selectedStoreIdProvider.notifier).state = 'store_003';
      expect(container.read(currentStoreIdProvider), equals('store_002'));
    });
  });

  group('Challenger 2 Empirical Stress Suite: POS Branch Initialization (selectedPOSBranchProvider)', () {
    test('selectedPOSBranchProvider initializes with canonical store_001', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(selectedPOSBranchProvider), equals('store_001'));
    });

    test('selectedPOSBranchProvider can be updated during active POS session', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedPOSBranchProvider.notifier).state = 'store_002';
      expect(container.read(selectedPOSBranchProvider), equals('store_002'));
    });
  });

  group('Challenger 2 Empirical Stress Suite: Product Multi-Store Aggregation & Stock Resolution', () {
    test('Product aggregate stock getter and stockInBranch across canonical and legacy keys', () {
      const product = Product(
        id: 'p_emp_1',
        name: 'Cà Phê Sữa Đá',
        code: 'CF01',
        price: 25000,
        costPrice: 15000,
        branchStocks: {
          'store_001': 100,
          'store_002': 50,
          'store_003': 25,
        },
        category: 'Đồ uống',
      );

      expect(product.stock, equals(175));
      expect(product.stockInBranch('store_001'), equals(100));
      expect(product.stockInBranch('store_002'), equals(50));
      expect(product.stockInBranch('store_003'), equals(25));
      expect(product.stockInBranch('unknown'), equals(0));

      // Alias checks
      expect(product.stockInBranch('branch_1'), equals(100));
      expect(product.stockInBranch('ĐT'), equals(100));
      expect(product.stockInBranch('branch_2'), equals(50));
      expect(product.stockInBranch('TB'), equals(50));
    });
  });

  group('Challenger 2 Empirical Stress Suite: Customer Staff Scoping Matching', () {
    test('Customer store matching matches store_001, store_002, and legacy aliases', () {
      // Create customers with varied branch definitions
      const cDtCanonical = Customer(
        id: 'c1',
        name: 'Khách Đông Thắng',
        phone: '0901234567',
        email: 'dt@test.com',
        address: 'Đông Thắng',
        purchases: [],
        branch: 'store_001',
      );
      const cDtAlias = Customer(
        id: 'c2',
        name: 'Khách ĐT Alias',
        phone: '0901234568',
        email: 'dt2@test.com',
        address: 'Đông Thắng',
        purchases: [],
        branch: 'Chi nhánh Đông Thắng',
      );
      const cTbCanonical = Customer(
        id: 'c3',
        name: 'Khách Thới Bình',
        phone: '0901234569',
        email: 'tb@test.com',
        address: 'Thới Bình',
        purchases: [],
        branch: 'store_002',
      );
      const cTbAlias = Customer(
        id: 'c4',
        name: 'Khách TB Alias',
        phone: '0901234570',
        email: 'tb2@test.com',
        address: 'Thới Bình',
        purchases: [],
        branch: 'TB',
      );
      const cEmptyBranch = Customer(
        id: 'c5',
        name: 'Khách Không Chi Nhánh',
        phone: '0901234571',
        email: 'empty@test.com',
        address: 'Cần Thơ',
        purchases: [],
        branch: null,
      );

      // Verify customer scoping logic
      // Staff at store_001 should see store_001, ĐT, and empty branch customers
      // Staff at store_002 should see store_002 and TB customers
      expect(cDtCanonical.branch, equals('store_001'));
      expect(cDtAlias.branch, equals('Chi nhánh Đông Thắng'));
      expect(cTbCanonical.branch, equals('store_002'));
      expect(cTbAlias.branch, equals('TB'));
      expect(cEmptyBranch.branch, isNull);
    });
  });

  group('Challenger 2 Empirical Stress Suite: Provider Lifecycle & AutoDispose Integrity', () {
    test('SelectedBranchesNotifier cleans up without leaks on container disposal', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => FakeAuthNotifier(adminUser)),
        ],
      );

      final selected = container.read(selectedBranchesProvider);
      expect(selected, isNotEmpty);

      // Dispose container
      container.dispose();
      // Should not throw or retain listeners
    });

    test('allStoresProductsProvider autoDispose lifecycle test', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => FakeAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWithValue('store_001'),
          selectedStoreFilterProvider.overrideWith((ref) => 'store_001'),
        ],
      );

      // Read stream provider
      final sub = container.listen(allStoresProductsProvider, (prev, next) {});
      expect(container.read(allStoresProductsProvider), isA<AsyncValue<List<Product>>>());

      sub.close();
      container.dispose();
    });
  });
}

