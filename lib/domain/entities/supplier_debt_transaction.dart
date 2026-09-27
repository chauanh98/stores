enum SupplierDebtType {
  importBill, // Nhập hàng ghi nợ (tăng nợ)
  payment, // Trả tiền NCC / Phiếu chi (giảm nợ)
  adjustment, // Điều chỉnh công nợ
  returnOrder, // Trả hàng NCC (giảm nợ)
}

extension SupplierDebtTypeExtension on SupplierDebtType {
  String get displayName {
    switch (this) {
      case SupplierDebtType.importBill:
        return 'Nhập hàng';
      case SupplierDebtType.payment:
        return 'Trả tiền NCC';
      case SupplierDebtType.adjustment:
        return 'Điều chỉnh nợ';
      case SupplierDebtType.returnOrder:
        return 'Trả hàng NCC';
    }
  }

  String toDbValue() {
    switch (this) {
      case SupplierDebtType.importBill:
        return 'import';
      case SupplierDebtType.payment:
        return 'payment';
      case SupplierDebtType.adjustment:
        return 'adjustment';
      case SupplierDebtType.returnOrder:
        return 'return';
    }
  }

  static SupplierDebtType fromDbValue(String? value) {
    switch (value?.toLowerCase()) {
      case 'import':
      case 'import_debt':
      case 'importdebt':
      case 'importbill':
      case 'purchase':
        return SupplierDebtType.importBill;
      case 'payment':
      case 'pay':
      case 'expense':
        return SupplierDebtType.payment;
      case 'adjustment':
      case 'adjust':
        return SupplierDebtType.adjustment;
      case 'return':
      case 'returnorder':
        return SupplierDebtType.returnOrder;
      default:
        return SupplierDebtType.payment;
    }
  }
}

class SupplierDebtTransaction {
  final String id;
  final String supplierId;
  final DateTime date;
  final SupplierDebtType type;

  /// Biến động nợ (+ tăng nợ NCC, - giảm nợ NCC)
  final double amount;

  /// Dư nợ còn lại sau giao dịch
  final double remainingDebt;

  /// Mã tham chiếu (mã phiếu nhập, mã phiếu chi,...)
  final String? referenceCode;
  final String? note;
  final String? createdBy;

  const SupplierDebtTransaction({
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

  SupplierDebtTransaction copyWith({
    String? id,
    String? supplierId,
    DateTime? date,
    SupplierDebtType? type,
    double? amount,
    double? remainingDebt,
    String? referenceCode,
    String? note,
    String? createdBy,
  }) {
    return SupplierDebtTransaction(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      date: date ?? this.date,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      remainingDebt: remainingDebt ?? this.remainingDebt,
      referenceCode: referenceCode ?? this.referenceCode,
      note: note ?? this.note,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplierId': supplierId,
      'date': date.toIso8601String(),
      'type': type.toDbValue(),
      'amount': amount,
      'remainingDebt': remainingDebt,
      'referenceCode': referenceCode,
      'note': note,
      'createdBy': createdBy,
    };
  }

  factory SupplierDebtTransaction.fromMap(Map<dynamic, dynamic> map) {
    return SupplierDebtTransaction(
      id: map['id']?.toString() ?? '',
      supplierId: map['supplierId']?.toString() ?? '',
      date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
      type: SupplierDebtTypeExtension.fromDbValue(map['type']?.toString()),
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      remainingDebt: (map['remainingDebt'] as num?)?.toDouble() ?? 0.0,
      referenceCode: map['referenceCode']?.toString(),
      note: map['note']?.toString(),
      createdBy: map['createdBy']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplierDebtTransaction &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          supplierId == other.supplierId &&
          date == other.date &&
          type == other.type &&
          amount == other.amount &&
          remainingDebt == other.remainingDebt &&
          referenceCode == other.referenceCode &&
          note == other.note &&
          createdBy == other.createdBy;

  @override
  int get hashCode =>
      id.hashCode ^
      supplierId.hashCode ^
      date.hashCode ^
      type.hashCode ^
      amount.hashCode ^
      remainingDebt.hashCode ^
      referenceCode.hashCode ^
      note.hashCode ^
      createdBy.hashCode;

  @override
  String toString() {
    return 'SupplierDebtTransaction(id: $id, supplierId: $supplierId, date: $date, type: $type, amount: $amount, remainingDebt: $remainingDebt, ref: $referenceCode)';
  }
}
