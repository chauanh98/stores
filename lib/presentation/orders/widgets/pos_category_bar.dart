import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/core/theme/app_colors.dart';

import '../../../application/products/categories_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/product.dart';

class PosCategoryBar extends ConsumerWidget {
  final String selectedCategoryId;
  final void Function(String categoryId, String categoryName)?
      onCategorySelected;

  const PosCategoryBar({
    super.key,
    required this.selectedCategoryId,
    this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoryListProvider);
    final productsAsync = ref.watch(productListProvider);

    final products = productsAsync.value ?? [];
    final categories = categoriesAsync.value ?? [];

    // Danh sách danh mục gồm 'Tất cả' ở đầu và các danh mục lấy từ Firebase
    const allCategory = Category(id: 'all', name: 'Tất cả');
    final displayCategories = [allCategory, ...categories];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: displayCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = displayCategories[index];
          final isSelected = cat.id == selectedCategoryId ||
              (selectedCategoryId.isEmpty && cat.id == 'all');

          // Đếm số lượng sản phẩm đang kinh doanh thuộc nhóm này
          final count = _getCategoryProductCount(cat, products);

          return _buildCategoryChip(
            context: context,
            category: cat,
            count: count,
            isSelected: isSelected,
            onTap: () {
              onCategorySelected?.call(cat.id, cat.name);
            },
          );
        },
      ),
    );
  }

  int _getCategoryProductCount(Category cat, List<Product> products) {
    if (cat.id == 'all') {
      return products.where((p) => p.allowSale).length;
    }
    final catNameLower = cat.name.trim().toLowerCase();
    final catIdLower = cat.id.trim().toLowerCase();

    return products.where((p) {
      if (!p.allowSale) return false;
      final pCatLower = p.category.trim().toLowerCase();
      if (pCatLower == catNameLower || pCatLower == catIdLower) return true;
      // Hỗ trợ trường hợp category phân cấp 'Laptop >> Gaming' hoặc 'Điện thoại'
      if (pCatLower.contains(catNameLower) ||
          catNameLower.contains(pCatLower)) {
        return true;
      }
      return false;
    }).length;
  }

  Widget _buildCategoryChip({
    required BuildContext context,
    required Category category,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final icon = _getCategoryIcon(category);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              category.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.white.withOpacity(0.25)
                    : AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppColors.white : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(Category cat) {
    if (cat.id == 'all') return Icons.grid_view_rounded;
    final lower = cat.name.toLowerCase();
    if (lower.contains('smart') ||
        lower.contains('phone') ||
        lower.contains('thoại')) {
      return Icons.phone_android;
    }
    if (lower.contains('lap') || lower.contains('máy tính')) {
      return Icons.laptop_mac;
    }
    if (lower.contains('tab') || lower.contains('bảng')) {
      return Icons.tablet_android;
    }
    if (lower.contains('head') ||
        lower.contains('tai nghe') ||
        lower.contains('phụ kiện') ||
        lower.contains('access')) {
      return Icons.headphones;
    }
    if (lower.contains('cam')) {
      return Icons.camera_alt;
    }
    if (lower.contains('chuột') || lower.contains('mouse')) {
      return Icons.mouse;
    }
    if (lower.contains('phím') || lower.contains('keyboard')) {
      return Icons.keyboard;
    }
    if (lower.contains('màn') || lower.contains('monitor')) {
      return Icons.monitor;
    }
    return Icons.category_outlined;
  }
}
