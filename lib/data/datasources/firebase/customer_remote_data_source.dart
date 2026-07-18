import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

class CustomerRemoteDataSource {
  CustomerRemoteDataSource(this._db);

  final FirebaseDatabase _db;

  DatabaseReference get _ref => _db.ref('shared_customers');

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
        final map = Map<String, dynamic>.from(val);
        final id = map['id']?.toString();
        if (id != null) {
          cache[id] = map;
          safeEmit();
        }
      }
    });

    final changeSub = _ref.onChildChanged.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        final map = Map<String, dynamic>.from(val);
        final id = map['id']?.toString();
        if (id != null) {
          cache[id] = map;
          safeEmit();
        }
      }
    });

    final removeSub = _ref.onChildRemoved.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        final map = Map<String, dynamic>.from(val);
        final id = map['id']?.toString();
        if (id != null) {
          cache.remove(id);
          safeEmit();
        }
      }
    });

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
}
