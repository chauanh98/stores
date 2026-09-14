library overview_kpis;

/// Domain entities for Overview KPI metrics, charts, breakdowns, stock alerts, and rankings.
/// Pure Dart: No Flutter UI, Firebase, or Riverpod dependencies.

/// Tổng hợp các chỉ số kinh doanh chính (KPIs) và tăng trưởng so với kỳ liền trước
class OverviewKPIs {
  final double netRevenue;
  final int orderCount;
  final double grossProfit;
  final double returnGoodsValue;
  final double aov; // Average Order Value = netRevenue / orderCount
  final double revenueGrowthPercent; // vs prior period
  final double orderCountGrowthPercent;
  final double profitGrowthPercent;
  final double aovGrowthPercent;
  final double customerDebt;
  final double previousRevenue;
  final int previousOrders;
  final double previousProfit;
  final double previousAov;

  const OverviewKPIs({
    required this.netRevenue,
    required this.orderCount,
    required this.grossProfit,
    this.returnGoodsValue = 0.0,
    required this.aov,
    this.revenueGrowthPercent = 0.0,
    this.orderCountGrowthPercent = 0.0,
    this.profitGrowthPercent = 0.0,
    this.aovGrowthPercent = 0.0,
    this.customerDebt = 0.0,
    this.previousRevenue = 0.0,
    this.previousOrders = 0,
    this.previousProfit = 0.0,
    this.previousAov = 0.0,
  });

  /// Tỷ suất lợi nhuận gộp (%)
  double get grossMarginPercent =>
      netRevenue > 0 ? (grossProfit / netRevenue) * 100 : 0.0;

  /// Doanh thu có tăng trưởng dương không
  bool get isRevenueGrowthPositive => revenueGrowthPercent >= 0;

  /// Lợi nhuận có tăng trưởng dương không
  bool get isProfitGrowthPositive => profitGrowthPercent >= 0;

  /// Số đơn hàng có tăng trưởng dương không
  bool get isOrderCountGrowthPositive => orderCountGrowthPercent >= 0;

  /// AOV có tăng trưởng dương không
  bool get isAovGrowthPositive => aovGrowthPercent >= 0;

  static const empty = OverviewKPIs(
    netRevenue: 0.0,
    orderCount: 0,
    grossProfit: 0.0,
    returnGoodsValue: 0.0,
    aov: 0.0,
    revenueGrowthPercent: 0.0,
    orderCountGrowthPercent: 0.0,
    profitGrowthPercent: 0.0,
    aovGrowthPercent: 0.0,
    customerDebt: 0.0,
    previousRevenue: 0.0,
    previousOrders: 0,
    previousProfit: 0.0,
    previousAov: 0.0,
  );
}

/// Dữ liệu doanh thu theo từng khung giờ (0..23) phục vụ phân tích giờ cao điểm
class HourlyRevenueData {
  final int hour; // 0..23
  final double revenue;
  final int orderCount;
  final Map<String, double> branchRevenue;

  const HourlyRevenueData({
    required this.hour,
    required this.revenue,
    required this.orderCount,
    this.branchRevenue = const {},
  });

  /// Nhãn hiển thị giờ (ví dụ: '08:00', '14:00')
  String get hourLabel => '${hour.toString().padLeft(2, '0')}:00';

  /// Nhãn ngắn (ví dụ: '8h', '14h')
  String get shortLabel => '${hour}h';
}

/// Cơ cấu doanh thu theo phương thức thanh toán
class PaymentBreakdown {
  final double cashAmount;
  final double transferAmount;
  final double debtAmount;
  final double totalAmount;

  const PaymentBreakdown({
    required this.cashAmount,
    required this.transferAmount,
    required this.debtAmount,
    required this.totalAmount,
  });

  double get cashPercentage =>
      totalAmount > 0 ? (cashAmount / totalAmount) * 100 : 0.0;

  double get transferPercentage =>
      totalAmount > 0 ? (transferAmount / totalAmount) * 100 : 0.0;

  double get debtPercentage =>
      totalAmount > 0 ? (debtAmount / totalAmount) * 100 : 0.0;

  static const empty = PaymentBreakdown(
    cashAmount: 0.0,
    transferAmount: 0.0,
    debtAmount: 0.0,
    totalAmount: 0.0,
  );
}

/// Tỷ trọng doanh thu theo từng nhóm hàng / danh mục
class CategoryRevenueShare {
  final String categoryName;
  final double revenue;
  final double percentage;
  final int quantitySold;

  const CategoryRevenueShare({
    required this.categoryName,
    required this.revenue,
    required this.percentage,
    this.quantitySold = 0,
  });
}

/// Thống kê cảnh báo tồn kho và định mức kho
class StockAlertSummary {
  final int outOfStockCount; // stock == 0
  final int lowStockCount; // 0 < stock <= minStock (5)
  final int totalItemCount; // Tổng số sản phẩm trong kho
  final double totalInventoryCost; // Tổng giá trị tồn kho theo giá vốn
  final List<String> outOfStockProductIds;
  final List<String> lowStockProductIds;

  const StockAlertSummary({
    required this.outOfStockCount,
    required this.lowStockCount,
    required this.totalItemCount,
    required this.totalInventoryCost,
    this.outOfStockProductIds = const [],
    this.lowStockProductIds = const [],
  });

  static const empty = StockAlertSummary(
    outOfStockCount: 0,
    lowStockCount: 0,
    totalItemCount: 0,
    totalInventoryCost: 0.0,
    outOfStockProductIds: [],
    lowStockProductIds: [],
  );
}

/// Xếp hạng sản phẩm bán chạy (theo doanh thu hoặc số lượng)
class ProductRankingItem {
  final String productId;
  final String productName;
  final int quantity;
  final double revenue;
  final String? categoryName;
  final String? imageUrl;

  const ProductRankingItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.revenue,
    this.categoryName,
    this.imageUrl,
  });
}

/// Xếp hạng khách hàng mua nhiều nhất / thân thiết nhất
class CustomerRankingItem {
  final String customerId;
  final String customerName;
  final double totalSpent;
  final int orderCount;
  final String? phoneNumber;

  const CustomerRankingItem({
    required this.customerId,
    required this.customerName,
    required this.totalSpent,
    required this.orderCount,
    this.phoneNumber,
  });
}

/// Chu kỳ gom nhóm biểu đồ doanh thu theo độ dài khoảng thời gian lọc (R3)
enum ChartAggregationInterval {
  hourly,
  daily,
  weekly,
  monthly;

  bool get isHourly => this == ChartAggregationInterval.hourly;
  bool get isDaily => this == ChartAggregationInterval.daily;
  bool get isWeekly => this == ChartAggregationInterval.weekly;
  bool get isMonthly => this == ChartAggregationInterval.monthly;
}

/// Dữ liệu một cột / mốc gom nhóm trên biểu đồ doanh thu thông minh (R3)
class RevenueChartBucket {
  final String label;
  final String fullLabel;
  final DateTime startDate;
  final DateTime endDate;
  final double totalRevenue;
  final double totalCost;
  final double profit;
  final int totalOrders;
  final int totalItemsSold;
  final Map<String, double> storeRevenues;

  const RevenueChartBucket({
    required this.label,
    required this.fullLabel,
    required this.startDate,
    required this.endDate,
    required this.totalRevenue,
    this.totalCost = 0.0,
    this.profit = 0.0,
    this.totalOrders = 0,
    this.totalItemsSold = 0,
    this.storeRevenues = const {},
  });
}
