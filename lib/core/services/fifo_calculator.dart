import '../../domain/entities/inventory_transaction.dart';
import '../../domain/entities/transaction_type.dart';
import '../utils/store_resolver_helper.dart';

/// Class để theo dõi inventory còn lại của từng lô nhập
class InventoryLot {
  final String transactionId;
  final DateTime importDate;
  final double importPrice;
  int remainingQuantity;
  final String? storeId;

  double get unitCost => importPrice;

  InventoryLot({
    required this.transactionId,
    required this.importDate,
    required this.importPrice,
    required this.remainingQuantity,
    this.storeId,
  });

  InventoryLot copyWith({
    String? transactionId,
    DateTime? importDate,
    double? importPrice,
    int? remainingQuantity,
    String? storeId,
  }) {
    return InventoryLot(
      transactionId: transactionId ?? this.transactionId,
      importDate: importDate ?? this.importDate,
      importPrice: importPrice ?? this.importPrice,
      remainingQuantity: remainingQuantity ?? this.remainingQuantity,
      storeId: storeId ?? this.storeId,
    );
  }
}

/// Instance-based FIFO Engine để đảm bảo cách ly trạng thái (state isolation),
/// tránh race conditions, phân vùng độc lập theo từng chi nhánh (store-partitioned lot tracking)
/// và hỗ trợ tính toán chính xác đa ngày (multi-day reports) cùng 6 edge cases toàn diện.
class FifoCalculator {
  /// Phân vùng lưu trữ lô FIFO: storeId -> (productId -> List<InventoryLot>)
  final Map<String, Map<String, List<InventoryLot>>> _storeTrackers = {};

  FifoCalculator([
    List<InventoryTransaction>? importTransactions,
    String? defaultStoreId,
  ]) {
    if (importTransactions != null && importTransactions.isNotEmpty) {
      initializeInventoryTracker(
        importTransactions,
        defaultStoreId: defaultStoreId,
      );
    }
  }

  /// Chuẩn hóa mã định danh chi nhánh về key thống nhất
  static String normalizeStoreKey(String? storeId) {
    if (storeId == null || storeId.isEmpty) return 'default';
    final normalized = StoreResolverHelper.normalizeStoreId(storeId);
    return normalized.isNotEmpty ? normalized : storeId.trim();
  }

  /// Lấy hoặc tạo danh sách lô FIFO cho sản phẩm tại chi nhánh tương ứng
  List<InventoryLot> _getOrCreateLotQueue(String? storeId, String productId) {
    final key = normalizeStoreKey(storeId);
    final productMap =
        _storeTrackers.putIfAbsent(key, () => <String, List<InventoryLot>>{});
    return productMap.putIfAbsent(productId, () => <InventoryLot>[]);
  }

  /// Khởi tạo inventory tracker từ các giao dịch import, cân bằng kho (inventoryAudit) và xuất kho (export)
  void initializeInventoryTracker(
    List<InventoryTransaction> transactions, {
    String? defaultStoreId,
  }) {
    _storeTrackers.clear();

    // Lọc các giao dịch nhập hàng, cân bằng kho và xuất kho
    final eligibleTxs = transactions.where((t) {
      return t.type == TransactionType.import ||
          t.type == TransactionType.inventoryAudit ||
          t.type == TransactionType.export;
    }).toList();

    // Sắp xếp các giao dịch theo thời gian tăng dần
    eligibleTxs.sort((a, b) => a.date.compareTo(b.date));

    // Tạo inventory lots và áp dụng cân bằng kho / xuất kho theo trình tự thời gian
    for (final tx in eligibleTxs) {
      final storeKey = normalizeStoreKey(tx.storeId ?? defaultStoreId);
      final productMap = _storeTrackers.putIfAbsent(
          storeKey, () => <String, List<InventoryLot>>{});
      final lots = productMap.putIfAbsent(tx.productId, () => <InventoryLot>[]);

      if (tx.type == TransactionType.import) {
        // Case 1: Nhập kho (Inbound purchase / Transfer import)
        if (tx.quantity > 0) {
          lots.add(InventoryLot(
            transactionId: tx.id,
            importDate: tx.date,
            importPrice: tx.importPrice ?? 0.0,
            remainingQuantity: tx.quantity,
            storeId: storeKey,
          ));
        }
      } else if (tx.type == TransactionType.inventoryAudit) {
        final isNegative = _isNegativeAudit(tx);
        if (!isNegative) {
          // Case 4: Cân bằng kho tăng (+): Đăng ký như một lô tồn mới với giá vốn tại thời điểm audit
          final diffQty = tx.auditDifference != null && tx.auditDifference! > 0
              ? tx.auditDifference!
              : tx.quantity;
          if (diffQty > 0) {
            lots.add(InventoryLot(
              transactionId: tx.id,
              importDate: tx.date,
              importPrice: tx.importPrice ?? 0.0,
              remainingQuantity: diffQty,
              storeId: storeKey,
            ));
          }
        } else {
          // Case 5: Cân bằng kho giảm (-): Khấu trừ lượng hao hụt theo thứ tự FIFO từ các lô hiện có
          final toDeduct = tx.auditDifference != null && tx.auditDifference! < 0
              ? tx.auditDifference!.abs()
              : tx.quantity;
          int remainingToDeduct = toDeduct;
          for (final lot in lots) {
            if (remainingToDeduct <= 0) break;
            if (lot.remainingQuantity <= 0) continue;
            final deduct = remainingToDeduct > lot.remainingQuantity
                ? lot.remainingQuantity
                : remainingToDeduct;
            lot.remainingQuantity -= deduct;
            remainingToDeduct -= deduct;
          }
        }
      } else if (tx.type == TransactionType.export) {
        // Khấu trừ lô khi có giao dịch xuất kho trong lịch sử (ví dụ: chuyển kho xuất)
        int remainingToDeduct = tx.quantity;
        for (final lot in lots) {
          if (remainingToDeduct <= 0) break;
          if (lot.remainingQuantity <= 0) continue;
          final deduct = remainingToDeduct > lot.remainingQuantity
              ? lot.remainingQuantity
              : remainingToDeduct;
          lot.remainingQuantity -= deduct;
          remainingToDeduct -= deduct;
        }
      }
    }
  }

  /// Xác định giao dịch kiểm kê là âm (giảm tồn) hay dương (tăng tồn)
  static bool _isNegativeAudit(InventoryTransaction tx) {
    if (tx.isAuditNegative != null) {
      return tx.isAuditNegative!;
    }
    if (tx.auditDifference != null) {
      return tx.auditDifference! < 0;
    }
    final note = tx.note.toLowerCase();
    if (note.contains('chênh lệch: -')) return true;
    if (note.contains('chênh lệch: +')) return false;
    if (note.contains('-') && !note.contains('+')) return true;
    return false;
  }

  /// Tính cost của sản phẩm theo nguyên tắc FIFO (Case 2: Bán hàng POS / Oversold)
  double calculateCostForSale({
    required String productId,
    required int quantity,
    required DateTime saleDate,
    String? storeId,
    double? fallbackCostPrice,
  }) {
    if (quantity <= 0) return 0.0;

    final storeKey = normalizeStoreKey(storeId);
    List<InventoryLot>? inventoryLots;

    if (_storeTrackers.containsKey(storeKey) &&
        _storeTrackers[storeKey]!.containsKey(productId)) {
      inventoryLots = _storeTrackers[storeKey]![productId];
    } else if (storeId == null) {
      // Legacy unpartitioned fallback: kiểm tra phân vùng 'default' trước
      final defaultKey = normalizeStoreKey(null);
      if (_storeTrackers.containsKey(defaultKey) &&
          _storeTrackers[defaultKey]!.containsKey(productId)) {
        inventoryLots = _storeTrackers[defaultKey]![productId];
      } else {
        // Tìm kiếm trên tất cả phân vùng nếu không chỉ định storeId
        for (final storeMap in _storeTrackers.values) {
          if (storeMap.containsKey(productId) &&
              storeMap[productId]!.isNotEmpty) {
            inventoryLots = storeMap[productId];
            break;
          }
        }
      }
    }

    double totalCost = 0.0;
    int remainingQuantity = quantity;
    double? lastKnownLotPrice;

    if (inventoryLots != null && inventoryLots.isNotEmpty) {
      // Tính cost theo FIFO từ các lô còn lại (ưu tiên lô nhập trước)
      for (final lot in inventoryLots) {
        if (remainingQuantity <= 0) break;
        if (lot.remainingQuantity <= 0) continue;

        lastKnownLotPrice = lot.importPrice;
        final usedQuantity = remainingQuantity > lot.remainingQuantity
            ? lot.remainingQuantity
            : remainingQuantity;

        totalCost += usedQuantity * lot.importPrice;
        lot.remainingQuantity -= usedQuantity;
        remainingQuantity -= usedQuantity;
      }
    }

    // Nếu không có lô nhập hoặc số lượng bán vượt quá số lượng trong các lô nhập (Oversold):
    // Fallback về fallbackCostPrice (giá vốn sản phẩm), hoặc giá lô nhập cuối cùng / lastKnownLotPrice
    // Đảm bảo 0 negative lot invariant: không bao giờ gán âm cho remainingQuantity của lô
    if (remainingQuantity > 0) {
      final fallbackPrice = fallbackCostPrice ??
          lastKnownLotPrice ??
          (inventoryLots != null && inventoryLots.isNotEmpty
              ? inventoryLots.last.importPrice
              : 0.0);
      totalCost += remainingQuantity * fallbackPrice;
    }

    return totalCost;
  }

  /// Trả hàng / Hoàn hóa đơn (Case 6): Đưa số lượng trả lại vào đầu hàng đợi FIFO (index 0)
  /// với đơn giá vốn ban đầu để ưu tiên xuất trước ở lần bán tiếp theo.
  void returnToInventory({
    required String productId,
    required int quantity,
    required double unitCost,
    DateTime? returnDate,
    String? storeId,
    String? transactionId,
  }) {
    if (quantity <= 0) return;

    final lots = _getOrCreateLotQueue(storeId, productId);
    final returnLot = InventoryLot(
      transactionId:
          transactionId ?? 'return_${DateTime.now().millisecondsSinceEpoch}',
      importDate: returnDate ?? DateTime.now(),
      importPrice: unitCost,
      remainingQuantity: quantity,
      storeId: normalizeStoreKey(storeId),
    );

    // Chèn vào ĐẦU (index 0) hàng đợi FIFO của chi nhánh
    lots.insert(0, returnLot);
  }

  /// Chuyển kho liên chi nhánh (Case 3):
  /// Khấu trừ tuần tự các lô FIFO từ kho xuất (sourceStoreId),
  /// và chuyển lô với giá vốn đó sang hàng đợi FIFO của kho nhập (targetStoreId).
  double transferInventory({
    required String productId,
    required int quantity,
    required String sourceStoreId,
    required String targetStoreId,
    DateTime? transferDate,
    double? unitCost,
    double? fallbackCostPrice,
    String? transactionId,
  }) {
    if (quantity <= 0) return 0.0;
    final date = transferDate ?? DateTime.now();

    // 1. Khấu trừ từ kho xuất theo FIFO và lấy tổng giá vốn chuyển giao
    final transferCost = calculateCostForSale(
      productId: productId,
      quantity: quantity,
      saleDate: date,
      storeId: sourceStoreId,
      fallbackCostPrice: unitCost ?? fallbackCostPrice,
    );

    final effectiveUnitCost =
        quantity > 0 ? (transferCost / quantity) : (unitCost ?? 0.0);

    // 2. Thêm lô nhập vào kho đích với giá vốn được bảo toàn nguyên vẹn
    final targetQueue = _getOrCreateLotQueue(targetStoreId, productId);
    targetQueue.add(InventoryLot(
      transactionId: transactionId ?? 'transfer_${date.millisecondsSinceEpoch}',
      importDate: date,
      importPrice: effectiveUnitCost,
      remainingQuantity: quantity,
      storeId: normalizeStoreKey(targetStoreId),
    ));

    return transferCost;
  }

  /// Thêm thủ công 1 lô nhập vào hàng đợi chi nhánh
  void addInventoryLot(
    String productId,
    InventoryLot lot, {
    String? storeId,
  }) {
    final queue = _getOrCreateLotQueue(storeId ?? lot.storeId, productId);
    queue.add(lot);
  }

  /// Reset inventory tracker cho 1 chi nhánh hoặc toàn bộ
  void resetInventoryTracker({String? storeId}) {
    if (storeId != null) {
      final key = normalizeStoreKey(storeId);
      _storeTrackers.remove(key);
    } else {
      _storeTrackers.clear();
    }
  }

  /// Lấy thông tin inventory còn lại của sản phẩm
  List<InventoryLot> getInventoryLots(String productId, {String? storeId}) {
    if (storeId != null) {
      final key = normalizeStoreKey(storeId);
      return _storeTrackers[key]?[productId] ?? [];
    }
    // Nếu storeId null, kiểm tra phân vùng 'default' trước
    final defaultKey = normalizeStoreKey(null);
    if (_storeTrackers.containsKey(defaultKey) &&
        _storeTrackers[defaultKey]!.containsKey(productId)) {
      return _storeTrackers[defaultKey]![productId]!;
    }
    // Fallback: tìm kiếm trên tất cả phân vùng
    for (final storeMap in _storeTrackers.values) {
      if (storeMap.containsKey(productId) && storeMap[productId]!.isNotEmpty) {
        return storeMap[productId]!;
      }
    }
    return [];
  }

  /// Lấy tổng số lượng tồn kho còn lại của sản phẩm trong các lô FIFO
  int getRemainingQuantity(String productId, {String? storeId}) {
    final lots = getInventoryLots(productId, storeId: storeId);
    return lots.fold(0, (sum, lot) => sum + lot.remainingQuantity);
  }

  /// Kiểm tra sản phẩm có lô tồn khả dụng hay không
  bool hasAvailableLots(String productId, {String? storeId}) {
    return getRemainingQuantity(productId, storeId: storeId) > 0;
  }

  /// Tính profit margin theo chuẩn: (revenue - cost) / revenue * 100
  static double calculateProfitMargin(double revenue, double cost) {
    if (revenue <= 0) return 0.0;
    return ((revenue - cost) / revenue) * 100;
  }
}
