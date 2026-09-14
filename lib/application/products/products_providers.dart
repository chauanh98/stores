import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/store_resolver_helper.dart';
import '../../data/datasources/firebase/product_remote_data_source.dart';
import '../../data/repositories/product_repository_impl.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../auth/auth_providers.dart';
import '../reports/overview_providers.dart';

final productRemoteDataSourceProvider =
    Provider<ProductRemoteDataSource>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  return ProductRemoteDataSource(FirebaseDatabase.instance, storeId);
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  final ds = ref.watch(productRemoteDataSourceProvider);
  return ProductRepositoryImpl(ds);
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
  final availableStores = ref.watch(availableStoresProvider).value ?? {};

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
        if (!controller.isClosed) {
          controller.add(combined);
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

final productCategoryFilterProvider =
    StateProvider.autoDispose<String>((ref) => 'All');

final productBrandFilterProvider =
    StateProvider.autoDispose<String?>((ref) => null);

enum StockStatus {
  all,
  inStock,
  outOfStock,
  belowMinStock,
}

final productStockStatusFilterProvider =
    StateProvider.autoDispose<StockStatus>((ref) => StockStatus.all);

enum ProductSortOption {
  stockDesc,
  stockAsc,
  nameAsc,
  nameDesc,
  priceAsc,
  priceDesc,
}

final productSortOptionProvider =
    StateProvider.autoDispose<ProductSortOption>(
        (ref) => ProductSortOption.stockDesc);

final showCostPriceProvider =
    StateProvider.autoDispose<bool>((ref) => false);

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
  final selectedBrand = ref.watch(productBrandFilterProvider);
  final stockStatus = ref.watch(productStockStatusFilterProvider);
  final sortOption = ref.watch(productSortOptionProvider);

  return productsAsync.whenData((products) {
    // Dynamic categories and brands extraction from all store products
    final categoriesSet = <String>{};
    final brandsSet = <String>{};

    for (final p in products) {
      final cat = p.category.trim();
      if (cat.isNotEmpty) {
        categoriesSet.add(cat);
      }
      final b = p.brand?.trim();
      if (b != null && b.isNotEmpty) {
        brandsSet.add(b);
      }
    }

    final categories = ['All', ...(categoriesSet.toList()..sort())];
    final brands = brandsSet.toList()..sort();

    // Start with a copy of all products
    List<Product> filtered = List<Product>.from(products);

    // 1. Category Filter: exact match or multi-level category
    if (selectedCategory != 'All' && selectedCategory.trim().isNotEmpty) {
      final targetCat = selectedCategory.trim().toLowerCase();
      filtered = filtered.where((p) {
        final catMatch = p.category.trim().toLowerCase() == targetCat;
        final cat3Match = p.category3Levels != null &&
            p.category3Levels!.toLowerCase().contains(targetCat);
        return catMatch || cat3Match;
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
        filtered.sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case ProductSortOption.nameDesc:
        filtered.sort((a, b) =>
            b.name.toLowerCase().compareTo(a.name.toLowerCase()));
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
