import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../../domain/entities/stock_transfer.dart';
import '../../domain/repositories/stock_transfer_repository.dart';

/// Phiếu chuyển kho lưu ở `stock_transfers/{id}` (dùng chung cho 2 chi nhánh).
class StockTransferRepositoryImpl implements StockTransferRepository {
  StockTransferRepositoryImpl(this._db);

  final FirebaseDatabase _db;

  static const _path = 'stock_transfers';

  DatabaseReference get _ref => _db.ref(_path);

  static List<StockTransfer> _parse(Object? value) {
    if (value is! Map) return const [];
    final out = <StockTransfer>[];
    value.forEach((key, v) {
      if (v is Map) {
        try {
          final t = StockTransfer.fromMap(v);
          out.add(t.id.isEmpty ? t.copyWith(id: '$key') : t);
        } catch (_) {}
      }
    });
    return out;
  }

  @override
  Stream<List<StockTransfer>> watchTransfers(String storeId,
      {int limit = 100}) {
    final isAll = storeId.isEmpty || storeId == 'all';
    if (isAll) {
      return _ref
          .orderByChild('createdAt')
          .limitToLast(limit)
          .onValue
          .map((e) => _sorted(_parse(e.snapshot.value)));
    }

    late StreamController<List<StockTransfer>> controller;
    StreamSubscription? subSource;
    StreamSubscription? subTarget;
    var source = <StockTransfer>[];
    var target = <StockTransfer>[];

    void emit() {
      final merged = <String, StockTransfer>{
        for (final t in source) t.id: t,
        for (final t in target) t.id: t,
      };
      if (!controller.isClosed) {
        controller.add(_sorted(merged.values.toList()));
      }
    }

    controller = StreamController<List<StockTransfer>>(
      onListen: () {
        subSource = _ref
            .orderByChild('sourceStoreId')
            .equalTo(storeId)
            .limitToLast(limit)
            .onValue
            .listen((e) {
          source = _parse(e.snapshot.value);
          emit();
        }, onError: controller.addError);
        subTarget = _ref
            .orderByChild('targetStoreId')
            .equalTo(storeId)
            .limitToLast(limit)
            .onValue
            .listen((e) {
          target = _parse(e.snapshot.value);
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await subSource?.cancel();
        await subTarget?.cancel();
      },
    );
    return controller.stream;
  }

  static List<StockTransfer> _sorted(List<StockTransfer> list) =>
      list..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Stream<int> watchPendingIncomingCount(String storeId) {
    if (storeId.isEmpty || storeId == 'all') return Stream.value(0);
    return _db
        .ref(StockTransferRepository.pendingIndexPath(storeId))
        .onValue
        .map((e) {
      final v = e.snapshot.value;
      return v is Map ? v.length : 0;
    });
  }

  @override
  Future<StockTransfer?> getById(String id) async {
    final snap = await _ref.child(id).get();
    if (!snap.exists || snap.value is! Map) return null;
    final t = StockTransfer.fromMap(snap.value as Map);
    return t.id.isEmpty ? t.copyWith(id: id) : t;
  }

  @override
  Future<String> nextCode() async {
    final result =
        await _db.ref('stock_transfer_counter').runTransaction((current) {
      final n = current is num ? current.toInt() : 0;
      return Transaction.success(n + 1);
    });
    final n = (result.snapshot.value as num?)?.toInt() ?? 1;
    return 'TRF${n.toString().padLeft(6, '0')}';
  }
}
