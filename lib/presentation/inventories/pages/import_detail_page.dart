import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/product.dart';

class ImportDetailPage extends StatelessWidget {
  const ImportDetailPage({super.key, required this.tx, required this.product});

  final InventoryTransaction tx;
  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.importDetail),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.successLight,
                        border: Border.all(color: AppColors.success),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(l10n.import,
                          style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _row(theme, "ID", '#${tx.id}'),
                _row(theme, l10n.products, product.name),
                _row(theme, l10n.productId, product.id),
                _row(theme, l10n.date, _fmt(tx.date)),
                _row(theme, l10n.quantity, '${tx.quantity}'),
                if (tx.importPrice != null)
                  _row(theme, l10n.importPrice,
                      tx.importPrice!.toStringAsFixed(0)),
                _row(theme, l10n.performedBy,
                    tx.createdByName ?? tx.createdBy ?? '—'),
                if (tx.note.isNotEmpty) _row(theme, l10n.note, tx.note),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
