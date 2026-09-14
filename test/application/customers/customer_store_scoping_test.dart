import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/user_account.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _FakeCustomerListNotifier
    extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _FakeCustomerListNotifier(this._initialCustomers);

  final List<Customer> _initialCustomers;

  @override
  Future<List<Customer>> build() async {
    return _initialCustomers;
  }

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_initialCustomers);
  }
}

void main() {
  const staffStore1 = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên Đông Thắng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const staffStore2 = UserAccount(
    username: 'staff_02',
    displayName: 'Nhân viên Thới Bình',
    role: 'nhanvien',
    storeId: 'store_002',
  );

  const adminUser = UserAccount(
    username: 'admin_user',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor_user',
    displayName: 'Giám sát viên',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const List<Customer> sampleCustomers = [
    Customer(
      id: 'cust_01',
      name: 'Khách Đông Thắng 1',
      phone: '0901111111',
      email: 'khach1@example.com',
      address: 'Đông Thắng',
      purchases: [],
      branch: 'store_001',
      createdAt: '2026-08-01 10:00:00',
      totalSales: 1000000,
    ),
    Customer(
      id: 'cust_02',
      name: 'Khách Đông Thắng 2',
      phone: '0902222222',
      email: 'khach2@example.com',
      address: 'Đông Thắng',
      purchases: [],
      branch: 'Chi nhánh Đông Thắng',
      createdAt: '2026-08-02 10:00:00',
      totalSales: 2000000,
    ),
    Customer(
      id: 'cust_03',
      name: 'Khách Thới Bình 1',
      phone: '0903333333',
      email: 'khach3@example.com',
      address: 'Thới Bình',
      purchases: [],
      branch: 'store_002',
      createdAt: '2026-08-03 10:00:00',
      totalSales: 3000000,
    ),
    Customer(
      id: 'cust_04',
      name: 'Khách Thới Bình 2',
      phone: '0904444444',
      email: 'khach4@example.com',
      address: 'Thới Bình',
      purchases: [],
      branch: 'Chi nhánh Thới Bình',
      createdAt: '2026-08-04 10:00:00',
      totalSales: 4000000,
    ),
    Customer(
      id: 'cust_05',
      name: 'Khách Vãng Lai Không Chi Nhánh',
      phone: '0905555555',
      email: 'khach5@example.com',
      address: 'Cần Thơ',
      purchases: [],
      branch: null,
      createdAt: '2026-08-05 10:00:00',
      totalSales: 500000,
    ),
  ];

  group('processedCustomersProvider Store Scoping Tests', () {
    test('Staff at store_001 sees only store_001 and fallback customers', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier(sampleCustomers)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);
      final result = container.read(processedCustomersProvider);
      expect(result.hasValue, isTrue);

      final items = result.value!;
      final customers = items.whereType<Customer>().toList();

      expect(customers.map((c) => c.id).toSet(),
          equals({'cust_01', 'cust_02', 'cust_05'}));
      expect(customers.any((c) => c.id == 'cust_03'), isFalse);
      expect(customers.any((c) => c.id == 'cust_04'), isFalse);
    });

    test('Staff at store_002 sees only store_002 customers', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore2)),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier(sampleCustomers)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);
      final result = container.read(processedCustomersProvider);
      expect(result.hasValue, isTrue);

      final items = result.value!;
      final customers = items.whereType<Customer>().toList();

      expect(customers.map((c) => c.id).toSet(),
          equals({'cust_03', 'cust_04'}));
      expect(customers.any((c) => c.id == 'cust_01'), isFalse);
      expect(customers.any((c) => c.id == 'cust_02'), isFalse);
      expect(customers.any((c) => c.id == 'cust_05'), isFalse);
    });

    test('Admin sees all customers across all stores', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier(sampleCustomers)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);
      final result = container.read(processedCustomersProvider);
      expect(result.hasValue, isTrue);

      final items = result.value!;
      final customers = items.whereType<Customer>().toList();

      expect(customers.length, equals(5));
      expect(customers.map((c) => c.id).toSet(),
          equals({'cust_01', 'cust_02', 'cust_03', 'cust_04', 'cust_05'}));
    });

    test('Supervisor sees all customers across all stores', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier(sampleCustomers)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);
      final result = container.read(processedCustomersProvider);
      expect(result.hasValue, isTrue);

      final items = result.value!;
      final customers = items.whereType<Customer>().toList();

      expect(customers.length, equals(5));
    });

    test('Staff customer list respects search query in addition to store scoping', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier(sampleCustomers)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customerListNotifierProvider.future);
      container.read(customerSearchQueryProvider.notifier).state = 'Đông Thắng 1';

      final result = container.read(processedCustomersProvider);
      expect(result.hasValue, isTrue);

      final customers = result.value!.whereType<Customer>().toList();
      expect(customers.length, equals(1));
      expect(customers.first.id, equals('cust_01'));
    });
  });
}
