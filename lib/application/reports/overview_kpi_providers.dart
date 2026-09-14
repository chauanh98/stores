import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/customer.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/overview_kpis.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/revenue_report.dart';
import '../customers/customers_providers.dart';
import '../orders/orders_providers.dart';
import '../products/products_providers.dart';
import 'overview_providers.dart';
import 'revenue_providers.dart';

// =============================================================================
// 1. Date Range Providers for Overview & Comparison
// =============================================================================

/// Provider khoảng thời gian đang được chọn trên Tab Tổng quan
final overviewCurrentDateRangeProvider =
    Provider.autoDispose<DateTimeRange>((ref) {
  return ref.watch(overviewActiveDateRangeProvider);
});

/// Provider tính toán khoảng thời gian so sánh liền trước (Prior Period)
/// Phục vụ tính % tăng trưởng cùng kỳ (Period-over-Period growth)
final overviewPriorPeriodDateRangeProvider =
    Provider.autoDispose<DateTimeRange>((ref) {
  final type = ref.watch(overviewTimeRangeTypeProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  switch (type) {
    case OverviewTimeRange.today:
      // Hôm nay -> So với Hôm qua
      final yesterday = today.subtract(const Duration(days: 1));
      return DateTimeRange(
        start: yesterday,
        end: DateTime(
            yesterday.year, yesterday.month, yesterday.day, 23, 59, 59, 999),
      );

    case OverviewTimeRange.yesterday:
      // Hôm qua -> So với Hôm kia (2 ngày trước)
      final twoDaysAgo = today.subtract(const Duration(days: 2));
      return DateTimeRange(
        start: twoDaysAgo,
        end: DateTime(
            twoDaysAgo.year, twoDaysAgo.month, twoDaysAgo.day, 23, 59, 59, 999),
      );

    case OverviewTimeRange.last7Days:
      // 7 ngày qua -> So với 7 ngày liền trước đó (từ ngày -13 đến ngày -7)
      final prevStart = today.subtract(const Duration(days: 13));
      final prevEnd = today.subtract(const Duration(days: 7));
      return DateTimeRange(
        start: prevStart,
        end: DateTime(
            prevEnd.year, prevEnd.month, prevEnd.day, 23, 59, 59, 999),
      );

    case OverviewTimeRange.thisMonth:
      // Tháng này -> So với trọn vẹn Tháng trước
      final firstOfThisMonth = DateTime(now.year, now.month, 1);
      final lastOfLastMonth =
          firstOfThisMonth.subtract(const Duration(days: 1));
      final firstOfLastMonth =
          DateTime(lastOfLastMonth.year, lastOfLastMonth.month, 1);
      return DateTimeRange(
        start: firstOfLastMonth,
        end: DateTime(lastOfLastMonth.year, lastOfLastMonth.month,
            lastOfLastMonth.day, 23, 59, 59, 999),
      );

    case OverviewTimeRange.lastMonth:
      // Tháng trước -> So với Tháng trước nữa (2 tháng trước)
      final firstOfThisMonth = DateTime(now.year, now.month, 1);
      final lastOfLastMonth =
          firstOfThisMonth.subtract(const Duration(days: 1));
      final firstOfLastMonth =
          DateTime(lastOfLastMonth.year, lastOfLastMonth.month, 1);
      final lastOfTwoMonthsAgo =
          firstOfLastMonth.subtract(const Duration(days: 1));
      final firstOfTwoMonthsAgo =
          DateTime(lastOfTwoMonthsAgo.year, lastOfTwoMonthsAgo.month, 1);
      return DateTimeRange(
        start: firstOfTwoMonthsAgo,
        end: DateTime(lastOfTwoMonthsAgo.year, lastOfTwoMonthsAgo.month,
            lastOfTwoMonthsAgo.day, 23, 59, 59, 999),
      );

    case OverviewTimeRange.custom:
      // Tùy chỉnh -> Khoảng thời gian liền trước có cùng độ dài (duration)
      final customRange = ref.watch(overviewCustomDateRangeProvider);
      final duration = customRange.duration;
      final prevEnd = customRange.start.subtract(const Duration(milliseconds: 1));
      final prevStart = prevEnd.subtract(duration);
      return DateTimeRange(
        start: DateTime(prevStart.year, prevStart.month, prevStart.day),
        end: DateTime(
            prevEnd.year, prevEnd.month, prevEnd.day, 23, 59, 59, 999),
      );
  }
});

/// Công thức toán học tính % tăng/giảm giữa 2 kỳ
double calculateGrowthPercent(double current, double prior) {
  if (prior == 0.0 && current == 0.0) return 0.0;
  if (prior == 0.0 && current > 0.0) return 100.0;
  if (prior > 0.0 && current == 0.0) return -100.0;
  return ((current - prior) / prior.abs()) * 100.0;
}

// =============================================================================
// 2. Comprehensive Business KPIs Provider (R1)
// =============================================================================

/// Provider tổng hợp toàn diện các chỉ số kinh doanh & % tăng trưởng so với kỳ trước
final overviewKPIsProvider =
    Provider.autoDispose<AsyncValue<OverviewKPIs>>((ref) {
  final currentRange = ref.watch(overviewCurrentDateRangeProvider);
  final priorRange = ref.watch(overviewPriorPeriodDateRangeProvider);

  final currentSummaryAsync = ref.watch(revenueByDateRangeProvider(currentRange));
  final priorSummaryAsync = ref.watch(revenueByDateRangeProvider(priorRange));
  final customersAsync = ref.watch(customerListNotifierProvider);

  // Nếu bất kỳ luồng dữ liệu nào đang loading
  if (currentSummaryAsync.isLoading ||
      priorSummaryAsync.isLoading ||
      customersAsync.isLoading) {
    return const AsyncValue.loading();
  }

  // Nếu có lỗi phát sinh
  if (currentSummaryAsync.hasError) {
    return AsyncValue.error(
        currentSummaryAsync.error!, currentSummaryAsync.stackTrace!);
  }
  if (priorSummaryAsync.hasError) {
    return AsyncValue.error(
        priorSummaryAsync.error!, priorSummaryAsync.stackTrace!);
  }

  final currentSummary = currentSummaryAsync.value;
  final priorSummary = priorSummaryAsync.value;
  final customers = customersAsync.value ?? [];

  if (currentSummary == null || priorSummary == null) {
    return const AsyncValue.data(OverviewKPIs.empty);
  }

  // Các chỉ số kỳ hiện tại
  final netRevenue = currentSummary.totalRevenue;
  final orderCount = currentSummary.totalOrders;
  final grossProfit = currentSummary.totalProfit;
  final aov = orderCount > 0 ? (netRevenue / orderCount) : 0.0;
  const returnGoodsValue = 0.0;

  // Các chỉ số kỳ trước
  final priorRevenue = priorSummary.totalRevenue;
  final priorOrders = priorSummary.totalOrders;
  final priorProfit = priorSummary.totalProfit;
  final priorAov = priorOrders > 0 ? (priorRevenue / priorOrders) : 0.0;

  // Tính toán % tăng trưởng
  final revenueGrowth = calculateGrowthPercent(netRevenue, priorRevenue);
  final ordersGrowth =
      calculateGrowthPercent(orderCount.toDouble(), priorOrders.toDouble());
  final profitGrowth = calculateGrowthPercent(grossProfit, priorProfit);
  final aovGrowth = calculateGrowthPercent(aov, priorAov);

  // Tổng công nợ khách hàng cần thu
  final customerDebt = customers.fold<double>(
    0.0,
    (sum, c) => sum + (c.currentDebt != null && c.currentDebt! > 0 ? c.currentDebt! : 0.0),
  );

  final kpis = OverviewKPIs(
    netRevenue: netRevenue,
    orderCount: orderCount,
    grossProfit: grossProfit,
    returnGoodsValue: returnGoodsValue,
    aov: aov,
    revenueGrowthPercent: revenueGrowth,
    orderCountGrowthPercent: ordersGrowth,
    profitGrowthPercent: profitGrowth,
    aovGrowthPercent: aovGrowth,
    customerDebt: customerDebt,
    previousRevenue: priorRevenue,
    previousOrders: priorOrders,
    previousProfit: priorProfit,
    previousAov: priorAov,
  );

  return AsyncValue.data(kpis);
});

// =============================================================================
// 3. Hourly Revenue Distribution Provider (R2)
// =============================================================================

/// Provider phân bổ doanh thu theo 24 mốc giờ trong ngày (0h..23h) cho chế độ 1 ngày
final hourlyRevenueListProvider =
    Provider.autoDispose<AsyncValue<List<HourlyRevenueData>>>((ref) {
  final currentRange = ref.watch(overviewCurrentDateRangeProvider);
  final ordersAsync =
      ref.watch(allBranchesOrdersByDateRangeProvider(currentRange));

  return ordersAsync.whenData((orders) {
    // Chỉ tính các đơn hàng hoàn thành
    final completedOrders =
        orders.where((o) => o.status == 'completed').toList();

    // Khởi tạo 24 khung giờ
    final hourlyRevenueMap = <int, double>{};
    final hourlyOrderCountMap = <int, int>{};
    final hourlyBranchMap = <int, Map<String, double>>{};

    for (int h = 0; h < 24; h++) {
      hourlyRevenueMap[h] = 0.0;
      hourlyOrderCountMap[h] = 0;
      hourlyBranchMap[h] = {};
    }

    for (final order in completedOrders) {
      final hour = order.createdAt.hour;
      hourlyRevenueMap[hour] = (hourlyRevenueMap[hour] ?? 0.0) + order.total;
      hourlyOrderCountMap[hour] = (hourlyOrderCountMap[hour] ?? 0) + 1;

      final branchKey = order.createdBy ?? 'store';
      final branchMap = hourlyBranchMap[hour] ?? {};
      branchMap[branchKey] = (branchMap[branchKey] ?? 0.0) + order.total;
      hourlyBranchMap[hour] = branchMap;
    }

    final List<HourlyRevenueData> result = [];
    for (int h = 0; h < 24; h++) {
      result.add(HourlyRevenueData(
        hour: h,
        revenue: hourlyRevenueMap[h] ?? 0.0,
        orderCount: hourlyOrderCountMap[h] ?? 0,
        branchRevenue: hourlyBranchMap[h] ?? {},
      ));
    }

    return result;
  });
});

// =============================================================================
// 4. Payment Method Breakdown Provider (R4)
// =============================================================================

/// Provider cơ cấu doanh thu theo phương thức thanh toán: Tiền mặt, Chuyển khoản, Ghi nợ
final paymentBreakdownProvider =
    Provider.autoDispose<AsyncValue<PaymentBreakdown>>((ref) {
  final currentRange = ref.watch(overviewCurrentDateRangeProvider);
  final ordersAsync =
      ref.watch(allBranchesOrdersByDateRangeProvider(currentRange));

  return ordersAsync.whenData((orders) {
    final completedOrders =
        orders.where((o) => o.status == 'completed').toList();

    double cash = 0.0;
    double transfer = 0.0;
    double debt = 0.0;
    double total = 0.0;

    for (final order in completedOrders) {
      final method = order.paymentMethod.toLowerCase();
      final paid = order.amountPaid;
      final orderDebt = order.debtAmount;
      final orderTotal = order.total;

      total += orderTotal;

      if (orderDebt > 0) {
        debt += orderDebt;
      }

      if (method == 'split' || method.contains('split')) {
        cash += (order.cashAmount ?? 0.0);
        transfer += (order.transferAmount ?? 0.0);
      } else if (paid > 0) {
        if (method.contains('transfer') ||
            method.contains('bank') ||
            method.contains('qr') ||
            method.contains('vietqr') ||
            method.contains('chuyen')) {
          transfer += paid;
        } else {
          cash += paid;
        }
      } else if (orderDebt == 0) {
        // Đơn hàng thanh toán đủ nhưng không ghi rõ amountPaid (fallback)
        if (method.contains('transfer') ||
            method.contains('bank') ||
            method.contains('qr') ||
            method.contains('vietqr') ||
            method.contains('chuyen')) {
          transfer += orderTotal;
        } else {
          cash += orderTotal;
        }
      }
    }

    return PaymentBreakdown(
      cashAmount: cash,
      transferAmount: transfer,
      debtAmount: debt,
      totalAmount: total,
    );
  });
});

// =============================================================================
// 5. Category Revenue Share Provider (R4)
// =============================================================================

/// Provider thống kê tỷ trọng doanh thu theo từng nhóm hàng / danh mục
final categoryRevenueShareProvider =
    Provider.autoDispose<AsyncValue<List<CategoryRevenueShare>>>((ref) {
  final currentRange = ref.watch(overviewCurrentDateRangeProvider);
  final ordersAsync =
      ref.watch(allBranchesOrdersByDateRangeProvider(currentRange));
  final productsAsync = ref.watch(allStoresProductsProvider);

  if (ordersAsync.isLoading || productsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (ordersAsync.hasError) {
    return AsyncValue.error(ordersAsync.error!, ordersAsync.stackTrace!);
  }
  if (productsAsync.hasError) {
    return AsyncValue.error(productsAsync.error!, productsAsync.stackTrace!);
  }

  final orders = ordersAsync.value ?? [];
  final products = productsAsync.value ?? [];

  // Tạo map tra cứu category của từng product ID
  final productCategoryMap = <String, String>{};
  for (final p in products) {
    productCategoryMap[p.id] = p.category.isNotEmpty ? p.category : 'Khác';
  }

  final categoryRevenueMap = <String, double>{};
  final categoryQtyMap = <String, int>{};

  final completedOrders = orders.where((o) => o.status == 'completed');
  for (final order in completedOrders) {
    for (final item in order.items) {
      final cat = productCategoryMap[item.productId] ?? 'Khác';
      final itemRevenue = item.price * item.quantity;

      categoryRevenueMap[cat] = (categoryRevenueMap[cat] ?? 0.0) + itemRevenue;
      categoryQtyMap[cat] = (categoryQtyMap[cat] ?? 0) + item.quantity;
    }
  }

  final totalCategoryRevenue =
      categoryRevenueMap.values.fold(0.0, (sum, rev) => sum + rev);

  final List<CategoryRevenueShare> list = [];
  for (final entry in categoryRevenueMap.entries) {
    final catName = entry.key;
    final rev = entry.value;
    final pct = totalCategoryRevenue > 0 ? (rev / totalCategoryRevenue) * 100 : 0.0;
    final qty = categoryQtyMap[catName] ?? 0;

    list.add(CategoryRevenueShare(
      categoryName: catName,
      revenue: rev,
      percentage: pct,
      quantitySold: qty,
    ));
  }

  // Sắp xếp danh mục theo doanh thu giảm dần
  list.sort((a, b) => b.revenue.compareTo(a.revenue));

  return AsyncValue.data(list);
});

// =============================================================================
// 6. Smart Stock & Inventory Alert Summary Provider (R3)
// =============================================================================

/// Provider tính toán tổng hợp cảnh báo tồn kho (Hết hàng, Sắp hết hàng, Giá trị kho)
/// Lọc chính xác theo chi nhánh được chọn (selectedBranches)
final stockAlertSummaryProvider =
    Provider.autoDispose<AsyncValue<StockAlertSummary>>((ref) {
  final productsAsync = ref.watch(allStoresProductsProvider);
  final selectedBranches = ref.watch(selectedBranchesProvider);

  return productsAsync.whenData((products) {
    int outOfStock = 0;
    int lowStock = 0;
    int totalItems = 0;
    double totalInventoryCost = 0.0;
    final List<String> outOfStockIds = [];
    final List<String> lowStockIds = [];

    // Nhóm sản phẩm theo ID duy nhất (loại bỏ trùng lặp giữa các store)
    final uniqueProductsMap = <String, Product>{};
    for (final p in products) {
      uniqueProductsMap[p.id] = p;
    }

    for (final product in uniqueProductsMap.values) {
      // Tính tồn kho của sản phẩm đối với các chi nhánh được chọn
      int stock = 0;
      if (product.branchStocks.isNotEmpty) {
        for (final branchId in selectedBranches) {
          stock += product.branchStocks[branchId] ?? 0;
        }
      } else {
        stock = product.stock;
      }

      totalItems += stock;
      totalInventoryCost += stock * product.costPrice;

      if (stock == 0) {
        outOfStock++;
        outOfStockIds.add(product.id);
      } else if (stock > 0 && stock <= 5) {
        lowStock++;
        lowStockIds.add(product.id);
      }
    }

    return StockAlertSummary(
      outOfStockCount: outOfStock,
      lowStockCount: lowStock,
      totalItemCount: totalItems,
      totalInventoryCost: totalInventoryCost,
      outOfStockProductIds: outOfStockIds,
      lowStockProductIds: lowStockIds,
    );
  });
});

// =============================================================================
// 7. Top Rankings Providers (R5)
// =============================================================================

/// Tiêu chí sắp xếp bảng xếp hạng sản phẩm bán chạy
enum TopProductsSortBy {
  revenue, // Doanh thu
  quantity, // Số lượng
}

final topSellingSortByProvider =
    StateProvider.autoDispose<TopProductsSortBy>((ref) => TopProductsSortBy.revenue);

final topSellingLimitProvider = StateProvider.autoDispose<int>((ref) => 5);

/// Provider Top sản phẩm bán chạy nhất trong kỳ lọc
final topSellingProductsRankingProvider =
    Provider.autoDispose<AsyncValue<List<ProductRankingItem>>>((ref) {
  final currentRange = ref.watch(overviewCurrentDateRangeProvider);
  final ordersAsync =
      ref.watch(allBranchesOrdersByDateRangeProvider(currentRange));
  final productsAsync = ref.watch(allStoresProductsProvider);
  final sortBy = ref.watch(topSellingSortByProvider);
  final limit = ref.watch(topSellingLimitProvider);

  if (ordersAsync.isLoading || productsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (ordersAsync.hasError) {
    return AsyncValue.error(ordersAsync.error!, ordersAsync.stackTrace!);
  }
  if (productsAsync.hasError) {
    return AsyncValue.error(productsAsync.error!, productsAsync.stackTrace!);
  }

  final orders = ordersAsync.value ?? [];
  final products = productsAsync.value ?? [];

  // Tạo map thông tin sản phẩm để lấy category & hình ảnh
  final productDetailsMap = <String, Product>{};
  for (final p in products) {
    productDetailsMap[p.id] = p;
  }

  final Map<String, _AggregatedProduct> itemMap = {};

  final completedOrders = orders.where((o) => o.status == 'completed');
  for (final order in completedOrders) {
    for (final item in order.items) {
      final existing = itemMap[item.productId];
      final itemRev = item.price * item.quantity;

      if (existing != null) {
        existing.quantity += item.quantity;
        existing.revenue += itemRev;
      } else {
        itemMap[item.productId] = _AggregatedProduct(
          productId: item.productId,
          productName: item.productName,
          quantity: item.quantity,
          revenue: itemRev,
        );
      }
    }
  }

  final aggregatedList = itemMap.values.map((agg) {
    final prod = productDetailsMap[agg.productId];
    return ProductRankingItem(
      productId: agg.productId,
      productName: prod?.name ?? agg.productName,
      quantity: agg.quantity,
      revenue: agg.revenue,
      categoryName: prod?.category,
      imageUrl: prod?.imageUrl,
    );
  }).toList();

  // Sắp xếp theo tiêu chí được chọn
  if (sortBy == TopProductsSortBy.revenue) {
    aggregatedList.sort((a, b) => b.revenue.compareTo(a.revenue));
  } else {
    aggregatedList.sort((a, b) => b.quantity.compareTo(a.quantity));
  }

  return AsyncValue.data(aggregatedList.take(limit).toList());
});

class _AggregatedProduct {
  final String productId;
  final String productName;
  int quantity;
  double revenue;

  _AggregatedProduct({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.revenue,
  });
}

final topCustomersLimitProvider = StateProvider.autoDispose<int>((ref) => 5);

/// Provider Top khách hàng mua nhiều nhất trong kỳ lọc
final topCustomersRankingProvider =
    Provider.autoDispose<AsyncValue<List<CustomerRankingItem>>>((ref) {
  final currentRange = ref.watch(overviewCurrentDateRangeProvider);
  final ordersAsync =
      ref.watch(allBranchesOrdersByDateRangeProvider(currentRange));
  final customersAsync = ref.watch(customerListNotifierProvider);
  final limit = ref.watch(topCustomersLimitProvider);

  if (ordersAsync.isLoading || customersAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (ordersAsync.hasError) {
    return AsyncValue.error(ordersAsync.error!, ordersAsync.stackTrace!);
  }
  if (customersAsync.hasError) {
    return AsyncValue.error(customersAsync.error!, customersAsync.stackTrace!);
  }

  final orders = ordersAsync.value ?? [];
  final customers = customersAsync.value ?? [];

  final customerMap = <String, Customer>{};
  for (final c in customers) {
    customerMap[c.id] = c;
  }

  final customerStats = <String, _CustomerStat>{};

  final completedOrders = orders.where((o) => o.status == 'completed');
  for (final order in completedOrders) {
    final custId = order.customerId;
    if (custId.isEmpty) continue; // Bỏ qua đơn khách vãng lai không có ID

    final stat = customerStats[custId];
    if (stat != null) {
      stat.totalSpent += order.total;
      stat.orderCount += 1;
    } else {
      customerStats[custId] = _CustomerStat(
        customerId: custId,
        totalSpent: order.total,
        orderCount: 1,
      );
    }
  }

  final rankingList = customerStats.values.map((stat) {
    final cust = customerMap[stat.customerId];
    return CustomerRankingItem(
      customerId: stat.customerId,
      customerName: cust?.name ?? 'Khách hàng #${stat.customerId}',
      totalSpent: stat.totalSpent,
      orderCount: stat.orderCount,
      phoneNumber: cust?.phone,
    );
  }).toList();

  // Sắp xếp theo tổng tiền mua giảm dần
  rankingList.sort((a, b) => b.totalSpent.compareTo(a.totalSpent));

  return AsyncValue.data(rankingList.take(limit).toList());
});

class _CustomerStat {
  final String customerId;
  double totalSpent;
  int orderCount;

  _CustomerStat({
    required this.customerId,
    required this.totalSpent,
    required this.orderCount,
  });
}

// =============================================================================
// 8. Recent Activity Feed Provider (R6)
// =============================================================================

/// Provider danh sách 5 đơn hàng / giao dịch phát sinh gần nhất
final recentOrdersFeedProvider =
    Provider.autoDispose<AsyncValue<List<Order>>>((ref) {
  final currentRange = ref.watch(overviewCurrentDateRangeProvider);
  final ordersAsync =
      ref.watch(allBranchesOrdersByDateRangeProvider(currentRange));

  return ordersAsync.whenData((orders) {
    final sorted = List<Order>.from(orders)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(5).toList();
  });
});

// =============================================================================
// 9. Smart Adaptive Revenue Chart Aggregation (R3)
// =============================================================================

/// Xác định chế độ gom nhóm biểu đồ doanh thu thông minh dựa vào độ dài khoảng thời gian lọc (R3)
/// - <= 1 ngày: Hourly (24 mốc giờ trong ngày)
/// - 2..31 ngày: Daily (dd/MM)
/// - 32..60 ngày: Weekly (T1 Th08, T2 Th08...)
/// - > 60 ngày: Monthly (Th06, Th07, Th08...)
ChartAggregationInterval getChartAggregationInterval(DateTimeRange range) {
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  final days = end.difference(start).inDays + 1;

  if (days <= 1) return ChartAggregationInterval.hourly;
  if (days <= 31) return ChartAggregationInterval.daily;
  if (days <= 60) return ChartAggregationInterval.weekly;
  return ChartAggregationInterval.monthly;
}

/// Gom nhóm danh sách RevenueReport theo chu kỳ thích ứng (Daily / Weekly / Monthly)
/// và tính tổng hợp hợp nhất doanh thu, chi phí, lợi nhuận, đơn hàng và phân rã chi nhánh.
List<RevenueChartBucket> aggregateRevenueReports({
  required List<RevenueReport> dailyReports,
  required DateTimeRange range,
}) {
  if (dailyReports.isEmpty) return const [];

  final interval = getChartAggregationInterval(range);
  if (interval == ChartAggregationInterval.hourly) {
    return const []; // Chế độ hourly được xử lý riêng bởi hourlyRevenueListProvider
  }

  if (interval == ChartAggregationInterval.daily) {
    return dailyReports.map((report) {
      final date = report.date;
      final label = DateFormat('dd/MM').format(date);
      final fullLabel = DateFormat('dd/MM/yyyy').format(date);
      return RevenueChartBucket(
        label: label,
        fullLabel: fullLabel,
        startDate: date,
        endDate: date,
        totalRevenue: report.totalRevenue,
        totalCost: report.totalCost,
        profit: report.profit,
        totalOrders: report.totalOrders,
        totalItemsSold: report.totalItemsSold,
        storeRevenues: report.storeRevenues,
      );
    }).toList();
  }

  final Map<String, List<RevenueReport>> groupedMap = {};
  final Map<String, ({String label, String fullLabel, DateTime start, DateTime end})> metaMap = {};

  for (final report in dailyReports) {
    final date = report.date;
    final String key;
    final String label;
    final String fullLabel;

    if (interval == ChartAggregationInterval.weekly) {
      final weekNum = ((date.day - 1) ~/ 7) + 1;
      final monthStr = date.month.toString().padLeft(2, '0');
      key = '${date.year}-$monthStr-W$weekNum';
      label = 'T$weekNum Th$monthStr';
      fullLabel = 'Tuần $weekNum - Tháng $monthStr/${date.year}';
    } else {
      // Monthly
      final monthStr = date.month.toString().padLeft(2, '0');
      key = '${date.year}-$monthStr';
      label = 'Th$monthStr';
      fullLabel = 'Tháng $monthStr/${date.year}';
    }

    groupedMap.putIfAbsent(key, () => []).add(report);
    if (!metaMap.containsKey(key)) {
      metaMap[key] = (label: label, fullLabel: fullLabel, start: date, end: date);
    } else {
      final existing = metaMap[key]!;
      final newEnd = date.isAfter(existing.end) ? date : existing.end;
      final newStart = date.isBefore(existing.start) ? date : existing.start;
      metaMap[key] = (label: existing.label, fullLabel: existing.fullLabel, start: newStart, end: newEnd);
    }
  }

  final List<RevenueChartBucket> buckets = [];

  for (final entry in groupedMap.entries) {
    final key = entry.key;
    final reportsInBucket = entry.value;
    final meta = metaMap[key]!;

    double totalRevenue = 0.0;
    double totalCost = 0.0;
    double totalProfit = 0.0;
    int totalOrders = 0;
    int totalItemsSold = 0;
    final Map<String, double> mergedStoreRevenues = {};

    for (final r in reportsInBucket) {
      totalRevenue += r.totalRevenue;
      totalCost += r.totalCost;
      totalProfit += r.profit;
      totalOrders += r.totalOrders;
      totalItemsSold += r.totalItemsSold;

      r.storeRevenues.forEach((storeId, rev) {
        mergedStoreRevenues[storeId] = (mergedStoreRevenues[storeId] ?? 0.0) + rev;
      });
    }

    buckets.add(RevenueChartBucket(
      label: meta.label,
      fullLabel: meta.fullLabel,
      startDate: meta.start,
      endDate: meta.end,
      totalRevenue: totalRevenue,
      totalCost: totalCost,
      profit: totalProfit,
      totalOrders: totalOrders,
      totalItemsSold: totalItemsSold,
      storeRevenues: mergedStoreRevenues,
    ));
  }

  buckets.sort((a, b) => a.startDate.compareTo(b.startDate));
  return buckets;
}

/// Provider danh sách các RevenueChartBucket đã gom nhóm thông minh theo khoảng thời gian lọc (R3)
final aggregatedRevenueChartBucketsProvider =
    Provider.autoDispose<AsyncValue<List<RevenueChartBucket>>>((ref) {
  final currentRange = ref.watch(overviewCurrentDateRangeProvider);
  final summaryAsync = ref.watch(revenueByDateRangeProvider(currentRange));

  return summaryAsync.whenData((summary) {
    return aggregateRevenueReports(
      dailyReports: summary.dailyReports,
      range: currentRange,
    );
  });
});

