import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';

void main() {
  group('Empirical Challenger 1: Adversarial FIFO Stress Suite', () {
    // -------------------------------------------------------------------------
    // CHALLENGE 1: Multi-Store Interleaved Concurrency & Isolation
    // -------------------------------------------------------------------------
    test('Interleaved simultaneous transactions in store_001 and store_002 never contaminate queues or COGS', () {
      final fifo = FifoCalculator();

      // Initialize both stores with distinct lots for the same product 'laptop'
      fifo.initializeInventoryTracker([
        // Store 001: 10 @ 10,000, 20 @ 15,000
        InventoryTransaction(
          id: 's1_imp1',
          productId: 'laptop',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'S1 Batch 1',
          importPrice: 10000.0,
          storeId: 'store_001',
        ),
        InventoryTransaction(
          id: 's1_imp2',
          productId: 'laptop',
          type: TransactionType.import,
          quantity: 20,
          date: DateTime(2024, 1, 2),
          note: 'S1 Batch 2',
          importPrice: 15000.0,
          storeId: 'store_001',
        ),
        // Store 002: 15 @ 40,000, 25 @ 50,000
        InventoryTransaction(
          id: 's2_imp1',
          productId: 'laptop',
          type: TransactionType.import,
          quantity: 15,
          date: DateTime(2024, 1, 1),
          note: 'S2 Batch 1',
          importPrice: 40000.0,
          storeId: 'store_002',
        ),
        InventoryTransaction(
          id: 's2_imp2',
          productId: 'laptop',
          type: TransactionType.import,
          quantity: 25,
          date: DateTime(2024, 1, 2),
          note: 'S2 Batch 2',
          importPrice: 50000.0,
          storeId: 'store_002',
        ),
      ]);

      // Interleave sales between store_001 and store_002
      // Step 1: Store 1 sells 5 (5 @ 10k = 50k)
      final c1 = fifo.calculateCostForSale(
        productId: 'laptop',
        quantity: 5,
        saleDate: DateTime(2024, 1, 3),
        storeId: 'store_001',
      );
      expect(c1, equals(50000.0));
      expect(fifo.getRemainingQuantity('laptop', storeId: 'store_001'), equals(25));
      expect(fifo.getRemainingQuantity('laptop', storeId: 'store_002'), equals(40));

      // Step 2: Store 2 sells 20 (15 @ 40k + 5 @ 50k = 600k + 250k = 850k)
      final c2 = fifo.calculateCostForSale(
        productId: 'laptop',
        quantity: 20,
        saleDate: DateTime(2024, 1, 4),
        storeId: 'store_002',
      );
      expect(c2, equals(850000.0));
      expect(fifo.getRemainingQuantity('laptop', storeId: 'store_001'), equals(25));
      expect(fifo.getRemainingQuantity('laptop', storeId: 'store_002'), equals(20));

      // Step 3: Store 1 sells 10 (5 remaining @ 10k + 5 @ 15k = 50k + 75k = 125k)
      final c3 = fifo.calculateCostForSale(
        productId: 'laptop',
        quantity: 10,
        saleDate: DateTime(2024, 1, 5),
        storeId: 'store_001',
      );
      expect(c3, equals(125000.0));
      expect(fifo.getRemainingQuantity('laptop', storeId: 'store_001'), equals(15));
      expect(fifo.getRemainingQuantity('laptop', storeId: 'store_002'), equals(20));

      // Step 4: Store 2 sells 10 (10 @ 50k = 500k)
      final c4 = fifo.calculateCostForSale(
        productId: 'laptop',
        quantity: 10,
        saleDate: DateTime(2024, 1, 6),
        storeId: 'store_002',
      );
      expect(c4, equals(500000.0));
      expect(fifo.getRemainingQuantity('laptop', storeId: 'store_001'), equals(15));
      expect(fifo.getRemainingQuantity('laptop', storeId: 'store_002'), equals(10));

      // Check remaining lots precision
      final s1Lots = fifo.getInventoryLots('laptop', storeId: 'store_001');
      expect(s1Lots[0].remainingQuantity, equals(0));
      expect(s1Lots[1].remainingQuantity, equals(15));

      final s2Lots = fifo.getInventoryLots('laptop', storeId: 'store_002');
      expect(s2Lots[0].remainingQuantity, equals(0));
      expect(s2Lots[1].remainingQuantity, equals(10));
    });

    // -------------------------------------------------------------------------
    // CHALLENGE 2: Case 2 (Oversold Stock & Invariant Integrity)
    // -------------------------------------------------------------------------
    test('Case 2: Oversold sale clamps remaining quantities at 0 and does NOT swallow subsequent imports', () {
      final fifo = FifoCalculator();

      // Initial import: 5 units @ 10,000 in store_001
      fifo.initializeInventoryTracker([
        InventoryTransaction(
          id: 'init_imp',
          productId: 'phone',
          type: TransactionType.import,
          quantity: 5,
          date: DateTime(2024, 1, 1),
          note: 'Initial import',
          importPrice: 10000.0,
          storeId: 'store_001',
        ),
      ]);

      // Sale of 15 units (Oversold by 10 units). Fallback cost price = 12,000
      // Expected COGS: 5 @ 10,000 + 10 @ 12,000 = 50,000 + 120,000 = 170,000
      final oversoldCost = fifo.calculateCostForSale(
        productId: 'phone',
        quantity: 15,
        saleDate: DateTime(2024, 1, 2),
        storeId: 'store_001',
        fallbackCostPrice: 12000.0,
      );

      expect(oversoldCost, equals(170000.0));

      // Verify ZERO negative lot invariant
      final lotsAfterOversold = fifo.getInventoryLots('phone', storeId: 'store_001');
      expect(lotsAfterOversold.length, equals(1));
      expect(lotsAfterOversold[0].remainingQuantity, equals(0)); // MUST NOT be -10
      expect(fifo.getRemainingQuantity('phone', storeId: 'store_001'), equals(0));

      // SUBSEQUENT IMPORT: 8 units @ 20,000
      // If the engine incorrectly stored a negative balance (-10), this new import would be swallowed or reduced to 0.
      fifo.addInventoryLot(
        'phone',
        InventoryLot(
          transactionId: 'subsequent_imp',
          importDate: DateTime(2024, 1, 3),
          importPrice: 20000.0,
          remainingQuantity: 8,
          storeId: 'store_001',
        ),
        storeId: 'store_001',
      );

      // Remaining quantity MUST be exactly 8
      expect(fifo.getRemainingQuantity('phone', storeId: 'store_001'), equals(8));

      // Subsequent sale of 4 units: MUST consume from the new lot @ 20,000 = 80,000
      final costNextSale = fifo.calculateCostForSale(
        productId: 'phone',
        quantity: 4,
        saleDate: DateTime(2024, 1, 4),
        storeId: 'store_001',
      );

      expect(costNextSale, equals(80000.0));
      expect(fifo.getRemainingQuantity('phone', storeId: 'store_001'), equals(4));
    });

    test('Case 2: Pure Oversold sale with zero initial inventory uses fallback price correctly', () {
      final fifo = FifoCalculator();

      // Product 'gadget' has 0 inventory
      final cost = fifo.calculateCostForSale(
        productId: 'gadget',
        quantity: 7,
        saleDate: DateTime(2024, 1, 1),
        storeId: 'store_001',
        fallbackCostPrice: 35000.0,
      );

      expect(cost, equals(7 * 35000.0));
      expect(fifo.getRemainingQuantity('gadget', storeId: 'store_001'), equals(0));

      // Adding fresh inventory lot
      fifo.addInventoryLot(
        'gadget',
        InventoryLot(
          transactionId: 'gadget_imp',
          importDate: DateTime(2024, 1, 2),
          importPrice: 40000.0,
          remainingQuantity: 10,
          storeId: 'store_001',
        ),
        storeId: 'store_001',
      );

      expect(fifo.getRemainingQuantity('gadget', storeId: 'store_001'), equals(10));
    });

    // -------------------------------------------------------------------------
    // CHALLENGE 3: Case 3 (Multi-Hop Inter-Store Transfer Cost Basis)
    // -------------------------------------------------------------------------
    test('Case 3: Multi-hop transfer preserves exact weighted-average cost basis across stores', () {
      final fifo = FifoCalculator();

      // Store A has 2 lots: 10 @ 10,000 and 10 @ 20,000
      fifo.initializeInventoryTracker([
        InventoryTransaction(
          id: 'imp_sA_1',
          productId: 'prod_transfer',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Lot 1 Store A',
          importPrice: 10000.0,
          storeId: 'store_001',
        ),
        InventoryTransaction(
          id: 'imp_sA_2',
          productId: 'prod_transfer',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 2),
          note: 'Lot 2 Store A',
          importPrice: 20000.0,
          storeId: 'store_001',
        ),
      ]);

      // Transfer 15 units from Store A to Store B on Jan 3:
      // Transferred COGS: 10 @ 10k + 5 @ 20k = 100k + 100k = 200,000 (unit cost = 200,000 / 15 = 13,333.333...)
      final transferCostAB = fifo.transferInventory(
        productId: 'prod_transfer',
        quantity: 15,
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        transferDate: DateTime(2024, 1, 3),
      );

      expect(transferCostAB, equals(200000.0));
      expect(fifo.getRemainingQuantity('prod_transfer', storeId: 'store_001'), equals(5));
      expect(fifo.getRemainingQuantity('prod_transfer', storeId: 'store_002'), equals(15));

      // Store B now has 1 lot of 15 @ (200,000 / 15)
      final s2Lots = fifo.getInventoryLots('prod_transfer', storeId: 'store_002');
      expect(s2Lots.length, equals(1));
      expect(s2Lots[0].remainingQuantity, equals(15));
      expect(s2Lots[0].importPrice, closeTo(200000.0 / 15, 0.001));

      // Multi-hop: Transfer 6 units from Store B to Store C (custom_store_003)
      // Transferred COGS: 6 * (200,000 / 15) = 80,000
      final transferCostBC = fifo.transferInventory(
        productId: 'prod_transfer',
        quantity: 6,
        sourceStoreId: 'store_002',
        targetStoreId: 'custom_store_003',
        transferDate: DateTime(2024, 1, 4),
      );

      expect(transferCostBC, closeTo(80000.0, 0.001));
      expect(fifo.getRemainingQuantity('prod_transfer', storeId: 'store_002'), equals(9));
      expect(fifo.getRemainingQuantity('prod_transfer', storeId: 'custom_store_003'), equals(6));

      // Sale at Store C of all 6 units
      final saleCostC = fifo.calculateCostForSale(
        productId: 'prod_transfer',
        quantity: 6,
        saleDate: DateTime(2024, 1, 5),
        storeId: 'custom_store_003',
      );

      expect(saleCostC, closeTo(80000.0, 0.001));
      expect(fifo.getRemainingQuantity('prod_transfer', storeId: 'custom_store_003'), equals(0));
    });

    // -------------------------------------------------------------------------
    // CHALLENGE 4: Case 6 (Sales Return Head Insertion & Prioritization)
    // -------------------------------------------------------------------------
    test('Case 6: Multiple returns are inserted at index 0 and consumed strictly before older stock', () {
      final fifo = FifoCalculator();

      // Store 1 initial lot: 20 @ 50,000
      fifo.initializeInventoryTracker([
        InventoryTransaction(
          id: 'imp_s1',
          productId: 'shoe',
          type: TransactionType.import,
          quantity: 20,
          date: DateTime(2024, 1, 1),
          note: 'Initial import @ 50k',
          importPrice: 50000.0,
          storeId: 'store_001',
        ),
      ]);

      // Sale 1: Sell 10 @ 50,000 -> Remaining in initial lot = 10
      final cost1 = fifo.calculateCostForSale(
        productId: 'shoe',
        quantity: 10,
        saleDate: DateTime(2024, 1, 2),
        storeId: 'store_001',
      );
      expect(cost1, equals(500000.0));
      expect(fifo.getRemainingQuantity('shoe', storeId: 'store_001'), equals(10));

      // Return 1: Return 3 units with cost 30,000 (e.g. from an earlier sale discount/voucher)
      fifo.returnToInventory(
        productId: 'shoe',
        quantity: 3,
        unitCost: 30000.0,
        returnDate: DateTime(2024, 1, 3),
        storeId: 'store_001',
        transactionId: 'ret_1',
      );

      // Return 2: Return 2 units with cost 20,000
      fifo.returnToInventory(
        productId: 'shoe',
        quantity: 2,
        unitCost: 20000.0,
        returnDate: DateTime(2024, 1, 4),
        storeId: 'store_001',
        transactionId: 'ret_2',
      );

      // Queue state in Store 1:
      // index 0: ret_2 (2 @ 20k)
      // index 1: ret_1 (3 @ 30k)
      // index 2: imp_s1 (10 remaining @ 50k)
      final lots = fifo.getInventoryLots('shoe', storeId: 'store_001');
      expect(lots.length, equals(3));
      expect(lots[0].transactionId, equals('ret_2'));
      expect(lots[0].remainingQuantity, equals(2));
      expect(lots[0].importPrice, equals(20000.0));

      expect(lots[1].transactionId, equals('ret_1'));
      expect(lots[1].remainingQuantity, equals(3));
      expect(lots[1].importPrice, equals(30000.0));

      expect(lots[2].transactionId, equals('imp_s1'));
      expect(lots[2].remainingQuantity, equals(10));
      expect(lots[2].importPrice, equals(50000.0));

      // Next Sale: Sell 7 units
      // Consumption order:
      // 1. 2 from ret_2 @ 20k = 40k
      // 2. 3 from ret_1 @ 30k = 90k
      // 3. 2 from imp_s1 @ 50k = 100k
      // Total expected COGS = 40k + 90k + 100k = 230,000
      final costNext = fifo.calculateCostForSale(
        productId: 'shoe',
        quantity: 7,
        saleDate: DateTime(2024, 1, 5),
        storeId: 'store_001',
      );

      expect(costNext, equals(230000.0));
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(0));
      expect(lots[2].remainingQuantity, equals(8));
      expect(fifo.getRemainingQuantity('shoe', storeId: 'store_001'), equals(8));
    });

    // -------------------------------------------------------------------------
    // CHALLENGE 5: Cases 4 & 5 (Stock Audit Increases and Decreases)
    // -------------------------------------------------------------------------
    test('Cases 4 & 5: Complex alternating stock audits maintain FIFO lot sequence and accurate depletion', () {
      final txs = [
        InventoryTransaction(
          id: 'imp_1',
          productId: 'prod_audit',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Import 1',
          importPrice: 100.0,
          storeId: 'store_001',
        ),
        InventoryTransaction(
          id: 'imp_2',
          productId: 'prod_audit',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 2),
          note: 'Import 2',
          importPrice: 200.0,
          storeId: 'store_001',
        ),
        // Case 5: Audit shrinkage: deduct 15 units (10 from imp_1 + 5 from imp_2)
        InventoryTransaction(
          id: 'audit_neg',
          productId: 'prod_audit',
          type: TransactionType.inventoryAudit,
          quantity: 15,
          date: DateTime(2024, 1, 3),
          note: 'Audit negative',
          importPrice: 100.0,
          storeId: 'store_001',
          isAuditNegative: true,
          auditDifference: -15,
        ),
        // Case 4: Audit increase: found 8 units @ 250.0
        InventoryTransaction(
          id: 'audit_pos',
          productId: 'prod_audit',
          type: TransactionType.inventoryAudit,
          quantity: 8,
          date: DateTime(2024, 1, 4),
          note: 'Audit positive',
          importPrice: 250.0,
          storeId: 'store_001',
          isAuditNegative: false,
          auditDifference: 8,
        ),
      ];

      final fifo = FifoCalculator(txs);
      final lots = fifo.getInventoryLots('prod_audit', storeId: 'store_001');

      // Remaining lots:
      // imp_1: 0 left
      // imp_2: 5 left @ 200.0
      // audit_pos: 8 left @ 250.0
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(5));
      expect(lots[2].remainingQuantity, equals(8));
      expect(fifo.getRemainingQuantity('prod_audit', storeId: 'store_001'), equals(13));

      // Sale of 7 units: 5 @ 200.0 + 2 @ 250.0 = 1000 + 500 = 1500.0
      final cost = fifo.calculateCostForSale(
        productId: 'prod_audit',
        quantity: 7,
        saleDate: DateTime(2024, 1, 5),
        storeId: 'store_001',
      );

      expect(cost, equals(1500.0));
      expect(lots[1].remainingQuantity, equals(0));
      expect(lots[2].remainingQuantity, equals(6));
    });

    // -------------------------------------------------------------------------
    // CHALLENGE 6: High-Volume Randomized Invariant Oracle Harness (2,000 Ops)
    // -------------------------------------------------------------------------
    test('Randomized 2,000 Operations Stress Harness maintains FIFO and Inventory Invariants', () {
      final rng = Random(42);
      final fifo = FifoCalculator();
      final stores = ['store_001', 'store_002', 'custom_store_003'];
      final products = ['prod_alpha', 'prod_beta', 'prod_gamma'];

      // Simple ground truth lot structure for oracle
      final Map<String, Map<String, List<Map<String, dynamic>>>> oracle = {
        for (final s in stores) s: {for (final p in products) p: []}
      };

      for (int i = 0; i < 2000; i++) {
        final storeId = stores[rng.nextInt(stores.length)];
        final productId = products[rng.nextInt(products.length)];
        final op = rng.nextInt(5); // 0: Import, 1: Sale, 2: Return, 3: Transfer, 4: Reset check

        switch (op) {
          case 0: // Import
            final qty = rng.nextInt(50) + 1;
            final price = (rng.nextInt(100) + 1) * 1000.0;
            fifo.addInventoryLot(
              productId,
              InventoryLot(
                transactionId: 'tx_rand_imp_$i',
                importDate: DateTime(2024, 1, 1).add(Duration(hours: i)),
                importPrice: price,
                remainingQuantity: qty,
                storeId: storeId,
              ),
              storeId: storeId,
            );
            oracle[storeId]![productId]!.add({
              'price': price,
              'qty': qty,
            });
            break;

          case 1: // Sale
            final qty = rng.nextInt(30) + 1;
            const fallback = 15000.0;

            // Oracle calculation
            double oracleCost = 0.0;
            int rem = qty;
            final oLots = oracle[storeId]![productId]!;
            for (final lot in oLots) {
              if (rem <= 0) break;
              final lotQty = lot['qty'] as int;
              if (lotQty <= 0) continue;
              final take = min(rem, lotQty);
              oracleCost += take * (lot['price'] as double);
              lot['qty'] = lotQty - take;
              rem -= take;
            }
            if (rem > 0) {
              oracleCost += rem * fallback;
            }

            final actualCost = fifo.calculateCostForSale(
              productId: productId,
              quantity: qty,
              saleDate: DateTime(2024, 1, 1).add(Duration(hours: i)),
              storeId: storeId,
              fallbackCostPrice: fallback,
            );

            expect(actualCost, closeTo(oracleCost, 0.001),
                reason: 'Cost mismatch at op $i on $storeId - $productId');
            break;

          case 2: // Return
            final qty = rng.nextInt(10) + 1;
            final price = (rng.nextInt(50) + 1) * 1000.0;
            fifo.returnToInventory(
              productId: productId,
              quantity: qty,
              unitCost: price,
              returnDate: DateTime(2024, 1, 1).add(Duration(hours: i)),
              storeId: storeId,
              transactionId: 'tx_rand_ret_$i',
            );
            oracle[storeId]![productId]!.insert(0, {
              'price': price,
              'qty': qty,
            });
            break;

          case 3: // Transfer
            final targetStore = stores[(stores.indexOf(storeId) + 1) % stores.length];
            final qty = rng.nextInt(20) + 1;
            const fallback = 10000.0;

            // Oracle transfer
            double oTransferCost = 0.0;
            int remT = qty;
            final sLots = oracle[storeId]![productId]!;
            for (final lot in sLots) {
              if (remT <= 0) break;
              final lotQty = lot['qty'] as int;
              if (lotQty <= 0) continue;
              final take = min(remT, lotQty);
              oTransferCost += take * (lot['price'] as double);
              lot['qty'] = lotQty - take;
              remT -= take;
            }
            if (remT > 0) {
              oTransferCost += remT * fallback;
            }
            final effectiveUnitCost = qty > 0 ? (oTransferCost / qty) : fallback;
            oracle[targetStore]![productId]!.add({
              'price': effectiveUnitCost,
              'qty': qty,
            });

            final actualTransferCost = fifo.transferInventory(
              productId: productId,
              quantity: qty,
              sourceStoreId: storeId,
              targetStoreId: targetStore,
              transferDate: DateTime(2024, 1, 1).add(Duration(hours: i)),
              fallbackCostPrice: fallback,
            );

            expect(actualTransferCost, closeTo(oTransferCost, 0.001),
                reason: 'Transfer cost mismatch at op $i from $storeId to $targetStore');
            break;

          case 4: // Invariant Verification Check
            final expectedQty = oracle[storeId]![productId]!
                .fold<int>(0, (sum, lot) => sum + (lot['qty'] as int));
            final actualQty = fifo.getRemainingQuantity(productId, storeId: storeId);
            expect(actualQty, equals(expectedQty),
                reason: 'Quantity mismatch at op $i on $storeId - $productId');

            // Assert Zero Negative Lot invariant
            final lots = fifo.getInventoryLots(productId, storeId: storeId);
            for (final lot in lots) {
              expect(lot.remainingQuantity >= 0, isTrue,
                  reason: 'Negative lot detected at op $i on $storeId - $productId');
            }
            break;
        }
      }
    });

    // -------------------------------------------------------------------------
    // CHALLENGE 7: Degenerate & Boundary Inputs
    // -------------------------------------------------------------------------
    test('Degenerate boundary conditions (zero qty, negative qty, missing product, alias variations)', () {
      final fifo = FifoCalculator();

      // Zero and negative sale quantities
      expect(fifo.calculateCostForSale(
        productId: 'none',
        quantity: 0,
        saleDate: DateTime.now(),
      ), equals(0.0));

      expect(fifo.calculateCostForSale(
        productId: 'none',
        quantity: -10,
        saleDate: DateTime.now(),
      ), equals(0.0));

      // Zero quantity return does nothing
      fifo.returnToInventory(
        productId: 'none',
        quantity: 0,
        unitCost: 1000.0,
      );
      expect(fifo.getRemainingQuantity('none'), equals(0));

      // Zero quantity transfer returns 0
      final zeroTransfer = fifo.transferInventory(
        productId: 'none',
        quantity: 0,
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
      );
      expect(zeroTransfer, equals(0.0));

      // Store aliases with whitespace and casing
      expect(FifoCalculator.normalizeStoreKey('  branch_1  '), equals('store_001'));
      expect(FifoCalculator.normalizeStoreKey('  TB  '), equals('store_002'));
      expect(FifoCalculator.normalizeStoreKey(''), equals('default'));
      expect(FifoCalculator.normalizeStoreKey(null), equals('default'));
    });

    // -------------------------------------------------------------------------
    // CHALLENGE 8: Cyclic Transfers Between Stores (A -> B -> A)
    // -------------------------------------------------------------------------
    test('Cyclic transfer A -> B -> A maintains accurate cost basis and queue ordering', () {
      final fifo = FifoCalculator();

      // Store A has 10 @ 100k
      fifo.initializeInventoryTracker([
        InventoryTransaction(
          id: 'imp_A',
          productId: 'cyclic_item',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Store A initial',
          importPrice: 100000.0,
          storeId: 'store_001',
        ),
      ]);

      // Transfer 6 from Store A to Store B
      final costAB = fifo.transferInventory(
        productId: 'cyclic_item',
        quantity: 6,
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        transferDate: DateTime(2024, 1, 2),
      );
      expect(costAB, equals(600000.0));
      expect(fifo.getRemainingQuantity('cyclic_item', storeId: 'store_001'), equals(4));
      expect(fifo.getRemainingQuantity('cyclic_item', storeId: 'store_002'), equals(6));

      // Store B sells 2 @ 100k = 200k
      final costB = fifo.calculateCostForSale(
        productId: 'cyclic_item',
        quantity: 2,
        saleDate: DateTime(2024, 1, 3),
        storeId: 'store_002',
      );
      expect(costB, equals(200000.0));
      expect(fifo.getRemainingQuantity('cyclic_item', storeId: 'store_002'), equals(4));

      // Transfer 2 back from Store B to Store A
      final costBA = fifo.transferInventory(
        productId: 'cyclic_item',
        quantity: 2,
        sourceStoreId: 'store_002',
        targetStoreId: 'store_001',
        transferDate: DateTime(2024, 1, 4),
      );
      expect(costBA, equals(200000.0));
      expect(fifo.getRemainingQuantity('cyclic_item', storeId: 'store_002'), equals(2));
      expect(fifo.getRemainingQuantity('cyclic_item', storeId: 'store_001'), equals(6));

      // Store A has: original lot (4 left @ 100k) + transfer lot (2 @ 100k)
      final s1Lots = fifo.getInventoryLots('cyclic_item', storeId: 'store_001');
      expect(s1Lots.length, equals(2));
      expect(s1Lots[0].remainingQuantity, equals(4));
      expect(s1Lots[1].remainingQuantity, equals(2));

      // Store A sells 5 units: 4 from original lot @ 100k + 1 from transfer lot @ 100k = 500k
      final costA2 = fifo.calculateCostForSale(
        productId: 'cyclic_item',
        quantity: 5,
        saleDate: DateTime(2024, 1, 5),
        storeId: 'store_001',
      );
      expect(costA2, equals(500000.0));
      expect(s1Lots[0].remainingQuantity, equals(0));
      expect(s1Lots[1].remainingQuantity, equals(1));
      expect(fifo.getRemainingQuantity('cyclic_item', storeId: 'store_001'), equals(1));
    });

    // -------------------------------------------------------------------------
    // CHALLENGE 9: Oversold -> Return -> Sale Cycle
    // -------------------------------------------------------------------------
    test('Oversold followed by customer return correctly prioritizes return lot for immediate resale', () {
      final fifo = FifoCalculator();

      // Zero initial stock -> Oversold sale of 4 items with fallback 50k
      final costOversold = fifo.calculateCostForSale(
        productId: 'oversold_item',
        quantity: 4,
        saleDate: DateTime(2024, 1, 1),
        storeId: 'store_001',
        fallbackCostPrice: 50000.0,
      );
      expect(costOversold, equals(200000.0));
      expect(fifo.getRemainingQuantity('oversold_item', storeId: 'store_001'), equals(0));

      // Customer returns 2 items with unit cost 45k
      fifo.returnToInventory(
        productId: 'oversold_item',
        quantity: 2,
        unitCost: 45000.0,
        returnDate: DateTime(2024, 1, 2),
        storeId: 'store_001',
        transactionId: 'ret_oversold',
      );
      expect(fifo.getRemainingQuantity('oversold_item', storeId: 'store_001'), equals(2));

      // Next sale of 1 item consumes 1 returned unit @ 45k = 45k
      final costSaleAfterReturn = fifo.calculateCostForSale(
        productId: 'oversold_item',
        quantity: 1,
        saleDate: DateTime(2024, 1, 3),
        storeId: 'store_001',
      );
      expect(costSaleAfterReturn, equals(45000.0));
      expect(fifo.getRemainingQuantity('oversold_item', storeId: 'store_001'), equals(1));
    });

    // -------------------------------------------------------------------------
    // CHALLENGE 10: Fallback Cost Price Hierarchy Resolution
    // -------------------------------------------------------------------------
    test('Fallback cost resolution hierarchy when fallbackCostPrice is omitted', () {
      final fifo = FifoCalculator();

      // Case A: Exhaust existing lot (1 @ 77,000) then oversell 2 more with null fallbackCostPrice
      fifo.addInventoryLot(
        'item_hier',
        InventoryLot(
          transactionId: 'hier_1',
          importDate: DateTime(2024, 1, 1),
          importPrice: 77000.0,
          remainingQuantity: 1,
          storeId: 'store_001',
        ),
        storeId: 'store_001',
      );

      // Sale of 3 items (1 from lot @ 77k + 2 oversold @ lastKnownLotPrice 77k = 231,000)
      final costA = fifo.calculateCostForSale(
        productId: 'item_hier',
        quantity: 3,
        saleDate: DateTime(2024, 1, 2),
        storeId: 'store_001',
        fallbackCostPrice: null,
      );
      expect(costA, equals(231000.0));

      // Case B: Completely unknown product with null fallbackCostPrice -> defaults to 0.0
      final costB = fifo.calculateCostForSale(
        productId: 'completely_unknown_item',
        quantity: 5,
        saleDate: DateTime(2024, 1, 2),
        storeId: 'store_001',
        fallbackCostPrice: null,
      );
      expect(costB, equals(0.0));
    });
  });
}
