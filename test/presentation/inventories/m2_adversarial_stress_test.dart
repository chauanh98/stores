import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/inventories/widgets/accounting_numpad.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_product_edit_sheet.dart';

Widget buildStressTestApp({
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
  const testProduct = Product(
    id: 'PROD_STRESS_01',
    name: 'Sữa tươi tiệt trùng Vinamilk 100% 1L',
    code: 'VNM1L',
    barcode: '8934673123456',
    price: 38000.0,
    costPrice: 32000.0,
    branchStocks: {
      'store_001': 24,
      'store_002': 10,
    },
    category: 'Sữa & Bơ sữa',
    unit: 'Hộp 1L',
  );

  group('M2 Adversarial Stress Test: Rapid Numpad Typing & Multi-digit Inputs', () {
    testWidgets('T1.1: Rapid typing burst on price without delays formats properly', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildStressTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 24,
            preFilledPrice: 10000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus price
      await tester.tap(find.byKey(const Key('sheet_input_price')));
      await tester.pumpAndSettle();

      // Rapidly burst-tap 1, 2, 3, 4, 5, 6
      await tester.tap(find.byKey(const Key('numpad_1')));
      await tester.tap(find.byKey(const Key('numpad_2')));
      await tester.tap(find.byKey(const Key('numpad_3')));
      await tester.tap(find.byKey(const Key('numpad_4')));
      await tester.tap(find.byKey(const Key('numpad_5')));
      await tester.tap(find.byKey(const Key('numpad_6')));
      await tester.pumpAndSettle();

      // Should be formatted as 123.456
      expect(find.text('123.456'), findsOneWidget);
      expect(find.text('123.456 đ'), findsWidgets);
    });

    testWidgets('T1.2: Multi-digit keys (00 and 000) scale price into millions/billions cleanly', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildStressTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 24,
            preFilledPrice: 50000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sheet_input_price')));
      await tester.pumpAndSettle();

      // Tap 5 -> 5
      await tester.tap(find.byKey(const Key('numpad_5')));
      // Tap 00 -> 500
      await tester.tap(find.byKey(const Key('numpad_00')));
      // Tap 000 -> 500.000
      await tester.tap(find.byKey(const Key('numpad_000')));
      // Tap 000 -> 500.000.000
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.pumpAndSettle();

      expect(find.text('500.000.000'), findsOneWidget);
      expect(find.text('500.000.000 đ'), findsWidgets);
    });

    testWidgets('T1.3: Multi-digit keys (00 and 000) on quantity update integer quantity', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildStressTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 24,
            preFilledPrice: 2000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();

      // Tap 2, then 00 -> 200
      await tester.tap(find.byKey(const Key('numpad_2')));
      await tester.tap(find.byKey(const Key('numpad_00')));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('200'));
      // Total = 2000 * 200 = 400.000 đ
      expect(find.text('400.000 đ'), findsOneWidget);
    });

    testWidgets('T1.4: Fresh field with 000 or 00 keys handles leading zeros safely', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildStressTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 24,
            preFilledPrice: 2000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus discount (currently 0)
      await tester.tap(find.byKey(const Key('sheet_input_discount')));
      await tester.pumpAndSettle();

      // Tap 000 multiple times on fresh discount
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.pumpAndSettle();

      // Discount remains 0
      expect(find.text('0'), findsWidgets);

      // Now tap 7
      await tester.tap(find.byKey(const Key('numpad_7')));
      await tester.pumpAndSettle();

      final discountController = tester.widget<TextFormField>(find.byKey(const Key('sheet_input_discount'))).controller;
      expect(discountController?.text, equals('7'));
    });
  });

  group('M2 Adversarial Stress Test: Backspace on Empty & Clear Stress', () {
    testWidgets('T2.1: 10 consecutive backspaces on empty/zero price do not throw or crash', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildStressTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 24,
            preFilledPrice: 1000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sheet_input_price')));
      await tester.pumpAndSettle();

      // Backspace 10 times consecutively
      for (int i = 0; i < 10; i++) {
        await tester.tap(find.byKey(const Key('numpad_backspace')));
      }
      await tester.pumpAndSettle();

      // Price is 0
      expect(find.text('0'), findsWidgets);
      // Net price is 0 đ
      expect(find.text('0 đ'), findsWidgets);
    });

    testWidgets('T2.2: 10 consecutive backspaces on quantity reduce to 0, commit clamps to 1', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? resultItem;

      await tester.pumpWidget(
        buildStressTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final item = await StockInProductEditSheet.show(
                  context: ctx,
                  product: testProduct,
                  branchStock: 24,
                  preFilledPrice: 50000.0,
                );
                resultItem = item;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Focus quantity
      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();

      // Backspace 10 times consecutively
      for (int i = 0; i < 10; i++) {
        await tester.tap(find.byKey(const Key('numpad_backspace')));
      }
      await tester.pumpAndSettle();

      // Displayed quantity is '0'
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('0'));

      // Commit via "Xong" button
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      // Clamped to minimum 1
      expect(resultItem, isNotNull);
      expect(resultItem!.quantity, equals(1));
    });

    testWidgets('T2.3: Clear ("C") resets active field to 0 (or 1 for qty) and updates live total', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildStressTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 24,
            preFilledPrice: 80000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Clear Price
      await tester.tap(find.byKey(const Key('sheet_input_price')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_clear')));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsWidgets);
      expect(find.text('0 đ'), findsWidgets);

      // 2. Set price back to 50,000
      await tester.tap(find.byKey(const Key('numpad_5')));
      await tester.tap(find.byKey(const Key('numpad_0')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.pumpAndSettle();
      expect(find.text('50.000'), findsOneWidget);

      // 3. Clear Quantity
      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_9')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('9'));

      await tester.tap(find.byKey(const Key('numpad_clear')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('1'));
    });
  });

  group('M2 Adversarial Stress Test: Stepper Floor & Discount Clamping', () {
    testWidgets('T3.1: Stepper at qty 1 decrement remains 1 (multiple decrement taps)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildStressTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 24,
            preFilledPrice: 40000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('1'));

      // Tap decrement 10 times
      for (int i = 0; i < 10; i++) {
        await tester.tap(find.byKey(const Key('sheet_stepper_dec')));
      }
      await tester.pumpAndSettle();

      // Remains strictly 1
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('1'));
      expect(find.text('40.000 đ'), findsWidgets);
    });

    testWidgets('T3.2: Increment to 5, then decrement 10 times stops firmly at 1', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildStressTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 24,
            preFilledPrice: 10000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Increment 4 times -> qty = 5
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('5'));

      // Decrement 10 times with pump between taps -> stops at 1
      for (int i = 0; i < 10; i++) {
        await tester.tap(find.byKey(const Key('sheet_stepper_dec')));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('1'));
      expect(find.text('10.000 đ'), findsWidgets);
    });

    testWidgets('T3.3: Discount equal to price results in net price = 0 đ and total = 0 đ', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildStressTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 24,
            preFilledPrice: 50000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus discount and enter 50000
      await tester.tap(find.byKey(const Key('sheet_input_discount')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('numpad_5')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.tap(find.byKey(const Key('numpad_0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sheet_calculated_net_price')), findsOneWidget);
      expect(find.text('0 đ'), findsWidgets);
      expect(find.byKey(const Key('sheet_calculated_total')), findsOneWidget);
    });

    testWidgets('T3.4: Discount larger than price clamps net price and line total to 0 đ without negative values', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? resultItem;

      await tester.pumpWidget(
        buildStressTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final item = await StockInProductEditSheet.show(
                  context: ctx,
                  product: testProduct,
                  branchStock: 24,
                  preFilledPrice: 30000.0,
                );
                resultItem = item;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter discount 100,000 via numpad
      await tester.tap(find.byKey(const Key('sheet_input_discount')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('numpad_1')));
      await tester.tap(find.byKey(const Key('numpad_00')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.pumpAndSettle();

      // Net price must be 0 đ (not -70.000 đ)
      expect(find.text('0 đ'), findsWidgets);
      expect(find.text('-70.000 đ'), findsNothing);

      // Commit
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(resultItem, isNotNull);
      expect(resultItem!.unitPrice, equals(0.0)); // Net price clamped to 0
      expect(resultItem!.originalPrice, equals(30000.0));
      expect(resultItem!.discount, equals(100000.0));
      expect(resultItem!.totalPrice, equals(0.0));
    });
  });

  group('M2 Adversarial Stress Test: Decimal Point Behavior', () {
    testWidgets('T4.1: Decimal point key is completely ignored on integer quantity', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildStressTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 24,
            preFilledPrice: 10000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();

      // Tap 3, then '.', then 5
      await tester.tap(find.byKey(const Key('numpad_3')));
      await tester.tap(find.byKey(const Key('numpad_.')));
      await tester.tap(find.byKey(const Key('numpad_5')));
      await tester.pumpAndSettle();

      // '.' was ignored -> quantity is 35
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('35'));
    });

    testWidgets('T4.2: Decimal point on price with existing thousand separator is ignored safely', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildStressTestApp(
          child: const StockInProductEditSheet(
            product: testProduct,
            branchStock: 24,
            preFilledPrice: 50000.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sheet_input_price')));
      await tester.pumpAndSettle();

      // Tap '.' on '50.000'
      await tester.tap(find.byKey(const Key('numpad_.')));
      await tester.pumpAndSettle();

      // Does not throw, does not produce NaN
      expect(find.text('50.000'), findsOneWidget);
    });
  });

  group('M2 Adversarial Stress Test: Seamless Field Focus Switching Without Data Loss', () {
    testWidgets('T5.1: Switching focus between Qty, Price, Discount retains all edited values', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? resultItem;

      await tester.pumpWidget(
        buildStressTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final item = await StockInProductEditSheet.show(
                  context: ctx,
                  product: testProduct,
                  branchStock: 24,
                  preFilledPrice: 200000.0,
                );
                resultItem = item;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // 1. Focus Quantity -> set to 12
      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_1')));
      await tester.tap(find.byKey(const Key('numpad_2')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('12'));

      // 2. Switch to Unit Price -> set to 150.000
      await tester.tap(find.byKey(const Key('sheet_input_price')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_1')));
      await tester.tap(find.byKey(const Key('numpad_5')));
      await tester.tap(find.byKey(const Key('numpad_0')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.pumpAndSettle();

      // Verify Qty was NOT lost!
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('12'));
      expect(find.text('150.000'), findsOneWidget);

      // 3. Switch to Discount -> set to 30.000
      await tester.tap(find.byKey(const Key('sheet_input_discount')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_3')));
      await tester.tap(find.byKey(const Key('numpad_0')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.pumpAndSettle();

      // Verify Qty & Price were NOT lost!
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('12'));
      expect(find.text('150.000'), findsOneWidget);
      expect(find.text('30.000'), findsOneWidget);

      // Net price = 150,000 - 30,000 = 120,000 đ
      expect(find.text('120.000 đ'), findsOneWidget);
      // Total = 120,000 * 12 = 1,440,000 đ
      expect(find.text('1.440.000 đ'), findsOneWidget);

      // 4. Switch back to Quantity and increment via stepper
      await tester.tap(find.byKey(const Key('sheet_qty_text')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
      await tester.pumpAndSettle();

      // Qty becomes 13
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('13'));
      // Total = 120,000 * 13 = 1,560,000 đ
      expect(find.text('1.560.000 đ'), findsOneWidget);

      // 5. Enter note
      await tester.enterText(find.byKey(const Key('sheet_input_note')), 'Kiểm tra chất lượng lô hàng');
      await tester.pumpAndSettle();

      // 6. Commit via "Xong"
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(resultItem, isNotNull);
      expect(resultItem!.quantity, equals(13));
      expect(resultItem!.unitPrice, equals(120000.0)); // Net price
      expect(resultItem!.originalPrice, equals(150000.0));
      expect(resultItem!.discount, equals(30000.0));
      expect(resultItem!.totalPrice, equals(1560000.0));
      expect(resultItem!.note, equals('Kiểm tra chất lượng lô hàng'));
    });

    testWidgets('T5.2: Tapping field and immediately committing without editing preserves existing value', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? resultItem;

      await tester.pumpWidget(
        buildStressTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final item = await StockInProductEditSheet.show(
                  context: ctx,
                  product: testProduct,
                  branchStock: 24,
                  preFilledPrice: 75000.0,
                );
                resultItem = item;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap price field (sets _isPriceFresh = true) but don't type anything
      await tester.tap(find.byKey(const Key('sheet_input_price')));
      await tester.pumpAndSettle();

      // Immediately tap "Xong"
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(resultItem, isNotNull);
      expect(resultItem!.unitPrice, equals(75000.0)); // Original 75,000 preserved!
    });
  });

  group('M2 Adversarial Stress Test: AccountingNumpad Standalone Robustness', () {
    testWidgets('T6.1: Null callbacks on all 16 keys do not throw exceptions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccountingNumpad(),
          ),
        ),
      );

      // Tap every single key on the numpad
      final keys = [
        '1', '2', '3', 'backspace',
        '4', '5', '6', 'clear',
        '7', '8', '9', '000',
        '.', '0', '00', 'enter',
      ];

      for (final k in keys) {
        await tester.tap(find.byKey(Key('numpad_$k')));
      }
      await tester.pumpAndSettle();

      // No exception thrown!
      expect(find.byKey(const Key('accounting_numpad')), findsOneWidget);
    });

    testWidgets('T6.2: Rapid key taps fire corresponding callbacks accurately', (tester) async {
      final List<String> digits = [];
      int deletes = 0;
      int clears = 0;
      int dones = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountingNumpad(
              onDigit: (d) => digits.add(d),
              onDelete: () => deletes++,
              onClear: () => clears++,
              onDone: () => dones++,
            ),
          ),
        ),
      );

      // Burst of rapid taps
      await tester.tap(find.byKey(const Key('numpad_1')));
      await tester.tap(find.byKey(const Key('numpad_2')));
      await tester.tap(find.byKey(const Key('numpad_00')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.tap(find.byKey(const Key('numpad_backspace')));
      await tester.tap(find.byKey(const Key('numpad_clear')));
      await tester.tap(find.byKey(const Key('numpad_enter')));
      await tester.pumpAndSettle();

      expect(digits, equals(['1', '2', '00', '000']));
      expect(deletes, equals(1));
      expect(clears, equals(1));
      expect(dones, equals(1));
    });
  });

  group('M2 Adversarial Stress Test: Existing Item Mutation & Extreme Values', () {
    testWidgets('T7.1: Mutating existingItem preserves transactionId and updates all fields', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? updatedItem;

      final existing = StockInReceiptItem(
        transactionId: 'TX_PRESERVE_999',
        productId: testProduct.id,
        quantity: 10,
        unitPrice: 30000.0,
        originalPrice: 32000.0,
        discount: 2000.0,
        note: 'Ghi chú ban đầu',
        productName: testProduct.name,
      );

      await tester.pumpWidget(
        buildStressTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final item = await StockInProductEditSheet.show(
                  context: ctx,
                  product: testProduct,
                  existingItem: existing,
                );
                updatedItem = item;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Decrement quantity 5 times
      for (int i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('sheet_stepper_dec')));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sheet_qty_text'))).data, equals('5'));

      // Modify note
      await tester.enterText(find.byKey(const Key('sheet_input_note')), 'Ghi chú cập nhật');
      await tester.pumpAndSettle();

      // Commit
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(updatedItem, isNotNull);
      expect(updatedItem!.transactionId, equals('TX_PRESERVE_999')); // Preserved
      expect(updatedItem!.quantity, equals(5));
      expect(updatedItem!.originalPrice, equals(32000.0));
      expect(updatedItem!.discount, equals(2000.0));
      expect(updatedItem!.unitPrice, equals(30000.0));
      expect(updatedItem!.totalPrice, equals(150000.0)); // 30,000 * 5
      expect(updatedItem!.note, equals('Ghi chú cập nhật'));
    });

    testWidgets('T7.2: Extreme values: price of 999,000,000 with qty 5 calculates 4.995.000.000 đ', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? resultItem;

      await tester.pumpWidget(
        buildStressTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final item = await StockInProductEditSheet.show(
                  context: ctx,
                  product: testProduct,
                  branchStock: 24,
                  preFilledPrice: 1000.0,
                );
                resultItem = item;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Set qty to 5 via stepper
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // Focus price -> type 999,000,000
      await tester.tap(find.byKey(const Key('sheet_input_price')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_9')));
      await tester.tap(find.byKey(const Key('numpad_9')));
      await tester.tap(find.byKey(const Key('numpad_9')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.pumpAndSettle();

      expect(find.text('999.000.000'), findsOneWidget);
      // Total = 999,000,000 * 5 = 4,995,000,000 đ
      expect(find.text('4.995.000.000 đ'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(resultItem, isNotNull);
      expect(resultItem!.quantity, equals(5));
      expect(resultItem!.unitPrice, equals(999000000.0));
      expect(resultItem!.totalPrice, equals(4995000000.0));
    });

    testWidgets('T7.3: Huge discount (999,999,999) with smaller price safely clamps to 0 đ', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StockInReceiptItem? resultItem;

      await tester.pumpWidget(
        buildStressTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final item = await StockInProductEditSheet.show(
                  context: ctx,
                  product: testProduct,
                  branchStock: 24,
                  preFilledPrice: 50000.0,
                );
                resultItem = item;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter 999,999,999 discount
      await tester.tap(find.byKey(const Key('sheet_input_discount')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_9')));
      await tester.tap(find.byKey(const Key('numpad_9')));
      await tester.tap(find.byKey(const Key('numpad_9')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.pumpAndSettle();

      expect(find.text('0 đ'), findsWidgets);
      expect(find.text('999.000.000'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(resultItem, isNotNull);
      expect(resultItem!.originalPrice, equals(50000.0));
      expect(resultItem!.discount, equals(999000000.0));
      expect(resultItem!.unitPrice, equals(0.0));
      expect(resultItem!.totalPrice, equals(0.0));
    });
  });
}
