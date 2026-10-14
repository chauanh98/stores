import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/presentation/customers/pages/add_customer_page.dart';
import 'package:stores/presentation/customers/pages/customer_debt_adjustment_page.dart';
import 'package:stores/presentation/customers/pages/customer_debt_page.dart';
import 'package:stores/presentation/customers/pages/customer_detail_page.dart';
import 'package:stores/presentation/customers/pages/customer_transactions_page.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/customers/widgets/customer_list_tile.dart';

import 'sweep_harness.dart';

class _Customers extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _Customers(this.list, {this.fail = false});
  final List<Customer> list;
  final bool fail;
  @override
  Future<List<Customer>> build() async {
    if (fail) throw Exception('boom');
    return list;
  }

  @override
  Future<void> refresh() async => state = AsyncValue.data(list);
}

List<Customer> customers(int n) => [
      for (var i = 0; i < n; i++)
        Customer(
          id: 'c$i',
          name: i % 3 == 0
              ? 'Nguyễn Thị Thanh Thảo Hoàng Gia Bảo Châu Quận Bình Thạnh $i'
              : 'Khách $i',
          phone: '09012345$i',
          email: 'khach.hang.co.email.rat.dai.$i@congtyxyz.example.com',
          address:
              'Số 123/45/6 Đường Nguyễn Hữu Cảnh, Phường 22, Quận Bình Thạnh, TP Hồ Chí Minh',
          purchases: const [],
          branch: 'store_001',
          createdAt: '2026-08-01 10:00:00',
          totalSales: sweepHugeMoney,
          netSales: sweepHugeMoney,
          currentDebt: sweepHugeMoney,
          company: 'Công ty TNHH Một Thành Viên Thương Mại Dịch Vụ Rất Dài',
          notes: 'Ghi chú rất dài ' * 10,
        ),
    ];

Order _order(String cid, int i) => Order(
      id: 'o$i',
      customerId: cid,
      customerName: 'Nguyễn Thị Thanh Thảo Hoàng Gia Bảo Châu',
      createdAt: DateTime(2026, 9, 1).subtract(Duration(days: i)),
      items: [
        OrderItem(
            productId: 'p',
            productName: sweepLongName,
            quantity: 1000000,
            price: sweepHugeMoney,
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 9, 1)),
      ],
      total: sweepHugeMoney,
      amountPaid: 1,
      debtAmount: sweepHugeMoney,
      storeId: 'store_001',
    );

CustomerDebtTransaction _tx(String cid, int i) => CustomerDebtTransaction(
      id: 't$i',
      code: 'TTHD0127230000$i',
      customerId: cid,
      date: DateTime(2026, 9, 1).subtract(Duration(days: i)),
      amount: i.isEven ? sweepHugeMoney : -sweepHugeMoney,
      remainingDebt: sweepHugeMoney,
      type: DebtTransactionType.values[i % 3],
      note: 'Ghi chú điều chỉnh công nợ rất dài để kiểm tra tràn dòng ' * 3,
    );

List<Override> _ov(user, List<Customer> list,
        {bool fail = false, int orders = 30}) =>
    [
      authProvider.overrideWith((ref) => SweepAuth(user)),
      currentStoreIdProvider.overrideWithValue('store_001'),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': sweepLongStore,
            'store_002': 'Chi nhánh Thới Bình',
          }),
      customerListNotifierProvider
          .overrideWith(() => _Customers(list, fail: fail)),
      customerOrdersProvider.overrideWith((ref, id) =>
          Stream.value([for (var i = 0; i < orders; i++) _order(id, i)])),
      customerDebtTransactionsProvider.overrideWith((ref, id) =>
          Stream.value([for (var i = 0; i < orders; i++) _tx(id, i)])),
    ];

void main() {
  final one = customers(1).first;
  final small = {'320x568': sweepScreens['320x568']!};

  sweepMatrix('CustomersPage(40)', () => const CustomersPage(),
      (u) => _ov(u, customers(40)));
  sweepMatrix('CustomersPage(empty)', () => const CustomersPage(),
      (u) => _ov(u, const []),
      screens: small);
  sweepMatrix('CustomersPage(error)', () => const CustomersPage(),
      (u) => _ov(u, const [], fail: true),
      screens: small);
  sweepMatrix('CustomerDetailPage', () => CustomerDetailPage(customer: one),
      (u) => _ov(u, [one]));
  sweepMatrix('CustomerDebtPage', () => CustomerDebtPage(customer: one),
      (u) => _ov(u, [one]));
  sweepMatrix('CustomerTransactionsPage',
      () => CustomerTransactionsPage(customer: one), (u) => _ov(u, [one]));
  sweepMatrix('CustomerDebtAdjustmentPage',
      () => CustomerDebtAdjustmentPage(customer: one), (u) => _ov(u, [one]));
  sweepMatrix(
      'AddCustomerPage', () => const AddCustomerPage(), (u) => _ov(u, [one]));

  testWidgets('CustomersPage with 500 customers builds lazily', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        sweepHost(const CustomersPage(), _ov(sweepAdmin, customers(500))));
    await tester.pumpAndSettle();
    expectNoException(tester);
    expect(find.byType(CustomerListTile).evaluate().length, lessThan(60));
  });
}
