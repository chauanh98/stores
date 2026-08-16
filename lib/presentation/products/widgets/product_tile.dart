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

  const ProductTile({super.key, required this.product});

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
      child: ListTile(
        leading: ProductImageThumbnail(
          imageUrl: product.imageUrl,
          productName: product.name,
          categoryName: product.category,
          size: 46,
          borderRadius: 8,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                product.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            if (product.isCombo) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mã: ${product.code}',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            if (product.isCombo && product.comboComponents.isNotEmpty) ...[
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
            const SizedBox(height: 4),
            _buildStockStatus(context, l10n, displayStock),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
            const SizedBox(height: 2),
            Text(
              product.isCombo ? 'Tồn bộ: $displayStock' : 'Tồn: $displayStock',
              style: TextStyle(
                color: product.isCombo ? AppColors.primary : Colors.black87,
                fontWeight:
                    product.isCombo ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
        onTap: () => _navigateToDetail(context),
      ),
    );
  }

  Widget _buildStockStatus(
      BuildContext context, AppLocalizations l10n, int effectiveStock) {
    if (effectiveStock == 0) {
      // Hết hàng - hiển thị cảnh báo đỏ
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
              size: 14,
              color: Colors.red[700],
            ),
            const SizedBox(width: 4),
            Text(
              l10n.needRestock,
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    } else if (effectiveStock < 10) {
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
              size: 14,
              color: Colors.orange[700],
            ),
            const SizedBox(width: 4),
            Text(
              l10n.lowStock,
              style: TextStyle(
                color: Colors.orange[700],
                fontSize: 12,
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
              size: 14,
              color: Colors.green[700],
            ),
            const SizedBox(width: 4),
            Text(
              l10n.inStock,
              style: TextStyle(
                color: Colors.green[700],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
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
