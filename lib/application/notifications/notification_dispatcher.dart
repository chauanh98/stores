import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/customer.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/return_order.dart';
import '../../domain/entities/stock_in_receipt.dart';
import '../../domain/entities/stock_transfer.dart';
import '../../data/datasources/firebase/server_clock.dart';
import '../../domain/entities/user_account.dart';
import 'notifications_providers.dart';

/// Provider for [NotificationDispatcher] with autoDispose.
final notificationDispatcherProvider =
    Provider.autoDispose<NotificationDispatcher>((ref) {
  final repository = ref.watch(notificationRepositoryProvider);
  final pushService = ref.watch(pushNotificationServiceProvider);
  return NotificationDispatcher(repository, pushService);
});

/// Application service that standardizes notification creation across the system.
///
/// Ensures all 8 business events generate properly formatted, categorized,
/// and metadata-enriched [NotificationItem] records, while guaranteeing that
/// notification failures never crash or disrupt POS or inventory transactions.
class NotificationDispatcher {
  final NotificationRepository _repository;
  final PushNotificationService? _pushNotificationService;
  static int _counter = 0;

  NotificationDispatcher(
    this._repository, [
    this._pushNotificationService,
  ]);

  /// Thời điểm tạo theo giờ máy chủ (bù độ lệch đồng hồ của máy tạo sự kiện)
  /// để máy nhận tính đúng độ "mới" khi bật pop-up.
  ///
  /// GIỮ định dạng giờ địa phương (không `.toUtc()`): truy vấn
  /// `orderByChild('createdAt').limitToLast(50)` so sánh CHUỖI, trộn chuỗi
  /// "…Z" (UTC) với chuỗi giờ địa phương cũ sẽ làm thông báo mới bị xếp sai
  /// và rơi khỏi cửa sổ 50 thông báo gần nhất.
  static DateTime _now() {
    ServerClock.ensureStarted();
    return ServerClock.now();
  }

  static String _generateId(String prefix) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seq = ++_counter;
    return '${prefix}_${now}_$seq';
  }

  static String _formatCurrency(num amount) {
    final formatter = NumberFormat('#,###', 'vi_VN');
    return '${formatter.format(amount)}đ';
  }

  static bool _isRetailCustomer(String? id, [String? name]) {
    final cleanId = id?.trim().toLowerCase() ?? '';
    final cleanName = name?.trim().toLowerCase() ?? '';
    if (cleanId.isEmpty ||
        cleanId == 'default' ||
        cleanId == 'khach_le' ||
        cleanId == 'walk_in' ||
        cleanId == 'retail' ||
        cleanId == 'khach le' ||
        cleanId == 'null' ||
        cleanId == 'undefined' ||
        cleanId == 'none') {
      return true;
    }
    if (cleanName == 'khach_le' ||
        cleanName == 'walk_in' ||
        cleanName == 'retail' ||
        cleanName == 'default' ||
        cleanName == 'khách lẻ' ||
        cleanName == 'khach le' ||
        cleanName == 'null' ||
        cleanName == 'undefined' ||
        cleanName == 'none') {
      return true;
    }
    return false;
  }

  static String _resolveCustomerId(String? rawId) {
    final trimmed = rawId?.trim() ?? '';
    if (_isRetailCustomer(trimmed)) {
      return 'default';
    }
    return trimmed;
  }

  static String _resolveCustomerName(
      String? rawName, String effectiveCustomerId) {
    final trimmedName = rawName?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      final lower = trimmedName.toLowerCase();
      if (lower == 'khach_le' ||
          lower == 'walk_in' ||
          lower == 'retail' ||
          lower == 'default' ||
          lower == 'khách lẻ' ||
          lower == 'khach le' ||
          lower == 'null' ||
          lower == 'undefined' ||
          lower == 'none') {
        return 'Khách lẻ';
      }
      return trimmedName;
    }
    return 'Khách lẻ';
  }

  static bool _isRetailSupplier(String? id, [String? name]) {
    final cleanId = id?.trim().toLowerCase() ?? '';
    final cleanName = name?.trim().toLowerCase() ?? '';
    if (cleanId.isEmpty ||
        cleanId == 'default' ||
        cleanId == 'ncc_le' ||
        cleanId == 'walk_in' ||
        cleanId == 'retail' ||
        cleanId == 'ncc le' ||
        cleanId == 'null' ||
        cleanId == 'undefined' ||
        cleanId == 'none') {
      return true;
    }
    if (cleanName == 'ncc_le' ||
        cleanName == 'walk_in' ||
        cleanName == 'retail' ||
        cleanName == 'default' ||
        cleanName == 'nhà cung cấp lẻ' ||
        cleanName == 'nha cung cap le' ||
        cleanName == 'null' ||
        cleanName == 'undefined' ||
        cleanName == 'none') {
      return true;
    }
    return false;
  }

  static String _resolveSupplierId(String? rawId) {
    final trimmed = rawId?.trim() ?? '';
    if (_isRetailSupplier(trimmed)) {
      return 'default';
    }
    return trimmed;
  }

  static String _resolveSupplierName(
      String? rawName, String effectiveSupplierId) {
    final trimmedName = rawName?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      final lower = trimmedName.toLowerCase();
      if (lower == 'ncc_le' ||
          lower == 'walk_in' ||
          lower == 'retail' ||
          lower == 'default' ||
          lower == 'nhà cung cấp lẻ' ||
          lower == 'nha cung cap le' ||
          lower == 'null' ||
          lower == 'undefined' ||
          lower == 'none') {
        return 'Nhà cung cấp lẻ';
      }
      return trimmedName;
    }
    return 'Nhà cung cấp lẻ';
  }

  static bool _isValidString(String? val) {
    if (val == null) return false;
    final t = val.trim();
    final l = t.toLowerCase();
    return t.isNotEmpty && l != 'null' && l != 'undefined' && l != 'none';
  }

  static String _resolveCreator(
    UserAccount? user, [
    String? fallback1,
    String? fallback2,
  ]) {
    if (user != null && _isValidString(user.name)) {
      return user.name.trim();
    }
    if (_isValidString(fallback1)) {
      return fallback1!.trim();
    }
    if (_isValidString(fallback2)) {
      return fallback2!.trim();
    }
    return 'Không xác định';
  }

  Future<void> _syncPushNotification(
    String storeId,
    NotificationItem notification,
  ) async {
    final push = _pushNotificationService;
    if (push == null) return;
    try {
      await push.syncPushNotification(
        storeId: storeId,
        notification: notification,
      );
    } catch (e) {
      debugPrint('[NotificationDispatcher] push notification sync skipped: $e');
    }
  }

  /// Dispatches an event when a new sales order is completed.
  ///
  /// Safe against draft orders (skipped).
  Future<void> notifyOrderCreated({
    required String storeId,
    required Order order,
    required UserAccount? user,
  }) async {
    try {
      if (order.isDraft) return;

      final customerId = _resolveCustomerId(order.customerId);
      final customerName = _resolveCustomerName(order.customerName, customerId);
      final createdBy = _resolveCreator(
        user,
        order.createdByName,
        order.createdBy,
      );

      final notif = NotificationItem(
        id: _generateId('NOTIF_ORD'),
        storeId: storeId,
        title: 'Đơn hàng mới #${order.id}',
        body:
            '${_formatCurrency(order.total)} - Khách: $customerName (Tạo bởi: $createdBy)',
        type: NotificationType.orderCreated,
        createdAt: _now(),
        targetRoute: 'invoice_detail',
        targetId: order.id,
        metadata: {
          'orderId': order.id,
          'total': order.total,
          'netPayable': order.netPayable,
          'customerName': customerName,
          'customerId': customerId,
          'createdBy': createdBy,
        },
      );

      try {
        await _repository.addNotification(notif);
      } catch (repoErr, repoSt) {
        debugPrint(
            '[NotificationDispatcher] RTDB addNotification error on notifyOrderCreated: $repoErr\n$repoSt');
      }
      await _syncPushNotification(storeId, notif);
    } catch (e, stackTrace) {
      debugPrint(
          '[NotificationDispatcher] Failed to dispatch notifyOrderCreated: $e\n$stackTrace');
    }
  }

  /// Dispatches an event when an existing order is edited into a versioned invoice.
  Future<void> notifyOrderUpdated({
    required String storeId,
    required Order order,
    required String originalOrderId,
    required UserAccount? user,
  }) async {
    try {
      final customerId = _resolveCustomerId(order.customerId);
      final customerName = _resolveCustomerName(order.customerName, customerId);
      final createdBy = _resolveCreator(
        user,
        order.createdByName,
        order.createdBy,
      );
      final effectiveOriginalId =
          _isValidString(originalOrderId) ? originalOrderId.trim() : order.id;

      final notif = NotificationItem(
        id: _generateId('NOTIF_VER'),
        storeId: storeId,
        title: 'Sửa hóa đơn #$effectiveOriginalId',
        body:
            'Mã mới #${order.id}: ${_formatCurrency(order.total)} - Khách: $customerName (Bởi: $createdBy)',
        type: NotificationType.orderUpdated,
        createdAt: _now(),
        targetRoute: 'invoice_detail',
        targetId: order.id,
        metadata: {
          'newOrderId': order.id,
          'originalOrderId': effectiveOriginalId,
          'total': order.total,
          'customerName': customerName,
          'customerId': customerId,
          'createdBy': createdBy,
          'updatedBy': createdBy,
        },
      );

      try {
        await _repository.addNotification(notif);
      } catch (repoErr, repoSt) {
        debugPrint(
            '[NotificationDispatcher] RTDB addNotification error on notifyOrderUpdated: $repoErr\n$repoSt');
      }
      await _syncPushNotification(storeId, notif);
    } catch (e, stackTrace) {
      debugPrint(
          '[NotificationDispatcher] Failed to dispatch notifyOrderUpdated: $e\n$stackTrace');
    }
  }

  /// Dispatches an event when an order is cancelled.
  Future<void> notifyOrderCancelled({
    required String storeId,
    required Order order,
    required String cancelReason,
    required UserAccount? user,
  }) async {
    try {
      final cleanCancel = cancelReason.trim();
      final cleanOrderCancel = order.cancelReason?.trim();
      final effectiveReason = _isValidString(cleanCancel)
          ? cleanCancel
          : (_isValidString(cleanOrderCancel)
              ? cleanOrderCancel!
              : 'Không có lý do');
      final customerId = _resolveCustomerId(order.customerId);
      final customerName = _resolveCustomerName(order.customerName, customerId);
      final createdBy = _resolveCreator(
        user,
        order.cancelledByName,
        order.cancelledBy ?? order.createdByName ?? order.createdBy,
      );

      final notif = NotificationItem(
        id: _generateId('NOTIF_CAN'),
        storeId: storeId,
        title: 'Hủy đơn hàng #${order.id}',
        body:
            'Lý do: $effectiveReason - Khách: $customerName (Bởi: $createdBy)',
        type: NotificationType.orderCancelled,
        createdAt: _now(),
        targetRoute: 'invoice_detail',
        targetId: order.id,
        metadata: {
          'orderId': order.id,
          'reason': effectiveReason,
          'customerName': customerName,
          'customerId': customerId,
          'createdBy': createdBy,
          'cancelledBy': createdBy,
        },
      );

      try {
        await _repository.addNotification(notif);
      } catch (repoErr, repoSt) {
        debugPrint(
            '[NotificationDispatcher] RTDB addNotification error on notifyOrderCancelled: $repoErr\n$repoSt');
      }
      await _syncPushNotification(storeId, notif);
    } catch (e, stackTrace) {
      debugPrint(
          '[NotificationDispatcher] Failed to dispatch notifyOrderCancelled: $e\n$stackTrace');
    }
  }

  /// Dispatches an event when a customer return order is processed.
  Future<void> notifyOrderReturned({
    required String storeId,
    required ReturnOrder returnOrder,
    required UserAccount? user,
  }) async {
    try {
      final customerId = _resolveCustomerId(returnOrder.customerId);
      final resolvedCustomerName =
          _resolveCustomerName(returnOrder.customerName, customerId);
      final createdBy = _resolveCreator(
        user,
        returnOrder.createdByName,
        returnOrder.createdBy,
      );
      final effectiveOrderId = _isValidString(returnOrder.orderId)
          ? returnOrder.orderId.trim()
          : returnOrder.id;

      final notif = NotificationItem(
        id: _generateId('NOTIF_RET'),
        storeId: storeId,
        title: 'Đơn trả hàng #$effectiveOrderId',
        body:
            'Hoàn ${_formatCurrency(returnOrder.totalReturnAmount)} - Khách: $resolvedCustomerName (Xử lý: $createdBy)',
        type: NotificationType.orderReturn,
        createdAt: _now(),
        targetRoute: 'invoice_detail',
        targetId: effectiveOrderId,
        metadata: {
          'orderId': effectiveOrderId,
          'returnId': returnOrder.id,
          'refundAmount': returnOrder.totalReturnAmount,
          'customerName': resolvedCustomerName,
          'customerId': customerId,
          'createdBy': createdBy,
        },
      );

      try {
        await _repository.addNotification(notif);
      } catch (repoErr, repoSt) {
        debugPrint(
            '[NotificationDispatcher] RTDB addNotification error on notifyOrderReturned: $repoErr\n$repoSt');
      }
      await _syncPushNotification(storeId, notif);
    } catch (e, stackTrace) {
      debugPrint(
          '[NotificationDispatcher] Failed to dispatch notifyOrderReturned: $e\n$stackTrace');
    }
  }

  /// Thông báo phiếu chuyển kho cho CẢ chi nhánh gửi lẫn chi nhánh nhận.
  ///
  /// [received] = false: vừa tạo phiếu (Đang chuyển); true: chi nhánh nhận đã
  /// xác nhận nhận hàng. Nội dung KHÔNG chứa giá trị để không lộ giá vốn cho
  /// người không có quyền xem giá.
  Future<void> notifyStockTransfer({
    required StockTransfer transfer,
    required bool received,
    String? actorName,
  }) async {
    final actor = (actorName != null && actorName.trim().isNotEmpty)
        ? actorName.trim()
        : 'Nhân viên';
    final from = transfer.sourceStoreName;
    final to = transfer.targetStoreName;
    final qty =
        received ? transfer.totalReceivedQuantity : transfer.totalQuantity;
    final title = received
        ? 'Nhận chuyển hàng #${transfer.code}'
        : 'Chuyển hàng #${transfer.code}';
    final body = received
        ? '$actor đã nhận $qty/${transfer.totalQuantity} sản phẩm '
            '(${transfer.itemCount} mặt hàng) từ $from tại $to.'
        : '$actor chuyển ${transfer.itemCount} mặt hàng '
            '(SL: ${transfer.totalQuantity}) từ $from đến $to.';

    for (final storeId in {transfer.sourceStoreId, transfer.targetStoreId}) {
      if (storeId.isEmpty) continue;
      try {
        final notif = NotificationItem(
          id: _generateId('NOTIF_TRF'),
          storeId: storeId,
          title: title,
          body: body,
          type: NotificationType.stockTransfer,
          createdAt: _now(),
          targetRoute: 'transfer_detail',
          targetId: transfer.id,
          metadata: {
            'transferId': transfer.id,
            'transferCode': transfer.code,
            'sourceStoreId': transfer.sourceStoreId,
            'targetStoreId': transfer.targetStoreId,
            'status': transfer.status.value,
            'createdBy': actor,
          },
        );
        try {
          await _repository.addNotification(notif);
        } catch (repoErr, repoSt) {
          debugPrint(
              '[NotificationDispatcher] RTDB addNotification error on notifyStockTransfer: $repoErr\n$repoSt');
        }
        await _syncPushNotification(storeId, notif);
      } catch (e, stackTrace) {
        debugPrint(
            '[NotificationDispatcher] Failed to dispatch notifyStockTransfer: $e\n$stackTrace');
      }
    }
  }

  /// Thông báo khi phiếu nhập kho bị hủy.
  Future<void> notifyStockInCancelled({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {
    try {
      final code = _isValidString(receipt.importCode)
          ? receipt.importCode.trim()
          : receipt.id;
      final cleanReason = _isValidString(reason) ? reason.trim() : 'Không có';
      final notif = NotificationItem(
        id: _generateId('NOTIF_STK_CAN'),
        storeId: storeId,
        title: 'Hủy phiếu nhập kho #$code',
        body: 'Lý do: $cleanReason (Hủy bởi: $cancelledBy)',
        type: NotificationType.inventoryImported,
        createdAt: _now(),
        targetRoute: 'stock_in_detail',
        targetId: code,
        metadata: {
          'receiptId': receipt.id,
          'importCode': code,
          'totalAmount': receipt.totalAmount,
          'cancelReason': cleanReason,
          'cancelledBy': cancelledBy,
        },
      );
      try {
        await _repository.addNotification(notif);
      } catch (repoErr, repoSt) {
        debugPrint(
            '[NotificationDispatcher] RTDB addNotification error on notifyStockInCancelled: $repoErr\n$repoSt');
      }
      await _syncPushNotification(storeId, notif);
    } catch (e, stackTrace) {
      debugPrint(
          '[NotificationDispatcher] Failed to dispatch notifyStockInCancelled: $e\n$stackTrace');
    }
  }

  /// Dispatches an event when a stock-in receipt is successfully completed.
  ///
  /// Safe against draft or cancelled receipts (skipped).
  Future<void> notifyStockInCompleted({
    required String storeId,
    required StockInReceipt receipt,
    required UserAccount? user,
  }) async {
    try {
      if (receipt.isDraft || receipt.isCancelled) return;

      final supplierId = _resolveSupplierId(receipt.supplierId);
      final supplierName =
          _resolveSupplierName(receipt.supplierName, supplierId);
      final createdBy = _resolveCreator(
        user,
        receipt.createdByName,
        receipt.createdBy,
      );
      final effectiveImportCode = _isValidString(receipt.importCode)
          ? receipt.importCode.trim()
          : receipt.id;

      final notif = NotificationItem(
        id: _generateId('NOTIF_STK'),
        storeId: storeId,
        title: 'Phiếu nhập kho #$effectiveImportCode',
        body:
            '${_formatCurrency(receipt.totalAmount)} - NCC: $supplierName (Lập bởi: $createdBy)',
        type: NotificationType.inventoryImported,
        createdAt: _now(),
        targetRoute: 'stock_in_detail',
        targetId: effectiveImportCode,
        metadata: {
          'receiptId': receipt.id,
          'importCode': effectiveImportCode,
          'supplierName': supplierName,
          'totalAmount': receipt.totalAmount,
          'customerName': supplierName,
          'customerId': supplierId,
          'createdBy': createdBy,
        },
      );

      try {
        await _repository.addNotification(notif);
      } catch (repoErr, repoSt) {
        debugPrint(
            '[NotificationDispatcher] RTDB addNotification error on notifyStockInCompleted: $repoErr\n$repoSt');
      }
      await _syncPushNotification(storeId, notif);
    } catch (e, stackTrace) {
      debugPrint(
          '[NotificationDispatcher] Failed to dispatch notifyStockInCompleted: $e\n$stackTrace');
    }
  }

  /// Dispatches an event when a new customer profile is created.
  Future<void> notifyCustomerCreated({
    required String storeId,
    required Customer customer,
    required UserAccount? user,
  }) async {
    try {
      final customerId = _resolveCustomerId(customer.id);
      final customerName = _resolveCustomerName(customer.name, customerId);
      final phone =
          _isValidString(customer.phone) ? customer.phone.trim() : '---';
      final createdBy = _resolveCreator(
        user,
        customer.createdBy,
      );

      final notif = NotificationItem(
        id: _generateId('NOTIF_CUST'),
        storeId: storeId,
        title: 'Khách hàng mới',
        body: '$customerName - SĐT: $phone (Tạo bởi: $createdBy)',
        type: NotificationType.customerCreated,
        createdAt: _now(),
        targetRoute: 'customer_detail',
        targetId: customerId,
        metadata: {
          'customerId': customerId,
          'customerName': customerName,
          'phone': phone,
          'createdBy': createdBy,
        },
      );

      try {
        await _repository.addNotification(notif);
      } catch (repoErr, repoSt) {
        debugPrint(
            '[NotificationDispatcher] RTDB addNotification error on notifyCustomerCreated: $repoErr\n$repoSt');
      }
      await _syncPushNotification(storeId, notif);
    } catch (e, stackTrace) {
      debugPrint(
          '[NotificationDispatcher] Failed to dispatch notifyCustomerCreated: $e\n$stackTrace');
    }
  }

  /// Dispatches an event when debt is incurred by a customer from an order.
  ///
  /// Safe against non-positive debt amounts (skipped).
  Future<void> notifyCustomerDebtAdded({
    required String storeId,
    required String customerId,
    required String customerName,
    required double debtAmount,
    required String orderId,
    required UserAccount? user,
  }) async {
    try {
      if (debtAmount <= 0) return;

      final effectiveId = _resolveCustomerId(customerId);
      final effectiveName = _resolveCustomerName(customerName, effectiveId);
      final createdBy = _resolveCreator(user);
      final effectiveOrderId = _isValidString(orderId) ? orderId.trim() : '---';

      final notif = NotificationItem(
        id: _generateId('NOTIF_DEBT'),
        storeId: storeId,
        title: 'Ghi nhận nợ mới',
        body:
            'Ghi nợ ${_formatCurrency(debtAmount)} từ đơn #$effectiveOrderId - Khách: $effectiveName (Bởi: $createdBy)',
        type: NotificationType.customerDebtAdded,
        createdAt: _now(),
        targetRoute: 'customer_debt',
        targetId: effectiveId,
        metadata: {
          'customerId': effectiveId,
          'customerName': effectiveName,
          'debtAmount': debtAmount,
          'orderId': effectiveOrderId,
          'createdBy': createdBy,
        },
      );

      try {
        await _repository.addNotification(notif);
      } catch (repoErr, repoSt) {
        debugPrint(
            '[NotificationDispatcher] RTDB addNotification error on notifyCustomerDebtAdded: $repoErr\n$repoSt');
      }
      await _syncPushNotification(storeId, notif);
    } catch (e, stackTrace) {
      debugPrint(
          '[NotificationDispatcher] Failed to dispatch notifyCustomerDebtAdded: $e\n$stackTrace');
    }
  }

  /// Dispatches an event when customer debt is paid/collected.
  ///
  /// Safe against non-positive collected amounts (skipped).
  Future<void> notifyCustomerDebtCollected({
    required String storeId,
    required String customerId,
    required String customerName,
    required double collectedAmount,
    required UserAccount? user,
    double? remainingDebt,
  }) async {
    try {
      if (collectedAmount <= 0) return;

      final effectiveId = _resolveCustomerId(customerId);
      final effectiveName = _resolveCustomerName(customerName, effectiveId);
      final createdBy = _resolveCreator(user);

      final body =
          'Thu ${_formatCurrency(collectedAmount)} từ khách $effectiveName (Thu bởi: $createdBy)';

      final notif = NotificationItem(
        id: _generateId('NOTIF_PAID'),
        storeId: storeId,
        title: 'Thu nợ khách hàng',
        body: body,
        type: NotificationType.customerDebtPaid,
        createdAt: _now(),
        targetRoute: 'customer_debt',
        targetId: effectiveId,
        metadata: {
          'customerId': effectiveId,
          'customerName': effectiveName,
          'collectedAmount': collectedAmount,
          'paidAmount': collectedAmount,
          if (remainingDebt != null) 'remainingDebt': remainingDebt,
          'createdBy': createdBy,
          'collectedBy': createdBy,
        },
      );

      try {
        await _repository.addNotification(notif);
      } catch (repoErr, repoSt) {
        debugPrint(
            '[NotificationDispatcher] RTDB addNotification error on notifyCustomerDebtCollected: $repoErr\n$repoSt');
      }
      await _syncPushNotification(storeId, notif);
    } catch (e, stackTrace) {
      debugPrint(
          '[NotificationDispatcher] Failed to dispatch notifyCustomerDebtCollected: $e\n$stackTrace');
    }
  }
}
