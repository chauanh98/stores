import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_product_edit_sheet.dart';

class FailingStockInReceiptRepository implements StockInReceiptRepository {
  @override
  Future<double?> getLatestImportPrice({required String storeId, required String productId}) async {
    throw Exception('Simulated network timeout / Firebase connection failure');
  }

  @override
  Future<String> saveDraft(StockInReceipt receipt) async => 'DRAFT_001';
  @override
  Future<void> updateDraft(StockInReceipt receipt) async {}
  @override
  Future<void> deleteDraft({required String storeId, required String receiptId}) async {}
  @override
  Future<void> cancelReceipt({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {}
  @override
  Stream<List<StockInReceipt>> watchReceipts(String storeId) => Stream.value([]);
  @override
  Future<List<StockInReceipt>> fetchReceipts(String storeId) async => [];
  @override
  Future<StockInReceipt?> getReceiptById({required String storeId, required String receiptId}) async => null;
  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {}
  @override
  Future<void> deleteReceipt({required String storeId, required String receiptId}) async {}
}

Widget buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      currentStoreIdProvider.overrideWith((ref) => 'store_001'),
      ...overrides,
    ],
    child: MaterialApp(
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  group('Milestone 2 Adversarial & Boundary Stress Tests', () {
    const testProduct = Product(
      id: 'PROD_ADVERSARIAL',
      name: 'Phân Bón Hữu Cơ Cao Cấp Đầu Trâu',
      code: 'PBHC_001',
      barcode: '893000000001',
      price: 1500000.0,
      costPrice: 1200000.0,
      branchStocks: {
        'store_001': 88,
        'store_002': 14,
      },
      category: 'Phân bón',
      unit: 'Bao 50kg',
    );

    // ------------------------------------------------------------------------
    // Challenge 1: Narrow viewport & Small Screen Layout Resilience
    // ------------------------------------------------------------------------
    testWidgets('C1: Modal renders on 360x640 standard mobile screen', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 88,
            preFilledPrice: 1200000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('product_edit_sheet')), findsOneWidget);
      expect(find.byKey(const Key('btn_sheet_done')), findsOneWidget);
    });

    // ------------------------------------------------------------------------
    // Challenge 2: Graceful error recovery when repository throws during async load
    // ------------------------------------------------------------------------
    testWidgets('C2: Gracefully falls back to product.costPrice when repository query fails', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            stockInReceiptRepositoryProvider.overrideWithValue(FailingStockInReceiptRepository()),
          ],
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 88,
            // preFilledPrice omitted to force async query
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should not throw, should display product.costPrice (1,200,000)
      expect(tester.takeException(), isNull);
      expect(find.text('1.200.000'), findsOneWidget);
      expect(find.text('1.200.000 đ'), findsWidgets);
    });

    // ------------------------------------------------------------------------
    // Challenge 3: Extreme Multi-Billion Dong Values & Large Quantity Stress
    // ------------------------------------------------------------------------
    testWidgets('C3: Billions dong and large quantity calculate accurately without crashing', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? committedItem;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final item = await StockInProductEditSheet.show(
                  context: ctx,
                  product: testProduct,
                  preFilledPrice: 50000000.0, // 50 million đ per unit
                  onItemUpdated: (updated) => committedItem = updated,
                );
                committedItem ??= item;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Focus Quantity
      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();

      // Enter 125 via numpad
      await tester.tap(find.byKey(const Key('numpad_1')));
      await tester.tap(find.byKey(const Key('numpad_2')));
      await tester.tap(find.byKey(const Key('numpad_5')));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('125'));

      // Total = 50,000,000 * 125 = 6,250,000,000 đ (6.25 billion đ)
      expect(find.text('6.250.000.000 đ'), findsOneWidget);

      // Commit via Xong
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(committedItem, isNotNull);
      expect(committedItem!.quantity, equals(125));
      expect(committedItem!.unitPrice, equals(50000000.0));
      expect(committedItem!.totalPrice, equals(6250000000.0));
    });

    // ------------------------------------------------------------------------
    // Challenge 4: Zero Quantity protection on Done commit
    // ------------------------------------------------------------------------
    testWidgets('C4: Backspacing quantity to 0 still commits at least 1 unit', (tester) async {
      StockInReceiptItem? result;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final res = await StockInProductEditSheet.show(
                  context: ctx,
                  product: testProduct,
                  preFilledPrice: 100000.0,
                );
                result = res;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Focus quantity
      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();

      // Backspace to empty (which displays '0')
      await tester.tap(find.byKey(const Key('numpad_backspace')));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('0'));

      // Tap Xong
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      // Effective quantity must be clamped to 1
      expect(result, isNotNull);
      expect(result!.quantity, equals(1));
    });

    // ------------------------------------------------------------------------
    // Challenge 5: Rapid Concurrent Double Pop Protection
    // ------------------------------------------------------------------------
    testWidgets('C5: Multiple rapid Done taps do not cause duplicate pop exceptions', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int doneCount = 0;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                await StockInProductEditSheet.show(
                  context: ctx,
                  product: testProduct,
                  preFilledPrice: 100000.0,
                  onDone: (_, __, ___, ____) => doneCount++,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap Xong twice rapidly
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.tap(find.byKey(const Key('btn_sheet_done')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(doneCount, equals(1));
    });

    // ------------------------------------------------------------------------
    // Challenge 6: Decimal Dot '.' on Numpad Price Entry Behavior
    // ------------------------------------------------------------------------
    testWidgets('C6: Decimal point entry on price is preserved upon subsequent digit entry', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            preFilledPrice: 0.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus Price input
      await tester.tap(find.byKey(const Key('sheet_input_price')));
      await tester.pumpAndSettle();

      // Enter '5', then '.', then '5'
      await tester.tap(find.byKey(const Key('numpad_5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_.')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_5')));
      await tester.pumpAndSettle();

      // Decimal point '.' is preserved instead of stripped
      final priceField = tester.widget<TextFormField>(find.byKey(const Key('sheet_input_price')));
      expect(priceField.controller!.text, equals('5.5'));
    });
  });
}
