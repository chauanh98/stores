import 'order_item.dart';

class Order {
  final String id;
  final String customerId;
  final String? customerName;
  final DateTime createdAt;
  final List<OrderItem> items;
  final double total;
  final double discount;
  final String status; // 'draft', 'completed', 'cancelled', 'returned'
  final double amountPaid;
  final double debtAmount;
  final String paymentMethod;
  final String? createdBy;
  final String? createdByName;

  // Fields for cancellation tracking and store scoping
  final String? cancelReason;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelledByName;
  final String? storeId;

  // Split payment and order note fields
  final double? cashAmount;
  final double? transferAmount;
  final String? note;

  const Order({
    required this.id,
    required this.customerId,
    this.customerName,
    required this.createdAt,
    required this.items,
    required this.total,
    this.discount = 0.0,
    this.status = 'completed',
    this.amountPaid = 0.0,
    this.debtAmount = 0.0,
    this.paymentMethod = 'cash',
    this.createdBy,
    this.createdByName,
    this.cancelReason,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelledByName,
    this.storeId,
    this.cashAmount,
    this.transferAmount,
    this.note,
  });

  bool get isCancelled {
    final s = status.trim().toLowerCase();
    return s == 'cancelled' ||
        s == 'canceled' ||
        s.contains('hủy') ||
        s.contains('huỷ') ||
        s.contains('cancel') ||
        s.contains('huy');
  }

  bool get isCompleted => status == 'completed';
  bool get isDraft => status == 'draft';
  bool get isReturned => status == 'returned';
  bool get hasReturns => items.any((i) => i.returnedQuantity > 0);
  double get netPayable => (total - discount).clamp(0.0, double.infinity);
  double get remainingDebt => isCancelled
      ? 0.0
      : (debtAmount > 0
          ? debtAmount
          : (netPayable - amountPaid).clamp(0.0, double.infinity));
  bool get hasDebt => remainingDebt > 0;

  Order copyWith({
    String? id,
    String? customerId,
    String? customerName,
    DateTime? createdAt,
    List<OrderItem>? items,
    double? total,
    double? discount,
    String? status,
    double? amountPaid,
    double? debtAmount,
    String? paymentMethod,
    String? createdBy,
    String? createdByName,
    String? cancelReason,
    DateTime? cancelledAt,
    String? cancelledBy,
    String? cancelledByName,
    String? storeId,
    double? cashAmount,
    double? transferAmount,
    String? note,
  }) {
    final effectiveStatus = status ?? this.status;
    final s = effectiveStatus.trim().toLowerCase();
    final isCancelledStatus = s == 'cancelled' ||
        s == 'canceled' ||
        s.contains('hủy') ||
        s.contains('huỷ') ||
        s.contains('cancel') ||
        s.contains('huy');
    return Order(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      createdAt: createdAt ?? this.createdAt,
      items: items ?? this.items,
      total: total ?? this.total,
      discount: discount ?? this.discount,
      status: effectiveStatus,
      amountPaid: amountPaid ?? this.amountPaid,
      debtAmount: isCancelledStatus ? 0.0 : (debtAmount ?? this.debtAmount),
      paymentMethod: paymentMethod ?? this.paymentMethod,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      cancelReason: cancelReason ?? this.cancelReason,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      cancelledByName: cancelledByName ?? this.cancelledByName,
      storeId: storeId ?? this.storeId,
      cashAmount: cashAmount ?? this.cashAmount,
      transferAmount: transferAmount ?? this.transferAmount,
      note: note ?? this.note,
    );
  }
}
