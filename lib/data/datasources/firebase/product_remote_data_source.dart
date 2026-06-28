import 'package:firebase_database/firebase_database.dart';

class ProductRemoteDataSource {
  ProductRemoteDataSource(this._db, this.storeId);
  final FirebaseDatabase _db;
  final String storeId;

  DatabaseReference get _ref => _db.ref('stores/$storeId/products');

  Stream<List<Map>> watchAll() => _ref.onValue.map((event) {
    final data = event.snapshot.value as Map? ?? {};
    return data.values.map<Map>((e) => Map.from(e as Map)).toList();
  });

  Future<List<Map>> fetchAll() async {
    final snap = await _ref.get();
    final data = snap.value as Map? ?? {};
    return data.values.map<Map>((e) => Map.from(e as Map)).toList();
  }

  Future<Map?> fetchById(String id) async {
    final snap = await _ref.child(id).get();
    return snap.value == null ? null : Map.from(snap.value as Map);
  }

  Future<void> upsert(String id, Map<String, dynamic> map) {
    return _ref.child(id).set(map);
  }

  Future<void> delete(String id) => _ref.child(id).remove();

  Future<void> updateStock(String id, int stock) {
    return _ref.child(id).update({'stock': stock});
  }
}