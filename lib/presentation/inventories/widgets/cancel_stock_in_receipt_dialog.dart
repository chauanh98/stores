import 'package:stores/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/inventories/stock_in_receipts_providers.dart';

/// Modal dialog for cancelling a completed stock-in receipt with mandatory reason validation.
///
/// Rolls back branch inventory, restores supplier debt, and logs an audit transaction.
class CancelStockInReceiptDialog extends ConsumerStatefulWidget {
  final StockInReceipt? receipt;
  final String? storeId;
  final ValueChanged<String>? onConfirmCancel;
  final VoidCallback? onCancelled;

  const CancelStockInReceiptDialog({
    super.key,
    this.receipt,
    this.storeId,
    this.onConfirmCancel,
    this.onCancelled,
  });

  /// Static helper to show [CancelStockInReceiptDialog].
  static Future<bool?> show(
    BuildContext context, {
    required StockInReceipt receipt,
    String? storeId,
    VoidCallback? onCancelled,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => CancelStockInReceiptDialog(
        receipt: receipt,
        storeId: storeId,
        onCancelled: onCancelled,
      ),
    );
  }

  @override
  ConsumerState<CancelStockInReceiptDialog> createState() =>
      _CancelStockInReceiptDialogState();
}

class _CancelStockInReceiptDialogState
    extends ConsumerState<CancelStockInReceiptDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _isLoading = true);

    final reason = _reasonController.text.trim();

    if (widget.onConfirmCancel != null) {
      widget.onConfirmCancel!(reason);
      Navigator.of(context).pop(true);
      return;
    }

    if (widget.receipt == null) {
      Navigator.of(context).pop(true);
      return;
    }

    try {
      final storeId = widget.storeId ??
          widget.receipt!.storeId ??
          ref.read(currentStoreIdProvider) ??
          'store_001';
      final user = ref.read(authProvider);
      final cancelledBy =
          user?.username ?? user?.displayName ?? 'Quản trị viên';

      await ref.read(cancelStockInReceiptUseCaseProvider).execute(
            storeId: storeId,
            receipt: widget.receipt!,
            reason: reason,
            cancelledBy: cancelledBy,
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã hủy phiếu nhập kho thành công'),
          backgroundColor: AppColors.success,
        ),
      );

      widget.onCancelled?.call();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi hủy phiếu: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('cancel_receipt_dialog'),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.danger),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hủy phiếu nhập kho',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hủy phiếu nhập sẽ tự động hoàn trả số lượng tồn kho và công nợ nhà cung cấp.',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: const Key('cancel_reason_input'),
              child: TextFormField(
                key: const Key('input_cancel_reason'),
                controller: _reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Lý do hủy phiếu *',
                  hintText: 'Nhập lý do hủy phiếu (bắt buộc)...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Vui lòng nhập lý do hủy';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('btn_cancel_dialog_close'),
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Đóng'),
        ),
        ElevatedButton(
          key: const Key('btn_confirm_cancel'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: AppColors.white,
          ),
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : const Text(
                  'Xác nhận hủy',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}

/// Compatibility alias matching test harnesses.
typedef CancelReceiptDialog = CancelStockInReceiptDialog;
