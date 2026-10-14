import '../../common/utils/number_parsing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/order.dart';

class DebtCollectionDialog extends ConsumerStatefulWidget {
  final Order order;
  final Customer? customer;
  final double remainingDebt;

  const DebtCollectionDialog({
    super.key,
    required this.order,
    this.customer,
    required this.remainingDebt,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Order order,
    Customer? customer,
    required double remainingDebt,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DebtCollectionDialog(
        order: order,
        customer: customer,
        remainingDebt: remainingDebt,
      ),
    );
  }

  @override
  ConsumerState<DebtCollectionDialog> createState() =>
      _DebtCollectionDialogState();
}

class _DebtCollectionDialogState extends ConsumerState<DebtCollectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  String _paymentMethod = 'cash'; // 'cash' or 'transfer'
  bool _isLoading = false;

  final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  @override
  void initState() {
    super.initState();
    final initialAmount = (widget.remainingDebt.isFinite ? widget.remainingDebt.toInt() : 0);
    _amountController = TextEditingController(
      text: _currencyFormat.format(initialAmount),
    );
    _noteController = TextEditingController(
      text: 'Thu nợ hóa đơn ${widget.order.id}',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double get _parsedAmount {
    final digits = _amountController.text.replaceAll(RegExp(r'\D'), '');
    return tryParseFinite(digits) ?? 0.0;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context);
    final amount = _parsedAmount;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n?.orderCollectDebtMinAmountError ??
              'Số tiền thu nợ phải lớn hơn 0đ'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (amount > widget.remainingDebt + 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n?.orderCollectDebtExceedsLimit(
                    _currencyFormat.format(widget.remainingDebt)) ??
                'Số tiền thu không được vượt quá số nợ còn lại (${_currencyFormat.format(widget.remainingDebt)} đ)',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final currentUser = ref.read(authProvider);
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n?.orderCollectDebtLoginRequired ??
              'Vui lòng đăng nhập để thực hiện thu nợ.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final useCase = ref.read(collectInvoiceDebtUseCaseProvider);
      await useCase.execute(
        order: widget.order,
        amount: amount,
        paymentMethod: _paymentMethod,
        currentUser: currentUser,
        note: _noteController.text.trim().isNotEmpty
            ? _noteController.text.trim()
            : null,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n?.orderCollectDebtSuccess(
                      _currencyFormat.format(amount), widget.order.id) ??
                  'Đã thu ${_currencyFormat.format(amount)} đ thành công cho hóa đơn ${widget.order.id}.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                l10n?.orderCollectDebtError(e.toString()) ?? 'Lỗi thu nợ: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final customerName = widget.customer?.name ??
        (widget.order.customerId == 'khach_le' ||
                widget.order.customerId.isEmpty
            ? (l10n?.retailCustomer ?? 'Khách lẻ')
            : widget.order.customerId);
    final customerPhone = widget.customer?.phone ?? '';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        l10n?.orderCollectDebtTitle(widget.order.id) ??
                            'Thu nợ - Hóa đơn ${widget.order.id}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(false),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const Divider(height: 20, color: AppColors.divider),

                // Info Box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.15)),
                  ),
                  child: Column(
                    children: [
                      _buildInfoRow(
                          l10n?.customerLabel ?? 'Khách hàng:', customerName,
                          phone: customerPhone),
                      const SizedBox(height: 6),
                      _buildInfoRow(
                        l10n?.orderCollectTotalInvoice ?? 'Tổng tiền HĐ:',
                        '${_currencyFormat.format(widget.order.total)} đ',
                      ),
                      const SizedBox(height: 6),
                      _buildInfoRow(
                        l10n?.commonTotalPaidAmount ?? 'Đã thanh toán:',
                        '${_currencyFormat.format(widget.order.amountPaid)} đ',
                        color: AppColors.success,
                      ),
                      const SizedBox(height: 6),
                      _buildInfoRow(
                        l10n?.orderCollectRemainingDebt ?? 'Còn ghi nợ:',
                        '${_currencyFormat.format(widget.remainingDebt)} đ',
                        color: AppColors.danger,
                        isBold: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Input Amount
                Text(
                  l10n?.orderCollectAmountFieldLabel ?? 'Số tiền thu (VNĐ) *',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: const Key('debt_collection_amount_field'),
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CurrencyInputFormatter()],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                  decoration: InputDecoration(
                    suffixText: 'đ',
                    suffixStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                    filled: true,
                    fillColor: AppColors.grey50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return l10n?.orderCollectAmountRequired ??
                          'Vui lòng nhập số tiền thu';
                    }
                    final amt = _parsedAmount;
                    if (amt <= 0) {
                      return l10n?.orderCollectAmountMustBeGreaterThanZero ??
                          'Số tiền phải lớn hơn 0';
                    }
                    if (amt > widget.remainingDebt + 0.01) {
                      return l10n?.orderCollectAmountExceedsRemainingDebt ??
                          'Vượt quá số nợ còn lại';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 6),

                // Quick buttons for full collection
                Row(
                  children: [
                    Flexible(
                        child: InkWell(
                      onTap: () {
                        setState(() {
                          _amountController.text = _currencyFormat
                              .format((widget.remainingDebt.isFinite ? widget.remainingDebt.toInt() : 0));
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: Text(
                          l10n?.orderCollectAllDebt ?? 'Thu toàn bộ nợ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    )),
                  ],
                ),
                const SizedBox(height: 14),

                // Payment Method
                Text(
                  l10n?.orderCollectPaymentMethodLabel ??
                      'Phương thức thanh toán *',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _paymentMethod = 'cash'),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _paymentMethod == 'cash'
                                ? AppColors.primary.withOpacity(0.1)
                                : AppColors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _paymentMethod == 'cash'
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: _paymentMethod == 'cash' ? 1.5 : 1.0,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.money,
                                size: 18,
                                color: _paymentMethod == 'cash'
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                  child: Text(
                                l10n?.cash ?? 'Tiền mặt',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: _paymentMethod == 'cash'
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _paymentMethod == 'cash'
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                ),
                              )),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            setState(() => _paymentMethod = 'transfer'),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _paymentMethod == 'transfer'
                                ? AppColors.primary.withOpacity(0.1)
                                : AppColors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _paymentMethod == 'transfer'
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: _paymentMethod == 'transfer' ? 1.5 : 1.0,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.qr_code,
                                size: 18,
                                color: _paymentMethod == 'transfer'
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                  child: Text(
                                l10n?.paymentMethodTransfer ?? 'Chuyển khoản',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: _paymentMethod == 'transfer'
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _paymentMethod == 'transfer'
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                ),
                              )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Note
                Text(
                  l10n?.note ?? 'Ghi chú',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: const Key('debt_collection_note_field'),
                  controller: _noteController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText:
                        l10n?.orderCollectNoteHint ?? 'Nhập ghi chú thu nợ...',
                    filled: true,
                    fillColor: AppColors.grey50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        child: Text(
                          l10n?.orderCollectCancelButton ?? 'Hủy bỏ',
                          style: const TextStyle(color: AppColors.textPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        key: const Key('confirm_debt_collection_button'),
                        onPressed: _isLoading ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.white,
                                ),
                              )
                            : Text(
                                l10n?.orderCollectConfirmButton ??
                                    'Xác nhận thu nợ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    String? phone,
    Color? color,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 2,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                    color: color ?? AppColors.textPrimary,
                  ),
                ),
              ),
              if (phone != null && phone.isNotEmpty) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '($phone)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textTertiary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
