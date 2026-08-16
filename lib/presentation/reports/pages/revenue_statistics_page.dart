import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/reports/revenue_providers.dart';
import '../../../domain/entities/revenue_report.dart';

class RevenueStatisticsPage extends ConsumerStatefulWidget {
  const RevenueStatisticsPage({super.key});

  @override
  ConsumerState<RevenueStatisticsPage> createState() =>
      _RevenueStatisticsPageState();
}

class _RevenueStatisticsPageState extends ConsumerState<RevenueStatisticsPage> {
  DateTime _selectedDate = DateTime.now();
  DateTimeRange? _selectedDateRange;
  bool _isRangeMode = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.revenue),
        actions: [
          IconButton(
            icon: Icon(_isRangeMode ? Icons.calendar_today : Icons.date_range),
            onPressed: _toggleDateMode,
          ),
        ],
      ),
      body: Column(
        children: [
          // Date selector
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isRangeMode ? l10n.selectDateRange : l10n.selectDate,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (_isRangeMode) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _buildDateRangeButton(),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: _buildDateButton(),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Revenue data
          Expanded(
            child:
                _isRangeMode ? _buildRevenueSummary() : _buildRevenueReport(),
          ),
        ],
      ),
    );
  }

  Widget _buildDateButton() {
    return InkWell(
      onTap: _selectDate,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              DateFormat('dd/MM/yyyy').format(_selectedDate),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeButton() {
    final l10n = AppLocalizations.of(context)!;

    return InkWell(
      onTap: _selectDateRange,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.date_range,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              _selectedDateRange != null
                  ? '${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.end)}'
                  : l10n.selectDateRange,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueReport() {
    final l10n = AppLocalizations.of(context)!;

    return Consumer(
      builder: (context, ref, child) {
        final revenueAsync = ref.watch(revenueByDateProvider(_selectedDate));

        return revenueAsync.when(
          data: (report) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryCard(report),
                const SizedBox(height: 16),
                _buildProductRevenueCard(report.productRevenues),
              ],
            ),
          ),
          loading: () => const LoadingIndicator(),
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: $error'),
                ElevatedButton(
                  onPressed: () =>
                      ref.invalidate(revenueByDateProvider(_selectedDate)),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRevenueSummary() {
    final l10n = AppLocalizations.of(context)!;

    if (_selectedDateRange == null) {
      return Center(
        child: Text(l10n.pleaseSelectDateRange),
      );
    }

    return Consumer(
      builder: (context, ref, child) {
        final summaryAsync =
            ref.watch(revenueByDateRangeProvider(_selectedDateRange!));

        return summaryAsync.when(
          data: (summary) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryOverviewCard(summary),
                const SizedBox(height: 16),
                _buildDailyReportsCard(summary.dailyReports),
              ],
            ),
          ),
          loading: () => const LoadingIndicator(),
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: $error'),
                ElevatedButton(
                  onPressed: () => ref.invalidate(
                      revenueByDateRangeProvider(_selectedDateRange!)),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(RevenueReport report) {
    final l10n = AppLocalizations.of(context)!;
    final canViewCostPrice = ref.watch(authProvider)?.canViewCostPrice ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.revenueSummary} ${DateFormat('dd/MM/yyyy').format(report.date)}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    l10n.revenue,
                    NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                        .format(report.totalRevenue),
                    Colors.green,
                    Icons.attach_money,
                  ),
                ),
                if (canViewCostPrice) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricCard(
                      l10n.expense,
                      NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                          .format(report.totalCost),
                      Colors.red,
                      Icons.shopping_cart,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (canViewCostPrice) ...[
                  Expanded(
                    child: _buildMetricCard(
                      l10n.profit,
                      NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                          .format(report.profit),
                      report.profit >= 0 ? Colors.blue : Colors.orange,
                      Icons.trending_up,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _buildMetricCard(
                    l10n.orders,
                    '${report.totalOrders}',
                    Colors.purple,
                    Icons.receipt,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryOverviewCard(RevenueSummary summary) {
    final l10n = AppLocalizations.of(context)!;
    final canViewCostPrice = ref.watch(authProvider)?.canViewCostPrice ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.overview} ${DateFormat('dd/MM/yyyy').format(summary.startDate)} - ${DateFormat('dd/MM/yyyy').format(summary.endDate)}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    l10n.totalRevenue,
                    NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                        .format(summary.totalRevenue),
                    Colors.green,
                    Icons.attach_money,
                  ),
                ),
                if (canViewCostPrice) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricCard(
                      l10n.totalExpense,
                      NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                          .format(summary.totalCost),
                      Colors.red,
                      Icons.shopping_cart,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (canViewCostPrice) ...[
                  Expanded(
                    child: _buildMetricCard(
                      l10n.totalProfit,
                      NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                          .format(summary.totalProfit),
                      summary.totalProfit >= 0 ? Colors.blue : Colors.orange,
                      Icons.trending_up,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _buildMetricCard(
                    l10n.totalOrders,
                    '${summary.totalOrders}',
                    Colors.purple,
                    Icons.receipt,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
      String title, String value, Color color, IconData icon) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProductRevenueCard(List<ProductRevenue> productRevenues) {
    final l10n = AppLocalizations.of(context)!;

    if (productRevenues.isEmpty) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.inventory_2, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  l10n.notFound,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.revenueByProduct,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ...productRevenues.map((pr) => _buildProductRevenueItem(pr)),
          ],
        ),
      ),
    );
  }

  Widget _buildProductRevenueItem(ProductRevenue pr) {
    final l10n = AppLocalizations.of(context)!;
    final canViewCostPrice = ref.watch(authProvider)?.canViewCostPrice ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pr.productName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  '${l10n.quantity}: ${pr.quantitySold}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Doanh thu theo sản phẩm
                Text(
                  '${l10n.revenue}: ${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(pr.revenue)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.right,
                ),
                if (canViewCostPrice) ...[
                  // Giá vốn (FIFO) theo sản phẩm
                  Text(
                    '${l10n.expense}: ${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(pr.cost)}',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.right,
                  ),
                  // Lãi theo sản phẩm
                  Text(
                    '${l10n.profit}: ${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(pr.profit)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: pr.profit >= 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.right,
                  ),
                  // Tỷ suất lãi theo sản phẩm
                  Text(
                    '${pr.profitMargin.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: pr.profit >= 0 ? Colors.green : Colors.red,
                        ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyReportsCard(List<RevenueReport> dailyReports) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.dailyReport,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ...dailyReports.map((report) => _buildDailyReportItem(report)),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyReportItem(RevenueReport report) {
    final l10n = AppLocalizations.of(context)!;
    final canViewCostPrice = ref.watch(authProvider)?.canViewCostPrice ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                DateFormat('dd/MM/yyyy').format(report.date),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Text(
              NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                  .format(report.totalRevenue),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (canViewCostPrice) ...[
              const SizedBox(width: 16),
              Text(
                NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                    .format(report.profit),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: report.profit >= 0 ? Colors.blue : Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(width: 16),
            Text(
              '${report.totalOrders} ${l10n.orders}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleDateMode() {
    setState(() {
      _isRangeMode = !_isRangeMode;
      if (!_isRangeMode) {
        _selectedDateRange = null;
      }
    });
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() {
        _selectedDate = date;
      });
    }
  }

  Future<void> _selectDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );
    if (range != null) {
      setState(() {
        _selectedDateRange = range;
      });
    }
  }
}
