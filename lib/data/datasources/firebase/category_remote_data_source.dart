import 'package:firebase_database/firebase_database.dart';

class CategoryRemoteDataSource {
  CategoryRemoteDataSource(this._db);

  final FirebaseDatabase _db;

  DatabaseReference get _ref => _db.ref('shared_categories');

  List<Map> _parseSnapshot(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value
          .where((e) => e != null)
          .map<Map>((e) => Map.from(e as Map))
          .toList();
    }
    if (value is Map) {
      return value.values
          .where((e) => e != null)
          .map<Map>((e) => Map.from(e as Map))
          .toList();
    }
    return [];
  }

  Stream<List<Map>> watchAll() => _ref.onValue.map((event) {
        return _parseSnapshot(event.snapshot.value);
      });

  Future<List<Map>> fetchAll() async {
    final snap = await _ref.get();
    return _parseSnapshot(snap.value);
  }

  Future<void> upsert(String id, Map<String, dynamic> map) {
    return _ref.child(id).set(map);
  }

  Future<void> delete(String id) => _ref.child(id).remove();
}
