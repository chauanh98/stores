import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';

void main() {
  group('FifoCalculator Tests', () {
    late List<InventoryTransaction> importTransactions;

    setUp(() {
      // Tạo dữ liệu test: Nhập hàng theo ví dụ chuẩn
      importTransactions = [
        InventoryTransaction(
          id: 'import1',
          productId: 'product1',
          type: TransactionType.import,
          quantity: 5,
          date: DateTime(2024, 1, 1),
          note: 'Nhập lô đầu tiên',
          importPrice: 10000, // 10k
        ),
        InventoryTransaction(
          id: 'import2',
          productId: 'product1',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 2),
          note: 'Nhập lô thứ hai',
          importPrice: 12000, // 12k
        ),
      ];
    });

    test('Test FIFO calculation - Bán 6 cái từ lô đầu tiên', () {
      final tracker = FifoCalculator(importTransactions);

      // Bán 6 cái: 5 cái giá 10k + 1 cái giá 12k = 50k + 12k = 62k
      final cost = tracker.calculateCostForSale(
        productId: 'product1',
        quantity: 6,
        saleDate: DateTime(2024, 1, 3),
      );

      expect(cost, equals(62000)); // 5*10k + 1*12k = 62k

      final inventoryLots = tracker.getInventoryLots('product1');
      expect(inventoryLots.length, equals(2));
      expect(inventoryLots[0].remainingQuantity, equals(0)); // Lô đầu tiên hết
      expect(inventoryLots[1].remainingQuantity, equals(9)); // Lô thứ hai còn 9 cái
    });

    test('Test FIFO calculation - Bán tiếp 3 cái từ lô thứ hai', () {
      final tracker = FifoCalculator(importTransactions);

      // Bán 6 cái đầu tiên
      tracker.calculateCostForSale(
        productId: 'product1',
        quantity: 6,
        saleDate: DateTime(2024, 1, 3),
      );

      // Bán tiếp 3 cái: 3 cái giá 12k = 36k
      final cost = tracker.calculateCostForSale(
        productId: 'product1',
        quantity: 3,
        saleDate: DateTime(2024, 1, 3),
      );

      expect(cost, equals(36000)); // 3*12k = 36k

      final inventoryLots = tracker.getInventoryLots('product1');
      expect(inventoryLots.length, equals(2));
      expect(inventoryLots[0].remainingQuantity, equals(0)); // Lô đầu tiên hết
      expect(inventoryLots[1].remainingQuantity, equals(6)); // Lô thứ hai còn 6 cái
    });

    test('Test FIFO calculation - Bán nhiều lần trong cùng ngày', () {
      final tracker = FifoCalculator(importTransactions);

      final cost1 = tracker.calculateCostForSale(
        productId: 'product1',
        quantity: 6,
        saleDate: DateTime(2024, 1, 3),
      );

      final cost2 = tracker.calculateCostForSale(
        productId: 'product1',
        quantity: 3,
        saleDate: DateTime(2024, 1, 3),
      );

      expect(cost1, equals(62000));
      expect(cost2, equals(36000));
      expect(cost1 + cost2, equals(98000));

      final inventoryLots = tracker.getInventoryLots('product1');
      expect(inventoryLots[0].remainingQuantity, equals(0));
      expect(inventoryLots[1].remainingQuantity, equals(6));
    });

    test('Test FIFO calculation - Bán vượt quá inventory with fallback', () {
      final tracker = FifoCalculator(importTransactions);

      // Bán 20 cái (vượt quá inventory có 15 cái), fallback cost price = 15000
      final cost = tracker.calculateCostForSale(
        productId: 'product1',
        quantity: 20,
        saleDate: DateTime(2024, 1, 3),
        fallbackCostPrice: 15000,
      );

      // 5*10k + 10*12k + 5*15k = 50k + 120k + 75k = 245k
      expect(cost, equals(245000));

      final inventoryLots = tracker.getInventoryLots('product1');
      expect(inventoryLots[0].remainingQuantity, equals(0));
      expect(inventoryLots[1].remainingQuantity, equals(0));
    });

    test('Test FIFO calculation - Instance isolation (No global state conflict)', () {
      final tracker1 = FifoCalculator(importTransactions);
      final tracker2 = FifoCalculator([
        InventoryTransaction(
          id: 'imp_other',
          productId: 'product1',
          type: TransactionType.import,
          quantity: 20,
          date: DateTime(2024, 1, 1),
          note: 'Nhập lô kho khác',
          importPrice: 8000,
        ),
      ]);

      // Tracker 1 bán 5 cái -> 5*10k = 50k
      final cost1 = tracker1.calculateCostForSale(
        productId: 'product1',
        quantity: 5,
        saleDate: DateTime(2024, 1, 2),
      );
      expect(cost1, equals(50000));

      // Tracker 2 bán 5 cái -> 5*8k = 40k
      final cost2 = tracker2.calculateCostForSale(
        productId: 'product1',
        quantity: 5,
        saleDate: DateTime(2024, 1, 2),
      );
      expect(cost2, equals(40000));

      // Đảm bảo không bị ảnh hưởng lẫn nhau
      expect(tracker1.getInventoryLots('product1')[0].remainingQuantity, equals(0));
      expect(tracker2.getInventoryLots('product1')[0].remainingQuantity, equals(15));
    });

    test('Test FIFO calculation - Fallback cost price when no import transaction', () {
      final tracker = FifoCalculator();

      // Product không có lô nhập nào, fallback cost price là 25000
      final cost = tracker.calculateCostForSale(
        productId: 'product_no_imports',
        quantity: 4,
        saleDate: DateTime(2024, 1, 1),
        fallbackCostPrice: 25000,
      );

      expect(cost, equals(100000)); // 4 * 25k = 100k
    });

    test('Test FIFO calculation - Multi-day sequential lot depletion', () {
      // Giả lập tính toán multi-day: Day 1 bán hết lô 1, Day 2 bán tiếp sang lô 2
      final multiDayTracker = FifoCalculator(importTransactions);

      // Day 1: Bán 5 cái -> rút hết lô 1 (5*10k = 50k)
      final day1Cost = multiDayTracker.calculateCostForSale(
        productId: 'product1',
        quantity: 5,
        saleDate: DateTime(2024, 1, 3),
      );
      expect(day1Cost, equals(50000));
      expect(multiDayTracker.getInventoryLots('product1')[0].remainingQuantity, equals(0));
      expect(multiDayTracker.getInventoryLots('product1')[1].remainingQuantity, equals(10));

      // Day 2: Bán tiếp 4 cái -> rút từ lô 2 (4*12k = 48k), không bị reset lô 1!
      final day2Cost = multiDayTracker.calculateCostForSale(
        productId: 'product1',
        quantity: 4,
        saleDate: DateTime(2024, 1, 4),
      );
      expect(day2Cost, equals(48000));
      expect(multiDayTracker.getInventoryLots('product1')[1].remainingQuantity, equals(6));
    });

    test('Test profit margin calculation', () {
      final margin1 = FifoCalculator.calculateProfitMargin(100000, 62000); // Revenue 100k, Cost 62k
      expect(margin1, equals(38.0)); // (100k-62k)/100k * 100 = 38%

      final margin2 = FifoCalculator.calculateProfitMargin(50000, 50000); // Revenue 50k, Cost 50k
      expect(margin2, equals(0.0)); // No profit

      final margin3 = FifoCalculator.calculateProfitMargin(0, 10000); // Revenue 0
      expect(margin3, equals(0.0)); // No revenue

      final margin4 = FifoCalculator.calculateProfitMargin(-100, 50); // Negative revenue
      expect(margin4, equals(0.0));
    });

    test('Test FIFO calculation with positive Inventory Audit (+)', () {
      // 1. Initial import: 10 items @ 10,000
      // 2. Direct stock adjustment increase (+5 items) @ 12,000
      final txs = [
        InventoryTransaction(
          id: 'imp_1',
          productId: 'prod_audit_1',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Nhập lô 1',
          importPrice: 10000,
        ),
        InventoryTransaction(
          id: 'audit_1',
          productId: 'prod_audit_1',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: DateTime(2024, 1, 2),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 15, chênh lệch: +5)',
          importPrice: 12000,
        ),
      ];

      final calculator = FifoCalculator(txs);
      final lots = calculator.getInventoryLots('prod_audit_1');
      expect(lots.length, equals(2));
      expect(lots[0].remainingQuantity, equals(10));
      expect(lots[0].importPrice, equals(10000));
      expect(lots[0].unitCost, equals(10000));
      expect(lots[1].remainingQuantity, equals(5));
      expect(lots[1].importPrice, equals(12000));
      expect(lots[1].unitCost, equals(12000));

      // Bán 12 cái: 10 cái từ lô 1 (10*10k = 100k) + 2 cái từ lô audit (2*12k = 24k) = 124k
      final cost = calculator.calculateCostForSale(
        productId: 'prod_audit_1',
        quantity: 12,
        saleDate: DateTime(2024, 1, 3),
      );

      expect(cost, equals(124000));
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(3));
    });

    test('Test FIFO calculation with negative Inventory Audit (-)', () {
      // 1. Initial import: 10 items @ 10,000
      // 2. Second import: 10 items @ 15,000
      // 3. Direct stock adjustment decrease (-5 items due to damage)
      final txs = [
        InventoryTransaction(
          id: 'imp_1',
          productId: 'prod_audit_2',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 1),
          note: 'Nhập lô 1',
          importPrice: 10000,
        ),
        InventoryTransaction(
          id: 'imp_2',
          productId: 'prod_audit_2',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 2),
          note: 'Nhập lô 2',
          importPrice: 15000,
        ),
        InventoryTransaction(
          id: 'audit_neg',
          productId: 'prod_audit_2',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: DateTime(2024, 1, 3),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 20 -> Tồn mới: 15, chênh lệch: -5)',
          importPrice: 10000,
        ),
      ];

      final calculator = FifoCalculator(txs);
      final lots = calculator.getInventoryLots('prod_audit_2');
      expect(lots.length, equals(2));
      // FIFO order: first lot was reduced from 10 to 5
      expect(lots[0].remainingQuantity, equals(5));
      expect(lots[1].remainingQuantity, equals(10));

      // Bán 7 cái: 5 cái còn lại của lô 1 (5*10k = 50k) + 2 cái từ lô 2 (2*15k = 30k) = 80k
      final cost = calculator.calculateCostForSale(
        productId: 'prod_audit_2',
        quantity: 7,
        saleDate: DateTime(2024, 1, 4),
      );

      expect(cost, equals(80000));
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(8));
    });

    test('Test FIFO calculation with negative audit exhausting first lot and reducing second lot', () {
      final txs = [
        InventoryTransaction(
          id: 'imp_1',
          productId: 'prod_audit_3',
          type: TransactionType.import,
          quantity: 4,
          date: DateTime(2024, 1, 1),
          note: 'Nhập lô 1',
          importPrice: 10000,
        ),
        InventoryTransaction(
          id: 'imp_2',
          productId: 'prod_audit_3',
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2024, 1, 2),
          note: 'Nhập lô 2',
          importPrice: 20000,
        ),
        InventoryTransaction(
          id: 'audit_neg',
          productId: 'prod_audit_3',
          type: TransactionType.inventoryAudit,
          quantity: 6, // 4 from lot 1 + 2 from lot 2
          date: DateTime(2024, 1, 3),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 14 -> Tồn mới: 8, chênh lệch: -6)',
          importPrice: 15000,
        ),
      ];

      final calculator = FifoCalculator(txs);
      final lots = calculator.getInventoryLots('prod_audit_3');
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(8));

      // Bán 3 cái từ lô 2: 3 * 20k = 60k
      final cost = calculator.calculateCostForSale(
        productId: 'prod_audit_3',
        quantity: 3,
        saleDate: DateTime(2024, 1, 4),
      );
      expect(cost, equals(60000));
      expect(lots[1].remainingQuantity, equals(5));
    });
  });
}
