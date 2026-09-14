import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/models/supplier_debt_transaction_model.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';

void main() {
  group('SupplierDebtTransactionModel Tests', () {
    final testDate = DateTime(2026, 8, 19, 14, 30, 0);

    final testModel = SupplierDebtTransactionModel(
      id: 'TX_001',
      supplierId: 'NCC000001',
      date: testDate.toIso8601String(),
      type: 'payment',
      amount: -10000000.0,
      remainingDebt: 22500000.0,
      referenceCode: 'PC00123',
      note: 'Chi trả tiền nhập đợt 2',
      createdBy: 'Admin',
    );

    test('toMap serializes properly', () {
      final map = testModel.toMap();

      expect(map['id'], 'TX_001');
      expect(map['supplierId'], 'NCC000001');
      expect(map['date'], testDate.toIso8601String());
      expect(map['type'], 'payment');
      expect(map['amount'], -10000000.0);
      expect(map['remainingDebt'], 22500000.0);
      expect(map['referenceCode'], 'PC00123');
      expect(map['note'], 'Chi trả tiền nhập đợt 2');
      expect(map['createdBy'], 'Admin');
    });

    test('fromMap deserializes map properly', () {
      final map = {
        'id': 'TX_002',
        'supplierId': 'NCC000002',
        'date': testDate.toIso8601String(),
        'type': 'import',
        'amount': 25000000,
        'remainingDebt': 25000000,
        'referenceCode': 'PN0055',
        'note': 'Nhập kho linh kiện',
        'createdBy': 'Supervisor',
      };

      final model = SupplierDebtTransactionModel.fromMap(map);

      expect(model.id, 'TX_002');
      expect(model.supplierId, 'NCC000002');
      expect(model.type, 'import');
      expect(model.amount, 25000000.0);
      expect(model.remainingDebt, 25000000.0);
      expect(model.referenceCode, 'PN0055');
      expect(model.note, 'Nhập kho linh kiện');
      expect(model.createdBy, 'Supervisor');
    });

    test('toDomain and fromDomain conversions preserve transaction state', () {
      final domain = SupplierDebtTransaction(
        id: 'TX_003',
        supplierId: 'NCC000003',
        date: testDate,
        type: SupplierDebtType.adjustment,
        amount: -500000.0,
        remainingDebt: 4500000.0,
        referenceCode: 'DC001',
        note: 'Điều chỉnh số dư cuối kỳ',
        createdBy: 'Admin',
      );

      final model = SupplierDebtTransactionModel.fromDomain(domain);
      final backToDomain = model.toDomain();

      expect(backToDomain.id, domain.id);
      expect(backToDomain.supplierId, domain.supplierId);
      expect(backToDomain.date, domain.date);
      expect(backToDomain.type, domain.type);
      expect(backToDomain.amount, domain.amount);
      expect(backToDomain.remainingDebt, domain.remainingDebt);
      expect(backToDomain.referenceCode, domain.referenceCode);
      expect(backToDomain.note, domain.note);
      expect(backToDomain.createdBy, domain.createdBy);
    });
  });
}
