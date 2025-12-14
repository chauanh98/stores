class ProductModel {
  final String id;
  final String name;
  final String brand;
  final String model;
  final double price;
  final int stock;
  final String category;

  const ProductModel({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    required this.price,
    required this.stock,
    required this.category,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'brand': brand,
    'model': model,
    'price': price,
    'stock': stock,
    'category': category,
  };

  factory ProductModel.fromMap(Map<dynamic, dynamic> map) => ProductModel(
    id: map['id'] as String,
    name: map['name'] as String,
    brand: map['brand'] as String,
    model: map['model'] as String,
    price: (map['price'] as num).toDouble(),
    stock: map['stock'] as int,
    category: map['category'] as String,
  );
}