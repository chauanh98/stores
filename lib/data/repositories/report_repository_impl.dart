import '../../domain/entities/product_report.dart';
import '../../domain/entities/transaction_type.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/report_repository.dart';

class ReportRepositoryImpl implements ReportRepository {
  ReportRepositoryImpl(this.products, this.inventory);

  final ProductRepository products;
  final InventoryRepository inventory;

  @override
  Future<ProductReport> productReport({
    required String productId,
    required DateTime from,
    required DateTime to,
  }) async {
    final product = await products.fetchById(productId);
    if (product == null) {
      throw StateError('Product not found');
    }

    final txs = await inventory.watchByProduct(productId).first;
    final range = txs.where((t) => !t.date.isBefore(from) && !t.date.isAfter(to));

    final exported = range.where((t) => t.type == TransactionType.export);
    final imported = range.where((t) => t.type == TransactionType.import);

    final totalQty = exported.fold<int>(0, (s, t) => s + t.quantity);
    final revenue = exported.fold<double>(0, (s, t) => s + t.quantity * product.price);
    final importCost = imported.fold<double>(0, (s, t) => s + (t.importPrice ?? 0) * t.quantity);
    final profit = revenue - importCost;

    return ProductReport(
      product: product,
      totalQuantity: totalQty,
      revenue: revenue,
      importPrice: importCost,
      profit: profit,
    );
  }
}