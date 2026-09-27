import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/inventories/stock_in_receipts_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../application/suppliers/suppliers_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/store_resolver_helper.dart';
import '../../../domain/entities/supplier.dart';
import '../../common/widgets/scroll_aware_fab.dart';
import '../../common/widgets/date_grouped_list_view.dart';
import '../widgets/stock_in_receipt_card.dart';
import '../widgets/stock_in_receipt_detail_bottom_sheet.dart';
import 'import_inventory_page.dart';

/// Filter bar for stock-in receipts status: "Tất cả", "Đã hoàn thành", "Phiếu tạm", "Đã hủy".
class StockInReceiptsFilterBar extends StatelessWidget {
  final String selectedStatus;
  final ValueChanged<String> onStatusChanged;

  const StockInReceiptsFilterBar({
    super.key,
    required this.selectedStatus,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    const filters = [
      {'key': 'all', 'label': 'Tất cả', 'widgetKey': 'filter_all'},
      {
        'key': 'completed',
        'label': 'Đã hoàn thành',
        'widgetKey': 'filter_completed'
      },
      {'key': 'draft', 'label': 'Phiếu tạm', 'widgetKey': 'filter_draft'},
      {'key': 'cancelled', 'label': 'Đã hủy', 'widgetKey': 'filter_cancelled'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: filters.map((f) {
          final isSelected = selectedStatus == f['key'] ||
              (f['key'] == 'all' &&
                  (selectedStatus.isEmpty || selectedStatus == 'all'));
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              key: Key(f['widgetKey']!),
              label: Text(f['label']!),
              selected: isSelected,
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.grey100,
              showCheckmark: false,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? AppColors.white : AppColors.textPrimary,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: 0.8,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              onSelected: (_) => onStatusChanged(f['key']!),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Stock-in Receipts Management Screen (Phiếu nhập kho) according to KiotViet standards.
/// Displays consolidated import receipts, multi-dimensional filters, instant search,
/// and RBAC-governed cost-price protection.
class StockInReceiptsPage extends ConsumerStatefulWidget {
  const StockInReceiptsPage({super.key});

  @override
  ConsumerState<StockInReceiptsPage> createState() =>
      _StockInReceiptsPageState();
}

class _StockInReceiptsPageState extends ConsumerState<StockInReceiptsPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  Future<bool> _showDeleteDraftDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: const Text('Xóa phiếu tạm này?'),
        actions: [
          TextButton(
            key: const Key('btn_cancel_delete_draft'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            key: const Key('btn_confirm_delete_draft'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa', style: TextStyle(color: AppColors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _confirmDeleteDraft(
      BuildContext context, StockInReceipt receipt) async {
    final confirmed = await _showDeleteDraftDialog(context);
    if (confirmed && context.mounted) {
      await _executeDeleteDraft(context, receipt);
    }
  }

  Future<void> _executeDeleteDraft(
      BuildContext context, StockInReceipt receipt) async {
    try {
      final storeId =
          receipt.storeId ?? ref.read(currentStoreIdProvider) ?? 'store_001';
      await ref.read(deleteStockInReceiptUseCaseProvider).execute(
            storeId: storeId,
            receipt: receipt,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa phiếu tạm thành công')),
      );
      ref.invalidate(rawImportTransactionsStreamProvider);
      ref.invalidate(storedStockInReceiptsStreamProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi xóa phiếu tạm: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // Initialize search controller text from existing filter state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final filter = ref.read(stockInReceiptsFilterProvider);
      if (filter.searchQuery.isNotEmpty && _searchController.text.isEmpty) {
        _searchController.text = filter.searchQuery;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(stockInReceiptsFilterProvider);
    final filterNotifier = ref.read(stockInReceiptsFilterProvider.notifier);
    final receiptsAsync = ref.watch(filteredStockInReceiptsAsyncProvider);
    final canViewCostPrice = ref.watch(canViewCostPriceProvider);
    final user = ref.watch(authProvider);
    final canSwitchStore = user?.canSwitchStore ?? false;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.transparent,
        elevation: 0.5,
        title: const Text(
          'Phiếu nhập kho',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (filter.hasActiveFilters)
            IconButton(
              icon: const Icon(Icons.filter_alt_off_outlined,
                  color: AppColors.primary),
              tooltip: 'Đặt lại bộ lọc',
              onPressed: () {
                _searchController.clear();
                filterNotifier.resetFilters();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Search & Filter Bar ──
          Container(
            color: AppColors.white,
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Column(
              children: [
                // 1. Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                    height: 42,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Mã phiếu, nhà cung cấp, sản phẩm...',
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    size: 18, color: AppColors.grey400),
                                onPressed: () {
                                  _searchController.clear();
                                  filterNotifier.setSearchQuery('');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.surfaceLight,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 0, horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 1.2),
                        ),
                      ),
                      onChanged: (val) {
                        filterNotifier.setSearchQuery(val);
                        setState(() {});
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // 2. Status Filter Bar (Tất cả / Đã hoàn thành / Phiếu tạm / Đã hủy)
                StockInReceiptsFilterBar(
                  selectedStatus: filter.statusFilter,
                  onStatusChanged: (status) {
                    filterNotifier.setStatusFilter(status);
                  },
                ),

                const SizedBox(height: 8),

                // 3. Filter Chips Row (Horizontal Scroll)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      // Time Range Filter Chip
                      _buildTimeRangeChip(context, filter, filterNotifier),
                      const SizedBox(width: 8),

                      // Supplier Filter Chip
                      _buildSupplierChip(context, filter, filterNotifier),
                      const SizedBox(width: 8),

                      // Branch Filter Chip (if Admin)
                      if (canSwitchStore) ...[
                        _buildBranchChip(context, filter, filterNotifier),
                        const SizedBox(width: 8),
                      ],

                      // Reset chip if active filters exist
                      if (filter.hasActiveFilters)
                        ActionChip(
                          avatar: const Icon(Icons.close,
                              size: 14, color: AppColors.danger),
                          label: const Text(
                            'Xóa lọc',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          backgroundColor: AppColors.dangerLight,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          onPressed: () {
                            _searchController.clear();
                            filterNotifier.resetFilters();
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.dividerLight),

          // ── Receipts List & States ──
          Expanded(
            child: receiptsAsync.when(
              loading: () => _buildSkeletonLoading(),
              error: (err, stack) => _buildErrorState(err),
              data: (receipts) {
                if (receipts.isEmpty) {
                  return _buildEmptyState(context, filter, filterNotifier);
                }

                final totalSum =
                    receipts.fold(0.0, (sum, r) => sum + r.totalAmount);

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${receipts.length} phiếu nhập',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (canViewCostPrice) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Tổng: ${currencyFormat.format(totalSum)} đ',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: () async {
                          ref.invalidate(rawImportTransactionsStreamProvider);
                          ref.invalidate(storedStockInReceiptsStreamProvider);
                        },
                        child: DateGroupedListView<StockInReceipt>(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(
                              top: 4, bottom: 88, left: 12, right: 12),
                          items: receipts,
                          dateSelector: (r) => r.createdAt ?? r.date,
                          itemUnit: 'phiếu nhập',
                          itemAmountSelector:
                              canViewCostPrice ? (r) => r.totalAmount : null,
                          currencyFormat: currencyFormat,
                          itemBuilder: (context, receipt) {
                            final card = StockInReceiptCard(
                              receipt: receipt,
                              canViewCostPrice: canViewCostPrice,
                              onTap: () async {
                                if (receipt.isDraft) {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ImportInventoryPage(
                                        initialReceipt: receipt,
                                      ),
                                    ),
                                  );
                                  if (!context.mounted) return;
                                  ref.invalidate(
                                      rawImportTransactionsStreamProvider);
                                  ref.invalidate(
                                      storedStockInReceiptsStreamProvider);
                                } else {
                                  StockInReceiptDetailBottomSheet.show(
                                    context,
                                    receipt: receipt,
                                  );
                                }
                              },
                              onLongPress: receipt.isDraft
                                  ? () => _confirmDeleteDraft(context, receipt)
                                  : null,
                              onDeleteDraft: receipt.isDraft
                                  ? () => _confirmDeleteDraft(context, receipt)
                                  : null,
                            );

                            if (receipt.isDraft) {
                              return Dismissible(
                                key: Key('dismissible_draft_${receipt.id}'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.danger,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.delete,
                                          color: AppColors.white),
                                      SizedBox(width: 8),
                                      Text(
                                        'Xóa phiếu tạm',
                                        style: TextStyle(
                                          color: AppColors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                confirmDismiss: (_) async {
                                  return await _showDeleteDraftDialog(context);
                                },
                                onDismissed: (_) async {
                                  await _executeDeleteDraft(context, receipt);
                                },
                                child: card,
                              );
                            }

                            return card;
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: ScrollAwareFab(
        scrollController: _scrollController,
        child: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          icon: const Icon(Icons.add),
          label: const Text(
            'Tạo phiếu nhập',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ImportInventoryPage()),
            );
            if (!context.mounted) return;
            ref.invalidate(rawImportTransactionsStreamProvider);
          },
        ),
      ),
    );
  }

  // ── Time Range Filter Chip ──
  Widget _buildTimeRangeChip(
    BuildContext context,
    StockInReceiptsFilterState filter,
    StockInReceiptsFilterNotifier notifier,
  ) {
    String label;
    if (filter.timeRange == OverviewTimeRange.custom &&
        filter.customDateRange != null) {
      final startStr =
          DateFormat('dd/MM').format(filter.customDateRange!.start);
      final endStr = DateFormat('dd/MM').format(filter.customDateRange!.end);
      label = '$startStr - $endStr';
    } else {
      label = filter.timeRange.label;
    }

    final isFiltered = filter.timeRange != OverviewTimeRange.thisMonth;

    return FilterChip(
      avatar: Icon(
        Icons.calendar_today_outlined,
        size: 13,
        color: isFiltered ? AppColors.white : AppColors.primary,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isFiltered ? AppColors.white : AppColors.textPrimary,
        ),
      ),
      selected: isFiltered,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.grey100,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isFiltered ? AppColors.primary : AppColors.border,
          width: 0.8,
        ),
      ),
      onSelected: (_) => _showTimeRangeModal(context, filter, notifier),
    );
  }

  void _showTimeRangeModal(
    BuildContext context,
    StockInReceiptsFilterState filter,
    StockInReceiptsFilterNotifier notifier,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Chọn thời gian',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.today_outlined),
                  title: const Text('Hôm nay'),
                  trailing: filter.timeRange == OverviewTimeRange.today
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    notifier.setTimeRange(OverviewTimeRange.today);
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('Hôm qua'),
                  trailing: filter.timeRange == OverviewTimeRange.yesterday
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    notifier.setTimeRange(OverviewTimeRange.yesterday);
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.date_range_outlined),
                  title: const Text('7 ngày qua'),
                  trailing: filter.timeRange == OverviewTimeRange.last7Days
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    notifier.setTimeRange(OverviewTimeRange.last7Days);
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Tháng này (Mặc định)'),
                  trailing: filter.timeRange == OverviewTimeRange.thisMonth
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    notifier.setTimeRange(OverviewTimeRange.thisMonth);
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_calendar_outlined),
                  title: const Text('Tùy chọn khoảng ngày...'),
                  trailing: filter.timeRange == OverviewTimeRange.custom
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final initial = filter.customDateRange ??
                        DateTimeRange(
                          start:
                              DateTime.now().subtract(const Duration(days: 7)),
                          end: DateTime.now(),
                        );
                    final picked = await showDateRangePicker(
                      context: context,
                      initialDateRange: initial,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: AppColors.primary,
                              onPrimary: AppColors.white,
                              onSurface: AppColors.textPrimary,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      notifier.setCustomDateRange(picked);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Supplier Filter Chip ──
  Widget _buildSupplierChip(
    BuildContext context,
    StockInReceiptsFilterState filter,
    StockInReceiptsFilterNotifier notifier,
  ) {
    final suppliers = ref.watch(supplierListNotifierProvider).value ?? [];
    String supplierLabel = 'Nhà cung cấp';
    final bool isFiltered = filter.supplierId != null &&
        filter.supplierId!.isNotEmpty &&
        filter.supplierId != 'all';

    if (isFiltered) {
      for (final s in suppliers) {
        if (s.id == filter.supplierId) {
          supplierLabel = s.name;
          break;
        }
      }
    }

    return FilterChip(
      avatar: Icon(
        Icons.storefront_outlined,
        size: 13,
        color: isFiltered ? AppColors.white : AppColors.textSecondary,
      ),
      label: Text(
        supplierLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isFiltered ? AppColors.white : AppColors.textPrimary,
        ),
      ),
      selected: isFiltered,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.grey100,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isFiltered ? AppColors.primary : AppColors.border,
          width: 0.8,
        ),
      ),
      onSelected: (_) =>
          _showSupplierModal(context, filter, notifier, suppliers),
    );
  }

  void _showSupplierModal(
    BuildContext context,
    StockInReceiptsFilterState filter,
    StockInReceiptsFilterNotifier notifier,
    List<Supplier> suppliers,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredList = suppliers.where((s) {
              if (query.trim().isEmpty) return true;
              return s.name.toLowerCase().contains(query.toLowerCase()) ||
                  s.phone.contains(query) ||
                  s.code.toLowerCase().contains(query.toLowerCase());
            }).toList();

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.grey300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Lọc theo Nhà cung cấp',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Tìm nhà cung cấp...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (v) {
                          setModalState(() => query = v);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.apps_outlined),
                            title: const Text('Tất cả nhà cung cấp'),
                            trailing: filter.supplierId == null ||
                                    filter.supplierId == 'all'
                                ? const Icon(Icons.check,
                                    color: AppColors.primary)
                                : null,
                            onTap: () {
                              notifier.setSupplier(null);
                              Navigator.of(ctx).pop();
                            },
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ...filteredList.map((s) {
                            final isSelected = filter.supplierId == s.id;
                            return ListTile(
                              leading: const Icon(Icons.storefront_outlined),
                              title: Text(s.name),
                              subtitle: Text(
                                s.phone.isNotEmpty
                                    ? s.phone
                                    : (s.code.isNotEmpty ? s.code : ''),
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check,
                                      color: AppColors.primary)
                                  : null,
                              onTap: () {
                                notifier.setSupplier(s.id);
                                Navigator.of(ctx).pop();
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Branch Filter Chip ──
  Widget _buildBranchChip(
    BuildContext context,
    StockInReceiptsFilterState filter,
    StockInReceiptsFilterNotifier notifier,
  ) {
    final bool isFiltered = filter.storeId != null &&
        filter.storeId!.isNotEmpty &&
        filter.storeId != 'all';

    String branchLabel = 'Tất cả chi nhánh';
    if (isFiltered) {
      final norm = StoreResolverHelper.normalizeStoreId(filter.storeId);
      if (norm == 'store_001') {
        branchLabel = 'Chi nhánh Đông Thắng';
      } else if (norm == 'store_002') {
        branchLabel = 'Chi nhánh Thới Bình';
      } else {
        branchLabel = 'Chi nhánh ${filter.storeId}';
      }
    }

    return FilterChip(
      avatar: Icon(
        Icons.hub_outlined,
        size: 13,
        color: isFiltered ? AppColors.white : AppColors.textSecondary,
      ),
      label: Text(
        branchLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isFiltered ? AppColors.white : AppColors.textPrimary,
        ),
      ),
      selected: isFiltered,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.grey100,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isFiltered ? AppColors.primary : AppColors.border,
          width: 0.8,
        ),
      ),
      onSelected: (_) => _showBranchModal(context, filter, notifier),
    );
  }

  void _showBranchModal(
    BuildContext context,
    StockInReceiptsFilterState filter,
    StockInReceiptsFilterNotifier notifier,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Lọc theo Chi nhánh',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: const Text('Tất cả chi nhánh'),
                  trailing: filter.storeId == null || filter.storeId == 'all'
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    notifier.setStore('all');
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.storefront_outlined,
                      color: AppColors.branchDongThangText),
                  title: const Text('Chi nhánh Đông Thắng'),
                  trailing: filter.storeId == 'store_001'
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    notifier.setStore('store_001');
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.store_outlined,
                      color: AppColors.branchThoiBinhText),
                  title: const Text('Chi nhánh Thới Bình'),
                  trailing: filter.storeId == 'store_002'
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    notifier.setStore('store_002');
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Skeleton Loading ──
  Widget _buildSkeletonLoading() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          elevation: 0,
          color: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 130,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.grey200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Container(
                      width: 90,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.grey200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: 200,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 140,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.dividerLight),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 100,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.grey200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Container(
                      width: 110,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.grey200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Empty State ──
  Widget _buildEmptyState(
    BuildContext context,
    StockInReceiptsFilterState filter,
    StockInReceiptsFilterNotifier notifier,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 16),
            const Text(
              'Chưa có phiếu nhập kho nào',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filter.hasActiveFilters
                  ? 'Không tìm thấy kết quả phù hợp với các tiêu chí lọc hiện tại'
                  : 'Hãy tạo phiếu nhập kho đầu tiên để theo dõi xuất nhập tồn',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (filter.hasActiveFilters) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                ),
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Đặt lại bộ lọc'),
                onPressed: () {
                  _searchController.clear();
                  notifier.resetFilters();
                  setState(() {});
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Error State ──
  Widget _buildErrorState(Object err) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(
              'Lỗi tải dữ liệu: $err',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Thử lại'),
              onPressed: () {
                ref.invalidate(rawImportTransactionsStreamProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}
