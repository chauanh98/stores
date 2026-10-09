import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/fcm_token_repository.dart';
import '../datasources/firebase/fcm_remote_data_source.dart';

/// Concrete implementation of [FcmTokenRepository] delegating to [FcmRemoteDataSource].
class FcmTokenRepositoryImpl implements FcmTokenRepository {
  final FcmRemoteDataSource _remoteDataSource;

  FcmTokenRepositoryImpl(this._remoteDataSource);

  @override
  Future<void> saveToken({
    required String storeId,
    required String userId,
    required String token,
    Map<String, dynamic>? deviceInfo,
  }) {
    return _remoteDataSource.saveToken(
      storeId: storeId,
      userId: userId,
      token: token,
      deviceInfo: deviceInfo,
    );
  }

  @override
  Future<void> deleteToken({
    required String storeId,
    required String userId,
    required String token,
  }) {
    return _remoteDataSource.deleteToken(
      storeId: storeId,
      userId: userId,
      token: token,
    );
  }

  @override
  Future<void> clearUserTokens({
    required String storeId,
    required String userId,
  }) {
    return _remoteDataSource.clearUserTokens(
      storeId: storeId,
      userId: userId,
    );
  }

  @override
  Future<List<String>> getAdminTokens({
    required String storeId,
  }) {
    return _remoteDataSource.getAdminTokens(storeId: storeId);
  }

  @override
  Future<void> queuePushNotification({
    required String storeId,
    required NotificationItem notification,
    required List<String> targetTokens,
  }) {
    final payload = <String, dynamic>{
      'id': notification.id,
      'notificationId': notification.id,
      'storeId': storeId,
      'title': notification.title,
      'body': notification.body,
      'type': notification.type.value,
      if (notification.targetRoute != null)
        'targetRoute': notification.targetRoute!,
      if (notification.targetId != null)
        'targetId': notification.targetId!,
      'targetTokens': targetTokens,
      'priority': 'high',
      'channel_id': 'store_notifications_channel',
      'channelId': 'store_notifications_channel',
      'sound': 'default',
      'vibrate': true,
      'android': {
        'priority': 'high',
        'notification': {
          'channel_id': 'store_notifications_channel',
          'sound': 'default',
          'default_sound': true,
          'default_vibrate_timings': true,
        },
      },
      'apns': {
        'headers': {
          'apns-priority': '10',
          'apns-push-type': 'alert',
        },
        'payload': {
          'aps': {
            'alert': {
              'title': notification.title,
              'body': notification.body,
            },
            'badge': 1,
            'sound': 'default',
            'content-available': 1,
          },
        },
      },
      'data': {
        'id': notification.id,
        'notificationId': notification.id,
        'storeId': storeId,
        'title': notification.title,
        'body': notification.body,
        'type': notification.type.value,
        if (notification.targetRoute != null)
          'targetRoute': notification.targetRoute!,
        if (notification.targetId != null)
          'targetId': notification.targetId!,
        'priority': 'high',
        'channel_id': 'store_notifications_channel',
        'sound': 'default',
        if (notification.metadata != null)
          ...notification.metadata!.map((k, v) => MapEntry(k, v.toString())),
      },
      if (notification.metadata != null) 'metadata': notification.metadata,
    };

    return _remoteDataSource.queuePushNotification(
      storeId: storeId,
      payload: payload,
    );
  }
}
