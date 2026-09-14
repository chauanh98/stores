import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/data/models/inventory_transaction_model.dart';
import 'package:stores/data/repositories/revenue_repository_impl.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';

class MockOrderRemoteDataSource extends Fake implements OrderRemoteDataSource {
  final String _storeId;
  MockOrderRemoteDataSource([this._storeId = 'store_001']);

  @override
  String get storeId => _storeId;
}

class MockInventoryRemoteDataSource extends Fake
    implements InventoryRemoteDataSource {
  final List<Map> mockData;
  MockInventoryRemoteDataSource(this.mockData);

  @override
  Future<List<Map>> fetchAll() async => mockData;
}

class MockProductRemoteDataSource extends Fake
    implements ProductRemoteDataSource {
  final List<Map> mockData;
  MockProductRemoteDataSource(this.mockData);

  @override
  Future<List<Map>> fetchAll() async => mockData;
}

Map<String, dynamic> createMockOrder({
  required String id,
  required String customerId,
  required DateTime date,
  required List<Map<String, dynamic>> items,
  required double total,
  String status = 'completed',
}) {
  return {
    'id': id,
    'customerId': customerId,
    'createdAt': date.toIso8601String(),
    'total': total,
    'status': status,
    'items': items.map((item) {
      return {
        'productId': item['productId'] ?? '',
        'productName': item['productName'] ?? '',
        'quantity': item['quantity'] ?? 1,
        'price': (item['price'] as num?)?.toDouble() ?? 0.0,
        'warrantyMonths': item['warrantyMonths'] ?? 0,
        'purchaseDate': (item['purchaseDate'] is String)
            ? item['purchaseDate']
            : date.toIso8601String(),
      };
    }).toList(),
  };
}

void main() {
  group('Challenger 2 Empirical Stress-Tests: Cases 4 & 5 Audits, Multi-Day Revenue & Multi-Store', () {

    // =========================================================================
    // 1. CASE 4 & 5: STRUCTURED FIELDS & EDGE CASE STRESS TESTS
    // =========================================================================
    group('Case 4 & 5 Stock Audits & Invariants', () {
      test('Consecutive mixed audits (Audit+ -> Audit- -> Audit+ -> Audit-) maintain precise lot queues', () {
        final txs = [
          // Initial Import: 10 @ 10,000
          InventoryTransaction(
            id: 'tx_init',
            productId: 'p_audit_consec',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2024, 1, 1),
            note: 'Initial import',
            importPrice: 10000.0,
            storeId: 'store_001',
          ),
          // Audit 1 (+): +5 @ 12,000 (diff = +5)
          InventoryTransaction(
            id: 'tx_aud1_plus',
            productId: 'p_audit_consec',
            type: TransactionType.inventoryAudit,
            quantity: 5,
            date: DateTime(2024, 1, 2),
            note: 'Cân bằng tăng +5',
            importPrice: 12000.0,
            storeId: 'store_001',
            isAuditNegative: false,
            auditDifference: 5,
          ),
          // Audit 2 (-): -8 (deficit: 8 deducted from oldest lot -> lot 1 has 2 left)
          InventoryTransaction(
            id: 'tx_aud2_minus',
            productId: 'p_audit_consec',
            type: TransactionType.inventoryAudit,
            quantity: 8,
            date: DateTime(2024, 1, 3),
            note: 'Cân bằng giảm -8',
            importPrice: 10000.0,
            storeId: 'store_001',
            isAuditNegative: true,
            auditDifference: -8,
          ),
          // Audit 3 (+): +10 @ 15,000 (diff = +10)
          InventoryTransaction(
            id: 'tx_aud3_plus',
            productId: 'p_audit_consec',
            type: TransactionType.inventoryAudit,
            quantity: 10,
            date: DateTime(2024, 1, 4),
            note: 'Cân bằng tăng +10',
            importPrice: 15000.0,
            storeId: 'store_001',
            isAuditNegative: false,
            auditDifference: 10,
          ),
          // Audit 4 (-): -4 (deficit: 2 from lot 1 (exhausted), 2 from lot 2 (3 left))
          InventoryTransaction(
            id: 'tx_aud4_minus',
            productId: 'p_audit_consec',
            type: TransactionType.inventoryAudit,
            quantity: 4,
            date: DateTime(2024, 1, 5),
            note: 'Cân bằng giảm -4',
            importPrice: 10000.0,
            storeId: 'store_001',
            isAuditNegative: true,
            auditDifference: -4,
          ),
        ];

        final fifo = FifoCalculator(txs);
        final lots = fifo.getInventoryLots('p_audit_consec', storeId: 'store_001');

        // Remaining breakdown:
        // Lot 1 (init): 10 - 8 (aud2) - 2 (aud4) = 0 remaining
        // Lot 2 (aud1): 5 - 2 (aud4) = 3 remaining @ 12,000
        // Lot 3 (aud3): 10 remaining @ 15,000
        expect(lots.length, equals(3));
        expect(lots[0].remainingQuantity, equals(0));
        expect(lots[1].remainingQuantity, equals(3));
        expect(lots[1].importPrice, equals(12000.0));
        expect(lots[2].remainingQuantity, equals(10));
        expect(lots[2].importPrice, equals(15000.0));
        expect(fifo.getRemainingQuantity('p_audit_consec', storeId: 'store_001'), equals(13));

        // Now perform a sale of 5 items on Jan 6:
        // Draws 3 @ 12,000 + 2 @ 15,000 = 36,000 + 30,000 = 66,000
        final cost = fifo.calculateCostForSale(
          productId: 'p_audit_consec',
          quantity: 5,
          saleDate: DateTime(2024, 1, 6),
          storeId: 'store_001',
        );

        expect(cost, equals(66000.0));
        expect(lots[1].remainingQuantity, equals(0));
        expect(lots[2].remainingQuantity, equals(8));
        expect(fifo.getRemainingQuantity('p_audit_consec', storeId: 'store_001'), equals(8));
      });

      test('Large negative audit exceeding total available stock clamps lots at 0 without negative quantities', () {
        final txs = [
          InventoryTransaction(
            id: 'tx_init1',
            productId: 'p_heavy_neg',
            type: TransactionType.import,
            quantity: 5,
            date: DateTime(2024, 1, 1),
            note: 'Import 5',
            importPrice: 50000.0,
            storeId: 'store_001',
          ),
          InventoryTransaction(
            id: 'tx_init2',
            productId: 'p_heavy_neg',
            type: TransactionType.import,
            quantity: 5,
            date: DateTime(2024, 1, 2),
            note: 'Import 5',
            importPrice: 60000.0,
            storeId: 'store_001',
          ),
          // Massive negative audit: deficit of 100 items when stock is only 10
          InventoryTransaction(
            id: 'tx_audit_huge_neg',
            productId: 'p_heavy_neg',
            type: TransactionType.inventoryAudit,
            quantity: 100,
            date: DateTime(2024, 1, 3),
            note: 'Kiểm kê thất thoát lớn',
            importPrice: 50000.0,
            storeId: 'store_001',
            isAuditNegative: true,
            auditDifference: -100,
          ),
        ];

        final fifo = FifoCalculator(txs);
        final lots = fifo.getInventoryLots('p_heavy_neg', storeId: 'store_001');

        // All lots must be clamped at 0, strictly NON-NEGATIVE
        expect(lots[0].remainingQuantity, equals(0));
        expect(lots[1].remainingQuantity, equals(0));
        expect(fifo.getRemainingQuantity('p_heavy_neg', storeId: 'store_001'), equals(0));

        // Subsequent sale of 4 items must use fallback cost without crashing
        final cost = fifo.calculateCostForSale(
          productId: 'p_heavy_neg',
          quantity: 4,
          saleDate: DateTime(2024, 1, 4),
          storeId: 'store_001',
          fallbackCostPrice: 70000.0,
        );

        expect(cost, equals(280000.0)); // 4 * 70,000
        expect(lots[0].remainingQuantity, equals(0));
        expect(lots[1].remainingQuantity, equals(0));
      });

      test('Negative audit on completely empty lot queue does not throw and preserves state', () {
        final txs = [
          InventoryTransaction(
            id: 'tx_audit_empty',
            productId: 'p_empty',
            type: TransactionType.inventoryAudit,
            quantity: 10,
            date: DateTime(2024, 1, 1),
            note: 'Audit negative on 0 stock',
            storeId: 'store_001',
            isAuditNegative: true,
            auditDifference: -10,
          ),
        ];

        final fifo = FifoCalculator(txs);
        expect(fifo.getRemainingQuantity('p_empty', storeId: 'store_001'), equals(0));

        final cost = fifo.calculateCostForSale(
          productId: 'p_empty',
          quantity: 2,
          saleDate: DateTime(2024, 1, 2),
          storeId: 'store_001',
          fallbackCostPrice: 15000.0,
        );

        expect(cost, equals(30000.0));
      });

      test('Zero-adjustment audit (diff = 0) does not create dummy lots or deduct stock', () {
        final txs = [
          InventoryTransaction(
            id: 'tx_imp',
            productId: 'p_zero_audit',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2024, 1, 1),
            note: 'Import 10',
            importPrice: 20000.0,
            storeId: 'store_001',
          ),
          InventoryTransaction(
            id: 'tx_zero_aud',
            productId: 'p_zero_audit',
            type: TransactionType.inventoryAudit,
            quantity: 0,
            date: DateTime(2024, 1, 2),
            note: 'Audit no change',
            importPrice: 20000.0,
            storeId: 'store_001',
            isAuditNegative: false,
            auditDifference: 0,
          ),
        ];

        final fifo = FifoCalculator(txs);
        final lots = fifo.getInventoryLots('p_zero_audit', storeId: 'store_001');

        // Only 1 lot should exist with 10 units
        expect(lots.length, equals(1));
        expect(lots[0].remainingQuantity, equals(10));
        expect(fifo.getRemainingQuantity('p_zero_audit', storeId: 'store_001'), equals(10));
      });

      test('Structured field variations: isAuditNegative and auditDifference priority and fallbacks', () {
        // Case A: isAuditNegative: true overrides positive auditDifference if misconfigured
        final txA = InventoryTransaction(
          id: 'txA',
          productId: 'p_struct_A',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: DateTime(2024, 1, 2),
          note: 'Misconfigured audit',
          importPrice: 10000.0,
          storeId: 'store_001',
          isAuditNegative: true,
          auditDifference: 5,
        );

        // Case B: isAuditNegative: null, auditDifference: -7
        final txB = InventoryTransaction(
          id: 'txB',
          productId: 'p_struct_B',
          type: TransactionType.inventoryAudit,
          quantity: 7,
          date: DateTime(2024, 1, 2),
          note: 'Audit negative with null flag',
          importPrice: 10000.0,
          storeId: 'store_001',
          isAuditNegative: null,
          auditDifference: -7,
        );

        // Case C: isAuditNegative: null, auditDifference: null, note: 'chênh lệch: -3'
        final txC = InventoryTransaction(
          id: 'txC',
          productId: 'p_struct_C',
          type: TransactionType.inventoryAudit,
          quantity: 3,
          date: DateTime(2024, 1, 2),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 7, chênh lệch: -3)',
          importPrice: 10000.0,
          storeId: 'store_001',
        );

        // Base imports
        final baseImports = [
          InventoryTransaction(
            id: 'impA',
            productId: 'p_struct_A',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2024, 1, 1),
            note: 'Import A',
            importPrice: 10000.0,
            storeId: 'store_001',
          ),
          InventoryTransaction(
            id: 'impB',
            productId: 'p_struct_B',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2024, 1, 1),
            note: 'Import B',
            importPrice: 10000.0,
            storeId: 'store_001',
          ),
          InventoryTransaction(
            id: 'impC',
            productId: 'p_struct_C',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2024, 1, 1),
            note: 'Import C',
            importPrice: 10000.0,
            storeId: 'store_001',
          ),
        ];

        final fifo = FifoCalculator([...baseImports, txA, txB, txC]);

        // txA: 10 - 5 = 5 left
        expect(fifo.getRemainingQuantity('p_struct_A', storeId: 'store_001'), equals(5));
        // txB: 10 - 7 = 3 left
        expect(fifo.getRemainingQuantity('p_struct_B', storeId: 'store_001'), equals(3));
        // txC: 10 - 3 = 7 left
        expect(fifo.getRemainingQuantity('p_struct_C', storeId: 'store_001'), equals(7));
      });

      test('InventoryTransactionModel handles various dynamic Firebase serialization formats', () {
        // Test map with string "true", int quantity, double importPrice
        final map1 = {
          'id': 'tx_fb_1',
          'productId': 'prod_fb',
          'type': 'INVENTORY_AUDIT',
          'quantity': 5,
          'date': '2024-01-01T10:00:00.000',
          'note': 'Audit note',
          'importPrice': 50000,
          'storeId': 'store_001',
          'isAuditNegative': 'true', // String from legacy DB
          'auditDifference': -5,
        };

        final model1 = InventoryTransactionModel.fromMap(map1);
        expect(model1.toTransactionType(), equals(TransactionType.inventoryAudit));
        expect(model1.isAuditNegative, isTrue);
        expect(model1.auditDifference, equals(-5));
        expect(model1.importPrice, equals(50000.0));

        // Test map with bool false, int auditDifference
        final map2 = {
          'id': 'tx_fb_2',
          'productId': 'prod_fb',
          'type': 'inventory_audit',
          'quantity': 10,
          'date': '2024-01-02T10:00:00.000',
          'note': 'Audit note 2',
          'importPrice': 60000.5,
          'storeId': 'store_002',
          'isAuditNegative': false,
          'auditDifference': 10,
        };

        final model2 = InventoryTransactionModel.fromMap(map2);
        expect(model2.toTransactionType(), equals(TransactionType.inventoryAudit));
        expect(model2.isAuditNegative, isFalse);
        expect(model2.auditDifference, equals(10));

        // Test roundtrip from Entity -> Model -> Map -> Model -> Entity
        final entity = model2.toEntity();
        expect(entity.storeId, equals('store_002'));
        expect(entity.isAuditNegative, isFalse);
        expect(entity.auditDifference, equals(10));

        final roundtripModel = InventoryTransactionModel.fromEntity(entity);
        final roundtripMap = roundtripModel.toMap();
        expect(roundtripMap['storeId'], equals('store_002'));
        expect(roundtripMap['isAuditNegative'], isFalse);
        expect(roundtripMap['auditDifference'], equals(10));
      });
    });

    // =========================================================================
    // 2. MULTI-DAY MULTI-STORE REVENUE & PROFIT CALCULATION
    // =========================================================================
    group('Multi-Day Multi-Store Revenue Calculations (RevenueRepositoryImpl)', () {
      late List<Map> products;
      late List<Map> multiStoreInventoryTxs;

      setUp(() {
        products = [
          {
            'id': 'prod_snack',
            'name': 'Bánh Snack Khoai Tây',
            'price': 20000.0,
            'costPrice': 12000.0,
            'branchStocks': {'store_001': 50, 'store_002': 50},
          },
          {
            'id': 'prod_drink',
            'name': 'Nước ngọt Có ga',
            'price': 15000.0,
            'costPrice': 8000.0,
            'branchStocks': {'store_001': 50, 'store_002': 50},
          }
        ];

        // Store 001 (Đông Thắng) lots:
        // Snack: 10 @ 10,000 on Jan 1, 10 @ 11,000 on Jan 2
        // Drink: 20 @ 7,000 on Jan 1
        // Store 002 (Thới Bình) lots:
        // Snack: 15 @ 13,000 on Jan 1
        // Drink: 10 @ 9,000 on Jan 1, 10 @ 9,500 on Jan 2
        multiStoreInventoryTxs = [
          // Store 001
          {
            'id': 'tx_s1_snk1',
            'productId': 'prod_snack',
            'type': 'import',
            'quantity': 10,
            'date': DateTime(2024, 1, 1).toIso8601String(),
            'importPrice': 10000.0,
            'storeId': 'store_001',
          },
          {
            'id': 'tx_s1_snk2',
            'productId': 'prod_snack',
            'type': 'import',
            'quantity': 10,
            'date': DateTime(2024, 1, 2).toIso8601String(),
            'importPrice': 11000.0,
            'storeId': 'store_001',
          },
          {
            'id': 'tx_s1_drk1',
            'productId': 'prod_drink',
            'type': 'import',
            'quantity': 20,
            'date': DateTime(2024, 1, 1).toIso8601String(),
            'importPrice': 7000.0,
            'storeId': 'store_001',
          },
          // Store 002
          {
            'id': 'tx_s2_snk1',
            'productId': 'prod_snack',
            'type': 'import',
            'quantity': 15,
            'date': DateTime(2024, 1, 1).toIso8601String(),
            'importPrice': 13000.0,
            'storeId': 'store_002',
          },
          {
            'id': 'tx_s2_drk1',
            'productId': 'prod_drink',
            'type': 'import',
            'quantity': 10,
            'date': DateTime(2024, 1, 1).toIso8601String(),
            'importPrice': 9000.0,
            'storeId': 'store_002',
          },
          {
            'id': 'tx_s2_drk2',
            'productId': 'prod_drink',
            'type': 'import',
            'quantity': 10,
            'date': DateTime(2024, 1, 2).toIso8601String(),
            'importPrice': 9500.0,
            'storeId': 'store_002',
          },
        ];
      });

      test('Multi-day revenue in Store 001 sequentially depletes Store 001 lots across 3 days', () {
        final repoS1 = RevenueRepositoryImpl(
          MockOrderRemoteDataSource('store_001'),
          MockInventoryRemoteDataSource(multiStoreInventoryTxs),
          MockProductRemoteDataSource(products),
        );

        final ordersS1 = [
          // Day 1 (Jan 1): Sells 6 Snack (from Lot 1 @ 10k)
          createMockOrder(
            id: 'ord_s1_d1',
            customerId: 'cust_1',
            date: DateTime(2024, 1, 1, 10, 0),
            total: 120000.0,
            items: [
              {
                'productId': 'prod_snack',
                'productName': 'Bánh Snack Khoai Tây',
                'quantity': 6,
                'price': 20000.0,
                'warrantyMonths': 0,
              }
            ],
          ),
          // Day 2 (Jan 2): Sells 8 Snack (4 from Lot 1 @ 10k + 4 from Lot 2 @ 11k)
          createMockOrder(
            id: 'ord_s1_d2',
            customerId: 'cust_1',
            date: DateTime(2024, 1, 2, 14, 0),
            total: 160000.0,
            items: [
              {
                'productId': 'prod_snack',
                'productName': 'Bánh Snack Khoai Tây',
                'quantity': 8,
                'price': 20000.0,
                'warrantyMonths': 0,
              }
            ],
          ),
          // Day 3 (Jan 3): Sells 10 Snack (6 from Lot 2 @ 11k + 4 Oversold @ fallback 12k)
          createMockOrder(
            id: 'ord_s1_d3',
            customerId: 'cust_1',
            date: DateTime(2024, 1, 3, 16, 0),
            total: 200000.0,
            items: [
              {
                'productId': 'prod_snack',
                'productName': 'Bánh Snack Khoai Tây',
                'quantity': 10,
                'price': 20000.0,
                'warrantyMonths': 0,
              }
            ],
          ),
        ];

        final summary = repoS1.calculateRevenueSummary(
          orders: ordersS1,
          inventoryTransactions: multiStoreInventoryTxs,
          products: products,
          startDate: DateTime(2024, 1, 1),
          endDate: DateTime(2024, 1, 3),
        );

        // Day 1 COGS: 6 * 10k = 60,000 (Profit = 120k - 60k = 60,000)
        // Day 2 COGS: 4 * 10k + 4 * 11k = 40k + 44k = 84,000 (Profit = 160k - 84k = 76,000)
        // Day 3 COGS: 6 * 11k + 4 * 12k (fallback) = 66k + 48k = 114,000 (Profit = 200k - 114k = 86,000)
        // Total Revenue: 480,000
        // Total Cost: 60k + 84k + 114k = 258,000
        // Total Profit: 480k - 258k = 222,000

        expect(summary.totalRevenue, equals(480000.0));
        expect(summary.totalCost, equals(258000.0));
        expect(summary.totalProfit, equals(222000.0));
        expect(summary.totalItemsSold, equals(24));
        expect(summary.dailyReports.length, equals(3));

        expect(summary.dailyReports[0].totalCost, equals(60000.0));
        expect(summary.dailyReports[0].profit, equals(60000.0));

        expect(summary.dailyReports[1].totalCost, equals(84000.0));
        expect(summary.dailyReports[1].profit, equals(76000.0));

        expect(summary.dailyReports[2].totalCost, equals(114000.0));
        expect(summary.dailyReports[2].profit, equals(86000.0));
      });

      test('Multi-store isolation: Store 002 revenue calculations do not consume Store 001 lots', () {
        final repoS2 = RevenueRepositoryImpl(
          MockOrderRemoteDataSource('store_002'),
          MockInventoryRemoteDataSource(multiStoreInventoryTxs),
          MockProductRemoteDataSource(products),
        );

        // Store 002 order: Sells 10 Snack on Jan 1
        // Store 002 Lot 1 is 15 @ 13,000 (NOT Store 001's 10,000!)
        final ordersS2 = [
          createMockOrder(
            id: 'ord_s2_d1',
            customerId: 'cust_2',
            date: DateTime(2024, 1, 1, 11, 0),
            total: 200000.0,
            items: [
              {
                'productId': 'prod_snack',
                'productName': 'Bánh Snack Khoai Tây',
                'quantity': 10,
                'price': 20000.0,
                'warrantyMonths': 0,
              }
            ],
          )
        ];

        final summaryS2 = repoS2.calculateRevenueSummary(
          orders: ordersS2,
          inventoryTransactions: multiStoreInventoryTxs,
          products: products,
          startDate: DateTime(2024, 1, 1),
          endDate: DateTime(2024, 1, 1),
        );

        // COGS at Store 002: 10 * 13,000 = 130,000
        // Profit at Store 002: 200,000 - 130,000 = 70,000
        expect(summaryS2.totalRevenue, equals(200000.0));
        expect(summaryS2.totalCost, equals(130000.0));
        expect(summaryS2.totalProfit, equals(70000.0));
      });

      test('mergeRevenueSummaries accurately merges multi-store multi-day summaries without data corruption', () {
        final repoS1 = RevenueRepositoryImpl(
          MockOrderRemoteDataSource('store_001'),
          MockInventoryRemoteDataSource(multiStoreInventoryTxs),
          MockProductRemoteDataSource(products),
        );

        final repoS2 = RevenueRepositoryImpl(
          MockOrderRemoteDataSource('store_002'),
          MockInventoryRemoteDataSource(multiStoreInventoryTxs),
          MockProductRemoteDataSource(products),
        );

        // Orders Store 001 on Jan 1: Sells 5 Drink @ 15k -> Revenue = 75k, Cost = 5 * 7k = 35k
        final ordersS1 = [
          createMockOrder(
            id: 'ord_s1_drink',
            customerId: 'cust_1',
            date: DateTime(2024, 1, 1, 9, 0),
            total: 75000.0,
            items: [
              {
                'productId': 'prod_drink',
                'productName': 'Nước ngọt Có ga',
                'quantity': 5,
                'price': 15000.0,
                'warrantyMonths': 0,
              }
            ],
          )
        ];

        // Orders Store 002 on Jan 1: Sells 5 Drink @ 15k -> Revenue = 75k, Cost = 5 * 9k = 45k
        final ordersS2 = [
          createMockOrder(
            id: 'ord_s2_drink',
            customerId: 'cust_2',
            date: DateTime(2024, 1, 1, 10, 0),
            total: 75000.0,
            items: [
              {
                'productId': 'prod_drink',
                'productName': 'Nước ngọt Có ga',
                'quantity': 5,
                'price': 15000.0,
                'warrantyMonths': 0,
              }
            ],
          )
        ];

        final summaryS1 = repoS1.calculateRevenueSummary(
          orders: ordersS1,
          inventoryTransactions: multiStoreInventoryTxs,
          products: products,
          startDate: DateTime(2024, 1, 1),
          endDate: DateTime(2024, 1, 1),
        );

        final summaryS2 = repoS2.calculateRevenueSummary(
          orders: ordersS2,
          inventoryTransactions: multiStoreInventoryTxs,
          products: products,
          startDate: DateTime(2024, 1, 1),
          endDate: DateTime(2024, 1, 1),
        );

        final merged = mergeRevenueSummaries(
          [summaryS1, summaryS2],
          DateTime(2024, 1, 1),
          DateTime(2024, 1, 1),
        );

        // Combined:
        // Total Revenue: 75k + 75k = 150,000
        // Total Cost: 35k + 45k = 80,000
        // Total Profit: 150k - 80k = 70,000
        // Total Items Sold: 10
        expect(merged.totalRevenue, equals(150000.0));
        expect(merged.totalCost, equals(80000.0));
        expect(merged.totalProfit, equals(70000.0));
        expect(merged.totalItemsSold, equals(10));
        expect(merged.dailyReports.length, equals(1));
        expect(merged.dailyReports[0].totalRevenue, equals(150000.0));
        expect(merged.dailyReports[0].totalCost, equals(80000.0));
        expect(merged.dailyReports[0].storeRevenues['store_001'], equals(75000.0));
        expect(merged.dailyReports[0].storeRevenues['store_002'], equals(75000.0));
      });

      test('Multi-day date range with gaps/empty days produces intact dailyReports for all calendar days', () {
        final repoS1 = RevenueRepositoryImpl(
          MockOrderRemoteDataSource('store_001'),
          MockInventoryRemoteDataSource(multiStoreInventoryTxs),
          MockProductRemoteDataSource(products),
        );

        // Only Day 1 and Day 3 have orders (Day 2 is empty)
        final ordersWithGap = [
          createMockOrder(
            id: 'ord_d1',
            customerId: 'cust_1',
            date: DateTime(2024, 1, 1, 10, 0),
            total: 20000.0,
            items: [
              {
                'productId': 'prod_snack',
                'productName': 'Bánh Snack Khoai Tây',
                'quantity': 1,
                'price': 20000.0,
                'warrantyMonths': 0,
              }
            ],
          ),
          createMockOrder(
            id: 'ord_d3',
            customerId: 'cust_1',
            date: DateTime(2024, 1, 3, 10, 0),
            total: 20000.0,
            items: [
              {
                'productId': 'prod_snack',
                'productName': 'Bánh Snack Khoai Tây',
                'quantity': 1,
                'price': 20000.0,
                'warrantyMonths': 0,
              }
            ],
          ),
        ];

        final summary = repoS1.calculateRevenueSummary(
          orders: ordersWithGap,
          inventoryTransactions: multiStoreInventoryTxs,
          products: products,
          startDate: DateTime(2024, 1, 1),
          endDate: DateTime(2024, 1, 3),
        );

        expect(summary.dailyReports.length, equals(3));
        // Day 1: 20k revenue, 10k cost
        expect(summary.dailyReports[0].totalRevenue, equals(20000.0));
        expect(summary.dailyReports[0].totalCost, equals(10000.0));
        // Day 2: 0 revenue, 0 cost
        expect(summary.dailyReports[1].totalRevenue, equals(0.0));
        expect(summary.dailyReports[1].totalCost, equals(0.0));
        expect(summary.dailyReports[1].profit, equals(0.0));
        expect(summary.dailyReports[1].totalOrders, equals(0));
        // Day 3: 20k revenue, 10k cost (2nd item from Lot 1)
        expect(summary.dailyReports[2].totalRevenue, equals(20000.0));
        expect(summary.dailyReports[2].totalCost, equals(10000.0));
      });
    });
  });
}
