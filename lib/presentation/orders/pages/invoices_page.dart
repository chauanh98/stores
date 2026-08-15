import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/presentation/common/widgets/error_view.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/customers/customers_providers.dart';
import '../../../application/orders/cart_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/product.dart';
import '../../../application/settings/store_payment_config_providers.dart';
import '../../../core/utils/invoice_print_helper.dart';
import '../../customers/pages/customer_detail_page.dart';
import '../../products/pages/product_detail_page.dart';
import 'pos_checkout_page.dart';

class InvoicesPage extends ConsumerStatefulWidget {
  const InvoicesPage({super.key});

  @override
  ConsumerState<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends ConsumerState<InvoicesPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatusFilter = 'all'; // 'all', 'completed', 'draft'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final activeRange = ref.watch(invoicesActiveDateRangeProvider);
    final timeRangeType = ref.watch(invoicesTimeRangeTypeProvider);
    final selectedBranchIds = ref.watch(selectedBranchesProvider);

    // Watch all orders for the active date range (including multi-branch support)
    final ordersAsync =
        ref.watch(allBranchesOrdersByDateRangeProvider(activeRange));
    final customersAsync = ref.watch(customerListNotifierProvider);

    final currencyFormat = NumberFormat('#,###', 'vi_VN');

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
    if (selectedBranchIds.length == mockBranches.length) {
      branchLabel = l10n.allBranches;
    } else if (selectedBranchIds.length == 1) {
      branchLabel =
          mockBranches.firstWhere((b) => b.id == selectedBranchIds.first).name;
    } else {
      branchLabel = '${selectedBranchIds.length} chi nhánh';
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.invoicesTitle,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () {},
          )
        ],
      ),
      body: Column(
        children: [
          // 1. Thanh tìm kiếm hoá đơn
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchInvoicesHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                fillColor: Colors.white,
                filled: true,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),

          // 2. Thanh bộ lọc (Thời gian & Chi nhánh)
          _buildFiltersBar(context, dateLabel, branchLabel),

          // Bộ lọc trạng thái hoá đơn (Tất cả, Đã thanh toán, Lưu tạm)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: Row(
              children: [
                _buildStatusFilterChip('all', l10n.all),
                const SizedBox(width: 8),
                _buildStatusFilterChip('completed', l10n.paid),
                const SizedBox(width: 8),
                _buildStatusFilterChip('draft', l10n.draft),
              ],
            ),
          ),

          // 3. Nội dung hoá đơn
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                return customersAsync.when(
                  data: (customers) {
                    final branchFilteredOrders = orders;

                    // Áp dụng bộ lọc trạng thái
                    final statusFilteredOrders =
                        branchFilteredOrders.where((order) {
                      if (_selectedStatusFilter == 'all') return true;
                      return order.status == _selectedStatusFilter;
                    }).toList();

                    // Tìm kiếm
                    final searchFilteredOrders =
                        statusFilteredOrders.where((order) {
                      final query = _searchQuery.toLowerCase().trim();
                      if (query.isEmpty) return true;

                      final cName =
                          _getCustomerName(context, customers, order.customerId)
                              .toLowerCase();
                      return order.id.toLowerCase().contains(query) ||
                          cName.contains(query);
                    }).toList();

                    // Sắp xếp đơn mới nhất lên đầu
                    searchFilteredOrders
                        .sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    final totalInvoices = searchFilteredOrders.length;
                    final totalRevenue = searchFilteredOrders.fold(
                        0.0, (sum, o) => sum + o.total);

                    return Column(
                      children: [
                        // Thẻ thống kê tổng tiền hoá đơn đang lọc
                        _buildTotalSummaryCard(
                            totalInvoices, totalRevenue, currencyFormat, l10n),

                        // Danh sách
                        Expanded(
                          child: searchFilteredOrders.isEmpty
                              ? Center(child: Text(l10n.noInvoicesFound))
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  itemCount: searchFilteredOrders.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final order = searchFilteredOrders[index];
                                    final customerName = _getCustomerName(
                                        context, customers, order.customerId);

                                    // Phương thức thanh toán đọc từ Firebase
                                    final isTransfer =
                                        order.paymentMethod == 'transfer';
                                    final paymentMethodStr =
                                        isTransfer ? l10n.transfer : l10n.cash;

                                    return InkWell(
                                      onTap: () =>
                                          _showInvoiceDetailsBottomSheet(
                                              context,
                                              ref,
                                              order,
                                              customerName),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: AppColors.border),
                                        ),
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  customerName,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                      color: Colors.black87),
                                                ),
                                                Text(
                                                  '${currencyFormat.format(order.total)} đ',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: AppColors.primary,
                                                      fontSize: 14),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      l10n.orderIdLabel(
                                                          order.id),
                                                      style: const TextStyle(
                                                          color: Colors.black54,
                                                          fontSize: 12),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      DateFormat(
                                                              'dd/MM/yyyy HH:mm')
                                                          .format(
                                                              order.createdAt),
                                                      style: const TextStyle(
                                                          color: Colors.black38,
                                                          fontSize: 11),
                                                    ),
                                                  ],
                                                ),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 8,
                                                          vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: order.status ==
                                                                'draft'
                                                            ? Colors.orange
                                                                .withOpacity(
                                                                    0.06)
                                                            : Colors.green
                                                                .withOpacity(
                                                                    0.06),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: Text(
                                                        order.status == 'draft'
                                                            ? l10n.draft
                                                            : l10n.paid,
                                                        style: TextStyle(
                                                          color: order.status ==
                                                                  'draft'
                                                              ? Colors.orange
                                                              : Colors.green,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 8,
                                                          vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.primary
                                                            .withOpacity(0.06),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: Text(
                                                        paymentMethodStr,
                                                        style: const TextStyle(
                                                            color: AppColors
                                                                .primary,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              ],
                                            )
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(child: LoadingIndicator()),
                  error: (e, _) => Center(child: ErrorView(e)),
                );
              },
              loading: () => const Center(child: LoadingIndicator()),
              error: (e, _) => Center(child: ErrorView(e)),
            ),
          ),
        ],
      ),
    );
  }

  // Thanh bộ lọc (Thời gian & Chi nhánh)
  Widget _buildFiltersBar(
      BuildContext context, String dateText, String branchText) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
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
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down,
                      color: AppColors.primary, size: 18),
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
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down,
                    color: Colors.black54, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Thẻ tổng kết trên cùng danh sách hoá đơn
  Widget _buildTotalSummaryCard(int count, double totalRevenue,
      NumberFormat format, AppLocalizations l10n) {
    return Container(
      color: AppColors.primary.withOpacity(0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l10n.totalInvoices(count),
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87),
          ),
          Text(
            '${format.format(totalRevenue)} đ',
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.primary),
          )
        ],
      ),
    );
  }

  // Tra cứu tên khách hàng dựa trên ID
  String _getCustomerName(
      BuildContext context, List<Customer> customers, String id) {
    final l10n = AppLocalizations.of(context)!;
    if (id == 'khach_le' || id.isEmpty) return l10n.retailCustomer;
    final match = customers.firstWhere((c) => c.id == id,
        orElse: () => Customer(
            id: '',
            name: l10n.retailCustomer,
            phone: '',
            email: '',
            address: '',
            purchases: const []));
    return match.name;
  }

  // Hộp thoại Bottom Sheet lọc Thời gian
  void _showDateRangeFilterBottomSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
            final activeType = sheetRef.watch(invoicesTimeRangeTypeProvider);
            return SafeArea(
              child: SingleChildScrollView(
                child: Container(
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
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check,
                                  color: AppColors.primary)
                              : null,
                          onTap: () async {
                            Navigator.pop(consumerContext);
                            if (type == OverviewTimeRange.custom) {
                              final initialRange =
                                  ref.read(invoicesCustomDateRangeProvider);
                              final now = DateTime.now();
                              // Chuẩn hóa initialRange về start of day để tránh lỗi của Flutter date picker
                              final normalizedInitialRange = DateTimeRange(
                                start: DateTime(
                                    initialRange.start.year,
                                    initialRange.start.month,
                                    initialRange.start.day),
                                end: DateTime(
                                    initialRange.end.year,
                                    initialRange.end.month,
                                    initialRange.end.day),
                              );
                              final pickedRange = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2020),
                                lastDate:
                                    DateTime(now.year, now.month, now.day),
                                initialDateRange: normalizedInitialRange,
                              );
                              if (pickedRange != null) {
                                ref
                                    .read(invoicesCustomDateRangeProvider
                                        .notifier)
                                    .state = pickedRange;
                                ref
                                    .read(
                                        invoicesTimeRangeTypeProvider.notifier)
                                    .state = OverviewTimeRange.custom;
                              }
                            } else {
                              ref
                                  .read(invoicesTimeRangeTypeProvider.notifier)
                                  .state = type;
                            }
                          },
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Hộp thoại Bottom Sheet lọc Chi nhánh
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

  Widget _buildStatusFilterChip(String value, String label) {
    final isSelected = _selectedStatusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedStatusFilter = value;
          });
        }
      },
      selectedColor: AppColors.primary.withOpacity(0.12),
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primary : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  void _showInvoiceDetailsBottomSheet(
    BuildContext context,
    WidgetRef ref,
    Order order,
    String customerName,
  ) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (sheetContext) {
        final customers =
            ref.read(customerListNotifierProvider).value ?? <Customer>[];
        Customer? targetCustomer;
        if (order.customerId != 'khach_le') {
          for (final c in customers) {
            if (c.id == order.customerId) {
              targetCustomer = c;
              break;
            }
          }
        }

        final products = ref.read(productListProvider).value ?? <Product>[];
        final productMap = {for (final p in products) p.id: p};

        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    order.status == 'draft'
                        ? l10n.draftDetail
                        : l10n.invoiceDetail,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const Divider(color: AppColors.divider),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow(l10n.invoiceId, order.id),
                      if (targetCustomer != null)
                        _buildClickableDetailRow(
                          label: l10n.customers,
                          value: customerName,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CustomerDetailPage(
                                    customer: targetCustomer!),
                              ),
                            );
                          },
                        )
                      else
                        _buildDetailRow(l10n.customers, customerName),
                      _buildDetailRow(
                          l10n.createdTime,
                          DateFormat('dd/MM/yyyy HH:mm')
                              .format(order.createdAt)),
                      _buildDetailRow(
                        l10n.status,
                        order.status == 'draft' ? l10n.draftUnpaid : l10n.paid,
                        textColor: order.status == 'draft'
                            ? Colors.orange
                            : Colors.green,
                      ),
                      _buildDetailRow(
                        l10n.paymentMethod,
                        order.paymentMethod == 'transfer'
                            ? l10n.transfer
                            : l10n.cash,
                      ),
                      _buildDetailRow(l10n.createdBy,
                          order.createdByName ?? order.createdBy ?? '—'),
                      const SizedBox(height: 16),
                      Text(
                        l10n.productList,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      ...order.items.map((item) {
                        final matchingProduct = productMap[item.productId];
                        return InkWell(
                          onTap: () {
                            if (matchingProduct != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProductDetailPage(
                                      product: matchingProduct),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.productNotFoundInSystem),
                                ),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 6.0, horizontal: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.productName,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.chevron_right,
                                              size: 16,
                                              color: AppColors.primary),
                                        ],
                                      ),
                                      Text(
                                        '${item.quantity} x ${currencyFormat.format(item.price)} đ',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54),
                                      )
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${currencyFormat.format(item.price * item.quantity)} đ',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold),
                                )
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                      const Divider(height: 24, color: AppColors.divider),
                      Builder(builder: (context) {
                        final subtotal = order.items.fold(
                            0.0, (sum, item) => sum + (item.price * item.quantity));
                        final discount = (subtotal - order.total) > 0.5
                            ? (subtotal - order.total)
                            : 0.0;
                        final remainingDebt = (order.total - order.amountPaid)
                            .clamp(0.0, double.infinity);

                        return Column(
                          children: [
                            if (discount > 0) ...[
                              _buildDetailRow('Tổng cộng',
                                  '${currencyFormat.format(subtotal)} đ'),
                              _buildDetailRow('Giảm giá',
                                  '${currencyFormat.format(discount)} đ',
                                  textColor: AppColors.danger),
                              _buildDetailRow(
                                'Sau giảm',
                                '${currencyFormat.format(order.total)} đ',
                                textColor: AppColors.primary,
                              ),
                            ] else ...[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    l10n.totalPaymentAmount,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14),
                                  ),
                                  Text(
                                    '${currencyFormat.format(order.total)} đ',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: AppColors.primary),
                                  )
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            _buildDetailRow('Đã thanh toán (cọc)',
                                '${currencyFormat.format(order.amountPaid)} đ'),
                            const SizedBox(height: 4),
                            _buildDetailRow(
                              'Còn lại',
                              '${currencyFormat.format(remainingDebt)} đ',
                              textColor: remainingDebt > 0
                                  ? AppColors.danger
                                  : Colors.green,
                            ),
                          ],
                        );
                      }),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              if (order.status == 'draft') ...[
                Builder(builder: (context) {
                  final user = ref.watch(authProvider);
                  final canDelete = user?.canDeleteInvoice ?? false;
                  return Row(
                    children: [
                      if (canDelete) ...[
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: () =>
                                  _showCancelDraftDialog(context, ref, order.id),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.danger),
                                foregroundColor: AppColors.danger,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(
                                l10n.cancelDraftOrder,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: FilledButton(
                          onPressed: () {
                            Navigator.pop(context); // Đóng Bottom Sheet

                            // Nạp lại đơn hàng nháp vào giỏ hàng
                            final products =
                                ref.read(productListProvider).value ?? [];
                            ref
                                .read(cartProvider.notifier)
                                .populateCart(order.items, products);

                            // Set mã đơn tạm đang hoạt động
                            ref.read(activeOrderIdProvider.notifier).state =
                                order.id;

                            // Tìm khách hàng
                            final customers =
                                ref.read(customerListNotifierProvider).value ??
                                    [];
                            Customer? customer;
                            for (final c in customers) {
                              if (c.id == order.customerId) {
                                customer = c;
                                break;
                              }
                            }

                            // Điều hướng trực tiếp sang màn hình thanh toán
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => POSCheckoutPage(
                                  initialCustomer: customer,
                                ),
                              ),
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(
                            l10n.continuePayment,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
                }),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final config = ref.read(storePaymentConfigProvider);
                    await InvoicePrintHelper.printInvoice(
                      context,
                      order,
                      targetCustomer,
                      config,
                    );
                  },
                  icon: const Icon(Icons.print, color: AppColors.primary),
                  label: const Text(
                    'In Hóa Đơn',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.primary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: textColor ?? Colors.black87,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildClickableDetailRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right,
                      size: 16, color: AppColors.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCancelDraftDialog(
      BuildContext context, WidgetRef ref, String orderId) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.cancelDraftOrder),
        content: Text(l10n.confirmCancelDraftOrder),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(dialogContext); // pop dialog
              Navigator.pop(context); // pop bottom sheet
              try {
                await ref.read(orderRepositoryProvider).delete(orderId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.draftOrderCancelled),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lỗi khi hủy đơn: $e')),
                  );
                }
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
