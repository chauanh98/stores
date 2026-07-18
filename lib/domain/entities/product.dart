class Product {
  final String id;
  final String name;
  final String code; // Mã hàng (e.g. XD15)
  final String? barcode; // Mã vạch
  final String? brand;
  final String? model;
  final double price; // Giá bán
  final double costPrice; // Giá vốn
  final Map<String, int>
      branchStocks; // Lượng tồn chi nhánh: {'branch_1': 1, 'branch_2': 0}
  final String category;

  // New fields from Excel
  final String? type;
  final String? category3Levels;
  final String? unit;
  final String? description;
  final String? noteTemplate;
  final String? components;
  final String? imageUrl;

  const Product({
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

  // Tính tổng tồn của tất cả chi nhánh
  int get stock => branchStocks.values.fold(0, (sum, val) => sum + val);

  Product copyWith({
    String? name,
    String? code,
    String? barcode,
    String? brand,
    String? model,
    double? price,
    double? costPrice,
    Map<String, int>? branchStocks,
    String? category,
    String? type,
    String? category3Levels,
    String? unit,
    String? description,
    String? noteTemplate,
    String? components,
    String? imageUrl,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        code: code ?? this.code,
        barcode: barcode ?? this.barcode,
        brand: brand ?? this.brand,
        model: model ?? this.model,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        branchStocks: branchStocks ?? this.branchStocks,
        category: category ?? this.category,
        type: type ?? this.type,
        category3Levels: category3Levels ?? this.category3Levels,
        unit: unit ?? this.unit,
        description: description ?? this.description,
        noteTemplate: noteTemplate ?? this.noteTemplate,
        components: components ?? this.components,
        imageUrl: imageUrl ?? this.imageUrl,
      );
}
