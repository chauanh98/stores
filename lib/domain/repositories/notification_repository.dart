import '../entities/notification_item.dart';

/// Pure Dart abstract repository contract for managing notifications.
/// Complies with Clean Architecture (no Flutter UI, no Firebase dependencies).
abstract class NotificationRepository {
  /// Watches notifications in real-time for a given store, bounded by [limit] (default 50)
  /// to ensure RTDB bandwidth remains strictly within the 10GB/month free quota.
  Stream<List<NotificationItem>> watchNotifications(String storeId, {int limit = 50});

  /// Adds a new notification to the store's notification collection.
  Future<void> addNotification(NotificationItem notification);

  /// Marks a specific notification as read.
  Future<void> markAsRead({required String storeId, required String id});

  /// Marks all notifications as read for the specified store.
  Future<void> markAllAsRead(String storeId);

  /// Deletes a specific notification from the store.
  Future<void> deleteNotification({required String storeId, required String id});
}
