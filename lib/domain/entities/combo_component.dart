class ComboComponent {
  final String productId;
  final String productCode;
  final String productName;
  final int quantity;
  final double? costPrice;

  const ComboComponent({
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.quantity,
    this.costPrice,
  });

  ComboComponent copyWith({
    String? productId,
    String? productCode,
    String? productName,
    int? quantity,
    double? costPrice,
  }) {
    return ComboComponent(
      productId: productId ?? this.productId,
      productCode: productCode ?? this.productCode,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      costPrice: costPrice ?? this.costPrice,
    );
  }

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productCode': productCode,
        'productName': productName,
        'quantity': quantity,
        'costPrice': costPrice,
      };

  factory ComboComponent.fromMap(Map<dynamic, dynamic> map) {
    return ComboComponent(
      productId: map['productId'] as String? ?? '',
      productCode: map['productCode'] as String? ?? '',
      productName: map['productName'] as String? ?? '',
      quantity: (map['quantity'] as num? ?? 1).toInt(),
      costPrice: map['costPrice'] != null
          ? (map['costPrice'] as num).toDouble()
          : null,
    );
  }
}
