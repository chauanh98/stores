import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/product.dart';

class InterStoreTransferService {
  InterStoreTransferService(this._db);
  final FirebaseDatabase _db;

  Future<String?> transferProduct({
    required String sourceStoreId,
    required String targetStoreId,
    required Product product,
    required int quantity,
  }) async {
    try {
      if (quantity <= 0) return 'Số lượng phải lớn hơn 0';
      if (product.stock < quantity) return 'Không đủ số lượng trong kho';
      if (sourceStoreId == targetStoreId) return 'Không thể chuyển cùng kho';

      final updates = <String, dynamic>{};
      final now = DateTime.now();
      final isoDate = now.toIso8601String();
      final timestamp = now.millisecondsSinceEpoch;

      // 1. Deduct from source store product
      final newSourceStock = product.stock - quantity;
      updates['stores/$sourceStoreId/products/${product.id}/stock'] = newSourceStock;

      // 2. Add Export transaction to source store
      final exportTxId = 'tx_${timestamp}_export';
      updates['stores/$sourceStoreId/inventory_transactions/$exportTxId'] = {
        'id': exportTxId,
        'productId': product.id,
        'type': 'export',
        'quantity': quantity,
        'date': isoDate,
        'note': 'Chuyển sang cửa hàng $targetStoreId',
      };

      // 3. Add to target store product
      final targetProductSnap = await _db.ref('stores/$targetStoreId/products/${product.id}').get();
      int currentTargetStock = 0;
      if (targetProductSnap.exists && targetProductSnap.value != null) {
         final map = Map<dynamic, dynamic>.from(targetProductSnap.value as Map);
         currentTargetStock = (map['stock'] ?? 0) as int;
         updates['stores/$targetStoreId/products/${product.id}/stock'] = currentTargetStock + quantity;
      } else {
         updates['stores/$targetStoreId/products/${product.id}'] = {
           'id': product.id,
           'name': product.name,
           'brand': product.brand,
           'model': product.model,
           'price': product.price,
           'stock': quantity,
           'category': product.category,
         };
      }

      // 4. Add Import transaction to target store
      final importTxId = 'tx_${timestamp}_import';
      updates['stores/$targetStoreId/inventory_transactions/$importTxId'] = {
        'id': importTxId,
        'productId': product.id,
        'type': 'import',
        'quantity': quantity,
        'date': isoDate,
        'note': 'Nhận từ cửa hàng $sourceStoreId',
      };

      await _db.ref().update(updates);
      return null; // success
    } catch (e) {
      return 'Lỗi: $e';
    }
  }
}

final interStoreTransferServiceProvider = Provider<InterStoreTransferService>((ref) {
  return InterStoreTransferService(FirebaseDatabase.instance);
});
