import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/presentation/customers/pages/customer_debt_page.dart';

import '../../support/firebase_test_harness.dart';

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

/// A MockQuery that delegates its onValue stream to a shared CancellableEventStream.
class _LifecycleTrackingQuery extends Fake implements Query {
  @override
  final String path;
  final CancellableEventStream cancellableStream;
  final MethodCallRecorder recorder;
  final String? orderedKey;
  final dynamic equalValue;

  _LifecycleTrackingQuery({
    required this.path,
    required this.cancellableStream,
    required this.recorder,
    this.orderedKey,
    this.equalValue,
  });

  @override
  Query orderByChild(String key) {
    recorder.record('orderByChild', path: path, extra: {'key': key});
    return _LifecycleTrackingQuery(
      path: path,
      cancellableStream: cancellableStream,
      recorder: recorder,
      orderedKey: key,
      equalValue: equalValue,
    );
  }

  @override
  Query equalTo(dynamic value, {String? key}) {
    recorder.record('equalTo', path: path, extra: {'value': value});
    return _LifecycleTrackingQuery(
      path: path,
      cancellableStream: cancellableStream,
      recorder: recorder,
      orderedKey: orderedKey,
      equalValue: value,
    );
  }

  @override
  Stream<DatabaseEvent> get onValue => cancellableStream.stream;
}

/// Mock DatabaseReference that routes queries through _LifecycleTrackingQuery
/// sharing a single CancellableEventStream per reference path.
class _LifecycleTrackingRef extends MockDatabaseReference {
  final CancellableEventStream queryStream = CancellableEventStream();

  _LifecycleTrackingRef({
    required super.path,
    required super.recorder,
  });

  @override
  Query orderByChild(String key) {
    recorder.record('orderByChild', path: path, extra: {'key': key});
    return _LifecycleTrackingQuery(
      path: path,
      cancellableStream: queryStream,
      recorder: recorder,
      orderedKey: key,
    );
  }
}

/// Mock FirebaseDatabase for tracking queries and subscription lifecycle.
class _LifecycleTrackingDatabase extends MockFirebaseDatabase {
  final Map<String, _LifecycleTrackingRef> trackingRefs = {};

  @override
  DatabaseReference ref([String? path]) {
    final cleanPath =
        path != null && path.startsWith('/') ? path.substring(1) : (path ?? '');
    requestedPaths.add(cleanPath);
    return trackingRefs.putIfAbsent(
      cleanPath,
      () => _LifecycleTrackingRef(path: cleanPath, recorder: recorder),
    );
  }
}

void main() {
  group('customerOrdersProvider - Cross-Branch & Bandwidth Optimization', () {
    late MockFirebaseDatabase mockDb;

    const adminUser = UserAccount(
      username: 'admin',
      displayName: 'Quản trị viên',
      role: 'admin',
      storeId: 'store_001',
    );

    const staffStore1User = UserAccount(
      username: 'staff1',
      displayName: 'Nhân viên ĐT',
      role: 'nhanvien',
      storeId: 'store_001',
    );

    const staffStore2User = UserAccount(
      username: 'staff2',
      displayName: 'Nhân viên TB',
      role: 'nhanvien',
      storeId: 'store_002',
    );

    setUp(() {
      mockDb = MockFirebaseDatabase();
    });

    test('Admin aggregates orders from all branches sorted by createdAt DESC and stamps storeId', () async {
      // Seed orders in store_001 (older) and store_002 (newer)
      mockDb.seedData('stores/store_001/orders', {
        'ord_dong_thang': {
          'id': 'ord_dong_thang',
          'customerId': 'cust_999',
          'total': 1500000.0,
          'createdAt': '2026-09-19T08:00:00.000Z',
          'status': 'completed',
          // storeId missing in DB to test provenance stamping
        },
      });

      mockDb.seedData('stores/store_002/orders', {
        'ord_thoi_binh': {
          'id': 'ord_thoi_binh',
          'customerId': 'cust_999',
          'total': 2500000.0,
          'createdAt': '2026-09-19T10:00:00.000Z',
          'status': 'completed',
          'storeId': 'store_002',
        },
      });

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          availableStoresProvider.overrideWith((ref) async => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
              }),
          firebaseDatabaseProvider.overrideWithValue(mockDb),
        ],
      );
      addTearDown(container.dispose);

      final completer = Completer<List<Order>>();
      final sub = container.listen(
        customerOrdersProvider('cust_999'),
        (previous, next) {
          next.whenData((orders) {
            if (orders.length == 2 && !completer.isCompleted) {
              completer.complete(orders);
            }
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final orders = await completer.future.timeout(const Duration(seconds: 3));

      // Expect both orders combined
      expect(orders.length, equals(2));

      // Expect sorted newest first (DESC)
      expect(orders[0].id, equals('ord_thoi_binh'));
      expect(orders[0].total, equals(2500000.0));
      expect(orders[0].storeId, equals('store_002'));

      expect(orders[1].id, equals('ord_dong_thang'));
      expect(orders[1].total, equals(1500000.0));
      // Provenance stamping applied from branch key
      expect(orders[1].storeId, equals('store_001'));
    });

    test('Staff assigned to store_001 only gets orders from store_001', () async {
      mockDb.seedData('stores/store_001/orders', {
        'ord_dt_1': {
          'id': 'ord_dt_1',
          'customerId': 'cust_999',
          'total': 1200000.0,
          'createdAt': '2026-09-19T08:00:00.000Z',
          'status': 'completed',
        },
      });

      mockDb.seedData('stores/store_002/orders', {
        'ord_tb_1': {
          'id': 'ord_tb_1',
          'customerId': 'cust_999',
          'total': 3400000.0,
          'createdAt': '2026-09-19T09:00:00.000Z',
          'status': 'completed',
        },
      });

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1User)),
          availableStoresProvider.overrideWith((ref) async => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
              }),
          firebaseDatabaseProvider.overrideWithValue(mockDb),
        ],
      );
      addTearDown(container.dispose);

      final completer = Completer<List<Order>>();
      final sub = container.listen(
        customerOrdersProvider('cust_999'),
        (previous, next) {
          next.whenData((orders) {
            if (orders.isNotEmpty && !completer.isCompleted) {
              completer.complete(orders);
            }
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final orders = await completer.future.timeout(const Duration(seconds: 3));

      // Staff only sees store_001 order
      expect(orders.length, equals(1));
      expect(orders.first.id, equals('ord_dt_1'));
      expect(orders.first.total, equals(1200000.0));
    });

    test('Staff assigned to store_002 only gets orders from store_002', () async {
      mockDb.seedData('stores/store_001/orders', {
        'ord_dt_1': {
          'id': 'ord_dt_1',
          'customerId': 'cust_999',
          'total': 1200000.0,
          'createdAt': '2026-09-19T08:00:00.000Z',
          'status': 'completed',
        },
      });

      mockDb.seedData('stores/store_002/orders', {
        'ord_tb_1': {
          'id': 'ord_tb_1',
          'customerId': 'cust_999',
          'total': 3400000.0,
          'createdAt': '2026-09-19T09:00:00.000Z',
          'status': 'completed',
        },
      });

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore2User)),
          availableStoresProvider.overrideWith((ref) async => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
              }),
          firebaseDatabaseProvider.overrideWithValue(mockDb),
        ],
      );
      addTearDown(container.dispose);

      final completer = Completer<List<Order>>();
      final sub = container.listen(
        customerOrdersProvider('cust_999'),
        (previous, next) {
          next.whenData((orders) {
            if (orders.isNotEmpty && !completer.isCompleted) {
              completer.complete(orders);
            }
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final orders = await completer.future.timeout(const Duration(seconds: 3));

      // Staff only sees store_002 order
      expect(orders.length, equals(1));
      expect(orders.first.id, equals('ord_tb_1'));
      expect(orders.first.total, equals(3400000.0));
    });

    test('Server-side indexed query orderByChild(customerId).equalTo(id) is used without unindexed root get()', () async {
      mockDb.seedData('stores/store_001/orders', {
        'ord_dt_1': {
          'id': 'ord_dt_1',
          'customerId': 'cust_target',
          'total': 500000.0,
          'createdAt': '2026-09-19T08:00:00.000Z',
          'status': 'completed',
        },
      });

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1User)),
          firebaseDatabaseProvider.overrideWithValue(mockDb),
        ],
      );
      addTearDown(container.dispose);

      final completer = Completer<List<Order>>();
      final sub = container.listen(
        customerOrdersProvider('cust_target'),
        (previous, next) {
          next.whenData((orders) {
            if (orders.isNotEmpty && !completer.isCompleted) {
              completer.complete(orders);
            }
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      await completer.future.timeout(const Duration(seconds: 3));

      // Verify server-side indexed query was used with indexed constraints
      final getCalls = mockDb.recorder.callsFor('get', path: 'stores/store_001/orders');
      expect(getCalls, isNotEmpty);
      expect(
        getCalls.every((c) => c.extra?['orderedByChildKey'] == 'customerId'),
        isTrue,
      );
      expect(
        getCalls.every((c) => c.extra?['equalToVal'] == 'cust_target'),
        isTrue,
      );

      // Verify unindexed root .get() was NEVER called (all gets were indexed)
      final unindexedGetCalls = getCalls
          .where((c) => c.extra?['orderedByChildKey'] == null)
          .toList();
      expect(unindexedGetCalls, isEmpty);
    });

    test('autoDispose cancels underlying stream subscriptions when provider listener is closed', () async {
      final trackingDb = _LifecycleTrackingDatabase();

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          availableStoresProvider.overrideWith((ref) async => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
              }),
          firebaseDatabaseProvider.overrideWithValue(trackingDb),
        ],
      );
      addTearDown(container.dispose);

      // Listen to the provider
      final sub = container.listen(
        customerOrdersProvider('cust_lifecycle'),
        (_, __) {},
      );

      final ref1 = trackingDb.ref('stores/store_001/orders') as _LifecycleTrackingRef;
      final ref2 = trackingDb.ref('stores/store_002/orders') as _LifecycleTrackingRef;

      // 2 branch streams should have active listeners
      expect(ref1.queryStream.activeListeners, equals(1));
      expect(ref2.queryStream.activeListeners, equals(1));

      // Emit data so listeners receive initial event
      ref1.queryStream.emitSnapshot(
        MockDataSnapshot(key: 'orders', value: {}),
      );
      ref2.queryStream.emitSnapshot(
        MockDataSnapshot(key: 'orders', value: {}),
      );

      // Closing the subscription triggers autoDispose teardown
      sub.close();
      await Future<void>.delayed(Duration.zero);

      // Verify all subscriptions were cleanly cancelled
      expect(ref1.queryStream.activeListeners, equals(0));
      expect(ref2.queryStream.activeListeners, equals(0));
      expect(ref1.queryStream.cancelCount, equals(1));
      expect(ref2.queryStream.cancelCount, equals(1));
    });

    test('Customer.effectiveTotalSales prioritizes active orders sum over static totalSales', () {
      const customerWithStaticSales = Customer(
        id: 'cust_01',
        name: 'Nguyễn Văn A',
        phone: '0901234567',
        email: 'a@example.com',
        address: '123 Đông Thắng',
        purchases: [],
        totalSales: 1000000.0,
      );

      final order1 = Order(
        id: 'o1',
        customerId: 'cust_01',
        createdAt: DateTime.now(),
        items: [
          OrderItem(
            productId: 'p1',
            productName: 'Item 1',
            quantity: 1,
            price: 2000000,
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 9, 1),
          ),
        ],
        total: 2000000.0,
      );

      final order2 = Order(
        id: 'o2',
        customerId: 'cust_01',
        createdAt: DateTime.now(),
        items: [
          OrderItem(
            productId: 'p2',
            productName: 'Item 2',
            quantity: 1,
            price: 3000000,
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 9, 2),
          ),
        ],
        total: 3000000.0,
      );

      final cancelledOrder = Order(
        id: 'o3',
        customerId: 'cust_01',
        createdAt: DateTime.now(),
        status: 'cancelled',
        items: [
          OrderItem(
            productId: 'p3',
            productName: 'Item 3',
            quantity: 1,
            price: 9000000,
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 9, 3),
          ),
        ],
        total: 9000000.0,
      );

      // 1. With active orders: 2M + 3M = 5M (excluding cancelled order 9M and ignoring static 1M)
      final effectiveWithOrders = customerWithStaticSales.effectiveTotalSales([
        order1,
        order2,
        cancelledOrder,
      ]);
      expect(effectiveWithOrders, equals(5000000.0));

      // 2. With empty orders: falls back to static imported totalSales
      final effectiveEmpty = customerWithStaticSales.effectiveTotalSales([]);
      expect(effectiveEmpty, equals(1000000.0));

      // 3. Customer without static sales with orders
      const customerNoStatic = Customer(
        id: 'cust_02',
        name: 'Trần Thị B',
        phone: '0909888777',
        email: 'b@example.com',
        address: '456 Thới Bình',
        purchases: [],
      );
      expect(customerNoStatic.effectiveTotalSales([order1]), equals(2000000.0));

      // 4. Customer without static sales and empty orders
      expect(customerNoStatic.effectiveTotalSales([]), equals(0.0));
    });

    test('Customer.effectiveCurrentDebt calculates debt using orders and debt transactions', () {
      const customer = Customer(
        id: 'cust_debt',
        name: 'Lê Văn C',
        phone: '0911222333',
        email: 'c@example.com',
        address: '789 Đông Thắng',
        purchases: [],
        currentDebt: 500000.0,
      );

      final now = DateTime.now();
      final txOld = CustomerDebtTransaction(
        id: 'tx1',
        code: 'PT01',
        customerId: 'cust_debt',
        date: now.subtract(const Duration(days: 2)),
        amount: 200000.0,
        type: DebtTransactionType.payment,
        remainingDebt: 300000.0,
      );

      final txNewest = CustomerDebtTransaction(
        id: 'tx2',
        code: 'PT02',
        customerId: 'cust_debt',
        date: now.subtract(const Duration(days: 1)),
        amount: 100000.0,
        type: DebtTransactionType.payment,
        remainingDebt: 200000.0,
      );

      // With transactions, takes newest remainingDebt
      final debtWithTxs = customer.effectiveCurrentDebt([], [txOld, txNewest]);
      expect(debtWithTxs, equals(200000.0));

      // Without transactions, falls back to customer currentDebt
      final debtNoTxs = customer.effectiveCurrentDebt([], []);
      expect(debtNoTxs, equals(500000.0));
    });

    testWidgets('CustomerDebtPage line 108 renders effectiveCurrentDebt rather than static currentDebt', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const customer = Customer(
        id: 'cust_sync_test',
        name: 'Khách hàng Đồng bộ',
        phone: '0988776655',
        email: 'dongbo@example.com',
        address: 'Hà Nội',
        purchases: [],
        currentDebt: 50000000.0, // Outdated snapshot debt
      );

      final debtTransactions = [
        CustomerDebtTransaction(
          id: 'TX_01',
          code: 'PT01',
          customerId: 'cust_sync_test',
          date: DateTime.now(),
          amount: 38000000.0,
          remainingDebt: 12000000.0, // Live current debt after payments
          type: DebtTransactionType.payment,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerRepositoryProvider.overrideWithValue(_SimpleCustomerRepo([customer])),
            customerOrdersProvider('cust_sync_test').overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider('cust_sync_test').overrideWith((ref) => Stream.value(debtTransactions)),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: CustomerDebtPage(customer: customer),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header should display dynamic remainingDebt (12.000.000 đ), NOT outdated static debt (50.000.000 đ)
      expect(find.text('12.000.000 đ'), findsOneWidget);
      expect(find.text('50.000.000 đ'), findsNothing);
    });
  });
}

class _SimpleCustomerRepo extends Fake implements CustomerRepository {
  final List<Customer> customers;
  _SimpleCustomerRepo(this.customers);

  @override
  Stream<List<Customer>> watchAll() => Stream.value(customers);

  @override
  Future<Customer?> fetchById(String id) async {
    try {
      return customers.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }
}

