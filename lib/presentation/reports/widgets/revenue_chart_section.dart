import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/reports/overview_kpi_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../application/reports/revenue_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/overview_kpis.dart';

/// Sub-widget Biểu Đồ Doanh Thu Đa Chiều & Phân Tích Giờ Cao Điểm (R2 - Revenue Chart Section)
/// - Khi lọc 1 ngày (Hôm nay / Hôm qua): Tự động hiển thị Biểu đồ 24 mốc giờ trong ngày (Hourly Peak Chart)
///   kèm badge nhận diện Khung giờ cao điểm (Peak Rush Hour).
/// - Khi lọc nhiều ngày (7 ngày qua, Tháng này, Tháng trước, Tùy chỉnh): Hiển thị Biểu đồ cột xếp chồng chi nhánh.
/// - Tooltip tương tác hiển thị chi tiết doanh thu từng chi nhánh/khung giờ.
/// - Nút chuyển đổi mượt mà giữa Chế độ Biểu đồ (Chart) và Chế độ Bảng danh sách (List).
class RevenueChartSection extends ConsumerStatefulWidget {
  const RevenueChartSection({super.key});

  @override
  ConsumerState<RevenueChartSection> createState() =>
      _RevenueChartSectionState();
}

class _RevenueChartSectionState extends ConsumerState<RevenueChartSection> {
  bool _showChart = true; // true: Biểu đồ, false: Danh sách

  void _toggleViewMode() {
    setState(() {
      _showChart = !_showChart;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeRange = ref.watch(overviewActiveDateRangeProvider);
    final interval = getChartAggregationInterval(activeRange);
    final isSingleDay = interval.isHourly;

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
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Tiêu đề, Toggle View Mode (Chart/List) & Peak badge nếu là single day
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isSingleDay
                        ? 'Doanh thu theo giờ trong ngày'
                        : 'Biểu đồ doanh thu',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _showChart
                          ? Icons.format_list_bulleted_rounded
                          : Icons.bar_chart_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    tooltip: _showChart
                        ? 'Xem dạng danh sách'
                        : 'Xem dạng biểu đồ',
                    onPressed: _toggleViewMode,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Nội dung: Hourly Chart hoặc Multi-day Chart
          if (isSingleDay)
            _buildHourlySection(context, currencyFormat)
          else
            _buildMultiDaySection(context, activeRange, currencyFormat),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. Hourly Section (Cho 1 ngày)
  // ===========================================================================
  Widget _buildHourlySection(BuildContext context, NumberFormat currencyFormat) {
    final hourlyAsync = ref.watch(hourlyRevenueListProvider);

    return hourlyAsync.when(
      data: (hourlyList) {
        // Tìm giờ cao điểm (Peak rush hour)
        HourlyRevenueData? peakHour;
        double maxRev = 0.0;
        for (final item in hourlyList) {
          if (item.revenue > maxRev) {
            maxRev = item.revenue;
            peakHour = item;
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Peak Hour Badge nếu có doanh thu
            if (peakHour != null && maxRev > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.chartOrange.withOpacity(0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        color: Color(0xFFD97706),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Khung giờ cao điểm: ${peakHour.hourLabel} - ${(peakHour.hour + 1).toString().padLeft(2, '0')}:00',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${currencyFormat.format(peakHour.revenue)} đ)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Render Biểu đồ hoặc Danh sách
            _showChart
                ? _buildHourlyBarChart(hourlyList)
                : _buildHourlyList(hourlyList, currencyFormat),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 180,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'Lỗi tải biểu đồ giờ: $e',
            style: const TextStyle(color: AppColors.danger, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildHourlyBarChart(List<HourlyRevenueData> hourlyList) {
    double maxRevenue = 10000;
    for (final item in hourlyList) {
      if (item.revenue > maxRevenue) {
        maxRevenue = item.revenue;
      }
    }

    final List<BarChartGroupData> barGroups = [];
    for (int i = 0; i < hourlyList.length; i++) {
      final data = hourlyList[i];
      final rev = data.revenue;

      barGroups.add(
        BarChartGroupData(
          x: data.hour,
          barRods: [
            BarChartRodData(
              toY: rev,
              color: rev > 0 ? AppColors.primary : Colors.grey.shade200,
              width: 8,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
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
          maxY: maxRevenue * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.primary,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final hour = group.x.toInt();
                final hourData = hourlyList.firstWhere(
                  (d) => d.hour == hour,
                  orElse: () => HourlyRevenueData(hour: hour, revenue: 0, orderCount: 0),
                );
                final valStr = NumberFormat('#,###', 'vi_VN').format(rod.toY);
                return BarTooltipItem(
                  '${hourData.hourLabel}\n$valStr đ (${hourData.orderCount} đơn)',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final hour = value.toInt();
                  // Hiển thị nhãn mỗi 3 tiếng: 0h, 3h, 6h, 9h, 12h, 15h, 18h, 21h
                  if (hour % 3 == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        '${hour}h',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (double value, TitleMeta meta) {
                  if (value == 0) return const SizedBox.shrink();
                  return Text(
                    NumberFormat.compact(locale: 'vi_VN').format(value),
                    style: const TextStyle(color: Colors.black45, fontSize: 9),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.black.withOpacity(0.05),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
        ),
      ),
    );
  }

  Widget _buildHourlyList(
    List<HourlyRevenueData> hourlyList,
    NumberFormat format,
  ) {
    final activeHours = hourlyList.where((h) => h.revenue > 0).toList();

    if (activeHours.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'Chưa có đơn hàng trong ngày',
            style: TextStyle(color: Colors.black38, fontSize: 12),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: activeHours.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.divider),
      itemBuilder: (context, index) {
        final item = activeHours[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.hourLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              Row(
                children: [
                  Text(
                    '${format.format(item.revenue)} đ',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${item.orderCount} đơn',
                      style:
                          const TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 2. Multi-Day Section (Cho nhiều ngày với Smart Aggregation R3)
  // ===========================================================================
  Widget _buildMultiDaySection(
    BuildContext context,
    DateTimeRange activeRange,
    NumberFormat currencyFormat,
  ) {
    final summaryAsync = ref.watch(revenueByDateRangeProvider(activeRange));

    return summaryAsync.when(
      data: (summary) {
        final interval = getChartAggregationInterval(activeRange);
        final buckets = aggregateRevenueReports(
          dailyReports: summary.dailyReports,
          range: activeRange,
        );
        return Column(
          children: [
            _showChart
                ? Column(
                    children: [
                      _buildMultiDayBarChart(buckets, interval),
                      _buildChartLegend(),
                    ],
                  )
                : _buildMultiDayList(buckets, currencyFormat),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 180,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'Lỗi tải doanh thu: $e',
            style: const TextStyle(color: AppColors.danger, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Color _getStoreColor(String storeId, int index) {
    switch (storeId) {
      case 'store_001':
        return AppColors.primary; // KiotViet Blue
      case 'store_002':
        return AppColors.secondary; // KiotViet Green
      default:
        final colors = [
          AppColors.primary,
          AppColors.secondary,
          AppColors.chartOrange,
          AppColors.chartPurple,
          AppColors.chartRed,
          AppColors.chartTeal,
        ];
        return colors[index % colors.length];
    }
  }

  Widget _buildMultiDayBarChart(
    List<RevenueChartBucket> buckets,
    ChartAggregationInterval interval,
  ) {
    if (buckets.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Không có dữ liệu hiển thị',
            style: TextStyle(color: Colors.black38),
          ),
        ),
      );
    }

    final List<BarChartGroupData> barGroups = [];
    double maxRevenue = 10000;

    // Chiều rộng cột phản hồi thích ứng (Monthly: 24, Weekly: 18, Daily: 8-14)
    final double barWidth;
    switch (interval) {
      case ChartAggregationInterval.monthly:
        barWidth = 24.0;
        break;
      case ChartAggregationInterval.weekly:
        barWidth = 18.0;
        break;
      case ChartAggregationInterval.daily:
      case ChartAggregationInterval.hourly:
        barWidth = buckets.length > 15 ? 8.0 : 14.0;
        break;
    }

    for (int i = 0; i < buckets.length; i++) {
      final bucket = buckets[i];
      final rev = bucket.totalRevenue;
      if (rev > maxRevenue) maxRevenue = rev;

      final List<BarChartRodStackItem> rodStackItems = [];
      if (bucket.storeRevenues.isNotEmpty) {
        final sortedStoreIds = bucket.storeRevenues.keys.toList()..sort();
        double currentY = 0.0;
        for (int j = 0; j < sortedStoreIds.length; j++) {
          final storeId = sortedStoreIds[j];
          final val = bucket.storeRevenues[storeId] ?? 0.0;
          if (val > 0) {
            rodStackItems.add(
              BarChartRodStackItem(
                currentY,
                currentY + val,
                _getStoreColor(storeId, j),
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
              color: AppColors.primary,
              width: barWidth,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
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
                final bucket = buckets[group.x.toInt()];
                final valStr = NumberFormat('#,###', 'vi_VN').format(rod.toY);

                String tooltipText = '${bucket.label}\nTổng: $valStr đ';

                if (bucket.storeRevenues.length > 1) {
                  final sortedStoreIds = bucket.storeRevenues.keys.toList()..sort();
                  final availableStores =
                      ref.read(availableStoresProvider).value ?? {};
                  for (final storeId in sortedStoreIds) {
                    final storeRev = bucket.storeRevenues[storeId] ?? 0.0;
                    if (storeRev > 0) {
                      final storeName = availableStores[storeId] ?? storeId;
                      final storeValStr =
                          NumberFormat.compact(locale: 'vi_VN').format(storeRev);
                      tooltipText += '\n• $storeName: $storeValStr đ';
                    }
                  }
                }

                return BarTooltipItem(
                  tooltipText,
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
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
                  if (index >= 0 && index < buckets.length) {
                    if (interval == ChartAggregationInterval.daily) {
                      int step = 1;
                      if (buckets.length > 20) {
                        step = 5;
                      } else if (buckets.length > 10) {
                        step = 2;
                      }
                      if (index % step != 0) {
                        return const SizedBox.shrink();
                      }
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        buckets[index].label,
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: (interval == ChartAggregationInterval.weekly ||
                                  interval == ChartAggregationInterval.monthly)
                              ? 10
                              : 9,
                          fontWeight: (interval == ChartAggregationInterval.weekly ||
                                  interval == ChartAggregationInterval.monthly)
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
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
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.black.withOpacity(0.05),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
        ),
      ),
    );
  }

  Widget _buildChartLegend() {
    final availableStoresAsync = ref.watch(availableStoresProvider);
    return availableStoresAsync.when(
      data: (availableStores) {
        if (availableStores.length <= 1) return const SizedBox.shrink();

        final uniqueStoreIds = availableStores.keys.toList()..sort();

        return Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: uniqueStoreIds.map((storeId) {
              final index = uniqueStoreIds.indexOf(storeId);
              final color = _getStoreColor(storeId, index);
              final storeName = availableStores[storeId] ?? storeId;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    storeName,
                    style: const TextStyle(
                      fontSize: 11,
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

  Widget _buildMultiDayList(
    List<RevenueChartBucket> buckets,
    NumberFormat format,
  ) {
    final activeBuckets =
        buckets.where((b) => b.totalOrders > 0 || b.totalRevenue > 0).toList();
    final reversedList = List.from(activeBuckets.reversed);

    if (reversedList.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'Chưa có giao dịch phát sinh',
            style: TextStyle(color: Colors.black38, fontSize: 13),
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
        final item = reversedList[index] as RevenueChartBucket;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.fullLabel,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              Row(
                children: [
                  Text(
                    '${format.format(item.totalRevenue)} đ',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${item.totalOrders} đơn)',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

