class OrderItem {
  final String productId;
  final String productName;
  final int quantity;
  final double price; // Giá bán thực tế tại thời điểm tạo đơn hàng
  final int warrantyMonths;
  final DateTime purchaseDate;
  final int returnedQuantity; // Số lượng đã trả lại

  const OrderItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    required this.warrantyMonths,
    required this.purchaseDate,
    this.returnedQuantity = 0,
  });

  int get activeQuantity => quantity - returnedQuantity;
  int get remainingQuantity => quantity - returnedQuantity;
  bool get isFullyReturned => activeQuantity <= 0;

  OrderItem copyWith({
    String? productId,
    String? productName,
    int? quantity,
    double? price,
    int? warrantyMonths,
    DateTime? purchaseDate,
    int? returnedQuantity,
  }) {
    return OrderItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      warrantyMonths: warrantyMonths ?? this.warrantyMonths,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      returnedQuantity: returnedQuantity ?? this.returnedQuantity,
    );
  }
}
