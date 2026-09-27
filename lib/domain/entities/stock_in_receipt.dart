import 'inventory_transaction.dart';
import 'product.dart';
import 'supplier_debt_transaction.dart';
import 'transaction_type.dart';

/// Represents a consolidated stock-in receipt (Phiếu nhập kho) according to KiotViet standards.
/// Groups one or more [InventoryTransaction] records sharing the same [importCode].
class StockInReceipt {
  final String id;
  final String importCode;
  final DateTime date;
  final String? storeId;
  final String? branchName;
  final String? supplierId;
  final String? supplierName;
  final String? supplierPhone;
  final String? createdBy;
  final String? createdByName;
  final String note;
  final List<StockInReceiptItem> items;
  final double? _totalAmount;
  final double discount;
  final double? netPayable;
  final double? paidAmount;
  final double? debtAmount;
  final String status;
  final String paymentMethod;
  final String? cancelReason;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const StockInReceipt({
    required this.id,
    required this.importCode,
    required this.date,
    this.storeId,
    this.branchName,
    this.supplierId,
    this.supplierName,
    this.supplierPhone,
    this.createdBy,
    this.createdByName,
    this.note = '',
    required this.items,
    this.paidAmount,
    this.debtAmount,
    this.discount = 0.0,
    this.netPayable,
    this.status = 'Đã nhập hàng',
    this.paymentMethod = 'cash',
    this.cancelReason,
    this.cancelledAt,
    this.cancelledBy,
    this.createdAt,
    this.updatedAt,
    double? totalAmount,
  }) : _totalAmount = totalAmount;

  /// Status helpers
  bool get isDraft => status == 'draft' || status == 'Phiếu tạm';
  bool get isCancelled => status == 'cancelled' || status == 'Đã hủy';
  bool get isCompleted => !isDraft && !isCancelled;

  /// Total units/quantity of all items in this receipt.
  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);

  /// Total monetary value of all items in this receipt (subtotal).
  double get totalAmount =>
      _totalAmount ?? items.fold(0.0, (sum, item) => sum + item.totalPrice);

  /// Total number of distinct product lines in this receipt.
  int get itemCount => items.length;

  /// Effective net payable after discount: netPayable ?? (totalAmount - discount)
  double get effectiveNetPayable => netPayable ?? (totalAmount - discount);

  /// Outstanding debt remaining to be paid: effectiveNetPayable - paidAmount
  double get remainingDebt => effectiveNetPayable - (paidAmount ?? 0.0);

  StockInReceipt copyWith({
    String? id,
    String? importCode,
    DateTime? date,
    String? storeId,
    String? branchName,
    String? supplierId,
    String? supplierName,
    String? supplierPhone,
    String? createdBy,
    String? createdByName,
    String? note,
    List<StockInReceiptItem>? items,
    double? totalAmount,
    double? discount,
    double? netPayable,
    double? paidAmount,
    double? debtAmount,
    String? status,
    String? paymentMethod,
    String? cancelReason,
    DateTime? cancelledAt,
    String? cancelledBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StockInReceipt(
      id: id ?? this.id,
      importCode: importCode ?? this.importCode,
      date: date ?? this.date,
      storeId: storeId ?? this.storeId,
      branchName: branchName ?? this.branchName,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      supplierPhone: supplierPhone ?? this.supplierPhone,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      note: note ?? this.note,
      items: items ?? this.items,
      totalAmount: totalAmount ?? _totalAmount,
      discount: discount ?? this.discount,
      netPayable: netPayable ?? this.netPayable,
      paidAmount: paidAmount ?? this.paidAmount,
      debtAmount: debtAmount ?? this.debtAmount,
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      cancelReason: cancelReason ?? this.cancelReason,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'importCode': importCode,
      'date': date.toIso8601String(),
      'storeId': storeId,
      'branchName': branchName,
      'supplierId': supplierId,
      'supplierName': supplierName,
      'supplierPhone': supplierPhone,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'note': note,
      'totalAmount': totalAmount,
      'discount': discount,
      'netPayable': effectiveNetPayable,
      'paidAmount': paidAmount,
      'debtAmount': debtAmount,
      'remainingDebt': remainingDebt,
      'status': status,
      'paymentMethod': paymentMethod,
      if (cancelReason != null) 'cancelReason': cancelReason,
      if (cancelledAt != null) 'cancelledAt': cancelledAt!.toIso8601String(),
      if (cancelledBy != null) 'cancelledBy': cancelledBy,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      'items': items.map((item) => item.toMap()).toList(),
    };
  }

  factory StockInReceipt.fromMap(Map<String, dynamic> map) {
    DateTime parsedDate;
    if (map['date'] != null) {
      if (map['date'] is DateTime) {
        parsedDate = map['date'] as DateTime;
      } else {
        parsedDate =
            DateTime.tryParse(map['date'].toString()) ?? DateTime.now();
      }
    } else {
      parsedDate = DateTime.now();
    }

    DateTime? parsedCreatedAt;
    if (map['createdAt'] != null) {
      if (map['createdAt'] is DateTime) {
        parsedCreatedAt = map['createdAt'] as DateTime;
      } else {
        parsedCreatedAt = DateTime.tryParse(map['createdAt'].toString());
      }
    }

    DateTime? parsedUpdatedAt;
    if (map['updatedAt'] != null) {
      if (map['updatedAt'] is DateTime) {
        parsedUpdatedAt = map['updatedAt'] as DateTime;
      } else {
        parsedUpdatedAt = DateTime.tryParse(map['updatedAt'].toString());
      }
    }

    DateTime? parsedCancelledAt;
    if (map['cancelledAt'] != null) {
      if (map['cancelledAt'] is DateTime) {
        parsedCancelledAt = map['cancelledAt'] as DateTime;
      } else {
        parsedCancelledAt = DateTime.tryParse(map['cancelledAt'].toString());
      }
    }

    final rawItems = map['items'];
    List<StockInReceiptItem> parsedItems = [];
    if (rawItems is List) {
      parsedItems = rawItems
          .whereType<Map>()
          .map((e) => StockInReceiptItem.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } else if (rawItems is Map) {
      parsedItems = rawItems.values
          .whereType<Map>()
          .map((e) => StockInReceiptItem.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }

    final rawTotal = (map['totalAmount'] as num?)?.toDouble() ??
        (map['total'] as num?)?.toDouble();
    final rawDiscount = (map['discount'] as num?)?.toDouble() ?? 0.0;
    final rawNetPayable = (map['netPayable'] as num?)?.toDouble();
    final rawPaidAmount = (map['paidAmount'] as num?)?.toDouble();
    final rawDebtAmount = (map['debtAmount'] as num?)?.toDouble();

    final id = (map['id'] ?? map['importCode'] ?? '').toString();
    final importCode = (map['importCode'] ?? map['id'] ?? id).toString();

    return StockInReceipt(
      id: id,
      importCode: importCode,
      date: parsedDate,
      storeId: map['storeId']?.toString(),
      branchName: map['branchName']?.toString(),
      supplierId: map['supplierId']?.toString(),
      supplierName: map['supplierName']?.toString(),
      supplierPhone: map['supplierPhone']?.toString(),
      createdBy: map['createdBy']?.toString(),
      createdByName: map['createdByName']?.toString(),
      note: map['note']?.toString() ?? '',
      items: parsedItems,
      totalAmount: rawTotal,
      discount: rawDiscount,
      netPayable: rawNetPayable,
      paidAmount: rawPaidAmount,
      debtAmount: rawDebtAmount,
      status: map['status']?.toString() ?? 'Đã nhập hàng',
      paymentMethod: map['paymentMethod']?.toString() ?? 'cash',
      cancelReason: map['cancelReason']?.toString(),
      cancelledAt: parsedCancelledAt,
      cancelledBy: map['cancelledBy']?.toString(),
      createdAt: parsedCreatedAt,
      updatedAt: parsedUpdatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockInReceipt &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          importCode == other.importCode &&
          date == other.date &&
          storeId == other.storeId &&
          branchName == other.branchName &&
          supplierId == other.supplierId &&
          supplierName == other.supplierName &&
          supplierPhone == other.supplierPhone &&
          createdBy == other.createdBy &&
          createdByName == other.createdByName &&
          note == other.note &&
          discount == other.discount &&
          netPayable == other.netPayable &&
          paidAmount == other.paidAmount &&
          debtAmount == other.debtAmount &&
          status == other.status &&
          paymentMethod == other.paymentMethod &&
          cancelReason == other.cancelReason &&
          cancelledAt == other.cancelledAt &&
          cancelledBy == other.cancelledBy &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          _listEquals(items, other.items);

  @override
  int get hashCode =>
      id.hashCode ^
      importCode.hashCode ^
      date.hashCode ^
      (storeId?.hashCode ?? 0) ^
      (branchName?.hashCode ?? 0) ^
      (supplierId?.hashCode ?? 0) ^
      (supplierName?.hashCode ?? 0) ^
      (supplierPhone?.hashCode ?? 0) ^
      (createdBy?.hashCode ?? 0) ^
      (createdByName?.hashCode ?? 0) ^
      note.hashCode ^
      discount.hashCode ^
      (netPayable?.hashCode ?? 0) ^
      (paidAmount?.hashCode ?? 0) ^
      (debtAmount?.hashCode ?? 0) ^
      status.hashCode ^
      paymentMethod.hashCode ^
      (cancelReason?.hashCode ?? 0) ^
      (cancelledAt?.hashCode ?? 0) ^
      (cancelledBy?.hashCode ?? 0) ^
      items.length.hashCode;

  @override
  String toString() {
    return 'StockInReceipt(id: $id, importCode: $importCode, branch: $branchName, date: $date, supplier: $supplierName, items: ${items.length}, total: $totalAmount, status: $status, paymentMethod: $paymentMethod)';
  }

  static bool _listEquals(
      List<StockInReceiptItem> a, List<StockInReceiptItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Represents an individual item line in a stock-in receipt.
class StockInReceiptItem {
  final String transactionId;
  final String productId;
  final int quantity;
  final double unitPrice;
  final String note;
  final String? productName;
  final String? productCode;
  final String? imageUrl;
  final String? unit;
  final String? barcode;
  final double? originalPrice;
  final double discount;
  final double discountPercentage;

  const StockInReceiptItem({
    required this.transactionId,
    required this.productId,
    required this.quantity,
    double? unitPrice,
    double? importPrice,
    this.note = '',
    this.productName,
    this.productCode,
    this.imageUrl,
    this.unit,
    this.barcode,
    this.originalPrice,
    this.discount = 0.0,
    this.discountPercentage = 0.0,
  }) : unitPrice = unitPrice ?? importPrice ?? 0.0;

  /// Price per unit (importPrice). Provided for backwards compatibility.
  double get importPrice => unitPrice;

  /// Original unit price before line item discount.
  double get effectiveOriginalPrice =>
      originalPrice ?? (discount > 0 ? unitPrice + discount : unitPrice);

  /// Total price for this line item (net line total).
  double get totalPrice => quantity * unitPrice;

  /// Line item subtotal before discount.
  double get subtotal => quantity * effectiveOriginalPrice;

  /// Total line item discount amount.
  double get totalDiscount => (effectiveOriginalPrice - unitPrice) * quantity;

  StockInReceiptItem copyWith({
    String? transactionId,
    String? productId,
    int? quantity,
    double? unitPrice,
    double? importPrice,
    String? note,
    String? productName,
    String? productCode,
    String? imageUrl,
    String? unit,
    String? barcode,
    double? originalPrice,
    double? discount,
    double? discountPercentage,
  }) {
    return StockInReceiptItem(
      transactionId: transactionId ?? this.transactionId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? importPrice ?? this.unitPrice,
      note: note ?? this.note,
      productName: productName ?? this.productName,
      productCode: productCode ?? this.productCode,
      imageUrl: imageUrl ?? this.imageUrl,
      unit: unit ?? this.unit,
      barcode: barcode ?? this.barcode,
      originalPrice: originalPrice ?? this.originalPrice,
      discount: discount ?? this.discount,
      discountPercentage: discountPercentage ?? this.discountPercentage,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'transactionId': transactionId,
      'productId': productId,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'importPrice': unitPrice,
      'note': note,
      'productName': productName,
      'productCode': productCode,
      if (imageUrl != null &&
          !imageUrl!.trim().toLowerCase().startsWith('data:image'))
        'imageUrl': imageUrl,
      'unit': unit,
      'barcode': barcode,
      'originalPrice': originalPrice,
      'discount': discount,
      'discountPercentage': discountPercentage,
      'totalPrice': totalPrice,
    };
  }

  factory StockInReceiptItem.fromMap(Map<String, dynamic> map) {
    final qty = (map['quantity'] as num?)?.toInt() ?? 1;
    final uPrice = (map['unitPrice'] as num?)?.toDouble() ??
        (map['importPrice'] as num?)?.toDouble() ??
        0.0;
    final origPrice = (map['originalPrice'] as num?)?.toDouble();
    final disc = (map['discount'] as num?)?.toDouble() ?? 0.0;
    final discPct = (map['discountPercentage'] as num?)?.toDouble() ?? 0.0;

    return StockInReceiptItem(
      transactionId: (map['transactionId'] ?? map['id'] ?? '').toString(),
      productId: (map['productId'] ?? '').toString(),
      quantity: qty,
      unitPrice: uPrice,
      importPrice: uPrice,
      note: map['note']?.toString() ?? '',
      productName: map['productName']?.toString(),
      productCode: map['productCode']?.toString(),
      imageUrl: map['imageUrl']?.toString(),
      unit: map['unit']?.toString(),
      barcode: map['barcode']?.toString(),
      originalPrice: origPrice,
      discount: disc,
      discountPercentage: discPct,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockInReceiptItem &&
          runtimeType == other.runtimeType &&
          transactionId == other.transactionId &&
          productId == other.productId &&
          quantity == other.quantity &&
          unitPrice == other.unitPrice &&
          note == other.note &&
          productName == other.productName &&
          productCode == other.productCode &&
          imageUrl == other.imageUrl &&
          unit == other.unit &&
          barcode == other.barcode &&
          originalPrice == other.originalPrice &&
          discount == other.discount &&
          discountPercentage == other.discountPercentage;

  @override
  int get hashCode =>
      transactionId.hashCode ^
      productId.hashCode ^
      quantity.hashCode ^
      unitPrice.hashCode ^
      note.hashCode ^
      (productName?.hashCode ?? 0) ^
      (productCode?.hashCode ?? 0) ^
      (imageUrl?.hashCode ?? 0) ^
      (unit?.hashCode ?? 0) ^
      (barcode?.hashCode ?? 0) ^
      (originalPrice?.hashCode ?? 0) ^
      discount.hashCode ^
      discountPercentage.hashCode;

  @override
  String toString() {
    return 'StockInReceiptItem(txId: $transactionId, prodId: $productId, name: $productName, qty: $quantity, price: $unitPrice, total: $totalPrice)';
  }
}

/// Helper class providing grouping logic for stock-in receipts.
class StockInReceiptGroupingHelper {
  /// Groups a list of [InventoryTransaction] records into consolidated [StockInReceipt] entities.
  static List<StockInReceipt> group({
    required List<InventoryTransaction> transactions,
    List<Product> products = const [],
    List<SupplierDebtTransaction> debtTransactions = const [],
  }) {
    return groupTransactionsToReceipts(
      transactions: transactions,
      products: products,
      debtTransactions: debtTransactions,
    );
  }
}

/// Standalone grouping function conforming to interface contracts in PROJECT.md.
///
/// Groups raw [InventoryTransaction] records where `type == TransactionType.import`
/// by [InventoryTransaction.importCode] (fallback to [InventoryTransaction.id]).
/// Enriches items with metadata from [products].
/// Resolves debt and paid amounts from matching [debtTransactions] where `referenceCode == importCode`.
/// Sorts resulting receipts descending by [StockInReceipt.date].
List<StockInReceipt> groupTransactionsToReceipts({
  required List<InventoryTransaction> transactions,
  List<Product> products = const [],
  List<SupplierDebtTransaction> debtTransactions = const [],
}) {
  if (transactions.isEmpty) return const [];

  // Filter to import transactions only
  final importTxs = transactions.where((t) => t.type == TransactionType.import);
  if (importTxs.isEmpty) return const [];

  // Index products by id and code for fast lookup
  final Map<String, Product> productById = {};
  final Map<String, Product> productByCode = {};
  for (final p in products) {
    productById[p.id] = p;
    if (p.code.isNotEmpty) {
      productByCode[p.code] = p;
      productByCode[p.code.toLowerCase()] = p;
    }
  }

  // Index debt transactions by referenceCode (importCode)
  final Map<String, List<SupplierDebtTransaction>> debtsByRef = {};
  for (final d in debtTransactions) {
    if (d.referenceCode != null && d.referenceCode!.trim().isNotEmpty) {
      final ref = d.referenceCode!.trim();
      debtsByRef.putIfAbsent(ref, () => []).add(d);
    }
  }

  // Group transactions by importCode (fallback to transaction id)
  final Map<String, List<InventoryTransaction>> grouped = {};
  for (final tx in importTxs) {
    final key = (tx.importCode != null && tx.importCode!.trim().isNotEmpty)
        ? tx.importCode!.trim()
        : tx.id.trim();
    grouped.putIfAbsent(key, () => []).add(tx);
  }

  final List<StockInReceipt> receipts = [];

  for (final entry in grouped.entries) {
    final groupCode = entry.key;
    final groupTxs = entry.value;
    if (groupTxs.isEmpty) continue;

    final firstTx = groupTxs.first;

    // Resolve header metadata: find first non-null/non-empty values across items in group
    String? resolvedSupplierId;
    String? resolvedSupplierName;
    String? resolvedStoreId;
    String? resolvedCreatedBy;
    String? resolvedCreatedByName;
    DateTime latestDate = firstTx.date;

    for (final tx in groupTxs) {
      if (resolvedSupplierId == null &&
          tx.supplierId != null &&
          tx.supplierId!.isNotEmpty) {
        resolvedSupplierId = tx.supplierId;
      }
      if (resolvedSupplierName == null &&
          tx.supplierName != null &&
          tx.supplierName!.isNotEmpty) {
        resolvedSupplierName = tx.supplierName;
      }
      if (resolvedStoreId == null &&
          tx.storeId != null &&
          tx.storeId!.isNotEmpty) {
        resolvedStoreId = tx.storeId;
      }
      if (resolvedCreatedBy == null &&
          tx.createdBy != null &&
          tx.createdBy!.isNotEmpty) {
        resolvedCreatedBy = tx.createdBy;
      }
      if (resolvedCreatedByName == null &&
          tx.createdByName != null &&
          tx.createdByName!.isNotEmpty) {
        resolvedCreatedByName = tx.createdByName;
      }
      if (tx.date.isAfter(latestDate)) {
        latestDate = tx.date;
      }
    }

    // Build line items
    final List<StockInReceiptItem> items = [];
    for (final tx in groupTxs) {
      final product = productById[tx.productId] ??
          productByCode[tx.productId] ??
          productByCode[tx.productId.toLowerCase()];

      final double effectivePrice = tx.importPrice ?? product?.costPrice ?? 0.0;

      String productName;
      if (product != null && product.name.isNotEmpty) {
        productName = product.name;
      } else if (tx.note.startsWith('Import - ') && tx.note.length > 9) {
        productName = tx.note.substring(9).trim();
      } else {
        productName = 'Sản phẩm ${tx.productId}';
      }

      final String productCode = product?.code ?? '';
      final String? imageUrl = product?.imageUrl ??
          (product?.images.isNotEmpty == true ? product!.images.first : null);
      final String? unit = product?.unit;

      items.add(StockInReceiptItem(
        transactionId: tx.id,
        productId: tx.productId,
        quantity: tx.quantity,
        unitPrice: effectivePrice,
        importPrice: effectivePrice,
        originalPrice: effectivePrice,
        note: tx.note,
        productName: productName,
        productCode: productCode,
        imageUrl: imageUrl,
        unit: unit,
        barcode: product?.barcode,
      ));
    }

    final double calculatedTotal =
        items.fold(0.0, (sum, it) => sum + it.totalPrice);

    // Resolve financial debt / paid amounts
    // Try matching referenceCode with groupCode or any item's importCode
    List<SupplierDebtTransaction>? matchedDebts = debtsByRef[groupCode];
    if (matchedDebts == null && firstTx.importCode != null) {
      matchedDebts = debtsByRef[firstTx.importCode!.trim()];
    }

    double? debtAmount;
    double? paidAmount;

    if (matchedDebts != null && matchedDebts.isNotEmpty) {
      // Find import debt transaction
      SupplierDebtTransaction? importDebtTx;
      for (final d in matchedDebts) {
        if (d.type == SupplierDebtType.importBill) {
          importDebtTx = d;
          break;
        }
      }
      importDebtTx ??= matchedDebts.first;

      debtAmount = importDebtTx.amount;
      paidAmount = (calculatedTotal - debtAmount).clamp(0.0, calculatedTotal);
    } else if (resolvedSupplierId != null && resolvedSupplierId.isNotEmpty) {
      // Supplier selected but no debt recorded => paid in full
      paidAmount = calculatedTotal;
      debtAmount = 0.0;
    } else {
      // No supplier specified => paid in full
      paidAmount = calculatedTotal;
      debtAmount = 0.0;
    }

    // Combine distinct notes (excluding default 'Import - [Product]' generated notes if other notes exist)
    final distinctNotes = groupTxs
        .map((t) => t.note.trim())
        .where((n) => n.isNotEmpty && !n.startsWith('Import - '))
        .toSet()
        .toList();
    final combinedNote = distinctNotes.isNotEmpty
        ? distinctNotes.join('; ')
        : (groupTxs.first.note.trim());

    final String finalImportCode = groupCode.startsWith('PN_')
        ? groupCode
        : (firstTx.importCode != null && firstTx.importCode!.trim().isNotEmpty
            ? firstTx.importCode!.trim()
            : 'PN_${latestDate.millisecondsSinceEpoch}');

    receipts.add(StockInReceipt(
      id: groupCode,
      importCode: finalImportCode,
      date: latestDate,
      storeId: resolvedStoreId,
      branchName: resolvedStoreId == 'store_002'
          ? 'Chi nhánh Thới Bình'
          : (resolvedStoreId == 'store_001' ? 'Chi nhánh Đông Thắng' : null),
      supplierId: resolvedSupplierId,
      supplierName: resolvedSupplierName,
      createdBy: resolvedCreatedBy,
      createdByName: resolvedCreatedByName,
      note: combinedNote,
      items: items,
      paidAmount: paidAmount,
      debtAmount: debtAmount,
      status: 'Đã nhập hàng',
    ));
  }

  // Sort descending by date (newest first)
  receipts.sort((a, b) => b.date.compareTo(a.date));

  return receipts;
}
