import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../../../core/utils/stream_debounce_helper.dart';

class OrderRemoteDataSource {
  OrderRemoteDataSource(this._db, this.storeId);

  final FirebaseDatabase _db;
  final String storeId;

  DatabaseReference get _ref => _db.ref('stores/$storeId/orders');

  Future<void> create(String id, Map<String, dynamic> map) {
    return _ref.child(id).set(map);
  }

  Future<void> update(String id, Map<String, dynamic> map) {
    return _ref.child(id).update(map);
  }

  Future<void> delete(String id) {
    return _ref.child(id).remove();
  }

  Future<Map<String, dynamic>?> fetchById(String id) async {
    final snap = await _ref.child(id).get();
    if (snap.value == null) return null;
    if (snap.value is Map) {
      return Map<String, dynamic>.from(snap.value as Map);
    }
    return null;
  }

  Stream<List<Map<String, dynamic>>> watchByCustomer(String customerId) {
    return _ref
        .orderByChild('customerId')
        .equalTo(customerId)
        .onValue
        .debounce(const Duration(milliseconds: 250))
        .map((event) {
      final data = event.snapshot.value as Map? ?? {};
      return data.values
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  /// Optimized: dùng debounced stream cho onChildAdded và onValue.take(1) kiểm tra node rỗng,
  /// giới hạn tối đa [limit] (mặc định: 50) đơn hàng gần nhất để kiểm soát egress.
  Stream<List<Map<String, dynamic>>> watchRecentOrders({int limit = 50}) {
    final query = limit > 0 ? _ref.limitToLast(limit) : _ref;
    final controller = StreamController<List<Map<String, dynamic>>>();
    final Map<String, Map<String, dynamic>> cache = {};
    Timer? debounceTimer;
    bool hasEmitted = false;

    void debouncedEmit() {
      debounceTimer?.cancel();
      debounceTimer = Timer(const Duration(milliseconds: 250), () {
        if (!controller.isClosed) {
          hasEmitted = true;
          controller.add(cache.values.toList());
        }
      });
    }

    final addSub = query.onChildAdded.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        final map = Map<String, dynamic>.from(val);
        final id = map['id']?.toString() ?? event.snapshot.key;
        if (id != null) {
          cache[id] = map;
          debouncedEmit();
        }
      }
    });

    final changeSub = query.onChildChanged.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        final map = Map<String, dynamic>.from(val);
        final id = map['id']?.toString() ?? event.snapshot.key;
        if (id != null) {
          cache[id] = map;
          if (!controller.isClosed) {
            controller.add(cache.values.toList());
          }
        }
      }
    });

    final removeSub = query.onChildRemoved.listen((event) {
      final key = event.snapshot.key;
      if (key != null) {
        cache.remove(key);
        cache.removeWhere((k, v) => v['id']?.toString() == key);
        if (!controller.isClosed) {
          controller.add(cache.values.toList());
        }
      }
    });

    final emptyCheckSub = _ref.limitToFirst(1).onValue.take(1).listen((event) {
      if (event.snapshot.value == null) {
        if (cache.isEmpty && !hasEmitted && !controller.isClosed) {
          hasEmitted = true;
          controller.add([]);
        }
      }
    });

    controller.onCancel = () {
      debounceTimer?.cancel();
      addSub.cancel();
      changeSub.cancel();
      removeSub.cancel();
      emptyCheckSub.cancel();
    };

    return controller.stream;
  }

  /// Backward-compatible wrapper calling [watchRecentOrders] with limit = 50.
  Stream<List<Map<String, dynamic>>> watchAll() => watchRecentOrders(limit: 50);

  // Lấy orders theo khoảng thời gian
  Stream<List<Map<String, dynamic>>> watchByDateRange(
      DateTime startDate, DateTime endDate) {
    // Đảm bảo endDate luôn là cuối ngày để không bỏ sót đơn hàng trong ngày đó
    final adjustedEndDate =
        DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

    // Dùng inclusive range: start <= createdAt <= end (end cuối ngày)
    final start = startDate.toIso8601String();
    final end = adjustedEndDate.toIso8601String();

    return _ref
        .orderByChild('createdAt')
        .startAt(start)
        .endAt(end)
        .onValue
        .debounce(const Duration(milliseconds: 250))
        .map((event) {
      final data = event.snapshot.value as Map? ?? {};
      final list = data.values
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // Firebase Realtime Database orderByChild+range đôi khi bao gồm phần tử biên không như mong muốn
      // nên lọc lại phía client để đảm bảo phạm vi chính xác theo ngày giao dịch gốc
      return list.where((m) {
        final dateStr =
            m['orderDate']?.toString() ?? m['createdAt']?.toString() ?? '';
        final parsed = DateTime.tryParse(dateStr);
        if (parsed == null) return false;
        final txDate = parsed.isUtc ? parsed.toLocal() : parsed;
        return !txDate.isBefore(startDate) && !txDate.isAfter(adjustedEndDate);
      }).toList();
    });
  }

  // Lấy orders theo khoảng thời gian bằng Future (chạy một lần, không bị treo)
  Future<List<Map<String, dynamic>>> fetchByDateRange(
      DateTime startDate, DateTime endDate) async {
    final adjustedEndDate =
        DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
    final start = startDate.toIso8601String();
    final end = adjustedEndDate.toIso8601String();

    try {
      final snap =
          await _ref.orderByChild('createdAt').startAt(start).endAt(end).get();

      final data = snap.value as Map? ?? {};
      final list = data.values
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      return list.where((m) {
        final dateStr =
            m['orderDate']?.toString() ?? m['createdAt']?.toString() ?? '';
        final parsed = DateTime.tryParse(dateStr);
        if (parsed == null) return false;
        final txDate = parsed.isUtc ? parsed.toLocal() : parsed;
        return !txDate.isBefore(startDate) && !txDate.isAfter(adjustedEndDate);
      }).toList();
    } catch (_) {
      // Eliminated illegal fallback _ref.get() to prevent full collection RAM scans.
      // Return empty list to preserve egress quota.
      return [];
    }
  }

  // Return Orders CRUD & Stream methods
  DatabaseReference get _returnsRef => _db.ref('stores/$storeId/return_orders');

  Future<void> createReturn(String id, Map<String, dynamic> map) {
    return _returnsRef.child(id).set(map);
  }

  Future<Map<String, dynamic>?> fetchReturnById(String id) async {
    final snap = await _returnsRef.child(id).get();
    if (snap.value == null) return null;
    if (snap.value is Map) {
      return Map<String, dynamic>.from(snap.value as Map);
    }
    return null;
  }

  Stream<List<Map<String, dynamic>>> watchReturnsByDateRange(
      DateTime startDate, DateTime endDate) {
    final adjustedEndDate =
        DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
    final start = startDate.toIso8601String();
    final end = adjustedEndDate.toIso8601String();

    return _returnsRef
        .orderByChild('createdAt')
        .startAt(start)
        .endAt(end)
        .onValue
        .debounce(const Duration(milliseconds: 250))
        .map((event) {
      final data = event.snapshot.value as Map? ?? {};
      final list = data.values
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return list.where((m) {
        final parsed = DateTime.tryParse(m['createdAt']?.toString() ?? '');
        if (parsed == null) return false;
        final createdAt = parsed.isUtc ? parsed.toLocal() : parsed;
        return !createdAt.isBefore(startDate) &&
            !createdAt.isAfter(adjustedEndDate);
      }).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> watchReturnsByOrderId(String orderId) {
    return _returnsRef
        .orderByChild('orderId')
        .equalTo(orderId)
        .onValue
        .debounce(const Duration(milliseconds: 250))
        .map((event) {
      final data = event.snapshot.value as Map? ?? {};
      return data.values
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }
}
