import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../application/reports/overview_kpi_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/order.dart';

/// Sub-widget Feed Giao Dịch Gần Đây (R6 - Recent Activity Feed)
/// Hiển thị 5 đơn hàng / giao dịch phát sinh gần nhất trong ngày với:
/// - Mã đơn hàng
/// - Tên khách hàng (hoặc Khách lẻ)
/// - Tổng tiền
/// - Thời gian phát sinh giao dịch
/// - Badge trạng thái: Hoàn thành (xanh lá), Lưu tạm (cam), Đang giao (xanh dương)
class RecentActivityFeed extends ConsumerWidget {
  const RecentActivityFeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentOrdersAsync = ref.watch(recentOrdersFeedProvider);
    final customersAsync = ref.watch(customerListNotifierProvider);
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    final customersMap = <String, String>{};
    if (customersAsync.hasValue && customersAsync.value != null) {
      for (final c in customersAsync.value!) {
        customersMap[c.id] = c.name;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Giao dịch gần đây',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          recentOrdersAsync.when(
            data: (orders) => _buildOrdersFeed(
              context,
              orders,
              customersMap,
              currencyFormat,
            ),
            loading: () => const SizedBox(
              height: 120,
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (e, _) => SizedBox(
              height: 60,
              child: Center(
                child: Text(
                  'Lỗi tải giao dịch gần đây: $e',
                  style: const TextStyle(
                      color: AppColors.danger, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersFeed(
    BuildContext context,
    List<Order> orders,
    Map<String, String> customersMap,
    NumberFormat format,
  ) {
    if (orders.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: Text(
            'Chưa có đơn hàng nào trong khoảng thời gian này',
            style: TextStyle(color: Colors.black38, fontSize: 12),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: orders.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 16, color: AppColors.divider),
      itemBuilder: (context, index) {
        final order = orders[index];
        final customerName = order.customerId.isNotEmpty
            ? (customersMap[order.customerId] ?? 'Khách #${order.customerId}')
            : 'Khách lẻ';

        final timeStr = _formatRelativeTime(order.createdAt);
        final shortOrderId = order.id.length > 8
            ? order.id.substring(order.id.length - 8).toUpperCase()
            : order.id.toUpperCase();

        return Row(
          children: [
            // Order Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),

            const SizedBox(width: 10),

            // Order info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '#$shortOrderId',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '• $timeStr',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    customerName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Amount & Status Badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${format.format(order.total)} đ',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                _buildStatusBadge(order.status),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color textColor;
    Color bgColor;
    String label;

    switch (status.toLowerCase()) {
      case 'completed':
        textColor = AppColors.success;
        bgColor = AppColors.successLight;
        label = 'Hoàn thành';
        break;
      case 'draft':
      case 'pending':
        textColor = const Color(0xFFD97706);
        bgColor = AppColors.warningLight;
        label = 'Lưu tạm';
        break;
      case 'shipping':
        textColor = AppColors.primary;
        bgColor = AppColors.surfaceInfo;
        label = 'Đang giao';
        break;
      case 'cancelled':
        textColor = AppColors.danger;
        bgColor = AppColors.dangerLight;
        label = 'Đã hủy';
        break;
      default:
        textColor = Colors.black54;
        bgColor = Colors.grey.shade100;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'Vừa xong';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}p trước';
    } else if (diff.inHours < 24 && dateTime.day == now.day) {
      return DateFormat('HH:mm').format(dateTime);
    } else {
      return DateFormat('dd/MM HH:mm').format(dateTime);
    }
  }
}
