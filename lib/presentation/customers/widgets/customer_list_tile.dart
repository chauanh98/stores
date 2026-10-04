import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/customers/customers_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/customer.dart';
import '../pages/customer_detail_page.dart';

class CustomerListTile extends ConsumerStatefulWidget {
  final Customer customer;
  final VoidCallback? onDeleted;
  final VoidCallback? onDeleteFailed;

  const CustomerListTile({
    super.key,
    required this.customer,
    this.onDeleted,
    this.onDeleteFailed,
  });

  @override
  ConsumerState<CustomerListTile> createState() => _CustomerListTileState();
}

class _CustomerListTileState extends ConsumerState<CustomerListTile> {
  bool _isDismissed = false;

  @override
  void didUpdateWidget(covariant CustomerListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customer.id != widget.customer.id) {
      _isDismissed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDismissed) {
      return const SizedBox.shrink();
    }

    final customer = widget.customer;
    final l10n = context.l10n;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    // Deduct returns from customer total sales if any
    final returnsMap = ref.watch(customerTotalReturnsMapProvider);
    final returnedForCustomer = returnsMap[customer.id] ?? 0.0;

    final rawSales = customer.displayTotalSales;
    final double displayTotalSales;
    if (customer.netSales != null &&
        customer.totalSales != null &&
        customer.netSales! < customer.totalSales!) {
      final alreadyDeducted = (customer.totalSales! - customer.netSales!)
          .clamp(0.0, double.infinity);
      final remainingReturn =
          (returnedForCustomer - alreadyDeducted).clamp(0.0, double.infinity);
      displayTotalSales =
          (rawSales - remainingReturn).clamp(0.0, double.infinity);
    } else {
      displayTotalSales =
          (rawSales - returnedForCustomer).clamp(0.0, double.infinity);
    }

    final debtToDisplay = customer.displayCurrentDebt;

    // Self-healing: persist corrected totalSales & netSales to Firebase if discrepancy exists
    if (returnedForCustomer > 0 &&
        (customer.totalSales ?? 0.0) > displayTotalSales) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(customerRepositoryProvider).upsert(
              customer.copyWith(
                totalSales: displayTotalSales,
                netSales: displayTotalSales,
              ),
            );
      });
    }

    final user = ref.watch(authProvider);
    final canViewTotalSales = user?.canViewTotalSales ?? false;

    final tileCard = Card(
      key: Key('customer_list_tile_${customer.id}'),
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

    return Dismissible(
      key: Key('dismissible_customer_${customer.id}'),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.delete_outline,
          color: AppColors.white,
          size: 24,
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.delete_outline,
          color: AppColors.white,
          size: 24,
        ),
      ),
      confirmDismiss: (direction) async {
        final debt = customer.totalDebt;
        if (debt > 0) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.customerCannotDeleteHasDebtWarning(currencyFormat.format(debt)),
              ),
              backgroundColor: AppColors.danger,
            ),
          );
          return false;
        }

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: Text(l10n.deleteCustomerTitle),
            content: Text(l10n.deleteCustomerConfirm(customer.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        );

        return confirmed ?? false;
      },
      onDismissed: (direction) async {
        setState(() => _isDismissed = true);
        widget.onDeleted?.call();
        final messenger = ScaffoldMessenger.of(context);
        final repo = ref.read(customerRepositoryProvider);
        final listNotifier = ref.read(customerListNotifierProvider.notifier);
        try {
          await repo.delete(customer.id);
          listNotifier.refresh();
          if (messenger.mounted) {
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.customerDeleted)),
            );
          }
        } catch (e) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _isDismissed = false);
            }
            widget.onDeleteFailed?.call();
          });
          if (messenger.mounted) {
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: Text(l10n.customerDeleteError(e.toString())),
                backgroundColor: AppColors.danger,
              ),
            );
          }
        }
      },
      child: tileCard,
    );
  }
}
