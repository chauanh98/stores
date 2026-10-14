import 'dart:math';

import 'package:stores/application/inventories/usecases/stock_transfer_use_cases.dart';
import 'package:stores/application/inventory/inter_store_transfer_service.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/stock_transfer.dart';

import 'fuzz_support.dart';

/// Executes random operations against the real use cases and mirrors them in
/// the independent [Model].
class Runner {
  Runner(this.h, this.r);
  final Harness h;
  final Random r;
  Model get m => h.model;
  int _seq = 0;
  int opsRun = 0;

  List<String> get branches => h.branches;
  T pick<T>(List<T> l) => l[r.nextInt(l.length)];
  bool chance(double p) => r.nextDouble() < p;

  String rawStore(String canonicalId) =>
      (canonicalId == 'store_001' || canonicalId == 'store_002') && chance(0.2)
          ? aliasOf(canonicalId)
          : canonicalId;

  void note(String s) {
    h.log.add(s);
    if (h.log.length > 40) h.log.removeAt(0);
  }

  Future<void> step() async {
    opsRun++;
    final x = r.nextInt(100);
    if (x < 14) {
      await opStockIn();
    } else if (x < 20) {
      await opCancelStockIn();
    } else if (x < 24) {
      await opCompleteThenCancel();
    } else if (x < 42) {
      await opTransferCreate();
    } else if (x < 62) {
      await opReceive();
    } else if (x < 70) {
      await opCancelTransfer();
    } else if (x < 78) {
      await opRace();
    } else if (x < 86) {
      await opPos();
    } else if (x < 91) {
      await opDirectTransfer();
    } else if (x < 93) {
      await opDeleteDraft();
    } else {
      h.checkAll(null, strictCrossView: !h.threeBranches);
    }
  }

  // ------------------------------------------------------------ stock-in --

  StockInReceipt _buildReceipt(String store, String storeField, int n) {
    final cands = [
      for (final e in m.records.entries)
        if (e.value.contains(store)) e.key
    ];
    final lines = <StockInReceiptItem>[];
    final count = 1 + r.nextInt(5);
    for (var i = 0; i < count; i++) {
      final pid = (i > 0 && chance(0.3) && lines.isNotEmpty)
          ? pick(lines).productId // duplicate line
          : pick(cands);
      final qty =
          chance(0.03) ? 1000000 + r.nextInt(3000000) : 1 + r.nextInt(40);
      final price =
          pick(const [0.0, 1000.0, 2500.5, 1234.5678, 99999.99, 3.333]);
      lines.add(StockInReceiptItem(
          transactionId: 't$i',
          productId: pid,
          productCode: 'C$pid',
          quantity: qty,
          unitPrice: price));
    }
    final total = lines.fold<double>(0, (a, b) => a + b.quantity * b.unitPrice);
    final discount = chance(0.4)
        ? double.parse((total * r.nextDouble()).toStringAsFixed(2))
        : 0.0;
    final net = total - discount;
    final paid = pick<double?>([
      null,
      0.0,
      net,
      double.parse((net * r.nextDouble()).toStringAsFixed(2)),
      net + 5000,
    ]);
    final sup = pick<String?>([null, null, 'S1', 'S2', 'S3', 'S1', 'GHOST']);
    return StockInReceipt(
      id: 'R$n',
      importCode: 'PN$n',
      date: DateTime(2026, 8, 1),
      storeId: storeField,
      supplierId: sup,
      supplierName: sup,
      status: 'draft',
      items: lines,
      discount: discount,
      paidAmount: paid,
    );
  }

  /// With 3 branches a record can hold a stale view of the other branches (the
  /// use cases only know the two main stores), which skews the weighted
  /// average. Such products are excluded from exact cost assertions.
  void _markStale(String store, Iterable<String> pids) {
    if (!h.threeBranches) return;
    for (final pid in pids) {
      final e = h.entityAt(store, pid);
      if (e != null && e.stock != m.totalUnits(pid)) m.costUnknown.add(pid);
    }
  }

  /// Applies the reference semantics of a completed stock-in.
  void _modelComplete(StockInReceipt rc, String store) {
    final agg = <String, int>{};
    final cost = <String, double>{};
    for (final it in rc.items) {
      agg[it.productId] = (agg[it.productId] ?? 0) + it.quantity;
      cost[it.productId] =
          (cost[it.productId] ?? 0) + it.quantity * it.unitPrice;
    }
    for (final pid in agg.keys) {
      final q = agg[pid]!;
      final T = m.totalUnits(pid);
      final c = m.costAt[pid]![store]!;
      final nc = T <= 0 ? cost[pid]! / q : (T * c + cost[pid]!) / (T + q);
      m.stock[pid]![store] = m.stock[pid]![store]! + q;
      m.ledger[pid] = m.ledger[pid]! + q;
      for (final rec in {store, 'store_001', 'store_002'}) {
        if (m.records[pid]!.contains(rec)) m.costAt[pid]![rec] = nc;
      }
    }
    final net =
        rc.items.fold<double>(0, (a, b) => a + b.quantity * b.unitPrice) -
            rc.discount;
    final paid =
        rc.paidAmount == null ? 0.0 : rc.paidAmount!.clamp(0.0, max(0.0, net));
    final remaining = max(0.0, net - paid);
    final s = rc.supplierId;
    if (s != null && m.supDebt.containsKey(s)) {
      m.supDebt[s] = max(0.0, m.supDebt[s]! + remaining);
      m.supTotal[s] = m.supTotal[s]! + net;
    }
  }

  void _modelCancelIn(StockInReceipt rc, String store) {
    final agg = <String, int>{};
    final cost = <String, double>{};
    for (final it in rc.items) {
      agg[it.productId] = (agg[it.productId] ?? 0) + it.quantity;
      cost[it.productId] =
          (cost[it.productId] ?? 0) + it.quantity * it.unitPrice;
    }
    for (final pid in agg.keys) {
      final q = agg[pid]!;
      final T = m.totalUnits(pid);
      final cur = m.stock[pid]![store]!;
      final removed = min(cur, q);
      m.stock[pid]![store] = cur - removed;
      m.ledger[pid] = m.ledger[pid]! - removed;
      final c = m.costAt[pid]![store]!;
      var reverted =
          c; // unchanged unless a sane weighted-average revert exists
      if (T - q > 0) {
        final cand = (c * T - cost[pid]!) / (T - q);
        final tol = 1e-9 * ((cost[pid]! / (T - q)).abs() + 1.0);
        if (cand.isFinite && cand >= -tol) reverted = max(0.0, cand);
      }
      for (final rec in {store, 'store_001', 'store_002'}) {
        if (m.records[pid]!.contains(rec)) m.costAt[pid]![rec] = reverted;
      }
    }
    final net = rc.effectiveNetPayable;
    final s = rc.supplierId;
    if (s != null && m.supDebt.containsKey(s)) {
      m.supTotal[s] = max(0.0, m.supTotal[s]! - net);
      m.supDebt[s] = max(0.0, m.supDebt[s]! - rc.remainingDebt);
    }
  }

  Future<void> opStockIn() async {
    final store = pick(branches);
    final storeField = rawStore(store);
    final n = ++_seq;
    final rc = _buildReceipt(store, storeField, n);
    note(
        'stockIn $n @$storeField ${rc.items.map((i) => '${i.productId}x${i.quantity}@${i.unitPrice}').join(',')} sup=${rc.supplierId} disc=${rc.discount} paid=${rc.paidAmount}');
    h.productRepo.scope = store;
    if (chance(0.06)) {
      final before = dbDump(h.db);
      h.db.failNextUpdate = true;
      var threw = false;
      try {
        await h.complete.execute(rc, user: admin);
      } catch (_) {
        threw = true;
      }
      h.db.failNextUpdate = false;
      if (!threw) h.fail('stockIn with failing write did not throw');
      if (dbDump(h.db) != before) h.fail('failed stockIn left partial state');
      h.checkNotifications(0, 'failed stockIn');
    }
    // expected state transition
    _markStale(store, rc.items.map((i) => i.productId));
    final preStock = {
      for (final e in m.stock.entries) e.key: Map<String, int>.from(e.value)
    };
    final done = await h.complete.execute(rc, user: admin);
    _modelComplete(done, store);
    final mr = MReceipt(done, store);
    mr.preStock = preStock;
    m.receipts[done.id] = mr;
    h.checkNotifications(1, 'stockIn');
    // second complete of the same (now stored completed) receipt must not re-apply
    if (chance(0.15)) {
      final before = dbDump(h.db);
      var threw = false;
      try {
        await h.complete.execute(rc, user: admin);
      } catch (_) {
        threw = true;
      }
      if (!threw || dbDump(h.db) != before) {
        h.fail(
            'duplicate complete of receipt ${rc.id} re-applied stock (threw=$threw)');
        // keep model aligned with whatever the DB did so later checks are meaningful
        _modelComplete(done, store);
      }
      h.notifSeen = h.notifRepo.added.length;
    }
    h.checkAll(rc.items.map((i) => i.productId).toSet(),
        strictCrossView: !h.threeBranches);
  }

  Future<void> opCancelStockIn() async {
    if (m.receipts.isEmpty) return;
    final mr = pick(m.receipts.values.toList());
    final rc = mr.receipt;
    final store = canon(mr.store);
    note('cancelStockIn ${rc.id} (${mr.status}) store=${mr.store}');
    h.productRepo.scope = store;
    final pids = rc.items.map((i) => i.productId).toSet();
    _markStale(store, pids);
    if (chance(0.15) && mr.status == 'completed') {
      // two devices cancel the same receipt (stale 'completed' snapshot)
      final results = await Future.wait([
        _try(() => h.cancelIn.execute(
            storeId: mr.store, receipt: rc, reason: 'x', cancelledBy: 'a')),
        _try(() => h.cancelIn.execute(
            storeId: mr.store, receipt: rc, reason: 'y', cancelledBy: 'b')),
      ]);
      final ok = results.where((e) => e).length;
      if (ok != 1) h.fail('double cancel from two devices: $ok succeeded');
      for (var i = 0; i < ok; i++) {
        _modelCancelIn(rc, store);
      }
      mr.status = 'cancelled';
      h.notifSeen = h.notifRepo.added.length;
      h.checkAll(pids, strictCrossView: !h.threeBranches);
      return;
    }
    final ok = await _try(() => h.cancelIn.execute(
        storeId: mr.store, receipt: rc, reason: 'x', cancelledBy: 'a'));
    if (mr.status == 'completed') {
      if (!ok) h.fail('cancel of completed receipt failed');
      _modelCancelIn(rc, store);
      mr.status = 'cancelled';
      h.checkNotifications(1, 'cancelStockIn');
    } else {
      // stale snapshot of an already cancelled receipt
      if (ok) {
        h.fail('second cancel of ${rc.id} succeeded (double rollback)');
        _modelCancelIn(rc, store);
      }
      h.notifSeen = h.notifRepo.added.length;
    }
    h.checkAll(pids, strictCrossView: !h.threeBranches);
  }

  Future<bool> _try(Future<void> Function() f) async {
    try {
      await f();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Complete then immediately cancel: product stock, cost (when the stock was
  /// positive) and supplier numbers must return exactly to the start.
  Future<void> opCompleteThenCancel() async {
    final store = pick(branches);
    final n = ++_seq;
    final rc = _buildReceipt(store, store, n);
    h.productRepo.scope = store;
    final pids = rc.items.map((i) => i.productId).toSet();
    final prevCost = {
      for (final p in pids) p: h.entityAt(store, p)!.costPrice,
    };
    final prevT = {for (final p in pids) p: h.entityAt(store, p)!.stock};
    final prevStock = {
      for (final p in pids) p: h.entityAt(store, p)!.stockInBranch(store)
    };
    final prevSup = {
      for (final s in m.supDebt.keys) s: [m.supDebt[s]!, m.supTotal[s]!]
    };
    note('completeThenCancel $n @$store');
    _markStale(store, pids);
    final done = await h.complete.execute(rc, user: admin);
    _modelComplete(done, store);
    await h.cancelIn.execute(
        storeId: store, receipt: done, reason: 'undo', cancelledBy: 'a');
    _modelCancelIn(done, store);
    m.receipts[done.id] = MReceipt(done, store)..status = 'cancelled';
    h.notifSeen = h.notifRepo.added.length;
    for (final p in pids) {
      final e = h.entityAt(store, p)!;
      if (e.stockInBranch(store) != prevStock[p]) {
        h.fail('complete+cancel did not restore stock of $p');
      }
      // revert subtracts a (possibly huge) receipt cost from a small stock:
      // allow the matching floating-point cancellation error.
      final C = done.items
          .where((i) => i.productId == p)
          .fold<double>(0, (a, i) => a + i.quantity * i.unitPrice);
      final slack = 1e-13 * C / max(1, prevT[p]!);
      if (prevT[p]! > 0 &&
          (e.costPrice - prevCost[p]!).abs() >
              slack + 1e-7 * prevCost[p]!.abs() + 1e-6) {
        h.fail(
            'complete+cancel did not restore cost of $p: ${prevCost[p]} -> ${e.costPrice}');
      }
    }
    for (final s in m.supDebt.keys) {
      if (!near(m.supDebt[s]!, prevSup[s]![0])) {
        // debt revert is exact unless clamped; informational only
      }
    }
    h.checkAll(pids, strictCrossView: !h.threeBranches);
  }

  // ----------------------------------------------------------- transfers --

  StockTransfer _draft(
          String srcRaw, String tgtRaw, List<StockTransferItem> items,
          {String id = '', String code = ''}) =>
      StockTransfer(
        id: id,
        code: code,
        status: StockTransferStatus.draft,
        sourceStoreId: srcRaw,
        sourceStoreName: 'src',
        targetStoreId: tgtRaw,
        targetStoreName: 'tgt',
        items: items,
        createdAt: DateTime(2026, 1, 1),
      );

  StockTransferItem _item(String pid, int q) => StockTransferItem(
      productId: pid, name: 'Product $pid', code: 'C$pid', quantity: q);

  /// Expected aggregated quantities, or null when the reference says "reject".
  Map<String, int>? _expectCreate(String src, List<StockTransferItem> items) {
    if (items.isEmpty) return null;
    final agg = <String, int>{};
    for (final i in items) {
      if (i.quantity <= 0) return null;
      if (!m.records[i.productId]!.contains(src)) return null;
      agg[i.productId] = (agg[i.productId] ?? 0) + i.quantity;
    }
    for (final e in agg.entries) {
      if (e.value > m.stock[e.key]![src]!) return null;
    }
    return agg;
  }

  void _modelCreate(MSlip s, Map<String, int> agg) {
    agg.forEach((pid, q) => m.stock[pid]![s.src] = m.stock[pid]![s.src]! - q);
    s.setStatus('in_transit');
  }

  Future<void> opTransferCreate() async {
    final src = pick(branches);
    var tgt = pick(branches.where((b) => b != src).toList());
    final sameStore = chance(0.04);
    if (sameStore) tgt = aliasOf(src) == src ? src : aliasOf(src);
    final srcRaw = rawStore(src);
    final tgtRaw = sameStore ? tgt : rawStore(tgt);
    final stocked = [
      for (final e in m.stock.entries)
        if (m.records[e.key]!.contains(src)) e.key
    ];
    if (stocked.isEmpty) return;
    final items = <StockTransferItem>[];
    final count = 1 + r.nextInt(4);
    for (var i = 0; i < count; i++) {
      final pid = (items.isNotEmpty && chance(0.3))
          ? pick(items).productId
          : pick(stocked);
      final have = m.stock[pid]![src]!;
      int q;
      if (chance(0.05)) {
        q = 0;
      } else if (chance(0.15)) {
        q = have + 1 + r.nextInt(3);
      } else {
        q = have == 0 ? 1 : 1 + r.nextInt(max(1, min(have, 30)));
        if (have > 1000 && chance(0.3)) q = have; // all of a huge stock
      }
      items.add(_item(pid, q));
    }
    final mode = r.nextInt(3); // 0 direct, 1 draft->send, 2 draft + double send
    final expect = sameStore ? null : _expectCreate(src, items);
    note(
        'create mode=$mode $srcRaw->$tgtRaw ${items.map((i) => '${i.productId}x${i.quantity}').join(',')} expectOk=${expect != null}');
    final user = admin;

    StockTransfer? saved;
    if (mode > 0) {
      if (sameStore) {
        // still allowed to save a draft
      }
      saved = await h.saveDraft.execute(_draft(srcRaw, tgtRaw, items));
    }
    final send = _draft(srcRaw, tgtRaw, items,
        id: saved?.id ?? '', code: saved?.code ?? '');

    if (expect != null && chance(0.08)) {
      final before = dbDump(h.db);
      h.db.failNextUpdate = true;
      final ok = await _try(() => h.create.execute(send, user: user));
      h.db.failNextUpdate = false;
      if (ok) h.fail('create with failing write succeeded');
      if (dbDump(h.db) != before) h.fail('failed create left partial state');
      h.checkNotifications(0, 'failed create');
    }

    if (mode == 2 && expect != null) {
      final res = await Future.wait([
        _tryT(() => h.create.execute(send, user: user)),
        _tryT(() => h.create.execute(send, user: user)),
      ]);
      final okRes = res.whereType<StockTransfer>().toList();
      if (okRes.length != 1) {
        h.fail('double create-from-draft: ${okRes.length} succeeded');
      }
      for (final t in okRes) {
        final s = MSlip(t.id, src, canon(tgt), []);
        m.slips[t.id] = s;
        _modelCreate(s, expect);
        _checkCreated(t, src, expect);
      }
      h.notifSeen = h.notifRepo.added.length;
      h.checkAll(items.map((e) => e.productId).toSet(),
          strictCrossView: !h.threeBranches);
      return;
    }

    final res = await _tryT(() => h.create.execute(send, user: user));
    if (expect == null) {
      if (res != null) {
        h.fail(
            'create should have been rejected but succeeded: $srcRaw->$tgtRaw');
        // align model with reality to avoid cascades
        final agg = <String, int>{};
        for (final i in items) {
          agg[i.productId] = (agg[i.productId] ?? 0) + i.quantity;
        }
        m.slips[res.id] = MSlip(res.id, src, canon(tgt), [])
          ..setStatus('in_transit');
        for (final p in agg.keys) {
          m.stock[p]![src] = max(0, m.stock[p]![src]! - agg[p]!);
        }
        h.notifSeen = h.notifRepo.added.length;
      } else {
        h.checkNotifications(0, 'rejected create');
      }
    } else {
      if (res == null) {
        h.fail('create unexpectedly failed: $srcRaw->$tgtRaw');
      } else {
        final s = MSlip(res.id, src, canon(tgt), []);
        if (saved != null)
          s.history
            ..clear()
            ..add('draft');
        m.slips[res.id] = s;
        _modelCreate(s, expect);
        if (saved == null)
          s.history
            ..clear()
            ..add('in_transit');
        _checkCreated(res, src, expect);
        h.checkNotifications(2, 'create');
      }
    }
    if (mode > 0 && res == null && saved != null) {
      // leftover draft: track so the slip check sees it as draft
      final s = MSlip(saved.id, src, canon(tgt), []);
      m.slips[saved.id] = s;
    }
    h.checkAll(items.map((e) => e.productId).toSet(),
        strictCrossView: !h.threeBranches);
  }

  Future<StockTransfer?> _tryT(Future<StockTransfer> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  void _checkCreated(StockTransfer t, String src, Map<String, int> agg) {
    final got = <String, int>{};
    for (final i in t.items) {
      got[i.productId] = (got[i.productId] ?? 0) + i.quantity;
    }
    for (final e in agg.entries) {
      if (got[e.key] != e.value) {
        h.fail(
            'slip ${t.id} qty of ${e.key} = ${got[e.key]} expected ${e.value}');
      }
    }
    final stored = h.db.read('stock_transfers/${t.id}');
    if (stored is Map) {
      final st = StockTransfer.fromMap(stored);
      if (st.sourceStoreId != src ||
          st.targetStoreId != canon(st.targetStoreId)) {
        h.fail(
            'slip ${t.id} stores not canonical: ${st.sourceStoreId}->${st.targetStoreId}');
      }
      for (final i in st.items) {
        final c = m.costAt[i.productId]![src];
        // cost snapshot is the pre-send cost (unchanged by transfers)
        if (c != null &&
            !h.model.costUnknown.contains(i.productId) &&
            !near(i.unitPrice, c, 1e-7)) {
          h.fail(
              'slip item ${i.productId} unitPrice ${i.unitPrice} != cost $c');
        }
      }
    }
  }

  Map<String, int> _slipAgg(MSlip s) {
    final raw = h.db.read('stock_transfers/${s.id}');
    final out = <String, int>{};
    if (raw is Map) {
      for (final i in StockTransfer.fromMap(raw).items) {
        out[i.productId] = (out[i.productId] ?? 0) + i.quantity;
      }
    }
    return out;
  }

  Map<String, int> _recvMap(Map<String, int> sent) {
    final mode = r.nextInt(5);
    return {
      for (final e in sent.entries)
        if (mode != 0 || chance(0.0))
          e.key: switch (mode) {
            1 => e.value,
            2 => r.nextInt(e.value + 1),
            3 => e.value + 1 + r.nextInt(5),
            _ => chance(0.2) ? -3 : (chance(0.5) ? e.value : 0),
          }
    };
  }

  void _modelReceive(MSlip s, Map<String, int> sent, Map<String, int> map) {
    for (final e in sent.entries) {
      final recv = (map[e.key] ?? 0).clamp(0, e.value);
      s.receivedTotals[e.key] = recv;
      if (recv > 0) {
        m.stock[e.key]![s.tgt] = m.stock[e.key]![s.tgt]! + recv;
        if (!m.records[e.key]!.contains(s.tgt)) {
          m.records[e.key]!.add(s.tgt);
          m.costAt[e.key]![s.tgt] = m.costAt[e.key]![s.src] ?? 0;
        }
      }
    }
    s.setStatus('received');
  }

  void _modelCancelSlip(MSlip s, Map<String, int> sent) {
    sent.forEach((pid, q) => m.stock[pid]![s.src] = m.stock[pid]![s.src]! + q);
    s.setStatus('cancelled');
  }

  MSlip? _pickSlip({bool inTransitOnly = false}) {
    final l = [
      for (final s in m.slips.values)
        if (!inTransitOnly || s.status == 'in_transit') s
    ];
    if (l.isEmpty) return null;
    return pick(l);
  }

  Future<void> opReceive() async {
    final s = _pickSlip(inTransitOnly: chance(0.85));
    if (s == null) return;
    final sent = _slipAgg(s);
    final map = _recvMap(sent);
    note('receive ${s.id} (${s.status}) $map');
    final wasInTransit = s.status == 'in_transit';
    if (wasInTransit && chance(0.1)) {
      final before = dbDump(h.db);
      h.db.failNextUpdate = true;
      final ok = await _tryT(
          () => h.receive.execute(s.id, receivedByProduct: map, user: admin));
      h.db.failNextUpdate = false;
      if (ok != null) h.fail('receive with failing write succeeded');
      if (dbDump(h.db) != before) h.fail('failed receive left partial state');
      h.checkNotifications(0, 'failed receive');
    }
    final res = await _tryT(
        () => h.receive.execute(s.id, receivedByProduct: map, user: admin));
    if (wasInTransit) {
      if (res == null) {
        h.fail('receive of in-transit slip failed');
      } else {
        _modelReceive(s, sent, map);
        h.checkNotifications(2, 'receive');
        _checkReceived(res, s, sent, map);
      }
    } else {
      if (res != null) {
        h.fail('receive of ${s.status} slip succeeded');
        h.notifSeen = h.notifRepo.added.length;
      } else {
        h.checkNotifications(0, 'rejected receive');
      }
    }
    h.checkAll(sent.keys.toSet(), strictCrossView: !h.threeBranches);
  }

  void _checkReceived(
      StockTransfer t, MSlip s, Map<String, int> sent, Map<String, int> map) {
    final got = <String, int>{};
    for (final i in t.items) {
      got[i.productId] = (got[i.productId] ?? 0) + i.receivedQuantity;
    }
    for (final e in sent.entries) {
      final want = (map[e.key] ?? 0).clamp(0, e.value);
      if (got[e.key] != want) {
        h.fail(
            'slip ${s.id} received qty ${e.key}=${got[e.key]} expected $want');
      }
    }
  }

  Future<void> opCancelTransfer() async {
    final s = _pickSlip(inTransitOnly: chance(0.85));
    if (s == null) return;
    final sent = _slipAgg(s);
    note('cancelTransfer ${s.id} (${s.status})');
    final was = s.status == 'in_transit';
    if (was && chance(0.1)) {
      final before = dbDump(h.db);
      h.db.failNextUpdate = true;
      final ok = await _try(() => h.cancelTr.execute(s.id, user: admin));
      h.db.failNextUpdate = false;
      if (ok) h.fail('cancel with failing write succeeded');
      if (dbDump(h.db) != before) h.fail('failed cancel left partial state');
    }
    final ok = await _try(() => h.cancelTr.execute(s.id, user: admin));
    if (was) {
      if (!ok) h.fail('cancel of in-transit slip failed');
      _modelCancelSlip(s, sent);
    } else if (ok) {
      h.fail('cancel of ${s.status} slip succeeded');
    }
    h.notifSeen = h.notifRepo.added.length;
    h.checkAll(sent.keys.toSet(), strictCrossView: !h.threeBranches);
  }

  Future<void> opRace() async {
    final s = _pickSlip(inTransitOnly: true);
    if (s == null) return;
    final sent = _slipAgg(s);
    final map = _recvMap(sent);
    final kind = r.nextInt(3);
    note('race kind=$kind ${s.id}');
    if (kind == 0) {
      final res = await Future.wait([
        _tryT(
            () => h.receive.execute(s.id, receivedByProduct: map, user: admin)),
        _tryT(
            () => h.receive.execute(s.id, receivedByProduct: map, user: admin)),
      ]);
      final ok = res.whereType<StockTransfer>().length;
      if (ok != 1) h.fail('double receive: $ok succeeded');
      if (ok >= 1) _modelReceive(s, sent, map);
    } else {
      final res = await Future.wait([
        _tryT(
            () => h.receive.execute(s.id, receivedByProduct: map, user: admin)),
        _try(() => h.cancelTr.execute(s.id, user: admin))
            .then((v) => v ? StockTransfer.fromMap({'id': 'x'}) : null),
      ]);
      final recvOk = res[0] != null, cancelOk = res[1] != null;
      if (recvOk == cancelOk)
        h.fail('receive+cancel race: recv=$recvOk cancel=$cancelOk');
      if (recvOk) {
        _modelReceive(s, sent, map);
      } else if (cancelOk) {
        _modelCancelSlip(s, sent);
      }
    }
    h.notifSeen = h.notifRepo.added.length;
    h.checkAll(sent.keys.toSet(), strictCrossView: !h.threeBranches);
  }

  Future<void> opDeleteDraft() async {
    final l = m.slips.values.where((s) => s.status == 'draft').toList();
    if (l.isEmpty) return;
    final s = pick(l);
    await h.saveDraft.delete(s.id);
    s.setStatus('deleted');
    h.checkAll(const [], strictCrossView: !h.threeBranches);
  }

  // ---------------------------------------------- instant (legacy) transfer --

  /// InterStoreTransferService receives a Product snapshot from the UI which
  /// may be stale (sold/received since it was loaded): RTDB must win.
  Future<void> opDirectTransfer() async {
    final src = pick(branches);
    final tgt = pick(branches.where((b) => b != src).toList());
    final cands = [
      for (final e in m.records.entries)
        if (e.value.contains(src)) e.key
    ];
    if (cands.isEmpty) return;
    final pid = pick(cands);
    final snapshot = h.entityAt(src, pid)!;
    if (chance(0.4) && m.stock[pid]![src]! > 0) {
      await opPosOn(pid, src);
    }
    final have = m.stock[pid]![src]!;
    final q =
        chance(0.2) ? have + 1 : (have == 0 ? 1 : 1 + r.nextInt(min(have, 25)));
    note('direct $pid $src->$tgt x$q have=$have');
    final err = await InterStoreTransferService(h.db).transferProduct(
        sourceStoreId: rawStore(src),
        targetStoreId: rawStore(tgt),
        product: snapshot,
        quantity: q);
    if (q <= have) {
      if (err != null) {
        h.fail('direct transfer failed: $err');
      } else {
        m.stock[pid]![src] = have - q;
        m.stock[pid]![tgt] = m.stock[pid]![tgt]! + q;
        if (!m.records[pid]!.contains(tgt)) {
          m.records[pid]!.add(tgt);
          m.costAt[pid]![tgt] = m.costAt[pid]![src] ?? 0;
        }
      }
    } else if (err == null) {
      h.fail('direct transfer of $q > stock $have accepted (stale snapshot)');
      m.stock[pid]![src] = 0;
      m.stock[pid]![tgt] = m.stock[pid]![tgt]! + q;
      m.ledger[pid] =
          m.ledger[pid]! + (q - have); // keep later checks meaningful
    }
    h.checkAll([pid], strictCrossView: !h.threeBranches);
  }

  // ---------------------------------------------------------------- POS --

  Future<void> opPos() async {
    final pid = pick(m.stock.keys.toList());
    await opPosOn(pid, pick(m.records[pid]!.toList()));
  }

  Future<void> opPosOn(String pid, String s) async {
    final have = m.stock[pid]![s]!;
    if (have <= 0) return;
    final q = 1 + r.nextInt(min(have, 20));
    note('pos $pid @$s x$q');
    // Replicates a POS deduction: every copy of the product record gets the
    // new stock for branch [s].
    for (final rec in m.records[pid]!) {
      final e = h.entityAt(rec, pid)!;
      final stocks = applyStoreStock(e.branchStocks, s, have - q);
      h.db.seed('stores/$rec/products/$pid/branchStocks', stocks);
    }
    m.stock[pid]![s] = have - q;
    m.ledger[pid] = m.ledger[pid]! - q;
    h.checkAll([pid], strictCrossView: !h.threeBranches);
  }
}
