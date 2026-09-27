import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../../../core/utils/stream_debounce_helper.dart';

class InventoryRemoteDataSource {
  InventoryRemoteDataSource(this._db, this.storeId);

  final FirebaseDatabase _db;
  final String storeId;

  DatabaseReference get _ref =>
      _db.ref('stores/$storeId/inventory_transactions');

  Stream<List<Map>> watchByProduct(String productId) => _ref
          .orderByChild('productId')
          .equalTo(productId)
          .onValue
          .debounce(const Duration(milliseconds: 250))
          .map((event) {
        final data = event.snapshot.value as Map? ?? {};
        return data.values.map<Map>((e) => Map.from(e as Map)).toList();
      });

  Future<void> record(String id, Map<String, dynamic> map) {
    return _ref.child(id).set(map);
  }

  /// Optimized: dùng debounced stream cho onChildAdded và onValue.take(1) kiểm tra node rỗng,
  /// giới hạn tối đa [limit] (mặc định: 50) giao dịch gần nhất để kiểm soát egress.
  Stream<List<Map>> watchRecentTransactions({int limit = 50}) {
    final effectiveLimit = limit > 0 ? limit : 50;
    final query = _ref.limitToLast(effectiveLimit);
    final controller = StreamController<List<Map>>();
    final Map<String, Map> cache = {};
    Timer? debounceTimer;
    bool hasEmitted = false;

    void debouncedEmit() {
      debounceTimer?.cancel();
      debounceTimer = Timer(const Duration(milliseconds: 250), () {
        if (!controller.isClosed) {
          hasEmitted = true;
          controller.add(cache.values.toList());
        }
      });
    }

    final addSub = query.onChildAdded.listen((event) {
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

    final changeSub = query.onChildChanged.listen((event) {
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

    final removeSub = query.onChildRemoved.listen((event) {
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

  /// Backward-compatible wrapper calling [watchRecentTransactions] with limit = 50.
  Stream<List<Map>> watchAll() => watchRecentTransactions(limit: 50);

  /// Retrieves recent inventory transactions constrained by limitToLast(50) to protect egress quota.
  Future<List<Map>> fetchAll() async {
    final snap = await _ref.limitToLast(50).get();
    final data = snap.value as Map? ?? {};
    return data.values.map<Map>((e) => Map.from(e as Map)).toList();
  }

  /// Retrieves inventory transactions up to [endDate] bounded by [limit] (default: 100).
  Future<List<Map>> fetchTransactionsUpToDate(DateTime endDate,
      {int limit = 100}) async {
    try {
      final effectiveLimit = limit > 0 ? limit : 100;
      final snap = await _ref
          .orderByChild('date')
          .endAt(endDate.toIso8601String())
          .limitToLast(effectiveLimit)
          .get();
      final data = snap.value as Map? ?? {};
      return data.values.map<Map>((e) => Map.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  // Lấy import transactions theo khoảng thời gian
  Stream<List<Map>> watchImportsByDateRange(
      DateTime startDate, DateTime endDate) {
    return _ref
        .orderByChild('date')
        .startAt(startDate.toIso8601String())
        .endAt(endDate.toIso8601String())
        .onValue
        .debounce(const Duration(milliseconds: 250))
        .map((event) {
      final data = event.snapshot.value as Map? ?? {};
      return data.values
          .map<Map>((e) => Map.from(e as Map))
          .where((m) => m['type'] == 'import')
          .toList();
    });
  }

  // Lấy import transactions theo khoảng thời gian bằng Future (bounded query)
  Future<List<Map>> fetchImportsByDateRange(
      DateTime startDate, DateTime endDate) async {
    try {
      final snap = await _ref
          .orderByChild('date')
          .startAt(startDate.toIso8601String())
          .endAt(endDate.toIso8601String())
          .get();
      final data = snap.value as Map? ?? {};
      return data.values
          .map<Map>((e) => Map.from(e as Map))
          .where((m) => m['type'] == 'import')
          .toList();
    } catch (e) {
      // Eliminated illegal fallback _ref.get() to prevent full collection scans.
      // Return empty list to preserve egress quota.
      return [];
    }
  }

  /// Retrieves the latest unit import price for [productId] from inventory_transactions.
  Future<double?> getLatestImportPrice(String productId) async {
    try {
      final snap =
          await _ref.orderByChild('productId').equalTo(productId).get();
      final data = snap.value;
      if (data is! Map) return null;

      double? latestPrice;
      DateTime? latestDate;

      for (final entry in data.values) {
        if (entry is! Map) continue;
        if (entry['type'] != 'import') continue;
        final rawPrice = (entry['importPrice'] as num?)?.toDouble();
        if (rawPrice == null || rawPrice <= 0) continue;

        final dateStr = entry['date']?.toString();
        final date = dateStr != null ? DateTime.tryParse(dateStr) : null;

        if (date != null) {
          if (latestDate == null || date.isAfter(latestDate)) {
            latestDate = date;
            latestPrice = rawPrice;
          }
        } else {
          latestPrice ??= rawPrice;
        }
      }
      return latestPrice;
    } catch (_) {
      return null;
    }
  }
}
