import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/excel_helper.dart';
import '../../../domain/entities/customer.dart';
import '../../common/widgets/error_view.dart';
import '../../common/widgets/loading_indicator.dart';
import '../../common/widgets/scroll_aware_fab.dart';
import '../widgets/customer_list_tile.dart';
import 'add_customer_page.dart';

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _currentLimit = 50;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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
    final processedAsync = ref.watch(processedCustomersProvider);
    final searchQuery = ref.watch(customerSearchQueryProvider);
    final customerTimeRangeType = ref.watch(customerTimeRangeTypeProvider);
    final customerActiveRange = ref.watch(customerActiveDateRangeProvider);

    final String dateLabel;
    if (customerTimeRangeType == null) {
      dateLabel = l10n.allTime;
    } else if (customerTimeRangeType == OverviewTimeRange.custom) {
      dateLabel =
          '${DateFormat('dd/MM').format(customerActiveRange!.start)} - ${DateFormat('dd/MM').format(customerActiveRange.end)}';
    } else {
      dateLabel = customerTimeRangeType.label;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customers),
        actions: [
          if (kIsWeb)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: l10n.excelActions,
              onSelected: (value) {
                if (value == 'import') {
                  _importCustomers(context);
                } else if (value == 'export') {
                  _exportCustomers(context);
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
                      const Icon(Icons.download, color: Colors.green),
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
              onChanged: (v) {
                ref.read(customerSearchQueryProvider.notifier).state = v;
                setState(() {
                  _currentLimit = 50;
                });
              },
            ),
          ),

          // Date Filter Bar
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
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
                        Text(
                          l10n.createdTimeLabel(dateLabel),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
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
                    icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                    onPressed: () {
                      ref.read(customerTimeRangeTypeProvider.notifier).state =
                          null;
                      setState(() {
                        _currentLimit = 50;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
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
                    _buildTotalSummaryCard(customersList, l10n),
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
                                      color: Colors.grey),
                                  const SizedBox(height: 16),
                                  Text(
                                    searchQuery.isNotEmpty
                                        ? l10n.notFound
                                        : l10n.noCustomersFound,
                                    style: const TextStyle(
                                        fontSize: 18, color: Colors.grey),
                                  ),
                                  if (searchQuery.isNotEmpty)
                                    Text(
                                      l10n.tryAdjustingSearch,
                                      style:
                                          const TextStyle(color: Colors.grey),
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
                                          Expanded(
                                            child: Divider(
                                              color: Colors.grey.shade300,
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
          foregroundColor: Colors.white,
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

  Future<void> _importCustomers(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.filePickerError)),
          );
        }
        return;
      }

      final file = result.files.first;
      List<int> bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      } else {
        throw Exception('Cannot read file bytes');
      }

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final importedCustomers = ExcelHelper.parseCustomers(bytes);
      final repo = ref.read(customerRepositoryProvider);

      int addedCount = 0;
      int updatedCount = 0;

      for (final customer in importedCustomers) {
        final existing = await repo.fetchById(customer.id);
        if (existing != null) {
          final merged = customer.copyWith(
            purchases: existing.purchases,
          );
          await repo.upsert(merged);
          updatedCount++;
        } else {
          await repo.upsert(customer);
          addedCount++;
        }
      }

      ref.invalidate(customerListNotifierProvider);

      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${l10n.importSuccess} (Thêm: $addedCount, Sửa: $updatedCount)'),
            backgroundColor: Colors.green,
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
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportCustomers(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final customersAsync = ref.read(customerListNotifierProvider);
      final customers = customersAsync.maybeWhen(
        data: (list) => list,
        orElse: () => <Customer>[],
      );

      if (customers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.noDataToExport)),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final file = await ExcelHelper.exportCustomers(customers);

      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading

        await Share.shareXFiles(
          [XFile(file.path)],
          subject: l10n.customers,
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
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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
                                : Colors.black87,
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
                                setState(() {
                                  _currentLimit = 50;
                                });
                              }
                            } else {
                              ref
                                  .read(customerTimeRangeTypeProvider.notifier)
                                  .state = type;
                              setState(() {
                                _currentLimit = 50;
                              });
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

  Widget _buildTotalSummaryCard(
      List<Customer> customers, AppLocalizations l10n) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final count = customers.length;
    final totalSalesSum =
        customers.fold(0.0, (sum, c) => sum + c.displayTotalSales);

    return Container(
      color: AppColors.surfaceInfo,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                l10n.totalSales,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black87),
              ),
              const SizedBox(width: 8),
              Text(
                currencyFormat.format(totalSalesSum),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          Text(
            l10n.totalCustomers(count),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
