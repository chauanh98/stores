import 'combo_component.dart';

class ReturnOrderItem {
  final String productId;
  final String productName;
  final double price; // Đơn giá lúc mua
  final int quantity; // Số lượng trả lại
  final String? unit;
  final bool isCombo;
  final List<ComboComponent> comboComponents;

  const ReturnOrderItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.unit,
    this.isCombo = false,
    this.comboComponents = const [],
  });

  double get totalRefund => price * quantity;
  double get total => price * quantity;

  ReturnOrderItem copyWith({
    String? productId,
    String? productName,
    double? price,
    int? quantity,
    String? unit,
    bool? isCombo,
    List<ComboComponent>? comboComponents,
  }) {
    return ReturnOrderItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      isCombo: isCombo ?? this.isCombo,
      comboComponents: comboComponents ?? this.comboComponents,
    );
  }

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'price': price,
        'quantity': quantity,
        if (unit != null) 'unit': unit,
        'isCombo': isCombo,
        'comboComponents': comboComponents.map((e) => e.toMap()).toList(),
        'total': totalRefund,
      };

  factory ReturnOrderItem.fromMap(Map<dynamic, dynamic> map) {
    return ReturnOrderItem(
      productId: map['productId']?.toString() ?? '',
      productName: map['productName']?.toString() ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      unit: map['unit']?.toString(),
      isCombo: map['isCombo'] as bool? ?? false,
      comboComponents: (map['comboComponents'] as List?)
              ?.map((e) => ComboComponent.fromMap(e as Map))
              .toList() ??
          const [],
    );
  }
}

class ReturnOrder {
  final String id;
  final String orderId;
  final String customerId;
  final String storeId;
  final DateTime createdAt;
  final List<ReturnOrderItem> items;
  final double totalReturnAmount;
  final double debtDeducted;
  final double cashRefunded;
  final String? reason;
  final String? createdBy;
  final String? createdByName;
  final String refundPaymentMethod; // 'cash', 'transfer', 'debt_deduction'

  const ReturnOrder({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.storeId,
    required this.createdAt,
    required this.items,
    required this.totalReturnAmount,
    this.debtDeducted = 0.0,
    this.cashRefunded = 0.0,
    this.reason,
    this.createdBy,
    this.createdByName,
    this.refundPaymentMethod = 'cash',
  });

  double get totalRefund => totalReturnAmount;

  ReturnOrder copyWith({
    String? id,
    String? orderId,
    String? customerId,
    String? storeId,
    DateTime? createdAt,
    List<ReturnOrderItem>? items,
    double? totalReturnAmount,
    double? debtDeducted,
    double? cashRefunded,
    String? reason,
    String? createdBy,
    String? createdByName,
    String? refundPaymentMethod,
  }) {
    return ReturnOrder(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      customerId: customerId ?? this.customerId,
      storeId: storeId ?? this.storeId,
      createdAt: createdAt ?? this.createdAt,
      items: items ?? this.items,
      totalReturnAmount: totalReturnAmount ?? this.totalReturnAmount,
      debtDeducted: debtDeducted ?? this.debtDeducted,
      cashRefunded: cashRefunded ?? this.cashRefunded,
      reason: reason ?? this.reason,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      refundPaymentMethod: refundPaymentMethod ?? this.refundPaymentMethod,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'orderId': orderId,
        'customerId': customerId,
        'storeId': storeId,
        'createdAt': createdAt.toIso8601String(),
        'items': items.map((e) => e.toMap()).toList(),
        'totalReturnAmount': totalReturnAmount,
        'debtDeducted': debtDeducted,
        'cashRefunded': cashRefunded,
        if (reason != null) 'reason': reason,
        if (createdBy != null) 'createdBy': createdBy,
        if (createdByName != null) 'createdByName': createdByName,
        'refundPaymentMethod': refundPaymentMethod,
      };

  factory ReturnOrder.fromMap(Map<dynamic, dynamic> map) {
    return ReturnOrder(
      id: map['id']?.toString() ?? '',
      orderId: map['orderId']?.toString() ?? '',
      customerId: map['customerId']?.toString() ?? '',
      storeId: map['storeId']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      items: (map['items'] as List?)
              ?.map((e) => ReturnOrderItem.fromMap(e as Map))
              .toList() ??
          const [],
      totalReturnAmount: (map['totalReturnAmount'] as num?)?.toDouble() ??
          (map['totalRefund'] as num?)?.toDouble() ??
          0.0,
      debtDeducted: (map['debtDeducted'] as num?)?.toDouble() ?? 0.0,
      cashRefunded: (map['cashRefunded'] as num?)?.toDouble() ?? 0.0,
      reason: map['reason']?.toString() ?? map['note']?.toString(),
      createdBy: map['createdBy']?.toString(),
      createdByName: map['createdByName']?.toString(),
      refundPaymentMethod: map['refundPaymentMethod']?.toString() ?? 'cash',
    );
  }
}
