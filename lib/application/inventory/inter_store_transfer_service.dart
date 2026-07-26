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
    String? sourceStoreName,
    String? targetStoreName,
    String? createdBy,
    String? createdByName,
  }) async {
    try {
      if (quantity <= 0) return 'Số lượng phải lớn hơn 0';
      if (product.stock < quantity) return 'Không đủ số lượng trong kho';
      if (sourceStoreId == targetStoreId) return 'Không thể chuyển cùng kho';

      final updates = <String, dynamic>{};
      final now = DateTime.now();
      final isoDate = now.toIso8601String();
      final timestamp = now.millisecondsSinceEpoch;

      String getStoreName(String id, String? name) {
        if (name != null &&
            name.isNotEmpty &&
            name != id &&
            !name.startsWith('store_')) {
          return name;
        }
        if (id == 'store_001') return 'Chi nhánh Thới Bình';
        if (id == 'store_002') return 'Chi nhánh Đông Thắng';
        return 'Chi nhánh $id';
      }

      final sourceLabel = getStoreName(sourceStoreId, sourceStoreName);
      final targetLabel = getStoreName(targetStoreId, targetStoreName);

      // 1. Deduct from source store product's branchStocks
      final sourceBranchStocks = Map<String, int>.from(product.branchStocks);
      final sourceBranchStock = sourceBranchStocks['branch_1'] ?? product.stock;
      sourceBranchStocks['branch_1'] =
          (sourceBranchStock - quantity).clamp(0, 999999);
      updates['stores/$sourceStoreId/products/${product.id}/branchStocks'] =
          sourceBranchStocks;

      // 2. Add Export transaction to source store
      final exportTxId = 'tx_${timestamp}_export';
      updates['stores/$sourceStoreId/inventory_transactions/$exportTxId'] = {
        'id': exportTxId,
        'productId': product.id,
        'type': 'export',
        'quantity': quantity,
        'date': isoDate,
        'note': 'Chuyển hàng sang $targetLabel',
        if (createdBy != null) 'createdBy': createdBy,
        if (createdByName != null) 'createdByName': createdByName,
      };

      // 3. Add to target store product's branchStocks
      final targetProductSnap =
          await _db.ref('stores/$targetStoreId/products/${product.id}').get();

      if (targetProductSnap.exists && targetProductSnap.value != null) {
        final map = Map<dynamic, dynamic>.from(targetProductSnap.value as Map);
        Map<String, int> targetBranchStocks = {};
        if (map['branchStocks'] != null && map['branchStocks'] is Map) {
          targetBranchStocks = Map<String, int>.from(
            (map['branchStocks'] as Map)
                .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
          );
        }
        final currentTargetStock = targetBranchStocks['branch_1'] ??
            (map['stock'] as num? ?? 0).toInt();
        targetBranchStocks['branch_1'] = currentTargetStock + quantity;

        updates['stores/$targetStoreId/products/${product.id}/branchStocks'] =
            targetBranchStocks;
      } else {
        // Create new product record in target store
        updates['stores/$targetStoreId/products/${product.id}'] = {
          'id': product.id,
          'name': product.name,
          'code': product.code,
          'barcode': product.barcode,
          'brand': product.brand,
          'model': product.model,
          'price': product.price,
          'costPrice': product.costPrice,
          'branchStocks': {'branch_1': quantity, 'branch_2': 0},
          'category': product.category,
          'unit': product.unit,
          'description': product.description,
          'imageUrl': product.imageUrl,
          'isCombo': product.isCombo,
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
        'note': 'Nhận chuyển kho từ $sourceLabel',
        if (createdBy != null) 'createdBy': createdBy,
        if (createdByName != null) 'createdByName': createdByName,
      };

      await _db.ref().update(updates);
      return null; // success
    } catch (e) {
      return 'Lỗi: $e';
    }
  }
}

final interStoreTransferServiceProvider =
    Provider<InterStoreTransferService>((ref) {
  return InterStoreTransferService(FirebaseDatabase.instance);
});
