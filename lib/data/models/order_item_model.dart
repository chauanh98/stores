class OrderItemModel {
  final String productId;
  final String productName;
  final int quantity;
  final double price; // Giá bán thực tế tại thời điểm tạo đơn hàng
  final int warrantyMonths;
  final DateTime purchaseDate;
  final int returnedQuantity;

  const OrderItemModel({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    required this.warrantyMonths,
    required this.purchaseDate,
    this.returnedQuantity = 0,
  });

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'price': price,
        'warrantyMonths': warrantyMonths,
        'purchaseDate': purchaseDate.toIso8601String(),
        'returnedQuantity': returnedQuantity,
      };

  factory OrderItemModel.fromMap(Map<dynamic, dynamic> map) {
    final rawQty = map['quantity'];
    final quantity = rawQty is num
        ? rawQty.toInt()
        : (int.tryParse(rawQty?.toString() ?? '') ??
            (double.tryParse(rawQty?.toString() ?? '')?.toInt() ?? 1));

    final rawPrice = map['price'];
    final parsedPrice = rawPrice is num
        ? rawPrice.toDouble()
        : (double.tryParse(rawPrice?.toString() ?? '') ?? 0.0);
    final price = parsedPrice < 0 ? 0.0 : parsedPrice;

    final rawWarranty = map['warrantyMonths'];
    final warrantyMonths = rawWarranty is num
        ? rawWarranty.toInt()
        : (int.tryParse(rawWarranty?.toString() ?? '') ?? 0);

    final rawReturned = map['returnedQuantity'];
    final returnedQuantity = rawReturned is num
        ? rawReturned.toInt()
        : (int.tryParse(rawReturned?.toString() ?? '') ?? 0);

    return OrderItemModel(
      productId: map['productId']?.toString() ?? '',
      productName: map['productName']?.toString() ?? '',
      quantity: quantity,
      price: price,
      warrantyMonths: warrantyMonths,
      purchaseDate: DateTime.tryParse(map['purchaseDate']?.toString() ?? '') ??
          DateTime.now(),
      returnedQuantity: returnedQuantity,
    );
  }
}
