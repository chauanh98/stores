import 'package:flutter/foundation.dart';

import '../../core/services/fifo_calculator.dart';
import '../../domain/entities/inventory_transaction.dart';
import '../../domain/entities/revenue_report.dart';
import '../../domain/entities/transaction_type.dart';
import '../datasources/firebase/inventory_remote_data_source.dart';
import '../datasources/firebase/order_remote_data_source.dart';
import '../datasources/firebase/product_remote_data_source.dart';
import '../models/inventory_transaction_model.dart';
import '../models/order_model.dart';

class RevenueRepositoryImpl {
  final OrderRemoteDataSource _orderDs;
  final InventoryRemoteDataSource _inventoryDs;
  final ProductRemoteDataSource _productDs;

  RevenueRepositoryImpl(this._orderDs, this._inventoryDs, this._productDs);

  /// Lấy báo cáo doanh thu theo ngày
  Future<RevenueReport> getRevenueByDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

    // Lấy orders trong ngày
    final ordersStream = _orderDs.watchByDateRange(startOfDay, endOfDay);
    final orders = await ordersStream.first;

    // Lấy products trước để biết nhu cầu lô FIFO của từng sản phẩm
    final products = await _productDs.fetchAll();

    // Lấy inventory transactions date-bounded thay vì fetchAll() không giới hạn
    List<Map> inventoryTransactions;
    try {
      inventoryTransactions = await _fetchLots(endOfDay, orders, products);
    } catch (_) {
      try {
        inventoryTransactions =
            await _inventoryDs.fetchImportsByDateRange(startOfDay, endOfDay);
      } catch (_) {
        inventoryTransactions = await _inventoryDs.fetchAll();
      }
    }

    return calculateRevenueReport(
      orders: orders,
      inventoryTransactions: inventoryTransactions,
      products: products,
      date: date,
    );
  }

  /// Lấy báo cáo doanh thu theo khoảng thời gian
  Future<RevenueSummary> getRevenueByDateRange(
      DateTime startDate, DateTime endDate) async {
    final startOfRange =
        DateTime(startDate.year, startDate.month, startDate.day);
    final endOfRange =
        DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

    final ordersStream = _orderDs.watchByDateRange(startOfRange, endOfRange);
    final orders = await ordersStream.first;

    final products = await _productDs.fetchAll();

    // Lấy inventory transactions date-bounded thay vì fetchAll() không giới hạn
    List<Map> inventoryTransactions;
    try {
      inventoryTransactions = await _fetchLots(endOfRange, orders, products);
    } catch (_) {
      try {
        inventoryTransactions = await _inventoryDs.fetchImportsByDateRange(
            startOfRange, endOfRange);
      } catch (_) {
        inventoryTransactions = await _inventoryDs.fetchAll();
      }
    }

    return calculateRevenueSummary(
      orders: orders,
      inventoryTransactions: inventoryTransactions,
      products: products,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Lấy lô nhập phục vụ FIFO: phân trang lùi có chặn, dừng khi đã đủ lô cho các
  /// sản phẩm trong đơn (nhu cầu = số bán trong kỳ + tồn hiện tại). Nếu nguồn dữ
  /// liệu không hỗ trợ thì dùng truy vấn cũ [fetchTransactionsUpToDate].
  Future<List<Map>> _fetchLots(DateTime end, List<Map<String, dynamic>> orders,
      List<Map> products) async {
    final needed = <String, int>{};
    for (final o in orders) {
      try {
        final m = OrderModel.fromMap(o);
        if (m.isCancelled || m.isDraft || m.isReturned) continue;
        for (final it in m.items) {
          if (it.activeQuantity > 0) {
            needed[it.productId] =
                (needed[it.productId] ?? 0) + it.activeQuantity;
          }
        }
      } catch (_) {}
    }
    for (final p in products) {
      final id = p['id']?.toString();
      if (id == null || !needed.containsKey(id)) continue;
      final bs = p['branchStocks'];
      var stock = 0;
      if (bs is Map) {
        for (final v in bs.values) {
          if (v is num && v > 0) stock += v.toInt();
        }
      } else if (p['stock'] is num) {
        stock = (p['stock'] as num).toInt();
      }
      needed[id] = needed[id]! + stock;
    }
    try {
      return await _inventoryDs.fetchLotTransactionsUpToDate(end,
          neededQty: needed);
    } catch (_) {
      return _inventoryDs.fetchTransactionsUpToDate(end);
    }
  }

  /// Helper phân tích inventory transactions
  List<InventoryTransaction> _parseInventoryTransactions(
    List<Map> inventoryTransactions,
    Map<String, Map> productMap,
  ) {
    final inventoryTxs = <InventoryTransaction>[];
    for (final m in inventoryTransactions) {
      try {
        final model = InventoryTransactionModel.fromMap(m);
        // POS ghi 1 giao dịch `export_<ms>_<productId>` cho MỖI lần bán. Chính
        // đơn bán đã tiêu thụ lô khi tính giá vốn (calculateCostForSale) nên
        // phải bỏ giao dịch này, nếu không lô bị trừ 2 lần và các đơn sau rơi về
        // giá vốn dự phòng => sai giá vốn / lợi nhuận.
        if (model.toTransactionType() == TransactionType.export &&
            model.id.startsWith('export_')) {
          continue;
        }
        final product = productMap[model.productId];
        final fallbackPrice =
            product != null ? _toDouble(product['costPrice']) : null;

        inventoryTxs.add(InventoryTransaction(
          id: model.id,
          productId: model.productId,
          type: model.toTransactionType(),
          quantity: model.quantity,
          date: model.date,
          note: model.note,
          importPrice: model.importPrice ?? fallbackPrice,
          createdBy: model.createdBy,
          createdByName: model.createdByName,
          storeId: model.storeId,
          isAuditNegative: model.isAuditNegative,
          auditDifference: model.auditDifference,
        ));
      } catch (e) {
        debugPrint('Error parsing inventory transaction: $e');
        continue;
      }
    }
    return inventoryTxs;
  }

  /// Tính toán báo cáo doanh thu tổng hợp từ dữ liệu có sẵn
  /// Sử dụng 1 FifoCalculator instance duy nhất chạy xuyên suốt các ngày
  /// để tránh lỗi reset lot tồn kho giữa các ngày (Multi-day lot depletion bug)
  RevenueSummary calculateRevenueSummary({
    required List<Map<String, dynamic>> orders,
    required List<Map> inventoryTransactions,
    required List<Map> products,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    // Tạo map products để lookup nhanh
    final productMap = <String, Map>{};
    for (final product in products) {
      if (product['id'] != null) {
        productMap[product['id'].toString()] = product;
      }
    }

    final inventoryTxs =
        _parseInventoryTransactions(inventoryTransactions, productMap);

    // Khởi tạo một instance FifoCalculator duy nhất cho toàn bộ khoảng thời gian
    final fifo = FifoCalculator(inventoryTxs, _orderDs.storeId);

    // Sắp xếp toàn bộ orders theo thời gian tăng dần
    final allSortedOrders = List<Map<String, dynamic>>.from(orders);
    allSortedOrders.sort((a, b) {
      final dateA =
          DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime(1970);
      final dateB =
          DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime(1970);
      return dateA.compareTo(dateB);
    });

    // Gom đơn theo NGÀY LỊCH CỤC BỘ trong 1 lượt (O(n)) thay vì lọc lại toàn bộ
    // danh sách cho từng ngày (O(ngày x đơn)). Mốc thời gian dạng UTC ('Z' /
    // offset) phải đổi sang giờ máy trước khi lấy ngày, giống bộ lọc ở
    // OrderRemoteDataSource.watchByDateRange; nếu không đơn 'Z' bị xếp sai ngày
    // (và biến mất khỏi báo cáo 1 ngày) khi múi giờ khác UTC.
    final ordersByDay = <DateTime, List<Map<String, dynamic>>>{};
    for (final order in allSortedOrders) {
      final createdAtStr =
          (order['orderDate'] ?? order['createdAt'] ?? order['date'])
              ?.toString();
      if (createdAtStr == null) continue;
      final parsed = DateTime.tryParse(createdAtStr);
      if (parsed == null) continue;
      final local = parsed.isUtc ? parsed.toLocal() : parsed;
      ordersByDay
          .putIfAbsent(DateTime(local.year, local.month, local.day),
              () => <Map<String, dynamic>>[])
          .add(order);
    }

    final dailyReports = <RevenueReport>[];
    DateTime currentDate =
        DateTime(startDate.year, startDate.month, startDate.day);
    final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);

    while (!currentDate.isAfter(endDateOnly)) {
      final dayOrders = ordersByDay[currentDate] ?? const [];

      final dailyReport = calculateRevenueReport(
        orders: List<Map<String, dynamic>>.of(dayOrders),
        inventoryTransactions: inventoryTransactions,
        products: products,
        date: currentDate,
        fifoCalculator: fifo,
      );

      dailyReports.add(dailyReport);
      currentDate =
          DateTime(currentDate.year, currentDate.month, currentDate.day + 1);
    }

    // Tính tổng kết
    final totalRevenue =
        dailyReports.fold(0.0, (sum, report) => sum + report.totalRevenue);
    final totalCost =
        dailyReports.fold(0.0, (sum, report) => sum + report.totalCost);
    final totalOrders =
        dailyReports.fold(0, (sum, report) => sum + report.totalOrders);
    final totalItemsSold =
        dailyReports.fold(0, (sum, report) => sum + report.totalItemsSold);

    return RevenueSummary(
      startDate: startDate,
      endDate: endDate,
      totalRevenue: totalRevenue,
      totalCost: totalCost,
      totalProfit: totalRevenue - totalCost,
      totalOrders: totalOrders,
      totalItemsSold: totalItemsSold,
      dailyReports: dailyReports,
    );
  }

  RevenueReport calculateRevenueReport({
    required List<Map<String, dynamic>> orders,
    required List<Map> inventoryTransactions,
    required List<Map> products,
    required DateTime date,
    FifoCalculator? fifoCalculator,
  }) {
    final productRevenues = <ProductRevenue>[];
    double totalRevenue = 0.0;
    double totalCost = 0.0;
    int totalItemsSold = 0;

    // Tạo map products để lookup nhanh
    final productMap = <String, Map>{};
    for (final product in products) {
      if (product['id'] != null) {
        productMap[product['id'].toString()] = product;
      }
    }

    // Nếu không truyền FifoCalculator từ bên ngoài vào thì tạo instance mới
    final FifoCalculator fifo;
    if (fifoCalculator != null) {
      fifo = fifoCalculator;
    } else {
      final inventoryTxs =
          _parseInventoryTransactions(inventoryTransactions, productMap);
      fifo = FifoCalculator(inventoryTxs, _orderDs.storeId);
    }

    // Sắp xếp orders theo thời gian tăng dần
    final sortedOrders = List<Map<String, dynamic>>.from(orders);
    sortedOrders.sort((a, b) {
      final dateA =
          DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime(1970);
      final dateB =
          DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime(1970);
      return dateA.compareTo(dateB);
    });

    int totalValidOrders = 0;
    for (final orderMap in sortedOrders) {
      try {
        final orderModel = OrderModel.fromMap(orderMap);
        if (orderModel.isCancelled ||
            orderModel.isDraft ||
            orderModel.isReturned ||
            orderModel.allItemsReturned) {
          continue;
        }
        totalValidOrders++;
        totalRevenue += orderModel.netPayable;

        for (final itemModel in orderModel.items) {
          final activeQty = itemModel.activeQuantity;
          if (activeQty <= 0) continue;

          final product = productMap[itemModel.productId];

          // Giá bán thực tế từ item hoặc giá niêm yết sản phẩm
          final actualPrice = itemModel.price != 0.0
              ? itemModel.price
              : (product != null ? (_toDouble(product['price']) ?? 0.0) : 0.0);

          // Giá vốn dự phòng (fallback cost price) từ costPrice của sản phẩm
          final fallbackCostPrice = product != null
              ? (_toDouble(product['costPrice']) ??
                  (_toDouble(product['price']) != null
                      ? _toDouble(product['price'])! * 0.7
                      : 0.0))
              : 0.0;

          // Tính cost theo FIFO instance
          final cost = fifo.calculateCostForSale(
            productId: itemModel.productId,
            quantity: activeQty,
            saleDate: orderModel.createdAt,
            storeId: _orderDs.storeId,
            fallbackCostPrice: fallbackCostPrice,
          );

          totalCost += cost;
          totalItemsSold += activeQty;

          // Cập nhật product revenue
          final existingIndex = productRevenues
              .indexWhere((pr) => pr.productId == itemModel.productId);
          if (existingIndex >= 0) {
            final existing = productRevenues[existingIndex];
            final newRevenue = activeQty * actualPrice;
            productRevenues[existingIndex] = ProductRevenue(
              productId: existing.productId,
              productName: existing.productName,
              quantitySold: existing.quantitySold + activeQty,
              revenue: existing.revenue + newRevenue,
              cost: existing.cost + cost,
              profit: (existing.revenue + newRevenue) - (existing.cost + cost),
              profitMargin: FifoCalculator.calculateProfitMargin(
                existing.revenue + newRevenue,
                existing.cost + cost,
              ),
            );
          } else {
            final revenue = activeQty * actualPrice;
            productRevenues.add(ProductRevenue(
              productId: itemModel.productId,
              productName: product != null
                  ? (product['name'] ?? 'Unknown Product')
                  : itemModel.productName,
              quantitySold: activeQty,
              revenue: revenue,
              cost: cost,
              profit: revenue - cost,
              profitMargin: FifoCalculator.calculateProfitMargin(revenue, cost),
            ));
          }
        }
      } catch (e) {
        debugPrint('Error processing order: $e');
        continue;
      }
    }

    return RevenueReport(
      date: date,
      totalRevenue: totalRevenue,
      totalCost: totalCost,
      profit: totalRevenue - totalCost,
      totalOrders: totalValidOrders,
      totalItemsSold: totalItemsSold,
      productRevenues: productRevenues,
      storeRevenues: {
        _orderDs.storeId: totalRevenue,
      },
    );
  }

  /// Helper method để convert value thành double safely
  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
