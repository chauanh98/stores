import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/suppliers/suppliers_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../domain/entities/supplier.dart';

class SupplierDebtPaymentDialog extends ConsumerStatefulWidget {
  final Supplier supplier;

  const SupplierDebtPaymentDialog({super.key, required this.supplier});

  @override
  ConsumerState<SupplierDebtPaymentDialog> createState() =>
      _SupplierDebtPaymentDialogState();
}

class _SupplierDebtPaymentDialogState
    extends ConsumerState<SupplierDebtPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late final TextEditingController _refCodeController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final defaultAmount = widget.supplier.currentDebt > 0
        ? NumberFormat('#,###', 'vi_VN').format(widget.supplier.currentDebt)
        : '';
    _amountController = TextEditingController(text: defaultAmount);
    _noteController = TextEditingController(text: 'Thanh toán nợ nhà cung cấp');
    _refCodeController = TextEditingController(
      text:
          'PC${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _refCodeController.dispose();
    super.dispose();
  }

  double _parseAmount(String text) {
    final clean = text.replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(clean) ?? 0.0;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = _parseAmount(_amountController.text);
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Số tiền thanh toán phải lớn hơn 0'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = ref.read(authProvider);
      final createdBy = user?.username ?? 'Admin';

      await ref.read(supplierListNotifierProvider.notifier).recordDebtPayment(
            supplierId: widget.supplier.id,
            paymentAmount: amount,
            referenceCode: _refCodeController.text.trim().isNotEmpty
                ? _refCodeController.text.trim()
                : null,
            note: _noteController.text.trim().isNotEmpty
                ? _noteController.text.trim()
                : null,
            createdBy: createdBy,
          );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã ghi nhận trả nợ ${NumberFormat('#,###', 'vi_VN').format(amount)} đ cho ${widget.supplier.name}',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.payment, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Lập phiếu chi trả nợ NCC',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Supplier Summary Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.supplier.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Dư nợ hiện tại:',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '${currencyFormat.format(widget.supplier.currentDebt)} đ',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Payment Amount Input
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Số tiền thanh toán (VNĐ) *',
                  hintText: 'Nhập số tiền trả',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.attach_money),
                  suffixIcon: widget.supplier.currentDebt > 0
                      ? TextButton(
                          onPressed: () {
                            _amountController.text = currencyFormat
                                .format(widget.supplier.currentDebt);
                          },
                          child: const Text(
                            'Trả hết',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      : null,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Vui lòng nhập số tiền';
                  }
                  final parsed = _parseAmount(val);
                  if (parsed <= 0) {
                    return 'Số tiền phải lớn hơn 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Reference Code
              TextFormField(
                controller: _refCodeController,
                decoration: const InputDecoration(
                  labelText: 'Mã chứng từ / Phiếu chi',
                  hintText: 'VD: PC000001',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.receipt_long),
                ),
              ),
              const SizedBox(height: 12),

              // Note
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú thanh toán',
                  hintText: 'Nhập nội dung chi trả...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          onPressed: _isLoading ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
          ),
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : const Icon(Icons.check, size: 18),
          label: const Text('Xác nhận trả nợ'),
        ),
      ],
    );
  }
}
