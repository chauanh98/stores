/// Broad category of notifications in the system.
enum NotificationCategory {
  orders('orders'),
  inventory('inventory'),
  customers('customers'),
  system('system');

  final String value;
  const NotificationCategory(this.value);

  /// Safe parser with fallback to [NotificationCategory.system].
  static NotificationCategory fromString(String? raw) {
    if (raw == null) return NotificationCategory.system;
    final normalized = raw.trim().toLowerCase();
    for (final cat in NotificationCategory.values) {
      if (cat.name.toLowerCase() == normalized ||
          cat.value.toLowerCase() == normalized) {
        return cat;
      }
    }
    return NotificationCategory.system;
  }
}

/// Granular business event types that generate notifications.
enum NotificationType {
  orderCreated('order_created', NotificationCategory.orders),
  orderUpdated('order_updated', NotificationCategory.orders),
  orderCancelled('order_cancelled', NotificationCategory.orders),
  orderReturn('order_return', NotificationCategory.orders),
  inventoryImported('inventory_imported', NotificationCategory.inventory),
  customerCreated('customer_created', NotificationCategory.customers),
  customerDebtAdded('customer_debt_added', NotificationCategory.customers),
  customerDebtPaid('customer_debt_paid', NotificationCategory.customers);

  final String value;
  final NotificationCategory category;

  const NotificationType(this.value, this.category);

  /// Safe parser tolerant of snake_case, camelCase, and keywords.
  static NotificationType fromString(String? raw) {
    if (raw == null) return NotificationType.orderCreated;
    final normalized = raw.trim().toLowerCase().replaceAll('-', '_');
    for (final type in NotificationType.values) {
      if (type.value.toLowerCase() == normalized ||
          type.name.toLowerCase() == normalized ||
          type.name.toLowerCase() == normalized.replaceAll('_', '')) {
        return type;
      }
    }

    // Tolerant keyword matching
    if (normalized.contains('cancel')) return NotificationType.orderCancelled;
    if (normalized.contains('return')) return NotificationType.orderReturn;
    if (normalized.contains('update') || normalized.contains('edit')) {
      return NotificationType.orderUpdated;
    }
    if (normalized.contains('order')) return NotificationType.orderCreated;
    if (normalized.contains('invent') ||
        normalized.contains('import') ||
        normalized.contains('stock')) {
      return NotificationType.inventoryImported;
    }
    if (normalized.contains('paid') || normalized.contains('collect')) {
      return NotificationType.customerDebtPaid;
    }
    if (normalized.contains('debt')) return NotificationType.customerDebtAdded;
    if (normalized.contains('customer')) return NotificationType.customerCreated;
    return NotificationType.orderCreated;
  }
}
