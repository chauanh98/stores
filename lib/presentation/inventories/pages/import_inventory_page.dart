import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/inventory/inventory_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../common/widgets/error_view.dart';

class ImportInventoryPage extends ConsumerStatefulWidget {
  const ImportInventoryPage({super.key});

  @override
  ConsumerState<ImportInventoryPage> createState() =>
      _ImportInventoryPageState();
}

class _ImportInventoryPageState extends ConsumerState<ImportInventoryPage> {
  final List<_ImportItem> _items = [_ImportItem()];
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.import),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saving ? null : () => _save(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Header info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.inventory_2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.importProduct,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.importDescription,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Items
            productsAsync.when(
              data: (products) => Column(
                children: [
                  ..._items.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    final product = products.firstWhere(
                      (p) => p.id == item.productId,
                      orElse: () => products.isNotEmpty
                          ? products.first
                          : null as Product,
                    );

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Sản phẩm với Autocomplete
                            _ProductAutocomplete(
                              products: products,
                              selectedProductId: item.productId,
                              onProductSelected: (productId) => setState(() {
                                item.productId = productId;
                              }),
                            ),

                            const SizedBox(height: 12),

                            // Số lượng và giá nhập
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: item.quantity.toString(),
                                    decoration: InputDecoration(
                                      labelText: l10n.quantity,
                                      border: const OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) => setState(() {
                                      item.quantity = int.tryParse(v) ?? 1;
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: item.importPrice.toString(),
                                    decoration: InputDecoration(
                                      labelText: l10n.importPrice,
                                      border: const OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) => setState(() {
                                      item.importPrice =
                                          double.tryParse(v) ?? 0.0;
                                    }),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Thông tin hiển thị
                            if (product != null) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildInfoField(
                                      l10n.currentStock,
                                      '${product.stock}',
                                      Icons.inventory,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildInfoField(
                                      l10n.stockAfterImport,
                                      '${product.stock + item.quantity}',
                                      Icons.add_circle,
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            if (_items.length > 1)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _items.removeAt(idx)),
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  label: Text(l10n.delete,
                                      style:
                                          const TextStyle(color: Colors.red)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _items.add(_ImportItem())),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.addProduct),
                  ),
                ],
              ),
              loading: () =>
                  const SizedBox(height: 120, child: LoadingIndicator()),
              error: (e, _) => ErrorView(e),
            ),

            const SizedBox(height: 12),

            // Summary
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.importSummary,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.numberOfProducts),
                        Text('${_items.length}'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.totalQuantity),
                        Text(
                            '${_items.fold(0, (sum, item) => sum + item.quantity)}'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.totalValue),
                        Text(
                          NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                              .format(_items.fold(
                                  0.0,
                                  (sum, item) =>
                                      sum +
                                      (item.importPrice * item.quantity))),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoField(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon,
              size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;

    // Validate
    for (final item in _items) {
      if (item.productId == null ||
          item.quantity <= 0 ||
          item.importPrice <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.checkProductsAndQuantity)),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final products = ref
          .read(productListProvider)
          .maybeWhen(data: (v) => v, orElse: () => <Product>[]);
      final productRepo = ref.read(productRepositoryProvider);
      final inventoryRepo = ref.read(inventoryRepositoryProvider);

      for (final item in _items) {
        final product = products.firstWhere((p) => p.id == item.productId);

        // 1) Cập nhật stock chi nhánh và tính toán lại giá vốn (Weighted Average)
        final branchStocks = Map<String, int>.from(product.branchStocks);
        final currentBranchStock = branchStocks['branch_1'] ?? 0;
        branchStocks['branch_1'] = currentBranchStock + item.quantity;

        final currentTotalStock = product.stock;
        final double newCostPrice = (currentTotalStock + item.quantity) > 0
            ? ((currentTotalStock * product.costPrice) +
                    (item.quantity * item.importPrice)) /
                (currentTotalStock + item.quantity)
            : item.importPrice;

        final updatedProduct = product.copyWith(
          branchStocks: branchStocks,
          costPrice: newCostPrice,
        );
        await productRepo.upsert(updatedProduct);

        // 2) Ghi inventory transaction
        await inventoryRepo.record(InventoryTransaction(
          id: 'import_${now.millisecondsSinceEpoch}_${item.productId}',
          productId: item.productId!,
          type: TransactionType.import,
          quantity: item.quantity,
          date: now,
          note: 'Import - ${product.name}',
          importPrice: item.importPrice,
        ));
      }

      // Refresh providers
      ref.invalidate(productListProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.updated),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// Widget Autocomplete cho sản phẩm (tương tự như CreateOrderPage)
class _ProductAutocomplete extends StatefulWidget {
  final List<Product> products;
  final String? selectedProductId;
  final Function(String?) onProductSelected;

  const _ProductAutocomplete({
    required this.products,
    required this.selectedProductId,
    required this.onProductSelected,
  });

  @override
  State<_ProductAutocomplete> createState() => _ProductAutocompleteState();
}

class _ProductAutocompleteState extends State<_ProductAutocomplete> {
  late TextEditingController _controller;
  String _lastSelectedText = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _updateDisplayText();
  }

  @override
  void didUpdateWidget(_ProductAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedProductId != widget.selectedProductId) {
      _updateDisplayText();
    }
  }

  void _updateDisplayText() {
    if (widget.selectedProductId != null) {
      final product = widget.products.firstWhere(
        (p) => p.id == widget.selectedProductId,
        orElse: () => const Product(
            id: '',
            name: '',
            code: '',
            brand: '',
            model: '',
            price: 0,
            costPrice: 0,
            branchStocks: {},
            category: ''),
      );
      _lastSelectedText =
          '${product.name} • ${product.brand ?? ''} • ${product.model ?? ''}';
      _controller.text = _lastSelectedText;
    } else {
      _lastSelectedText = '';
      _controller.text = '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Autocomplete<Product>(
      displayStringForOption: (product) =>
          '${product.name} • ${product.brand ?? ''} • ${product.model ?? ''}',
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return widget.products;
        }
        return widget.products.where((product) {
          final query = textEditingValue.text.toLowerCase();
          return product.name.toLowerCase().contains(query) ||
              (product.brand ?? '').toLowerCase().contains(query) ||
              (product.model ?? '').toLowerCase().contains(query);
        }).toList();
      },
      onSelected: (product) {
        widget.onProductSelected(product.id);
        _lastSelectedText =
            '${product.name} • ${product.brand ?? ''} • ${product.model ?? ''}';
        _controller.text = _lastSelectedText;
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: l10n.searchProducts,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.search),
            hintText: l10n.searchProductsHint,
          ),
          onChanged: (value) {
            if (value != _lastSelectedText && value.isNotEmpty) {
              widget.onProductSelected(null);
            }
          },
        );
      },
    );
  }
}

class _ImportItem {
  String? productId;
  int quantity = 1;
  double importPrice = 0.0;
}
