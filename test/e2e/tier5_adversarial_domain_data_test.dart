import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/data/models/inventory_transaction_model.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/product_unit.dart';
import 'package:stores/domain/entities/transaction_type.dart';

void main() {
  group('=== TIER 5: ADVERSARIAL DOMAIN & FIFO HARDENING SUITE ===', () {
    // =========================================================================
    // GROUP 1: MULTI-STORE FIFO ISOLATION & QUEUE BOUNDARY HARDENING
    // =========================================================================
    group('Group 1: Multi-Store FIFO Isolation & Queue Boundary Hardening', () {
      test('T5.1: Complete Store-Partition Isolation Under Parallel Multi-Branch Transactions', () {
        final txs = [
          // Store 1: Inbound import
          InventoryTransaction(
            id: 'tx_s1_imp1',
            productId: 'p_iso_1',
            type: TransactionType.import,
            quantity: 100,
            date: DateTime(2026, 1, 1),
            note: 'Store 1 Import',
            importPrice: 10000.0,
            storeId: 'store_001',
          ),
          // Store 2: Inbound import with higher cost
          InventoryTransaction(
            id: 'tx_s2_imp1',
            productId: 'p_iso_1',
            type: TransactionType.import,
            quantity: 50,
            date: DateTime(2026, 1, 2),
            note: 'Store 2 Import',
            importPrice: 20000.0,
            storeId: 'store_002',
          ),
        ];

        final fifo = FifoCalculator(txs);

        // Perform sale in Store 1: 40 units
        final costS1 = fifo.calculateCostForSale(
          productId: 'p_iso_1',
          quantity: 40,
          saleDate: DateTime(2026, 1, 3),
          storeId: 'store_001',
        );
        expect(costS1, equals(400000.0)); // 40 * 10,000

        // Perform sale in Store 2: 30 units
        final costS2 = fifo.calculateCostForSale(
          productId: 'p_iso_1',
          quantity: 30,
          saleDate: DateTime(2026, 1, 4),
          storeId: 'store_002',
        );
        expect(costS2, equals(600000.0)); // 30 * 20,000

        // Check remaining inventory in Store 1: exactly 60 units remaining @ 10k
        final lotsS1 = fifo.getInventoryLots('p_iso_1', storeId: 'store_001');
        expect(lotsS1.length, equals(1));
        expect(lotsS1[0].remainingQuantity, equals(60));
        expect(lotsS1[0].importPrice, equals(10000.0));
        expect(fifo.getRemainingQuantity('p_iso_1', storeId: 'store_001'), equals(60));

        // Check remaining inventory in Store 2: exactly 20 units remaining @ 20k
        final lotsS2 = fifo.getInventoryLots('p_iso_1', storeId: 'store_002');
        expect(lotsS2.length, equals(1));
        expect(lotsS2[0].remainingQuantity, equals(20));
        expect(lotsS2[0].importPrice, equals(20000.0));
        expect(fifo.getRemainingQuantity('p_iso_1', storeId: 'store_002'), equals(20));

        // Invariant: Cross-querying with aliases should match canonical stores
        expect(fifo.getRemainingQuantity('p_iso_1', storeId: 'branch_1'), equals(60));
        expect(fifo.getRemainingQuantity('p_iso_1', storeId: 'ĐT'), equals(60));
        expect(fifo.getRemainingQuantity('p_iso_1', storeId: 'branch_2'), equals(20));
        expect(fifo.getRemainingQuantity('p_iso_1', storeId: 'TB'), equals(20));
      });

      test('T5.2: Dynamic & Non-Canonical Store Identifiers Partitioning', () {
        final fifo = FifoCalculator();

        // Add lots to 3 distinct custom branches
        fifo.addInventoryLot(
          'prod_custom',
          InventoryLot(
            transactionId: 'lot_wh',
            importDate: DateTime(2026, 2, 1),
            importPrice: 15000.0,
            remainingQuantity: 50,
            storeId: 'store_warehouse_main',
          ),
          storeId: 'store_warehouse_main',
        );

        fifo.addInventoryLot(
          'prod_custom',
          InventoryLot(
            transactionId: 'lot_van',
            importDate: DateTime(2026, 2, 2),
            importPrice: 18000.0,
            remainingQuantity: 25,
            storeId: 'store_van_01',
          ),
          storeId: 'store_van_01',
        );

        fifo.addInventoryLot(
          'prod_custom',
          InventoryLot(
            transactionId: 'lot_popup',
            importDate: DateTime(2026, 2, 3),
            importPrice: 22000.0,
            remainingQuantity: 10,
            storeId: 'store_popup_hcm',
          ),
          storeId: 'store_popup_hcm',
        );

        expect(fifo.getRemainingQuantity('prod_custom', storeId: 'store_warehouse_main'), equals(50));
        expect(fifo.getRemainingQuantity('prod_custom', storeId: 'store_van_01'), equals(25));
        expect(fifo.getRemainingQuantity('prod_custom', storeId: 'store_popup_hcm'), equals(10));

        // Sell from van
        final vanCost = fifo.calculateCostForSale(
          productId: 'prod_custom',
          quantity: 20,
          saleDate: DateTime(2026, 2, 4),
          storeId: 'store_van_01',
        );
        expect(vanCost, equals(360000.0)); // 20 * 18,000
        expect(fifo.getRemainingQuantity('prod_custom', storeId: 'store_van_01'), equals(5));

        // Verify warehouse and popup are completely untouched
        expect(fifo.getRemainingQuantity('prod_custom', storeId: 'store_warehouse_main'), equals(50));
        expect(fifo.getRemainingQuantity('prod_custom', storeId: 'store_popup_hcm'), equals(10));
      });

      test('T5.3: Reset and Scoped Re-initialization State Cleanliness', () {
        final fifo = FifoCalculator();

        fifo.addInventoryLot(
          'p1',
          InventoryLot(
            transactionId: 'l1',
            importDate: DateTime(2026, 1, 1),
            importPrice: 100.0,
            remainingQuantity: 10,
            storeId: 'store_001',
          ),
          storeId: 'store_001',
        );

        fifo.addInventoryLot(
          'p1',
          InventoryLot(
            transactionId: 'l2',
            importDate: DateTime(2026, 1, 1),
            importPrice: 200.0,
            remainingQuantity: 20,
            storeId: 'store_002',
          ),
          storeId: 'store_002',
        );

        // Reset store_001 only
        fifo.resetInventoryTracker(storeId: 'store_001');
        expect(fifo.getRemainingQuantity('p1', storeId: 'store_001'), equals(0));
        expect(fifo.hasAvailableLots('p1', storeId: 'store_001'), isFalse);
        expect(fifo.getRemainingQuantity('p1', storeId: 'store_002'), equals(20));
        expect(fifo.hasAvailableLots('p1', storeId: 'store_002'), isTrue);

        // Reset all
        fifo.resetInventoryTracker();
        expect(fifo.getRemainingQuantity('p1', storeId: 'store_002'), equals(0));
        expect(fifo.hasAvailableLots('p1', storeId: 'store_002'), isFalse);
      });
    });

    // =========================================================================
    // GROUP 2: INTER-STORE TRANSFERS & BLENDED COST PRESERVATION
    // =========================================================================
    group('Group 2: Inter-Store Transfers & Blended Cost Preservation', () {
      test('T5.4: Multi-Lot Fragmented Inter-Store Transfer with Blended Cost Basis Conservation', () {
        final txs = [
          InventoryTransaction(
            id: 'tx_src_1',
            productId: 'p_transfer',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 1, 1),
            note: 'Lot 1',
            importPrice: 10000.0,
            storeId: 'store_001',
          ),
          InventoryTransaction(
            id: 'tx_src_2',
            productId: 'p_transfer',
            type: TransactionType.import,
            quantity: 20,
            date: DateTime(2026, 1, 2),
            note: 'Lot 2',
            importPrice: 20000.0,
            storeId: 'store_001',
          ),
          InventoryTransaction(
            id: 'tx_src_3',
            productId: 'p_transfer',
            type: TransactionType.import,
            quantity: 30,
            date: DateTime(2026, 1, 3),
            note: 'Lot 3',
            importPrice: 30000.0,
            storeId: 'store_001',
          ),
        ];

        final fifo = FifoCalculator(txs);
        // Total initial in store_001: 60 units, total value = (10*10k) + (20*20k) + (30*30k) = 100k + 400k + 900k = 1,400,000

        // Transfer 25 units from store_001 to store_002:
        // Consumes all 10 of Lot 1 (100k) + 15 of Lot 2 (300k) = total transfer COGS 400,000
        // Effective unit cost = 400,000 / 25 = 16,000
        final transferCost = fifo.transferInventory(
          productId: 'p_transfer',
          quantity: 25,
          sourceStoreId: 'store_001',
          targetStoreId: 'store_002',
          transferDate: DateTime(2026, 1, 4),
        );

        expect(transferCost, equals(400000.0));

        // Check store_001 remaining lots:
        final srcLots = fifo.getInventoryLots('p_transfer', storeId: 'store_001');
        expect(srcLots[0].remainingQuantity, equals(0)); // Lot 1 depleted
        expect(srcLots[1].remainingQuantity, equals(5)); // Lot 2 has 5 left @ 20k
        expect(srcLots[2].remainingQuantity, equals(30)); // Lot 3 has 30 left @ 30k
        expect(fifo.getRemainingQuantity('p_transfer', storeId: 'store_001'), equals(35));

        // Value remaining in store_001: (5 * 20k) + (30 * 30k) = 100k + 900k = 1,000,000
        final srcRemainingValue = srcLots.fold(0.0, (sum, l) => sum + (l.remainingQuantity * l.importPrice));
        expect(srcRemainingValue, equals(1000000.0));

        // Check store_002: has 1 lot of 25 units @ 16,000 unit cost (value = 400,000)
        final tgtLots = fifo.getInventoryLots('p_transfer', storeId: 'store_002');
        expect(tgtLots.length, equals(1));
        expect(tgtLots[0].remainingQuantity, equals(25));
        expect(tgtLots[0].importPrice, equals(16000.0));
        expect(fifo.getRemainingQuantity('p_transfer', storeId: 'store_002'), equals(25));

        // CONSERVATION OF VALUE LAW: Initial (1,400,000) == Source (1,000,000) + Target (400,000)
        expect(srcRemainingValue + (tgtLots[0].remainingQuantity * tgtLots[0].importPrice), equals(1400000.0));
      });

      test('T5.5: Round-Trip Multi-Store Transfer Loop Cost Neutrality (A -> B -> A)', () {
        final fifo = FifoCalculator();

        fifo.addInventoryLot(
          'p_loop',
          InventoryLot(
            transactionId: 'lot_init',
            importDate: DateTime(2026, 1, 1),
            importPrice: 50000.0,
            remainingQuantity: 10,
            storeId: 'store_001',
          ),
          storeId: 'store_001',
        );

        // Transfer 10 units: store_001 -> store_002
        fifo.transferInventory(
          productId: 'p_loop',
          quantity: 10,
          sourceStoreId: 'store_001',
          targetStoreId: 'store_002',
          transferDate: DateTime(2026, 1, 2),
        );
        expect(fifo.getRemainingQuantity('p_loop', storeId: 'store_001'), equals(0));
        expect(fifo.getRemainingQuantity('p_loop', storeId: 'store_002'), equals(10));

        // Transfer 10 units back: store_002 -> store_001
        fifo.transferInventory(
          productId: 'p_loop',
          quantity: 10,
          sourceStoreId: 'store_002',
          targetStoreId: 'store_001',
          transferDate: DateTime(2026, 1, 3),
        );
        expect(fifo.getRemainingQuantity('p_loop', storeId: 'store_002'), equals(0));
        expect(fifo.getRemainingQuantity('p_loop', storeId: 'store_001'), equals(10));

        // Sell 10 units in store_001: COGS must remain exactly 500,000
        final cost = fifo.calculateCostForSale(
          productId: 'p_loop',
          quantity: 10,
          saleDate: DateTime(2026, 1, 4),
          storeId: 'store_001',
        );
        expect(cost, equals(500000.0));
        expect(fifo.getRemainingQuantity('p_loop', storeId: 'store_001'), equals(0));
      });

      test('T5.6: Inter-Store Transfer with Partial Oversold Source Fallback Propagation', () {
        final fifo = FifoCalculator();

        // Source only has 3 units @ 10,000
        fifo.addInventoryLot(
          'p_part_trans',
          InventoryLot(
            transactionId: 'lot_init',
            importDate: DateTime(2026, 1, 1),
            importPrice: 10000.0,
            remainingQuantity: 3,
            storeId: 'store_001',
          ),
          storeId: 'store_001',
        );

        // Transfer 10 units (3 from lot @ 10k + 7 oversold with fallback 15k)
        final transferCost = fifo.transferInventory(
          productId: 'p_part_trans',
          quantity: 10,
          sourceStoreId: 'store_001',
          targetStoreId: 'store_002',
          fallbackCostPrice: 15000.0,
          transferDate: DateTime(2026, 1, 2),
        );

        // 3 * 10,000 + 7 * 15,000 = 30,000 + 105,000 = 135,000
        expect(transferCost, equals(135000.0));

        // Target unit cost = 135,000 / 10 = 13,500
        final tgtLots = fifo.getInventoryLots('p_part_trans', storeId: 'store_002');
        expect(tgtLots.length, equals(1));
        expect(tgtLots[0].remainingQuantity, equals(10));
        expect(tgtLots[0].importPrice, equals(13500.0));

        // Source lot must be clamped to 0, not negative
        final srcLots = fifo.getInventoryLots('p_part_trans', storeId: 'store_001');
        expect(srcLots[0].remainingQuantity, equals(0));
      });
    });

    // =========================================================================
    // GROUP 3: SALES RETURNS, MULTI-RETURN CHAINING & INDEX-0 PREPENDING
    // =========================================================================
    group('Group 3: Sales Returns, Multi-Return Chaining & Index-0 Prepending', () {
      test('T5.7: Single Sales Return Prepending to Head of Queue (Index 0)', () {
        final txs = [
          InventoryTransaction(
            id: 'tx_r1',
            productId: 'p_ret',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 1, 1),
            note: 'Lot 1',
            importPrice: 20000.0,
            storeId: 'store_001',
          ),
          InventoryTransaction(
            id: 'tx_r2',
            productId: 'p_ret',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 1, 3),
            note: 'Lot 2',
            importPrice: 30000.0,
            storeId: 'store_001',
          ),
        ];

        final fifo = FifoCalculator(txs);

        // Sell 5 units on Jan 2 (from Lot 1)
        fifo.calculateCostForSale(
          productId: 'p_ret',
          quantity: 5,
          saleDate: DateTime(2026, 1, 2),
          storeId: 'store_001',
        );
        expect(fifo.getRemainingQuantity('p_ret', storeId: 'store_001'), equals(15));

        // Return 3 units on Jan 4 @ 20,000
        fifo.returnToInventory(
          productId: 'p_ret',
          quantity: 3,
          unitCost: 20000.0,
          returnDate: DateTime(2026, 1, 4),
          storeId: 'store_001',
        );

        final lots = fifo.getInventoryLots('p_ret', storeId: 'store_001');
        expect(lots.length, equals(3));
        // Verify index 0 is the returned lot
        expect(lots[0].remainingQuantity, equals(3));
        expect(lots[0].importPrice, equals(20000.0));
        // Index 1 is Lot 1 remaining (5 units @ 20k)
        expect(lots[1].remainingQuantity, equals(5));
        expect(lots[1].importPrice, equals(20000.0));
        // Index 2 is Lot 2 (10 units @ 30k)
        expect(lots[2].remainingQuantity, equals(10));
        expect(lots[2].importPrice, equals(30000.0));

        // Next sale of 4 units: consumes 3 from return lot + 1 from Lot 1 = 4 * 20k = 80,000
        final nextSaleCost = fifo.calculateCostForSale(
          productId: 'p_ret',
          quantity: 4,
          saleDate: DateTime(2026, 1, 5),
          storeId: 'store_001',
        );
        expect(nextSaleCost, equals(80000.0));
        expect(lots[0].remainingQuantity, equals(0)); // Return lot exhausted
        expect(lots[1].remainingQuantity, equals(4)); // Lot 1 has 4 left
      });

      test('T5.8: Consecutive Chained Multi-Return Ordering and Priority Consumption', () {
        final fifo = FifoCalculator();

        fifo.addInventoryLot(
          'p_chain',
          InventoryLot(
            transactionId: 'base_lot',
            importDate: DateTime(2026, 1, 1),
            importPrice: 100.0,
            remainingQuantity: 2,
            storeId: 'store_001',
          ),
          storeId: 'store_001',
        );

        // Return 1: 2 units @ 100
        fifo.returnToInventory(
          productId: 'p_chain',
          quantity: 2,
          unitCost: 100.0,
          storeId: 'store_001',
          transactionId: 'ret_1',
        );

        // Return 2: 3 units @ 80 (VIP discounted return)
        fifo.returnToInventory(
          productId: 'p_chain',
          quantity: 3,
          unitCost: 80.0,
          storeId: 'store_001',
          transactionId: 'ret_2',
        );

        final lots = fifo.getInventoryLots('p_chain', storeId: 'store_001');
        expect(lots.length, equals(3));
        expect(lots[0].transactionId, equals('ret_2'));
        expect(lots[0].importPrice, equals(80.0));
        expect(lots[0].remainingQuantity, equals(3));

        expect(lots[1].transactionId, equals('ret_1'));
        expect(lots[1].importPrice, equals(100.0));
        expect(lots[1].remainingQuantity, equals(2));

        expect(lots[2].transactionId, equals('base_lot'));
        expect(lots[2].importPrice, equals(100.0));
        expect(lots[2].remainingQuantity, equals(2));

        // Sell 4 units: consumes 3 @ 80 (from ret_2) + 1 @ 100 (from ret_1) = 240 + 100 = 340
        final cost = fifo.calculateCostForSale(
          productId: 'p_chain',
          quantity: 4,
          saleDate: DateTime(2026, 1, 2),
          storeId: 'store_001',
        );
        expect(cost, equals(340.0));
        expect(lots[0].remainingQuantity, equals(0));
        expect(lots[1].remainingQuantity, equals(1));
        expect(lots[2].remainingQuantity, equals(2));
      });

      test('T5.9: Store-Scoped Sales Return Isolation', () {
        final fifo = FifoCalculator();

        fifo.addInventoryLot(
          'p_ret_iso',
          InventoryLot(
            transactionId: 's1_l',
            importDate: DateTime(2026, 1, 1),
            importPrice: 10000.0,
            remainingQuantity: 10,
            storeId: 'store_001',
          ),
          storeId: 'store_001',
        );

        // Process return specifically in store_002
        fifo.returnToInventory(
          productId: 'p_ret_iso',
          quantity: 5,
          unitCost: 15000.0,
          storeId: 'store_002',
        );

        expect(fifo.getRemainingQuantity('p_ret_iso', storeId: 'store_001'), equals(10));
        expect(fifo.getRemainingQuantity('p_ret_iso', storeId: 'store_002'), equals(5));

        final lotsS2 = fifo.getInventoryLots('p_ret_iso', storeId: 'store_002');
        expect(lotsS2.length, equals(1));
        expect(lotsS2[0].importPrice, equals(15000.0));
      });
    });

    // =========================================================================
    // GROUP 4: OVERSOLD STOCK, FALLBACK COSTING & INVARIANT VERIFICATION
    // =========================================================================
    group('Group 4: Oversold Stock, Fallback Costing & Invariants', () {
      test('T5.10: Pure Zero-Lot Oversold Sale with Explicit Fallback Cost Price', () {
        final fifo = FifoCalculator();

        // No lots registered anywhere
        final cost = fifo.calculateCostForSale(
          productId: 'p_empty',
          quantity: 100,
          saleDate: DateTime(2026, 1, 1),
          storeId: 'store_001',
          fallbackCostPrice: 75000.0,
        );

        expect(cost, equals(7500000.0)); // 100 * 75,000
        expect(fifo.getRemainingQuantity('p_empty', storeId: 'store_001'), equals(0));
        expect(fifo.hasAvailableLots('p_empty', storeId: 'store_001'), isFalse);
      });

      test('T5.11: Mixed In-Stock and Massive Oversold Depletion with Non-Negative Invariant', () {
        final fifo = FifoCalculator();

        fifo.addInventoryLot(
          'p_huge_oversold',
          InventoryLot(
            transactionId: 'l1',
            importDate: DateTime(2026, 1, 1),
            importPrice: 10000.0,
            remainingQuantity: 5,
            storeId: 'store_001',
          ),
          storeId: 'store_001',
        );

        // Sell 1,000,005 units with fallback price 20,000
        final cost = fifo.calculateCostForSale(
          productId: 'p_huge_oversold',
          quantity: 1000005,
          saleDate: DateTime(2026, 1, 2),
          storeId: 'store_001',
          fallbackCostPrice: 20000.0,
        );

        // (5 * 10,000) + (1,000,000 * 20,000) = 50,000 + 20,000,000,000 = 20,000,050,000
        expect(cost, equals(20000050000.0));

        final lots = fifo.getInventoryLots('p_huge_oversold', storeId: 'store_001');
        expect(lots.length, equals(1));
        expect(lots[0].remainingQuantity, equals(0)); // strictly 0, NEVER negative!
        expect(fifo.getRemainingQuantity('p_huge_oversold', storeId: 'store_001'), equals(0));
      });

      test('T5.12: Oversold Followed by Restock and Normal FIFO Resumption', () {
        final fifo = FifoCalculator();

        // 1. Oversold sale
        final cost1 = fifo.calculateCostForSale(
          productId: 'p_resump',
          quantity: 10,
          saleDate: DateTime(2026, 1, 1),
          storeId: 'store_001',
          fallbackCostPrice: 50000.0,
        );
        expect(cost1, equals(500000.0));

        // 2. Inbound restock
        fifo.addInventoryLot(
          'p_resump',
          InventoryLot(
            transactionId: 'restock_1',
            importDate: DateTime(2026, 1, 2),
            importPrice: 40000.0,
            remainingQuantity: 20,
            storeId: 'store_001',
          ),
          storeId: 'store_001',
        );
        expect(fifo.getRemainingQuantity('p_resump', storeId: 'store_001'), equals(20));

        // 3. Subsequent sale takes from new lot
        final cost2 = fifo.calculateCostForSale(
          productId: 'p_resump',
          quantity: 15,
          saleDate: DateTime(2026, 1, 3),
          storeId: 'store_001',
        );
        expect(cost2, equals(600000.0)); // 15 * 40,000
        expect(fifo.getRemainingQuantity('p_resump', storeId: 'store_001'), equals(5));
      });
    });

    // =========================================================================
    // GROUP 5: INVENTORY AUDITS (POSITIVE & NEGATIVE) & CASCADING DRAIN
    // =========================================================================
    group('Group 5: Inventory Audits & Cascading Depletion', () {
      test('T5.13: Negative Inventory Audit Cascading Over Multiple Exhausted Lots', () {
        final txs = [
          InventoryTransaction(
            id: 'tx_lotA',
            productId: 'p_cascade',
            type: TransactionType.import,
            quantity: 5,
            date: DateTime(2026, 1, 1),
            note: 'Lot A',
            importPrice: 10000.0,
            storeId: 'store_001',
          ),
          InventoryTransaction(
            id: 'tx_lotB',
            productId: 'p_cascade',
            type: TransactionType.import,
            quantity: 10,
            date: DateTime(2026, 1, 2),
            note: 'Lot B',
            importPrice: 20000.0,
            storeId: 'store_001',
          ),
          InventoryTransaction(
            id: 'tx_lotC',
            productId: 'p_cascade',
            type: TransactionType.import,
            quantity: 15,
            date: DateTime(2026, 1, 3),
            note: 'Lot C',
            importPrice: 30000.0,
            storeId: 'store_001',
          ),
          // Audit (-18 units loss)
          InventoryTransaction(
            id: 'tx_audit_neg',
            productId: 'p_cascade',
            type: TransactionType.inventoryAudit,
            quantity: 18,
            date: DateTime(2026, 1, 4),
            note: 'Kiểm kê giảm do hỏng vỡ',
            isAuditNegative: true,
            auditDifference: -18,
            storeId: 'store_001',
          ),
        ];

        final fifo = FifoCalculator(txs);

        final lots = fifo.getInventoryLots('p_cascade', storeId: 'store_001');
        expect(lots.length, equals(3));
        expect(lots[0].remainingQuantity, equals(0)); // 5 drained
        expect(lots[1].remainingQuantity, equals(0)); // 10 drained
        expect(lots[2].remainingQuantity, equals(12)); // 15 - 3 = 12 left
        expect(fifo.getRemainingQuantity('p_cascade', storeId: 'store_001'), equals(12));

        // Next sale of 5 units comes from Lot C @ 30,000
        final cost = fifo.calculateCostForSale(
          productId: 'p_cascade',
          quantity: 5,
          saleDate: DateTime(2026, 1, 5),
          storeId: 'store_001',
        );
        expect(cost, equals(150000.0)); // 5 * 30,000
        expect(lots[2].remainingQuantity, equals(7));
      });

      test('T5.14: Negative Inventory Audit with Excess Drainage Clamping to Zero', () {
        final txs = [
          InventoryTransaction(
            id: 'tx_l1',
            productId: 'p_clamp',
            type: TransactionType.import,
            quantity: 3,
            date: DateTime(2026, 1, 1),
            note: 'Lot 1',
            importPrice: 10000.0,
            storeId: 'store_001',
          ),
          InventoryTransaction(
            id: 'tx_l2',
            productId: 'p_clamp',
            type: TransactionType.import,
            quantity: 4,
            date: DateTime(2026, 1, 2),
            note: 'Lot 2',
            importPrice: 20000.0,
            storeId: 'store_001',
          ),
          // Audit with massive negative difference (-50 units)
          InventoryTransaction(
            id: 'tx_audit_excess',
            productId: 'p_clamp',
            type: TransactionType.inventoryAudit,
            quantity: 50,
            date: DateTime(2026, 1, 3),
            note: 'Kiểm kê thất thoát lớn',
            isAuditNegative: true,
            auditDifference: -50,
            storeId: 'store_001',
          ),
        ];

        final fifo = FifoCalculator(txs);
        final lots = fifo.getInventoryLots('p_clamp', storeId: 'store_001');

        expect(lots[0].remainingQuantity, equals(0));
        expect(lots[1].remainingQuantity, equals(0));
        expect(fifo.getRemainingQuantity('p_clamp', storeId: 'store_001'), equals(0));
        expect(fifo.hasAvailableLots('p_clamp', storeId: 'store_001'), isFalse);
      });

      test('T5.15: Positive Inventory Audit With and Without Explicit Unit Cost', () {
        final txs = [
          InventoryTransaction(
            id: 'tx_audit_pos_1',
            productId: 'p_aud_pos',
            type: TransactionType.inventoryAudit,
            quantity: 15,
            date: DateTime(2026, 1, 1),
            note: 'Kiểm kê phát hiện thừa',
            isAuditNegative: false,
            auditDifference: 15,
            importPrice: 35000.0,
            storeId: 'store_001',
          ),
          InventoryTransaction(
            id: 'tx_audit_pos_2',
            productId: 'p_aud_pos',
            type: TransactionType.inventoryAudit,
            quantity: 10,
            date: DateTime(2026, 1, 2),
            note: 'Kiểm kê thừa không rõ giá',
            isAuditNegative: false,
            auditDifference: 10,
            importPrice: null, // Zero fallback
            storeId: 'store_001',
          ),
        ];

        final fifo = FifoCalculator(txs);
        final lots = fifo.getInventoryLots('p_aud_pos', storeId: 'store_001');

        expect(lots.length, equals(2));
        expect(lots[0].remainingQuantity, equals(15));
        expect(lots[0].importPrice, equals(35000.0));
        expect(lots[1].remainingQuantity, equals(10));
        expect(lots[1].importPrice, equals(0.0));

        // Sell 20 units: 15 @ 35,000 + 5 @ 0.0 = 525,000
        final cost = fifo.calculateCostForSale(
          productId: 'p_aud_pos',
          quantity: 20,
          saleDate: DateTime(2026, 1, 3),
          storeId: 'store_001',
        );
        expect(cost, equals(525000.0));
        expect(fifo.getRemainingQuantity('p_aud_pos', storeId: 'store_001'), equals(5));
      });

      test('T5.16: Audit Negative Detection Rules Resolution (Flags, Differences & Note Patterns)', () {
        final txExplicitFlag = InventoryTransaction(
          id: 't1',
          productId: 'p_detect',
          type: TransactionType.inventoryAudit,
          quantity: 2,
          date: DateTime(2026, 1, 1),
          note: 'Some note',
          isAuditNegative: true,
        );

        final txDiffNeg = InventoryTransaction(
          id: 't2',
          productId: 'p_detect',
          type: TransactionType.inventoryAudit,
          quantity: 2,
          date: DateTime(2026, 1, 1),
          note: 'Some note',
          auditDifference: -5,
        );

        final txNoteMinus = InventoryTransaction(
          id: 't3',
          productId: 'p_detect',
          type: TransactionType.inventoryAudit,
          quantity: 2,
          date: DateTime(2026, 1, 1),
          note: 'Khớp chênh lệch: -3 chai hỏng',
        );

        final txPositive = InventoryTransaction(
          id: 't4',
          productId: 'p_detect',
          type: TransactionType.inventoryAudit,
          quantity: 2,
          date: DateTime(2026, 1, 1),
          note: 'Khớp chênh lệch: +4 chai tìm thấy',
          isAuditNegative: false,
          auditDifference: 4,
        );

        final fifo = FifoCalculator([
          InventoryTransaction(
            id: 'init',
            productId: 'p_detect',
            type: TransactionType.import,
            quantity: 20,
            date: DateTime(2026, 1, 1),
            note: 'Init',
            importPrice: 100.0,
          ),
          txExplicitFlag,
          txDiffNeg,
          txNoteMinus,
          txPositive,
        ]);

        // Initial = 20
        // - t1 (isAuditNegative: true, toDeduct = quantity = 2) -> 18
        // - t2 (auditDifference: -5, toDeduct = 5) -> 13
        // - t3 (note has '-', auditDifference null, toDeduct = quantity = 2) -> 11
        // + t4 (auditDifference: +4, diffQty = 4) -> 15
        expect(fifo.getRemainingQuantity('p_detect'), equals(15));
      });
    });

    // =========================================================================
    // GROUP 6: MULTI-UNIT CONVERSIONS & BASE UNIT ARITHMETIC UNDER FIFO
    // =========================================================================
    group('Group 6: Multi-Unit Conversions & Base Unit Arithmetic', () {
      test('T5.17: Multi-Unit (Thùng -> Hộp -> Gói) Conversion and Base Unit FIFO Depletion', () {
        // Base unit: Gói
        // Hộp = 10 Gói
        // Thùng = 240 Gói (24 Hộp)
        const unitGoi = ProductUnit(id: 'u_goi', unitName: 'Gói', conversionRate: 1, price: 5000.0);
        const unitHop = ProductUnit(id: 'u_hop', unitName: 'Hộp', conversionRate: 10, price: 50000.0);
        const unitThung = ProductUnit(id: 'u_thung', unitName: 'Thùng', conversionRate: 240, price: 1100000.0);

        const product = Product(
          id: 'p_multi_unit',
          name: 'Mì Ăn Liền Hảo Hảo',
          code: 'HH01',
          price: 5000.0,
          costPrice: 3000.0,
          branchStocks: {'store_001': 530}, // 530 base units (2 Thùng + 5 Hộp)
          category: 'Thực phẩm',
          units: [unitGoi, unitHop, unitThung],
        );

        // FIFO Tracker initialized with base units:
        // Lot 1: 2 Thùng (= 480 Gói) @ 700,000/Thùng = 700,000 / 240 = 2,916.6667 per Gói
        // Lot 2: 5 Hộp (= 50 Gói) @ 32,000/Hộp = 3,200 per Gói
        final fifo = FifoCalculator([
          InventoryTransaction(
            id: 'imp_thung',
            productId: product.id,
            type: TransactionType.import,
            quantity: 480,
            date: DateTime(2026, 1, 1),
            note: 'Nhập 2 Thùng mì',
            importPrice: 700000.0 / 240.0,
            storeId: 'store_001',
          ),
          InventoryTransaction(
            id: 'imp_hop',
            productId: product.id,
            type: TransactionType.import,
            quantity: 50,
            date: DateTime(2026, 1, 2),
            note: 'Nhập 5 Hộp lẻ',
            importPrice: 32000.0 / 10.0,
            storeId: 'store_001',
          ),
        ]);

        // Customer buys: 1 Thùng (240 Gói) + 3 Hộp (30 Gói) + 5 Gói = 275 Gói
        const qtyGoi = 5;
        final qtyHop = 3 * unitHop.conversionRate;
        final qtyThung = 1 * unitThung.conversionRate;
        final totalBaseQtyToDeduct = qtyGoi + qtyHop + qtyThung; // 275

        expect(totalBaseQtyToDeduct, equals(275));

        final totalCogs = fifo.calculateCostForSale(
          productId: product.id,
          quantity: totalBaseQtyToDeduct,
          saleDate: DateTime(2026, 1, 3),
          storeId: 'store_001',
        );

        // 275 Gói consumed entirely from Lot 1 @ (700,000 / 240) = 802,083.3333
        expect(totalCogs, closeTo(275 * (700000.0 / 240.0), 0.001));

        // Remaining base quantity: 530 - 275 = 255 (205 in Lot 1, 50 in Lot 2)
        expect(fifo.getRemainingQuantity(product.id, storeId: 'store_001'), equals(255));
      });

      test('T5.18: Multi-Unit Return Conversion & Immediate Resale', () {
        final fifo = FifoCalculator();

        // Customer returns 1 Hộp (10 base units) where unitCost per base unit = 3,000
        const hopConversionRate = 10;
        const returnedBaseQty = 1 * hopConversionRate;
        const baseUnitCost = 3000.0;

        fifo.returnToInventory(
          productId: 'p_ret_unit',
          quantity: returnedBaseQty,
          unitCost: baseUnitCost,
          storeId: 'store_001',
          transactionId: 'ret_hop_1',
        );

        // Also add standard warehouse lot: 100 units @ 4,000
        fifo.addInventoryLot(
          'p_ret_unit',
          InventoryLot(
            transactionId: 'wh_lot',
            importDate: DateTime(2026, 1, 1),
            importPrice: 4000.0,
            remainingQuantity: 100,
            storeId: 'store_001',
          ),
          storeId: 'store_001',
        );

        // Sale of 15 base units: consumes 10 @ 3,000 (from return) + 5 @ 4,000 (from warehouse)
        final cost = fifo.calculateCostForSale(
          productId: 'p_ret_unit',
          quantity: 15,
          saleDate: DateTime(2026, 1, 2),
          storeId: 'store_001',
        );

        expect(cost, equals((10 * 3000.0) + (5 * 4000.0))); // 30,000 + 20,000 = 50,000
        expect(fifo.getRemainingQuantity('p_ret_unit', storeId: 'store_001'), equals(95));
      });
    });

    // =========================================================================
    // GROUP 7: DATA MODEL SERIALIZATION, DESERIALIZATION & CORRUPTED RESILIENCE
    // =========================================================================
    group('Group 7: Data Model Serialization Resilience', () {
      test('T5.19: ProductModel Resilient Deserialization with Corrupted & Legacy Map Data', () {
        final corruptedMap = {
          'id': 'p_corrupt_1',
          'name': 'Sữa Tươi Tiệt Trùng 1L',
          'price': 35000.0,
          // missing costPrice -> should fallback to price * 0.7 = 24,500
          'branchStocks': {
            'branch_1': '15', // string integer handled via tryParse
            'Chi nhánh Thới Bình': 25, // full name key
            'store_003': 10,
          },
          'minStock': 5,
          'maxStock': null,
          'allowSale': null,
          'isActive': true, // legacy flag
          'category': null, // null category -> fallback to 'Khác'
        };

        final model = ProductModel.fromMap(corruptedMap);
        final entity = model.toEntity();

        expect(entity.id, equals('p_corrupt_1'));
        expect(entity.name, equals('Sữa Tươi Tiệt Trùng 1L'));
        expect(entity.price, equals(35000.0));
        expect(entity.costPrice, equals(24500.0)); // 35000 * 0.7
        expect(entity.category, equals('Khác'));
        expect(entity.minStock, equals(5));
        expect(entity.maxStock, isNull);
        expect(entity.allowSale, isTrue);

        // Branch stocks normalization:
        expect(entity.branchStocks['store_001'], equals(15));
        expect(entity.branchStocks['store_002'], equals(25));
        expect(entity.branchStocks['store_003'], equals(10));
        expect(entity.stock, equals(50)); // 15 + 25 + 10
      });

      test('T5.20: ProductModel Firebase Map-Encoded List Parsing for Units and Combo Components', () {
        final firebaseMap = {
          'id': 'p_firebase_struct',
          'name': 'Nước Xả Vải Comfort',
          'price': 120000.0,
          'costPrice': 80000.0,
          'branchStocks': {'store_001': 10, 'store_002': 20},
          // Units encoded as Map with string integer keys (Firebase array-like map)
          'units': {
            '0': {
              'id': 'u1',
              'unitName': 'Thùng',
              'conversionRate': 4,
              'price': 450000.0,
              'costPrice': 300000.0,
              'isDirectSale': true,
            },
            '1': {
              'id': 'u2',
              'unitName': 'Túi',
              'conversionRate': 1,
              'price': 120000.0,
              'costPrice': 80000.0,
              'isDirectSale': true,
            }
          },
          // Combo components as List of Maps
          'isCombo': true,
          'comboComponents': [
            {'productId': 'comp_1', 'productName': 'Comfort 1L', 'quantity': 2},
            {'productId': 'comp_2', 'productName': 'Quà Tặng Khăn Mặt', 'quantity': 1},
          ],
        };

        final model = ProductModel.fromMap(firebaseMap);
        expect(model.units.length, equals(2));
        expect(model.units[0].unitName, equals('Thùng'));
        expect(model.units[0].conversionRate, equals(4));
        expect(model.units[1].unitName, equals('Túi'));

        expect(model.isCombo, isTrue);
        expect(model.comboComponents.length, equals(2));
        expect(model.comboComponents[0].productId, equals('comp_1'));
        expect(model.comboComponents[1].quantity, equals(1));
      });

      test('T5.21: InventoryTransactionModel Malformed Input & Safe Type Parsing', () {
        final malformedMap = {
          'id': 'tx_malformed',
          'productId': 'p_test',
          'type': 'INVENTORY_AUDIT', // Uppercase string
          'quantity': 10,
          'date': 'not-a-valid-date-string', // Corrupted date string
          'note': 'Kiểm kê kho',
          'importPrice': 45000.5,
          'isAuditNegative': 'true', // String boolean converted safely
          'auditDifference': -10,
          'storeId': 'store_001',
        };

        final model = InventoryTransactionModel.fromMap(malformedMap);
        final entity = model.toEntity();

        expect(entity.id, equals('tx_malformed'));
        expect(entity.productId, equals('p_test'));
        expect(entity.type, equals(TransactionType.inventoryAudit));
        expect(entity.quantity, equals(10));
        expect(entity.importPrice, equals(45000.5));
        expect(entity.isAuditNegative, isTrue);
        expect(entity.auditDifference, equals(-10));
        expect(entity.storeId, equals('store_001'));
        // Date falls back gracefully to a non-null DateTime
        expect(entity.date, isNotNull);
        expect(entity.date.isBefore(DateTime.now().add(const Duration(seconds: 5))), isTrue);
      });

      test('T5.22: Product Entity stockInBranch Robust Canonical Alias Resolution', () {
        const product = Product(
          id: 'p_aliases',
          name: 'Nước Ngọt Coca Cola',
          code: 'COCA',
          price: 10000.0,
          costPrice: 7000.0,
          branchStocks: {
            'store_001': 15,
            'store_002': 25,
            'store_warehouse': 50,
          },
          category: 'Nước giải khát',
        );

        // Store 001 canonical and aliases
        expect(product.stockInBranch('store_001'), equals(15));
        expect(product.stockInBranch('branch_1'), equals(15));
        expect(product.stockInBranch('ĐT'), equals(15));
        expect(product.stockInBranch('đt'), equals(15));
        expect(product.stockInBranch('DT'), equals(15));
        expect(product.stockInBranch('dt'), equals(15));
        expect(product.stockInBranch('Chi nhánh Đông Thắng'), equals(15));
        expect(product.stockInBranch('đông thắng'), equals(15));
        expect(product.stockInBranch('dong thang'), equals(15));

        // Store 002 canonical and aliases
        expect(product.stockInBranch('store_002'), equals(25));
        expect(product.stockInBranch('branch_2'), equals(25));
        expect(product.stockInBranch('TB'), equals(25));
        expect(product.stockInBranch('tb'), equals(25));
        expect(product.stockInBranch('Chi nhánh Thới Bình'), equals(25));
        expect(product.stockInBranch('thới bình'), equals(25));
        expect(product.stockInBranch('thoi binh'), equals(25));

        // Custom branch
        expect(product.stockInBranch('store_warehouse'), equals(50));
        expect(product.stockInBranch('STORE_WAREHOUSE'), equals(50));

        // Non-existent or empty
        expect(product.stockInBranch('unknown_branch'), equals(0));
        expect(product.stockInBranch(''), equals(0));
        expect(product.stockInBranch('   '), equals(0));
      });
    });

    // =========================================================================
    // GROUP 8: MATHEMATICAL PRECISION, PROFIT MARGIN & HIGH-VOLUME STRESS
    // =========================================================================
    group('Group 8: Mathematical Precision, Margins & High-Volume Stress', () {
      test('T5.23: Extreme Floating-Point Precision & Profit Margin Boundary Stress', () {
        // Zero cost
        expect(FifoCalculator.calculateProfitMargin(100.0, 0.0), equals(100.0));

        // Zero revenue
        expect(FifoCalculator.calculateProfitMargin(0.0, 50.0), equals(0.0));

        // Negative revenue
        expect(FifoCalculator.calculateProfitMargin(-10.0, 50.0), equals(0.0));

        // Breakeven
        expect(FifoCalculator.calculateProfitMargin(500.0, 500.0), equals(0.0));

        // Loss sale: Revenue = 100, Cost = 150 -> margin = (100 - 150) / 100 * 100 = -50.0%
        expect(FifoCalculator.calculateProfitMargin(100.0, 150.0), equals(-50.0));

        // High precision fractional margin: Revenue = 10,000,000, Cost = 6,666,666.6667
        final margin = FifoCalculator.calculateProfitMargin(10000000.0, 6666666.6667);
        expect(margin, closeTo(33.33333, 0.001));
      });

      test('T5.24: High-Volume Transaction Stress Simulation (10,000 FIFO Operations)', () {
        final random = Random(42);
        final List<InventoryTransaction> transactions = [];
        final baseDate = DateTime(2026, 1, 1);

        // Generate 10,000 transactions across 3 stores and 10 products
        final storeIds = ['store_001', 'store_002', 'store_003'];
        final productIds = List.generate(10, (i) => 'stress_prod_$i');

        for (int i = 0; i < 10000; i++) {
          final storeId = storeIds[random.nextInt(storeIds.length)];
          final productId = productIds[random.nextInt(productIds.length)];
          final date = baseDate.add(Duration(minutes: i * 5));
          final typeRoll = random.nextDouble();

          if (typeRoll < 0.6) {
            // 60% Inbound Imports
            transactions.add(InventoryTransaction(
              id: 'tx_stress_$i',
              productId: productId,
              type: TransactionType.import,
              quantity: random.nextInt(50) + 1,
              date: date,
              note: 'Stress Import $i',
              importPrice: (random.nextInt(100) + 10) * 1000.0,
              storeId: storeId,
            ));
          } else if (typeRoll < 0.8) {
            // 20% Positive Audit
            transactions.add(InventoryTransaction(
              id: 'tx_stress_$i',
              productId: productId,
              type: TransactionType.inventoryAudit,
              quantity: random.nextInt(10) + 1,
              date: date,
              note: 'Stress Audit + $i',
              isAuditNegative: false,
              auditDifference: random.nextInt(10) + 1,
              importPrice: (random.nextInt(100) + 10) * 1000.0,
              storeId: storeId,
            ));
          } else {
            // 20% Negative Audit
            final diff = -(random.nextInt(15) + 1);
            transactions.add(InventoryTransaction(
              id: 'tx_stress_$i',
              productId: productId,
              type: TransactionType.inventoryAudit,
              quantity: diff.abs(),
              date: date,
              note: 'Stress Audit - $i',
              isAuditNegative: true,
              auditDifference: diff,
              storeId: storeId,
            ));
          }
        }

        final stopwatch = Stopwatch()..start();
        final fifo = FifoCalculator(transactions);

        // Perform 500 interleaved sales across products and stores
        double totalSimulatedCogs = 0.0;
        for (int j = 0; j < 500; j++) {
          final storeId = storeIds[random.nextInt(storeIds.length)];
          final productId = productIds[random.nextInt(productIds.length)];
          final qty = random.nextInt(30) + 1;

          final cogs = fifo.calculateCostForSale(
            productId: productId,
            quantity: qty,
            saleDate: baseDate.add(const Duration(days: 40)),
            storeId: storeId,
            fallbackCostPrice: 50000.0,
          );
          totalSimulatedCogs += cogs;
        }

        stopwatch.stop();

        // High performance check: 10k transactions + 500 sales processed in < 1500ms
        expect(stopwatch.elapsedMilliseconds, lessThan(1500));
        expect(totalSimulatedCogs, greaterThan(0.0));

        // Invariant check: No lot across all stores and products must have remainingQuantity < 0
        for (final sId in storeIds) {
          for (final pId in productIds) {
            final lots = fifo.getInventoryLots(pId, storeId: sId);
            for (final lot in lots) {
              expect(lot.remainingQuantity, greaterThanOrEqualTo(0));
            }
          }
        }
      });

      test('T5.25: Comprehensive End-to-End Retail Multi-Store Lifecycle with Ledger Parity', () {
        // End-to-End Simulation over 7 Days:
        // Day 1: Inbound import 100 units @ 50,000 in store_001
        // Day 2: POS sale 30 units @ 100,000 in store_001 (COGS = 1,500,000, Revenue = 3,000,000, Profit = 1,500,000)
        // Day 3: Inter-store transfer 40 units from store_001 to store_002 (Transfer Cost = 2,000,000)
        // Day 4: POS sale 25 units @ 120,000 in store_002 (COGS = 1,250,000, Revenue = 3,000,000, Profit = 1,750,000)
        // Day 5: Customer returns 5 units in store_002 @ 50,000
        // Day 6: Physical audit (-) in store_001 losing 5 units (spoiled)
        // Day 7: store_002 sells 10 units @ 120,000 (5 from return @ 50k + 5 from remaining @ 50k = 500k COGS)

        final fifo = FifoCalculator();

        // Day 1: Import in store_001
        fifo.addInventoryLot(
          'prod_e2e',
          InventoryLot(
            transactionId: 'day1_import',
            importDate: DateTime(2026, 3, 1),
            importPrice: 50000.0,
            remainingQuantity: 100,
            storeId: 'store_001',
          ),
          storeId: 'store_001',
        );
        expect(fifo.getRemainingQuantity('prod_e2e', storeId: 'store_001'), equals(100));

        // Day 2: POS Sale in store_001 (30 units)
        final cogsDay2 = fifo.calculateCostForSale(
          productId: 'prod_e2e',
          quantity: 30,
          saleDate: DateTime(2026, 3, 2),
          storeId: 'store_001',
        );
        expect(cogsDay2, equals(1500000.0));
        expect(fifo.getRemainingQuantity('prod_e2e', storeId: 'store_001'), equals(70));

        // Day 3: Inter-Store Transfer (40 units: store_001 -> store_002)
        final transferCost = fifo.transferInventory(
          productId: 'prod_e2e',
          quantity: 40,
          sourceStoreId: 'store_001',
          targetStoreId: 'store_002',
          transferDate: DateTime(2026, 3, 3),
        );
        expect(transferCost, equals(2000000.0)); // 40 * 50,000
        expect(fifo.getRemainingQuantity('prod_e2e', storeId: 'store_001'), equals(30));
        expect(fifo.getRemainingQuantity('prod_e2e', storeId: 'store_002'), equals(40));

        // Day 4: POS Sale in store_002 (25 units)
        final cogsDay4 = fifo.calculateCostForSale(
          productId: 'prod_e2e',
          quantity: 25,
          saleDate: DateTime(2026, 3, 4),
          storeId: 'store_002',
        );
        expect(cogsDay4, equals(1250000.0)); // 25 * 50,000
        expect(fifo.getRemainingQuantity('prod_e2e', storeId: 'store_002'), equals(15));

        // Day 5: Customer return 5 units in store_002
        fifo.returnToInventory(
          productId: 'prod_e2e',
          quantity: 5,
          unitCost: 50000.0,
          returnDate: DateTime(2026, 3, 5),
          storeId: 'store_002',
          transactionId: 'day5_return',
        );
        expect(fifo.getRemainingQuantity('prod_e2e', storeId: 'store_002'), equals(20));

        // Day 6: Audit (-) in store_001 losing 5 units
        final s1Lots = fifo.getInventoryLots('prod_e2e', storeId: 'store_001');
        s1Lots[0].remainingQuantity -= 5; // Spoilage deduction
        expect(fifo.getRemainingQuantity('prod_e2e', storeId: 'store_001'), equals(25));

        // Day 7: store_002 sells 10 units
        final cogsDay7 = fifo.calculateCostForSale(
          productId: 'prod_e2e',
          quantity: 10,
          saleDate: DateTime(2026, 3, 7),
          storeId: 'store_002',
        );
        expect(cogsDay7, equals(500000.0)); // 10 * 50,000
        expect(fifo.getRemainingQuantity('prod_e2e', storeId: 'store_002'), equals(10));

        // FINAL RECONCILIATION:
        // Total Inbound: 100
        // Total Sold: 30 (s1) + 25 (s2) + 10 (s2) = 65
        // Total Returned: 5 (s2)
        // Total Spoiled/Audited Out: 5 (s1)
        // Expected Physical Balance = 100 - 65 + 5 - 5 = 35 units
        // store_001 stock = 25 units
        // store_002 stock = 10 units
        // Total = 35 units! 100% LEDGER PARITY!
        expect(fifo.getRemainingQuantity('prod_e2e', storeId: 'store_001'), equals(25));
        expect(fifo.getRemainingQuantity('prod_e2e', storeId: 'store_002'), equals(10));
        expect(
          fifo.getRemainingQuantity('prod_e2e', storeId: 'store_001') +
              fifo.getRemainingQuantity('prod_e2e', storeId: 'store_002'),
          equals(35),
        );
      });
    });
  });
}
