import 'order_item_model.dart';

class OrderModel {
  final String id;
  final String customerId;
  final DateTime createdAt;
  final List<OrderItemModel> items;
  final double total;
  final String status;

  const OrderModel({
    required this.id,
    required this.customerId,
    required this.createdAt,
    required this.items,
    required this.total,
    this.status = 'completed',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        'createdAt': createdAt.toIso8601String(),
        'total': total,
        'items': items.map((e) => e.toMap()).toList(),
        'status': status,
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
      );
}
