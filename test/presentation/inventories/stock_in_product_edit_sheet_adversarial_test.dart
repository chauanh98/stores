import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_product_edit_sheet.dart';

/// Configurable mock repository to test various price lookup scenarios.
class MockStockInReceiptRepository implements StockInReceiptRepository {
  double? latestPriceToReturn;
  bool shouldThrowException = false;
  String? lastQueriedStoreId;
  String? lastQueriedProductId;
  int queryCallCount = 0;

  @override
  Future<double?> getLatestImportPrice({
    required String storeId,
    required String productId,
  }) async {
    queryCallCount++;
    lastQueriedStoreId = storeId;
    lastQueriedProductId = productId;
    if (shouldThrowException) {
      throw Exception('Database connection timeout or network failure');
    }
    return latestPriceToReturn;
  }

  @override
  Future<String> saveDraft(StockInReceipt receipt) async => receipt.id;

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
  Future<StockInReceipt?> getReceiptById({
    required String storeId,
    required String receiptId,
  }) async =>
      null;

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
  const sampleProduct = Product(
    id: 'PROD_TEST_99',
    name: 'Gạo ST25 Sóc Trăng Thượng Hạng',
    code: 'ST25-SOCTRANG',
    barcode: '893600999999',
    price: 350000.0,
    costPrice: 280000.0,
    branchStocks: {
      'store_001': 42,
      'store_002': 18,
    },
    category: 'Gạo cao cấp',
    unit: 'Bao 10kg',
  );

  group('Requirement 1: Price Pre-filling Adversarial Stress Tests', () {
    testWidgets('1.1 Pre-fills latest historical import price when repository returns a positive price',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockRepo = MockStockInReceiptRepository();
      mockRepo.latestPriceToReturn = 295000.0;

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const StockInProductEditSheet(
            product: sampleProduct,
            storeId: 'store_001',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(mockRepo.queryCallCount, equals(1));
      expect(mockRepo.lastQueriedStoreId, equals('store_001'));
      expect(mockRepo.lastQueriedProductId, equals('PROD_TEST_99'));
      expect(find.text('295.000'), findsOneWidget);
      expect(find.text('295.000 đ'), findsWidgets);
    });

    testWidgets('1.2 Falls back to product.costPrice when latest import price does not exist (returns null)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockRepo = MockStockInReceiptRepository();
      mockRepo.latestPriceToReturn = null; // No previous imports

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const StockInProductEditSheet(
            product: sampleProduct,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(mockRepo.queryCallCount, equals(1));
      // Fallback to sampleProduct.costPrice (280,000)
      expect(find.text('280.000'), findsOneWidget);
      expect(find.text('280.000 đ'), findsWidgets);
    });

    testWidgets('1.3 Falls back to product.costPrice when repository returns 0 or negative price',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockRepo = MockStockInReceiptRepository();
      mockRepo.latestPriceToReturn = 0.0; // Corrupt/zero historical price

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const StockInProductEditSheet(
            product: sampleProduct,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Remains fallback costPrice (280,000)
      expect(find.text('280.000'), findsOneWidget);
    });

    testWidgets('1.4 Gracefully handles repository exceptions and maintains fallback costPrice',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockRepo = MockStockInReceiptRepository();
      mockRepo.shouldThrowException = true; // Simulating network/database failure

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const StockInProductEditSheet(
            product: sampleProduct,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Does not throw crash, gracefully retains product.costPrice
      expect(find.text('280.000'), findsOneWidget);
    });

    testWidgets('1.5 Respects explicit preFilledPrice and skips repository query',
        (tester) async {
      final mockRepo = MockStockInReceiptRepository();
      mockRepo.latestPriceToReturn = 999999.0;

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const StockInProductEditSheet(
            product: sampleProduct,
            preFilledPrice: 310000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Repo should NOT be queried when preFilledPrice is supplied
      expect(mockRepo.queryCallCount, equals(0));
      expect(find.text('310.000'), findsOneWidget);
    });

    testWidgets('1.6 Respects existingItem prices and skips repository query',
        (tester) async {
      final mockRepo = MockStockInReceiptRepository();
      mockRepo.latestPriceToReturn = 999999.0;

      final existing = StockInReceiptItem(
        transactionId: 'TX_123',
        productId: sampleProduct.id,
        quantity: 5,
        unitPrice: 260000.0,
        originalPrice: 270000.0,
        discount: 10000.0,
      );

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: StockInProductEditSheet(
            product: sampleProduct,
            existingItem: existing,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(mockRepo.queryCallCount, equals(0));
      expect(find.text('270.000'), findsOneWidget); // Original price
      expect(find.text('10.000'), findsOneWidget); // Discount
      expect(find.text('260.000 đ'), findsOneWidget); // Net price
    });

    testWidgets('1.7 Fallback when product.costPrice is 0.0 formats cleanly without crash',
        (tester) async {
      const zeroCostProduct = Product(
        id: 'PROD_ZERO_COST',
        name: 'Mặt hàng khuyến mãi không tính giá vốn',
        code: 'KM-01',
        costPrice: 0.0,
        price: 0.0,
        category: 'Khuyến mãi',
        branchStocks: {'store_001': 0},
      );

      final mockRepo = MockStockInReceiptRepository();
      mockRepo.latestPriceToReturn = null;

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const StockInProductEditSheet(
            product: zeroCostProduct,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0'), findsWidgets);
      expect(find.text('0 đ'), findsWidgets);
    });
  });

  group('Requirement 2: Subtotal Reactivity & Line Total Adversarial Stress Tests', () {
    testWidgets('2.1 Stepper reactivity: incrementing 1 to 5 and decrementing to 1 maintains exact line total',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: const StockInProductEditSheet(
            product: sampleProduct,
            preFilledPrice: 100000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Qty 1: 100,000 đ
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('1'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('100.000 đ'));

      // Step up to 2
      await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('2'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('200.000 đ'));

      // Step up to 3
      await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('3'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('300.000 đ'));

      // Step up to 4
      await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('4'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('400.000 đ'));

      // Step down to 3
      await tester.tap(find.byKey(const Key('sheet_stepper_dec')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('3'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('300.000 đ'));

      // Step down to 1
      await tester.tap(find.byKey(const Key('sheet_stepper_dec')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet_stepper_dec')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('1'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('100.000 đ'));

      // Stepper dec at min 1 does not decrement below 1
      await tester.tap(find.byKey(const Key('sheet_stepper_dec')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('1'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('100.000 đ'));
    });

    testWidgets('2.2 Numpad typing on Quantity immediately recalculates line total',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: const StockInProductEditSheet(
            product: sampleProduct,
            preFilledPrice: 50000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus quantity
      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();

      // Type 7 -> qty = 7, total = 350,000 đ
      await tester.tap(find.byKey(const Key('numpad_7')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('7'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('350.000 đ'));

      // Type 2 -> qty = 72, total = 3,600,000 đ
      await tester.tap(find.byKey(const Key('numpad_2')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('72'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('3.600.000 đ'));

      // Decimal dot is ignored for quantity
      await tester.tap(find.byKey(const Key('numpad_.')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('72'));

      // Backspace -> qty = 7
      await tester.tap(find.byKey(const Key('numpad_backspace')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('7'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('350.000 đ'));

      // Clear 'C' -> resets to 1
      await tester.tap(find.byKey(const Key('numpad_clear')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('1'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('50.000 đ'));
    });

    testWidgets('2.3 Numpad typing on Unit Price immediately recalculates net price and line total',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: const StockInProductEditSheet(
            product: sampleProduct,
            preFilledPrice: 10000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Set quantity to 3 via stepper
      await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
      await tester.pumpAndSettle();

      // Focus Unit Price
      await tester.tap(find.byKey(const Key('sheet_input_price')));
      await tester.pumpAndSettle();

      // Type 4, 5, 0, 000 -> 450,000
      await tester.tap(find.byKey(const Key('numpad_4')));
      await tester.tap(find.byKey(const Key('numpad_5')));
      await tester.tap(find.byKey(const Key('numpad_0')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_net_price'))).data, equals('450.000 đ'));
      // Line total = 450,000 * 3 = 1,350,000 đ
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('1.350.000 đ'));
    });

    testWidgets('2.4 Discount immediately recalculates net price and line total and clamps negative to 0',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: const StockInProductEditSheet(
            product: sampleProduct,
            preFilledPrice: 200000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Set quantity to 4
      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_4')));
      await tester.pumpAndSettle();

      // Focus Discount
      await tester.tap(find.byKey(const Key('sheet_input_discount')));
      await tester.pumpAndSettle();

      // Type 50,000 discount
      await tester.tap(find.byKey(const Key('numpad_5')));
      await tester.tap(find.byKey(const Key('numpad_0')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.pumpAndSettle();

      // Net price = 200,000 - 50,000 = 150,000 đ
      // Line total = 150,000 * 4 = 600,000 đ
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_net_price'))).data, equals('150.000 đ'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('600.000 đ'));

      // Adversarial discount: enter 250,000 discount (exceeds unit price 200,000)
      await tester.enterText(find.byKey(const Key('sheet_input_discount')), '250000');
      await tester.pumpAndSettle();

      // Clamped to 0 đ
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_net_price'))).data, equals('0 đ'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('0 đ'));
    });

    testWidgets('2.5 High number calculation stress test (large quantities and prices)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: const StockInProductEditSheet(
            product: sampleProduct,
            preFilledPrice: 50000000.0, // 50 million VND per unit
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Quantity = 100 via numpad
      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_1')));
      await tester.tap(find.byKey(const Key('numpad_00')));
      await tester.pumpAndSettle();

      // Discount = 2,000,000
      await tester.enterText(find.byKey(const Key('sheet_input_discount')), '2000000');
      await tester.pumpAndSettle();

      // Net price = 48,000,000 đ
      // Line total = 48,000,000 * 100 = 4,800,000,000 đ (4.8 billion)
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_net_price'))).data, equals('48.000.000 đ'));
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('4.800.000.000 đ'));
    });
  });

  group('Requirement 3: Note Input Multi-line & Special Characters Preservation', () {
    testWidgets('3.1 Multi-line note input preserves newlines and text verbatim',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? resultItem;
      const multiLineNote = 'Dòng 1: Gạo lúa mùa đặc biệt\nDòng 2: Độ ẩm < 14%\nDòng 3: Đạt chuẩn xuất khẩu EU\nDòng 4: Lô #2026-ST25-09';

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                resultItem = await StockInProductEditSheet.show(
                  context: ctx,
                  product: sampleProduct,
                  preFilledPrice: 300000.0,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter multi-line note into sheet_input_note
      await tester.enterText(find.byKey(const Key('sheet_input_note')), multiLineNote);
      await tester.pumpAndSettle();

      // Commit via Xong
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(resultItem, isNotNull);
      expect(resultItem!.note, equals(multiLineNote));
      expect(resultItem!.note.split('\n').length, equals(4));
    });

    testWidgets('3.2 Single-line special characters, Vietnamese diacritics, symbols, quotes, and emoji are preserved',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? resultItem;
      const singleLineComplexNote = 'Tiếng Việt: Ơ, Ư, Đ, Ê, Ô, À, Ả, Ầ, Ậ, ỹ! | Ký tự: <tag> & "kép" \'đơn\' / \\ | ! @ # \$ % ^ * ( ) _ + = - { } [ ] : ; , . ? | Unicode: 🌾 📦 💯 🔥 🍚 ✅ ₫ € ¥ £';

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                resultItem = await StockInProductEditSheet.show(
                  context: ctx,
                  product: sampleProduct,
                  preFilledPrice: 300000.0,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('sheet_input_note')), singleLineComplexNote);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(resultItem, isNotNull);
      expect(resultItem!.note, equals(singleLineComplexNote));
    });

    testWidgets('3.3 Pre-existing note on existingItem is loaded and preserved when unedited',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? resultItem;
      const initialNote = 'Ghi chú gốc từ phiếu nhập kho\nĐã kiểm đếm đợt 1';
      final existingItem = StockInReceiptItem(
        transactionId: 'TX_PRE_EXISTING',
        productId: sampleProduct.id,
        quantity: 2,
        unitPrice: 280000.0,
        originalPrice: 280000.0,
        note: initialNote,
      );

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                resultItem = await StockInProductEditSheet.show(
                  context: ctx,
                  product: sampleProduct,
                  existingItem: existingItem,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Verify text field shows initialNote
      final noteField = tester.widget<TextFormField>(find.byKey(const Key('sheet_input_note')));
      expect(noteField.controller?.text, equals(initialNote));

      // Commit without changing note
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(resultItem, isNotNull);
      expect(resultItem!.note, equals(initialNote));
    });

    testWidgets('3.4 Note field whitespace trimming strips external padding but keeps internal whitespace on single line',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? resultItem;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                resultItem = await StockInProductEditSheet.show(
                  context: ctx,
                  product: sampleProduct,
                  preFilledPrice: 100000.0,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('sheet_input_note')),
        '   \t  Dòng A    Dòng B  \t   ',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(resultItem, isNotNull);
      expect(resultItem!.note, equals('Dòng A    Dòng B'));
    });
  });

  group('Requirement 4: "Xong" Button, Numpad "Nhập" Enter Key, and Pop Lifecycle', () {
    testWidgets('4.1 "Xong" button returns exact, valid StockInReceiptItem with all fields populated',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? poppedItem;
      StockInReceiptItem? updatedItemFromCallback;
      int? cbQty;
      double? cbPrice;
      double? cbDiscount;
      String? cbNote;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                poppedItem = await StockInProductEditSheet.show(
                  context: ctx,
                  product: sampleProduct,
                  branchStock: 42,
                  preFilledPrice: 500000.0,
                  onDone: (qty, price, discount, note) {
                    cbQty = qty;
                    cbPrice = price;
                    cbDiscount = discount;
                    cbNote = note;
                  },
                  onItemUpdated: (item) {
                    updatedItemFromCallback = item;
                  },
                );
              },
              child: const Text('Open Modal'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Set Qty = 5
      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_5')));
      await tester.pumpAndSettle();

      // Set Discount = 50,000
      await tester.enterText(find.byKey(const Key('sheet_input_discount')), '50000');
      await tester.pumpAndSettle();

      // Set Note
      await tester.enterText(find.byKey(const Key('sheet_input_note')), 'Kiểm hàng đủ 5 bao');
      await tester.pumpAndSettle();

      // Tap "Xong"
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      // Sheet must be popped
      expect(find.byKey(const Key('product_edit_sheet')), findsNothing);

      // Verify popped item
      expect(poppedItem, isNotNull);
      expect(poppedItem!.productId, equals(sampleProduct.id));
      expect(poppedItem!.productName, equals(sampleProduct.name));
      expect(poppedItem!.productCode, equals(sampleProduct.code));
      expect(poppedItem!.barcode, equals(sampleProduct.barcode));
      expect(poppedItem!.unit, equals(sampleProduct.unit));
      expect(poppedItem!.quantity, equals(5));
      expect(poppedItem!.originalPrice, equals(500000.0));
      expect(poppedItem!.discount, equals(50000.0));
      expect(poppedItem!.unitPrice, equals(450000.0)); // 500,000 - 50,000
      expect(poppedItem!.totalPrice, equals(2250000.0)); // 450,000 * 5
      expect(poppedItem!.note, equals('Kiểm hàng đủ 5 bao'));

      // Verify callbacks
      expect(cbQty, equals(5));
      expect(cbPrice, equals(450000.0));
      expect(cbDiscount, equals(50000.0));
      expect(cbNote, equals('Kiểm hàng đủ 5 bao'));
      expect(updatedItemFromCallback, equals(poppedItem));
    });

    testWidgets('4.2 Numpad "Nhập" (Enter) key returns exact valid StockInReceiptItem and pops cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? poppedItem;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                poppedItem = await StockInProductEditSheet.show(
                  context: ctx,
                  product: sampleProduct,
                  preFilledPrice: 250000.0,
                );
              },
              child: const Text('Open Modal'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Tap "Nhập" key on AccountingNumpad
      await tester.tap(find.byKey(const Key('numpad_enter')));
      await tester.pumpAndSettle();

      // Sheet popped
      expect(find.byKey(const Key('product_edit_sheet')), findsNothing);

      expect(poppedItem, isNotNull);
      expect(poppedItem!.productId, equals(sampleProduct.id));
      expect(poppedItem!.quantity, equals(1));
      expect(poppedItem!.unitPrice, equals(250000.0));
      expect(poppedItem!.originalPrice, equals(250000.0));
    });

    testWidgets('4.3 Rapid double-tap on "Xong" or "Nhập" does not cause duplicate pop or crash',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int popCount = 0;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final res = await StockInProductEditSheet.show(
                  context: ctx,
                  product: sampleProduct,
                  preFilledPrice: 150000.0,
                );
                if (res != null) {
                  popCount++;
                }
              },
              child: const Text('Open Modal'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Rapidly tap "Xong" button multiple times in succession
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.tap(find.byKey(const Key('btn_sheet_done')), warnIfMissed: false);
      await tester.tap(find.byKey(const Key('numpad_enter')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(popCount, equals(1));
      expect(find.byKey(const Key('product_edit_sheet')), findsNothing);
    });

    testWidgets('4.4 Submitting with 0 quantity automatically clamps quantity to 1',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? poppedItem;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                poppedItem = await StockInProductEditSheet.show(
                  context: ctx,
                  product: sampleProduct,
                  preFilledPrice: 100000.0,
                );
              },
              child: const Text('Open Modal'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Focus quantity and type '0'
      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_0')));
      await tester.pumpAndSettle();

      // Tap "Xong"
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(poppedItem, isNotNull);
      // Effective quantity is clamped to 1
      expect(poppedItem!.quantity, equals(1));
    });

    testWidgets('4.5 Dismissing via back chevron pops cleanly returning null without executing callbacks',
        (tester) async {
      StockInReceiptItem? poppedItem;
      bool onDoneCalled = false;
      bool onItemUpdatedCalled = false;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                poppedItem = await StockInProductEditSheet.show(
                  context: ctx,
                  product: sampleProduct,
                  preFilledPrice: 100000.0,
                  onDone: (qty, price, discount, note) => onDoneCalled = true,
                  onItemUpdated: (item) => onItemUpdatedCalled = true,
                );
              },
              child: const Text('Open Modal'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Tap back chevron
      await tester.tap(find.byKey(const Key('btn_sheet_back')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('product_edit_sheet')), findsNothing);
      expect(poppedItem, isNull);
      expect(onDoneCalled, isFalse);
      expect(onItemUpdatedCalled, isFalse);
    });
  });
}
