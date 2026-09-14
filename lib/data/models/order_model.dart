import 'order_item_model.dart';

class OrderModel {
  final String id;
  final String customerId;
  final DateTime createdAt;
  final List<OrderItemModel> items;
  final double total;
  final String status;
  final double amountPaid;
  final double debtAmount;
  final String paymentMethod;
  final String? createdBy;
  final String? createdByName;
  final String? cancelReason;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelledByName;
  final String? storeId;
  final double? cashAmount;
  final double? transferAmount;
  final String? note;

  const OrderModel({
    required this.id,
    required this.customerId,
    required this.createdAt,
    required this.items,
    required this.total,
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

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        'createdAt': createdAt.toIso8601String(),
        'total': total,
        'items': items.map((e) => e.toMap()).toList(),
        'status': status,
        'amountPaid': amountPaid,
        'debtAmount': debtAmount,
        'paymentMethod': paymentMethod,
        if (createdBy != null) 'createdBy': createdBy,
        if (createdByName != null) 'createdByName': createdByName,
        if (cancelReason != null) 'cancelReason': cancelReason,
        if (cancelledAt != null) 'cancelledAt': cancelledAt!.toIso8601String(),
        if (cancelledBy != null) 'cancelledBy': cancelledBy,
        if (cancelledByName != null) 'cancelledByName': cancelledByName,
        if (storeId != null) 'storeId': storeId,
        if (cashAmount != null) 'cashAmount': cashAmount,
        if (transferAmount != null) 'transferAmount': transferAmount,
        if (note != null) 'note': note,
      };

  factory OrderModel.fromMap(Map<dynamic, dynamic> map) => OrderModel(
        id: map['id']?.toString() ?? '',
        customerId: map['customerId']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
        total: (map['total'] as num?)?.toDouble() ?? 0.0,
        items: (map['items'] as List?)
                ?.map((e) =>
                    OrderItemModel.fromMap(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        status: map['status']?.toString() ?? 'completed',
        amountPaid: map['amountPaid'] != null
            ? (map['amountPaid'] as num).toDouble()
            : (map['total'] as num?)?.toDouble() ?? 0.0,
        debtAmount: map['debtAmount'] != null
            ? (map['debtAmount'] as num).toDouble()
            : 0.0,
        paymentMethod: map['paymentMethod']?.toString() ?? 'cash',
        createdBy: map['createdBy']?.toString(),
        createdByName: map['createdByName']?.toString(),
        cancelReason: map['cancelReason']?.toString(),
        cancelledAt: map['cancelledAt'] != null
            ? DateTime.tryParse(map['cancelledAt'].toString())
            : null,
        cancelledBy: map['cancelledBy']?.toString(),
        cancelledByName: map['cancelledByName']?.toString(),
        storeId: map['storeId']?.toString(),
        cashAmount: (map['cashAmount'] as num?)?.toDouble(),
        transferAmount: (map['transferAmount'] as num?)?.toDouble(),
        note: map['note']?.toString(),
      );
}

