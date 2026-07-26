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
      };

  factory OrderModel.fromMap(Map<dynamic, dynamic> map) => OrderModel(
        id: map['id'] as String,
        customerId: map['customerId'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        total: (map['total'] as num).toDouble(),
        items: (map['items'] as List)
            .map((e) =>
                OrderItemModel.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        status: map['status']?.toString() ?? 'completed',
        amountPaid: map['amountPaid'] != null
            ? (map['amountPaid'] as num).toDouble()
            : (map['total'] as num).toDouble(),
        debtAmount: map['debtAmount'] != null
            ? (map['debtAmount'] as num).toDouble()
            : 0.0,
        paymentMethod: map['paymentMethod']?.toString() ?? 'cash',
        createdBy: map['createdBy']?.toString(),
        createdByName: map['createdByName']?.toString(),
      );
}
