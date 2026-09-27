import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/suppliers/usecases/import_suppliers_usecase.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

class _FakeSupplierRepository implements SupplierRepository {
  final Map<String, Supplier> storage = {};

  _FakeSupplierRepository([List<Supplier> initial = const []]) {
    for (final s in initial) {
      storage[s.id] = s;
    }
  }

  @override
  Stream<List<Supplier>> watchAll({String? storeId}) =>
      Stream.value(storage.values.toList());

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async => storage[id];

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    storage[supplier.id] = supplier;
  }

  @override
  Future<void> delete(String id, {String? storeId}) async {
    storage.remove(id);
  }

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction transaction,
      {String? storeId}) async {}

  @override
  Stream<List<SupplierDebtTransaction>> watchDebtTransactions(String supplierId,
          {String? storeId}) =>
      Stream.value([]);

  @override
  Future<List<SupplierDebtTransaction>> fetchDebtTransactions(String supplierId,
          {String? storeId}) async =>
      [];
}

void main() {
  group('ImportSuppliersUseCase Tests', () {
    late _FakeSupplierRepository supplierRepo;
    late ImportSuppliersUseCase useCase;

    setUp(() {
      supplierRepo = _FakeSupplierRepository();
      useCase = ImportSuppliersUseCase(supplierRepository: supplierRepo);
    });

    test('Empty list returns empty ImportResult', () async {
      final result = await useCase.execute(suppliers: []);
      expect(result.total, 0);
      expect(result.added, 0);
      expect(result.updated, 0);
      expect(result.skipped, 0);
      expect(result.errors, 0);
      expect(result.isSuccess, isTrue);
    });

    test('New supplier is inserted successfully', () async {
      const newSupplier = Supplier(
        id: 'sup_new_01',
        code: 'NCC01',
        name: 'Công ty TNHH Thiết bị Số',
        phone: '0912345678',
        email: 'sales@thietbiso.vn',
        address: 'Hà Nội',
        currentDebt: 0.0,
      );

      final result = await useCase.execute(suppliers: [newSupplier]);

      expect(result.total, 1);
      expect(result.added, 1);
      expect(result.updated, 0);
      expect(result.errors, 0);

      final stored = await supplierRepo.fetchById('sup_new_01');
      expect(stored, isNotNull);
      expect(stored!.name, 'Công ty TNHH Thiết bị Số');
      expect(stored.code, 'NCC01');
    });

    test(
        'Duplicate by ID updates contact info and strictly preserves currentDebt and totalPurchase',
        () async {
      const existing = Supplier(
        id: 'sup_existing_1',
        code: 'NCC_APPLE',
        name: 'Apple Vietnam LLC',
        phone: '0901112233',
        email: 'old_contact@apple.com',
        address: 'Quận 1, TP. HCM',
        taxCode: '0312345678',
        currentDebt: 85000000.0,
        totalPurchase: 500000000.0,
        note: 'Đối tác chiến lược',
      );
      await supplierRepo.upsert(existing);

      const imported = Supplier(
        id: 'sup_existing_1',
        code: 'NCC_APPLE',
        name: 'Apple Vietnam LLC (Đại diện mới)',
        phone: '0909998877',
        email: 'new_contact@apple.com',
        address: 'Quận 7, TP. HCM',
        taxCode: '0312345678',
        currentDebt: 0.0, // Should NOT wipe out 85,000,000 debt
        totalPurchase: 0.0, // Should NOT wipe out 500,000,000 purchase
        note: 'Cập nhật đại diện kinh doanh',
      );

      final result = await useCase.execute(suppliers: [imported]);

      expect(result.total, 1);
      expect(result.updated, 1);
      expect(result.added, 0);

      final stored = await supplierRepo.fetchById('sup_existing_1');
      expect(stored, isNotNull);

      // Contact info updated:
      expect(stored!.name, 'Apple Vietnam LLC (Đại diện mới)');
      expect(stored.phone, '0909998877');
      expect(stored.email, 'new_contact@apple.com');
      expect(stored.address, 'Quận 7, TP. HCM');
      expect(stored.note, 'Cập nhật đại diện kinh doanh');

      // CRITICAL PRESERVATION:
      expect(stored.currentDebt, 85000000.0);
      expect(stored.totalPurchase, 500000000.0);
    });

    test('Duplicate by Code matches case-insensitively and preserves debt',
        () async {
      const existing = Supplier(
        id: 'sup_code_match',
        code: 'SAMSUNG_VN',
        name: 'Samsung Electronics',
        phone: '0944556677',
        currentDebt: 42000000.0,
        totalPurchase: 200000000.0,
      );
      await supplierRepo.upsert(existing);

      const imported = Supplier(
        id: 'sup_generated_random_id',
        code: 'samsung_vn', // lowercase match
        name: 'Samsung Electronics Vietnam',
        phone: '0944556677',
        currentDebt: 0.0,
        totalPurchase: 0.0,
      );

      final result = await useCase.execute(suppliers: [imported]);

      expect(result.updated, 1);
      expect(result.added, 0);

      final stored = await supplierRepo.fetchById('sup_code_match');
      expect(stored, isNotNull);
      expect(stored!.name, 'Samsung Electronics Vietnam');
      expect(stored.currentDebt, 42000000.0);
      expect(stored.totalPurchase, 200000000.0);
    });

    test(
        'Duplicate by Phone matches normalized phone and preserves debt and code',
        () async {
      const existing = Supplier(
        id: 'sup_phone_match',
        code: 'NCC_XIAOMI',
        name: 'Xiaomi Store',
        phone: '0988112233',
        currentDebt: 15000000.0,
        totalPurchase: 80000000.0,
      );
      await supplierRepo.upsert(existing);

      const imported = Supplier(
        id: 'sup_different_id',
        code: 'NCC_DIFF_CODE',
        name: 'Xiaomi Store Official',
        phone: '+84 988 112 233', // formatted phone
        currentDebt: 0.0,
      );

      final result = await useCase.execute(suppliers: [imported]);

      expect(result.updated, 1);
      expect(result.added, 0);

      final stored = await supplierRepo.fetchById('sup_phone_match');
      expect(stored, isNotNull);
      expect(stored!.name, 'Xiaomi Store Official');
      expect(stored.code, 'NCC_XIAOMI'); // Preserved original code
      expect(stored.currentDebt, 15000000.0); // Preserved debt
    });

    test('Summary string matches standard format', () async {
      const s1 = Supplier(
        id: 'sup_sum_1',
        code: 'S01',
        name: 'Supplier 1',
        currentDebt: 1000,
      );
      await supplierRepo.upsert(s1);

      const imported1 = Supplier(
        id: 'sup_sum_1',
        code: 'S01',
        name: 'Supplier 1 Updated',
      );
      const imported2 = Supplier(
        id: 'sup_sum_2',
        code: 'S02',
        name: 'Supplier 2 New',
      );

      final result =
          await useCase.execute(suppliers: [imported1, imported2]);

      expect(result.total, 2);
      expect(result.added, 1);
      expect(result.updated, 1);
      expect(
        result.toSummaryString(),
        'Tổng số dòng: 2 | Thêm mới: 1 | Cập nhật: 1 | Bỏ qua: 0 | Lỗi: 0',
      );
    });
  });
}
