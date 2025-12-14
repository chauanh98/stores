import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/products/products_providers.dart';
import '../../../application/inventory/inventory_providers.dart';
import '../../../core/constants/product_categories.dart';
import '../../../domain/entities/product.dart';

class ProductDetailPage extends ConsumerStatefulWidget {
  final Product product;

  const ProductDetailPage({
    super.key,
    required this.product,
  });

  @override
  ConsumerState<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends ConsumerState<ProductDetailPage> {
  bool _isEditing = false;
  bool _isLoading = false;
  late Product _currentProduct;
  int _txFilterIndex = 0; // 0: All, 1: Imports, 2: Exports

  late TextEditingController _nameController;
  late TextEditingController _brandController;
  late TextEditingController _modelController;
  late TextEditingController _priceController;
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    _currentProduct = widget.product;
    _initializeControllers();
  }

  void _initializeControllers() {
    _nameController = TextEditingController(text: _currentProduct.name);
    _brandController = TextEditingController(text: _currentProduct.brand);
    _modelController = TextEditingController(text: _currentProduct.model);
    _priceController =
        TextEditingController(text: _currentProduct.price.toStringAsFixed(0));
    _selectedCategory = _currentProduct.category;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l10n.editProduct : l10n.productDetail),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (!_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: l10n.edit,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _showDeleteDialog,
              tooltip: l10n.delete,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isLoading ? null : _saveProduct,
              tooltip: l10n.save,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _isLoading ? null : _cancelEdit,
              tooltip: l10n.cancel,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(
                            ProductCategories.getCategoryIcon(
                                _currentProduct.category),
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentProduct.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_currentProduct.brand} • ${_currentProduct.model}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(context, l10n.category,
                        _currentProduct.category, Icons.category),
                    _buildInfoRow(
                        context,
                        l10n.price,
                        _formatPrice(_currentProduct.price),
                        Icons.attach_money),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Edit Form (when editing)
            if (_isEditing) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildEditField(_nameController, l10n.name, Icons.label),
                      const SizedBox(height: 16),
                      _buildEditField(
                          _brandController, l10n.brand, Icons.business),
                      const SizedBox(height: 16),
                      _buildEditField(
                          _modelController, l10n.model, Icons.model_training),
                      const SizedBox(height: 16),
                      _buildEditField(
                          _priceController, l10n.price, Icons.attach_money,
                          isNumber: true),
                      const SizedBox(height: 16),
                      _buildCategoryDropdown(l10n),
                    ],
                  ),
                ),
              ),
            ],

            // Transactions section
            const SizedBox(height: 16),
            _buildTransactionsSection(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
      BuildContext context, String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditField(
      TextEditingController controller, String label, IconData icon,
      {bool isNumber = false}) {
    final l10n = AppLocalizations.of(context)!;

    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '${l10n.pleaseEnter} $label';
        }
        if (isNumber) {
          final number = isNumber ? double.tryParse(value) : null;
          if (number == null) {
            return l10n.pleaseEnterValidNumber;
          }
        }
        return null;
      },
    );
  }

  Widget _buildCategoryDropdown(AppLocalizations l10n) {
    return DropdownButtonFormField<String>(
      value: _selectedCategory,
      decoration: InputDecoration(
        labelText: l10n.category,
        prefixIcon: const Icon(Icons.category),
        border: const OutlineInputBorder(),
      ),
      items: ProductCategories.categories.map((category) {
        return DropdownMenuItem(
          value: category,
          child: Row(
            children: [
              Icon(ProductCategories.getCategoryIcon(category)),
              const SizedBox(width: 8),
              Text(category),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() => _selectedCategory = value);
        }
      },
    );
  }

  String _formatPrice(double price) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(price);
  }

  Widget _buildTransactionsSection(AppLocalizations l10n) {
    return Consumer(
      builder: (context, ref, child) {
        final txAsync =
            ref.watch(transactionsByProductProvider(_currentProduct.id));
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(l10n.inventoryTransactions,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    SegmentedButton<int>(
                      segments: [
                        ButtonSegment(
                            value: 0,
                            label: Text(l10n.all,
                                overflow: TextOverflow.ellipsis, maxLines: 1)),
                        ButtonSegment(
                            value: 1,
                            label: Text(l10n.import,
                                overflow: TextOverflow.ellipsis, maxLines: 1)),
                        ButtonSegment(
                            value: 2,
                            label: Text(l10n.export,
                                overflow: TextOverflow.ellipsis, maxLines: 1)),
                      ],
                      selected: {_txFilterIndex},
                      onSelectionChanged: (set) {
                        setState(() => _txFilterIndex = set.first);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                txAsync.when(
                  data: (txs) {
                    final filtered = txs.where((t) {
                      if (_txFilterIndex == 1) return t.type.name == 'import';
                      if (_txFilterIndex == 2) return t.type.name == 'export';
                      return true;
                    }).toList()
                      ..sort((a, b) => b.date.compareTo(a.date));

                    if (filtered.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(l10n.notFound),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final tx = filtered[index];
                        final isImport = tx.type.name == 'import';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: isImport
                                ? Colors.green.withOpacity(0.1)
                                : Colors.red.withOpacity(0.1),
                            child: Icon(
                              isImport ? Icons.call_received : Icons.call_made,
                              color: isImport ? Colors.green : Colors.red,
                            ),
                          ),
                          title: Text(
                            '${DateFormat('dd/MM/yyyy').format(tx.date)} • ${tx.quantity}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (tx.importPrice != null)
                                Text(
                                    '${l10n.importPrice}: ${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(tx.importPrice)}'),
                              if (tx.note.isNotEmpty) Text(tx.note),
                            ],
                          ),
                          trailing: Text(isImport ? l10n.import : l10n.export,
                              style: TextStyle(
                                  color: isImport ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.w600)),
                        );
                      },
                    );
                  },
                  loading: () => const LoadingIndicator(),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error: $e'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveProduct() async {
    final l10n = AppLocalizations.of(context)!;

    // Validate form
    if (_nameController.text.trim().isEmpty ||
        _brandController.text.trim().isEmpty ||
        _modelController.text.trim().isEmpty ||
        _priceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseFillAllField)),
      );
      return;
    }

    final price = double.tryParse(_priceController.text.trim());

    if (price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseEnterValidNumber)),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedProduct = Product(
        id: _currentProduct.id,
        name: _nameController.text.trim(),
        brand: _brandController.text.trim(),
        model: _modelController.text.trim(),
        price: price,
        stock: _currentProduct.stock,
        category: _selectedCategory,
      );

      await ref.read(productRepositoryProvider).upsert(updatedProduct);

      if (mounted) {
        setState(() {
          _currentProduct = updatedProduct;
          _isEditing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.updated)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _cancelEdit() {
    _initializeControllers();
    setState(() => _isEditing = false);
  }

  void _showDeleteDialog() {
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete),
        content: Text('${l10n.wantToDelete} "${_currentProduct.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _deleteProduct();
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteProduct() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isLoading = true);

    try {
      await ref.read(productRepositoryProvider).delete(_currentProduct.id);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.updated)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
