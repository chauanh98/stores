import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../common/utils/route_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/presentation/common/widgets/empty_state_view.dart';
import 'package:stores/presentation/common/widgets/error_view.dart';
import 'package:stores/presentation/common/widgets/min_height_scroll.dart';
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
import '../../../application/inventory/inventory_providers.dart';
import '../../../core/utils/order_code_resolver.dart';
import '../../../core/utils/search_text_helper.dart';
import '../../../core/utils/vietnamese_text_helper.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../notifications/widgets/notification_bell_action.dart';

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

  String _buildFilterDescription([BuildContext? ctx]) {
    final effectiveContext = ctx ?? (mounted ? context : null);
    final l10n =
        effectiveContext != null ? AppLocalizations.of(effectiveContext) : null;
    final parts = <String>[];
    if (_selectedStatusFilter != 'all') {
      String statusText;
      switch (_selectedStatusFilter) {
        case 'completed':
          statusText = l10n?.orderBadgeCompleted ?? 'Đã hoàn thành';
          break;
        case 'returned':
          statusText = l10n?.orderReturnOrders ?? 'Đơn trả hàng';
          break;
        case 'draft':
          statusText = l10n?.draft ?? 'Lưu tạm';
          break;
        case 'cancelled':
          statusText = l10n?.orderBadgeCancelled ?? 'Đã hủy';
          break;
        default:
          statusText = _selectedStatusFilter;
      }
      parts.add(l10n != null
          ? l10n.orderStatusFilterChip(statusText)
          : 'Trạng thái: $statusText');
    }
    if (_selectedPaymentMethodFilter != 'all') {
      final methodText = _selectedPaymentMethodFilter == 'transfer'
          ? (l10n?.transfer ?? 'Chuyển khoản')
          : (l10n?.cash ?? 'Tiền mặt');
      parts.add(l10n != null
          ? l10n.orderPaymentFilterChip(methodText)
          : 'Hình thức: $methodText');
    }
    if (_selectedDebtStatusFilter != 'all') {
      final debtText = _selectedDebtStatusFilter == 'paid'
          ? (l10n?.orderDebtPaidInFull ?? 'Đã thanh toán đủ')
          : (l10n?.orderDebtRemaining ?? 'Còn ghi nợ');
      parts.add(l10n != null
          ? l10n.orderDebtFilterChip(debtText)
          : 'Công nợ: $debtText');
    }
    if (_selectedStaffFilter != 'all') {
      parts.add(l10n != null
          ? l10n.orderStaffFilterChip(_selectedStaffFilter)
          : 'Nhân viên: $_selectedStaffFilter');
    }
    if (_searchQuery.trim().isNotEmpty) {
      parts.add(l10n != null
          ? l10n.orderSearchFilterChip(_searchQuery)
          : 'Tìm kiếm: "$_searchQuery"');
    }
    return parts.isEmpty
        ? (l10n?.orderAllInvoicesTitle ?? 'Tất cả hóa đơn')
        : parts.join(', ');
  }

  Future<void> _exportInvoicesToExcel(
    BuildContext context,
    List<Order> filteredOrders,
    Map<String, Customer> customerMap,
    String branchLabel,
  ) async {
    final currentUser = ref.read(authProvider);
    if (!kIsWeb || (currentUser?.isAdmin != true)) return;

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (filteredOrders.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n?.orderNoInvoicesToExport ??
              'Không có dữ liệu hóa đơn để xuất Excel.'),
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
      final filterDesc = _buildFilterDescription(context);

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
            content: Text(l10n != null
                ? l10n.orderExcelExportError(e.toString())
                : 'Lỗi khi xuất file Excel: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _importInvoices() async {
    final user = ref.read(authProvider);
    if (!kIsWeb || (user?.isAdmin != true)) return;

    final l10n = mounted ? AppLocalizations.of(context) : null;
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
            SnackBar(
                content: Text(l10n?.orderNoFileSelected ??
                    'Không có file nào được chọn')),
          );
        }
        return;
      }

      final fileBytes = result.files.first.bytes ??
          (result.files.first.path != null
              ? await File(result.files.first.path!).readAsBytes()
              : null);

      if (fileBytes == null) {
        throw Exception(
            l10n?.orderCannotReadFile ?? 'Không thể đọc nội dung file');
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

      // Danh sách hoá đơn là listener realtime nên tự nhận các đơn vừa nhập.

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
            content: Text(l10n != null
                ? l10n.orderExcelImportError(e.toString())
                : 'Lỗi khi nhập file Excel: $e'),
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
      branchLabel = l10n.branchSelectedCount(selectedBranchIds.length);
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
          const NotificationBellAction(),
          if (kIsWeb && (user?.isAdmin == true))
            PopupMenuButton<String>(
              key: const Key('invoices_excel_actions_menu'),
              icon: const Icon(Icons.more_vert),
              tooltip: l10n.excelActions,
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
                PopupMenuItem<String>(
                  value: 'import_excel',
                  child: Row(
                    children: [
                      const Icon(Icons.upload_file, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(l10n.importInvoicesFromExcel),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'export_excel',
                  child: Row(
                    children: [
                      const Icon(Icons.download, color: AppColors.success),
                      const SizedBox(width: 8),
                      Text(l10n.exportInvoicesToExcel),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: MinHeightScroll(
          minHeight: 420,
          child: Column(
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
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
                                ? _buildInvoicesEmptyState(l10n.noInvoicesFound)
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
                                            .where(
                                                (i) => i.returnedQuantity > 0)
                                            .toList();
                                        for (final i in returnedItems) {
                                          dayTotalQty += i.returnedQuantity;
                                        }
                                        dayAmount +=
                                            (o.total > 0 ? o.total : 0.0);
                                      }
                                      return DateGroupHeader(
                                        date: date,
                                        itemCount: dayItems.length,
                                        itemUnit: dayTotalQty > 0
                                            ? l10n.orderReturnSummaryLabel(
                                                dayTotalQty)
                                            : l10n.orderReturnUnit,
                                        totalAmount: dayAmount,
                                        currencyFormat: currencyFormat,
                                      );
                                    },
                                    itemUnit: l10n.orderReturnUnit,
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
                      return _buildInvoicesEmptyState(l10n.noInvoicesFound);
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
                          totalProductQuantity +=
                              (i.quantity - i.returnedQuantity);
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
                                    ? l10n
                                        .orderInvoicesSummaryLabel(dayTotalQty)
                                    : l10n.orderInvoiceUnit,
                                totalAmount: dayAmount,
                                currencyFormat: currencyFormat,
                              );
                            },
                            itemUnit: l10n.orderInvoiceUnit,
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
                  error: (e, _) => ErrorView(
                    e,
                    onRetry: () => ref.invalidate(
                        allBranchesOrdersByDateRangeProvider(activeRange)),
                  ),
                ),
              ),
            ],
          )),
    );
  }

  /// Trạng thái rỗng: nếu đang tìm kiếm thì gợi ý & cho xoá từ khoá nhanh.
  Widget _buildInvoicesEmptyState(String title) {
    final hasSearch = _searchQuery.trim().isNotEmpty;
    return EmptyStateView(
      icon: hasSearch ? Icons.search_off_rounded : Icons.receipt_long_outlined,
      title: title,
      message: hasSearch
          ? 'Không có hoá đơn khớp "${_searchQuery.trim()}". Có thể gõ không dấu, hoặc đổi khoảng thời gian / bộ lọc.'
          : 'Chưa có hoá đơn trong khoảng thời gian và bộ lọc đang chọn.',
      actionLabel: hasSearch ? 'Xoá từ khoá' : null,
      actionIcon: Icons.close_rounded,
      onAction: hasSearch
          ? () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            }
          : null,
    );
  }

  // Bộ nhớ đệm kết quả lọc: tránh lọc + sắp xếp lại toàn bộ danh sách hoá đơn
  // mỗi lần build chỉ vì đổi trạng thái mở rộng/thu gọn thẻ.
  List<Order>? _filterCacheOrders;
  List<Customer>? _filterCacheCustomers;
  String? _filterCacheKey;
  List<Order>? _filterCacheResult;

  List<Order> _applyFilters(List<Order> orders, List<Customer> customers) {
    final key = '$_selectedStatusFilter|$_selectedPaymentMethodFilter|'
        '$_selectedDebtStatusFilter|$_selectedStaffFilter|$_searchQuery';
    if (identical(orders, _filterCacheOrders) &&
        identical(customers, _filterCacheCustomers) &&
        key == _filterCacheKey &&
        _filterCacheResult != null) {
      return _filterCacheResult!;
    }
    final result = _computeFilters(orders, customers);
    _filterCacheOrders = orders;
    _filterCacheCustomers = customers;
    _filterCacheKey = key;
    _filterCacheResult = result;
    return result;
  }

  List<Order> _computeFilters(List<Order> orders, List<Customer> customers) {
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
          // Khớp thêm kiểu không dấu & nhiều từ khoá ("nguyen van a", "nuoc ngot").
          final tokens = SearchTextHelper.queryTokens(query);
          final orderHaystack = SearchTextHelper.haystackOf(
            order,
            () => [
              order.id,
              order.customerName,
              order.customerId,
              order.createdByName,
              order.createdBy,
              for (final i in order.items) ...[i.productName, i.productId],
            ],
            namespace: 'invoices',
          );
          final extra =
              VietnameseTextHelper.normalizeUnaccented('$cName $cPhone');
          if (!SearchTextHelper.matchesTokens(
              '$orderHaystack $extra', tokens)) {
            return false;
          }
        }
      }

      return true;
    }).toList();

    // Sắp xếp đơn mới nhất lên đầu
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  Widget _buildMultiDimensionalFilterBar(List<UserAccount> staffAccounts) {
    final l10n = AppLocalizations.of(context);
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Status Filters
            _buildStatusChip(
                'all', l10n?.orderAllStatuses ?? 'Tất cả trạng thái'),
            const SizedBox(width: 6),
            _buildStatusChip(
                'completed', l10n?.orderBadgeCompleted ?? 'Đã hoàn thành'),
            const SizedBox(width: 6),
            _buildStatusChip(
                'returned', l10n?.orderReturnOrders ?? 'Đơn trả hàng'),
            const SizedBox(width: 6),
            _buildStatusChip('draft', l10n?.draft ?? 'Lưu tạm'),
            const SizedBox(width: 6),
            _buildStatusChip(
                'cancelled', l10n?.orderBadgeCancelled ?? 'Đã hủy'),
            if (_hasActiveFilters) ...[
              const SizedBox(width: 4),
              IconButton(
                key: const Key('invoices_reset_filter_button'),
                icon: const Icon(Icons.refresh,
                    size: 18, color: AppColors.primary),
                tooltip: l10n?.commonResetFilter ?? 'Đặt lại bộ lọc',
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
    final l10n = AppLocalizations.of(context);
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
                  ? (l10n?.orderPaymentMethodFilterTitle ?? 'PT thanh toán')
                  : (_selectedPaymentMethodFilter == 'transfer'
                      ? (l10n?.transfer ?? 'Chuyển khoản')
                      : (l10n?.cash ?? 'Tiền mặt')),
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
        PopupMenuItem(
            value: 'all',
            child: Text(l10n?.orderAllPaymentMethods ?? 'Tất cả phương thức')),
        PopupMenuItem(value: 'cash', child: Text(l10n?.cash ?? 'Tiền mặt')),
        PopupMenuItem(
            value: 'transfer', child: Text(l10n?.transfer ?? 'Chuyển khoản')),
      ],
    );
  }

  Widget _buildDebtStatusDropdown() {
    final l10n = AppLocalizations.of(context);
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
                  ? (l10n?.customerDebt ?? 'Công nợ')
                  : (_selectedDebtStatusFilter == 'paid'
                      ? (l10n?.orderDebtPaidShort ?? 'Đã TT đủ')
                      : (l10n?.orderDebtRemaining ?? 'Còn ghi nợ')),
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
        PopupMenuItem(
            value: 'all', child: Text(l10n?.orderAllDebts ?? 'Tất cả công nợ')),
        PopupMenuItem(
            value: 'paid',
            child: Text(l10n?.orderDebtPaidInFull ?? 'Đã thanh toán đủ')),
        PopupMenuItem(
            value: 'debt',
            child: Text(l10n?.orderDebtRemaining ?? 'Còn ghi nợ')),
      ],
    );
  }

  Widget _buildStaffDropdown(List<UserAccount> staffAccounts) {
    final l10n = AppLocalizations.of(context);
    final isFiltered = _selectedStaffFilter != 'all';
    String staffLabel = l10n?.staff ?? 'Nhân viên';
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
        PopupMenuItem(
            value: 'all',
            child: Text(l10n?.orderAllStaff ?? 'Tất cả nhân viên')),
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
    final l10n = AppLocalizations.of(context);
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
            Flexible(
                child: InkWell(
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
                    Flexible(
                      child: Text(
                        l10n?.orderFilterActiveCount(
                                filterState.activeFilterCount) ??
                            'Lọc (${filterState.activeFilterCount})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.close, size: 14, color: AppColors.primary),
                  ],
                ),
              ),
            )),
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
    final l10n = AppLocalizations.of(context);
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
                  l10n?.orderTotalReturnCount(totalReturnCount) ??
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
                  l10n?.orderTotalRefundAmount(
                          format.format(totalRefundAmount)) ??
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
                  l10n?.orderCashRefundedAmount(
                          format.format(totalCashRefunded)) ??
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
                  l10n?.orderDebtDeductedAmount(
                          format.format(totalDebtDeducted)) ??
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
          final l10n = AppLocalizations.of(context);
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
                          Text(
                            l10n?.invoicesTitle ?? 'Hóa đơn',
                            style: const TextStyle(
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
                              l10n?.orderCountLabelShort(totalInvoices) ??
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
                          Text(
                            l10n?.orderTotalGoodsShort ?? 'Tổng hàng',
                            style: const TextStyle(
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
                          Text(
                            l10n?.totalProductAmount ?? 'Tổng tiền hàng',
                            style: const TextStyle(
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
                      if (constraints.maxWidth >= 280) ...[
                        const SizedBox(width: 3),
                        Text(
                          _expandAll
                              ? (l10n?.orderCollapseItems ?? 'Gọn')
                              : (l10n?.orderExpandItems ?? 'Xem món'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _expandAll
                                ? AppColors.primary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ],
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
      statusBadgeText = l10n.orderBadgeCancelled;
      statusBadgeColor = AppColors.dangerDeep;
      statusBadgeBgColor = AppColors.dangerLightest;
    } else if (order.isReturned) {
      statusBadgeText = l10n.orderBadgeReturned;
      statusBadgeColor = AppColors.supervisorDark;
      statusBadgeBgColor = AppColors.supervisorLight;
    } else if (order.hasReturns) {
      statusBadgeText = l10n.orderBadgePartiallyReturned;
      statusBadgeColor = AppColors.supervisorDark;
      statusBadgeBgColor = AppColors.supervisorLight;
    } else if (order.status == 'draft') {
      statusBadgeText = l10n.draft;
      statusBadgeColor = AppColors.warningDark;
      statusBadgeBgColor = AppColors.warningLight;
    } else {
      statusBadgeText = l10n.orderBadgeCompleted;
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
                                  l10n.orderItemAndQtySummary(
                                      itemCount, totalQuantity),
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
                                          ? l10n.orderCollapseItemsFull
                                          : l10n.orderExpandItemsFull,
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
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: AppColors.border, width: 0.6),
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'x${item.quantity}',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (item.returnedQuantity > 0) ...[
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    l10n.orderItemReturnedQty(
                                        item.returnedQuantity),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.supervisorDark,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 8),
                              Flexible(
                                flex: 2,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    '${currencyFormat.format(item.price * item.quantity)} đ',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
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
                                l10n.orderDiscountAmount(
                                    currencyFormat.format(order.discount)),
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
                                l10n.orderRemainingDebtTag(
                                    currencyFormat.format(order.remainingDebt)),
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
    if (id == 'khach_le' || id == 'walk_in' || id.isEmpty) {
      return l10n.retailCustomer;
    }
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
            final currentStoreId = ref.watch(currentStoreIdProvider);
            final mockBranches = getMockBranches(currentStoreId);

            return Container(
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              child: SingleChildScrollView(child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            l10n.selectBranch,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: InkWell(
                            onTap: () {
                              ref.read(selectedBranchesProvider.notifier).selectAll();
                            },
                            child: Text(
                              l10n.selectAll,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                            ),
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
                        ref.read(selectedBranchesProvider.notifier).toggleBranch(branch.id);
                      },
                    );
                  }),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => closeRoute(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        child: Text(l10n.doneBtn),
                      ),
                    ),
                  )
                ],
              )),
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
        // Closes THIS sheet only. Returns false when it is already closing /
        // covered (rapid double tap): a second tap used to pop the page below
        // the sheet and then use its dead BuildContext.
        bool closeSheet() {
          if (!sheetContext.mounted) return false;
          final route = ModalRoute.of(sheetContext);
          if (route == null || !route.isActive || !route.isCurrent) {
            return false;
          }
          Navigator.of(sheetContext).pop();
          return true;
        }

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
            phone: order.customerPhone ?? '',
            email: '',
            address: '',
            purchases: const [],
          );
        } else if (customerName.isNotEmpty &&
            customerName != 'Khách lẻ' &&
            customerName != 'Walk-in Customer') {
          for (final c in customers) {
            if (c.name.trim().toLowerCase() ==
                customerName.trim().toLowerCase()) {
              targetCustomer = c;
              break;
            }
          }
        }

        final customerPhone = (targetCustomer?.phone != null &&
                targetCustomer!.phone.trim().isNotEmpty)
            ? targetCustomer.phone.trim()
            : ((order.customerPhone != null &&
                    order.customerPhone!.trim().isNotEmpty)
                ? order.customerPhone!.trim()
                : '');

        final products =
            ref.read(productListProvider).valueOrNull ?? <Product>[];
        final orderProductIds = {for (final i in order.items) i.productId};
        final productMap = {
          for (final p in products)
            if (orderProductIds.contains(p.id)) p.id: p
        };
        final currentUser = ref.read(authProvider);
        final canDelete = currentUser?.canDeleteInvoice ?? false;

        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
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
                              ? l10n.orderCancelledDetailTitle
                              : l10n.invoiceDetail),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: closeSheet,
                  )
                ],
              ),
              const Divider(color: AppColors.divider),

              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
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
                                  Row(
                                    children: [
                                      const Icon(Icons.cancel,
                                          color: AppColors.danger, size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        l10n.orderCancelledBanner,
                                        style: const TextStyle(
                                          color: AppColors.danger,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    l10n.orderCancelReasonLabel(
                                        order.cancelReason ?? '—'),
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.textPrimary),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    l10n.orderCancelledByLabel(
                                        order.cancelledByName ??
                                            order.cancelledBy ??
                                            '—'),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary),
                                  ),
                                  if (order.cancelledAt != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      l10n.orderCancelledAtLabel(
                                          DateFormat('dd/MM/yyyy HH:mm')
                                              .format(order.cancelledAt!)),
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
                                if (!sheetContext.mounted) return;
                                Navigator.push(
                                  sheetContext,
                                  MaterialPageRoute(
                                    builder: (context) => CustomerDetailPage(
                                        customer: targetCustomer!),
                                  ),
                                );
                              },
                            )
                          else
                            _buildDetailRow(l10n.customers, customerName),
                          if (customerPhone.isNotEmpty)
                            _buildCustomerPhoneRow(sheetContext, customerPhone),
                          _buildDetailRow(
                            l10n.createdTime,
                            DateFormat('dd/MM/yyyy HH:mm')
                                .format(order.createdAt),
                          ),
                          _buildDetailRow(
                            l10n.status,
                            order.isCancelled
                                ? l10n.orderBadgeCancelled
                                : (order.isReturned
                                    ? l10n.orderBadgeReturned
                                    : (order.hasReturns
                                        ? l10n.orderBadgePartiallyReturned
                                        : (order.status == 'draft'
                                            ? l10n.draft
                                            : l10n.orderBadgeCompleted))),
                            textColor: order.isCancelled
                                ? AppColors.danger
                                : (order.status == 'draft'
                                    ? AppColors.warning
                                    : (order.isReturned
                                        ? AppColors.supervisor
                                        : AppColors.success)),
                          ),
                          _buildDetailRow(
                            l10n.payment,
                            order.isCancelled
                                ? l10n.orderPaymentNotApplicable
                                : (order.remainingDebt <= 0.001
                                    ? l10n.orderPaymentPaidFull
                                    : (order.amountPaid > 0
                                        ? l10n.orderPaymentPartial
                                        : l10n.orderPaymentUnpaidDebt)),
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
                                ? l10n.orderPaymentSplit
                                : (order.paymentMethod == 'transfer'
                                    ? l10n.paymentMethodTransfer
                                    : l10n.cash),
                          ),
                          if (order.note != null &&
                              order.note!.trim().isNotEmpty) ...[
                            _buildDetailRow(
                              l10n.note,
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
                        ],
                      ),
                    ),
                    SliverList.builder(
                      itemCount: order.items.length,
                      itemBuilder: (context, index) {
                        final item = order.items[index];
                        final matchingProduct = productMap[item.productId];
                        final hasDiscount = item.discount > 0 ||
                            item.originalPrice > item.price;
                        final origPrice = item.originalPrice > item.price
                            ? item.originalPrice
                            : (item.effectiveOriginalPrice > item.price
                                ? item.effectiveOriginalPrice
                                : (item.discount > 0
                                    ? (item.isDiscountPercent
                                        ? (item.discount < 100
                                            ? item.price /
                                                (1 - item.discount / 100)
                                            : (matchingProduct?.price ??
                                                item.price))
                                        : (item.price + item.discount))
                                    : (matchingProduct != null &&
                                            matchingProduct.price > item.price
                                        ? matchingProduct.price
                                        : item.price)));
                        final showStrikethrough =
                            hasDiscount && origPrice > item.price;

                        return InkWell(
                          onTap: () {
                            if (!sheetContext.mounted) return;
                            if (matchingProduct != null) {
                              Navigator.push(
                                sheetContext,
                                MaterialPageRoute(
                                  builder: (context) => ProductDetailPage(
                                      product: matchingProduct),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
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
                                      if (item.note != null &&
                                          item.note!.trim().isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          item.note!.trim(),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                      Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 2,
                                        children: [
                                          if (showStrikethrough) ...[
                                            Text(
                                              '${item.quantity} x ',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      AppColors.textSecondary),
                                            ),
                                            Text(
                                              '${currencyFormat.format(origPrice)} đ',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                                decoration:
                                                    TextDecoration.lineThrough,
                                              ),
                                            ),
                                            Text(
                                              '${currencyFormat.format(item.price)} đ',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ] else ...[
                                            Text(
                                              '${item.quantity} x ${currencyFormat.format(item.price)} đ',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      AppColors.textSecondary),
                                            ),
                                          ],
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
                                                l10n.orderItemReturnedCount(
                                                    item.returnedQuantity),
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
                      },
                    ),
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 24, color: AppColors.divider),
                          Builder(builder: (context) {
                            final itemsSubtotal = order.items.fold(
                                0.0,
                                (sum, item) =>
                                    sum + (item.price * item.quantity));
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
                                  _buildDetailRow(l10n.totalProductAmount,
                                      '${currencyFormat.format(baseSubtotal)} đ'),
                                  _buildDetailRow(l10n.inventoryDiscount,
                                      '${currencyFormat.format(discount)} đ',
                                      textColor: AppColors.danger),
                                  _buildDetailRow(
                                    l10n.amountToPay,
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
                                _buildDetailRow(l10n.paid,
                                    '${currencyFormat.format(order.amountPaid)} đ'),
                                if (order.paymentMethod == 'split') ...[
                                  _buildDetailRow(l10n.orderCashBreakdown,
                                      '${currencyFormat.format(order.cashAmount ?? 0.0)} đ'),
                                  _buildDetailRow(l10n.orderTransferBreakdown,
                                      '${currencyFormat.format(order.transferAmount ?? 0.0)} đ'),
                                ],
                                const SizedBox(height: 4),
                                _buildDetailRow(
                                  (remainingDebt > 0 || order.isCancelled)
                                      ? l10n.orderRemainingDebtShort
                                      : l10n.orderRemainingAmountShort,
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
                  ],
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
                            if (!closeSheet()) return; // Đóng Bottom Sheet
                            if (!context.mounted) return;

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
                            if (!closeSheet()) return;
                            if (!context.mounted) return;
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
                          label: Text(
                            l10n.orderActionViewReturn,
                            style: const TextStyle(
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

              // Completed Order Action Buttons (Edit, Return, Debt collection, Cancel)
              if (order.status == 'completed' &&
                  !order.isCancelled &&
                  !order.isReturned) ...[
                Row(
                  children: [
                    // Edit Invoice Button ("Sửa hóa đơn") - Chỉ hiển thị cho hóa đơn chưa từng có sản phẩm trả lại
                    if (!order.hasReturns) ...[
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: OutlinedButton.icon(
                            key: const Key('edit_invoice_action_button'),
                            onPressed: () => _handleEditInvoice(
                              context,
                              ref,
                              order,
                              customerName,
                              targetCustomer,
                              closeSheet: closeSheet,
                            ),
                            icon:
                                const Icon(Icons.edit_note_outlined, size: 16),
                            label: Text(
                              l10n.orderActionEditInvoice,
                              style: const TextStyle(
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
                      const SizedBox(width: 8),
                    ],

                    // Return Goods Button ("Trả hàng")
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: OutlinedButton.icon(
                          key: const Key('return_order_action_button'),
                          onPressed: () async {
                            if (!closeSheet()) return; // Close details sheet
                            if (!context.mounted) return;
                            await ReturnOrderBottomSheet.show(
                              context,
                              order: order,
                              customer: targetCustomer,
                            );
                          },
                          icon: const Icon(Icons.assignment_return_outlined,
                              size: 16),
                          label: Text(
                            l10n.orderActionReturnGoods,
                            style: const TextStyle(
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
                  ],
                ),
                if (order.hasDebt || canDelete) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Debt Collection Button ("Thu nợ")
                      if (order.hasDebt) ...[
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: FilledButton.icon(
                              key: const Key('collect_debt_action_button'),
                              onPressed: () async {
                                if (!closeSheet()) return; // Close details sheet
                                if (!context.mounted) return;
                                await DebtCollectionDialog.show(
                                  context,
                                  order: order,
                                  customer: targetCustomer,
                                  remainingDebt: order.remainingDebt,
                                );
                              },
                              icon:
                                  const Icon(Icons.payments_outlined, size: 16),
                              label: Text(
                                l10n.orderActionCollectDebt(
                                    currencyFormat.format(order.remainingDebt)),
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
                      if (order.hasDebt && canDelete) const SizedBox(width: 8),
                      // Cancel Order Button ("Hủy HĐ")
                      if (canDelete) ...[
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: OutlinedButton.icon(
                              key: const Key('cancel_invoice_action_button'),
                              onPressed: () async {
                                if (!closeSheet()) return; // Close details sheet
                                if (!context.mounted) return;
                                await CancelInvoiceDialog.show(
                                  context,
                                  order: order,
                                  customer: targetCustomer,
                                );
                              },
                              icon: const Icon(Icons.delete_forever,
                                  color: AppColors.danger, size: 16),
                              label: Text(
                                l10n.orderActionCancelInvoice,
                                style: const TextStyle(
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
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 8),
              ],

              // Cancelled Order Action Buttons (Recreate as new order, or Restore order)
              if (order.isCancelled) ...[
                Row(
                  children: [
                    // Nút Tạo lại đơn từ đây
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: OutlinedButton.icon(
                          key: const Key(
                              'recreate_cancelled_order_action_button'),
                          onPressed: () => _handleEditInvoice(
                            context,
                            ref,
                            order,
                            customerName,
                            targetCustomer,
                            isFromCancelled: true,
                            closeSheet: closeSheet,
                          ),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: Text(
                            l10n.orderActionRecreate,
                            style: const TextStyle(
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
                    if (canDelete) ...[
                      const SizedBox(width: 8),
                      // Nút Khôi phục đơn
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: FilledButton.icon(
                            key: const Key(
                                'restore_cancelled_order_action_button'),
                            onPressed: () => _showRestoreOrderDialog(
                              context,
                              ref,
                              order,
                              targetCustomer,
                              closeSheet: closeSheet,
                            ),
                            icon: const Icon(Icons.restore, size: 16),
                            label: Text(
                              l10n.orderActionRestore,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
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
                    // The sheet may already be closing (double tap): its context
                    // is not valid for showDialog then.
                    if (!sheetContext.mounted) return;
                    final config = ref.read(storePaymentConfigProvider);
                    await InvoicePrintHelper.printInvoice(
                      sheetContext,
                      order,
                      targetCustomer,
                      config,
                    );
                  },
                  icon: const Icon(Icons.print,
                      color: AppColors.primary, size: 18),
                  label: Text(
                    l10n.orderActionPrint,
                    style: const TextStyle(
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

  Widget _buildCustomerPhoneRow(BuildContext context, String phone) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              l10n.phone,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
              child: InkWell(
            key: const Key('copy_customer_phone_button'),
            borderRadius: BorderRadius.circular(4),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: phone));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.orderCopyPhoneSuccess),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.copy,
                    size: 15,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }

  Future<void> _handleEditInvoice(
    BuildContext context,
    WidgetRef ref,
    Order order,
    String customerName,
    Customer? targetCustomer, {
    bool isFromCancelled = false,
    required bool Function() closeSheet,
  }) async {
    // Closes the details sheet only (a double tap used to pop the page too).
    if (!closeSheet()) return;
    if (!context.mounted) return;

    if (!isFromCancelled &&
        (order.isCancelled ||
            order.isReturned ||
            order.hasReturns ||
            order.status != 'completed')) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n?.orderCannotEditCancelledOrReturned ??
              'Không thể sửa hóa đơn đã hủy hoặc đã có sản phẩm trả hàng.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // 1. Sinh mã hóa đơn mới:
    // - Sửa hóa đơn (!isFromCancelled): Phương án 1 (mã cũ + '_' + số lần sửa + 1: HD000001 -> HD000001_01)
    // - Tạo lại đơn từ đơn đã hủy (isFromCancelled): lấy mã hóa đơn mới tiếp theo của hệ thống
    final String newOrderId;
    try {
      newOrderId = isFromCancelled
          ? await OrderCodeResolver.resolveNextOrderCode(
              ref,
              storeId: order.storeId,
              currentOrderId: order.id,
            )
          : await OrderCodeResolver.resolveVersionedOrderCode(
              ref,
              originalOrderId: order.id,
              storeId: order.storeId,
            );
    } on OrderCodeUnavailableException catch (e) {
      if (!mounted) return;
      // `this.context`: context tham số thuộc bottom sheet vừa đóng ở đầu hàm.
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
            content: Text(e.toString()), backgroundColor: AppColors.warning),
      );
      return;
    }

    // 2. Tải danh mục sản phẩm nếu chưa có trong cache
    var products = ref.read(productListProvider).valueOrNull ?? [];
    if (products.isEmpty) {
      try {
        products = await ref.read(productRepositoryProvider).fetchAll();
      } catch (_) {}
    }

    // 3. Đặt mã đơn hàng phiên bản mới và lưu thông tin hóa đơn cũ cần sửa (nếu không phải từ đơn đã hủy)
    ref.read(activeOrderIdProvider.notifier).state = newOrderId;
    if (!isFromCancelled) {
      ref.read(editingOriginalOrderProvider.notifier).state = order;
    } else {
      ref.read(editingOriginalOrderProvider.notifier).state = null;
    }

    // 4. Tìm kiếm thông tin khách hàng đầy đủ
    final customers = ref.read(customerListNotifierProvider).valueOrNull ?? [];
    Customer? customer = targetCustomer;
    if (customer == null &&
        order.customerId != 'khach_le' &&
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
        phone: order.customerPhone ?? '',
        email: '',
        address: '',
        purchases: const [],
      );
    } else if (customer == null &&
        customerName.isNotEmpty &&
        customerName != 'Khách lẻ' &&
        customerName != 'Walk-in Customer') {
      for (final c in customers) {
        if (c.name.trim().toLowerCase() == customerName.trim().toLowerCase()) {
          customer = c;
          break;
        }
      }
    }

    // 5. Đồng bộ chi nhánh POS
    if (order.storeId != null && order.storeId!.isNotEmpty) {
      ref.read(selectedPOSBranchProvider.notifier).state = order.storeId!;
    }

    // 6. Nạp đầy đủ thông tin vào giỏ hàng POS
    ref.read(cartProvider.notifier).populateCart(
          order.items,
          products,
          orderId: newOrderId,
          customer: customer,
          discount: order.discount,
          isDiscountPercent: false,
          note: order.note,
        );

    // 7. Mở màn hình POS Checkout
    if (!context.mounted) return;
    await Navigator.push(
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

    // Dọn dẹp trạng thái sửa dở dang nếu người dùng nhấn Back / thoát mà không lưu hoặc thanh toán
    if (ref.read(editingOriginalOrderProvider) != null ||
        ref.read(activeOrderIdProvider) != null) {
      ref.read(editingOriginalOrderProvider.notifier).state = null;
      ref.read(activeOrderIdProvider.notifier).state = null;
      ref.read(cartProvider.notifier).clearCart();
    }
  }

  Future<void> _showRestoreOrderDialog(
    BuildContext context,
    WidgetRef ref,
    Order order,
    Customer? targetCustomer, {
    required bool Function() closeSheet,
  }) async {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        scrollable: true,
        title: Text(l10n.orderRestoreInvoiceTitle),
        content: Text(
          l10n.orderRestoreInvoiceMsg(order.id),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l10n.orderRestoreInvoiceSkip),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(l10n.orderRestoreInvoiceConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    if (!closeSheet()) return; // Đóng Bottom Sheet chi tiết
    if (!context.mounted) return;

    try {
      final now = DateTime.now();
      final String storeId =
          (order.storeId != null && order.storeId!.isNotEmpty)
              ? order.storeId!
              : (ref.read(selectedPOSBranchProvider) ?? 'store_001');
      final currentUser = ref.read(authProvider);
      final productRepo = ref.read(productRepositoryProvider);
      final inventoryRepo = ref.read(inventoryRepositoryProvider);
      final customerRepo = ref.read(customerRepositoryProvider);
      final orderRepo = ref.read(orderRepositoryProvider);

      // 1. Trừ lại tồn kho cho các sản phẩm
      for (final item in order.items) {
        final qtyToDeduct = item.activeQuantity;
        if (qtyToDeduct <= 0) continue;

        final product = await productRepo.fetchById(item.productId);
        if (product != null) {
          if (product.isCombo && product.comboComponents.isNotEmpty) {
            for (final comp in product.comboComponents) {
              final childProduct = await productRepo.fetchById(comp.productId);
              if (childProduct != null) {
                final compQtyToDeduct = qtyToDeduct * comp.quantity;
                final updatedBranchStocks = _updateBranchStockHelper(
                    childProduct.branchStocks, storeId, -compQtyToDeduct);
                await productRepo.upsert(
                    childProduct.copyWith(branchStocks: updatedBranchStocks));

                final tx = InventoryTransaction(
                  id: 'restore_export_${now.millisecondsSinceEpoch}_${childProduct.id}',
                  productId: childProduct.id,
                  type: TransactionType.export,
                  quantity: compQtyToDeduct,
                  date: now,
                  note: 'Khôi phục HĐ ${order.id} (Combo: ${product.name})',
                  createdBy: currentUser?.username,
                  createdByName: currentUser?.displayName ?? currentUser?.name,
                  storeId: storeId,
                );
                await inventoryRepo.record(tx);
              }
            }
          } else {
            final updatedBranchStocks = _updateBranchStockHelper(
                product.branchStocks, storeId, -qtyToDeduct);
            await productRepo
                .upsert(product.copyWith(branchStocks: updatedBranchStocks));

            final tx = InventoryTransaction(
              id: 'restore_export_${now.millisecondsSinceEpoch}_${product.id}',
              productId: product.id,
              type: TransactionType.export,
              quantity: qtyToDeduct,
              date: now,
              note: 'Khôi phục HĐ ${order.id}',
              createdBy: currentUser?.username,
              createdByName: currentUser?.displayName ?? currentUser?.name,
              storeId: storeId,
            );
            await inventoryRepo.record(tx);
          }
        }
      }

      // 2. Ghi nhận lại công nợ và doanh số khách hàng (nếu là khách hàng đăng ký)
      final customerId = order.customerId;
      if (customerId.isNotEmpty &&
          customerId != 'khach_le' &&
          customerId != 'walk_in') {
        final cust = await customerRepo.fetchById(customerId);
        if (cust != null) {
          final debtToAdd =
              (order.total - order.amountPaid).clamp(0.0, double.infinity);
          final updatedDebt = cust.displayCurrentDebt + debtToAdd;
          final updatedTotalSales = (cust.totalSales ?? 0.0) + order.total;
          final updatedNetSales =
              (cust.netSales ?? cust.totalSales ?? 0.0) + order.netPayable;

          await customerRepo.upsert(cust.copyWith(
            currentDebt: updatedDebt,
            totalSales: updatedTotalSales,
            netSales: updatedNetSales,
          ));
        }
      }

      // 3. Cập nhật lại hóa đơn về trạng thái completed
      final restoredDebtAmount =
          (order.total - order.amountPaid).clamp(0.0, double.infinity);
      final restoredOrder = order.copyWith(
        status: 'completed',
        debtAmount: restoredDebtAmount,
        clearCancelledInfo: true,
      );
      await orderRepo.update(restoredOrder);

      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.orderRestoreSuccess(order.id) ??
                'Đã khôi phục thành công hóa đơn ${order.id}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.orderRestoreError(e.toString()) ??
                'Lỗi khi khôi phục hóa đơn: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Map<String, int> _updateBranchStockHelper(
      Map<String, int> currentStocks, String storeId, int delta) {
    final stocks = Map<String, int>.from(currentStocks);
    String targetKey = storeId;
    if (!stocks.containsKey(storeId)) {
      if (storeId == 'store_001' && stocks.containsKey('branch_1')) {
        targetKey = 'branch_1';
      } else if (storeId == 'store_002' && stocks.containsKey('branch_2')) {
        targetKey = 'branch_2';
      } else if (storeId == 'branch_1' && stocks.containsKey('store_001')) {
        targetKey = 'store_001';
      } else if (storeId == 'branch_2' && stocks.containsKey('store_002')) {
        targetKey = 'store_002';
      }
    }
    final current = stocks[targetKey] ?? 0;
    stocks[targetKey] = max(0, current + delta);
    return stocks;
  }

  void _showCancelDraftDialog(
      BuildContext context, WidgetRef ref, String orderId) {
    // Rapid double taps can call this after the originating sheet is gone.
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
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
              // A double tap can open this dialog twice: the sheet may already
              // be gone by the time the second confirmation runs.
              if (!context.mounted) return;
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
                    SnackBar(
                        content: Text(l10n.orderCancelError(e.toString()))),
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
