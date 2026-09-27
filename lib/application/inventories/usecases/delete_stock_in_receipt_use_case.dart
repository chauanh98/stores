import '../../../domain/entities/stock_in_receipt.dart';
import '../../../domain/repositories/stock_in_receipt_repository.dart';

/// Use case that deletes a draft or hard-deletes a cancelled receipt from RTDB.
///
/// **SAFETY INVARIANT**:
/// A completed receipt CANNOT be deleted directly without first being cancelled,
/// to ensure stock and debt rollbacks are executed safely.
class DeleteStockInReceiptUseCase {
  final StockInReceiptRepository _repository;

  DeleteStockInReceiptUseCase(this._repository);

  /// Executes deletion of [receipt] from [storeId].
  Future<void> execute({
    required String storeId,
    required StockInReceipt receipt,
  }) async {
    if (receipt.isCompleted) {
      throw StateError(
        'Không thể xóa phiếu nhập đã hoàn thành. Vui lòng hủy phiếu để hoàn trả tồn kho và công nợ trước khi xóa.',
      );
    }

    await _repository.deleteReceipt(
      storeId: storeId,
      receiptId: receipt.id,
    );
  }
}
