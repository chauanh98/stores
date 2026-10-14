import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/stock_transfer.dart';
import 'package:stores/domain/repositories/stock_transfer_repository.dart';

/// In-memory tree used by [FakeRtdb]. Paths are '/'-separated.
class _Tree {
  final Map<String, dynamic> root = {};

  dynamic read(String path) {
    dynamic cur = root;
    for (final seg in _segs(path)) {
      if (cur is Map && cur.containsKey(seg)) {
        cur = cur[seg];
      } else {
        return null;
      }
    }
    return cur;
  }

  void write(String path, dynamic value) {
    final segs = _segs(path);
    if (segs.isEmpty) return;
    Map<String, dynamic> cur = root;
    for (var i = 0; i < segs.length - 1; i++) {
      final next = cur[segs[i]];
      if (next is Map) {
        cur = next.cast<String, dynamic>();
      } else {
        final m = <String, dynamic>{};
        cur[segs[i]] = m;
        cur = m;
      }
    }
    if (value == null) {
      cur.remove(segs.last);
    } else {
      cur[segs.last] = _deepCopy(value);
    }
  }

  static List<String> _segs(String p) =>
      p.split('/').where((s) => s.isNotEmpty).toList();

  static dynamic _deepCopy(dynamic v) {
    if (v is Map) {
      return {for (final e in v.entries) '${e.key}': _deepCopy(e.value)};
    }
    if (v is List) return v.map(_deepCopy).toList();
    return v;
  }
}

class _FakeSnapshot extends Fake implements DataSnapshot {
  _FakeSnapshot(this._value);
  final dynamic _value;

  @override
  bool get exists => _value != null;

  @override
  Object? get value => _value;
}

class _FakeTxResult extends Fake implements TransactionResult {
  _FakeTxResult(this.committed, this.snapshot);
  @override
  final bool committed;
  @override
  final DataSnapshot snapshot;
}

class _FakeRef extends Fake implements DatabaseReference {
  _FakeRef(this._db, this._path);
  final FakeRtdb _db;
  final String _path;

  @override
  String? get key {
    final s = _path.split('/').where((e) => e.isNotEmpty).toList();
    return s.isEmpty ? null : s.last;
  }

  @override
  DatabaseReference child(String path) => _FakeRef(_db, '$_path/$path');

  @override
  DatabaseReference push() => _FakeRef(_db, '$_path/-key${_db._seq++}');

  @override
  Future<DataSnapshot> get() async {
    _db.getPaths.add(_path.split('/').where((e) => e.isNotEmpty).join('/'));
    return _FakeSnapshot(_db._tree.read(_path));
  }

  @override
  Future<void> set(Object? value, {Object? priority}) async {
    _db._tree.write(_path, value);
  }

  @override
  Future<void> remove() async => _db._tree.write(_path, null);

  @override
  Future<TransactionResult> runTransaction(TransactionHandler handler,
      {bool applyLocally = true}) async {
    _db.transactionCalls++;
    final current = _db._tree.read(_path);
    final tx = handler(current);
    if (tx.aborted) return _FakeTxResult(false, _FakeSnapshot(current));
    _db._tree.write(_path, tx.value);
    return _FakeTxResult(true, _FakeSnapshot(tx.value));
  }

  @override
  Future<void> update(Map<String, Object?> value) async {
    if (_db.failNextUpdate) {
      _db.failNextUpdate = false;
      throw Exception('network down');
    }
    _db.updateCalls++;
    value.forEach((k, v) => _db._tree.write('$_path/$k', v));
  }
}

/// Minimal in-memory FirebaseDatabase: get/set/update/remove/push/child only.
class FakeRtdb extends Fake implements FirebaseDatabase {
  final _Tree _tree = _Tree();
  int _seq = 1;
  int updateCalls = 0;
  int transactionCalls = 0;
  bool failNextUpdate = false;

  /// Every path read through get(), in order (for egress assertions).
  final List<String> getPaths = [];

  @override
  DatabaseReference ref([String? path]) => _FakeRef(this, path ?? '');

  void seed(String path, dynamic value) => _tree.write(path, value);
  dynamic read(String path) => _tree.read(path);
}

/// Repository backed by [FakeRtdb] (no queries / transactions needed in tests).
class FakeStockTransferRepository implements StockTransferRepository {
  FakeStockTransferRepository(this.db);
  final FakeRtdb db;
  int _counter = 0;

  @override
  Future<String> nextCode() async =>
      'TRF${(++_counter).toString().padLeft(6, '0')}';

  @override
  Future<StockTransfer?> getById(String id) async {
    final v = db.read('stock_transfers/$id');
    if (v is! Map) return null;
    return StockTransfer.fromMap(v);
  }

  @override
  Stream<int> watchPendingIncomingCount(String storeId) {
    final v = db.read(StockTransferRepository.pendingIndexPath(storeId));
    return Stream.value(v is Map ? v.length : 0);
  }

  @override
  Stream<List<StockTransfer>> watchTransfers(String storeId,
      {int limit = 100}) {
    final v = db.read('stock_transfers');
    if (v is! Map) return Stream.value(const []);
    return Stream.value([
      for (final e in v.values)
        if (e is Map) StockTransfer.fromMap(e),
    ]);
  }
}
