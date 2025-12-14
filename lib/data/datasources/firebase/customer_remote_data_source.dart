import 'package:firebase_database/firebase_database.dart';

class CustomerRemoteDataSource {
  CustomerRemoteDataSource(this._db);
  final FirebaseDatabase _db;

  DatabaseReference get _ref => _db.ref('stores/store_001/customers');

  Stream<List<Map>> watchAll() => _ref.onValue.map((event) {
    final data = event.snapshot.value as Map? ?? {};
    return data.values.map<Map>((e) => Map.from(e as Map)).toList();
  });

  Future<Map?> fetchById(String id) async {
    final snap = await _ref.child(id).get();
    return snap.value == null ? null : Map.from(snap.value as Map);
  }

  Future<void> upsert(String id, Map<String, dynamic> map) {
    return _ref.child(id).set(map);
  }

  Future<void> delete(String id) => _ref.child(id).remove();
}