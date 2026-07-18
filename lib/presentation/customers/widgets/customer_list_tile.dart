import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../domain/entities/customer.dart';
import '../pages/customer_detail_page.dart';

class CustomerListTile extends StatelessWidget {
  final Customer customer;

  const CustomerListTile({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final subtitleParts = <String>[];
    if (customer.phone.isNotEmpty) subtitleParts.add(customer.phone);
    if (customer.email.isNotEmpty) subtitleParts.add(customer.email);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
            child: Text(customer.name.isNotEmpty
                ? customer.name[0].toUpperCase()
                : '?')),
        title: Text(
          customer.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle:
            subtitleParts.isNotEmpty ? Text(subtitleParts.join('\n')) : null,
        isThreeLine: subtitleParts.length > 1,
        trailing: Text(
          '${customer.purchases.length}\n${l10n.products}',
          textAlign: TextAlign.center,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => CustomerDetailPage(customer: customer)),
        ),
      ),
    );
  }
}
