import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/supplier.dart';

void main() {
  group('Supplier Entity Tests', () {
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
      note: 'Nhà phân phối chính hãng Apple, Xiaomi',
      status: 'active',
      branch: 'store_001',
      createdAt: '2026-05-15T08:00:00.000Z',
      createdBy: 'Admin',
    );

    test('Supplier default values and getters', () {
      const minimalSupplier = Supplier(
        id: 'NCC000002',
        code: 'NCC000002',
        name: 'Nhà cung cấp ABC',
      );

      expect(minimalSupplier.id, 'NCC000002');
      expect(minimalSupplier.code, 'NCC000002');
      expect(minimalSupplier.name, 'Nhà cung cấp ABC');
      expect(minimalSupplier.phone, '');
      expect(minimalSupplier.email, '');
      expect(minimalSupplier.address, '');
      expect(minimalSupplier.taxCode, isNull);
      expect(minimalSupplier.totalPurchase, 0.0);
      expect(minimalSupplier.currentDebt, 0.0);
      expect(minimalSupplier.note, isNull);
      expect(minimalSupplier.status, 'active');
      expect(minimalSupplier.isActive, isTrue);
      expect(minimalSupplier.hasDebt, isFalse);
    });

    test('Supplier isActive handles active and numeric 1', () {
      final active1 = testSupplier.copyWith(status: 'active');
      final active2 = testSupplier.copyWith(status: '1');
      final inactive = testSupplier.copyWith(status: 'inactive');

      expect(active1.isActive, isTrue);
      expect(active2.isActive, isTrue);
      expect(inactive.isActive, isFalse);
    });

    test('Supplier hasDebt calculates correctly', () {
      final withDebt = testSupplier.copyWith(currentDebt: 500000.0);
      final zeroDebt = testSupplier.copyWith(currentDebt: 0.0);
      final negativeDebt = testSupplier.copyWith(currentDebt: -100.0);

      expect(withDebt.hasDebt, isTrue);
      expect(zeroDebt.hasDebt, isFalse);
      expect(negativeDebt.hasDebt, isFalse);
    });

    test('copyWith updates specified fields and preserves untouched fields', () {
      final updated = testSupplier.copyWith(
        name: 'Digiworld Corporation Updated',
        currentDebt: 20000000.0,
        totalPurchase: 200000000.0,
        note: 'Cập nhật hợp đồng mới',
      );

      expect(updated.id, 'NCC000001');
      expect(updated.code, 'NCC000001');
      expect(updated.name, 'Digiworld Corporation Updated');
      expect(updated.phone, '02839291234');
      expect(updated.email, 'contact@digiworld.com.vn');
      expect(updated.address, '195 Cô Bắc, Q.1, TP.HCM');
      expect(updated.taxCode, '0302861742');
      expect(updated.totalPurchase, 200000000.0);
      expect(updated.currentDebt, 20000000.0);
      expect(updated.note, 'Cập nhật hợp đồng mới');
      expect(updated.status, 'active');
      expect(updated.branch, 'store_001');
      expect(updated.createdAt, '2026-05-15T08:00:00.000Z');
      expect(updated.createdBy, 'Admin');
    });

    test('Equality and hashCode comparison', () {
      const copy1 = Supplier(
        id: 'NCC000001',
        code: 'NCC000001',
        name: 'Công ty Digiworld',
        phone: '02839291234',
        email: 'contact@digiworld.com.vn',
        address: '195 Cô Bắc, Q.1, TP.HCM',
        taxCode: '0302861742',
        totalPurchase: 145000000.0,
        currentDebt: 32500000.0,
        note: 'Nhà phân phối chính hãng Apple, Xiaomi',
        status: 'active',
        branch: 'store_001',
        createdAt: '2026-05-15T08:00:00.000Z',
        createdBy: 'Admin',
      );

      expect(testSupplier, equals(copy1));
      expect(testSupplier.hashCode, equals(copy1.hashCode));

      final different = testSupplier.copyWith(name: 'Khác tên');
      expect(testSupplier, isNot(equals(different)));
    });

    test('toString formatting contains key fields', () {
      final str = testSupplier.toString();
      expect(str, contains('NCC000001'));
      expect(str, contains('Công ty Digiworld'));
      expect(str, contains('32500000'));
    });
  });
}
