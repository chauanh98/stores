import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/suppliers/supplier_list_notifier.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/presentation/customers/pages/add_customer_page.dart';
import 'package:stores/presentation/customers/pages/customer_debt_adjustment_page.dart';
import 'package:stores/presentation/customers/pages/customer_debt_page.dart';
import 'package:stores/presentation/customers/pages/customer_detail_page.dart';
import 'package:stores/presentation/customers/pages/customer_transactions_page.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/customers/widgets/customer_list_tile.dart';
import 'package:stores/presentation/suppliers/pages/add_edit_supplier_page.dart';
import 'package:stores/presentation/suppliers/pages/supplier_detail_page.dart';
import 'package:stores/presentation/suppliers/pages/suppliers_page.dart';
import 'package:stores/presentation/suppliers/widgets/supplier_debt_adjustment_dialog.dart';
import 'package:stores/presentation/suppliers/widgets/supplier_debt_payment_dialog.dart';
import 'package:stores/presentation/suppliers/widgets/supplier_list_tile.dart';

import 'stress_kit.dart';

class _Customers extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _Customers(this.list);
  final List<Customer> list;
  @override
  Future<List<Customer>> build() async => list;
  @override
  Future<void> refresh() async => state = AsyncValue.data(list);
  @override
  dynamic noSuchMethod(Invocation i) async {}
}

class _Suppliers extends AutoDisposeAsyncNotifier<List<Supplier>>
    implements SupplierListNotifier {
  _Suppliers(this.list);
  final List<Supplier> list;
  @override
  Future<List<Supplier>> build() async => list;
  @override
  Future<void> refresh() async {}
  @override
  dynamic noSuchMethod(Invocation i) async {}
}

final _g = Gen();
final customers = _g.customers(2000);
final suppliers = _g.suppliers(500);

Order _order(String cid, int i) => Order(
      id: 'o$i',
      customerId: cid,
      customerName: _g.adv(),
      createdAt: DateTime(2026, 9, 1).subtract(Duration(days: i)),
      items: [
        OrderItem(
            productId: 'p',
            productName: _g.adv(),
            quantity: _g.r.nextInt(1000000),
            price: _g.amount(),
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 9, 1)),
      ],
      total: _g.amount(),
      amountPaid: _g.amount(),
      debtAmount: _g.amount(),
      storeId: 'store_001',
    );

CustomerDebtTransaction _tx(String cid, int i) => CustomerDebtTransaction(
      id: 't$i',
      code: 'TT$i',
      customerId: cid,
      date: DateTime(2026, 9, 1).subtract(Duration(days: i)),
      amount: _g.amount(),
      remainingDebt: _g.amount(),
      type: DebtTransactionType.values[i % 3],
      note: _g.adv(),
    );

SupplierDebtTransaction _stx(String id, int i) => SupplierDebtTransaction(
      id: 'T$i',
      supplierId: id,
      date: DateTime(2026, 8, 15).subtract(Duration(days: i)),
      type: SupplierDebtType.values[i % 4],
      amount: _g.amount(),
      remainingDebt: _g.amount(),
      referenceCode: 'PN$i',
      note: _g.adv(),
    );

List<Override> ov(user, {List<Customer>? c, List<Supplier>? s}) => [
      authProvider.overrideWith((ref) => SweepAuth(user)),
      currentStoreIdProvider.overrideWithValue('store_001'),
      availableStoresProvider.overrideWith((ref) async =>
          {'store_001': sweepLongStore, 'store_002': 'Chi nhánh Thới Bình'}),
      customerListNotifierProvider
          .overrideWith(() => _Customers(c ?? customers)),
      supplierListNotifierProvider
          .overrideWith(() => _Suppliers(s ?? suppliers)),
      customerOrdersProvider.overrideWith((ref, id) =>
          Stream.value([for (var i = 0; i < 300; i++) _order(id, i)])),
      customerDebtTransactionsProvider.overrideWith((ref, id) =>
          Stream.value([for (var i = 0; i < 300; i++) _tx(id, i)])),
      supplierDebtTransactionsProvider.overrideWith((ref, id) =>
          Stream.value([for (var i = 0; i < 300; i++) _stx(id, i)])),
    ];

final _adv = Customer(
    id: 'adv',
    name: longWord,
    phone: emojiStr,
    email: rtl,
    address: '$newlines$zeroWidth',
    purchases: const [],
    currentDebt: 1e12,
    totalSales: -1e12,
    netSales: 0,
    notes: '$combining\n$longWord');
final _advSup = Supplier(
    id: 'advs',
    code: longWord,
    name: emojiStr * 10,
    phone: rtl,
    email: longWord,
    address: newlines,
    currentDebt: -1e12,
    totalPurchase: 1e12,
    note: longWord);

void main() {
  stressMatrix('CustomersPage(2000)', () => const CustomersPage(), (u) => ov(u),
      check: (t, d) async {
    final n = built(CustomerListTile);
    expect(n, lessThan(100), reason: 'built $n of 2000');
    await t.fling(find.byType(Scrollable).first, const Offset(0, -4000), 6000);
    await t.pumpAndSettle();
  });
  stressMatrix('CustomersPage(empty)', () => const CustomersPage(),
      (u) => ov(u, c: const []),
      rot: 2);
  final one = customers[3];
  for (final entry in <String, Customer>{'gen': one, 'adv': _adv}.entries) {
    final c = entry.value;
    final r = entry.key == 'gen' ? 0 : 3;
    stressMatrix('CustomerDetailPage(${entry.key})',
        () => CustomerDetailPage(customer: c), (u) => ov(u, c: [c]),
        rot: r);
    stressMatrix('CustomerDebtPage(${entry.key})',
        () => CustomerDebtPage(customer: c), (u) => ov(u, c: [c]),
        rot: r + 1);
    stressMatrix('CustomerTransactionsPage(${entry.key})',
        () => CustomerTransactionsPage(customer: c), (u) => ov(u, c: [c]),
        rot: r + 2);
    stressMatrix('CustomerDebtAdjustmentPage(${entry.key})',
        () => CustomerDebtAdjustmentPage(customer: c), (u) => ov(u, c: [c]),
        rot: r + 3);
  }
  stressMatrix('AddCustomerPage', () => const AddCustomerPage(), (u) => ov(u),
      rot: 1);

  stressMatrix('SuppliersPage(500)', () => const SuppliersPage(), (u) => ov(u),
      rot: 1, check: (t, d) async {
    expect(built(SupplierListTile), lessThan(100));
    await t.fling(find.byType(Scrollable).first, const Offset(0, -4000), 6000);
    await t.pumpAndSettle();
  });
  stressMatrix('SuppliersPage(empty)', () => const SuppliersPage(),
      (u) => ov(u, s: const []),
      rot: 3);
  for (final entry
      in <String, Supplier>{'gen': suppliers[2], 'adv': _advSup}.entries) {
    final s = entry.value;
    final r = entry.key == 'gen' ? 2 : 4;
    stressMatrix('SupplierDetailPage(${entry.key})',
        () => SupplierDetailPage(supplier: s), (u) => ov(u, s: [s]),
        rot: r);
    stressMatrix('AddEditSupplierPage(${entry.key})',
        () => AddEditSupplierPage(supplier: s), (u) => ov(u, s: [s]),
        rot: r + 1);
    stressMatrix(
        'SupplierDebtPaymentDialog(${entry.key})',
        () => Opener((_) => SupplierDebtPaymentDialog(supplier: s)),
        (u) => ov(u, s: [s]),
        rot: r + 2);
    stressMatrix(
        'SupplierDebtAdjustmentDialog(${entry.key})',
        () => Opener((_) => SupplierDebtAdjustmentDialog(supplier: s)),
        (u) => ov(u, s: [s]),
        rot: r + 3);
  }
  stressMatrix('AddEditSupplierPage(new)', () => const AddEditSupplierPage(),
      (u) => ov(u),
      rot: 2);
}
