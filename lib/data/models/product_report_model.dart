import 'package:stores/data/models/product_model.dart';

class ProductReportModel {
  final ProductModel product;
  final int totalQuantity;
  final double revenue;
  final double importPrice;
  final double profit;

  const ProductReportModel({
    required this.product,
    required this.totalQuantity,
    required this.revenue,
    required this.importPrice,
    required this.profit,
  });
}