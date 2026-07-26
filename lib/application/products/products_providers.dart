import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  final List<String> targetStoreIds = [];
  if (user?.isAdmin == true) {
    if (storeFilter == 'all') {
      final availableStores = ref.watch(availableStoresProvider).value ?? {};
      if (availableStores.isNotEmpty) {
        targetStoreIds.addAll(availableStores.keys);
      } else {
        targetStoreIds.add(currentStoreId);
      }
    } else if (storeFilter != null) {
      targetStoreIds.add(storeFilter);
    } else {
      // Khi không lọc trực tiếp cửa hàng, ánh xạ từ danh sách chi nhánh được chọn trên giao diện
      for (final branchId in selectedBranches) {
        if (currentStoreId == 'store_001') {
          if (branchId == 'branch_1') {
            targetStoreIds.add('store_001'); // Cửa hàng Hà Nội
          } else if (branchId == 'branch_2') {
            targetStoreIds.add('store_002'); // Cửa hàng TP.HCM
          }
        } else if (currentStoreId == 'store_002') {
          if (branchId == 'branch_1') {
            targetStoreIds.add('store_002'); // Cửa hàng TP.HCM
          } else if (branchId == 'branch_2') {
            targetStoreIds.add('store_001'); // Cửa hàng Hà Nội
          }
        }
      }
    }
  }

  if (targetStoreIds.isEmpty) {
    targetStoreIds.add(currentStoreId);
  }

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

final productSearchQueryProvider =
    StateProvider.autoDispose<String>((ref) => '');
final productCategoryFilterProvider =
    StateProvider.autoDispose<String>((ref) => 'All');

class ProcessedProductsData {
  final List<Product> filteredProducts;
  final Set<String> categories;
  final int totalStock;

  ProcessedProductsData({
    required this.filteredProducts,
    required this.categories,
    required this.totalStock,
  });
}

final processedProductsProvider =
    Provider.autoDispose<AsyncValue<ProcessedProductsData>>((ref) {
  final productsAsync = ref.watch(productListProvider);
  final searchQuery = ref.watch(productSearchQueryProvider);
  final selectedCategory = ref.watch(productCategoryFilterProvider);

  return productsAsync.whenData((products) {
    final cats = {'All', ...products.map((e) => e.category).toSet()};

    final byCategory = selectedCategory == 'All'
        ? products
        : products.where((p) => p.category == selectedCategory).toList();

    final q = searchQuery.trim().toLowerCase();
    final filtered = q.isEmpty
        ? byCategory
        : byCategory.where((p) {
            return p.name.toLowerCase().contains(q) ||
                (p.brand ?? '').toLowerCase().contains(q) ||
                (p.model ?? '').toLowerCase().contains(q) ||
                p.category.toLowerCase().contains(q);
          }).toList();

    final totalStock = filtered.fold(0, (sum, p) => sum + p.stock);

    return ProcessedProductsData(
      filteredProducts: filtered,
      categories: cats,
      totalStock: totalStock,
    );
  });
});
