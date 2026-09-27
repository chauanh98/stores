import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/customer.dart';
import '../pages/customer_detail_page.dart';

class CustomerListTile extends ConsumerWidget {
  final Customer customer;

  const CustomerListTile({super.key, required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    // R1: Eliminate N+1 listeners by directly reading stored customer entity values
    final displayTotalSales = customer.displayTotalSales;
    final debtToDisplay = customer.displayCurrentDebt;

    final user = ref.watch(authProvider);
    final canViewTotalSales = user?.canViewTotalSales ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.primary.withOpacity(0.08),
          child: Text(
            customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
        title: Text(
          customer.name,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          customer.phone.isNotEmpty ? customer.phone : l10n.noPhone,
          style: TextStyle(
            color: customer.phone.isNotEmpty
                ? AppColors.textSecondary
                : AppColors.grey500,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (canViewTotalSales)
                Text(
                  currencyFormat.format(displayTotalSales),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (debtToDisplay > 0)
                Container(
                  key: Key('debt_badge_${customer.id}'),
                  margin: EdgeInsets.only(top: canViewTotalSales ? 4.0 : 0.0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: AppColors.dangerLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.danger.withOpacity(0.3),
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
                      Flexible(
                        child: Text(
                          '${l10n.customerDebt}: ${currencyFormat.format(debtToDisplay)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.danger,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              else if (!canViewTotalSales)
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.textDisabled,
                ),
            ],
          ),
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
