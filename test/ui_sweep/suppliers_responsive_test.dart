import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/suppliers/supplier_list_notifier.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/presentation/suppliers/pages/add_edit_supplier_page.dart';
import 'package:stores/presentation/suppliers/pages/supplier_detail_page.dart';
import 'package:stores/presentation/suppliers/pages/suppliers_page.dart';
import 'package:stores/presentation/suppliers/widgets/supplier_debt_adjustment_dialog.dart';
import 'package:stores/presentation/suppliers/widgets/supplier_debt_payment_dialog.dart';
import 'package:stores/presentation/suppliers/widgets/supplier_list_tile.dart';

import 'sweep_harness.dart';

class _Suppliers extends AutoDisposeAsyncNotifier<List<Supplier>>
    implements SupplierListNotifier {
  _Suppliers(this.list, {this.fail = false});
  final List<Supplier> list;
  final bool fail;
  @override
  Future<List<Supplier>> build() async {
    if (fail) throw Exception('boom');
    return list;
  }

  @override
  Future<void> refresh() async {}
  @override
  dynamic noSuchMethod(Invocation i) async {}
}

List<Supplier> suppliers(int n) => [
      for (var i = 0; i < n; i++)
        Supplier(
          id: 'NCC$i',
          code: 'NCC00000$i',
          name: i % 3 == 0
              ? 'Công ty Trách nhiệm hữu hạn Thương mại Dịch vụ Xuất nhập khẩu Rất Dài $i'
              : 'Nhà cung cấp $i',
          phone: '0283929123$i',
          email: 'lien.he.nha.cung.cap.rat.dai.$i@congtyxyz.example.com',
          address:
              'Số 123/45/6 Đường Nguyễn Hữu Cảnh, Phường 22, Quận Bình Thạnh, TP Hồ Chí Minh',
          taxCode: '0302861742',
          totalPurchase: sweepHugeMoney,
          currentDebt: sweepHugeMoney,
          note: 'Ghi chú rất dài ' * 10,
        ),
    ];

SupplierDebtTransaction _tx(String id, int i) => SupplierDebtTransaction(
      id: 'T$i',
      supplierId: id,
      date: DateTime(2026, 8, 15).subtract(Duration(days: i)),
      type: SupplierDebtType.values[i % 4],
      amount: sweepHugeMoney,
      remainingDebt: sweepHugeMoney,
      referenceCode: 'PN000000000000$i',
      note: 'Ghi chú giao dịch rất dài để kiểm tra tràn dòng ' * 3,
    );

List<Override> _ov(user, List<Supplier> list, {bool fail = false}) => [
      authProvider.overrideWith((ref) => SweepAuth(user)),
      currentStoreIdProvider.overrideWithValue('store_001'),
      supplierListNotifierProvider
          .overrideWith(() => _Suppliers(list, fail: fail)),
      supplierDebtTransactionsProvider.overrideWith(
          (ref, id) => Stream.value([for (var i = 0; i < 30; i++) _tx(id, i)])),
    ];

void main() {
  final one = suppliers(1).first;
  final small = {'320x568': sweepScreens['320x568']!};
  sweepMatrix('SuppliersPage(40)', () => const SuppliersPage(),
      (u) => _ov(u, suppliers(40)));
  sweepMatrix('SuppliersPage(empty)', () => const SuppliersPage(),
      (u) => _ov(u, const []),
      screens: small);
  sweepMatrix('SuppliersPage(error)', () => const SuppliersPage(),
      (u) => _ov(u, const [], fail: true),
      screens: small);
  sweepMatrix('SupplierDetailPage', () => SupplierDetailPage(supplier: one),
      (u) => _ov(u, [one]));
  sweepMatrix('AddEditSupplierPage(new)', () => const AddEditSupplierPage(),
      (u) => _ov(u, [one]));
  sweepMatrix('AddEditSupplierPage(edit)',
      () => AddEditSupplierPage(supplier: one), (u) => _ov(u, [one]));

  sweepMatrix(
      'SupplierDebtPaymentDialog',
      () => Scaffold(body: SupplierDebtPaymentDialog(supplier: one)),
      (u) => _ov(u, [one]));
  sweepMatrix(
      'SupplierDebtAdjustmentDialog',
      () => Scaffold(body: SupplierDebtAdjustmentDialog(supplier: one)),
      (u) => _ov(u, [one]));

  testWidgets('SuppliersPage with 500 suppliers builds lazily', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        sweepHost(const SuppliersPage(), _ov(sweepAdmin, suppliers(500))));
    await tester.pumpAndSettle();
    expectNoException(tester);
    expect(find.byType(SupplierListTile).evaluate().length, lessThan(60));
  });
}
