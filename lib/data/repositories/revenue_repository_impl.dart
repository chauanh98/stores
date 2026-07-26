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

    // Lấy inventory transactions (dùng fetchAll() = .get() thay vì watchAll().first)
    final inventoryTransactions = await _inventoryDs.fetchAll();

    // Lấy products
    final products = await _productDs.fetchAll();

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

    // Dùng fetchAll() = .get() thay vì watchAll().first để tránh tạo listener rồi cancel
    final inventoryTransactions = await _inventoryDs.fetchAll();
    final products = await _productDs.fetchAll();

    return calculateRevenueSummary(
      orders: orders,
      inventoryTransactions: inventoryTransactions,
      products: products,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Tính toán báo cáo doanh thu tổng hợp từ dữ liệu có sẵn
  RevenueSummary calculateRevenueSummary({
    required List<Map<String, dynamic>> orders,
    required List<Map> inventoryTransactions,
    required List<Map> products,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    // Tính toán cho từng ngày
    final dailyReports = <RevenueReport>[];
    DateTime currentDate =
        DateTime(startDate.year, startDate.month, startDate.day);
    final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);

    while (!currentDate.isAfter(endDateOnly)) {
      final dayOrders = orders.where((order) {
        final createdAtStr = order['createdAt']?.toString();
        if (createdAtStr == null) return false;
        final orderDate = DateTime.tryParse(createdAtStr);
        if (orderDate == null) return false;
        return orderDate.year == currentDate.year &&
            orderDate.month == currentDate.month &&
            orderDate.day == currentDate.day;
      }).toList();

      final dailyReport = calculateRevenueReport(
        orders: dayOrders,
        inventoryTransactions: inventoryTransactions,
        products: products,
        date: currentDate,
      );

      dailyReports.add(dailyReport);
      currentDate = currentDate.add(const Duration(days: 1));
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
  }) {
    final productRevenues = <ProductRevenue>[];
    double totalRevenue = 0.0;
    double totalCost = 0.0;
    int totalItemsSold = 0;

    // Tạo map products để lookup nhanh
    final productMap = <String, Map>{};
    for (final product in products) {
      productMap[product['id']] = product;
    }

    // Tạo inventory transactions với error handling và lọc theo ngày
    final inventoryTxs = <InventoryTransaction>[];
    for (final m in inventoryTransactions) {
      try {
        final model = InventoryTransactionModel.fromMap(m);
        final product = productMap[model.productId];
        final fallbackPrice =
            product != null ? _toDouble(product['costPrice']) : null;

        inventoryTxs.add(InventoryTransaction(
          id: model.id,
          productId: model.productId,
          type: model.type == 'import'
              ? TransactionType.import
              : TransactionType.export,
          quantity: model.quantity,
          date: model.date,
          note: model.note,
          importPrice: model.importPrice ?? fallbackPrice,
        ));
      } catch (e) {
        print('Error parsing inventory transaction: $e');
        continue;
      }
    }

    // Khởi tạo FIFO Calculator với inventory tracking
    FifoCalculator.resetInventoryTracker();
    FifoCalculator.initializeInventoryTracker(inventoryTxs);

    // Sắp xếp orders theo thời gian để đảm bảo FIFO chính xác
    final sortedOrders = List<Map<String, dynamic>>.from(orders);
    sortedOrders.sort((a, b) {
      final dateA =
          DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime(1970);
      final dateB =
          DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime(1970);
      return dateA.compareTo(dateB);
    });

    // Tính toán cho từng order theo thứ tự thời gian

    // Tính toán cho từng order theo thứ tự thời gian
    for (final orderMap in sortedOrders) {
      try {
        final orderModel = OrderModel.fromMap(orderMap);
        totalRevenue += orderModel.total;

        for (final itemModel in orderModel.items) {
          final product = productMap[itemModel.productId];
          if (product == null) {
            continue;
          }

          // Sử dụng giá bán thực tế từ OrderItem thay vì giá hiện tại của sản phẩm
          // Fallback về giá hiện tại nếu OrderItem cũ không có trường price
          final actualPrice =
              itemModel.price ?? _toDouble(product['price']) ?? 0.0;

          // Tính cost theo FIFO với inventory tracking
          final cost = FifoCalculator.calculateCostForSale(
            productId: itemModel.productId,
            quantity: itemModel.quantity,
            saleDate: orderModel.createdAt,
          );

          totalCost += cost;
          totalItemsSold += itemModel.quantity;

          // Cập nhật product revenue
          final existingIndex = productRevenues
              .indexWhere((pr) => pr.productId == itemModel.productId);
          if (existingIndex >= 0) {
            final existing = productRevenues[existingIndex];
            final newRevenue = itemModel.quantity * actualPrice;
            productRevenues[existingIndex] = ProductRevenue(
              productId: existing.productId,
              productName: existing.productName,
              quantitySold: existing.quantitySold + itemModel.quantity,
              revenue: existing.revenue + newRevenue,
              cost: existing.cost + cost,
              profit: (existing.revenue + newRevenue) - (existing.cost + cost),
              profitMargin: FifoCalculator.calculateProfitMargin(
                existing.revenue + newRevenue,
                existing.cost + cost,
              ),
            );
          } else {
            final revenue = itemModel.quantity * actualPrice;
            productRevenues.add(ProductRevenue(
              productId: itemModel.productId,
              productName: product['name'] ?? 'Unknown Product',
              quantitySold: itemModel.quantity,
              revenue: revenue,
              cost: cost,
              profit: revenue - cost,
              profitMargin: FifoCalculator.calculateProfitMargin(revenue, cost),
            ));
          }
        }
      } catch (e) {
        print('Error processing order: $e');
        continue;
      }
    }

    return RevenueReport(
      date: date,
      totalRevenue: totalRevenue,
      totalCost: totalCost,
      profit: totalRevenue - totalCost,
      totalOrders: orders.length,
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
