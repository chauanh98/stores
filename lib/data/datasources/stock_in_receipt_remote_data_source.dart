import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import 'package:stores/core/utils/stream_debounce_helper.dart';

/// Remote data source handling CRUD and real-time streaming of stock-in receipts
/// in Firebase Realtime Database at path `stores/$storeId/stock_in_receipts`.
class StockInReceiptRemoteDataSource {
  final FirebaseDatabase _db;

  StockInReceiptRemoteDataSource(this._db);

  DatabaseReference _receiptsRef(String storeId) =>
      _db.ref('stores/$storeId/stock_in_receipts');

  /// Saves or overwrites a stock-in receipt at `stores/$storeId/stock_in_receipts/$receiptId`.
  Future<void> saveReceipt(
    String storeId,
    String receiptId,
    Map<String, dynamic> data,
  ) async {
    await _receiptsRef(storeId).child(receiptId).set(data);
  }

  /// Updates existing stock-in receipt fields.
  Future<void> updateReceipt(
    String storeId,
    String receiptId,
    Map<String, dynamic> data,
  ) async {
    await _receiptsRef(storeId).child(receiptId).update(data);
  }

  /// Deletes a stock-in receipt from `stores/$storeId/stock_in_receipts/$receiptId`.
  Future<void> deleteReceipt(String storeId, String receiptId) async {
    await _receiptsRef(storeId).child(receiptId).remove();
  }

  /// Retrieves a single receipt by [receiptId].
  Future<Map<String, dynamic>?> getReceipt(
    String storeId,
    String receiptId,
  ) async {
    final snap = await _receiptsRef(storeId).child(receiptId).get();
    final val = snap.value;
    if (val is Map) {
      final map = Map<String, dynamic>.from(val);
      map['id'] ??= snap.key;
      return map;
    }
    return null;
  }

  /// Fetches receipts for a given [storeId] once.
  Future<List<Map<String, dynamic>>> fetchReceipts(
    String storeId, {
    int limit = 50,
  }) async {
    final snap = await _receiptsRef(storeId).limitToLast(limit).get();
    final val = snap.value;
    return _parseSnapshot(val);
  }

  /// Real-time stream of receipts for [storeId].
  Stream<List<Map<String, dynamic>>> watchReceipts(
    String storeId, {
    int limit = 50,
  }) {
    return _receiptsRef(storeId)
        .limitToLast(limit)
        .onValue
        .debounce(const Duration(milliseconds: 250))
        .map((event) {
      return _parseSnapshot(event.snapshot.value);
    });
  }

  /// Executes atomic multi-path update at the database root level.
  Future<void> atomicUpdate(Map<String, dynamic> updates) async {
    await _db.ref().update(updates);
  }

  /// Queries the latest import unit price for [productId] in [storeId]
  /// from `stores/$storeId/inventory_transactions`.
  Future<double?> getLatestImportPrice({
    required String storeId,
    required String productId,
  }) async {
    try {
      final txRef = _db.ref('stores/$storeId/inventory_transactions');
      final snap =
          await txRef.orderByChild('productId').equalTo(productId).get();
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

  List<Map<String, dynamic>> _parseSnapshot(dynamic val) {
    if (val == null) return [];
    final List<Map<String, dynamic>> list = [];

    if (val is Map) {
      for (final entry in val.entries) {
        if (entry.value is Map) {
          final map = Map<String, dynamic>.from(entry.value as Map);
          map['id'] ??= entry.key.toString();
          list.add(map);
        }
      }
    } else if (val is List) {
      for (final item in val) {
        if (item is Map) {
          list.add(Map<String, dynamic>.from(item));
        }
      }
    }

    return list;
  }
}
