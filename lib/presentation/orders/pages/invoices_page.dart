import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/presentation/common/widgets/error_view.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';
import 'package:stores/presentation/common/widgets/product_image_thumbnail.dart';
import '../../common/widgets/date_grouped_list_view.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/customers/customers_providers.dart';
import '../../../application/orders/cart_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../application/orders/usecases/import_invoices_usecase.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../application/settings/store_payment_config_providers.dart';
import '../../../core/utils/excel_helper.dart';
import '../../../core/utils/file_saver.dart';
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
import '../controllers/invoices_filter_controller.dart';
import 'pos_checkout_page.dart';

class InvoicesPage extends ConsumerStatefulWidget {
  const InvoicesPage({super.key});

  @override
  ConsumerState<InvoicesPage> createState() => InvoicesPageState();
}

class InvoicesPageState extends ConsumerState<InvoicesPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // State for items view expansion in invoice cards
  bool _expandAll = false;
  final Set<String> _expandedOrderIds = {};
  final Set<String> _collapsedOrderIds = {};

  bool _isOrderExpanded(String orderId) {
    if (_expandAll) {
      return !_collapsedOrderIds.contains(orderId);
    } else {
      return _expandedOrderIds.contains(orderId);
    }
  }

  void _toggleOrderExpanded(String orderId) {
    setState(() {
      if (_expandAll) {
        if (_collapsedOrderIds.contains(orderId)) {
          _collapsedOrderIds.remove(orderId);
        } else {
          _collapsedOrderIds.add(orderId);
        }
      } else {
        if (_expandedOrderIds.contains(orderId)) {
          _expandedOrderIds.remove(orderId);
        } else {
          _expandedOrderIds.add(orderId);
        }
      }
    });
  }

  void _toggleExpandAll() {
    setState(() {
      _expandAll = !_expandAll;
      _expandedOrderIds.clear();
      _collapsedOrderIds.clear();
    });
  }

  // Multi-dimensional filters backed by InvoicesFilterNotifier
  String get _selectedStatusFilter => ref.watch(invoicesFilterProvider).status;
  String get _selectedPaymentMethodFilter =>
      ref.watch(invoicesFilterProvider).paymentMethod;
  String get _selectedDebtStatusFilter =>
      ref.watch(invoicesFilterProvider).debtStatus;
  String get _selectedStaffFilter => ref.watch(invoicesFilterProvider).staff;
  bool get _hasActiveFilters =>
      ref.watch(invoicesFilterProvider).hasActiveFilters;

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
    final currentUser = ref.read(authProvider);
    if (!kIsWeb || (currentUser?.isAdmin != true)) return;

    final messenger = ScaffoldMessenger.of(context);
    if (filteredOrders.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Không có dữ liệu hóa đơn để xuất Excel.'),
          backgroundColor: AppColors.warning,
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
      final filterDesc = _buildFilterDescription();

      final bytes = await ExcelHelper.exportInvoices(
        filteredOrders,
        storeName: branchLabel,
        filterDescription: filterDesc,
        customerMap: customerMap,
        exportedBy: currentUser?.name,
      );

      if (mounted) {
        if (navigator.canPop()) {
          navigator.pop(); // pop loading dialog
        }
        await saveExcelFile(bytes, 'DanhSachHoaDon_Export.xlsx');
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

  Future<void> _importInvoices() async {
    final user = ref.read(authProvider);
    if (!kIsWeb || (user?.isAdmin != true)) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Không có file nào được chọn')),
          );
        }
        return;
      }

      final fileBytes = result.files.first.bytes ??
          (result.files.first.path != null
              ? await File(result.files.first.path!).readAsBytes()
              : null);

      if (fileBytes == null) {
        throw Exception('Không thể đọc nội dung file');
      }

      if (!mounted) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: LoadingIndicator()),
      );

      final currentStoreId = ref.read(currentStoreIdProvider);
      final importedOrders = ExcelHelper.parseInvoices(
        fileBytes,
        defaultStoreId: currentStoreId,
      );

      final importResult =
          await ref.read(importInvoicesUseCaseProvider).execute(
                orders: importedOrders,
                targetStoreId: currentStoreId,
              );

      final activeRange = ref.read(invoicesActiveDateRangeProvider);
      ref.invalidate(allBranchesOrdersByDateRangeProvider(activeRange));

      if (mounted) {
        if (navigator.canPop()) {
          navigator.pop();
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(importResult.toSummaryString()),
            backgroundColor:
                importResult.errors > 0 ? AppColors.warning : AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) {
          navigator.pop();
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text('Lỗi khi nhập file Excel: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @visibleForTesting
  Future<void> testImportInvoices() => _importInvoices();

  @visibleForTesting
  Future<void> testExportInvoices(BuildContext context) =>
      _exportInvoicesToExcel(context, [], {}, 'Chi nhánh 1');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(authProvider);
    final activeRange = ref.watch(invoicesActiveDateRangeProvider);
    final timeRangeType = ref.watch(invoicesTimeRangeTypeProvider);
    final selectedBranchIds = ref.watch(selectedBranchesProvider);

    // Watch all orders for the active date range (including multi-branch support)
    final ordersAsync =
        ref.watch(allBranchesOrdersByDateRangeProvider(activeRange));

    // Selective customer catalog watching: only watch when non-retail orders lack embedded customerName
    final hasMissingCustomerNames = ordersAsync.valueOrNull?.any((o) =>
            o.customerId != 'khach_le' &&
            o.customerId != 'walk_in' &&
            o.customerId.isNotEmpty &&
            (o.customerName == null || o.customerName!.trim().isEmpty)) ??
        false;
    final customers = hasMissingCustomerNames
        ? (ref.watch(customerListNotifierProvider).valueOrNull ??
            const <Customer>[])
        : const <Customer>[];

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

    final staffAccounts = accountsAsync.valueOrNull ?? <UserAccount>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          l10n.invoicesTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.white,
        actions: [
          if (kIsWeb && (user?.isAdmin == true))
            PopupMenuButton<String>(
              key: const Key('invoices_excel_actions_menu'),
              icon: const Icon(Icons.more_vert),
              tooltip: 'Thao tác Excel',
              onSelected: (value) {
                if (value == 'import_excel') {
                  _importInvoices();
                } else if (value == 'export_excel') {
                  final orders = ordersAsync.valueOrNull ?? <Order>[];
                  final exportCustomers =
                      ref.read(customerListNotifierProvider).valueOrNull ??
                          customers;
                  final customerMap = {
                    for (final c in exportCustomers) c.id: c
                  };
                  for (final o in orders) {
                    if (o.customerId.isNotEmpty &&
                        !customerMap.containsKey(o.customerId) &&
                        o.customerName != null &&
                        o.customerName!.trim().isNotEmpty) {
                      customerMap[o.customerId] = Customer(
                        id: o.customerId,
                        name: o.customerName!,
                        phone: '',
                        email: '',
                        address: '',
                        purchases: const [],
                      );
                    }
                  }
                  final filtered = _applyFilters(orders, exportCustomers);
                  _exportInvoicesToExcel(
                    context,
                    filtered,
                    customerMap,
                    branchLabel,
                  );
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'import_excel',
                  child: Row(
                    children: [
                      Icon(Icons.upload_file, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Nhập hóa đơn từ Excel'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'export_excel',
                  child: Row(
                    children: [
                      Icon(Icons.download, color: AppColors.success),
                      SizedBox(width: 8),
                      Text('Xuất Excel'),
                    ],
                  ),
                ),
              ],
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
                fillColor: AppColors.white,
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
                final searchFilteredOrders = _applyFilters(orders, customers);

                if (_selectedStatusFilter == 'returned') {
                  final totalReturnCount = searchFilteredOrders.length;
                  double totalRefundAmount = 0.0;
                  double totalCashRefunded = 0.0;
                  double totalDebtDeducted = 0.0;

                  for (final o in searchFilteredOrders) {
                    final returnedItems =
                        o.items.where((i) => i.returnedQuantity > 0).toList();
                    final orderReturnTotal = returnedItems.isNotEmpty
                        ? returnedItems.fold<double>(0.0,
                            (sum, i) => sum + (i.returnedQuantity * i.price))
                        : (o.isReturned
                            ? (o.total > 0
                                ? o.total
                                : o.items.fold<double>(0.0,
                                    (sum, i) => sum + (i.quantity * i.price)))
                            : 0.0);
                    totalRefundAmount += orderReturnTotal;
                    final debtPart = min(orderReturnTotal, o.remainingDebt);
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
                            : DateGroupedListView<Order>(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                items: searchFilteredOrders,
                                dateSelector: (o) => o.createdAt,
                                headerBuilder: (context, date, dayItems) {
                                  int dayTotalQty = 0;
                                  double dayAmount = 0.0;
                                  for (final o in dayItems) {
                                    final returnedItems = o.items
                                        .where((i) => i.returnedQuantity > 0)
                                        .toList();
                                    for (final i in returnedItems) {
                                      dayTotalQty += i.returnedQuantity;
                                    }
                                    dayAmount += (o.total > 0 ? o.total : 0.0);
                                  }
                                  return DateGroupHeader(
                                    date: date,
                                    itemCount: dayItems.length,
                                    itemUnit: dayTotalQty > 0
                                        ? 'đơn trả • $dayTotalQty sp'
                                        : 'đơn trả',
                                    totalAmount: dayAmount,
                                    currencyFormat: currencyFormat,
                                  );
                                },
                                itemUnit: 'đơn trả',
                                itemAmountSelector: (o) => o.total,
                                currencyFormat: currencyFormat,
                                itemBuilder: (context, order) {
                                  final customerName = _getCustomerName(
                                      context, customers, order.customerId,
                                      order: order);

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

                // List of invoices (khối tổng kết màu cam đã ẩn theo R3)
                if (searchFilteredOrders.isEmpty) {
                  return Center(child: Text(l10n.noInvoicesFound));
                }

                // Compute summary metrics for filtered orders
                int totalProductQuantity = 0;
                int totalProductLines = 0;
                double totalGrossAmount = 0.0;

                for (final o in searchFilteredOrders) {
                  if (!o.isCancelled) {
                    totalGrossAmount += o.total;
                    totalProductLines += o.items.length;
                    for (final i in o.items) {
                      totalProductQuantity += (i.quantity - i.returnedQuantity);
                    }
                  }
                }

                return Column(
                  children: [
                    _buildItemsSummaryHeader(
                      totalInvoices: searchFilteredOrders.length,
                      totalProductQuantity: totalProductQuantity,
                      totalProductLines: totalProductLines,
                      totalGrossAmount: totalGrossAmount,
                      currencyFormat: currencyFormat,
                    ),
                    Expanded(
                      child: DateGroupedListView<Order>(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        items: searchFilteredOrders,
                        dateSelector: (o) => o.createdAt,
                        headerBuilder: (context, date, dayItems) {
                          int dayTotalQty = 0;
                          double dayAmount = 0.0;
                          for (final o in dayItems) {
                            if (!o.isCancelled) {
                              dayAmount += o.total;
                              for (final i in o.items) {
                                dayTotalQty +=
                                    (i.quantity - i.returnedQuantity);
                              }
                            }
                          }
                          return DateGroupHeader(
                            date: date,
                            itemCount: dayItems.length,
                            itemUnit: dayTotalQty > 0
                                ? 'hóa đơn • $dayTotalQty sp'
                                : 'hóa đơn',
                            totalAmount: dayAmount,
                            currencyFormat: currencyFormat,
                          );
                        },
                        itemUnit: 'hóa đơn',
                        itemAmountSelector: (o) =>
                            o.isCancelled ? 0.0 : o.total,
                        currencyFormat: currencyFormat,
                        itemBuilder: (context, order) {
                          final customerName = _getCustomerName(
                              context, customers, order.customerId,
                              order: order);

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
                (order.customerName != null &&
                        order.customerName!.trim().isNotEmpty
                    ? order.customerName!
                    : (order.customerId == 'khach_le' ||
                            order.customerId == 'walk_in' ||
                            order.customerId.isEmpty
                        ? 'khách lẻ'
                        : order.customerId)))
            .toLowerCase();
        final cPhone = (customer?.phone ?? '').toLowerCase();
        final cCode = (customer?.id ?? order.customerId).toLowerCase();
        final orderId = order.id.toLowerCase();
        final staff =
            (order.createdByName ?? order.createdBy ?? '').toLowerCase();
        final hasItemMatch = order.items.any((i) =>
            i.productName.toLowerCase().contains(query) ||
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
      color: AppColors.white,
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
            if (_hasActiveFilters) ...[
              const SizedBox(width: 4),
              IconButton(
                key: const Key('invoices_reset_filter_button'),
                icon: const Icon(Icons.refresh,
                    size: 18, color: AppColors.primary),
                tooltip: 'Đặt lại bộ lọc',
                onPressed: () {
                  ref.read(invoicesFilterProvider.notifier).reset();
                },
              ),
            ],
            const SizedBox(width: 8),
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
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String value, String label) {
    final isSelected = _selectedStatusFilter == value;
    Color activeColor = AppColors.primary;
    if (value == 'draft') activeColor = AppColors.warning;
    if (value == 'cancelled') activeColor = AppColors.danger;
    if (value == 'completed') activeColor = AppColors.success;
    if (value == 'returned') activeColor = AppColors.supervisor;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          ref.read(invoicesFilterProvider.notifier).setStatus(value);
        }
      },
      selectedColor: activeColor.withOpacity(0.12),
      labelStyle: TextStyle(
        color: isSelected ? activeColor : AppColors.textPrimary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  Widget _buildPaymentMethodDropdown() {
    final isFiltered = _selectedPaymentMethodFilter != 'all';
    return PopupMenuButton<String>(
      initialValue: _selectedPaymentMethodFilter,
      onSelected: (val) =>
          ref.read(invoicesFilterProvider.notifier).setPaymentMethod(val),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isFiltered
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.grey100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isFiltered ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedPaymentMethodFilter == 'all'
                  ? 'PT thanh toán'
                  : (_selectedPaymentMethodFilter == 'transfer'
                      ? 'Chuyển khoản'
                      : 'Tiền mặt'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isFiltered ? FontWeight.bold : FontWeight.normal,
                color: isFiltered ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: isFiltered ? AppColors.primary : AppColors.textSecondary,
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
      onSelected: (val) =>
          ref.read(invoicesFilterProvider.notifier).setDebtStatus(val),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isFiltered
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.grey100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isFiltered ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedDebtStatusFilter == 'all'
                  ? 'Công nợ'
                  : (_selectedDebtStatusFilter == 'paid'
                      ? 'Đã TT đủ'
                      : 'Còn ghi nợ'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isFiltered ? FontWeight.bold : FontWeight.normal,
                color: isFiltered ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: isFiltered ? AppColors.primary : AppColors.textSecondary,
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
      onSelected: (val) =>
          ref.read(invoicesFilterProvider.notifier).setStaff(val),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isFiltered
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.grey100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isFiltered ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              staffLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isFiltered ? FontWeight.bold : FontWeight.normal,
                color: isFiltered ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: isFiltered ? AppColors.primary : AppColors.textSecondary,
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
    final filterState = ref.watch(invoicesFilterProvider);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Row(
        children: [
          // Bộ lọc Thời gian
          Flexible(
            child: InkWell(
              onTap: () => _showDateRangeFilterBottomSheet(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      dateText,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down,
                      color: AppColors.primary, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Bộ lọc Chi nhánh
          Flexible(
            child: InkWell(
              onTap: () => _showBranchFilterBottomSheet(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      branchText,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 13.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down,
                      color: AppColors.textSecondary, size: 18),
                ],
              ),
            ),
          ),
          if (filterState.hasActiveFilters) ...[
            const SizedBox(width: 10),
            InkWell(
              key: const Key('invoices_reset_filter_badge_button'),
              onTap: () => ref.read(invoicesFilterProvider.notifier).reset(),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.filter_alt,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Lọc (${filterState.activeFilterCount})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.close, size: 14, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ],
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
      color: AppColors.supervisor.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Số đơn trả: $totalReturnCount',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Tổng hoàn trả: ${format.format(totalRefundAmount)} đ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppColors.supervisor,
                  ),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Tiền hoàn lại: ${format.format(totalCashRefunded)} đ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColors.success,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Cấn trừ nợ: ${format.format(totalDebtDeducted)} đ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: totalDebtDeducted > 0
                        ? AppColors.chartIndigo
                        : AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSummaryHeader({
    required int totalInvoices,
    required int totalProductQuantity,
    required int totalProductLines,
    required double totalGrossAmount,
    required NumberFormat currencyFormat,
  }) {
    return Container(
      key: const Key('invoices_items_summary_bar'),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showIcons = constraints.maxWidth >= 330;

          return Row(
            children: [
              // 1. Số hóa đơn
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showIcons) ...[
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.receipt_long_outlined,
                            size: 15, color: AppColors.primary),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Hóa đơn',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '$totalInvoices đơn',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                height: 24,
                width: 1,
                color: AppColors.dividerLight,
                margin: const EdgeInsets.symmetric(horizontal: 4),
              ),

              // 2. Tổng hàng hóa (items)
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showIcons) ...[
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryDark.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.inventory_2_outlined,
                            size: 15, color: AppColors.secondaryDark),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Tổng hàng',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '$totalProductQuantity sp',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondaryDark,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                height: 24,
                width: 1,
                color: AppColors.dividerLight,
                margin: const EdgeInsets.symmetric(horizontal: 4),
              ),

              // 3. Doanh thu thuần -> Tổng tiền hàng
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showIcons) ...[
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppColors.warningLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.payments_outlined,
                            size: 15, color: AppColors.warningDark),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Tổng tiền hàng',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${currencyFormat.format(totalGrossAmount)} đ',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warningDeep,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 4. Nút Mở rộng / Thu gọn tất cả
              const SizedBox(width: 4),
              InkWell(
                key: const Key('invoices_toggle_expand_all_button'),
                onTap: _toggleExpandAll,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  decoration: BoxDecoration(
                    color: _expandAll
                        ? AppColors.primary.withOpacity(0.12)
                        : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _expandAll ? AppColors.primary : AppColors.border,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _expandAll ? Icons.unfold_less : Icons.unfold_more,
                        size: 14,
                        color: _expandAll
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _expandAll ? 'Gọn' : 'Xem món',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _expandAll
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
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
    final paymentMethodStr =
        isTransfer ? l10n.paymentMethodTransfer : l10n.cash;

    // Status Badge Style
    String statusBadgeText;
    Color statusBadgeColor;
    Color statusBadgeBgColor;
    if (order.isCancelled) {
      statusBadgeText = 'Đã hủy';
      statusBadgeColor = AppColors.dangerDeep;
      statusBadgeBgColor = AppColors.dangerLightest;
    } else if (order.isReturned) {
      statusBadgeText = 'Đã trả hàng';
      statusBadgeColor = AppColors.supervisorDark;
      statusBadgeBgColor = AppColors.supervisorLight;
    } else if (order.hasReturns) {
      statusBadgeText = 'Trả 1 phần';
      statusBadgeColor = AppColors.supervisorDark;
      statusBadgeBgColor = AppColors.supervisorLight;
    } else if (order.status == 'draft') {
      statusBadgeText = l10n.draft;
      statusBadgeColor = AppColors.warningDark;
      statusBadgeBgColor = AppColors.warningLight;
    } else {
      statusBadgeText = 'Đã hoàn thành';
      statusBadgeColor = AppColors.secondaryDark;
      statusBadgeBgColor = AppColors.successLight;
    }

    final hasDebt = order.hasDebt && !order.isCancelled;

    final totalQuantity =
        order.items.fold<int>(0, (sum, i) => sum + i.quantity);
    final itemCount = order.items.length;
    final hasItems = order.items.isNotEmpty;
    final isExpanded = _isOrderExpanded(order.id);

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
          color: AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: order.isCancelled
                ? AppColors.danger.withOpacity(0.3)
                : AppColors.border,
          ),
        ),
        padding: const EdgeInsets.all(12),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: order.isCancelled
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                      decoration: order.isCancelled
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${currencyFormat.format(order.total)} đ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: order.isCancelled
                            ? AppColors.textTertiary
                            : AppColors.primary,
                        fontSize: 14,
                        decoration: order.isCancelled
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Item Summary & Quick Preview / Expand Row
            if (hasItems) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.12),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Item count badge
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.inventory_2_outlined,
                                size: 13,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '$itemCount mặt hàng • $totalQuantity sp',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Toggle Expand button
                        Flexible(
                          child: InkWell(
                            onTap: () => _toggleOrderExpanded(order.id),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Flexible(
                                    child: Text(
                                      isExpanded
                                          ? 'Thu gọn'
                                          : 'Xem chi tiết món',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  Icon(
                                    isExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    size: 15,
                                    color: AppColors.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // If not expanded: Single-line subtle summary preview
                    if (!isExpanded) ...[
                      const SizedBox(height: 3),
                      Text(
                        order.items
                            .map((i) => '${i.productName} (x${i.quantity})')
                            .join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],

                    // If expanded: Detailed items list
                    if (isExpanded) ...[
                      const SizedBox(height: 6),
                      const Divider(height: 1, color: AppColors.dividerLight),
                      const SizedBox(height: 4),
                      ...order.items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primary,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  item.productName,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: AppColors.border, width: 0.6),
                                ),
                                child: Text(
                                  'x${item.quantity}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              if (item.returnedQuantity > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '(Trả ${item.returnedQuantity})',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.supervisorDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              const SizedBox(width: 8),
                              Text(
                                '${currencyFormat.format(item.price * item.quantity)} đ',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],

            // Bottom Row: Metadata & Status Badges
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.orderIdLabel(order.id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(order.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusBadgeBgColor,
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

                      // Discount Badge if any
                      if (order.discount > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.warningLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Giảm: -${currencyFormat.format(order.discount)} đ',
                                style: const TextStyle(
                                  color: AppColors.warningDeep,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],

                      // Debt Badge if any
                      if (hasDebt) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.dangerLightest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Nợ: ${currencyFormat.format(order.remainingDebt)} đ',
                                style: const TextStyle(
                                  color: AppColors.dangerDeep,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],

                      // Payment Method Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
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
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Tra cứu tên khách hàng dựa trên ID hoặc embedded customerName
  String _getCustomerName(
      BuildContext context, List<Customer> customers, String id,
      {Order? order}) {
    final l10n = AppLocalizations.of(context)!;
    if (order?.customerName != null && order!.customerName!.trim().isNotEmpty) {
      return order.customerName!;
    }
    if (id == 'khach_le' || id == 'walk_in' || id.isEmpty)
      return l10n.retailCustomer;
    final match = customers.firstWhere(
      (c) => c.id == id,
      orElse: () => Customer(
        id: id,
        name: id,
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
      backgroundColor: AppColors.white,
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
                                  : AppColors.textPrimary,
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
                                    .read(invoicesFilterProvider.notifier)
                                    .setCustomDateRange(pickedRange);
                              }
                            } else {
                              ref
                                  .read(invoicesFilterProvider.notifier)
                                  .setTimeRangeType(type);
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
      backgroundColor: AppColors.white,
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
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (sheetContext) {
        final customers =
            ref.read(customerListNotifierProvider).valueOrNull ?? <Customer>[];
        Customer? targetCustomer;
        if (order.customerId != 'khach_le' &&
            order.customerId != 'walk_in' &&
            order.customerId.isNotEmpty) {
          for (final c in customers) {
            if (c.id == order.customerId) {
              targetCustomer = c;
              break;
            }
          }
          targetCustomer ??= Customer(
            id: order.customerId,
            name: customerName,
            phone: '',
            email: '',
            address: '',
            purchases: const [],
          );
        }

        final products =
            ref.read(productListProvider).valueOrNull ?? <Product>[];
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
                  Expanded(
                    child: Text(
                      order.status == 'draft'
                          ? l10n.draftDetail
                          : (order.isCancelled
                              ? 'Chi tiết hóa đơn đã hủy'
                              : l10n.invoiceDetail),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
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
                                    fontSize: 12.5,
                                    color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Người hủy: ${order.cancelledByName ?? order.cancelledBy ?? '—'}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary),
                              ),
                              if (order.cancelledAt != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Thời gian hủy: ${DateFormat('dd/MM/yyyy HH:mm').format(order.cancelledAt!)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary),
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
                            : (order.isReturned
                                ? 'Đã trả hàng'
                                : (order.hasReturns
                                    ? 'Trả 1 phần'
                                    : (order.status == 'draft'
                                        ? l10n.draft
                                        : 'Đã hoàn thành'))),
                        textColor: order.isCancelled
                            ? AppColors.danger
                            : (order.status == 'draft'
                                ? AppColors.warning
                                : (order.isReturned
                                    ? AppColors.supervisor
                                    : AppColors.success)),
                      ),
                      _buildDetailRow(
                        'Thanh toán',
                        order.isCancelled
                            ? 'Không áp dụng (Đã hủy)'
                            : (order.remainingDebt <= 0.001
                                ? 'Đã thanh toán đủ'
                                : (order.amountPaid > 0
                                    ? 'Thanh toán 1 phần'
                                    : 'Chưa thanh toán (Ghi nợ)')),
                        textColor: order.isCancelled
                            ? AppColors.textSecondary
                            : (order.remainingDebt <= 0.001
                                ? AppColors.success
                                : (order.amountPaid > 0
                                    ? AppColors.warning
                                    : AppColors.danger)),
                      ),
                      _buildDetailRow(
                        l10n.paymentMethod,
                        order.paymentMethod == 'split'
                            ? 'Kết hợp (TM + CK)'
                            : (order.paymentMethod == 'transfer'
                                ? l10n.paymentMethodTransfer
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
                        l10n.orderCreatedBy,
                        order.createdByName ?? order.createdBy ?? '—',
                      ),
                      const SizedBox(height: 16),

                      Text(
                        l10n.productList,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.textPrimary),
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
                                  imageUrl: matchingProduct?.primaryImageUrl ??
                                      matchingProduct?.imageUrl,
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
                                      Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 2,
                                        children: [
                                          Text(
                                            '${item.quantity} x ${currencyFormat.format(item.price)} đ',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary),
                                          ),
                                          if (item.returnedQuantity > 0)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 1),
                                              decoration: BoxDecoration(
                                                color: AppColors.warning
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                'Đã trả: ${item.returnedQuantity}',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppColors.warning,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 95),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      '${currencyFormat.format(item.price * item.quantity)} đ',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const Divider(height: 24, color: AppColors.divider),

                      Builder(builder: (context) {
                        final itemsSubtotal = order.items.fold(0.0,
                            (sum, item) => sum + (item.price * item.quantity));
                        final baseSubtotal =
                            itemsSubtotal > 0 ? itemsSubtotal : order.total;
                        final discount = order.discount > 0
                            ? order.discount
                            : ((baseSubtotal - order.netPayable) > 0.5
                                ? (baseSubtotal - order.netPayable)
                                : 0.0);
                        final remainingDebt = order.remainingDebt;

                        return Column(
                          children: [
                            if (discount > 0) ...[
                              _buildDetailRow('Tổng tiền hàng',
                                  '${currencyFormat.format(baseSubtotal)} đ'),
                              _buildDetailRow('Giảm giá',
                                  '${currencyFormat.format(discount)} đ',
                                  textColor: AppColors.danger),
                              _buildDetailRow(
                                'Khách cần trả',
                                '${currencyFormat.format(order.netPayable)} đ',
                                textColor: AppColors.primary,
                              ),
                            ] else ...[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      l10n.totalPaymentAmount,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '${currencyFormat.format(order.total)} đ',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: AppColors.primary),
                                      textAlign: TextAlign.end,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
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
                              (remainingDebt > 0 || order.isCancelled)
                                  ? 'Còn nợ'
                                  : 'Còn lại',
                              '${currencyFormat.format(order.isCancelled ? 0.0 : remainingDebt)} đ',
                              textColor:
                                  (remainingDebt > 0 && !order.isCancelled)
                                      ? AppColors.danger
                                      : (order.isCancelled
                                          ? AppColors.textSecondary
                                          : AppColors.success),
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
                          onPressed: () async {
                            Navigator.pop(context); // Đóng Bottom Sheet

                            // Nạp lại đơn hàng nháp vào giỏ hàng
                            var products =
                                ref.read(productListProvider).valueOrNull ?? [];
                            if (products.isEmpty) {
                              try {
                                products = await ref
                                    .read(productRepositoryProvider)
                                    .fetchAll();
                              } catch (_) {}
                            }

                            // Set mã đơn tạm đang hoạt động
                            ref.read(activeOrderIdProvider.notifier).state =
                                order.id;

                            // Tìm khách hàng hoặc tổng hợp fallback từ embedded customerName
                            final customers = ref
                                    .read(customerListNotifierProvider)
                                    .valueOrNull ??
                                [];
                            Customer? customer;
                            if (order.customerId != 'khach_le' &&
                                order.customerId != 'walk_in' &&
                                order.customerId.isNotEmpty) {
                              for (final c in customers) {
                                if (c.id == order.customerId) {
                                  customer = c;
                                  break;
                                }
                              }
                              customer ??= Customer(
                                id: order.customerId,
                                name: customerName,
                                phone: '',
                                email: '',
                                address: '',
                                purchases: const [],
                              );
                            }

                            if (order.storeId != null &&
                                order.storeId!.isNotEmpty) {
                              ref
                                  .read(selectedPOSBranchProvider.notifier)
                                  .state = order.storeId!;
                            }

                            ref.read(cartProvider.notifier).populateCart(
                                  order.items,
                                  products,
                                  orderId: order.id,
                                  customer: customer,
                                  discount: order.discount,
                                  isDiscountPercent: false,
                                  note: order.note,
                                );

                            // Điều hướng trực tiếp sang màn hình thanh toán
                            if (!context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => POSCheckoutPage(
                                  initialCustomer: customer,
                                  initialDiscount: order.discount,
                                  isDiscountPercent: false,
                                  initialNote: order.note,
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
              if ((order.isReturned || order.hasReturns) &&
                  !order.isCancelled) ...[
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
                            backgroundColor: AppColors.supervisor,
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
              if (order.status == 'completed' &&
                  !order.isCancelled &&
                  !order.isReturned) ...[
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
                            icon: const Icon(Icons.payments_outlined, size: 16),
                            label: Text(
                              'Thu nợ (${currencyFormat.format(order.remainingDebt)})',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.success,
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
                  icon: const Icon(Icons.print,
                      color: AppColors.primary, size: 18),
                  label: const Text(
                    'In Hóa Đơn',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.primary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side:
                        const BorderSide(color: AppColors.primary, width: 1.5),
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
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: textColor ?? AppColors.textPrimary,
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
          Flexible(
            child: Text(
              label,
              style:
                  const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right,
                        size: 16, color: AppColors.primary),
                  ],
                ),
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
