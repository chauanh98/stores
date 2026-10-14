import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/data/repositories/revenue_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

/// Days: D1 = 2026-10-12, D2 = 2026-10-13, D3 = 2026-10-14.
final d1 = DateTime(2026, 10, 12);
final d3 = DateTime(2026, 10, 14);

class FakeOrderDs extends Fake implements OrderRemoteDataSource {
  FakeOrderDs(this.storeId, this.orders);
  @override
  final String storeId;
  final List<Map<String, dynamic>> orders;

  @override
  Stream<List<Map<String, dynamic>>> watchByDateRange(
      DateTime start, DateTime end) {
    final res = orders.where((o) {
      final d = DateTime.parse((o['orderDate'] ?? o['createdAt']).toString());
      return !d.isBefore(start) && !d.isAfter(end);
    }).toList();
    return Stream.value(res);
  }
}

class FakeInvDs extends Fake implements InventoryRemoteDataSource {
  FakeInvDs(this.txs);
  final List<Map> txs;
  int lotCalls = 0;

  @override
  Future<List<Map>> fetchLotTransactionsUpToDate(DateTime endDate,
      {Map<String, int> neededQty = const {},
      int pageSize = 100,
      int maxPages = 5}) async {
    lotCalls++;
    return txs
        .where((t) => !DateTime.parse(t['date'].toString()).isAfter(endDate))
        .toList();
  }
}

class FakeProdDs extends Fake implements ProductRemoteDataSource {
  FakeProdDs(this.products);
  final List<Map> products;
  @override
  Future<List<Map>> fetchAll() async => products;
}

Map<String, dynamic> item(String pid, int qty, double price,
        {int returned = 0}) =>
    {
      'productId': pid,
      'productName': pid,
      'quantity': qty,
      'price': price,
      'originalPrice': price,
      'warrantyMonths': 0,
      'purchaseDate': '2026-10-12T00:00:00.000',
      'returnedQuantity': returned,
    };

Map<String, dynamic> order(
  String id,
  String at,
  List<Map<String, dynamic>> items, {
  required double total,
  double discount = 0,
  String status = 'completed',
  String method = 'cash',
  double? paid,
  double debt = 0,
  double? cash,
  double? transfer,
  String customer = 'khach_le',
  String store = 'store_001',
}) =>
    {
      'id': id,
      'customerId': customer,
      'createdAt': at,
      'orderDate': at,
      'items': items,
      'total': total,
      if (discount > 0) 'discount': discount,
      'status': status,
      'amountPaid': paid ?? (debt > 0 ? total - discount - debt : total - discount),
      'debtAmount': debt,
      'paymentMethod': method,
      'storeId': store,
      if (cash != null) 'cashAmount': cash,
      if (transfer != null) 'transferAmount': transfer,
    };

Map inv(String id, String pid, String type, int qty, String date,
        {double? price, String store = 'store_001', Map<String, dynamic>? extra}) =>
    {
      'id': id,
      'productId': pid,
      'type': type,
      'quantity': qty,
      'date': date,
      'note': '',
      if (price != null) 'importPrice': price,
      'storeId': store,
      ...?extra,
    };

final products = <Map>[
  {'id': 'A', 'name': 'A', 'price': 100000.0, 'costPrice': 60000.0},
  {'id': 'B', 'name': 'B', 'price': 50000.0, 'costPrice': 30000.0},
  {'id': 'C', 'name': 'C', 'price': 40000.0, 'costPrice': 20000.0},
  {'id': 'COMBO1', 'name': 'Combo', 'price': 150000.0, 'costPrice': 90000.0},
];

/// Branch 1 (store_001) lots, hand-computed state at 2026-10-12:
///  A: import 10@50k (10-01), 20@55k (10-05), audit -2 (10-06) => L1 8,
///     audit +5@58k (10-07) => L3 5@58k, transfer-export 3 (10-08) => L1 5,
///     POS 'export_*' tx qty 4 must be IGNORED.
///  => A lots: L1 5@50k, L2 20@55k, L3 5@58k.
///  B: import 15@28k (10-02), 10@32k (10-09).
final b1Inventory = <Map>[
  inv('imp_a1', 'A', 'import', 10, '2026-10-01T09:00:00.000', price: 50000),
  inv('imp_a2', 'A', 'import', 20, '2026-10-05T09:00:00.000', price: 55000),
  inv('aud_a_neg', 'A', 'INVENTORY_AUDIT', 2, '2026-10-06T09:00:00.000',
      extra: {'isAuditNegative': true, 'auditDifference': -2}),
  inv('aud_a_pos', 'A', 'INVENTORY_AUDIT', 5, '2026-10-07T09:00:00.000',
      price: 58000, extra: {'isAuditNegative': false, 'auditDifference': 5}),
  inv('xfer_out_a', 'A', 'export', 3, '2026-10-08T09:00:00.000'),
  inv('export_1700000000_A', 'A', 'export', 4, '2026-10-09T09:00:00.000'),
  inv('imp_b1', 'B', 'import', 15, '2026-10-02T09:00:00.000', price: 28000),
  inv('imp_b2', 'B', 'import', 10, '2026-10-09T09:00:00.000', price: 32000),
];

final b2Inventory = <Map>[
  inv('imp2_a1', 'A', 'import', 10, '2026-10-03T09:00:00.000',
      price: 52000, store: 'store_002'),
];

List<Map<String, dynamic>> branch1Orders() => [
      // D1
      order('O1', '2026-10-12T09:00:00.000',
          [item('A', 3, 100000), item('B', 2, 50000)],
          total: 400000, method: 'cash'),
      order('O2', '2026-10-12T23:59:59.000', [item('A', 4, 100000)],
          total: 400000,
          discount: 20000,
          method: 'split',
          cash: 200000,
          transfer: 180000,
          paid: 380000),
      // D2 (00:00:00 boundary)
      order('O3', '2026-10-13T00:00:00.000', [item('B', 5, 50000)],
          total: 250000, method: 'transfer'),
      order('O4', '2026-10-13T10:00:00.000', [item('A', 12, 90000)],
          total: 1080000,
          discount: 80000,
          method: 'cash',
          paid: 400000,
          debt: 600000,
          customer: 'c1'),
      order('O5', '2026-10-13T11:00:00.000', [item('A', 50, 100000)],
          total: 5000000, status: 'cancelled'),
      order('O6', '2026-10-13T12:00:00.000', [item('B', 1, 50000)],
          total: 50000, status: 'draft', paid: 0),
      order('O7', '2026-10-13T14:00:00.000', [item('C', 2, 40000)],
          total: 80000, method: 'card', transfer: 80000, cash: 0),
      // D3
      // O8: originally A x10 + B x4 = 1,200,000; 2 A returned (refund 200k) =>
      // stored total 1,000,000 (return use case already reduced it).
      order('O8', '2026-10-14T08:00:00.000',
          [item('A', 10, 100000, returned: 2), item('B', 4, 50000)],
          total: 1000000, method: 'wallet', transfer: 1000000, cash: 0),
      // O9: fully returned, still status completed in legacy data
      order('O9', '2026-10-14T09:00:00.000', [item('A', 2, 100000, returned: 2)],
          total: 0),
      order('O10', '2026-10-14T10:00:00.000', [item('A', 3, 100000, returned: 3)],
          total: 0, status: 'returned'),
      order('O11', '2026-10-14T15:00:00.000', [item('COMBO1', 1, 150000)],
          total: 150000, method: 'qr', transfer: 150000, cash: 0),
      order('O12', '2026-10-14T16:00:00.000', [item('B', 12, 50000)],
          total: 600000, method: 'bank_transfer', transfer: 600000, cash: 0),
      // Versioned edit: original cancelled (replacement), v2 completed
      order('O13', '2026-10-14T17:00:00.000', [item('A', 1, 100000)],
          total: 100000, status: 'cancelled'),
      order('O13-v2', '2026-10-14T17:00:00.000', [item('A', 1, 100000)],
          total: 100000, method: 'cash'),
    ];

List<Map<String, dynamic>> branch2Orders() => [
      order('P1', '2026-10-12T10:00:00.000', [item('A', 5, 100000)],
          total: 500000, store: 'store_002'),
      order('P2', '2026-10-13T10:00:00.000', [item('A', 8, 100000)],
          total: 800000,
          discount: 50000,
          method: 'transfer',
          store: 'store_002'),
      order('P3', '2026-10-14T12:00:00.000', [item('B', 10, 50000)],
          total: 500000,
          paid: 0,
          debt: 500000,
          customer: 'c2',
          store: 'store_002'),
      order('P4', '2026-10-14T12:30:00.000', [item('B', 3, 50000)],
          total: 150000, status: 'cancelled', store: 'store_002'),
    ];

RevenueRepositoryImpl repoFor(String store, List<Map<String, dynamic>> orders,
        List<Map> inventory) =>
    RevenueRepositoryImpl(
        FakeOrderDs(store, orders), FakeInvDs(inventory), FakeProdDs(products));
