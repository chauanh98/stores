import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/core/theme/app_colors.dart';

import '../../../application/products/categories_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../core/utils/vietnamese_text_helper.dart';
import '../../../domain/entities/category.dart';
import 'add_category_page.dart';

class SelectCategoryPage extends ConsumerStatefulWidget {
  final Category? initialCategory;

  const SelectCategoryPage({super.key, this.initialCategory});

  @override
  ConsumerState<SelectCategoryPage> createState() => _SelectCategoryPageState();
}

class _SelectCategoryPageState extends ConsumerState<SelectCategoryPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _expandedCategoryIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoryListProvider);
    final productsAsync = ref.watch(productListProvider);
    final categoryRepo = ref.watch(categoryRepositoryProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Chọn nhóm hàng',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppColors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.primary, size: 28),
            tooltip: 'Thêm nhóm mới',
            onPressed: () async {
              final newCat = await Navigator.push<Category>(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddCategoryPage(),
                ),
              );
              if (newCat != null && context.mounted) {
                // Instantly select the newly created category
                Navigator.pop(context, newCat);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm nhóm hàng...',
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
                fillColor: AppColors.white,
                filled: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.borderLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          // List of Categories
          Expanded(
            child: categoriesAsync.when(
              data: (rawCategories) {
                final products = productsAsync.valueOrNull ?? [];
                final categories = harvestCategoriesFromProducts(
                  rawCategories,
                  products,
                  syncRepo: categoryRepo,
                );
                if (categories.isEmpty) {
                  return const Center(child: Text('Chưa có nhóm hàng nào'));
                }

                // If searching, show flat list matching the query
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
                        child: Text('Không tìm thấy nhóm hàng phù hợp'));
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, idx) {
                      final cat = filtered[idx];
                      final isSelected = widget.initialCategory?.id == cat.id;
                      final fullPath = _buildCategoryPath(cat, categories);
                      return _buildFlatCategoryItem(cat, fullPath, isSelected);
                    },
                  );
                }

                // Build tree structure
                final categoryMap = {for (final c in categories) c.id: c};
                final roots = categories
                    .where((c) =>
                        c.parentId == null ||
                        c.parentId!.trim().isEmpty ||
                        !categoryMap.containsKey(c.parentId!.trim()))
                    .toList();
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: roots.length,
                  itemBuilder: (context, index) {
                    final root = roots[index];
                    return _buildCategoryNode(root, categories, 0);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Lỗi: $err')),
            ),
          ),
        ],
      ),
    );
  }

  // Recursive tree node renderer
  Widget _buildCategoryNode(
      Category node, List<Category> allCategories, int depth,
      [Set<String> visitedAncestors = const {}]) {
    final currentAncestors = {...visitedAncestors, node.id};
    final validChildren = allCategories
        .where((c) => c.parentId == node.id && !currentAncestors.contains(c.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final hasChildren = validChildren.isNotEmpty;
    final isExpanded = _expandedCategoryIds.contains(node.id);
    final isSelected = widget.initialCategory?.id == node.id;

    final clampedDepth = depth > 4 ? 4 : depth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            Navigator.pop(context, node);
          },
          child: Container(
            padding: EdgeInsets.only(
              left: (clampedDepth * 16.0) + 8.0,
              right: 12,
              top: 10,
              bottom: 10,
            ),
            decoration: BoxDecoration(
              border: const Border(
                  bottom: BorderSide(color: AppColors.surfaceLight)),
              color: isSelected
                  ? AppColors.surfaceHighlight
                  : AppColors.transparent,
              borderRadius: isSelected ? BorderRadius.circular(6) : null,
            ),
            child: Row(
              children: [
                if (hasChildren)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedCategoryIds.remove(node.id);
                        } else {
                          _expandedCategoryIds.add(node.id);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 26),
                Icon(
                  hasChildren
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 18,
                  color: isSelected
                      ? AppColors.primaryMedium
                      : AppColors.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                      color: isSelected
                          ? AppColors.primaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check, color: AppColors.primary, size: 18),
              ],
            ),
          ),
        ),
        if (hasChildren && isExpanded)
          Column(
            children: validChildren
                .map((c) => _buildCategoryNode(
                    c, allCategories, depth + 1, currentAncestors))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildFlatCategoryItem(
      Category cat, String fullPath, bool isSelected) {
    return ListTile(
      tileColor: isSelected ? AppColors.surfaceHighlight : AppColors.white,
      title: Text(
        cat.name,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
        ),
      ),
      subtitle: fullPath != cat.name
          ? Text(
              fullPath,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textTertiary),
            )
          : null,
      trailing:
          isSelected ? const Icon(Icons.check, color: AppColors.primary) : null,
      onTap: () {
        Navigator.pop(context, cat);
      },
    );
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
