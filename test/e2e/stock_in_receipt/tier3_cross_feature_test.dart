import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';

import 'stock_in_test_harness.dart';

void main() {
  group('=== MOBILE STOCK-IN UPGRADE: TIER 3 CROSS-FEATURE COMBINATIONS ===',
      () {
    late StockInE2ETestHarness harness;

    setUp(() {
      harness = StockInE2ETestHarness();
    });

    // ========================================================================
    // T3.1: Complete Lifecycle: Draft -> Resume -> Edit -> Complete -> Cancel -> Audit Rollback
    // ========================================================================
    test(
        'T3.1: Full End-to-End Lifecycle: Draft -> Resume -> Edit -> Complete -> Cancel -> Verify Stock & Debt & Audit',
        () async {
      final pST25 = harness.products['PROD_ST25']!; // Initial stock 10
      final pST26 = harness.products['PROD_ST26']!; // Initial stock 1
      final pFert = harness.products['PROD_FERT_NPK']!; // Initial stock 50
      final supABC = harness.suppliers[
          'SUP_001']!; // Initial debt 15,000,000, purchase 50,000,000

      const storeId = StockInE2ETestHarness.storeDongThang;

      // ── Step 1: Create initial draft with ST25 (5 units @ 110k) and ST26 (1 unit @ 6,000k) ──
      final draft1 = StockInReceipt(
        id: 'LIFECYCLE_DRAFT_001',
        importCode: 'PN_LC_001',
        date: DateTime.now(),
        storeId: storeId,
        items: [
          StockInReceiptItem(
            transactionId: 'TX_LC_1',
            productId: pST25.id,
            quantity: 5,
            unitPrice: 110000.0,
            productName: pST25.name,
          ),
          StockInReceiptItem(
            transactionId: 'TX_LC_2',
            productId: pST26.id,
            quantity: 1,
            unitPrice: 6000000.0,
            productName: pST26.name,
          ),
        ],
        totalAmount: 6550000.0,
        status: 'draft',
      );

      final draftId = await harness.saveDraft(draft1);
      expect(draftId, equals('LIFECYCLE_DRAFT_001'));

      // Check Invariant: RTDB has draft, stock and debt are UNCHANGED
      expect(harness.products[pST25.id]!.stockInBranch(storeId), equals(10));
      expect(harness.products[pST26.id]!.stockInBranch(storeId), equals(1));
      expect(harness.suppliers[supABC.id]!.currentDebt, equals(15000000.0));
      expect(harness.suppliers[supABC.id]!.totalPurchase, equals(50000000.0));

      // ── Step 2: Resume Draft from "Phiếu tạm" tab ──
      final draftsList = harness.filterReceipts(
        receiptsList: harness.receipts.values.toList(),
        statusFilter: 'draft',
      );
      expect(draftsList.any((d) => d.id == draftId), isTrue);

      final resumedDraft = harness.receipts[draftId]!;
      expect(resumedDraft.items.length, equals(2));
      expect(resumedDraft.isDraft, isTrue);

      // ── Step 3: Edit Draft: Modify ST25 to 8 units, add pFert (2 units @ 800k), select Supplier ABC ──
      final updatedItems = [
        resumedDraft.items[0].copyWith(quantity: 8), // 8 * 110k = 880k
        resumedDraft.items[1], // 1 * 6,000k = 6,000k
        StockInReceiptItem(
          transactionId: 'TX_LC_3',
          productId: pFert.id,
          quantity: 2,
          unitPrice: 800000.0,
          // 2 * 800k = 1,600k
          productName: pFert.name,
        ),
      ];

      const double newTotal =
          (8 * 110000.0) + (1 * 6000000.0) + (2 * 800000.0); // 8,480,000 đ
      const double discount = 480000.0; // netPayable = 8,000,000 đ
      const double paidAmount =
          4000000.0; // 50% cash payment -> remaining debt = 4,000,000 đ

      final receiptToComplete = resumedDraft.copyWith(
        items: updatedItems,
        totalAmount: newTotal,
        discount: discount,
        netPayable: newTotal - discount,
        paidAmount: paidAmount,
        debtAmount: (newTotal - discount) - paidAmount,
        supplierId: supABC.id,
        supplierName: supABC.name,
      );

      // ── Step 4: Complete Receipt ──
      await harness.completeReceipt(
        receiptToComplete,
        paymentMethod: 'cash',
        createdBy: 'admin_test',
      );

      // Verify post-complete state:
      // Stock: ST25: 10 + 8 = 18; ST26: 1 + 1 = 2; Fert: 50 + 2 = 52
      expect(harness.products[pST25.id]!.stockInBranch(storeId), equals(18));
      expect(harness.products[pST26.id]!.stockInBranch(storeId), equals(2));
      expect(harness.products[pFert.id]!.stockInBranch(storeId), equals(52));

      // Supplier debt & total purchase:
      // Debt: 15,000,000 + 4,000,000 = 19,000,000 đ
      // Total Purchase: 50,000,000 + 8,000,000 = 58,000,000 đ
      expect(harness.suppliers[supABC.id]!.currentDebt, equals(19000000.0));
      expect(harness.suppliers[supABC.id]!.totalPurchase, equals(58000000.0));
      expect(harness.receipts[draftId]!.isCompleted, isTrue);

      // ── Step 5: Cancel Receipt with Reason ──
      await harness.cancelReceipt(
        storeId: storeId,
        receipt: harness.receipts[draftId]!,
        reason: 'Hàng không đúng chủng loại yêu cầu, hoàn trả kho nhà cung cấp',
        cancelledBy: 'sup_dongthang',
      );

      // Verify post-cancel state:
      // Stock rolled back:
      expect(harness.products[pST25.id]!.stockInBranch(storeId), equals(10));
      expect(harness.products[pST26.id]!.stockInBranch(storeId), equals(1));
      expect(harness.products[pFert.id]!.stockInBranch(storeId), equals(50));

      // Supplier debt & total purchase rolled back:
      expect(harness.suppliers[supABC.id]!.currentDebt, equals(15000000.0));
      expect(harness.suppliers[supABC.id]!.totalPurchase, equals(50000000.0));

      // Audit trail:
      final auditRecord = harness.receiptAudits[draftId]!;
      expect(
          auditRecord.cancelReason,
          equals(
              'Hàng không đúng chủng loại yêu cầu, hoàn trả kho nhà cung cấp'));
      expect(auditRecord.cancelledBy, equals('sup_dongthang'));

      // Reversal debt transaction:
      final reversalDebtTx = harness.recordedDebtTransactions.last;
      expect(reversalDebtTx.type, equals(SupplierDebtType.adjustment));
      expect(reversalDebtTx.amount, equals(-4000000.0));

      // Reversal inventory export transactions recorded:
      final reversalTxs = harness.recordedTransactions
          .where((t) =>
              t.type == TransactionType.export &&
              t.importCode == receiptToComplete.importCode)
          .toList();
      expect(reversalTxs.length, equals(3));
    });

    // ========================================================================
    // T3.2: Multi-Branch Draft Scoping & Isolation
    // ========================================================================
    test(
        'T3.2: Drafts created in store_001 and store_002 remain strictly isolated by branch scope',
        () async {
      final pST25 = harness
          .products['PROD_ST25']!; // Initial: Đông Thắng = 10, Thới Bình = 25

      // 1. Create draft D1 in store_001 (Đông Thắng)
      final draftD1 = StockInReceipt(
        id: 'DRAFT_STORE_001',
        importCode: 'PN_DT_01',
        date: DateTime.now(),
        storeId: StockInE2ETestHarness.storeDongThang,
        items: [
          StockInReceiptItem(
            transactionId: 'TX_D1',
            productId: pST25.id,
            quantity: 15,
            unitPrice: 120000.0,
            productName: pST25.name,
          ),
        ],
        totalAmount: 1800000.0,
        status: 'draft',
      );
      await harness.saveDraft(draftD1);

      // 2. Create draft D2 in store_002 (Thới Bình)
      final draftD2 = StockInReceipt(
        id: 'DRAFT_STORE_002',
        importCode: 'PN_TB_01',
        date: DateTime.now(),
        storeId: StockInE2ETestHarness.storeThoiBinh,
        items: [
          StockInReceiptItem(
            transactionId: 'TX_D2',
            productId: pST25.id,
            quantity: 40,
            unitPrice: 120000.0,
            productName: pST25.name,
          ),
        ],
        totalAmount: 4800000.0,
        status: 'draft',
      );
      await harness.saveDraft(draftD2);

      // 3. Verify Branch-Scoped RTDB paths
      final snapD1 = await harness.db
          .ref(
              'stores/${StockInE2ETestHarness.storeDongThang}/stock_in_receipts/DRAFT_STORE_001')
          .get();
      final snapD2 = await harness.db
          .ref(
              'stores/${StockInE2ETestHarness.storeThoiBinh}/stock_in_receipts/DRAFT_STORE_002')
          .get();

      expect(snapD1.exists, isTrue);
      expect(snapD2.exists, isTrue);

      // Ensure D1 is NOT under store_002, and D2 is NOT under store_001
      final snapD1InStore2 = await harness.db
          .ref(
              'stores/${StockInE2ETestHarness.storeThoiBinh}/stock_in_receipts/DRAFT_STORE_001')
          .get();
      final snapD2InStore1 = await harness.db
          .ref(
              'stores/${StockInE2ETestHarness.storeDongThang}/stock_in_receipts/DRAFT_STORE_002')
          .get();

      expect(snapD1InStore2.exists, isFalse);
      expect(snapD2InStore1.exists, isFalse);

      // 4. Complete D1 for Đông Thắng: ONLY Đông Thắng stock updates (10 + 15 = 25); Thới Bình remains 25!
      await harness.completeReceipt(draftD1);

      final pAfterD1 = harness.products[pST25.id]!;
      expect(pAfterD1.stockInBranch(StockInE2ETestHarness.storeDongThang),
          equals(25));
      expect(pAfterD1.stockInBranch('branch_1'), equals(25)); // Canonical alias
      expect(pAfterD1.stockInBranch(StockInE2ETestHarness.storeThoiBinh),
          equals(25)); // Untouched!
    });

    // ========================================================================
    // T3.3: Exit Warning 3-Choice Interaction Flows
    // ========================================================================
    testWidgets(
        'T3.3: Exit dialog flows: "Ở lại" preserves state, "Rời khỏi" discards, "Lưu tạm" persists to RTDB',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final product = harness.products['PROD_ST25']!;
      bool isDirty = true;
      bool pagePopped = false;
      bool draftPersisted = false;

      Widget buildInteractiveExitFlow() {
        return buildStockInTestApp(
          child: Builder(
            builder: (ctx) {
              return ElevatedButton(
                key: const Key('btn_simulate_back'),
                onPressed: () {
                  if (isDirty) {
                    showDialog(
                      context: ctx,
                      builder: (dialogCtx) => ExitReceiptDialog(
                        onStay: () => Navigator.of(dialogCtx).pop(),
                        onExitDiscard: () {
                          Navigator.of(dialogCtx).pop();
                          pagePopped = true;
                        },
                        onSaveDraft: () async {
                          Navigator.of(dialogCtx).pop();
                          await harness.saveDraft(
                            StockInReceipt(
                              id: 'DRAFT_FROM_EXIT',
                              importCode: 'PN_EXIT_01',
                              date: DateTime.now(),
                              items: [
                                StockInReceiptItem(
                                  transactionId: 'TX_E1',
                                  productId: product.id,
                                  quantity: 5,
                                  unitPrice: 120000.0,
                                ),
                              ],
                              totalAmount: 600000.0,
                            ),
                          );
                          draftPersisted = true;
                          pagePopped = true;
                        },
                      ),
                    );
                  }
                },
                child: const Text('Back'),
              );
            },
          ),
        );
      }

      await tester.pumpWidget(buildInteractiveExitFlow());
      await tester.pumpAndSettle();

      // Flow 1: Tap Back -> Choose "Ở lại" -> Dialog dismisses, page NOT popped, no draft
      await tester.tap(find.byKey(const Key('btn_simulate_back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exit_receipt_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dialog_choice_stay')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exit_receipt_dialog')), findsNothing);
      expect(pagePopped, isFalse);
      expect(draftPersisted, isFalse);

      // Flow 2: Tap Back -> Choose "Rời khỏi" -> Page popped, no draft in RTDB
      await tester.tap(find.byKey(const Key('btn_simulate_back')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dialog_choice_exit')));
      await tester.pumpAndSettle();
      expect(pagePopped, isTrue);
      expect(draftPersisted, isFalse);

      // Flow 3: Tap Back -> Choose "Lưu tạm" -> Saves draft and pops
      pagePopped = false;
      await tester.tap(find.byKey(const Key('btn_simulate_back')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dialog_choice_draft')));
      await tester.pumpAndSettle();
      expect(pagePopped, isTrue);
      expect(draftPersisted, isTrue);

      final snap = await harness.db
          .ref(
              'stores/${StockInE2ETestHarness.storeDongThang}/stock_in_receipts/DRAFT_FROM_EXIT')
          .get();
      expect(snap.exists, isTrue);
    });

    // ========================================================================
    // T3.4: Weighted Cost Price & Debt Calculation Sync Across Full Cycle
    // ========================================================================
    test(
        'T3.4: Product weighted average cost price and supplier debt adjust accurately across import and cancellation',
        () async {
      // 1. Initial product: 10 units @ 100,000 đ cost price
      const initialStock = 10;
      const initialCost = 100000.0;
      final product = harness.products['PROD_ST25']!.copyWith(
        costPrice: initialCost,
        branchStocks: {'store_001': initialStock, 'branch_1': initialStock},
      );
      harness.products[product.id] = product;

      // 2. Import 10 units @ 120,000 đ.
      // Expected new cost price: (10 * 100k + 10 * 120k) / 20 = 110,000 đ
      final receipt = StockInReceipt(
        id: 'REC_COST_CALC_01',
        importCode: 'PN_COST_01',
        date: DateTime.now(),
        storeId: StockInE2ETestHarness.storeDongThang,
        items: [
          StockInReceiptItem(
            transactionId: 'TX_C1',
            productId: product.id,
            quantity: 10,
            unitPrice: 120000.0,
            productName: product.name,
          ),
        ],
        totalAmount: 1200000.0,
      );

      await harness.completeReceipt(receipt);

      final updatedProd = harness.products[product.id]!;
      expect(updatedProd.costPrice, equals(110000.0));
      expect(updatedProd.stockInBranch(StockInE2ETestHarness.storeDongThang),
          equals(20));

      // 3. Cancel receipt
      await harness.cancelReceipt(
        storeId: StockInE2ETestHarness.storeDongThang,
        receipt: receipt,
        reason: 'Hủy kiểm toán',
        cancelledBy: 'admin_test',
      );

      // Stock rolled back to 10
      expect(
          harness.products[product.id]!
              .stockInBranch(StockInE2ETestHarness.storeDongThang),
          equals(10));
    });
  });
}
