// Shared harness + independent reference model for the stock fuzz tests.
//
// The reference model deliberately does NOT reuse the use cases' map-merging
// helpers: it tracks plain truth tables (units per branch/product, cost per
// record, supplier money, slip state) and the checks read the raw fake RTDB.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:stores/application/inventories/usecases/cancel_stock_in_receipt_use_case.dart';
import 'package:stores/application/inventories/usecases/complete_stock_in_receipt_use_case.dart';
import 'package:stores/application/inventories/usecases/stock_transfer_use_cases.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notification_visibility.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/stock_transfer.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/stock_in_receipt_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

import '../../support/fake_rtdb.dart';

int envInt(String name, int def) =>
    int.tryParse(Platform.environment[name] ?? '') ?? def;

final int stressSeed = envInt('STRESS_SEED', 20261014);
final int stressIter = envInt('STRESS_ITER', 1500);

Future<void> initFuzzLocale() => initializeDateFormatting('vi_VN');

// ---------------------------------------------------------------- fakes ----

class NotifRepo implements NotificationRepository {
  final List<NotificationItem> added = [];
  @override
  Future<void> addNotification(NotificationItem n) async => added.add(n);
  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {}
  @override
  Future<void> markAllAsRead(String storeId) async {}
  @override
  Future<void> markAsRead(
      {required String storeId, required String id}) async {}
  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
          {int limit = 50}) =>
      Stream.value(added);
}

/// Store-scoped product repository over the fake RTDB (like the real one).
class DbProductRepo implements ProductRepository {
  DbProductRepo(this.db);
  final FakeRtdb db;
  String scope = 'store_001';
  @override
  Future<Product?> fetchById(String id) async {
    final v = db.read('stores/$scope/products/$id');
    if (v is! Map) return null;
    return ProductModel.fromMap(Map<dynamic, dynamic>.from(v), scope)
        .toEntity();
  }

  // The real repository's upsert is a cache/replication step on top of the
  // atomic multi-path update the use cases already issue; the fuzz verifies the
  // atomic update, so this is intentionally a no-op.
  @override
  Future<void> upsert(Product p) async {}

  @override
  dynamic noSuchMethod(Invocation i) async => null;
}

class DbSupplierRepo implements SupplierRepository {
  DbSupplierRepo(this.db);
  final FakeRtdb db;
  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async {
    final v = db.read('shared_suppliers/$id');
    if (v is! Map) return null;
    return Supplier(
      id: id,
      code: id,
      name: '${v['name']}',
      currentDebt: (v['currentDebt'] as num?)?.toDouble() ?? 0,
      totalPurchase: (v['totalPurchase'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Future<void> upsert(Supplier s, {String? storeId}) async {
    db.seed('shared_suppliers/${s.id}/currentDebt', s.currentDebt);
    db.seed('shared_suppliers/${s.id}/totalPurchase', s.totalPurchase);
  }

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction t,
      {String? storeId}) async {}
  @override
  dynamic noSuchMethod(Invocation i) async => null;
}

class NoopReceiptRepo implements StockInReceiptRepository {
  @override
  dynamic noSuchMethod(Invocation i) async => null;
}

class NoopInvRepo implements InventoryRepository {
  @override
  Future<void> record(InventoryTransaction t) async {}
  @override
  dynamic noSuchMethod(Invocation i) async => null;
}

// ------------------------------------------------------------- helpers -----

const admin = UserAccount(
    username: 'admin', displayName: 'Admin', role: 'admin', storeId: 'all');
const staff = UserAccount(
    username: 'nv', displayName: 'NV', role: 'nhanvien', storeId: 'store_001');
final moneyRe = RegExp(r'\d[\d.,]*\s?(?:đ|₫|vnđ|vnd)', caseSensitive: false);

String canon(String s) {
  switch (s) {
    case 'branch_1':
      return 'store_001';
    case 'branch_2':
      return 'store_002';
  }
  return s;
}

String aliasOf(String s) =>
    s == 'store_001' ? 'branch_1' : (s == 'store_002' ? 'branch_2' : s);

bool near(double a, double b, [double rel = 1e-9]) =>
    (a - b).abs() <= 1e-6 + rel * max(a.abs(), b.abs());

dynamic prune(dynamic v) {
  if (v is Map) {
    final out = <String, dynamic>{};
    for (final e in v.entries) {
      final p = prune(e.value);
      if (p is Map && p.isEmpty) continue;
      out['${e.key}'] = p;
    }
    return out;
  }
  if (v is List) return v.map(prune).toList();
  return v;
}

String dbDump(FakeRtdb db) => jsonEncode(prune(db.read('')));

// -------------------------------------------------------------- model ------

class MSlip {
  MSlip(this.id, this.src, this.tgt, this.lines);
  final String id;
  final String src, tgt; // canonical
  final List<List<dynamic>> lines; // [pid, qty]
  String status = 'draft';
  Map<String, int> receivedTotals = {};
  final List<String> history = ['draft'];
  void setStatus(String s) {
    status = s;
    history.add(s);
  }
}

class MReceipt {
  MReceipt(this.receipt, this.store);
  StockInReceipt receipt;
  final String store;
  String status = 'completed';
  // pre-complete snapshot, used for exact-revert checks
  Map<String, Map<String, int>>? preStock;
  Map<String, Map<String, double>>? preCost;
}

class Model {
  Model(this.branches);
  final List<String> branches;
  // truth units
  final Map<String, Map<String, int>> stock = {}; // pid -> branch -> units
  final Map<String, Map<String, double>> costAt = {}; // pid -> record -> cost
  final Map<String, Set<String>> records = {}; // pid -> stores with a record
  final Map<String, double> supDebt = {};
  final Map<String, double> supTotal = {};
  final Map<String, MSlip> slips = {};
  final Map<String, MReceipt> receipts = {};
  // independent unit ledger: initial + stockIn - removedByCancel - sold
  final Map<String, int> ledger = {};
  final Set<String> costUnknown = {}; // products whose cost can't be asserted
  int ops = 0;

  int totalUnits(String pid) => stock[pid]!.values.fold(0, (a, b) => a + b);
}

// ------------------------------------------------------------ harness ------

class Harness {
  Harness({required this.threeBranches}) {
    db = FakeRtdb();
    repo = FakeStockTransferRepository(db);
    notifRepo = NotifRepo();
    dispatcher = NotificationDispatcher(notifRepo);
    productRepo = DbProductRepo(db);
    supplierRepo = DbSupplierRepo(db);
    complete = CompleteStockInReceiptUseCase(
        db: db,
        productRepository: productRepo,
        inventoryRepository: NoopInvRepo(),
        supplierRepository: supplierRepo,
        receiptRepository: NoopReceiptRepo(),
        notificationDispatcher: dispatcher);
    cancelIn = CancelStockInReceiptUseCase(
        db: db,
        productRepository: productRepo,
        inventoryRepository: NoopInvRepo(),
        supplierRepository: supplierRepo,
        receiptRepository: NoopReceiptRepo(),
        notificationDispatcher: dispatcher);
    saveDraft = SaveStockTransferDraftUseCase(db, repo, dispatcher);
    create = CreateStockTransferUseCase(db, repo, dispatcher);
    receive = ReceiveStockTransferUseCase(db, repo, dispatcher);
    cancelTr = CancelStockTransferUseCase(db, repo, dispatcher);
    model = Model(branches);
  }
  final bool threeBranches;
  late final FakeRtdb db;
  late final FakeStockTransferRepository repo;
  late final NotifRepo notifRepo;
  late final NotificationDispatcher dispatcher;
  late final DbProductRepo productRepo;
  late final DbSupplierRepo supplierRepo;
  late final CompleteStockInReceiptUseCase complete;
  late final CancelStockInReceiptUseCase cancelIn;
  late final SaveStockTransferDraftUseCase saveDraft;
  late final CreateStockTransferUseCase create;
  late final ReceiveStockTransferUseCase receive;
  late final CancelStockTransferUseCase cancelTr;
  late final Model model;
  final List<String> log = [];
  int notifSeen = 0;

  List<String> get branches => threeBranches
      ? const ['store_001', 'store_002', 'store_003']
      : const ['store_001', 'store_002'];

  // ---- seeding ----
  Map<String, dynamic> _stocksDialect(
      Random r, Map<String, int> truth, int dialect) {
    final out = <String, dynamic>{};
    for (final e in truth.entries) {
      final b = e.key;
      final v = e.value;
      dynamic val = v;
      if (dialect == 4) val = '$v';
      if (dialect == 6 && v == 0) val = null;
      switch (dialect) {
        case 1:
          out[b] = val;
          if (b == 'store_001') out['branch_1'] = val;
          if (b == 'store_002') out['branch_2'] = val;
          break;
        case 2:
          if (b == 'store_001') {
            out['branch_1'] = val;
          } else if (b == 'store_002') {
            out['branch_2'] = val;
          } else {
            out[b] = val;
          }
          break;
        case 3:
          if (b == 'store_001') {
            out['ĐT'] = val;
          } else if (b == 'store_002') {
            out['TB'] = val;
          } else {
            out[b] = val;
          }
          break;
        default:
          out[b] = val;
      }
    }
    return out;
  }

  void seedProducts(Random r, int n) {
    for (var i = 0; i < n; i++) {
      final pid = 'p$i';
      final truth = <String, int>{
        for (final b in branches)
          b: r.nextInt(5) == 0
              ? 0
              : (r.nextInt(40) == 0
                  ? 1000000 + r.nextInt(5000000)
                  : r.nextInt(120)),
      };
      final cost =
          const [0.0, 1000.0, 2500.5, 1234.5678, 99999.99, 3.333][r.nextInt(6)];
      final recs = <String>{};
      for (final b in branches) {
        // products missing in some branches (never missing everywhere)
        if (r.nextInt(6) == 0) continue;
        recs.add(b);
      }
      if (recs.isEmpty) recs.add('store_001');
      for (final b in branches) {
        if (!recs.contains(b)) {
          // product absent in this branch => it holds no units there
          truth[b] = 0;
        }
      }
      // second pass: views of absent branches are still written as 0 in
      // records of other stores, so truth stays consistent.
      final isCombo = r.nextInt(8) == 0;
      for (final b in recs) {
        final dialect =
            r.nextInt(7) == 0 ? 0 : [0, 1, 2, 3, 4, 6][r.nextInt(6)];
        db.seed('stores/$b/products/$pid', {
          'id': pid,
          'name': 'Product $pid',
          'code': 'C$pid',
          'price': cost * 1.4,
          'costPrice': cost,
          'category': 'cat',
          'isCombo': isCombo,
          'branchStocks': _stocksDialect(r, truth, dialect),
        });
      }
      model.stock[pid] = truth;
      model.records[pid] = recs;
      model.costAt[pid] = {for (final b in recs) b: cost};
      model.ledger[pid] = truth.values.fold(0, (a, b) => a + b);
    }
    for (final s in ['S1', 'S2', 'S3']) {
      db.seed('shared_suppliers/$s', {
        'id': s,
        'name': 'Supplier $s',
        'currentDebt': 0.0,
        'totalPurchase': 0.0
      });
      model.supDebt[s] = 0;
      model.supTotal[s] = 0;
    }
  }

  // ---- checks ----

  /// Reads the product record of [store] like the app does.
  Product? entityAt(String store, String pid) {
    final v = db.read('stores/$store/products/$pid');
    if (v is! Map) return null;
    return ProductModel.fromMap(Map<dynamic, dynamic>.from(v), store)
        .toEntity();
  }

  final List<String> violations = [];
  void fail(String msg) => violations.add(msg);

  void checkAll(Iterable<String>? only, {bool strictCrossView = true}) {
    final m = model;
    final pids = only ?? m.stock.keys;
    // no junk store nodes
    final stores = db.read('stores');
    if (stores is Map) {
      for (final k in stores.keys) {
        if (!branches.contains('$k')) fail('junk node stores/$k in RTDB');
      }
    }
    for (final pid in pids) {
      final truth = m.stock[pid]!;
      for (final s in branches) {
        final raw = db.read('stores/$s/products/$pid');
        final shouldExist = m.records[pid]!.contains(s);
        if ((raw is Map) != shouldExist) {
          fail('$pid record at $s exists=${raw is Map} expected $shouldExist');
          continue;
        }
        if (raw is! Map) continue;
        final e = entityAt(s, pid)!;
        // own view
        final own = e.stockInBranch(s);
        if (own != truth[s]) {
          fail(
              '$pid own view at $s = $own expected ${truth[s]} raw=${raw['branchStocks']}');
        }
        // cross views (strict in the 2-branch world)
        if (strictCrossView) {
          for (final b in branches) {
            if (e.stockInBranch(b) != truth[b]) {
              fail(
                  '$pid record@$s views $b=${e.stockInBranch(b)} truth=${truth[b]} raw=${raw['branchStocks']}');
            }
          }
        }
        // raw alias consistency + no negatives
        final bs = raw['branchStocks'];
        if (bs is Map) {
          for (final v in bs.values) {
            final n = v is num ? v : num.tryParse('$v') ?? 0;
            if (n < 0) fail('$pid@$s negative stock in raw $bs');
          }
          void alias(String a, String b) {
            if (bs.containsKey(a) &&
                bs.containsKey(b) &&
                '${bs[a]}' != '${bs[b]}') {
              fail('$pid@$s alias mismatch $a=${bs[a]} $b=${bs[b]}');
            }
          }

          alias('store_001', 'branch_1');
          alias('store_002', 'branch_2');
        }
        // cost
        if (!m.costUnknown.contains(pid)) {
          final c = m.costAt[pid]![s];
          if (c != null && !near(e.costPrice, c, 1e-7)) {
            fail('$pid cost at $s = ${e.costPrice} expected $c');
          }
        }
        if (e.stock < 0) fail('$pid negative total');
      }
    }
    _checkSlipsAndIndex();
    _checkConservation(pids);
    _checkSuppliers();
  }

  void _checkSlipsAndIndex() {
    final raw = db.read('stock_transfers');
    final inTransitFor = <String, Set<String>>{
      for (final b in branches) b: <String>{}
    };
    final dbSlips = <String, StockTransfer>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.value is! Map) continue;
        dbSlips['${e.key}'] = StockTransfer.fromMap(e.value as Map);
      }
    }
    for (final ms in model.slips.values) {
      final t = dbSlips[ms.id];
      if (t == null) {
        if (ms.status != 'deleted') fail('slip ${ms.id} missing in db');
        continue;
      }
      if (t.status.value != ms.status) {
        fail('slip ${ms.id} db=${t.status.value} model=${ms.status}');
      }
      // legal transitions
      const legal = {
        'draft': {'in_transit', 'deleted'},
        'in_transit': {'received', 'cancelled'},
        'received': <String>{},
        'cancelled': <String>{},
        'deleted': <String>{},
      };
      for (var i = 1; i < ms.history.length; i++) {
        if (!legal[ms.history[i - 1]]!.contains(ms.history[i])) {
          fail('illegal slip transition ${ms.history}');
        }
      }
    }
    for (final t in dbSlips.values) {
      if (t.isInTransit) {
        final k = canon(t.targetStoreId);
        inTransitFor.putIfAbsent(k, () => <String>{}).add(t.id);
      }
      // quantities sane
      for (final i in t.items) {
        if (i.receivedQuantity < 0 || i.receivedQuantity > i.quantity) {
          fail(
              'slip ${t.id} item ${i.productId} received ${i.receivedQuantity}/${i.quantity}');
        }
      }
    }
    final idx = db.read('stock_transfer_pending');
    if (idx is Map) {
      for (final k in idx.keys) {
        if (!inTransitFor.containsKey('$k')) {
          fail('pending index under unknown/alias store key $k');
        }
      }
    }
    for (final e in inTransitFor.entries) {
      final v = db.read('stock_transfer_pending/${e.key}');
      final got = v is Map ? v.keys.map((k) => '$k').toSet() : <String>{};
      if (got.length != e.value.length || !got.containsAll(e.value)) {
        fail('pending index ${e.key}: $got vs in-transit slips ${e.value}');
      }
    }
  }

  void _checkConservation(Iterable<String> pids) {
    // Units in the DB (branch truth read from each branch's OWN record, or 0
    // where it has none) + in transit + shortfall (lost) == independent ledger.
    final raw = db.read('stock_transfers');
    final transit = <String, int>{};
    final lost = <String, int>{};
    if (raw is Map) {
      for (final v in raw.values) {
        if (v is! Map) continue;
        final t = StockTransfer.fromMap(v);
        for (final i in t.items) {
          if (t.isInTransit) {
            transit[i.productId] = (transit[i.productId] ?? 0) + i.quantity;
          } else if (t.isReceived) {
            lost[i.productId] =
                (lost[i.productId] ?? 0) + (i.quantity - i.receivedQuantity);
          }
        }
      }
    }
    for (final pid in pids) {
      var units = 0;
      for (final b in branches) {
        final e = entityAt(b, pid);
        if (e != null) units += e.stockInBranch(b);
      }
      final sum = units + (transit[pid] ?? 0) + (lost[pid] ?? 0);
      if (sum != model.ledger[pid]) {
        fail(
            'conservation $pid: stock=$units transit=${transit[pid] ?? 0} lost=${lost[pid] ?? 0} sum=$sum ledger=${model.ledger[pid]}');
      }
    }
  }

  void _checkSuppliers() {
    for (final s in model.supDebt.keys) {
      final d = (db.read('shared_suppliers/$s/currentDebt') as num).toDouble();
      final t =
          (db.read('shared_suppliers/$s/totalPurchase') as num).toDouble();
      if (!near(d, model.supDebt[s]!))
        fail('supplier $s debt $d vs ${model.supDebt[s]}');
      if (!near(t, model.supTotal[s]!))
        fail('supplier $s total $t vs ${model.supTotal[s]}');
      if (d < 0) fail('supplier $s negative debt');
    }
    for (final r in model.receipts.values) {
      final st =
          db.read('stores/${r.store}/stock_in_receipts/${r.receipt.id}/status');
      if (st != r.status)
        fail('receipt ${r.receipt.id} status $st vs ${r.status}');
    }
  }

  /// Notification checks for items added since the last call.
  void checkNotifications(int expectedNew, String what) {
    final fresh = notifRepo.added.sublist(notifSeen);
    notifSeen = notifRepo.added.length;
    if (fresh.length != expectedNew) {
      fail('$what: expected $expectedNew notifications, got ${fresh.length}');
    }
    final perStore = <String, int>{};
    for (final n in fresh) {
      perStore[n.storeId] = (perStore[n.storeId] ?? 0) + 1;
      if (!branches.contains(n.storeId)) {
        fail('$what: notification for non-canonical store ${n.storeId}');
      }
    }
    if (perStore.values.any((c) => c > 1)) {
      fail('$what: duplicate notification per store $perStore');
    }
    for (final n in notificationsForViewer(fresh, staff)) {
      if (moneyRe.hasMatch(n.body)) {
        fail('$what: staff-visible body leaks money: ${n.body}');
      }
    }
  }
}
