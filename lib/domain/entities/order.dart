import 'order_item.dart';

class Order {
  final String id;
  final String customerId;
  final DateTime createdAt;
  final List<OrderItem> items;
  final double total;
  final String status; // 'draft' hoặc 'completed'
  final double amountPaid;
  final double debtAmount;
  final String paymentMethod;
  final String? createdBy;
  final String? createdByName;

  const Order({
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
}
