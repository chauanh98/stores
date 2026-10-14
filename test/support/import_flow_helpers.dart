import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helpers for the 2-step stock-in wizard (ImportInventoryPage):
///   step 0: pick supplier + products (each product edited in a bottom sheet)
///   step 1: payment confirmation (StockInPaymentConfirmationView)

/// Search for a product on step 0 and tap it, opening StockInProductEditSheet.
Future<void> openProductSheet(
  WidgetTester tester, {
  required String search,
  required String productText,
}) async {
  final searchField = find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm');
  await tester.tap(searchField);
  await tester.enterText(searchField, search);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(productText).last);
  await tester.pumpAndSettle();
}

/// Open the sheet for a product, optionally set quantity (stepper) / unit price
/// (field, only exists for roles that can view cost price), then press "Xong".
Future<void> addProductViaSheet(
  WidgetTester tester, {
  required String search,
  required String productText,
  int? quantity,
  String? unitPrice,
}) async {
  await openProductSheet(tester, search: search, productText: productText);
  expect(find.byKey(const Key('product_edit_sheet')), findsOneWidget);

  if (quantity != null && quantity > 1) {
    final inc = find.byKey(const Key('sheet_stepper_inc'));
    for (var i = 1; i < quantity; i++) {
      await tester.tap(inc);
      await tester.pump();
    }
  }
  if (unitPrice != null) {
    final price = find.byKey(const Key('sheet_input_price'));
    if (price.evaluate().isNotEmpty) {
      await tester.enterText(price, unitPrice);
      await tester.pump();
    }
  }
  await tester.ensureVisible(find.byKey(const Key('btn_sheet_done')));
  await tester.tap(find.byKey(const Key('btn_sheet_done')));
  await tester.pumpAndSettle();
}

/// Step 0 -> step 1 ("Tiếp tục").
Future<void> goToPaymentStep(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Tiếp tục'));
  await tester.tap(find.text('Tiếp tục'));
  await tester.pumpAndSettle();
}

/// Step 1 -> finish ("Hoàn thành").
Future<void> completeReceiptOnPaymentStep(WidgetTester tester) async {
  final btn = find.byKey(const Key('btn_payment_complete'));
  await tester.ensureVisible(btn);
  await tester.tap(btn);
  await tester.pumpAndSettle();
}
