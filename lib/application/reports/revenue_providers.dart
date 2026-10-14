import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/fifo_calculator.dart';
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
  // BĂNG THÔNG: provider này giữ listener RTDB cho toàn bộ đơn hàng + phiếu nhập
  // trong khoảng ngày. Mọi `ref.watch` ở đây đều khiến listener bị huỷ & mở lại
  // (= tải lại toàn bộ khoảng ngày). Vì vậy:
  // - Chỉ watch tập store ID dưới dạng key so sánh theo giá trị.
  // - KHÔNG watch danh sách sản phẩm (đổi tồn kho sau mỗi lần bán) — chỉ `listen`
  //   và tính lại khi giá vốn / giá bán / tên thay đổi.
  final targetStoreIds = StoreResolverHelper.storeIdsFromKey(
      ref.watch(filteredStoreIdsKeyProvider.select((k) => k)));
  final user = ref.watch(authProvider);
  final isPrivileged = user?.canSwitchStore == true || user?.isAdmin == true;
  // Chi nhánh được chọn chỉ dùng để lọc cho nhân viên; Admin/Giám sát đã lọc
  // qua tập store ID ở trên => không watch để bấm chip chi nhánh không mở lại listener.
  final selectedBranches =
      isPrivileged ? const <String>[] : ref.watch(selectedBranchesProvider);

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

  // Mỗi sự kiện trên trigger = "dữ liệu đầu vào đã đổi, tính lại".
  final trigger = StreamController<void>();
  final List<StreamSubscription> subscriptions = [];
  final List<Timer> timers = [];
  final Map<String, List<Map<String, dynamic>>> storeOrdersMap = {};
  final Map<String, List<Map>> storeImportsMap = {};

  void notify() {
    if (!trigger.isClosed) trigger.add(null);
  }

  for (final storeId in targetStoreIds) {
    final orderDs = OrderRemoteDataSource(FirebaseDatabase.instance, storeId);
    subscriptions.add(orderDs.watchByDateRange(start, end).listen(
      (orders) {
        storeOrdersMap[storeId] = orders;
        notify();
      },
      onError: (Object err, StackTrace st) {
        if (!trigger.isClosed) trigger.addError(err, st);
      },
    ));

    // Phiếu nhập dùng để tính giá vốn FIFO: nghe realtime (cùng truy vấn với
    // trang Nhập hàng nên SDK dùng chung 1 listener) thay vì `get()` lại mỗi
    // lần provider rebuild.
    final inventoryDs =
        InventoryRemoteDataSource(FirebaseDatabase.instance, storeId);
    // Offline & chưa có dữ liệu: không để báo cáo "Đang tải" mãi — sau 8s tính
    // với danh sách phiếu nhập rỗng, dữ liệu thật đến sau sẽ tính lại.
    final importsTimeout = Timer(const Duration(seconds: 8), () {
      if (!storeImportsMap.containsKey(storeId)) {
        storeImportsMap[storeId] = const [];
        notify();
      }
    });
    timers.add(importsTimeout);
    subscriptions.add(inventoryDs.watchImportsByDateRange(start, end).listen(
      (imports) {
        importsTimeout.cancel();
        storeImportsMap[storeId] = imports;
        notify();
      },
      onError: (Object e) {
        debugPrint('Error watching inventory imports for store $storeId: $e');
        storeImportsMap[storeId] = const [];
        notify();
      },
    ));
  }

  int pricingSignature(List<Product>? products) {
    if (products == null) return 0;
    var hash = products.length;
    for (final p in products) {
      hash = Object.hash(hash, p.id, p.costPrice, p.price, p.name);
    }
    return hash;
  }

  List<Product> currentProducts() {
    final all = ref.read(allStoresProductsProvider).valueOrNull;
    if (all != null && all.isNotEmpty) return all;
    return ref.read(productListProvider).valueOrNull ?? const <Product>[];
  }

  var lastPricingSignature = pricingSignature(currentProducts());
  void onProductsChanged() {
    final sig = pricingSignature(currentProducts());
    if (sig != lastPricingSignature) {
      lastPricingSignature = sig;
      notify();
    }
  }

  // `listen` giữ 2 provider sản phẩm sống (như watch cũ) nhưng không rebuild provider này.
  ref.listen<AsyncValue<List<Product>>>(
      allStoresProductsProvider, (_, __) => onProductsChanged());
  ref.listen<AsyncValue<List<Product>>>(
      productListProvider, (_, __) => onProductsChanged());

  ref.onDispose(() {
    for (final sub in subscriptions) {
      sub.cancel();
    }
    for (final t in timers) {
      t.cancel();
    }
    trigger.close();
  });

  try {
    await for (final _ in trigger.stream) {
      // Chờ đủ dữ liệu đơn hàng + phiếu nhập của mọi chi nhánh để không phát ra
      // kết quả tạm (giá vốn = 0 => lợi nhuận ảo).
      final ready = targetStoreIds.every((id) =>
          storeOrdersMap.containsKey(id) && storeImportsMap.containsKey(id));
      if (!ready) continue;

      final products = currentProducts()
          .map((p) => <String, dynamic>{
                'id': p.id,
                'name': p.name,
                'price': p.price,
                'costPrice': p.costPrice,
              })
          .toList();

      // Tính toán summary cho từng store riêng biệt, rồi gộp lại để đảm bảo FIFO chuẩn xác từng store
      final List<RevenueSummary> summaries = [];

      for (final storeId in targetStoreIds) {
        final storeOrders = storeOrdersMap[storeId] ?? [];
        final filteredStoreOrders = storeOrders.where((order) {
          final orderModel = OrderModel.fromMap(order);
          if (orderModel.isCancelled ||
              orderModel.isDraft ||
              orderModel.isReturned ||
              orderModel.allItemsReturned) {
            return false;
          }

          // Nếu là Admin/Supervisor (canSwitchStore == true), việc lọc theo chi nhánh đã được thực hiện bằng cách chỉ chọn query store tương ứng ở bước trên!
          if (isPrivileged) {
            return true;
          }

          // Nhân viên thường: Chỉ được xem chi nhánh được phân quyền của cửa hàng hiện tại
          final normalizedStoreId =
              StoreResolverHelper.normalizeStoreId(storeId);
          return selectedBranches.any((b) =>
              StoreResolverHelper.normalizeStoreId(b) == normalizedStoreId);
        }).toList();

        // Tạo repo cho storeId này để tính toán chuẩn xác độc lập
        final storeRepo = RevenueRepositoryImpl(
          OrderRemoteDataSource(FirebaseDatabase.instance, storeId),
          InventoryRemoteDataSource(FirebaseDatabase.instance, storeId),
          ProductRemoteDataSource(FirebaseDatabase.instance, storeId),
        );

        final storeSummary = storeRepo.calculateRevenueSummary(
          orders: filteredStoreOrders,
          inventoryTransactions: storeImportsMap[storeId] ?? const [],
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
        // Cùng công thức với RevenueRepositoryImpl: biên lợi nhuận trên DOANH THU
        // (không phải trên giá vốn).
        profitMargin: FifoCalculator.calculateProfitMargin(newRevenue, newCost),
      );
    } else {
      map[pr.productId] = pr;
    }
  }
  return map.values.toList();
}
