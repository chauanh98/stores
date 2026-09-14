import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/data/datasources/firebase/inventory_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/product_remote_data_source.dart';
import 'package:stores/data/models/inventory_transaction_model.dart';
import 'package:stores/data/repositories/revenue_repository_impl.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';

// Fake Data Sources for testing
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
  group('FifoCalculator Adversarial Stress Tests', () {
    // =========================================================================
    // SCENARIO 1: Imports -> Positive Audit -> Sales (Exports)
    // =========================================================================
    test(
        'Scenario 1: Imports -> Positive Audit -> Sequential Sales draw FIFO lots then audit lot',
        () {
      // Lot 1: 10 @ 10,000 (Jan 1)
      // Lot 2: 10 @ 12,000 (Jan 2)
      // Lot 3 (Audit +): 10 @ 15,000 (Jan 3)
      final txs = [
        InventoryTransaction(
          id: 'imp_1',
          productId: 'prod_sc1',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Nhập lô 1',
          importPrice: 10000.0,
        ),
        InventoryTransaction(
          id: 'imp_2',
          productId: 'prod_sc1',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 2),
          note: 'Nhập lô 2',
          importPrice: 12000.0,
        ),
        InventoryTransaction(
          id: 'audit_pos',
          productId: 'prod_sc1',
          type: TransactionType.inventoryAudit,
          quantity: 10,
          date: DateTime(2024, 1, 3),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 20 -> Tồn mới: 30, chênh lệch: +10)',
          importPrice: 15000.0,
        ),
      ];

      final fifo = FifoCalculator(txs);
      final lots = fifo.getInventoryLots('prod_sc1');
      expect(lots.length, equals(3));
      expect(lots[0].remainingQuantity, equals(10));
      expect(lots[0].importPrice, equals(10000.0));
      expect(lots[1].remainingQuantity, equals(10));
      expect(lots[1].importPrice, equals(12000.0));
      expect(lots[2].remainingQuantity, equals(10));
      expect(lots[2].importPrice, equals(15000.0));

      // Sale 1: 8 items -> draws 8 from Lot 1 @ 10k = 80k
      final cost1 = fifo.calculateCostForSale(
        productId: 'prod_sc1',
        quantity: 8,
        saleDate: DateTime(2024, 1, 4),
      );
      expect(cost1, equals(80000.0));
      expect(lots[0].remainingQuantity, equals(2));
      expect(lots[1].remainingQuantity, equals(10));
      expect(lots[2].remainingQuantity, equals(10));

      // Sale 2: 7 items -> draws 2 from Lot 1 @ 10k (20k) + 5 from Lot 2 @ 12k (60k) = 80k
      final cost2 = fifo.calculateCostForSale(
        productId: 'prod_sc1',
        quantity: 7,
        saleDate: DateTime(2024, 1, 5),
      );
      expect(cost2, equals(80000.0));
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(5));
      expect(lots[2].remainingQuantity, equals(10));

      // Sale 3: 10 items -> draws 5 from Lot 2 @ 12k (60k) + 5 from Lot 3 (Audit) @ 15k (75k) = 135k
      final cost3 = fifo.calculateCostForSale(
        productId: 'prod_sc1',
        quantity: 10,
        saleDate: DateTime(2024, 1, 6),
      );
      expect(cost3, equals(135000.0));
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(0));
      expect(lots[2].remainingQuantity, equals(5));

      // Sale 4: 5 items -> draws remaining 5 from Lot 3 (Audit) @ 15k = 75k
      final cost4 = fifo.calculateCostForSale(
        productId: 'prod_sc1',
        quantity: 5,
        saleDate: DateTime(2024, 1, 7),
      );
      expect(cost4, equals(75000.0));
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(0));
      expect(lots[2].remainingQuantity, equals(0));

      // Total Cost across all sales: 80k + 80k + 135k + 75k = 370k
      // (10 * 10k + 10 * 12k + 10 * 15k = 100k + 120k + 150k = 370k)
      expect(cost1 + cost2 + cost3 + cost4, equals(370000.0));
    });

    // =========================================================================
    // SCENARIO 2: Imports -> Negative Audit (reducing older lots) -> Sales
    // =========================================================================
    test(
        'Scenario 2.1: Negative audit strictly reduces oldest lot first and preserves newer lot cost basis',
        () {
      // Lot 1: 10 @ 10,000 (Jan 1)
      // Lot 2: 10 @ 20,000 (Jan 2)
      // Audit (-): -6 items (Jan 3) -> Lot 1 reduced from 10 to 4. Lot 2 untouched (10).
      final txs = [
        InventoryTransaction(
          id: 'imp_1',
          productId: 'prod_sc2_1',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Nhập lô 1',
          importPrice: 10000.0,
        ),
        InventoryTransaction(
          id: 'imp_2',
          productId: 'prod_sc2_1',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 2),
          note: 'Nhập lô 2',
          importPrice: 20000.0,
        ),
        InventoryTransaction(
          id: 'audit_neg',
          productId: 'prod_sc2_1',
          type: TransactionType.inventoryAudit,
          quantity: 6,
          date: DateTime(2024, 1, 3),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 20 -> Tồn mới: 14, chênh lệch: -6)',
          importPrice: 10000.0,
        ),
      ];

      final fifo = FifoCalculator(txs);
      final lots = fifo.getInventoryLots('prod_sc2_1');
      expect(lots.length, equals(2));
      expect(lots[0].remainingQuantity, equals(4)); // 10 - 6 = 4
      expect(lots[0].importPrice, equals(10000.0));
      expect(lots[1].remainingQuantity, equals(10)); // untouched
      expect(lots[1].importPrice, equals(20000.0));

      // Sale 1: 6 items -> draws 4 from Lot 1 @ 10k (40k) + 2 from Lot 2 @ 20k (40k) = 80k
      final cost1 = fifo.calculateCostForSale(
        productId: 'prod_sc2_1',
        quantity: 6,
        saleDate: DateTime(2024, 1, 4),
      );
      expect(cost1, equals(80000.0));
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(8));

      // Sale 2: 8 items -> draws 8 from Lot 2 @ 20k = 160k
      final cost2 = fifo.calculateCostForSale(
        productId: 'prod_sc2_1',
        quantity: 8,
        saleDate: DateTime(2024, 1, 5),
      );
      expect(cost2, equals(160000.0));
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(0));

      // Total sold: 14 items, Total COGS: 80k + 160k = 240k (4*10k + 10*20k)
      expect(cost1 + cost2, equals(240000.0));
    });

    test(
        'Scenario 2.2: Negative audit spans across multiple lots (depletes Lot 1 and partial Lot 2)',
        () {
      // Lot 1: 5 @ 10,000 (Jan 1)
      // Lot 2: 5 @ 15,000 (Jan 2)
      // Lot 3: 10 @ 20,000 (Jan 3)
      // Audit (-): -12 items (Jan 4)
      // -> Lot 1 (5) completely drained (0)
      // -> Lot 2 (5) completely drained (0)
      // -> Lot 3 (10) reduced by 2 to 8
      final txs = [
        InventoryTransaction(
          id: 'imp_1',
          productId: 'prod_sc2_2',
          type: TransactionType.import,
          quantity: 5,
          date: DateTime(2024, 1, 1),
          note: 'Nhập lô 1',
          importPrice: 10000.0,
        ),
        InventoryTransaction(
          id: 'imp_2',
          productId: 'prod_sc2_2',
          type: TransactionType.import,
          quantity: 5,
          date: DateTime(2024, 1, 2),
          note: 'Nhập lô 2',
          importPrice: 15000.0,
        ),
        InventoryTransaction(
          id: 'imp_3',
          productId: 'prod_sc2_2',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 3),
          note: 'Nhập lô 3',
          importPrice: 20000.0,
        ),
        InventoryTransaction(
          id: 'audit_neg',
          productId: 'prod_sc2_2',
          type: TransactionType.inventoryAudit,
          quantity: 12,
          date: DateTime(2024, 1, 4),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 20 -> Tồn mới: 8, chênh lệch: -12)',
          importPrice: 15000.0,
        ),
      ];

      final fifo = FifoCalculator(txs);
      final lots = fifo.getInventoryLots('prod_sc2_2');
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(0));
      expect(lots[2].remainingQuantity, equals(8));
      expect(lots[2].importPrice, equals(20000.0));

      // Sale 5 items from remaining Lot 3: 5 * 20k = 100k
      final cost = fifo.calculateCostForSale(
        productId: 'prod_sc2_2',
        quantity: 5,
        saleDate: DateTime(2024, 1, 5),
      );
      expect(cost, equals(100000.0));
      expect(lots[2].remainingQuantity, equals(3));
    });

    // =========================================================================
    // SCENARIO 3: Multiple consecutive audits (+10, -5, +20, -15) with varying prices
    // =========================================================================
    test(
        'Scenario 3: Multi-audit sequence (+10, -5, +20, -15) calculates exact stock balance, remaining lot quantities, and profit',
        () {
      // Timeline:
      // 1. Jan 1: Import 10 @ 10,000 -> Lot 1: 10 @ 10k
      // 2. Jan 2: Audit +10 @ 12,000 -> Lot 2: 10 @ 12k (Total = 20)
      // 3. Jan 3: Audit -5 -> Lot 1 reduced to 5 @ 10k, Lot 2: 10 @ 12k (Total = 15)
      // 4. Jan 4: Audit +20 @ 14,000 -> Lot 3: 20 @ 14k (Total = 35)
      // 5. Jan 5: Audit -15 -> Lot 1: 0 (reduced 5), Lot 2: 0 (reduced 10), Lot 3: 20 @ 14k (Total = 20)
      final txs = [
        InventoryTransaction(
          id: 'imp_1',
          productId: 'prod_sc3',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Nhập lô 1',
          importPrice: 10000.0,
        ),
        InventoryTransaction(
          id: 'audit_1',
          productId: 'prod_sc3',
          type: TransactionType.inventoryAudit,
          quantity: 10,
          date: DateTime(2024, 1, 2),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 20, chênh lệch: +10)',
          importPrice: 12000.0,
        ),
        InventoryTransaction(
          id: 'audit_2',
          productId: 'prod_sc3',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: DateTime(2024, 1, 3),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 20 -> Tồn mới: 15, chênh lệch: -5)',
          importPrice: 10000.0,
        ),
        InventoryTransaction(
          id: 'audit_3',
          productId: 'prod_sc3',
          type: TransactionType.inventoryAudit,
          quantity: 20,
          date: DateTime(2024, 1, 4),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 15 -> Tồn mới: 35, chênh lệch: +20)',
          importPrice: 14000.0,
        ),
        InventoryTransaction(
          id: 'audit_4',
          productId: 'prod_sc3',
          type: TransactionType.inventoryAudit,
          quantity: 15,
          date: DateTime(2024, 1, 5),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 35 -> Tồn mới: 20, chênh lệch: -15)',
          importPrice: 12000.0,
        ),
      ];

      final fifo = FifoCalculator(txs);
      final lots = fifo.getInventoryLots('prod_sc3');
      expect(lots.length, equals(3));
      expect(lots[0].remainingQuantity, equals(0)); // Lot 1
      expect(lots[1].remainingQuantity, equals(0)); // Lot 2
      expect(lots[2].remainingQuantity, equals(20)); // Lot 3 (Audit 3)
      expect(lots[2].importPrice, equals(14000.0));

      final totalRemaining =
          lots.fold<int>(0, (sum, l) => sum + l.remainingQuantity);
      expect(totalRemaining, equals(20));

      // Sale 1 (Jan 6): Sell 12 items @ selling price 25,000
      final costSale1 = fifo.calculateCostForSale(
        productId: 'prod_sc3',
        quantity: 12,
        saleDate: DateTime(2024, 1, 6),
      );
      // Cost = 12 * 14,000 = 168,000
      expect(costSale1, equals(168000.0));
      expect(lots[2].remainingQuantity, equals(8));

      const revenueSale1 = 12 * 25000.0; // 300,000
      final profitSale1 = revenueSale1 - costSale1; // 132,000
      final marginSale1 =
          FifoCalculator.calculateProfitMargin(revenueSale1, costSale1);
      expect(profitSale1, equals(132000.0));
      expect(marginSale1, equals(44.0)); // (300k - 168k)/300k * 100 = 44%

      // Sale 2 (Jan 7): Sell 10 items (8 from Lot 3 @ 14k + 2 fallback @ 16k) @ selling price 25,000
      final costSale2 = fifo.calculateCostForSale(
        productId: 'prod_sc3',
        quantity: 10,
        saleDate: DateTime(2024, 1, 7),
        fallbackCostPrice: 16000.0,
      );
      // Cost = 8 * 14k (112k) + 2 * 16k (32k) = 144k
      expect(costSale2, equals(144000.0));
      expect(lots[2].remainingQuantity, equals(0));

      const revenueSale2 = 10 * 25000.0; // 250,000
      final profitSale2 = revenueSale2 - costSale2; // 106,000
      final marginSale2 =
          FifoCalculator.calculateProfitMargin(revenueSale2, costSale2);
      expect(profitSale2, equals(106000.0));
      expect(marginSale2, equals((106000.0 / 250000.0) * 100)); // 42.4%

      const totalRevenue = revenueSale1 + revenueSale2; // 550,000
      final totalCost = costSale1 + costSale2; // 312,000
      final totalProfit = totalRevenue - totalCost; // 238,000
      final totalMargin =
          FifoCalculator.calculateProfitMargin(totalRevenue, totalCost);
      expect(totalProfit, equals(238000.0));
      expect(totalMargin, closeTo(43.2727, 0.001));
    });

    // =========================================================================
    // SCENARIO 4: Boundary values / Zero quantity / Empty lists / Format robustness
    // =========================================================================
    test('Scenario 4.1: Zero and negative sale quantities return 0 cost', () {
      final fifo = FifoCalculator([
        InventoryTransaction(
          id: 'imp_1',
          productId: 'prod_boundary',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Nhập lô',
          importPrice: 50000.0,
        ),
      ]);

      expect(
        fifo.calculateCostForSale(
          productId: 'prod_boundary',
          quantity: 0,
          saleDate: DateTime(2024, 1, 2),
        ),
        equals(0.0),
      );

      expect(
        fifo.calculateCostForSale(
          productId: 'prod_boundary',
          quantity: -5,
          saleDate: DateTime(2024, 1, 2),
        ),
        equals(0.0),
      );

      // Remaining stock should remain intact
      expect(fifo.getInventoryLots('prod_boundary')[0].remainingQuantity,
          equals(10));
    });

    test('Scenario 4.2: Empty transaction list with and without fallback cost',
        () {
      final fifoEmpty = FifoCalculator([]);

      // With fallback
      final costWithFallback = fifoEmpty.calculateCostForSale(
        productId: 'prod_unknown',
        quantity: 5,
        saleDate: DateTime(2024, 1, 1),
        fallbackCostPrice: 35000.0,
      );
      expect(costWithFallback, equals(175000.0)); // 5 * 35k

      // Without fallback
      final costWithoutFallback = fifoEmpty.calculateCostForSale(
        productId: 'prod_unknown',
        quantity: 5,
        saleDate: DateTime(2024, 1, 1),
      );
      expect(costWithoutFallback, equals(0.0));
    });

    test(
        'Scenario 4.3: Negative audit exceeding total current stock reduces lots to 0 gracefully',
        () {
      final txs = [
        InventoryTransaction(
          id: 'imp_1',
          productId: 'prod_excess_audit',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Nhập lô 1',
          importPrice: 20000.0,
        ),
        InventoryTransaction(
          id: 'audit_excess',
          productId: 'prod_excess_audit',
          type: TransactionType.inventoryAudit,
          quantity: 30, // Exceeds 10
          date: DateTime(2024, 1, 2),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 0, chênh lệch: -30)',
          importPrice: 20000.0,
        ),
      ];

      final fifo = FifoCalculator(txs);
      final lots = fifo.getInventoryLots('prod_excess_audit');
      expect(lots[0].remainingQuantity, equals(0));

      // Selling when stock is 0 uses fallback or last lot price
      final cost = fifo.calculateCostForSale(
        productId: 'prod_excess_audit',
        quantity: 5,
        saleDate: DateTime(2024, 1, 3),
        fallbackCostPrice: 25000.0,
      );
      expect(cost, equals(125000.0)); // 5 * 25k fallback
    });

    test('Scenario 4.4: Robust audit note parsing across diverse formats', () {
      final txs = [
        // Standard positive
        InventoryTransaction(
          id: 'tx_p1',
          productId: 'p_notes',
          type: TransactionType.inventoryAudit,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 0 -> Tồn mới: 10, chênh lệch: +10)',
          importPrice: 10000.0,
        ),
        // Standard negative
        InventoryTransaction(
          id: 'tx_n1',
          productId: 'p_notes',
          type: TransactionType.inventoryAudit,
          quantity: 3,
          date: DateTime(2024, 1, 2),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 7, chênh lệch: -3)',
          importPrice: 10000.0,
        ),
        // Freeform negative with minus sign
        InventoryTransaction(
          id: 'tx_n2',
          productId: 'p_notes',
          type: TransactionType.inventoryAudit,
          quantity: 2,
          date: DateTime(2024, 1, 3),
          note: 'Giảm kho do hỏng -2 cái',
          importPrice: 10000.0,
        ),
        // Freeform positive
        InventoryTransaction(
          id: 'tx_p2',
          productId: 'p_notes',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: DateTime(2024, 1, 4),
          note: 'Tìm thấy thêm hàng tồn +5 cái',
          importPrice: 12000.0,
        ),
      ];

      final fifo = FifoCalculator(txs);
      final lots = fifo.getInventoryLots('p_notes');
      // Lot 1 (tx_p1): started 10, reduced 3 (tx_n1) -> 7, reduced 2 (tx_n2) -> 5
      // Lot 2 (tx_p2): 5 @ 12k
      expect(lots.length, equals(2));
      expect(lots[0].remainingQuantity, equals(5));
      expect(lots[0].importPrice, equals(10000.0));
      expect(lots[1].remainingQuantity, equals(5));
      expect(lots[1].importPrice, equals(12000.0));

      final totalStock =
          lots.fold<int>(0, (sum, l) => sum + l.remainingQuantity);
      expect(totalStock, equals(10));
    });

    test(
        'Scenario 4.5: Unordered transactions are sorted chronologically by date automatically',
        () {
      // Pass transactions out of chronological order
      final txs = [
        InventoryTransaction(
          id: 'tx_3',
          productId: 'prod_unordered',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: DateTime(2024, 1, 3), // Date 3
          note: 'Cân bằng kho (chênh lệch: +5)',
          importPrice: 30000.0,
        ),
        InventoryTransaction(
          id: 'tx_1',
          productId: 'prod_unordered',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1), // Date 1
          note: 'Nhập lô 1',
          importPrice: 10000.0,
        ),
        InventoryTransaction(
          id: 'tx_2',
          productId: 'prod_unordered',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 2), // Date 2
          note: 'Nhập lô 2',
          importPrice: 20000.0,
        ),
      ];

      final fifo = FifoCalculator(txs);
      final lots = fifo.getInventoryLots('prod_unordered');

      expect(lots.length, equals(3));
      expect(lots[0].transactionId, equals('tx_1'));
      expect(lots[0].importPrice, equals(10000.0));
      expect(lots[1].transactionId, equals('tx_2'));
      expect(lots[1].importPrice, equals(20000.0));
      expect(lots[2].transactionId, equals('tx_3'));
      expect(lots[2].importPrice, equals(30000.0));

      // Selling 15 items draws 10 from tx_1 (100k) + 5 from tx_2 (100k) = 200k
      final cost = fifo.calculateCostForSale(
        productId: 'prod_unordered',
        quantity: 15,
        saleDate: DateTime(2024, 1, 4),
      );
      expect(cost, equals(200000.0));
    });

    // =========================================================================
    // SCENARIO 5: Multi-product State Isolation Stress Test
    // =========================================================================
    test(
        'Scenario 5: Multi-product isolation ensures independent lot tracking and zero cross-talk',
        () {
      final txs = [
        // Product A: 10 @ 10k, Audit +5 @ 12k
        InventoryTransaction(
          id: 'tx_a1',
          productId: 'prod_A',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Nhập A',
          importPrice: 10000.0,
        ),
        InventoryTransaction(
          id: 'tx_a2',
          productId: 'prod_A',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: DateTime(2024, 1, 2),
          note: 'Audit A +5',
          importPrice: 12000.0,
        ),
        // Product B: 20 @ 50k, Audit -5
        InventoryTransaction(
          id: 'tx_b1',
          productId: 'prod_B',
          type: TransactionType.import,
          quantity: 20,
          date: DateTime(2024, 1, 1),
          note: 'Nhập B',
          importPrice: 50000.0,
        ),
        InventoryTransaction(
          id: 'tx_b2',
          productId: 'prod_B',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: DateTime(2024, 1, 2),
          note: 'Audit B -5 (chênh lệch: -5)',
          importPrice: 50000.0,
        ),
      ];

      final fifo = FifoCalculator(txs);

      // Sell from Product A
      final costA = fifo.calculateCostForSale(
        productId: 'prod_A',
        quantity: 12,
        saleDate: DateTime(2024, 1, 3),
      );
      // Cost A = 10 * 10k + 2 * 12k = 124k
      expect(costA, equals(124000.0));
      expect(fifo.getInventoryLots('prod_A')[0].remainingQuantity, equals(0));
      expect(fifo.getInventoryLots('prod_A')[1].remainingQuantity, equals(3));

      // Verify Product B lots remain completely untouched by Product A operations
      final lotsB = fifo.getInventoryLots('prod_B');
      expect(lotsB.length, equals(1));
      expect(lotsB[0].remainingQuantity, equals(15)); // 20 - 5 = 15

      // Sell from Product B
      final costB = fifo.calculateCostForSale(
        productId: 'prod_B',
        quantity: 5,
        saleDate: DateTime(2024, 1, 3),
      );
      // Cost B = 5 * 50k = 250k
      expect(costB, equals(250000.0));
      expect(lotsB[0].remainingQuantity, equals(10));
    });

    // =========================================================================
    // SCENARIO 6: Full RevenueRepositoryImpl End-to-End Multi-Day Stress Test
    // =========================================================================
    test(
        'Scenario 6: RevenueRepositoryImpl with positive & negative audits maintains accurate COGS, Revenue, and Profit across 3 consecutive days',
        () {
      final products = [
        {
          'id': 'p1',
          'name': 'Áo thun thể thao DryFit',
          'code': 'AT01',
          'price': 200000.0,
          'costPrice': 100000.0,
          'branchStocks': {'branch_1': 30},
        },
      ];

      final inventoryTransactions = [
        // Jan 1: Import 10 @ 90,000
        {
          'id': 'tx_1',
          'productId': 'p1',
          'type': 'import',
          'quantity': 10,
          'date': DateTime(2024, 1, 1).toIso8601String(),
          'importPrice': 90000.0,
        },
        // Jan 2: Positive Audit +10 @ 110,000
        {
          'id': 'tx_2',
          'productId': 'p1',
          'type': 'INVENTORY_AUDIT',
          'quantity': 10,
          'date': DateTime(2024, 1, 2).toIso8601String(),
          'note': 'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 20, chênh lệch: +10)',
          'importPrice': 110000.0,
        },
        // Jan 4: Negative Audit -4 (reducing Lot 1 from remaining)
        {
          'id': 'tx_3',
          'productId': 'p1',
          'type': 'INVENTORY_AUDIT',
          'quantity': 4,
          'date': DateTime(2024, 1, 4).toIso8601String(),
          'note': 'Cân bằng kho trực tiếp (Tồn cũ: 15 -> Tồn mới: 11, chênh lệch: -4)',
          'importPrice': 90000.0,
        },
      ];

      final orders = [
        // Day 1 (Jan 3): Sell 5 items @ 200,000 -> 5 * 90k = 450k cost. Lot 1 remaining: 5.
        {
          'id': 'ord_1',
          'customerId': 'c1',
          'createdAt': DateTime(2024, 1, 3, 10, 0).toIso8601String(),
          'total': 1000000.0, // 5 * 200k
          'status': 'completed',
          'items': [
            {
              'productId': 'p1',
              'productName': 'Áo thun thể thao DryFit',
              'quantity': 5,
              'price': 200000.0,
              'warrantyMonths': 0,
              'purchaseDate': DateTime(2024, 1, 3, 10, 0).toIso8601String(),
            }
          ],
        },
        // Day 2 (Jan 5): (After Audit -4 on Jan 4, Lot 1 has 5 - 4 = 1 left).
        // Sell 6 items @ 200,000 -> 1 from Lot 1 @ 90k (90k) + 5 from Lot 2 @ 110k (550k) = 640k cost.
        {
          'id': 'ord_2',
          'customerId': 'c2',
          'createdAt': DateTime(2024, 1, 5, 14, 0).toIso8601String(),
          'total': 1200000.0, // 6 * 200k
          'status': 'completed',
          'items': [
            {
              'productId': 'p1',
              'productName': 'Áo thun thể thao DryFit',
              'quantity': 6,
              'price': 200000.0,
              'warrantyMonths': 0,
              'purchaseDate': DateTime(2024, 1, 5, 14, 0).toIso8601String(),
            }
          ],
        },
        // Day 3 (Jan 6): Sell 5 items @ 200,000 -> 5 from Lot 2 @ 110k = 550k cost.
        {
          'id': 'ord_3',
          'customerId': 'c3',
          'createdAt': DateTime(2024, 1, 6, 16, 0).toIso8601String(),
          'total': 1000000.0, // 5 * 200k
          'status': 'completed',
          'items': [
            {
              'productId': 'p1',
              'productName': 'Áo thun thể thao DryFit',
              'quantity': 5,
              'price': 200000.0,
              'warrantyMonths': 0,
              'purchaseDate': DateTime(2024, 1, 6, 16, 0).toIso8601String(),
            }
          ],
        },
      ];

      final repo = RevenueRepositoryImpl(
        FakeOrderRemoteDataSource(),
        FakeInventoryRemoteDataSource(inventoryTransactions),
        FakeProductRemoteDataSource(products),
      );

      final summary = repo.calculateRevenueSummary(
        orders: orders,
        inventoryTransactions: inventoryTransactions,
        products: products,
        startDate: DateTime(2024, 1, 3),
        endDate: DateTime(2024, 1, 6),
      );

      // Total Revenue = 1,000,000 + 1,200,000 + 1,000,000 = 3,200,000
      // Total Cost = 450,000 (Day 1) + 640,000 (Day 2) + 550,000 (Day 3) = 1,640,000
      // Total Profit = 3,200,000 - 1,640,000 = 1,560,000
      expect(summary.totalRevenue, equals(3200000.0));
      expect(summary.totalCost, equals(1640000.0));
      expect(summary.totalProfit, equals(1560000.0));
      expect(summary.totalOrders, equals(3));
      expect(summary.totalItemsSold, equals(16));

      // Verify daily reports (Jan 3, Jan 4 [empty], Jan 5, Jan 6)
      expect(summary.dailyReports.length, equals(4));
      // Jan 3
      expect(summary.dailyReports[0].totalRevenue, equals(1000000.0));
      expect(summary.dailyReports[0].totalCost, equals(450000.0));
      expect(summary.dailyReports[0].profit, equals(550000.0));

      // Jan 4 (no orders, 0 revenue)
      expect(summary.dailyReports[1].totalRevenue, equals(0.0));
      expect(summary.dailyReports[1].totalCost, equals(0.0));
      expect(summary.dailyReports[1].profit, equals(0.0));

      // Jan 5
      expect(summary.dailyReports[2].totalRevenue, equals(1200000.0));
      expect(summary.dailyReports[2].totalCost, equals(640000.0));
      expect(summary.dailyReports[2].profit, equals(560000.0));

      // Jan 6
      expect(summary.dailyReports[3].totalRevenue, equals(1000000.0));
      expect(summary.dailyReports[3].totalCost, equals(550000.0));
      expect(summary.dailyReports[3].profit, equals(450000.0));
    });

    // =========================================================================
    // SCENARIO 7: InventoryTransactionModel Type Serialization & Deserialization
    // =========================================================================
    test(
        'Scenario 7: InventoryTransactionModel roundtrip serialization with legacy strings',
        () {
      // Test parsing of all variations
      expect(
        InventoryTransactionModel.parseTransactionType('INVENTORY_AUDIT'),
        equals(TransactionType.inventoryAudit),
      );
      expect(
        InventoryTransactionModel.parseTransactionType('inventory_audit'),
        equals(TransactionType.inventoryAudit),
      );
      expect(
        InventoryTransactionModel.parseTransactionType('inventoryAudit'),
        equals(TransactionType.inventoryAudit),
      );
      expect(
        InventoryTransactionModel.parseTransactionType('audit'),
        equals(TransactionType.inventoryAudit),
      );
      expect(
        InventoryTransactionModel.parseTransactionType('import'),
        equals(TransactionType.import),
      );
      expect(
        InventoryTransactionModel.parseTransactionType('export'),
        equals(TransactionType.export),
      );

      // Test typeToString
      expect(
        InventoryTransactionModel.typeToString(TransactionType.inventoryAudit),
        equals('INVENTORY_AUDIT'),
      );
      expect(
        InventoryTransactionModel.typeToString(TransactionType.import),
        equals('import'),
      );
      expect(
        InventoryTransactionModel.typeToString(TransactionType.export),
        equals('export'),
      );

      // Model Map serialization
      final now = DateTime(2024, 1, 1, 10, 30);
      final model = InventoryTransactionModel(
        id: 'tx_test_1',
        productId: 'prod_test',
        type: 'INVENTORY_AUDIT',
        quantity: 15,
        date: now,
        note: 'Cân bằng kho trực tiếp',
        importPrice: 75000.0,
        createdBy: 'admin_user',
        createdByName: 'Administrator',
      );

      final map = model.toMap();
      expect(map['id'], equals('tx_test_1'));
      expect(map['productId'], equals('prod_test'));
      expect(map['type'], equals('INVENTORY_AUDIT'));
      expect(map['quantity'], equals(15));
      expect(map['importPrice'], equals(75000.0));
      expect(map['createdBy'], equals('admin_user'));
      expect(map['createdByName'], equals('Administrator'));

      final restored = InventoryTransactionModel.fromMap(map);
      expect(restored.id, equals('tx_test_1'));
      expect(restored.toTransactionType(),
          equals(TransactionType.inventoryAudit));
      expect(restored.quantity, equals(15));
      expect(restored.importPrice, equals(75000.0));
      expect(restored.createdBy, equals('admin_user'));
      expect(restored.createdByName, equals('Administrator'));
    });
  });
}
