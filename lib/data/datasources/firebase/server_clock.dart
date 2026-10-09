import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Đồng hồ đã hiệu chỉnh theo máy chủ Firebase.
///
/// Thông báo realtime chỉ bật pop-up khi `createdAt` còn "mới" (vài chục giây).
/// `createdAt` do máy TẠO sự kiện ghi, còn máy NHẬN so với giờ của nó — nếu
/// đồng hồ 2 máy lệch nhau quá ngưỡng thì pop-up bị bỏ qua mà không báo lỗi.
/// `.info/serverTimeOffset` là node cục bộ của SDK (không tốn băng thông),
/// cho biết độ lệch giữa đồng hồ máy và máy chủ.
class ServerClock {
  ServerClock._();

  static Duration _offset = Duration.zero;
  static StreamSubscription<DatabaseEvent>? _sub;

  /// Bắt đầu theo dõi độ lệch (gọi nhiều lần cũng an toàn).
  static void ensureStarted([FirebaseDatabase? db]) {
    if (_sub != null) return;
    try {
      final database = db ?? FirebaseDatabase.instance;
      _sub = database.ref('.info/serverTimeOffset').onValue.listen(
        (event) {
          final value = event.snapshot.value;
          if (value is num && value.isFinite) {
            _offset = Duration(milliseconds: value.round());
          }
        },
        onError: (Object e) =>
            debugPrint('[ServerClock] serverTimeOffset error: $e'),
      );
    } catch (_) {
      // Firebase chưa khởi tạo (unit test) → dùng giờ máy.
    }
  }

  /// Giờ hiện tại theo máy chủ (giờ máy nếu chưa có độ lệch).
  static DateTime now() => DateTime.now().add(_offset);

  @visibleForTesting
  static void debugSetOffset(Duration offset) => _offset = offset;
}
