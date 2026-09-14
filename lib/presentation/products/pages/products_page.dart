import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/inventory/inventory_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../core/utils/excel_helper.dart';
import '../../../core/utils/sample_image_helper.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../common/widgets/error_view.dart';
import '../../common/widgets/scroll_aware_fab.dart';
import '../../inventories/pages/import_inventory_page.dart';
import '../widgets/product_tile.dart';
import 'add_product_page.dart';

class ProductsPage extends ConsumerStatefulWidget {
  final String? initialCategory;

  const ProductsPage({
    super.key,
    this.initialCategory,
  });

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
    if (widget.initialCategory != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(productCategoryFilterProvider.notifier).state =
            widget.initialCategory!;
      });
    }
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
    final selectedBrand = ref.watch(productBrandFilterProvider);
    final stockStatus = ref.watch(productStockStatusFilterProvider);
    final sortOption = ref.watch(productSortOptionProvider);

    final user = ref.watch(authProvider);
    final canManageProducts = user?.canManageProducts ?? false;
    final isSupervisor = user?.isSupervisor == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.products),
        actions: [
          if (canManageProducts)
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
                  _importProducts();
                } else if (value == 'export_excel') {
                  _exportProducts();
                } else if (value == 'auto_assign_images') {
                  _autoAssignSampleImages();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'import_inventory',
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined,
                          color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      Text(l10n.importProduct),
                    ],
                  ),
                ),
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
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'auto_assign_images',
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.amber),
                      SizedBox(width: 8),
                      Text('Tự động gán ảnh mẫu',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
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

          // 2. Compact Filter Bar (Stock Status, Category, Brand, Sort & Reset)
          processedAsync.maybeWhen(
            data: (data) => _buildCompactFilterBar(
              stockStatus: stockStatus,
              categories: data.categories,
              brands: data.brands,
              selectedCategory: selectedCategory,
              selectedBrand: selectedBrand,
              sortOption: sortOption,
            ),
            orElse: () => const SizedBox.shrink(),
          ),

          // 4. Products List & Summary Card
          Expanded(
            child: processedAsync.when(
              data: (data) {
                final displayProducts =
                    data.filteredProducts.take(_currentLimit).toList();
                return Column(
                  children: [
                    _buildTotalSummaryCard(
                      count: data.totalProducts,
                      totalStock: data.totalStock,
                      totalCostValue: data.totalCostValue,
                      isSupervisor: isSupervisor,
                      l10n: l10n,
                    ),
                    Expanded(
                      child: data.filteredProducts.isEmpty
                          ? Center(child: Text(l10n.notFound))
                          : RefreshIndicator(
                              onRefresh: _refreshProducts,
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
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
      floatingActionButton: canManageProducts
          ? ScrollAwareFab(
              scrollController: _scrollController,
              child: FloatingActionButton(
                heroTag: 'addProductFab',
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                onPressed: _navigateToAddProduct,
                child: const Icon(Icons.add),
              ),
            )
          : null,
    );
  }

  Widget _buildCompactFilterBar({
    required StockStatus stockStatus,
    required List<String> categories,
    required List<String> brands,
    required String selectedCategory,
    required String? selectedBrand,
    required ProductSortOption sortOption,
  }) {
    final isStockFiltered = stockStatus != StockStatus.all;
    final isCategoryFiltered = selectedCategory != 'All';
    final isBrandFiltered = selectedBrand != null;
    final isSortFiltered = sortOption != ProductSortOption.stockDesc;
    final hasActiveFilters = isStockFiltered ||
        isCategoryFiltered ||
        isBrandFiltered ||
        isSortFiltered;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.dividerLight),
          bottom: BorderSide(color: AppColors.divider),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 1. Tồn kho (Stock Status)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isStockFiltered
                    ? AppColors.primary.withOpacity(0.08)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      isStockFiltered ? AppColors.primary : AppColors.border,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<StockStatus>(
                  value: stockStatus,
                  isDense: true,
                  style: TextStyle(
                    color:
                        isStockFiltered ? AppColors.primary : Colors.black87,
                    fontWeight: isStockFiltered
                        ? FontWeight.bold
                        : FontWeight.w600,
                    fontSize: 12,
                  ),
                  icon: Icon(
                    Icons.arrow_drop_down,
                    color: isStockFiltered
                        ? AppColors.primary
                        : AppColors.primary,
                    size: 18,
                  ),
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(productStockStatusFilterProvider.notifier)
                          .state = v;
                      setState(() {
                        _currentLimit = 50;
                      });
                    }
                  },
                  items: const [
                    DropdownMenuItem(
                      value: StockStatus.all,
                      child: Text(
                        'Tất cả',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                    DropdownMenuItem(
                      value: StockStatus.inStock,
                      child: Text(
                        'Còn hàng (> 0)',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                    DropdownMenuItem(
                      value: StockStatus.outOfStock,
                      child: Text(
                        'Hết hàng (= 0)',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                    DropdownMenuItem(
                      value: StockStatus.belowMinStock,
                      child: Text(
                        'Dưới định mức',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 2. Danh mục (Category)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isCategoryFiltered
                    ? AppColors.primary.withOpacity(0.08)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isCategoryFiltered
                      ? AppColors.primary
                      : AppColors.border,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: categories.contains(selectedCategory)
                      ? selectedCategory
                      : 'All',
                  isDense: true,
                  style: TextStyle(
                    color: isCategoryFiltered
                        ? AppColors.primary
                        : AppColors.primary,
                    fontWeight: isCategoryFiltered
                        ? FontWeight.bold
                        : FontWeight.w600,
                    fontSize: 12,
                  ),
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
                  items: categories
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c == 'All' ? 'Tất cả nhóm hàng' : c,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 3. Thương hiệu (Brand)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isBrandFiltered
                    ? AppColors.primary.withOpacity(0.08)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isBrandFiltered
                      ? AppColors.primary
                      : AppColors.border,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: (selectedBrand != null &&
                          brands.contains(selectedBrand))
                      ? selectedBrand
                      : null,
                  isDense: true,
                  style: TextStyle(
                    color: isBrandFiltered
                        ? AppColors.primary
                        : AppColors.primary,
                    fontWeight: isBrandFiltered
                        ? FontWeight.bold
                        : FontWeight.w600,
                    fontSize: 12,
                  ),
                  icon: const Icon(Icons.arrow_drop_down,
                      color: AppColors.primary, size: 18),
                  hint: const Text(
                    'Tất cả thương hiệu',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                  onChanged: (v) {
                    ref.read(productBrandFilterProvider.notifier).state = v;
                    setState(() {
                      _currentLimit = 50;
                    });
                  },
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'Tất cả thương hiệu',
                        style:
                            TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                    ...brands.map((b) => DropdownMenuItem<String?>(
                          value: b,
                          child: Text(
                            b,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 4. Sắp xếp (Sort)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isSortFiltered
                    ? AppColors.primary.withOpacity(0.08)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSortFiltered
                      ? AppColors.primary
                      : AppColors.border,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ProductSortOption>(
                  value: sortOption,
                  isDense: true,
                  style: TextStyle(
                    color: isSortFiltered
                        ? AppColors.primary
                        : AppColors.primary,
                    fontWeight: isSortFiltered
                        ? FontWeight.bold
                        : FontWeight.w600,
                    fontSize: 12,
                  ),
                  icon: const Icon(Icons.sort,
                      color: AppColors.primary, size: 18),
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(productSortOptionProvider.notifier).state = v;
                      setState(() {
                        _currentLimit = 50;
                      });
                    }
                  },
                  items: const [
                    DropdownMenuItem(
                      value: ProductSortOption.stockDesc,
                      child: Text('Tồn kho: Cao → Thấp',
                          style: TextStyle(
                              fontSize: 12, color: Colors.black87)),
                    ),
                    DropdownMenuItem(
                      value: ProductSortOption.stockAsc,
                      child: Text('Tồn kho: Thấp → Cao',
                          style: TextStyle(
                              fontSize: 12, color: Colors.black87)),
                    ),
                    DropdownMenuItem(
                      value: ProductSortOption.nameAsc,
                      child: Text('Tên: A → Z',
                          style: TextStyle(
                              fontSize: 12, color: Colors.black87)),
                    ),
                    DropdownMenuItem(
                      value: ProductSortOption.nameDesc,
                      child: Text('Tên: Z → A',
                          style: TextStyle(
                              fontSize: 12, color: Colors.black87)),
                    ),
                    DropdownMenuItem(
                      value: ProductSortOption.priceAsc,
                      child: Text('Giá: Thấp → Cao',
                          style: TextStyle(
                              fontSize: 12, color: Colors.black87)),
                    ),
                    DropdownMenuItem(
                      value: ProductSortOption.priceDesc,
                      child: Text('Giá: Cao → Thấp',
                          style: TextStyle(
                              fontSize: 12, color: Colors.black87)),
                    ),
                  ],
                ),
              ),
            ),

            // 5. Đặt lại bộ lọc (Reset Filters)
            if (hasActiveFilters) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Đặt lại bộ lọc',
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.refresh,
                        color: AppColors.primary, size: 18),
                    tooltip: 'Đặt lại bộ lọc',
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    constraints:
                        const BoxConstraints(minHeight: 32, minWidth: 32),
                    onPressed: () {
                      ref
                          .read(productStockStatusFilterProvider.notifier)
                          .state = StockStatus.all;
                      ref
                          .read(productCategoryFilterProvider.notifier)
                          .state = 'All';
                      ref
                          .read(productBrandFilterProvider.notifier)
                          .state = null;
                      ref
                          .read(productSortOptionProvider.notifier)
                          .state = ProductSortOption.stockDesc;
                      setState(() {
                        _currentLimit = 50;
                      });
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTotalSummaryCard({
    required int count,
    required int totalStock,
    required double totalCostValue,
    required bool isSupervisor,
    required AppLocalizations l10n,
  }) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceInfo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        l10n.totalProducts(count),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.totalStockCount(totalStock),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSupervisor
                        ? Icons.account_balance_wallet_outlined
                        : Icons.lock_outline,
                    size: 15,
                    color: isSupervisor ? Colors.teal : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Giá trị kho:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              if (isSupervisor)
                Flexible(
                  child: Text(
                    '${currencyFormat.format(totalCostValue)} đ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.teal,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                )
              else
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock, size: 13, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      '***',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _refreshProducts() async {
    try {
      ref.invalidate(productListProvider);
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (_) {}
    ref.invalidate(productListProvider);
    await Future.delayed(const Duration(milliseconds: 100));
  }

  void _navigateToAddProduct() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AddProductPage(),
      ),
    );
  }

  Future<void> _importProducts() async {
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
          final merged = product.copyWith(
            branchStocks: existing.branchStocks,
            imageUrl: existing.imageUrl,
          );
          await productRepo.upsert(merged);
          updatedCount++;
        } else {
          await productRepo.upsert(product);
          for (final entry in product.branchStocks.entries) {
            if (entry.value > 0) {
              final tx = InventoryTransaction(
                id: 'import_${now.millisecondsSinceEpoch}_${product.id}_${entry.key}',
                productId: product.id,
                type: TransactionType.import,
                quantity: entry.value,
                date: now,
                note: 'Nhập tồn đầu kỳ từ file Excel (${entry.key})',
                importPrice: product.costPrice,
                storeId: entry.key,
              );
              await inventoryRepo.record(tx);
            }
          }
          addedCount++;
        }
      }

      ref.invalidate(productListProvider);

      if (mounted) {
        Navigator.of(context).pop();
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
          Navigator.of(context).pop();
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

  Future<void> _exportProducts() async {
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
        Navigator.of(context).pop();

        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Danh sách sản phẩm',
        );
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
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

  Future<void> _autoAssignSampleImages() async {
    final productsAsync = ref.read(productListProvider);
    final allProducts = productsAsync.maybeWhen(
      data: (list) => list,
      orElse: () => <Product>[],
    );

    if (allProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có sản phẩm nào trong hệ thống!')),
      );
      return;
    }

    final missingImageProducts = allProducts
        .where((p) => p.imageUrl == null || p.imageUrl!.isEmpty)
        .toList();

    if (missingImageProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tất cả sản phẩm đều đã có hình ảnh!')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tự động gán ảnh mẫu'),
        content: Text(
          'Tìm thấy ${missingImageProducts.length} sản phẩm chưa có ảnh. Hệ thống sẽ tự động gán hình ảnh minh họa chất lượng cao phù hợp cho từng sản phẩm.\n\nBạn có muốn tiếp tục?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Bắt đầu gán ảnh'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Đang gán ảnh cho ${missingImageProducts.length} sản phẩm...',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    int count = 0;
    try {
      final repo = ref.read(productRepositoryProvider);
      for (final p in missingImageProducts) {
        final sampleUrl = SampleImageHelper.getSampleImageUrl(p);
        final updated = p.copyWith(imageUrl: sampleUrl);
        await repo.upsert(updated);
        count++;
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã tự động gán ảnh thành công cho $count sản phẩm!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Có lỗi xảy ra: $e (Đã gán được $count sản phẩm)'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
