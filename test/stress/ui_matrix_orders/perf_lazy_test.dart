// Large-data lazy-building + rebuild-cost guards (2,000 invoices, 5,000
// products, 1,000 customers, 100-300 line documents, 500 notifications).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/pages/stock_in_receipts_page.dart';
import 'package:stores/presentation/inventories/pages/stock_transfers_page.dart';
import 'package:stores/presentation/notifications/pages/notifications_page.dart';
import 'package:stores/presentation/notifications/widgets/notification_card.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/pages/pos_checkout_page.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';
import 'package:stores/presentation/orders/widgets/invoice_detail_bottom_sheet.dart';
import 'package:stores/presentation/orders/widgets/return_order_bottom_sheet.dart';

import '../support/orders_screens.dart';
import '../support/orders_support.dart';

/// Debug-mode budget (see task): ~1.5 s for a single pump of a big list.
const _budgetMs = 1500;

void main() {
  final data = StressData.generate(envInt('STRESS_SEED', 20261014));

  void phone(WidgetTester t, {Device? d, double dpr = 1}) {
    setView(t, d ?? devices[5], dpr);
    addTearDown(t.view.reset);
  }

  Future<int> timed(Future<void> Function() f) async {
    final sw = Stopwatch()..start();
    await f();
    return sw.elapsedMilliseconds;
  }

  testWidgets(
      'InvoicesPage: 2000 invoices build lazily, first pump + rebuild fast',
      (t) async {
    phone(t);
    await withLog(t, 'InvoicesPage x2000', (log) async {
      final c = ProviderContainer(overrides: ordersOverrides(adminUser, data));
      addTearDown(c.dispose);
      final first = await timed(() async {
        await t.pumpWidget(stressApp(const InvoicesPage(), container: c));
        await t.pumpAndSettle();
      });
      final cards = find.textContaining('mặt hàng').evaluate().length;
      // ignore: avoid_print
      print(
          'PERF InvoicesPage x2000 first pump ${first}ms, tiles built=$cards');
      expect(cards, greaterThan(0));
      expect(cards, lessThan(60),
          reason: 'built $cards of ${data.orders.length}');
      final rebuild = await timed(() async {
        await t.pumpWidget(
            stressApp(const InvoicesPage(), container: c, textScale: 1.3));
        await t.pump();
      });
      // ignore: avoid_print
      print('PERF InvoicesPage x2000 rebuild(text scale) ${rebuild}ms');
      expect(rebuild, lessThan(_budgetMs));
      // typing in the search field re-filters 2000 invoices
      final typing = await timed(() async {
        await t.enterText(find.byType(TextField).first, 'Khách hàng 12');
        await t.pump();
      });
      // ignore: avoid_print
      print('PERF InvoicesPage x2000 search keystroke ${typing}ms');
      expect(typing, lessThan(_budgetMs));
      // wheel-scroll through the list
      final scroll = await timed(() async {
        for (var i = 0; i < 30; i++) {
          await wheelScroll(t, 900, times: 1);
        }
      });
      // ignore: avoid_print
      print('PERF InvoicesPage x2000 30 wheel steps ${scroll}ms');
    });
  });

  testWidgets('POSPage: 5000 products build lazily, search + cart taps fast',
      (t) async {
    phone(t);
    await withLog(t, 'POSPage x5000', (log) async {
      final c = ProviderContainer(overrides: ordersOverrides(adminUser, data));
      addTearDown(c.dispose);
      final first = await timed(() async {
        await t.pumpWidget(stressApp(const POSPage(), container: c));
        await t.pumpAndSettle();
      });
      final tiles =
          find.byKey(const Key('pos_add_to_cart_p0'), skipOffstage: false);
      final built = find
          .byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('pos_add_to_cart_'))
          .evaluate()
          .length;
      // ignore: avoid_print
      print(
          'PERF POSPage x5000 first pump ${first}ms (Cards=$built, p0 tile=${tiles.evaluate().length})');
      expect(built, lessThan(40));
      final type = await timed(() async {
        await t.enterText(find.byType(TextField).first, 'Sản phẩm 12');
        await t.pump();
      });
      // ignore: avoid_print
      print('PERF POSPage x5000 search keystroke ${type}ms');
      expect(type, lessThan(_budgetMs));
      // add 60 products to the cart one by one and measure the average rebuild
      final sw = Stopwatch()..start();
      final n = c.read(cartProvider.notifier);
      for (var i = 0; i < 60; i++) {
        n.addToCart(data.products[i * 13]);
        await t.pump();
      }
      // ignore: avoid_print
      print(
          'PERF POSPage x5000 avg cart add rebuild ${sw.elapsedMilliseconds / 60}ms');
      expect(sw.elapsedMilliseconds / 60, lessThan(300));
    });
  });

  testWidgets('POSCheckoutPage: 300 cart lines built lazily', (t) async {
    phone(t);
    await withLog(t, 'checkout 300', (log) async {
      final c = ProviderContainer(overrides: ordersOverrides(adminUser, data));
      addTearDown(c.dispose);
      fillCart(c, data, 300);
      final ms = await timed(() async {
        await t.pumpWidget(stressApp(
            POSCheckoutPage(initialCustomer: data.customers[1]),
            container: c));
        await t.pumpAndSettle();
      });
      final dismiss = find.byType(Dismissible).evaluate().length;
      // ignore: avoid_print
      print('PERF POSCheckoutPage 300 lines pump ${ms}ms, rows built=$dismiss');
      expect(ms, lessThan(_budgetMs * 2));
      expect(dismiss, lessThan(60));
    });
  });

  testWidgets('InvoiceDetail/Return sheets: 300 lines lazy', (t) async {
    phone(t);
    await withLog(t, 'detail 300', (log) async {
      final c = ProviderContainer(overrides: ordersOverrides(adminUser, data));
      addTearDown(c.dispose);
      await t.pumpWidget(stressApp(
          launcher((ctx) => InvoiceDetailBottomSheet.show(ctx, data.bigOrder300,
              customerName: 'x')),
          container: c));
      final ms = await timed(() async {
        await t.tap(find.byKey(const Key('launch')));
        await t.pumpAndSettle();
      });
      // ignore: avoid_print
      print('PERF InvoiceDetailBottomSheet 300 lines open ${ms}ms');
      expect(ms, lessThan(_budgetMs));
      await t.drag(find.byType(CustomScrollView).last, const Offset(0, -300000),
          warnIfMissed: false);
      await t.pumpAndSettle();
      await t.tapAt(const Offset(5, 5)); // dismiss the sheet via the barrier
      await t.pumpAndSettle();
    });
  });

  testWidgets('ReturnOrderBottomSheet 300 lines lazy', (t) async {
    phone(t);
    await withLog(t, 'return 300', (log) async {
      final c = ProviderContainer(overrides: ordersOverrides(adminUser, data));
      addTearDown(c.dispose);
      await t.pumpWidget(stressApp(
          launcher((ctx) => ReturnOrderBottomSheet.show(ctx,
              order: data.bigOrder300, customer: data.customers[2])),
          container: c));
      final ms = await timed(() async {
        await t.tap(find.byKey(const Key('launch')));
        await t.pumpAndSettle();
      });
      // ignore: avoid_print
      print('PERF ReturnOrderBottomSheet 300 lines open ${ms}ms');
      expect(ms, lessThan(_budgetMs));
    });
  });

  testWidgets('StockInReceiptsPage: 600 receipts lazy', (t) async {
    phone(t);
    await withLog(t, 'receipts 600', (log) async {
      final c =
          ProviderContainer(overrides: inventoryOverrides(adminUser, data));
      addTearDown(c.dispose);
      final ms = await timed(() async {
        await t
            .pumpWidget(stressApp(const StockInReceiptsPage(), container: c));
        await t.pumpAndSettle();
      });
      final cards = find.byType(Card).evaluate().length;
      // ignore: avoid_print
      print('PERF StockInReceiptsPage x600 pump ${ms}ms, Cards=$cards');
      expect(cards, lessThan(40));
      expect(ms, lessThan(_budgetMs));
    });
  });

  testWidgets('ImportInventoryPage: 300-line draft lazy', (t) async {
    phone(t);
    await withLog(t, 'import 300', (log) async {
      final c =
          ProviderContainer(overrides: inventoryOverrides(adminUser, data));
      addTearDown(c.dispose);
      final draft = data.g.receipt(555, lines: 300, status: 'draft');
      final ms = await timed(() async {
        await t.pumpWidget(stressApp(ImportInventoryPage(initialReceipt: draft),
            container: c));
        await t.pumpAndSettle();
      });
      final cards = find.byType(Card).evaluate().length;
      // ignore: avoid_print
      print('PERF ImportInventoryPage 300 lines pump ${ms}ms, Cards=$cards');
      expect(cards, lessThan(40));
      expect(ms, lessThan(_budgetMs * 2));
    });
  });

  testWidgets('StockTransfersPage: 300 transfers lazy', (t) async {
    phone(t);
    await withLog(t, 'transfers 300', (log) async {
      final c =
          ProviderContainer(overrides: inventoryOverrides(adminUser, data));
      addTearDown(c.dispose);
      final ms = await timed(() async {
        await t.pumpWidget(stressApp(const StockTransfersPage(), container: c));
        await t.pumpAndSettle();
      });
      final cards = find.textContaining('TRF').evaluate().length;
      // ignore: avoid_print
      print('PERF StockTransfersPage x300 pump ${ms}ms, Cards=$cards');
      expect(cards, lessThan(40));
      expect(ms, lessThan(_budgetMs));
    });
  });

  testWidgets('NotificationsPage: 500 notifications lazy', (t) async {
    phone(t);
    await withLog(t, 'notifications 500', (log) async {
      final c =
          ProviderContainer(overrides: notificationOverrides(adminUser, data));
      addTearDown(c.dispose);
      final ms = await timed(() async {
        await t.pumpWidget(stressApp(const NotificationsPage(), container: c));
        await t.pumpAndSettle();
      });
      final cards = find.byType(NotificationCard).evaluate().length;
      // ignore: avoid_print
      print('PERF NotificationsPage x500 pump ${ms}ms, rows=$cards');
      expect(cards, lessThan(60));
      expect(ms, lessThan(_budgetMs));
      final scroll = await timed(() async {
        for (var i = 0; i < 30; i++) {
          await wheelScroll(t, 700, times: 1);
        }
      });
      // ignore: avoid_print
      print('PERF NotificationsPage x500 30 wheel steps ${scroll}ms');
    });
  });

  testWidgets('hostile money (NaN / infinity / negative) never throws',
      (t) async {
    phone(t);
    await withLog(t, 'hostile money', (log) async {
      final g = data.g;
      final hostile = <Order>[
        for (final v in [
          double.nan,
          double.infinity,
          -double.infinity,
          -1e15,
          1e300
        ])
          g
              .order(7000 + v.hashCode % 1000, lines: 3, status: 'completed')
              .copyWith(
                total: v,
                amountPaid: v,
                debtAmount: v,
              ),
      ];
      final c = ProviderContainer(
          overrides: ordersOverrides(adminUser, data, orders: hostile));
      addTearDown(c.dispose);
      await t.pumpWidget(stressApp(const InvoicesPage(), container: c));
      await t.pumpAndSettle();
      await tapFirst(t, find.textContaining('HD'));
    });
  });
}
