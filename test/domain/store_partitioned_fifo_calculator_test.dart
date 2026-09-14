import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';

void main() {
  group('Store-Partitioned FifoCalculator Tests (F8)', () {
    late List<InventoryTransaction> mixedStoreTransactions;

    setUp(() {
      mixedStoreTransactions = [
        // Store 001 (Đông Thắng) - 2 imports for prod_A at 10,000 and 12,000
        InventoryTransaction(
          id: 'tx_s1_imp1',
          productId: 'prod_A',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Store 1 Import 1',
          importPrice: 10000.0,
          storeId: 'store_001',
        ),
        InventoryTransaction(
          id: 'tx_s1_imp2',
          productId: 'prod_A',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 3),
          note: 'Store 1 Import 2',
          importPrice: 12000.0,
          storeId: 'store_001',
        ),

        // Store 002 (Thới Bình) - 2 imports for prod_A at 15,000 and 18,000
        InventoryTransaction(
          id: 'tx_s2_imp1',
          productId: 'prod_A',
          type: TransactionType.import,
          quantity: 5,
          date: DateTime(2024, 1, 2),
          note: 'Store 2 Import 1',
          importPrice: 15000.0,
          storeId: 'store_002',
        ),
        InventoryTransaction(
          id: 'tx_s2_imp2',
          productId: 'prod_A',
          type: TransactionType.import,
          quantity: 15,
          date: DateTime(2024, 1, 4),
          note: 'Store 2 Import 2',
          importPrice: 18000.0,
          storeId: 'store_002',
        ),
      ];
    });

    test('Store isolation: queues and lots are completely isolated between store_001 and store_002', () {
      final fifo = FifoCalculator(mixedStoreTransactions);

      // Verify store_001 lots
      final s1Lots = fifo.getInventoryLots('prod_A', storeId: 'store_001');
      expect(s1Lots.length, equals(2));
      expect(s1Lots[0].remainingQuantity, equals(10));
      expect(s1Lots[0].importPrice, equals(10000.0));
      expect(s1Lots[1].remainingQuantity, equals(10));
      expect(s1Lots[1].importPrice, equals(12000.0));
      expect(fifo.getRemainingQuantity('prod_A', storeId: 'store_001'), equals(20));

      // Verify store_002 lots
      final s2Lots = fifo.getInventoryLots('prod_A', storeId: 'store_002');
      expect(s2Lots.length, equals(2));
      expect(s2Lots[0].remainingQuantity, equals(5));
      expect(s2Lots[0].importPrice, equals(15000.0));
      expect(s2Lots[1].remainingQuantity, equals(15));
      expect(s2Lots[1].importPrice, equals(18000.0));
      expect(fifo.getRemainingQuantity('prod_A', storeId: 'store_002'), equals(20));
    });

    test('Sale in store_001 consumes only store_001 lots without affecting store_002', () {
      final fifo = FifoCalculator(mixedStoreTransactions);

      // Sale 12 units at store_001: 10 units @ 10,000 + 2 units @ 12,000 = 100,000 + 24,000 = 124,000
      final costS1 = fifo.calculateCostForSale(
        productId: 'prod_A',
        quantity: 12,
        saleDate: DateTime(2024, 1, 5),
        storeId: 'store_001',
      );

      expect(costS1, equals(124000.0));

      // store_001 lot state: lot 1 exhausted, lot 2 has 8 left
      final s1Lots = fifo.getInventoryLots('prod_A', storeId: 'store_001');
      expect(s1Lots[0].remainingQuantity, equals(0));
      expect(s1Lots[1].remainingQuantity, equals(8));
      expect(fifo.getRemainingQuantity('prod_A', storeId: 'store_001'), equals(8));

      // store_002 lot state must be 100% UNTOUCHED (5 + 15 = 20)
      final s2Lots = fifo.getInventoryLots('prod_A', storeId: 'store_002');
      expect(s2Lots[0].remainingQuantity, equals(5));
      expect(s2Lots[1].remainingQuantity, equals(15));
      expect(fifo.getRemainingQuantity('prod_A', storeId: 'store_002'), equals(20));

      // Now sell 6 units at store_002: 5 units @ 15,000 + 1 unit @ 18,000 = 75,000 + 18,000 = 93,000
      final costS2 = fifo.calculateCostForSale(
        productId: 'prod_A',
        quantity: 6,
        saleDate: DateTime(2024, 1, 6),
        storeId: 'store_002',
      );

      expect(costS2, equals(93000.0));
      expect(s2Lots[0].remainingQuantity, equals(0));
      expect(s2Lots[1].remainingQuantity, equals(14));
      expect(fifo.getRemainingQuantity('prod_A', storeId: 'store_002'), equals(14));
    });

    test('Store key normalization handles aliases correctly', () {
      expect(FifoCalculator.normalizeStoreKey('branch_1'), equals('store_001'));
      expect(FifoCalculator.normalizeStoreKey('ĐT'), equals('store_001'));
      expect(FifoCalculator.normalizeStoreKey('Chi nhánh Đông Thắng'), equals('store_001'));
      expect(FifoCalculator.normalizeStoreKey('đông thắng'), equals('store_001'));

      expect(FifoCalculator.normalizeStoreKey('branch_2'), equals('store_002'));
      expect(FifoCalculator.normalizeStoreKey('TB'), equals('store_002'));
      expect(FifoCalculator.normalizeStoreKey('Chi nhánh Thới Bình'), equals('store_002'));
      expect(FifoCalculator.normalizeStoreKey('thới bình'), equals('store_002'));

      expect(FifoCalculator.normalizeStoreKey(null), equals('default'));
      expect(FifoCalculator.normalizeStoreKey(''), equals('default'));
      expect(FifoCalculator.normalizeStoreKey('custom_store_99'), equals('custom_store_99'));
    });

    test('Alias lookups match partitioned stores', () {
      final fifo = FifoCalculator(mixedStoreTransactions);

      // Accessing with 'branch_1' alias
      final lotsBranch1 = fifo.getInventoryLots('prod_A', storeId: 'branch_1');
      expect(lotsBranch1.length, equals(2));
      expect(lotsBranch1[0].importPrice, equals(10000.0));

      // Accessing with 'TB' alias
      final lotsTB = fifo.getInventoryLots('prod_A', storeId: 'TB');
      expect(lotsTB.length, equals(2));
      expect(lotsTB[0].importPrice, equals(15000.0));
    });

    test('Resetting specific store partition leaves other stores intact', () {
      final fifo = FifoCalculator(mixedStoreTransactions);

      fifo.resetInventoryTracker(storeId: 'store_001');

      expect(fifo.getInventoryLots('prod_A', storeId: 'store_001'), isEmpty);
      expect(fifo.hasAvailableLots('prod_A', storeId: 'store_001'), isFalse);

      expect(fifo.getInventoryLots('prod_A', storeId: 'store_002').length, equals(2));
      expect(fifo.hasAvailableLots('prod_A', storeId: 'store_002'), isTrue);
      expect(fifo.getRemainingQuantity('prod_A', storeId: 'store_002'), equals(20));

      // Global reset
      fifo.resetInventoryTracker();
      expect(fifo.getInventoryLots('prod_A', storeId: 'store_002'), isEmpty);
    });

    test('Manual lot addition respects store partition', () {
      final fifo = FifoCalculator();

      fifo.addInventoryLot(
        'prod_manual',
        InventoryLot(
          transactionId: 'manual_s1',
          importDate: DateTime(2024, 1, 1),
          importPrice: 50000.0,
          remainingQuantity: 7,
          storeId: 'store_001',
        ),
        storeId: 'store_001',
      );

      fifo.addInventoryLot(
        'prod_manual',
        InventoryLot(
          transactionId: 'manual_s2',
          importDate: DateTime(2024, 1, 1),
          importPrice: 60000.0,
          remainingQuantity: 3,
          storeId: 'store_002',
        ),
        storeId: 'store_002',
      );

      expect(fifo.getRemainingQuantity('prod_manual', storeId: 'store_001'), equals(7));
      expect(fifo.getRemainingQuantity('prod_manual', storeId: 'store_002'), equals(3));

      final cost = fifo.calculateCostForSale(
        productId: 'prod_manual',
        quantity: 2,
        saleDate: DateTime(2024, 1, 2),
        storeId: 'store_001',
      );

      expect(cost, equals(100000.0));
      expect(fifo.getRemainingQuantity('prod_manual', storeId: 'store_001'), equals(5));
      expect(fifo.getRemainingQuantity('prod_manual', storeId: 'store_002'), equals(3));
    });
  });
}
