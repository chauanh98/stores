import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:stores/core/utils/stream_debounce_helper.dart';

/// Remote data source responsible for notification CRUD operations and real-time streams
/// on Firebase Realtime Database at path `stores/$storeId/notifications`.
class NotificationRemoteDataSource {
  final FirebaseDatabase _db;

  NotificationRemoteDataSource([FirebaseDatabase? db])
      : _db = db ?? FirebaseDatabase.instance;

  DatabaseReference _notificationsRef(String storeId) =>
      _db.ref('stores/$storeId/notifications');

  /// Streams notifications in real time for a store, limited to [limit] records (default 50)
  /// and debounced by 250ms to minimize Firebase RTDB egress bandwidth.
  Stream<List<Map<String, dynamic>>> watchNotifications(
    String storeId, {
    int limit = 50,
  }) {
    final effectiveLimit = limit > 0 ? limit : 50;
    final query = _notificationsRef(storeId)
        .orderByChild('createdAt')
        .limitToLast(effectiveLimit);

    return query.onValue
        .debounce(const Duration(milliseconds: 250))
        .map((event) => _parseSnapshot(event.snapshot.value));
  }

  /// One-shot fetch of notifications for [storeId], limited to [limit] records.
  Future<List<Map<String, dynamic>>> fetchNotifications(
    String storeId, {
    int limit = 50,
  }) async {
    final effectiveLimit = limit > 0 ? limit : 50;
    final snap = await _notificationsRef(storeId)
        .orderByChild('createdAt')
        .limitToLast(effectiveLimit)
        .get();
    return _parseSnapshot(snap.value);
  }

  /// Adds a new notification to `stores/$storeId/notifications`.
  /// Uses existing `data['id']` if provided, otherwise creates an atomic push key.
  Future<void> addNotification(
    String storeId,
    Map<String, dynamic> data,
  ) async {
    final ref = _notificationsRef(storeId);
    final id = data['id']?.toString().trim();
    if (id != null && id.isNotEmpty) {
      await ref.child(id).set(data);
    } else {
      final newRef = ref.push();
      final autoId =
          newRef.key ?? DateTime.now().millisecondsSinceEpoch.toString();
      final mapWithId = Map<String, dynamic>.from(data)..['id'] = autoId;
      await newRef.set(mapWithId);
    }
  }

  /// Marks a specific notification as read by updating `isRead: true`.
  Future<void> markAsRead(String storeId, String id) async {
    await _notificationsRef(storeId).child(id).update({
      'isRead': true,
    });
  }

  /// Marks unread notifications as read via atomic multi-path update.
  /// Queries only unread records (`isRead == false`) limited to 100 to prevent large payloads.
  Future<void> markAllAsRead(String storeId) async {
    final ref = _notificationsRef(storeId);
    final snap = await ref
        .orderByChild('isRead')
        .equalTo(false)
        .limitToLast(100)
        .get();

    final val = snap.value;
    if (val == null) return;

    final updates = <String, Object?>{};

    if (val is Map) {
      for (final key in val.keys) {
        updates['$key/isRead'] = true;
      }
    } else if (val is List) {
      for (var i = 0; i < val.length; i++) {
        if (val[i] != null) {
          updates['$i/isRead'] = true;
        }
      }
    }

    if (updates.isNotEmpty) {
      await ref.update(updates);
    }
  }

  /// Deletes a specific notification from `stores/$storeId/notifications/$id`.
  Future<void> deleteNotification(String storeId, String id) async {
    await _notificationsRef(storeId).child(id).remove();
  }

  /// Parses Firebase snapshot value safely handling Map, List, or null.
  List<Map<String, dynamic>> _parseSnapshot(dynamic val) {
    if (val == null) return [];
    final List<Map<String, dynamic>> list = [];

    if (val is Map) {
      for (final entry in val.entries) {
        if (entry.value is Map) {
          final map = <String, dynamic>{};
          (entry.value as Map).forEach((k, v) {
            if (k != null) map[k.toString()] = v;
          });
          final rawId = map['id']?.toString().trim();
          if (rawId == null || rawId.isEmpty) {
            map['id'] = entry.key.toString();
          }
          list.add(map);
        }
      }
    } else if (val is List) {
      for (var i = 0; i < val.length; i++) {
        final item = val[i];
        if (item is Map) {
          final map = <String, dynamic>{};
          item.forEach((k, v) {
            if (k != null) map[k.toString()] = v;
          });
          final rawId = map['id']?.toString().trim();
          if (rawId == null || rawId.isEmpty) {
            map['id'] = i.toString();
          }
          list.add(map);
        }
      }
    }

    return list;
  }
}
