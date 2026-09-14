import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/supplier_remote_data_source.dart';
import 'package:stores/data/repositories/supplier_repository_impl.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';

class _FakeSupplierRemoteDataSource implements SupplierRemoteDataSource {
  final Map<String, Map<String, dynamic>> _storage = {};
  final Map<String, Map<String, Map<String, dynamic>>> _debtStorage = {};
  final StreamController<List<Map>> _streamController =
      StreamController<List<Map>>.broadcast();
  final Map<String, StreamController<List<Map>>> _debtControllers = {};

  void emitAll() {
    _streamController.add(_storage.values.toList());
  }

  void emitDebts(String supplierId) {
    final list = _debtStorage[supplierId]?.values.toList() ?? [];
    _debtControllers[supplierId]?.add(list);
  }

  @override
  Stream<List<Map>> watchAll({String? storeId}) {
    // Schedule initial emit
    Future.microtask(() => emitAll());
    return _streamController.stream;
  }

  @override
  Future<Map?> fetchById(String id, {String? storeId}) async {
    return _storage[id];
  }

  @override
  Future<void> upsert(String id, Map<String, dynamic> map, {String? storeId}) async {
    _storage[id] = Map<String, dynamic>.from(map);
    emitAll();
  }

  @override
  Future<void> delete(String id, {String? storeId}) async {
    _storage.remove(id);
    emitAll();
  }

  @override
  Future<void> saveDebtTransaction(
    String supplierId,
    Map<String, dynamic> map, {
    String? storeId,
  }) async {
    final id = map['id']?.toString() ?? 'TX_${DateTime.now().millisecondsSinceEpoch}';
    _debtStorage.putIfAbsent(supplierId, () => {})[id] = Map<String, dynamic>.from(map);

    if (map.containsKey('remainingDebt') && _storage.containsKey(supplierId)) {
      _storage[supplierId]!['currentDebt'] = map['remainingDebt'];
      emitAll();
    }

    emitDebts(supplierId);
  }

  @override
  Stream<List<Map>> watchDebtTransactions(String supplierId, {String? storeId}) {
    final controller = _debtControllers.putIfAbsent(
      supplierId,
      () => StreamController<List<Map>>.broadcast(),
    );
    Future.microtask(() => emitDebts(supplierId));
    return controller.stream;
  }

  @override
  Future<List<Map>> fetchDebtTransactions(String supplierId, {String? storeId}) async {
    return _debtStorage[supplierId]?.values.toList() ?? [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupplierRepositoryImpl Tests', () {
    late _FakeSupplierRemoteDataSource fakeDs;
    late SupplierRepositoryImpl repository;

    setUp(() {
      fakeDs = _FakeSupplierRemoteDataSource();
      repository = SupplierRepositoryImpl(fakeDs);
    });

    const testSupplier = Supplier(
      id: 'NCC000001',
      code: 'NCC000001',
      name: 'Công ty Digiworld',
      phone: '02839291234',
      email: 'contact@digiworld.com.vn',
      address: '195 Cô Bắc, Q.1, TP.HCM',
      taxCode: '0302861742',
      totalPurchase: 145000000.0,
      currentDebt: 32500000.0,
      status: 'active',
      branch: 'store_001',
    );

    test('upsert, fetchById, and delete', () async {
      // Initially empty
      expect(await repository.fetchById('NCC000001'), isNull);

      // Upsert
      await repository.upsert(testSupplier);
      final fetched = await repository.fetchById('NCC000001');
      expect(fetched, isNotNull);
      expect(fetched!.id, 'NCC000001');
      expect(fetched.name, 'Công ty Digiworld');
      expect(fetched.currentDebt, 32500000.0);

      // Delete
      await repository.delete('NCC000001');
      expect(await repository.fetchById('NCC000001'), isNull);
    });

    test('watchAll emits stream of suppliers', () async {
      await repository.upsert(testSupplier);
      await repository.upsert(const Supplier(
        id: 'NCC000002',
        code: 'NCC000002',
        name: 'Công ty Synnex FPT',
      ));

      final streamList = await repository.watchAll().first;
      expect(streamList.length, 2);
      expect(streamList.map((s) => s.id), containsAll(['NCC000001', 'NCC000002']));
    });

    test('recordDebtTransaction and watchDebtTransactions/fetchDebtTransactions', () async {
      await repository.upsert(testSupplier);

      final tx1 = SupplierDebtTransaction(
        id: 'TX_01',
        supplierId: 'NCC000001',
        date: DateTime(2026, 8, 10),
        type: SupplierDebtType.importBill,
        amount: 32500000.0,
        remainingDebt: 32500000.0,
        referenceCode: 'PN001',
      );

      final tx2 = SupplierDebtTransaction(
        id: 'TX_02',
        supplierId: 'NCC000001',
        date: DateTime(2026, 8, 15),
        type: SupplierDebtType.payment,
        amount: -12500000.0,
        remainingDebt: 20000000.0,
        referenceCode: 'PC001',
      );

      await repository.recordDebtTransaction(tx1);
      await repository.recordDebtTransaction(tx2);

      final fetchedTxs = await repository.fetchDebtTransactions('NCC000001');
      expect(fetchedTxs.length, 2);
      // Verify sorted latest first
      expect(fetchedTxs[0].id, 'TX_02');
      expect(fetchedTxs[1].id, 'TX_01');

      final streamTxs = await repository.watchDebtTransactions('NCC000001').first;
      expect(streamTxs.length, 2);
      expect(streamTxs[0].id, 'TX_02');
    });
  });
}
