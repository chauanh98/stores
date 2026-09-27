import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/store_resolver_helper.dart';
import '../../data/datasources/firebase/product_remote_data_source.dart';
import '../../data/repositories/product_repository_impl.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../../core/services/filter_storage_service.dart';
import '../auth/auth_providers.dart';
import '../reports/overview_providers.dart';
import 'categories_providers.dart';
import 'usecases/cascade_category_update_usecase.dart';

final productRemoteDataSourceProvider =
    Provider<ProductRemoteDataSource>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  final db = FirebaseDatabase.instance;
  // Trigger background self-healing for split branchStocks across stores
  ProductRemoteDataSource.autoHealSplitBranchStocks(db).catchError((_) {});
  return ProductRemoteDataSource(db, storeId);
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  final ds = ref.watch(productRemoteDataSourceProvider);
  return ProductRepositoryImpl(ds);
});

class _FallbackProductRepository implements ProductRepository {
  @override
  Stream<List<Product>> watchAll() => const Stream.empty();
  @override
  Future<List<Product>> fetchAll() async => [];
  @override
  Future<Product?> fetchById(String id) async => null;
  @override
  Future<void> upsert(Product product) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> updateStock(String id, int newStock) async {}
}

final cascadeCategoryUpdateUseCaseProvider =
    Provider<CascadeCategoryUpdateUseCase>((ref) {
  final categoryRepo = ref.watch(categoryRepositoryProvider);
  ProductRepository productRepo;
  try {
    productRepo = ref.watch(productRepositoryProvider);
  } catch (_) {
    productRepo = _FallbackProductRepository();
  }
  final storeId = ref.watch(currentStoreIdProvider);
  FirebaseDatabase? db;
  try {
    db = FirebaseDatabase.instance;
  } catch (_) {}
  return CascadeCategoryUpdateUseCase(
    categoryRepository: categoryRepo,
    productRepository: productRepo,
    firebaseDatabase: db,
    currentStoreId: storeId,
  );
});

final productListProvider = StreamProvider.autoDispose<List<Product>>((ref) {
  return ref.watch(productRepositoryProvider).watchAll();
});

// Provider quản lý danh sách sản phẩm gộp từ nhiều cửa hàng cho Admin
// Optimized: thêm autoDispose để tự hủy listener khi không cần
final allStoresProductsProvider =
    StreamProvider.autoDispose<List<Product>>((ref) {
  final storeFilter = ref.watch(selectedStoreFilterProvider);
  final currentStoreId = ref.watch(currentStoreIdProvider);
  final selectedBranches = ref.watch(selectedBranchesProvider);
  final user = ref.watch(authProvider);
  final availableStores = ref.watch(availableStoresProvider).valueOrNull ?? {};

  final targetStoreIds = StoreResolverHelper.resolveTargetStoreIds(
    selectedBranches,
    currentStoreId: currentStoreId,
    user: user,
    storeFilter: storeFilter,
    availableStores: availableStores,
  );

  final controller = StreamController<List<Product>>();
  final List<StreamSubscription> subscriptions = [];
  final Map<String, List<Product>> storeProductsMap = {};

  for (final storeId in targetStoreIds) {
    final productDs =
        ProductRemoteDataSource(FirebaseDatabase.instance, storeId);
    final productRepo = ProductRepositoryImpl(productDs);
    final sub = productRepo.watchAll().listen(
      (products) {
        storeProductsMap[storeId] = products;
        final combined = storeProductsMap.values.expand((e) => e).toList();
        final Map<String, Product> deduplicated = {};
        for (final p in combined) {
          if (!deduplicated.containsKey(p.id)) {
            deduplicated[p.id] = p;
          } else {
            final existing = deduplicated[p.id]!;
            final mergedStocks = Map<String, int>.from(existing.branchStocks);
            for (final entry in p.branchStocks.entries) {
              final cur = mergedStocks[entry.key] ?? 0;
              if (entry.value > cur) {
                mergedStocks[entry.key] = entry.value;
              }
            }
            deduplicated[p.id] = existing.copyWith(
              branchStocks: mergedStocks,
              costPrice: p.costPrice > 0 ? p.costPrice : existing.costPrice,
            );
          }
        }
        if (!controller.isClosed) {
          controller.add(deduplicated.values.toList());
        }
      },
      onError: (err) {
        if (!controller.isClosed) {
          controller.addError(err);
        }
      },
    );
    subscriptions.add(sub);
  }

  ref.onDispose(() {
    for (final sub in subscriptions) {
      sub.cancel();
    }
    controller.close();
  });

  return controller.stream;
});

// Provider quản lý tìm kiếm và bộ lọc sản phẩm
final productSearchQueryProvider =
    StateProvider.autoDispose<String>((ref) => '');

final productSelectedCategoriesProvider = StateProvider<Set<String>>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return const <String>{};

  final storage = ref.watch(filterStorageServiceProvider);
  final saved = storage.loadFilterSync('products', user.username);
  if (saved != null && saved['selectedCategories'] is List) {
    final list = (saved['selectedCategories'] as List)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty && e != 'null' && e != 'All')
        .toSet();
    if (list.isNotEmpty) return list;
  }
  if (saved != null && saved['category'] != null) {
    final cat = saved['category'].toString().trim();
    if (cat.isNotEmpty && cat != 'null' && cat != 'All') {
      return {cat};
    }
  }
  return const <String>{};
});

final productCategoryFilterProvider = StateProvider<String>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return 'All';

  final storage = ref.watch(filterStorageServiceProvider);
  final saved = storage.loadFilterSync('products', user.username);
  if (saved != null && saved['category'] != null) {
    final cat = saved['category'].toString().trim();
    if (cat.isNotEmpty && cat != 'null') {
      return cat;
    }
  }
  return 'All';
});

enum ProductTypeFilter {
  standard,
  combo,
  service,
}

final productTypeFilterProvider = StateProvider<Set<ProductTypeFilter>>((ref) {
  final user = ref.watch(authProvider);
  const defaultTypes = {
    ProductTypeFilter.standard,
    ProductTypeFilter.combo,
    ProductTypeFilter.service,
  };
  if (user == null) return defaultTypes;

  final storage = ref.watch(filterStorageServiceProvider);
  final saved = storage.loadFilterSync('products', user.username);
  if (saved != null && saved['productTypes'] is List) {
    final list = (saved['productTypes'] as List)
        .map((e) => e.toString())
        .map((name) =>
            ProductTypeFilter.values.cast<ProductTypeFilter?>().firstWhere(
                  (v) => v?.name == name,
                  orElse: () => null,
                ))
        .whereType<ProductTypeFilter>()
        .toSet();
    if (list.isNotEmpty) return list;
  }
  return defaultTypes;
});

final productBrandFilterProvider = StateProvider<String?>((ref) => null);

enum StockStatus {
  all,
  inStock,
  outOfStock,
  belowMinStock,
}

final productStockStatusFilterProvider = StateProvider<StockStatus>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return StockStatus.all;

  final storage = ref.watch(filterStorageServiceProvider);
  final saved = storage.loadFilterSync('products', user.username);
  if (saved != null && saved['stockStatus'] != null) {
    return StockStatus.values.firstWhere(
      (e) => e.name == saved['stockStatus']?.toString(),
      orElse: () => StockStatus.all,
    );
  }
  return StockStatus.all;
});

enum ProductSortOption {
  stockDesc,
  stockAsc,
  nameAsc,
  nameDesc,
  priceAsc,
  priceDesc,
}

final productSortOptionProvider =
    StateProvider<ProductSortOption>((ref) => ProductSortOption.stockDesc);

final showCostPriceProvider = StateProvider.autoDispose<bool>((ref) => false);

class ProcessedProductsData {
  final List<Product> filteredProducts;
  final List<String> categories;
  final List<String> brands;
  final int totalStock;
  final double totalCostValue;
  final int totalProducts;

  ProcessedProductsData({
    required this.filteredProducts,
    required this.categories,
    required this.brands,
    required this.totalStock,
    required this.totalCostValue,
    required this.totalProducts,
  });
}

final processedProductsProvider =
    Provider.autoDispose<AsyncValue<ProcessedProductsData>>((ref) {
  final productsAsync = ref.watch(productListProvider);
  final searchQuery = ref.watch(productSearchQueryProvider);
  final selectedCategory = ref.watch(productCategoryFilterProvider);
  final selectedCategories = ref.watch(productSelectedCategoriesProvider);
  final selectedProductTypes = ref.watch(productTypeFilterProvider);
  final selectedBrand = ref.watch(productBrandFilterProvider);
  final stockStatus = ref.watch(productStockStatusFilterProvider);
  final sortOption = ref.watch(productSortOptionProvider);
  final categoryRepo = ref.watch(categoryRepositoryProvider);
  final rawKnownCategories =
      ref.watch(categoryListProvider).valueOrNull ?? const <Category>[];

  return productsAsync.whenData((products) {
    final allKnownCategories = harvestCategoriesFromProducts(
      rawKnownCategories,
      products,
      syncRepo: categoryRepo,
    );
    // Dynamic categories and brands extraction from all store products
    final categoriesSet = <String>{};
    final brandsSet = <String>{};

    for (final p in products) {
      final cat = p.category.trim();
      if (cat.isNotEmpty) {
        if (cat.contains('>>') || cat.contains('>')) {
          for (final seg in cat.split(RegExp(r'>>|>'))) {
            final s = seg.trim();
            if (s.isNotEmpty) categoriesSet.add(s);
          }
        } else {
          categoriesSet.add(cat);
        }
      }
      final c3 = p.category3Levels?.trim();
      if (c3 != null && c3.isNotEmpty) {
        for (final seg in c3.split(RegExp(r'>>|>'))) {
          final s = seg.trim();
          if (s.isNotEmpty) categoriesSet.add(s);
        }
      }
      final b = p.brand?.trim();
      if (b != null && b.isNotEmpty) {
        brandsSet.add(b);
      }
    }

    for (final c in allKnownCategories) {
      final name = c.name.trim();
      if (name.isNotEmpty) {
        categoriesSet.add(name);
      }
    }

    final categories = ['All', ...(categoriesSet.toList()..sort())];
    final brands = brandsSet.toList()..sort();

    // Start with a copy of all products
    List<Product> filtered = List<Product>.from(products);

    final bool isMultiSelect =
        selectedCategories.isNotEmpty && !selectedCategories.contains('All');

    // 1. Category Filter: hierarchical multi-level category matching
    // Determine active categories: prioritize multi-select if present and not 'All', fallback to legacy
    final Set<String> activeCategories;
    if (isMultiSelect) {
      activeCategories = selectedCategories
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty && c != 'All')
          .toSet();
    } else if (selectedCategory != 'All' &&
        selectedCategory.trim().isNotEmpty) {
      activeCategories = {selectedCategory.trim()};
    } else {
      activeCategories = const {};
    }

    if (activeCategories.isNotEmpty) {
      Set<String> extractProductCategorySegments(Product p) {
        final segments = <String>{p.category.trim().toLowerCase()};
        if (p.category.contains('>>') || p.category.contains('>')) {
          for (final seg in p.category.split(RegExp(r'>>|>'))) {
            final s = seg.trim().toLowerCase();
            if (s.isNotEmpty) segments.add(s);
          }
        }
        if (p.category3Levels != null && p.category3Levels!.trim().isNotEmpty) {
          for (final seg in p.category3Levels!.split(RegExp(r'>>|>'))) {
            final s = seg.trim().toLowerCase();
            if (s.isNotEmpty) segments.add(s);
          }
        }
        return segments;
      }

      final allTargetNamesAndIds = <String>{};
      final visitedIds = <String>{};

      void collectDescendants(String parentId) {
        for (final c in allKnownCategories) {
          if (c.parentId != null &&
              c.parentId!.trim().toLowerCase() == parentId) {
            final childId = c.id.trim().toLowerCase();
            if (visitedIds.add(childId)) {
              allTargetNamesAndIds.add(c.name.trim().toLowerCase());
              allTargetNamesAndIds.add(childId);
              collectDescendants(childId);
            }
          }
        }
      }

      for (final rawCat in activeCategories) {
        final targetCat = rawCat.trim().toLowerCase();
        if (targetCat.isEmpty) continue;

        Category? matchedNode;
        for (final c in allKnownCategories) {
          if (c.name.trim().toLowerCase() == targetCat ||
              c.id.trim().toLowerCase() == targetCat) {
            matchedNode = c;
            break;
          }
        }

        if (matchedNode != null) {
          final rootId = matchedNode.id.trim().toLowerCase();
          allTargetNamesAndIds.add(matchedNode.name.trim().toLowerCase());
          allTargetNamesAndIds.add(rootId);
          if (visitedIds.add(rootId)) {
            collectDescendants(rootId);
          }
        } else if (allKnownCategories.isEmpty) {
          allTargetNamesAndIds.add(targetCat);
        }
      }

      if (allTargetNamesAndIds.isNotEmpty) {
        filtered = filtered.where((p) {
          final segments = extractProductCategorySegments(p);
          for (final seg in segments) {
            if (allTargetNamesAndIds.contains(seg)) {
              return true;
            }
          }
          return false;
        }).toList();
      }
    }

    // 1b. Product Types Filter
    if (selectedProductTypes.length < ProductTypeFilter.values.length) {
      filtered = filtered.where((p) {
        if (p.isCombo) {
          return selectedProductTypes.contains(ProductTypeFilter.combo);
        } else if (p.type?.trim().toLowerCase() == 'dịch vụ') {
          return selectedProductTypes.contains(ProductTypeFilter.service);
        } else {
          return selectedProductTypes.contains(ProductTypeFilter.standard);
        }
      }).toList();
    }

    // 2. Brand Filter: exact match on brand
    if (selectedBrand != null && selectedBrand.trim().isNotEmpty) {
      final targetBrand = selectedBrand.trim().toLowerCase();
      filtered = filtered.where((p) {
        return (p.brand?.trim().toLowerCase() ?? '') == targetBrand;
      }).toList();
    }

    // 3. Stock Status Filter
    switch (stockStatus) {
      case StockStatus.all:
        break;
      case StockStatus.inStock:
        filtered = filtered.where((p) => p.stock > 0).toList();
        break;
      case StockStatus.outOfStock:
        filtered = filtered.where((p) => p.stock <= 0).toList();
        break;
      case StockStatus.belowMinStock:
        filtered = filtered.where((p) => p.isLowStock()).toList();
        break;
    }

    // 4. Smart Search: match name, code (SKU), barcode, brand, model, category
    final q = searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered = filtered.where((p) {
        final nameMatch = p.name.toLowerCase().contains(q);
        final codeMatch = p.code.toLowerCase().contains(q);
        final barcodeMatch =
            p.barcode != null && p.barcode!.toLowerCase().contains(q);
        final brandMatch =
            p.brand != null && p.brand!.toLowerCase().contains(q);
        final modelMatch =
            p.model != null && p.model!.toLowerCase().contains(q);
        final categoryMatch = p.category.toLowerCase().contains(q);
        final category3Match = p.category3Levels != null &&
            p.category3Levels!.toLowerCase().contains(q);
        return nameMatch ||
            codeMatch ||
            barcodeMatch ||
            brandMatch ||
            modelMatch ||
            categoryMatch ||
            category3Match;
      }).toList();
    }

    // 5. Sorting
    switch (sortOption) {
      case ProductSortOption.stockDesc:
        filtered.sort((a, b) => b.stock.compareTo(a.stock));
        break;
      case ProductSortOption.stockAsc:
        filtered.sort((a, b) => a.stock.compareTo(b.stock));
        break;
      case ProductSortOption.nameAsc:
        filtered.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case ProductSortOption.nameDesc:
        filtered.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case ProductSortOption.priceAsc:
        filtered.sort((a, b) => a.price.compareTo(b.price));
        break;
      case ProductSortOption.priceDesc:
        filtered.sort((a, b) => b.price.compareTo(a.price));
        break;
    }

    // 6. Summary metrics calculation
    final totalProducts = filtered.length;
    final totalStock = filtered.fold<int>(0, (sum, p) => sum + p.stock);
    final totalCostValue = filtered.fold<double>(
      0.0,
      (sum, p) => p.isCombo ? sum : sum + (p.stock * p.costPrice),
    );

    return ProcessedProductsData(
      filteredProducts: filtered,
      categories: categories,
      brands: brands,
      totalStock: totalStock,
      totalCostValue: totalCostValue,
      totalProducts: totalProducts,
    );
  });
});
