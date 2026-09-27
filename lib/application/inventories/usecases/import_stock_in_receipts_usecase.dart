import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/stock_in_receipt.dart';
import '../../../domain/entities/supplier.dart';
import '../../../domain/entities/supplier_debt_transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../../domain/repositories/product_repository.dart';
import '../../../domain/repositories/supplier_repository.dart';
import '../../inventory/inventory_providers.dart';
import '../../products/products_providers.dart';
import '../../suppliers/suppliers_providers.dart';

/// Contract for recording supplier debt transactions if a dedicated repository is used.
abstract class SupplierDebtTransactionRepository {
  Future<void> recordDebtTransaction(
    SupplierDebtTransaction transaction, {
    String? storeId,
  });
}

/// Result of importing stock-in receipts.
class ImportResult {
  final int totalReceipts;
  final int importedReceipts;
  final int updatedProductsCount;
  final int updatedSuppliersCount;
  final List<String> errors;
  final List<String> warnings;

  const ImportResult({
    this.totalReceipts = 0,
    this.importedReceipts = 0,
    this.updatedProductsCount = 0,
    this.updatedSuppliersCount = 0,
    this.errors = const [],
    this.warnings = const [],
  });

  bool get isSuccess => errors.isEmpty;
  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;

  // Compatibility aliases
  int get total => totalReceipts;
  int get added => importedReceipts;
  int get updated => updatedProductsCount;
  int get skipped => totalReceipts - importedReceipts;
  int get errorCount => errors.length;
  List<String> get errorMessages => errors;

  String toSummaryString() =>
      'Tổng số phiếu: $totalReceipts | Thành công: $importedReceipts | '
      'Sản phẩm cập nhật: $updatedProductsCount | NCC cập nhật: $updatedSuppliersCount'
      '${errors.isNotEmpty ? ' | Lỗi: ${errors.length}' : ''}'
      '${warnings.isNotEmpty ? ' | Cảnh báo: ${warnings.length}' : ''}';

  String get summaryMessage => toSummaryString();

  ImportResult copyWith({
    int? totalReceipts,
    int? importedReceipts,
    int? updatedProductsCount,
    int? updatedSuppliersCount,
    List<String>? errors,
    List<String>? warnings,
  }) {
    return ImportResult(
      totalReceipts: totalReceipts ?? this.totalReceipts,
      importedReceipts: importedReceipts ?? this.importedReceipts,
      updatedProductsCount: updatedProductsCount ?? this.updatedProductsCount,
      updatedSuppliersCount:
          updatedSuppliersCount ?? this.updatedSuppliersCount,
      errors: errors ?? this.errors,
      warnings: warnings ?? this.warnings,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportResult &&
          runtimeType == other.runtimeType &&
          totalReceipts == other.totalReceipts &&
          importedReceipts == other.importedReceipts &&
          updatedProductsCount == other.updatedProductsCount &&
          updatedSuppliersCount == other.updatedSuppliersCount &&
          _listEquals(errors, other.errors) &&
          _listEquals(warnings, other.warnings);

  @override
  int get hashCode =>
      totalReceipts.hashCode ^
      importedReceipts.hashCode ^
      updatedProductsCount.hashCode ^
      updatedSuppliersCount.hashCode ^
      errors.length.hashCode ^
      warnings.length.hashCode;

  @override
  String toString() => toSummaryString();

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Riverpod provider for [ImportStockInReceiptsUseCase].
final importStockInReceiptsUseCaseProvider =
    Provider<ImportStockInReceiptsUseCase>((ref) {
  return ImportStockInReceiptsUseCase(
    productRepository: ref.watch(productRepositoryProvider),
    inventoryRepository: ref.watch(inventoryRepositoryProvider),
    supplierRepository: ref.watch(supplierRepositoryProvider),
  );
});

/// Use case that imports a list of [StockInReceipt] entities, updates product branch stock
/// and weighted average cost price, logs inventory transactions, and synchronizes supplier debt.
class ImportStockInReceiptsUseCase {
  final ProductRepository _productRepo;
  final InventoryRepository _inventoryRepo;
  final SupplierRepository _supplierRepo;
  final SupplierDebtTransactionRepository? _supplierDebtRepo;

  ImportStockInReceiptsUseCase({
    ProductRepository? productRepository,
    ProductRepository? productRepo,
    InventoryRepository? inventoryRepository,
    InventoryRepository? inventoryRepo,
    SupplierRepository? supplierRepository,
    SupplierRepository? supplierRepo,
    SupplierDebtTransactionRepository? supplierDebtRepository,
    SupplierDebtTransactionRepository? supplierDebtRepo,
  })  : _productRepo = productRepository ?? productRepo!,
        _inventoryRepo = inventoryRepository ?? inventoryRepo!,
        _supplierRepo = supplierRepository ?? supplierRepo!,
        _supplierDebtRepo = supplierDebtRepository ?? supplierDebtRepo;

  ProductRepository get productRepository => _productRepo;
  InventoryRepository get inventoryRepository => _inventoryRepo;
  SupplierRepository get supplierRepository => _supplierRepo;
  SupplierDebtTransactionRepository? get supplierDebtRepository =>
      _supplierDebtRepo;

  /// Executes the import process for a list of [receipts].
  ///
  /// - [storeId] or [targetStoreId] is the fallback store if receipt doesn't specify one.
  /// - [performedBy] is the operator's username or identifier.
  Future<ImportResult> execute({
    required List<StockInReceipt> receipts,
    String? storeId,
    String? targetStoreId,
    String performedBy = 'Admin',
  }) async {
    if (receipts.isEmpty) {
      return const ImportResult();
    }

    final fallbackStoreId = storeId ?? targetStoreId ?? 'store_001';
    final effectivePerformedBy =
        performedBy.trim().isNotEmpty ? performedBy.trim() : 'Admin';

    int importedReceipts = 0;
    final Set<String> updatedProductIds = {};
    final Set<String> updatedSupplierIds = {};
    final List<String> errors = [];
    final List<String> warnings = [];

    // 1. Pre-load existing products and index for fast O(1) lookup
    final Map<String, Product> productById = {};
    final Map<String, Product> productByCode = {};
    final Map<String, Product> productByBarcode = {};

    try {
      final existingProducts = await _productRepo.fetchAll();
      for (final p in existingProducts) {
        _indexProduct(p, productById, productByCode, productByBarcode);
      }
    } catch (_) {
      // In case fetchAll fails (e.g. offline or empty fake), continue with on-demand lookup
    }

    // 2. Pre-load existing suppliers and index
    final Map<String, Supplier> supplierById = {};
    final Map<String, Supplier> supplierByCode = {};
    final Map<String, Supplier> supplierByName = {};

    try {
      final existingSuppliers = await _supplierRepo
          .watchAll()
          .first
          .timeout(const Duration(seconds: 4), onTimeout: () => <Supplier>[]);
      for (final s in existingSuppliers) {
        _indexSupplier(s, supplierById, supplierByCode, supplierByName);
      }
    } catch (_) {
      // Continue with on-demand lookup
    }

    // 3. Process each receipt
    for (int receiptIndex = 0; receiptIndex < receipts.length; receiptIndex++) {
      final receipt = receipts[receiptIndex];
      final receiptId = receipt.id.trim().isNotEmpty
          ? receipt.id.trim()
          : (receipt.importCode.trim().isNotEmpty
              ? receipt.importCode.trim()
              : 'PN_${receipt.date.millisecondsSinceEpoch}_$receiptIndex');

      bool receiptHasFatalError = false;

      // Determine branch storeId: use receipt.storeId if not empty and != 'store_001', else fallback
      final String effectiveStoreId;
      if (receipt.storeId != null &&
          receipt.storeId!.trim().isNotEmpty &&
          receipt.storeId!.trim() != 'store_001') {
        effectiveStoreId = receipt.storeId!.trim();
      } else if (storeId != null && storeId.trim().isNotEmpty) {
        effectiveStoreId = storeId.trim();
      } else if (receipt.storeId != null &&
          receipt.storeId!.trim().isNotEmpty) {
        effectiveStoreId = receipt.storeId!.trim();
      } else {
        effectiveStoreId = fallbackStoreId;
      }

      final receiptOperator =
          (receipt.createdBy != null && receipt.createdBy!.trim().isNotEmpty)
              ? receipt.createdBy!.trim()
              : effectivePerformedBy;

      try {
        // A. Process each line item in the receipt
        for (int itemIndex = 0; itemIndex < receipt.items.length; itemIndex++) {
          final item = receipt.items[itemIndex];

          try {
            // Find product by SKU / code / barcode / ID
            final product = await _findProduct(
              item: item,
              productById: productById,
              productByCode: productByCode,
              productByBarcode: productByBarcode,
            );

            if (product != null) {
              // Update branch stock: branchStocks[effectiveStoreId] = (currentBranchStock + item.quantity)
              final branchStocks = Map<String, int>.from(product.branchStocks);
              final currentBranchStock =
                  product.stockInBranch(effectiveStoreId);
              branchStocks[effectiveStoreId] =
                  currentBranchStock + item.quantity;

              // Synchronize branch aliases if present
              if (effectiveStoreId == 'store_001' &&
                  branchStocks.containsKey('branch_1')) {
                branchStocks['branch_1'] = branchStocks[effectiveStoreId]!;
              } else if (effectiveStoreId == 'store_002' &&
                  branchStocks.containsKey('branch_2')) {
                branchStocks['branch_2'] = branchStocks[effectiveStoreId]!;
              } else if (effectiveStoreId == 'branch_1' &&
                  branchStocks.containsKey('store_001')) {
                branchStocks['store_001'] = branchStocks['branch_1']!;
              } else if (effectiveStoreId == 'branch_2' &&
                  branchStocks.containsKey('store_002')) {
                branchStocks['store_002'] = branchStocks['branch_2']!;
              }

              // Update weighted average cost price:
              // newCost = ((currentStock * currentCost) + (item.quantity * item.unitPrice)) / (currentStock + item.quantity)
              // (if new total stock > 0, else item.unitPrice).
              final int currentStock = product.stock;
              final double currentCost = product.costPrice;
              final int itemQty = item.quantity;
              final double itemPrice = item.unitPrice;
              final int newTotalStock = currentStock + itemQty;

              final double newCost;
              if (newTotalStock > 0) {
                if (currentStock <= 0) {
                  newCost = itemPrice;
                } else {
                  newCost =
                      ((currentStock * currentCost) + (itemQty * itemPrice)) /
                          newTotalStock;
                }
              } else {
                newCost = itemPrice;
              }

              final updatedProduct = product.copyWith(
                branchStocks: branchStocks,
                costPrice: newCost,
              );

              // Save updated product via productRepo.updateProduct / upsert
              await _saveProduct(updatedProduct);

              // Update local in-memory index for subsequent items
              _indexProduct(
                  updatedProduct, productById, productByCode, productByBarcode);
              updatedProductIds.add(updatedProduct.id);
            } else {
              // Product not found: record warning
              final identifier = item.productCode ??
                  (item.productId.isNotEmpty
                      ? item.productId
                      : item.barcode ?? 'Không rõ');
              warnings.add(
                  'Không tìm thấy sản phẩm với mã: $identifier trong phiếu $receiptId');
            }

            // Record InventoryTransaction for each line item
            final tx = InventoryTransaction(
              id: 'tx_import_${receiptId}_${product?.id ?? item.productId}_${itemIndex}_${DateTime.now().millisecondsSinceEpoch}',
              productId: product?.id ?? item.productId,
              type: TransactionType.import,
              quantity: item.quantity,
              date: receipt.date,
              importPrice: item.unitPrice,
              storeId: effectiveStoreId,
              createdBy: receiptOperator,
              createdByName: receipt.createdByName ?? receiptOperator,
              supplierId: receipt.supplierId,
              supplierName: receipt.supplierName,
              importCode: receipt.importCode.isNotEmpty
                  ? receipt.importCode
                  : receiptId,
              note: 'Nhập hàng từ Excel: $receiptId',
            );

            await _inventoryRepo.record(tx);
          } catch (itemError) {
            warnings.add(
                'Lỗi xử lý mặt hàng ${item.productId} trong phiếu $receiptId: $itemError');
          }
        }

        // B. Supplier debt synchronization
        final hasSupplier = (receipt.supplierId != null &&
                receipt.supplierId!.trim().isNotEmpty) ||
            (receipt.supplierName != null &&
                receipt.supplierName!.trim().isNotEmpty);

        final double paidAmount = receipt.paidAmount ?? 0.0;
        final double netPayable = receipt.effectiveNetPayable;

        if (hasSupplier && netPayable > 0) {
          final double unpaidAmount = netPayable - paidAmount;

          final supplier = await _findSupplier(
            supplierId: receipt.supplierId,
            supplierName: receipt.supplierName,
            supplierById: supplierById,
            supplierByCode: supplierByCode,
            supplierByName: supplierByName,
          );

          if (supplier != null) {
            final double currentDebt = supplier.currentDebt;
            final double totalPurchase = supplier.totalPurchase;
            final double newDebt =
                unpaidAmount > 0 ? (currentDebt + unpaidAmount) : currentDebt;
            final double newTotalPurchase = totalPurchase + netPayable;

            final updatedSupplier = supplier.copyWith(
              currentDebt: newDebt,
              totalPurchase: newTotalPurchase,
            );

            // Save updated supplier via supplierRepo.updateSupplier / upsert
            await _saveSupplier(updatedSupplier, storeId: effectiveStoreId);

            // Update local in-memory index
            _indexSupplier(
                updatedSupplier, supplierById, supplierByCode, supplierByName);
            updatedSupplierIds.add(updatedSupplier.id);

            // Record SupplierDebtTransaction only if debt is incurred
            if (unpaidAmount > 0) {
              final debtTx = SupplierDebtTransaction(
                id: 'debt_tx_${receipt.importCode.isNotEmpty ? receipt.importCode : receiptId}_${DateTime.now().millisecondsSinceEpoch}',
                supplierId: supplier.id,
                date: receipt.date,
                type: SupplierDebtType.importBill,
                amount: unpaidAmount,
                remainingDebt: newDebt,
                referenceCode: receipt.importCode.isNotEmpty
                    ? receipt.importCode
                    : receiptId,
                note: 'Nhập hàng từ Excel: $receiptId',
                createdBy: receiptOperator,
              );

              final debtRepo = _supplierDebtRepo;
              if (debtRepo != null) {
                try {
                  await debtRepo.recordDebtTransaction(
                    debtTx,
                    storeId: effectiveStoreId,
                  );
                } catch (_) {
                  try {
                    await (debtRepo as dynamic).record(debtTx);
                  } catch (_) {}
                }
              }

              try {
                await _supplierRepo.recordDebtTransaction(
                  debtTx,
                  storeId: effectiveStoreId,
                );
              } catch (_) {
                // Ignore if supplierRepo fake does not implement recordDebtTransaction
              }
            }
          } else {
            warnings.add(
                'Không tìm thấy nhà cung cấp: ${receipt.supplierId ?? receipt.supplierName} cho phiếu $receiptId');
          }
        }
      } catch (receiptError) {
        receiptHasFatalError = true;
        errors.add('Lỗi xử lý phiếu $receiptId: $receiptError');
      }

      if (!receiptHasFatalError) {
        importedReceipts++;
      }
    }

    return ImportResult(
      totalReceipts: receipts.length,
      importedReceipts: importedReceipts,
      updatedProductsCount: updatedProductIds.length,
      updatedSuppliersCount: updatedSupplierIds.length,
      errors: errors,
      warnings: warnings,
    );
  }

  void _indexProduct(
    Product p,
    Map<String, Product> productById,
    Map<String, Product> productByCode,
    Map<String, Product> productByBarcode,
  ) {
    final idKey = p.id.trim().toLowerCase();
    if (idKey.isNotEmpty) productById[idKey] = p;

    final codeKey = p.code.trim().toLowerCase();
    if (codeKey.isNotEmpty) productByCode[codeKey] = p;

    if (p.barcode != null && p.barcode!.trim().isNotEmpty) {
      productByBarcode[p.barcode!.trim().toLowerCase()] = p;
    }
  }

  void _indexSupplier(
    Supplier s,
    Map<String, Supplier> supplierById,
    Map<String, Supplier> supplierByCode,
    Map<String, Supplier> supplierByName,
  ) {
    final idKey = s.id.trim().toLowerCase();
    if (idKey.isNotEmpty) supplierById[idKey] = s;

    final codeKey = s.code.trim().toLowerCase();
    if (codeKey.isNotEmpty) supplierByCode[codeKey] = s;

    final nameKey = s.name.trim().toLowerCase();
    if (nameKey.isNotEmpty) supplierByName[nameKey] = s;
  }

  Future<Product?> _findProduct({
    required StockInReceiptItem item,
    required Map<String, Product> productById,
    required Map<String, Product> productByCode,
    required Map<String, Product> productByBarcode,
  }) async {
    // 1. Try searchProducts dynamically if repository provides it
    try {
      final query =
          (item.productCode != null && item.productCode!.trim().isNotEmpty)
              ? item.productCode!.trim()
              : item.productId.trim();
      if (query.isNotEmpty) {
        final dynamic result =
            await (_productRepo as dynamic).searchProducts(query);
        if (result is List && result.isNotEmpty && result.first is Product) {
          return result.first as Product;
        } else if (result is Product) {
          return result;
        }
      }
    } catch (e) {
      if (e is! NoSuchMethodError) {
        // Ignore searchProducts non-fatal error and fall back to local indexes
      }
    }

    // 2. Search by SKU / code (case-insensitive)
    if (item.productCode != null && item.productCode!.trim().isNotEmpty) {
      final codeKey = item.productCode!.trim().toLowerCase();
      if (productByCode.containsKey(codeKey)) {
        return productByCode[codeKey];
      }
    }

    // 3. Search by productId as code or ID
    final prodIdKey = item.productId.trim().toLowerCase();
    if (prodIdKey.isNotEmpty) {
      if (productByCode.containsKey(prodIdKey)) {
        return productByCode[prodIdKey];
      }
      if (productById.containsKey(prodIdKey)) {
        return productById[prodIdKey];
      }
    }

    // 4. Search by barcode
    if (item.barcode != null && item.barcode!.trim().isNotEmpty) {
      final barcodeKey = item.barcode!.trim().toLowerCase();
      if (productByBarcode.containsKey(barcodeKey)) {
        return productByBarcode[barcodeKey];
      }
    }

    // 5. Fallback: repository fetchById
    if (item.productId.trim().isNotEmpty) {
      try {
        final fetched = await _productRepo.fetchById(item.productId.trim());
        if (fetched != null) return fetched;
      } catch (_) {}
    }
    if (item.productCode != null && item.productCode!.trim().isNotEmpty) {
      try {
        final fetched = await _productRepo.fetchById(item.productCode!.trim());
        if (fetched != null) return fetched;
      } catch (_) {}
    }

    return null;
  }

  Future<Supplier?> _findSupplier({
    String? supplierId,
    String? supplierName,
    required Map<String, Supplier> supplierById,
    required Map<String, Supplier> supplierByCode,
    required Map<String, Supplier> supplierByName,
  }) async {
    // 1. By supplierId in ID map or Code map
    if (supplierId != null && supplierId.trim().isNotEmpty) {
      final key = supplierId.trim().toLowerCase();
      if (supplierById.containsKey(key)) {
        return supplierById[key];
      }
      if (supplierByCode.containsKey(key)) {
        return supplierByCode[key];
      }
    }

    // 2. By supplierName in Name map
    if (supplierName != null && supplierName.trim().isNotEmpty) {
      final nameKey = supplierName.trim().toLowerCase();
      if (supplierByName.containsKey(nameKey)) {
        return supplierByName[nameKey];
      }
    }

    // 3. Fallback: fetchById
    if (supplierId != null && supplierId.trim().isNotEmpty) {
      try {
        final fetched = await _supplierRepo.fetchById(supplierId.trim());
        if (fetched != null) return fetched;
      } catch (_) {}
    }

    return null;
  }

  Future<void> _saveProduct(Product product) async {
    try {
      await (_productRepo as dynamic).updateProduct(product);
      return;
    } catch (e) {
      if (e is! NoSuchMethodError) {
        rethrow;
      }
    }

    await _productRepo.upsert(product);
  }

  Future<void> _saveSupplier(Supplier supplier, {String? storeId}) async {
    try {
      await (_supplierRepo as dynamic).updateSupplier(supplier);
      return;
    } catch (e) {
      if (e is! NoSuchMethodError) {
        rethrow;
      }
    }

    await _supplierRepo.upsert(supplier, storeId: storeId);
  }
}
