import 'package:stores/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Pinned sticky bottom summary bar widget for the Stock-In Cart (Step 1).
/// Matches KiotViet standard and video DATA_IMPORT/video_2026-09-27_07-41-44.mp4 (frame 018).
///
/// Displays:
/// - "Tổng tiền hàng: [totalAmount]"
/// - "[N] mặt hàng • Số lượng: [totalQty]"
/// - Side-by-side action buttons: "Lưu tạm" (outlined) & "Tiếp tục" (solid primary).
class StickyBottomSummaryBar extends StatelessWidget {
  final double totalAmount;
  final int itemCount;
  final int totalQuantity;
  final VoidCallback onSaveDraft;
  final VoidCallback onContinue;
  final bool isEnabled;

  const StickyBottomSummaryBar({
    super.key,
    required this.totalAmount,
    required this.itemCount,
    required this.totalQuantity,
    required this.onSaveDraft,
    required this.onContinue,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final bool canProceed = isEnabled && itemCount > 0;

    return Container(
      key: const Key('sticky_bottom_summary_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: "Tổng tiền hàng" and "X mặt hàng • Số lượng: Y"
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Tổng tiền hàng',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${currencyFormat.format(totalAmount)} đ',
                          key: const Key('bottom_bar_total_amount'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppColors.primaryAction,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '$itemCount mặt hàng • Số lượng: $totalQuantity',
                    key: const Key('bottom_bar_item_count'),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      color: AppColors.textBodyDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Row 2: Action buttons "Lưu tạm" & "Tiếp tục"
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('btn_save_draft'),
                    onPressed: isEnabled ? onSaveDraft : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 8),
                      side: BorderSide(
                        color: isEnabled
                            ? AppColors.primaryAction
                            : AppColors.grey300,
                        width: 1.2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Lưu tạm',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isEnabled
                              ? AppColors.primaryAction
                              : AppColors.grey400,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('btn_continue'),
                    onPressed: canProceed ? onContinue : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryAction,
                      disabledBackgroundColor: AppColors.grey300,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: canProceed ? 1 : 0,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Tiếp tục',
                        style: TextStyle(
                          color:
                              canProceed ? AppColors.white : AppColors.grey500,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
