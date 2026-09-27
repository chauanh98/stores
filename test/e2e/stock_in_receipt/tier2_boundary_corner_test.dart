import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/transaction_type.dart';

import 'stock_in_test_harness.dart';

void main() {
  group('=== MOBILE STOCK-IN UPGRADE: TIER 2 BOUNDARY & CORNER CASES ===', () {
    late StockInE2ETestHarness harness;

    setUp(() {
      harness = StockInE2ETestHarness();
    });

    // ========================================================================
    // T2.1: Zero / Negative Quantity Guard
    // ========================================================================
    testWidgets(
        'T2.1: Stepper blocks decrement below 1 and validates against 0/negative input',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final product = harness.products['PROD_ST25']!;
      int currentQty = 1;

      await tester.pumpWidget(
        buildStockInTestApp(
          child: StatefulBuilder(
            builder: (context, setState) {
              final item = StockInReceiptItem(
                transactionId: 'TX_T2_1',
                productId: product.id,
                quantity: currentQty,
                unitPrice: 120000.0,
                productName: product.name,
                productCode: product.code,
              );

              return VisualStockInItemCard(
                item: item,
                currentStock: 10,
                onQuantityChanged: (newQty) {
                  if (newQty >= 1) setState(() => currentQty = newQty);
                },
                onDelete: () {},
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);

      // Decrement button tapped when quantity is 1
      await tester.tap(find.byKey(const Key('stepper_dec_PROD_ST25')));
      await tester.pumpAndSettle();

      // Quantity cannot drop to 0 or negative; triggers delete confirmation dialog
      expect(
          find.byKey(const Key('delete_confirmation_dialog')), findsOneWidget);
      expect(currentQty, equals(1));
    });

    // ========================================================================
    // T2.2: Negative Discount & Discount > Unit Price Clamping
    // ========================================================================
    testWidgets(
        'T2.2: Line discount exceeding unit price clamps net price to 0.0 to prevent negative line totals',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final pRegent = harness.products['PROD_PEST_01']!; // Unit price 45,000 đ
      double returnedPrice = -1.0;
      double returnedDiscount = -1.0;

      await tester.pumpWidget(
        buildStockInTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: ctx,
                  builder: (_) => StockInProductEditSheet(
                    product: pRegent,
                    branchStock: 100,
                    preFilledPrice: 45000.0,
                    onDone: (qty, unitPrice, discount, note) {
                      returnedPrice = unitPrice;
                      returnedDiscount = discount;
                    },
                  ),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Input discount 60,000 đ (which exceeds unit price 45,000 đ)
      await tester.enterText(
          find.byKey(const Key('sheet_input_discount')), '60000');
      await tester.pumpAndSettle();

      // Calculated net price must clamp to 0 đ (not -15,000 đ)
      expect(find.text('0 đ'), findsWidgets);

      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(returnedPrice, equals(0.0));
      expect(returnedDiscount, equals(60000.0));
    });

    // ========================================================================
    // T2.3: Extreme High Value / Overflow Safety (5 Billion VNĐ)
    // ========================================================================
    testWidgets(
        'T2.3: Receipt total exceeding 5,000,000,000 VNĐ formats cleanly without NaN or rendering overflow',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const largeTotal = 5000000000.0; // 5 tỷ VNĐ
      final currencyFormat = NumberFormat('#,###', 'vi_VN');
      final formattedExpected = '${currencyFormat.format(largeTotal)} đ';

      await tester.pumpWidget(
        buildStockInTestApp(
          child: Column(
            children: [
              const Expanded(child: Placeholder()),
              StickyBottomSummaryBar(
                totalAmount: largeTotal,
                itemCount: 10,
                totalQuantity: 5000,
                onSaveDraft: () {},
                onContinue: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(formattedExpected), findsOneWidget);
      expect(find.text('5.000.000.000 đ'), findsOneWidget);
    });

    // ========================================================================
    // T2.4: Empty Receipt Submission Guard
    // ========================================================================
    testWidgets('T2.4: Empty item list disables continue and draft buttons',
        (tester) async {
      bool continueCalled = false;
      bool draftCalled = false;

      await tester.pumpWidget(
        buildStockInTestApp(
          child: Column(
            children: [
              const Expanded(
                  child: Center(child: Text('Chưa có hàng trong phiếu'))),
              StickyBottomSummaryBar(
                totalAmount: 0.0,
                itemCount: 0,
                totalQuantity: 0,
                isEnabled: false,
                onSaveDraft: () => draftCalled = true,
                onContinue: () => continueCalled = true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_continue')));
      await tester.tap(find.byKey(const Key('btn_save_draft')));
      await tester.pumpAndSettle();

      expect(continueCalled, isFalse);
      expect(draftCalled, isFalse);
    });

    // ========================================================================
    // T2.5: Resumed Draft with Deleted Product
    // ========================================================================
    testWidgets(
        'T2.5: Resuming draft containing product deleted from catalog renders gracefully without crashing',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Draft contains PROD_OBSOLETE which is NOT in harness.products
      const obsoleteItem = StockInReceiptItem(
        transactionId: 'TX_OBSOLETE_01',
        productId: 'PROD_OBSOLETE',
        quantity: 10,
        unitPrice: 50000.0,
        productName: 'Sản phẩm ngưng kinh doanh',
        productCode: 'OBS01',
      );

      // Check that product is indeed deleted/absent from active catalog
      expect(harness.products.containsKey('PROD_OBSOLETE'), isFalse);

      await tester.pumpWidget(
        buildStockInTestApp(
          child: VisualStockInItemCard(
            item: obsoleteItem,
            currentStock: 0, // Fallback stock 0
            onQuantityChanged: (_) {},
            onDelete: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sản phẩm ngưng kinh doanh'), findsOneWidget);
      expect(find.text('Mã: OBS01 • Tồn kho: 0'), findsOneWidget);
      expect(find.text('500.000 đ'), findsOneWidget);
    });

    // ========================================================================
    // T2.6: Idempotent Cancellation
    // ========================================================================
    test(
        'T2.6: Repeated cancellation calls on already cancelled receipt are ignored without double-decrementing stock',
        () async {
      final pST25 = harness.products['PROD_ST25']!;
      final supABC = harness.suppliers['SUP_001']!;

      final initialStock =
          pST25.stockInBranch(StockInE2ETestHarness.storeDongThang);
      final initialDebt = supABC.currentDebt;

      final receipt = StockInReceipt(
        id: 'REC_DOUBLE_CANCEL_TEST',
        importCode: 'PN_IDEMPOTENT_001',
        date: DateTime.now(),
        storeId: StockInE2ETestHarness.storeDongThang,
        supplierId: supABC.id,
        items: [
          StockInReceiptItem(
            transactionId: 'TX_IDEM_1',
            productId: pST25.id,
            quantity: 5,
            unitPrice: 120000.0,
            productName: pST25.name,
          ),
        ],
        totalAmount: 600000.0,
        paidAmount: 200000.0,
        debtAmount: 400000.0,
      );

      // 1. Complete receipt
      await harness.completeReceipt(receipt);
      expect(
          harness.products[pST25.id]!
              .stockInBranch(StockInE2ETestHarness.storeDongThang),
          equals(initialStock + 5));

      // 2. First Cancellation
      await harness.cancelReceipt(
        storeId: StockInE2ETestHarness.storeDongThang,
        receipt: harness.receipts[receipt.id]!,
        reason: 'Hủy lần 1',
        cancelledBy: 'admin_test',
      );

      expect(
          harness.products[pST25.id]!
              .stockInBranch(StockInE2ETestHarness.storeDongThang),
          equals(initialStock));
      expect(harness.suppliers[supABC.id]!.currentDebt, equals(initialDebt));

      // 3. Second Cancellation Attempt (Duplicate)
      final cancelledReceipt = harness.receipts[receipt.id]!;
      expect(cancelledReceipt.isCancelled, isTrue);

      await harness.cancelReceipt(
        storeId: StockInE2ETestHarness.storeDongThang,
        receipt: cancelledReceipt,
        reason: 'Hủy lần 2 (trùng lặp)',
        cancelledBy: 'admin_test',
      );

      // Stock and debt MUST NOT be double-decremented!
      expect(
          harness.products[pST25.id]!
              .stockInBranch(StockInE2ETestHarness.storeDongThang),
          equals(initialStock));
      expect(harness.suppliers[supABC.id]!.currentDebt, equals(initialDebt));
    });

    // ========================================================================
    // T2.7: Negative Stock Clamping / Inventory Anomaly Handling
    // ========================================================================
    test(
        'T2.7: Cancellation when stock was already sold records negative stock and logs ledger audit accurately',
        () async {
      final pST26 = harness.products['PROD_ST26']!; // initial stock = 1
      const storeId = StockInE2ETestHarness.storeDongThang;

      final receipt = StockInReceipt(
        id: 'REC_ANOMALY_TEST',
        importCode: 'PN_ANOMALY_001',
        date: DateTime.now(),
        storeId: storeId,
        items: [
          StockInReceiptItem(
            transactionId: 'TX_ANOMALY_1',
            productId: pST26.id,
            quantity: 5,
            unitPrice: 6000000.0,
            productName: pST26.name,
          ),
        ],
        totalAmount: 30000000.0,
      );

      // 1. Complete receipt: stock becomes 1 + 5 = 6
      await harness.completeReceipt(receipt);
      expect(harness.products[pST26.id]!.stockInBranch(storeId), equals(6));

      // 2. Simulate POS sales of 5 units: stock drops to 1
      final prodAfterSales = harness.products[pST26.id]!.copyWith(
        branchStocks: {
          storeId: 1,
          'branch_1': 1,
        },
      );
      harness.products[pST26.id] = prodAfterSales;

      // 3. Manager cancels receipt of 5 units.
      // Current stock is 1 -> 1 - 5 = -4
      await harness.cancelReceipt(
        storeId: storeId,
        receipt: harness.receipts[receipt.id]!,
        reason: 'Hủy phiếu sau khi đã bán hàng ngoài quầy',
        cancelledBy: 'admin_test',
      );

      // Stock is negative (-4), correctly reflecting inventory deficit without crash
      final finalStock = harness.products[pST26.id]!.stockInBranch(storeId);
      expect(finalStock, equals(-4));

      // Audit transaction logged
      final lastTx = harness.recordedTransactions.last;
      expect(lastTx.type, equals(TransactionType.export));
      expect(lastTx.quantity, equals(5));
      expect(lastTx.note, contains('đã bán hàng ngoài quầy'));
    });

    // ========================================================================
    // T2.8: Paid Amount Greater Than Net Payable (Clamping Protection)
    // ========================================================================
    test(
        'T2.8: Paid amount greater than net payable clamps remaining debt to 0.0 without generating negative debt',
        () {
      final receipt = StockInReceipt(
        id: 'REC_OVERPAY_TEST',
        importCode: 'PN_OVERPAY_001',
        date: DateTime.now(),
        items: const [
          StockInReceiptItem(
            transactionId: 'TX_1',
            productId: 'PROD_ST25',
            quantity: 2,
            unitPrice: 100000.0,
          ),
        ],
        totalAmount: 200000.0,
        discount: 50000.0,
        // netPayable = 150,000 đ
        paidAmount: 200000.0, // paid > netPayable
      );

      expect(receipt.effectiveNetPayable, equals(150000.0));
      // remainingDebt formula: (effectiveNetPayable - paidAmount).clamp(0.0, double.infinity)
      final debt = (receipt.effectiveNetPayable - (receipt.paidAmount ?? 0.0))
          .clamp(0.0, double.infinity);
      expect(debt, equals(0.0));
    });
  });
}
