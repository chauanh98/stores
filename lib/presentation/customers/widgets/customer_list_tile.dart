import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/customer_debt_transaction.dart';
import '../../../domain/entities/order.dart';
import '../pages/customer_detail_page.dart';

class CustomerListTile extends ConsumerWidget {
  final Customer customer;

  const CustomerListTile({super.key, required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    final ordersAsync = ref.watch(customerOrdersProvider(customer.id));
    final debtTxsAsync =
        ref.watch(customerDebtTransactionsProvider(customer.id));

    final orders = ordersAsync.value ?? <Order>[];
    final debtTxs = debtTxsAsync.value ?? <CustomerDebtTransaction>[];

    final displayTotalSales = customer.effectiveTotalSales(orders);
    final displayCurrentDebt = customer.effectiveCurrentDebt(orders, debtTxs);
    final debtToDisplay =
        displayCurrentDebt > 0 ? displayCurrentDebt : customer.displayCurrentDebt;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.1),
          child: Text(
            customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          customer.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Colors.black87,
          ),
        ),
        subtitle: Text(
          customer.phone.isNotEmpty ? customer.phone : l10n.noPhone,
          style: TextStyle(
            color: customer.phone.isNotEmpty ? Colors.black54 : Colors.grey,
            fontSize: 13,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              currencyFormat.format(displayTotalSales),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            if (debtToDisplay > 0)
              Container(
                key: Key('debt_badge_${customer.id}'),
                margin: const EdgeInsets.only(top: 4.0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.dangerLight,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.danger.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 12,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${l10n.customerDebt}: ${currencyFormat.format(debtToDisplay)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CustomerDetailPage(customer: customer),
          ),
        ),
      ),
    );
  }
}
