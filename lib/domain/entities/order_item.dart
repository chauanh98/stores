class OrderItem {
  final String productId;
  final String productName;
  final int quantity;
  final double price; // Giá bán thực tế tại thời điểm tạo đơn hàng (sau giảm giá món)
  final double originalPrice; // Giá gốc trước giảm
  final double discount; // Giá trị giảm giá trên từng sản phẩm (theo % hoặc VNĐ)
  final bool isDiscountPercent; // true nếu giảm theo %, false nếu giảm theo tiền trực tiếp
  final String? note; // Ghi chú riêng cho sản phẩm này
  final int warrantyMonths;
  final DateTime purchaseDate;
  final int returnedQuantity; // Số lượng đã trả lại

  const OrderItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    this.originalPrice = 0.0,
    this.discount = 0.0,
    this.isDiscountPercent = false,
    this.note,
    required this.warrantyMonths,
    required this.purchaseDate,
    this.returnedQuantity = 0,
  });

  int get activeQuantity => quantity - returnedQuantity;
  int get remainingQuantity => quantity - returnedQuantity;
  bool get isFullyReturned => activeQuantity <= 0;

  double get effectiveOriginalPrice =>
      originalPrice > 0 ? originalPrice : price;

  double get totalDiscountAmount {
    if (discount <= 0) return 0.0;
    final basePrice = effectiveOriginalPrice;
    final unitDiscount = isDiscountPercent
        ? (basePrice * discount / 100).clamp(0.0, basePrice)
        : discount.clamp(0.0, basePrice);
    return unitDiscount * quantity;
  }

  double get lineTotal => price * quantity;

  OrderItem copyWith({
    String? productId,
    String? productName,
    int? quantity,
    double? price,
    double? originalPrice,
    double? discount,
    bool? isDiscountPercent,
    String? note,
    bool clearNote = false,
    int? warrantyMonths,
    DateTime? purchaseDate,
    int? returnedQuantity,
  }) {
    return OrderItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      originalPrice: originalPrice ?? this.originalPrice,
      discount: discount ?? this.discount,
      isDiscountPercent: isDiscountPercent ?? this.isDiscountPercent,
      note: clearNote ? null : (note ?? this.note),
      warrantyMonths: warrantyMonths ?? this.warrantyMonths,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      returnedQuantity: returnedQuantity ?? this.returnedQuantity,
    );
  }
}
