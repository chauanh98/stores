import '../entities/stock_transfer.dart';

abstract class StockTransferRepository {
  /// Đường dẫn chỉ mục phiếu chờ nhận của chi nhánh (chỉ chứa id phiếu).
  static String pendingIndexPath(String storeId, [String? transferId]) {
    final key = storeId.trim();
    final base = 'stock_transfer_pending/$key';
    return transferId == null ? base : '$base/$transferId';
  }

  /// Phiếu liên quan đến [storeId] (gửi hoặc nhận), mới nhất trước.
  /// [storeId] rỗng/`all` => mọi chi nhánh (giới hạn [limit] phiếu gần nhất).
  Stream<List<StockTransfer>> watchTransfers(String storeId, {int limit = 100});

  /// Số phiếu ĐANG CHUYỂN chờ chi nhánh [storeId] nhận. Đọc từ chỉ mục nhẹ
  /// `stock_transfer_pending/{store}` (chỉ chứa id), không tải nội dung phiếu.
  Stream<int> watchPendingIncomingCount(String storeId);

  Future<StockTransfer?> getById(String id);

  /// Sinh mã phiếu kế tiếp (TRF000001...) bằng transaction.
  Future<String> nextCode();
}
