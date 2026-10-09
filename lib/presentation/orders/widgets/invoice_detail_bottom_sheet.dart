import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/store_resolver_helper.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/product.dart';
import '../../common/widgets/product_image_thumbnail.dart';
import '../../customers/pages/customer_detail_page.dart';

/// Modal bottom sheet displaying detailed invoice breakdown, customer info,
/// items with discounts/notes, and payment summary.
class InvoiceDetailBottomSheet extends ConsumerWidget {
  final Order order;
  final String? customerName;

  const InvoiceDetailBottomSheet({
    super.key,
    required this.order,
    this.customerName,
  });

  /// Static convenience helper to display the sheet.
  static Future<void> show(
    BuildContext context,
    Order order, {
    String? customerName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (ctx) => InvoiceDetailBottomSheet(
        order: order,
        customerName: customerName,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final l10n = AppLocalizations.of(context);

    final customers =
        ref.watch(customerListNotifierProvider).valueOrNull ?? <Customer>[];
    Customer? targetCustomer;

    final resolvedCustomerName = customerName ?? order.customerName ?? '';
    if (order.customerId != 'khach_le' &&
        order.customerId != 'walk_in' &&
        order.customerId.isNotEmpty) {
      for (final c in customers) {
        if (c.id == order.customerId) {
          targetCustomer = c;
          break;
        }
      }
      targetCustomer ??= Customer(
        id: order.customerId,
        name: resolvedCustomerName,
        phone: order.customerPhone ?? '',
        email: '',
        address: '',
        purchases: const [],
      );
    } else if (resolvedCustomerName.isNotEmpty &&
        resolvedCustomerName != 'Khách lẻ' &&
        resolvedCustomerName != 'Walk-in Customer') {
      for (final c in customers) {
        if (c.name.trim().toLowerCase() ==
            resolvedCustomerName.trim().toLowerCase()) {
          targetCustomer = c;
          break;
        }
      }
    }

    final customerPhone = (targetCustomer?.phone != null &&
            targetCustomer!.phone.trim().isNotEmpty)
        ? targetCustomer.phone.trim()
        : ((order.customerPhone != null &&
                order.customerPhone!.trim().isNotEmpty)
            ? order.customerPhone!.trim()
            : '');

    final products =
        ref.watch(productListProvider).valueOrNull ?? <Product>[];
    final productMap = {for (final p in products) p.id: p};

    return Container(
      padding: const EdgeInsets.all(16),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  order.isCancelled
                      ? (l10n?.orderCancelledDetailTitle ?? 'Hóa đơn đã hủy')
                      : (l10n?.invoiceDetail ?? 'Chi tiết hoá đơn'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(color: AppColors.divider),

          // ── Scrollable Content ──
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cancelled banner if cancelled
                  if (order.isCancelled) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.danger.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.cancel,
                                  color: AppColors.danger, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                l10n?.orderCancelledBanner ??
                                    'HÓA ĐƠN NÀY ĐÃ BỊ HỦY',
                                style: const TextStyle(
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n?.orderCancelReasonLabel(
                                    order.cancelReason ?? '—') ??
                                'Lý do hủy: ${order.cancelReason ?? '—'}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Order ID & Date
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '#${order.id}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        dateFormat.format(order.createdAt),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Store Badge
                  if (order.storeId != null && order.storeId!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        StoreResolverHelper.resolveStoreName(order.storeId),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Customer info section
                  if (resolvedCustomerName.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person_outline,
                                  size: 16, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: targetCustomer != null
                                    ? InkWell(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  CustomerDetailPage(
                                                      customer:
                                                          targetCustomer!),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          resolvedCustomerName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: AppColors.primary,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      )
                                    : Text(
                                        resolvedCustomerName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                          if (customerPhone.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.phone_outlined,
                                  size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 6),
                                Text(
                                  customerPhone,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  key: const Key('copy_customer_phone_button'),
                                  onTap: () {
                                    Clipboard.setData(
                                        ClipboardData(text: customerPhone));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Đã sao chép số điện thoại'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  child: const Icon(Icons.copy,
                                      size: 14, color: AppColors.primary),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Status & Payment
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n?.status ?? 'Trạng thái',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textSecondary)),
                        Text(
                          order.isCancelled
                              ? (l10n?.orderBadgeCancelled ?? 'Đã hủy')
                              : (order.isReturned
                                  ? (l10n?.orderBadgeReturned ?? 'Đã trả hàng')
                                  : (order.status == 'draft'
                                      ? (l10n?.draft ?? 'Phiếu tạm')
                                      : (l10n?.orderBadgeCompleted ??
                                          'Hoàn thành'))),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: order.isCancelled
                                ? AppColors.danger
                                : (order.status == 'draft'
                                    ? AppColors.warning
                                    : AppColors.success),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n?.payment ?? 'Thanh toán',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textSecondary)),
                        Text(
                          order.remainingDebt <= 0.001
                              ? (l10n?.orderPaymentPaidFull ?? 'Đã trả đủ')
                              : (l10n?.orderPaymentUnpaidDebt ?? 'Còn nợ'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: order.remainingDebt <= 0.001
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Products list
                  Text(
                    l10n?.productList ?? 'Danh sách sản phẩm',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...order.items.map((item) {
                    final matchingProduct = productMap[item.productId];
                    final itemSubtotal = item.price * item.quantity;
                    final hasDiscount = item.discount > 0 ||
                        item.effectiveOriginalPrice > item.price;
                    final originalPrice = item.effectiveOriginalPrice;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ProductImageThumbnail(
                            imageUrl: matchingProduct?.primaryImageUrl ??
                                matchingProduct?.imageUrl,
                            productName: item.productName,
                            categoryName: matchingProduct?.category,
                            size: 38,
                            borderRadius: 6,
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
                                  ),
                                ),
                                if (item.note != null &&
                                    item.note!.isNotEmpty) ...[
                                  Text(
                                    item.note!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      '${item.quantity} x ',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    if (hasDiscount) ...[
                                      Text(
                                        '${currencyFormat.format(originalPrice)}đ',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textMuted,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      '${currencyFormat.format(item.price)}đ',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${currencyFormat.format(itemSubtotal)}đ',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(color: AppColors.divider),

                  // Financial summary
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n?.totalPaymentAmount ?? 'Tổng tiền hàng:'),
                        Text(
                          '${currencyFormat.format(order.total)}đ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  if (order.discount > 0) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Giảm giá:'),
                          Text(
                            '-${currencyFormat.format(order.discount)}đ',
                            style: const TextStyle(color: AppColors.danger),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Khách phải trả:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${currencyFormat.format(order.netPayable)}đ',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n?.paid ?? 'Đã thanh toán:'),
                        Text(
                          '${currencyFormat.format(order.amountPaid)}đ',
                        ),
                      ],
                    ),
                  ),
                  if (order.remainingDebt > 0.001) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(l10n?.orderDebtRemaining ?? 'Còn ghi nợ:'),
                          Text(
                            '${currencyFormat.format(order.remainingDebt)}đ',
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
