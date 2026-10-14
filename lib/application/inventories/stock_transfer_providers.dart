import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/stock_transfer_repository_impl.dart';
import '../../domain/entities/stock_transfer.dart';
import '../../domain/repositories/stock_transfer_repository.dart';
import '../auth/auth_providers.dart';
import '../products/products_providers.dart';
import '../notifications/notification_dispatcher.dart';
import '../orders/orders_providers.dart';
import 'usecases/stock_transfer_use_cases.dart';

final stockTransferRepositoryProvider =
    Provider.autoDispose<StockTransferRepository>((ref) {
  return StockTransferRepositoryImpl(ref.watch(firebaseDatabaseProvider));
});

/// Số phiếu tối đa tải về mỗi lần (mỗi truy vấn gửi/nhận); "Xem thêm" tăng dần.
final stockTransfersLimitProvider = StateProvider.autoDispose<int>((ref) => 30);

/// Phiếu chuyển kho của chi nhánh đang chọn (gửi hoặc nhận).
final stockTransfersProvider =
    StreamProvider.autoDispose<List<StockTransfer>>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  final limit = ref.watch(stockTransfersLimitProvider);
  return ref
      .watch(stockTransferRepositoryProvider)
      .watchTransfers(storeId, limit: limit);
});

/// Số phiếu đang chuyển đến chi nhánh đang chọn (chờ nhận), đọc từ chỉ mục nhẹ
/// nên badge không phải tải nội dung phiếu.
final pendingIncomingTransferCountProvider =
    StreamProvider.autoDispose<int>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  return ref
      .watch(stockTransferRepositoryProvider)
      .watchPendingIncomingCount(storeId);
});

final stockTransferByIdProvider =
    StreamProvider.autoDispose.family<StockTransfer?, String>((ref, id) {
  final db = ref.watch(firebaseDatabaseProvider);
  return db.ref('stock_transfers/$id').onValue.map((e) {
    final v = e.snapshot.value;
    if (v is! Map) return null;
    final t = StockTransfer.fromMap(v);
    return t.id.isEmpty ? t.copyWith(id: id) : t;
  });
});

/// Chỉ admin/giám sát (quyền xem giá vốn) mới thấy giá & giá trị phiếu chuyển.
final canViewTransferPriceProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(authProvider)?.canViewCostPrice ?? false;
});

final saveStockTransferDraftUseCaseProvider =
    Provider.autoDispose<SaveStockTransferDraftUseCase>((ref) {
  return SaveStockTransferDraftUseCase(
    ref.watch(firebaseDatabaseProvider),
    ref.watch(stockTransferRepositoryProvider),
    null,
  );
});

final createStockTransferUseCaseProvider =
    Provider.autoDispose<CreateStockTransferUseCase>((ref) {
  return CreateStockTransferUseCase(
    ref.watch(firebaseDatabaseProvider),
    ref.watch(stockTransferRepositoryProvider),
    ref.watch(notificationDispatcherProvider),
  );
});

final receiveStockTransferUseCaseProvider =
    Provider.autoDispose<ReceiveStockTransferUseCase>((ref) {
  return ReceiveStockTransferUseCase(
    ref.watch(firebaseDatabaseProvider),
    ref.watch(stockTransferRepositoryProvider),
    ref.watch(notificationDispatcherProvider),
  );
});

final cancelStockTransferUseCaseProvider =
    Provider.autoDispose<CancelStockTransferUseCase>((ref) {
  return CancelStockTransferUseCase(
    ref.watch(firebaseDatabaseProvider),
    ref.watch(stockTransferRepositoryProvider),
    null,
  );
});

/// productId -> ảnh chính (kể cả Base64) của chi nhánh đang xem, để hiển thị ảnh
/// mặt hàng trong phiếu mà không phải lưu ảnh nặng vào từng phiếu.
final transferProductImageMapProvider =
    Provider.autoDispose<Map<String, String>>((ref) {
  final products = ref.watch(productListProvider).valueOrNull ?? const [];
  return {
    for (final p in products)
      if (p.primaryImageUrl != null) p.id: p.primaryImageUrl!,
  };
});
