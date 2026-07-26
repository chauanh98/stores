import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/customer_debt_transaction.dart';
import 'customer_debt_adjustment_page.dart';

class _DebtLedgerItem {
  final String id;
  final String code;
  final DateTime date;
  final double amount;
  final double remainingDebt;
  final String typeLabel;
  final bool isPayment;
  final bool isAdjustment;
  final String? note;

  _DebtLedgerItem({
    required this.id,
    required this.code,
    required this.date,
    required this.amount,
    required this.remainingDebt,
    required this.typeLabel,
    required this.isPayment,
    this.isAdjustment = false,
    this.note,
  });
}

class CustomerDebtPage extends ConsumerStatefulWidget {
  final Customer customer;

  const CustomerDebtPage({super.key, required this.customer});

  @override
  ConsumerState<CustomerDebtPage> createState() => _CustomerDebtPageState();
}

class _CustomerDebtPageState extends ConsumerState<CustomerDebtPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final customersAsync = ref.watch(customerListNotifierProvider);

    final currentCustomer = customersAsync.maybeWhen(
      data: (list) => list.firstWhere(
        (x) => x.id == widget.customer.id,
        orElse: () => widget.customer,
      ),
      orElse: () => widget.customer,
    );

    final ordersAsync = ref.watch(customerOrdersProvider(currentCustomer.id));
    final debtTxsAsync =
        ref.watch(customerDebtTransactionsProvider(currentCustomer.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.customerDebt,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (currentCustomer.name.isNotEmpty)
              Text(
                '${currentCustomer.name} · ${currentCustomer.phone}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.black54,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Header summary: Nợ cần thu
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.debtToCollect,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  '${currencyFormat.format(currentCustomer.displayCurrentDebt)} đ',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          // Combined Ledger List Content
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                return debtTxsAsync.when(
                  data: (debtTxs) {
                    final ledgerItems = <_DebtLedgerItem>[];

                    // Add Order Invoices
                    for (final order in orders) {
                      ledgerItems.add(
                        _DebtLedgerItem(
                          id: order.id,
                          code: order.id,
                          date: order.createdAt,
                          amount: order.total,
                          remainingDebt: order.total,
                          typeLabel: l10n.invoice,
                          isPayment: false,
                        ),
                      );
                    }

                    // Add Payment Receipts and Adjustments
                    for (final tx in debtTxs) {
                      final isPay = tx.type == DebtTransactionType.payment;
                      final isAdj = tx.type == DebtTransactionType.adjustment;
                      ledgerItems.add(
                        _DebtLedgerItem(
                          id: tx.id,
                          code: tx.code,
                          date: tx.date,
                          amount: tx.amount,
                          remainingDebt: tx.remainingDebt,
                          typeLabel: isPay ? l10n.payment : l10n.adjustment,
                          isPayment: isPay,
                          isAdjustment: isAdj,
                          note: tx.note,
                        ),
                      );
                    }

                    // Sort latest first
                    ledgerItems.sort((a, b) => b.date.compareTo(a.date));

                    return Column(
                      children: [
                        // Count Bar
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          color: AppColors.background,
                          child: Text(
                            '${ledgerItems.length} giao dịch',
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black54),
                          ),
                        ),

                        // List
                        Expanded(
                          child: ledgerItems.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                          Icons.account_balance_wallet_outlined,
                                          size: 56,
                                          color: Colors.grey),
                                      const SizedBox(height: 12),
                                      Text(
                                        l10n.noDebtData,
                                        style: const TextStyle(
                                            fontSize: 16, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  itemCount: ledgerItems.length,
                                  itemBuilder: (context, index) {
                                    final item = ledgerItems[index];
                                    final dateStr =
                                        DateFormat('dd/MM/yyyy HH:mm')
                                            .format(item.date);

                                    final isNegative = item.amount < 0;
                                    final amountText = isNegative
                                        ? '-${currencyFormat.format(item.amount.abs())}'
                                        : currencyFormat.format(item.amount);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border:
                                            Border.all(color: AppColors.border),
                                      ),
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    item.code,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 15,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  InkWell(
                                                    onTap: () {
                                                      Clipboard.setData(
                                                          ClipboardData(
                                                              text: item.code));
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                            content: Text(l10n
                                                                .copyCodeSuccess(
                                                                    item.code))),
                                                      );
                                                    },
                                                    child: const Padding(
                                                      padding:
                                                          EdgeInsets.all(4.0),
                                                      child: Icon(
                                                          Icons.copy_rounded,
                                                          size: 15,
                                                          color:
                                                              Colors.black45),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                amountText,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  color: item.isPayment
                                                      ? Colors.green
                                                      : Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                dateStr,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              Row(
                                                children: [
                                                  Text(
                                                    l10n.remainingDebtLabel(
                                                        currencyFormat.format(
                                                            item.remainingDebt)),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                  if (item.isPayment) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.green
                                                            .withOpacity(0.08),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: Text(
                                                        item.typeLabel,
                                                        style: const TextStyle(
                                                          color: Colors.green,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                          if (item.note != null &&
                                              item.note!.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              item.note!,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, _) =>
                      Center(child: Text('${l10n.importError}: $err')),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text('${l10n.importError}: $err')),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SafeArea(
          child: Row(
            children: [
              // Nút [Điều chỉnh]
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CustomerDebtAdjustmentPage(
                            customer: currentCustomer),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    l10n.adjustment,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Nút [Thanh toán]
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      _showPaymentOptionsBottomSheet(context, currentCustomer),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    l10n.payment,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPaymentOptionsBottomSheet(BuildContext context, Customer customer) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.qr_code_2, color: AppColors.primary),
                ),
                title: Text(
                  l10n.createQr,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showQrCodeDialog(context, customer);
                },
              ),
              const Divider(color: AppColors.divider, height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt, color: Colors.green),
                ),
                title: Text(
                  l10n.createReceipt,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCreateReceiptDialog(context, customer);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showQrCodeDialog(BuildContext context, Customer customer) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.qrTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child:
                    Icon(Icons.qr_code_2, size: 140, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              customer.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.amountToPayLabel(
                  currencyFormat.format(customer.displayCurrentDebt)),
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  void _showCreateReceiptDialog(BuildContext context, Customer customer) {
    final l10n = AppLocalizations.of(context)!;
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.createReceiptTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.currentDebt}: ${currencyFormat.format(customer.displayCurrentDebt)} đ',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CurrencyInputFormatter(),
              ],
              decoration: InputDecoration(
                labelText: l10n.receiptAmount,
                hintText: 'Ví dụ: 1.000.000',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: l10n.note,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final text = amountController.text
                  .trim()
                  .replaceAll('.', '')
                  .replaceAll(',', '');
              final payAmount = double.tryParse(text);
              if (payAmount == null || payAmount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.invalidAmount)),
                );
                return;
              }

              final newDebt = (customer.displayCurrentDebt - payAmount)
                  .clamp(0.0, double.infinity);

              final txId = 'TTHD_${DateTime.now().millisecondsSinceEpoch}';
              final txCode =
                  'TTHD${DateFormat('yyMMddHHmm').format(DateTime.now())}';

              final debtTx = CustomerDebtTransaction(
                id: txId,
                code: txCode,
                customerId: customer.id,
                date: DateTime.now(),
                amount: -payAmount,
                remainingDebt: newDebt,
                type: DebtTransactionType.payment,
                note: noteController.text.trim().isNotEmpty
                    ? noteController.text.trim()
                    : l10n.paymentNoteDefault,
              );

              await ref
                  .read(customerRemoteDataSourceProvider)
                  .saveDebtTransaction(customer.id, debtTx.toMap());

              final updated = customer.copyWith(currentDebt: newDebt);
              await ref.read(customerRepositoryProvider).upsert(updated);

              if (context.mounted) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.receiptCreatedSuccess(
                        currencyFormat.format(payAmount))),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text(l10n.saveReceipt),
          ),
        ],
      ),
    );
  }
}
