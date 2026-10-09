import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/customers/customers_providers.dart';
import '../../../application/notifications/notifications_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../domain/entities/customer.dart';
import '../../customers/pages/customer_debt_page.dart';
import '../../customers/pages/customer_detail_page.dart';
import '../../inventories/widgets/stock_in_receipt_detail_bottom_sheet.dart';
import '../../orders/widgets/invoice_detail_bottom_sheet.dart';
import '../../orders/widgets/return_order_detail_bottom_sheet.dart';

/// Context-safe deep linking dispatcher for in-app notification taps.
///
/// Follows strict context safety rules (guarded with `if (!context.mounted) return;`
/// after every async gap) and handles all business event targets gracefully.
class NotificationNavigationHandler {
  const NotificationNavigationHandler._();

  /// Primary tap dispatcher.
  /// 1. Marks notification as read if unread.
  /// 2. Deep links to Invoice Detail, Stock-In Detail, or Customer Debt/Detail.
  static Future<void> handleTap({
    required BuildContext context,
    required WidgetRef ref,
    required NotificationItem notification,
  }) async {
    final targetRoute = notification.targetRoute ?? '';
    final targetId = notification.targetId ?? '';
    final isOrder = targetRoute == 'invoice_detail' ||
        notification.category == NotificationCategory.orders;
    final isCustomer = targetRoute == 'customer_debt' ||
        targetRoute == 'customer_detail' ||
        notification.category == NotificationCategory.customers;

    // Synchronously capture required providers before any async gaps
    String storeId = '';
    try {
      storeId = ref.read(currentStoreIdProvider);
    } catch (_) {}

    NotificationController? notifController;
    try {
      notifController = ref.read(notificationControllerProvider.notifier);
    } catch (_) {}

    dynamic orderRepo;
    if (isOrder) {
      try {
        orderRepo = ref.read(orderRepositoryProvider);
      } catch (_) {}
    }

    dynamic customerRepo;
    List<Customer>? inMemoryCustomers;
    if (isCustomer) {
      try {
        customerRepo = ref.read(customerRepositoryProvider);
      } catch (_) {}
      try {
        inMemoryCustomers =
            ref.read(customerListNotifierProvider).valueOrNull;
      } catch (_) {}
    }

    // 1. Mark as read immediately
    if (!notification.isRead && notifController != null) {
      try {
        final effectiveStoreId = notification.storeId.isNotEmpty
            ? notification.storeId
            : storeId;
        await notifController.markAsRead(
          notification.id,
          storeId: effectiveStoreId,
        );
      } catch (e) {
        debugPrint(
            '[NotificationNavigation] Error marking notification as read: $e');
      }
    }

    if (!context.mounted) return;

    if (targetId.isEmpty) return;

    // 2. Route by event category / target route
    if (isOrder) {
      await _navigateToOrder(context, orderRepo, targetId);
    } else if (targetRoute == 'stock_in_detail' ||
        notification.category == NotificationCategory.inventory) {
      await _navigateToStockIn(context, targetId);
    } else if (isCustomer) {
      await _navigateToCustomer(
        context,
        customerRepo,
        inMemoryCustomers,
        targetId,
        isDebtPage: targetRoute == 'customer_debt' ||
            notification.type == NotificationType.customerDebtAdded ||
            notification.type == NotificationType.customerDebtPaid,
        fallbackName: notification.metadata?['customerName'] as String?,
        fallbackPhone: notification.metadata?['phone'] as String?,
      );
    }
  }

  /// Looks up order by ID and opens either ReturnOrderDetailBottomSheet or InvoiceDetailBottomSheet.
  static Future<void> _navigateToOrder(
    BuildContext context,
    dynamic orderRepo,
    String orderId,
  ) async {
    try {
      final order =
          orderRepo != null ? await orderRepo.fetchById(orderId) : null;

      if (!context.mounted) return;

      if (order != null) {
        if (order.isReturned) {
          await ReturnOrderDetailBottomSheet.show(context, order: order);
        } else {
          await InvoiceDetailBottomSheet.show(context, order);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không tìm thấy thông tin đơn hàng #$orderId'),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi tải thông tin đơn hàng #$orderId: $e'),
        ),
      );
    }
  }

  /// Opens Stock-In Receipt detail bottom sheet using importCode.
  static Future<void> _navigateToStockIn(
    BuildContext context,
    String importCode,
  ) async {
    await StockInReceiptDetailBottomSheet.show(
      context,
      importCode: importCode,
    );
  }

  /// Looks up customer and pushes either CustomerDebtPage or CustomerDetailPage.
  static Future<void> _navigateToCustomer(
    BuildContext context,
    dynamic customerRepo,
    List<Customer>? inMemoryCustomers,
    String customerId, {
    required bool isDebtPage,
    String? fallbackName,
    String? fallbackPhone,
  }) async {
    try {
      // Check in-memory cache first
      Customer? customer = inMemoryCustomers
          ?.where((c) => c.id == customerId)
          .firstOrNull;

      if (customer == null && customerRepo != null) {
        customer = await customerRepo.fetchById(customerId);
      }

      if (!context.mounted) return;

      // Resilient fallback representation if deleted or unindexed
      if (customer == null && fallbackName != null && fallbackName.isNotEmpty) {
        customer = Customer(
          id: customerId,
          name: fallbackName,
          phone: fallbackPhone ?? '',
          email: '',
          address: '',
          purchases: const [],
        );
      }

      final resolvedCustomer = customer;
      if (resolvedCustomer != null) {
        if (isDebtPage) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CustomerDebtPage(customer: resolvedCustomer),
            ),
          );
        } else {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CustomerDetailPage(customer: resolvedCustomer),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không tìm thấy thông tin khách hàng #$customerId'),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi tải thông tin khách hàng #$customerId: $e'),
        ),
      );
    }
  }
}
