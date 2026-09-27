import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../application/auth/auth_providers.dart';
import '../../../application/customers/customers_providers.dart';
import '../../../application/customers/usecases/import_customers_usecase.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../core/services/filter_storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/excel_helper.dart';
import '../../../core/utils/file_saver.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/user_account.dart';
import '../../common/widgets/error_view.dart';
import '../../common/widgets/loading_indicator.dart';
import '../../common/widgets/scroll_aware_fab.dart';
import '../widgets/customer_list_tile.dart';
import 'add_customer_page.dart';

class CustomersPage extends ConsumerStatefulWidget {
  final CustomerDebtFilter? initialDebtFilter;

  const CustomersPage({
    super.key,
    this.initialDebtFilter,
  });

  @override
  ConsumerState<CustomersPage> createState() => CustomersPageState();
}

class CustomersPageState extends ConsumerState<CustomersPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _currentLimit = 50;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final storage = ref.read(filterStorageServiceProvider);
      final user = ref.read(authProvider);
      final canViewDebt = user?.canViewDebtSummary ?? false;

      if (!canViewDebt) {
        ref.read(customerDebtFilterProvider.notifier).state =
            CustomerDebtFilter.all;
      } else if (widget.initialDebtFilter != null) {
        ref.read(customerDebtFilterProvider.notifier).state =
            widget.initialDebtFilter!;
        persistCustomerFilters(ref, debtFilter: widget.initialDebtFilter);
      }

      // Hydrate from storage if present
      final saved = await storage.loadFilter('customers', user?.username);
      if (saved != null &&
          mounted &&
          ref.read(authProvider)?.username == user?.username) {
        if (canViewDebt &&
            widget.initialDebtFilter == null &&
            saved['debtFilter'] != null) {
          final debt = CustomerDebtFilter.values.firstWhere(
            (e) => e.name == saved['debtFilter']?.toString(),
            orElse: () => CustomerDebtFilter.all,
          );
          ref.read(customerDebtFilterProvider.notifier).state = debt;
        }
        if (saved.containsKey('timeRangeType')) {
          final rawType = saved['timeRangeType'];
          if (rawType == null) {
            ref.read(customerTimeRangeTypeProvider.notifier).state = null;
          } else {
            try {
              final timeRange =
                  OverviewTimeRange.values.byName(rawType.toString());
              ref.read(customerTimeRangeTypeProvider.notifier).state =
                  timeRange;
            } catch (_) {}
          }
        }
        if (saved['customStartDate'] != null &&
            saved['customEndDate'] != null) {
          final start =
              DateTime.tryParse(saved['customStartDate']?.toString() ?? '');
          final end =
              DateTime.tryParse(saved['customEndDate']?.toString() ?? '');
          if (start != null && end != null) {
            ref.read(customerCustomDateRangeProvider.notifier).state =
                DateTimeRange(start: start, end: end);
          }
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant CustomersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDebtFilter != null &&
        oldWidget.initialDebtFilter != widget.initialDebtFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final user = ref.read(authProvider);
        if (user?.canViewDebtSummary == true) {
          ref.read(customerDebtFilterProvider.notifier).state =
              widget.initialDebtFilter!;
          persistCustomerFilters(ref, debtFilter: widget.initialDebtFilter);
        }
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(processedCustomersProvider).whenData((listItems) {
        if (_currentLimit < listItems.length) {
          setState(() {
            _currentLimit += 50;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(authProvider);
    final canViewDebtSummary = user?.canViewDebtSummary ?? false;
    final canViewTotalSales = user?.canViewTotalSales ?? false;

    ref.listen<UserAccount?>(authProvider, (prev, next) {
      if (next != null &&
          (prev == null ||
              prev.username != next.username ||
              prev.canViewDebtSummary != next.canViewDebtSummary)) {
        if (!next.canViewDebtSummary) {
          ref.read(customerDebtFilterProvider.notifier).state =
              CustomerDebtFilter.all;
        }
        ref
            .read(filterStorageServiceProvider)
            .loadFilter('customers', next.username)
            .then((saved) {
          if (saved != null &&
              mounted &&
              ref.read(authProvider)?.username == next.username) {
            if (next.canViewDebtSummary && saved['debtFilter'] != null) {
              final debt = CustomerDebtFilter.values.firstWhere(
                (e) => e.name == saved['debtFilter']?.toString(),
                orElse: () => CustomerDebtFilter.all,
              );
              ref.read(customerDebtFilterProvider.notifier).state = debt;
            }
            if (saved.containsKey('timeRangeType')) {
              final rawType = saved['timeRangeType'];
              if (rawType == null) {
                ref.read(customerTimeRangeTypeProvider.notifier).state = null;
              } else {
                try {
                  final timeRange =
                      OverviewTimeRange.values.byName(rawType.toString());
                  ref.read(customerTimeRangeTypeProvider.notifier).state =
                      timeRange;
                } catch (_) {}
              }
            }
            if (saved['customStartDate'] != null &&
                saved['customEndDate'] != null) {
              final start =
                  DateTime.tryParse(saved['customStartDate']?.toString() ?? '');
              final end =
                  DateTime.tryParse(saved['customEndDate']?.toString() ?? '');
              if (start != null && end != null) {
                ref.read(customerCustomDateRangeProvider.notifier).state =
                    DateTimeRange(start: start, end: end);
              }
            }
          }
        });
      }
    });

    final processedAsync = ref.watch(processedCustomersProvider);
    final searchQuery = ref.watch(customerSearchQueryProvider);
    final customerTimeRangeType = ref.watch(customerTimeRangeTypeProvider);
    final customerActiveRange = ref.watch(customerActiveDateRangeProvider);
    final currentDebtFilter = ref.watch(customerDebtFilterProvider);
    final debtCounts = canViewDebtSummary
        ? ref.watch(customerDebtCountsProvider)
        : const <CustomerDebtFilter, int>{};

    final String dateLabel;
    if (customerTimeRangeType == null) {
      dateLabel = l10n.allTime;
    } else if (customerTimeRangeType == OverviewTimeRange.custom) {
      dateLabel =
          '${DateFormat('dd/MM').format(customerActiveRange!.start)} - ${DateFormat('dd/MM').format(customerActiveRange.end)}';
    } else {
      dateLabel = customerTimeRangeType.label;
    }

    int activeFilterCount = 0;
    if (canViewDebtSummary && currentDebtFilter != CustomerDebtFilter.all) {
      activeFilterCount++;
    }
    if (customerTimeRangeType != null) activeFilterCount++;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customers),
        actions: [
          if (kIsWeb && (user?.isAdmin == true))
            PopupMenuButton<String>(
              key: const Key('customers_excel_actions_menu'),
              icon: const Icon(Icons.more_vert),
              tooltip: l10n.excelActions,
              onSelected: (value) {
                if (value == 'import') {
                  _importCustomers();
                } else if (value == 'export') {
                  _exportCustomers();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'import',
                  child: Row(
                    children: [
                      const Icon(Icons.upload_file, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(l10n.importExcel),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'export',
                  child: Row(
                    children: [
                      const Icon(Icons.download, color: AppColors.success),
                      const SizedBox(width: 8),
                      Text(l10n.exportExcel),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchCustomersHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(customerSearchQueryProvider.notifier).state =
                              '';
                          setState(() {
                            _currentLimit = 50;
                          });
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
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (v) {
                ref.read(customerSearchQueryProvider.notifier).state = v;
                setState(() {
                  _currentLimit = 50;
                });
              },
            ),
          ),

          // Debt Filter Segment Bar
          if (canViewDebtSummary)
            _buildDebtFilterBar(currentDebtFilter, debtCounts),

          // Date Filter Bar
          Container(
            decoration: const BoxDecoration(
              color: AppColors.white,
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _showDateRangeFilterBottomSheet(context),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            l10n.createdTimeLabel(dateLabel),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
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
                if (customerTimeRangeType != null)
                  IconButton(
                    icon: const Icon(Icons.clear,
                        size: 16, color: AppColors.grey400),
                    onPressed: () {
                      ref.read(customerTimeRangeTypeProvider.notifier).state =
                          null;
                      persistCustomerFilters(ref, resetTimeRange: true);
                      setState(() {
                        _currentLimit = 50;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (activeFilterCount > 0) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    key: const Key('reset_customer_filters_button'),
                    onTap: () {
                      ref.read(customerDebtFilterProvider.notifier).state =
                          CustomerDebtFilter.all;
                      ref.read(customerTimeRangeTypeProvider.notifier).state =
                          null;
                      ref.read(customerCustomDateRangeProvider.notifier).state =
                          OverviewTimeRange.thisMonth.getRange();
                      final user = ref.read(authProvider);
                      ref
                          .read(filterStorageServiceProvider)
                          .clearFilter('customers', user?.username);
                      setState(() {
                        _currentLimit = 50;
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.refresh,
                              size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Đặt lại ($activeFilterCount)',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Customers list
          Expanded(
            child: processedAsync.when(
              data: (listItems) {
                final customersList = listItems.whereType<Customer>().toList();
                final displayItems = listItems.take(_currentLimit).toList();

                return Column(
                  children: [
                    _buildTotalSummaryCard(
                      customersList,
                      l10n,
                      canViewDebtSummary: canViewDebtSummary,
                      canViewTotalSales: canViewTotalSales,
                    ),
                    Expanded(
                      child: listItems.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                      searchQuery.isNotEmpty
                                          ? Icons.search_off
                                          : Icons.people_outline,
                                      size: 64,
                                      color: AppColors.grey400),
                                  const SizedBox(height: 16),
                                  Text(
                                    searchQuery.isNotEmpty
                                        ? l10n.notFound
                                        : l10n.noCustomersFound,
                                    style: const TextStyle(
                                        fontSize: 18, color: AppColors.grey400),
                                  ),
                                  if (searchQuery.isNotEmpty)
                                    Text(
                                      l10n.tryAdjustingSearch,
                                      style: const TextStyle(
                                          color: AppColors.grey400),
                                    ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () async {
                                await ref
                                    .read(customerListNotifierProvider.notifier)
                                    .refresh();
                              },
                              child: ListView.builder(
                                controller: _scrollController,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: displayItems.length,
                                itemBuilder: (context, index) {
                                  final item = displayItems[index];
                                  if (item is String) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                          top: 16, bottom: 8),
                                      child: Row(
                                        children: [
                                          Text(
                                            item,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textTertiary,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Expanded(
                                            child: Divider(
                                              color: AppColors.grey300,
                                              thickness: 1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  final customer = item as Customer;
                                  return CustomerListTile(customer: customer);
                                },
                              ),
                            ),
                    ),
                  ],
                );
              },
              loading: () => const LoadingIndicator(),
              error: (error, stack) => ErrorView(error),
            ),
          ),
        ],
      ),
      floatingActionButton: ScrollAwareFab(
        scrollController: _scrollController,
        child: FloatingActionButton(
          heroTag: 'addCustomerFab',
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddCustomerPage()),
            );
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Future<void> _importCustomers() async {
    final user = ref.read(authProvider);
    if (!kIsWeb || (user?.isAdmin != true)) return;

    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.filePickerError)),
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
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final importedCustomers = ExcelHelper.parseCustomers(fileBytes);
      final importResult =
          await ref.read(importCustomersUseCaseProvider).execute(
                customers: importedCustomers,
              );

      ref.invalidate(customerListNotifierProvider);

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(); // dismiss loading
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(importResult.toSummaryString()),
            backgroundColor:
                importResult.errors > 0 ? AppColors.warning : AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(); // dismiss loading
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.importError}: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _exportCustomers() async {
    final user = ref.read(authProvider);
    if (!kIsWeb || (user?.isAdmin != true)) return;

    final l10n = AppLocalizations.of(context)!;
    try {
      final customersAsync = ref.read(customerListNotifierProvider);
      final customers = customersAsync.maybeWhen(
        data: (list) => list,
        orElse: () => <Customer>[],
      );

      if (customers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.noDataToExport)),
          );
        }
        return;
      }

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final bytes = await ExcelHelper.exportCustomers(customers);

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(); // dismiss loading
        }
        await saveExcelFile(bytes, 'DanhSachKhachHang_Export.xlsx');
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(); // dismiss loading
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.importError}: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @visibleForTesting
  Future<void> testImportCustomers() => _importCustomers();

  @visibleForTesting
  Future<void> testExportCustomers() => _exportCustomers();

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
            final activeType = sheetRef.watch(customerTimeRangeTypeProvider);
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

                      // Thêm lựa chọn "Tất cả"
                      ListTile(
                        title: Text(
                          l10n.allTime,
                          style: TextStyle(
                            color: activeType == null
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontWeight: activeType == null
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: activeType == null
                            ? const Icon(Icons.check, color: AppColors.primary)
                            : null,
                        onTap: () {
                          Navigator.pop(consumerContext);
                          ref
                              .read(customerTimeRangeTypeProvider.notifier)
                              .state = null;
                          persistCustomerFilters(ref, resetTimeRange: true);
                          setState(() {
                            _currentLimit = 50;
                          });
                        },
                      ),

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
                                  ref.read(customerCustomDateRangeProvider);
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
                                    .read(customerCustomDateRangeProvider
                                        .notifier)
                                    .state = pickedRange;
                                ref
                                    .read(
                                        customerTimeRangeTypeProvider.notifier)
                                    .state = OverviewTimeRange.custom;
                                persistCustomerFilters(
                                  ref,
                                  timeRangeType: OverviewTimeRange.custom,
                                  customDateRange: pickedRange,
                                );
                                setState(() {
                                  _currentLimit = 50;
                                });
                              }
                            } else {
                              ref
                                  .read(customerTimeRangeTypeProvider.notifier)
                                  .state = type;
                              persistCustomerFilters(ref, timeRangeType: type);
                              setState(() {
                                _currentLimit = 50;
                              });
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

  Widget _buildTotalSummaryCard(
    List<Customer> customers,
    AppLocalizations l10n, {
    required bool canViewDebtSummary,
    required bool canViewTotalSales,
  }) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final count = customers.length;
    final totalSalesSum = canViewTotalSales
        ? customers.fold(0.0, (sum, c) => sum + c.displayTotalSales)
        : 0.0;
    final totalDebtSum = canViewDebtSummary
        ? customers.fold(
            0.0,
            (sum, c) =>
                sum + (c.displayCurrentDebt > 0 ? c.displayCurrentDebt : 0.0))
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceInfo,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.6)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (canViewTotalSales)
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          l10n.totalSales,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        flex: 2,
                        child: Text(
                          currencyFormat.format(totalSalesSum),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    const Icon(Icons.people_alt_outlined,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      l10n.customers,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.totalCustomers(count),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (canViewDebtSummary) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${l10n.customerDebt}:',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        flex: 2,
                        child: Text(
                          currencyFormat.format(totalDebtSum),
                          key: const Key('total_debt_summary_text'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.danger,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (totalDebtSum > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: AppColors.dangerLight,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.danger.withOpacity(0.3),
                        width: 0.5,
                      ),
                    ),
                    child: const Text(
                      'Cần thu',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDebtFilterBar(
    CustomerDebtFilter currentFilter,
    Map<CustomerDebtFilter, int> counts,
  ) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            _buildDebtFilterTab(
              filter: CustomerDebtFilter.all,
              label: 'Tất cả',
              count: counts[CustomerDebtFilter.all] ?? 0,
              isSelected: currentFilter == CustomerDebtFilter.all,
            ),
            _buildDebtFilterTab(
              filter: CustomerDebtFilter.inDebt,
              label: 'Còn nợ',
              count: counts[CustomerDebtFilter.inDebt] ?? 0,
              isSelected: currentFilter == CustomerDebtFilter.inDebt,
              activeColor: AppColors.danger,
              activeBgColor: AppColors.dangerLight,
            ),
            _buildDebtFilterTab(
              filter: CustomerDebtFilter.cleared,
              label: 'Hết nợ',
              count: counts[CustomerDebtFilter.cleared] ?? 0,
              isSelected: currentFilter == CustomerDebtFilter.cleared,
              activeColor: AppColors.success,
              activeBgColor: AppColors.successLight,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebtFilterTab({
    required CustomerDebtFilter filter,
    required String label,
    required int count,
    required bool isSelected,
    Color? activeColor,
    Color? activeBgColor,
  }) {
    final selectedTextColor = activeColor ?? AppColors.primary;
    final selectedBgColor = activeBgColor ?? AppColors.white;

    return Expanded(
      child: GestureDetector(
        key: Key('debt_filter_tab_${filter.name}'),
        onTap: () {
          ref.read(customerDebtFilterProvider.notifier).state = filter;
          persistCustomerFilters(ref, debtFilter: filter);
          setState(() {
            _currentLimit = 50;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? selectedBgColor : AppColors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.black.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? selectedTextColor
                        : AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? selectedTextColor.withOpacity(0.15)
                      : AppColors.grey200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? selectedTextColor
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
