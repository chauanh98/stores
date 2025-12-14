class Product {
  final String id;
  final String name;
  final String brand;
  final String model;
  final double price;
  final int stock;
  final String category;

  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    required this.price,
    required this.stock,
    required this.category,
  });

  Product copyWith({int? stock}) => Product(
    id: id,
    name: name,
    brand: brand,
    model: model,
    price: price,
    stock: stock ?? this.stock,
    category: category,
  );
}