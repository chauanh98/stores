import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/products/products_providers.dart';
import '../../../core/utils/sample_data_seeder.dart';
import '../../../domain/entities/product.dart';
import '../../common/widgets/error_view.dart';
import '../../inventories/pages/import_inventory_page.dart';
import '../widgets/product_tile.dart';
import 'add_product_page.dart';

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  String _selectedCategory = 'All';
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final productsAsync = ref.watch(productListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.products),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // IconButton(
          //   tooltip: 'Seed Products',
          //   icon: const Icon(Icons.dataset),
          //   onPressed: _seedProducts,
          // ),
          IconButton(
            tooltip: l10n.import,
            icon: const Icon(Icons.inventory_2),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ImportInventoryPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SearchBar(
                    controller: _searchController,
                    hintText: l10n.searchProductsHint,
                    leading: const Icon(Icons.search),
                    onChanged: (v) => setState(() => _search = v),
                    trailing: _search.isNotEmpty
                        ? [
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _search = '');
                              },
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                _CategoryFilter(
                  selected: _selectedCategory,
                  onChanged: (v) => setState(() => _selectedCategory = v),
                  productsAsync: productsAsync,
                ),
              ],
            ),
          ),
          Expanded(
            child: productsAsync.when(
              data: (products) {
                final categories = _buildCategories(products);
                final filtered = _applyFilters(products, categories);
                if (filtered.isEmpty) {
                  return Center(child: Text(l10n.notFound));
                }
                return RefreshIndicator(
                  onRefresh: _refreshProducts,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => ProductTile(product: filtered[i]),
                  ),
                );
              },
              loading: () => const LoadingIndicator(),
              error: (error, stack) => ErrorView(error),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'addProductFab',
        onPressed: _navigateToAddProduct,
        child: const Icon(Icons.add),
      ),
    );
  }

  Set<String> _buildCategories(List<Product> products) {
    final cats = products.map((e) => e.category).toSet();
    return {'All', ...cats};
  }

  List<Product> _applyFilters(List<Product> products, Set<String> categories) {
    final byCategory = _selectedCategory == 'All'
        ? products
        : products.where((p) => p.category == _selectedCategory).toList();

    final q = _search.trim().toLowerCase();

    if (q.isEmpty) return byCategory;

    return byCategory.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.model.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _refreshProducts() async {
    try {
      ref.invalidate(productListProvider);

      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {}
  }

  void _navigateToAddProduct() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AddProductPage(),
      ),
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final AsyncValue<List<Product>> productsAsync;

  const _CategoryFilter({
    required this.selected,
    required this.onChanged,
    required this.productsAsync,
  });

  @override
  Widget build(BuildContext context) {
    return productsAsync.when(
      data: (products) {
        final cats = {'All', ...products.map((e) => e.category).toSet()};
        return DropdownButton<String>(
          value: selected,
          onChanged: (v) => v == null ? null : onChanged(v),
          items: cats
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
        );
      },
      loading: () => const SizedBox(
        width: 48,
        height: 48,
        child: LoadingIndicator(),
      ),
      error: (e, _) => ErrorView(e),
    );
  }
}
