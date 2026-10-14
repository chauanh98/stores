import 'package:firebase_database/firebase_database.dart';

import '../../../core/utils/store_resolver_helper.dart';
import '../../../data/models/product_model.dart';

/// Cách ghi tồn/giá vốn của [productId] vào từng chi nhánh khi nhập/hủy phiếu.
///
/// - Chi nhánh của phiếu ([storeId], dạng chuẩn) luôn được ghi (`false`: ghi
///   cả bản đồ tồn đã cập nhật).
/// - Chi nhánh khác chỉ được ghi khi bản ghi sản phẩm ĐÃ CÓ ở đó (ghi vào đường
///   dẫn con của sản phẩm chưa tồn tại tạo bản ghi "mồ côi" không tên/giá, và
///   các nút `stores/branch_1`, `stores/branch_2` không phải chi nhánh thật).
///   Giá trị `true`: bản ghi có `branchStocks` dạng Map => chỉ ghi RIÊNG các
///   khoá của chi nhánh đang nhập, không ghi đè tồn các chi nhánh khác bằng
///   bản đồ cũ của chi nhánh này. `false`: bản ghi cũ (chỉ có `stock`/`stocks`)
///   => ghi cả bản đồ để không mất tồn.
Future<Map<String, Map<String, int>?>> storesToSyncProduct(
  FirebaseDatabase? db,
  String storeId,
  String productId,
) async {
  final primary = StoreResolverHelper.normalizeStoreId(storeId);
  final out = <String, Map<String, int>?>{
    if (primary.isNotEmpty) primary: null,
  };
  if (db == null) return out;
  final others = ['store_001', 'store_002'].where((s) => s != primary).toList();
  final modes = await Future.wait(others.map((s) async {
    try {
      final base = 'stores/$s/products/$productId';
      final bs = await db.ref('$base/branchStocks').get();
      if (bs.exists && bs.value is Map) {
        return ProductModel.fromMap(
                {'id': productId, 'branchStocks': bs.value}, s)
            .branchStocks;
      }
      final name = await db.ref('$base/name').get();
      if (name.exists) return <String, int>{}; // bản ghi cũ
      // Chưa thấy trường nào: đọc cả nút (rỗng/không tồn tại => gần như 0 byte).
      final whole = await db.ref('stores/$s/products').child(productId).get();
      if (whole.exists && whole.value is Map) {
        return ProductModel.fromMap(
                Map<dynamic, dynamic>.from(whole.value as Map), s)
            .branchStocks;
      }
      return null;
    } catch (_) {
      return null;
    }
  }));
  for (var i = 0; i < others.length; i++) {
    final m = modes[i];
    if (m != null) out[others[i]] = m; // {} = bản ghi cũ (chỉ có stock)
  }
  return out;
}

/// Khoá `branchStocks` của chi nhánh [storeId] (khoá chuẩn + alias cũ).
List<String> branchStockKeys(String storeId) {
  final norm = StoreResolverHelper.normalizeStoreId(storeId);
  final keys = <String>{
    if (storeId.isNotEmpty) storeId,
    if (norm.isNotEmpty) norm
  };
  if (norm == 'store_001') keys.add('branch_1');
  if (norm == 'store_002') keys.add('branch_2');
  return keys.toList();
}

/// Ghi tồn mới của [storeId] cho [productId] vào mọi chi nhánh cần đồng bộ.
///
/// Với chi nhánh khác, bản đồ tồn hiện có CỦA CHÍNH BẢN GHI ĐÓ được giữ nguyên
/// và chỉ khoá của [storeId] được cập nhật (không ghi đè tồn các chi nhánh khác
/// bằng bản đồ cũ của chi nhánh đang nhập). Bản ghi cũ (chưa có bản đồ tồn)
/// nhận bản đồ đầy đủ [fullBranchStocks] để không mất tồn.
void writeProductStockUpdates(
  Map<String, dynamic> updates, {
  required Map<String, Map<String, int>?> targets,
  required String productId,
  required String storeId,
  required int newStock,
  required Map<String, int> fullBranchStocks,
  required double costPrice,
}) {
  final keys = branchStockKeys(storeId);
  targets.forEach((sId, current) {
    final base = 'stores/$sId/products/$productId';
    if (current == null) {
      updates['$base/branchStocks'] = fullBranchStocks;
    } else if (current.isEmpty) {
      updates['$base/branchStocks'] = fullBranchStocks;
    } else {
      final merged = Map<String, int>.from(current);
      for (final k in keys) {
        merged[k] = newStock;
      }
      updates['$base/branchStocks'] = merged;
    }
    updates['$base/costPrice'] = costPrice;
  });
}

/// Giữ chỗ trạng thái phiếu nhập bằng transaction để 2 thiết bị / bấm đúp
/// không áp dụng (hoàn thành hoặc hủy) cùng một phiếu hai lần.
class ReceiptStatusClaim {
  ReceiptStatusClaim._(this._ref, this._prev);
  final DatabaseReference? _ref;
  final Object? _prev;

  /// Trả `null` nếu phiếu đã ở trạng thái [blocked] (đã xử lý).
  static Future<ReceiptStatusClaim?> acquire(
    FirebaseDatabase db,
    String path, {
    required String to,
    required Set<String> blocked,
  }) async {
    final ref = db.ref(path);
    Object? prev;
    try {
      final tx = await ref.runTransaction((current) {
        prev = current;
        if (current is String && blocked.contains(current)) {
          return Transaction.abort();
        }
        return Transaction.success(to);
      });
      if (!tx.committed) return null;
      return ReceiptStatusClaim._(ref, prev);
    } catch (_) {
      // Không có transaction (mất mạng / môi trường giả lập): hành vi cũ,
      // không giữ chỗ và không có gì để hoàn lại.
      return ReceiptStatusClaim._(null, null);
    }
  }

  /// Trả trạng thái cũ khi việc ghi thất bại.
  Future<void> release() async {
    final ref = _ref;
    if (ref == null) return;
    try {
      if (_prev == null) {
        await ref.remove();
      } else {
        await ref.set(_prev);
      }
    } catch (_) {}
  }
}
