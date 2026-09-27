import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';

import 'stock_in_test_harness.dart';

void main() {
  group('=== MOBILE STOCK-IN UPGRADE: TIER 1 FEATURE COVERAGE (R1 - R4) ===', () {
    late StockInE2ETestHarness harness;

    setUp(() {
      harness = StockInE2ETestHarness();
    });

    // ========================================================================
    // T1.1: Visual Stock-In Item Card list rendering & Stepper increment/decrement
    // ========================================================================
    testWidgets('T1.1: Item Card renders thumbnail, name, SKU, stock, stepper and updates totals dynamically', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final product = harness.products['PROD_ST25']!;
      int quantity = 2;

      await tester.pumpWidget(
        buildStockInTestApp(
          child: StatefulBuilder(
            builder: (context, setState) {
              final item = StockInReceiptItem(
                transactionId: 'TX_TEMP_01',
                productId: product.id,
                quantity: quantity,
                unitPrice: 115000.0,
                productName: product.name,
                productCode: product.code,
              );

              return VisualStockInItemCard(
                item: item,
                currentStock: product.stockInBranch(StockInE2ETestHarness.storeDongThang),
                onQuantityChanged: (newQty) {
                  setState(() => quantity = newQty);
                },
                onDelete: () {},
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify Card Info
      expect(find.text(product.name), findsOneWidget);
      expect(find.text('Mã: ST25 • Tồn kho: 10'), findsOneWidget);
      expect(find.text('Đơn giá: 115.000 đ'), findsOneWidget);
      expect(find.text('230.000 đ'), findsOneWidget); // 115,000 * 2
      expect(find.text('2'), findsOneWidget);

      // 2. Increment Stepper [+]
      await tester.tap(find.byKey(const Key('stepper_inc_PROD_ST25')));
      await tester.pumpAndSettle();

      expect(quantity, equals(3));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('345.000 đ'), findsOneWidget); // 115,000 * 3

      // 3. Decrement Stepper [-]
      await tester.tap(find.byKey(const Key('stepper_dec_PROD_ST25')));
      await tester.pumpAndSettle();

      expect(quantity, equals(2));
      expect(find.text('2'), findsOneWidget);
      expect(find.text('230.000 đ'), findsOneWidget);
    });

    // ========================================================================
    // T1.2: Swipe-to-delete with confirmation alert dialog ("Xóa hàng hóa này?")
    // ========================================================================
    testWidgets('T1.2: Swipe or tap delete reveals confirmation dialog; cancel retains item, confirm removes item', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final product = harness.products['PROD_ST25']!;
      bool isDeleted = false;

      await tester.pumpWidget(
        buildStockInTestApp(
          child: StatefulBuilder(
            builder: (context, setState) {
              if (isDeleted) {
                return const Center(child: Text('Danh sách trống', key: Key('empty_list_text')));
              }

              final item = StockInReceiptItem(
                transactionId: 'TX_TEMP_02',
                productId: product.id,
                quantity: 1,
                unitPrice: 115000.0,
                productName: product.name,
                productCode: product.code,
              );

              return VisualStockInItemCard(
                item: item,
                currentStock: 10,
                onQuantityChanged: (_) {},
                onDelete: () {
                  setState(() => isDeleted = true);
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Swipe left on the Item Card
      await tester.drag(find.byKey(const Key('item_card_PROD_ST25')), const Offset(-400, 0));
      await tester.pumpAndSettle();

      // Confirmation dialog must appear
      expect(find.byKey(const Key('delete_confirmation_dialog')), findsOneWidget);
      expect(find.text('Xóa hàng hóa này khỏi phiếu nhập?'), findsOneWidget);

      // 1. Tap Cancel -> Dialog closes, item retained
      await tester.tap(find.byKey(const Key('btn_cancel_delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_confirmation_dialog')), findsNothing);
      expect(find.byKey(const Key('item_card_PROD_ST25')), findsOneWidget);
      expect(isDeleted, isFalse);

      // 2. Swipe again and tap Confirm Delete
      await tester.drag(find.byKey(const Key('item_card_PROD_ST25')), const Offset(-400, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_confirm_delete')));
      await tester.pumpAndSettle();

      expect(isDeleted, isTrue);
      expect(find.byKey(const Key('empty_list_text')), findsOneWidget);
    });

    // ========================================================================
    // T1.3: Sticky Bottom Summary Bar
    // ========================================================================
    testWidgets('T1.3: Sticky bottom bar renders formatted sum, total quantity and action buttons', (tester) async {
      bool draftClicked = false;
      bool continueClicked = false;

      await tester.pumpWidget(
        buildStockInTestApp(
          child: Column(
            children: [
              const Expanded(child: Placeholder()),
              StickyBottomSummaryBar(
                totalAmount: 18400000.0,
                itemCount: 3,
                totalQuantity: 25,
                onSaveDraft: () => draftClicked = true,
                onContinue: () => continueClicked = true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sticky_bottom_summary_bar')), findsOneWidget);
      expect(find.text('18.400.000 đ'), findsOneWidget);
      expect(find.text('3 mặt hàng • Số lượng: 25'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_save_draft')));
      expect(draftClicked, isTrue);

      await tester.tap(find.byKey(const Key('btn_continue')));
      expect(continueClicked, isTrue);
    });

    // ========================================================================
    // T1.4: Step 2 Payment & Supplier Confirmation View
    // ========================================================================
    testWidgets('T1.4: Step 2 Payment View recalculates net payable, debt, and validates supplier requirement', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sampleReceipt = StockInReceipt(
        id: 'REC_STEP2_TEST',
        importCode: 'PN_STEP2_001',
        date: DateTime.now(),
        storeId: StockInE2ETestHarness.storeDongThang,
        items: [
          const StockInReceiptItem(
            transactionId: 'TX_1',
            productId: 'PROD_ST25',
            quantity: 10,
            unitPrice: 120000.0,
            productName: 'Lúa giống ST25',
          ),
        ],
        totalAmount: 1200000.0,
        discount: 0.0,
        paidAmount: 1200000.0,
      );

      bool completed = false;

      await tester.pumpWidget(
        buildStockInTestApp(
          child: StockInPaymentConfirmationView(
            receipt: sampleReceipt,
            suppliers: harness.suppliers.values.toList(),
            onComplete: ({
              required supplierId,
              required discount,
              required paidAmount,
              required paymentMethod,
              required note,
            }) {
              completed = true;
            },
            onSaveDraft: () {},
            onViewItems: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check initial values
      expect(find.text('1.200.000 đ'), findsWidgets); // Total amount
      expect(find.text('0 đ'), findsWidgets); // Remaining debt when fully paid

      // Enter discount 200,000 đ -> Net Payable becomes 1,000,000 đ
      await tester.enterText(find.byKey(const Key('input_receipt_discount')), '200000');
      await tester.pumpAndSettle();

      expect(find.text('1.000.000 đ'), findsWidgets);

      // Enter paid amount 600,000 đ -> Remaining debt becomes 400,000 đ
      await tester.enterText(find.byKey(const Key('input_paid_amount')), '600000');
      await tester.pumpAndSettle();

      expect(find.text('400.000 đ'), findsOneWidget);

      // Attempt complete without supplier when debt > 0 -> SnackBar warning
      await tester.tap(find.byKey(const Key('btn_payment_complete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('snackbar_supplier_required')), findsOneWidget);
      expect(completed, isFalse);

      // Select supplier & change payment method to Bank Transfer
      await tester.tap(find.byKey(const Key('dropdown_supplier')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Phân Bón Ánh Dương').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('payment_transfer')));
      await tester.pumpAndSettle();

      // Now complete succeeds
      await tester.tap(find.byKey(const Key('btn_payment_complete')));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
    });

    // ========================================================================
    // T1.5: Product Edit Modal Sheet with Latest Cost Price Pre-fill (Video 00:15 - 00:33)
    // ========================================================================
    testWidgets('T1.5: Product Edit Modal pre-fills latest cost price and calculates real-time net price and subtotal', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final pST26 = harness.products['PROD_ST26']!;
      final latestPrice = await harness.getLatestImportPrice(
        storeId: StockInE2ETestHarness.storeDongThang,
        productId: pST26.id,
      );

      expect(latestPrice, equals(6100000.0)); // From historical import

      int returnedQty = 0;
      double returnedPrice = 0.0;
      double returnedDiscount = 0.0;
      String returnedNote = '';

      await tester.pumpWidget(
        buildStockInTestApp(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => StockInProductEditSheet(
                    product: pST26,
                    branchStock: pST26.stockInBranch(StockInE2ETestHarness.storeDongThang),
                    preFilledPrice: latestPrice ?? pST26.costPrice,
                    onDone: (qty, unitPrice, discount, note) {
                      returnedQty = qty;
                      returnedPrice = unitPrice;
                      returnedDiscount = discount;
                      returnedNote = note;
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

      // Header checks matching video frame 010
      expect(find.byKey(const Key('sheet_header_sku')), findsOneWidget);
      expect(find.text('< ST26'), findsOneWidget);
      expect(find.text('Tồn: 1'), findsOneWidget);
      expect(find.text('6.100.000'), findsWidgets);

      // Increase quantity to 5
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
      }
      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);

      // Add discount 100,000 đ
      await tester.enterText(find.byKey(const Key('sheet_input_discount')), '100000');
      await tester.pumpAndSettle();

      // Real-time calculated values:
      // Giá nhập = 6,100,000 - 100,000 = 6,000,000 đ
      // Thành tiền = 6,000,000 * 5 = 30,000,000 đ
      expect(find.byKey(const Key('sheet_calculated_net_price')), findsOneWidget);
      expect(find.text('6.000.000 đ'), findsOneWidget);
      expect(find.byKey(const Key('sheet_calculated_total')), findsOneWidget);
      expect(find.text('30.000.000 đ'), findsOneWidget);

      // Add note
      await tester.enterText(find.byKey(const Key('sheet_input_note')), 'Hàng nhập tuyển chọn vụ mùa 2026');

      // Tap "Xong"
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      expect(returnedQty, equals(5));
      expect(returnedPrice, equals(6000000.0));
      expect(returnedDiscount, equals(100000.0));
      expect(returnedNote, equals('Hàng nhập tuyển chọn vụ mùa 2026'));
    });

    // ========================================================================
    // T1.6: Draft Save without Stock or Debt Mutations (INV-1)
    // ========================================================================
    test('T1.6: Saving draft writes status="draft" to RTDB with ZERO stock or debt side effects', () async {
      final pST25 = harness.products['PROD_ST25']!;
      final supABC = harness.suppliers['SUP_001']!;

      final initialStock = pST25.stockInBranch(StockInE2ETestHarness.storeDongThang);
      final initialCostPrice = pST25.costPrice;
      final initialSupplierDebt = supABC.currentDebt;
      final initialTotalPurchase = supABC.totalPurchase;
      final initialTxCount = harness.recordedTransactions.length;
      final initialDebtTxCount = harness.recordedDebtTransactions.length;

      final draftReceipt = StockInReceipt(
        id: 'PN_DRAFT_T1_6',
        importCode: 'PN_DRAFT_001',
        date: DateTime.now(),
        storeId: StockInE2ETestHarness.storeDongThang,
        supplierId: supABC.id,
        supplierName: supABC.name,
        items: [
          StockInReceiptItem(
            transactionId: 'TX_ITEM_01',
            productId: pST25.id,
            quantity: 50,
            unitPrice: 110000.0,
            productName: pST25.name,
          ),
        ],
        totalAmount: 5500000.0,
        discount: 500000.0,
        paidAmount: 2000000.0,
        debtAmount: 3000000.0,
        status: 'draft',
      );

      final savedId = await harness.saveDraft(draftReceipt);
      expect(savedId, equals('PN_DRAFT_T1_6'));

      // STRICT INVARIANT CHECKS:
      // 1. Stock remains unchanged
      expect(harness.products[pST25.id]!.stockInBranch(StockInE2ETestHarness.storeDongThang), equals(initialStock));
      // 2. Cost price remains unchanged
      expect(harness.products[pST25.id]!.costPrice, equals(initialCostPrice));
      // 3. Supplier debt & total purchase unchanged
      expect(harness.suppliers[supABC.id]!.currentDebt, equals(initialSupplierDebt));
      expect(harness.suppliers[supABC.id]!.totalPurchase, equals(initialTotalPurchase));
      // 4. No inventory transactions or debt ledger written
      expect(harness.recordedTransactions.length, equals(initialTxCount));
      expect(harness.recordedDebtTransactions.length, equals(initialDebtTxCount));

      // 5. RTDB document contains status = 'draft'
      final snap = await harness.db.ref('stores/${StockInE2ETestHarness.storeDongThang}/stock_in_receipts/$savedId').get();
      expect(snap.exists, isTrue);
      expect(snap.child('status').value, equals('draft'));
      expect(snap.child('totalAmount').value, equals(5500000.0));
    });

    // ========================================================================
    // T1.7: PopScope Exit Warning Dialog (3 choices)
    // ========================================================================
    testWidgets('T1.7: PopScope Exit Warning Dialog presents 3 explicit choices ("Lưu tạm", "Rời khỏi", "Ở lại")', (tester) async {
      bool draftSaved = false;
      bool discarded = false;
      bool stayed = false;

      await tester.pumpWidget(
        buildStockInTestApp(
          child: ExitReceiptDialog(
            onSaveDraft: () => draftSaved = true,
            onExitDiscard: () => discarded = true,
            onStay: () => stayed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('exit_receipt_dialog')), findsOneWidget);
      expect(find.byKey(const Key('dialog_choice_draft')), findsOneWidget);
      expect(find.byKey(const Key('dialog_choice_exit')), findsOneWidget);
      expect(find.byKey(const Key('dialog_choice_stay')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dialog_choice_stay')));
      expect(stayed, isTrue);

      await tester.tap(find.byKey(const Key('dialog_choice_exit')));
      expect(discarded, isTrue);

      await tester.tap(find.byKey(const Key('dialog_choice_draft')));
      expect(draftSaved, isTrue);
    });

    // ========================================================================
    // T1.8: Stock-In Receipts 3-State Filter & Status Badges
    // ========================================================================
    testWidgets('T1.8: Stock-In Receipts displays distinct status badges and filters accurately across 3 states', (tester) async {
      final rCompleted = StockInReceipt(
        id: 'REC_COMPLETED',
        importCode: 'PN_001',
        date: DateTime.now(),
        items: const [],
        status: 'completed',
      );
      final rDraft = StockInReceipt(
        id: 'REC_DRAFT',
        importCode: 'PN_002',
        date: DateTime.now(),
        items: const [],
        status: 'draft',
      );
      final rCancelled = StockInReceipt(
        id: 'REC_CANCELLED',
        importCode: 'PN_003',
        date: DateTime.now(),
        items: const [],
        status: 'cancelled',
      );

      final allReceipts = [rCompleted, rDraft, rCancelled];

      // 1. Verify Status Badges
      await tester.pumpWidget(
        buildStockInTestApp(
          child: Column(
            children: [
              StockInReceiptStatusBadge(status: rCompleted.status),
              StockInReceiptStatusBadge(status: rDraft.status),
              StockInReceiptStatusBadge(status: rCancelled.status),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('badge_completed')), findsOneWidget);
      expect(find.text('Đã hoàn thành'), findsOneWidget);

      expect(find.byKey(const Key('badge_draft')), findsOneWidget);
      expect(find.text('Phiếu tạm'), findsOneWidget);

      expect(find.byKey(const Key('badge_cancelled')), findsOneWidget);
      expect(find.text('Đã hủy'), findsOneWidget);

      // 2. Verify Filter Logic
      final completedOnly = harness.filterReceipts(receiptsList: allReceipts, statusFilter: 'completed');
      expect(completedOnly.length, equals(1));
      expect(completedOnly.first.id, equals('REC_COMPLETED'));

      final draftOnly = harness.filterReceipts(receiptsList: allReceipts, statusFilter: 'draft');
      expect(draftOnly.length, equals(1));
      expect(draftOnly.first.id, equals('REC_DRAFT'));

      final cancelledOnly = harness.filterReceipts(receiptsList: allReceipts, statusFilter: 'cancelled');
      expect(cancelledOnly.length, equals(1));
      expect(cancelledOnly.first.id, equals('REC_CANCELLED'));

      final all = harness.filterReceipts(receiptsList: allReceipts, statusFilter: 'all');
      expect(all.length, equals(3));
    });

    // ========================================================================
    // T1.9: Completed Receipt Cancellation Rollback (INV-3)
    // ========================================================================
    test('T1.9: Cancelling completed receipt rolls back branch stock and supplier debt with reversal audit', () async {
      final pFert = harness.products['PROD_FERT_NPK']!;
      final supABC = harness.suppliers['SUP_001']!;

      final initialStock = pFert.stockInBranch(StockInE2ETestHarness.storeDongThang); // 50
      final initialDebt = supABC.currentDebt; // 15,000,000
      final initialPurchase = supABC.totalPurchase; // 50,000,000

      // Step 1: Complete receipt importing 20 units @ 800,000 đ = 16,000,000 đ.
      // Discount = 1,000,000 đ -> Net Payable = 15,000,000 đ.
      // Paid = 5,000,000 đ -> Remaining debt = 10,000,000 đ.
      final receipt = StockInReceipt(
        id: 'REC_TO_CANCEL',
        importCode: 'PN_CANCEL_TEST_001',
        date: DateTime.now(),
        storeId: StockInE2ETestHarness.storeDongThang,
        supplierId: supABC.id,
        supplierName: supABC.name,
        items: [
          StockInReceiptItem(
            transactionId: 'TX_FERT_1',
            productId: pFert.id,
            quantity: 20,
            unitPrice: 800000.0,
            productName: pFert.name,
          ),
        ],
        totalAmount: 16000000.0,
        discount: 1000000.0,
        netPayable: 15000000.0,
        paidAmount: 5000000.0,
        debtAmount: 10000000.0,
      );

      await harness.completeReceipt(receipt, paymentMethod: 'cash', createdBy: 'admin_test');

      // Verify post-completion state
      expect(harness.products[pFert.id]!.stockInBranch(StockInE2ETestHarness.storeDongThang), equals(initialStock + 20)); // 70
      expect(harness.suppliers[supABC.id]!.currentDebt, equals(initialDebt + 10000000.0)); // 25,000,000
      expect(harness.suppliers[supABC.id]!.totalPurchase, equals(initialPurchase + 15000000.0)); // 65,000,000

      // Step 2: Cancel receipt with reason
      await harness.cancelReceipt(
        storeId: StockInE2ETestHarness.storeDongThang,
        receipt: harness.receipts[receipt.id]!,
        reason: 'Hàng bao rách ẩm mốc giao trả lại nhà cung cấp',
        cancelledBy: 'sup_dongthang',
      );

      // Verify rollback invariants:
      // 1. Stock rolled back by 20 units
      expect(harness.products[pFert.id]!.stockInBranch(StockInE2ETestHarness.storeDongThang), equals(initialStock)); // 50
      expect(harness.products[pFert.id]!.stockInBranch('branch_1'), equals(initialStock)); // Alias synced

      // 2. Supplier debt rolled back by 10,000,000 đ
      expect(harness.suppliers[supABC.id]!.currentDebt, equals(initialDebt)); // 15,000,000

      // 3. Supplier total purchase rolled back by 15,000,000 đ
      expect(harness.suppliers[supABC.id]!.totalPurchase, equals(initialPurchase)); // 50,000,000

      // 4. SupplierDebtTransaction logged with adjustment type and negative debt
      final lastDebtTx = harness.recordedDebtTransactions.last;
      expect(lastDebtTx.type, equals(SupplierDebtType.adjustment));
      expect(lastDebtTx.amount, equals(-10000000.0));
      expect(lastDebtTx.referenceCode, equals(receipt.importCode));
      expect(lastDebtTx.note, contains('Hàng bao rách ẩm mốc'));

      // 5. Export reversal transaction recorded
      final lastTx = harness.recordedTransactions.last;
      expect(lastTx.type, equals(TransactionType.export));
      expect(lastTx.quantity, equals(20));
      expect(lastTx.note, contains('Hủy phiếu nhập'));

      // 6. Receipt status in RTDB is 'cancelled'
      final audit = harness.receiptAudits[receipt.id]!;
      expect(audit.cancelReason, equals('Hàng bao rách ẩm mốc giao trả lại nhà cung cấp'));
      expect(audit.cancelledBy, equals('sup_dongthang'));
      expect(harness.receipts[receipt.id]!.status, equals('cancelled'));
    });
  });
}
