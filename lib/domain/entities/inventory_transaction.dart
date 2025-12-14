import 'package:stores/domain/entities/transaction_type.dart';

class InventoryTransaction {
  final String id;
  final String productId;
  final TransactionType type;
  final int quantity;
  final DateTime date;
  final String note;
  final double? importPrice;

  const InventoryTransaction({
    required this.id,
    required this.productId,
    required this.type,
    required this.quantity,
    required this.date,
    required this.note,
    this.importPrice,
  });
}