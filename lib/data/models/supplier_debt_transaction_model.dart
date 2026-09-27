import '../../domain/entities/supplier_debt_transaction.dart';

class SupplierDebtTransactionModel {
  final String id;
  final String supplierId;
  final String date;
  final String type;
  final double amount;
  final double remainingDebt;
  final String? referenceCode;
  final String? note;
  final String? createdBy;

  const SupplierDebtTransactionModel({
    required this.id,
    required this.supplierId,
    required this.date,
    required this.type,
    required this.amount,
    required this.remainingDebt,
    this.referenceCode,
    this.note,
    this.createdBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplierId': supplierId,
      'date': date,
      'type': type,
      'amount': amount,
      'remainingDebt': remainingDebt,
      'referenceCode': referenceCode,
      'note': note,
      'createdBy': createdBy,
    };
  }

  factory SupplierDebtTransactionModel.fromMap(Map<dynamic, dynamic> map) {
    return SupplierDebtTransactionModel(
      id: map['id']?.toString() ?? '',
      supplierId: map['supplierId']?.toString() ?? '',
      date: map['date']?.toString() ?? DateTime.now().toIso8601String(),
      type: map['type']?.toString() ?? 'payment',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      remainingDebt: (map['remainingDebt'] as num?)?.toDouble() ?? 0.0,
      referenceCode: map['referenceCode']?.toString(),
      note: map['note']?.toString(),
      createdBy: map['createdBy']?.toString(),
    );
  }

  SupplierDebtTransaction toDomain() {
    return SupplierDebtTransaction(
      id: id,
      supplierId: supplierId,
      date: DateTime.tryParse(date) ?? DateTime.now(),
      type: SupplierDebtTypeExtension.fromDbValue(type),
      amount: amount,
      remainingDebt: remainingDebt,
      referenceCode: referenceCode,
      note: note,
      createdBy: createdBy,
    );
  }

  factory SupplierDebtTransactionModel.fromDomain(
      SupplierDebtTransaction domain) {
    return SupplierDebtTransactionModel(
      id: domain.id,
      supplierId: domain.supplierId,
      date: domain.date.toIso8601String(),
      type: domain.type.toDbValue(),
      amount: domain.amount,
      remainingDebt: domain.remainingDebt,
      referenceCode: domain.referenceCode,
      note: domain.note,
      createdBy: domain.createdBy,
    );
  }
}
