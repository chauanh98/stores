import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/vietnamese_text_helper.dart';

import '../../../application/products/categories_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/repositories/category_repository.dart';

class CategoriesManagementPage extends ConsumerStatefulWidget {
  const CategoriesManagementPage({super.key});

  @override
  ConsumerState<CategoriesManagementPage> createState() =>
      _CategoriesManagementPageState();
}

class _CategoriesManagementPageState
    extends ConsumerState<CategoriesManagementPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _expandedCategoryIds = {};

  List<Category>? _lastRawCategories;
  List<Product>? _lastProducts;
  List<Category> _cachedHarvestedCategories = const [];
  Map<String, int> _cachedProductCounts = const {};

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
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoryListProvider);
    final productsAsync = ref.watch(productListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Quản lý nhóm hàng',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: AppColors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            key: const Key('add_root_category_button'),
            icon: const Icon(Icons.add_circle_outline,
                color: AppColors.primary, size: 26),
            tooltip: 'Thêm nhóm hàng gốc',
            onPressed: () => _showAddCategoryDialog(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab_add_category'),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: AppColors.white),
        label: const Text(
          'Thêm nhóm hàng',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.white),
        ),
        onPressed: () => _showAddCategoryDialog(context),
      ),
      body: Column(
        children: [
          // Search Header
          Container(
            color: AppColors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm tên nhóm hàng...',
                prefixIcon: const Icon(Icons.search, color: AppColors.grey400),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.grey400),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.background,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          const Divider(height: 1, color: AppColors.divider),

          // Categories Tree List
          Expanded(
            child: categoriesAsync.when(
              data: (rawCategories) {
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
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.category_outlined,
                            size: 64, color: AppColors.grey400),
                        const SizedBox(height: 12),
                        const Text(
                          'Chưa có nhóm hàng nào',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showAddCategoryDialog(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Tạo nhóm đầu tiên'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.white,
                          ),
                        ),
                      ],
                    ),
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
                      child: Text(
                        'Không tìm thấy nhóm hàng phù hợp',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final cat = filtered[index];
                      final count = productCountMap[cat.id] ?? 0;
                      final path = _buildCategoryPath(cat, categories);
                      return _buildCategoryCard(
                        category: cat,
                        count: count,
                        allCategories: categories,
                        subtitlePath: path,
                        products: products,
                      );
                    },
                  );
                }

                // Tree View - include root categories, orphaned categories, and cycle-breakers
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
                    Container(
                      color: AppColors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Tổng cộng: ${categories.length} nhóm',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            key: const Key('collapse_all_categories_button'),
                            onPressed: _expandedCategoryIds.isEmpty
                                ? null
                                : () => setState(
                                    () => _expandedCategoryIds.clear()),
                            icon: const Icon(Icons.unfold_less, size: 15),
                            label: const Text('Thu gọn',
                                style: TextStyle(fontSize: 11.5)),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: _expandedCategoryIds.isEmpty
                                  ? AppColors.grey400
                                  : AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                            ),
                          ),
                          const SizedBox(width: 4),
                          TextButton.icon(
                            key: const Key('expand_all_categories_button'),
                            onPressed: () {
                              final parentIds = categories
                                  .where((c) =>
                                      c.parentId != null &&
                                      c.parentId!.trim().isNotEmpty)
                                  .map((c) => c.parentId!.trim())
                                  .toSet();
                              setState(
                                  () => _expandedCategoryIds.addAll(parentIds));
                            },
                            icon: const Icon(Icons.unfold_more, size: 15),
                            label: const Text('Mở rộng',
                                style: TextStyle(fontSize: 11.5)),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.dividerLight),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        itemCount: rootCategories.length,
                        itemBuilder: (context, index) {
                          final root = rootCategories[index];
                          return _buildTreeNode(
                            node: root,
                            allCategories: categories,
                            productCountMap: productCountMap,
                            products: products,
                            depth: 0,
                            cycleRootIds: cycleRootIds,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text('Lỗi tải nhóm hàng: $err',
                    style: const TextStyle(color: AppColors.danger)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Recursive Tree Node Widget
  Widget _buildTreeNode({
    required Category node,
    required List<Category> allCategories,
    required Map<String, int> productCountMap,
    required List<Product> products,
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
    final count = productCountMap[node.id] ?? 0;
    final clampedDepth = depth > 4 ? 4 : depth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: EdgeInsets.only(
            left: clampedDepth * 12.0,
            top: 4,
            bottom: 4,
          ),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: depth == 0 ? AppColors.border : AppColors.borderLight,
            ),
            boxShadow: depth == 0
                ? [
                    BoxShadow(
                      color: AppColors.black.withOpacity(0.02),
                      offset: const Offset(0, 1),
                      blurRadius: 3,
                    )
                  ]
                : null,
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: hasChildren
                ? InkWell(
                    key: Key('toggle_category_${node.id}'),
                    onTap: () {
                      setState(() {
                        if (_expandedCategoryIds.contains(node.id)) {
                          _expandedCategoryIds.remove(node.id);
                        } else {
                          _expandedCategoryIds.add(node.id);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 22,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                : const SizedBox(
                    width: 24,
                    height: 24,
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: AppColors.textDisabled,
                    ),
                  ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(
                      fontWeight:
                          depth == 0 ? FontWeight.bold : FontWeight.w500,
                      fontSize: depth == 0 ? 14 : 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '$count sản phẩm',
              style: TextStyle(
                fontSize: 11,
                color: count > 0 ? AppColors.primary : AppColors.textTertiary,
                fontWeight: count > 0 ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quick "+" button to add subcategory directly under this node
                IconButton(
                  key: Key('add_child_category_${node.id}'),
                  icon: const Icon(Icons.add_circle_outline,
                      color: AppColors.primary, size: 20),
                  tooltip: 'Thêm nhóm con',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showAddCategoryDialog(
                    context,
                    parentCategory: node,
                  ),
                ),
                const SizedBox(width: 4),
                // Edit button
                IconButton(
                  key: Key('edit_category_${node.id}'),
                  icon: const Icon(Icons.edit_outlined,
                      color: AppColors.textSecondary, size: 18),
                  tooltip: 'Sửa',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showEditCategoryDialog(
                    context,
                    category: node,
                    allCategories: allCategories,
                  ),
                ),
                const SizedBox(width: 4),
                // Delete button
                IconButton(
                  key: Key('delete_category_${node.id}'),
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.danger, size: 18),
                  tooltip: 'Xóa',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDeleteCategory(
                    context,
                    category: node,
                    allCategories: allCategories,
                    productCount: count,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasChildren && isExpanded)
          ...validChildren.map((child) => _buildTreeNode(
                node: child,
                allCategories: allCategories,
                productCountMap: productCountMap,
                products: products,
                depth: depth + 1,
                visitedAncestors: currentAncestors,
                cycleRootIds: cycleRootIds,
              )),
      ],
    );
  }

  // Flat card for search results
  Widget _buildCategoryCard({
    required Category category,
    required int count,
    required List<Category> allCategories,
    required String subtitlePath,
    required List<Product> products,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: Icon(
          category.parentId == null ? Icons.folder : Icons.label_outline,
          color: category.parentId == null
              ? AppColors.primary
              : AppColors.chartTeal,
        ),
        title: Text(
          category.name,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: AppColors.textPrimary),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitlePath.isNotEmpty && subtitlePath != category.name)
              Text(
                subtitlePath,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            Text(
              '$count sản phẩm',
              style: TextStyle(
                fontSize: 11,
                color: count > 0 ? AppColors.primary : AppColors.textTertiary,
                fontWeight: count > 0 ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline,
                  color: AppColors.primary, size: 20),
              tooltip: 'Thêm nhóm con',
              onPressed: () => _showAddCategoryDialog(
                context,
                parentCategory: category,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  color: AppColors.grey400, size: 19),
              tooltip: 'Chỉnh sửa',
              onPressed: () => _showEditCategoryDialog(
                context,
                category: category,
                allCategories: allCategories,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.danger, size: 19),
              tooltip: 'Xóa',
              onPressed: () => _confirmDeleteCategory(
                context,
                category: category,
                allCategories: allCategories,
                productCount: count,
              ),
            ),
          ],
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

  // Dialog: Add category (root or child)
  void _showAddCategoryDialog(BuildContext context,
      {Category? parentCategory}) {
    final nameCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    Category? selectedParent = parentCategory;
    final rawCategories = ref.read(categoryListProvider).valueOrNull ?? [];
    final products = ref.read(productListProvider).valueOrNull ?? [];
    final categoryRepo = ref.read(categoryRepositoryProvider);
    final categories = harvestCategoriesFromProducts(
      rawCategories,
      products,
      syncRepo: categoryRepo,
    );

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.create_new_folder_outlined,
                      color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    selectedParent != null ? 'Thêm nhóm con' : 'Thêm nhóm hàng',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        key: const Key('category_name_input'),
                        controller: nameCtrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Tên nhóm hàng *',
                          hintText: 'Nhập tên nhóm hàng',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Vui lòng nhập tên nhóm hàng';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Nhóm cha trực thuộc:',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            key: const Key('category_parent_dropdown'),
                            isExpanded: true,
                            value: selectedParent?.id,
                            hint: const Text('Không có (Nhóm gốc)'),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Không có (Nhóm gốc)'),
                              ),
                              ...categories
                                  .map((c) => DropdownMenuItem<String?>(
                                        value: c.id,
                                        child: Text(
                                          c.parentId != null
                                              ? '— ${c.name}'
                                              : c.name,
                                          style: TextStyle(
                                            fontWeight: c.parentId == null
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      )),
                            ],
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == null) {
                                  selectedParent = null;
                                } else {
                                  selectedParent =
                                      categories.cast<Category?>().firstWhere(
                                            (c) => c?.id == val,
                                            orElse: () => null,
                                          );
                                }
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Hủy',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  key: const Key('save_category_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final name = nameCtrl.text.trim();
                    final id = generateCategoryId(name, selectedParent?.id);

                    final newCat = Category(
                      id: id,
                      name: name,
                      parentId: selectedParent?.id,
                    );

                    Navigator.pop(dialogCtx);

                    try {
                      await ref.read(categoryRepositoryProvider).upsert(newCat);
                      ref.invalidate(categoryListProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Đã thêm nhóm: $name'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Lỗi thêm nhóm: $e'),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Dialog: Edit category (name and parent)
  void _showEditCategoryDialog(
    BuildContext context, {
    required Category category,
    required List<Category> allCategories,
  }) {
    final nameCtrl = TextEditingController(text: category.name);
    final formKey = GlobalKey<FormState>();

    // Disallow choosing itself or any of its descendants as parent
    final invalidParentIds = <String>{category.id};
    void collectDescendantIds(String parentId) {
      for (final c in allCategories) {
        if (c.parentId == parentId) {
          if (invalidParentIds.add(c.id)) {
            collectDescendantIds(c.id);
          }
        }
      }
    }

    collectDescendantIds(category.id);

    final allowedParents =
        allCategories.where((c) => !invalidParentIds.contains(c.id)).toList();

    Category? selectedParent = allCategories.cast<Category?>().firstWhere(
          (c) => c?.id == category.parentId,
          orElse: () => null,
        );

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.edit, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('Sửa nhóm hàng',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        key: const Key('edit_category_name_input'),
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tên nhóm hàng *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Vui lòng nhập tên nhóm hàng';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Nhóm cha trực thuộc:',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            key: const Key('edit_category_parent_dropdown'),
                            isExpanded: true,
                            value: selectedParent?.id,
                            hint: const Text('Không có (Nhóm gốc)'),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Không có (Nhóm gốc)'),
                              ),
                              ...allowedParents
                                  .map((c) => DropdownMenuItem<String?>(
                                        value: c.id,
                                        child: Text(
                                          c.parentId != null
                                              ? '— ${c.name}'
                                              : c.name,
                                          style: TextStyle(
                                            fontWeight: c.parentId == null
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      )),
                            ],
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == null) {
                                  selectedParent = null;
                                } else {
                                  selectedParent = allowedParents
                                      .cast<Category?>()
                                      .firstWhere(
                                        (c) => c?.id == val,
                                        orElse: () => null,
                                      );
                                }
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Hủy',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  key: const Key('save_edit_category_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final updatedName = nameCtrl.text.trim();
                    final newParentId = selectedParent?.id;

                    Navigator.pop(dialogCtx);

                    final bool nameChanged = updatedName != category.name;
                    final bool parentChanged = newParentId != category.parentId;

                    if (!nameChanged && !parentChanged) {
                      return;
                    }

                    bool loadingShown = false;
                    if (context.mounted) {
                      loadingShown = true;
                      showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (loadingCtx) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    try {
                      final currentProducts =
                          ref.read(productListProvider).valueOrNull ??
                              const <Product>[];

                      final result = await ref
                          .read(cascadeCategoryUpdateUseCaseProvider)
                          .execute(
                            targetCategory: category,
                            newName: updatedName,
                            newParentId: newParentId,
                            allCategories: allCategories,
                            currentProducts: currentProducts,
                          );

                      ref.invalidate(categoryListProvider);
                      ref.invalidate(productListProvider);
                      ref.invalidate(processedProductsProvider);

                      if (context.mounted) {
                        if (loadingShown) {
                          Navigator.of(context, rootNavigator: true).pop();
                          loadingShown = false;
                        }
                        final message = result.updatedProductsCount > 0
                            ? 'Đã cập nhật nhóm hàng và ${result.updatedProductsCount} sản phẩm liên quan'
                            : 'Đã cập nhật: $updatedName';

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(message),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        if (loadingShown) {
                          Navigator.of(context, rootNavigator: true).pop();
                          loadingShown = false;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Lỗi cập nhật: $e'),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Delete category with confirmation & warning dialog
  void _confirmDeleteCategory(
    BuildContext context, {
    required Category category,
    required List<Category> allCategories,
    required int productCount,
  }) {
    final children =
        allCategories.where((c) => c.parentId == category.id).toList();
    final hasChildren = children.isNotEmpty;
    final hasProducts = productCount > 0;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                hasChildren || hasProducts
                    ? Icons.warning_amber_rounded
                    : Icons.delete_outline,
                color: AppColors.danger,
              ),
              const SizedBox(width: 8),
              const Text('Xóa nhóm hàng',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  text: 'Bạn có chắc chắn muốn xóa nhóm hàng ',
                  children: [
                    TextSpan(
                      text: '"${category.name}"',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: '?'),
                  ],
                ),
              ),
              if (hasChildren || hasProducts) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.dangerBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasChildren)
                        Row(
                          children: [
                            const Icon(Icons.info_outline,
                                size: 16, color: AppColors.danger),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Cảnh báo: Có ${children.length} nhóm con trực thuộc!',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      if (hasProducts) ...[
                        if (hasChildren) const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.info_outline,
                                size: 16, color: AppColors.danger),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Cảnh báo: Có $productCount sản phẩm đang thuộc nhóm này!',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Hủy',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              key: const Key('confirm_delete_category_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: AppColors.white,
              ),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                try {
                  await ref
                      .read(categoryRepositoryProvider)
                      .delete(category.id);
                  ref.invalidate(categoryListProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Đã xóa nhóm hàng: ${category.name}'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Lỗi xóa nhóm hàng: $e'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                  }
                }
              },
              child: const Text('Xác nhận xóa'),
            ),
          ],
        );
      },
    );
  }
}
