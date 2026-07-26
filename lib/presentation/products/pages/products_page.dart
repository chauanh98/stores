import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/inventory/inventory_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../core/utils/excel_helper.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../common/widgets/error_view.dart';
import '../../common/widgets/scroll_aware_fab.dart';
import '../../inventories/pages/import_inventory_page.dart';
import '../widgets/product_tile.dart';
import 'add_product_page.dart';

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  final _searchController = TextEditingController();
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
      ref.read(processedProductsProvider).whenData((data) {
        if (_currentLimit < data.filteredProducts.length) {
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
    final processedAsync = ref.watch(processedProductsProvider);
    final search = ref.watch(productSearchQueryProvider);
    final selectedCategory = ref.watch(productCategoryFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.products),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Thao tác sản phẩm',
            onSelected: (value) {
              if (value == 'import_inventory') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ImportInventoryPage(),
                  ),
                );
              } else if (value == 'import_excel') {
                _importProducts(context);
              } else if (value == 'export_excel') {
                _exportProducts(context);
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'import_inventory',
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    Text(l10n.importProduct),
                  ],
                ),
              ),
              if (kIsWeb) ...[
                PopupMenuItem<String>(
                  value: 'import_excel',
                  child: Row(
                    children: [
                      const Icon(Icons.upload_file, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(l10n.importExcel),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'export_excel',
                  child: Row(
                    children: [
                      const Icon(Icons.download, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(l10n.exportExcel),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchProductsHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(productSearchQueryProvider.notifier).state =
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
                ref.read(productSearchQueryProvider.notifier).state = v;
                setState(() {
                  _currentLimit = 50;
                });
              },
            ),
          ),
          // KiotViet Filter Bar
          processedAsync.maybeWhen(
            data: (data) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    // Bộ lọc loại hàng
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedCategory,
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                        icon: const Icon(Icons.arrow_drop_down,
                            color: AppColors.primary, size: 18),
                        onChanged: (v) {
                          if (v != null) {
                            ref
                                .read(productCategoryFilterProvider.notifier)
                                .state = v;
                            setState(() {
                              _currentLimit = 50;
                            });
                          }
                        },
                        items: data.categories
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                      c == 'All' ? 'Tất cả loại hàng' : c,
                                      style: const TextStyle(
                                          fontSize: 13, color: Colors.black87)),
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Bảng giá đang chọn
                    Row(
                      children: const [
                        Text(
                          'Giá bán',
                          style: TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                        Icon(Icons.arrow_drop_down,
                            color: Colors.black45, size: 18),
                      ],
                    ),
                  ],
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: processedAsync.when(
              data: (data) {
                final displayProducts =
                    data.filteredProducts.take(_currentLimit).toList();
                return Column(
                  children: [
                    _buildTotalSummaryCard(
                        data.filteredProducts.length, data.totalStock, l10n),
                    Expanded(
                      child: data.filteredProducts.isEmpty
                          ? Center(child: Text(l10n.notFound))
                          : RefreshIndicator(
                              onRefresh: _refreshProducts,
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                itemCount: displayProducts.length,
                                itemBuilder: (_, i) =>
                                    ProductTile(product: displayProducts[i]),
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
          heroTag: 'addProductFab',
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          onPressed: _navigateToAddProduct,
          child: const Icon(Icons.add),
        ),
      ),
    );
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

  Future<void> _importProducts(BuildContext context) async {
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

      final importedProducts = ExcelHelper.parseProducts(bytes);
      final productRepo = ref.read(productRepositoryProvider);
      final inventoryRepo = ref.read(inventoryRepositoryProvider);
      final now = DateTime.now();

      int addedCount = 0;
      int updatedCount = 0;

      for (final product in importedProducts) {
        final existing = await productRepo.fetchById(product.id);
        if (existing != null) {
          final oldStock = existing.branchStocks['branch_1'] ?? 0;
          final newStock = product.branchStocks['branch_1'] ?? 0;
          final diff = newStock - oldStock;

          final updatedBranchStocks =
              Map<String, int>.from(existing.branchStocks);
          updatedBranchStocks['branch_1'] = newStock;

          final merged = product.copyWith(
            brand: existing.brand ?? product.brand,
            model: existing.model ?? product.model,
            branchStocks: updatedBranchStocks,
          );
          await productRepo.upsert(merged);

          if (diff > 0) {
            await inventoryRepo.record(InventoryTransaction(
              id: 'import_adj_${now.millisecondsSinceEpoch}_${product.id}',
              productId: product.id,
              type: TransactionType.import,
              quantity: diff,
              date: now,
              note: 'Điều chỉnh tăng kho từ Excel',
              importPrice: product.costPrice,
            ));
          } else if (diff < 0) {
            await inventoryRepo.record(InventoryTransaction(
              id: 'export_adj_${now.millisecondsSinceEpoch}_${product.id}',
              productId: product.id,
              type: TransactionType.export,
              quantity: -diff,
              date: now,
              note: 'Điều chỉnh giảm kho từ Excel',
            ));
          }

          updatedCount++;
        } else {
          await productRepo.upsert(product);

          final stock = product.branchStocks['branch_1'] ?? 0;
          if (stock > 0) {
            await inventoryRepo.record(InventoryTransaction(
              id: 'import_init_${now.millisecondsSinceEpoch}_${product.id}',
              productId: product.id,
              type: TransactionType.import,
              quantity: stock,
              date: now,
              note: 'Nhập kho khởi tạo từ Excel',
              importPrice: product.costPrice,
            ));
          }
          addedCount++;
        }
      }

      ref.invalidate(productListProvider);

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

  Future<void> _exportProducts(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final productsAsync = ref.read(productListProvider);
      final products = productsAsync.maybeWhen(
        data: (list) => list,
        orElse: () => <Product>[],
      );

      if (products.isEmpty) {
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

      final file = await ExcelHelper.exportProducts(products);

      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading

        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Danh sách sản phẩm',
        );
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(); // dismiss loading
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi xuất file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildTotalSummaryCard(
      int count, int totalStock, AppLocalizations l10n) {
    return Container(
      color: AppColors.surfaceInfo,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l10n.totalProducts(count),
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87),
          ),
          Text(
            l10n.totalStockCount(totalStock),
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.primary),
          )
        ],
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
