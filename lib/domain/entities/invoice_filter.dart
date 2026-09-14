import 'order.dart';

class InvoiceFilter {
  final String status; // 'all', 'completed', 'draft', 'cancelled', 'returned'
  final String paymentMethod; // 'all', 'cash', 'transfer'
  final String debtStatus; // 'all', 'paid', 'debt'
  final String? staffId; // username or ID of creator
  final String? staffName; // display name of creator
  final String searchQuery;
  final DateTime? startDate;
  final DateTime? endDate;

  const InvoiceFilter({
    this.status = 'all',
    this.paymentMethod = 'all',
    this.debtStatus = 'all',
    this.staffId,
    this.staffName,
    this.searchQuery = '',
    this.startDate,
    this.endDate,
  });

  bool get isFilteringActive {
    return status != 'all' ||
        paymentMethod != 'all' ||
        debtStatus != 'all' ||
        (staffId != null && staffId != 'all' && staffId!.isNotEmpty) ||
        (staffName != null && staffName != 'all' && staffName!.isNotEmpty) ||
        searchQuery.trim().isNotEmpty ||
        startDate != null ||
        endDate != null;
  }

  bool matches(
    Order order, {
    String? customerName,
    String? customerPhone,
    String? customerCode,
  }) {
    // 1. Filter by Status
    if (status != 'all') {
      if (status == 'has_debt') {
        if (order.remainingDebt <= 0.001) return false;
      } else if (status == 'paid') {
        if (order.remainingDebt > 0.001) return false;
      } else if (order.status != status) {
        return false;
      }
    }

    // 2. Filter by Payment Method
    if (paymentMethod != 'all') {
      if (order.paymentMethod != paymentMethod) return false;
    }

    // 3. Filter by Debt Status
    if (debtStatus != 'all') {
      final remaining = order.remainingDebt;
      if (debtStatus == 'paid' && remaining > 0.001) return false;
      if (debtStatus == 'debt' && remaining <= 0.001) return false;
      if (debtStatus == 'has_debt' && remaining <= 0.001) return false;
    }

    // 4. Filter by Staff
    if (staffId != null && staffId != 'all' && staffId!.trim().isNotEmpty) {
      final target = staffId!.trim().toLowerCase();
      final orderStaff = (order.createdBy ?? '').trim().toLowerCase();
      if (orderStaff != target) return false;
    }
    if (staffName != null && staffName != 'all' && staffName!.trim().isNotEmpty) {
      final target = staffName!.trim().toLowerCase();
      final orderStaffName = (order.createdByName ?? '').trim().toLowerCase();
      if (!orderStaffName.contains(target)) return false;
    }

    // 5. Filter by Date Range
    if (startDate != null) {
      final start = DateTime(
          startDate!.year, startDate!.month, startDate!.day, 0, 0, 0, 0);
      if (order.createdAt.isBefore(start)) return false;
    }
    if (endDate != null) {
      final end = DateTime(
          endDate!.year, endDate!.month, endDate!.day, 23, 59, 59, 999);
      if (order.createdAt.isAfter(end)) return false;
    }

    // 6. Filter by Search Query
    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase().trim();
      final idMatch = order.id.toLowerCase().contains(q);
      final customerIdMatch = order.customerId.toLowerCase().contains(q);
      final customerCodeMatch =
          customerCode?.toLowerCase().contains(q) ?? false;
      final cNameMatch = customerName?.toLowerCase().contains(q) ?? false;
      final cPhoneMatch = customerPhone?.toLowerCase().contains(q) ?? false;
      final staffMatch =
          (order.createdByName ?? order.createdBy ?? '').toLowerCase().contains(q);
      final itemMatch =
          order.items.any((i) => i.productName.toLowerCase().contains(q) || i.productId.toLowerCase().contains(q));

      if (!idMatch &&
          !customerIdMatch &&
          !customerCodeMatch &&
          !cNameMatch &&
          !cPhoneMatch &&
          !staffMatch &&
          !itemMatch) {
        return false;
      }
    }

    return true;
  }

  InvoiceFilter copyWith({
    String? status,
    String? paymentMethod,
    String? debtStatus,
    String? staffId,
    String? staffName,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    bool clearDates = false,
    bool clearStaff = false,
  }) {
    return InvoiceFilter(
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      debtStatus: debtStatus ?? this.debtStatus,
      staffId: clearStaff ? null : (staffId ?? this.staffId),
      staffName: clearStaff ? null : (staffName ?? this.staffName),
      searchQuery: searchQuery ?? this.searchQuery,
      startDate: clearDates ? null : (startDate ?? this.startDate),
      endDate: clearDates ? null : (endDate ?? this.endDate),
    );
  }

  InvoiceFilter clear() {
    return const InvoiceFilter();
  }

  static const initial = InvoiceFilter();
}
