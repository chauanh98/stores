// Web / mouse / keyboard specifics: hover, wheel scrolling, Tab traversal,
// Enter to submit, text selection, chart screens with degenerate data.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/presentation/auth/pages/login_page.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';
import 'package:stores/presentation/reports/pages/overview_page.dart';
import 'package:stores/presentation/reports/pages/revenue_statistics_page.dart';
import 'package:stores/presentation/suppliers/pages/suppliers_page.dart';

import 'customers_suppliers_matrix_test.dart' as cs;
import 'products_matrix_test.dart' as pm;
import 'reports_matrix_test.dart' as rp;
import 'stress_kit.dart';

class _LoginAuth extends SweepAuth {
  _LoginAuth() : super(null);
  final calls = <String>[];
  @override
  Future<String?> login(String u, String p) async {
    calls.add('$u|$p');
    return null;
  }
}

Future<TestGesture> _mouse(WidgetTester t) async {
  final g = await t.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: Offset.zero);
  addTearDown(g.removePointer);
  return g;
}

void main() {
  final webDevs = [
    devices[11],
    devices[13],
    devices[15],
    devices[16],
    devices[17]
  ];

  for (final d in webDevs) {
    testWidgets('login: Tab traversal + Enter submits @${d.name}', (t) async {
      final auth = _LoginAuth();
      setDevice(t, d);
      addTearDown(t.view.reset);
      await t.pumpWidget(stressHost(
          const LoginPage(), [authProvider.overrideWith((ref) => auth)]));
      await t.pumpAndSettle();
      await t.tap(find.byType(TextField).first);
      await t.enterText(find.byType(TextField).first, '  admin 😀  ');
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.enterText(find.byType(TextField).last, 'p' * 500);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expectClean(t, 'login');
      expect(auth.calls, isNotEmpty, reason: 'Enter must submit the form');
      // Empty submit shows the validation message, no exception
      await t.enterText(find.byType(TextField).first, '');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expectClean(t, 'login empty');
      // select-all + long-press selection on the field
      await t.enterText(find.byType(TextField).first, longWord);
      await t.longPress(find.byType(TextField).first);
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyA);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      expectClean(t, 'login selection');
    });
  }

  for (final d in webDevs) {
    testWidgets('products: hover + wheel + Tab keys @${d.name}', (t) async {
      setDevice(t, d);
      addTearDown(t.view.reset);
      await t.pumpWidget(
          stressHost(const ProductsPage(), pm.ov(sweepAdmin), textScale: 1.0));
      await t.pumpAndSettle();
      final g = await _mouse(t);
      // hover across the first tiles
      final tiles = find.byType(ProductTile);
      for (var i = 0; i < 6 && i < tiles.evaluate().length; i++) {
        await g.moveTo(t.getCenter(tiles.at(i)));
        await t.pump(const Duration(milliseconds: 60));
      }
      // wheel: many events, both directions
      final c = t.getCenter(find.byType(Scrollable).first);
      await g.moveTo(c);
      for (var i = 0; i < 40; i++) {
        await t.sendEventToBinding(PointerScrollEvent(
            position: c,
            scrollDelta: Offset(0, i.isEven ? 240.0 : -90.0),
            kind: PointerDeviceKind.mouse));
        await t.pump(const Duration(milliseconds: 16));
      }
      await t.pumpAndSettle();
      expect(built(ProductTile), lessThan(100));
      // keyboard traversal
      for (var i = 0; i < 40; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump(const Duration(milliseconds: 16));
      }
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expectClean(t, 'products web');
      // Enter on a focused tile may have opened a detail page: come back.
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      while (nav.canPop()) {
        nav.pop();
        await t.pumpAndSettle();
      }
      expectClean(t, 'products web back');
      // search typing then selection
      await t.enterText(find.byType(TextField).first, 'Sản phẩm 1');
      await t.pumpAndSettle();
      await t.tap(find.byType(TextField).first);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyA);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      expectClean(t, 'products search selection');
    });
  }

  testWidgets('customers/suppliers wheel scrolling @web1920x1080', (t) async {
    setDevice(t, devices[14]);
    addTearDown(t.view.reset);
    final g = await _mouse(t);
    for (final page in [const CustomersPage(), const SuppliersPage()]) {
      await t.pumpWidget(stressHost(page, cs.ov(sweepAdmin)));
      await t.pumpAndSettle();
      final c = t.getCenter(find.byType(Scrollable).first);
      await g.moveTo(c);
      for (var i = 0; i < 25; i++) {
        await t.sendEventToBinding(PointerScrollEvent(
            position: c,
            scrollDelta: const Offset(0, 400),
            kind: PointerDeviceKind.mouse));
        await t.pump(const Duration(milliseconds: 16));
      }
      await t.pumpAndSettle();
      expectClean(t, '${page.runtimeType} wheel');
    }
  });

  // Chart pages with every degenerate data shape, at web sizes, no exception.
  for (final m in ['zeros', 'single', 'equal', 'nan', 'outlier', 'negative']) {
    testWidgets('charts degenerate [$m] @web', (t) async {
      for (final d in [devices[11], devices[16]]) {
        setDevice(t, d);
        addTearDown(t.view.reset);
        for (final page in <Widget>[
          const OverviewPage(),
          const RevenueStatisticsPage()
        ]) {
          await t.pumpWidget(
              stressHost(page, rp.ov(sweepAdmin, mode: m, days: 365)));
          await t.pumpAndSettle();
          // hover the chart area (fl_chart touch/tooltips)
          final g = await t.createGesture(kind: PointerDeviceKind.mouse);
          await g.addPointer(location: Offset.zero);
          for (var i = 1; i < 8; i++) {
            await g.moveTo(Offset(d.w * i / 8, d.h * 0.4));
            await t.pump(const Duration(milliseconds: 30));
          }
          await g.removePointer();
          expectClean(t, 'chart $m ${page.runtimeType} ${d.name}');
        }
      }
    });
  }
}
