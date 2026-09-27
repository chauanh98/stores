import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/reports/overview_kpi_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/overview_kpis.dart';
import '../../inventories/pages/import_inventory_page.dart';
import '../../products/pages/products_page.dart';

/// Sub-widget Trung Tâm Cảnh Báo Thông Minh & Tồn Kho (R3 - Smart Stock & Operation Alerts)
/// Hiển thị:
/// - Thẻ cảnh báo Hết hàng (tồn = 0) với click điều hướng sang ProductsPage
/// - Thẻ cảnh báo Sắp hết hàng (tồn <= 5) với click điều hướng sang ProductsPage
/// - Nút Nhập hàng nhanh dẫn tới ImportInventoryPage
/// - Tổng số lượng sản phẩm tồn kho và Tổng giá trị tồn theo giá vốn
class SmartStockAlertsCard extends ConsumerWidget {
  const SmartStockAlertsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAlertAsync = ref.watch(stockAlertSummaryProvider);
    final user = ref.watch(authProvider);
    final canViewCostPrice = user?.canViewCostPrice ?? false;

    return stockAlertAsync.when(
      data: (summary) => _buildContent(context, summary, canViewCostPrice),
      loading: () => _buildLoadingCard(),
      error: (error, _) => _buildErrorCard(error),
    );
  }

  Widget _buildContent(
    BuildContext context,
    StockAlertSummary summary,
    bool canViewCostPrice,
  ) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Container(
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
          // Tiêu đề Section & Nút Nhập kho nhanh
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.warning,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Cảnh báo kho & Vận hành',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ImportInventoryPage(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.secondary.withOpacity(0.3),
                      width: 0.8,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_shopping_cart_rounded,
                        size: 13,
                        color: AppColors.secondary,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Nhập hàng',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 2 Thẻ cảnh báo tương tác: Hết hàng & Sắp hết hàng
          Row(
            children: [
              // Thẻ Hết hàng (Out of stock = 0)
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProductsPage(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: summary.outOfStockCount > 0
                          ? AppColors.dangerLight
                          : AppColors.grey50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: summary.outOfStockCount > 0
                            ? AppColors.danger.withOpacity(0.4)
                            : AppColors.grey200,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'Hết hàng',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: summary.outOfStockCount > 0
                                      ? AppColors.danger
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.error_outline_rounded,
                              size: 16,
                              color: summary.outOfStockCount > 0
                                  ? AppColors.danger
                                  : AppColors.textMuted,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${summary.outOfStockCount}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: summary.outOfStockCount > 0
                                    ? AppColors.danger
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'mặt hàng',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: summary.outOfStockCount > 0
                                      ? AppColors.danger.withOpacity(0.8)
                                      : AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Thẻ Sắp hết hàng (Low stock <= 5)
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProductsPage(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: summary.lowStockCount > 0
                          ? AppColors.warningLight
                          : AppColors.grey50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: summary.lowStockCount > 0
                            ? AppColors.warning.withOpacity(0.4)
                            : AppColors.grey200,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'Sắp hết hàng',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: summary.lowStockCount > 0
                                      ? AppColors.warningMedium
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: summary.lowStockCount > 0
                                  ? AppColors.warningMedium
                                  : AppColors.textMuted,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${summary.lowStockCount}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: summary.lowStockCount > 0
                                    ? AppColors.warningMedium
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'mặt hàng',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: summary.lowStockCount > 0
                                      ? AppColors.warningMedium
                                      : AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const Divider(height: 24, color: AppColors.divider),

          // Tổng kết kho: Số lượng tồn & Định giá vốn
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tổng tồn kho',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${NumberFormat('#,###').format(summary.totalItemCount)} sản phẩm',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (canViewCostPrice)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Giá trị kho (Giá vốn)',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${currencyFormat.format(summary.totalInventoryCost)} đ',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      height: 120,
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
          'Lỗi tải cảnh báo tồn kho: $error',
          style: const TextStyle(color: AppColors.danger, fontSize: 12),
        ),
      ),
    );
  }
}
