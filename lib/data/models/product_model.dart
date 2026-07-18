class ProductModel {
  final String id;
  final String name;
  final String code;
  final String? barcode;
  final String? brand;
  final String? model;
  final double price;
  final double costPrice;
  final Map<String, int> branchStocks;
  final String category;

  // New fields from Excel
  final String? type;
  final String? category3Levels;
  final String? unit;
  final String? description;
  final String? noteTemplate;
  final String? components;
  final String? imageUrl;

  const ProductModel({
    required this.id,
    required this.name,
    required this.code,
    this.barcode,
    this.brand,
    this.model,
    required this.price,
    required this.costPrice,
    required this.branchStocks,
    required this.category,
    this.type,
    this.category3Levels,
    this.unit,
    this.description,
    this.noteTemplate,
    this.components,
    this.imageUrl,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'barcode': barcode,
        'brand': brand,
        'model': model,
        'price': price,
        'costPrice': costPrice,
        'branchStocks': branchStocks,
        'category': category,
        'type': type,
        'category3Levels': category3Levels,
        'unit': unit,
        'description': description,
        'noteTemplate': noteTemplate,
        'components': components,
        'imageUrl': imageUrl,
      };

  factory ProductModel.fromMap(Map<dynamic, dynamic> map) {
    // Fallback cho branchStocks nếu bản ghi cũ chỉ có trường 'stock'
    Map<String, int> resolvedStocks = {};
    if (map['branchStocks'] != null) {
      resolvedStocks = Map<String, int>.from(
        (map['branchStocks'] as Map)
            .map((k, v) => MapEntry(k as String, v as int)),
      );
    } else {
      final oldStock = map['stock'] as int? ?? 0;
      resolvedStocks = {'branch_1': oldStock, 'branch_2': 0};
    }

    // Fallback cho giá vốn nếu bản ghi cũ chưa có
    final double resolvedCostPrice = map['costPrice'] != null
        ? (map['costPrice'] as num).toDouble()
        : ((map['price'] as num? ?? 0).toDouble() * 0.7);

    return ProductModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      code: map['code'] as String? ?? (map['id'] as String? ?? ''),
      barcode: map['barcode'] as String?,
      brand: map['brand'] as String?,
      model: map['model'] as String?,
      price: (map['price'] as num? ?? 0).toDouble(),
      costPrice: resolvedCostPrice,
      branchStocks: resolvedStocks,
      category: map['category'] as String? ?? 'Khác',
      type: map['type'] as String?,
      category3Levels: map['category3Levels'] as String?,
      unit: map['unit'] as String?,
      description: map['description'] as String?,
      noteTemplate: map['noteTemplate'] as String?,
      components: map['components'] as String?,
      imageUrl: map['imageUrl'] as String?,
    );
  }
}
