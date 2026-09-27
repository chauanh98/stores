import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../../../data/models/inventory_transaction_model.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/stock_in_receipt.dart';
import '../../../domain/entities/supplier.dart';
import '../../../domain/entities/supplier_debt_transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../../domain/repositories/product_repository.dart';
import '../../../domain/repositories/stock_in_receipt_repository.dart';
import '../../../domain/repositories/supplier_repository.dart';

/// Use case that rolls back a completed stock-in receipt atomically.
///
/// Multi-path rollback operations:
/// 1. Updates receipt status to 'cancelled' with cancelReason, cancelledAt, cancelledBy.
/// 2. Rolls back branch stocks: `branchStocks[storeId] = (currentStock - qty).clamp(0, 999999)`
///    with branch alias synchronization (`store_001` <-> `branch_1`, `store_002` <-> `branch_2`).
/// 3. Records reversal inventory transactions for each cancelled item line.
/// 4. Rolls back supplier debt (`currentDebt -= remainingDebt`) and total purchase
///    (`totalPurchase -= netPayable`), recording reversal `SupplierDebtTransaction`.
class CancelStockInReceiptUseCase {
  final FirebaseDatabase? _db;
  final ProductRepository _productRepo;
  final InventoryRepository _inventoryRepo;
  final SupplierRepository _supplierRepo;
  final StockInReceiptRepository _receiptRepo;

  CancelStockInReceiptUseCase({
    FirebaseDatabase? db,
    required ProductRepository productRepository,
    required InventoryRepository inventoryRepository,
    required SupplierRepository supplierRepository,
    required StockInReceiptRepository receiptRepository,
  })  : _db = db,
        _productRepo = productRepository,
        _inventoryRepo = inventoryRepository,
        _supplierRepo = supplierRepository,
        _receiptRepo = receiptRepository;

  /// Executes atomic cancellation and rollback.
  Future<void> execute({
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

    final cancelledReceipt = receipt.copyWith(
      status: 'cancelled',
      cancelReason: reason,
      cancelledAt: now,
      cancelledBy: cancelledBy,
      updatedAt: now,
    );

    final Map<String, dynamic> updates = {};

    // 1. Receipt status rollback update
    updates['stores/$storeId/stock_in_receipts/${receipt.id}'] =
        cancelledReceipt.toMap();

    // 2. Product stock rollback with branch alias synchronization and duplicate productId accumulator
    final List<Product> rolledBackProducts = [];
    final List<InventoryTransaction> reversalTransactions = [];
    final Map<String, Product> productCache = {};
    final Map<String, int> productQuantityMap = {};

    for (int i = 0; i < receipt.items.length; i++) {
      final item = receipt.items[i];
      Product? product = productCache[item.productId];
      if (product == null) {
        try {
          product = await _productRepo.fetchById(item.productId);
        } catch (_) {}

        if (product == null &&
            item.productCode != null &&
            item.productCode!.isNotEmpty) {
          try {
            product = await _productRepo.fetchById(item.productCode!);
          } catch (_) {}
        }

        if (product != null) {
          productCache[item.productId] = product;
          productCache[product.id] = product;
          if (item.productCode != null && item.productCode!.isNotEmpty) {
            productCache[item.productCode!] = product;
          }
        }
      }

      if (product != null) {
        productQuantityMap[product.id] =
            (productQuantityMap[product.id] ?? 0) + item.quantity;
      }

      // Reversal inventory transaction
      final revTxId =
          'tx_cancel_${receipt.importCode}_${item.productId}_${i}_${now.millisecondsSinceEpoch}';
      final revTx = InventoryTransaction(
        id: revTxId,
        productId: item.productId,
        type: TransactionType.export,
        quantity: item.quantity,
        date: now,
        importPrice: item.unitPrice,
        storeId: storeId,
        createdBy: cancelledBy,
        createdByName: cancelledBy,
        supplierId: receipt.supplierId,
        supplierName: receipt.supplierName,
        importCode: receipt.importCode,
        note: 'Hủy phiếu nhập ${receipt.importCode}: $reason',
      );
      reversalTransactions.add(revTx);

      updates['stores/$storeId/inventory_transactions/$revTxId'] =
          InventoryTransactionModel.fromEntity(revTx).toMap();
    }

    // Apply accumulated rollback stock per distinct product
    for (final entry in productQuantityMap.entries) {
      final productId = entry.key;
      final totalQuantity = entry.value;
      final product = productCache[productId]!;

      final currentStock = product.stockInBranch(storeId);
      final rolledBackStock = (currentStock - totalQuantity).clamp(0, 999999);
      final branchStocks = Map<String, int>.from(product.branchStocks);
      branchStocks[storeId] = rolledBackStock;

      // Synchronize canonical alias keys
      if (storeId == 'store_001' || storeId == 'branch_1') {
        branchStocks['store_001'] = rolledBackStock;
        branchStocks['branch_1'] = rolledBackStock;
      } else if (storeId == 'store_002' || storeId == 'branch_2') {
        branchStocks['store_002'] = rolledBackStock;
        branchStocks['branch_2'] = rolledBackStock;
      }

      final updatedProduct = product.copyWith(branchStocks: branchStocks);
      rolledBackProducts.add(updatedProduct);

      final targetStoreIds = <String>{
        storeId,
        'store_001',
        'branch_1',
        'store_002',
        'branch_2',
      };
      for (final sId in targetStoreIds) {
        updates['stores/$sId/products/${product.id}/branchStocks'] =
            branchStocks;
      }
    }

    // 3. Supplier debt & total purchase rollback
    Supplier? rolledBackSupplier;
    SupplierDebtTransaction? revDebtTx;
    if (receipt.supplierId != null && receipt.supplierId!.trim().isNotEmpty) {
      Supplier? supplier;
      try {
        supplier = await _supplierRepo.fetchById(receipt.supplierId!.trim());
      } catch (_) {}

      if (supplier != null) {
        final double effectiveNetPayable = receipt.effectiveNetPayable;
        final double debtToReverse = receipt.remainingDebt;

        final double newTotalPurchase =
            (supplier.totalPurchase - effectiveNetPayable)
                .clamp(0.0, double.infinity);
        final double newCurrentDebt =
            (supplier.currentDebt - debtToReverse).clamp(0.0, double.infinity);

        rolledBackSupplier = supplier.copyWith(
          currentDebt: newCurrentDebt,
          totalPurchase: newTotalPurchase,
        );

        updates['shared_suppliers/${supplier.id}/currentDebt'] = newCurrentDebt;
        updates['shared_suppliers/${supplier.id}/totalPurchase'] =
            newTotalPurchase;

        final debtTxId =
            'debt_rev_${receipt.importCode}_${now.millisecondsSinceEpoch}';
        revDebtTx = SupplierDebtTransaction(
          id: debtTxId,
          supplierId: supplier.id,
          date: now,
          type: SupplierDebtType.adjustment,
          amount: -debtToReverse,
          remainingDebt: newCurrentDebt,
          referenceCode: receipt.importCode,
          note: 'Hủy phiếu nhập ${receipt.importCode}: $reason',
          createdBy: cancelledBy,
        );

        updates['shared_suppliers/${supplier.id}/debt_transactions/$debtTxId'] =
            revDebtTx.toMap();
      }
    }

    // 4. Commit atomic update
    if (_db != null) {
      await _db.ref().update(updates);
    }

    // 5. Update repository state
    await _receiptRepo.cancelReceipt(
      storeId: storeId,
      receipt: receipt,
      reason: reason,
      cancelledBy: cancelledBy,
    );

    for (final p in rolledBackProducts) {
      await _productRepo.upsert(p);
    }

    for (final t in reversalTransactions) {
      await _inventoryRepo.record(t);
    }

    if (rolledBackSupplier != null) {
      await _supplierRepo.upsert(rolledBackSupplier, storeId: storeId);
      if (revDebtTx != null) {
        try {
          await _supplierRepo.recordDebtTransaction(revDebtTx,
              storeId: storeId);
        } catch (_) {}
      }
    }
  }
}
