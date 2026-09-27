import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/store_resolver_helper.dart';
import '../../data/models/product_model.dart';
import '../../domain/entities/product.dart';

class InterStoreTransferService {
  InterStoreTransferService(this._db);

  final FirebaseDatabase? _db;

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
      if (sourceStoreId.isEmpty || targetStoreId.isEmpty)
        return 'Chi nhánh không hợp lệ';
      if (quantity <= 0) return 'Số lượng phải lớn hơn 0';
      if (sourceStoreId == targetStoreId) return 'Không thể chuyển cùng kho';

      final normSource = StoreResolverHelper.normalizeStoreId(sourceStoreId);
      final normTarget = StoreResolverHelper.normalizeStoreId(targetStoreId);
      if (normSource.isNotEmpty && normSource == normTarget) {
        return 'Không thể chuyển cùng kho';
      }

      final sourceCurrentStock = product.stockInBranch(sourceStoreId);
      if (sourceCurrentStock < quantity) {
        return 'Không đủ số lượng trong kho';
      }

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
        if (id == 'store_001') return 'Chi nhánh Đông Thắng';
        if (id == 'store_002') return 'Chi nhánh Thới Bình';
        return 'Chi nhánh $id';
      }

      final sourceLabel = getStoreName(sourceStoreId, sourceStoreName);
      final targetLabel = getStoreName(targetStoreId, targetStoreName);

      // Inspect target store stock in DB if exists to avoid overwriting newer stock
      int targetCurrentStock = product.stockInBranch(targetStoreId);
      DataSnapshot? targetProductSnap;
      if (_db != null) {
        targetProductSnap =
            await _db.ref('stores/$targetStoreId/products/${product.id}').get();
        if (targetProductSnap.exists && targetProductSnap.value is Map) {
          final tMap =
              Map<dynamic, dynamic>.from(targetProductSnap.value as Map);
          final tModel = ProductModel.fromMap(tMap, targetStoreId);
          final snapTargetStock =
              tModel.toEntity().stockInBranch(targetStoreId);
          if (snapTargetStock > targetCurrentStock) {
            targetCurrentStock = snapTargetStock;
          }
        }
      }

      final newSourceStock = (sourceCurrentStock - quantity).clamp(0, 999999);
      final newTargetStock = targetCurrentStock + quantity;

      // Build unified, synchronized branchStocks for both stores
      final updatedBranchStocks = Map<String, int>.from(product.branchStocks);
      updatedBranchStocks[sourceStoreId] = newSourceStock;
      updatedBranchStocks[targetStoreId] = newTargetStock;
      if (normSource.isNotEmpty)
        updatedBranchStocks[normSource] = newSourceStock;
      if (normTarget.isNotEmpty)
        updatedBranchStocks[normTarget] = newTargetStock;

      if (normSource == 'store_001' ||
          normTarget == 'store_001' ||
          sourceStoreId == 'store_001' ||
          targetStoreId == 'store_001') {
        final s1 = (normSource == 'store_001' || sourceStoreId == 'store_001')
            ? newSourceStock
            : newTargetStock;
        updatedBranchStocks['store_001'] = s1;
        updatedBranchStocks['branch_1'] = s1;
      }
      if (normSource == 'store_002' ||
          normTarget == 'store_002' ||
          sourceStoreId == 'store_002' ||
          targetStoreId == 'store_002') {
        final s2 = (normSource == 'store_002' || sourceStoreId == 'store_002')
            ? newSourceStock
            : newTargetStock;
        updatedBranchStocks['store_002'] = s2;
        updatedBranchStocks['branch_2'] = s2;
      }

      // 1. Update source store product's branchStocks
      updates['stores/$sourceStoreId/products/${product.id}/branchStocks'] =
          updatedBranchStocks;

      // 2. Add Export transaction to source store
      final exportTxId = 'tx_${timestamp}_export';
      updates['stores/$sourceStoreId/inventory_transactions/$exportTxId'] = {
        'id': exportTxId,
        'productId': product.id,
        'type': 'export',
        'quantity': quantity,
        'date': isoDate,
        'note': 'Chuyển hàng sang $targetLabel',
        'importPrice': product.costPrice,
        'storeId': sourceStoreId,
        if (createdBy != null) 'createdBy': createdBy,
        if (createdByName != null) 'createdByName': createdByName,
      };

      // 3. Update or create target store product with unified branchStocks
      if (targetProductSnap != null &&
          targetProductSnap.exists &&
          targetProductSnap.value != null) {
        updates['stores/$targetStoreId/products/${product.id}/branchStocks'] =
            updatedBranchStocks;
      } else {
        // Create full product record in target store
        final fullTargetProduct = ProductModel.fromEntity(
          product.copyWith(branchStocks: updatedBranchStocks),
        ).toMap();
        updates['stores/$targetStoreId/products/${product.id}'] =
            fullTargetProduct;
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
        'importPrice': product.costPrice,
        'storeId': targetStoreId,
        if (createdBy != null) 'createdBy': createdBy,
        if (createdByName != null) 'createdByName': createdByName,
      };

      if (_db == null) return null;
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
