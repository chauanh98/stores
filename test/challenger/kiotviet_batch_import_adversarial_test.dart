import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Challenger 2: Adversarial Stress Testing on KiotViet Staged Data', () {
    final workspaceDir = Directory.current.path;
    final stagingDir = '$workspaceDir/data_staging';

    final customersFile = File('$stagingDir/customers_clean.json');
    final suppliersFile = File('$stagingDir/suppliers_clean.json');
    final productsFile = File('$stagingDir/products_clean.json');
    final ordersFile = File('$stagingDir/orders_clean.json');

    test('All staged JSON files exist and are non-empty', () {
      expect(customersFile.existsSync(), isTrue);
      expect(suppliersFile.existsSync(), isTrue);
      expect(productsFile.existsSync(), isTrue);
      expect(ordersFile.existsSync(), isTrue);

      expect(customersFile.lengthSync(), greaterThan(1000000));
      expect(suppliersFile.lengthSync(), greaterThan(10000));
      expect(productsFile.lengthSync(), greaterThan(1000000));
      expect(ordersFile.lengthSync(), greaterThan(1000000));
    });

    test('Dart DateTime.parse() stress test: 100% of ISO 8601 timestamps parse cleanly', () {
      int totalDatesChecked = 0;

      // 1. Customers
      final customers = jsonDecode(customersFile.readAsStringSync()) as List;
      for (final c in customers) {
        final map = c as Map<String, dynamic>;
        for (final field in ['createdAt', 'dob', 'lastTransactionDate']) {
          final val = map[field];
          if (val != null && val is String && val.isNotEmpty) {
            totalDatesChecked++;
            expect(() => DateTime.parse(val), returnsNormally,
                reason: 'Failed parsing $field: $val in customer ${map['id']}');
            final parsed = DateTime.parse(val);
            expect(parsed.year, inInclusiveRange(1900, 2030));
          }
        }
      }

      // 2. Suppliers
      final suppliers = jsonDecode(suppliersFile.readAsStringSync()) as List;
      for (final s in suppliers) {
        final map = s as Map<String, dynamic>;
        for (final field in ['createdAt', 'lastTransactionDate']) {
          final val = map[field];
          if (val != null && val is String && val.isNotEmpty) {
            totalDatesChecked++;
            expect(() => DateTime.parse(val), returnsNormally,
                reason: 'Failed parsing $field: $val in supplier ${map['id']}');
            final parsed = DateTime.parse(val);
            expect(parsed.year, inInclusiveRange(1900, 2030));
          }
        }
      }

      // 3. Products
      final products = jsonDecode(productsFile.readAsStringSync()) as List;
      for (final p in products) {
        final map = p as Map<String, dynamic>;
        for (final field in ['createdAt']) {
          final val = map[field];
          if (val != null && val is String && val.isNotEmpty) {
            totalDatesChecked++;
            expect(() => DateTime.parse(val), returnsNormally,
                reason: 'Failed parsing $field: $val in product ${map['id']}');
            final parsed = DateTime.parse(val);
            expect(parsed.year, inInclusiveRange(1900, 2030));
          }
        }
      }

      // 4. Orders
      final orders = jsonDecode(ordersFile.readAsStringSync()) as List;
      for (final o in orders) {
        final map = o as Map<String, dynamic>;
        for (final field in ['createdAt', 'completedAt']) {
          final val = map[field];
          if (val != null && val is String && val.isNotEmpty) {
            totalDatesChecked++;
            expect(() => DateTime.parse(val), returnsNormally,
                reason: 'Failed parsing $field: $val in order ${map['id']}');
            final parsed = DateTime.parse(val);
            expect(parsed.year, inInclusiveRange(1900, 2030));
          }
        }
      }

      expect(totalDatesChecked, equals(19599),
          reason: 'Expected exactly 19,599 non-null date fields across all datasets');
    });

    test('Vietnamese Unicode integrity & mojibake detection', () {
      final mojibakeRegex = RegExp(r'(Ã[¡-¿]|áº|á»|â€|ï¿½|\\u[0-9a-fA-F]{4})');
      final vnCharRegex = RegExp(r'[àáảãạăắằẳẵặâấầẩẫậèéẻẽẹêếềểễệìíỉĩịòóỏõọôốồổỗộơớờởỡợùúủũụưứừửữựỳýỷỹỵđĐ]');

      int totalStrings = 0;
      int totalVnStrings = 0;
      int parenthesesCount = 0;
      int slashesCount = 0;

      void checkValue(dynamic val, String context) {
        if (val is String) {
          totalStrings++;
          expect(mojibakeRegex.hasMatch(val), isFalse,
              reason: 'Mojibake detected in $context: "$val"');
          if (vnCharRegex.hasMatch(val)) {
            totalVnStrings++;
          }
          if (val.contains('(') || val.contains(')')) {
            parenthesesCount++;
          }
          if (val.contains('/') || val.contains('\\')) {
            slashesCount++;
          }
        } else if (val is Map) {
          for (final entry in val.entries) {
            checkValue(entry.key, '$context.key');
            checkValue(entry.value, '$context.${entry.key}');
          }
        } else if (val is List) {
          for (int i = 0; i < val.length; i++) {
            checkValue(val[i], '$context[$i]');
          }
        }
      }

      checkValue(jsonDecode(customersFile.readAsStringSync()), 'customers');
      checkValue(jsonDecode(suppliersFile.readAsStringSync()), 'suppliers');
      checkValue(jsonDecode(productsFile.readAsStringSync()), 'products');
      checkValue(jsonDecode(ordersFile.readAsStringSync()), 'orders');

      expect(totalStrings, greaterThan(150000));
      expect(totalVnStrings, greaterThan(60000));
      expect(parenthesesCount, greaterThan(1000));
      expect(slashesCount, greaterThan(1000));
    });

    test('Verify customer synthetic stub KH002414 and discontinued products', () {
      final customers = jsonDecode(customersFile.readAsStringSync()) as List;
      final stub = customers.firstWhere((c) => c['id'] == 'KH002414', orElse: () => null);
      expect(stub, isNotNull);
      expect(stub['name'], equals('Chị Thạnh (VPCC)'));
      expect(stub['status'], equals('inactive'));

      final products = jsonDecode(productsFile.readAsStringSync()) as List;
      final discontinuedIds = [
        'BTDB16', 'HS18', 'HS19', 'HS20', 'THOB14',
        'TTTR6', 'TTTR7', 'TTTR8', 'VG1', 'VG2', 'VG5'
      ];
      for (final id in discontinuedIds) {
        final prod = products.firstWhere((p) => p['id'] == id, orElse: () => null);
        expect(prod, isNotNull, reason: 'Discontinued product $id missing');
        expect(prod['allowSale'], isFalse, reason: 'Product $id allowSale should be false');
        expect(prod['description'], contains('ngừng kinh doanh'));
      }
    });

    test('Verify orders line items aggregation integrity', () {
      final orders = jsonDecode(ordersFile.readAsStringSync()) as List;
      expect(orders.length, equals(3929));

      int totalItems = 0;
      double sumPayable = 0.0;
      for (final o in orders) {
        final items = o['items'] as List;
        expect(items.isNotEmpty, isTrue, reason: 'Order ${o['id']} has no items');
        totalItems += items.length;
        sumPayable += ((o['finalAmount'] ?? o['total'] ?? 0) as num).toDouble();

        for (final item in items) {
          expect(item['productId'], isNotNull);
          expect(item['productName'], isNotNull);
          expect(item['quantity'], greaterThan(0));
          expect(item['price'], greaterThanOrEqualTo(0));
        }
      }

      expect(totalItems, equals(6012));
      expect((sumPayable - 23373637200.0).abs(), lessThan(1.0));
    });
  });
}
