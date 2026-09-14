import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/suppliers/suppliers_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../domain/entities/supplier.dart';

class SupplierDebtAdjustmentDialog extends ConsumerStatefulWidget {
  final Supplier supplier;

  const SupplierDebtAdjustmentDialog({super.key, required this.supplier});

  @override
  ConsumerState<SupplierDebtAdjustmentDialog> createState() =>
      _SupplierDebtAdjustmentDialogState();
}

class _SupplierDebtAdjustmentDialogState
    extends ConsumerState<SupplierDebtAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _newDebtController;
  late final TextEditingController _noteController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _newDebtController = TextEditingController(
      text: NumberFormat('#,###', 'vi_VN').format(widget.supplier.currentDebt),
    );
    _noteController = TextEditingController(text: 'Điều chỉnh công nợ NCC');
  }

  @override
  void dispose() {
    _newDebtController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double _parseAmount(String text) {
    final clean = text.replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(clean) ?? 0.0;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final newDebt = _parseAmount(_newDebtController.text);
    setState(() => _isLoading = true);

    try {
      final user = ref.read(authProvider);
      final createdBy = user?.username ?? 'Admin';

      await ref.read(supplierListNotifierProvider.notifier).recordDebtAdjustment(
            supplierId: widget.supplier.id,
            newDebt: newDebt,
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
            'Đã điều chỉnh công nợ ${widget.supplier.name} thành ${NumberFormat('#,###', 'vi_VN').format(newDebt)} đ',
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
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.tune, color: AppColors.warning),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Điều chỉnh công nợ NCC',
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dư nợ hiện tại:'),
                    Text(
                      '${currencyFormat.format(widget.supplier.currentDebt)} đ',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newDebtController,
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Dư nợ mới (VNĐ) *',
                  hintText: 'Nhập giá trị công nợ mới',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit_note),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Vui lòng nhập giá trị nợ mới';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Lý do điều chỉnh',
                  hintText: 'Nhập lý do điều chỉnh công nợ...',
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
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Cập nhật nợ'),
        ),
      ],
    );
  }
}
