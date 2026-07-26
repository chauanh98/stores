import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

class ProductRemoteDataSource {
  ProductRemoteDataSource(this._db, this.storeId);

  final FirebaseDatabase _db;
  final String storeId;

  DatabaseReference get _ref => _db.ref('stores/$storeId/products');

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

  /// Optimized: dùng onChildAdded/Changed/Removed thay vì onValue
  /// để chỉ download delta (bản ghi thay đổi) thay vì toàn bộ node
  Stream<List<Map>> watchAll() {
    final controller = StreamController<List<Map>>();
    final Map<String, Map> cache = {};
    bool initialLoaded = false;

    void safeEmit() {
      if (initialLoaded && !controller.isClosed) {
        controller.add(cache.values.toList());
      }
    }

    final addSub = _ref.onChildAdded.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        cache[event.snapshot.key!] = Map.from(val);
        safeEmit();
      }
    });

    final changeSub = _ref.onChildChanged.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        cache[event.snapshot.key!] = Map.from(val);
        safeEmit();
      }
    });

    final removeSub = _ref.onChildRemoved.listen((event) {
      cache.remove(event.snapshot.key);
      safeEmit();
    });

    // Dùng get() để load initial data 1 lần, sau đó onChildAdded sẽ bổ sung
    // Cần đánh dấu initialLoaded sau khi get() xong
    _ref.get().then((snap) {
      final value = snap.value;
      if (value != null) {
        final initialList = _parseSnapshot(value);
        for (final item in initialList) {
          final id = item['id']?.toString();
          if (id != null) {
            cache[id] = item;
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

  Future<List<Map>> fetchAll() async {
    final snap = await _ref.get();
    return _parseSnapshot(snap.value);
  }

  Future<Map?> fetchById(String id) async {
    final snap = await _ref.child(id).get();
    if (snap.value == null) return null;
    if (snap.value is Map) {
      return Map.from(snap.value as Map);
    }
    return null;
  }

  Future<void> upsert(String id, Map<String, dynamic> map) {
    return _ref.child(id).set(map);
  }

  Future<void> delete(String id) => _ref.child(id).remove();

  Future<void> updateStock(String id, int stock) {
    return _ref.child(id).update({'stock': stock});
  }
}
