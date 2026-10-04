import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/repositories/revenue_repository_impl.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';

// Fake DataSources for isolated testing
class _FakeOrderRemoteDataSource implements OrderRemoteDataSource {
  @override
  final String storeId = 'store_001';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryRemoteDataSource implements InventoryRemoteDataSource {
  @override
  final String storeId = 'store_001';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductRemoteDataSource implements ProductRemoteDataSource {
  @override
  final String storeId = 'store_001';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Returned Order Revenue & Profit and Customer Sales Verification', () {
    late RevenueRepositoryImpl repo;

    setUp(() {
      repo = RevenueRepositoryImpl(
        _FakeOrderRemoteDataSource(),
        _FakeInventoryRemoteDataSource(),
        _FakeProductRemoteDataSource(),
      );
    });

    test(
        '1 cancelled order + 1 returned order yields exactly 0 net revenue and 0 gross profit (not negative!)',
        () {
      final date = DateTime(2026, 10, 1);

      // Order 1: Cancelled
      final cancelledOrderMap = {
        'id': 'HD000001',
        'customerId': 'cust_01',
        'createdAt': date.toIso8601String(),
        'status': 'cancelled',
        'total': 10000000.0,
        'discount': 0.0,
        'amountPaid': 0.0,
        'debtAmount': 0.0,
        'items': [
          {
            'productId': 'sp_01',
            'productName': 'Bộ bàn ghế',
            'quantity': 1,
            'price': 10000000.0,
            'costPrice': 8000000.0,
            'warrantyMonths': 12,
            'purchaseDate': date.toIso8601String(),
            'returnedQuantity': 0,
          }
        ],
      };

      // Order 2: Returned (HD000002 with 25.000.000 cost/price)
      final returnedOrderMap = {
        'id': 'HD000002',
        'customerId': 'cust_01',
        'createdAt': date.toIso8601String(),
        'status': 'returned',
        'total': 0.0,
        'discount': 0.0,
        'amountPaid': 0.0,
        'debtAmount': 0.0,
        'items': [
          {
            'productId': 'sp_02',
            'productName': 'Tủ thờ gõ đỏ cao cấp',
            'quantity': 1,
            'price': 25000000.0,
            'costPrice': 25000000.0,
            'warrantyMonths': 12,
            'purchaseDate': date.toIso8601String(),
            'returnedQuantity': 1, // Fully returned
          }
        ],
      };

      final products = [
        {
          'id': 'sp_01',
          'name': 'Bộ bàn ghế',
          'price': 10000000.0,
          'costPrice': 8000000.0,
        },
        {
          'id': 'sp_02',
          'name': 'Tủ thờ gõ đỏ cao cấp',
          'price': 25000000.0,
          'costPrice': 25000000.0,
        },
      ];

      final report = repo.calculateRevenueReport(
        orders: [cancelledOrderMap, returnedOrderMap],
        inventoryTransactions: [],
        products: products,
        date: date,
      );

      // Verify that net revenue and gross profit are both strictly 0.0
      expect(report.totalRevenue, equals(0.0));
      expect(report.totalCost, equals(0.0));
      expect(report.profit, equals(0.0));
      expect(report.totalOrders, equals(0));
      expect(report.totalItemsSold, equals(0));
    });

    test(
        'Customer.effectiveTotalSales excludes returned orders from customer purchase history and total sales',
        () {
      const customer = Customer(
        id: 'cust_01',
        name: 'Nguyễn Văn A',
        phone: '0901234567',
        email: 'a@example.com',
        address: '123 Đường ABC',
        purchases: [],
        totalSales: 180466000.0, // Historical sales including the 25M order
      );

      final date = DateTime(2026, 10, 1);

      final validOrder = Order(
        id: 'HD000001',
        customerId: 'cust_01',
        createdAt: date,
        total: 67400000.0,
        items: [
          OrderItem(
            productId: 'p1',
            productName: 'Sản phẩm 1',
            quantity: 1,
            price: 67400000.0,
            warrantyMonths: 12,
            purchaseDate: date,
          ),
        ],
      );

      final returnedOrder = Order(
        id: 'HD000002',
        customerId: 'cust_01',
        createdAt: date,
        status: 'returned',
        total: 25000000.0,
        items: [
          OrderItem(
            productId: 'p2',
            productName: 'Tủ thờ',
            quantity: 1,
            price: 25000000.0,
            warrantyMonths: 12,
            purchaseDate: date,
            returnedQuantity: 1, // Fully returned
          ),
        ],
      );

      final cancelledOrder = Order(
        id: 'HD000003',
        customerId: 'cust_01',
        createdAt: date,
        status: 'cancelled',
        total: 10000000.0,
        items: [],
      );

      final effectiveSales = customer.effectiveTotalSales([
        validOrder,
        returnedOrder,
        cancelledOrder,
      ]);

      // 180.466.000 - 25.000.000 returned = 155.466.000
      expect(effectiveSales, equals(155466000.0));
    });

    test(
        'Customer.displayTotalSales prioritizes netSales when smaller than totalSales to reflect returns',
        () {
      // Case 1: KH006981 with 44.950.000 totalSales, but all returned (netSales = 0.0)
      const fullyReturnedCustomer = Customer(
        id: 'KH006981',
        name: 'afsd',
        phone: '0966777888',
        email: '',
        address: '',
        purchases: [],
        totalSales: 44950000.0,
        netSales: 0.0,
      );
      expect(fullyReturnedCustomer.displayTotalSales, equals(0.0));

      // Case 2: KH006981 with partial return (e.g. 25M returned from 44.95M -> netSales = 19.95M)
      const partiallyReturnedCustomer = Customer(
        id: 'KH006981',
        name: 'afsd',
        phone: '0966777888',
        email: '',
        address: '',
        purchases: [],
        totalSales: 44950000.0,
        netSales: 19950000.0,
      );
      expect(partiallyReturnedCustomer.displayTotalSales, equals(19950000.0));

      // Case 3: Customer with no returns (netSales == null)
      const normalCustomer = Customer(
        id: 'KH000001',
        name: 'Cô Huệ',
        phone: '0986694899',
        email: '',
        address: '',
        purchases: [],
        totalSales: 3000000.0,
        netSales: null,
      );
      expect(normalCustomer.displayTotalSales, equals(3000000.0));
    });

    test(
        'Customer list return deduction logic correctly eliminates returned amounts without double deduction',
        () {
      // Scenario A: Stored totalSales = 44.950.000, netSales was null, return order = 44.950.000
      const custA = Customer(
        id: 'KH006981',
        name: 'afsd',
        phone: '0966777888',
        email: '',
        address: '',
        purchases: [],
        totalSales: 44950000.0,
        netSales: null,
      );

      const returnedForCustomerA = 44950000.0;
      final rawSalesA = custA.displayTotalSales;
      final double displayA;
      if (custA.netSales != null &&
          custA.totalSales != null &&
          custA.netSales! < custA.totalSales!) {
        final alreadyDeducted =
            (custA.totalSales! - custA.netSales!).clamp(0.0, double.infinity);
        final remainingReturn =
            (returnedForCustomerA - alreadyDeducted).clamp(0.0, double.infinity);
        displayA = (rawSalesA - remainingReturn).clamp(0.0, double.infinity);
      } else {
        displayA = (rawSalesA - returnedForCustomerA).clamp(0.0, double.infinity);
      }
      expect(displayA, equals(0.0)); // Strictly 0! Does not display 44.950.000

      // Scenario B: Customer already has netSales = 0.0, return order = 44.950.000 (No double deduction below 0)
      const custB = Customer(
        id: 'KH006981',
        name: 'afsd',
        phone: '0966777888',
        email: '',
        address: '',
        purchases: [],
        totalSales: 44950000.0,
        netSales: 0.0,
      );
      final rawSalesB = custB.displayTotalSales; // 0.0
      final double displayB;
      if (custB.netSales != null &&
          custB.totalSales != null &&
          custB.netSales! < custB.totalSales!) {
        final alreadyDeducted =
            (custB.totalSales! - custB.netSales!).clamp(0.0, double.infinity);
        final remainingReturn =
            (returnedForCustomerA - alreadyDeducted).clamp(0.0, double.infinity);
        displayB = (rawSalesB - remainingReturn).clamp(0.0, double.infinity);
      } else {
        displayB = (rawSalesB - returnedForCustomerA).clamp(0.0, double.infinity);
      }
      expect(displayB, equals(0.0));
    });
  });
}
