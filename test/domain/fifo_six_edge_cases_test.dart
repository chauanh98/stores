import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';

void main() {
  group('FIFO 6 Comprehensive Edge Cases Tests (F9)', () {
    // =========================================================================
    // CASE 1: Nhập kho (Inbound Purchase)
    // =========================================================================
    test('Case 1: Inbound purchase appends new lot with actual unit cost to store queue', () {
      final txs = [
        InventoryTransaction(
          id: 'tx_case1_1',
          productId: 'prod_case1',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Nhập kho đợt 1',
          importPrice: 50000.0,
          storeId: 'store_001',
        ),
        InventoryTransaction(
          id: 'tx_case1_2',
          productId: 'prod_case1',
          type: TransactionType.import,
          quantity: 20,
          date: DateTime(2024, 1, 2),
          note: 'Nhập kho đợt 2',
          importPrice: 55000.0,
          storeId: 'store_001',
        ),
      ];

      final fifo = FifoCalculator(txs);
      final lots = fifo.getInventoryLots('prod_case1', storeId: 'store_001');

      expect(lots.length, equals(2));
      expect(lots[0].remainingQuantity, equals(10));
      expect(lots[0].importPrice, equals(50000.0));
      expect(lots[0].unitCost, equals(50000.0));
      expect(lots[0].storeId, equals('store_001'));

      expect(lots[1].remainingQuantity, equals(20));
      expect(lots[1].importPrice, equals(55000.0));
      expect(lots[1].unitCost, equals(55000.0));
      expect(lots[1].storeId, equals('store_001'));

      expect(fifo.getRemainingQuantity('prod_case1', storeId: 'store_001'), equals(30));
    });

    // =========================================================================
    // CASE 2: Bán hàng POS & Oversold Stock (Zero Negative Lot Invariant)
    // =========================================================================
    test('Case 2: POS sale depletes oldest lots; oversold volume uses fallback price without negative lot qty', () {
      final txs = [
        InventoryTransaction(
          id: 'tx_case2_1',
          productId: 'prod_case2',
          type: TransactionType.import,
          quantity: 5,
          date: DateTime(2024, 1, 1),
          note: 'Lô 1',
          importPrice: 10000.0,
          storeId: 'store_001',
        ),
        InventoryTransaction(
          id: 'tx_case2_2',
          productId: 'prod_case2',
          type: TransactionType.import,
          quantity: 5,
          date: DateTime(2024, 1, 2),
          note: 'Lô 2',
          importPrice: 15000.0,
          storeId: 'store_001',
        ),
      ];

      final fifo = FifoCalculator(txs);

      // Sell 15 items (stock has only 10 items; 5 items are oversold).
      // Fallback cost price = 20,000
      // Expected COGS: (5 * 10k) + (5 * 15k) + (5 * 20k) = 50k + 75k + 100k = 225,000
      final cost = fifo.calculateCostForSale(
        productId: 'prod_case2',
        quantity: 15,
        saleDate: DateTime(2024, 1, 3),
        storeId: 'store_001',
        fallbackCostPrice: 20000.0,
      );

      expect(cost, equals(225000.0));

      final lots = fifo.getInventoryLots('prod_case2', storeId: 'store_001');
      expect(lots[0].remainingQuantity, equals(0)); // NOT negative!
      expect(lots[1].remainingQuantity, equals(0)); // NOT negative!
      expect(fifo.getRemainingQuantity('prod_case2', storeId: 'store_001'), equals(0));
    });

    // =========================================================================
    // CASE 3: Chuyển kho liên chi nhánh (Inter-Store Transfer Cost Preservation)
    // =========================================================================
    test('Case 3: Inter-store transfer deducts from source store and preserves cost basis in target store', () {
      final txs = [
        // Store 001 has 2 lots: 5 @ 10,000 and 5 @ 20,000
        InventoryTransaction(
          id: 'tx_case3_imp1',
          productId: 'prod_case3',
          type: TransactionType.import,
          quantity: 5,
          date: DateTime(2024, 1, 1),
          note: 'Lô 1 kho 1',
          importPrice: 10000.0,
          storeId: 'store_001',
        ),
        InventoryTransaction(
          id: 'tx_case3_imp2',
          productId: 'prod_case3',
          type: TransactionType.import,
          quantity: 5,
          date: DateTime(2024, 1, 2),
          note: 'Lô 2 kho 1',
          importPrice: 20000.0,
          storeId: 'store_001',
        ),
      ];

      final fifo = FifoCalculator(txs);

      // Transfer 8 units from store_001 to store_002 on Jan 3:
      // Transferred COGS: 5 @ 10k + 3 @ 20k = 50k + 60k = 110,000 (average unit cost = 110,000 / 8 = 13,750)
      final transferCost = fifo.transferInventory(
        productId: 'prod_case3',
        quantity: 8,
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        transferDate: DateTime(2024, 1, 3),
      );

      expect(transferCost, equals(110000.0));

      // Source store: Lot 1 exhausted (0), Lot 2 has 2 left
      final s1Lots = fifo.getInventoryLots('prod_case3', storeId: 'store_001');
      expect(s1Lots[0].remainingQuantity, equals(0));
      expect(s1Lots[1].remainingQuantity, equals(2));
      expect(fifo.getRemainingQuantity('prod_case3', storeId: 'store_001'), equals(2));

      // Target store: Has received a new lot of 8 items with effective unit cost = 13,750
      final s2Lots = fifo.getInventoryLots('prod_case3', storeId: 'store_002');
      expect(s2Lots.length, equals(1));
      expect(s2Lots[0].remainingQuantity, equals(8));
      expect(s2Lots[0].importPrice, equals(13750.0));
      expect(fifo.getRemainingQuantity('prod_case3', storeId: 'store_002'), equals(8));

      // Now sell 4 items from target store (store_002)
      // COGS at store_002: 4 * 13,750 = 55,000
      final saleCostAtS2 = fifo.calculateCostForSale(
        productId: 'prod_case3',
        quantity: 4,
        saleDate: DateTime(2024, 1, 4),
        storeId: 'store_002',
      );

      expect(saleCostAtS2, equals(55000.0));
      expect(s2Lots[0].remainingQuantity, equals(4));
    });

    // =========================================================================
    // CASE 4: Cân bằng kho tăng (+) (Stock Audit Increase)
    // =========================================================================
    test('Case 4: Positive stock audit creates a new lot with unit cost at audit date', () {
      final txs = [
        InventoryTransaction(
          id: 'tx_case4_imp',
          productId: 'prod_case4',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Lô ban đầu',
          importPrice: 30000.0,
          storeId: 'store_001',
        ),
        InventoryTransaction(
          id: 'tx_case4_audit',
          productId: 'prod_case4',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: DateTime(2024, 1, 2),
          note: 'Cân bằng tăng',
          importPrice: 35000.0,
          storeId: 'store_001',
          isAuditNegative: false,
          auditDifference: 5,
        ),
      ];

      final fifo = FifoCalculator(txs);
      final lots = fifo.getInventoryLots('prod_case4', storeId: 'store_001');

      expect(lots.length, equals(2));
      expect(lots[0].remainingQuantity, equals(10));
      expect(lots[0].importPrice, equals(30000.0));
      expect(lots[1].remainingQuantity, equals(5));
      expect(lots[1].importPrice, equals(35000.0));

      // Selling 12 items: 10 from initial lot @ 30k + 2 from audit lot @ 35k = 300k + 70k = 370k
      final cost = fifo.calculateCostForSale(
        productId: 'prod_case4',
        quantity: 12,
        saleDate: DateTime(2024, 1, 3),
        storeId: 'store_001',
      );

      expect(cost, equals(370000.0));
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(3));
    });

    // =========================================================================
    // CASE 5: Cân bằng kho giảm (-) (Stock Audit Shrinkage)
    // =========================================================================
    test('Case 5: Negative stock audit deducts deficit sequentially from oldest lots in store queue', () {
      final txs = [
        InventoryTransaction(
          id: 'tx_case5_imp1',
          productId: 'prod_case5',
          type: TransactionType.import,
          quantity: 6,
          date: DateTime(2024, 1, 1),
          note: 'Lô 1',
          importPrice: 20000.0,
          storeId: 'store_001',
        ),
        InventoryTransaction(
          id: 'tx_case5_imp2',
          productId: 'prod_case5',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 2),
          note: 'Lô 2',
          importPrice: 25000.0,
          storeId: 'store_001',
        ),
        InventoryTransaction(
          id: 'tx_case5_audit_neg',
          productId: 'prod_case5',
          type: TransactionType.inventoryAudit,
          quantity: 8, // Shrinkage: 6 from Lot 1 + 2 from Lot 2
          date: DateTime(2024, 1, 3),
          note: 'Kiểm kê giảm 8 cái',
          importPrice: 20000.0,
          storeId: 'store_001',
          isAuditNegative: true,
          auditDifference: -8,
        ),
      ];

      final fifo = FifoCalculator(txs);
      final lots = fifo.getInventoryLots('prod_case5', storeId: 'store_001');

      // Lot 1 must be exhausted (0), Lot 2 has 8 left (10 - 2 = 8)
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(8));
      expect(fifo.getRemainingQuantity('prod_case5', storeId: 'store_001'), equals(8));

      // Subsequent sale of 5 items draws from remaining Lot 2 @ 25,000 = 125,000
      final cost = fifo.calculateCostForSale(
        productId: 'prod_case5',
        quantity: 5,
        saleDate: DateTime(2024, 1, 4),
        storeId: 'store_001',
      );

      expect(cost, equals(125000.0));
      expect(lots[1].remainingQuantity, equals(3));
    });

    // =========================================================================
    // CASE 6: Trả hàng / Hoàn hóa đơn (Sales Return Head Prepending)
    // =========================================================================
    test('Case 6: Return to inventory prepends returned lot to HEAD (index 0) of the store queue', () {
      final txs = [
        InventoryTransaction(
          id: 'tx_case6_imp1',
          productId: 'prod_case6',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Lô 1 ban đầu @ 10k',
          importPrice: 10000.0,
          storeId: 'store_001',
        ),
        InventoryTransaction(
          id: 'tx_case6_imp2',
          productId: 'prod_case6',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 2),
          note: 'Lô 2 sau @ 20k',
          importPrice: 20000.0,
          storeId: 'store_001',
        ),
      ];

      final fifo = FifoCalculator(txs);

      // 1. Initial sale of 10 items exhausts Lot 1 @ 10k
      final cost1 = fifo.calculateCostForSale(
        productId: 'prod_case6',
        quantity: 10,
        saleDate: DateTime(2024, 1, 3),
        storeId: 'store_001',
      );
      expect(cost1, equals(100000.0));

      final lotsBeforeReturn = fifo.getInventoryLots('prod_case6', storeId: 'store_001');
      expect(lotsBeforeReturn[0].remainingQuantity, equals(0));
      expect(lotsBeforeReturn[1].remainingQuantity, equals(10));

      // 2. Customer returns 4 items from the first sale (original cost was 10,000)
      fifo.returnToInventory(
        productId: 'prod_case6',
        quantity: 4,
        unitCost: 10000.0,
        returnDate: DateTime(2024, 1, 4),
        storeId: 'store_001',
        transactionId: 'return_tx_001',
      );

      final lotsAfterReturn = fifo.getInventoryLots('prod_case6', storeId: 'store_001');
      // Returned lot is inserted at INDEX 0 (HEAD)
      expect(lotsAfterReturn.length, equals(3));
      expect(lotsAfterReturn[0].transactionId, equals('return_tx_001'));
      expect(lotsAfterReturn[0].remainingQuantity, equals(4));
      expect(lotsAfterReturn[0].importPrice, equals(10000.0));

      // 3. Next sale of 6 items draws 4 returned items @ 10k + 2 items from Lot 2 @ 20k
      // Expected COGS: (4 * 10k) + (2 * 20k) = 40k + 40k = 80,000
      final costAfterReturn = fifo.calculateCostForSale(
        productId: 'prod_case6',
        quantity: 6,
        saleDate: DateTime(2024, 1, 5),
        storeId: 'store_001',
      );

      expect(costAfterReturn, equals(80000.0));
      expect(lotsAfterReturn[0].remainingQuantity, equals(0)); // Returned lot consumed first
      expect(lotsAfterReturn[2].remainingQuantity, equals(8)); // Lot 2 reduced by 2
    });

    // =========================================================================
    // Combined Stress Test: Sequential execution of all 6 cases
    // =========================================================================
    test('All 6 edge cases working harmoniously across multiple stores', () {
      final fifo = FifoCalculator();

      // Step 1 (Case 1): Import 10 @ 100k at store_001
      fifo.initializeInventoryTracker([
        InventoryTransaction(
          id: 'imp_s1',
          productId: 'iphone',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Inbound',
          importPrice: 100000.0,
          storeId: 'store_001',
        ),
      ]);

      // Step 2 (Case 3): Transfer 4 units to store_002
      fifo.transferInventory(
        productId: 'iphone',
        quantity: 4,
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        transferDate: DateTime(2024, 1, 2),
      );

      expect(fifo.getRemainingQuantity('iphone', storeId: 'store_001'), equals(6));
      expect(fifo.getRemainingQuantity('iphone', storeId: 'store_002'), equals(4));

      // Step 3 (Case 4): Positive audit +2 at store_001 @ 110k
      fifo.addInventoryLot(
        'iphone',
        InventoryLot(
          transactionId: 'audit_plus_2',
          importDate: DateTime(2024, 1, 3),
          importPrice: 110000.0,
          remainingQuantity: 2,
          storeId: 'store_001',
        ),
        storeId: 'store_001',
      );

      expect(fifo.getRemainingQuantity('iphone', storeId: 'store_001'), equals(8));

      // Step 4 (Case 2): POS sale 5 units at store_001 -> 5 @ 100k = 500k
      final posCost = fifo.calculateCostForSale(
        productId: 'iphone',
        quantity: 5,
        saleDate: DateTime(2024, 1, 4),
        storeId: 'store_001',
      );
      expect(posCost, equals(500000.0));
      expect(fifo.getRemainingQuantity('iphone', storeId: 'store_001'), equals(3));

      // Step 5 (Case 6): Return 2 units to store_001 @ 100k
      fifo.returnToInventory(
        productId: 'iphone',
        quantity: 2,
        unitCost: 100000.0,
        returnDate: DateTime(2024, 1, 5),
        storeId: 'store_001',
      );
      expect(fifo.getRemainingQuantity('iphone', storeId: 'store_001'), equals(5));

      // Step 6 (Case 2): Oversold sale at store_002 (has 4 @ 100k, sell 6 with fallback 120k)
      final overCost = fifo.calculateCostForSale(
        productId: 'iphone',
        quantity: 6,
        saleDate: DateTime(2024, 1, 6),
        storeId: 'store_002',
        fallbackCostPrice: 120000.0,
      );
      // 4 * 100k + 2 * 120k = 400k + 240k = 640k
      expect(overCost, equals(640000.0));
      expect(fifo.getRemainingQuantity('iphone', storeId: 'store_002'), equals(0));
    });
  });
}
