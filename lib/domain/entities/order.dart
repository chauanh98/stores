import 'order_item.dart';

class Order {
  final String id;
  final String customerId;
  final DateTime createdAt;
  final List<OrderItem> items;
  final double total;
  final String status; // 'draft' hoặc 'completed'

  const Order({
    required this.id,
    required this.customerId,
    required this.createdAt,
    required this.items,
    required this.total,
    this.status = 'completed',
  });
}