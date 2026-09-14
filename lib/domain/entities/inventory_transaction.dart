import 'package:stores/domain/entities/transaction_type.dart';

class InventoryTransaction {
  final String id;
  final String productId;
  final TransactionType type;
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

  const InventoryTransaction({
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

  InventoryTransaction copyWith({
    String? id,
    String? productId,
    TransactionType? type,
    int? quantity,
    DateTime? date,
    String? note,
    double? importPrice,
    String? createdBy,
    String? createdByName,
    String? storeId,
    bool? isAuditNegative,
    int? auditDifference,
    String? supplierId,
    String? supplierName,
    String? importCode,
  }) {
    return InventoryTransaction(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      type: type ?? this.type,
      quantity: quantity ?? this.quantity,
      date: date ?? this.date,
      note: note ?? this.note,
      importPrice: importPrice ?? this.importPrice,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      storeId: storeId ?? this.storeId,
      isAuditNegative: isAuditNegative ?? this.isAuditNegative,
      auditDifference: auditDifference ?? this.auditDifference,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      importCode: importCode ?? this.importCode,
    );
  }
}
