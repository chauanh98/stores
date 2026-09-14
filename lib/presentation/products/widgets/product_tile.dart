import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/theme/app_colors.dart';

import '../../../application/products/products_providers.dart';
import '../../../core/utils/combo_helper.dart';
import '../../../domain/entities/product.dart';
import '../../common/widgets/product_image_thumbnail.dart';
import '../pages/product_detail_page.dart';

class ProductTile extends ConsumerWidget {
  final Product product;
  final VoidCallback? onTap;

  const ProductTile({
    super.key,
    required this.product,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final allProducts = ref.watch(productListProvider).value ?? [];

    final displayStock = product.isCombo
        ? ComboHelper.getTotalAvailableStock(
            product: product, allProducts: allProducts)
        : product.stock;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap ?? () => _navigateToDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductImageThumbnail(
                imageUrl: product.imageUrl,
                productName: product.name,
                categoryName: product.category,
                size: 52,
                borderRadius: 8,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (product.isCombo) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: AppColors.primary.withOpacity(0.3)),
                            ),
                            child: const Text(
                              'COMBO',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Mã: ${product.code}',
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    if (product.isCombo &&
                        product.comboComponents.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Gồm: ${product.comboComponents.map((c) => "${c.quantity}x ${c.productName}").join(", ")}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (product.branchStocks.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.storefront_outlined,
                              size: 13, color: Colors.black45),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _formatBranchStocks(product.branchStocks),
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    _buildStockStatus(context, l10n, displayStock),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatPrice(product.price),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.isCombo
                        ? 'Tồn bộ: $displayStock'
                        : 'Tồn: $displayStock',
                    style: TextStyle(
                      color:
                          product.isCombo ? AppColors.primary : Colors.black87,
                      fontWeight:
                          product.isCombo ? FontWeight.bold : FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStockStatus(
      BuildContext context, AppLocalizations l10n, int effectiveStock) {
    if (effectiveStock <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning,
              size: 13,
              color: Colors.red[700],
            ),
            const SizedBox(width: 4),
            Text(
              'Hết hàng',
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    } else if (product.isLowStock() ||
        effectiveStock <= (product.minStock ?? 5)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber,
              size: 13,
              color: Colors.orange[800],
            ),
            const SizedBox(width: 4),
            Text(
              'Dưới định mức',
              style: TextStyle(
                color: Colors.orange[800],
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              size: 13,
              color: Colors.green[700],
            ),
            const SizedBox(width: 4),
            Text(
              'Còn hàng',
              style: TextStyle(
                color: Colors.green[700],
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
  }

  static String _formatBranchStocks(Map<String, int> branchStocks) {
    if (branchStocks.isEmpty) return '';
    return branchStocks.entries.map((entry) {
      final branchName = _getBranchShortName(entry.key);
      return '$branchName: ${entry.value}';
    }).join(' | ');
  }

  static String _getBranchShortName(String key) {
    final lower = key.trim().toLowerCase();
    if (lower == 'store_001' ||
        lower == 'branch_1' ||
        lower == 'đt' ||
        lower == 'dt' ||
        lower.contains('đông thắng') ||
        lower.contains('dong thang')) {
      return 'ĐT';
    }
    if (lower == 'store_002' ||
        lower == 'branch_2' ||
        lower == 'tb' ||
        lower.contains('thới bình') ||
        lower.contains('thoi binh') ||
        lower.contains('thời bình')) {
      return 'TB';
    }

    // Dynamic short code generation for store_XXX / branch_XXX
    final storeMatch = RegExp(r'^(?:store|branch)[_-]?(\d+)$', caseSensitive: false)
        .firstMatch(key.trim());
    if (storeMatch != null) {
      final numStr = storeMatch.group(1)!;
      final numVal = int.tryParse(numStr) ?? 0;
      return 'CN$numVal';
    }

    // Dynamic acronym for "Chi nhánh X Y" (e.g. "Chi nhánh Cần Thơ" -> "CT")
    if (lower.startsWith('chi nhánh ') || lower.startsWith('chi nhanh ')) {
      final rest = key.trim().substring(10).trim();
      final words =
          rest.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.length >= 2) {
        return words.map((w) => w[0].toUpperCase()).join();
      } else if (rest.isNotEmpty && rest.length <= 3) {
        return rest.toUpperCase();
      }
    }

    return key;
  }

  void _navigateToDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProductDetailPage(product: product),
      ),
    );
  }

  static final NumberFormat _vietnamCurrencyFormat =
      NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

  static String _formatPrice(double v) {
    return _vietnamCurrencyFormat.format(v);
  }
}
