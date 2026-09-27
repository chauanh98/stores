import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/theme/app_colors.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../application/reports/overview_kpi_providers.dart';
import '../../../domain/entities/overview_kpis.dart';
import '../../customers/pages/customers_page.dart';
import '../../products/pages/products_page.dart';

/// Section phân tích cơ cấu doanh thu theo Phương thức thanh toán (Donut)
/// và tỷ trọng doanh thu theo Nhóm hàng / Danh mục sản phẩm (R4).
class PaymentCategoryBreakdownSection extends ConsumerWidget {
  const PaymentCategoryBreakdownSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final paymentAsync = ref.watch(paymentBreakdownProvider);
    final categoryAsync = ref.watch(categoryRevenueShareProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card 1: Cơ Cấu Phương Thức Thanh Toán (Donut Chart)
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  const Flexible(
                    child: Text(
                      'Cơ cấu phương thức thanh toán',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              paymentAsync.when(
                data: (payment) =>
                    _buildPaymentDonut(context, payment, currencyFormat),
                loading: () => const SizedBox(
                  height: 140,
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (e, _) => SizedBox(
                  height: 60,
                  child: Center(
                    child: Text(
                      'Lỗi tải phân tích thanh toán: $e',
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Card 2: Doanh Thu Theo Danh Mục Sản Phẩm (Category Revenue Share)
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Flexible(
                    child: Text(
                      'Doanh thu theo danh mục',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              categoryAsync.when(
                data: (categories) => _buildCategoryProgressList(
                    context, categories, currencyFormat),
                loading: () => const SizedBox(
                  height: 120,
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (e, _) => SizedBox(
                  height: 60,
                  child: Center(
                    child: Text(
                      'Lỗi tải danh mục: $e',
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // Payment Donut Chart & Legend
  // ===========================================================================
  Widget _buildPaymentDonut(
    BuildContext context,
    PaymentBreakdown payment,
    NumberFormat format,
  ) {
    if (payment.totalAmount <= 0) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'Chưa có dữ liệu thanh toán trong kỳ',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
      );
    }

    final cashPct = payment.cashPercentage;
    final transferPct = payment.transferPercentage;
    final debtPct = payment.debtPercentage;

    final sections = <PieChartSectionData>[
      if (payment.cashAmount > 0)
        PieChartSectionData(
          color: AppColors.primary,
          value: payment.cashAmount,
          title: '${cashPct.toStringAsFixed(0)}%',
          radius: 36,
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.white,
          ),
        ),
      if (payment.transferAmount > 0)
        PieChartSectionData(
          color: AppColors.secondary,
          value: payment.transferAmount,
          title: '${transferPct.toStringAsFixed(0)}%',
          radius: 36,
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.white,
          ),
        ),
      if (payment.debtAmount > 0)
        PieChartSectionData(
          color: AppColors.chartOrange,
          value: payment.debtAmount,
          title: '${debtPct.toStringAsFixed(0)}%',
          radius: 36,
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.white,
          ),
        ),
    ];

    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        // Donut Chart
        SizedBox(
          width: 110,
          height: 110,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 26,
                  sectionsSpace: 2,
                ),
              ),
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),

        // Legend & Amounts
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPaymentLegendItem(
                context: context,
                color: AppColors.primary,
                label: 'Tiền mặt',
                amount: payment.cashAmount,
                percent: cashPct,
                format: format,
              ),
              const SizedBox(height: 8),
              _buildPaymentLegendItem(
                context: context,
                color: AppColors.secondary,
                label: 'Chuyển khoản / QR',
                amount: payment.transferAmount,
                percent: transferPct,
                format: format,
              ),
              const SizedBox(height: 8),
              _buildPaymentLegendItem(
                context: context,
                color: AppColors.chartOrange,
                label: 'Ghi nợ khách',
                amount: payment.debtAmount,
                percent: debtPct,
                format: format,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CustomersPage(
                        initialDebtFilter: CustomerDebtFilter.inDebt,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentLegendItem({
    required BuildContext context,
    required Color color,
    required String label,
    required double amount,
    required double percent,
    required NumberFormat format,
    VoidCallback? onTap,
  }) {
    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${format.format(amount)} đ',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '(${percent.toStringAsFixed(0)}%)',
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            const Icon(
              Icons.chevron_right,
              size: 14,
              color: AppColors.textMuted,
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: AppColors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: rowContent,
        ),
      );
    }

    return rowContent;
  }

  // ===========================================================================
  // Category Progress Bars List
  // ===========================================================================
  Widget _buildCategoryProgressList(
    BuildContext context,
    List<CategoryRevenueShare> categories,
    NumberFormat format,
  ) {
    if (categories.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: Text(
            'Chưa có dữ liệu danh mục trong kỳ',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
      );
    }

    final palette = [
      AppColors.primary,
      AppColors.secondary,
      AppColors.chartOrange,
      AppColors.chartPurple,
      AppColors.chartTeal,
      AppColors.supervisor,
    ];

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length > 5 ? 5 : categories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final cat = categories[index];
        final color = palette[index % palette.length];

        return Material(
          color: AppColors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ProductsPage(initialCategory: cat.categoryName),
                ),
              );
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                cat.categoryName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (cat.quantitySold > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '(${cat.quantitySold} sp)',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${cat.percentage.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.chevron_right,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (cat.percentage / 100).clamp(0.0, 1.0),
                      backgroundColor: AppColors.grey100,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
