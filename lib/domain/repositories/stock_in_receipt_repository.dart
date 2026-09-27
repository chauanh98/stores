import '../entities/stock_in_receipt.dart';

/// Repository contract for managing stock-in receipts, drafts, and cancellations.
abstract class StockInReceiptRepository {
  /// Saves a receipt as a draft (status: 'draft') without modifying inventory or debt.
  /// Returns the saved receipt ID.
  Future<String> saveDraft(StockInReceipt receipt);

  /// Updates an existing draft receipt.
  Future<void> updateDraft(StockInReceipt receipt);

  /// Deletes a draft receipt from RTDB.
  Future<void> deleteDraft({
    required String storeId,
    required String receiptId,
  });

  /// Cancels a completed receipt, rolling back stock and debt atomically.
  Future<void> cancelReceipt({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  });

  /// Streams live stock-in receipts (including drafts and completed) for a given store.
  Stream<List<StockInReceipt>> watchReceipts(String storeId);

  /// Fetches stock-in receipts once for a given store.
  Future<List<StockInReceipt>> fetchReceipts(String storeId);

  /// Fetches a single receipt by ID.
  Future<StockInReceipt?> getReceiptById({
    required String storeId,
    required String receiptId,
  });

  /// Saves or updates a completed/cancelled receipt.
  Future<void> saveReceipt(StockInReceipt receipt);

  /// Deletes a receipt by ID.
  Future<void> deleteReceipt({
    required String storeId,
    required String receiptId,
  });

  /// Retrieves the latest unit import price for [productId] in [storeId],
  /// querying inventory transactions and falling back to product cost price.
  Future<double?> getLatestImportPrice({
    required String storeId,
    required String productId,
  });
}
