import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/notifications/notifications_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/store_resolver_helper.dart';
import '../../common/widgets/error_view.dart';
import '../widgets/notification_card.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final Set<String> _locallyDismissedIds = {};

  /// Admin/Owner: xem thông báo của mọi chi nhánh thay vì chỉ chi nhánh đang chọn.
  bool _allStores = false;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controllerState = ref.watch(notificationControllerProvider);
    final isMutating = controllerState.isLoading;
    final selectedFilter = ref.watch(notificationCategoryFilterProvider);

    final hasOtherStores =
        ref.watch(otherAdminNotificationStoreIdsKeyProvider).isNotEmpty;
    final showAllStores = _allStores && hasOtherStores;

    final AsyncValue<List<NotificationItem>> streamAsync;
    final List<NotificationItem> allFiltered;
    final int unreadCount;
    if (showAllStores) {
      // Gộp mọi chi nhánh (dùng chung listener với pop-up, không tải thêm).
      streamAsync = ref.watch(popupNotificationStreamProvider);
      final merged = streamAsync.valueOrNull ?? const <NotificationItem>[];
      allFiltered = selectedFilter == null
          ? merged
          : merged.where((n) => n.category == selectedFilter).toList();
      unreadCount = merged.where((n) => !n.isRead).length;
    } else {
      streamAsync = ref.watch(notificationStreamProvider);
      allFiltered = ref.watch(filteredNotificationsProvider);
      unreadCount = ref.watch(unreadNotificationCountProvider);
    }
    final storeNames = showAllStores
        ? (ref.watch(availableStoresProvider).valueOrNull ??
            const <String, String>{})
        : const <String, String>{};
    final notifications = allFiltered
        .where((item) => !_locallyDismissedIds.contains(item.id))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          l10n?.notificationsTitle ?? 'Thông báo',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.white,
        elevation: 0.5,
        actions: [
          if (isMutating)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),
            )
          else
            KeyedSubtree(
              key: const Key('btn_mark_all_read'),
              child: TextButton.icon(
                key: const Key('notifications_mark_all_read_button'),
                onPressed: unreadCount == 0
                    ? null
                    : () async {
                        try {
                          final controller =
                              ref.read(notificationControllerProvider.notifier);
                          if (showAllStores) {
                            final storeIds = notifications
                                .where((n) => !n.isRead)
                                .map((n) => n.storeId)
                                .where((id) => id.isNotEmpty)
                                .toSet();
                            for (final id in storeIds) {
                              await controller.markAllAsRead(storeId: id);
                            }
                          } else {
                            final storeId = ref.read(currentStoreIdProvider);
                            await controller.markAllAsRead(storeId: storeId);
                          }
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                l10n?.notificationsMarkAllAsReadSuccess ??
                                    'Đã đánh dấu tất cả thông báo là đã đọc',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        } catch (e) {
                          debugPrint(
                              '[NotificationsPage] Mark all read error: $e');
                        }
                      },
                icon: Icon(
                  Icons.done_all_rounded,
                  size: 18,
                  color: unreadCount == 0
                      ? AppColors.textDisabled
                      : AppColors.primary,
                ),
                label: Text(
                  l10n?.notificationsMarkAllAsRead ?? 'Đọc tất cả',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: unreadCount == 0
                        ? AppColors.textDisabled
                        : AppColors.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips Bar
          Container(
            color: AppColors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildCategoryChip(
                    label: l10n?.notificationsFilterAll ?? 'Tất cả',
                    category: null,
                    icon: null,
                    isSelected: selectedFilter == null,
                  ),
                  const SizedBox(width: 8),
                  _buildCategoryChip(
                    label: l10n?.notificationsFilterOrders ?? 'Đơn hàng',
                    category: NotificationCategory.orders,
                    icon: Icons.receipt_long_outlined,
                    isSelected: selectedFilter == NotificationCategory.orders,
                  ),
                  const SizedBox(width: 8),
                  _buildCategoryChip(
                    label: l10n?.notificationsFilterInventory ?? 'Kho hàng',
                    category: NotificationCategory.inventory,
                    icon: Icons.inventory_2_outlined,
                    isSelected: selectedFilter == NotificationCategory.inventory,
                  ),
                  const SizedBox(width: 8),
                  _buildCategoryChip(
                    label: l10n?.notificationsFilterCustomers ?? 'Khách hàng',
                    category: NotificationCategory.customers,
                    icon: Icons.person_outline_rounded,
                    isSelected: selectedFilter == NotificationCategory.customers,
                  ),
                  if (hasOtherStores) ...[
                    const SizedBox(width: 12),
                    Container(width: 1, height: 22, color: AppColors.borderLight),
                    const SizedBox(width: 12),
                    FilterChip(
                      key: const Key('notification_chip_all_stores'),
                      avatar: Icon(
                        Icons.storefront_outlined,
                        size: 16,
                        color: showAllStores
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      label: const Text('Mọi chi nhánh'),
                      selected: showAllStores,
                      showCheckmark: false,
                      onSelected: (v) => setState(() => _allStores = v),
                      selectedColor: AppColors.primaryLight,
                      backgroundColor: AppColors.surface,
                      labelStyle: TextStyle(
                        color: showAllStores
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontWeight:
                            showAllStores ? FontWeight.bold : FontWeight.w500,
                        fontSize: 13,
                      ),
                      side: BorderSide(
                        color: showAllStores
                            ? AppColors.primary
                            : AppColors.borderLight,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.borderLight),

          // Content List
          Expanded(
            child: Builder(
              builder: (context) {
                if (streamAsync.isLoading && streamAsync.valueOrNull == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (streamAsync.hasError && streamAsync.valueOrNull == null) {
                  return ErrorView(
                    streamAsync.error!,
                    onRetry: () => ref.invalidate(notificationStreamProvider),
                  );
                }

                if (notifications.isEmpty) {
                  return Center(
                    key: const Key('notification_empty_state'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: const BoxDecoration(
                              color: AppColors.grey100,
                              shape: BoxShape.circle,
                            ),
                            child: const Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  Icons.notifications_none_outlined,
                                  size: 40,
                                  color: AppColors.grey400,
                                ),
                                Opacity(
                                  opacity: 0,
                                  child: Icon(
                                    Icons.notifications_none_rounded,
                                    size: 40,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n?.notificationsEmpty ?? 'Không có thông báo nào',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textHeadline,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n?.notificationsEmptyDesc ??
                                'Bạn sẽ nhận được thông báo khi có đơn hàng mới, nhập kho hoặc biến động công nợ.',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Gom nhóm theo ngày: "Hôm nay", "Hôm qua", dd/MM/yyyy.
                final entries = _groupByDay(notifications);

                return RefreshIndicator(
                  // Danh sách là realtime: chỉ mở lại listener khi đang lỗi
                  // (mở lại khi đang ổn = tải lại toàn bộ 50 thông báo).
                  onRefresh: () async {
                    if (ref.read(notificationStreamProvider).hasError) {
                      ref.invalidate(notificationStreamProvider);
                    }
                    if (showAllStores &&
                        ref.read(popupNotificationStreamProvider).hasError) {
                      ref.invalidate(popupNotificationStreamProvider);
                    }
                    await Future<void>.delayed(
                        const Duration(milliseconds: 400));
                  },
                  child: ListView.builder(
                    key: const Key('notification_list_view'),
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      if (entry is String) {
                        return _buildDayHeader(entry);
                      }
                      final item = entry as NotificationItem;
                      return Dismissible(
                        key: Key('dismissible_${item.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.delete_outline_rounded,
                                color: AppColors.white,
                                size: 24,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                l10n?.notificationsDeleteSuccess ?? 'Xóa',
                                style: const TextStyle(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onDismissed: (direction) async {
                          final removed = item;
                          setState(() {
                            _locallyDismissedIds.add(removed.id);
                          });

                          try {
                            final storeId = ref.read(currentStoreIdProvider);
                            final effectiveStoreId = removed.storeId.isNotEmpty
                                ? removed.storeId
                                : storeId;
                            await ref
                                .read(notificationControllerProvider.notifier)
                                .deleteNotification(
                                  removed.id,
                                  storeId: effectiveStoreId,
                                );
                          } catch (e) {
                            debugPrint(
                                '[NotificationsPage] Delete notification error: $e');
                          }

                          if (!context.mounted) return;

                          final messenger = ScaffoldMessenger.of(context);
                          messenger.hideCurrentSnackBar();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                l10n?.notificationsDeleteSuccess ??
                                    'Đã xóa thông báo',
                              ),
                              duration: const Duration(seconds: 4),
                              action: SnackBarAction(
                                label: l10n?.notificationsUndo ??
                                    l10n?.commonUndo ??
                                    'Hoàn tác',
                                textColor: AppColors.white,
                                onPressed: () async {
                                  setState(() {
                                    _locallyDismissedIds.remove(removed.id);
                                  });
                                  try {
                                    await ref
                                        .read(notificationControllerProvider
                                            .notifier)
                                        .addNotification(removed);
                                  } catch (e) {
                                    debugPrint(
                                        '[NotificationsPage] Undo error: $e');
                                  }
                                },
                              ),
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: Key('notification_dismiss_${item.id}'),
                          child: NotificationCard(
                            item: item,
                            storeLabel: showAllStores
                                ? StoreResolverHelper.getShortStoreName(
                                    item.storeId,
                                    storeNames: storeNames,
                                  )
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Trả về danh sách phẳng gồm tiêu đề ngày (String) xen kẽ các thông báo.
  List<Object> _groupByDay(List<NotificationItem> items) {
    final sorted = [...items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final result = <Object>[];
    String? lastLabel;
    for (final item in sorted) {
      final local = item.createdAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final String label;
      if (day == today) {
        label = 'Hôm nay';
      } else if (day == yesterday) {
        label = 'Hôm qua';
      } else {
        // Không dùng DateFormat theo locale để không phụ thuộc dữ liệu intl 'vi'.
        const weekdays = [
          'Thứ Hai',
          'Thứ Ba',
          'Thứ Tư',
          'Thứ Năm',
          'Thứ Sáu',
          'Thứ Bảy',
          'Chủ Nhật',
        ];
        String two(int v) => v.toString().padLeft(2, '0');
        label =
            '${weekdays[local.weekday - 1]}, ${two(local.day)}/${two(local.month)}/${local.year}';
      }
      if (label != lastLabel) {
        result.add(label);
        lastLabel = label;
      }
      result.add(item);
    }
    return result;
  }

  Widget _buildDayHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: AppColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildCategoryChip({
    required String label,
    required NotificationCategory? category,
    required IconData? icon,
    required bool isSelected,
  }) {
    final catName = category?.name ?? 'all';
    return KeyedSubtree(
      key: Key('chip_filter_$catName'),
      child: ChoiceChip(
        key: Key('notification_chip_$catName'),
        avatar: icon != null
            ? Icon(
                icon,
                size: 16,
                color:
                    isSelected ? AppColors.primary : AppColors.textSecondary,
              )
            : null,
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          ref.read(notificationCategoryFilterProvider.notifier).state =
              selected ? category : null;
        },
        selectedColor: AppColors.primaryLight,
        backgroundColor: AppColors.surface,
        labelStyle: TextStyle(
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 13,
        ),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.borderLight,
          width: 1.0,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
