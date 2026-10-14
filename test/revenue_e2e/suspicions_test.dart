import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/models/order_model.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../audit/audit_support.dart';

// ---- minimal RTDB query fake: orderByChild + endAt + limitToLast ----------
class _Snap extends Fake implements DataSnapshot {
  _Snap(this._v);
  final dynamic _v;
  @override
  Object? get value => _v;
}

class _Db extends Fake implements FirebaseDatabase {
  _Db(this.nodes);
  final Map<String, Map<String, dynamic>> nodes; // key -> record
  final List<String> queries = []; // log of executed queries
  int fetchedRecords = 0;
  @override
  DatabaseReference ref([String? path]) => _Q(this);
}

class _Q extends Fake implements DatabaseReference {
  _Q(this.db, {this.orderKey, this.end, this.limit});
  final _Db db;
  final String? orderKey;
  final String? end;
  final int? limit;
  @override
  Query orderByChild(String path) => _Q(db, orderKey: path, end: end, limit: limit);
  @override
  Query endAt(Object? value, {String? key}) =>
      _Q(db, orderKey: orderKey, end: value as String, limit: limit);
  @override
  Query limitToLast(int l) => _Q(db, orderKey: orderKey, end: end, limit: l);
  @override
  Future<DataSnapshot> get() async {
    // Unbounded read is a rule violation => fail loudly.
    if (limit == null) throw StateError('unbounded RTDB read');
    final rows = db.nodes.entries
        .where((e) => end == null || e.value[orderKey]!.toString().compareTo(end!) <= 0)
        .toList()
      ..sort((a, b) => a.value[orderKey]!.toString().compareTo(b.value[orderKey]!.toString()));
    final page = rows.length > limit! ? rows.sublist(rows.length - limit!) : rows;
    db.queries.add('endAt=$end limit=$limit -> ${page.length}');
    db.fetchedRecords += page.length;
    return _Snap({for (final e in page) e.key: e.value});
  }
}

const admin = UserAccount(
    username: 'a', displayName: 'A', role: 'admin', storeId: 'store_001');

void main() {
  group('Suspicion 1: fetchTransactionsUpToDate limitToLast(100) drops old lots', () {
    // Product A's only lot (10@50k) is old; 150 newer imports of OTHER products
    // follow, so the newest 100 records do not contain A's lot.
    Map<String, Map<String, dynamic>> busyStore() {
      final m = <String, Map<String, dynamic>>{};
      m['a_old'] = {
        'id': 'a_old', 'productId': 'A', 'type': 'import', 'quantity': 10,
        'date': '2026-09-01T09:00:00.000', 'importPrice': 50000.0,
      };
      for (var i = 0; i < 150; i++) {
        final d = DateTime(2026, 10, 1).add(Duration(minutes: i)).toIso8601String();
        m['k$i'] = {
          'id': 'k$i', 'productId': 'X$i', 'type': 'import', 'quantity': 1,
          'date': d, 'importPrice': 1000.0,
        };
      }
      return m;
    }

    final end = DateTime(2026, 10, 14, 23, 59, 59);

    test('CONFIRMED: legacy single query loses the lot', () async {
      final ds = InventoryRemoteDataSource(_Db(busyStore()), 's');
      final res = await ds.fetchTransactionsUpToDate(end);
      expect(res.length, 100);
      expect(res.any((m) => m['id'] == 'a_old'), isFalse); // FIFO falls back to costPrice
    });

    test('FIX: lot-aware paging finds the lot, bounded and stops early', () async {
      final db = _Db(busyStore());
      final ds = InventoryRemoteDataSource(db, 's');
      final res = await ds.fetchLotTransactionsUpToDate(end,
          neededQty: {'A': 8}, pageSize: 100, maxPages: 5);
      expect(res.any((m) => m['id'] == 'a_old'), isTrue);
      expect(res.length, 151); // no duplicates across pages
      // page1 100 + page2 51 (<pageSize => exhausted) => 2 bounded queries.
      expect(db.queries.length, 2);
    });

    test('FIX: stops as soon as demand is covered (no extra pages)', () async {
      final db = _Db(busyStore());
      final ds = InventoryRemoteDataSource(db, 's');
      await ds.fetchLotTransactionsUpToDate(end,
          neededQty: {'X149': 1}, pageSize: 100, maxPages: 5);
      expect(db.queries.length, 1); // X149 is in the newest page
    });

    test('FIX: hard cap on pages (bandwidth bound) and empty demand = 1 page',
        () async {
      final db = _Db(busyStore());
      final ds = InventoryRemoteDataSource(db, 's');
      await ds.fetchLotTransactionsUpToDate(end,
          neededQty: {'A': 999}, pageSize: 20, maxPages: 3);
      expect(db.queries.length, 3);
      expect(db.fetchedRecords, lessThanOrEqualTo(60));
      final db2 = _Db(busyStore());
      await InventoryRemoteDataSource(db2, 's')
          .fetchLotTransactionsUpToDate(end, pageSize: 20);
      expect(db2.queries.length, 1);
    });
  });

  group('Suspicion 2: OrderModel.fromMap collapses payment methods to cash', () {
    String m(String raw) => OrderModel.fromMap({
          'id': 'x',
          'total': 1,
          'paymentMethod': raw,
          'items': [],
        }).paymentMethod;

    test('card/wallet/qr/bank values are preserved or normalised to transfer', () {
      expect(m('card'), 'card');
      expect(m('wallet'), 'wallet');
      expect(m('qr'), 'qr');
      expect(m('vietqr'), 'qr');
      expect(m('bank'), 'transfer');
      expect(m('bank_transfer'), 'transfer');
    });

    test('legacy values unchanged', () {
      expect(m('cash'), 'cash');
      expect(m('Tiền mặt'), 'cash');
      expect(m('transfer'), 'transfer');
      expect(m('ck'), 'transfer');
      expect(m('Chuyển khoản'), 'transfer');
      expect(m('banking'), 'transfer');
      expect(m('split'), 'split');
      expect(m('Kết hợp'), 'split');
      expect(m('???'), 'cash');
    });
  });

  group('Suspicion 3: inventory tx id collision for same product on 2 lines', () {
    OrderItem oi(String pid, int q) => OrderItem(
        productId: pid,
        productName: pid,
        quantity: q,
        price: 100,
        warrantyMonths: 0,
        purchaseDate: DateTime(2026, 10, 12));

    Product prod(String id, {List<ComboComponent> combo = const []}) => Product(
        id: id,
        name: id,
        code: id,
        price: 100,
        costPrice: 50,
        branchStocks: const {'store_001': 5},
        category: 'c',
        isCombo: combo.isNotEmpty,
        comboComponents: combo);

    test('cancel: two lines of A => two distinct records, total qty restored', () async {
      final orders = AOrderRepo();
      final prods = AProductRepo()..products['A'] = prod('A');
      // Persist like the real repository: id is the key => collision overwrites.
      final inv = _KeyedInv();
      final uc = CancelInvoiceUseCase(
          orderRepository: orders,
          productRepository: prods,
          inventoryRepository: inv,
          customerRepository: ACustomerRepo());
      final o = Order(
          id: 'HD1',
          customerId: 'khach_le',
          createdAt: DateTime(2026, 10, 12),
          items: [oi('A', 2), oi('A', 3)],
          total: 500,
          amountPaid: 500,
          storeId: 'store_001');
      orders.orders['HD1'] = o;
      await uc.execute(
          order: o, cancelReason: 'x', currentUser: admin, storeId: 'store_001');
      expect(inv.byId.length, 2);
      expect(inv.byId.values.fold<int>(0, (s, t) => s + (t.quantity as int)), 5);
      expect(inv.byId.keys.every((k) => k.startsWith('cancel_import_')), isTrue);
    });

    test('return: two lines of A => distinct ids (single-line id format kept)', () async {
      final orders = AOrderRepo();
      final prods = AProductRepo()..products['A'] = prod('A');
      final inv = _KeyedInv();
      final uc = ProcessReturnOrderUseCase(
          orderRepository: orders,
          productRepository: prods,
          inventoryRepository: inv,
          customerRepository: ACustomerRepo());
      final o = Order(
          id: 'HD1',
          customerId: 'khach_le',
          createdAt: DateTime(2026, 10, 12),
          items: [oi('A', 2), oi('A', 3)],
          total: 500,
          amountPaid: 500,
          storeId: 'store_001');
      orders.orders['HD1'] = o;
      await uc.execute(
          originalOrder: o,
          returnItems: const [
            ReturnOrderItem(productId: 'A', productName: 'A', price: 100, quantity: 1),
            ReturnOrderItem(productId: 'A', productName: 'A', price: 100, quantity: 2),
          ],
          storeId: 'store_001',
          currentUser: admin);
      expect(inv.byId.length, 2);
      expect(inv.byId.values.fold<int>(0, (s, t) => s + (t.quantity as int)), 3);
      expect(inv.byId.keys.every((k) => k.startsWith('return_import_')), isTrue);
    });

    test('single line keeps legacy id format <prefix>_<ms>_<productId>', () async {
      final orders = AOrderRepo();
      final prods = AProductRepo()..products['A'] = prod('A');
      final inv = _KeyedInv();
      final uc = CancelInvoiceUseCase(
          orderRepository: orders,
          productRepository: prods,
          inventoryRepository: inv,
          customerRepository: ACustomerRepo());
      final o = Order(
          id: 'HD2',
          customerId: 'khach_le',
          createdAt: DateTime(2026, 10, 12),
          items: [oi('A', 2)],
          total: 200,
          amountPaid: 200,
          storeId: 'store_001');
      orders.orders['HD2'] = o;
      await uc.execute(
          order: o, cancelReason: 'x', currentUser: admin, storeId: 'store_001');
      expect(inv.byId.keys.single, matches(RegExp(r'^cancel_import_\d+_A$')));
    });
  });
}

/// Inventory repo that, like RTDB `child(id).set`, overwrites on equal ids.
class _KeyedInv extends AInvRepo {
  final Map<String, dynamic> byId = {};
  @override
  Future<void> record(t) async {
    byId[t.id] = t;
  }
}
