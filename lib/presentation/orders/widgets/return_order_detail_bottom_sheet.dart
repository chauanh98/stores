import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/return_order.dart';

class ReturnOrderDetailBottomSheet extends ConsumerWidget {
  final Order order;
  final ReturnOrder? returnOrder;
  final Customer? customer;
  final VoidCallback? onViewOriginalInvoice;

  const ReturnOrderDetailBottomSheet({
    super.key,
    required this.order,
    this.returnOrder,
    this.customer,
    this.onViewOriginalInvoice,
  });

  static Future<void> show(
    BuildContext context, {
    required Order order,
    ReturnOrder? returnOrder,
    Customer? customer,
    VoidCallback? onViewOriginalInvoice,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ReturnOrderDetailBottomSheet(
        order: order,
        returnOrder: returnOrder,
        customer: customer,
        onViewOriginalInvoice: onViewOriginalInvoice,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    // Extract return items
    final List<ReturnOrderItem> displayItems;
    if (returnOrder != null && returnOrder!.items.isNotEmpty) {
      displayItems = returnOrder!.items;
    } else {
      final returnedOrderItems =
          order.items.where((i) => i.returnedQuantity > 0).toList();
      if (returnedOrderItems.isNotEmpty) {
        displayItems = returnedOrderItems
            .map(
              (i) => ReturnOrderItem(
                productId: i.productId,
                productName: i.productName,
                price: i.price,
                quantity: i.returnedQuantity,
              ),
            )
            .toList();
      } else {
        // Fallback for full return
        displayItems = order.items
            .map(
              (i) => ReturnOrderItem(
                productId: i.productId,
                productName: i.productName,
                price: i.price,
                quantity: i.quantity,
              ),
            )
            .toList();
      }
    }

    final double totalReturnAmount = returnOrder?.totalReturnAmount ??
        displayItems.fold(
            0.0, (sum, item) => sum + (item.price * item.quantity));
    final double debtDeducted = returnOrder?.debtDeducted ?? 0.0;
    final double cashRefunded =
        returnOrder?.cashRefunded ?? (totalReturnAmount - debtDeducted);

    final String reason =
        returnOrder?.reason ?? order.cancelReason ?? 'Khách trả hàng';
    final String staffName = returnOrder?.createdByName ??
        returnOrder?.createdBy ??
        order.createdByName ??
        order.createdBy ??
        'Nhân viên';
    final DateTime createdAt = returnOrder?.createdAt ?? order.createdAt;
    final String returnId = returnOrder?.id ?? 'TH_${order.id}';

    String paymentMethodLabel = 'Tiền mặt';
    if (returnOrder?.refundPaymentMethod == 'transfer') {
      paymentMethodLabel = 'Chuyển khoản';
    } else if (returnOrder?.refundPaymentMethod == 'debt_deduction' ||
        (debtDeducted > 0 && cashRefunded == 0)) {
      paymentMethodLabel = 'Cấn trừ công nợ';
    } else if (debtDeducted > 0 && cashRefunded > 0) {
      paymentMethodLabel = 'Cấn trừ nợ + Tiền mặt';
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title & Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phiếu trả hàng: $returnId',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(createdAt),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.withOpacity(0.3)),
                ),
                child: const Text(
                  'Đã hoàn tiền',
                  style: TextStyle(
                    color: Colors.purple,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: AppColors.divider),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Linked Original Invoice Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.receipt_long_outlined,
                          color: AppColors.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hóa đơn gốc: #${order.id}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: Colors.black87,
                                ),
                              ),
                              if (customer != null ||
                                  order.customerId.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Khách hàng: ${customer?.name ?? (order.customerId == 'khach_le' ? 'Khách lẻ' : order.customerId)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        TextButton(
                          key: const Key('view_original_invoice_button'),
                          onPressed: () {
                            Navigator.pop(context);
                            if (onViewOriginalInvoice != null) {
                              onViewOriginalInvoice!();
                            }
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Row(
                            children: [
                              Text(
                                'Xem chi tiết',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: AppColors.primary,
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  size: 16, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Returned Items Header
                  const Text(
                    'Danh sách sản phẩm trả lại',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Items List
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayItems.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 12, color: AppColors.divider),
                    itemBuilder: (context, index) {
                      final item = displayItems[index];
                      final itemTotal = item.price * item.quantity;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.purple,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item.quantity} ${item.unit ?? 'cái'} x ${currencyFormat.format(item.price)} đ',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${currencyFormat.format(itemTotal)} đ',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.purple,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Divider(height: 24, color: AppColors.divider),

                  // 3. Financial Breakdown
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        _buildSummaryRow(
                          'Tổng tiền hàng trả',
                          '${currencyFormat.format(totalReturnAmount)} đ',
                          isBold: true,
                          valueColor: Colors.purple,
                        ),
                        if (debtDeducted > 0) ...[
                          const SizedBox(height: 6),
                          _buildSummaryRow(
                            'Cấn trừ công nợ',
                            '- ${currencyFormat.format(debtDeducted)} đ',
                            valueColor: Colors.indigo,
                          ),
                        ],
                        const SizedBox(height: 6),
                        _buildSummaryRow(
                          'Tiền hoàn lại cho khách',
                          '${currencyFormat.format(cashRefunded)} đ',
                          isBold: true,
                          valueColor: Colors.green.shade700,
                        ),
                        const Divider(height: 16, color: AppColors.divider),
                        _buildSummaryRow(
                          'Hình thức hoàn tiền',
                          paymentMethodLabel,
                          valueColor: Colors.black87,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. Return Metadata
                  const Text(
                    'Thông tin bổ sung',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow('Lý do trả hàng', reason),
                        const SizedBox(height: 6),
                        _buildInfoRow('Nhân viên thực hiện', staffName),
                        const SizedBox(height: 6),
                        _buildInfoRow(
                          'Thời gian tạo',
                          DateFormat('dd/MM/yyyy HH:mm:ss').format(createdAt),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Bottom Action Bar
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    key: const Key('view_original_invoice_bottom_button'),
                    onPressed: () {
                      Navigator.pop(context);
                      if (onViewOriginalInvoice != null) {
                        onViewOriginalInvoice!();
                      }
                    },
                    icon: const Icon(Icons.receipt_long,
                        size: 18, color: AppColors.primary),
                    label: const Text(
                      'Xem lại Hóa đơn gốc',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.primary,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: Colors.black54),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
