import '../../../domain/entities/stock_in_receipt.dart';
import '../../../domain/repositories/stock_in_receipt_repository.dart';

/// Use case to save a stock-in receipt as a draft (Phiếu tạm).
///
/// **CRITICAL INVARIANT**:
/// Saving a draft MUST NEVER mutate branch stocks, product cost prices,
/// inventory transactions, or supplier debt / purchase totals.
class SaveStockInDraftUseCase {
  final StockInReceiptRepository _repository;

  SaveStockInDraftUseCase(this._repository);

  /// Executes saving of the draft receipt.
  /// Returns the saved receipt ID.
  Future<String> execute(StockInReceipt receipt) async {
    final effectiveStoreId = receipt.storeId?.trim().isNotEmpty == true
        ? receipt.storeId!.trim()
        : 'store_001';

    final now = DateTime.now();
    final effectiveId = receipt.id.trim().isNotEmpty
        ? receipt.id.trim()
        : 'PN_DRAFT_${now.millisecondsSinceEpoch}';

    final effectiveImportCode = receipt.importCode.trim().isNotEmpty
        ? receipt.importCode.trim()
        : 'PN_${now.millisecondsSinceEpoch}';

    final draft = receipt.copyWith(
      id: effectiveId,
      importCode: effectiveImportCode,
      storeId: effectiveStoreId,
      status: 'draft',
      createdAt: receipt.createdAt ?? now,
      updatedAt: now,
    );

    return await _repository.saveDraft(draft);
  }
}
