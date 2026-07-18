import '../entities/product_report.dart';

abstract class ReportRepository {
  Future<ProductReport> productReport({
    required String productId,
    required DateTime from,
    required DateTime to,
  });
}
