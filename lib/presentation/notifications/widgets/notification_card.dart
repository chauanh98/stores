import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/notification_item.dart';
import '../../../domain/entities/notification_type.dart';
import '../utils/notification_navigation_handler.dart';

class _CategoryStyle {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;

  const _CategoryStyle({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
  });
}

_CategoryStyle _resolveCategoryStyle(NotificationCategory category) {
  switch (category) {
    case NotificationCategory.orders:
      return const _CategoryStyle(
        icon: Icons.receipt_long_rounded,
        iconColor: AppColors.primary,
        backgroundColor: AppColors.primaryLight,
      );
    case NotificationCategory.inventory:
      return const _CategoryStyle(
        icon: Icons.inventory_2_outlined,
        iconColor: AppColors.warningMedium,
        backgroundColor: AppColors.warningLight,
      );
    case NotificationCategory.customers:
      return const _CategoryStyle(
        icon: Icons.person_outline_rounded,
        iconColor: AppColors.supervisor,
        backgroundColor: AppColors.supervisorLight,
      );
    case NotificationCategory.system:
    default:
      return const _CategoryStyle(
        icon: Icons.notifications_none_outlined,
        iconColor: AppColors.grey600,
        backgroundColor: AppColors.grey100,
      );
  }
}

/// Icon & màu theo TỪNG loại sự kiện (huỷ đơn = đỏ, trả hàng = cam, thu nợ =
/// xanh lá…) để chủ cửa hàng nhận ra mức độ quan trọng chỉ bằng một cái liếc.
_CategoryStyle _resolveTypeStyle(NotificationItem item) {
  switch (item.type) {
    case NotificationType.orderCancelled:
      return const _CategoryStyle(
        icon: Icons.cancel_outlined,
        iconColor: AppColors.danger,
        backgroundColor: AppColors.dangerLight,
      );
    case NotificationType.orderReturn:
      return const _CategoryStyle(
        icon: Icons.assignment_return_outlined,
        iconColor: AppColors.warningDark,
        backgroundColor: AppColors.warningLight,
      );
    case NotificationType.orderUpdated:
      return const _CategoryStyle(
        icon: Icons.edit_note_rounded,
        iconColor: AppColors.info,
        backgroundColor: AppColors.infoLight,
      );
    case NotificationType.customerDebtAdded:
      return const _CategoryStyle(
        icon: Icons.account_balance_wallet_outlined,
        iconColor: AppColors.warningDark,
        backgroundColor: AppColors.warningLight,
      );
    case NotificationType.customerDebtPaid:
      return const _CategoryStyle(
        icon: Icons.payments_outlined,
        iconColor: AppColors.success,
        backgroundColor: AppColors.successLight,
      );
    default:
      return _resolveCategoryStyle(item.category);
  }
}

/// Chặn bấm liên tiếp vào cùng một thông báo (mở trùng bottom sheet).
final Set<String> _notificationTapsInFlight = <String>{};

String formatNotificationRelativeTime(BuildContext context, DateTime dateTime) {
  final l10n = AppLocalizations.of(context);
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.isNegative || difference.inSeconds < 60) {
    return l10n?.notificationsTimeJustNow ?? 'Vừa xong';
  } else if (difference.inMinutes < 60) {
    final minutes = difference.inMinutes;
    return l10n?.notificationsTimeMinutesAgo(minutes) ?? '$minutes phút trước';
  } else if (difference.inHours < 24) {
    final hours = difference.inHours;
    return l10n?.notificationsTimeHoursAgo(hours) ?? '$hours giờ trước';
  } else if (difference.inDays < 7) {
    final days = difference.inDays;
    return l10n?.notificationsTimeDaysAgo(days) ?? '$days ngày trước';
  } else {
    // createdAt lưu UTC => đổi về giờ máy trước khi hiển thị ngày giờ tuyệt đối.
    return DateFormat('dd/MM/yyyy HH:mm').format(dateTime.toLocal());
  }
}

class NotificationCard extends ConsumerWidget {
  final NotificationItem item;
  final VoidCallback? onTap;

  /// Tên ngắn của chi nhánh phát sinh (hiện khi xem "Mọi chi nhánh").
  final String? storeLabel;

  const NotificationCard({
    super.key,
    required this.item,
    this.onTap,
    this.storeLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = _resolveTypeStyle(item);
    final isRead = item.isRead;
    final relativeTime = formatNotificationRelativeTime(context, item.createdAt);

    return Container(
      key: Key('notification_card_container_${item.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isRead ? AppColors.surfaceCard : AppColors.softBlueSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRead ? AppColors.borderLight : AppColors.softBlueBorder,
          width: isRead ? 1.0 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isRead
                ? AppColors.black.withOpacity(0.02)
                : AppColors.primary.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('notification_card_${item.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            if (onTap != null) {
              onTap!();
              return;
            }
            if (!_notificationTapsInFlight.add(item.id)) return;
            try {
              await NotificationNavigationHandler.handleTap(
                context: context,
                ref: ref,
                notification: item,
              );
            } finally {
              _notificationTapsInFlight.remove(item.id);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: style.backgroundColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    style.icon,
                    color: style.iconColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                                color: AppColors.textHeadline,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            relativeTime,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          if (!isRead) ...[
                            const SizedBox(width: 6),
                            Container(
                              key: Key('unread_dot_${item.id}'),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const SizedBox.shrink(
                                key: Key('notification_unread_dot'),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (storeLabel != null && storeLabel!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.storefront_outlined,
                                size: 12, color: AppColors.textMuted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                storeLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textBodyDark,
                          height: 1.3,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
