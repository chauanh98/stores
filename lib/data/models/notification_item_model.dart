import '../../domain/entities/notification_item.dart';
import '../../domain/entities/notification_type.dart';

/// Data transfer object (DTO) and serialization model for [NotificationItem].
///
/// Implements robust deserialization from Firebase Realtime Database payloads,
/// handling dynamic map types, string booleans, fallback dates, RTDB snapshot keys,
/// and nested metadata sanitization.
class NotificationItemModel {
  final String id;
  final String storeId;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final String? targetRoute;
  final String? targetId;
  final Map<String, dynamic>? metadata;

  const NotificationItemModel({
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

  /// Category derived directly from parsed notification type.
  NotificationCategory get category => notificationType.category;

  /// Parsed notification type enum.
  NotificationType get notificationType => NotificationType.fromString(type);

  /// Converts this model to a clean, null-safe map for Firebase RTDB storage.
  /// Omits null optional fields to minimize egress bandwidth.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'storeId': storeId,
      'title': title,
      'body': body,
      'type': type,
      'isRead': isRead,
      'createdAt': createdAt.toIso8601String(),
      if (targetRoute != null) 'targetRoute': targetRoute,
      if (targetId != null) 'targetId': targetId,
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// Robust deserializer handling dynamic maps, fallback dates, string booleans,
  /// RTDB child keys, and nested metadata structures.
  factory NotificationItemModel.fromMap(
    Map<dynamic, dynamic> map, [
    String? id,
  ]) {
    final resolvedId = (id != null && id.trim().isNotEmpty)
        ? id.trim()
        : (map['id']?.toString().trim() ?? '');

    final storeId = map['storeId']?.toString().trim() ?? '';
    final title = map['title']?.toString().trim() ?? '';
    final body = map['body']?.toString().trim() ??
        map['message']?.toString().trim() ??
        map['content']?.toString().trim() ??
        '';

    final rawType = map['type']?.toString().trim();
    final type = (rawType != null && rawType.isNotEmpty)
        ? NotificationType.fromString(rawType).value
        : NotificationType.orderCreated.value;

    final rawIsRead = map['isRead'] ?? map['read'];
    final isRead = _parseBool(rawIsRead, fallback: false);

    final rawCreated =
        map['createdAt'] ?? map['timestamp'] ?? map['date'] ?? map['time'];
    final createdAt = _parseDateTime(rawCreated);

    final rawTargetRoute = map['targetRoute']?.toString().trim();
    final targetRoute =
        (rawTargetRoute != null && rawTargetRoute.isNotEmpty)
            ? rawTargetRoute
            : null;

    final rawTargetId = map['targetId']?.toString().trim();
    final targetId =
        (rawTargetId != null && rawTargetId.isNotEmpty) ? rawTargetId : null;

    final metadata = _parseMetadata(map['metadata']);

    return NotificationItemModel(
      id: resolvedId,
      storeId: storeId,
      title: title,
      body: body,
      type: type,
      isRead: isRead,
      createdAt: createdAt,
      targetRoute: targetRoute,
      targetId: targetId,
      metadata: metadata,
    );
  }

  /// Converts this model to a pure Dart domain [NotificationItem].
  NotificationItem toDomain() {
    return NotificationItem(
      id: id,
      storeId: storeId,
      title: title,
      body: body,
      type: NotificationType.fromString(type),
      isRead: isRead,
      createdAt: createdAt,
      targetRoute: targetRoute,
      targetId: targetId,
      metadata: metadata,
    );
  }

  /// Creates a model from a pure Dart domain [NotificationItem].
  factory NotificationItemModel.fromDomain(NotificationItem item) {
    return NotificationItemModel(
      id: item.id,
      storeId: item.storeId,
      title: item.title,
      body: item.body,
      type: item.type.value,
      isRead: item.isRead,
      createdAt: item.createdAt,
      targetRoute: item.targetRoute,
      targetId: item.targetId,
      metadata: item.metadata,
    );
  }

  /// Creates a copy of this model with given fields replaced.
  NotificationItemModel copyWith({
    String? id,
    String? storeId,
    String? title,
    String? body,
    String? type,
    bool? isRead,
    DateTime? createdAt,
    String? targetRoute,
    String? targetId,
    Map<String, dynamic>? metadata,
  }) {
    return NotificationItemModel(
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
    if (other is! NotificationItemModel || runtimeType != other.runtimeType) {
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
    return 'NotificationItemModel(id: $id, storeId: $storeId, title: $title, '
        'type: $type, isRead: $isRead, createdAt: $createdAt, '
        'targetRoute: $targetRoute, targetId: $targetId)';
  }

  // ================= PRIVATE ROBUST PARSERS ================= //

  static bool _parseBool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      if (lower == 'true' || lower == '1' || lower == 'yes' || lower == 't') {
        return true;
      }
      if (lower == 'false' || lower == '0' || lower == 'no' || lower == 'f') {
        return false;
      }
    }
    return fallback;
  }

  /// Maximum and minimum milliseconds allowed by Dart's [DateTime.fromMillisecondsSinceEpoch].
  static const int _maxEpochMs = 8640000000000000;
  static const int _minEpochMs = -8640000000000000;

  static DateTime _parseDateTime(dynamic value, {DateTime? fallback}) {
    try {
      if (value == null) return fallback ?? DateTime.now();
      if (value is DateTime) return value;

      if (value is num) {
        if (!value.isFinite) return fallback ?? DateTime.now();
        return _fromEpochNum(value, fallback: fallback);
      }

      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return fallback ?? DateTime.now();

        // 1. Check numeric representations first (epoch seconds/millis, NaN/Infinity literals)
        final parsedNum = num.tryParse(trimmed);
        if (parsedNum != null) {
          if (!parsedNum.isFinite) return fallback ?? DateTime.now();
          return _fromEpochNum(parsedNum, fallback: fallback);
        }

        // 2. Parse standard ISO-8601 strings (guard against absurd 6-digit years)
        final parsedIso = DateTime.tryParse(trimmed);
        if (parsedIso != null &&
            parsedIso.year <= 9999 &&
            parsedIso.year >= -9999) {
          return parsedIso;
        }
      }

      return fallback ?? DateTime.now();
    } catch (_) {
      return fallback ?? DateTime.now();
    }
  }

  /// Converts a finite [number] to [DateTime], handling seconds vs milliseconds
  /// and bounding against Dart's DateTime millisecond range.
  static DateTime _fromEpochNum(num number, {DateTime? fallback}) {
    if (!number.isFinite) return fallback ?? DateTime.now();
    try {
      if (number > _maxEpochMs || number < _minEpochMs) {
        return fallback ?? DateTime.now();
      }
      final intVal = number.toInt();
      // Values under 10 billion (10-digit epoch timestamp) represent epoch seconds
      final ms = (intVal > 0 && intVal < 10000000000) ? intVal * 1000 : intVal;
      if (ms < _minEpochMs || ms > _maxEpochMs) {
        return fallback ?? DateTime.now();
      }
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return fallback ?? DateTime.now();
    }
  }

  static Map<String, dynamic>? _parseMetadata(dynamic value) {
    if (value == null || value is! Map) return null;
    final result = <String, dynamic>{};
    value.forEach((key, val) {
      if (key != null) {
        result[key.toString()] = _sanitizeDynamicValue(val);
      }
    });
    return result;
  }

  static dynamic _sanitizeDynamicValue(dynamic value) {
    if (value is Map) {
      final sanitizedMap = <String, dynamic>{};
      value.forEach((k, v) {
        if (k != null) {
          sanitizedMap[k.toString()] = _sanitizeDynamicValue(v);
        }
      });
      return sanitizedMap;
    } else if (value is List) {
      return value.map(_sanitizeDynamicValue).toList();
    }
    return value;
  }

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
