/// Trạng thái phiếu chuyển kho giữa các chi nhánh.
enum StockTransferStatus {
  draft('draft'),
  inTransit('in_transit'),
  received('received'),
  cancelled('cancelled');

  final String value;
  const StockTransferStatus(this.value);

  static StockTransferStatus fromString(String? raw) {
    final n = (raw ?? '').trim().toLowerCase().replaceAll('-', '_');
    for (final s in StockTransferStatus.values) {
      if (s.value == n || s.name.toLowerCase() == n.replaceAll('_', '')) {
        return s;
      }
    }
    return StockTransferStatus.inTransit;
  }
}

/// Chỉ lưu URL ảnh ngắn (http/ref) vào phiếu; ảnh Base64 quá nặng cho RTDB
/// nên được tra lại theo productId khi hiển thị.
String? transferSafeImageUrl(String? raw) {
  final v = raw?.trim();
  if (v == null || v.isEmpty || v.startsWith('data:') || v.length > 500) {
    return null;
  }
  return v;
}

/// Một mặt hàng trong phiếu chuyển kho.
class StockTransferItem {
  final String productId;
  final String name;
  final String code;
  final String? imageUrl;

  /// Đơn giá chuyển (giá vốn tại thời điểm chuyển).
  final double unitPrice;
  final int quantity;

  /// Số lượng chi nhánh nhận thực nhận (0 khi chưa nhận).
  final int receivedQuantity;

  const StockTransferItem({
    required this.productId,
    required this.name,
    required this.code,
    this.imageUrl,
    this.unitPrice = 0,
    required this.quantity,
    this.receivedQuantity = 0,
  });

  double get totalValue => unitPrice * quantity;
  double get receivedValue => unitPrice * receivedQuantity;

  StockTransferItem copyWith({
    String? imageUrl,
    int? quantity,
    int? receivedQuantity,
    double? unitPrice,
  }) {
    return StockTransferItem(
      productId: productId,
      name: name,
      code: code,
      imageUrl: imageUrl ?? this.imageUrl,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
      receivedQuantity: receivedQuantity ?? this.receivedQuantity,
    );
  }

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'code': code,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'receivedQuantity': receivedQuantity,
      };

  factory StockTransferItem.fromMap(Map<dynamic, dynamic> map) {
    int toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    double toDouble(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return StockTransferItem(
      productId: '${map['productId'] ?? ''}',
      name: '${map['name'] ?? ''}',
      code: '${map['code'] ?? ''}',
      imageUrl: map['imageUrl']?.toString(),
      unitPrice: toDouble(map['unitPrice']),
      quantity: toInt(map['quantity']),
      receivedQuantity: toInt(map['receivedQuantity']),
    );
  }
}

/// Phiếu chuyển kho (mã TRFxxxxxx) từ chi nhánh gửi sang chi nhánh nhận.
class StockTransfer {
  final String id;
  final String code;
  final StockTransferStatus status;
  final String sourceStoreId;
  final String sourceStoreName;
  final String targetStoreId;
  final String targetStoreName;
  final List<StockTransferItem> items;
  final String note;
  final String receiveNote;
  final DateTime createdAt;
  final String? createdBy;
  final String? createdByName;
  final DateTime? receivedAt;
  final String? receivedBy;
  final String? receivedByName;

  const StockTransfer({
    required this.id,
    required this.code,
    required this.status,
    required this.sourceStoreId,
    required this.sourceStoreName,
    required this.targetStoreId,
    required this.targetStoreName,
    required this.items,
    this.note = '',
    this.receiveNote = '',
    required this.createdAt,
    this.createdBy,
    this.createdByName,
    this.receivedAt,
    this.receivedBy,
    this.receivedByName,
  });

  bool get isDraft => status == StockTransferStatus.draft;
  bool get isInTransit => status == StockTransferStatus.inTransit;
  bool get isReceived => status == StockTransferStatus.received;
  bool get isCancelled => status == StockTransferStatus.cancelled;

  int get itemCount => items.length;
  int get totalQuantity => items.fold(0, (s, i) => s + i.quantity);
  int get totalReceivedQuantity =>
      items.fold(0, (s, i) => s + i.receivedQuantity);
  double get totalValue => items.fold(0.0, (s, i) => s + i.totalValue);
  double get totalReceivedValue =>
      items.fold(0.0, (s, i) => s + i.receivedValue);
  int get receivedItemCount =>
      items.where((i) => i.receivedQuantity > 0).length;

  /// Số sản phẩm đã nhận / đã chuyển, ví dụ "4/4".
  String get receivedSummary =>
      '${isReceived ? totalReceivedQuantity : 0}/$totalQuantity';

  StockTransfer copyWith({
    String? id,
    String? code,
    StockTransferStatus? status,
    String? targetStoreId,
    String? targetStoreName,
    List<StockTransferItem>? items,
    String? note,
    String? receiveNote,
    DateTime? createdAt,
    DateTime? receivedAt,
    String? receivedBy,
    String? receivedByName,
  }) {
    return StockTransfer(
      id: id ?? this.id,
      code: code ?? this.code,
      status: status ?? this.status,
      sourceStoreId: sourceStoreId,
      sourceStoreName: sourceStoreName,
      targetStoreId: targetStoreId ?? this.targetStoreId,
      targetStoreName: targetStoreName ?? this.targetStoreName,
      items: items ?? this.items,
      note: note ?? this.note,
      receiveNote: receiveNote ?? this.receiveNote,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy,
      createdByName: createdByName,
      receivedAt: receivedAt ?? this.receivedAt,
      receivedBy: receivedBy ?? this.receivedBy,
      receivedByName: receivedByName ?? this.receivedByName,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'code': code,
        'status': status.value,
        'sourceStoreId': sourceStoreId,
        'sourceStoreName': sourceStoreName,
        'targetStoreId': targetStoreId,
        'targetStoreName': targetStoreName,
        'items': items.map((i) => i.toMap()).toList(),
        'note': note,
        'receiveNote': receiveNote,
        'createdAt': createdAt.toIso8601String(),
        if (createdBy != null) 'createdBy': createdBy,
        if (createdByName != null) 'createdByName': createdByName,
        if (receivedAt != null) 'receivedAt': receivedAt!.toIso8601String(),
        if (receivedBy != null) 'receivedBy': receivedBy,
        if (receivedByName != null) 'receivedByName': receivedByName,
      };

  factory StockTransfer.fromMap(Map<dynamic, dynamic> map) {
    final rawItems = map['items'];
    final items = <StockTransferItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) items.add(StockTransferItem.fromMap(e));
      }
    } else if (rawItems is Map) {
      for (final e in rawItems.values) {
        if (e is Map) items.add(StockTransferItem.fromMap(e));
      }
    }
    return StockTransfer(
      id: '${map['id'] ?? ''}',
      code: '${map['code'] ?? ''}',
      status: StockTransferStatus.fromString(map['status']?.toString()),
      sourceStoreId: '${map['sourceStoreId'] ?? ''}',
      sourceStoreName: '${map['sourceStoreName'] ?? ''}',
      targetStoreId: '${map['targetStoreId'] ?? ''}',
      targetStoreName: '${map['targetStoreName'] ?? ''}',
      items: items,
      note: '${map['note'] ?? ''}',
      receiveNote: '${map['receiveNote'] ?? ''}',
      createdAt: DateTime.tryParse('${map['createdAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      createdBy: map['createdBy']?.toString(),
      createdByName: map['createdByName']?.toString(),
      receivedAt: DateTime.tryParse('${map['receivedAt'] ?? ''}'),
      receivedBy: map['receivedBy']?.toString(),
      receivedByName: map['receivedByName']?.toString(),
    );
  }
}
