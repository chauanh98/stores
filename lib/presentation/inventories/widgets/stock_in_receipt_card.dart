import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/store_resolver_helper.dart';
import '../../../application/inventories/stock_in_receipts_providers.dart';

/// Reusable store branch badge displaying branch name and color.
class StoreBadge extends StatelessWidget {
  final String? storeId;
  final String? storeName;

  const StoreBadge({
    super.key,
    required this.storeId,
    this.storeName,
  });

  @override
  Widget build(BuildContext context) {
    final norm = StoreResolverHelper.normalizeStoreId(storeId);
    Color textColor;
    Color bgColor;
    Color borderColor;
    String label;
    IconData iconData;

    if (norm == 'store_001') {
      textColor = AppColors.branchDongThangText;
      bgColor = AppColors.branchDongThangBg;
      borderColor = AppColors.branchDongThangBorder;
      label = storeName ?? 'Chi nhánh Đông Thắng';
      iconData = Icons.storefront_outlined;
    } else if (norm == 'store_002') {
      textColor = AppColors.branchThoiBinhText;
      bgColor = AppColors.branchThoiBinhBg;
      borderColor = AppColors.branchThoiBinhBorder;
      label = storeName ?? 'Chi nhánh Thới Bình';
      iconData = Icons.store_outlined;
    } else {
      textColor = AppColors.primary;
      bgColor = AppColors.primary.withOpacity(0.1);
      borderColor = AppColors.primary.withOpacity(0.25);
      label = storeName ??
          (storeId != null && storeId!.isNotEmpty
              ? 'Chi nhánh $storeId'
              : 'Chi nhánh khác');
      iconData = Icons.storefront_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 12, color: textColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual status badge for Stock-in Receipts: 'Đã hoàn thành', 'Phiếu tạm', 'Đã hủy'.
class StockInReceiptStatusBadge extends StatelessWidget {
  final String status;

  const StockInReceiptStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    Key badgeKey;

    final norm = status.toLowerCase().trim();
    if (norm == 'draft' || norm == 'phiếu tạm') {
      bg = AppColors.receiptDraftBg;
      fg = AppColors.receiptDraftText;
      label = 'Phiếu tạm';
      badgeKey = const Key('badge_draft');
    } else if (norm == 'cancelled' || norm == 'đã hủy') {
      bg = AppColors.receiptCancelledBg;
      fg = AppColors.receiptCancelledText;
      label = 'Đã hủy';
      badgeKey = const Key('badge_cancelled');
    } else {
      bg = AppColors.branchThoiBinhBg;
      fg = AppColors.branchThoiBinhText;
      label = 'Đã hoàn thành';
      badgeKey = const Key('badge_completed');
    }

    return Container(
      key: badgeKey,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Card representing a single stock-in receipt in the list view.
/// Adheres strictly to KiotViet design language and cost price RBAC security.
class StockInReceiptCard extends ConsumerWidget {
  final StockInReceipt receipt;
  final VoidCallback? onTap;
  final VoidCallback? onDeleteDraft;
  final VoidCallback? onLongPress;
  final bool? canViewCostPrice;

  const StockInReceiptCard({
    super.key,
    required this.receipt,
    this.onTap,
    this.onDeleteDraft,
    this.onLongPress,
    this.canViewCostPrice,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool effectiveCanView =
        canViewCostPrice ?? ref.watch(canViewCostPriceProvider);
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    final bool hasDebt =
        (receipt.debtAmount != null && receipt.debtAmount! > 0);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      elevation: 0,
      color: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: Import Code, Date, Status Badge, Branch Badge ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            receipt.importCode.startsWith('#')
                                ? receipt.importCode
                                : '#${receipt.importCode}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            dateFormat.format(receipt.date),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  StockInReceiptStatusBadge(status: receipt.status),
                  const SizedBox(width: 6),
                  Flexible(
                    child: StoreBadge(storeId: receipt.storeId),
                  ),
                  if (receipt.isDraft && onDeleteDraft != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      key: Key('btn_delete_draft_${receipt.id}'),
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: AppColors.danger),
                      tooltip: 'Xóa phiếu tạm',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: onDeleteDraft,
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 8),

              // ── Body: Supplier, Creator, Items Count Badge ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      receipt.supplierName != null &&
                              receipt.supplierName!.isNotEmpty
                          ? receipt.supplierName!
                          : 'Nhà cung cấp lẻ',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.borderLight, width: 0.8),
                      ),
                      child: Text(
                        '${receipt.itemCount} mặt hàng • ${receipt.totalQuantity} sp',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 5),

              // Creator and Note (if any)
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Người nhập: ${receipt.createdByName ?? receipt.createdBy ?? '—'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (receipt.note.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.notes_outlined,
                              size: 13, color: AppColors.textSecondary),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              receipt.note,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 10),
              const Divider(height: 1, color: AppColors.dividerLight),
              const SizedBox(height: 8),

              // ── Footer: Debt Status Badge, Total Monetary Amount, Chevron ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Debt Status Badge
                  Flexible(
                    child: _buildDebtStatusBadge(
                        hasDebt, effectiveCanView, currencyFormat),
                  ),
                  const SizedBox(width: 8),

                  // Total Amount and Chevron
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (effectiveCanView)
                          Flexible(
                            child: Text(
                              key: Key('receipt_total_amount_${receipt.id}'),
                              '${currencyFormat.format(receipt.totalAmount)} đ',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else
                          const Text(
                            '••••••',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                              letterSpacing: 2,
                            ),
                          ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: AppColors.textDisabled,
                        ),
                      ],
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

  Widget _buildDebtStatusBadge(
      bool hasDebt, bool isCostPriceVisible, NumberFormat format) {
    if (receipt.isDraft) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: AppColors.receiptDraftBg,
          borderRadius: BorderRadius.circular(6),
          border:
              Border.all(color: AppColors.warning.withOpacity(0.4), width: 0.8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note, size: 12, color: AppColors.receiptDraftText),
            SizedBox(width: 4),
            Flexible(
              child: Text(
                'Bản nháp (Chưa lưu kho)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.receiptDraftText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    if (receipt.isCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: AppColors.receiptCancelledBg,
          borderRadius: BorderRadius.circular(6),
          border:
              Border.all(color: AppColors.danger.withOpacity(0.4), width: 0.8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel_outlined,
                size: 12, color: AppColors.receiptCancelledText),
            SizedBox(width: 4),
            Flexible(
              child: Text(
                'Đã hủy phiếu',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.receiptCancelledText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    if (hasDebt) {
      final double debt = receipt.debtAmount ?? 0.0;
      final String label = isCostPriceVisible
          ? 'Nợ NCC: ${format.format(debt)} đ'
          : 'Ghi nợ NCC';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(6),
          border:
              Border.all(color: AppColors.warning.withOpacity(0.4), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule_outlined,
                size: 12, color: AppColors.warning),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.receiptDraftText, // Dark amber
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: AppColors.successLight,
          borderRadius: BorderRadius.circular(6),
          border:
              Border.all(color: AppColors.success.withOpacity(0.4), width: 0.8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 12, color: AppColors.success),
            SizedBox(width: 4),
            Flexible(
              child: Text(
                'Đã thanh toán đủ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.branchThoiBinhText, // Dark green
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
  }
}
