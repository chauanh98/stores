import 'package:firebase_database/firebase_database.dart';

class OrderRemoteDataSource {
  OrderRemoteDataSource(this._db, this.storeId);
  final FirebaseDatabase _db;
  final String storeId;

  DatabaseReference get _ref => _db.ref('stores/$storeId/orders');

  Future<void> create(String id, Map<String, dynamic> map) {
    return _ref.child(id).set(map);
  }

  Stream<List<Map<String, dynamic>>> watchByCustomer(String customerId) {
    return _ref.orderByChild('customerId').equalTo(customerId).onValue.map((event) {
      final data = event.snapshot.value as Map? ?? {};
      return data.values.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    });
  }

  // Thêm method để lấy tất cả orders
  Stream<List<Map<String, dynamic>>> watchAll() {
    return _ref.onValue.map((event) {
      final data = event.snapshot.value as Map? ?? {};
      return data.values.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    });
  }

  // Lấy orders theo khoảng thời gian
  Stream<List<Map<String, dynamic>>> watchByDateRange(DateTime startDate, DateTime endDate) {
    // Đảm bảo endDate luôn là cuối ngày để không bỏ sót đơn hàng trong ngày đó
    final adjustedEndDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

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
      final list = data.values.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      // Firebase Realtime Database orderByChild+range đôi khi bao gồm phần tử biên không như mong muốn
      // nên lọc lại phía client để đảm bảo phạm vi chính xác
      return list.where((m) {
        final createdAt = DateTime.tryParse(m['createdAt']?.toString() ?? '');
        if (createdAt == null) return false;
        return !createdAt.isBefore(startDate) && !createdAt.isAfter(adjustedEndDate);
      }).toList();
    });
  }

  // Lấy orders theo khoảng thời gian bằng Future (chạy một lần, không bị treo)
  Future<List<Map<String, dynamic>>> fetchByDateRange(DateTime startDate, DateTime endDate) async {
    final adjustedEndDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
    final start = startDate.toIso8601String();
    final end = adjustedEndDate.toIso8601String();

    final snap = await _ref
        .orderByChild('createdAt')
        .startAt(start)
        .endAt(end)
        .get();

    final data = snap.value as Map? ?? {};
    final list = data.values.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    
    return list.where((m) {
      final createdAt = DateTime.tryParse(m['createdAt']?.toString() ?? '');
      if (createdAt == null) return false;
      return !createdAt.isBefore(startDate) && !createdAt.isAfter(adjustedEndDate);
    }).toList();
  }
}