// ignore_for_file: text_direction_code_point_in_literal
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/inventories/pages/import_detail_page.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/pages/imports_page.dart';
import 'package:stores/presentation/inventories/pages/inter_store_transfer_page.dart';
import 'package:stores/presentation/inventories/pages/stock_in_receipts_page.dart';
import 'package:stores/presentation/inventories/pages/stock_transfer_create_page.dart';
import 'package:stores/presentation/inventories/pages/stock_transfer_detail_page.dart';
import 'package:stores/presentation/inventories/pages/stock_transfer_receive_page.dart';
import 'package:stores/presentation/inventories/pages/stock_transfers_page.dart';
import 'package:stores/presentation/inventories/widgets/cancel_stock_in_receipt_dialog.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_exit_dialog.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_product_edit_sheet.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_receipt_detail_bottom_sheet.dart';
import 'package:stores/presentation/notifications/pages/notifications_page.dart';
import 'package:stores/presentation/orders/controllers/invoices_filter_controller.dart';
import 'package:stores/presentation/orders/pages/create_order_page.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/pages/pos_checkout_page.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';
import 'package:stores/presentation/orders/pages/pos_payment_page.dart';
import 'package:stores/presentation/orders/widgets/cancel_invoice_dialog.dart';
import 'package:stores/presentation/orders/widgets/debt_collection_dialog.dart';
import 'package:stores/presentation/orders/widgets/draft_orders_bottom_sheet.dart';
import 'package:stores/presentation/orders/widgets/invoice_detail_bottom_sheet.dart';
import 'package:stores/presentation/orders/widgets/return_order_bottom_sheet.dart';
import 'package:stores/presentation/orders/widgets/return_order_detail_bottom_sheet.dart';

import 'orders_support.dart';

/// A screen under test.
class Scr {
  Scr(this.name, this.build,
      {this.launch = false,
      this.cart = 0,
      this.after,
      this.overrides,
      this.nest = false});
  final String name;
  final Widget Function(StressData d) build;
  final bool launch;
  final int cart;

  /// Extra interaction after the screen settled.
  final Future<void> Function(WidgetTester t, StressData d)? after;
  final List<Override> Function(UserAccount u, StressData d)? overrides;
  final bool nest;
}

/// Populate the cart with seeded, adversarial lines.
void fillCart(ProviderContainer c, StressData d, int n) {
  final notifier = c.read(cartProvider.notifier);
  final g = Gen(d.seed + 77);
  var added = 0;
  for (var i = 0; added < n && i < d.products.length; i++) {
    final p = d.products[(i * 7) % d.products.length];
    notifier.addToCart(p,
        quantity: g.r.nextInt(10) == 0 ? 1000000 : 1 + g.r.nextInt(30));
    added++;
  }
}

/// Registers device x scale x role x theme tests for every screen.
///
/// Every device is exercised at least once per screen and every text scale
/// at least once per screen (scale/dpr/role/theme rotate with the device
/// index, shifted by the screen index). Tiny devices additionally run at the
/// two largest text scales.
void registerMatrix(
  StressData Function() data,
  List<Scr> screens,
  List<Override> Function(UserAccount u, StressData d) overrides, {
  int stride = 1,
}) {
  for (var si = 0; si < screens.length; si++) {
    final s = screens[si];
    final combos = <(Device, double, double, UserAccount, bool)>[];
    for (var di = 0; di < devices.length; di += 1) {
      final k = di + si;
      combos.add((
        devices[di],
        textScales[k % textScales.length],
        dprs[k % dprs.length],
        k % 2 == 0 ? adminUser : staffUser,
        k % 3 == 0
      ));
    }
    // extra extreme combos
    combos.add((devices[0], 2.0, 1.0, adminUser, false));
    combos.add((devices[1], 1.8, 3.0, staffUser, true));
    combos.add((devices[2], 2.0, 2.0, adminUser, true));
    for (var ci = 0; ci < combos.length; ci += stride) {
      final (dev, scale, dpr, user, dark) = combos[ci];
      testWidgets(
          '${s.name} @ ${dev.name} x$scale dpr$dpr ${user.role}${dark ? ' dark' : ''}',
          (tester) async {
        final d = data();
        setView(tester, dev, dpr);
        addTearDown(tester.view.reset);
        final log = ErrorLog()..install();
        final container = ProviderContainer(
            overrides: s.overrides?.call(user, d) ?? overrides(user, d));
        addTearDown(container.dispose);
        if (s.cart > 0) fillCart(container, d, s.cart);
        try {
          await tester.pumpWidget(stressApp(s.build(d),
              container: container, textScale: scale, dark: dark));
          await tester.pumpAndSettle(const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate, const Duration(seconds: 20));
          if (s.launch) {
            await tester.tap(find.byKey(const Key('launch')));
            await tester.pumpAndSettle();
          }
          await s.after?.call(tester, d);
          if (dev.web) {
            await mouseHoverSweep(tester);
            await wheelScroll(tester, 400);
            await wheelScroll(tester, -400, times: 1);
            await keyboardTraverse(tester, tabs: 6);
            await tester.pumpAndSettle();
          }
        } catch (e) {
          log.uninstall();
          log.drain(tester);
          if (log.errors.isNotEmpty) {
            fail(
                '${s.name} @ ${dev.name} x$scale dpr$dpr threw $e\n  - ${log.unique().join('\n  - ')}');
          }
          rethrow;
        }
        log.drain(tester);
        log.uninstall();
        expectClean(log, '${s.name} @ ${dev.name} x$scale dpr$dpr');
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Screen catalogues
// ---------------------------------------------------------------------------

Future<void> tapFirst(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) return;
  await t.ensureVisible(f.first);
  await t.tap(f.first, warnIfMissed: false);
  await t.pumpAndSettle();
}

List<Scr> posScreens() => [
      Scr('POSPage', (d) => const POSPage(), cart: 40),
      Scr('POSPage search', (d) => const POSPage(), cart: 3,
          after: (t, d) async {
        await t.enterText(find.byType(TextField).first, 'Sản phẩm 12');
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).first, 'Z̀́😀مرحبا');
        await t.pumpAndSettle();
      }),
      Scr('POSPage empty cart', (d) => const POSPage()),
      Scr(
          'POSCheckoutPage',
          (d) => POSCheckoutPage(
              initialCustomer: d.customers[1],
              initialNote: 'Ghi chú rất dài ' * 10),
          cart: 150),
      Scr('POSCheckoutPage empty cart', (d) => const POSCheckoutPage()),
      Scr('POSCheckoutPage edit item sheet',
          (d) => POSCheckoutPage(initialCustomer: d.customers[0]), cart: 5,
          after: (t, d) async {
        await tapFirst(t, find.byType(ListTile));
        await tapFirst(t, find.textContaining('Sản phẩm'));
      }),
      Scr(
          'POSPaymentPage',
          (d) => POSPaymentPage(
              initialCustomer: d.customers[2], initialNote: 'Ghi chú'),
          cart: 150),
      Scr('POSPaymentPage split modal',
          (d) => POSPaymentPage(initialCustomer: d.customers[2]), cart: 5,
          after: (t, d) async {
        await tapFirst(t, find.byIcon(Icons.more_horiz));
      }),
      Scr('POSPaymentPage transfer tab',
          (d) => POSPaymentPage(initialCustomer: d.customers[2]), cart: 5,
          after: (t, d) async {
        await tapFirst(t, find.text('Chuyển\nkhoản'));
      }),
      Scr(
          'AddCustomerDialog',
          (d) => launcher((ctx) => showDialog<void>(
              context: ctx, builder: (_) => const AddCustomerDialog())),
          launch: true),
      Scr('CreateOrderPage',
          (d) => const CreateOrderPage(selectedCustomerId: 'c1')),
    ];

List<Scr> invoiceScreens() => [
      Scr('InvoicesPage 2000', (d) => const InvoicesPage(),
          after: (t, d) async {
        final toggle =
            find.byKey(const Key('invoices_toggle_expand_all_button'));
        if (toggle.evaluate().isNotEmpty) {
          await t.tap(toggle);
          await t.pumpAndSettle();
        }
        final field = find.byType(TextField);
        if (field.evaluate().isNotEmpty) {
          await t.enterText(field.first, 'nguyen');
          await t.pumpAndSettle();
        }
      }),
      Scr('InvoicesPage detail sheet', (d) => const InvoicesPage(),
          after: (t, d) async {
        await tapFirst(t, find.textContaining('HD100'));
        if (find.byType(CustomScrollView).evaluate().isNotEmpty) {
          await t.drag(
              find.byType(CustomScrollView).last, const Offset(0, -3000),
              warnIfMissed: false);
          await t.pumpAndSettle();
        }
      }),
      Scr('InvoicesPage returned filter', (d) => const InvoicesPage(),
          after: (t, d) async {
        final c =
            ProviderScope.containerOf(t.element(find.byType(InvoicesPage)));
        c.read(invoicesFilterProvider.notifier).setStatus('returned');
        await t.pumpAndSettle();
        c.read(invoicesFilterProvider.notifier).setStatus('cancelled');
        await t.pumpAndSettle();
      }),
      Scr('InvoicesPage date+branch sheet', (d) => const InvoicesPage(),
          after: (t, d) async {
        await tapFirst(t, find.byIcon(Icons.arrow_drop_down));
        final c = find.byType(BackButton);
        if (c.evaluate().isNotEmpty) await t.pageBack();
      }),
      Scr(
          'InvoiceDetailBottomSheet 150 lines',
          (d) => launcher((ctx) => InvoiceDetailBottomSheet.show(
              ctx, d.bigOrder,
              customerName: d.bigOrder.customerName)),
          launch: true),
      Scr(
          'InvoiceDetailBottomSheet cancelled',
          (d) => launcher((ctx) => InvoiceDetailBottomSheet.show(
              ctx, d.orders.firstWhere((o) => o.status == 'cancelled'),
              customerName: 'مرحبا שלום')),
          launch: true),
      Scr(
          'ReturnOrderBottomSheet 150 lines',
          (d) => launcher((ctx) => ReturnOrderBottomSheet.show(ctx,
              order: d.bigOrder, customer: d.customers[3])),
          launch: true),
      Scr(
          'ReturnOrderDetailBottomSheet 120 lines',
          (d) => launcher((ctx) => ReturnOrderDetailBottomSheet.show(ctx,
              order: d.bigOrder,
              returnOrder: d.bigReturn,
              customer: d.customers[3])),
          launch: true),
      Scr(
          'DebtCollectionDialog',
          (d) => launcher((ctx) => DebtCollectionDialog.show(ctx,
              order: d.orders.firstWhere((o) => o.debtAmount > 0),
              customer: d.customers[4],
              remainingDebt: 123456789000)),
          launch: true),
      Scr(
          'CancelInvoiceDialog',
          (d) => launcher((ctx) => CancelInvoiceDialog.show(ctx,
              order: d.orders.firstWhere((o) => o.status == 'completed'),
              customer: d.customers[4])),
          launch: true),
      Scr(
          'DraftOrdersBottomSheet',
          (d) => launcher((ctx) => showModalBottomSheet<void>(
              context: ctx,
              isScrollControlled: true,
              builder: (_) => const DraftOrdersBottomSheet())),
          launch: true),
    ];

StockInReceipt _draftWith(StressData d, int lines) => d.g
    .receipt(777, lines: lines, status: 'draft')
    .copyWith(storeId: 'store_001');

List<Scr> stockInScreens() => [
      Scr('StockInReceiptsPage 600', (d) => const StockInReceiptsPage(),
          after: (t, d) async {
        final field = find.byType(TextField);
        if (field.evaluate().isNotEmpty) {
          await t.enterText(field.first, 'Ánh Dương');
          await t.pumpAndSettle();
        }
      }),
      Scr('StockInReceiptsPage tap card', (d) => const StockInReceiptsPage(),
          after: (t, d) async {
        await tapFirst(t, find.textContaining('PN_'));
      }),
      Scr(
          'StockInReceiptDetailBottomSheet 250 lines',
          (d) => launcher((ctx) =>
              StockInReceiptDetailBottomSheet.show(ctx, receipt: d.bigReceipt)),
          launch: true),
      Scr(
          'StockInReceiptDetailBottomSheet cancelled',
          (d) => launcher((ctx) => StockInReceiptDetailBottomSheet.show(ctx,
              receipt: d.receipts.firstWhere((r) => r.isCancelled))),
          launch: true),
      Scr(
          'CancelStockInReceiptDialog',
          (d) => launcher((ctx) => CancelStockInReceiptDialog.show(ctx,
              receipt: d.receipts.firstWhere((r) => r.isCompleted))),
          launch: true),
      Scr('StockInExitDialog',
          (d) => launcher((ctx) => StockInExitDialog.show(ctx)),
          launch: true),
      Scr('ImportInventoryPage empty (step 1)',
          (d) => const ImportInventoryPage()),
      Scr('ImportInventoryPage 200-line draft (step 1)',
          (d) => ImportInventoryPage(initialReceipt: _draftWith(d, 200))),
      Scr('ImportInventoryPage step 2 payment',
          (d) => ImportInventoryPage(initialReceipt: _draftWith(d, 120)),
          after: (t, d) async {
        final btn = find.byKey(const Key('btn_continue'));
        if (btn.evaluate().isNotEmpty) {
          await t.ensureVisible(btn);
          await t.tap(btn, warnIfMissed: false);
          await t.pumpAndSettle();
        }
      }),
      Scr(
          'StockInProductEditSheet',
          (d) => launcher((ctx) => StockInProductEditSheet.show(
              context: ctx,
              product: d.products[1],
              branchStock: 999999,
              storeId: 'store_001',
              preFilledPrice: 1e12)),
          launch: true),
      Scr(
          'StockInProductEditSheet existing item',
          (d) => launcher((ctx) => StockInProductEditSheet.show(
              context: ctx,
              product: d.products[2],
              branchStock: -3,
              storeId: 'store_001',
              existingItem: d.bigReceipt.items.first)),
          launch: true),
      Scr('ImportsPage', (d) => const ImportsPage()),
      Scr(
          'ImportDetailPage',
          (d) => ImportDetailPage(
              tx: InventoryTransaction(
                  id: 'tx1',
                  productId: 'p1',
                  type: TransactionType.import,
                  quantity: 1000000,
                  date: DateTime(2026, 10, 14),
                  note: 'Import - ${d.g.adv()}',
                  importPrice: 1e12,
                  createdByName: adminUser.displayName,
                  storeId: 'store_001'),
              product: d.products[1])),
    ];

List<Scr> transferScreens() => [
      Scr('StockTransfersPage 300', (d) => const StockTransfersPage()),
      Scr('StockTransferDetailPage',
          (d) => StockTransferDetailPage(transferId: d.transfers[1].id)),
      Scr('StockTransferDetailPage 200 lines',
          (d) => StockTransferDetailPage(transferId: d.bigTransfer.id)),
      Scr('StockTransferReceivePage 200 lines',
          (d) => StockTransferReceivePage(transferId: d.bigTransfer.id)),
      Scr('StockTransferCreatePage',
          (d) => StockTransferCreatePage(product: d.products[3])),
      Scr('StockTransferCreatePage empty',
          (d) => const StockTransferCreatePage()),
      Scr('InterStoreTransferPage', (d) => const InterStoreTransferPage()),
      Scr('InterStoreTransferPage product',
          (d) => InterStoreTransferPage(product: d.products[4])),
    ];

List<Scr> notificationScreens() => [
      Scr('NotificationsPage 500', (d) => const NotificationsPage()),
      Scr('NotificationsPage tap+menu', (d) => const NotificationsPage(),
          after: (t, d) async {
        await tapFirst(t, find.byType(InkWell));
        await tapFirst(t, find.byType(PopupMenuButton));
        await tapFirst(t, find.byType(FilterChip));
      }),
    ];
