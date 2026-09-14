import '../../domain/entities/inventory_transaction.dart';
import '../../domain/entities/transaction_type.dart';

class InventoryTransactionModel {
  final String id;
  final String productId;
  final String type;
  final int quantity;
  final DateTime date;
  final String note;
  final double? importPrice;
  final String? createdBy;
  final String? createdByName;
  final String? storeId;
  final bool? isAuditNegative;
  final int? auditDifference;
  final String? supplierId;
  final String? supplierName;
  final String? importCode;

  const InventoryTransactionModel({
    required this.id,
    required this.productId,
    required this.type,
    required this.quantity,
    required this.date,
    required this.note,
    this.importPrice,
    this.createdBy,
    this.createdByName,
    this.storeId,
    this.isAuditNegative,
    this.auditDifference,
    this.supplierId,
    this.supplierName,
    this.importCode,
  });

  TransactionType toTransactionType() => parseTransactionType(type);

  static TransactionType parseTransactionType(String typeStr) {
    final lower = typeStr.toLowerCase().trim();
    if (lower == 'inventory_audit' ||
        lower == 'inventoryaudit' ||
        lower == 'audit') {
      return TransactionType.inventoryAudit;
    }
    if (lower == 'export') {
      return TransactionType.export;
    }
    return TransactionType.import;
  }

  static String typeToString(TransactionType type) {
    switch (type) {
      case TransactionType.import:
        return 'import';
      case TransactionType.export:
        return 'export';
      case TransactionType.inventoryAudit:
        return 'INVENTORY_AUDIT';
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'type': type,
        'quantity': quantity,
        'date': date.toIso8601String(),
        'note': note,
        'importPrice': importPrice,
        if (createdBy != null) 'createdBy': createdBy,
        if (createdByName != null) 'createdByName': createdByName,
        if (storeId != null) 'storeId': storeId,
        if (isAuditNegative != null) 'isAuditNegative': isAuditNegative,
        if (auditDifference != null) 'auditDifference': auditDifference,
        if (supplierId != null) 'supplierId': supplierId,
        if (supplierName != null) 'supplierName': supplierName,
        if (importCode != null) 'importCode': importCode,
      };

  factory InventoryTransactionModel.fromMap(Map<dynamic, dynamic> map) =>
      InventoryTransactionModel(
        id: map['id']?.toString() ?? '',
        productId: map['productId']?.toString() ?? '',
        type: map['type']?.toString() ?? 'import',
        quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        date: map['date'] != null
            ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now()
            : DateTime.now(),
        note: map['note']?.toString() ?? '',
        importPrice: map['importPrice'] == null
            ? null
            : (map['importPrice'] as num).toDouble(),
        createdBy: map['createdBy']?.toString(),
        createdByName: map['createdByName']?.toString(),
        storeId: map['storeId']?.toString(),
        isAuditNegative: map['isAuditNegative'] is bool
            ? map['isAuditNegative'] as bool
            : (map['isAuditNegative'] != null
                ? map['isAuditNegative'].toString().toLowerCase() == 'true'
                : null),
        auditDifference: (map['auditDifference'] as num?)?.toInt(),
        supplierId: map['supplierId']?.toString(),
        supplierName: map['supplierName']?.toString(),
        importCode: map['importCode']?.toString(),
      );

  InventoryTransaction toEntity() => InventoryTransaction(
        id: id,
        productId: productId,
        type: toTransactionType(),
        quantity: quantity,
        date: date,
        note: note,
        importPrice: importPrice,
        createdBy: createdBy,
        createdByName: createdByName,
        storeId: storeId,
        isAuditNegative: isAuditNegative,
        auditDifference: auditDifference,
        supplierId: supplierId,
        supplierName: supplierName,
        importCode: importCode,
      );

  factory InventoryTransactionModel.fromEntity(InventoryTransaction entity) =>
      InventoryTransactionModel(
        id: entity.id,
        productId: entity.productId,
        type: typeToString(entity.type),
        quantity: entity.quantity,
        date: entity.date,
        note: entity.note,
        importPrice: entity.importPrice,
        createdBy: entity.createdBy,
        createdByName: entity.createdByName,
        storeId: entity.storeId,
        isAuditNegative: entity.isAuditNegative,
        auditDifference: entity.auditDifference,
        supplierId: entity.supplierId,
        supplierName: entity.supplierName,
        importCode: entity.importCode,
      );
}
