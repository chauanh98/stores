class ProductUnit {
  final String id;
  final String unitName;
  final int conversionRate; // Tỷ lệ quy đổi so với đơn vị cơ bản (mặc định 1)
  final double price; // Giá bán của đơn vị này
  final double? costPrice; // Giá vốn của đơn vị này
  final String? barcode; // Mã vạch riêng của đơn vị
  final String? code; // Mã hàng riêng của đơn vị
  final bool isDirectSale; // Cho phép bán trực tiếp trên POS (mặc định true)

  const ProductUnit({
    required this.id,
    required this.unitName,
    this.conversionRate = 1,
    required this.price,
    this.costPrice,
    this.barcode,
    this.code,
    this.isDirectSale = true,
  });

  ProductUnit copyWith({
    String? id,
    String? unitName,
    int? conversionRate,
    double? price,
    double? costPrice,
    String? barcode,
    String? code,
    bool? isDirectSale,
  }) {
    return ProductUnit(
      id: id ?? this.id,
      unitName: unitName ?? this.unitName,
      conversionRate: conversionRate ?? this.conversionRate,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      barcode: barcode ?? this.barcode,
      code: code ?? this.code,
      isDirectSale: isDirectSale ?? this.isDirectSale,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'unitName': unitName,
        'conversionRate': conversionRate,
        'price': price,
        'costPrice': costPrice,
        'barcode': barcode,
        'code': code,
        'isDirectSale': isDirectSale,
      };

  factory ProductUnit.fromMap(Map<dynamic, dynamic> map) {
    return ProductUnit(
      id: map['id'] as String? ?? '',
      unitName: map['unitName'] as String? ?? '',
      conversionRate: (map['conversionRate'] as num? ?? 1).toInt(),
      price: (map['price'] as num? ?? 0).toDouble(),
      costPrice: map['costPrice'] != null
          ? (map['costPrice'] as num).toDouble()
          : null,
      barcode: map['barcode'] as String?,
      code: map['code'] as String?,
      isDirectSale: map['isDirectSale'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductUnit &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          unitName == other.unitName &&
          conversionRate == other.conversionRate &&
          price == other.price &&
          costPrice == other.costPrice &&
          barcode == other.barcode &&
          code == other.code &&
          isDirectSale == other.isDirectSale;

  @override
  int get hashCode =>
      id.hashCode ^
      unitName.hashCode ^
      conversionRate.hashCode ^
      price.hashCode ^
      costPrice.hashCode ^
      barcode.hashCode ^
      code.hashCode ^
      isDirectSale.hashCode;

  @override
  String toString() =>
      'ProductUnit(id: $id, unitName: $unitName, conversionRate: $conversionRate, price: $price, costPrice: $costPrice, barcode: $barcode, code: $code, isDirectSale: $isDirectSale)';
}
