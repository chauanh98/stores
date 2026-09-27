import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/core/theme/app_colors.dart';
import '../../../core/utils/vietnamese_text_helper.dart';

import '../../../application/products/categories_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/repositories/category_repository.dart';
import '../pages/categories_management_page.dart';

class CategoryFilterBottomSheet extends ConsumerStatefulWidget {
  final String? currentSelectedCategory;
  final ValueChanged<String>? onCategorySelected;
  final Set<String>? initialSelectedCategories;
  final ValueChanged<Set<String>>? onCategoriesSelected;

  const CategoryFilterBottomSheet({
    super.key,
    this.currentSelectedCategory,
    this.onCategorySelected,
    this.initialSelectedCategories,
    this.onCategoriesSelected,
  });

  static Future<void> show(
    BuildContext context, {
    String? currentCategory,
    Set<String>? initialSelectedCategories,
    ValueChanged<String>? onSelected,
    ValueChanged<Set<String>>? onCategoriesSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.transparent,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width,
      ),
      builder: (_) => CategoryFilterBottomSheet(
        currentSelectedCategory: currentCategory,
        onCategorySelected: onSelected,
        initialSelectedCategories: initialSelectedCategories,
        onCategoriesSelected: onCategoriesSelected,
      ),
    );
  }

  @override
  ConsumerState<CategoryFilterBottomSheet> createState() =>
      _CategoryFilterBottomSheetState();
}

class _CategoryFilterBottomSheetState
    extends ConsumerState<CategoryFilterBottomSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  final Set<String> _expandedCategoryIds = {};
  late Set<String> _selectedCategories;

  List<Category>? _lastRawCategories;
  List<Product>? _lastProducts;
  List<Category> _cachedHarvestedCategories = const [];
  Map<String, int> _cachedProductCounts = const {};

  @override
  void initState() {
    super.initState();
    if (widget.initialSelectedCategories != null) {
      _selectedCategories = Set<String>.from(
        widget.initialSelectedCategories!
            .where((c) => c != 'All' && c.trim().isNotEmpty),
      );
    } else if (widget.currentSelectedCategory != null &&
        widget.currentSelectedCategory != 'All' &&
        widget.currentSelectedCategory!.trim().isNotEmpty) {
      _selectedCategories = {widget.currentSelectedCategory!.trim()};
    } else {
      _selectedCategories = {};
    }
  }

  bool _isCategorySelected(Category cat) {
    return _selectedCategories.any(
      (s) =>
          s.trim().toLowerCase() == cat.name.trim().toLowerCase() ||
          s.trim().toLowerCase() == cat.id.trim().toLowerCase(),
    );
  }

  void _toggleCategory(Category cat) {
    setState(() {
      final existing = _selectedCategories.firstWhere(
        (s) =>
            s.trim().toLowerCase() == cat.name.trim().toLowerCase() ||
            s.trim().toLowerCase() == cat.id.trim().toLowerCase(),
        orElse: () => '',
      );
      if (existing.isNotEmpty) {
        _selectedCategories.remove(existing);
      } else {
        _selectedCategories.add(cat.name);
      }
    });
  }

  List<Category> _getHarvestedCategories(
    List<Category> rawCategories,
    List<Product> products,
    CategoryRepository repo,
  ) {
    if (identical(_lastRawCategories, rawCategories) &&
        identical(_lastProducts, products) &&
        _cachedHarvestedCategories.isNotEmpty) {
      return _cachedHarvestedCategories;
    }
    _cachedHarvestedCategories = harvestCategoriesFromProducts(
      rawCategories,
      products,
      syncRepo: repo,
    );
    return _cachedHarvestedCategories;
  }

  Map<String, int> _getProductCounts(
    List<Category> rawCategories,
    List<Product> products,
    List<Category> harvestedCategories,
  ) {
    if (identical(_lastRawCategories, rawCategories) &&
        identical(_lastProducts, products) &&
        _cachedProductCounts.isNotEmpty) {
      return _cachedProductCounts;
    }
    _lastRawCategories = rawCategories;
    _lastProducts = products;
    _cachedProductCounts =
        _calculateCategoryProductCounts(harvestedCategories, products);
    return _cachedProductCounts;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoryListProvider);
    final productsAsync = ref.watch(productListProvider);
    final isAllSelected = _selectedCategories.isEmpty;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width,
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
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

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.category, color: AppColors.primary, size: 22),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Chọn nhóm hàng',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    // Quick Action Shortcut: Quản lý nhóm hàng
                    TextButton.icon(
                      key: const Key('manage_categories_button'),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CategoriesManagementPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      label: const Text(
                        'Quản lý',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.grey400),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: TextField(
              key: const Key('category_search_field'),
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm nhóm hàng...',
                prefixIcon: const Icon(Icons.search,
                    size: 20, color: AppColors.grey400),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            size: 18, color: AppColors.grey400),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.background,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.borderLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),

          // "Tất cả nhóm hàng" Option
          if (_searchQuery.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: InkWell(
                key: const Key('category_item_all'),
                onTap: () {
                  setState(() {
                    _selectedCategories.clear();
                  });
                  if (widget.onCategoriesSelected != null) {
                    widget.onCategoriesSelected!(const <String>{});
                  } else if (widget.onCategorySelected != null) {
                    widget.onCategorySelected!('All');
                  }
                  Navigator.pop(context);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isAllSelected
                        ? AppColors.primary.withOpacity(0.08)
                        : AppColors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isAllSelected
                        ? Border.all(color: AppColors.primary)
                        : Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        key: const Key('checkbox_category_all'),
                        value: isAllSelected,
                        onChanged: (_) {
                          setState(() {
                            _selectedCategories.clear();
                          });
                          if (widget.onCategoriesSelected == null) {
                            widget.onCategorySelected?.call('All');
                            Navigator.pop(context);
                          }
                        },
                        activeColor: AppColors.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.apps,
                        size: 20,
                        color: isAllSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tất cả nhóm hàng',
                          style: TextStyle(
                            fontWeight: isAllSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 14,
                            color: isAllSelected
                                ? AppColors.primary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (isAllSelected)
                        const Icon(Icons.check,
                            color: AppColors.primary, size: 18),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 6),
          const Divider(height: 1, color: AppColors.dividerLight),

          // Categories Tree / Flat Search List
          Expanded(
            child: Builder(
              builder: (context) {
                final rawCategories = categoriesAsync.valueOrNull ?? [];
                final products = productsAsync.valueOrNull ?? [];
                final categoryRepo = ref.watch(categoryRepositoryProvider);

                final categories = _getHarvestedCategories(
                  rawCategories,
                  products,
                  categoryRepo,
                );

                final productCountMap =
                    _getProductCounts(rawCategories, products, categories);

                if (categories.isEmpty) {
                  if (categoriesAsync.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return const Center(
                    child: Text('Chưa có nhóm hàng nào'),
                  );
                }

                // If searching, show filtered flat list
                if (_searchQuery.isNotEmpty) {
                  final qLower = _searchQuery.toLowerCase();
                  final qNorm =
                      VietnameseTextHelper.normalizeUnaccented(_searchQuery);
                  final filtered = categories.where((c) {
                    final nameLower = c.name.toLowerCase();
                    final nameNorm =
                        VietnameseTextHelper.normalizeUnaccented(c.name);
                    return nameLower.contains(qLower) ||
                        nameNorm.contains(qNorm);
                  }).toList();

                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text('Không tìm thấy nhóm hàng phù hợp',
                          style: TextStyle(color: AppColors.textSecondary)),
                    );
                  }

                  return ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final cat = filtered[index];
                      final isSelected = _isCategorySelected(cat);
                      final count = productCountMap[cat.id] ?? 0;
                      final path = _buildCategoryPath(cat, categories);

                      return _buildCategoryTile(
                        category: cat,
                        isSelected: isSelected,
                        productCount: count,
                        subtitle: path,
                        depth: 0,
                        hasChildren: false,
                        isExpanded: false,
                        onToggleExpand: null,
                      );
                    },
                  );
                }

                // Tree View - include roots, orphan categories, and cycle-breakers
                final categoryMap = {for (final c in categories) c.id: c};
                final reachableFromRoot = <String>{};

                final standardRoots = <Category>[];
                for (final c in categories) {
                  if (c.parentId == null ||
                      c.parentId!.trim().isEmpty ||
                      !categoryMap.containsKey(c.parentId!.trim())) {
                    standardRoots.add(c);
                  }
                }

                void markReachable(String parentId) {
                  for (final c in categories) {
                    if (c.parentId != null &&
                        c.parentId!.trim() == parentId &&
                        reachableFromRoot.add(c.id)) {
                      markReachable(c.id);
                    }
                  }
                }

                for (final root in standardRoots) {
                  reachableFromRoot.add(root.id);
                  markReachable(root.id);
                }

                final cycleRoots = <Category>[];
                for (final c in categories) {
                  if (!reachableFromRoot.contains(c.id)) {
                    cycleRoots.add(c);
                  }
                }
                final cycleRootIds = cycleRoots.map((e) => e.id).toSet();

                final rootCategories = [...standardRoots, ...cycleRoots]..sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                return Column(
                  children: [
                    _buildTreeToolbar(categories),
                    const Divider(height: 1, color: AppColors.dividerLight),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        itemCount: rootCategories.length,
                        itemBuilder: (context, index) {
                          final root = rootCategories[index];
                          return _buildTreeNode(
                            node: root,
                            allCategories: categories,
                            productCountMap: productCountMap,
                            depth: 0,
                            cycleRootIds: cycleRootIds,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildTreeToolbar(List<Category> categories) {
    final parentIds = categories
        .where((c) => c.parentId != null && c.parentId!.trim().isNotEmpty)
        .map((c) => c.parentId!.trim())
        .toSet();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nhóm (${categories.length})',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              key: const Key('collapse_all_categories_button'),
              onPressed: _expandedCategoryIds.isEmpty
                  ? null
                  : () => setState(() => _expandedCategoryIds.clear()),
              icon: const Icon(Icons.unfold_less, size: 15),
              label: const Text('Thu gọn', style: TextStyle(fontSize: 11.5)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: _expandedCategoryIds.isEmpty
                    ? AppColors.grey400
                    : AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              key: const Key('expand_all_categories_button'),
              onPressed: () =>
                  setState(() => _expandedCategoryIds.addAll(parentIds)),
              icon: const Icon(Icons.unfold_more, size: 15),
              label: const Text('Mở rộng', style: TextStyle(fontSize: 11.5)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final isAllSelected = _selectedCategories.isEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.06),
            offset: const Offset(0, -2),
            blurRadius: 6,
          ),
        ],
        border: const Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: OutlinedButton(
                key: const Key('reset_category_filter_button'),
                onPressed: isAllSelected
                    ? null
                    : () => setState(() => _selectedCategories.clear()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                    color:
                        isAllSelected ? AppColors.grey300 : AppColors.primary,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Bỏ chọn',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                key: const Key('apply_category_filter_button'),
                onPressed: () {
                  final result = Set<String>.from(_selectedCategories);
                  if (widget.onCategoriesSelected != null) {
                    widget.onCategoriesSelected!(result);
                  } else if (widget.onCategorySelected != null) {
                    widget.onCategorySelected!(
                        result.isEmpty ? 'All' : result.first);
                  }
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  isAllSelected
                      ? 'Áp dụng (Tất cả)'
                      : 'Áp dụng (${_selectedCategories.length} nhóm)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Recursive Tree Node Widget
  Widget _buildTreeNode({
    required Category node,
    required List<Category> allCategories,
    required Map<String, int> productCountMap,
    required int depth,
    Set<String> visitedAncestors = const {},
    Set<String> cycleRootIds = const {},
  }) {
    final currentAncestors = {...visitedAncestors, node.id};
    final validChildren = allCategories
        .where((c) =>
            c.parentId == node.id &&
            !currentAncestors.contains(c.id) &&
            !cycleRootIds.contains(c.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final hasChildren = validChildren.isNotEmpty;
    final isExpanded = _expandedCategoryIds.contains(node.id);
    final isSelected = _isCategorySelected(node);
    final count = productCountMap[node.id] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCategoryTile(
          category: node,
          isSelected: isSelected,
          productCount: count,
          depth: depth,
          hasChildren: hasChildren,
          isExpanded: isExpanded,
          onToggleExpand: hasChildren
              ? () {
                  setState(() {
                    if (_expandedCategoryIds.contains(node.id)) {
                      _expandedCategoryIds.remove(node.id);
                    } else {
                      _expandedCategoryIds.add(node.id);
                    }
                  });
                }
              : null,
        ),
        if (hasChildren && isExpanded)
          ...validChildren.map((child) => _buildTreeNode(
                node: child,
                allCategories: allCategories,
                productCountMap: productCountMap,
                depth: depth + 1,
                visitedAncestors: currentAncestors,
                cycleRootIds: cycleRootIds,
              )),
      ],
    );
  }

  Widget _buildCategoryTile({
    required Category category,
    required bool isSelected,
    required int productCount,
    required int depth,
    required bool hasChildren,
    required bool isExpanded,
    required VoidCallback? onToggleExpand,
    String? subtitle,
  }) {
    final clampedDepth = depth > 4 ? 4 : depth;
    return Container(
      margin: EdgeInsets.only(
        left: clampedDepth * 12.0,
        top: 2,
        bottom: 2,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primary.withOpacity(0.08)
            : AppColors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isSelected
            ? Border.all(color: AppColors.primary)
            : const Border(bottom: BorderSide(color: AppColors.surfaceLight)),
      ),
      child: InkWell(
        key: Key('category_filter_item_${category.id}'),
        onTap: () {
          final isCurrentlyOnlySelected = _selectedCategories.length == 1 &&
              (_selectedCategories.contains(category.id) ||
                  _selectedCategories.contains(category.name));
          if (isCurrentlyOnlySelected) {
            setState(() {
              _selectedCategories.clear();
            });
            if (widget.onCategoriesSelected != null) {
              widget.onCategoriesSelected!(const <String>{});
            } else if (widget.onCategorySelected != null) {
              widget.onCategorySelected!('All');
            }
            Navigator.pop(context);
          } else {
            final catValue = category.name;
            setState(() {
              _selectedCategories = {catValue};
            });
            if (widget.onCategoriesSelected != null) {
              widget.onCategoriesSelected!({catValue});
            } else if (widget.onCategorySelected != null) {
              widget.onCategorySelected!(catValue);
            }
            Navigator.pop(context);
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              if (hasChildren && onToggleExpand != null)
                GestureDetector(
                  onTap: onToggleExpand,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                )
              else
                SizedBox(width: depth > 0 ? 10 : 26),
              Checkbox(
                key: Key('checkbox_category_${category.id}'),
                value: isSelected,
                onChanged: (_) {
                  _toggleCategory(category);
                },
                activeColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Icon(
                hasChildren
                    ? (isExpanded ? Icons.folder_open : Icons.folder)
                    : Icons.label_outline,
                size: 18,
                color: isSelected
                    ? AppColors.primary
                    : (depth == 0
                        ? AppColors.textSecondary
                        : AppColors.chartTeal),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: depth == 0 ? 14 : 13,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null &&
                        subtitle.isNotEmpty &&
                        subtitle != category.name)
                      Text(
                        subtitle,
                        style: const TextStyle(
                            fontSize: 10.5, color: AppColors.textTertiary),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.15)
                      : AppColors.grey100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$productCount',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? AppColors.primary : AppColors.grey700,
                  ),
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check, color: AppColors.primary, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Map<String, int> _calculateCategoryProductCounts(
    List<Category> categories,
    List<Product> products,
  ) {
    if (categories.isEmpty || products.isEmpty) {
      return const {};
    }

    final categoryById = {for (final c in categories) c.id: c};
    final tokenToCategoryIds = <String, List<String>>{};
    for (final c in categories) {
      final nameLower = c.name.trim().toLowerCase();
      final idLower = c.id.trim().toLowerCase();
      tokenToCategoryIds.putIfAbsent(nameLower, () => []).add(c.id);
      if (idLower != nameLower) {
        tokenToCategoryIds.putIfAbsent(idLower, () => []).add(c.id);
      }
    }

    final countMap = <String, int>{for (final c in categories) c.id: 0};

    for (final p in products) {
      final matchedCatIdsForProduct = <String>{};

      // Extract tokens from product
      final tokens = <String>{p.category.trim().toLowerCase()};
      if (p.category.contains('>>') || p.category.contains('>')) {
        for (final seg in p.category.split(RegExp(r'>>|>'))) {
          final s = seg.trim().toLowerCase();
          if (s.isNotEmpty) tokens.add(s);
        }
      }
      final c3 = p.category3Levels;
      if (c3 != null && c3.isNotEmpty) {
        for (final seg in c3.split(RegExp(r'>>|>'))) {
          final s = seg.trim().toLowerCase();
          if (s.isNotEmpty) tokens.add(s);
        }
      }

      for (final t in tokens) {
        final catIds = tokenToCategoryIds[t];
        if (catIds != null) {
          for (final catId in catIds) {
            var curId = catId;
            final cycleGuard = <String>{};
            while (curId.isNotEmpty && cycleGuard.add(curId)) {
              matchedCatIdsForProduct.add(curId);
              final cat = categoryById[curId];
              if (cat == null ||
                  cat.parentId == null ||
                  cat.parentId!.trim().isEmpty) {
                break;
              }
              curId = cat.parentId!.trim();
            }
          }
        }
      }

      for (final catId in matchedCatIdsForProduct) {
        countMap[catId] = (countMap[catId] ?? 0) + 1;
      }
    }

    return countMap;
  }

  String _buildCategoryPath(Category cat, List<Category> all) {
    final path = <String>[cat.name];
    final visited = <String>{cat.id};
    var current = cat;
    while (current.parentId != null && current.parentId!.trim().isNotEmpty) {
      final pid = current.parentId!.trim();
      final parent = all.cast<Category?>().firstWhere(
            (c) => c?.id == pid,
            orElse: () => null,
          );
      if (parent == null || parent.id.isEmpty) break;
      if (!visited.add(parent.id)) break; // Cycle guard
      path.insert(0, parent.name);
      current = parent;
    }
    return path.join(' >> ');
  }
}
