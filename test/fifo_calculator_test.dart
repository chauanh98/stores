import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';

void main() {
  group('FifoCalculator Tests', () {
    late List<InventoryTransaction> importTransactions;

    setUp(() {
      // Reset inventory tracker trước mỗi test
      FifoCalculator.resetInventoryTracker();
      
      // Tạo dữ liệu test: Nhập hàng theo ví dụ của bạn
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
      // Khởi tạo inventory tracker
      FifoCalculator.initializeInventoryTracker(importTransactions);

      // Bán 6 cái: 5 cái giá 10k + 1 cái giá 12k = 50k + 12k = 62k
      final cost = FifoCalculator.calculateCostForSale(
        productId: 'product1',
        quantity: 6,
        saleDate: DateTime(2024, 1, 3),
      );

      expect(cost, equals(62000)); // 5*10k + 1*12k = 62k

      // Kiểm tra inventory còn lại
      final inventoryLots = FifoCalculator.getInventoryLots('product1');
      expect(inventoryLots.length, equals(2));
      expect(inventoryLots[0].remainingQuantity, equals(0)); // Lô đầu tiên hết
      expect(inventoryLots[1].remainingQuantity, equals(9)); // Lô thứ hai còn 9 cái
    });

    test('Test FIFO calculation - Bán tiếp 3 cái từ lô thứ hai', () {
      // Khởi tạo inventory tracker
      FifoCalculator.initializeInventoryTracker(importTransactions);

      // Bán 6 cái đầu tiên
      FifoCalculator.calculateCostForSale(
        productId: 'product1',
        quantity: 6,
        saleDate: DateTime(2024, 1, 3),
      );

      // Bán tiếp 3 cái: 3 cái giá 12k = 36k
      final cost = FifoCalculator.calculateCostForSale(
        productId: 'product1',
        quantity: 3,
        saleDate: DateTime(2024, 1, 3),
      );

      expect(cost, equals(36000)); // 3*12k = 36k

      // Kiểm tra inventory còn lại
      final inventoryLots = FifoCalculator.getInventoryLots('product1');
      expect(inventoryLots.length, equals(2));
      expect(inventoryLots[0].remainingQuantity, equals(0)); // Lô đầu tiên hết
      expect(inventoryLots[1].remainingQuantity, equals(6)); // Lô thứ hai còn 6 cái
    });

    test('Test FIFO calculation - Bán nhiều lần trong cùng ngày', () {
      // Khởi tạo inventory tracker
      FifoCalculator.initializeInventoryTracker(importTransactions);

      // Bán 6 cái lần 1: 5*10k + 1*12k = 62k
      final cost1 = FifoCalculator.calculateCostForSale(
        productId: 'product1',
        quantity: 6,
        saleDate: DateTime(2024, 1, 3),
      );

      // Bán 3 cái lần 2: 3*12k = 36k
      final cost2 = FifoCalculator.calculateCostForSale(
        productId: 'product1',
        quantity: 3,
        saleDate: DateTime(2024, 1, 3),
      );

      expect(cost1, equals(62000));
      expect(cost2, equals(36000));

      // Tổng cost: 62k + 36k = 98k
      expect(cost1 + cost2, equals(98000));

      // Kiểm tra inventory còn lại
      final inventoryLots = FifoCalculator.getInventoryLots('product1');
      expect(inventoryLots[0].remainingQuantity, equals(0)); // Lô đầu tiên hết
      expect(inventoryLots[1].remainingQuantity, equals(6)); // Lô thứ hai còn 6 cái
    });

    test('Test FIFO calculation - Bán vượt quá inventory', () {
      // Khởi tạo inventory tracker
      FifoCalculator.initializeInventoryTracker(importTransactions);

      // Bán 20 cái (vượt quá inventory có 15 cái)
      final cost = FifoCalculator.calculateCostForSale(
        productId: 'product1',
        quantity: 20,
        saleDate: DateTime(2024, 1, 3),
      );

      // Cost = 5*10k + 10*12k + 5*12k (dùng giá cuối cùng) = 50k + 120k + 60k = 230k
      expect(cost, equals(230000));

      // Kiểm tra inventory còn lại
      final inventoryLots = FifoCalculator.getInventoryLots('product1');
      expect(inventoryLots[0].remainingQuantity, equals(0)); // Lô đầu tiên hết
      expect(inventoryLots[1].remainingQuantity, equals(0)); // Lô thứ hai hết
    });

    test('Test profit margin calculation', () {
      final margin1 = FifoCalculator.calculateProfitMargin(100000, 62000); // Revenue 100k, Cost 62k
      expect(margin1, equals(38.0)); // (100k-62k)/100k * 100 = 38%

      final margin2 = FifoCalculator.calculateProfitMargin(50000, 50000); // Revenue 50k, Cost 50k
      expect(margin2, equals(0.0)); // No profit

      final margin3 = FifoCalculator.calculateProfitMargin(0, 10000); // Revenue 0
      expect(margin3, equals(0.0)); // No revenue
    });
  });
}
