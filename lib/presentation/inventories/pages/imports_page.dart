import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/inventory/inventory_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/product.dart';
import '../../common/widgets/error_view.dart';
import '../../common/widgets/loading_indicator.dart';
import 'import_detail_page.dart';

class ImportsPage extends ConsumerWidget {
  const ImportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final filterMode = ref.watch(importFilterModeProvider);
    final selectedDate = ref.watch(selectedImportDateProvider);
    final selectedRange = ref.watch(selectedImportRangeProvider);
    final importsAsync = ref.watch(importsFilteredProvider);
    final productsAsync = ref.watch(productListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.import),

        actions: [
          IconButton(
            icon: Icon(filterMode == ImportFilterMode.range
                ? Icons.calendar_today
                : Icons.date_range),
            onPressed: () async {
              if (filterMode == ImportFilterMode.range) {
                ref.read(importFilterModeProvider.notifier).state = ImportFilterMode.day;
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  ref.read(selectedImportDateProvider.notifier).state = picked;
                }
              } else {
                ref.read(importFilterModeProvider.notifier).state = ImportFilterMode.range;
                final initialRange = DateTimeRange(start: selectedRange.start, end: selectedRange.end);
                final pickedRange = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  initialDateRange: initialRange,
                );
                if (pickedRange != null) {
                  final start = DateTime(pickedRange.start.year, pickedRange.start.month, pickedRange.start.day, 0, 0, 0);
                  final end = DateTime(pickedRange.end.year, pickedRange.end.month, pickedRange.end.day, 23, 59, 59, 999);
                  ref.read(selectedImportRangeProvider.notifier).state = TupleDateRange(start, end);
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Date selector card (like revenue page)
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    filterMode == ImportFilterMode.range
                        ? l10n.selectDateRange
                        : l10n.selectDate,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            if (filterMode == ImportFilterMode.range) {
                              final initialRange = DateTimeRange(start: selectedRange.start, end: selectedRange.end);
                              final pickedRange = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                                initialDateRange: initialRange,
                              );
                              if (pickedRange != null) {
                                final start = DateTime(pickedRange.start.year, pickedRange.start.month, pickedRange.start.day, 0, 0, 0);
                                final end = DateTime(pickedRange.end.year, pickedRange.end.month, pickedRange.end.day, 23, 59, 59, 999);
                                ref.read(selectedImportRangeProvider.notifier).state = TupleDateRange(start, end);
                              }
                            } else {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                ref.read(selectedImportDateProvider.notifier).state = picked;
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(context).colorScheme.outline),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  filterMode == ImportFilterMode.range
                                      ? Icons.date_range
                                      : Icons.calendar_today,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  filterMode == ImportFilterMode.range
                                      ? '${DateFormat('dd/MM/yyyy').format(selectedRange.start)} - ${DateFormat('dd/MM/yyyy').format(selectedRange.end)}'
                                      : DateFormat('dd/MM/yyyy').format(selectedDate),
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Data list
          Expanded(
            child: importsAsync.when(
        data: (imports) {
          if (imports.isEmpty) {
            return Center(child: Text(l10n.notFound));
          }

          return productsAsync.when(
            data: (products) {
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: imports.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final tx = imports[index];
                  final product = _findProduct(products, tx.productId);
                  return _ImportListTile(tx: tx, product: product);
                },
              );
            },
            loading: () => const LoadingIndicator(),
            error: (e, _) => ErrorView(e),
          );
        },
        loading: () => const LoadingIndicator(),
        error: (e, _) => ErrorView(e),
            ),
          ),
        ],
      ),
    );
  }

  Product _findProduct(List<Product> products, String id) {
    return products.firstWhere(
      (p) => p.id == id,
      orElse: () => const Product(
        id: '',
        name: 'Unknown',
        code: '',
        brand: '',
        model: '',
        price: 0,
        costPrice: 0,
        branchStocks: {},
        category: 'Other',
      ),
    );
  }
}

class _ImportListTile extends StatelessWidget {
  const _ImportListTile({required this.tx, required this.product});
  final InventoryTransaction tx;
  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      tileColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(Icons.call_received, color: theme.colorScheme.onPrimaryContainer),
      ),
      title: Text(product.name.isEmpty ? '#${tx.id.substring(0, 6)}' : product.name,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text('${_fmt(tx.date)} • ${tx.quantity}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ImportDetailPage(tx: tx, product: product)),
        );
      },
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}


