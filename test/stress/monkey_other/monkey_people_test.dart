import 'package:flutter/material.dart';
import 'package:stores/presentation/customers/pages/add_customer_page.dart';
import 'package:stores/presentation/customers/pages/customer_debt_adjustment_page.dart';
import 'package:stores/presentation/customers/pages/customer_debt_page.dart';
import 'package:stores/presentation/customers/pages/customer_detail_page.dart';
import 'package:stores/presentation/customers/pages/customer_transactions_page.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/suppliers/pages/add_edit_supplier_page.dart';
import 'package:stores/presentation/suppliers/pages/supplier_detail_page.dart';
import 'package:stores/presentation/suppliers/pages/suppliers_page.dart';
import 'package:stores/presentation/suppliers/widgets/supplier_debt_adjustment_dialog.dart';
import 'package:stores/presentation/suppliers/widgets/supplier_debt_payment_dialog.dart';

import '../ui_matrix_other/customers_suppliers_matrix_test.dart' as cs;
import 'monkey_kit.dart';

void main() {
  final c = cs.customers[5];
  final s = cs.suppliers[4];
  monkeyTest(
      'CustomersPage(2000)', () => const CustomersPage(), (u) => cs.ov(u));
  monkeyTest('AddCustomerPage', () => const AddCustomerPage(), (u) => cs.ov(u));
  monkeyTest('CustomerDetailPage', () => CustomerDetailPage(customer: c),
      (u) => cs.ov(u, c: [c]));
  monkeyTest('CustomerDebtPage', () => CustomerDebtPage(customer: c),
      (u) => cs.ov(u, c: [c]));
  monkeyTest('CustomerDebtAdjustmentPage',
      () => CustomerDebtAdjustmentPage(customer: c), (u) => cs.ov(u, c: [c]));
  monkeyTest('CustomerTransactionsPage',
      () => CustomerTransactionsPage(customer: c), (u) => cs.ov(u, c: [c]));

  monkeyTest(
      'SuppliersPage(500)', () => const SuppliersPage(), (u) => cs.ov(u));
  monkeyTest('AddEditSupplierPage', () => const AddEditSupplierPage(),
      (u) => cs.ov(u));
  monkeyTest('SupplierDetailPage', () => SupplierDetailPage(supplier: s),
      (u) => cs.ov(u, s: [s]));
  monkeyTest(
      'SupplierDebtPaymentDialog',
      () => Opener((_) => SupplierDebtPaymentDialog(supplier: s)),
      (u) => cs.ov(u, s: [s]));
  monkeyTest(
      'SupplierDebtAdjustmentDialog',
      () => Opener((_) => SupplierDebtAdjustmentDialog(supplier: s)),
      (u) => cs.ov(u, s: [s]));
}
