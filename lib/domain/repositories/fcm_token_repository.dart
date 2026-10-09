import '../entities/notification_item.dart';

/// Pure Dart domain repository interface for FCM device token persistence
/// and push notification triggering. Adheres strictly to Clean Architecture
/// (Zero Flutter, Zero Firebase imports).
abstract class FcmTokenRepository {
  /// Stores or updates an FCM registration token for an Admin/Owner under:
  /// `stores/$storeId/fcm_tokens/$userId/$tokenId`
  Future<void> saveToken({
    required String storeId,
    required String userId,
    required String token,
    Map<String, dynamic>? deviceInfo,
  });

  /// Deletes a specific device token for an Admin/Owner on logout:
  /// `stores/$storeId/fcm_tokens/$userId/$tokenId`
  Future<void> deleteToken({
    required String storeId,
    required String userId,
    required String token,
  });

  /// Deletes all device tokens registered for a specific user.
  Future<void> clearUserTokens({
    required String storeId,
    required String userId,
  });

  /// Fetches all active FCM tokens belonging to Admin/Owner accounts for a store.
  Future<List<String>> getAdminTokens({
    required String storeId,
  });

  /// Queues or records a push notification event to be delivered to registered Admin devices.
  Future<void> queuePushNotification({
    required String storeId,
    required NotificationItem notification,
    required List<String> targetTokens,
  });
}
