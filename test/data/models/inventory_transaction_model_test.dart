import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/models/inventory_transaction_model.dart';
import 'package:stores/domain/entities/transaction_type.dart';

void main() {
  group('InventoryTransactionModel & TransactionType Unit Tests', () {
    test('Round-trip serialization and deserialization with INVENTORY_AUDIT',
        () {
      final now = DateTime(2026, 8, 17, 10, 30, 0);
      final model = InventoryTransactionModel(
        id: 'audit_001',
        productId: 'prod_123',
        type: InventoryTransactionModel.typeToString(
            TransactionType.inventoryAudit),
        quantity: 8,
        date: now,
        note:
            'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 18, chênh lệch: +8)',
        importPrice: 25000.0,
        createdBy: 'admin',
        createdByName: 'Admin Name',
      );

      final map = model.toMap();
      expect(map['id'], equals('audit_001'));
      expect(map['productId'], equals('prod_123'));
      expect(map['type'], equals('INVENTORY_AUDIT'));
      expect(map['quantity'], equals(8));
      expect(map['date'], equals(now.toIso8601String()));
      expect(map['note'], contains('Cân bằng kho'));
      expect(map['importPrice'], equals(25000.0));
      expect(map['createdBy'], equals('admin'));
      expect(map['createdByName'], equals('Admin Name'));

      final restored = InventoryTransactionModel.fromMap(map);
      expect(restored.id, equals('audit_001'));
      expect(restored.productId, equals('prod_123'));
      expect(restored.type, equals('INVENTORY_AUDIT'));
      expect(
          restored.toTransactionType(), equals(TransactionType.inventoryAudit));
      expect(restored.quantity, equals(8));
      expect(restored.date, equals(now));
      expect(restored.importPrice, equals(25000.0));
      expect(restored.createdBy, equals('admin'));
      expect(restored.createdByName, equals('Admin Name'));
    });

    test('parseTransactionType parses various string formats correctly', () {
      expect(
        InventoryTransactionModel.parseTransactionType('INVENTORY_AUDIT'),
        equals(TransactionType.inventoryAudit),
      );
      expect(
        InventoryTransactionModel.parseTransactionType('inventory_audit'),
        equals(TransactionType.inventoryAudit),
      );
      expect(
        InventoryTransactionModel.parseTransactionType('inventoryAudit'),
        equals(TransactionType.inventoryAudit),
      );
      expect(
        InventoryTransactionModel.parseTransactionType('audit'),
        equals(TransactionType.inventoryAudit),
      );
      expect(
        InventoryTransactionModel.parseTransactionType('export'),
        equals(TransactionType.export),
      );
      expect(
        InventoryTransactionModel.parseTransactionType('import'),
        equals(TransactionType.import),
      );
      expect(
        InventoryTransactionModel.parseTransactionType('unknown'),
        equals(TransactionType.import),
      );
    });

    test('typeToString converts all enum values correctly', () {
      expect(
        InventoryTransactionModel.typeToString(TransactionType.inventoryAudit),
        equals('INVENTORY_AUDIT'),
      );
      expect(
        InventoryTransactionModel.typeToString(TransactionType.import),
        equals('import'),
      );
      expect(
        InventoryTransactionModel.typeToString(TransactionType.export),
        equals('export'),
      );
    });
    test(
        'Round-trip serialization and deserialization with structured audit fields',
        () {
      final now = DateTime(2026, 8, 17, 10, 30, 0);
      final model = InventoryTransactionModel(
        id: 'audit_002',
        productId: 'prod_123',
        type: 'INVENTORY_AUDIT',
        quantity: 5,
        date: now,
        note: 'Cân bằng kho trực tiếp (-5)',
        importPrice: 25000.0,
        createdBy: 'admin',
        createdByName: 'Admin Name',
        storeId: 'store_001',
        isAuditNegative: true,
        auditDifference: -5,
      );

      final map = model.toMap();
      expect(map['id'], equals('audit_002'));
      expect(map['storeId'], equals('store_001'));
      expect(map['isAuditNegative'], isTrue);
      expect(map['auditDifference'], equals(-5));

      final restored = InventoryTransactionModel.fromMap(map);
      expect(restored.id, equals('audit_002'));
      expect(restored.storeId, equals('store_001'));
      expect(restored.isAuditNegative, isTrue);
      expect(restored.auditDifference, equals(-5));

      final entity = restored.toEntity();
      expect(entity.id, equals('audit_002'));
      expect(entity.storeId, equals('store_001'));
      expect(entity.isAuditNegative, isTrue);
      expect(entity.auditDifference, equals(-5));
      expect(entity.type, equals(TransactionType.inventoryAudit));

      final fromEntityModel = InventoryTransactionModel.fromEntity(entity);
      expect(fromEntityModel.id, equals('audit_002'));
      expect(fromEntityModel.storeId, equals('store_001'));
      expect(fromEntityModel.isAuditNegative, isTrue);
      expect(fromEntityModel.auditDifference, equals(-5));
      expect(fromEntityModel.type, equals('INVENTORY_AUDIT'));
    });
  });
}
