class InventoryTransactionModel {
  final String id;
  final String productId;
  final String type;
  final int quantity;
  final DateTime date;
  final String note;
  final double? importPrice;

  const InventoryTransactionModel({
    required this.id,
    required this.productId,
    required this.type,
    required this.quantity,
    required this.date,
    required this.note,
    this.importPrice,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'type': type,
        'quantity': quantity,
        'date': date.toIso8601String(),
        'note': note,
        'importPrice': importPrice,
      };

  factory InventoryTransactionModel.fromMap(Map<dynamic, dynamic> map) =>
      InventoryTransactionModel(
        id: map['id'] as String,
        productId: map['productId'] as String,
        type: map['type'] as String,
        quantity: map['quantity'] as int,
        date: DateTime.parse(map['date'] as String),
        note: map['note'] as String,
        importPrice: map['importPrice'] == null
            ? null
            : (map['importPrice'] as num).toDouble(),
      );
}
