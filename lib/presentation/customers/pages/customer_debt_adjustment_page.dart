import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/customer_debt_transaction.dart';

class CustomerDebtAdjustmentPage extends ConsumerStatefulWidget {
  final Customer customer;

  const CustomerDebtAdjustmentPage({super.key, required this.customer});

  @override
  ConsumerState<CustomerDebtAdjustmentPage> createState() =>
      _CustomerDebtAdjustmentPageState();
}

class _CustomerDebtAdjustmentPageState
    extends ConsumerState<CustomerDebtAdjustmentPage> {
  late TextEditingController _adjustedDebtController;
  late TextEditingController _noteController;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _adjustedDebtController = TextEditingController();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _adjustedDebtController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(_selectedDate);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          l10n.debtAdjustmentTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nợ hiện tại
            Text(
              l10n.currentDebt,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                currencyFormat.format(widget.customer.displayCurrentDebt),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Giá trị nợ điều chỉnh
            Text(
              l10n.adjustedDebtValue,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _adjustedDebtController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CurrencyInputFormatter(),
              ],
              decoration: InputDecoration(
                hintText: l10n.debtAdjustmentHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),

            // Thời gian
            Text(
              l10n.timeRange,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDateTime,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dateStr,
                      style: const TextStyle(fontSize: 15),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.black54),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Ghi chú
            Text(
              l10n.note,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: l10n.debtAdjustmentNoteHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _isLoading ? null : _submitAdjustment,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      l10n.update,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate != null && mounted) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDate),
      );
      if (pickedTime != null && mounted) {
        setState(() {
          _selectedDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  Future<void> _submitAdjustment() async {
    final l10n = AppLocalizations.of(context)!;
    final text = _adjustedDebtController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseEnterAdjustedDebt)),
      );
      return;
    }

    final newDebt =
        double.tryParse(text.replaceAll(',', '').replaceAll('.', ''));
    if (newDebt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.invalidDebtValue)),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final oldDebt = widget.customer.displayCurrentDebt;
      final amountChange = newDebt - oldDebt;
      final txId = 'DC_${DateTime.now().millisecondsSinceEpoch}';
      final txCode = 'DC${DateFormat('yyMMddHHmm').format(_selectedDate)}';

      final debtTx = CustomerDebtTransaction(
        id: txId,
        code: txCode,
        customerId: widget.customer.id,
        date: _selectedDate,
        amount: amountChange,
        remainingDebt: newDebt,
        type: DebtTransactionType.adjustment,
        note: _noteController.text.trim().isNotEmpty
            ? _noteController.text.trim()
            : l10n.adjustmentNoteDefault,
      );

      await ref
          .read(customerRemoteDataSourceProvider)
          .saveDebtTransaction(widget.customer.id, debtTx.toMap());

      final updated = widget.customer.copyWith(
        currentDebt: newDebt,
        notes: _noteController.text.trim().isNotEmpty
            ? _noteController.text.trim()
            : widget.customer.notes,
      );
      await ref.read(customerRepositoryProvider).upsert(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.debtUpdateSuccess),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${l10n.importError}: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
