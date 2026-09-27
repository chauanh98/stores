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

  /// Optimized: dùng debounced stream cho onChildAdded và onValue.take(1) kiểm tra node rỗng,
  /// loại bỏ hoàn toàn _ref.get() để tránh tải kép dữ liệu categories.
  Stream<List<Map>> watchAll() {
    final ref = _ref;
    if (ref == null) return const Stream.empty();

    final controller = StreamController<List<Map>>();
    final Map<String, Map> cache = {};
    Timer? debounceTimer;
    bool hasEmitted = false;

    void debouncedEmit() {
      debounceTimer?.cancel();
      debounceTimer = Timer(const Duration(milliseconds: 50), () {
        if (!controller.isClosed) {
          hasEmitted = true;
          controller.add(cache.values.toList());
        }
      });
    }

    final addSub = ref.onChildAdded.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        final map = Map.from(val);
        final id = map['id']?.toString() ?? event.snapshot.key;
        if (id != null) {
          cache[id] = map;
          debouncedEmit();
        }
      }
    });

    final changeSub = ref.onChildChanged.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        final map = Map.from(val);
        final id = map['id']?.toString() ?? event.snapshot.key;
        if (id != null) {
          cache[id] = map;
          if (!controller.isClosed) {
            controller.add(cache.values.toList());
          }
        }
      }
    });

    final removeSub = ref.onChildRemoved.listen((event) {
      final key = event.snapshot.key;
      if (key != null) {
        cache.remove(key);
        cache.removeWhere((k, v) => v['id']?.toString() == key);
        if (!controller.isClosed) {
          controller.add(cache.values.toList());
        }
      }
    });

    final emptyCheckSub = ref.limitToFirst(1).onValue.take(1).listen((event) {
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
