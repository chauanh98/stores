import 'package:stores/domain/entities/product.dart';

class ProductReport {
  final Product product;
  final int totalQuantity;
  final double revenue;
  final double importPrice;
  final double profit;

  const ProductReport({
    required this.product,
    required this.totalQuantity,
    required this.revenue,
    required this.importPrice,
    required this.profit,
  });
}
