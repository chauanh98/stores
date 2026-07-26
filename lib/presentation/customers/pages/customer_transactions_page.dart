import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/orders/orders_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/order.dart';
import '../../common/widgets/error_view.dart';
import '../../common/widgets/loading_indicator.dart';

class CustomerTransactionsPage extends ConsumerWidget {
  final Customer customer;

  const CustomerTransactionsPage({super.key, required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final customerOrdersAsync = ref.watch(customerOrdersProvider(customer.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          l10n.transactions,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
      ),
      body: customerOrdersAsync.when(
        data: (orders) {
          final sortedOrders = List<Order>.from(orders)
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final totalSum = sortedOrders.fold<double>(
            0.0,
            (sum, item) => sum + item.total,
          );

          // If no orders exist in stream yet, fall back to customer.displayTotalSales for display
          final displayTotal =
              totalSum > 0 ? totalSum : customer.displayTotalSales;

          return Column(
            children: [
              // Summary Header Bar
              Container(
                color: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.totalSalesAndReturns,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down,
                            color: Colors.black54),
                      ],
                    ),
                    Text(
                      currencyFormat.format(displayTotal),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),

              // Transaction Count Subheader
              Container(
                width: double.infinity,
                color: AppColors.background,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  '${sortedOrders.length} ${l10n.transactions.toLowerCase()}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
              ),

              // Orders List
              Expanded(
                child: sortedOrders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.receipt_long_outlined,
                                size: 56, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text(
                              l10n.noTransactionsYet,
                              style: const TextStyle(
                                  fontSize: 16, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: sortedOrders.length,
                        itemBuilder: (context, index) {
                          final order = sortedOrders[index];
                          final dateStr = DateFormat('dd/MM/yyyy HH:mm')
                              .format(order.createdAt);
                          final staffName = customer.createdBy ?? 'Khánh Đăng';
                          final itemsSummary =
                              order.items.map((e) => e.productName).join(', ');

                          final paymentMethod = order.id.hashCode % 2 == 0
                              ? l10n.cash
                              : l10n.transfer;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Order ID + Amount
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          order.id,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        InkWell(
                                          onTap: () {
                                            Clipboard.setData(
                                                ClipboardData(text: order.id));
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                  content: Text(l10n
                                                      .copyInvoiceCodeSuccess(
                                                          order.id))),
                                            );
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.all(4.0),
                                            child: Icon(Icons.copy_rounded,
                                                size: 15,
                                                color: Colors.black45),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      currencyFormat.format(order.total),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                // Date + Staff + Payment Method
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '$dateStr · $staffName',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    Text(
                                      paymentMethod,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                                if (itemsSummary.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    itemsSummary,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
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
        loading: () => const LoadingIndicator(),
        error: (err, _) => ErrorView(err),
      ),
    );
  }
}
