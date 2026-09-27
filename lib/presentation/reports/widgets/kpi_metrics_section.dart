import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/customers/customers_providers.dart';
import '../../../application/reports/overview_kpi_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/overview_kpis.dart';
import '../../customers/pages/customers_page.dart';

/// Sub-widget Bộ Chỉ Số Kinh Doanh Toàn Diện & So Sánh Tăng Trưởng (R1 - KPI Metrics Section)
/// Hiển thị:
/// - Doanh thu thuần kèm badge % tăng trưởng
/// - Số lượng đơn hàng kèm badge % tăng trưởng
/// - Lợi nhuận gộp kèm mắt toggle và badge % tăng trưởng (chỉ Admin/Supervisor)
/// - Giá trị trung bình đơn hàng (AOV = Doanh thu / Đơn) kèm badge % tăng trưởng
/// - Giá trị hàng trả lại
/// - Thẻ Tổng hợp Công nợ khách hàng cần thu tại chi nhánh kèm lối tắt điều hướng
class KPIMetricsSection extends ConsumerWidget {
  const KPIMetricsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpisAsync = ref.watch(overviewKPIsProvider);
    final isProfitVisible = ref.watch(profitVisibilityProvider);
    final user = ref.watch(authProvider);
    final canViewCostPrice = user?.canViewCostPrice ?? false;
    final canViewDebtSummary = user?.canViewDebtSummary ?? false;
    final timeRangeType = ref.watch(overviewTimeRangeTypeProvider);

    final comparisonLabel = _getComparisonLabel(timeRangeType);

    return kpisAsync.when(
      data: (kpis) => _buildContent(
        context,
        ref,
        kpis,
        isProfitVisible,
        canViewCostPrice,
        canViewDebtSummary,
        comparisonLabel,
      ),
      loading: () => _buildLoadingCard(),
      error: (error, _) => _buildErrorCard(error),
    );
  }

  String _getComparisonLabel(OverviewTimeRange range) {
    switch (range) {
      case OverviewTimeRange.today:
        return 'so với hôm qua';
      case OverviewTimeRange.yesterday:
        return 'so với hôm kia';
      case OverviewTimeRange.last7Days:
        return 'so với 7 ngày trước';
      case OverviewTimeRange.thisMonth:
        return 'so với tháng trước';
      case OverviewTimeRange.lastMonth:
        return 'so với 2 tháng trước';
      case OverviewTimeRange.custom:
        return 'so với kỳ trước';
    }
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    OverviewKPIs kpis,
    bool isProfitVisible,
    bool canViewCostPrice,
    bool canViewDebtSummary,
    String comparisonLabel,
  ) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Column(
      children: [
        // Card 1: Thẻ Doanh thu thuần & Lợi nhuận gộp (KPI Chính)
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Row 1: Doanh thu thuần & Lợi nhuận
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cột Doanh thu thuần
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.monetization_on_outlined,
                              size: 15,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Doanh thu thuần',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${currencyFormat.format(kpis.netRevenue)} đ',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildGrowthBadge(
                          growthPercent: kpis.revenueGrowthPercent,
                          comparisonLabel: comparisonLabel,
                        ),
                      ],
                    ),
                  ),

                  // Cột Lợi nhuận gộp (nếu có quyền xem giá vốn)
                  if (canViewCostPrice)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Flexible(
                                child: Text(
                                  'Lợi nhuận gộp',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () {
                                  ref
                                      .read(profitVisibilityProvider.notifier)
                                      .state = !isProfitVisible;
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(2.0),
                                  child: Icon(
                                    isProfitVisible
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 16,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isProfitVisible
                                ? '${currencyFormat.format(kpis.grossProfit)} đ'
                                : '*** ***',
                            style: const TextStyle(
                              color: AppColors.secondary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (isProfitVisible)
                            _buildGrowthBadge(
                              growthPercent: kpis.profitGrowthPercent,
                              comparisonLabel: comparisonLabel,
                              alignment: MainAxisAlignment.end,
                            )
                          else
                            const SizedBox(height: 18),
                        ],
                      ),
                    ),
                ],
              ),

              const Divider(height: 24, color: AppColors.divider),

              // Row 2: Số hóa đơn & AOV (Giá trị trung bình đơn)
              Row(
                children: [
                  // Số hóa đơn
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Số hóa đơn',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              '${kpis.orderCount}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _buildMiniGrowthBadge(kpis.orderCountGrowthPercent),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // AOV (Giá trị trung bình mỗi đơn)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AOV (Trung bình/đơn)',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${currencyFormat.format(kpis.aov)} đ',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _buildMiniGrowthBadge(kpis.aovGrowthPercent),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Row 3: Hàng bán trả lại
              if (kpis.returnGoodsValue > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.grey50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.grey200),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.assignment_return_outlined,
                        size: 15,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 6),
                      const Flexible(
                        child: Text(
                          'Hàng bán trả lại:',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${currencyFormat.format(kpis.returnGoodsValue)} đ',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        if (canViewDebtSummary) ...[
          const SizedBox(height: 12),

          // Card 2: Thẻ Tổng Hợp Công Nợ Khách Hàng Cần Thu
          InkWell(
            onTap: () {
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CustomersPage(
                    initialDebtFilter: CustomerDebtFilter.inDebt,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.chartOrange.withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: AppColors.chartOrange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Công nợ khách hàng cần thu',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${currencyFormat.format(kpis.customerDebt)} đ',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Sổ nợ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGrowthBadge({
    required double growthPercent,
    required String comparisonLabel,
    MainAxisAlignment alignment = MainAxisAlignment.start,
  }) {
    final isPositive = growthPercent > 0;
    final isZero = growthPercent == 0.0;
    final color = isZero
        ? AppColors.grey600
        : (isPositive ? AppColors.success : AppColors.danger);
    final bgColor = isZero
        ? AppColors.grey100
        : (isPositive ? AppColors.successLight : AppColors.dangerLight);

    final sign = isPositive ? '+' : '';
    final formattedPercent = '$sign${growthPercent.toStringAsFixed(1)}%';

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: alignment,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isZero)
                Icon(
                  isPositive
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 11,
                  color: color,
                ),
              Text(
                formattedPercent,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            comparisonLabel,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniGrowthBadge(double growthPercent) {
    if (growthPercent == 0.0) return const SizedBox.shrink();
    final isPositive = growthPercent > 0;
    final color = isPositive ? AppColors.success : AppColors.danger;
    final sign = isPositive ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: isPositive ? AppColors.successLight : AppColors.dangerLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            size: 12,
            color: color,
          ),
          Text(
            '$sign${growthPercent.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildErrorCard(Object error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          'Lỗi tải chỉ số kinh doanh: $error',
          style: const TextStyle(color: AppColors.danger, fontSize: 12),
        ),
      ),
    );
  }
}
