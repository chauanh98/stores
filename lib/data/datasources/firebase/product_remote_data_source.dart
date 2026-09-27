import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';

import '../../../core/utils/store_resolver_helper.dart';

class ProductRemoteDataSource {
  ProductRemoteDataSource(this._db, this.storeId);

  final FirebaseDatabase _db;
  final String storeId;

  FirebaseDatabase get db => _db;

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

  /// Optimized: dùng debounced stream cho onChildAdded và onValue.take(1) kiểm tra node rỗng,
  /// loại bỏ hoàn toàn _ref.get() để tránh tải kép dữ liệu.
  Stream<List<Map>> watchAll() {
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

    final addSub = _ref.onChildAdded.listen((event) {
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

    final changeSub = _ref.onChildChanged.listen((event) {
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

    final removeSub = _ref.onChildRemoved.listen((event) {
      final key = event.snapshot.key;
      if (key != null) {
        cache.remove(key);
        cache.removeWhere((k, v) => v['id']?.toString() == key);
        if (!controller.isClosed) {
          controller.add(cache.values.toList());
        }
      }
    });

    final emptyCheckSub = _ref.limitToFirst(1).onValue.take(1).listen((event) {
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
    final snap = await _ref.get();
    return _parseSnapshot(snap.value);
  }

  Future<Map?> fetchById(String id) async {
    final snap = await _ref.child(id).get();
    if (snap.value != null && snap.value is Map) {
      return Map.from(snap.value as Map);
    }
    // Fallback: check other canonical store if missing in current store
    final normCurrent = StoreResolverHelper.normalizeStoreId(storeId);
    if (normCurrent == 'store_001' || normCurrent == 'store_002') {
      final otherStoreId =
          normCurrent == 'store_001' ? 'store_002' : 'store_001';
      try {
        final otherSnap =
            await _db.ref('stores/$otherStoreId/products').child(id).get();
        if (otherSnap.value != null && otherSnap.value is Map) {
          final otherMap = Map<String, dynamic>.from(otherSnap.value as Map);
          _ref.child(id).set(otherMap).catchError((_) {});
          return otherMap;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<Map?> getById(String id) => fetchById(id);

  Future<void> upsert(String id, Map<String, dynamic> map) async {
    await _ref.child(id).set(map);

    // Cross-store catalog synchronization for canonical store branches
    final normCurrent = StoreResolverHelper.normalizeStoreId(storeId);
    if (normCurrent == 'store_001' || normCurrent == 'store_002') {
      final otherStoreId =
          normCurrent == 'store_001' ? 'store_002' : 'store_001';
      try {
        final otherRef = _db.ref('stores/$otherStoreId/products').child(id);
        final otherSnap = await otherRef.get();
        if (otherSnap.exists && otherSnap.value is Map) {
          final otherMap = Map<String, dynamic>.from(otherSnap.value as Map);
          final otherStocks = otherMap['branchStocks'] is Map
              ? Map<String, dynamic>.from(otherMap['branchStocks'] as Map)
              : <String, dynamic>{};
          final currentStocks = map['branchStocks'] is Map
              ? Map<String, dynamic>.from(map['branchStocks'] as Map)
              : <String, dynamic>{};

          final mergedStocks = Map<String, dynamic>.from(currentStocks);
          final otherVal = (otherStocks[otherStoreId] as num?)?.toInt() ??
              (otherStocks[otherStoreId == 'store_001'
                      ? 'branch_1'
                      : 'branch_2'] as num?)
                  ?.toInt() ??
              0;
          final curOtherVal = (currentStocks[otherStoreId] as num?)?.toInt() ??
              (currentStocks[otherStoreId == 'store_001'
                      ? 'branch_1'
                      : 'branch_2'] as num?)
                  ?.toInt() ??
              0;

          if (curOtherVal == 0 && otherVal > 0) {
            mergedStocks[otherStoreId] = otherVal;
            if (otherStoreId == 'store_001')
              mergedStocks['branch_1'] = otherVal;
            if (otherStoreId == 'store_002')
              mergedStocks['branch_2'] = otherVal;
          }

          if (mergedStocks.containsKey('store_001')) {
            mergedStocks['branch_1'] = mergedStocks['store_001'];
          }
          if (mergedStocks.containsKey('store_002')) {
            mergedStocks['branch_2'] = mergedStocks['store_002'];
          }

          final updatedMapForOther = Map<String, dynamic>.from(map);
          updatedMapForOther['branchStocks'] = mergedStocks;
          await otherRef.set(updatedMapForOther);

          if (curOtherVal == 0 && otherVal > 0) {
            await _ref.child(id).child('branchStocks').set(mergedStocks);
          }
        } else {
          final replicatedMap = Map<String, dynamic>.from(map);
          if (replicatedMap['branchStocks'] is Map) {
            final s =
                Map<String, dynamic>.from(replicatedMap['branchStocks'] as Map);
            if (s.containsKey('store_001')) s['branch_1'] = s['store_001'];
            if (s.containsKey('store_002')) s['branch_2'] = s['store_002'];
            replicatedMap['branchStocks'] = s;
          }
          await otherRef.set(replicatedMap);
        }
      } catch (_) {}
    }
  }

  Future<void> delete(String id) async {
    await _ref.child(id).remove();
    final normCurrent = StoreResolverHelper.normalizeStoreId(storeId);
    if (normCurrent == 'store_001' || normCurrent == 'store_002') {
      final otherStoreId =
          normCurrent == 'store_001' ? 'store_002' : 'store_001';
      try {
        await _db.ref('stores/$otherStoreId/products').child(id).remove();
      } catch (_) {}
    }
  }

  Future<void> updateStock(String id, int stock) {
    return _ref.child(id).update({'stock': stock});
  }

  static bool _hasAutoHealed = false;

  static void resetAutoHealedForTesting() {
    _hasAutoHealed = false;
  }

  /// Background scan to auto-heal existing products with split-brain branchStocks
  /// (e.g. SP000775 where store_001 has 7 and store_002 has 100).
  static Future<void> autoHealSplitBranchStocks(FirebaseDatabase db,
      {bool force = false}) async {
    if (_hasAutoHealed && !force) return;
    _hasAutoHealed = true;
    try {
      final snap001 = await db.ref('stores/store_001/products').get();
      final snap002 = await db.ref('stores/store_002/products').get();

      final map001 = (snap001.value is Map)
          ? Map<String, dynamic>.from(snap001.value as Map)
          : <String, dynamic>{};
      final map002 = (snap002.value is Map)
          ? Map<String, dynamic>.from(snap002.value as Map)
          : <String, dynamic>{};

      final allIds = <String>{...map001.keys, ...map002.keys};
      final updates = <String, dynamic>{};

      for (final id in allIds) {
        final p1 = map001[id] is Map
            ? Map<String, dynamic>.from(map001[id] as Map)
            : null;
        final p2 = map002[id] is Map
            ? Map<String, dynamic>.from(map002[id] as Map)
            : null;

        if (p1 == null && p2 != null) {
          updates['stores/store_001/products/$id'] = p2;
          continue;
        }
        if (p2 == null && p1 != null) {
          updates['stores/store_002/products/$id'] = p1;
          continue;
        }
        if (p1 != null && p2 != null) {
          final rawStocks1 = p1['branchStocks'] is Map
              ? Map<String, dynamic>.from(p1['branchStocks'] as Map)
              : <String, dynamic>{};
          final rawStocks2 = p2['branchStocks'] is Map
              ? Map<String, dynamic>.from(p2['branchStocks'] as Map)
              : <String, dynamic>{};

          final s1_001 = (rawStocks1['store_001'] as num?)?.toInt() ??
              (rawStocks1['branch_1'] as num?)?.toInt() ??
              0;
          final s1_002 = (rawStocks1['store_002'] as num?)?.toInt() ??
              (rawStocks1['branch_2'] as num?)?.toInt() ??
              0;

          final s2_001 = (rawStocks2['store_001'] as num?)?.toInt() ??
              (rawStocks2['branch_1'] as num?)?.toInt() ??
              0;
          final s2_002 = (rawStocks2['store_002'] as num?)?.toInt() ??
              (rawStocks2['branch_2'] as num?)?.toInt() ??
              0;

          final merged001 = math.max(s1_001, s2_001);
          final merged002 = math.max(s1_002, s2_002);

          if (s1_001 != merged001 || s1_002 != merged002) {
            final unifiedStocks1 = Map<String, dynamic>.from(rawStocks1);
            unifiedStocks1['store_001'] = merged001;
            unifiedStocks1['branch_1'] = merged001;
            unifiedStocks1['store_002'] = merged002;
            unifiedStocks1['branch_2'] = merged002;
            updates['stores/store_001/products/$id/branchStocks'] =
                unifiedStocks1;
          }

          if (s2_001 != merged001 || s2_002 != merged002) {
            final unifiedStocks2 = Map<String, dynamic>.from(rawStocks2);
            unifiedStocks2['store_001'] = merged001;
            unifiedStocks2['branch_1'] = merged001;
            unifiedStocks2['store_002'] = merged002;
            unifiedStocks2['branch_2'] = merged002;
            updates['stores/store_002/products/$id/branchStocks'] =
                unifiedStocks2;
          }
        }
      }

      if (updates.isNotEmpty) {
        await db.ref().update(updates);
      }
    } catch (_) {}
  }
}
