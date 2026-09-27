import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_product_edit_sheet.dart';

class FakeStockInReceiptRepository implements StockInReceiptRepository {
  double? nextLatestPrice;

  @override
  Future<double?> getLatestImportPrice({required String storeId, required String productId}) async {
    return nextLatestPrice;
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
  group('StockInProductEditSheet Widget Tests', () {
    const testProduct = Product(
      id: 'PROD_ST26',
      name: 'Gạo sạch hữu cơ ST26 đặc sản',
      code: 'ST26',
      barcode: '893600000002',
      price: 6800000.0,
      costPrice: 6100000.0,
      branchStocks: {
        'store_001': 5,
        'store_002': 12,
      },
      category: 'Gạo đặc sản',
      unit: 'Bao 25kg',
    );

    testWidgets('renders header, SKU, stock badge, thumbnail, name and initial values', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 5,
            preFilledPrice: 6100000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Root widget and header
      expect(find.byKey(const Key('product_edit_sheet')), findsOneWidget);
      expect(find.byKey(const Key('sheet_header_sku')), findsOneWidget);
      expect(find.text('< ST26'), findsOneWidget);

      // Stock badge
      expect(find.byKey(const Key('sheet_stock_badge')), findsOneWidget);
      expect(find.text('Tồn: 5'), findsOneWidget);

      // Product information
      expect(find.text('Gạo sạch hữu cơ ST26 đặc sản'), findsOneWidget);
      expect(find.text('ĐVT: Bao 25kg'), findsOneWidget);

      // Initial inputs
      expect(find.byKey(const Key('sheet_qty_text')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('1'));
      expect(find.text('6.100.000'), findsOneWidget);

      // Initial calculated amounts
      expect(find.byKey(const Key('sheet_calculated_net_price')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_net_price'))).data, equals('6.100.000 đ'));
      expect(find.byKey(const Key('sheet_calculated_total')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('sheet_calculated_total'))).data, equals('6.100.000 đ'));
    });

    testWidgets('back chevron button dismisses the sheet without committing', (tester) async {
      bool dismissed = false;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final result = await showModalBottomSheet<StockInReceiptItem>(
                  context: ctx,
                  builder: (_) => const StockInProductEditSheet(
                    product: testProduct,
                    branchStock: 5,
                    preFilledPrice: 6100000.0,
                  ),
                );
                if (result == null) {
                  dismissed = true;
                }
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_sheet_back')), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_sheet_back')));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
      expect(find.byKey(const Key('product_edit_sheet')), findsNothing);
    });

    testWidgets('stepper increments and decrements quantity (minimum 1) and updates total', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 5,
            preFilledPrice: 100000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially quantity = 1, total = 100,000 đ
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('1'));
      expect(find.text('100.000 đ'), findsWidgets);

      // Decrement button disabled at quantity 1
      await tester.tap(find.byKey(const Key('sheet_stepper_dec')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('1'));

      // Increment 2 times -> quantity = 3, total = 300,000 đ
      await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('3'));
      expect(find.text('300.000 đ'), findsOneWidget);

      // Decrement 1 time -> quantity = 2, total = 200,000 đ
      await tester.tap(find.byKey(const Key('sheet_stepper_dec')));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('2'));
      expect(find.text('200.000 đ'), findsOneWidget);
    });

    testWidgets('discount reduces net price and line total in real time', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 5,
            preFilledPrice: 1000000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Increase quantity to 2
      await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
      await tester.pumpAndSettle();

      // Enter discount 150,000 đ
      await tester.enterText(find.byKey(const Key('sheet_input_discount')), '150000');
      await tester.pumpAndSettle();

      // Net price = 1,000,000 - 150,000 = 850,000 đ
      // Line total = 850,000 * 2 = 1,700,000 đ
      expect(find.byKey(const Key('sheet_calculated_net_price')), findsOneWidget);
      expect(find.text('850.000 đ'), findsOneWidget);

      expect(find.byKey(const Key('sheet_calculated_total')), findsOneWidget);
      expect(find.text('1.700.000 đ'), findsOneWidget);
    });

    testWidgets('discount exceeding unit price clamps net price to 0 đ', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 5,
            preFilledPrice: 50000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter discount 80,000 đ (exceeds unit price 50,000 đ)
      await tester.enterText(find.byKey(const Key('sheet_input_discount')), '80000');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sheet_calculated_net_price')), findsOneWidget);
      expect(find.text('0 đ'), findsWidgets);
    });

    testWidgets('embedded AccountingNumpad modifies focused field and updates calculations', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 5,
            preFilledPrice: 200000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Focus Quantity by tapping the quantity text
      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();

      // Press 4 on numpad -> quantity becomes 4
      await tester.tap(find.byKey(const Key('numpad_4')));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('4'));
      expect(find.text('800.000 đ'), findsOneWidget); // 200,000 * 4

      // 2. Focus Unit Price by tapping input field
      await tester.tap(find.byKey(const Key('sheet_input_price')));
      await tester.pumpAndSettle();

      // Type 5, then 000, then 000 -> 5,000,000
      await tester.tap(find.byKey(const Key('numpad_5')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.pumpAndSettle();

      expect(find.text('5.000.000'), findsOneWidget);
      expect(find.text('20.000.000 đ'), findsOneWidget); // 5,000,000 * 4

      // Backspace on price
      await tester.tap(find.byKey(const Key('numpad_backspace')));
      await tester.pumpAndSettle();
      expect(find.text('500.000'), findsOneWidget);

      // Clear on price
      await tester.tap(find.byKey(const Key('numpad_clear')));
      await tester.pumpAndSettle();
      expect(find.text('0'), findsWidgets);
    });

    testWidgets('queries latest import price from repository when preFilledPrice is null', (tester) async {
      final fakeRepo = FakeStockInReceiptRepository();
      fakeRepo.nextLatestPrice = 5900000.0;

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            stockInReceiptRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 5,
            // preFilledPrice omitted
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should automatically load and display 5,900,000 from fake repository
      expect(find.text('5.900.000'), findsOneWidget);
      expect(find.text('5.900.000 đ'), findsWidgets);
    });

    testWidgets('Xong button validates and returns StockInReceiptItem with correct values', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? poppedItem;
      int? onDoneQty;
      double? onDonePrice;
      double? onDoneDiscount;
      String? onDoneNote;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final item = await StockInProductEditSheet.show(
                  context: ctx,
                  product: testProduct,
                  branchStock: 5,
                  preFilledPrice: 500000.0,
                  onDone: (qty, price, discount, note) {
                    onDoneQty = qty;
                    onDonePrice = price;
                    onDoneDiscount = discount;
                    onDoneNote = note;
                  },
                );
                poppedItem = item;
              },
              child: const Text('Open Modal'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Increase quantity to 3
      await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
      await tester.pumpAndSettle();

      // Enter discount 50,000 đ
      await tester.enterText(find.byKey(const Key('sheet_input_discount')), '50000');
      await tester.pumpAndSettle();

      // Enter note
      await tester.enterText(find.byKey(const Key('sheet_input_note')), 'Hàng đạt chuẩn VietGAP');
      await tester.pumpAndSettle();

      // Tap "Xong"
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      // Verify onDone callback arguments
      expect(onDoneQty, equals(3));
      expect(onDonePrice, equals(450000.0)); // 500,000 - 50,000
      expect(onDoneDiscount, equals(50000.0));
      expect(onDoneNote, equals('Hàng đạt chuẩn VietGAP'));

      // Verify returned StockInReceiptItem
      expect(poppedItem, isNotNull);
      expect(poppedItem!.productId, equals(testProduct.id));
      expect(poppedItem!.productName, equals(testProduct.name));
      expect(poppedItem!.productCode, equals(testProduct.code));
      expect(poppedItem!.quantity, equals(3));
      expect(poppedItem!.unitPrice, equals(450000.0));
      expect(poppedItem!.originalPrice, equals(500000.0));
      expect(poppedItem!.discount, equals(50000.0));
      expect(poppedItem!.totalPrice, equals(1350000.0)); // 450,000 * 3
      expect(poppedItem!.note, equals('Hàng đạt chuẩn VietGAP'));
    });

    testWidgets('editing existingItem pre-fills existing quantities, prices, discounts, and note', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final existing = StockInReceiptItem(
        transactionId: 'TX_EXISTING',
        productId: testProduct.id,
        quantity: 10,
        unitPrice: 5000000.0,
        originalPrice: 5500000.0,
        discount: 500000.0,
        note: 'Giao hàng đợt 1',
        productName: testProduct.name,
      );

      await tester.pumpWidget(
        buildTestApp(
          child: StockInProductEditSheet(
            product: testProduct,
            existingItem: existing,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('10'), findsOneWidget);
      expect(find.text('5.500.000'), findsOneWidget); // Original price
      expect(find.text('500.000'), findsWidgets); // Discount
      expect(find.text('5.000.000 đ'), findsOneWidget); // Net price
      expect(find.text('50.000.000 đ'), findsOneWidget); // Total: 5,000,000 * 10
      expect(find.text('Giao hàng đợt 1'), findsOneWidget);
    });

    testWidgets('tapping Nhập on numpad also commits and returns updated item', (tester) async {
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
                final item = await StockInProductEditSheet.show(
                  context: ctx,
                  product: testProduct,
                  preFilledPrice: 300000.0,
                );
                poppedItem = item;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap "Nhập" key on AccountingNumpad
      await tester.tap(find.byKey(const Key('numpad_enter')));
      await tester.pumpAndSettle();

      expect(poppedItem, isNotNull);
      expect(poppedItem!.quantity, equals(1));
      expect(poppedItem!.unitPrice, equals(300000.0));
    });

    testWidgets('renders cleanly on narrow 320px, 360px, and 375px viewports without RenderFlex overflow',
        (tester) async {
      const viewports = [
        Size(320, 568), // iPhone SE 1st gen
        Size(360, 640), // Standard Android small
        Size(375, 667), // iPhone 8 / SE 2nd gen
      ];

      for (final size in viewports) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          buildTestApp(
            child: const StockInProductEditSheet(
              product: testProduct,
              branchStock: 5,
              preFilledPrice: 6100000.0,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Must not throw overflow on viewport $size');
        expect(find.byKey(const Key('product_edit_sheet')), findsOneWidget);
        expect(find.byKey(const Key('sheet_calculated_net_price')), findsOneWidget);
        expect(find.byKey(const Key('sheet_calculated_total')), findsOneWidget);
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
