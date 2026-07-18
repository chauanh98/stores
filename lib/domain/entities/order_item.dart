class OrderItem {
  final String productId;
  final String productName;
  final int quantity;
  final double price; // Giá bán thực tế tại thời điểm tạo đơn hàng
  final int warrantyMonths;
  final DateTime purchaseDate;

  const OrderItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    required this.warrantyMonths,
    required this.purchaseDate,
  });
}
