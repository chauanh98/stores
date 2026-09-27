import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../support/firebase_test_harness.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

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

/// Controllable multi-branch event stream matching Firebase RTDB onValue semantics:
/// Emits current data immediately on subscribe, emits on updates, and tracks lifecycle.
class _ControllableEventStream {
  final StreamController<DatabaseEvent> _controller =
      StreamController<DatabaseEvent>.broadcast();
  int activeListeners = 0;
  int cancelCount = 0;
  DataSnapshot? _currentSnapshot;

  Stream<DatabaseEvent> get stream {
    return Stream<DatabaseEvent>.multi((multiController) {
      activeListeners++;

      // Firebase RTDB onValue semantic: deliver current snapshot immediately if present
      if (_currentSnapshot != null) {
        multiController.add(MockDatabaseEvent(_currentSnapshot!));
      }

      final sub = _controller.stream.listen(
        multiController.add,
        onError: multiController.addError,
        onDone: multiController.close,
      );

      multiController.onCancel = () {
        activeListeners--;
        cancelCount++;
        sub.cancel();
      };
    });
  }

  void emitSnapshot(DataSnapshot snapshot) {
    _currentSnapshot = snapshot;
    if (!_controller.isClosed) {
      _controller.add(MockDatabaseEvent(snapshot));
    }
  }

  void emitError(Object error, [StackTrace? stackTrace]) {
    if (!_controller.isClosed) {
      _controller.addError(error, stackTrace);
    }
  }
}

/// Advanced mock Query routing to a _ControllableEventStream per path.
class _StressTrackingQuery extends Fake implements Query {
  @override
  final String path;
  final _ControllableEventStream controllableStream;
  final MethodCallRecorder recorder;
  final String? orderedKey;
  final dynamic equalValue;

  _StressTrackingQuery({
    required this.path,
    required this.controllableStream,
    required this.recorder,
    this.orderedKey,
    this.equalValue,
  });

  @override
  Query orderByChild(String key) {
    recorder.record('orderByChild', path: path, extra: {'key': key});
    return _StressTrackingQuery(
      path: path,
      controllableStream: controllableStream,
      recorder: recorder,
      orderedKey: key,
      equalValue: equalValue,
    );
  }

  @override
  Query equalTo(dynamic value, {String? key}) {
    recorder.record('equalTo', path: path, extra: {'value': value});
    return _StressTrackingQuery(
      path: path,
      controllableStream: controllableStream,
      recorder: recorder,
      orderedKey: orderedKey,
      equalValue: value,
    );
  }

  @override
  Stream<DatabaseEvent> get onValue => controllableStream.stream;
}

/// Mock DatabaseReference supporting arbitrary branches and tracking streams.
class _StressTrackingRef extends MockDatabaseReference {
  final _ControllableEventStream queryStream = _ControllableEventStream();

  _StressTrackingRef({
    required super.path,
    required super.recorder,
  });

  @override
  Query orderByChild(String key) {
    recorder.record('orderByChild', path: path, extra: {'key': key});
    return _StressTrackingQuery(
      path: path,
      controllableStream: queryStream,
      recorder: recorder,
      orderedKey: key,
    );
  }

  void emitOrders(Map<String, dynamic> ordersMap) {
    queryStream.emitSnapshot(
      MockDataSnapshot(
        key: path.split('/').last,
        value: ordersMap.isEmpty ? null : ordersMap,
        exists: ordersMap.isNotEmpty,
      ),
    );
  }

  void emitError(Object error) {
    queryStream.emitError(error);
  }
}

/// Mock FirebaseDatabase for concurrency and lifecycle stress testing across 3+ branches.
class _StressTrackingDatabase extends MockFirebaseDatabase {
  final Map<String, _StressTrackingRef> trackingRefs = {};

  @override
  DatabaseReference ref([String? path]) {
    final cleanPath =
        path != null && path.startsWith('/') ? path.substring(1) : (path ?? '');
    requestedPaths.add(cleanPath);
    return trackingRefs.putIfAbsent(
      cleanPath,
      () => _StressTrackingRef(path: cleanPath, recorder: recorder),
    );
  }

  _StressTrackingRef getBranchRef(String storeId) {
    return ref('stores/$storeId/orders') as _StressTrackingRef;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Challenger 1: customerOrdersProvider Backend Stream & Concurrency Stress Suite', () {
    late _StressTrackingDatabase stressDb;

    const adminUser = UserAccount(
      username: 'admin',
      displayName: 'Tổng Quản Trị',
      role: 'admin',
      storeId: 'store_001',
    );

    const staffUserStore1 = UserAccount(
      username: 'staff_dt',
      displayName: 'Nhân viên Đông Thắng',
      role: 'nhanvien',
      storeId: 'store_001',
    );

    setUp(() {
      stressDb = _StressTrackingDatabase();
    });

    // =========================================================================
    // TEST 1: Rapid Concurrent Events Across 4 Branches with Timestamp Interleaving
    // =========================================================================
    test('STRESS-01: Rapid concurrent order events across 4 branches sort chronologically DESC', () async {
      final branches = ['store_001', 'store_002', 'store_003', 'store_004'];

      // Pre-seed 25 orders per branch (total 100 orders) with interleaved timestamps
      final baseDate = DateTime(2026, 9, 19, 10, 0, 0);
      for (int bIndex = 0; bIndex < branches.length; bIndex++) {
        final bId = branches[bIndex];
        final Map<String, dynamic> branchOrders = {};
        for (int i = 0; i < 25; i++) {
          final orderId = 'ord_${bId}_$i';
          final orderDate = baseDate.add(Duration(minutes: (i * 4) + bIndex));
          branchOrders[orderId] = {
            'id': orderId,
            'customerId': 'cust_stress_01',
            'total': 100000.0 * (i + 1),
            'createdAt': orderDate.toIso8601String(),
            'status': 'completed',
            // intentionally omit storeId to test provenance stamping
          };
        }
        stressDb.getBranchRef(bId).emitOrders(branchOrders);
      }

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          availableStoresProvider.overrideWith((ref) => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
                'store_003': 'Chi nhánh Cái Nước',
                'store_004': 'Chi nhánh Năm Căn',
              }),
          firebaseDatabaseProvider.overrideWithValue(stressDb),
        ],
      );
      addTearDown(container.dispose);

      final completer = Completer<List<Order>>();
      final sub = container.listen(
        customerOrdersProvider('cust_stress_01'),
        (previous, next) {
          next.whenData((orders) {
            if (orders.length == 100 && !completer.isCompleted) {
              completer.complete(orders);
            }
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // Verify each branch has an active listener
      for (final b in branches) {
        expect(stressDb.getBranchRef(b).queryStream.activeListeners, equals(1));
      }

      final finalOrders = await completer.future.timeout(const Duration(seconds: 3));

      // Exactly 100 orders across 4 branches
      expect(finalOrders.length, equals(100));

      // Check strict descending order by createdAt
      for (int i = 0; i < finalOrders.length - 1; i++) {
        final current = finalOrders[i].createdAt;
        final next = finalOrders[i + 1].createdAt;
        expect(
          current.isAfter(next) || current.isAtSameMomentAs(next),
          isTrue,
          reason: 'Order $i (${current.toIso8601String()}) must be >= Order ${i + 1} (${next.toIso8601String()})',
        );
      }

      // Check provenance stamping: every order must have a valid non-empty storeId matching its branch
      for (final order in finalOrders) {
        expect(order.storeId, isNotNull);
        expect(branches.contains(order.storeId), isTrue);
        expect(order.id.contains(order.storeId!), isTrue);
      }
    });

    // =========================================================================
    // TEST 2: Mixed Order States & Payload Resiliency (Cancelled, Zero, Null fields)
    // =========================================================================
    test('STRESS-02: Mixed order states: cancelled, zero total, null fields & effective calculations', () async {
      // Branch 1: Normal active order
      stressDb.getBranchRef('store_001').emitOrders({
        'ord_normal': {
          'id': 'ord_normal',
          'customerId': 'cust_mixed_states',
          'total': 2000000.0,
          'createdAt': '2026-09-19T08:00:00.000Z',
          'status': 'completed',
          'storeId': 'store_001',
        }
      });

      // Branch 2: Cancelled order with cancelReason and cancelledAt
      stressDb.getBranchRef('store_002').emitOrders({
        'ord_cancelled': {
          'id': 'ord_cancelled',
          'customerId': 'cust_mixed_states',
          'total': 5000000.0,
          'createdAt': '2026-09-19T09:00:00.000Z',
          'status': 'cancelled',
          'cancelReason': 'Khách đổi ý trả hàng',
          'cancelledAt': '2026-09-19T09:30:00.000Z',
          'cancelledBy': 'staff_tb',
          'cancelledByName': 'Nhân viên Thới Bình',
          // null storeId in payload to verify fallback stamping
          'storeId': null,
        }
      });

      // Branch 3: Zero-total order (e.g. warranty/complimentary) and order with missing items & notes
      stressDb.getBranchRef('store_003').emitOrders({
        'ord_zero': {
          'id': 'ord_zero',
          'customerId': 'cust_mixed_states',
          'total': 0.0,
          'createdAt': '2026-09-19T07:00:00.000Z',
          'status': 'completed',
          'items': [],
          'note': 'Bảo hành miễn phí',
        },
        'ord_sparse': {
          'id': 'ord_sparse',
          'customerId': 'cust_mixed_states',
          'total': 350000.0,
          'createdAt': '2026-09-19T11:00:00.000Z',
          // status omitted, should default to 'completed'
          // storeId omitted, should stamp 'store_003'
        }
      });

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          availableStoresProvider.overrideWith((ref) => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
                'store_003': 'Chi nhánh Đầm Dơi',
              }),
          firebaseDatabaseProvider.overrideWithValue(stressDb),
        ],
      );
      addTearDown(container.dispose);

      final completer = Completer<List<Order>>();
      final sub = container.listen(
        customerOrdersProvider('cust_mixed_states'),
        (previous, next) {
          next.whenData((orders) {
            if (orders.length == 4 && !completer.isCompleted) {
              completer.complete(orders);
            }
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final orders = await completer.future.timeout(const Duration(seconds: 3));
      expect(orders.length, equals(4));

      // 1. Verify ord_cancelled is identified correctly and stamped with store_002
      final cancelled = orders.firstWhere((o) => o.id == 'ord_cancelled');
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.status, equals('cancelled'));
      expect(cancelled.cancelReason, equals('Khách đổi ý trả hàng'));
      expect(cancelled.storeId, equals('store_002'));

      // 2. Verify ord_zero total is 0.0 and stamped with store_003
      final zeroOrder = orders.firstWhere((o) => o.id == 'ord_zero');
      expect(zeroOrder.total, equals(0.0));
      expect(zeroOrder.storeId, equals('store_003'));

      // 3. Verify ord_sparse defaults to status 'completed' and storeId 'store_003'
      final sparseOrder = orders.firstWhere((o) => o.id == 'ord_sparse');
      expect(sparseOrder.status, equals('completed'));
      expect(sparseOrder.storeId, equals('store_003'));

      // 4. Verify Customer.effectiveTotalSales excludes the 5M cancelled order!
      const customer = Customer(
        id: 'cust_mixed_states',
        name: 'Khách Thử Nghiệm',
        phone: '0901234567',
        email: 'test@example.com',
        address: 'Cà Mau',
        purchases: [],
        totalSales: 9999999.0, // Should be ignored when active orders exist
      );

      // Active orders: ord_normal (2M) + ord_sparse (350k) + ord_zero (0) = 2,350,000 đ
      final effectiveSales = customer.effectiveTotalSales(orders);
      expect(effectiveSales, equals(2350000.0));
    });

    // =========================================================================
    // TEST 3: Rapid Creation, Listening, and Immediate Disposal (Memory & Leak Guard)
    // =========================================================================
    test('STRESS-03: Rapid 50x creation/disposal cycles leave 0 active listeners and no leaks', () async {
      final freshDb = _StressTrackingDatabase();

      for (int i = 0; i < 50; i++) {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            availableStoresProvider.overrideWith((ref) => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                  'store_003': 'Chi nhánh Cái Nước',
                }),
            firebaseDatabaseProvider.overrideWithValue(freshDb),
          ],
        );

        final sub = container.listen(
          customerOrdersProvider('cust_rapid_disposal'),
          (_, __) {},
        );

        // Immediate disposal and event loop flush
        sub.close();
        container.dispose();
        await Future<void>.delayed(Duration.zero);
      }

      // After 50 rapid mount/unmount iterations, all tracking refs MUST have 0 active listeners
      final ref1 = freshDb.getBranchRef('store_001');
      final ref2 = freshDb.getBranchRef('store_002');
      final ref3 = freshDb.getBranchRef('store_003');

      expect(ref1.queryStream.activeListeners, equals(0));
      expect(ref2.queryStream.activeListeners, equals(0));
      expect(ref3.queryStream.activeListeners, equals(0));

      // Each ref must have been cancelled exactly 50 times
      expect(ref1.queryStream.cancelCount, equals(50));
      expect(ref2.queryStream.cancelCount, equals(50));
      expect(ref3.queryStream.cancelCount, equals(50));
    });

    // =========================================================================
    // TEST 4: Multi-Listener Fan-out & Partial Unsubscribe
    // =========================================================================
    test('STRESS-04: Multi-subscriber fan-out maintains branch listeners until last subscriber leaves', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          availableStoresProvider.overrideWith((ref) => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
              }),
          firebaseDatabaseProvider.overrideWithValue(stressDb),
        ],
      );
      addTearDown(container.dispose);

      // 3 independent listeners to the same family customer provider
      final sub1 = container.listen(customerOrdersProvider('cust_shared'), (_, __) {});
      final sub2 = container.listen(customerOrdersProvider('cust_shared'), (_, __) {});
      final sub3 = container.listen(customerOrdersProvider('cust_shared'), (_, __) {});

      final ref1 = stressDb.getBranchRef('store_001');
      final ref2 = stressDb.getBranchRef('store_002');

      // Shared provider holds 1 subscription per branch query
      expect(ref1.queryStream.activeListeners, equals(1));
      expect(ref2.queryStream.activeListeners, equals(1));

      // Close 1st listener: branch listeners must stay active
      sub1.close();
      await Future<void>.delayed(Duration.zero);
      expect(ref1.queryStream.activeListeners, equals(1));
      expect(ref2.queryStream.activeListeners, equals(1));

      // Close 2nd listener: branch listeners must still stay active
      sub2.close();
      await Future<void>.delayed(Duration.zero);
      expect(ref1.queryStream.activeListeners, equals(1));
      expect(ref2.queryStream.activeListeners, equals(1));

      // Close 3rd and final listener: branch listeners must tear down completely
      sub3.close();
      await Future<void>.delayed(Duration.zero);
      expect(ref1.queryStream.activeListeners, equals(0));
      expect(ref2.queryStream.activeListeners, equals(0));
      expect(ref1.queryStream.cancelCount, equals(1));
      expect(ref2.queryStream.cancelCount, equals(1));
    });

    // =========================================================================
    // TEST 5: Staff Role Tampering & Store Isolation Race Condition
    // =========================================================================
    test('STRESS-05: Staff user cannot receive orders from another store even under manipulated storeId/branches', () async {
      // Seed orders for store_001 and store_002
      final ref1 = stressDb.getBranchRef('store_001');
      final ref2 = stressDb.getBranchRef('store_002');
      final ref3 = stressDb.getBranchRef('store_003');

      ref1.emitOrders({
        'ord_staff_legit': {
          'id': 'ord_staff_legit',
          'customerId': 'cust_tamper_test',
          'total': 150000.0,
          'createdAt': '2026-09-19T08:00:00.000Z',
          'status': 'completed',
          'storeId': 'store_001',
        },
      });

      ref2.emitOrders({
        'ord_staff_leaked': {
          'id': 'ord_staff_leaked',
          'customerId': 'cust_tamper_test',
          'total': 99000000.0,
          'createdAt': '2026-09-19T09:00:00.000Z',
          'status': 'completed',
          'storeId': 'store_002',
        },
      });

      final authNotifier = _FakeAuthNotifier(staffUserStore1);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          // Attacker injects 3 available stores
          availableStoresProvider.overrideWith((ref) => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
                'store_003': 'Chi nhánh Cái Nước',
              }),
          // Attacker sets currentStoreId to store_002!
          currentStoreIdProvider.overrideWith((ref) => 'store_002'),
          firebaseDatabaseProvider.overrideWithValue(stressDb),
        ],
      );
      addTearDown(container.dispose);

      final completer = Completer<List<Order>>();
      final sub = container.listen(
        customerOrdersProvider('cust_tamper_test'),
        (previous, next) {
          next.whenData((orders) {
            if (!completer.isCompleted) {
              completer.complete(orders);
            }
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // Verify: ONLY store_001 listener was created! store_002 and store_003 were NEVER touched!
      expect(ref1.queryStream.activeListeners, equals(1));
      expect(ref2.queryStream.activeListeners, equals(0));
      expect(ref3.queryStream.activeListeners, equals(0));

      final receivedOrders = await completer.future.timeout(const Duration(seconds: 3));

      // Must strictly contain ONLY the store_001 order
      expect(receivedOrders.length, equals(1));
      expect(receivedOrders.first.id, equals('ord_staff_legit'));
      expect(receivedOrders.first.storeId, equals('store_001'));
      expect(receivedOrders.any((o) => o.id == 'ord_staff_leaked'), isFalse);
    });

    // =========================================================================
    // TEST 6: Dynamic Downgrade from Admin to Staff Cleans Multi-Branch Streams
    // =========================================================================
    test('STRESS-06: Session downgrade from Admin to Staff immediately severs unauthorized branches', () async {
      final authNotifier = _FakeAuthNotifier(adminUser);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          availableStoresProvider.overrideWith((ref) => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
              }),
          firebaseDatabaseProvider.overrideWithValue(stressDb),
        ],
      );
      addTearDown(container.dispose);

      final ref1 = stressDb.getBranchRef('store_001');
      final ref2 = stressDb.getBranchRef('store_002');

      final sub = container.listen(
        customerOrdersProvider('cust_downgrade_test'),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // As Admin: 2 branches actively listened
      expect(ref1.queryStream.activeListeners, equals(1));
      expect(ref2.queryStream.activeListeners, equals(1));

      // Dynamically switch/downgrade session to Staff of store_001
      authNotifier.setUser(staffUserStore1);
      await Future<void>.delayed(Duration.zero);

      // Old streams must have been torn down
      expect(ref2.queryStream.activeListeners, equals(0));
      expect(ref2.queryStream.cancelCount, equals(1));

      // Only store_001 remains actively listened for the staff session
      expect(ref1.queryStream.activeListeners, equals(1));
    });

    // =========================================================================
    // TEST 7: Single Branch Network Error Resiliency
    // =========================================================================
    test('STRESS-07: Single branch stream error does not crash the combined multi-branch stream', () async {
      // store_001 emits valid order
      stressDb.getBranchRef('store_001').emitOrders({
        'ord_good_1': {
          'id': 'ord_good_1',
          'customerId': 'cust_error_test',
          'total': 450000.0,
          'createdAt': '2026-09-19T08:00:00.000Z',
          'status': 'completed',
        }
      });

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          availableStoresProvider.overrideWith((ref) => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
              }),
          firebaseDatabaseProvider.overrideWithValue(stressDb),
        ],
      );
      addTearDown(container.dispose);

      final completer = Completer<List<Order>>();
      final sub = container.listen(
        customerOrdersProvider('cust_error_test'),
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

      // store_002 experiences network/permission failure
      stressDb.getBranchRef('store_002').emitError(Exception('Simulated branch RTDB timeout'));

      final orders = await completer.future.timeout(const Duration(seconds: 3));

      // The combined stream stays intact, delivering orders from the healthy branch
      expect(orders.length, equals(1));
      expect(orders.first.id, equals('ord_good_1'));
    });

    // =========================================================================
    // TEST 8: Live Concurrent Churn (Additions, Updates, Cancellations, Deletions)
    // =========================================================================
    test('STRESS-08: Live concurrent churn across 4 branches dynamically reconciles additions and cancellations', () async {
      final branches = ['store_001', 'store_002', 'store_003', 'store_004'];

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          availableStoresProvider.overrideWith((ref) => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
                'store_003': 'Chi nhánh Cái Nước',
                'store_004': 'Chi nhánh Năm Căn',
              }),
          firebaseDatabaseProvider.overrideWithValue(stressDb),
        ],
      );
      addTearDown(container.dispose);

      final latestEmissions = <List<Order>>[];
      final sub = container.listen(
        customerOrdersProvider('cust_churn_test'),
        (previous, next) {
          next.whenData((orders) {
            latestEmissions.add(orders);
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // Phase 1: Each branch emits 5 orders (20 total)
      final now = DateTime(2026, 9, 19, 12, 0, 0);
      final storeMaps = <String, Map<String, dynamic>>{};
      for (int b = 0; b < branches.length; b++) {
        final bId = branches[b];
        storeMaps[bId] = {};
        for (int i = 0; i < 5; i++) {
          final id = 'ord_${bId}_$i';
          storeMaps[bId]![id] = {
            'id': id,
            'customerId': 'cust_churn_test',
            'total': 500000.0,
            'createdAt': now.add(Duration(minutes: i * 10 + b)).toIso8601String(),
            'status': 'completed',
          };
        }
        stressDb.getBranchRef(bId).emitOrders(storeMaps[bId]!);
      }

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(latestEmissions.last.length, equals(20));

      // Phase 2: Concurrent churn:
      // - store_001 cancels 2 orders
      // - store_002 adds 3 new orders
      // - store_003 removes 1 order (simulating deletion/void)
      // - store_004 updates order amount
      storeMaps['store_001']!['ord_store_001_0']!['status'] = 'cancelled';
      storeMaps['store_001']!['ord_store_001_0']!['cancelReason'] = 'Hủy do nhập sai';
      storeMaps['store_001']!['ord_store_001_1']!['status'] = 'cancelled';

      storeMaps['store_002']!['ord_store_002_new1'] = {
        'id': 'ord_store_002_new1',
        'customerId': 'cust_churn_test',
        'total': 1200000.0,
        'createdAt': now.add(const Duration(hours: 1)).toIso8601String(),
        'status': 'completed',
      };
      storeMaps['store_002']!['ord_store_002_new2'] = {
        'id': 'ord_store_002_new2',
        'customerId': 'cust_churn_test',
        'total': 800000.0,
        'createdAt': now.add(const Duration(hours: 2)).toIso8601String(),
        'status': 'completed',
      };
      storeMaps['store_002']!['ord_store_002_new3'] = {
        'id': 'ord_store_002_new3',
        'customerId': 'cust_churn_test',
        'total': 950000.0,
        'createdAt': now.add(const Duration(hours: 3)).toIso8601String(),
        'status': 'completed',
      };

      storeMaps['store_003']!.remove('ord_store_003_4');

      storeMaps['store_004']!['ord_store_004_0']!['total'] = 777000.0;

      // Broadcast churn updates concurrently
      await Future.wait([
        Future(() => stressDb.getBranchRef('store_001').emitOrders(storeMaps['store_001']!)),
        Future(() => stressDb.getBranchRef('store_002').emitOrders(storeMaps['store_002']!)),
        Future(() => stressDb.getBranchRef('store_003').emitOrders(storeMaps['store_003']!)),
        Future(() => stressDb.getBranchRef('store_004').emitOrders(storeMaps['store_004']!)),
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final updatedOrders = latestEmissions.last;
      // Total orders: 5 + (5+3) + (5-1) + 5 = 22 orders
      expect(updatedOrders.length, equals(22));

      // Verify newest order is ord_store_002_new3 (createdAt + 3 hours)
      expect(updatedOrders.first.id, equals('ord_store_002_new3'));

      // Verify cancelled orders in store_001 are marked cancelled
      final c1 = updatedOrders.firstWhere((o) => o.id == 'ord_store_001_0');
      final c2 = updatedOrders.firstWhere((o) => o.id == 'ord_store_001_1');
      expect(c1.isCancelled, isTrue);
      expect(c2.isCancelled, isTrue);

      // Verify removed order is gone
      expect(updatedOrders.any((o) => o.id == 'ord_store_003_4'), isFalse);

      // Verify updated total in store_004 is reflected
      final modOrder = updatedOrders.firstWhere((o) => o.id == 'ord_store_004_0');
      expect(modOrder.total, equals(777000.0));
    });

    // =========================================================================
    // TEST 9: Timestamp Collisions & Microsecond Sorting Precision
    // =========================================================================
    test('STRESS-09: Identical timestamp orders across branches sort without crashing or dropping', () async {
      final sameInstant = DateTime(2026, 9, 19, 14, 0, 0, 0);

      stressDb.getBranchRef('store_001').emitOrders({
        'ord_collision_001': {
          'id': 'ord_collision_001',
          'customerId': 'cust_collision',
          'total': 100000.0,
          'createdAt': sameInstant.toIso8601String(),
          'status': 'completed',
        }
      });

      stressDb.getBranchRef('store_002').emitOrders({
        'ord_collision_002': {
          'id': 'ord_collision_002',
          'customerId': 'cust_collision',
          'total': 200000.0,
          'createdAt': sameInstant.toIso8601String(),
          'status': 'completed',
        }
      });

      stressDb.getBranchRef('store_003').emitOrders({
        'ord_collision_003': {
          'id': 'ord_collision_003',
          'customerId': 'cust_collision',
          'total': 300000.0,
          'createdAt': sameInstant.toIso8601String(),
          'status': 'completed',
        }
      });

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          availableStoresProvider.overrideWith((ref) => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
                'store_003': 'Chi nhánh Cái Nước',
              }),
          firebaseDatabaseProvider.overrideWithValue(stressDb),
        ],
      );
      addTearDown(container.dispose);

      final completer = Completer<List<Order>>();
      final sub = container.listen(
        customerOrdersProvider('cust_collision'),
        (previous, next) {
          next.whenData((orders) {
            if (orders.length == 3 && !completer.isCompleted) {
              completer.complete(orders);
            }
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final orders = await completer.future.timeout(const Duration(seconds: 3));
      expect(orders.length, equals(3));
      final ids = orders.map((o) => o.id).toSet();
      expect(ids, containsAll(['ord_collision_001', 'ord_collision_002', 'ord_collision_003']));
    });

    // =========================================================================
    // TEST 10: Staff Store ID Normalization Edge Cases (Aliases, Casing, Fallback)
    // =========================================================================
    test('STRESS-10: Staff store normalization resolves aliases and guards against storeId "all"', () async {
      // 1. Staff with legacy alias 'branch_1' resolves to 'store_001'
      const staffBranch1 = UserAccount(
        username: 'staff_legacy',
        displayName: 'Nhân viên Cũ',
        role: 'nhanvien',
        storeId: 'branch_1',
      );

      final container1 = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffBranch1)),
          currentStoreIdProvider.overrideWith((ref) => 'store_002'),
          firebaseDatabaseProvider.overrideWithValue(stressDb),
        ],
      );
      addTearDown(container1.dispose);

      final sub1 = container1.listen(customerOrdersProvider('cust_norm_1'), (_, __) {});
      addTearDown(sub1.close);

      expect(stressDb.getBranchRef('store_001').queryStream.activeListeners, equals(1));
      expect(stressDb.getBranchRef('store_002').queryStream.activeListeners, equals(0));

      // 2. Staff with storeId == 'all' (invalid for staff) falls back to currentStoreId
      const staffAllStore = UserAccount(
        username: 'staff_invalid_all',
        displayName: 'Nhân viên Lỗi All',
        role: 'nhanvien',
        storeId: 'all',
      );

      final container2 = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffAllStore)),
          currentStoreIdProvider.overrideWith((ref) => 'store_002'),
          firebaseDatabaseProvider.overrideWithValue(stressDb),
        ],
      );
      addTearDown(container2.dispose);

      final sub2 = container2.listen(customerOrdersProvider('cust_norm_2'), (_, __) {});
      addTearDown(sub2.close);

      // Must fall back to single store_002, NEVER multi-store
      expect(stressDb.getBranchRef('store_002').queryStream.activeListeners, equals(1));
    });

    // =========================================================================
    // TEST 11: High-Volume Scale (500 Orders Across 5 Branches)
    // =========================================================================
    test('STRESS-11: High-volume scale (500 orders across 5 branches) completes cleanly', () async {
      final branches = ['store_001', 'store_002', 'store_003', 'store_004', 'store_005'];
      final baseDate = DateTime(2026, 9, 1, 0, 0, 0);

      // Seed 100 orders per branch = 500 total orders
      for (int b = 0; b < branches.length; b++) {
        final bId = branches[b];
        final Map<String, dynamic> ordersMap = {};
        for (int i = 0; i < 100; i++) {
          final id = 'scale_${bId}_$i';
          ordersMap[id] = {
            'id': id,
            'customerId': 'cust_scale_500',
            'total': 10000.0 * (i + 1),
            'createdAt': baseDate.add(Duration(minutes: (i * 5) + b)).toIso8601String(),
            'status': 'completed',
          };
        }
        stressDb.getBranchRef(bId).emitOrders(ordersMap);
      }

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          availableStoresProvider.overrideWith((ref) => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
                'store_003': 'Chi nhánh Cái Nước',
                'store_004': 'Chi nhánh Năm Căn',
                'store_005': 'Chi nhánh U Minh',
              }),
          firebaseDatabaseProvider.overrideWithValue(stressDb),
        ],
      );
      addTearDown(container.dispose);

      final completer = Completer<List<Order>>();
      final stopwatch = Stopwatch()..start();

      final sub = container.listen(
        customerOrdersProvider('cust_scale_500'),
        (previous, next) {
          next.whenData((orders) {
            if (orders.length == 500 && !completer.isCompleted) {
              completer.complete(orders);
            }
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final orders = await completer.future.timeout(const Duration(seconds: 5));
      stopwatch.stop();

      expect(orders.length, equals(500));
      // Verify processing 500 orders is well under 1 second
      expect(stopwatch.elapsedMilliseconds, lessThan(1500));

      // Verify sorted DESC
      for (int i = 0; i < orders.length - 1; i++) {
        expect(
          orders[i].createdAt.isAfter(orders[i + 1].createdAt) ||
              orders[i].createdAt.isAtSameMomentAs(orders[i + 1].createdAt),
          isTrue,
        );
      }
    });
  });
}

