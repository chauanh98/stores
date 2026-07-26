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

  /// Optimized: bỏ _ref.get() vì onChildAdded đã fire cho mọi child hiện tại
  /// Tránh download data 2 lần khi khởi tạo
  Stream<List<Map>> watchAll() {
    final controller = StreamController<List<Map>>();
    final Map<String, Map> cache = {};
    Timer? debounceTimer;

    void debouncedEmit() {
      debounceTimer?.cancel();
      debounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (!controller.isClosed) {
          controller.add(cache.values.toList());
        }
      });
    }

    final addSub = _ref.onChildAdded.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        final map = Map<String, dynamic>.from(val);
        final id = map['id']?.toString();
        if (id != null) {
          cache[id] = map;
          debouncedEmit();
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
          // Emit ngay cho change events (không debounce)
          if (!controller.isClosed) {
            controller.add(cache.values.toList());
          }
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
          if (!controller.isClosed) {
            controller.add(cache.values.toList());
          }
        }
      }
    });

    controller.onCancel = () {
      debounceTimer?.cancel();
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
    return _ref.child(id).update(map);
  }

  Future<void> delete(String id) => _ref.child(id).remove();

  Future<void> saveDebtTransaction(
      String customerId, Map<String, dynamic> map) {
    final id = map['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    return _ref.child(customerId).child('debt_transactions').child(id).set(map);
  }

  Stream<List<Map>> watchDebtTransactions(String customerId) {
    return _ref
        .child(customerId)
        .child('debt_transactions')
        .onValue
        .map((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        return val.values
            .where((e) => e != null)
            .map<Map>((e) => Map.from(e as Map))
            .toList();
      }
      if (val is List) {
        return val
            .where((e) => e != null)
            .map<Map>((e) => Map.from(e as Map))
            .toList();
      }
      return <Map>[];
    });
  }
}
