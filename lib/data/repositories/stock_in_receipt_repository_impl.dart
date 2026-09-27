import 'dart:async';

import '../../domain/entities/stock_in_receipt.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/stock_in_receipt_repository.dart';
import '../datasources/stock_in_receipt_remote_data_source.dart';

/// Implementation of [StockInReceiptRepository] backed by Firebase RTDB via
/// [StockInReceiptRemoteDataSource].
class StockInReceiptRepositoryImpl implements StockInReceiptRepository {
  final StockInReceiptRemoteDataSource _remoteDataSource;
  final ProductRepository? _productRepo;

  StockInReceiptRepositoryImpl(
    this._remoteDataSource, {
    ProductRepository? productRepository,
  }) : _productRepo = productRepository;

  @override
  Future<String> saveDraft(StockInReceipt receipt) async {
    final effectiveStoreId = receipt.storeId?.trim().isNotEmpty == true
        ? receipt.storeId!.trim()
        : 'store_001';

    final effectiveId = receipt.id.trim().isNotEmpty
        ? receipt.id.trim()
        : 'PN_DRAFT_${DateTime.now().millisecondsSinceEpoch}';

    final effectiveImportCode = receipt.importCode.trim().isNotEmpty
        ? receipt.importCode.trim()
        : 'PN_${DateTime.now().millisecondsSinceEpoch}';

    final draft = receipt.copyWith(
      id: effectiveId,
      importCode: effectiveImportCode,
      storeId: effectiveStoreId,
      status: 'draft',
      createdAt: receipt.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _remoteDataSource.saveReceipt(
      effectiveStoreId,
      draft.id,
      draft.toMap(),
    );

    return draft.id;
  }

  @override
  Future<void> updateDraft(StockInReceipt receipt) async {
    final effectiveStoreId = receipt.storeId?.trim().isNotEmpty == true
        ? receipt.storeId!.trim()
        : 'store_001';

    final updated = receipt.copyWith(
      storeId: effectiveStoreId,
      status: 'draft',
      updatedAt: DateTime.now(),
    );

    await _remoteDataSource.saveReceipt(
      effectiveStoreId,
      updated.id,
      updated.toMap(),
    );
  }

  @override
  Future<void> deleteDraft({
    required String storeId,
    required String receiptId,
  }) async {
    await _remoteDataSource.deleteReceipt(storeId, receiptId);
  }

  @override
  Future<void> cancelReceipt({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Cancellation reason cannot be empty');
    }
    if (receipt.isCancelled) {
      throw StateError('Receipt is already cancelled');
    }
    if (receipt.isDraft) {
      throw StateError(
          'Cannot cancel a draft receipt. Use deleteDraft instead.');
    }

    final now = DateTime.now();
    final cancelled = receipt.copyWith(
      status: 'cancelled',
      cancelReason: reason,
      cancelledAt: now,
      cancelledBy: cancelledBy,
      updatedAt: now,
    );

    await _remoteDataSource.updateReceipt(
      storeId,
      receipt.id,
      cancelled.toMap(),
    );
  }

  @override
  Stream<List<StockInReceipt>> watchReceipts(String storeId) {
    return _remoteDataSource.watchReceipts(storeId).map((maps) {
      final list = maps.map((m) => StockInReceipt.fromMap(m)).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  @override
  Future<List<StockInReceipt>> fetchReceipts(String storeId) async {
    final maps = await _remoteDataSource.fetchReceipts(storeId);
    final list = maps.map((m) => StockInReceipt.fromMap(m)).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  @override
  Future<StockInReceipt?> getReceiptById({
    required String storeId,
    required String receiptId,
  }) async {
    final map = await _remoteDataSource.getReceipt(storeId, receiptId);
    if (map == null) return null;
    return StockInReceipt.fromMap(map);
  }

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    final effectiveStoreId = receipt.storeId?.trim().isNotEmpty == true
        ? receipt.storeId!.trim()
        : 'store_001';

    await _remoteDataSource.saveReceipt(
      effectiveStoreId,
      receipt.id,
      receipt.toMap(),
    );
  }

  @override
  Future<void> deleteReceipt({
    required String storeId,
    required String receiptId,
  }) async {
    await _remoteDataSource.deleteReceipt(storeId, receiptId);
  }

  @override
  Future<double?> getLatestImportPrice({
    required String storeId,
    required String productId,
  }) async {
    // 1. Query latest import transaction
    final txPrice = await _remoteDataSource.getLatestImportPrice(
      storeId: storeId,
      productId: productId,
    );
    if (txPrice != null && txPrice > 0) {
      return txPrice;
    }

    // 2. Fallback to product cost price if repository is available
    if (_productRepo != null) {
      try {
        final product = await _productRepo.fetchById(productId);
        if (product != null && product.costPrice > 0) {
          return product.costPrice;
        }
      } catch (_) {}
    }

    return null;
  }
}
