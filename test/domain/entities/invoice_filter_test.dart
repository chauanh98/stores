import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/invoice_filter.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';

void main() {
  group('InvoiceFilter Entity Tests', () {
    final now = DateTime(2026, 8, 17, 10, 0);

    final baseOrder = Order(
      id: 'HD000001',
      customerId: 'CUST001',
      createdAt: now,
      items: [
        OrderItem(
          productId: 'IP17',
          productName: 'iPhone 17 Pro Max',
          quantity: 1,
          price: 35000000,
          warrantyMonths: 12,
          purchaseDate: now,
        ),
      ],
      total: 35000000,
      amountPaid: 20000000,
      debtAmount: 15000000,
      paymentMethod: 'transfer',
      createdBy: 'nhanvien1',
      createdByName: 'Nguyen Van A',
      status: 'completed',
    );

    test('Initial filter matches any standard order', () {
      const filter = InvoiceFilter();
      expect(filter.isFilteringActive, false);
      expect(filter.matches(baseOrder), true);
    });

    test('Filter by status', () {
      const filterCompleted = InvoiceFilter(status: 'completed');
      const filterCancelled = InvoiceFilter(status: 'cancelled');
      const filterDraft = InvoiceFilter(status: 'draft');

      expect(filterCompleted.matches(baseOrder), true);
      expect(filterCancelled.matches(baseOrder), false);
      expect(filterDraft.matches(baseOrder), false);

      final cancelledOrder = baseOrder.copyWith(status: 'cancelled');
      expect(filterCancelled.matches(cancelledOrder), true);
      expect(filterCompleted.matches(cancelledOrder), false);
    });

    test('Filter by payment method', () {
      const filterTransfer = InvoiceFilter(paymentMethod: 'transfer');
      const filterCash = InvoiceFilter(paymentMethod: 'cash');

      expect(filterTransfer.matches(baseOrder), true);
      expect(filterCash.matches(baseOrder), false);

      final cashOrder = baseOrder.copyWith(paymentMethod: 'cash');
      expect(filterCash.matches(cashOrder), true);
      expect(filterTransfer.matches(cashOrder), false);
    });

    test('Filter by debt status', () {
      const filterDebt = InvoiceFilter(debtStatus: 'debt');
      const filterPaid = InvoiceFilter(debtStatus: 'paid');

      // baseOrder has remainingDebt = 15,000,000 > 0
      expect(filterDebt.matches(baseOrder), true);
      expect(filterPaid.matches(baseOrder), false);

      final paidOrder = baseOrder.copyWith(amountPaid: 35000000, debtAmount: 0);
      expect(filterPaid.matches(paidOrder), true);
      expect(filterDebt.matches(paidOrder), false);
    });

    test('Filter by staff username and staff display name', () {
      const filterStaff1 = InvoiceFilter(staffId: 'nhanvien1');
      const filterStaff2 = InvoiceFilter(staffId: 'nhanvien2');
      const filterName = InvoiceFilter(staffName: 'Nguyen Van A');

      expect(filterStaff1.matches(baseOrder), true);
      expect(filterStaff2.matches(baseOrder), false);
      expect(filterName.matches(baseOrder), true);
    });

    test('Filter by search query (Order ID, customer name, phone, item name)', () {
      const filterById = InvoiceFilter(searchQuery: 'HD000001');
      const filterByProduct = InvoiceFilter(searchQuery: 'iPhone 17');
      const filterByName = InvoiceFilter(searchQuery: 'Tran Thi B');
      const filterByPhone = InvoiceFilter(searchQuery: '0901234567');

      expect(filterById.matches(baseOrder), true);
      expect(filterByProduct.matches(baseOrder), true);
      expect(
        filterByName.matches(baseOrder, customerName: 'Tran Thi B'),
        true,
      );
      expect(
        filterByPhone.matches(baseOrder, customerPhone: '0901234567'),
        true,
      );
      expect(
        const InvoiceFilter(searchQuery: 'KhongKhop').matches(baseOrder),
        false,
      );
    });

    test('Filter by date range', () {
      final filterToday = InvoiceFilter(
        startDate: DateTime(2026, 8, 17),
        endDate: DateTime(2026, 8, 17),
      );
      final filterYesterday = InvoiceFilter(
        startDate: DateTime(2026, 8, 16),
        endDate: DateTime(2026, 8, 16),
      );

      expect(filterToday.matches(baseOrder), true);
      expect(filterYesterday.matches(baseOrder), false);
    });

    test('copyWith and clear resets state', () {
      const filter = InvoiceFilter(
        status: 'completed',
        paymentMethod: 'cash',
        debtStatus: 'debt',
        staffId: 'nhanvien1',
        searchQuery: 'HD001',
      );

      expect(filter.isFilteringActive, true);

      final updated = filter.copyWith(paymentMethod: 'transfer');
      expect(updated.paymentMethod, 'transfer');
      expect(updated.status, 'completed');

      final cleared = filter.clear();
      expect(cleared.isFilteringActive, false);
      expect(cleared.status, 'all');
      expect(cleared.paymentMethod, 'all');
      expect(cleared.debtStatus, 'all');
      expect(cleared.searchQuery, '');
    });

  });
}
