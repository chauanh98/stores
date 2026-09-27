import 'package:stores/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// User decision choice when exiting an in-progress Stock-In session.
enum StockInExitChoice {
  stay,
  exit,
  saveDraft,
}

/// 3-choice exit confirmation dialog for Stock-In receipt flow.
/// Matches KiotViet standard and video DATA_IMPORT/video_2026-09-27_07-41-44.mp4.
class StockInExitDialog extends StatelessWidget {
  final VoidCallback? onSaveDraft;
  final VoidCallback? onExitDiscard;
  final VoidCallback? onStay;

  const StockInExitDialog({
    super.key,
    this.onSaveDraft,
    this.onExitDiscard,
    this.onStay,
  });

  /// Displays the dialog and returns the selected [StockInExitChoice].
  static Future<StockInExitChoice?> show(BuildContext context) {
    return showDialog<StockInExitChoice>(
      context: context,
      builder: (ctx) => StockInExitDialog(
        onStay: () => Navigator.of(ctx).pop(StockInExitChoice.stay),
        onExitDiscard: () => Navigator.of(ctx).pop(StockInExitChoice.exit),
        onSaveDraft: () => Navigator.of(ctx).pop(StockInExitChoice.saveDraft),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('exit_receipt_dialog'),
      title: const Text(
        'Xác nhận thoát',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: const Text(
        'Phiếu nhập kho chưa được hoàn thành. Bạn có muốn lưu tạm để tiếp tục sau không?',
        style: TextStyle(fontSize: 14, height: 1.4),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        // Choice 3: "Ở lại"
        TextButton(
          key: const Key('dialog_choice_stay'),
          onPressed: () {
            if (onStay != null) {
              onStay!();
            } else {
              Navigator.of(context).pop(StockInExitChoice.stay);
            }
          },
          child: const Text('Ở lại'),
        ),
        // Choice 2: "Rời khỏi"
        TextButton(
          key: const Key('dialog_choice_exit'),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: () {
            if (onExitDiscard != null) {
              onExitDiscard!();
            } else {
              Navigator.of(context).pop(StockInExitChoice.exit);
            }
          },
          child: const Text('Rời khỏi'),
        ),
        // Choice 1: "Lưu tạm"
        ElevatedButton(
          key: const Key('dialog_choice_draft'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryAction,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            if (onSaveDraft != null) {
              onSaveDraft!();
            } else {
              Navigator.of(context).pop(StockInExitChoice.saveDraft);
            }
          },
          child: const Text(
            'Lưu tạm',
            style:
                TextStyle(color: AppColors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

/// Backward compatibility alias for test suites and alternate references.
typedef ExitReceiptDialog = StockInExitDialog;
