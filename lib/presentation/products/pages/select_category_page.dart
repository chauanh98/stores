import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/core/theme/app_colors.dart';

import '../../../application/products/categories_providers.dart';
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

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Chọn nhóm hàng',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
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
              if (newCat != null && mounted) {
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
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                fillColor: Colors.white,
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
              data: (categories) {
                if (categories.isEmpty) {
                  return const Center(child: Text('Chưa có nhóm hàng nào'));
                }

                // If searching, show flat list matching the query
                if (_searchQuery.isNotEmpty) {
                  final filtered = categories.where((c) {
                    return c.name
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase());
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
                final roots =
                    categories.where((c) => c.parentId == null).toList();
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
      Category node, List<Category> allCategories, int depth) {
    final children = allCategories.where((c) => c.parentId == node.id).toList();
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedCategoryIds.contains(node.id);
    final isSelected = widget.initialCategory?.id == node.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            Navigator.pop(context, node);
          },
          child: Container(
            padding: EdgeInsets.only(
              left: (depth * 16.0) + 8.0,
              right: 12,
              top: 10,
              bottom: 10,
            ),
            decoration: BoxDecoration(
              border: const Border(
                  bottom: BorderSide(color: AppColors.surfaceLight)),
              color:
                  isSelected ? AppColors.surfaceHighlight : Colors.transparent,
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
                        color: Colors.black54,
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
                  color: isSelected ? AppColors.primaryMedium : Colors.black45,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                      color:
                          isSelected ? AppColors.primaryDark : Colors.black87,
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
            children: children
                .map((c) => _buildCategoryNode(c, allCategories, depth + 1))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildFlatCategoryItem(
      Category cat, String fullPath, bool isSelected) {
    return ListTile(
      tileColor: isSelected ? AppColors.surfaceHighlight : Colors.white,
      title: Text(
        cat.name,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppColors.primaryDark : Colors.black87,
        ),
      ),
      subtitle: Text(
        fullPath,
        style: const TextStyle(fontSize: 11, color: Colors.black45),
      ),
      trailing:
          isSelected ? const Icon(Icons.check, color: AppColors.primary) : null,
      onTap: () {
        Navigator.pop(context, cat);
      },
    );
  }

  String _buildCategoryPath(Category cat, List<Category> all) {
    final path = <String>[cat.name];
    var current = cat;
    while (current.parentId != null) {
      final parent = all.firstWhere(
        (c) => c.id == current.parentId,
        orElse: () => Category(id: '', name: ''),
      );
      if (parent.id.isEmpty) break;
      path.insert(0, parent.name);
      current = parent;
    }
    return path.join(' >> ');
  }
}
