import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/presentation/common/widgets/error_view.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';
import 'package:stores/presentation/common/widgets/product_image_thumbnail.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/customers/customers_providers.dart';
import '../../../application/orders/cart_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../application/settings/store_payment_config_providers.dart';
import '../../../core/utils/excel_helper.dart';
import '../../../core/utils/invoice_print_helper.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/user_account.dart';
import '../../customers/pages/customer_detail_page.dart';
import '../../products/pages/product_detail_page.dart';
import '../widgets/cancel_invoice_dialog.dart';
import '../widgets/debt_collection_dialog.dart';
import '../widgets/return_order_bottom_sheet.dart';
import '../widgets/return_order_detail_bottom_sheet.dart';
import 'pos_checkout_page.dart';

class InvoicesPage extends ConsumerStatefulWidget {
  const InvoicesPage({super.key});

  @override
  ConsumerState<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends ConsumerState<InvoicesPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Multi-dimensional filters
  String _selectedStatusFilter = 'all'; // 'all', 'completed', 'returned', 'draft', 'cancelled'
  String _selectedPaymentMethodFilter = 'all'; // 'all', 'cash', 'transfer'
  String _selectedDebtStatusFilter = 'all'; // 'all', 'paid', 'debt'
  String _selectedStaffFilter = 'all'; // 'all' or staff username

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _buildFilterDescription() {
    final parts = <String>[];
    if (_selectedStatusFilter != 'all') {
      switch (_selectedStatusFilter) {
        case 'completed':
          parts.add('Trạng thái: Đã hoàn thành');
          break;
        case 'returned':
          parts.add('Trạng thái: Đơn trả hàng');
          break;
        case 'draft':
          parts.add('Trạng thái: Lưu tạm');
          break;
        case 'cancelled':
          parts.add('Trạng thái: Đã hủy');
          break;
      }
    }
    if (_selectedPaymentMethodFilter != 'all') {
      parts.add(
          'Hình thức: ${_selectedPaymentMethodFilter == 'transfer' ? 'Chuyển khoản' : 'Tiền mặt'}');
    }
    if (_selectedDebtStatusFilter != 'all') {
      parts.add(
          'Công nợ: ${_selectedDebtStatusFilter == 'paid' ? 'Đã thanh toán đủ' : 'Còn ghi nợ'}');
    }
    if (_selectedStaffFilter != 'all') {
      parts.add('Nhân viên: $_selectedStaffFilter');
    }
    if (_searchQuery.trim().isNotEmpty) {
      parts.add('Tìm kiếm: "$_searchQuery"');
    }
    return parts.isEmpty ? 'Tất cả hóa đơn' : parts.join(', ');
  }

  Future<void> _exportInvoicesToExcel(
    BuildContext context,
    List<Order> filteredOrders,
    Map<String, Customer> customerMap,
    String branchLabel,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (filteredOrders.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Không có dữ liệu hóa đơn để xuất Excel.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: LoadingIndicator()),
    );

    try {
      final currentUser = ref.read(authProvider);
      final filterDesc = _buildFilterDescription();

      final file = await ExcelHelper.exportInvoicesToFile(
        filteredOrders,
        storeName: branchLabel,
        filterDescription: filterDesc,
        customerMap: customerMap,
        exportedBy: currentUser?.name,
      );

      if (mounted) {
        navigator.pop(); // pop loading dialog

        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Danh sách hóa đơn - $branchLabel',
        );
      }
    } catch (e) {
      if (mounted) {
        if (navigator.canPop()) {
          navigator.pop();
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text('Lỗi khi xuất file Excel: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
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
    final accountsAsync = ref.watch(accountsListProvider);

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

    final staffAccounts = accountsAsync.value ?? <UserAccount>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          l10n.invoicesTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            key: const Key('export_excel_button'),
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Xuất Excel',
            onPressed: () {
              final orders = ordersAsync.value ?? <Order>[];
              final customers = customersAsync.value ?? <Customer>[];
              final customerMap = {for (final c in customers) c.id: c};
              final filtered = _applyFilters(orders, customers);
              _exportInvoicesToExcel(
                context,
                filtered,
                customerMap,
                branchLabel,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Thanh tìm kiếm hoá đơn
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
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
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),

          // 2. Thanh bộ lọc (Thời gian & Chi nhánh)
          _buildFiltersBar(context, dateLabel, branchLabel),

          // 3. Multi-dimensional Filter Bar (Status, Payment Method, Debt Status, Staff)
          _buildMultiDimensionalFilterBar(staffAccounts),

          // 4. Nội dung danh sách hoá đơn & KPI Card
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                return customersAsync.when(
                  data: (customers) {
                    final searchFilteredOrders =
                        _applyFilters(orders, customers);

                    if (_selectedStatusFilter == 'returned') {
                      final totalReturnCount = searchFilteredOrders.length;
                      double totalRefundAmount = 0.0;
                      double totalCashRefunded = 0.0;
                      double totalDebtDeducted = 0.0;

                      for (final o in searchFilteredOrders) {
                        final returnedItems = o.items
                            .where((i) => i.returnedQuantity > 0)
                            .toList();
                        final orderReturnTotal = returnedItems.isNotEmpty
                            ? returnedItems.fold<double>(
                                0.0,
                                (sum, i) =>
                                    sum + (i.returnedQuantity * i.price))
                            : (o.isReturned
                                ? (o.total > 0
                                    ? o.total
                                    : o.items.fold<double>(
                                        0.0,
                                        (sum, i) =>
                                            sum + (i.quantity * i.price)))
                                : 0.0);
                        totalRefundAmount += orderReturnTotal;
                        final debtPart =
                            min(orderReturnTotal, o.remainingDebt);
                        totalDebtDeducted += debtPart;
                        totalCashRefunded += (orderReturnTotal - debtPart);
                      }

                      return Column(
                        children: [
                          // Dedicated Return KPI Summary Card
                          _buildReturnSummaryCard(
                            totalReturnCount: totalReturnCount,
                            totalRefundAmount: totalRefundAmount,
                            totalCashRefunded: totalCashRefunded,
                            totalDebtDeducted: totalDebtDeducted,
                            format: currencyFormat,
                          ),

                          // List of invoices
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
                                          context,
                                          customers,
                                          order.customerId);

                                      return _buildInvoiceTile(
                                        context: context,
                                        order: order,
                                        customerName: customerName,
                                        currencyFormat: currencyFormat,
                                        l10n: l10n,
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    }

                    // Dynamic 4-Metric Aggregate Totals
                    final totalInvoices = searchFilteredOrders.length;
                    final activeOrders = searchFilteredOrders
                        .where((o) => !o.isCancelled)
                        .toList();
                    final totalRevenue =
                        activeOrders.fold(0.0, (sum, o) => sum + o.total);
                    final totalPaid =
                        activeOrders.fold(0.0, (sum, o) => sum + o.amountPaid);
                    final totalDebt = activeOrders.fold(
                        0.0, (sum, o) => sum + o.remainingDebt);

                    return Column(
                      children: [
                        // Dynamic 4-Metric KPI Summary Card
                        _buildTotalSummaryCard(
                          totalInvoices: totalInvoices,
                          totalRevenue: totalRevenue,
                          totalPaid: totalPaid,
                          totalDebt: totalDebt,
                          format: currencyFormat,
                          l10n: l10n,
                        ),

                        // List of invoices
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

                                    return _buildInvoiceTile(
                                      context: context,
                                      order: order,
                                      customerName: customerName,
                                      currencyFormat: currencyFormat,
                                      l10n: l10n,
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

  List<Order> _applyFilters(List<Order> orders, List<Customer> customers) {
    final customerMap = {for (final c in customers) c.id: c};

    final filtered = orders.where((order) {
      // 1. Status Filter
      if (_selectedStatusFilter != 'all') {
        if (_selectedStatusFilter == 'completed') {
          if (order.status != 'completed' || order.isCancelled) return false;
        } else if (_selectedStatusFilter == 'returned') {
          if (!order.isReturned && !order.hasReturns) return false;
        } else if (_selectedStatusFilter == 'draft') {
          if (order.status != 'draft') return false;
        } else if (_selectedStatusFilter == 'cancelled') {
          if (!order.isCancelled) return false;
        } else if (order.status != _selectedStatusFilter) {
          return false;
        }
      }

      // 2. Payment Method Filter
      if (_selectedPaymentMethodFilter != 'all') {
        if (order.paymentMethod != _selectedPaymentMethodFilter) {
          return false;
        }
      }

      // 3. Debt Status Filter
      if (_selectedDebtStatusFilter != 'all') {
        if (_selectedDebtStatusFilter == 'paid') {
          if (order.remainingDebt > 0.001) return false;
        } else if (_selectedDebtStatusFilter == 'debt') {
          if (order.remainingDebt <= 0.001) return false;
        }
      }

      // 4. Staff Filter
      if (_selectedStaffFilter != 'all') {
        final creator = (order.createdBy ?? '').trim().toLowerCase();
        final creatorName = (order.createdByName ?? '').trim().toLowerCase();
        final target = _selectedStaffFilter.trim().toLowerCase();
        if (creator != target && creatorName != target) {
          return false;
        }
      }

      // 5. Search Query
      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.toLowerCase().trim();
        final customer = customerMap[order.customerId];
        final cName = (customer?.name ??
                (order.customerId == 'khach_le'
                    ? 'khách lẻ'
                    : order.customerId))
            .toLowerCase();
        final cPhone = (customer?.phone ?? '').toLowerCase();
        final cCode = (customer?.id ?? '').toLowerCase();
        final orderId = order.id.toLowerCase();
        final staff = (order.createdByName ?? order.createdBy ?? '').toLowerCase();
        final hasItemMatch = order.items.any(
            (i) => i.productName.toLowerCase().contains(query) ||
                i.productId.toLowerCase().contains(query));

        if (!orderId.contains(query) &&
            !cName.contains(query) &&
            !cPhone.contains(query) &&
            !cCode.contains(query) &&
            !staff.contains(query) &&
            !hasItemMatch) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sắp xếp đơn mới nhất lên đầu
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  Widget _buildMultiDimensionalFilterBar(List<UserAccount> staffAccounts) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Status Filters
            _buildStatusChip('all', 'Tất cả trạng thái'),
            const SizedBox(width: 6),
            _buildStatusChip('completed', 'Đã hoàn thành'),
            const SizedBox(width: 6),
            _buildStatusChip('returned', 'Đơn trả hàng'),
            const SizedBox(width: 6),
            _buildStatusChip('draft', 'Lưu tạm'),
            const SizedBox(width: 6),
            _buildStatusChip('cancelled', 'Đã hủy'),
            const SizedBox(width: 12),
            Container(height: 20, width: 1, color: AppColors.divider),
            const SizedBox(width: 12),

            // Payment Method Filter
            _buildPaymentMethodDropdown(),
            const SizedBox(width: 8),

            // Debt Status Filter
            _buildDebtStatusDropdown(),
            const SizedBox(width: 8),

            // Staff Filter
            if (staffAccounts.isNotEmpty) ...[
              _buildStaffDropdown(staffAccounts),
              const SizedBox(width: 8),
            ],

            // Reset Filter Button if active
            if (_hasActiveFilters) ...[
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: AppColors.primary),
                tooltip: 'Đặt lại bộ lọc',
                onPressed: () {
                  setState(() {
                    _selectedStatusFilter = 'all';
                    _selectedPaymentMethodFilter = 'all';
                    _selectedDebtStatusFilter = 'all';
                    _selectedStaffFilter = 'all';
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _hasActiveFilters =>
      _selectedStatusFilter != 'all' ||
      _selectedPaymentMethodFilter != 'all' ||
      _selectedDebtStatusFilter != 'all' ||
      _selectedStaffFilter != 'all';

  Widget _buildStatusChip(String value, String label) {
    final isSelected = _selectedStatusFilter == value;
    Color activeColor = AppColors.primary;
    if (value == 'draft') activeColor = Colors.orange;
    if (value == 'cancelled') activeColor = AppColors.danger;
    if (value == 'completed') activeColor = Colors.green;
    if (value == 'returned') activeColor = Colors.purple;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedStatusFilter = value);
        }
      },
      selectedColor: activeColor.withOpacity(0.12),
      labelStyle: TextStyle(
        color: isSelected ? activeColor : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  Widget _buildPaymentMethodDropdown() {
    final isFiltered = _selectedPaymentMethodFilter != 'all';
    return PopupMenuButton<String>(
      initialValue: _selectedPaymentMethodFilter,
      onSelected: (val) => setState(() => _selectedPaymentMethodFilter = val),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isFiltered ? AppColors.primary.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isFiltered ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.payment,
              size: 14,
              color: isFiltered ? AppColors.primary : Colors.black54,
            ),
            const SizedBox(width: 4),
            Text(
              _selectedPaymentMethodFilter == 'all'
                  ? 'PT thanh toán'
                  : (_selectedPaymentMethodFilter == 'transfer'
                      ? 'Chuyển khoản'
                      : 'Tiền mặt'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isFiltered ? FontWeight.bold : FontWeight.normal,
                color: isFiltered ? AppColors.primary : Colors.black87,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: isFiltered ? AppColors.primary : Colors.black54,
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'all', child: Text('Tất cả phương thức')),
        const PopupMenuItem(value: 'cash', child: Text('Tiền mặt')),
        const PopupMenuItem(value: 'transfer', child: Text('Chuyển khoản')),
      ],
    );
  }

  Widget _buildDebtStatusDropdown() {
    final isFiltered = _selectedDebtStatusFilter != 'all';
    return PopupMenuButton<String>(
      initialValue: _selectedDebtStatusFilter,
      onSelected: (val) => setState(() => _selectedDebtStatusFilter = val),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isFiltered ? AppColors.primary.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isFiltered ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 14,
              color: isFiltered ? AppColors.primary : Colors.black54,
            ),
            const SizedBox(width: 4),
            Text(
              _selectedDebtStatusFilter == 'all'
                  ? 'Công nợ'
                  : (_selectedDebtStatusFilter == 'paid'
                      ? 'Đã TT đủ'
                      : 'Còn ghi nợ'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isFiltered ? FontWeight.bold : FontWeight.normal,
                color: isFiltered ? AppColors.primary : Colors.black87,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: isFiltered ? AppColors.primary : Colors.black54,
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'all', child: Text('Tất cả công nợ')),
        const PopupMenuItem(value: 'paid', child: Text('Đã thanh toán đủ')),
        const PopupMenuItem(value: 'debt', child: Text('Còn ghi nợ')),
      ],
    );
  }

  Widget _buildStaffDropdown(List<UserAccount> staffAccounts) {
    final isFiltered = _selectedStaffFilter != 'all';
    String staffLabel = 'Nhân viên';
    if (isFiltered) {
      final match = staffAccounts.firstWhere(
        (a) => a.username == _selectedStaffFilter,
        orElse: () => UserAccount(
          username: _selectedStaffFilter,
          role: 'nhanvien',
          storeId: '',
        ),
      );
      staffLabel = match.name;
    }

    return PopupMenuButton<String>(
      initialValue: _selectedStaffFilter,
      onSelected: (val) => setState(() => _selectedStaffFilter = val),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isFiltered ? AppColors.primary.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isFiltered ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_outline,
              size: 14,
              color: isFiltered ? AppColors.primary : Colors.black54,
            ),
            const SizedBox(width: 4),
            Text(
              staffLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isFiltered ? FontWeight.bold : FontWeight.normal,
                color: isFiltered ? AppColors.primary : Colors.black87,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: isFiltered ? AppColors.primary : Colors.black54,
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'all', child: Text('Tất cả nhân viên')),
        ...staffAccounts.map((account) {
          return PopupMenuItem(
            value: account.username,
            child: Text('${account.name} (${account.username})'),
          );
        }),
      ],
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
                      fontSize: 13.5,
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
                    fontSize: 13.5,
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

  // 4-Metric Reactive KPI Summary Card
  Widget _buildTotalSummaryCard({
    required int totalInvoices,
    required double totalRevenue,
    required double totalPaid,
    required double totalDebt,
    required NumberFormat format,
    required AppLocalizations l10n,
  }) {
    return Container(
      color: AppColors.primary.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Số HĐ: $totalInvoices',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              Text(
                'Doanh thu: ${format.format(totalRevenue)} đ',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Đã thu: ${format.format(totalPaid)} đ',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Colors.green,
                ),
              ),
              Text(
                'Còn nợ: ${format.format(totalDebt)} đ',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: totalDebt > 0 ? AppColors.danger : Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Dedicated Return KPI Summary Card
  Widget _buildReturnSummaryCard({
    required int totalReturnCount,
    required double totalRefundAmount,
    required double totalCashRefunded,
    required double totalDebtDeducted,
    required NumberFormat format,
  }) {
    return Container(
      key: const Key('return_kpi_summary_card'),
      color: Colors.purple.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Số đơn trả: $totalReturnCount',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              Text(
                'Tổng hoàn trả: ${format.format(totalRefundAmount)} đ',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tiền hoàn lại: ${format.format(totalCashRefunded)} đ',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Colors.green,
                ),
              ),
              Text(
                'Cấn trừ nợ: ${format.format(totalDebtDeducted)} đ',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: totalDebtDeducted > 0 ? Colors.indigo : Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceTile({
    required BuildContext context,
    required Order order,
    required String customerName,
    required NumberFormat currencyFormat,
    required AppLocalizations l10n,
  }) {
    final isTransfer = order.paymentMethod == 'transfer';
    final paymentMethodStr = isTransfer ? l10n.transfer : l10n.cash;

    // Status Badge Style
    String statusBadgeText;
    Color statusBadgeColor;
    if (order.isCancelled) {
      statusBadgeText = 'Đã hủy';
      statusBadgeColor = AppColors.danger;
    } else if (order.isReturned) {
      statusBadgeText = 'Đã trả hàng';
      statusBadgeColor = Colors.purple;
    } else if (order.hasReturns) {
      statusBadgeText = 'Trả 1 phần';
      statusBadgeColor = Colors.purple;
    } else if (order.status == 'draft') {
      statusBadgeText = l10n.draft;
      statusBadgeColor = Colors.orange;
    } else {
      statusBadgeText = 'Đã hoàn thành';
      statusBadgeColor = Colors.green;
    }

    final hasDebt = order.hasDebt && !order.isCancelled;

    return InkWell(
      onTap: () {
        if (order.isReturned) {
          ReturnOrderDetailBottomSheet.show(
            context,
            order: order,
            onViewOriginalInvoice: () {
              _showInvoiceDetailsBottomSheet(
                context,
                ref,
                order,
                customerName,
              );
            },
          );
        } else {
          _showInvoiceDetailsBottomSheet(
            context,
            ref,
            order,
            customerName,
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: order.isCancelled
                ? AppColors.danger.withOpacity(0.3)
                : AppColors.border,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Customer Name & Order Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    customerName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: order.isCancelled ? Colors.black54 : Colors.black87,
                      decoration: order.isCancelled
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                ),
                Text(
                  '${currencyFormat.format(order.total)} đ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: order.isCancelled
                        ? Colors.black45
                        : AppColors.primary,
                    fontSize: 14,
                    decoration: order.isCancelled
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Bottom Row: Metadata & Status Badges
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.orderIdLabel(order.id),
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(order.createdAt),
                      style: const TextStyle(
                          color: Colors.black38, fontSize: 11),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: [
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBadgeColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusBadgeText,
                        style: TextStyle(
                          color: statusBadgeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // Debt Badge if any
                    if (hasDebt) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Nợ: ${currencyFormat.format(order.remainingDebt)} đ',
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],

                    // Payment Method Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        paymentMethodStr,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Tra cứu tên khách hàng dựa trên ID
  String _getCustomerName(
      BuildContext context, List<Customer> customers, String id) {
    final l10n = AppLocalizations.of(context)!;
    if (id == 'khach_le' || id.isEmpty) return l10n.retailCustomer;
    final match = customers.firstWhere(
      (c) => c.id == id,
      orElse: () => Customer(
        id: '',
        name: l10n.retailCustomer,
        phone: '',
        email: '',
        address: '',
        purchases: const [],
      ),
    );
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
                      }),
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
                  }),
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
        final currentUser = ref.read(authProvider);
        final canDelete = currentUser?.canDeleteInvoice ?? false;

        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sheet Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    order.status == 'draft'
                        ? l10n.draftDetail
                        : (order.isCancelled
                            ? 'Chi tiết hóa đơn đã hủy'
                            : l10n.invoiceDetail),
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
                      // Cancelled Banner if cancelled
                      if (order.isCancelled) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.danger.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.cancel,
                                      color: AppColors.danger, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'HÓA ĐƠN ĐÃ HỦY',
                                    style: TextStyle(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Lý do hủy: ${order.cancelReason ?? '—'}',
                                style: const TextStyle(
                                    fontSize: 12.5, color: Colors.black87),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Người hủy: ${order.cancelledByName ?? order.cancelledBy ?? '—'}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                              if (order.cancelledAt != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Thời gian hủy: ${DateFormat('dd/MM/yyyy HH:mm').format(order.cancelledAt!)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

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
                        DateFormat('dd/MM/yyyy HH:mm').format(order.createdAt),
                      ),
                      _buildDetailRow(
                        l10n.status,
                        order.isCancelled
                            ? 'Đã hủy'
                            : (order.status == 'draft'
                                ? l10n.draftUnpaid
                                : 'Đã thanh toán'),
                        textColor: order.isCancelled
                            ? AppColors.danger
                            : (order.status == 'draft'
                                ? Colors.orange
                                : Colors.green),
                      ),
                      _buildDetailRow(
                        l10n.paymentMethod,
                        order.paymentMethod == 'split'
                            ? 'Kết hợp (TM + CK)'
                            : (order.paymentMethod == 'transfer'
                                ? l10n.transfer
                                : l10n.cash),
                      ),
                      if (order.note != null &&
                          order.note!.trim().isNotEmpty) ...[
                        _buildDetailRow(
                          'Ghi chú',
                          order.note!.trim(),
                        ),
                      ],
                      _buildDetailRow(
                        l10n.createdBy,
                        order.createdByName ?? order.createdBy ?? '—',
                      ),
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
                                ProductImageThumbnail(
                                  imageUrl: matchingProduct?.imageUrl,
                                  productName: item.productName,
                                  categoryName: matchingProduct?.category,
                                  size: 36,
                                  borderRadius: 6,
                                ),
                                const SizedBox(width: 10),
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
                                      Row(
                                        children: [
                                          Text(
                                            '${item.quantity} x ${currencyFormat.format(item.price)} đ',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.black54),
                                          ),
                                          if (item.returnedQuantity > 0) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                  horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.orange
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                'Đã trả: ${item.returnedQuantity}',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.orange,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
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
                      }),
                      const Divider(height: 24, color: AppColors.divider),

                      Builder(builder: (context) {
                        final subtotal = order.items.fold(0.0,
                            (sum, item) => sum + (item.price * item.quantity));
                        final discount = (subtotal - order.total) > 0.5
                            ? (subtotal - order.total)
                            : 0.0;
                        final remainingDebt = order.remainingDebt;

                        return Column(
                          children: [
                            if (discount > 0) ...[
                              _buildDetailRow('Tổng tiền hàng',
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
                            _buildDetailRow('Đã thanh toán',
                                '${currencyFormat.format(order.amountPaid)} đ'),
                            if (order.paymentMethod == 'split') ...[
                              _buildDetailRow('  • Tiền mặt',
                                  '${currencyFormat.format(order.cashAmount ?? 0.0)} đ'),
                              _buildDetailRow('  • Chuyển khoản',
                                  '${currencyFormat.format(order.transferAmount ?? 0.0)} đ'),
                            ],
                            const SizedBox(height: 4),
                            _buildDetailRow(
                              'Còn lại',
                              '${currencyFormat.format(remainingDebt)} đ',
                              textColor: (remainingDebt > 0 && !order.isCancelled)
                                  ? AppColors.danger
                                  : Colors.green,
                            ),
                          ],
                        );
                      }),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // ACTION BUTTONS BAR
              if (order.status == 'draft') ...[
                Row(
                  children: [
                    if (canDelete) ...[
                      Expanded(
                        child: SizedBox(
                          height: 44,
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
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 44,
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
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Return Order Detail Action Button for returned / partially returned orders
              if ((order.isReturned || order.hasReturns) && !order.isCancelled) ...[
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: FilledButton.icon(
                          key: const Key('view_return_order_action_button'),
                          onPressed: () {
                            Navigator.pop(context);
                            ReturnOrderDetailBottomSheet.show(
                              context,
                              order: order,
                              customer: targetCustomer,
                              onViewOriginalInvoice: () {
                                _showInvoiceDetailsBottomSheet(
                                  context,
                                  ref,
                                  order,
                                  customerName,
                                );
                              },
                            );
                          },
                          icon: const Icon(Icons.assignment_return_outlined,
                              size: 16),
                          label: const Text(
                            'Xem phiếu trả hàng',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.purple,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Completed Order Action Buttons (Return, Debt collection, Cancel)
              if (order.status == 'completed' && !order.isCancelled && !order.isReturned) ...[
                Row(
                  children: [
                    // Return Goods Button ("Trả hàng")
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: OutlinedButton.icon(
                          key: const Key('return_order_action_button'),
                          onPressed: () async {
                            Navigator.pop(context); // Close details sheet
                            await ReturnOrderBottomSheet.show(
                              context,
                              order: order,
                              customer: targetCustomer,
                            );
                          },
                          icon: const Icon(Icons.assignment_return_outlined,
                              size: 16),
                          label: const Text(
                            'Trả hàng',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primary),
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Debt Collection Button ("Thu nợ")
                    if (order.hasDebt) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: FilledButton.icon(
                            key: const Key('collect_debt_action_button'),
                            onPressed: () async {
                              Navigator.pop(context); // Close details sheet
                              await DebtCollectionDialog.show(
                                context,
                                order: order,
                                customer: targetCustomer,
                                remainingDebt: order.remainingDebt,
                              );
                            },
                            icon: const Icon(Icons.payments_outlined,
                                size: 16),
                            label: Text(
                              'Thu nợ (${currencyFormat.format(order.remainingDebt)})',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],

                    // Cancel Order Button ("Hủy HĐ")
                    if (canDelete) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 42,
                        child: OutlinedButton.icon(
                          key: const Key('cancel_invoice_action_button'),
                          onPressed: () async {
                            Navigator.pop(context); // Close details sheet
                            await CancelInvoiceDialog.show(
                              context,
                              order: order,
                              customer: targetCustomer,
                            );
                          },
                          icon: const Icon(Icons.delete_forever,
                              color: AppColors.danger, size: 16),
                          label: const Text(
                            'Hủy HĐ',
                            style: TextStyle(
                              color: AppColors.danger,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.danger),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Print Invoice Button
              SizedBox(
                width: double.infinity,
                height: 44,
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
                  icon: const Icon(Icons.print, color: AppColors.primary, size: 18),
                  label: const Text(
                    'In Hóa Đơn',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: textColor ?? Colors.black87,
              ),
            ),
          ),
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
