class Product {
  final String id;
  final String name;
  final String code; // Mã hàng (e.g. MDF24)
  final String? barcode; // Mã vạch
  final String brand;
  final String model;
  final double price; // Giá bán
  final double costPrice; // Giá vốn
  final Map<String, int> branchStocks; // Lượng tồn chi nhánh: {'branch_1': 1, 'branch_2': 0}
  final String category;

  const Product({
    required this.id,
    required this.name,
    required this.code,
    this.barcode,
    required this.brand,
    required this.model,
    required this.price,
    required this.costPrice,
    required this.branchStocks,
    required this.category,
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
  }) => Product(
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
  );
}