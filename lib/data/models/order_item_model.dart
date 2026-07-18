class OrderItemModel {
  final String productId;
  final String productName;
  final int quantity;
  final double price; // Giá bán thực tế tại thời điểm tạo đơn hàng
  final int warrantyMonths;
  final DateTime purchaseDate;

  const OrderItemModel({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    required this.warrantyMonths,
    required this.purchaseDate,
  });

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'price': price,
        'warrantyMonths': warrantyMonths,
        'purchaseDate': purchaseDate.toIso8601String(),
      };

  factory OrderItemModel.fromMap(Map<dynamic, dynamic> map) => OrderItemModel(
        productId: map['productId'] as String,
        productName: map['productName'] as String,
        quantity: map['quantity'] as int,
        price: (map['price'] as num?)?.toDouble() ?? 0.0,
        // Fallback về 0.0 nếu không có price
        warrantyMonths: map['warrantyMonths'] as int,
        purchaseDate: DateTime.parse(map['purchaseDate'] as String),
      );
}
