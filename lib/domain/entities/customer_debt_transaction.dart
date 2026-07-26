enum DebtTransactionType {
  invoice, // Hóa đơn bán hàng
  payment, // Thanh toán công nợ / Phiếu thu
  adjustment, // Điều chỉnh công nợ
}

class CustomerDebtTransaction {
  final String id;
  final String code; // HD012723, TTHD012723
  final String customerId;
  final DateTime date;
  final double
      amount; // Số tiền biến động (+ cho nợ phát sinh, - cho thanh toán)
  final double remainingDebt; // Nợ còn sau giao dịch
  final DebtTransactionType type;
  final String? note;
  final String? createdBy;

  const CustomerDebtTransaction({
    required this.id,
    required this.code,
    required this.customerId,
    required this.date,
    required this.amount,
    required this.remainingDebt,
    required this.type,
    this.note,
    this.createdBy,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'code': code,
        'customerId': customerId,
        'date': date.toIso8601String(),
        'amount': amount,
        'remainingDebt': remainingDebt,
        'type': type.name,
        'note': note,
        'createdBy': createdBy,
      };

  factory CustomerDebtTransaction.fromMap(Map<dynamic, dynamic> map) =>
      CustomerDebtTransaction(
        id: map['id']?.toString() ?? '',
        code: map['code']?.toString() ?? '',
        customerId: map['customerId']?.toString() ?? '',
        date:
            DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
        amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
        remainingDebt: (map['remainingDebt'] as num?)?.toDouble() ?? 0.0,
        type: DebtTransactionType.values.firstWhere(
          (e) => e.name == map['type']?.toString(),
          orElse: () => DebtTransactionType.payment,
        ),
        note: map['note']?.toString(),
        createdBy: map['createdBy']?.toString(),
      );
}
