import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../../../data/models/inventory_transaction_model.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/stock_in_receipt.dart';
import '../../../domain/entities/supplier.dart';
import '../../../domain/entities/supplier_debt_transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/entities/user_account.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../../domain/repositories/product_repository.dart';
import '../../../domain/repositories/stock_in_receipt_repository.dart';
import '../../../domain/repositories/supplier_repository.dart';
import '../../../core/utils/store_resolver_helper.dart';
import '../../notifications/notification_dispatcher.dart';
import 'stock_in_store_sync.dart';

/// Use case that completes a stock-in receipt using an atomic multi-path update.
///
/// Mutations committed atomically:
/// 1. Updates `branchStocks` with branch aliases (`store_001` / `branch_1`).
/// 2. Updates product weighted average `costPrice`.
/// 3. Records `inventory_transactions` for each line item.
/// 4. Updates supplier `currentDebt` and `totalPurchase`, recording `SupplierDebtTransaction`.
/// 5. Writes finalized `StockInReceipt` with `status: 'completed'` to RTDB.
class CompleteStockInReceiptUseCase {
  final FirebaseDatabase? _db;
  final ProductRepository _productRepo;
  final InventoryRepository _inventoryRepo;
  final SupplierRepository _supplierRepo;
  final StockInReceiptRepository _receiptRepo;
  final NotificationDispatcher? _notificationDispatcher;

  CompleteStockInReceiptUseCase({
    FirebaseDatabase? db,
    required ProductRepository productRepository,
    required InventoryRepository inventoryRepository,
    required SupplierRepository supplierRepository,
    required StockInReceiptRepository receiptRepository,
    NotificationDispatcher? notificationDispatcher,
  })  : _db = db,
        _productRepo = productRepository,
        _inventoryRepo = inventoryRepository,
        _supplierRepo = supplierRepository,
        _receiptRepo = receiptRepository,
        _notificationDispatcher = notificationDispatcher;

  /// Executes atomic receipt completion.
  /// Returns the completed [StockInReceipt].
  Future<StockInReceipt> execute(
    StockInReceipt receipt, {
    UserAccount? user,
  }) async {
    final now = DateTime.now();

    // Mã chuẩn (store_001/store_002/...): alias branch_1/branch_2 sẽ ghi phiếu,
    // giao dịch kho và thông báo vào nút chi nhánh không tồn tại.
    final effectiveStoreId = receipt.storeId?.trim().isNotEmpty == true
        ? StoreResolverHelper.normalizeStoreId(receipt.storeId!.trim())
        : 'store_001';

    final effectiveId = receipt.id.trim().isNotEmpty
        ? receipt.id.trim()
        : 'PN_${now.millisecondsSinceEpoch}';

    final effectiveImportCode = receipt.importCode.trim().isNotEmpty
        ? receipt.importCode.trim()
        : 'PN_${now.millisecondsSinceEpoch}';

    final completedReceipt = receipt.copyWith(
      id: effectiveId,
      importCode: effectiveImportCode,
      storeId: effectiveStoreId,
      status: 'completed',
      // Tiền trả không vượt phần phải trả (trả dư không được lưu vào phiếu).
      paidAmount: receipt.paidAmount == null
          ? null
          : receipt.paidAmount!
              .clamp(0.0, receipt.effectiveNetPayable.clamp(0.0, double.infinity)),
      createdAt: receipt.createdAt ?? now,
      updatedAt: now,
    );

    final Map<String, dynamic> updates = {};

    // 1. Process Product Stocks & Cost Price with in-flight accumulator for duplicate products
    final List<Product> updatedProducts = [];
    final Map<String, Product> productCache = {};
    final Map<String, int> productQuantityMap = {};
    final Map<String, double> productCostMap = {};

    for (final item in completedReceipt.items) {
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
        productCostMap[product.id] = (productCostMap[product.id] ?? 0.0) +
            (item.quantity * item.unitPrice);
      }
    }

    for (final entry in productQuantityMap.entries) {
      final productId = entry.key;
      final totalQuantity = entry.value;
      final totalCost = productCostMap[productId] ?? 0.0;
      final product = productCache[productId]!;

      final currentBranchStock = product.stockInBranch(effectiveStoreId);
      final newBranchStock = currentBranchStock + totalQuantity;
      final updatedBranchStocks = Map<String, int>.from(product.branchStocks);
      updatedBranchStocks[effectiveStoreId] = newBranchStock;

      // Synchronize canonical branch aliases
      if (effectiveStoreId == 'store_001' || effectiveStoreId == 'branch_1') {
        updatedBranchStocks['store_001'] = newBranchStock;
        updatedBranchStocks['branch_1'] = newBranchStock;
      } else if (effectiveStoreId == 'store_002' ||
          effectiveStoreId == 'branch_2') {
        updatedBranchStocks['store_002'] = newBranchStock;
        updatedBranchStocks['branch_2'] = newBranchStock;
      }

      // Weighted Average Cost recalculation
      final int currentTotalStock = product.stock;
      final int newTotalStock = currentTotalStock + totalQuantity;
      final double newCost;
      if (newTotalStock > 0) {
        if (currentTotalStock <= 0) {
          newCost = totalQuantity > 0
              ? (totalCost / totalQuantity)
              : product.costPrice;
        } else {
          newCost = ((currentTotalStock * product.costPrice) + totalCost) /
              newTotalStock;
        }
      } else {
        newCost =
            totalQuantity > 0 ? (totalCost / totalQuantity) : product.costPrice;
      }

      final updatedProduct = product.copyWith(
        branchStocks: updatedBranchStocks,
        costPrice: newCost,
      );
      updatedProducts.add(updatedProduct);

      final targets =
          await storesToSyncProduct(_db, effectiveStoreId, product.id);
      writeProductStockUpdates(
        updates,
        targets: targets,
        productId: product.id,
        storeId: effectiveStoreId,
        newStock: newBranchStock,
        fullBranchStocks: updatedBranchStocks,
        costPrice: newCost,
      );
    }

    // 2. Inventory Transactions
    final List<InventoryTransaction> transactions = [];
    for (int i = 0; i < completedReceipt.items.length; i++) {
      final item = completedReceipt.items[i];
      final txId =
          'tx_import_${completedReceipt.importCode}_${item.productId}_${i}_${now.millisecondsSinceEpoch}';

      final tx = InventoryTransaction(
        id: txId,
        productId: item.productId,
        type: TransactionType.import,
        quantity: item.quantity,
        date: completedReceipt.date,
        importPrice: item.unitPrice,
        storeId: effectiveStoreId,
        createdBy: completedReceipt.createdBy,
        createdByName:
            completedReceipt.createdByName ?? completedReceipt.createdBy,
        supplierId: completedReceipt.supplierId,
        supplierName: completedReceipt.supplierName,
        importCode: completedReceipt.importCode,
        note: item.note.isNotEmpty
            ? item.note
            : (completedReceipt.note.isNotEmpty
                ? completedReceipt.note
                : 'Nhập hàng ${completedReceipt.importCode}'),
      );
      transactions.add(tx);

      updates['stores/$effectiveStoreId/inventory_transactions/$txId'] =
          InventoryTransactionModel.fromEntity(tx).toMap();
    }

    // 3. Supplier Debt & Total Purchase
    Supplier? updatedSupplier;
    SupplierDebtTransaction? debtTx;
    if (completedReceipt.supplierId != null &&
        completedReceipt.supplierId!.trim().isNotEmpty) {
      Supplier? supplier;
      try {
        supplier =
            await _supplierRepo.fetchById(completedReceipt.supplierId!.trim());
      } catch (_) {}

      if (supplier != null) {
        final double netPayable = completedReceipt.effectiveNetPayable;
        final double remainingDebt = completedReceipt.remainingDebt;
        final double newCurrentDebt =
            (supplier.currentDebt + remainingDebt).clamp(0.0, double.infinity);
        final double newTotalPurchase = supplier.totalPurchase + netPayable;

        updatedSupplier = supplier.copyWith(
          currentDebt: newCurrentDebt,
          totalPurchase: newTotalPurchase,
        );

        updates['shared_suppliers/${supplier.id}/currentDebt'] = newCurrentDebt;
        updates['shared_suppliers/${supplier.id}/totalPurchase'] =
            newTotalPurchase;

        if (remainingDebt > 0) {
          final debtTxId =
              'debt_tx_${completedReceipt.importCode}_${now.millisecondsSinceEpoch}';
          debtTx = SupplierDebtTransaction(
            id: debtTxId,
            supplierId: supplier.id,
            date: completedReceipt.date,
            type: SupplierDebtType.importBill,
            amount: remainingDebt,
            remainingDebt: newCurrentDebt,
            referenceCode: completedReceipt.importCode,
            note: 'Nhập hàng ${completedReceipt.importCode}',
            createdBy: completedReceipt.createdBy,
          );

          updates['shared_suppliers/${supplier.id}/debt_transactions/$debtTxId'] =
              debtTx.toMap();
        }
      }
    }

    // 4. Stored Receipt Document
    updates['stores/$effectiveStoreId/stock_in_receipts/${completedReceipt.id}'] =
        completedReceipt.toMap();

    // 5. Execute Atomic Multi-Path Update if Firebase Database is present
    if (_db != null) {
      // Chặn hoàn thành trùng (bấm đúp / 2 thiết bị) cộng kho 2 lần.
      final claim = await ReceiptStatusClaim.acquire(
        _db,
        'stores/$effectiveStoreId/stock_in_receipts/${completedReceipt.id}/status',
        to: 'completed',
        blocked: const {'completed', 'cancelled', 'Đã hủy'},
      );
      if (claim == null) {
        throw StateError('Receipt ${completedReceipt.id} is already processed');
      }
      try {
        await _db.ref().update(updates);
      } catch (_) {
        await claim.release();
        rethrow;
      }
    }

    // Synchronize local repository state for cached/in-memory consistency
    await _receiptRepo.saveReceipt(completedReceipt);

    for (final p in updatedProducts) {
      await _productRepo.upsert(p);
    }

    for (final t in transactions) {
      await _inventoryRepo.record(t);
    }

    if (updatedSupplier != null) {
      await _supplierRepo.upsert(updatedSupplier, storeId: effectiveStoreId);
      if (debtTx != null) {
        try {
          await _supplierRepo.recordDebtTransaction(debtTx,
              storeId: effectiveStoreId);
        } catch (_) {}
      }
    }

    // Dispatch notification event
    if (_notificationDispatcher != null) {
      try {
        final effectiveUser = user ??
            (completedReceipt.createdBy != null
                ? UserAccount(
                    username: completedReceipt.createdBy!,
                    displayName: completedReceipt.createdByName,
                    role: 'nhanvien',
                    storeId: effectiveStoreId,
                  )
                : null);

        await _notificationDispatcher.notifyStockInCompleted(
          storeId: effectiveStoreId,
          receipt: completedReceipt,
          user: effectiveUser,
        );
      } catch (_) {
        // Safe against dispatch errors - business operations never fail
      }
    }

    return completedReceipt;
  }
}
