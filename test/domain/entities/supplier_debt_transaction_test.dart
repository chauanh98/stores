import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';

void main() {
  group('SupplierDebtTransaction & SupplierDebtType Tests', () {
    final testDate = DateTime(2026, 8, 19, 10, 0, 0);

    test('SupplierDebtTypeExtension displayName mappings', () {
      expect(SupplierDebtType.importBill.displayName, 'Nhập hàng');
      expect(SupplierDebtType.payment.displayName, 'Trả tiền NCC');
      expect(SupplierDebtType.adjustment.displayName, 'Điều chỉnh nợ');
      expect(SupplierDebtType.returnOrder.displayName, 'Trả hàng NCC');
    });

    test('SupplierDebtTypeExtension toDbValue mappings', () {
      expect(SupplierDebtType.importBill.toDbValue(), 'import');
      expect(SupplierDebtType.payment.toDbValue(), 'payment');
      expect(SupplierDebtType.adjustment.toDbValue(), 'adjustment');
      expect(SupplierDebtType.returnOrder.toDbValue(), 'return');
    });

    test('SupplierDebtTypeExtension fromDbValue mappings and fallbacks', () {
      expect(SupplierDebtTypeExtension.fromDbValue('import'), SupplierDebtType.importBill);
      expect(SupplierDebtTypeExtension.fromDbValue('importbill'), SupplierDebtType.importBill);
      expect(SupplierDebtTypeExtension.fromDbValue('purchase'), SupplierDebtType.importBill);

      expect(SupplierDebtTypeExtension.fromDbValue('payment'), SupplierDebtType.payment);
      expect(SupplierDebtTypeExtension.fromDbValue('pay'), SupplierDebtType.payment);
      expect(SupplierDebtTypeExtension.fromDbValue('expense'), SupplierDebtType.payment);

      expect(SupplierDebtTypeExtension.fromDbValue('adjustment'), SupplierDebtType.adjustment);
      expect(SupplierDebtTypeExtension.fromDbValue('adjust'), SupplierDebtType.adjustment);

      expect(SupplierDebtTypeExtension.fromDbValue('return'), SupplierDebtType.returnOrder);
      expect(SupplierDebtTypeExtension.fromDbValue('returnorder'), SupplierDebtType.returnOrder);

      // Default fallback
      expect(SupplierDebtTypeExtension.fromDbValue('unknown'), SupplierDebtType.payment);
      expect(SupplierDebtTypeExtension.fromDbValue(null), SupplierDebtType.payment);
    });

    test('SupplierDebtTransaction instantiation, toMap and fromMap serialization', () {
      final tx = SupplierDebtTransaction(
        id: 'TX_PAY_001',
        supplierId: 'NCC000001',
        date: testDate,
        type: SupplierDebtType.payment,
        amount: -15000000.0,
        remainingDebt: 17500000.0,
        referenceCode: 'PC0001',
        note: 'Thanh toán tiền hàng đợt 1',
        createdBy: 'Admin',
      );

      expect(tx.id, 'TX_PAY_001');
      expect(tx.supplierId, 'NCC000001');
      expect(tx.date, testDate);
      expect(tx.type, SupplierDebtType.payment);
      expect(tx.amount, -15000000.0);
      expect(tx.remainingDebt, 17500000.0);
      expect(tx.referenceCode, 'PC0001');
      expect(tx.note, 'Thanh toán tiền hàng đợt 1');
      expect(tx.createdBy, 'Admin');

      final map = tx.toMap();
      expect(map['id'], 'TX_PAY_001');
      expect(map['supplierId'], 'NCC000001');
      expect(map['date'], testDate.toIso8601String());
      expect(map['type'], 'payment');
      expect(map['amount'], -15000000.0);
      expect(map['remainingDebt'], 17500000.0);
      expect(map['referenceCode'], 'PC0001');
      expect(map['note'], 'Thanh toán tiền hàng đợt 1');
      expect(map['createdBy'], 'Admin');

      final deserialized = SupplierDebtTransaction.fromMap(map);
      expect(deserialized, equals(tx));
    });

    test('SupplierDebtTransaction copyWith and equality', () {
      final tx = SupplierDebtTransaction(
        id: 'TX_IMP_001',
        supplierId: 'NCC000002',
        date: testDate,
        type: SupplierDebtType.importBill,
        amount: 25000000.0,
        remainingDebt: 25000000.0,
        referenceCode: 'PN0001',
      );

      final updated = tx.copyWith(
        amount: 30000000.0,
        remainingDebt: 30000000.0,
        note: 'Cập nhật thêm số lượng',
      );

      expect(updated.id, 'TX_IMP_001');
      expect(updated.amount, 30000000.0);
      expect(updated.remainingDebt, 30000000.0);
      expect(updated.note, 'Cập nhật thêm số lượng');
      expect(updated.referenceCode, 'PN0001');

      final identicalTx = SupplierDebtTransaction(
        id: 'TX_IMP_001',
        supplierId: 'NCC000002',
        date: testDate,
        type: SupplierDebtType.importBill,
        amount: 25000000.0,
        remainingDebt: 25000000.0,
        referenceCode: 'PN0001',
      );

      expect(tx, equals(identicalTx));
      expect(tx.hashCode, equals(identicalTx.hashCode));
      expect(tx.toString(), contains('TX_IMP_001'));
    });
  });
}
