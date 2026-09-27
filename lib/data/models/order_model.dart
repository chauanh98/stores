import 'order_item_model.dart';

class OrderModel {
  final String id;
  final String customerId;
  final String? customerName;
  final DateTime createdAt;
  final List<OrderItemModel> items;
  final double total;
  final double discount;
  final String status;
  final double amountPaid;
  final double debtAmount;
  final String paymentMethod;
  final String? createdBy;
  final String? createdByName;
  final String? cancelReason;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelledByName;
  final String? storeId;
  final double? cashAmount;
  final double? transferAmount;
  final String? note;

  const OrderModel({
    required this.id,
    required this.customerId,
    this.customerName,
    required this.createdAt,
    required this.items,
    required this.total,
    this.discount = 0.0,
    this.status = 'completed',
    this.amountPaid = 0.0,
    this.debtAmount = 0.0,
    this.paymentMethod = 'cash',
    this.createdBy,
    this.createdByName,
    this.cancelReason,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelledByName,
    this.storeId,
    this.cashAmount,
    this.transferAmount,
    this.note,
  });

  bool get isCancelled {
    final s = status.trim().toLowerCase();
    return s == 'cancelled' ||
        s == 'canceled' ||
        s.contains('hủy') ||
        s.contains('huỷ') ||
        s.contains('cancel') ||
        s.contains('huy');
  }

  bool get isCompleted => status == 'completed';
  bool get isDraft => status == 'draft';
  bool get isReturned => status == 'returned';
  double get netPayable => (total - discount).clamp(0.0, double.infinity);

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        if (customerName != null) 'customerName': customerName,
        'createdAt': createdAt.toIso8601String(),
        'orderDate': createdAt.toIso8601String(),
        'total': total,
        if (discount > 0) 'discount': discount,
        'items': items.map((e) => e.toMap()).toList(),
        'status': status,
        'amountPaid': amountPaid,
        'debtAmount': status == 'cancelled' ? 0.0 : debtAmount,
        'paymentMethod': paymentMethod,
        if (createdBy != null) 'createdBy': createdBy,
        if (createdByName != null) 'createdByName': createdByName,
        if (cancelReason != null) 'cancelReason': cancelReason,
        if (cancelledAt != null) 'cancelledAt': cancelledAt!.toIso8601String(),
        if (cancelledBy != null) 'cancelledBy': cancelledBy,
        if (cancelledByName != null) 'cancelledByName': cancelledByName,
        if (storeId != null) 'storeId': storeId,
        if (cashAmount != null) 'cashAmount': cashAmount,
        if (transferAmount != null) 'transferAmount': transferAmount,
        if (note != null) 'note': note,
      };

  factory OrderModel.fromMap(Map<dynamic, dynamic> map) {
    final rawTotalVal = map['total'];
    final parsedTotal = rawTotalVal is num
        ? rawTotalVal.toDouble()
        : (double.tryParse(rawTotalVal?.toString() ?? '') ?? 0.0);
    final rawTotal = parsedTotal < 0 ? 0.0 : parsedTotal;

    final rawDiscountVal = map['discount'];
    final parsedDiscount = rawDiscountVal is num
        ? rawDiscountVal.toDouble()
        : (double.tryParse(rawDiscountVal?.toString() ?? '') ?? 0.0);
    var discount = parsedDiscount < 0 ? 0.0 : parsedDiscount;

    final rawItems = map['items'];
    final List<OrderItemModel> items = [];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e != null && e is Map) {
          try {
            items.add(OrderItemModel.fromMap(e));
          } catch (_) {}
        }
      }
    } else if (rawItems is Map) {
      for (final e in rawItems.values) {
        if (e != null && e is Map) {
          try {
            items.add(OrderItemModel.fromMap(e));
          } catch (_) {}
        }
      }
    }

    final rawSubtotalVal = map['subtotal'];
    final parsedSubtotal = rawSubtotalVal is num
        ? rawSubtotalVal.toDouble()
        : (double.tryParse(rawSubtotalVal?.toString() ?? '') ?? 0.0);
    final rawSubtotal = parsedSubtotal < 0 ? 0.0 : parsedSubtotal;

    var total = rawTotal;
    final itemsSum = items.isNotEmpty
        ? items.fold<double>(
            0.0, (sum, item) => sum + (item.price * item.quantity))
        : 0.0;
    final gross = itemsSum > 0 ? itemsSum : rawSubtotal;
    if (gross > rawTotal + 0.01) {
      total = gross;
      if (discount <= 0.01) {
        discount = gross - rawTotal;
      }
    }

    final rawStatusStr =
        (map['status']?.toString() ?? 'completed').trim().toLowerCase();
    final String status;
    if (rawStatusStr == 'cancelled' ||
        rawStatusStr == 'canceled' ||
        rawStatusStr.contains('hủy') ||
        rawStatusStr.contains('huỷ') ||
        rawStatusStr.contains('cancel') ||
        rawStatusStr.contains('huy')) {
      status = 'cancelled';
    } else if (rawStatusStr == 'returned' ||
        rawStatusStr == 'return' ||
        rawStatusStr.contains('trả hàng') ||
        rawStatusStr.contains('tra hang') ||
        rawStatusStr.contains('đổi trả') ||
        rawStatusStr.contains('doi tra')) {
      status = 'returned';
    } else if (rawStatusStr == 'draft' ||
        rawStatusStr.contains('lưu tạm') ||
        rawStatusStr.contains('luu tam') ||
        rawStatusStr == 'tạm' ||
        rawStatusStr == 'tam') {
      status = 'draft';
    } else {
      status = 'completed';
    }

    final rawPaid = map['amountPaid'];
    final parsedPaid = rawPaid != null
        ? (rawPaid is num
            ? rawPaid.toDouble()
            : (double.tryParse(rawPaid.toString()) ??
                (status == 'cancelled' ? 0.0 : rawTotal)))
        : (status == 'cancelled' ? 0.0 : rawTotal);
    final amountPaid = parsedPaid < 0 ? 0.0 : parsedPaid;

    final rawDebt = map['debtAmount'];
    final parsedDebt = rawDebt != null
        ? (rawDebt is num
            ? rawDebt.toDouble()
            : (double.tryParse(rawDebt.toString()) ?? 0.0))
        : 0.0;
    final debtAmount =
        status == 'cancelled' ? 0.0 : (parsedDebt < 0 ? 0.0 : parsedDebt);

    final rawMethodStr =
        (map['paymentMethod']?.toString() ?? 'cash').trim().toLowerCase();
    final String paymentMethod;
    if (rawMethodStr == 'split' ||
        rawMethodStr.contains('kết hợp') ||
        rawMethodStr.contains('ket hop')) {
      paymentMethod = 'split';
    } else if (rawMethodStr == 'transfer' ||
        rawMethodStr == 'ck' ||
        rawMethodStr.contains('chuyển khoản') ||
        rawMethodStr.contains('chuyen khoan') ||
        rawMethodStr.contains('banking')) {
      paymentMethod = 'transfer';
    } else {
      paymentMethod = 'cash';
    }

    final rawCash = map['cashAmount'];
    final cashAmount = rawCash is num
        ? rawCash.toDouble()
        : double.tryParse(rawCash?.toString() ?? '');

    final rawTransfer = map['transferAmount'];
    final transferAmount = rawTransfer is num
        ? rawTransfer.toDouble()
        : double.tryParse(rawTransfer?.toString() ?? '');

    return OrderModel(
      id: map['id']?.toString() ?? '',
      customerId: map['customerId']?.toString() ?? '',
      customerName: map['customerName']?.toString(),
      createdAt: DateTime.tryParse(map['orderDate']?.toString() ?? '') ??
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      total: total,
      discount: discount,
      items: items,
      status: status,
      amountPaid: amountPaid,
      debtAmount: debtAmount,
      paymentMethod: paymentMethod,
      createdBy: map['createdBy']?.toString(),
      createdByName: map['createdByName']?.toString(),
      cancelReason: map['cancelReason']?.toString(),
      cancelledAt: map['cancelledAt'] != null
          ? DateTime.tryParse(map['cancelledAt'].toString())
          : null,
      cancelledBy: map['cancelledBy']?.toString(),
      cancelledByName: map['cancelledByName']?.toString(),
      storeId: map['storeId']?.toString(),
      cashAmount: cashAmount,
      transferAmount: transferAmount,
      note: map['note']?.toString(),
    );
  }
}
