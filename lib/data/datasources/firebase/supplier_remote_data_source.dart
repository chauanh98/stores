import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

class SupplierRemoteDataSource {
  SupplierRemoteDataSource(this._db);

  final FirebaseDatabase _db;

  DatabaseReference _getSuppliersRef([String? storeId]) {
    // Suppliers are shared master data across all stores/branches (like shared_customers)
    return _db.ref('shared_suppliers');
  }

  DatabaseReference _getDebtRef([String? storeId, String supplierId = '']) {
    // If supplierId is in the 2nd argument (standard call: _getDebtRef(storeId, supplierId))
    final actualSupplierId =
        supplierId.isNotEmpty ? supplierId : (storeId ?? '');
    return _db.ref('shared_suppliers/$actualSupplierId/debt_transactions');
  }

  /// Real-time stream of all suppliers with debounce
  Stream<List<Map>> watchAll({String? storeId}) {
    final ref = _getSuppliersRef(storeId);
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
        final map = Map<String, dynamic>.from(val);
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
        final map = Map<String, dynamic>.from(val);
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

  Future<Map?> fetchById(String id, {String? storeId}) async {
    final snap = await _getSuppliersRef(storeId).child(id).get();
    if (snap.value == null) return null;
    if (snap.value is Map) {
      return Map.from(snap.value as Map);
    }
    return null;
  }

  Future<void> upsert(String id, Map<String, dynamic> map, {String? storeId}) {
    return _getSuppliersRef(storeId).child(id).update(map);
  }

  Future<void> delete(String id, {String? storeId}) {
    return _getSuppliersRef(storeId).child(id).remove();
  }

  Future<void> saveDebtTransaction(
    String supplierId,
    Map<String, dynamic> map, {
    String? storeId,
  }) async {
    final id = map['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    await _getDebtRef(storeId, supplierId).child(id).set(map);

    // Update supplier currentDebt directly if remainingDebt is present
    if (map.containsKey('remainingDebt')) {
      final remainingDebt = (map['remainingDebt'] as num?)?.toDouble() ?? 0.0;
      await _getSuppliersRef(storeId).child(supplierId).update({
        'currentDebt': remainingDebt,
      });
    }
  }

  Stream<List<Map>> watchDebtTransactions(String supplierId,
      {String? storeId}) {
    return _getDebtRef(storeId, supplierId).onValue.map((event) {
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

  Future<List<Map>> fetchDebtTransactions(String supplierId,
      {String? storeId}) async {
    final snap = await _getDebtRef(storeId, supplierId).get();
    final val = snap.value;
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
  }
}
