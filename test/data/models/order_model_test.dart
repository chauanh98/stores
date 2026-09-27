import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/excel_helper.dart';
import 'package:stores/data/models/order_model.dart';
import 'package:stores/domain/entities/order.dart';

void main() {
  group('OrderModel.fromMap Legacy Discount Reconstruction Tests', () {
    test(
        'Reconstructs gross total and discount when itemsSum > rawTotal and discount == 0',
        () {
      final legacyMap = {
        'id': 'HD_LEGACY_001',
        'customerId': 'cust_001',
        'createdAt': '2026-09-15T10:00:00.000Z',
        'total': 434030000.0, // netPayable stored in legacy total
        'status': 'completed',
        'amountPaid': 434030000.0,
        'debtAmount': 0.0,
        'items': [
          {
            'productId': 'prod_01',
            'productName': 'Sản phẩm 1',
            'quantity': 10,
            'price': 40000000.0, // 400.000.000
            'warrantyMonths': 12,
            'purchaseDate': '2026-09-15T10:00:00.000Z',
          },
          {
            'productId': 'prod_02',
            'productName': 'Sản phẩm 2',
            'quantity': 1,
            'price': 45360000.0, // 45.360.000 => itemsSum = 445.360.000
            'warrantyMonths': 12,
            'purchaseDate': '2026-09-15T10:00:00.000Z',
          },
        ],
      };

      final model = OrderModel.fromMap(legacyMap);

      expect(model.total, equals(445360000.0),
          reason: 'Total should be reconstructed to itemsSum');
      expect(model.discount, equals(11330000.0),
          reason: 'Discount should be itemsSum - rawTotal');
      expect(model.amountPaid, equals(434030000.0));
      expect(model.debtAmount, equals(0.0));

      final domainOrder = Order(
        id: model.id,
        customerId: model.customerId,
        createdAt: model.createdAt,
        items: const [],
        total: model.total,
        discount: model.discount,
        amountPaid: model.amountPaid,
        debtAmount: model.debtAmount,
        status: model.status,
      );
      expect(domainOrder.netPayable, equals(434030000.0));
    });

    test(
        'All 100 Thới Bình orders converted to legacy maps are accurately reconstructed',
        () {
      final excelFile =
          File('DanhSachChiTietHoaDon_KV20092026-185010-522.xlsx');
      if (!excelFile.existsSync()) return;

      final originalOrders = ExcelHelper.parseInvoices(
        excelFile.readAsBytesSync(),
        defaultStoreId: 'store_002',
      );
      expect(originalOrders.length, equals(100));

      // Simulate legacy Firebase database maps where 'total' was saved as netPayable and 'discount' was omitted
      final legacyFirebaseMaps = originalOrders.map((o) {
        return {
          'id': o.id,
          'customerId': o.customerId,
          'customerName': o.customerName,
          'createdAt': o.createdAt.toIso8601String(),
          'total': o.netPayable,
          // The legacy bug: total stored netPayable instead of gross
          // 'discount' is deliberately omitted
          'status': o.status,
          'amountPaid': o.amountPaid,
          'debtAmount': o.debtAmount,
          'paymentMethod': o.paymentMethod,
          'storeId': o.storeId,
          'items': o.items
              .map((i) => {
                    'productId': i.productId,
                    'productName': i.productName,
                    'quantity': i.quantity,
                    'price': i.price,
                    'warrantyMonths': i.warrantyMonths,
                    'purchaseDate': i.purchaseDate.toIso8601String(),
                  })
              .toList(),
        };
      }).toList();

      // Deserializing with OrderModel.fromMap should automatically restore gross total & discount!
      final reconstructedModels =
          legacyFirebaseMaps.map((m) => OrderModel.fromMap(m)).toList();

      // 1. All 100 orders
      final totalGross =
          reconstructedModels.fold<double>(0.0, (sum, m) => sum + m.total);
      final totalDiscount =
          reconstructedModels.fold<double>(0.0, (sum, m) => sum + m.discount);
      final totalNetPayable = reconstructedModels.fold<double>(
          0.0, (sum, m) => sum + (m.total - m.discount));

      expect(totalGross, equals(445360000.0),
          reason: 'Total Gross should be 445.360.000đ');
      expect(totalDiscount, equals(11330000.0),
          reason: 'Total Discount should be 11.330.000đ');
      expect(totalNetPayable, equals(434030000.0),
          reason: 'Total Net Payable should be 434.030.000đ');

      // 2. 94 Completed orders
      final completedModels =
          reconstructedModels.where((m) => m.status == 'completed').toList();
      expect(completedModels.length, equals(94));

      final completedGross =
          completedModels.fold<double>(0.0, (sum, m) => sum + m.total);
      final completedDiscount =
          completedModels.fold<double>(0.0, (sum, m) => sum + m.discount);
      final completedNet = completedModels.fold<double>(
          0.0, (sum, m) => sum + (m.total - m.discount));

      expect(completedGross, equals(416880000.0),
          reason: 'Completed Gross should be 416.880.000đ');
      expect(completedDiscount, equals(10500000.0),
          reason: 'Completed Discount should be 10.500.000đ');
      expect(completedNet, equals(406380000.0),
          reason: 'Completed Net Payable should be 406.380.000đ');

      // 3. 6 Cancelled orders
      final cancelledModels =
          reconstructedModels.where((m) => m.status == 'cancelled').toList();
      expect(cancelledModels.length, equals(6));

      final cancelledGross =
          cancelledModels.fold<double>(0.0, (sum, m) => sum + m.total);
      final cancelledDiscount =
          cancelledModels.fold<double>(0.0, (sum, m) => sum + m.discount);
      final cancelledNet = cancelledModels.fold<double>(
          0.0, (sum, m) => sum + (m.total - m.discount));

      expect(cancelledGross, equals(28480000.0),
          reason: 'Cancelled Gross should be 28.480.000đ');
      expect(cancelledDiscount, equals(830000.0),
          reason: 'Cancelled Discount should be 830.000đ');
      expect(cancelledNet, equals(27650000.0),
          reason: 'Cancelled Net Payable should be 27.650.000đ');
    });

    test('Does not mutate total or discount if discount already exists (> 0)',
        () {
      final map = {
        'id': 'HD_MODERN_01',
        'customerId': 'cust_01',
        'createdAt': '2026-09-15T10:00:00.000Z',
        'total': 1000000.0,
        'discount': 150000.0,
        'items': [
          {
            'productId': 'p1',
            'productName': 'Item 1',
            'quantity': 1,
            'price': 1000000.0,
            'warrantyMonths': 0,
            'purchaseDate': '2026-09-15T10:00:00.000Z',
          }
        ],
      };

      final model = OrderModel.fromMap(map);
      expect(model.total, equals(1000000.0));
      expect(model.discount, equals(150000.0));
    });

    test('Does not mutate total when itemsSum == rawTotal (no discount)', () {
      final map = {
        'id': 'HD_NO_DISCOUNT_01',
        'customerId': 'cust_01',
        'createdAt': '2026-09-15T10:00:00.000Z',
        'total': 500000.0,
        'discount': 0.0,
        'items': [
          {
            'productId': 'p1',
            'productName': 'Item 1',
            'quantity': 2,
            'price': 250000.0,
            'warrantyMonths': 0,
            'purchaseDate': '2026-09-15T10:00:00.000Z',
          }
        ],
      };

      final model = OrderModel.fromMap(map);
      expect(model.total, equals(500000.0));
      expect(model.discount, equals(0.0));
    });

    test('Supports Firebase RTDB items represented as a Map of keys', () {
      final mapWithMapItems = {
        'id': 'HD_MAP_ITEMS_01',
        'customerId': 'cust_01',
        'createdAt': '2026-09-15T10:00:00.000Z',
        'total': 900000.0,
        'items': {
          '0': {
            'productId': 'p1',
            'productName': 'Item 1',
            'quantity': 1,
            'price': 600000.0,
            'warrantyMonths': 0,
            'purchaseDate': '2026-09-15T10:00:00.000Z',
          },
          '1': {
            'productId': 'p2',
            'productName': 'Item 2',
            'quantity': 2,
            'price': 200000.0, // 400k => sum = 1,000,000
            'warrantyMonths': 0,
            'purchaseDate': '2026-09-15T10:00:00.000Z',
          },
        },
      };

      final model = OrderModel.fromMap(mapWithMapItems);
      expect(model.items.length, equals(2));
      expect(model.total, equals(1000000.0));
      expect(model.discount, equals(100000.0));
    });

    test('Cancelled order with null amountPaid defaults to 0.0', () {
      final cancelledMap = {
        'id': 'HD_CANCELLED_01',
        'customerId': 'cust_01',
        'createdAt': '2026-09-15T10:00:00.000Z',
        'total': 1000000.0,
        'status': 'cancelled',
        'items': [],
      };

      final model = OrderModel.fromMap(cancelledMap);
      expect(model.amountPaid, equals(0.0));
      expect(model.debtAmount, equals(0.0));
    });

    test(
        'Adversarial: safely parses stringified numbers and null warranty/quantity in items',
        () {
      final rawMap = {
        'id': 'HD_EDGE_001',
        'customerId': 'cust_01',
        'createdAt': '2026-09-15T10:00:00.000Z',
        'total': '900000',
        'discount': '0',
        'status': 'completed',
        'amountPaid': '900000',
        'debtAmount': '0',
        'cashAmount': '500000',
        'transferAmount': '400000',
        'items': [
          {
            'productId': 101,
            // int instead of String
            'productName': 'Item with null warranty and double quantity',
            'quantity': 2.0,
            // double instead of int
            'price': '500000',
            // String instead of double => itemsSum = 1,000,000
            'warrantyMonths': null,
            // null warranty
            'purchaseDate': null,
            // null date
          },
          null, // corrupted null entry in list
        ],
      };

      final model = OrderModel.fromMap(rawMap);
      expect(model.items.length, equals(1));
      expect(model.items.first.productId, equals('101'));
      expect(model.items.first.quantity, equals(2));
      expect(model.items.first.price, equals(500000.0));
      expect(model.items.first.warrantyMonths, equals(0));
      expect(model.total, equals(1000000.0),
          reason: 'Reconstructed gross total');
      expect(model.discount, equals(100000.0),
          reason: 'Reconstructed discount');
      expect(model.cashAmount, equals(500000.0));
      expect(model.transferAmount, equals(400000.0));
    });

    test(
        'Adversarial: Float precision micro-drift does not trigger false discount',
        () {
      final map = {
        'id': 'HD_FLOAT_DRIFT',
        'customerId': 'cust_01',
        'total': 100000.0,
        'discount': 0.0,
        'items': [
          {
            'productId': 'p1',
            'productName': 'Item',
            'quantity': 1,
            'price': 100000.0000000001, // IEEE 754 micro-drift
            'warrantyMonths': 0,
            'purchaseDate': '2026-09-15',
          }
        ],
      };

      final model = OrderModel.fromMap(map);
      expect(model.discount, equals(0.0),
          reason: 'Micro-drift <= 0.01 must not trigger discount');
      expect(model.total, equals(100000.0));
    });

    test('Adversarial: Non-string map keys in items do not crash or drop items',
        () {
      final map = {
        'id': 'HD_NON_STRING_KEYS',
        'customerId': 'cust_01',
        'total': 80000.0,
        'discount': 0.0,
        'items': [
          {
            'productId': 'p1',
            'productName': 'Item 1',
            'quantity': 1,
            'price': 100000.0,
            'warrantyMonths': 0,
            101: 'integer_key_metadata',
            'purchaseDate': '2026-09-15',
          }
        ],
      };

      final model = OrderModel.fromMap(map);
      expect(model.items.length, equals(1),
          reason: 'Item with int key must not be dropped');
      expect(model.items.first.productId, equals('p1'));
      expect(model.total, equals(100000.0), reason: 'Reconstructs total');
      expect(model.discount, equals(20000.0), reason: 'Reconstructs discount');
    });

    test(
        'Adversarial: Normalizes status and paymentMethod across Vietnamese and localized strings',
        () {
      final cancelledMap = {
        'id': 'HD_STATUS_NORM_1',
        'status': 'Đã hủy',
        'paymentMethod': 'Chuyển khoản',
        'total': 50000.0,
        'items': [],
      };
      final m1 = OrderModel.fromMap(cancelledMap);
      expect(m1.status, equals('cancelled'));
      expect(m1.paymentMethod, equals('transfer'));

      final returnedMap = {
        'id': 'HD_STATUS_NORM_2',
        'status': 'Trả hàng',
        'paymentMethod': 'Kết hợp',
        'total': 50000.0,
        'items': [],
      };
      final m2 = OrderModel.fromMap(returnedMap);
      expect(m2.status, equals('returned'));
      expect(m2.paymentMethod, equals('split'));

      final draftMap = {
        'id': 'HD_STATUS_NORM_3',
        'status': 'Lưu tạm',
        'paymentMethod': 'Tiền mặt',
        'total': 50000.0,
        'items': [],
      };
      final m3 = OrderModel.fromMap(draftMap);
      expect(m3.status, equals('draft'));
      expect(m3.paymentMethod, equals('cash'));
    });

    test('Adversarial: Negative item price is clamped to 0.0', () {
      final map = {
        'id': 'HD_NEG_PRICE',
        'customerId': 'cust_01',
        'total': 0.0,
        'discount': 0.0,
        'items': [
          {
            'productId': 'p1',
            'productName': 'Item',
            'quantity': 1,
            'price': -50000.0,
          }
        ],
      };

      final model = OrderModel.fromMap(map);
      expect(model.items.first.price, equals(0.0),
          reason: 'Negative price clamped to 0.0');
    });

    test(
        'Adversarial: Traditional Vietnamese tone placement (huỷ) and US spelling (canceled) are normalized',
        () {
      // 1. Traditional tone placement on 'y': 'huỷ' (U+0068 U+0075 U+1EF7)
      final traditionalMap = {
        'id': 'HD_TRAD_TONE',
        'status': 'Đã huỷ',
        'paymentMethod': 'ck',
        'total': 100000.0,
        'items': [],
      };
      final m1 = OrderModel.fromMap(traditionalMap);
      expect(m1.status, equals('cancelled'));
      expect(m1.paymentMethod, equals('transfer'));

      // 2. US spelling 'canceled' and 'banking'
      final usMap = {
        'id': 'HD_US_SPELL',
        'status': 'Canceled',
        'paymentMethod': 'Banking online',
        'total': 100000.0,
        'items': [],
      };
      final m2 = OrderModel.fromMap(usMap);
      expect(m2.status, equals('cancelled'));
      expect(m2.paymentMethod, equals('transfer'));

      // 3. Unaccented 'da huy' and 'chuyen khoan'
      final unaccentedMap = {
        'id': 'HD_UNACCENTED',
        'status': 'da huy',
        'paymentMethod': 'chuyen khoan',
        'total': 100000.0,
        'items': [],
      };
      final m3 = OrderModel.fromMap(unaccentedMap);
      expect(m3.status, equals('cancelled'));
      expect(m3.paymentMethod, equals('transfer'));
    });

    test(
        'Adversarial: Negative discount, total and debt are clamped, and Order.remainingDebt contract holds',
        () {
      final negMap = {
        'id': 'HD_NEG_VALS',
        'total': -100000.0,
        'discount': -20000.0,
        'amountPaid': -500.0,
        'debtAmount': -5000.0,
        'status': 'cancelled',
        'items': [],
      };
      final model = OrderModel.fromMap(negMap);
      expect(model.total, equals(0.0));
      expect(model.discount, equals(0.0));
      expect(model.amountPaid, equals(0.0));
      expect(model.debtAmount, equals(0.0));

      // Domain Order entity without explicit debtAmount evaluates to 0.0 on cancellation
      final orderNoDebt = Order(
        id: 'HD_CANCELLED_NO_DEBT',
        customerId: 'CUST_1',
        createdAt: DateTime.now(),
        items: const [],
        total: 1000000.0,
        discount: 100000.0,
        status: 'cancelled',
        amountPaid: 0.0,
        debtAmount: 0.0,
      );
      expect(orderNoDebt.isCancelled, isTrue);
      expect(orderNoDebt.remainingDebt, equals(0.0));
      expect(orderNoDebt.hasDebt, isFalse);

      // Cancelled order strictly has 0.0 remaining debt even if debtAmount was recorded
      final orderWithDebt = orderNoDebt.copyWith(debtAmount: 900000.0);
      expect(orderWithDebt.isCancelled, isTrue);
      expect(orderWithDebt.remainingDebt, equals(0.0));
      expect(orderWithDebt.hasDebt, isFalse);

      // Completed Order with explicit recorded debtAmount preserves that debt
      final completedOrderWithDebt =
          orderWithDebt.copyWith(status: 'completed');
      expect(completedOrderWithDebt.isCancelled, isFalse);
      expect(completedOrderWithDebt.remainingDebt, equals(900000.0));
      expect(completedOrderWithDebt.hasDebt, isTrue);
    });
  });
}
