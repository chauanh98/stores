import '../../domain/entities/inventory_transaction.dart';
import '../../domain/entities/transaction_type.dart';

/// Class để theo dõi inventory còn lại của từng lô nhập
class InventoryLot {
  final String transactionId;
  final DateTime importDate;
  final double importPrice;
  int remainingQuantity;

  InventoryLot({
    required this.transactionId,
    required this.importDate,
    required this.importPrice,
    required this.remainingQuantity,
  });
}

class FifoCalculator {
  /// Map để theo dõi inventory còn lại của từng sản phẩm
  static final Map<String, List<InventoryLot>> _inventoryTracker = {};

  /// Khởi tạo inventory tracker từ các giao dịch import
  static void initializeInventoryTracker(List<InventoryTransaction> importTransactions) {
    _inventoryTracker.clear();
    
    // Lọc và sắp xếp các giao dịch import
    final imports = importTransactions
        .where((t) => t.type == TransactionType.import)
        .toList();
    imports.sort((a, b) => a.date.compareTo(b.date));

    // Tạo inventory lots cho từng sản phẩm
    for (final import in imports) {
      _inventoryTracker.putIfAbsent(import.productId, () => []);
      _inventoryTracker[import.productId]!.add(InventoryLot(
        transactionId: import.id,
        importDate: import.date,
        importPrice: import.importPrice ?? 0.0,
        remainingQuantity: import.quantity,
      ));
    }
  }

  /// Tính cost của sản phẩm theo nguyên tắc FIFO với inventory tracking
  static double calculateCost({
    required String productId,
    required int quantity,
    required DateTime saleDate,
    required List<InventoryTransaction> importTransactions,
  }) {
    // Khởi tạo inventory tracker nếu chưa có
    if (_inventoryTracker.isEmpty) {
      initializeInventoryTracker(importTransactions);
    }

    final inventoryLots = _inventoryTracker[productId];
    if (inventoryLots == null || inventoryLots.isEmpty) {
      print('Warning: No import data found for product $productId');
      return 0.0;
    }

    double totalCost = 0.0;
    int remainingQuantity = quantity;

    // Tính cost theo FIFO từ các lô còn lại
    for (final lot in inventoryLots) {
      if (remainingQuantity <= 0) break;
      if (lot.remainingQuantity <= 0) continue;

      final usedQuantity = remainingQuantity > lot.remainingQuantity
          ? lot.remainingQuantity
          : remainingQuantity;

      totalCost += usedQuantity * lot.importPrice;
      lot.remainingQuantity -= usedQuantity;
      remainingQuantity -= usedQuantity;
    }

    // Nếu không đủ inventory để tính cost
    if (remainingQuantity > 0) {
      print('Warning: Not enough inventory for product $productId, remaining: $remainingQuantity');
      // Có thể dùng giá trung bình hoặc giá cuối cùng
      final lastLot = inventoryLots.last;
      totalCost += remainingQuantity * lastLot.importPrice;
    }

    return totalCost;
  }

  /// Tính cost cho một lần bán cụ thể (dùng khi có nhiều lần bán trong ngày)
  static double calculateCostForSale({
    required String productId,
    required int quantity,
    required DateTime saleDate,
  }) {
    final inventoryLots = _inventoryTracker[productId];
    if (inventoryLots == null || inventoryLots.isEmpty) {
      print('Warning: No inventory data for product $productId');
      return 0.0;
    }

    double totalCost = 0.0;
    int remainingQuantity = quantity;

    // Tính cost theo FIFO từ các lô còn lại
    for (final lot in inventoryLots) {
      if (remainingQuantity <= 0) break;
      if (lot.remainingQuantity <= 0) continue;

      final usedQuantity = remainingQuantity > lot.remainingQuantity
          ? lot.remainingQuantity
          : remainingQuantity;

      totalCost += usedQuantity * lot.importPrice;
      lot.remainingQuantity -= usedQuantity;
      remainingQuantity -= usedQuantity;
    }

    // Nếu không đủ inventory
    if (remainingQuantity > 0) {
      print('Warning: Not enough inventory for product $productId, remaining: $remainingQuantity');
      final lastLot = inventoryLots.last;
      totalCost += remainingQuantity * lastLot.importPrice;
    }

    return totalCost;
  }

  /// Reset inventory tracker (dùng khi tính toán lại từ đầu)
  static void resetInventoryTracker() {
    _inventoryTracker.clear();
  }

  /// Lấy thông tin inventory còn lại của sản phẩm
  static List<InventoryLot> getInventoryLots(String productId) {
    return _inventoryTracker[productId] ?? [];
  }

  /// Tính profit margin
  static double calculateProfitMargin(double revenue, double cost) {
    if (revenue == 0) return 0.0;
    return ((revenue - cost) / cost) * 100;
  }
}