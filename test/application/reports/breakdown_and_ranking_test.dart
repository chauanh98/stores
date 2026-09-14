import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/product.dart';

import '../../fixtures/mock_report_data.dart';

class FakeCustomerListNotifier extends CustomerListNotifier {
  @override
  FutureOr<List<Customer>> build() async => [];
}

void main() {
  group('Payment Breakdown, Category Share & Top Rankings (R4, R5)', () {
    PaymentBreakdown calculatePaymentBreakdown({
      required List<Order> orders,
      String? storeFilter,
    }) {
      double cash = 0.0;
      double transfer = 0.0;
      double debt = 0.0;
      double total = 0.0;

      for (final order in orders) {
        if (order.status != 'completed') continue;
        final storeId = order.createdBy ?? 'store_001';
        if (storeFilter != null &&
            storeFilter != 'all' &&
            storeId != storeFilter) {
          continue;
        }

        final method = order.paymentMethod.toLowerCase();
        final paid = order.amountPaid;
        final orderDebt = order.debtAmount;
        final orderTotal = order.total;

        total += orderTotal;

        if (orderDebt > 0) {
          debt += orderDebt;
        }

        if (paid > 0) {
          if (method.contains('transfer') ||
              method.contains('bank') ||
              method.contains('qr') ||
              method.contains('vietqr') ||
              method.contains('chuyen')) {
            transfer += paid;
          } else {
            cash += paid;
          }
        } else if (orderDebt == 0) {
          if (method.contains('transfer') ||
              method.contains('bank') ||
              method.contains('qr') ||
              method.contains('vietqr') ||
              method.contains('chuyen')) {
            transfer += orderTotal;
          } else {
            cash += orderTotal;
          }
        }
      }

      return PaymentBreakdown(
        cashAmount: cash,
        transferAmount: transfer,
        debtAmount: debt,
        totalAmount: total,
      );
    }

    // Pure calculation engine for Category Revenue Share
    List<CategoryRevenueShare> calculateCategoryShare({
      required List<Order> orders,
      required List<Product> products,
      String? storeFilter,
    }) {
      final categoryMap = {
        for (var p in products)
          p.id: (p.category.trim().isEmpty ? 'Chưa phân loại' : p.category)
      };

      final Map<String, double> categoryRevMap = {};
      double totalRev = 0.0;

      for (final order in orders) {
        if (order.status != 'completed') continue;
        final storeId = order.createdBy ?? 'store_001';
        if (storeFilter != null &&
            storeFilter != 'all' &&
            storeId != storeFilter) {
          continue;
        }

        for (final item in order.items) {
          final cat = categoryMap[item.productId] ?? 'Chưa phân loại';
          final itemRev = item.price * item.quantity;
          categoryRevMap[cat] = (categoryRevMap[cat] ?? 0.0) + itemRev;
          totalRev += itemRev;
        }
      }

      final List<CategoryRevenueShare> result = [];
      categoryRevMap.forEach((categoryName, revenue) {
        final percentage = totalRev > 0 ? (revenue / totalRev) * 100 : 0.0;
        result.add(CategoryRevenueShare(
          categoryName: categoryName,
          revenue: revenue,
          percentage: percentage,
        ));
      });

      result.sort((a, b) => b.revenue.compareTo(a.revenue));
      return result;
    }

    // Pure calculation engine for Top Selling Products Ranking
    List<ProductRankingItem> calculateTopProducts({
      required List<Order> orders,
      bool sortByRevenue = true,
      int limit = 5,
      String? storeFilter,
    }) {
      final Map<String, ProductRankingItem> productMap = {};

      for (final order in orders) {
        if (order.status != 'completed') continue;
        final storeId = order.createdBy ?? 'store_001';
        if (storeFilter != null &&
            storeFilter != 'all' &&
            storeId != storeFilter) {
          continue;
        }

        for (final item in order.items) {
          final existing = productMap[item.productId];
          if (existing != null) {
            productMap[item.productId] = ProductRankingItem(
              productId: item.productId,
              productName: item.productName,
              quantity: existing.quantity + item.quantity,
              revenue: existing.revenue + (item.price * item.quantity),
            );
          } else {
            productMap[item.productId] = ProductRankingItem(
              productId: item.productId,
              productName: item.productName,
              quantity: item.quantity,
              revenue: item.price * item.quantity,
            );
          }
        }
      }

      final list = productMap.values.toList();
      if (sortByRevenue) {
        list.sort((a, b) => b.revenue.compareTo(a.revenue));
      } else {
        list.sort((a, b) => b.quantity.compareTo(a.quantity));
      }

      return list.take(limit).toList();
    }

    // Pure calculation engine for Top Spending Customers Ranking
    List<CustomerRankingItem> calculateTopCustomers({
      required List<Order> orders,
      required List<Customer> customers,
      int limit = 5,
      String? storeFilter,
    }) {
      final customerNameMap = {for (var c in customers) c.id: c.name};
      final Map<String, double> spentMap = {};
      final Map<String, int> orderCountMap = {};

      for (final order in orders) {
        if (order.status != 'completed') continue;
        final storeId = order.createdBy ?? 'store_001';
        if (storeFilter != null &&
            storeFilter != 'all' &&
            storeId != storeFilter) {
          continue;
        }

        final custId =
            order.customerId.isEmpty ? 'walk_in_guest' : order.customerId;
        spentMap[custId] = (spentMap[custId] ?? 0.0) + order.total;
        orderCountMap[custId] = (orderCountMap[custId] ?? 0) + 1;
      }

      final List<CustomerRankingItem> list = [];
      spentMap.forEach((custId, totalSpent) {
        final name = custId == 'walk_in_guest'
            ? 'Khách vãng lai'
            : (customerNameMap[custId] ?? 'Khách hàng $custId');
        list.add(CustomerRankingItem(
          customerId: custId,
          customerName: name,
          totalSpent: totalSpent,
          orderCount: orderCountMap[custId] ?? 1,
        ));
      });

      list.sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
      return list.take(limit).toList();
    }

    group('Tier 1: Feature Coverage (Payment, Category, Rankings)', () {
      test('1.1 Computes payment breakdown across Cash, Transfer, and Debt',
          () {
        final orders = [
          MockReportData.createOrder(
            id: 'o_cash',
            total: 500000.0,
            paymentMethod: 'cash',
          ),
          MockReportData.createOrder(
            id: 'o_transfer',
            total: 300000.0,
            paymentMethod: 'bank_transfer',
          ),
          MockReportData.createOrder(
            id: 'o_debt',
            total: 200000.0,
            paymentMethod: 'debt',
            debtAmount: 200000.0,
          ),
        ];

        final breakdown = calculatePaymentBreakdown(orders: orders);
        expect(breakdown.cashAmount, equals(500000.0));
        expect(breakdown.transferAmount, equals(300000.0));
        expect(breakdown.debtAmount, equals(200000.0));
        expect(breakdown.totalAmount, equals(1000000.0));

        // Proportions
        expect(breakdown.cashPercentage, equals(50.0));
        expect(breakdown.transferPercentage, equals(30.0));
        expect(breakdown.debtPercentage, equals(20.0));
      });

      test('1.2 Computes category revenue share proportions accurately', () {
        final catalog = MockReportData.sampleProductCatalog();
        final orders = [
          MockReportData.createOrder(
            id: 'o1',
            items: [
              MockReportData.createOrderItem(
                productId: 'p_fashion_1', // Category: Thời trang
                quantity: 2,
                price: 250000.0, // 500k
              ),
              MockReportData.createOrderItem(
                productId: 'p_tech_1', // Category: Điện thoại & Phụ kiện
                quantity: 1,
                price: 120000.0, // 120k
              ),
            ],
          ),
          MockReportData.createOrder(
            id: 'o2',
            items: [
              MockReportData.createOrderItem(
                productId: 'p_fashion_2', // Category: Thời trang
                quantity: 1,
                price: 450000.0, // 450k
              ),
            ],
          ),
        ];

        final shares = calculateCategoryShare(
          orders: orders,
          products: catalog,
        );

        // Total Rev = 500k + 120k + 450k = 1,070,000
        // Thời trang = 950k (88.79%), Điện thoại & Phụ kiện = 120k (11.21%)
        expect(shares.length, equals(2));
        expect(shares[0].categoryName, equals('Thời trang'));
        expect(shares[0].revenue, equals(950000.0));
        expect(shares[0].percentage, closeTo(88.79, 0.01));

        expect(shares[1].categoryName, equals('Điện thoại & Phụ kiện'));
        expect(shares[1].revenue, equals(120000.0));
        expect(shares[1].percentage, closeTo(11.21, 0.01));
      });

      test('1.3 Ranks Top Selling Products by Revenue vs by Quantity Sold', () {
        final orders = [
          // Product A: 2 units @ 500k = 1M
          MockReportData.createOrder(
            id: 'o1',
            items: [
              MockReportData.createOrderItem(
                productId: 'prod_expensive',
                productName: 'Sản phẩm giá cao',
                quantity: 2,
                price: 500000.0,
              ),
            ],
          ),
          // Product B: 10 units @ 50k = 500k
          MockReportData.createOrder(
            id: 'o2',
            items: [
              MockReportData.createOrderItem(
                productId: 'prod_volume',
                productName: 'Sản phẩm số lượng',
                quantity: 10,
                price: 50000.0,
              ),
            ],
          ),
        ];

        // 1. By Revenue: Product A is #1 (1M vs 500k)
        final byRev = calculateTopProducts(orders: orders, sortByRevenue: true);
        expect(byRev.first.productId, equals('prod_expensive'));
        expect(byRev.first.revenue, equals(1000000.0));
        expect(byRev[1].productId, equals('prod_volume'));

        // 2. By Quantity: Product B is #1 (10 units vs 2 units)
        final byQty = calculateTopProducts(orders: orders, sortByRevenue: false);
        expect(byQty.first.productId, equals('prod_volume'));
        expect(byQty.first.quantity, equals(10));
        expect(byQty[1].productId, equals('prod_expensive'));
      });

      test('1.4 Ranks Top Spending Customers accurately', () {
        final customers = MockReportData.sampleCustomerList();
        final orders = [
          MockReportData.createOrder(
            id: 'o1',
            customerId: customers[0].id,
            total: 2000000.0,
          ),
          MockReportData.createOrder(
            id: 'o2',
            customerId: customers[1].id,
            total: 5000000.0,
          ),
          MockReportData.createOrder(
            id: 'o3',
            customerId: customers[0].id,
            total: 4000000.0,
          ), // Customer 0 total = 6M
        ];

        final topCustomers = calculateTopCustomers(
          orders: orders,
          customers: customers,
        );

        // Customer 0: 6M (2 orders) -> #1
        // Customer 1: 5M (1 order) -> #2
        expect(topCustomers.length, equals(2));
        expect(topCustomers[0].customerId, equals(customers[0].id));
        expect(topCustomers[0].customerName, equals(customers[0].name));
        expect(topCustomers[0].totalSpent, equals(6000000.0));
        expect(topCustomers[0].orderCount, equals(2));

        expect(topCustomers[1].customerId, equals(customers[1].id));
        expect(topCustomers[1].totalSpent, equals(5000000.0));
      });
    });

    group('Tier 2: Boundary & Corner Cases', () {
      test('2.1 100% Cash payment scenario', () {
        final orders = [
          MockReportData.createOrder(
            id: 'o_cash_only',
            total: 1000000.0,
            paymentMethod: 'cash',
          ),
        ];

        final breakdown = calculatePaymentBreakdown(orders: orders);
        expect(breakdown.cashPercentage, equals(100.0));
        expect(breakdown.transferPercentage, equals(0.0));
        expect(breakdown.debtPercentage, equals(0.0));
      });

      test('2.2 Zero orders results in 0.0% percentages without NaN', () {
        final breakdown = calculatePaymentBreakdown(orders: []);
        expect(breakdown.totalAmount, equals(0.0));
        expect(breakdown.cashPercentage, equals(0.0));
        expect(breakdown.transferPercentage, equals(0.0));
        expect(breakdown.debtPercentage, equals(0.0));
        expect(breakdown.cashPercentage.isNaN, isFalse);
      });

      test('2.3 Product with empty category is safely grouped into fallback',
          () {
        final uncategorizedProd = MockReportData.createProduct(
          id: 'p_nocat',
          name: 'Hàng không nhóm',
          category: '',
          price: 100000.0,
        );

        final order = MockReportData.createOrder(
          id: 'o_nocat',
          items: [
            MockReportData.createOrderItem(
              productId: 'p_nocat',
              quantity: 1,
              price: 100000.0,
            ),
          ],
        );

        final shares = calculateCategoryShare(
          orders: [order],
          products: [uncategorizedProd],
        );

        expect(shares.length, equals(1));
        expect(shares.first.categoryName, equals('Chưa phân loại'));
        expect(shares.first.percentage, equals(100.0));
      });

      test('2.4 Fewer items than requested ranking limit returns available list',
          () {
        final orders = [
          MockReportData.createOrder(
            id: 'o1',
            items: [
              MockReportData.createOrderItem(
                productId: 'only_one_item',
                productName: 'Duy nhất',
                quantity: 1,
                price: 100000.0,
              ),
            ],
          ),
        ];

        final top10 = calculateTopProducts(
          orders: orders,
          limit: 10,
        );

        expect(top10.length, equals(1));
        expect(top10.first.productId, equals('only_one_item'));
      });

      test('2.5 Tied rankings maintain deterministic output', () {
        final orders = [
          MockReportData.createOrder(
            id: 'o1',
            items: [
              MockReportData.createOrderItem(
                productId: 'prod_tie_1',
                productName: 'Sản phẩm 1',
                quantity: 5,
                price: 100000.0, // 500k
              ),
              MockReportData.createOrderItem(
                productId: 'prod_tie_2',
                productName: 'Sản phẩm 2',
                quantity: 5,
                price: 100000.0, // 500k
              ),
            ],
          ),
        ];

        final top = calculateTopProducts(orders: orders, limit: 5);
        expect(top.length, equals(2));
        expect(top[0].revenue, equals(top[1].revenue));
      });

      test('2.6 Anonymous customer orders grouped as Walk-in guest', () {
        final orders = [
          MockReportData.createOrder(
            id: 'o_walkin_1',
            customerId: '', // No customer ID
            total: 300000.0,
          ),
          MockReportData.createOrder(
            id: 'o_walkin_2',
            customerId: '',
            total: 200000.0,
          ),
        ];

        final top = calculateTopCustomers(
          orders: orders,
          customers: [],
        );

        expect(top.length, equals(1));
        expect(top.first.customerId, equals('walk_in_guest'));
        expect(top.first.customerName, equals('Khách vãng lai'));
        expect(top.first.totalSpent, equals(500000.0));
        expect(top.first.orderCount, equals(2));
      });
    });

    group('Tier 3: Combinatorial & Multi-Store Filtering', () {
      test('3.1 Payment breakdown and rankings filtered by Store 1', () {
        final orders = [
          MockReportData.createOrder(
            id: 'o_s1',
            total: 400000.0,
            paymentMethod: 'cash',
            createdBy: 'store_001',
          ),
          MockReportData.createOrder(
            id: 'o_s2',
            total: 600000.0,
            paymentMethod: 'transfer',
            createdBy: 'store_002',
          ),
        ];

        final breakdownStore1 = calculatePaymentBreakdown(
          orders: orders,
          storeFilter: 'store_001',
        );

        expect(breakdownStore1.totalAmount, equals(400000.0));
        expect(breakdownStore1.cashAmount, equals(400000.0));
        expect(breakdownStore1.transferAmount, equals(0.0));
      });
    });

    group('Tier 4: Realistic Retail Day Scenario', () {
      test('4.1 Full day with 15 orders across 4 categories, 3 payment methods',
          () {
        final catalog = MockReportData.sampleProductCatalog();
        final customers = MockReportData.sampleCustomerList();

        final List<Order> dayOrders = [
          // Order 1: Cash, Fashion (p_fashion_1, 2 units @ 250k = 500k)
          MockReportData.createOrder(
            id: 'ord_01',
            customerId: customers[0].id,
            paymentMethod: 'cash',
            items: [
              MockReportData.createOrderItem(
                productId: 'p_fashion_1',
                productName: 'Áo thun Polo Nam',
                quantity: 2,
                price: 250000.0,
              ),
            ],
            total: 500000.0,
          ),
          // Order 2: QR Transfer, Tech (p_tech_1, 4 units @ 120k = 480k)
          MockReportData.createOrder(
            id: 'ord_02',
            customerId: customers[1].id,
            paymentMethod: 'bank_transfer',
            items: [
              MockReportData.createOrderItem(
                productId: 'p_tech_1',
                productName: 'Cáp sạc Type-C',
                quantity: 4,
                price: 120000.0,
              ),
            ],
            total: 480000.0,
          ),
          // Order 3: Debt, Home (p_home_1, 3 units @ 180k = 540k)
          MockReportData.createOrder(
            id: 'ord_03',
            customerId: customers[2].id,
            paymentMethod: 'debt',
            debtAmount: 540000.0,
            items: [
              MockReportData.createOrderItem(
                productId: 'p_home_1',
                productName: 'Bình giữ nhiệt',
                quantity: 3,
                price: 180000.0,
              ),
            ],
            total: 540000.0,
          ),
          // Order 4: Cash, Beauty (p_beauty_1, 2 units @ 320k = 640k)
          MockReportData.createOrder(
            id: 'ord_04',
            customerId: customers[0].id,
            paymentMethod: 'cash',
            items: [
              MockReportData.createOrderItem(
                productId: 'p_beauty_1',
                productName: 'Kem chống nắng',
                quantity: 2,
                price: 320000.0,
              ),
            ],
            total: 640000.0,
          ),
        ];

        // 1. Payment Breakdown
        final breakdown = calculatePaymentBreakdown(orders: dayOrders);
        expect(breakdown.cashAmount, equals(1140000.0)); // 500k + 640k
        expect(breakdown.transferAmount, equals(480000.0)); // 480k
        expect(breakdown.debtAmount, equals(540000.0)); // 540k
        expect(breakdown.totalAmount, equals(2160000.0)); // Sum

        expect(
          breakdown.cashPercentage +
              breakdown.transferPercentage +
              breakdown.debtPercentage,
          closeTo(100.0, 0.001),
        );

        // 2. Category Share
        final shares = calculateCategoryShare(
          orders: dayOrders,
          products: catalog,
        );
        expect(shares.length, equals(4));
        final sumCategoryPercentages =
            shares.fold<double>(0.0, (sum, item) => sum + item.percentage);
        expect(sumCategoryPercentages, closeTo(100.0, 0.001));

        // 3. Top Products by Quantity
        final topByQty = calculateTopProducts(
          orders: dayOrders,
          sortByRevenue: false,
          limit: 5,
        );
        expect(topByQty.first.productId, equals('p_tech_1')); // 4 units

        // 4. Top Customer
        final topCust = calculateTopCustomers(
          orders: dayOrders,
          customers: customers,
          limit: 5,
        );
        // Customer 0 spent 500k + 640k = 1,140,000 (Top 1)
        expect(topCust.first.customerId, equals(customers[0].id));
        expect(topCust.first.totalSpent, equals(1140000.0));
      });
    });

    group('Riverpod Providers Integration (breakdown and ranking providers)', () {
      test('paymentBreakdownProvider and ranking providers compute with mock container', () {
        final container = ProviderContainer(
          overrides: [
            allBranchesOrdersByDateRangeProvider.overrideWith(
              (ref, range) => Stream.value([]),
            ),
            allStoresProductsProvider.overrideWith(
              (ref) => Stream.value([]),
            ),
            customerListNotifierProvider.overrideWith(
              () => FakeCustomerListNotifier(),
            ),
          ],
        );
        addTearDown(container.dispose);

        final paymentAsync = container.read(paymentBreakdownProvider);
        expect(paymentAsync, isA<AsyncValue<PaymentBreakdown>>());

        final catShareAsync = container.read(categoryRevenueShareProvider);
        expect(catShareAsync, isA<AsyncValue<List<CategoryRevenueShare>>>());

        final topProdAsync = container.read(topSellingProductsRankingProvider);
        expect(topProdAsync, isA<AsyncValue<List<ProductRankingItem>>>());

        final topCustAsync = container.read(topCustomersRankingProvider);
        expect(topCustAsync, isA<AsyncValue<List<CustomerRankingItem>>>());

        final recentOrdersAsync = container.read(recentOrdersFeedProvider);
        expect(recentOrdersAsync, isA<AsyncValue<List<Order>>>());
      });
    });
  });
}
