import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/store_resolver_helper.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/order.dart';
import '../../common/widgets/error_view.dart';
import '../../common/widgets/loading_indicator.dart';
import '../../common/widgets/date_grouped_list_view.dart';

/// Prominent, neat Store Badge displaying the branch where an order was created.
class StoreBadge extends StatelessWidget {
  final String? storeId;
  final String? storeName;

  const StoreBadge({
    super.key,
    required this.storeId,
    this.storeName,
  });

  @override
  Widget build(BuildContext context) {
    final norm = StoreResolverHelper.normalizeStoreId(storeId);
    Color textColor;
    Color bgColor;
    Color borderColor;
    String label;
    IconData iconData;

    if (norm == 'store_001') {
      textColor = AppColors.branchDongThangText;
      bgColor = AppColors.branchDongThangBg;
      borderColor = AppColors.branchDongThangBorder;
      label = storeName ?? 'Chi nhánh Đông Thắng';
      iconData = Icons.storefront_outlined;
    } else if (norm == 'store_002') {
      textColor = AppColors.branchThoiBinhText;
      bgColor = AppColors.branchThoiBinhBg;
      borderColor = AppColors.branchThoiBinhBorder;
      label = storeName ?? 'Chi nhánh Thới Bình';
      iconData = Icons.store_outlined;
    } else {
      textColor = AppColors.primary;
      bgColor = AppColors.primary.withOpacity(0.1);
      borderColor = AppColors.primary.withOpacity(0.25);
      label = storeName ??
          (storeId != null && storeId!.isNotEmpty
              ? 'Chi nhánh $storeId'
              : 'Chi nhánh khác');
      iconData = Icons.storefront_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(iconData, size: 13, color: textColor),
          const SizedBox(width: 3.5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerTransactionsPage extends ConsumerStatefulWidget {
  final Customer customer;

  const CustomerTransactionsPage({super.key, required this.customer});

  @override
  ConsumerState<CustomerTransactionsPage> createState() =>
      _CustomerTransactionsPageState();
}

class _CustomerTransactionsPageState
    extends ConsumerState<CustomerTransactionsPage> {
  String? _selectedStoreId;

  String _getStoreName(String sId, Map<String, String> availableStores) {
    final norm = StoreResolverHelper.normalizeStoreId(sId);
    if (availableStores.containsKey(norm)) return availableStores[norm]!;
    if (availableStores.containsKey(sId)) return availableStores[sId]!;
    if (norm == 'store_001') return 'Chi nhánh Đông Thắng';
    if (norm == 'store_002') return 'Chi nhánh Thới Bình';
    return 'Chi nhánh $sId';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final customerOrdersAsync =
        ref.watch(customerOrdersProvider(widget.customer.id));

    final user = ref.watch(authProvider);
    final isAdmin = user == null || user.canSwitchStore || user.isAdmin;
    final availableStores =
        ref.watch(availableStoresProvider).valueOrNull ?? {};

    final staffStoreId = user != null
        ? (StoreResolverHelper.normalizeStoreId(user.storeId).isNotEmpty
            ? StoreResolverHelper.normalizeStoreId(user.storeId)
            : 'store_001')
        : 'store_001';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          l10n.transactions,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.white,
      ),
      body: customerOrdersAsync.when(
        data: (orders) {
          final sortedOrders = List<Order>.from(orders)
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          // Calculate active filter
          final activeFilter =
              isAdmin ? (_selectedStoreId ?? 'all') : staffStoreId;

          // Prepare filter options
          final Map<String, String> branchOptions = {
            'all': 'Tất cả chi nhánh',
            'store_001': 'Chi nhánh Đông Thắng',
            'store_002': 'Chi nhánh Thới Bình',
          };
          for (final entry in availableStores.entries) {
            final norm = StoreResolverHelper.normalizeStoreId(entry.key);
            if (norm.isNotEmpty && !branchOptions.containsKey(norm)) {
              branchOptions[norm] = entry.value;
            }
          }
          for (final o in sortedOrders) {
            final norm = StoreResolverHelper.normalizeStoreId(o.storeId);
            if (norm.isNotEmpty && !branchOptions.containsKey(norm)) {
              branchOptions[norm] = 'Chi nhánh $norm';
            }
          }

          final List<MapEntry<String, String>> filterOptions;
          if (isAdmin) {
            filterOptions = branchOptions.entries.toList();
          } else {
            final staffStoreName = branchOptions[staffStoreId] ??
                _getStoreName(staffStoreId, availableStores);
            filterOptions = [MapEntry(staffStoreId, staffStoreName)];
          }

          // Count orders per filter
          final Map<String, int> counts = {
            'all': sortedOrders.length,
          };
          for (final opt in branchOptions.entries) {
            if (opt.key == 'all') continue;
            counts[opt.key] = sortedOrders.where((o) {
              final norm = StoreResolverHelper.normalizeStoreId(o.storeId);
              return norm == opt.key;
            }).length;
          }

          // Filter displayed orders
          final List<Order> displayedOrders;
          if (activeFilter == 'all') {
            displayedOrders = sortedOrders;
          } else {
            displayedOrders = sortedOrders.where((o) {
              final norm = StoreResolverHelper.normalizeStoreId(o.storeId);
              return norm == activeFilter;
            }).toList();
          }

          final activeDisplayedOrders =
              displayedOrders.where((o) => !o.isCancelled);
          final totalSum = activeDisplayedOrders.fold<double>(
            0.0,
            (sum, item) => sum + item.total,
          );

          // If 'all' is selected and no orders in stream yet, fall back to customer.displayTotalSales
          final displayTotal = activeFilter == 'all'
              ? (sortedOrders.isNotEmpty
                  ? totalSum
                  : widget.customer.displayTotalSales)
              : totalSum;

          return Column(
            children: [
              // Summary Header Bar
              Container(
                color: AppColors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              l10n.totalSalesAndReturns,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down,
                              color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      currencyFormat.format(displayTotal),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),

              // Local Store Filter Bar
              Container(
                color: AppColors.white,
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: filterOptions.map((opt) {
                      final filterKey = opt.key;
                      final filterName = opt.value;
                      final count = counts[filterKey] ?? 0;
                      final isSelected = activeFilter == filterKey;

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: ValueKey('store_filter_$filterKey'),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          showCheckmark: false,
                          label: Text('$filterName ($count)'),
                          labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected
                                ? AppColors.white
                                : AppColors.textPrimary,
                          ),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.grey100,
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.border,
                            width: 1.0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onSelected: isAdmin
                              ? (selected) {
                                  if (selected) {
                                    setState(() {
                                      _selectedStoreId = filterKey;
                                    });
                                  }
                                }
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // Transaction Count Subheader
              Container(
                width: double.infinity,
                color: AppColors.background,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  '${displayedOrders.length} ${l10n.transactions.toLowerCase()}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              // Orders List
              Expanded(
                child: displayedOrders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.receipt_long_outlined,
                                size: 56, color: AppColors.grey500),
                            const SizedBox(height: 12),
                            Text(
                              l10n.noTransactionsYet,
                              style: const TextStyle(
                                  fontSize: 16, color: AppColors.grey500),
                            ),
                          ],
                        ),
                      )
                    : DateGroupedListView<Order>(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        items: displayedOrders,
                        dateSelector: (o) => o.createdAt,
                        itemUnit: 'đơn hàng',
                        itemAmountSelector: (o) =>
                            o.isCancelled ? 0.0 : o.total,
                        currencyFormat: currencyFormat,
                        itemBuilder: (context, order) {
                          final dateStr = DateFormat('dd/MM/yyyy HH:mm')
                              .format(order.createdAt);
                          final staffName = order.createdByName ??
                              order.createdBy ??
                              widget.customer.createdBy ??
                              'Nhân viên';
                          final itemsSummary =
                              order.items.map((e) => e.productName).join(', ');

                          String paymentMethod;
                          if (order.paymentMethod
                                  .toLowerCase()
                                  .contains('transfer') ||
                              order.paymentMethod
                                  .toLowerCase()
                                  .contains('chuyển khoản')) {
                            paymentMethod = l10n.paymentMethodTransfer;
                          } else if (order.paymentMethod
                                  .toLowerCase()
                                  .contains('cash') ||
                              order.paymentMethod
                                  .toLowerCase()
                                  .contains('tiền mặt')) {
                            paymentMethod = l10n.cash;
                          } else {
                            paymentMethod = order.paymentMethod.isNotEmpty
                                ? order.paymentMethod
                                : l10n.cash;
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Row 1: Order ID + StoreBadge
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Flexible(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              order.id,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: AppColors.textPrimary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          InkWell(
                                            onTap: () {
                                              Clipboard.setData(ClipboardData(
                                                  text: order.id));
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(l10n
                                                        .copyInvoiceCodeSuccess(
                                                            order.id))),
                                              );
                                            },
                                            child: const Padding(
                                              padding: EdgeInsets.all(2.0),
                                              child: Icon(Icons.copy_rounded,
                                                  size: 14,
                                                  color:
                                                      AppColors.textTertiary),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Wrap(
                                        alignment: WrapAlignment.end,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          if (order.isCancelled)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.dangerLightest,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'Đã hủy',
                                                style: TextStyle(
                                                  color: AppColors.dangerDeep,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          if (order.discount > 0)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.warningLight,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                        maxWidth: 140),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    'Giảm: -${currencyFormat.format(order.discount)} đ',
                                                    style: const TextStyle(
                                                      color:
                                                          AppColors.warningDeep,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxWidth: 140),
                                            child: StoreBadge(
                                              storeId: order.storeId,
                                              storeName: availableStores[
                                                  StoreResolverHelper
                                                      .normalizeStoreId(
                                                          order.storeId)],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Row 2: Date + Staff + Amount
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$dateStr · $staffName',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 130),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          currencyFormat.format(order.total),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: order.isCancelled
                                                ? AppColors.textTertiary
                                                : AppColors.primary,
                                            decoration: order.isCancelled
                                                ? TextDecoration.lineThrough
                                                : TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // Row 3: Items summary + Payment Method
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        itemsSummary.isNotEmpty
                                            ? itemsSummary
                                            : l10n.noTransactionsYet,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textPrimary,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      paymentMethod,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const LoadingIndicator(),
        error: (err, _) => ErrorView(err),
      ),
    );
  }
}
