import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/reports/overview_kpi_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../application/reports/revenue_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/kpi_metrics_section.dart';
import '../widgets/overview_filter_bar.dart';
import '../widgets/overview_header.dart';
import '../widgets/payment_category_breakdown_section.dart';
import '../widgets/quick_actions_bar.dart';
import '../widgets/recent_activity_feed.dart';
import '../widgets/revenue_chart_section.dart';
import '../widgets/smart_stock_alerts_card.dart';
import '../widgets/top_rankings_section.dart';

/// Coordinator Page cho Tab Tổng quan (Overview Page) chuẩn KiotViet Pro
/// Điều phối và lắp ráp 9 modular sub-widgets với kiến trúc Clean Architecture:
/// - OverviewHeader: Logo, Store selection, Sync status
/// - OverviewFilterBar: Bộ lọc thời gian & chi nhánh
/// - QuickActionsBar (R6): Thanh 5 lối tắt tác vụ nhanh
/// - KPIMetricsSection (R1): Bộ chỉ số kinh doanh toàn diện, % tăng trưởng cùng kỳ, Công nợ khách
/// - SmartStockAlertsCard (R3): Cảnh báo tồn kho & Định giá vốn
/// - RevenueChartSection (R2): Biểu đồ 24h giờ cao điểm & Biểu đồ cột xếp chồng đa chi nhánh
/// - PaymentCategoryBreakdownSection (R4): Donut phương thức thanh toán & Tỷ trọng danh mục
/// - TopRankingsSection (R5): Top 5/10 bán chạy & Top khách hàng chi tiêu
/// - RecentActivityFeed (R6): Feed giao dịch gần nhất
///
/// Hỗ trợ Responsive:
/// - Mobile (width <= 600px): Cuộn dọc 1 cột tối ưu trải nghiệm
/// - Tablet / Desktop (width > 600px): Bố cục lưới 2 cột cân đối (60% / 40%)
class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  Future<void> _refreshAll(WidgetRef ref) async {
    final activeRange = ref.read(overviewActiveDateRangeProvider);
    ref.invalidate(revenueByDateRangeProvider(activeRange));
    ref.invalidate(overviewKPIsProvider);
    ref.invalidate(hourlyRevenueListProvider);
    ref.invalidate(paymentBreakdownProvider);
    ref.invalidate(categoryRevenueShareProvider);
    ref.invalidate(stockAlertSummaryProvider);
    ref.invalidate(topSellingProductsRankingProvider);
    ref.invalidate(topCustomersRankingProvider);
    ref.invalidate(recentOrdersFeedProvider);
    ref.invalidate(allStoresProductsProvider);
    ref.invalidate(customerListNotifierProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refreshAll(ref),
          color: AppColors.primary,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWideScreen = constraints.maxWidth > 600;

              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // Sticky Header & Filter Bar
                  const SliverToBoxAdapter(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OverviewHeader(),
                        OverviewFilterBar(),
                        Divider(height: 1, color: AppColors.divider),
                      ],
                    ),
                  ),

                  // Main Dashboard Body
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                    sliver: SliverToBoxAdapter(
                      child: isWideScreen
                          ? _buildWideScreenLayout(context)
                          : _buildMobileLayout(context),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. Mobile Layout (<= 600px): Single Column Flow
  // ===========================================================================
  Widget _buildMobileLayout(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Quick Actions Bar (R6)
        QuickActionsBar(),
        SizedBox(height: 12),

        // 2. Comprehensive KPIs & Growth & Customer Debt (R1)
        KPIMetricsSection(),
        SizedBox(height: 12),

        // 3. Smart Stock & Operation Alerts (R3)
        SmartStockAlertsCard(),
        SizedBox(height: 12),

        // 4. Multi-dimensional Revenue Visualizations & Peak Hour (R2)
        RevenueChartSection(),
        SizedBox(height: 12),

        // 5. Payment & Category Breakdown (R4)
        PaymentCategoryBreakdownSection(),
        SizedBox(height: 12),

        // 6. Top Rankings (R5)
        TopRankingsSection(),
        SizedBox(height: 12),

        // 7. Recent Activity Feed (R6)
        RecentActivityFeed(),
      ],
    );
  }

  // ===========================================================================
  // 2. Wide Screen Layout (> 600px): Balanced 2-Column Grid
  // ===========================================================================
  Widget _buildWideScreenLayout(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cột Trái (Left Column - 50% Width): KPIs, Charts, Breakdowns
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              QuickActionsBar(),
              SizedBox(height: 14),
              KPIMetricsSection(),
              SizedBox(height: 14),
              RevenueChartSection(),
              SizedBox(height: 14),
              PaymentCategoryBreakdownSection(),
            ],
          ),
        ),

        SizedBox(width: 14),

        // Cột Phải (Right Column - 50% Width): Alerts, Rankings, Feed
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SmartStockAlertsCard(),
              SizedBox(height: 14),
              TopRankingsSection(),
              SizedBox(height: 14),
              RecentActivityFeed(),
            ],
          ),
        ),
      ],
    );
  }
}
