import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/data/repositories/revenue_repository_impl.dart';

import '../support/fake_rtdb.dart';

Map<String, dynamic> sale(String id, DateTime d, int qty) => {
      'id': id,
      'customerId': 'khach_le',
      'createdAt': d.toIso8601String(),
      'total': 200.0 * qty,
      'amountPaid': 200.0 * qty,
      'status': 'completed',
      'items': [
        {
          'productId': 'p1',
          'productName': 'P',
          'quantity': qty,
          'price': 200.0,
          'warrantyMonths': 0,
          'purchaseDate': d.toIso8601String(),
        }
      ],
    };

Map saleExport(String id, DateTime d, int qty) => {
      'id': 'export_$id',
      'productId': 'p1',
      'type': 'export',
      'quantity': qty,
      'date': d.toIso8601String(),
      'note': id,
      'storeId': 'store_001',
    };

void main() {
  test(
      'FIFO cost: POS sale export transactions must not deplete lots a second time',
      () {
    final db = FakeRtdb();
    final repo = RevenueRepositoryImpl(
      OrderRemoteDataSource(db, 'store_001'),
      InventoryRemoteDataSource(db, 'store_001'),
      ProductRemoteDataSource(db, 'store_001'),
    );
    final d0 = DateTime(2026, 8, 1, 9);
    final d1 = DateTime(2026, 8, 2, 9);
    final d2 = DateTime(2026, 8, 3, 9);
    final imports = <Map>[
      {
        'id': 'imp1',
        'productId': 'p1',
        'type': 'import',
        'quantity': 10,
        'date': d0.toIso8601String(),
        'note': '',
        'importPrice': 100.0,
        'storeId': 'store_001',
      },
      // The stock movements the POS records for each sale (pos_payment_page.dart)
      saleExport('s1', d1, 5),
      saleExport('s2', d2, 5),
    ];
    final report = repo.calculateRevenueSummary(
      orders: [sale('s1', d1, 5), sale('s2', d2, 5)],
      inventoryTransactions: imports,
      // fallback cost (700) must NOT be used: 10 units @100 are in stock
      products: [
        {'id': 'p1', 'name': 'P', 'price': 200.0, 'costPrice': 100.0 * 7}
      ],
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 3),
    );
    // 10 units sold, all from the single 10 @ 100 lot => cost 1000
    expect(report.totalCost, closeTo(1000, 0.001));
  });
}
