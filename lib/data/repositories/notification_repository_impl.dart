import 'dart:async';

import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/notification_repository.dart';
import '../datasources/firebase/notification_remote_data_source.dart';
import '../models/notification_item_model.dart';

/// Concrete implementation of [NotificationRepository] delegating to [NotificationRemoteDataSource].
/// Translates between data-layer models and pure domain entities, and ensures notifications
/// are always presented sorted with newest first (`createdAt` descending).
class NotificationRepositoryImpl implements NotificationRepository {
  final NotificationRemoteDataSource _remoteDataSource;

  NotificationRepositoryImpl(this._remoteDataSource);

  @override
  Stream<List<NotificationItem>> watchNotifications(
    String storeId, {
    int limit = 50,
  }) {
    return _remoteDataSource
        .watchNotifications(storeId, limit: limit)
        .map((maps) {
      final items = maps
          .map((m) =>
              NotificationItemModel.fromMap(m, m['id']?.toString()).toDomain())
          .toList();
      // Ensure sorted by createdAt descending (newest first)
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    });
  }

  @override
  Future<void> addNotification(NotificationItem notification) async {
    final model = NotificationItemModel.fromDomain(notification);
    await _remoteDataSource.addNotification(
        notification.storeId, model.toMap());
  }

  @override
  Future<void> markAsRead({required String storeId, required String id}) async {
    await _remoteDataSource.markAsRead(storeId, id);
  }

  @override
  Future<void> markAllAsRead(String storeId) async {
    await _remoteDataSource.markAllAsRead(storeId);
  }

  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {
    await _remoteDataSource.deleteNotification(storeId, id);
  }
}
