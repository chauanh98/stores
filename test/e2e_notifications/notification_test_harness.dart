import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../support/firebase_test_harness.dart';

// ============================================================================
// 1. DOMAIN ENUMS & CANONICAL ENTITIES
// ============================================================================

enum NotificationCategory {
  orders,
  inventory,
  customers,
  system,
}

enum NotificationType {
  orderCreated('order_created'),
  orderUpdated('order_updated'),
  orderCancelled('order_cancelled'),
  orderReturn('order_return'),
  inventoryImported('inventory_imported'),
  customerCreated('customer_created'),
  customerDebtAdded('customer_debt_added'),
  customerDebtPaid('customer_debt_paid');

  final String value;
  const NotificationType(this.value);

  NotificationCategory get category {
    switch (this) {
      case NotificationType.orderCreated:
      case NotificationType.orderUpdated:
      case NotificationType.orderCancelled:
      case NotificationType.orderReturn:
        return NotificationCategory.orders;
      case NotificationType.inventoryImported:
        return NotificationCategory.inventory;
      case NotificationType.customerCreated:
      case NotificationType.customerDebtAdded:
      case NotificationType.customerDebtPaid:
        return NotificationCategory.customers;
    }
  }

  static NotificationType fromString(String? raw) {
    if (raw == null) return NotificationType.orderCreated;
    final normalized = raw.trim().toLowerCase();
    for (final type in NotificationType.values) {
      if (type.value == normalized) return type;
    }
    return NotificationType.orderCreated;
  }
}

class NotificationItem {
  final String id;
  final String storeId;
  final String title;
  final String body;
  final NotificationType type;
  final bool isRead;
  final DateTime createdAt;
  final String? targetRoute;
  final String? targetId;
  final Map<String, dynamic>? metadata;

  const NotificationItem({
    required this.id,
    required this.storeId,
    required this.title,
    required this.body,
    required this.type,
    this.isRead = false,
    required this.createdAt,
    this.targetRoute,
    this.targetId,
    this.metadata,
  });

  bool get isUnread => !isRead;
  NotificationCategory get category => type.category;

  NotificationItem copyWith({
    String? id,
    String? storeId,
    String? title,
    String? body,
    NotificationType? type,
    bool? isRead,
    DateTime? createdAt,
    String? targetRoute,
    String? targetId,
    Map<String, dynamic>? metadata,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      targetRoute: targetRoute ?? this.targetRoute,
      targetId: targetId ?? this.targetId,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        'title': title,
        'body': body,
        'type': type.value,
        'isRead': isRead,
        'createdAt': createdAt.toIso8601String(),
        if (targetRoute != null) 'targetRoute': targetRoute,
        if (targetId != null) 'targetId': targetId,
        if (metadata != null) 'metadata': metadata,
      };

  factory NotificationItem.fromMap(Map<dynamic, dynamic> map, [String? id]) {
    final effectiveId = id ?? map['id']?.toString() ?? '';
    final rawDate = map['createdAt']?.toString();
    final parsedDate = rawDate != null ? DateTime.tryParse(rawDate) : null;

    Map<String, dynamic>? meta;
    if (map['metadata'] is Map) {
      meta = Map<String, dynamic>.from(map['metadata'] as Map);
    }

    return NotificationItem(
      id: effectiveId,
      storeId: map['storeId']?.toString() ?? 'store_001',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      type: NotificationType.fromString(map['type']?.toString()),
      isRead: map['isRead'] == true ||
          map['isRead']?.toString().toLowerCase() == 'true',
      createdAt: parsedDate ?? DateTime.now(),
      targetRoute: map['targetRoute']?.toString(),
      targetId: map['targetId']?.toString(),
      metadata: meta,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          storeId == other.storeId &&
          isRead == other.isRead &&
          type == other.type &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      id.hashCode ^
      storeId.hashCode ^
      isRead.hashCode ^
      type.hashCode ^
      createdAt.hashCode;
}

// ============================================================================
// 2. LOCAL NOTIFICATIONS SERVICE FAKE
// ============================================================================

class LocalNotificationRecord {
  final int id;
  final String title;
  final String body;
  final String? payload;
  final DateTime timestamp;

  LocalNotificationRecord({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
  }) : timestamp = DateTime.now();
}

class FakeLocalNotificationService {
  final List<LocalNotificationRecord> displayedNotifications = [];
  bool hasPermission = true;

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!hasPermission) return;
    displayedNotifications.add(LocalNotificationRecord(
      id: id,
      title: title,
      body: body,
      payload: payload,
    ));
  }

  void clear() => displayedNotifications.clear();
}

// ============================================================================
// 3. NAVIGATION RECORDER (FOR DEEP LINKING VERIFICATION)
// ============================================================================

class NavigationRecord {
  final String route;
  final String? targetId;
  final BuildContext context;
  final DateTime timestamp;

  NavigationRecord({
    required this.route,
    this.targetId,
    required this.context,
  }) : timestamp = DateTime.now();
}

class NavigationRecorder {
  final List<NavigationRecord> navigations = [];

  void recordNavigation(
    BuildContext context, {
    required String route,
    String? targetId,
  }) {
    if (!context.mounted) return;
    navigations.add(NavigationRecord(
      route: route,
      targetId: targetId,
      context: context,
    ));
  }

  bool hasNavigatedTo(String route, {String? targetId}) {
    return navigations.any((n) =>
        n.route == route && (targetId == null || n.targetId == targetId));
  }

  int countNavigations(String route) {
    return navigations.where((n) => n.route == route).length;
  }

  void clear() => navigations.clear();
}

// ============================================================================
// 4. E2E NOTIFICATION TEST HARNESS
// ============================================================================

class NotificationTestHarness {
  final MockFirebaseDatabase db = MockFirebaseDatabase();
  final FakeLocalNotificationService localNotifications =
      FakeLocalNotificationService();
  final NavigationRecorder navigationRecorder = NavigationRecorder();

  static int _counter = 0;

  static const String storeDongThang = 'store_001';
  static const String storeThoiBinh = 'store_002';

  static const UserAccount adminUser = UserAccount(
    username: 'admin_test',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: storeDongThang,
  );

  static const UserAccount ownerUser = UserAccount(
    username: 'owner_test',
    displayName: 'Chủ sở hữu',
    role: 'owner',
    storeId: storeDongThang,
  );

  static const UserAccount staffUser = UserAccount(
    username: 'staff_test',
    displayName: 'Nhân viên bán hàng',
    role: 'nhanvien',
    storeId: storeDongThang,
  );

  final Map<String, List<NotificationItem>> _notificationsByStore = {
    storeDongThang: [],
    storeThoiBinh: [],
  };

  final Map<String, StreamController<List<NotificationItem>>> _streamControllers =
      {};

  NotificationTestHarness() {
    _streamControllers[storeDongThang] =
        StreamController<List<NotificationItem>>.broadcast();
    _streamControllers[storeThoiBinh] =
        StreamController<List<NotificationItem>>.broadcast();
  }

  void dispose() {
    for (final controller in _streamControllers.values) {
      controller.close();
    }
  }

  List<NotificationItem> getNotifications(String storeId) {
    return List.unmodifiable(_notificationsByStore[storeId] ?? []);
  }

  int getUnreadCount(String storeId) {
    final list = _notificationsByStore[storeId] ?? [];
    return list.where((item) => item.isUnread).length;
  }

  Stream<List<NotificationItem>> watchNotifications(
    String storeId, {
    int limit = 50,
    UserAccount? currentUser,
  }) {
    // RBAC Bandwidth Safety Guard: non-admins never receive stream data
    if (currentUser == null || !currentUser.isAdmin) {
      return Stream.value(<NotificationItem>[]);
    }

    final controller = _streamControllers.putIfAbsent(
      storeId,
      () => StreamController<List<NotificationItem>>.broadcast(),
    );

    // Initial emission respecting limitToLast(50)
    final all = _notificationsByStore[storeId] ?? [];
    final limited = all.length > limit ? all.sublist(all.length - limit) : all;
    // Sort descending by createdAt
    final sorted = List<NotificationItem>.from(limited)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Stream<List<NotificationItem>>.multi((multiController) {
      multiController.add(sorted);
      final sub = controller.stream.listen((items) {
        final lim =
            items.length > limit ? items.sublist(items.length - limit) : items;
        final srt = List<NotificationItem>.from(lim)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        multiController.add(srt);
      });
      multiController.onCancel = () {
        sub.cancel();
      };
    });
  }

  void _notifyStream(String storeId) {
    final list = _notificationsByStore[storeId] ?? [];
    _streamControllers[storeId]?.add(List<NotificationItem>.from(list));
  }

  /// Adds a notification directly and updates mock RTDB and local heads-up alerts.
  Future<void> addNotification(
    NotificationItem notification, {
    bool triggerLocalAlert = true,
    UserAccount? currentUser,
  }) async {
    final storeId = notification.storeId;
    final list = _notificationsByStore.putIfAbsent(storeId, () => []);
    list.add(notification);

    // Write to mock RTDB
    await db
        .ref('stores/$storeId/notifications/${notification.id}')
        .set(notification.toMap());

    _notifyStream(storeId);

    // Free Local Heads-Up alert triggered only for Admin / Owner
    if (triggerLocalAlert && (currentUser?.isAdmin ?? true)) {
      await localNotifications.showNotification(
        id: notification.id.hashCode,
        title: notification.title,
        body: notification.body,
        payload: notification.targetId,
      );
    }
  }

  /// Marks a specific notification as read.
  Future<void> markAsRead(String storeId, String id) async {
    final list = _notificationsByStore[storeId];
    if (list != null) {
      final index = list.indexWhere((item) => item.id == id);
      if (index >= 0) {
        list[index] = list[index].copyWith(isRead: true);
        await db
            .ref('stores/$storeId/notifications/$id')
            .update({'isRead': true});
        _notifyStream(storeId);
      }
    }
  }

  /// Marks all unread notifications in the store as read.
  Future<void> markAllAsRead(String storeId) async {
    final list = _notificationsByStore[storeId];
    if (list != null) {
      final Map<String, dynamic> updates = {};
      for (int i = 0; i < list.length; i++) {
        if (list[i].isUnread) {
          list[i] = list[i].copyWith(isRead: true);
          updates['stores/$storeId/notifications/${list[i].id}/isRead'] = true;
        }
      }
      if (updates.isNotEmpty) {
        await db.ref().update(updates);
      }
      _notifyStream(storeId);
    }
  }

  /// Deletes a notification from RTDB and local store.
  Future<void> deleteNotification(String storeId, String id) async {
    final list = _notificationsByStore[storeId];
    if (list != null) {
      list.removeWhere((item) => item.id == id);
      await db.ref('stores/$storeId/notifications/$id').remove();
      _notifyStream(storeId);
    }
  }

  /// Helper filter by category.
  List<NotificationItem> filterNotifications(
    List<NotificationItem> items,
    NotificationCategory? category,
  ) {
    if (category == null) return items;
    return items.where((item) => item.category == category).toList();
  }

  // --------------------------------------------------------------------------
  // BUSINESS EVENT DISPATCHERS
  // --------------------------------------------------------------------------

  Future<void> dispatchOrderCreated({
    required String storeId,
    required String orderId,
    required double totalAmount,
    required String customerName,
    UserAccount? actor,
  }) async {
    final formatter = NumberFormat('#,###', 'vi_VN');
    final formattedAmount = '${formatter.format(totalAmount)}đ';
    final notif = NotificationItem(
      id: 'NOTIF_ORD_${DateTime.now().millisecondsSinceEpoch}_${_counter++}',
      storeId: storeId,
      title: 'Đơn hàng mới #$orderId',
      body: 'Đơn hàng trị giá $formattedAmount cho khách $customerName',
      type: NotificationType.orderCreated,
      createdAt: DateTime.now(),
      targetRoute: 'invoice_detail',
      targetId: orderId,
      metadata: {
        'orderId': orderId,
        'total': totalAmount,
        'customerName': customerName,
      },
    );
    await addNotification(notif, currentUser: actor);
  }

  Future<void> dispatchOrderUpdated({
    required String storeId,
    required String newOrderId,
    required String originalOrderId,
    required double newTotalAmount,
    UserAccount? actor,
  }) async {
    final formatter = NumberFormat('#,###', 'vi_VN');
    final notif = NotificationItem(
      id: 'NOTIF_VER_${DateTime.now().millisecondsSinceEpoch}_${_counter++}',
      storeId: storeId,
      title: 'Đã sửa hóa đơn #$originalOrderId',
      body:
          'Tạo phiên bản mới #$newOrderId trị giá ${formatter.format(newTotalAmount)}đ',
      type: NotificationType.orderUpdated,
      createdAt: DateTime.now(),
      targetRoute: 'invoice_detail',
      targetId: newOrderId,
      metadata: {
        'newOrderId': newOrderId,
        'originalOrderId': originalOrderId,
      },
    );
    await addNotification(notif, currentUser: actor);
  }

  Future<void> dispatchOrderCancelled({
    required String storeId,
    required String orderId,
    required String reason,
    UserAccount? actor,
  }) async {
    final notif = NotificationItem(
      id: 'NOTIF_CAN_${DateTime.now().millisecondsSinceEpoch}_${_counter++}',
      storeId: storeId,
      title: 'Hủy đơn hàng #$orderId',
      body: 'Lý do: $reason',
      type: NotificationType.orderCancelled,
      createdAt: DateTime.now(),
      targetRoute: 'invoice_detail',
      targetId: orderId,
      metadata: {'orderId': orderId, 'reason': reason},
    );
    await addNotification(notif, currentUser: actor);
  }

  Future<void> dispatchOrderReturned({
    required String storeId,
    required String orderId,
    required String returnId,
    required double refundAmount,
    UserAccount? actor,
  }) async {
    final formatter = NumberFormat('#,###', 'vi_VN');
    final notif = NotificationItem(
      id: 'NOTIF_RET_${DateTime.now().millisecondsSinceEpoch}_${_counter++}',
      storeId: storeId,
      title: 'Khách trả hàng cho đơn #$orderId',
      body: 'Phiếu trả #$returnId • Hoàn tiền: ${formatter.format(refundAmount)}đ',
      type: NotificationType.orderReturn,
      createdAt: DateTime.now(),
      targetRoute: 'invoice_detail',
      targetId: orderId,
      metadata: {'orderId': orderId, 'returnId': returnId},
    );
    await addNotification(notif, currentUser: actor);
  }

  Future<void> dispatchStockInCompleted({
    required String storeId,
    required String receiptId,
    required String importCode,
    required double totalAmount,
    required String supplierName,
    UserAccount? actor,
  }) async {
    final formatter = NumberFormat('#,###', 'vi_VN');
    final notif = NotificationItem(
      id: 'NOTIF_STK_${DateTime.now().millisecondsSinceEpoch}_${_counter++}',
      storeId: storeId,
      title: 'Nhập kho hoàn tất #$importCode',
      body:
          'Nhập từ $supplierName • Tổng tiền: ${formatter.format(totalAmount)}đ',
      type: NotificationType.inventoryImported,
      createdAt: DateTime.now(),
      targetRoute: 'stock_in_detail',
      targetId: importCode,
      metadata: {
        'receiptId': receiptId,
        'importCode': importCode,
        'supplierName': supplierName,
      },
    );
    await addNotification(notif, currentUser: actor);
  }

  Future<void> dispatchCustomerCreated({
    required String storeId,
    required String customerId,
    required String customerName,
    required String customerPhone,
    UserAccount? actor,
  }) async {
    final notif = NotificationItem(
      id: 'NOTIF_CUST_${DateTime.now().millisecondsSinceEpoch}_${_counter++}',
      storeId: storeId,
      title: 'Khách hàng mới: $customerName',
      body: 'Mã: $customerId • SĐT: $customerPhone',
      type: NotificationType.customerCreated,
      createdAt: DateTime.now(),
      targetRoute: 'customer_detail',
      targetId: customerId,
      metadata: {'customerId': customerId, 'phone': customerPhone},
    );
    await addNotification(notif, currentUser: actor);
  }

  Future<void> dispatchCustomerDebtAdded({
    required String storeId,
    required String customerId,
    required String customerName,
    required double debtAmount,
    required String orderId,
    UserAccount? actor,
  }) async {
    final formatter = NumberFormat('#,###', 'vi_VN');
    final notif = NotificationItem(
      id: 'NOTIF_DEBT_${DateTime.now().millisecondsSinceEpoch}_${_counter++}',
      storeId: storeId,
      title: 'Ghi nhận công nợ mới: $customerName',
      body: 'Phát sinh ${formatter.format(debtAmount)}đ từ đơn hàng #$orderId',
      type: NotificationType.customerDebtAdded,
      createdAt: DateTime.now(),
      targetRoute: 'customer_debt',
      targetId: customerId,
      metadata: {
        'customerId': customerId,
        'debtAmount': debtAmount,
        'orderId': orderId,
      },
    );
    await addNotification(notif, currentUser: actor);
  }

  Future<void> dispatchCustomerDebtPaid({
    required String storeId,
    required String customerId,
    required String customerName,
    required double paidAmount,
    required double remainingDebt,
    UserAccount? actor,
  }) async {
    final formatter = NumberFormat('#,###', 'vi_VN');
    final notif = NotificationItem(
      id: 'NOTIF_PAID_${DateTime.now().millisecondsSinceEpoch}_${_counter++}',
      storeId: storeId,
      title: 'Thu nợ khách hàng: $customerName',
      body:
          'Đã thu ${formatter.format(paidAmount)}đ • Nợ còn: ${formatter.format(remainingDebt)}đ',
      type: NotificationType.customerDebtPaid,
      createdAt: DateTime.now(),
      targetRoute: 'customer_debt',
      targetId: customerId,
      metadata: {
        'customerId': customerId,
        'paidAmount': paidAmount,
        'remainingDebt': remainingDebt,
      },
    );
    await addNotification(notif, currentUser: actor);
  }
}

// ============================================================================
// 5. REQUIREMENT-DRIVEN UI CONTRACT WIDGETS
// ============================================================================

/// Reusable Notification Bell action widget for AppBars.
/// - Shows bell icon with reactive unread badge count.
/// - If unreadCount > 99, displays '99+'.
/// - RBAC Guard: If user is not Admin or Owner, returns SizedBox.shrink().
class NotificationBellWidget extends StatelessWidget {
  final UserAccount? user;
  final int unreadCount;
  final VoidCallback onTap;

  const NotificationBellWidget({
    super.key,
    required this.user,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // RBAC Guard: Non-admin staff users see NO bell and zero layout impact
    if (user == null || !user!.isAdmin) {
      return const SizedBox.shrink(key: Key('notification_bell_hidden'));
    }

    final badgeLabel = unreadCount > 99 ? '99+' : unreadCount.toString();

    return Stack(
      key: const Key('notification_bell_visible'),
      alignment: Alignment.center,
      children: [
        IconButton(
          key: const Key('btn_notification_bell'),
          icon: const Icon(Icons.notifications_outlined),
          tooltip: 'Thông báo',
          onPressed: onTap,
        ),
        if (unreadCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              key: const Key('notification_bell_badge'),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                badgeLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

/// Item tile representing an individual notification card.
/// Supports category icons, relative time formatting, unread dot indicator,
/// and swipe-to-delete action via Dismissible.
class NotificationCardWidget extends StatelessWidget {
  final NotificationItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const NotificationCardWidget({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes}p trước';
    if (diff.inHours < 24) return DateFormat('HH:mm').format(dt);
    return DateFormat('dd/MM HH:mm').format(dt);
  }

  IconData _categoryIcon(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.orders:
        return Icons.receipt_long_outlined;
      case NotificationCategory.inventory:
        return Icons.inventory_2_outlined;
      case NotificationCategory.customers:
        return Icons.person_outline;
      case NotificationCategory.system:
        return Icons.info_outline;
    }
  }

  Color _categoryColor(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.orders:
        return AppColors.primary;
      case NotificationCategory.inventory:
        return AppColors.warning;
      case NotificationCategory.customers:
        return AppColors.success;
      case NotificationCategory.system:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _categoryColor(item.category);

    return Dismissible(
      key: Key('dismissible_${item.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        color: AppColors.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: InkWell(
        key: Key('notification_card_${item.id}'),
        onTap: onTap,
        child: Container(
          color: item.isUnread ? AppColors.infoLight.withOpacity(0.15) : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Category Icon Circle
              CircleAvatar(
                backgroundColor: iconColor.withOpacity(0.12),
                radius: 20,
                child: Icon(_categoryIcon(item.category), color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),

              // 2. Content: Title, Body, Timestamp
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: item.isUnread
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.isUnread) ...[
                          const SizedBox(width: 6),
                          Container(
                            key: Key('unread_dot_${item.id}'),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimeAgo(item.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full Notification Center Page / View.
/// Contains category filter chips, Mark all as read button, and reactive list.
class NotificationCenterView extends StatefulWidget {
  final List<NotificationItem> items;
  final VoidCallback onMarkAllAsRead;
  final ValueChanged<NotificationItem> onItemTap;
  final ValueChanged<NotificationItem> onItemDelete;

  const NotificationCenterView({
    super.key,
    required this.items,
    required this.onMarkAllAsRead,
    required this.onItemTap,
    required this.onItemDelete,
  });

  @override
  State<NotificationCenterView> createState() => _NotificationCenterViewState();
}

class _NotificationCenterViewState extends State<NotificationCenterView> {
  NotificationCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final filteredItems = _selectedCategory == null
        ? widget.items
        : widget.items
            .where((i) => i.category == _selectedCategory)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        actions: [
          TextButton(
            key: const Key('btn_mark_all_read'),
            onPressed: widget.onMarkAllAsRead,
            child: const Text('Đọc tất cả'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  key: const Key('chip_filter_all'),
                  label: const Text('Tất cả'),
                  selected: _selectedCategory == null,
                  onSelected: (_) => setState(() => _selectedCategory = null),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  key: const Key('chip_filter_orders'),
                  label: const Text('Hóa đơn'),
                  selected: _selectedCategory == NotificationCategory.orders,
                  onSelected: (_) => setState(() =>
                      _selectedCategory = NotificationCategory.orders),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  key: const Key('chip_filter_inventory'),
                  label: const Text('Nhập kho'),
                  selected:
                      _selectedCategory == NotificationCategory.inventory,
                  onSelected: (_) => setState(() =>
                      _selectedCategory = NotificationCategory.inventory),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  key: const Key('chip_filter_customers'),
                  label: const Text('Khách hàng'),
                  selected:
                      _selectedCategory == NotificationCategory.customers,
                  onSelected: (_) => setState(() =>
                      _selectedCategory = NotificationCategory.customers),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Notification List or Empty State
          Expanded(
            child: filteredItems.isEmpty
                ? const Center(
                    key: Key('notification_empty_state'),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_none_outlined,
                            size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text(
                          'Không có thông báo nào',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    key: const Key('notification_list_view'),
                    itemCount: filteredItems.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 64),
                    itemBuilder: (ctx, index) {
                      final item = filteredItems[index];
                      return NotificationCardWidget(
                        item: item,
                        onTap: () => widget.onItemTap(item),
                        onDelete: () => widget.onItemDelete(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 6. TEST APP BUILDER
// ============================================================================

Widget buildNotificationTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      currentStoreIdProvider.overrideWith((ref) => 'store_001'),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': 'Chi nhánh Đông Thắng',
            'store_002': 'Chi nhánh Thới Bình',
          }),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Scaffold(body: child),
    ),
  );
}
