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

  /// Lấy các lô nhập (và kiểm kê/xuất kho) đến [endDate] để tính giá vốn FIFO mà
  /// KHÔNG cắt cụt lô cũ như `limitToLast(100)` một lần.
  ///
  /// Phân trang LÙI theo `date` (mỗi trang tối đa [pageSize] bản ghi, tối đa
  /// [maxPages] trang => tối đa pageSize*maxPages bản ghi, luôn bị chặn) và DỪNG SỚM
  /// khi mọi sản phẩm trong [neededQty] đã có đủ số lượng nhập tích luỹ (lô cũ hơn
  /// chắc chắn đã bị bán hết nên không ảnh hưởng FIFO). [neededQty] rỗng => chỉ 1
  /// trang (hành vi cũ). Trang kế tiếp dùng `endAt(ngày cũ nhất của trang trước)` và
  /// khử trùng theo id.
  Future<List<Map>> fetchLotTransactionsUpToDate(
    DateTime endDate, {
    Map<String, int> neededQty = const {},
    int pageSize = 100,
    int maxPages = 5,
  }) async {
    final result = <String, Map>{};
    final covered = <String, int>{};
    var cursor = endDate.toIso8601String();
    final pages = neededQty.isEmpty ? 1 : maxPages;
    for (var page = 0; page < pages; page++) {
      final snap = await _ref
          .orderByChild('date')
          .endAt(cursor)
          .limitToLast(pageSize)
          .get();
      final data = snap.value as Map? ?? {};
      final batch = data.entries
          .where((e) => e.value is Map)
          .map((e) => MapEntry(e.key.toString(), Map.from(e.value as Map)))
          .toList();
      var added = 0;
      String? oldest;
      for (final e in batch) {
        final m = e.value;
        final d = m['date']?.toString();
        if (d != null && (oldest == null || d.compareTo(oldest) < 0)) {
          oldest = d;
        }
        final key = m['id']?.toString() ?? e.key;
        if (result.containsKey(key)) continue;
        result[key] = m;
        added++;
        if (m['type']?.toString().toLowerCase() == 'import') {
          final pid = m['productId']?.toString();
          final q = (m['quantity'] as num?)?.toInt() ?? 0;
          if (pid != null && q > 0) covered[pid] = (covered[pid] ?? 0) + q;
        }
      }
      if (batch.length < pageSize || added == 0 || oldest == null) break;
      if (neededQty.isNotEmpty &&
          neededQty.entries.every((e) => (covered[e.key] ?? 0) >= e.value)) {
        break;
      }
      cursor = oldest;
    }
    return result.values.toList();
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
