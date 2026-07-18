import 'package:firebase_database/firebase_database.dart';

class InventoryRemoteDataSource {
  InventoryRemoteDataSource(this._db, this.storeId);

  final FirebaseDatabase _db;
  final String storeId;

  DatabaseReference get _ref =>
      _db.ref('stores/$storeId/inventory_transactions');

  Stream<List<Map>> watchByProduct(String productId) =>
      _ref.orderByChild('productId').equalTo(productId).onValue.map((event) {
        final data = event.snapshot.value as Map? ?? {};
        return data.values.map<Map>((e) => Map.from(e as Map)).toList();
      });

  Future<void> record(String id, Map<String, dynamic> map) {
    return _ref.child(id).set(map);
  }

  // Thêm method để lấy tất cả inventory transactions
  Stream<List<Map>> watchAll() {
    return _ref.onValue.map((event) {
      final data = event.snapshot.value as Map? ?? {};
      return data.values.map<Map>((e) => Map.from(e as Map)).toList();
    });
  }

  Future<List<Map>> fetchAll() async {
    final snap = await _ref.get();
    final data = snap.value as Map? ?? {};
    return data.values.map<Map>((e) => Map.from(e as Map)).toList();
  }

  // Lấy import transactions theo khoảng thời gian
  Stream<List<Map>> watchImportsByDateRange(
      DateTime startDate, DateTime endDate) {
    return _ref
        .orderByChild('date')
        .startAt(startDate.toIso8601String())
        .endAt(endDate.toIso8601String())
        .onValue
        .map((event) {
      final data = event.snapshot.value as Map? ?? {};
      return data.values
          .map<Map>((e) => Map.from(e as Map))
          .where((m) => m['type'] == 'import')
          .toList();
    });
  }
}
