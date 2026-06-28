import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:stores/presentation/common/widgets/error_view.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/reports/revenue_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/auth/auth_providers.dart';
import '../../../domain/entities/revenue_report.dart';
import '../../../domain/entities/product.dart';
import '../../../core/constants/app_constants.dart';

class OverviewPage extends ConsumerStatefulWidget {
  const OverviewPage({super.key});

  @override
  ConsumerState<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends ConsumerState<OverviewPage> {
  bool _showChart = true; // true: Biểu đồ, false: Danh sách

  // Toggle giữa biểu đồ doanh thu và danh sách doanh thu
  void _toggleViewMode() {
    setState(() {
      _showChart = !_showChart;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeRange = ref.watch(activeDateRangeProvider);
    final timeRangeType = ref.watch(selectedTimeRangeTypeProvider);
    final selectedBranchIds = ref.watch(selectedBranchesProvider);
    final isProfitVisible = ref.watch(profitVisibilityProvider);
    final productsAsync = ref.watch(allStoresProductsProvider);
    final storeFilter = ref.watch(selectedStoreFilterProvider);

    // Fetch dữ liệu doanh thu dựa trên khoảng thời gian đang lọc
    final summaryAsync = ref.watch(revenueByDateRangeProvider(activeRange));

    // Nhãn hiển thị thời gian
    final String dateLabel;
    if (timeRangeType == OverviewTimeRange.custom) {
      dateLabel = '${DateFormat('dd/MM').format(activeRange.start)} - ${DateFormat('dd/MM').format(activeRange.end)}';
    } else {
      dateLabel = timeRangeType.label;
    }

    final currentStoreId = ref.watch(currentStoreIdProvider);
    final mockBranches = getMockBranches(currentStoreId);

    // Nhãn hiển thị chi nhánh
    String branchLabel;
    if (storeFilter == 'all') {
      branchLabel = 'Tất cả chi nhánh (Xem gộp)';
    } else if (selectedBranchIds.length == mockBranches.length) {
      branchLabel = 'Tất cả chi nhánh';
    } else if (selectedBranchIds.length == 1) {
      branchLabel = mockBranches.firstWhere((b) => b.id == selectedBranchIds.first).name;
    } else {
      branchLabel = '${selectedBranchIds.length} chi nhánh';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(revenueByDateRangeProvider(activeRange));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. KiotViet Header
                _buildHeader(context),

                // 2. Bộ lọc nhanh
                _buildFiltersBar(context, dateLabel, branchLabel),

                summaryAsync.when(
                  data: (rawSummary) {
                    // Áp dụng bộ lọc chi nhánh mô phỏng cho thẻ tồn kho (các thông số doanh thu thực tế được lọc từ provider)
                    double branchFactor = 1.0;
                    if (selectedBranchIds.isEmpty) {
                      branchFactor = 0.0;
                    } else if (selectedBranchIds.length < mockBranches.length) {
                      branchFactor = selectedBranchIds.first == 'branch_1' ? 0.6 : 0.4;
                    }

                    final totalRevenue = rawSummary.totalRevenue;
                    final totalCost = rawSummary.totalCost;
                    final totalProfit = rawSummary.totalProfit;
                    final totalOrders = rawSummary.totalOrders;
                    final totalItemsSold = rawSummary.totalItemsSold;
                    final dailyReports = rawSummary.dailyReports;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          // 3. Thẻ Chỉ số doanh thu & lợi nhuận
                          _buildMetricsCard(
                            context,
                            totalOrders,
                            totalRevenue,
                            totalProfit,
                            isProfitVisible,
                          ),

                          const SizedBox(height: 16),
                          // 4. Lưới các hành động nhanh
                          _buildQuickActions(),

                          const SizedBox(height: 16),
                          // 5. Section Doanh thu (Biểu đồ & Danh sách)
                          _buildRevenueChartSection(context, dailyReports),

                          const SizedBox(height: 16),
                          // 6. Section Giá trị tồn kho
                          _buildInventoryValueCard(context, productsAsync, selectedBranchIds, storeFilter),

                          const SizedBox(height: 16),
                          // 7. Section Hàng bán chạy
                          _buildTopSellingSection(context, dailyReports),
                          const SizedBox(height: 24),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox(
                    height: 400,
                    child: Center(child: LoadingIndicator()),
                  ),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: ErrorView(e),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 1. Widget Header KiotViet
  Widget _buildHeader(BuildContext context) {
    final user = ref.watch(authProvider);
    final storeFilter = ref.watch(selectedStoreFilterProvider);
    final availableStoresAsync = ref.watch(availableStoresProvider);
    final currentStoreId = ref.watch(currentStoreIdProvider);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo KiotViet & Store selection (Admin)
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFF0067AC),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.insert_chart_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        AppConstants.appName,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0067AC),
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (user?.isAdmin == true) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0067AC).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Admin',
                            style: TextStyle(color: Color(0xFF0067AC), fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ]
                    ],
                  ),
                  const SizedBox(height: 2),
                  ref.watch(currentStoreNameProvider).when(
                        data: (name) => Text(
                          name,
                          style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500),
                        ),
                        loading: () => const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1)),
                        error: (_, __) => const Text('Cửa hàng', style: TextStyle(fontSize: 11, color: Colors.black54)),
                      ),
                ],
              )
            ],
          ),
          // Các Icon liên lạc, chuông báo, tin nhắn
          Row(
            children: [
              // Hotline icon
              IconButton(
                icon: const Icon(Icons.phone_in_talk_outlined, color: Colors.black87),
                onPressed: () {},
              ),
              // Notification icon với badge
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_outlined, color: Colors.black87),
                    onPressed: () {},
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: const Text(
                        '99',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                ],
              ),
              // Email icon với badge
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.mail_outline, color: Colors.black87),
                    onPressed: () {},
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: const Text(
                        '5',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                ],
              ),
            ],
          )
        ],
      ),
    );
  }

  // 2. Widget Bộ lọc nhanh
  Widget _buildFiltersBar(BuildContext context, String dateText, String branchText) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          // Bộ lọc Thời gian
          Expanded(
            child: InkWell(
              onTap: () => _showDateRangeFilterBottomSheet(context),
              child: Row(
                children: [
                  Text(
                    dateText,
                    style: const TextStyle(
                      color: Color(0xFF0067AC),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, color: Color(0xFF0067AC)),
                ],
              ),
            ),
          ),
          // Bộ lọc Chi nhánh
          InkWell(
            onTap: () => _showBranchFilterBottomSheet(context),
            child: Row(
              children: [
                Text(
                  branchText,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: Colors.black54),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 3. Widget Thẻ Chỉ số doanh thu & lợi nhuận
  Widget _buildMetricsCard(
    BuildContext context,
    int orderCount,
    double revenue,
    double profit,
    bool isProfitVisible,
  ) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              // Cột trái: Hoá đơn và Doanh thu
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$orderCount hoá đơn',
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${currencyFormat.format(revenue)} đ',
                      style: const TextStyle(
                        color: Color(0xFF0067AC),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              // Cột phải: Lợi nhuận
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text(
                          'Lợi nhuận',
                          style: TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            ref.read(profitVisibilityProvider.notifier).state = !isProfitVisible;
                          },
                          child: Icon(
                            isProfitVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 16,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isProfitVisible ? '${currencyFormat.format(profit)} đ' : '*** ***',
                      style: const TextStyle(
                        color: Color(0xFF4EB848),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
          const Divider(height: 24, color: Color(0xFFEEEEEE)),
          Row(
            children: const [
              Icon(Icons.assignment_return_outlined, color: Colors.black38, size: 18),
              SizedBox(width: 8),
              Text(
                '0 đơn trả hàng - 0',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          )
        ],
      ),
    );
  }

  // 4. Widget Lưới các hành động nhanh
  Widget _buildQuickActions() {
    final actions = [
      {'icon': Icons.account_balance_outlined, 'title': 'Vay vốn'},
      {'icon': Icons.local_shipping_outlined, 'title': 'Giao hàng'},
      {'icon': Icons.qr_code_scanner, 'title': 'Thanh toán'},
      {'icon': Icons.people_outline, 'title': 'Nhân viên'},
      {'icon': Icons.receipt_outlined, 'title': 'Thuế & Kế toán'},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: actions.map((item) {
        return Expanded(
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF0067AC).withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  item['icon'] as IconData,
                  color: const Color(0xFF0067AC),
                  size: 22,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item['title'] as String,
                style: const TextStyle(fontSize: 10, color: Colors.black87),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            ],
          ),
        );
      }).toList(),
    );
  }

  // 5. Section Doanh thu (Biểu đồ & Danh sách)
  Widget _buildRevenueChartSection(BuildContext context, List<RevenueReport> dailyReports) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Doanh thu',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Row(
                children: [
                  // Nút chuyển chế độ Biểu đồ / Danh sách
                  IconButton(
                    icon: Icon(
                      _showChart ? Icons.format_list_bulleted : Icons.bar_chart,
                      color: const Color(0xFF0067AC),
                    ),
                    onPressed: _toggleViewMode,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.chevron_right, color: Colors.black38),
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          // Biểu đồ hoặc Danh sách
          _showChart
              ? _buildBarChart(dailyReports)
              : _buildRevenueList(dailyReports, currencyFormat),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<RevenueReport> reports) {
    if (reports.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('Không có dữ liệu hiển thị', style: TextStyle(color: Colors.black38))),
      );
    }

    // Lấy dữ liệu vẽ cột doanh thu
    final List<BarChartGroupData> barGroups = [];
    double maxRevenue = 10000;

    for (int i = 0; i < reports.length; i++) {
      final rev = reports[i].totalRevenue;
      if (rev > maxRevenue) maxRevenue = rev;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: rev,
              color: const Color(0xFF4EB848), // Cột doanh thu màu xanh lá
              width: 14,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxRevenue * 1.15,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF0067AC),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final dateStr = DateFormat('dd/MM').format(reports[group.x.toInt()].date);
                final valStr = NumberFormat.compact(locale: 'vi_VN').format(rod.toY);
                return BarTooltipItem(
                  '$dateStr\n$valStr đ',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < reports.length) {
                    // Tính khoảng cách hiển thị nhãn động để biểu đồ không bị rối chữ
                    int interval = 1;
                    if (reports.length > 20) {
                      interval = 5;
                    } else if (reports.length > 10) {
                      interval = 2;
                    }

                    if (index % interval != 0) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        DateFormat('dd/MM').format(reports[index].date),
                        style: const TextStyle(color: Colors.black54, fontSize: 9),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
                reservedSize: 28,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  if (value == 0) return const SizedBox.shrink();
                  return Text(
                    NumberFormat.compact(locale: 'vi_VN').format(value),
                    style: const TextStyle(color: Colors.black45, fontSize: 9),
                  );
                },
                reservedSize: 32,
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.black.withOpacity(0.05),
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(
            show: false,
          ),
          barGroups: barGroups,
        ),
      ),
    );
  }

  Widget _buildRevenueList(List<RevenueReport> reports, NumberFormat format) {
    // Chỉ hiển thị các ngày có đơn hàng/doanh thu để phản ánh chính xác các ngày có phát sinh giao dịch
    final activeReports = reports.where((r) => r.totalOrders > 0).toList();
    final reversedList = List.from(activeReports.reversed);

    if (reversedList.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'Không có giao dịch nào trong khoảng thời gian này',
            style: TextStyle(color: Colors.black38, fontSize: 13),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: reversedList.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF0F0F0)),
      itemBuilder: (context, index) {
        final item = reversedList[index] as RevenueReport;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('dd/MM/yyyy').format(item.date),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              Row(
                children: [
                  Text(
                    '${format.format(item.totalRevenue)} đ',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0067AC)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${item.totalOrders} đơn)',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  )
                ],
              )
            ],
          ),
        );
      },
    );
  }

  // 6. Section Giá trị tồn kho
  Widget _buildInventoryValueCard(
    BuildContext context,
    AsyncValue<List<Product>> productsAsync,
    List<String> selectedBranchIds,
    String? storeFilter,
  ) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return productsAsync.when(
      data: (products) {
        int totalInventoryCount = 0;
        double totalInventoryValue = 0;

        for (final product in products) {
          int productBranchStock = 0;
          if (storeFilter == 'all') {
            // Xem gộp: cộng gộp tồn kho của tất cả chi nhánh thuộc tất cả cửa hàng
            productBranchStock = product.stock;
          } else {
            // Xem đơn lẻ: cộng theo chi nhánh được chọn lọc của cửa hàng hiện tại
            for (final branchId in selectedBranchIds) {
              productBranchStock += product.branchStocks[branchId] ?? 0;
            }
          }
          totalInventoryCount += productBranchStock;
          totalInventoryValue += productBranchStock * product.costPrice;
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Giá trị tồn',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${currencyFormat.format(totalInventoryCount)} hàng hoá',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  )
                ],
              ),
              Text(
                '${currencyFormat.format(totalInventoryValue)} đ',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              )
            ],
          ),
        );
      },
      loading: () => Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'Lỗi tải tồn kho: $e',
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      ),
    );
  }

  // 7. Section Hàng bán chạy
  Widget _buildTopSellingSection(BuildContext context, List<RevenueReport> dailyReports) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    // Gom dữ liệu bán chạy từ các báo cáo ngày
    final Map<String, _ProductAggregated> aggregateMap = {};
    for (final day in dailyReports) {
      for (final pr in day.productRevenues) {
        if (aggregateMap.containsKey(pr.productId)) {
          aggregateMap[pr.productId]!.quantity += pr.quantitySold;
          aggregateMap[pr.productId]!.revenue += pr.revenue;
        } else {
          aggregateMap[pr.productId] = _ProductAggregated(
            name: pr.productName,
            quantity: pr.quantitySold,
            revenue: pr.revenue,
          );
        }
      }
    }

    final topList = aggregateMap.values.toList();
    // Sắp xếp mặc định theo Doanh thu giảm dần
    topList.sort((a, b) => b.revenue.compareTo(a.revenue));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Hàng bán chạy',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
          const SizedBox(height: 12),
          // Hộp thoại Tabs nhỏ lọc "Theo doanh thu"
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 2,
                      )
                    ],
                  ),
                  child: const Text(
                    'Theo doanh thu',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0067AC)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: const Text(
                    'Theo số lượng',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (topList.isEmpty)
            const SizedBox(
              height: 100,
              child: Center(
                child: Text('Chưa có số liệu bán hàng', style: TextStyle(color: Colors.black38)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topList.length > 4 ? 4 : topList.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF0F0F0)),
              itemBuilder: (context, index) {
                final item = topList[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      // Số thứ tự
                      Container(
                        width: 24,
                        alignment: Alignment.center,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: index < 3 ? const Color(0xFF0067AC) : Colors.black38,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Tên sản phẩm & số lượng bán
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Đã bán: ${item.quantity}',
                              style: const TextStyle(fontSize: 11, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      // Doanh thu
                      Text(
                        '${currencyFormat.format(item.revenue)} đ',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // 8. Hộp thoại Bottom Sheet lọc Thời gian
  void _showDateRangeFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (sheetContext) {
        return Consumer(
          builder: (consumerContext, sheetRef, child) {
            final activeType = sheetRef.watch(selectedTimeRangeTypeProvider);
            return Container(
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      'Thời gian',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(color: Color(0xFFEEEEEE)),
                  ...OverviewTimeRange.values.map((type) {
                    final isSelected = activeType == type;
                    return ListTile(
                      title: Text(
                        type.label,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF0067AC) : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF0067AC)) : null,
                      onTap: () async {
                        Navigator.pop(consumerContext);
                        if (type == OverviewTimeRange.custom) {
                          // Kích hoạt date range picker của Flutter
                          final initialRange = ref.read(customDateRangeProvider);
                          final now = DateTime.now();
                          // Chuẩn hóa initialRange về start of day để tránh lỗi của Flutter date picker
                          final normalizedInitialRange = DateTimeRange(
                            start: DateTime(initialRange.start.year, initialRange.start.month, initialRange.start.day),
                            end: DateTime(initialRange.end.year, initialRange.end.month, initialRange.end.day),
                          );
                          final pickedRange = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(now.year, now.month, now.day),
                            initialDateRange: normalizedInitialRange,
                          );
                          if (pickedRange != null) {
                            ref.read(customDateRangeProvider.notifier).state = pickedRange;
                            ref.read(selectedTimeRangeTypeProvider.notifier).state = OverviewTimeRange.custom;
                          }
                        } else {
                          ref.read(selectedTimeRangeTypeProvider.notifier).state = type;
                        }
                      },
                    );
                  }).toList(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 9. Hộp thoại Bottom Sheet lọc Chi nhánh
  void _showBranchFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final selectedBranchIds = ref.watch(selectedBranchesProvider);
            final notifier = ref.read(selectedBranchesProvider.notifier);

            final currentStoreId = ref.watch(currentStoreIdProvider);
            final mockBranches = getMockBranches(currentStoreId);

            return Container(
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Chọn chi nhánh',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        InkWell(
                          onTap: () {
                            notifier.selectAll();
                          },
                          child: const Text(
                            'Chọn tất cả',
                            style: TextStyle(color: Color(0xFF0067AC), fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        )
                      ],
                    ),
                  ),
                  const Divider(color: Color(0xFFEEEEEE)),
                  ...mockBranches.map((branch) {
                    final isChecked = selectedBranchIds.contains(branch.id);
                    return CheckboxListTile(
                      title: Text(branch.name),
                      value: isChecked,
                      activeColor: const Color(0xFF0067AC),
                      onChanged: (_) {
                        notifier.toggleBranch(branch.id);
                      },
                    );
                  }).toList(),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0067AC),
                        ),
                        child: const Text('Xong'),
                      ),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// Lớp phụ trợ lưu dữ liệu sản phẩm gom nhóm
class _ProductAggregated {
  final String name;
  int quantity;
  double revenue;

  _ProductAggregated({
    required this.name,
    required this.quantity,
    required this.revenue,
  });
}
