import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/presentation/common/widgets/error_view.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../application/reports/revenue_providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/revenue_report.dart';

class OverviewPage extends ConsumerStatefulWidget {
  const OverviewPage({super.key});

  @override
  ConsumerState<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends ConsumerState<OverviewPage> {
  bool _showChart = true; // true: Biểu đồ, false: Danh sách
  bool _sortByRevenue = true; // true: Doanh thu, false: Số lượng

  // Toggle giữa biểu đồ doanh thu và danh sách doanh thu
  void _toggleViewMode() {
    setState(() {
      _showChart = !_showChart;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeRange = ref.watch(overviewActiveDateRangeProvider);
    final timeRangeType = ref.watch(overviewTimeRangeTypeProvider);
    final selectedBranchIds = ref.watch(selectedBranchesProvider);
    final isProfitVisible = ref.watch(profitVisibilityProvider);
    final productsAsync = ref.watch(allStoresProductsProvider);
    final storeFilter = ref.watch(selectedStoreFilterProvider);

    final l10n = AppLocalizations.of(context)!;

    // Fetch dữ liệu doanh thu dựa trên khoảng thời gian đang lọc
    final summaryAsync = ref.watch(revenueByDateRangeProvider(activeRange));

    // Nhãn hiển thị thời gian
    final String dateLabel;
    if (timeRangeType == OverviewTimeRange.custom) {
      dateLabel =
          '${DateFormat('dd/MM').format(activeRange.start)} - ${DateFormat('dd/MM').format(activeRange.end)}';
    } else {
      dateLabel = timeRangeType.label;
    }

    final currentStoreId = ref.watch(currentStoreIdProvider);
    final mockBranches = getMockBranches(currentStoreId);

    // Nhãn hiển thị chi nhánh
    String branchLabel;
    if (storeFilter == 'all') {
      branchLabel = l10n.allBranchesCombined;
    } else if (selectedBranchIds.length == mockBranches.length) {
      branchLabel = l10n.allBranches;
    } else if (selectedBranchIds.length == 1) {
      branchLabel =
          mockBranches.firstWhere((b) => b.id == selectedBranchIds.first).name;
    } else {
      branchLabel = '${selectedBranchIds.length} chi nhánh';
    }

    return Scaffold(
      backgroundColor: AppColors.background,
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
                      branchFactor =
                          selectedBranchIds.first == 'branch_1' ? 0.6 : 0.4;
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
                          _buildQuickActions(context),

                          const SizedBox(height: 16),
                          // 5. Section Doanh thu (Biểu đồ & Danh sách)
                          _buildRevenueChartSection(context, dailyReports),

                          const SizedBox(height: 16),
                          // 6. Section Giá trị tồn kho
                          _buildInventoryValueCard(context, productsAsync),

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
    final l10n = AppLocalizations.of(context)!;

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
                  color: AppColors.primary,
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
                          color: AppColors.primary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (user?.isAdmin == true) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Admin',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 8,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ]
                    ],
                  ),
                  const SizedBox(height: 2),
                  ref.watch(currentStoreNameProvider).when(
                        data: (name) => Text(
                          name,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                              fontWeight: FontWeight.w500),
                        ),
                        loading: () => const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1)),
                        error: (_, __) => Text(l10n.store,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black54)),
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
                icon: const Icon(Icons.phone_in_talk_outlined,
                    color: Colors.black87),
                onPressed: () {},
              ),
              // Notification icon với badge
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_outlined,
                        color: Colors.black87),
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
  Widget _buildFiltersBar(
      BuildContext context, String dateText, String branchText) {
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
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, color: AppColors.primary),
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
    final l10n = AppLocalizations.of(context)!;

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
                      l10n.invoiceCountLabel(orderCount),
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${currencyFormat.format(revenue)} đ',
                      style: const TextStyle(
                        color: AppColors.primary,
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
                        Text(
                          l10n.profit,
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 13),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            ref.read(profitVisibilityProvider.notifier).state =
                                !isProfitVisible;
                          },
                          child: Icon(
                            isProfitVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 16,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isProfitVisible
                          ? '${currencyFormat.format(profit)} đ'
                          : '*** ***',
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
          const Divider(height: 24, color: AppColors.divider),
          Row(
            children: [
              const Icon(Icons.assignment_return_outlined,
                  color: Colors.black38, size: 18),
              const SizedBox(width: 8),
              Text(
                l10n.returnsCountLabel,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          )
        ],
      ),
    );
  }

  // 4. Widget Lưới các hành động nhanh
  Widget _buildQuickActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final actions = [
      {'icon': Icons.account_balance_outlined, 'title': l10n.loans},
      {'icon': Icons.local_shipping_outlined, 'title': l10n.shipping},
      {'icon': Icons.qr_code_scanner, 'title': l10n.checkout},
      {'icon': Icons.people_outline, 'title': l10n.staff},
      {'icon': Icons.receipt_outlined, 'title': l10n.taxAndAccounting},
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
                  color: AppColors.primary.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  item['icon'] as IconData,
                  color: AppColors.primary,
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
  Widget _buildRevenueChartSection(
      BuildContext context, List<RevenueReport> dailyReports) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final l10n = AppLocalizations.of(context)!;

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
              Text(
                l10n.revenue,
                style: const TextStyle(
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
                      color: AppColors.primary,
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
              ? Column(
                  children: [
                    _buildBarChart(dailyReports),
                    _buildChartLegend(),
                  ],
                )
              : _buildRevenueList(dailyReports, currencyFormat),
        ],
      ),
    );
  }

  Color getStoreColor(String storeId, int index) {
    switch (storeId) {
      case 'store_001':
        return AppColors.primary; // KiotViet Blue
      case 'store_002':
        return AppColors.secondary; // KiotViet Green
      default:
        final colors = [
          AppColors.primary,
          AppColors.secondary,
          const Color(0xFFF39C12), // Orange
          const Color(0xFF9B59B6), // Purple
          const Color(0xFFE74C3C), // Red
          const Color(0xFF1ABC9C), // Teal
        ];
        return colors[index % colors.length];
    }
  }

  Widget _buildChartLegend() {
    final availableStoresAsync = ref.watch(availableStoresProvider);
    return availableStoresAsync.when(
      data: (availableStores) {
        final selectedBranchIds = ref.watch(selectedBranchesProvider);
        final currentStoreId = ref.watch(currentStoreIdProvider);
        final storeFilter = ref.watch(selectedStoreFilterProvider);
        final user = ref.watch(authProvider);

        final List<String> activeStoreIds = [];
        if (user?.isAdmin == true) {
          if (storeFilter == 'all') {
            activeStoreIds.addAll(availableStores.keys);
          } else if (storeFilter != null) {
            activeStoreIds.add(storeFilter);
          } else {
            for (final branchId in selectedBranchIds) {
              if (currentStoreId == 'store_001') {
                if (branchId == 'branch_1') activeStoreIds.add('store_001');
                if (branchId == 'branch_2') activeStoreIds.add('store_002');
              } else if (currentStoreId == 'store_002') {
                if (branchId == 'branch_1') activeStoreIds.add('store_002');
                if (branchId == 'branch_2') activeStoreIds.add('store_001');
              }
            }
          }
        } else {
          activeStoreIds.add(currentStoreId);
        }

        final uniqueStoreIds = activeStoreIds.toSet().toList()..sort();

        if (uniqueStoreIds.length <= 1) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: uniqueStoreIds.map((storeId) {
              final index = uniqueStoreIds.indexOf(storeId);
              final color = getStoreColor(storeId, index);
              final storeName = availableStores[storeId] ?? storeId;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    storeName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildBarChart(List<RevenueReport> reports) {
    if (reports.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
            child: Text('Không có dữ liệu hiển thị',
                style: TextStyle(color: Colors.black38))),
      );
    }

    // Lấy dữ liệu vẽ cột doanh thu
    final List<BarChartGroupData> barGroups = [];
    double maxRevenue = 10000;

    for (int i = 0; i < reports.length; i++) {
      final report = reports[i];
      final rev = report.totalRevenue;
      if (rev > maxRevenue) maxRevenue = rev;

      final List<BarChartRodStackItem> rodStackItems = [];
      if (report.storeRevenues.isNotEmpty) {
        final sortedStoreIds = report.storeRevenues.keys.toList()..sort();
        double currentY = 0.0;
        for (int j = 0; j < sortedStoreIds.length; j++) {
          final storeId = sortedStoreIds[j];
          final val = report.storeRevenues[storeId] ?? 0.0;
          if (val > 0) {
            rodStackItems.add(
              BarChartRodStackItem(
                currentY,
                currentY + val,
                getStoreColor(storeId, j),
              ),
            );
            currentY += val;
          }
        }
      }

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: rev,
              color: AppColors.secondary,
              // Fallback color
              width: 14,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
              rodStackItems: rodStackItems.isNotEmpty ? rodStackItems : null,
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
              getTooltipColor: (_) => AppColors.primary,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final report = reports[group.x.toInt()];
                final dateStr = DateFormat('dd/MM').format(report.date);
                final valStr = NumberFormat('#,###', 'vi_VN').format(rod.toY);

                String tooltipText = '$dateStr\nTổng: $valStr đ';

                if (report.storeRevenues.length > 1) {
                  final sortedStoreIds = report.storeRevenues.keys.toList()
                    ..sort();
                  final availableStores =
                      ref.read(availableStoresProvider).value ?? {};
                  for (final storeId in sortedStoreIds) {
                    final storeRev = report.storeRevenues[storeId] ?? 0.0;
                    if (storeRev > 0) {
                      final storeName = availableStores[storeId] ?? storeId;
                      final storeValStr = NumberFormat.compact(locale: 'vi_VN')
                          .format(storeRev);
                      tooltipText += '\n• $storeName: $storeValStr đ';
                    }
                  }
                }

                return BarTooltipItem(
                  tooltipText,
                  const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11),
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
                        style:
                            const TextStyle(color: Colors.black54, fontSize: 9),
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
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
    final l10n = AppLocalizations.of(context)!;

    if (reversedList.isEmpty) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Text(
            l10n.noTransactions,
            style: const TextStyle(color: Colors.black38, fontSize: 13),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: reversedList.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.divider),
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
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.ordersCount(item.totalOrders),
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
  ) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final l10n = AppLocalizations.of(context)!;

    return productsAsync.when(
      data: (products) {
        int totalInventoryCount = 0;
        double totalInventoryValue = 0;

        for (final product in products) {
          final productBranchStock = product.stock;
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
                  Text(
                    l10n.inventoryValue,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.goodsCount(totalInventoryCount),
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
            l10n.inventoryLoadError(e.toString()),
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildTopSellingSection(
      BuildContext context, List<RevenueReport> dailyReports) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final l10n = AppLocalizations.of(context)!;

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
    // Sắp xếp theo doanh thu hoặc số lượng giảm dần
    if (_sortByRevenue) {
      topList.sort((a, b) => b.revenue.compareTo(a.revenue));
    } else {
      topList.sort((a, b) => b.quantity.compareTo(a.quantity));
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.topSelling,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
          const SizedBox(height: 12),
          // Hộp thoại Tabs nhỏ lọc "Theo doanh thu" / "Theo số lượng"
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    if (!_sortByRevenue) {
                      setState(() {
                        _sortByRevenue = true;
                      });
                    }
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _sortByRevenue ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: _sortByRevenue
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 2,
                              )
                            ]
                          : null,
                    ),
                    child: Text(
                      l10n.byRevenue,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            _sortByRevenue ? FontWeight.bold : FontWeight.w500,
                        color:
                            _sortByRevenue ? AppColors.primary : Colors.black54,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    if (_sortByRevenue) {
                      setState(() {
                        _sortByRevenue = false;
                      });
                    }
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          !_sortByRevenue ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: !_sortByRevenue
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 2,
                              )
                            ]
                          : null,
                    ),
                    child: Text(
                      l10n.byQuantity,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            !_sortByRevenue ? FontWeight.bold : FontWeight.w500,
                        color: !_sortByRevenue
                            ? AppColors.primary
                            : Colors.black54,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (topList.isEmpty)
            SizedBox(
              height: 100,
              child: Center(
                child: Text(l10n.noSalesData,
                    style: const TextStyle(color: Colors.black38)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topList.length > 4 ? 4 : topList.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.divider),
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
                            color:
                                index < 3 ? AppColors.primary : Colors.black38,
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
                              l10n.soldQty(item.quantity),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black54),
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
    final l10n = AppLocalizations.of(context)!;
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
            final activeType = sheetRef.watch(overviewTimeRangeTypeProvider);
            return Container(
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      l10n.timeRange,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(color: AppColors.divider),
                  ...OverviewTimeRange.values.map((type) {
                    final isSelected = activeType == type;
                    return ListTile(
                      title: Text(
                        type.label,
                        style: TextStyle(
                          color:
                              isSelected ? AppColors.primary : Colors.black87,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: AppColors.primary)
                          : null,
                      onTap: () async {
                        Navigator.pop(consumerContext);
                        if (type == OverviewTimeRange.custom) {
                          // Kích hoạt date range picker của Flutter
                          final initialRange =
                              ref.read(overviewCustomDateRangeProvider);
                          final now = DateTime.now();
                          // Chuẩn hóa initialRange về start of day để tránh lỗi của Flutter date picker
                          final normalizedInitialRange = DateTimeRange(
                            start: DateTime(
                                initialRange.start.year,
                                initialRange.start.month,
                                initialRange.start.day),
                            end: DateTime(initialRange.end.year,
                                initialRange.end.month, initialRange.end.day),
                          );
                          final pickedRange = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(now.year, now.month, now.day),
                            initialDateRange: normalizedInitialRange,
                          );
                          if (pickedRange != null) {
                            ref
                                .read(overviewCustomDateRangeProvider.notifier)
                                .state = pickedRange;
                            ref
                                .read(overviewTimeRangeTypeProvider.notifier)
                                .state = OverviewTimeRange.custom;
                          }
                        } else {
                          ref
                              .read(overviewTimeRangeTypeProvider.notifier)
                              .state = type;
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
    final l10n = AppLocalizations.of(context)!;
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.selectBranch,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        InkWell(
                          onTap: () {
                            notifier.selectAll();
                          },
                          child: Text(
                            l10n.selectAll,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                        )
                      ],
                    ),
                  ),
                  const Divider(color: AppColors.divider),
                  ...mockBranches.map((branch) {
                    final isChecked = selectedBranchIds.contains(branch.id);
                    return CheckboxListTile(
                      title: Text(branch.name),
                      value: isChecked,
                      activeColor: AppColors.primary,
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
                          backgroundColor: AppColors.primary,
                        ),
                        child: Text(l10n.doneBtn),
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
