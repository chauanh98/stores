import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/core/utils/code_generator_helper.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

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

class _FakeSupplierRepository implements SupplierRepository {
  final Map<String, Supplier> _suppliers = {};
  final Map<String, List<SupplierDebtTransaction>> _debtTxs = {};
  final StreamController<List<Supplier>> _streamController =
      StreamController<List<Supplier>>.broadcast();
  final Map<String, StreamController<List<SupplierDebtTransaction>>>
      _debtStreamControllers = {};

  void _notify() {
    _streamController.add(_suppliers.values.toList());
  }

  void _notifyDebt(String supplierId) {
    final list = _debtTxs[supplierId] ?? [];
    list.sort((a, b) => b.date.compareTo(a.date));
    _debtStreamControllers[supplierId]?.add(list);
  }

  @override
  Stream<List<Supplier>> watchAll({String? storeId}) {
    Future.microtask(() => _notify());
    return _streamController.stream;
  }

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async {
    return _suppliers[id];
  }

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    _suppliers[supplier.id] = supplier;
    _notify();
  }

  @override
  Future<void> delete(String id, {String? storeId}) async {
    _suppliers.remove(id);
    _notify();
  }

  @override
  Future<void> recordDebtTransaction(
    SupplierDebtTransaction transaction, {
    String? storeId,
  }) async {
    _debtTxs.putIfAbsent(transaction.supplierId, () => []).add(transaction);
    _notifyDebt(transaction.supplierId);
  }

  @override
  Stream<List<SupplierDebtTransaction>> watchDebtTransactions(
    String supplierId, {
    String? storeId,
  }) {
    final controller = _debtStreamControllers.putIfAbsent(
      supplierId,
      () => StreamController<List<SupplierDebtTransaction>>.broadcast(),
    );
    Future.microtask(() => _notifyDebt(supplierId));
    return controller.stream;
  }

  @override
  Future<List<SupplierDebtTransaction>> fetchDebtTransactions(
    String supplierId, {
    String? storeId,
  }) async {
    final list = _debtTxs[supplierId] ?? [];
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const staffUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  group('Supplier Providers & Notifier Tests', () {
    late _FakeSupplierRepository fakeRepo;
    late ProviderContainer container;

    const s1 = Supplier(
      id: 'NCC000001',
      code: 'NCC000001',
      name: 'Công ty Cổ phần Thế Giới Số (Digiworld)',
      phone: '02839291234',
      email: 'contact@digiworld.com.vn',
      address: '195 Cô Bắc, Quận 1, TP.HCM',
      totalPurchase: 100000000.0,
      currentDebt: 30000000.0,
    );

    const s2 = Supplier(
      id: 'NCC000002',
      code: 'NCC000002',
      name: 'Công ty TNHH Synnex FPT',
      phone: '02473006666',
      email: 'fpt@synnex.com',
      address: 'Phố Duy Tân, Cầu Giấy, Hà Nội',
      totalPurchase: 50000000.0,
      currentDebt: 0.0,
    );

    const s3 = Supplier(
      id: 'NCC000003',
      code: 'NCC000003',
      name: 'Samsung Electronics Việt Nam',
      phone: '02838217300',
      email: 'samsung@vn.com',
      address: 'Hải Triều, Quận 1, TP.HCM',
      totalPurchase: 80000000.0,
      currentDebt: 12000000.0,
    );

    setUp(() {
      fakeRepo = _FakeSupplierRepository();
      fakeRepo.upsert(s1);
      fakeRepo.upsert(s2);
      fakeRepo.upsert(s3);

      container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
          currentStoreIdProvider.overrideWithValue('store_001'),
          supplierRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('SupplierListNotifier builds initial list and provides KPIs', () async {
      final list = await container.read(supplierListNotifierProvider.future);
      expect(list.length, 3);

      final kpis = container.read(supplierKpisProvider);
      expect(kpis.totalSuppliers, 3);
      expect(kpis.totalPurchase, 230000000.0);
      expect(kpis.totalDebt, 42000000.0);
    });

    test('Filter suppliers by Vietnamese unaccented search and debt status', () async {
      await container.read(supplierListNotifierProvider.future);

      // Search by unaccented Vietnamese name "the gioi so"
      container.read(supplierSearchQueryProvider.notifier).state = 'the gioi so';
      var filtered = container.read(filteredSuppliersProvider).value!;
      expect(filtered.length, 1);
      expect(filtered.first.id, 'NCC000001');

      // Search by phone
      container.read(supplierSearchQueryProvider.notifier).state = '0247300';
      filtered = container.read(filteredSuppliersProvider).value!;
      expect(filtered.length, 1);
      expect(filtered.first.id, 'NCC000002');

      // Reset search, test status hasDebt
      container.read(supplierSearchQueryProvider.notifier).state = '';
      container.read(supplierFilterStatusProvider.notifier).state = SupplierFilterStatus.hasDebt;
      filtered = container.read(filteredSuppliersProvider).value!;
      expect(filtered.length, 2);
      expect(filtered.map((s) => s.id), containsAll(['NCC000001', 'NCC000003']));

      // Test status noDebt
      container.read(supplierFilterStatusProvider.notifier).state = SupplierFilterStatus.noDebt;
      filtered = container.read(filteredSuppliersProvider).value!;
      expect(filtered.length, 1);
      expect(filtered.first.id, 'NCC000002');
    });

    test('SupplierListNotifier upsert and delete operations', () async {
      final notifier = container.read(supplierListNotifierProvider.notifier);
      await container.read(supplierListNotifierProvider.future);

      // Create new supplier
      const newSupplier = Supplier(
        id: 'NCC000004',
        code: 'NCC000004',
        name: 'Nhà cung cấp An Phát',
        totalPurchase: 10000000.0,
        currentDebt: 5000000.0,
      );

      await notifier.upsertSupplier(newSupplier);
      var list = await container.read(supplierListNotifierProvider.future);
      expect(list.length, 4);
      expect(list.any((s) => s.id == 'NCC000004'), isTrue);

      // Delete supplier
      await notifier.deleteSupplier('NCC000004');
      list = await container.read(supplierListNotifierProvider.future);
      expect(list.length, 3);
      expect(list.any((s) => s.id == 'NCC000004'), isFalse);
    });

    test('recordDebtPayment reduces debt and records transaction', () async {
      final notifier = container.read(supplierListNotifierProvider.notifier);
      await container.read(supplierListNotifierProvider.future);

      // Supplier NCC000001 has currentDebt = 30,000,000
      await notifier.recordDebtPayment(
        supplierId: 'NCC000001',
        paymentAmount: 10000000.0,
        referenceCode: 'PC001',
        note: 'Trả bớt nợ',
      );

      final updatedSupplier = await fakeRepo.fetchById('NCC000001');
      expect(updatedSupplier!.currentDebt, 20000000.0);

      final txs = await fakeRepo.fetchDebtTransactions('NCC000001');
      expect(txs.length, 1);
      expect(txs.first.type, SupplierDebtType.payment);
      expect(txs.first.amount, -10000000.0);
      expect(txs.first.remainingDebt, 20000000.0);
    });

    test('recordDebtAdjustment sets new debt and records difference', () async {
      final notifier = container.read(supplierListNotifierProvider.notifier);
      await container.read(supplierListNotifierProvider.future);

      // Supplier NCC000001 currentDebt = 30,000,000. Adjust to 28,000,000 (diff -2,000,000)
      await notifier.recordDebtAdjustment(
        supplierId: 'NCC000001',
        newDebt: 28000000.0,
        note: 'Chiết khấu bổ sung',
      );

      final updatedSupplier = await fakeRepo.fetchById('NCC000001');
      expect(updatedSupplier!.currentDebt, 28000000.0);

      final txs = await fakeRepo.fetchDebtTransactions('NCC000001');
      expect(txs.first.type, SupplierDebtType.adjustment);
      expect(txs.first.amount, -2000000.0);
      expect(txs.first.remainingDebt, 28000000.0);
    });

    test('recordImportDebt increases purchase total and debt for unpaid amount', () async {
      final notifier = container.read(supplierListNotifierProvider.notifier);
      await container.read(supplierListNotifierProvider.future);

      // Supplier NCC000002 has totalPurchase = 50,000,000, currentDebt = 0
      // Import 20,000,000 with 5,000,000 paid -> debt increases by 15,000,000
      await notifier.recordImportDebt(
        supplierId: 'NCC000002',
        totalAmount: 20000000.0,
        paidAmount: 5000000.0,
        importCode: 'PN0001',
      );

      final updatedSupplier = await fakeRepo.fetchById('NCC000002');
      expect(updatedSupplier!.totalPurchase, 70000000.0);
      expect(updatedSupplier.currentDebt, 15000000.0);

      final txs = await fakeRepo.fetchDebtTransactions('NCC000002');
      expect(txs.length, 1);
      expect(txs.first.type, SupplierDebtType.importBill);
      expect(txs.first.amount, 15000000.0);
      expect(txs.first.remainingDebt, 15000000.0);
    });

    test('CodeGeneratorHelper generates consecutive supplier codes', () {
      final codes = ['NCC000001', 'NCC000002', 'NCC000003'];
      final next = CodeGeneratorHelper.generateNextSupplierCode(codes);
      expect(next, 'NCC000004');

      final emptyNext = CodeGeneratorHelper.generateNextSupplierCode([]);
      expect(emptyNext, 'NCC000001');

      final unorderedNext = CodeGeneratorHelper.generateNextSupplierCode(['NCC000010', 'NCC000002']);
      expect(unorderedNext, 'NCC000011');
    });
  });
}
