import 'package:stores/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/stock_in_receipt.dart';
import '../../common/widgets/product_image_thumbnail.dart';

/// Visual Stock-In Item Card matching KiotViet standard and video DATA_IMPORT/video_2026-09-27_07-41-44.mp4 (frame 018, 033).
///
/// Features:
/// - Product thumbnail (48x48 rounded image or placeholder).
/// - Product name and SKU code.
/// - Subtitle: "Tồn kho: X • Giá: [unitPrice]".
/// - Stepper `[-] [qty] [+]` (min 1).
/// - Line total formatted in currency (VND).
/// - Swipe-to-action (`Dismissible`) revealing delete button with confirmation dialog.
/// - Tapping card re-opens `StockInProductEditSheet` for adjustments.
class StockInItemCard extends StatelessWidget {
  final StockInReceiptItem item;
  final int currentStock;
  final ValueChanged<int>? onQuantityChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  final bool isMasked;

  const StockInItemCard({
    super.key,
    required this.item,
    this.currentStock = 0,
    this.onQuantityChanged,
    this.onDelete,
    this.onTap,
    this.isMasked = false,
  });

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('delete_confirmation_dialog'),
        title: const Text('Xác nhận xóa'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Xóa hàng hóa này khỏi phiếu nhập?'),
            SizedBox(height: 6),
            Text(
              'Bạn có chắc muốn xóa mặt hàng này khỏi phiếu nhập?',
              style: TextStyle(fontSize: 12, color: AppColors.grey400),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('btn_cancel_delete'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            key: const Key('btn_confirm_delete'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa', style: TextStyle(color: AppColors.white)),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final formattedPrice =
        isMasked ? '***' : '${currencyFormat.format(item.unitPrice)} đ';
    final formattedTotal =
        isMasked ? '***' : '${currencyFormat.format(item.totalPrice)} đ';

    return Dismissible(
      key: Key('dismissible_${item.productId}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        final confirmed = await _showDeleteConfirmation(context);
        if (confirmed) {
          onDelete?.call();
        }
        return confirmed;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.dangerMedium,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.delete_outline, color: AppColors.white, size: 24),
            SizedBox(width: 4),
            Text(
              'Xóa',
              style: TextStyle(
                color: AppColors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
      child: Card(
        key: Key('item_card_${item.productId}'),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        elevation: 0.8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.grey200),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Product Thumbnail (48x48)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: AppColors.grey100,
                    child: (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                        ? ProductImageThumbnail(
                            imageUrl: item.imageUrl,
                            size: 48,
                          )
                        : const Icon(
                            Icons.inventory_2_outlined,
                            size: 24,
                            color: AppColors.grey400,
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                // 2. Info: Name, SKU, Stock & Price Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName ?? 'Sản phẩm',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textTitle,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      if (item.productCode != null &&
                          item.productCode!.isNotEmpty)
                        Text(
                          'Mã: ${item.productCode} • Tồn kho: $currentStock',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.grey700,
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 3),
                      Text(
                        'Đơn giá: $formattedPrice',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.grey600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // 3. Line Total & Stepper
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 115),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          formattedTotal,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.textHeadline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.borderSubtle),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Decrement button [-]
                              IconButton(
                                key: Key('stepper_dec_${item.productId}'),
                                icon: const Icon(Icons.remove, size: 16),
                                constraints: const BoxConstraints(
                                    minWidth: 28, minHeight: 28),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  minimumSize: const Size(28, 28),
                                  padding: EdgeInsets.zero,
                                ),
                                onPressed: () async {
                                  if (item.quantity > 1) {
                                    onQuantityChanged?.call(item.quantity - 1);
                                  } else {
                                    // Decrement below 1 prompts delete confirmation
                                    final confirmed =
                                        await _showDeleteConfirmation(context);
                                    if (confirmed) {
                                      onDelete?.call();
                                    }
                                  }
                                },
                              ),
                              // Quantity text [qty]
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  '${item.quantity}',
                                  key: Key('stepper_qty_${item.productId}'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppColors.textTitle,
                                  ),
                                ),
                              ),
                              // Increment button [+]
                              IconButton(
                                key: Key('stepper_inc_${item.productId}'),
                                icon: const Icon(Icons.add, size: 16),
                                constraints: const BoxConstraints(
                                    minWidth: 28, minHeight: 28),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  minimumSize: const Size(28, 28),
                                  padding: EdgeInsets.zero,
                                ),
                                onPressed: () {
                                  onQuantityChanged?.call(item.quantity + 1);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Backward compatibility alias for test suites and alternate references.
typedef VisualStockInItemCard = StockInItemCard;
