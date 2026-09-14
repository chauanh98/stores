import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

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
        .map((event) {
      final data = event.snapshot.value as Map? ?? {};
      return data.values
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  /// Optimized: dùng onChildAdded/Changed/Removed thay vì onValue
  /// để chỉ download delta thay vì toàn bộ node orders
  Stream<List<Map<String, dynamic>>> watchAll() {
    final controller = StreamController<List<Map<String, dynamic>>>();
    final Map<String, Map<String, dynamic>> cache = {};
    bool initialLoaded = false;

    void safeEmit() {
      if (initialLoaded && !controller.isClosed) {
        controller.add(cache.values.toList());
      }
    }

    final addSub = _ref.onChildAdded.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        cache[event.snapshot.key!] = Map<String, dynamic>.from(val);
        safeEmit();
      }
    });

    final changeSub = _ref.onChildChanged.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        cache[event.snapshot.key!] = Map<String, dynamic>.from(val);
        safeEmit();
      }
    });

    final removeSub = _ref.onChildRemoved.listen((event) {
      cache.remove(event.snapshot.key);
      safeEmit();
    });

    _ref.get().then((snap) {
      final value = snap.value;
      if (value != null && value is Map) {
        final map = Map<String, dynamic>.from(value);
        for (final entry in map.entries) {
          if (entry.value is Map) {
            cache[entry.key] = Map<String, dynamic>.from(entry.value as Map);
          }
        }
      }
      initialLoaded = true;
      safeEmit();
    }).catchError((err) {
      if (!controller.isClosed) {
        controller.addError(err);
      }
    });

    controller.onCancel = () {
      addSub.cancel();
      changeSub.cancel();
      removeSub.cancel();
    };

    return controller.stream;
  }

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
        .map((event) {
      final data = event.snapshot.value as Map? ?? {};
      final list = data.values
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // Firebase Realtime Database orderByChild+range đôi khi bao gồm phần tử biên không như mong muốn
      // nên lọc lại phía client để đảm bảo phạm vi chính xác
      return list.where((m) {
        final createdAt = DateTime.tryParse(m['createdAt']?.toString() ?? '');
        if (createdAt == null) return false;
        return !createdAt.isBefore(startDate) &&
            !createdAt.isAfter(adjustedEndDate);
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

    final snap =
        await _ref.orderByChild('createdAt').startAt(start).endAt(end).get();

    final data = snap.value as Map? ?? {};
    final list = data.values
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return list.where((m) {
      final createdAt = DateTime.tryParse(m['createdAt']?.toString() ?? '');
      if (createdAt == null) return false;
      return !createdAt.isBefore(startDate) &&
          !createdAt.isAfter(adjustedEndDate);
    }).toList();
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
        .map((event) {
      final data = event.snapshot.value as Map? ?? {};
      final list = data.values
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return list.where((m) {
        final createdAt = DateTime.tryParse(m['createdAt']?.toString() ?? '');
        if (createdAt == null) return false;
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
        .map((event) {
      final data = event.snapshot.value as Map? ?? {};
      return data.values
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }
}

