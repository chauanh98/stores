import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

class CategoryRemoteDataSource {
  CategoryRemoteDataSource([this._db]);

  final FirebaseDatabase? _db;

  DatabaseReference? get _ref => _db?.ref('shared_categories');

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
  Stream<List<Map>> watchAll() {
    final ref = _ref;
    if (ref == null) return const Stream.empty();

    final controller = StreamController<List<Map>>();
    final Map<String, Map> cache = {};
    bool initialLoaded = false;

    void safeEmit() {
      if (initialLoaded && !controller.isClosed) {
        controller.add(cache.values.toList());
      }
    }

    final addSub = ref.onChildAdded.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        cache[event.snapshot.key!] = Map.from(val);
        safeEmit();
      }
    });

    final changeSub = ref.onChildChanged.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        cache[event.snapshot.key!] = Map.from(val);
        safeEmit();
      }
    });

    final removeSub = ref.onChildRemoved.listen((event) {
      cache.remove(event.snapshot.key);
      safeEmit();
    });

    ref.get().then((snap) {
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
    final ref = _ref;
    if (ref == null) return [];
    final snap = await ref.get();
    return _parseSnapshot(snap.value);
  }

  Future<void> upsert(String id, Map<String, dynamic> map) {
    final ref = _ref;
    if (ref == null) return Future.value();
    return ref.child(id).set(map);
  }

  Future<void> delete(String id) {
    final ref = _ref;
    if (ref == null) return Future.value();
    return ref.child(id).remove();
  }
}
