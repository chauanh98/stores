import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/products/usecases/import_products_usecase.dart';
import '../../../core/services/filter_storage_service.dart';
import '../../../core/utils/excel_helper.dart';
import '../../../core/utils/file_saver.dart';
import '../../../core/utils/sample_image_helper.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/user_account.dart';
import '../../common/widgets/error_view.dart';
import '../../common/widgets/scroll_aware_fab.dart';
import '../../inventories/pages/import_inventory_page.dart';
import '../widgets/category_filter_bottom_sheet.dart';
import '../widgets/product_tile.dart';
import 'add_product_page.dart';

class ProductsPage extends ConsumerStatefulWidget {
  final String? initialCategory;

  const ProductsPage({
    super.key,
    this.initialCategory,
  });

  @override
  ConsumerState<ProductsPage> createState() => ProductsPageState();
}

class ProductsPageState extends ConsumerState<ProductsPage> {
  final _searchController = TextEditingController();
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
      if (widget.initialCategory != null) {
        ref.read(productCategoryFilterProvider.notifier).state =
            widget.initialCategory!;
        ref.read(productSelectedCategoriesProvider.notifier).state = {
          widget.initialCategory!
        };
        await _persistProductsFilters();
      } else {
        // Hydrate from storage if present
        final saved = await storage.loadFilter('products', user?.username);
        if (saved != null &&
            mounted &&
            ref.read(authProvider)?.username == user?.username) {
          if (saved['selectedCategories'] is List) {
            final cats = (saved['selectedCategories'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty && e != 'null' && e != 'All')
                .toSet();
            ref.read(productSelectedCategoriesProvider.notifier).state = cats;
            if (cats.isNotEmpty) {
              ref.read(productCategoryFilterProvider.notifier).state =
                  cats.length == 1 ? cats.first : 'All';
            }
          } else if (saved['category'] != null) {
            final cat = saved['category'].toString().trim();
            ref.read(productCategoryFilterProvider.notifier).state = cat;
            if (cat.isNotEmpty && cat != 'null' && cat != 'All') {
              ref.read(productSelectedCategoriesProvider.notifier).state = {
                cat
              };
            }
          }
          if (saved['productTypes'] is List) {
            final types = (saved['productTypes'] as List)
                .map((e) => e.toString())
                .map((name) => ProductTypeFilter.values
                    .cast<ProductTypeFilter?>()
                    .firstWhere(
                      (v) => v?.name == name,
                      orElse: () => null,
                    ))
                .whereType<ProductTypeFilter>()
                .toSet();
            if (types.isNotEmpty) {
              ref.read(productTypeFilterProvider.notifier).state = types;
            }
          }
          if (saved['stockStatus'] != null) {
            final status = StockStatus.values.firstWhere(
              (e) => e.name == saved['stockStatus']?.toString(),
              orElse: () => StockStatus.all,
            );
            ref.read(productStockStatusFilterProvider.notifier).state = status;
          }
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant ProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCategory != null &&
        widget.initialCategory != oldWidget.initialCategory) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        ref.read(productCategoryFilterProvider.notifier).state =
            widget.initialCategory!;
        ref.read(productSelectedCategoriesProvider.notifier).state = {
          widget.initialCategory!
        };
        await _persistProductsFilters();
      });
    }
  }

  Future<void> _persistProductsFilters() async {
    final user = ref.read(authProvider);
    final categories = ref.read(productSelectedCategoriesProvider);
    final productTypes = ref.read(productTypeFilterProvider);
    final stockStatus = ref.read(productStockStatusFilterProvider);
    final legacyCategory = ref.read(productCategoryFilterProvider);

    await ref.read(filterStorageServiceProvider).saveFilter(
        'products',
        {
          'category': legacyCategory,
          'selectedCategories': categories.toList(),
          'productTypes': productTypes.map((e) => e.name).toList(),
          'stockStatus': stockStatus.name,
        },
        user?.username);
  }

  void _setCategories(Set<String> categories) {
    final clean = categories
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty && c != 'All' && c != 'Tất cả')
        .toSet();
    ref.read(productSelectedCategoriesProvider.notifier).state = clean;
    ref.read(productCategoryFilterProvider.notifier).state =
        clean.length == 1 ? clean.first : 'All';
    _persistProductsFilters();
    setState(() {
      _currentLimit = 50;
    });
  }

  void _setCategory(String category) {
    final target =
        (category == 'All' || category == 'Tất cả') ? 'All' : category.trim();
    ref.read(productCategoryFilterProvider.notifier).state = target;
    ref.read(productSelectedCategoriesProvider.notifier).state =
        target == 'All' ? const <String>{} : {target};
    _persistProductsFilters();
    setState(() {
      _currentLimit = 50;
    });
  }

  void _setStockStatus(StockStatus status) {
    ref.read(productStockStatusFilterProvider.notifier).state = status;
    _persistProductsFilters();
    setState(() {
      _currentLimit = 50;
    });
  }

  void _setProductTypes(Set<ProductTypeFilter> types) {
    ref.read(productTypeFilterProvider.notifier).state = types;
    _persistProductsFilters();
    setState(() {
      _currentLimit = 50;
    });
  }

  void _showProductTypeFilterBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width,
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final currentTypes = ref.watch(productTypeFilterProvider);
            return Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width,
              ),
              decoration: const BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 6),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.grey300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'Chọn loại hàng',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          TextButton(
                            key: const Key('select_all_product_types_button'),
                            onPressed: () {
                              _setProductTypes({
                                ProductTypeFilter.standard,
                                ProductTypeFilter.combo,
                                ProductTypeFilter.service,
                              });
                            },
                            child: const Text('Tất cả'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.dividerLight),
                    CheckboxListTile(
                      key: const Key('product_type_checkbox_standard'),
                      title: const Text('Hàng hóa thường'),
                      value: currentTypes.contains(ProductTypeFilter.standard),
                      activeColor: AppColors.primary,
                      onChanged: (val) {
                        final updated =
                            Set<ProductTypeFilter>.from(currentTypes);
                        if (val == true) {
                          updated.add(ProductTypeFilter.standard);
                        } else {
                          updated.remove(ProductTypeFilter.standard);
                        }
                        _setProductTypes(updated);
                      },
                    ),
                    CheckboxListTile(
                      key: const Key('product_type_checkbox_combo'),
                      title: const Text('Combo - Đóng gói'),
                      value: currentTypes.contains(ProductTypeFilter.combo),
                      activeColor: AppColors.primary,
                      onChanged: (val) {
                        final updated =
                            Set<ProductTypeFilter>.from(currentTypes);
                        if (val == true) {
                          updated.add(ProductTypeFilter.combo);
                        } else {
                          updated.remove(ProductTypeFilter.combo);
                        }
                        _setProductTypes(updated);
                      },
                    ),
                    CheckboxListTile(
                      key: const Key('product_type_checkbox_service'),
                      title: const Text('Dịch vụ'),
                      value: currentTypes.contains(ProductTypeFilter.service),
                      activeColor: AppColors.primary,
                      onChanged: (val) {
                        final updated =
                            Set<ProductTypeFilter>.from(currentTypes);
                        if (val == true) {
                          updated.add(ProductTypeFilter.service);
                        } else {
                          updated.remove(ProductTypeFilter.service);
                        }
                        _setProductTypes(updated);
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
    final selectedCategories = ref.watch(productSelectedCategoriesProvider);
    final selectedProductTypes = ref.watch(productTypeFilterProvider);
    final selectedBrand = ref.watch(productBrandFilterProvider);
    final stockStatus = ref.watch(productStockStatusFilterProvider);
    final sortOption = ref.watch(productSortOptionProvider);

    final user = ref.watch(authProvider);

    ref.listen<UserAccount?>(authProvider, (prev, next) {
      if (next != null && (prev == null || prev.username != next.username)) {
        ref
            .read(filterStorageServiceProvider)
            .loadFilter('products', next.username)
            .then((saved) {
          if (saved != null &&
              mounted &&
              ref.read(authProvider)?.username == next.username) {
            if (saved['selectedCategories'] is List) {
              final cats = (saved['selectedCategories'] as List)
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty && e != 'null' && e != 'All')
                  .toSet();
              ref.read(productSelectedCategoriesProvider.notifier).state = cats;
              if (cats.isNotEmpty) {
                ref.read(productCategoryFilterProvider.notifier).state =
                    cats.length == 1 ? cats.first : 'All';
              }
            } else if (saved['category'] != null) {
              final cat = saved['category'].toString().trim();
              ref.read(productCategoryFilterProvider.notifier).state = cat;
              if (cat.isNotEmpty && cat != 'null' && cat != 'All') {
                ref.read(productSelectedCategoriesProvider.notifier).state = {
                  cat
                };
              }
            }
            if (saved['productTypes'] is List) {
              final types = (saved['productTypes'] as List)
                  .map((e) => e.toString())
                  .map((name) => ProductTypeFilter.values
                      .cast<ProductTypeFilter?>()
                      .firstWhere(
                        (v) => v?.name == name,
                        orElse: () => null,
                      ))
                  .whereType<ProductTypeFilter>()
                  .toSet();
              if (types.isNotEmpty) {
                ref.read(productTypeFilterProvider.notifier).state = types;
              }
            }
            if (saved['stockStatus'] != null) {
              final status = StockStatus.values.firstWhere(
                (e) => e.name == saved['stockStatus']?.toString(),
                orElse: () => StockStatus.all,
              );
              ref.read(productStockStatusFilterProvider.notifier).state =
                  status;
            }
          }
        });
      }
    });

    final canManageProducts = user?.canManageProducts ?? false;
    final canViewCostValue = user?.canViewCostPrice == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.products),
        actions: [
          if (canManageProducts)
            PopupMenuButton<String>(
              key: const Key('products_excel_actions_menu'),
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
                          color: AppColors.grey400),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l10n.importProduct)),
                    ],
                  ),
                ),
                if (kIsWeb && (user?.isAdmin == true)) ...[
                  PopupMenuItem<String>(
                    value: 'import_excel',
                    child: Row(
                      children: [
                        const Icon(Icons.upload_file, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(l10n.importExcel)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'export_excel',
                    child: Row(
                      children: [
                        const Icon(Icons.download, color: AppColors.success),
                        const SizedBox(width: 8),
                        Expanded(child: Text(l10n.exportExcel)),
                      ],
                    ),
                  ),
                ],
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'auto_assign_images',
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: AppColors.warning),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tự động gán ảnh mẫu',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                      ),
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
              selectedCategories: selectedCategories,
              selectedProductTypes: selectedProductTypes,
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
                      canViewCostValue: canViewCostValue,
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
                foregroundColor: AppColors.white,
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
    required Set<String> selectedCategories,
    required Set<ProductTypeFilter> selectedProductTypes,
    required String? selectedBrand,
    required ProductSortOption sortOption,
  }) {
    final isStockFiltered = stockStatus != StockStatus.all;
    final isTypeFiltered =
        selectedProductTypes.length < ProductTypeFilter.values.length;

    final effectiveCategory =
        (selectedCategory.trim().isNotEmpty && selectedCategory != 'All')
            ? selectedCategory
            : 'All';
    final isCategoryFiltered = (selectedCategories.isNotEmpty &&
            !selectedCategories.contains('All')) ||
        (effectiveCategory != 'All');

    final isBrandFiltered = selectedBrand != null;
    final isSortFiltered = sortOption != ProductSortOption.stockDesc;

    int activeFilterCount = 0;
    if (isStockFiltered) activeFilterCount++;
    if (isTypeFiltered) activeFilterCount++;
    if (isCategoryFiltered) activeFilterCount++;
    if (isBrandFiltered) activeFilterCount++;
    if (isSortFiltered) activeFilterCount++;
    final hasActiveFilters = activeFilterCount > 0;

    final String productTypeLabel;
    if (selectedProductTypes.length == ProductTypeFilter.values.length) {
      productTypeLabel = 'Loại hàng';
    } else if (selectedProductTypes.length == 1) {
      final single = selectedProductTypes.first;
      switch (single) {
        case ProductTypeFilter.standard:
          productTypeLabel = 'Hàng thường';
          break;
        case ProductTypeFilter.combo:
          productTypeLabel = 'Combo';
          break;
        case ProductTypeFilter.service:
          productTypeLabel = 'Dịch vụ';
          break;
      }
    } else {
      productTypeLabel = 'Loại hàng (${selectedProductTypes.length})';
    }

    final String categoryFilterLabel;
    if (selectedCategories.isEmpty || selectedCategories.contains('All')) {
      if (effectiveCategory == 'All') {
        categoryFilterLabel = 'Tất cả nhóm hàng';
      } else {
        categoryFilterLabel = effectiveCategory;
      }
    } else if (selectedCategories.length == 1) {
      categoryFilterLabel = selectedCategories.first;
    } else {
      categoryFilterLabel = 'Nhóm hàng (${selectedCategories.length})';
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
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
                  color: isStockFiltered ? AppColors.primary : AppColors.border,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<StockStatus>(
                  value: stockStatus,
                  isDense: true,
                  style: TextStyle(
                    color: isStockFiltered
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    fontWeight:
                        isStockFiltered ? FontWeight.bold : FontWeight.w600,
                    fontSize: 12,
                  ),
                  icon: Icon(
                    Icons.arrow_drop_down,
                    color:
                        isStockFiltered ? AppColors.primary : AppColors.primary,
                    size: 18,
                  ),
                  onChanged: (v) {
                    if (v != null) {
                      _setStockStatus(v);
                    }
                  },
                  items: const [
                    DropdownMenuItem(
                      value: StockStatus.all,
                      child: Text(
                        'Tất cả',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textPrimary),
                      ),
                    ),
                    DropdownMenuItem(
                      value: StockStatus.inStock,
                      child: Text(
                        'Còn hàng (> 0)',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textPrimary),
                      ),
                    ),
                    DropdownMenuItem(
                      value: StockStatus.outOfStock,
                      child: Text(
                        'Hết hàng (= 0)',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textPrimary),
                      ),
                    ),
                    DropdownMenuItem(
                      value: StockStatus.belowMinStock,
                      child: Text(
                        'Dưới định mức',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 1b. Loại hàng (Product Types)
            Container(
              key: const Key('product_type_filter_button'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isTypeFiltered
                    ? AppColors.primary.withOpacity(0.08)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isTypeFiltered ? AppColors.primary : AppColors.border,
                ),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showProductTypeFilterBottomSheet(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      productTypeLabel,
                      style: TextStyle(
                        color: isTypeFiltered
                            ? AppColors.primary
                            : AppColors.primary,
                        fontWeight:
                            isTypeFiltered ? FontWeight.bold : FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    if (isTypeFiltered) ...[
                      const SizedBox(width: 4),
                      InkWell(
                        key: const Key('clear_product_type_filter_button'),
                        onTap: () {
                          _setProductTypes({
                            ProductTypeFilter.standard,
                            ProductTypeFilter.combo,
                            ProductTypeFilter.service,
                          });
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 2),
                          child: Icon(Icons.close,
                              color: AppColors.primary, size: 16),
                        ),
                      ),
                    ] else ...[
                      const Icon(Icons.arrow_drop_down,
                          color: AppColors.primary, size: 18),
                    ],
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
                  color:
                      isCategoryFiltered ? AppColors.primary : AppColors.border,
                ),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  CategoryFilterBottomSheet.show(
                    context,
                    currentCategory: effectiveCategory,
                    initialSelectedCategories: selectedCategories,
                    onCategoriesSelected: (cats) {
                      _setCategories(cats);
                    },
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        key: const Key('product_category_dropdown'),
                        value: 'All',
                        isDense: true,
                        disabledHint: Text(
                          categoryFilterLabel,
                          style: TextStyle(
                            color: isCategoryFiltered
                                ? AppColors.primary
                                : AppColors.primary,
                            fontWeight: isCategoryFiltered
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        style: TextStyle(
                          color: isCategoryFiltered
                              ? AppColors.primary
                              : AppColors.primary,
                          fontWeight: isCategoryFiltered
                              ? FontWeight.bold
                              : FontWeight.w600,
                          fontSize: 12,
                        ),
                        icon: const SizedBox.shrink(),
                        onChanged: null,
                        items: categories
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                    c == 'All' ? categoryFilterLabel : c,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    if (isCategoryFiltered) ...[
                      const SizedBox(width: 4),
                      InkWell(
                        key: const Key('clear_category_filter_button'),
                        onTap: () => _setCategory('All'),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 2),
                          child: Icon(Icons.close,
                              color: AppColors.primary, size: 16),
                        ),
                      ),
                    ] else ...[
                      const Icon(Icons.arrow_drop_down,
                          color: AppColors.primary, size: 18),
                    ],
                  ],
                ),
              ),
            ),

            // Đặt lại bộ lọc (Reset Filters)
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
                  child: InkWell(
                    key: const Key('reset_product_filters_button'),
                    onTap: () async {
                      ref
                          .read(productStockStatusFilterProvider.notifier)
                          .state = StockStatus.all;
                      ref.read(productCategoryFilterProvider.notifier).state =
                          'All';
                      ref
                          .read(productSelectedCategoriesProvider.notifier)
                          .state = const <String>{};
                      ref.read(productTypeFilterProvider.notifier).state =
                          const {
                        ProductTypeFilter.standard,
                        ProductTypeFilter.combo,
                        ProductTypeFilter.service,
                      };
                      ref.read(productBrandFilterProvider.notifier).state =
                          null;
                      ref.read(productSortOptionProvider.notifier).state =
                          ProductSortOption.stockDesc;
                      final user = ref.read(authProvider);
                      await ref
                          .read(filterStorageServiceProvider)
                          .clearFilter('products', user?.username);
                      setState(() {
                        _currentLimit = 50;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.refresh,
                              color: AppColors.primary, size: 16),
                          const SizedBox(width: 4),
                          const Text(
                            'Đặt lại',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          if (activeFilterCount > 1) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$activeFilterCount',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
                  color: isBrandFiltered ? AppColors.primary : AppColors.border,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value:
                      (selectedBrand != null && brands.contains(selectedBrand))
                          ? selectedBrand
                          : null,
                  isDense: true,
                  style: TextStyle(
                    color:
                        isBrandFiltered ? AppColors.primary : AppColors.primary,
                    fontWeight:
                        isBrandFiltered ? FontWeight.bold : FontWeight.w600,
                    fontSize: 12,
                  ),
                  icon: const Icon(Icons.arrow_drop_down,
                      color: AppColors.primary, size: 18),
                  hint: const Text(
                    'Tất cả thương hiệu',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textPrimary),
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
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textPrimary),
                      ),
                    ),
                    ...brands.map((b) => DropdownMenuItem<String?>(
                          value: b,
                          child: Text(
                            b,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
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
                  color: isSortFiltered ? AppColors.primary : AppColors.border,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ProductSortOption>(
                  value: sortOption,
                  isDense: true,
                  style: TextStyle(
                    color:
                        isSortFiltered ? AppColors.primary : AppColors.primary,
                    fontWeight:
                        isSortFiltered ? FontWeight.bold : FontWeight.w600,
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
                              fontSize: 12, color: AppColors.textPrimary)),
                    ),
                    DropdownMenuItem(
                      value: ProductSortOption.stockAsc,
                      child: Text('Tồn kho: Thấp → Cao',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textPrimary)),
                    ),
                    DropdownMenuItem(
                      value: ProductSortOption.nameAsc,
                      child: Text('Tên: A → Z',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textPrimary)),
                    ),
                    DropdownMenuItem(
                      value: ProductSortOption.nameDesc,
                      child: Text('Tên: Z → A',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textPrimary)),
                    ),
                    DropdownMenuItem(
                      value: ProductSortOption.priceAsc,
                      child: Text('Giá: Thấp → Cao',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textPrimary)),
                    ),
                    DropdownMenuItem(
                      value: ProductSortOption.priceDesc,
                      child: Text('Giá: Cao → Thấp',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textPrimary)),
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

  Widget _buildTotalSummaryCard({
    required int count,
    required int totalStock,
    required double totalCostValue,
    required bool canViewCostValue,
    required AppLocalizations l10n,
  }) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.totalProducts(count),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.totalStockCount(totalStock),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
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
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      canViewCostValue
                          ? Icons.account_balance_wallet_outlined
                          : Icons.lock_outline,
                      size: 15,
                      color: canViewCostValue
                          ? AppColors.chartTeal
                          : AppColors.grey400,
                    ),
                    const SizedBox(width: 6),
                    const Flexible(
                      child: Text(
                        'Giá trị kho:',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (canViewCostValue)
                Flexible(
                  child: Text(
                    '${currencyFormat.format(totalCostValue)} đ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.chartTeal,
                    ),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock, size: 13, color: AppColors.grey400),
                    SizedBox(width: 4),
                    Text(
                      '***',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.grey400,
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
      final currentStoreId = ref.read(currentStoreIdProvider);
      final importResult =
          await ref.read(importProductsUseCaseProvider).execute(
                products: importedProducts,
                targetStoreId: currentStoreId,
              );

      ref.invalidate(productListProvider);

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
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
          Navigator.of(context).pop();
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

  Future<void> _exportProducts() async {
    final user = ref.read(authProvider);
    if (!kIsWeb || (user?.isAdmin != true)) return;

    final l10n = AppLocalizations.of(context)!;
    try {
      final productsAsync = ref.read(productListProvider);
      final products = productsAsync.maybeWhen(
        data: (list) => list,
        orElse: () => <Product>[],
      );

      if (products.isEmpty) {
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

      final bytes = await ExcelHelper.exportProducts(products);

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        await saveExcelFile(bytes, 'DanhSachSanPham_Export.xlsx');
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi xuất file: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @visibleForTesting
  Future<void> testImportProducts() => _importProducts();

  @visibleForTesting
  Future<void> testExportProducts() => _exportProducts();

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
            backgroundColor: AppColors.success,
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
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }
}
