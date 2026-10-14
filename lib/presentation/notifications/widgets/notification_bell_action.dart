import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/auth/auth_providers.dart';
import '../../../../application/notifications/notifications_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../pages/notifications_page.dart';

/// Reusable AppBar action widget displaying a notification bell with a reactive badge.
///
/// Strict RBAC Guard:
/// Completely hidden (returns [SizedBox.shrink]) if the current user is null or not an Admin/Owner.
class NotificationBellAction extends ConsumerWidget {
  final Color? iconColor;

  const NotificationBellAction({
    super.key,
    this.iconColor,
  });

  Future<void> _handleTap(BuildContext context) async {
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    try {
      await navigator.pushNamed('/notifications');
    } catch (_) {
      if (!context.mounted) return;
      await navigator.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/notifications'),
          builder: (context) => const NotificationsPage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Mọi vai trò đăng nhập đều có chuông (nội dung lọc theo quyền).
    final user = ref.watch(authProvider);
    if (user == null) {
      return const SizedBox.shrink();
    }

    // 2. Reactive unread badge count
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final l10n = AppLocalizations.of(context);
    final tooltip = l10n?.notificationsTitle ?? 'Thông báo';

    return IconButton(
      key: const Key('notification_bell_action_button'),
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        backgroundColor: AppColors.danger,
        label: Text(
          unreadCount > 99 ? '99+' : '$unreadCount',
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        child: Icon(
          unreadCount > 0 ? Icons.notifications : Icons.notifications_outlined,
          color: iconColor ?? AppColors.textPrimary,
          size: 24,
        ),
      ),
      tooltip: tooltip,
      onPressed: () => _handleTap(context),
    );
  }
}
