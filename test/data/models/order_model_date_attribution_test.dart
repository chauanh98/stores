import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/data/models/order_model.dart';
import 'package:stores/data/repositories/revenue_repository_impl.dart';

class _FakeOrderRemoteDataSource extends Fake implements OrderRemoteDataSource {
  @override
  String get storeId => 'store_002';
}

class _FakeInventoryRemoteDataSource extends Fake implements InventoryRemoteDataSource {}

class _FakeProductRemoteDataSource extends Fake implements ProductRemoteDataSource {}

void main() {
  group('OrderModel Date Attribution & HD013218 Fix', () {
    test('OrderModel.fromMap prioritizes orderDate over createdAt', () {
      final map = {
        'id': 'HD013218',
        'code': 'HD013218',
        'orderDate': '2026-09-19T16:17:25.000',
        'createdAt': '2026-09-20T10:38:04.000', // update time logged by KV
        'total': 1860000.0,
        'discount': 30000.0,
        'amountPaid': 600000.0,
        'status': 'Hoàn thành',
        'items': [],
      };

      final order = OrderModel.fromMap(map);

      // Must be attributed to 19/09/2026 (orderDate), NOT 20/09/2026!
      expect(order.createdAt.year, equals(2026));
      expect(order.createdAt.month, equals(9));
      expect(order.createdAt.day, equals(19));
      expect(order.createdAt.hour, equals(16));
      expect(order.createdAt.minute, equals(17));
      expect(order.createdAt.second, equals(25));
    });

    test('OrderModel.toMap includes orderDate matching createdAt', () {
      final order = OrderModel(
        id: 'HD013218',
        customerId: 'KH006955',
        createdAt: DateTime(2026, 9, 19, 16, 17, 25),
        items: [],
        total: 1860000.0,
        discount: 30000.0,
        status: 'Hoàn thành',
      );

      final map = order.toMap();
      expect(map['orderDate'], equals('2026-09-19T16:17:25.000'));
      expect(map['createdAt'], equals('2026-09-19T16:17:25.000'));
    });

    test('RevenueRepositoryImpl attributes order with orderDate to correct day', () {
      final repo = RevenueRepositoryImpl(
        _FakeOrderRemoteDataSource(),
        _FakeInventoryRemoteDataSource(),
        _FakeProductRemoteDataSource(),
      );

      final orders = [
        {
          'id': 'HD013218',
          'orderDate': '2026-09-19T16:17:25.000',
          'createdAt': '2026-09-20T10:38:04.000',
          'total': 1860000.0,
          'discount': 30000.0,
          'status': 'Hoàn thành',
          'items': [],
        },
      ];

      final summary = repo.calculateRevenueSummary(
        orders: orders,
        inventoryTransactions: [],
        products: [],
        startDate: DateTime(2026, 9, 19),
        endDate: DateTime(2026, 9, 20),
      );

      final dailyReports = summary.dailyReports;

      expect(dailyReports.length, equals(2));

      // Report for 19/09/2026
      final rep19 = dailyReports.firstWhere((r) => r.date.day == 19);
      expect(rep19.totalOrders, equals(1));
      expect(rep19.totalRevenue, equals(1830000.0)); // 1.860.000 - 30.000 net

      // Report for 20/09/2026 must be 0!
      final rep20 = dailyReports.firstWhere((r) => r.date.day == 20);
      expect(rep20.totalOrders, equals(0));
      expect(rep20.totalRevenue, equals(0.0));
    });
  });
}
