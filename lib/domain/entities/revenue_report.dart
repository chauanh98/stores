class RevenueReport {
  final DateTime date;
  final double totalRevenue;
  final double totalCost;
  final double profit;
  final int totalOrders;
  final int totalItemsSold;
  final List<ProductRevenue> productRevenues;

  const RevenueReport({
    required this.date,
    required this.totalRevenue,
    required this.totalCost,
    required this.profit,
    required this.totalOrders,
    required this.totalItemsSold,
    required this.productRevenues,
  });
}

class ProductRevenue {
  final String productId;
  final String productName;
  final int quantitySold;
  final double revenue;
  final double cost;
  final double profit;
  final double profitMargin;

  const ProductRevenue({
    required this.productId,
    required this.productName,
    required this.quantitySold,
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.profitMargin,
  });
}

class RevenueSummary {
  final DateTime startDate;
  final DateTime endDate;
  final double totalRevenue;
  final double totalCost;
  final double totalProfit;
  final int totalOrders;
  final int totalItemsSold;
  final List<RevenueReport> dailyReports;

  const RevenueSummary({
    required this.startDate,
    required this.endDate,
    required this.totalRevenue,
    required this.totalCost,
    required this.totalProfit,
    required this.totalOrders,
    required this.totalItemsSold,
    required this.dailyReports,
  });
}