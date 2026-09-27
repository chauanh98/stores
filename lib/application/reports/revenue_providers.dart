import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/store_resolver_helper.dart';
import '../../data/datasources/firebase/inventory_remote_data_source.dart';
import '../../data/datasources/firebase/order_remote_data_source.dart';
import '../../data/datasources/firebase/product_remote_data_source.dart';
import '../../data/models/order_model.dart';
import '../../data/repositories/revenue_repository_impl.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/revenue_report.dart';
import '../auth/auth_providers.dart';
import '../products/products_providers.dart';
import 'overview_providers.dart';

final orderRemoteDataSourceProvider = Provider<OrderRemoteDataSource>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  return OrderRemoteDataSource(FirebaseDatabase.instance, storeId);
});

final inventoryRemoteDataSourceProvider =
    Provider<InventoryRemoteDataSource>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  return InventoryRemoteDataSource(FirebaseDatabase.instance, storeId);
});

final productRemoteDataSourceProvider =
    Provider<ProductRemoteDataSource>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  return ProductRemoteDataSource(FirebaseDatabase.instance, storeId);
});

final revenueRepositoryProvider = Provider<RevenueRepositoryImpl>((ref) {
  final orderDs = ref.watch(orderRemoteDataSourceProvider);
  final inventoryDs = ref.watch(inventoryRemoteDataSourceProvider);
  final productDs = ref.watch(productRemoteDataSourceProvider);
  return RevenueRepositoryImpl(orderDs, inventoryDs, productDs);
});

// Dùng StreamProvider để tự động cập nhật khi có đơn hàng mới
final revenueByDateProvider = StreamProvider.autoDispose
    .family<RevenueReport, DateTime>((ref, date) async* {
  final startOfDay = DateTime(date.year, date.month, date.day);
  final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  final summary = await ref.watch(revenueByDateRangeProvider(
    DateTimeRange(start: startOfDay, end: endOfDay),
  ).future);

  if (summary.dailyReports.isNotEmpty) {
    yield summary.dailyReports.first;
  } else {
    yield RevenueReport(
      date: date,
      totalRevenue: 0.0,
      totalCost: 0.0,
      profit: 0.0,
      totalOrders: 0,
      totalItemsSold: 0,
      productRevenues: const [],
    );
  }
});

final revenueByDateRangeProvider = StreamProvider.autoDispose
    .family<RevenueSummary, DateTimeRange>((ref, range) async* {
  final selectedBranches = ref.watch(selectedBranchesProvider);
  final currentStoreId = ref.watch(currentStoreIdProvider);
  final storeFilter = ref.watch(selectedStoreFilterProvider);
  final user = ref.watch(authProvider);
  final availableStores = ref.watch(availableStoresProvider).valueOrNull ?? {};

  final targetStoreIds = StoreResolverHelper.resolveTargetStoreIds(
    selectedBranches,
    currentStoreId: currentStoreId,
    user: user,
    storeFilter: storeFilter,
    availableStores: availableStores,
  );

  if (targetStoreIds.isEmpty) {
    yield RevenueSummary(
      startDate: range.start,
      endDate: range.end,
      totalRevenue: 0.0,
      totalCost: 0.0,
      totalProfit: 0.0,
      totalOrders: 0,
      totalItemsSold: 0,
      dailyReports: const [],
    );
    return;
  }

  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end =
      DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);

  // Tạo combined stream để gộp các update của nhiều store
  final controller = StreamController<List<Map<String, dynamic>>>();
  final List<StreamSubscription> subscriptions = [];
  final Map<String, List<Map<String, dynamic>>> storeOrdersMap = {};

  for (final storeId in targetStoreIds) {
    final orderDs = OrderRemoteDataSource(FirebaseDatabase.instance, storeId);
    final sub = orderDs.watchByDateRange(start, end).listen(
      (orders) {
        storeOrdersMap[storeId] = orders;
        // Gộp tất cả các đơn hàng từ các store
        final combined = storeOrdersMap.values.expand((e) => e).toList();
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

  // R1: Tái sử dụng sản phẩm từ bộ nhớ (productListProvider / allStoresProductsProvider)
  // Triệt tiêu lệnh productDs.fetchAll() tải lại toàn bộ cây dữ liệu khi đổi khoảng ngày
  final inMemoryProducts =
      ref.watch(productListProvider).valueOrNull ?? const <Product>[];
  final inMemoryProductMaps = inMemoryProducts
      .map((p) => <String, dynamic>{
            'id': p.id,
            'name': p.name,
            'price': p.price,
            'costPrice': p.costPrice,
          })
      .toList();

  final allStoresProducts =
      ref.watch(allStoresProductsProvider).valueOrNull ?? const <Product>[];
  final allStoresProductMaps = allStoresProducts
      .map((p) => <String, dynamic>{
            'id': p.id,
            'name': p.name,
            'price': p.price,
            'costPrice': p.costPrice,
          })
      .toList();

  final combinedProducts = allStoresProductMaps.isNotEmpty
      ? allStoresProductMaps
      : inMemoryProductMaps;

  // Optimized: cache inventory imports cho mỗi store theo khoảng ngày
  final Map<String, List<Map>> inventoryCache = {};

  try {
    await for (final _ in controller.stream) {
      // Tính toán summary cho từng store riêng biệt, rồi gộp lại để đảm bảo FIFO chuẩn xác từng store
      final List<RevenueSummary> summaries = [];

      for (final storeId in targetStoreIds) {
        final storeOrders = storeOrdersMap[storeId] ?? [];
        final filteredStoreOrders = storeOrders.where((order) {
          final orderModel = OrderModel.fromMap(order);
          if (orderModel.isCancelled || orderModel.isDraft) return false;

          // Nếu là Admin/Supervisor (canSwitchStore == true), việc lọc theo chi nhánh đã được thực hiện bằng cách chỉ chọn query store tương ứng ở bước trên!
          if (user?.canSwitchStore == true || user?.isAdmin == true)
            return true;

          // Nhân viên thường: Chỉ được xem chi nhánh được phân quyền của cửa hàng hiện tại
          final normalizedStoreId =
              StoreResolverHelper.normalizeStoreId(storeId);
          return selectedBranches.any((b) =>
              StoreResolverHelper.normalizeStoreId(b) == normalizedStoreId);
        }).toList();

        // Optimized: cache inventory per store - chỉ fetch 1 lần
        if (!inventoryCache.containsKey(storeId)) {
          final inventoryDs =
              InventoryRemoteDataSource(FirebaseDatabase.instance, storeId);
          try {
            inventoryCache[storeId] =
                await inventoryDs.fetchImportsByDateRange(start, end);
          } catch (e) {
            debugPrint(
                'Error fetching inventory imports for store $storeId: $e');
            inventoryCache[storeId] = [];
          }
        }

        final inventory = inventoryCache[storeId]!;
        final products = combinedProducts;

        // Tạo repo cho storeId này để tính toán chuẩn xác độc lập
        final storeRepo = RevenueRepositoryImpl(
          OrderRemoteDataSource(FirebaseDatabase.instance, storeId),
          InventoryRemoteDataSource(FirebaseDatabase.instance, storeId),
          ProductRemoteDataSource(FirebaseDatabase.instance, storeId),
        );

        final storeSummary = storeRepo.calculateRevenueSummary(
          orders: filteredStoreOrders,
          inventoryTransactions: inventory,
          products: products,
          startDate: range.start,
          endDate: range.end,
        );
        summaries.add(storeSummary);
      }

      // Merge các summaries lại
      final mergedSummary =
          mergeRevenueSummaries(summaries, range.start, range.end);
      yield mergedSummary;
    }
  } catch (e, stack) {
    debugPrint('Revenue provider error: $e');
    debugPrint(stack.toString());
    rethrow;
  }
});

// Helper gộp nhiều RevenueSummary của các store riêng biệt
RevenueSummary mergeRevenueSummaries(
    List<RevenueSummary> summaries, DateTime startDate, DateTime endDate) {
  double totalRevenue = 0.0;
  double totalCost = 0.0;
  int totalOrders = 0;
  int totalItemsSold = 0;

  // Gộp dailyReports theo ngày
  final Map<DateTime, RevenueReport> combinedDailyReports = {};

  for (final summary in summaries) {
    totalRevenue += summary.totalRevenue;
    totalCost += summary.totalCost;
    totalOrders += summary.totalOrders;
    totalItemsSold += summary.totalItemsSold;

    for (final report in summary.dailyReports) {
      final dateOnly =
          DateTime(report.date.year, report.date.month, report.date.day);
      if (combinedDailyReports.containsKey(dateOnly)) {
        final existing = combinedDailyReports[dateOnly]!;
        combinedDailyReports[dateOnly] = RevenueReport(
          date: dateOnly,
          totalRevenue: existing.totalRevenue + report.totalRevenue,
          totalCost: existing.totalCost + report.totalCost,
          profit: (existing.totalRevenue + report.totalRevenue) -
              (existing.totalCost + report.totalCost),
          totalOrders: existing.totalOrders + report.totalOrders,
          totalItemsSold: existing.totalItemsSold + report.totalItemsSold,
          productRevenues: _mergeProductRevenues(
              existing.productRevenues, report.productRevenues),
          storeRevenues:
              _mergeStoreRevenues(existing.storeRevenues, report.storeRevenues),
        );
      } else {
        combinedDailyReports[dateOnly] = report;
      }
    }
  }

  // Sắp xếp lại dailyReports theo thời gian
  final sortedReports = combinedDailyReports.values.toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  return RevenueSummary(
    startDate: startDate,
    endDate: endDate,
    totalRevenue: totalRevenue,
    totalCost: totalCost,
    totalProfit: totalRevenue - totalCost,
    totalOrders: totalOrders,
    totalItemsSold: totalItemsSold,
    dailyReports: sortedReports,
  );
}

// Helper gộp storeRevenues của các store
Map<String, double> _mergeStoreRevenues(
    Map<String, double> map1, Map<String, double> map2) {
  final Map<String, double> result = Map.from(map1);
  map2.forEach((key, value) {
    result[key] = (result[key] ?? 0.0) + value;
  });
  return result;
}

// Helper gộp productRevenues của các store
List<ProductRevenue> _mergeProductRevenues(
    List<ProductRevenue> list1, List<ProductRevenue> list2) {
  final Map<String, ProductRevenue> map = {};
  for (final pr in [...list1, ...list2]) {
    if (map.containsKey(pr.productId)) {
      final existing = map[pr.productId]!;
      final newRevenue = existing.revenue + pr.revenue;
      final newCost = existing.cost + pr.cost;
      map[pr.productId] = ProductRevenue(
        productId: pr.productId,
        productName: pr.productName,
        quantitySold: existing.quantitySold + pr.quantitySold,
        revenue: newRevenue,
        cost: newCost,
        profit: newRevenue - newCost,
        profitMargin:
            ((newRevenue - newCost) / (newCost == 0 ? 1.0 : newCost)) * 100,
      );
    } else {
      map[pr.productId] = pr;
    }
  }
  return map.values.toList();
}
