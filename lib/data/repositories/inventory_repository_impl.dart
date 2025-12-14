import '../../domain/entities/inventory_transaction.dart';
import '../../domain/entities/transaction_type.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../datasources/firebase/inventory_remote_data_source.dart';
import '../models/inventory_transaction_model.dart';

class InventoryRepositoryImpl implements InventoryRepository {
  InventoryRepositoryImpl(this._ds);
  final InventoryRemoteDataSource _ds;

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      _ds.watchByProduct(productId).map((list) {
        return list.map((m) {
          final model = InventoryTransactionModel.fromMap(m);
          return InventoryTransaction(
            id: model.id,
            productId: model.productId,
            type: model.type == 'import' ? TransactionType.import : TransactionType.export,
            quantity: model.quantity,
            date: model.date,
            note: model.note,
            importPrice: model.importPrice,
          );
        }).toList();
      });

  @override
  Future<void> record(InventoryTransaction tx) {
    final map = InventoryTransactionModel(
      id: tx.id,
      productId: tx.productId,
      type: tx.type == TransactionType.import ? 'import' : 'export',
      quantity: tx.quantity,
      date: tx.date,
      note: tx.note,
      importPrice: tx.importPrice,
    ).toMap();
    return _ds.record(tx.id, map);
  }

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
      DateTime startDate, DateTime endDate) {
    return _ds.watchImportsByDateRange(startDate, endDate).map((list) {
      return list.map((m) {
        final model = InventoryTransactionModel.fromMap(m);
        return InventoryTransaction(
          id: model.id,
          productId: model.productId,
          type: TransactionType.import,
          quantity: model.quantity,
          date: model.date,
          note: model.note,
          importPrice: model.importPrice,
        );
      }).toList();
    });
  }
}