import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/data/models/inventory_transaction_model.dart';
import 'package:stores/data/models/order_model.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';

void main() {
  late Map<String, dynamic> sampleData;
  late Map<String, dynamic> store001Data;
  late Map<String, dynamic> store002Data;
  late Map<String, dynamic> store001ProductsRaw;
  late Map<String, dynamic> store002ProductsRaw;
  late Map<String, dynamic> store001OrdersRaw;
  late Map<String, dynamic> store002OrdersRaw;
  late Map<String, dynamic> store001TxRaw;
  late Map<String, dynamic> store002TxRaw;

  setUpAll(() {
    final file = File('data_mau.json');
    expect(file.existsSync(), isTrue,
        reason: 'data_mau.json must exist in the workspace root directory');
    final jsonString = file.readAsStringSync();
    sampleData = json.decode(jsonString) as Map<String, dynamic>;

    final stores = sampleData['stores'] as Map<String, dynamic>;
    store001Data = stores['store_001'] as Map<String, dynamic>;
    store002Data = stores['store_002'] as Map<String, dynamic>;

    store001ProductsRaw =
        (store001Data['products'] as Map<String, dynamic>?) ?? {};
    store002ProductsRaw =
        (store002Data['products'] as Map<String, dynamic>?) ?? {};

    store001OrdersRaw = (store001Data['orders'] as Map<String, dynamic>?) ?? {};
    store002OrdersRaw = (store002Data['orders'] as Map<String, dynamic>?) ?? {};

    store001TxRaw =
        (store001Data['inventory_transactions'] as Map<String, dynamic>?) ?? {};
    store002TxRaw =
        (store002Data['inventory_transactions'] as Map<String, dynamic>?) ?? {};
  });

  group('=== REQUIREMENT R3: REAL-WORLD E2E VERIFICATION WITH data_mau.json ===',
      () {
    // -------------------------------------------------------------------------
    // 1. Structure & Metadata Integrity
    // -------------------------------------------------------------------------
    group('1. Store & Branch Metadata Integrity', () {
      test('data_mau.json contains valid store_001 (Đông Thắng) metadata', () {
        expect(store001Data['name'], equals('Chi nhánh Đông Thắng'));
        expect(store001Data['address'], contains('Phố Huế'));
        expect(store001ProductsRaw.length, equals(11),
            reason: 'store_001 has exactly 11 product definitions');
        expect(store001OrdersRaw.length, equals(16),
            reason: 'store_001 has exactly 16 total orders');
      });

      test('data_mau.json contains valid store_002 (Thới Bình) metadata', () {
        final name = store002Data['name'] as String;
        expect(
            name == 'Chi nhánh Thới Bình' || name == 'Chi nhánh Thời Bình',
            isTrue,
            reason: 'store_002 name matches Thới Bình / Thời Bình');
        expect(store002Data['address'], contains('Nguyễn Huệ'));
        expect(store002ProductsRaw.length, equals(5),
            reason: 'store_002 has exactly 5 product definitions');
        expect(store002OrdersRaw.length, equals(2),
            reason: 'store_002 has exactly 2 total orders');
      });

      test(
          'Total product count in data_mau.json is exactly 16 across both stores',
          () {
        expect(store001ProductsRaw.length + store002ProductsRaw.length,
            equals(16));
      });

      test('Total order count in data_mau.json is exactly 18 across both stores',
          () {
        expect(store001OrdersRaw.length + store002OrdersRaw.length, equals(18));
      });

      test(
          'Total inventory transaction count in data_mau.json across both stores',
          () {
        expect(store001TxRaw.length, equals(86));
        expect(store002TxRaw.length, equals(11));
      });
    });

    // -------------------------------------------------------------------------
    // 2. All 16 Products Inventory & Stock Mapping Verification
    // -------------------------------------------------------------------------
    group(
        '2. Exhaustive Product Inventory & Multi-Branch Stock Verification (All 16 Products)',
        () {
      group('A. Store 001 (Chi nhánh Đông Thắng - ĐT) - 11 Products', () {
        test('Product 1 [1784349357357] (acd): ĐT: 10, TB: 0 (Total: 10)', () {
          final raw = store001ProductsRaw['1784349357357'] as Map;
          final product = ProductModel.fromMap(raw, 'store_001').toEntity();

          expect(product.id, equals('1784349357357'));
          expect(product.name, equals('acd'));
          expect(product.code, equals('ACD'));
          expect(product.stockInBranch('store_001'), equals(10));
          expect(product.stockInBranch('store_002'), equals(0));
          expect(product.stockInBranch('ĐT'), equals(10));
          expect(product.stockInBranch('TB'), equals(0));
          expect(product.stockInBranch('branch_1'), equals(10));
          expect(product.stockInBranch('branch_2'), equals(0));
          expect(product.stock, equals(10));
          expect(product.hasStock, isTrue);
          expect(product.isOutOfStock, isFalse);
        });

        test(
            'Product 2 [1784349709944] (Hihi sadasdasd): ĐT: 0, TB: 0 (Total: 0)',
            () {
          final raw = store001ProductsRaw['1784349709944'] as Map;
          final product = ProductModel.fromMap(raw, 'store_001').toEntity();

          expect(product.id, equals('1784349709944'));
          expect(product.name, equals('Hihi sadasdasd'));
          expect(product.code, equals('HIHi dcccc'));
          expect(product.stockInBranch('store_001'), equals(0));
          expect(product.stockInBranch('store_002'), equals(0));
          expect(product.stockInBranch('ĐT'), equals(0));
          expect(product.stockInBranch('TB'), equals(0));
          expect(product.stock, equals(0));
          expect(product.isOutOfStock, isTrue);
        });

        test(
            'Product 3 [1784735675190] (Combo huy diet): ĐT: 0, TB: 0, isCombo: true',
            () {
          final raw = store001ProductsRaw['1784735675190'] as Map;
          final product = ProductModel.fromMap(raw, 'store_001').toEntity();

          expect(product.id, equals('1784735675190'));
          expect(product.name, equals('Combo huy diet'));
          expect(product.code, equals('123'));
          expect(product.isCombo, isTrue);
          expect(product.comboComponents.length, equals(2));
          expect(product.stockInBranch('store_001'), equals(0));
          expect(product.stockInBranch('store_002'), equals(0));
          expect(product.stock, equals(0));
        });

        test(
            'Product 4 [1784736817596] (Combo tao lao): ĐT: 11, TB: 0 (Total: 11), isCombo: true',
            () {
          final raw = store001ProductsRaw['1784736817596'] as Map;
          final product = ProductModel.fromMap(raw, 'store_001').toEntity();

          expect(product.id, equals('1784736817596'));
          expect(product.name, equals('Combo tao lao'));
          expect(product.code, equals('21433214'));
          expect(product.isCombo, isTrue);
          expect(product.comboComponents.length, equals(3));
          expect(product.stockInBranch('store_001'), equals(11));
          expect(product.stockInBranch('store_002'), equals(0));
          expect(product.stockInBranch('ĐT'), equals(11));
          expect(product.stockInBranch('TB'), equals(0));
          expect(product.stock, equals(11));
        });

        test(
            'Product 5 [GCG08] (Ghế bậc thang đốt nhang - 1m2): ĐT: 11, TB: 0 (Total: 11)',
            () {
          final raw = store001ProductsRaw['GCG08'] as Map;
          final product = ProductModel.fromMap(raw, 'store_001').toEntity();

          expect(product.id, equals('GCG08'));
          expect(product.name, equals('Ghế bậc thang đốt nhang - 1m2'));
          expect(product.code, equals('GCG08'));
          expect(product.price, equals(2700000.0));
          expect(product.costPrice, equals(1000.0));
          expect(product.stockInBranch('store_001'), equals(11));
          expect(product.stockInBranch('store_002'), equals(0));
          expect(product.stockInBranch('ĐT'), equals(11));
          expect(product.stockInBranch('TB'), equals(0));
          expect(product.stock, equals(11));
        });

        test(
            'Product 6 [GCG09] (Ghế bậc thang đốt nhang -1m4): ĐT: 11, TB: 0 (Total: 11)',
            () {
          final raw = store001ProductsRaw['GCG09'] as Map;
          final product = ProductModel.fromMap(raw, 'store_001').toEntity();

          expect(product.id, equals('GCG09'));
          expect(product.name, equals('Ghế bậc thang đốt nhang -1m4'));
          expect(product.code, equals('GCG09'));
          expect(product.price, equals(2800000.0));
          expect(product.costPrice, closeTo(400818.18, 0.01));
          expect(product.stockInBranch('store_001'), equals(11));
          expect(product.stockInBranch('store_002'), equals(0));
          expect(product.stockInBranch('ĐT'), equals(11));
          expect(product.stockInBranch('TB'), equals(0));
          expect(product.stock, equals(11));
        });

        test(
            'Product 7 [GCG10] (Ghế bậc thang đốt nhang -1m6): ĐT: 0, TB: 0 (Total: 0)',
            () {
          final raw = store001ProductsRaw['GCG10'] as Map;
          final product = ProductModel.fromMap(raw, 'store_001').toEntity();

          expect(product.id, equals('GCG10'));
          expect(product.name, equals('Ghế bậc thang đốt nhang -1m6'));
          expect(product.code, equals('GCG10'));
          expect(product.price, equals(3150000.0));
          expect(product.costPrice, equals(2300000.0));
          expect(product.stockInBranch('store_001'), equals(0));
          expect(product.stockInBranch('store_002'), equals(0));
          expect(product.stockInBranch('ĐT'), equals(0));
          expect(product.stockInBranch('TB'), equals(0));
          expect(product.stock, equals(0));
          expect(product.isOutOfStock, isTrue);
        });

        test('Product 8 [KY29] (Kỷ xếp thao lao - 1m4): ĐT: 2, TB: 0 (Total: 2)',
            () {
          final raw = store001ProductsRaw['KY29'] as Map;
          final product = ProductModel.fromMap(raw, 'store_001').toEntity();

          expect(product.id, equals('KY29'));
          expect(product.name, equals('Kỷ xếp thao lao - 1m4'));
          expect(product.code, equals('KY29'));
          expect(product.price, equals(9800000.0));
          expect(product.costPrice, equals(6200000.0));
          expect(product.stockInBranch('store_001'), equals(2));
          expect(product.stockInBranch('store_002'), equals(0));
          expect(product.stockInBranch('ĐT'), equals(2));
          expect(product.stockInBranch('TB'), equals(0));
          expect(product.stock, equals(2));
          expect(product.isLowStock(5), isTrue);
        });

        test(
            'Product 9 [THOL17] (Tủ thờ thao lao - chạm - 1m4): ĐT: 2, TB: 0 (Total: 2)',
            () {
          final raw = store001ProductsRaw['THOL17'] as Map;
          final product = ProductModel.fromMap(raw, 'store_001').toEntity();

          expect(product.id, equals('THOL17'));
          expect(product.name, equals('Tủ thờ thao lao - chạm - 1m4'));
          expect(product.code, equals('THOL17'));
          expect(product.price, equals(7500000.0));
          expect(product.costPrice, equals(5300000.0));
          expect(product.stockInBranch('store_001'), equals(2));
          expect(product.stockInBranch('store_002'), equals(0));
          expect(product.stockInBranch('ĐT'), equals(2));
          expect(product.stockInBranch('TB'), equals(0));
          expect(product.stock, equals(2));
        });

        test(
            'Product 10 [VP88 in store_001] (Bàn chữ K MDF): ĐT: 0, TB: 0 (Total: 0)',
            () {
          final raw = store001ProductsRaw['VP88'] as Map;
          final product = ProductModel.fromMap(raw, 'store_001').toEntity();

          expect(product.id, equals('VP88'));
          expect(
              product.name, equals('Bàn chữ K mặt MDF - kệ trên dưới - 1m2'));
          expect(product.price, equals(1150000.0));
          expect(product.costPrice, equals(2500.0));
          expect(product.stockInBranch('store_001'), equals(0));
          expect(product.stockInBranch('store_002'), equals(0));
          expect(product.stockInBranch('ĐT'), equals(0));
          expect(product.stockInBranch('TB'), equals(0));
          expect(product.stock, equals(0));
          expect(product.isOutOfStock, isTrue);
        });

        test(
            'Product 11 [XD15] (Xích đu trứng - đôi 1 trụ): ĐT: 11, TB: 0 (Total: 11)',
            () {
          final raw = store001ProductsRaw['XD15'] as Map;
          final product = ProductModel.fromMap(raw, 'store_001').toEntity();

          expect(product.id, equals('XD15'));
          expect(
              product.name, equals('Xích đu trứng - đôi 1 trụ - tai thỏ 1'));
          expect(product.price, equals(4250000.0));
          expect(product.costPrice, equals(1000.0));
          expect(product.stockInBranch('store_001'), equals(11));
          expect(product.stockInBranch('store_002'), equals(0));
          expect(product.stockInBranch('ĐT'), equals(11));
          expect(product.stockInBranch('TB'), equals(0));
          expect(product.stock, equals(11));
        });
      });

      group(
          'B. Store 002 (Chi nhánh Thới Bình - TB) - 5 Products (Context-Aware Mapping)',
          () {
        test('Product 12 [1782636691862] (iPhone 17): ĐT: 0, TB: 4 (Total: 4)',
            () {
          final raw = store002ProductsRaw['1782636691862'] as Map;
          final product = ProductModel.fromMap(raw, 'store_002').toEntity();

          expect(product.id, equals('1782636691862'));
          expect(product.name, equals('iPhone 17'));
          expect(product.price, equals(21000000.0));
          expect(product.costPrice, closeTo(14333333.33, 0.01));
          // Context-aware: branch_1 in store_002 represents TB (store_002)
          expect(product.stockInBranch('store_001'), equals(0));
          expect(product.stockInBranch('store_002'), equals(4));
          expect(product.stockInBranch('ĐT'), equals(0));
          expect(product.stockInBranch('TB'), equals(4));
          expect(product.stock, equals(4));
          expect(product.isLowStock(5), isTrue);
        });

        test(
            'Product 13 [1784390108938] (ip 17 pro max): ĐT: 0, TB: 10 (Total: 10)',
            () {
          final raw = store002ProductsRaw['1784390108938'] as Map;
          final product = ProductModel.fromMap(raw, 'store_002').toEntity();

          expect(product.id, equals('1784390108938'));
          expect(product.name, equals('ip 17 pro max'));
          expect(product.price, equals(30000000.0));
          expect(product.costPrice, equals(20000000.0));
          expect(product.stockInBranch('store_001'), equals(0));
          expect(product.stockInBranch('store_002'), equals(10));
          expect(product.stockInBranch('ĐT'), equals(0));
          expect(product.stockInBranch('TB'), equals(10));
          expect(product.stock, equals(10));
        });

        test(
            'Product 14 [VP88 in store_002] (Bàn chữ K MDF Thới Bình instance): ĐT: 0, TB: 5 (Total: 5)',
            () {
          final raw = store002ProductsRaw['VP88'] as Map;
          final product = ProductModel.fromMap(raw, 'store_002').toEntity();

          expect(product.id, equals('VP88'));
          expect(
              product.name, equals('Bàn chữ K mặt MDF - kệ trên dưới - 1m2'));
          expect(product.price, equals(1150000.0));
          // branchStocks {'branch_1': 5} takes precedence over legacy stock: 3
          expect(product.stockInBranch('store_001'), equals(0));
          expect(product.stockInBranch('store_002'), equals(5));
          expect(product.stockInBranch('ĐT'), equals(0));
          expect(product.stockInBranch('TB'), equals(5));
          expect(product.stock, equals(5));
        });

        test('Product 15 [p101] (iPad Air M2): ĐT: 0, TB: 15 (Total: 15)', () {
          final raw = store002ProductsRaw['p101'] as Map;
          final product = ProductModel.fromMap(raw, 'store_002').toEntity();

          expect(product.id, equals('p101'));
          expect(product.name, equals('iPad Air M2'));
          expect(product.price, equals(15990000.0));
          expect(product.costPrice, equals(11193000.0));
          expect(product.stockInBranch('store_001'), equals(0));
          expect(product.stockInBranch('store_002'), equals(15));
          expect(product.stockInBranch('ĐT'), equals(0));
          expect(product.stockInBranch('TB'), equals(15));
          expect(product.stock, equals(15));
        });

        test('Product 16 [p102] (ThinkPad X1 Carbon): ĐT: 0, TB: 4 (Total: 4)',
            () {
          final raw = store002ProductsRaw['p102'] as Map;
          final product = ProductModel.fromMap(raw, 'store_002').toEntity();

          expect(product.id, equals('p102'));
          expect(product.name, equals('ThinkPad X1 Carbon'));
          expect(product.price, equals(42990000.0));
          expect(product.costPrice, equals(30092999.0));
          expect(product.stockInBranch('store_001'), equals(0));
          expect(product.stockInBranch('store_002'), equals(4));
          expect(product.stockInBranch('ĐT'), equals(0));
          expect(product.stockInBranch('TB'), equals(4));
          expect(product.stock, equals(4));
          expect(product.isLowStock(5), isTrue);
        });
      });

      group('C. Cross-Branch Alias Querying via Product.stockInBranch', () {
        test('stockInBranch supports all branch name variations and acronyms',
            () {
          final rawStore1 = store001ProductsRaw['1784349357357'] as Map;
          final prodStore1 =
              ProductModel.fromMap(rawStore1, 'store_001').toEntity();

          final rawStore2 = store002ProductsRaw['1782636691862'] as Map;
          final prodStore2 =
              ProductModel.fromMap(rawStore2, 'store_002').toEntity();

          // Store 1 product queries
          expect(prodStore1.stockInBranch('store_001'), equals(10));
          expect(prodStore1.stockInBranch('Chi nhánh Đông Thắng'), equals(10));
          expect(prodStore1.stockInBranch('Đông Thắng'), equals(10));
          expect(prodStore1.stockInBranch('dong thang'), equals(10));
          expect(prodStore1.stockInBranch('ĐT'), equals(10));
          expect(prodStore1.stockInBranch('đt'), equals(10));
          expect(prodStore1.stockInBranch('dt'), equals(10));
          expect(prodStore1.stockInBranch('store_002'), equals(0));
          expect(prodStore1.stockInBranch('TB'), equals(0));
          expect(prodStore1.stockInBranch('non_existent_branch'), equals(0));
          expect(prodStore1.stockInBranch(''), equals(0));

          // Store 2 product queries
          expect(prodStore2.stockInBranch('store_002'), equals(4));
          expect(prodStore2.stockInBranch('Chi nhánh Thới Bình'), equals(4));
          expect(prodStore2.stockInBranch('Chi nhánh Thời Bình'), equals(4));
          expect(prodStore2.stockInBranch('Thới Bình'), equals(4));
          expect(prodStore2.stockInBranch('thoi binh'), equals(4));
          expect(prodStore2.stockInBranch('TB'), equals(4));
          expect(prodStore2.stockInBranch('tb'), equals(4));
          expect(prodStore2.stockInBranch('store_001'), equals(0));
          expect(prodStore2.stockInBranch('ĐT'), equals(0));
        });
      });

      group('D. Network Inventory Aggregation', () {
        test('Total network stock sums to exactly 58 (ĐT) + 38 (TB) = 96 items',
            () {
          final store1Products = store001ProductsRaw.values
              .map((m) =>
                  ProductModel.fromMap(m as Map, 'store_001').toEntity())
              .toList();

          final store2Products = store002ProductsRaw.values
              .map((m) =>
                  ProductModel.fromMap(m as Map, 'store_002').toEntity())
              .toList();

          final totalDtStock = store1Products.fold<int>(
                  0, (sum, p) => sum + p.stockInBranch('store_001')) +
              store2Products.fold<int>(
                  0, (sum, p) => sum + p.stockInBranch('store_001'));

          final totalTbStock = store1Products.fold<int>(
                  0, (sum, p) => sum + p.stockInBranch('store_002')) +
              store2Products.fold<int>(
                  0, (sum, p) => sum + p.stockInBranch('store_002'));

          expect(totalDtStock, equals(58),
              reason: 'Store 001 inventory: 10+0+0+11+11+11+0+2+2+0+11 = 58');
          expect(totalTbStock, equals(38),
              reason: 'Store 002 inventory: 4+10+5+15+4 = 38');
          expect(totalDtStock + totalTbStock, equals(96),
              reason: 'Grand total network inventory is 96 units');
        });
      });
    });

    // -------------------------------------------------------------------------
    // 3. Exhaustive Invoices & Orders Verification Across All Months
    // -------------------------------------------------------------------------
    group(
        '3. Exhaustive Invoices & Orders Verification Across All Months (All 18 Orders)',
        () {
      late List<Order> store1Orders;
      late List<Order> store2Orders;
      late List<Order> allOrders;

      setUp(() {
        store1Orders = store001OrdersRaw.entries.map((entry) {
          final map = Map<String, dynamic>.from(entry.value as Map);
          map['id'] = entry.key;
          final m = OrderModel.fromMap(map);
          return Order(
            id: m.id,
            customerId: m.customerId,
            createdAt: m.createdAt,
            items: m.items
                .map((e) => OrderItem(
                      productId: e.productId,
                      productName: e.productName,
                      quantity: e.quantity,
                      price: e.price,
                      warrantyMonths: e.warrantyMonths,
                      purchaseDate: e.purchaseDate,
                    ))
                .toList(),
            total: m.total,
            status: m.status,
            amountPaid: m.amountPaid,
            debtAmount: m.debtAmount,
            paymentMethod: m.paymentMethod,
            createdBy: m.createdBy,
            createdByName: m.createdByName,
          );
        }).toList();

        store2Orders = store002OrdersRaw.entries.map((entry) {
          final map = Map<String, dynamic>.from(entry.value as Map);
          map['id'] = entry.key;
          final m = OrderModel.fromMap(map);
          return Order(
            id: m.id,
            customerId: m.customerId,
            createdAt: m.createdAt,
            items: m.items
                .map((e) => OrderItem(
                      productId: e.productId,
                      productName: e.productName,
                      quantity: e.quantity,
                      price: e.price,
                      warrantyMonths: e.warrantyMonths,
                      purchaseDate: e.purchaseDate,
                    ))
                .toList(),
            total: m.total,
            status: m.status,
            amountPaid: m.amountPaid,
            debtAmount: m.debtAmount,
            paymentMethod: m.paymentMethod,
            createdBy: m.createdBy,
            createdByName: m.createdByName,
          );
        }).toList();

        allOrders = [...store1Orders, ...store2Orders];
      });

      group('A. Tháng 08/2026 (August 2026) Orders Verification', () {
        test(
            'Tháng 08/2026: store_001 has 3 completed orders totaling 7,150,000đ',
            () {
          final augustOrders = store1Orders
              .where((o) =>
                  o.createdAt.year == 2026 &&
                  o.createdAt.month == 8 &&
                  o.status == 'completed')
              .toList();

          expect(augustOrders.length, equals(3));

          final hd1 = augustOrders.firstWhere((o) => o.id == 'HD000001');
          expect(hd1.total, equals(3150000.0));
          expect(hd1.amountPaid, equals(3150000.0));
          expect(hd1.debtAmount, equals(0.0));
          expect(hd1.items.length, equals(1));
          expect(hd1.items.first.productId, equals('GCG10'));

          final hd2 = augustOrders.firstWhere((o) => o.id == 'HD000002');
          expect(hd2.total, equals(3150000.0));
          expect(hd2.amountPaid, equals(150000.0));
          expect(hd2.debtAmount, equals(3000000.0));
          expect(hd2.items.first.productId, equals('GCG10'));

          final hd3 = augustOrders.firstWhere((o) => o.id == 'HD000003');
          expect(hd3.total, equals(850000.0),
              reason: '1,150,000đ price - 300,000đ discount = 850,000đ');
          expect(hd3.amountPaid, equals(150000.0));
          expect(hd3.debtAmount, equals(700000.0));
          expect(hd3.items.first.productId, equals('VP88'));

          final augustTotal =
              augustOrders.fold<double>(0.0, (sum, o) => sum + o.total);
          expect(augustTotal, equals(7150000.0));

          final augustCash =
              augustOrders.fold<double>(0.0, (sum, o) => sum + o.amountPaid);
          expect(augustCash, equals(3450000.0),
              reason: '3,150,000 + 150,000 + 150,000 = 3,450,000đ');

          final augustDebt =
              augustOrders.fold<double>(0.0, (sum, o) => sum + o.debtAmount);
          expect(augustDebt, equals(3700000.0),
              reason: '0 + 3,000,000 + 700,000 = 3,700,000đ');
        });

        test('Tháng 08/2026: store_002 has 0 orders', () {
          final augustStore2 = store2Orders
              .where((o) => o.createdAt.year == 2026 && o.createdAt.month == 8)
              .toList();
          expect(augustStore2, isEmpty);
        });

        test(
            'Tháng 08/2026: Total completed network revenue is exactly 7,150,000đ',
            () {
          final augustNetwork = allOrders
              .where((o) =>
                  o.createdAt.year == 2026 &&
                  o.createdAt.month == 8 &&
                  o.status == 'completed')
              .toList();
          final total =
              augustNetwork.fold<double>(0.0, (sum, o) => sum + o.total);
          expect(total, equals(7150000.0));
        });
      });

      group(
          'B. Tháng 07/2026 (July 2026) Orders & Draft Exclusion Verification',
          () {
        test(
            'Tháng 07/2026: store_001 has 9 completed orders (15,800,000đ) and excludes 1 draft (4,250,000đ)',
            () {
          final julyAll = store1Orders
              .where((o) => o.createdAt.year == 2026 && o.createdAt.month == 7)
              .toList();
          expect(julyAll.length, equals(10),
              reason: '10 total orders in store_001 in July 2026');

          final draftOrders =
              julyAll.where((o) => o.status == 'draft').toList();
          expect(draftOrders.length, equals(1));
          expect(draftOrders.first.id, equals('HD_1785037734813'));
          expect(draftOrders.first.total, equals(4250000.0));

          final completedOrders =
              julyAll.where((o) => o.status == 'completed').toList();
          expect(completedOrders.length, equals(9));

          final completedRevenue =
              completedOrders.fold<double>(0.0, (sum, o) => sum + o.total);
          expect(completedRevenue, equals(15800000.0),
              reason:
                  'July completed revenue is exactly 15,800,000đ (draft 4,250,000đ excluded)');
        });

        test(
            'Tháng 07/2026: Includes zero-total promo orders without breaking calculations',
            () {
          final julyCompleted = store1Orders
              .where((o) =>
                  o.createdAt.year == 2026 &&
                  o.createdAt.month == 7 &&
                  o.status == 'completed')
              .toList();

          final freeOrders =
              julyCompleted.where((o) => o.total == 0.0).toList();
          expect(freeOrders.length, equals(2));
          expect(freeOrders.map((o) => o.id),
              containsAll(['HD_1785043905525', 'HD_1785043970985']));
        });

        test('Tháng 07/2026: store_002 has 0 orders', () {
          final julyStore2 = store2Orders
              .where((o) => o.createdAt.year == 2026 && o.createdAt.month == 7)
              .toList();
          expect(julyStore2, isEmpty);
        });

        test(
            'Tháng 07/2026: Total completed network revenue is exactly 15,800,000đ',
            () {
          final julyCompletedNetwork = allOrders
              .where((o) =>
                  o.createdAt.year == 2026 &&
                  o.createdAt.month == 7 &&
                  o.status == 'completed')
              .toList();
          final total = julyCompletedNetwork.fold<double>(
              0.0, (sum, o) => sum + o.total);
          expect(total, equals(15800000.0));
        });
      });

      group('C. Tháng 06/2026 (June 2026) Orders Verification', () {
        test('Tháng 06/2026: store_001 has 3 completed orders = 104,361,000đ',
            () {
          final juneStore1 = store1Orders
              .where((o) =>
                  o.createdAt.year == 2026 &&
                  o.createdAt.month == 6 &&
                  o.status == 'completed')
              .toList();
          expect(juneStore1.length, equals(3));

          final hd1 =
              juneStore1.firstWhere((o) => o.id == 'HD_1781401938105');
          expect(hd1.total, equals(61980000.0),
              reason: 'p102 (42,990,000) + p002 (18,990,000) = 61,980,000');

          final hd2 =
              juneStore1.firstWhere((o) => o.id == 'HD_1782551063704');
          expect(hd2.total, equals(18990000.0));

          final hd3 =
              juneStore1.firstWhere((o) => o.id == 'HD_1782551069999');
          expect(hd3.total, equals(23391000.0),
              reason:
                  '25,990,000 with 10% discount (-2,599,000) = 23,391,000');

          final subtotalStore1 =
              juneStore1.fold<double>(0.0, (sum, o) => sum + o.total);
          expect(subtotalStore1, equals(104361000.0));
        });

        test('Tháng 06/2026: store_002 has 2 completed orders = 231,000,000đ',
            () {
          final juneStore2 = store2Orders
              .where((o) =>
                  o.createdAt.year == 2026 &&
                  o.createdAt.month == 6 &&
                  o.status == 'completed')
              .toList();
          expect(juneStore2.length, equals(2));

          final hd1 =
              juneStore2.firstWhere((o) => o.id == 'HD_1782636961924');
          expect(hd1.total, equals(21000000.0));

          final hd2 =
              juneStore2.firstWhere((o) => o.id == 'HD_1782637543339');
          expect(hd2.total, equals(210000000.0),
              reason: 'iPhone 17 x10 @ 21,000,000 = 210,000,000');

          final subtotalStore2 =
              juneStore2.fold<double>(0.0, (sum, o) => sum + o.total);
          expect(subtotalStore2, equals(231000000.0));
        });

        test(
            'Tháng 06/2026: Total completed network revenue = 104,361,000đ + 231,000,000đ = 335,361,000đ',
            () {
          final juneNetwork = allOrders
              .where((o) =>
                  o.createdAt.year == 2026 &&
                  o.createdAt.month == 6 &&
                  o.status == 'completed')
              .toList();
          expect(juneNetwork.length, equals(5));

          final total =
              juneNetwork.fold<double>(0.0, (sum, o) => sum + o.total);
          expect(total, equals(335361000.0));
        });
      });

      group('D. Grand Total Aggregate Invoices Across All 3 Months', () {
        test('Grand Total Completed Orders: 17 orders totaling 358,311,000đ',
            () {
          final completedAll =
              allOrders.where((o) => o.status == 'completed').toList();
          expect(completedAll.length, equals(17));

          final grandTotalRevenue =
              completedAll.fold<double>(0.0, (sum, o) => sum + o.total);
          expect(grandTotalRevenue, equals(358311000.0),
              reason:
                  '335,361,000 (Jun) + 15,800,000 (Jul) + 7,150,000 (Aug) = 358,311,000đ');

          // Store 1 breakdown
          final store1Completed =
              store1Orders.where((o) => o.status == 'completed').toList();
          expect(store1Completed.length, equals(15));
          final store1Total =
              store1Completed.fold<double>(0.0, (sum, o) => sum + o.total);
          expect(store1Total, equals(127311000.0),
              reason: '104,361,000 + 15,800,000 + 7,150,000 = 127,311,000đ');

          // Store 2 breakdown
          final store2Completed =
              store2Orders.where((o) => o.status == 'completed').toList();
          expect(store2Completed.length, equals(2));
          final store2Total =
              store2Completed.fold<double>(0.0, (sum, o) => sum + o.total);
          expect(store2Total, equals(231000000.0));

          expect(store1Total + store2Total, equals(358311000.0));
        });
      });
    });

    // -------------------------------------------------------------------------
    // 4. Store Resolution Logic Across Aliases
    // -------------------------------------------------------------------------
    group('4. Store Key & Alias Resolution Logic Verification', () {
      test('FifoCalculator.normalizeStoreKey accurately maps all valid aliases',
          () {
        // Canonical store keys
        expect(FifoCalculator.normalizeStoreKey('store_001'),
            equals('store_001'));
        expect(FifoCalculator.normalizeStoreKey('store_002'),
            equals('store_002'));

        // Legacy branch aliases
        expect(FifoCalculator.normalizeStoreKey('branch_1'),
            equals('store_001'));
        expect(FifoCalculator.normalizeStoreKey('branch_2'),
            equals('store_002'));

        // Short codes
        expect(FifoCalculator.normalizeStoreKey('ĐT'), equals('store_001'));
        expect(FifoCalculator.normalizeStoreKey('TB'), equals('store_002'));

        // Vietnamese names
        expect(FifoCalculator.normalizeStoreKey('Chi nhánh Đông Thắng'),
            equals('store_001'));
        expect(FifoCalculator.normalizeStoreKey('Chi nhánh Thới Bình'),
            equals('store_002'));
        expect(FifoCalculator.normalizeStoreKey('đông thắng'),
            equals('store_001'));
        expect(FifoCalculator.normalizeStoreKey('thới bình'),
            equals('store_002'));

        // Case insensitivity and whitespace trimming
        expect(FifoCalculator.normalizeStoreKey('  store_001  '),
            equals('store_001'));
        expect(FifoCalculator.normalizeStoreKey(' branch_2 '),
            equals('store_002'));
        expect(FifoCalculator.normalizeStoreKey('  ĐT  '), equals('store_001'));
        expect(FifoCalculator.normalizeStoreKey('  TB  '), equals('store_002'));

        // Empty / null fallback
        expect(FifoCalculator.normalizeStoreKey(null), equals('default'));
        expect(FifoCalculator.normalizeStoreKey(''), equals('default'));


        // Custom store ID preserves key
        expect(FifoCalculator.normalizeStoreKey('store_hn_01'),
            equals('store_hn_01'));
      });

      test(
          'Simulated targetStoreIds resolution handles multi-select combinations',
          () {
        List<String> resolveTargetStores(List<String> selectedBranches) {
          final List<String> targetStoreIds = [];
          for (final branchId in selectedBranches) {
            final canonicalId = FifoCalculator.normalizeStoreKey(branchId);
            if (canonicalId != 'default') {
              if (!targetStoreIds.contains(canonicalId)) {
                targetStoreIds.add(canonicalId);
              }
            } else if (!targetStoreIds.contains(branchId)) {
              targetStoreIds.add(branchId);
            }
          }
          if (targetStoreIds.isEmpty) {
            targetStoreIds.add('store_001'); // fallback
          }
          return targetStoreIds;
        }

        // When UI sends canonical IDs ['store_001', 'store_002']
        expect(resolveTargetStores(['store_001', 'store_002']),
            equals(['store_001', 'store_002']));

        // When UI sends legacy IDs ['branch_1', 'branch_2']
        expect(resolveTargetStores(['branch_1', 'branch_2']),
            equals(['store_001', 'store_002']));

        // When UI sends short codes ['ĐT', 'TB']
        expect(resolveTargetStores(['ĐT', 'TB']),
            equals(['store_001', 'store_002']));

        // When UI sends Vietnamese names
        expect(
            resolveTargetStores(
                ['Chi nhánh Đông Thắng', 'Chi nhánh Thới Bình']),
            equals(['store_001', 'store_002']));

        // Single store selection
        expect(resolveTargetStores(['store_002']), equals(['store_002']));
        expect(resolveTargetStores(['TB']), equals(['store_002']));
        expect(resolveTargetStores(['branch_2']), equals(['store_002']));

        // Empty selected branches fallback
        expect(resolveTargetStores([]), equals(['store_001']));
      });
    });

    // -------------------------------------------------------------------------
    // 5. FIFO Engine Verification with Sample Transactions
    // -------------------------------------------------------------------------
    group('5. FIFO Inventory Engine Ingestion with Sample Data Transactions',
        () {
      test(
          'Initializes FifoCalculator with sample data transactions and computes sequential lot depletion',
          () {
        final txsStore1 = store001TxRaw.entries.map((e) {
          final map = Map<String, dynamic>.from(e.value as Map);
          map['id'] = e.key;
          final m = InventoryTransactionModel.fromMap(map);
          return m.toEntity();
        }).toList();

        final fifo = FifoCalculator(txsStore1, 'store_001');

        // GCG08 chronological sequence in data_mau.json:
        // 1. Import 2 @ 2,100,000 (2026-07-05 12:35)
        // 2. Import 2 @ 2,100,000 (2026-07-05 21:05)
        // 3. Export 1 (2026-07-08) -> 3 remaining @ 2,100,000
        // 4. Export 1 (2026-07-26 09:06) -> 2 remaining @ 2,100,000
        // 5. Export 1 (2026-07-26 09:06) -> 1 remaining @ 2,100,000
        // 6. Import 11 @ 1,000 (2026-07-26 12:20)
        //
        // On 2026-08-01:
        // 1 unit remaining in the 2,100,000 lot, followed by 11 units in the 1,000 lot.
        final cost1Unit = fifo.calculateCostForSale(
          productId: 'GCG08',
          quantity: 1,
          saleDate: DateTime(2026, 8, 1),
          storeId: 'store_001',
          fallbackCostPrice: 1000.0,
        );
        expect(cost1Unit, equals(2100000.0),
            reason:
                'First sale on 2026-08-01 takes the 1 remaining unit from initial 2,100,000đ lot');

        // Subsequent sale of 2 units on 2026-08-01:
        // That 2,100,000 unit is now consumed, so the next units come from the 1,000đ lot
        final costNext2Units = fifo.calculateCostForSale(
          productId: 'GCG08',
          quantity: 2,
          saleDate: DateTime(2026, 8, 1, 1),
          storeId: 'store_001',
          fallbackCostPrice: 1000.0,
        );
        expect(costNext2Units, equals(2000.0),
            reason: 'Next 2 units come from the 11-unit lot @ 1,000đ');

        // Profit margin calculation for GCG08 sold at 2,700,000 with cost 2,100,000
        final profitMargin1 =
            FifoCalculator.calculateProfitMargin(2700000.0, 2100000.0);
        expect(profitMargin1, closeTo(22.22, 0.01));

        // Profit margin for subsequent unit sold at 2,700,000 with cost 1,000
        final profitMargin2 =
            FifoCalculator.calculateProfitMargin(2700000.0, 1000.0);
        expect(profitMargin2, closeTo(99.96, 0.01));
      });
    });
  });
}
