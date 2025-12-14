import '../entities/inventory_transaction.dart';

abstract class InventoryRepository {
  Stream<List<InventoryTransaction>> watchByProduct(String productId);
  Future<void> record(InventoryTransaction tx);
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
      DateTime startDate, DateTime endDate);
}