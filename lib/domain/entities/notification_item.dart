import 'notification_type.dart';

/// Pure Dart domain entity representing a real-time notification item.
/// Immutable, clean architecture compliant (Zero Flutter, Zero Firebase).
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

  /// Category shortcut directly derived from type.
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
      metadata: metadata ??
          (this.metadata != null
              ? Map<String, dynamic>.from(this.metadata!)
              : null),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NotificationItem || runtimeType != other.runtimeType) {
      return false;
    }
    return id == other.id &&
        storeId == other.storeId &&
        title == other.title &&
        body == other.body &&
        type == other.type &&
        isRead == other.isRead &&
        createdAt == other.createdAt &&
        targetRoute == other.targetRoute &&
        targetId == other.targetId &&
        _mapEquals(metadata, other.metadata);
  }

  @override
  int get hashCode =>
      id.hashCode ^
      storeId.hashCode ^
      title.hashCode ^
      body.hashCode ^
      type.hashCode ^
      isRead.hashCode ^
      createdAt.hashCode ^
      targetRoute.hashCode ^
      targetId.hashCode;

  @override
  String toString() {
    return 'NotificationItem(id: $id, storeId: $storeId, title: $title, '
        'type: $type, isRead: $isRead, createdAt: $createdAt, '
        'targetRoute: $targetRoute, targetId: $targetId)';
  }

  /// Pure Dart recursive map equality helper without Flutter foundation import.
  static bool _mapEquals(Map? a, Map? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      final valA = a[key];
      final valB = b[key];
      if (identical(valA, valB)) continue;
      if (valA is Map && valB is Map) {
        if (!_mapEquals(valA, valB)) return false;
      } else if (valA is List && valB is List) {
        if (!_listEquals(valA, valB)) return false;
      } else if (valA != valB) {
        return false;
      }
    }
    return true;
  }

  /// Pure Dart recursive list equality helper without Flutter foundation import.
  static bool _listEquals(List? a, List? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final valA = a[i];
      final valB = b[i];
      if (identical(valA, valB)) continue;
      if (valA is Map && valB is Map) {
        if (!_mapEquals(valA, valB)) return false;
      } else if (valA is List && valB is List) {
        if (!_listEquals(valA, valB)) return false;
      } else if (valA != valB) {
        return false;
      }
    }
    return true;
  }
}
