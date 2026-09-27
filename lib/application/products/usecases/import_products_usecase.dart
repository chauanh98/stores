import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/import_result.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/repositories/category_repository.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../../domain/repositories/product_repository.dart';
import '../../inventory/inventory_providers.dart';
import '../categories_providers.dart';
import '../products_providers.dart';

final importProductsUseCaseProvider = Provider<ImportProductsUseCase>((ref) {
  return ImportProductsUseCase(
    productRepository: ref.watch(productRepositoryProvider),
    inventoryRepository: ref.watch(inventoryRepositoryProvider),
    categoryRepository: ref.watch(categoryRepositoryProvider),
  );
});

class ImportProductsUseCase {
  final ProductRepository productRepository;
  final InventoryRepository inventoryRepository;
  final CategoryRepository? categoryRepository;

  ImportProductsUseCase({
    required this.productRepository,
    required this.inventoryRepository,
    this.categoryRepository,
  });

  Future<ImportResult> execute({
    required List<Product> products,
    required String targetStoreId,
  }) async {
    if (products.isEmpty) {
      return const ImportResult();
    }

    int added = 0;
    int updated = 0;
    int skipped = 0;
    int errors = 0;
    final List<String> errorMessages = [];

    // 1. Fetch existing products to build quick index maps
    List<Product> existingProducts = [];
    try {
      existingProducts = await productRepository.fetchAll();
    } catch (e) {
      // If fetching fails, still attempt to process
    }

    final Map<String, Product> idMap = {};
    final Map<String, Product> codeMap = {};

    for (final p in existingProducts) {
      final idKey = p.id.trim().toLowerCase();
      if (idKey.isNotEmpty) idMap[idKey] = p;

      final codeKey = p.code.trim().toLowerCase();
      if (codeKey.isNotEmpty) codeMap[codeKey] = p;
    }

    // 2. Process each imported product
    for (final imported in products) {
      try {
        final importedId = imported.id.trim().toLowerCase();
        final importedCode = imported.code.trim().toLowerCase();

        Product? existing;
        if (importedId.isNotEmpty && idMap.containsKey(importedId)) {
          existing = idMap[importedId];
        } else if (importedCode.isNotEmpty &&
            codeMap.containsKey(importedCode)) {
          existing = codeMap[importedCode];
        } else if (importedId.isNotEmpty && codeMap.containsKey(importedId)) {
          existing = codeMap[importedId];
        } else if (importedCode.isNotEmpty && idMap.containsKey(importedCode)) {
          existing = idMap[importedCode];
        }

        if (existing != null) {
          // DUPLICATE DETECTED:
          // Update basic fields: name, price, costPrice, unit, description, category3Levels, category.
          // STRICTLY PRESERVE: branchStocks and imageUrl / images.
          final hasExistingImage =
              existing.imageUrl != null && existing.imageUrl!.trim().isNotEmpty;
          final finalImageUrl =
              hasExistingImage ? existing.imageUrl : imported.imageUrl;
          final finalImages =
              existing.images.isNotEmpty ? existing.images : imported.images;

          final mergedProduct = existing.copyWith(
            name:
                imported.name.trim().isNotEmpty ? imported.name : existing.name,
            price: imported.price,
            costPrice: imported.costPrice,
            unit: imported.unit ?? existing.unit,
            description: imported.description ?? existing.description,
            category3Levels:
                imported.category3Levels ?? existing.category3Levels,
            category: imported.category.trim().isNotEmpty
                ? imported.category
                : existing.category,
            barcode: imported.barcode ?? existing.barcode,
            brand: (imported.brand != null && imported.brand != 'Khác')
                ? imported.brand
                : existing.brand,
            model: (imported.model != null && imported.model != 'Khác')
                ? imported.model
                : existing.model,
            type: imported.type ?? existing.type,
            noteTemplate: imported.noteTemplate ?? existing.noteTemplate,
            components: imported.components ?? existing.components,
            // Strictly preserved:
            branchStocks: existing.branchStocks,
            imageUrl: finalImageUrl,
            images: finalImages,
            isCombo: existing.isCombo,
            comboComponents: existing.comboComponents,
            minStock: existing.minStock,
            maxStock: existing.maxStock,
            units: existing.units,
            allowSale: existing.allowSale,
          );

          await productRepository.upsert(mergedProduct);

          // Update lookup indices
          final updatedIdKey = mergedProduct.id.trim().toLowerCase();
          if (updatedIdKey.isNotEmpty) idMap[updatedIdKey] = mergedProduct;
          final updatedCodeKey = mergedProduct.code.trim().toLowerCase();
          if (updatedCodeKey.isNotEmpty)
            codeMap[updatedCodeKey] = mergedProduct;

          updated++;
        } else {
          // NEW PRODUCT:
          // Record initial stock into targetStoreId
          final initialStock =
              imported.branchStocks[targetStoreId] ?? imported.stock;
          final newBranchStocks = <String, int>{targetStoreId: initialStock};

          final newProduct = imported.copyWith(branchStocks: newBranchStocks);
          await productRepository.upsert(newProduct);

          // Log initial stock transaction if stock > 0
          if (initialStock > 0) {
            final now = DateTime.now();
            final tx = InventoryTransaction(
              id: 'import_${now.millisecondsSinceEpoch}_${newProduct.id}_$targetStoreId',
              productId: newProduct.id,
              type: TransactionType.import,
              quantity: initialStock,
              date: now,
              note: 'Nhập tồn đầu kỳ từ file Excel ($targetStoreId)',
              importPrice:
                  newProduct.costPrice > 0 ? newProduct.costPrice : null,
              storeId: targetStoreId,
            );
            await inventoryRepository.record(tx);
          }

          // Update lookup indices
          final newIdKey = newProduct.id.trim().toLowerCase();
          if (newIdKey.isNotEmpty) idMap[newIdKey] = newProduct;
          final newCodeKey = newProduct.code.trim().toLowerCase();
          if (newCodeKey.isNotEmpty) codeMap[newCodeKey] = newProduct;

          added++;
        }
      } catch (e) {
        errors++;
        errorMessages
            .add('Lỗi tại sản phẩm ${imported.code} (${imported.name}): $e');
      }
    }

    // 3. Auto-harvest 3-level categories if CategoryRepository is available
    if (categoryRepository != null) {
      try {
        final baseCategories = await categoryRepository!.fetchAll();
        harvestCategoriesFromProducts(
          baseCategories,
          products,
          syncRepo: categoryRepository,
        );
      } catch (e) {
        // Harvesting categories in the background should not crash import
      }
    }

    return ImportResult(
      total: products.length,
      added: added,
      updated: updated,
      skipped: skipped,
      errors: errors,
      errorMessages: errorMessages,
    );
  }
}
