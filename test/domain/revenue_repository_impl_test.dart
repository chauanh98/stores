import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/data/repositories/revenue_repository_impl.dart';

// Dummy Fake Data Sources for unit testing without Firebase connection
class FakeOrderRemoteDataSource extends Fake implements OrderRemoteDataSource {
  @override
  String get storeId => 'store_001';
}

class FakeInventoryRemoteDataSource extends Fake
    implements InventoryRemoteDataSource {
  final List<Map> mockData;
  FakeInventoryRemoteDataSource(this.mockData);

  @override
  Future<List<Map>> fetchAll() async => mockData;
}

class FakeProductRemoteDataSource extends Fake
    implements ProductRemoteDataSource {
  final List<Map> mockData;
  FakeProductRemoteDataSource(this.mockData);

  @override
  Future<List<Map>> fetchAll() async => mockData;
}

void main() {
  group('RevenueRepositoryImpl FIFO & Summary Tests', () {
    late RevenueRepositoryImpl repo;
    late List<Map> products;
    late List<Map> inventoryTransactions;

    setUp(() {
      products = [
        {
          'id': 'prod_1',
          'name': 'Bình nước giữ nhiệt 500ml',
          'code': 'BN500',
          'price': 100000.0,
          'costPrice': 50000.0,
          'branchStocks': {'branch_1': 10},
          'category': 'Gia dụng',
        },
        {
          'id': 'prod_no_import',
          'name': 'Cáp sạc Type-C',
          'code': 'CAP01',
          'price': 60000.0,
          'costPrice': 30000.0,
          'branchStocks': {'branch_1': 5},
          'category': 'Phụ kiện',
        }
      ];

      inventoryTransactions = [
        {
          'id': 'tx_1',
          'productId': 'prod_1',
          'type': 'import',
          'quantity': 5,
          'date': DateTime(2024, 1, 1).toIso8601String(),
          'importPrice': 40000.0, // 40k
        },
        {
          'id': 'tx_2',
          'productId': 'prod_1',
          'type': 'import',
          'quantity': 10,
          'date': DateTime(2024, 1, 2).toIso8601String(),
          'importPrice': 45000.0, // 45k
        },
      ];

      repo = RevenueRepositoryImpl(
        FakeOrderRemoteDataSource(),
        FakeInventoryRemoteDataSource(inventoryTransactions),
        FakeProductRemoteDataSource(products),
      );
    });

    test('Single-day revenue calculation uses FIFO cost', () {
      final orders = [
        {
          'id': 'order_1',
          'customerId': 'cust_1',
          'createdAt': DateTime(2024, 1, 3, 10, 0).toIso8601String(),
          'total': 600000.0, // 6 cái * 100k
          'status': 'completed',
          'items': [
            {
              'productId': 'prod_1',
              'productName': 'Bình nước giữ nhiệt 500ml',
              'quantity': 6,
              'price': 100000.0,
              'warrantyMonths': 0,
              'purchaseDate': DateTime(2024, 1, 3, 10, 0).toIso8601String(),
            }
          ],
        }
      ];

      final report = repo.calculateRevenueReport(
        orders: orders,
        inventoryTransactions: inventoryTransactions,
        products: products,
        date: DateTime(2024, 1, 3),
      );

      // Cost = 5 * 40k + 1 * 45k = 200k + 45k = 245k
      expect(report.totalRevenue, equals(600000.0));
      expect(report.totalCost, equals(245000.0));
      expect(report.profit, equals(355000.0));
      expect(report.totalOrders, equals(1));
      expect(report.totalItemsSold, equals(6));
    });

    test('Fallback to product.costPrice when no inventory transaction exists', () {
      final orders = [
        {
          'id': 'order_2',
          'customerId': 'cust_2',
          'createdAt': DateTime(2024, 1, 3, 11, 0).toIso8601String(),
          'total': 180000.0, // 3 * 60k
          'status': 'completed',
          'items': [
            {
              'productId': 'prod_no_import',
              'productName': 'Cáp sạc Type-C',
              'quantity': 3,
              'price': 60000.0,
              'warrantyMonths': 0,
              'purchaseDate': DateTime(2024, 1, 3, 11, 0).toIso8601String(),
            }
          ],
        }
      ];

      final report = repo.calculateRevenueReport(
        orders: orders,
        inventoryTransactions: inventoryTransactions,
        products: products,
        date: DateTime(2024, 1, 3),
      );

      // Fallback cost = 3 * 30k = 90k
      expect(report.totalRevenue, equals(180000.0));
      expect(report.totalCost, equals(90000.0));
      expect(report.profit, equals(90000.0));
    });

    test('Multi-day revenue summary preserves lot depletion across days (No reset bug)', () {
      final orders = [
        // Day 1: sells 5 items of prod_1 (depleting all 5 items of Lot 1 at 40k)
        {
          'id': 'order_day1',
          'customerId': 'cust_1',
          'createdAt': DateTime(2024, 1, 3, 9, 0).toIso8601String(),
          'total': 500000.0, // 5 * 100k
          'status': 'completed',
          'items': [
            {
              'productId': 'prod_1',
              'productName': 'Bình nước giữ nhiệt 500ml',
              'quantity': 5,
              'price': 100000.0,
              'warrantyMonths': 0,
              'purchaseDate': DateTime(2024, 1, 3, 9, 0).toIso8601String(),
            }
          ],
        },
        // Day 2: sells 3 items of prod_1 (MUST draw from Lot 2 at 45k, not Lot 1)
        {
          'id': 'order_day2',
          'customerId': 'cust_2',
          'createdAt': DateTime(2024, 1, 4, 14, 0).toIso8601String(),
          'total': 300000.0, // 3 * 100k
          'status': 'completed',
          'items': [
            {
              'productId': 'prod_1',
              'productName': 'Bình nước giữ nhiệt 500ml',
              'quantity': 3,
              'price': 100000.0,
              'warrantyMonths': 0,
              'purchaseDate': DateTime(2024, 1, 4, 14, 0).toIso8601String(),
            }
          ],
        }
      ];

      final summary = repo.calculateRevenueSummary(
        orders: orders,
        inventoryTransactions: inventoryTransactions,
        products: products,
        startDate: DateTime(2024, 1, 3),
        endDate: DateTime(2024, 1, 4),
      );

      // Day 1 Cost: 5 * 40k = 200k
      // Day 2 Cost: 3 * 45k = 135k (If reset bug existed, it would have been 3 * 40k = 120k)
      // Total Cost: 200k + 135k = 335k
      expect(summary.totalRevenue, equals(800000.0));
      expect(summary.totalCost, equals(335000.0));
      expect(summary.totalProfit, equals(465000.0));
      expect(summary.dailyReports.length, equals(2));
      expect(summary.dailyReports[0].totalCost, equals(200000.0));
      expect(summary.dailyReports[1].totalCost, equals(135000.0));
    });

    test('Revenue summary with INVENTORY_AUDIT transactions preserves FIFO cost and profit margin', () {
      final auditTransactions = [
        {
          'id': 'tx_1',
          'productId': 'prod_1',
          'type': 'import',
          'quantity': 5,
          'date': DateTime(2024, 1, 1).toIso8601String(),
          'importPrice': 40000.0, // 40k
        },
        {
          'id': 'tx_audit',
          'productId': 'prod_1',
          'type': 'INVENTORY_AUDIT',
          'quantity': 5,
          'date': DateTime(2024, 1, 2).toIso8601String(),
          'note': 'Cân bằng kho trực tiếp (Tồn cũ: 5 -> Tồn mới: 10, chênh lệch: +5)',
          'importPrice': 48000.0, // 48k
        },
      ];

      final orders = [
        {
          'id': 'order_1',
          'customerId': 'cust_1',
          'createdAt': DateTime(2024, 1, 3, 10, 0).toIso8601String(),
          'total': 700000.0, // 7 * 100k
          'status': 'completed',
          'items': [
            {
              'productId': 'prod_1',
              'productName': 'Bình nước giữ nhiệt 500ml',
              'quantity': 7, // 5 * 40k + 2 * 48k = 200k + 96k = 296k
              'price': 100000.0,
              'warrantyMonths': 0,
              'purchaseDate': DateTime(2024, 1, 3, 10, 0).toIso8601String(),
            }
          ],
        }
      ];

      final summary = repo.calculateRevenueSummary(
        orders: orders,
        inventoryTransactions: auditTransactions,
        products: products,
        startDate: DateTime(2024, 1, 3),
        endDate: DateTime(2024, 1, 3),
      );

      // Revenue: 700,000
      // FIFO Cost: 5*40k + 2*48k = 296,000
      // Profit: 700,000 - 296,000 = 404,000
      expect(summary.totalRevenue, equals(700000.0));
      expect(summary.totalCost, equals(296000.0));
      expect(summary.totalProfit, equals(404000.0));
    });
  });
}
