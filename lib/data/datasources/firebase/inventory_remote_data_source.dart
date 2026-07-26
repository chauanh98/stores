import 'dart:async';

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

  /// Optimized: dùng onChildAdded/Changed/Removed thay vì onValue
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

    _ref.get().then((snap) {
      final value = snap.value;
      if (value != null && value is Map) {
        final map = Map.from(value);
        for (final entry in map.entries) {
          if (entry.value is Map) {
            cache[entry.key.toString()] = Map.from(entry.value as Map);
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
