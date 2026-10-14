import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/attendance_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/auth_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/category_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/customer_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/fcm_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/notification_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/store_payment_config_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/supplier_remote_data_source.dart';
import 'package:stores/data/datasources/stock_in_receipt_remote_data_source.dart';

import '../../support/firebase_test_harness.dart';

/// Spy database: records the SHAPE of every read (get / onValue / onChild*)
/// including limit/range/equalTo constraints (the shared MockQuery recorder
/// does not log limits or listeners).
class Shape {
  Shape(this.api, this.kind, this.path, this.orderBy, this.start, this.end,
      this.equalTo, this.limitFirst, this.limitLast, this.point);
  final String api; // e.g. OrderDS.watchByDateRange
  final String kind; // get | onValue | onChildAdded | onChildChanged | onChildRemoved
  final String path;
  final String? orderBy;
  final Object? start, end, equalTo;
  final int? limitFirst, limitLast;
  final bool point; // single-record path reached through child(id)

  bool get constrained =>
      limitFirst != null || limitLast != null || start != null || end != null || equalTo != null;
  bool get bounded => constrained || point;
  @override
  String toString() => '$api $kind $path'
      '${orderBy != null ? ' orderBy=$orderBy' : ''}'
      '${equalTo != null ? ' eq' : ''}${start != null ? ' start' : ''}${end != null ? ' end' : ''}'
      '${limitFirst != null ? ' first=$limitFirst' : ''}${limitLast != null ? ' last=$limitLast' : ''}'
      '${point ? ' (point)' : ''}';
}

class SpyDb extends Fake implements FirebaseDatabase {
  final List<Shape> shapes = [];
  String api = '';
  @override
  DatabaseReference ref([String? path]) =>
      _Q(this, (path ?? '').split('/').where((e) => e.isNotEmpty).join('/'));
}

class _Q extends Fake implements DatabaseReference {
  _Q(this.db, this.p,
      {this.ob, this.s, this.e, this.eq, this.lf, this.ll, this.pt = false});
  final SpyDb db;
  final String p;
  final String? ob;
  final Object? s, e, eq;
  final int? lf, ll;
  final bool pt;

  _Q _c({String? path, String? ob, Object? s, Object? e, Object? eq, int? lf, int? ll, bool? pt}) =>
      _Q(db, path ?? p,
          ob: ob ?? this.ob, s: s ?? this.s, e: e ?? this.e, eq: eq ?? this.eq,
          lf: lf ?? this.lf, ll: ll ?? this.ll, pt: pt ?? this.pt);

  void _rec(String kind) =>
      db.shapes.add(Shape(db.api, kind, p, ob, s, e, eq, lf, ll, pt));

  @override
  DatabaseReference child(String path) => _c(path: '$p/$path', pt: true);
  @override
  Query orderByChild(String path) => _c(ob: path);
  @override
  Query orderByKey() => _c(ob: r'$key');
  @override
  Query startAt(Object? value, {String? key}) => _c(s: value);
  @override
  Query endAt(Object? value, {String? key}) => _c(e: value);
  @override
  Query equalTo(Object? value, {String? key}) => _c(eq: value);
  @override
  Query limitToFirst(int limit) => _c(lf: limit);
  @override
  Query limitToLast(int limit) => _c(ll: limit);
  @override
  Future<DataSnapshot> get() async {
    _rec('get');
    return MockDataSnapshot(value: null);
  }

  @override
  Stream<DatabaseEvent> get onValue {
    _rec('onValue');
    return const Stream.empty();
  }

  @override
  Stream<DatabaseEvent> get onChildAdded {
    _rec('onChildAdded');
    return const Stream.empty();
  }

  @override
  Stream<DatabaseEvent> get onChildChanged {
    _rec('onChildChanged');
    return const Stream.empty();
  }

  @override
  Stream<DatabaseEvent> get onChildRemoved {
    _rec('onChildRemoved');
    return const Stream.empty();
  }

  @override
  Future<void> set(Object? value, {Object? priority}) async {}
  @override
  Future<void> update(Map<String, Object?> value) async {}
  @override
  Future<void> remove() async {}
}

String norm(String path) => path
    .replaceAll(RegExp(r'^stores/[^/]+/'), 'stores/\$store/')
    .replaceAllMapped(RegExp(r'(shared_suppliers|shared_customers|attendances|orders|products)/[^/]+'),
        (m) => '${m[1]}/\$id');

void main() {
  late SpyDb db;
  final dt = DateTime(2026, 10, 14);

  Future<void> run(String api, dynamic Function() body) async {
    db.api = api;
    try {
      final r = body();
      if (r is Stream) {
        final sub = r.listen((_) {}, onError: (_) {});
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await sub.cancel();
      } else if (r is Future) {
        await r.timeout(const Duration(seconds: 2));
      }
    } catch (_) {
      // some methods may fail on empty snapshots; only the issued queries matter
    }
  }

  setUp(() => db = SpyDb());

  Future<void> exerciseAll() async {
    const s = 'store_001';
    final order = OrderRemoteDataSource(db, s);
    await run('Order.fetchById', () => order.fetchById('x'));
    await run('Order.watchByCustomer', () => order.watchByCustomer('c'));
    await run('Order.watchDraftOrders', () => order.watchDraftOrders());
    await run('Order.watchRecentOrders', () => order.watchRecentOrders());
    await run('Order.watchAll', () => order.watchAll());
    await run('Order.watchByDateRange', () => order.watchByDateRange(dt, dt));
    await run('Order.fetchByDateRange', () => order.fetchByDateRange(dt, dt));
    await run('Order.fetchReturnById', () => order.fetchReturnById('r'));
    await run('Order.watchReturnsByDateRange', () => order.watchReturnsByDateRange(dt, dt));
    await run('Order.watchReturnsByOrderId', () => order.watchReturnsByOrderId('o'));
    await run('Order.watchAllReturns', () => order.watchAllReturns());

    final inv = InventoryRemoteDataSource(db, s);
    await run('Inventory.watchByProduct', () => inv.watchByProduct('p'));
    await run('Inventory.watchRecentTransactions', () => inv.watchRecentTransactions());
    await run('Inventory.fetchAll', () => inv.fetchAll());
    await run('Inventory.fetchTransactionsUpToDate', () => inv.fetchTransactionsUpToDate(dt));
    await run('Inventory.fetchLotTransactionsUpToDate',
        () => inv.fetchLotTransactionsUpToDate(dt, neededQty: {'p': 5}));
    await run('Inventory.watchImportsByDateRange', () => inv.watchImportsByDateRange(dt, dt));
    await run('Inventory.fetchImportsByDateRange', () => inv.fetchImportsByDateRange(dt, dt));
    await run('Inventory.getLatestImportPrice', () => inv.getLatestImportPrice('p'));

    final prod = ProductRemoteDataSource(db, s);
    await run('Product.watchAll', () => prod.watchAll());
    await run('Product.fetchAll', () => prod.fetchAll());
    await run('Product.fetchById', () => prod.fetchById('p'));

    final cust = CustomerRemoteDataSource(db);
    await run('Customer.watchAll', () => cust.watchAll());
    await run('Customer.fetchById', () => cust.fetchById('c'));
    await run('Customer.watchDebtTransactions', () => cust.watchDebtTransactions('c'));

    final cat = CategoryRemoteDataSource(db);
    await run('Category.watchAll', () => cat.watchAll());
    await run('Category.fetchAll', () => cat.fetchAll());

    final sup = SupplierRemoteDataSource(db);
    await run('Supplier.watchAll', () => sup.watchAll());
    await run('Supplier.fetchById', () => sup.fetchById('x'));
    await run('Supplier.watchDebtTransactions', () => sup.watchDebtTransactions('x'));
    await run('Supplier.fetchDebtTransactions', () => sup.fetchDebtTransactions('x'));

    final notif = NotificationRemoteDataSource(db);
    await run('Notification.watch', () => notif.watchNotifications(s));
    await run('Notification.fetch', () => notif.fetchNotifications(s));

    final rec = StockInReceiptRemoteDataSource(db);
    await run('Receipt.getReceipt', () => rec.getReceipt(s, 'r'));
    await run('Receipt.fetchReceipts', () => rec.fetchReceipts(s));
    await run('Receipt.watchReceipts', () => rec.watchReceipts(s));
    await run('Receipt.getLatestImportPrice', () => rec.getLatestImportPrice(storeId: s, productId: 'p'));

    final att = AttendanceRemoteDataSource(db: db);
    await run('Attendance.getShifts', () => att.getShifts());
    await run('Attendance.watchShifts', () => att.watchShifts());
    await run('Attendance.getAttendances(date)', () => att.getAttendances(storeId: s, dateStr: '2026-10-14'));
    await run('Attendance.getAttendances(month)', () => att.getAttendances(storeId: s, monthPrefix: '2026-10'));
    await run('Attendance.getAttendanceById', () => att.getAttendanceById('a'));
    await run('Attendance.watchAttendances', () => att.watchAttendances(storeId: s, dateStr: '2026-10-14'));
    await run('Attendance.getAdjustments', () => att.getAdjustments());
    await run('Attendance.watchAdjustments', () => att.watchAdjustments());

    final fcm = FcmRemoteDataSource(db);
    await run('Fcm.getAdminTokens', () => fcm.getAdminTokens(storeId: s));
    final auth = AuthRemoteDataSource(db);
    await run('Auth.watchAllAccounts', () => auth.watchAllAccounts());
    await run('Auth.getAccountPassword', () => auth.getAccountPassword('u'));
    final cfg = StorePaymentConfigRemoteDataSource(db);
    await run('PaymentCfg.watch', () => cfg.watchConfig(s));
    await run('PaymentCfg.fetch', () => cfg.fetchConfig(s));
  }

  test('every datasource read is bounded, except the documented catalog/collection reads',
      () async {
    await exerciseAll();
    final unbounded = db.shapes.where((x) => !x.bounded && x.path != '.info/serverTimeOffset').toList();
    final byApi = <String, Set<String>>{};
    for (final u in unbounded) {
      byApi.putIfAbsent(u.api, () => {}).add('${u.kind} ${norm(u.path)}');
    }
    // ignore: avoid_print
    print('Recorded ${db.shapes.length} read shapes; UNBOUNDED (whole-node) reads:\n'
        '${byApi.entries.map((e) => '  ${e.key}: ${e.value.join(', ')}').join('\n')}');

    // Known whole-node reads. Catalog/master collections (products, customers,
    // categories, suppliers, accounts, shifts, one config) are intentionally
    // cached listeners; anything NEW appearing here fails the test.
    const expected = <String>{
      'Product.watchAll', // 3 child listeners on stores/$store/products
      'Product.fetchAll', // stores/$store/products get()
      'Customer.watchAll', // shared_customers
      'Category.watchAll',
      'Category.fetchAll',
      'Supplier.watchAll',
      // Per-entity growing history (RISKY to cap: changes the visible ledger).
      'Supplier.watchDebtTransactions',
      'Supplier.fetchDebtTransactions',
      'Auth.watchAllAccounts', // stores/accounts
      'Attendance.getShifts', // shifts (tiny)
      'Attendance.watchShifts',
      'Fcm.getAdminTokens', // tokens of one store (small)
      'PaymentCfg.watch', // single config doc
      'PaymentCfg.fetch',
    };
    expect(byApi.keys.toSet().difference(expected), isEmpty,
        reason: 'new unbounded read(s): ${byApi.keys.toSet().difference(expected)}');
  });

  test('transaction-like collections are always range/limit constrained', () async {
    await exerciseAll();
    const heavy = [
      'stores/\$store/orders',
      'stores/\$store/return_orders',
      'stores/\$store/inventory_transactions',
      'stores/\$store/stock_in_receipts',
      'stores/\$store/notifications',
      'attendances',
      'attendance_adjustments',
    ];
    for (final x in db.shapes) {
      if (!heavy.contains(norm(x.path))) continue;
      expect(x.constrained, isTrue, reason: 'unconstrained read on heavy collection: $x');
    }
  });

  test('time-series reads carry a limit or a date range (no equalTo-only on growing data)',
      () async {
    await exerciseAll();
    // attendances by storeId only (no date) would download the whole history.
    final att = db.shapes.where((x) => x.api == 'Attendance.getAttendances(month)').toList();
    expect(att, isNotEmpty);
    for (final x in att) {
      expect(x.start, isNotNull);
      expect(x.end, isNotNull);
      expect(x.orderBy, 'date');
    }
    expect(db.shapes.where((x) => x.api == 'Attendance.getAttendanceById').every((x) => x.point), isTrue);
  });

  test('listener cap: each watch* opens at most 4 listeners (3 child + 1 limitToFirst(1))',
      () async {
    await exerciseAll();
    final perApi = <String, int>{};
    for (final x in db.shapes.where((x) => x.kind != 'get')) {
      perApi[x.api] = (perApi[x.api] ?? 0) + 1;
    }
    perApi.forEach((api, n) {
      expect(n, lessThanOrEqualTo(4), reason: '$api opens $n listeners');
    });
    // watchRecent*/whole-collection watchers add exactly one tiny empty-check query
    for (final api in ['Order.watchRecentOrders', 'Inventory.watchRecentTransactions', 'Product.watchAll', 'Customer.watchAll']) {
      expect(db.shapes.where((x) => x.api == api && x.limitFirst == 1).length, 1, reason: api);
    }
    // recent watchers are capped
    expect(
        db.shapes.where((x) => x.api == 'Order.watchRecentOrders' && x.kind == 'onChildAdded').single.limitLast,
        50);
  });

  test('LOT paging is capped: fetchLotTransactionsUpToDate issues at most maxPages bounded queries',
      () async {
    db.api = 'lots';
    final inv = InventoryRemoteDataSource(db, 'store_001');
    await inv.fetchLotTransactionsUpToDate(dt, neededQty: {'p': 5}, pageSize: 100, maxPages: 5);
    final gets = db.shapes.where((x) => x.kind == 'get').toList();
    expect(gets.length, lessThanOrEqualTo(5));
    expect(gets.every((x) => x.limitLast == 100 && x.end != null), isTrue);
  });
}
