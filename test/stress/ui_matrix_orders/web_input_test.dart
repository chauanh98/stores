// Mouse / keyboard specifics (web & desktop): hover, wheel scroll, Tab focus
// traversal and Enter-to-submit on forms. Nothing may throw.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/pages/stock_in_receipts_page.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/pages/pos_checkout_page.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';
import 'package:stores/presentation/orders/widgets/cancel_invoice_dialog.dart';
import 'package:stores/presentation/orders/widgets/debt_collection_dialog.dart';

import '../support/orders_screens.dart';
import '../support/orders_support.dart';

void main() {
  final data = StressData.generate(envInt('STRESS_SEED', 20261014),
      nOrders: 300, nProducts: 800, nCustomers: 100, nReceipts: 100);
  const web = Device('web 1280x720', 1280, 720, web: true);

  Future<void> hoverEverything(WidgetTester t) async {
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    final inks =
        find.byType(InkWell).hitTestable().evaluate().take(25).toList();
    for (final e in inks) {
      final rb = e.renderObject as RenderBox;
      await mouse.moveTo(rb.localToGlobal(rb.size.center(Offset.zero)));
      await t.pump(const Duration(milliseconds: 20));
    }
    await mouse.removePointer();
  }

  Future<void> tabThrough(WidgetTester t, {int n = 40}) async {
    for (var i = 0; i < n; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump(const Duration(milliseconds: 10));
    }
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(milliseconds: 200));
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump(const Duration(milliseconds: 200));
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump(const Duration(milliseconds: 300));
  }

  final pages = <String, Widget Function()>{
    'POSPage': () => const POSPage(),
    'POSCheckoutPage': () =>
        POSCheckoutPage(initialCustomer: data.customers[2]),
    'InvoicesPage': () => const InvoicesPage(),
    'StockInReceiptsPage': () => const StockInReceiptsPage(),
    'ImportInventoryPage': () => const ImportInventoryPage(),
  };

  for (final e in pages.entries) {
    testWidgets('mouse hover + wheel + Tab traversal: ${e.key}', (t) async {
      setView(t, web, 1);
      addTearDown(t.view.reset);
      await withLog(t, e.key, (log) async {
        final c = ProviderContainer(
            overrides: e.key.startsWith('StockIn') || e.key.startsWith('Import')
                ? inventoryOverrides(adminUser, data)
                : ordersOverrides(adminUser, data));
        addTearDown(c.dispose);
        if (e.key.startsWith('POS')) fillCart(c, data, 12);
        await t.pumpWidget(stressApp(e.value(), container: c));
        await t.pumpAndSettle();
        await hoverEverything(t);
        for (var i = 0; i < 6; i++) {
          await wheelScroll(t, 600, times: 1);
        }
        for (var i = 0; i < 6; i++) {
          await wheelScroll(t, -600, times: 1);
        }
        await tabThrough(t);
        await t.pumpAndSettle();
      });
    });
  }

  group('Enter submits / validates forms', () {
    testWidgets('AddCustomerDialog: Enter on empty form shows validation',
        (t) async {
      setView(t, web, 1);
      addTearDown(t.view.reset);
      await withLog(t, 'AddCustomerDialog Enter', (log) async {
        final c =
            ProviderContainer(overrides: ordersOverrides(adminUser, data));
        addTearDown(c.dispose);
        await t.pumpWidget(stressApp(
            launcher((ctx) => showDialog<void>(
                context: ctx, builder: (_) => const AddCustomerDialog())),
            container: c));
        await t.tap(find.byKey(const Key('launch')));
        await t.pumpAndSettle();
        final f = find.byType(TextFormField);
        expect(f, findsWidgets);
        await t.tap(f.first);
        await t.enterText(f.first, '');
        await t.testTextInput.receiveAction(TextInputAction.done);
        await t.pumpAndSettle();
        await t.enterText(f.first, 'Nguyễn ​ Văn 😀 مرحبا');
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
      });
    });

    testWidgets('DebtCollectionDialog: Enter with absurd / empty amounts',
        (t) async {
      setView(t, web, 1);
      addTearDown(t.view.reset);
      await withLog(t, 'DebtCollectionDialog Enter', (log) async {
        final c =
            ProviderContainer(overrides: ordersOverrides(adminUser, data));
        addTearDown(c.dispose);
        final order = data.orders.firstWhere((o) => o.debtAmount > 0);
        await t.pumpWidget(stressApp(
            launcher((ctx) => DebtCollectionDialog.show(ctx,
                order: order,
                customer: data.customers[3],
                remainingDebt: order.debtAmount)),
            container: c));
        await t.tap(find.byKey(const Key('launch')));
        await t.pumpAndSettle();
        final f = find.byType(TextField);
        expect(f, findsWidgets);
        for (final txt in [
          '',
          '0',
          '-5',
          'NaN',
          'Infinity',
          '9' * 40,
          '1e400'
        ]) {
          await t.enterText(f.first, txt);
          await t.testTextInput.receiveAction(TextInputAction.done);
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump(const Duration(milliseconds: 200));
      });
    });

    testWidgets('CancelInvoiceDialog: Enter on empty reason', (t) async {
      setView(t, web, 1);
      addTearDown(t.view.reset);
      await withLog(t, 'CancelInvoiceDialog Enter', (log) async {
        final c =
            ProviderContainer(overrides: ordersOverrides(adminUser, data));
        addTearDown(c.dispose);
        final order = data.orders.firstWhere((o) => o.status == 'completed');
        await t.pumpWidget(stressApp(
            launcher((ctx) => CancelInvoiceDialog.show(ctx,
                order: order, customer: data.customers[3])),
            container: c));
        await t.tap(find.byKey(const Key('launch')));
        await t.pumpAndSettle();
        final f = find.byType(TextField);
        if (f.evaluate().isNotEmpty) {
          await t.enterText(f.first, '');
          await t.testTextInput.receiveAction(TextInputAction.done);
          await t.pump(const Duration(milliseconds: 100));
          await t.enterText(f.first, 'z' * 400);
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
      });
    });
  });
}
