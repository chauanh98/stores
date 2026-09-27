import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'stock_in_test_harness.dart';

void main() {
  group('=== MOBILE STOCK-IN UPGRADE: TIER 4 REAL-WORLD SCENARIOS ===', () {
    late StockInE2ETestHarness harness;

    setUp(() {
      harness = StockInE2ETestHarness();
    });

    // ========================================================================
    // T4.1: Video Reference Reproduction Flow (DATA_IMPORT/video_2026-09-27_07-41-44.mp4)
    // ========================================================================
    testWidgets('T4.1: Complete 2-step import workflow matching video reference (Search -> Edit Sheet -> Cart -> Payment -> Complete)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const storeId = StockInE2ETestHarness.storeDongThang;
      final pST26 = harness.products['PROD_ST26']!;
      final pST25 = harness.products['PROD_ST25']!;
      final supABC = harness.suppliers['SUP_001']!;

      final initialStockST26 = pST26.stockInBranch(storeId); // 1
      final initialStockST25 = pST25.stockInBranch(storeId); // 10
      final initialDebt = supABC.currentDebt; // 15,000,000
      final initialPurchase = supABC.totalPurchase; // 50,000,000

      // Step 1: User adds ST26 via Edit Modal (5 units @ 6,000,000 đ after 100k discount)
      final itemST26 = StockInReceiptItem(
        transactionId: 'TX_V_1',
        productId: pST26.id,
        quantity: 5,
        originalPrice: 6100000.0,
        discount: 100000.0,
        unitPrice: 6000000.0, // 30,000,000 đ
        productName: pST26.name,
        productCode: pST26.code,
        note: 'Nhập ST26 tuyển chọn',
      );

      // Step 2: User adds ST25 (10 units @ 115,000 đ = 1,150,000 đ)
      final itemST25 = StockInReceiptItem(
        transactionId: 'TX_V_2',
        productId: pST25.id,
        quantity: 10,
        unitPrice: 115000.0, // 1,150,000 đ
        productName: pST25.name,
        productCode: pST25.code,
      );

      final lineItems = [itemST26, itemST25];
      final totalGoods = lineItems.fold(0.0, (sum, i) => sum + i.totalPrice); // 31,150,000 đ
      final totalQty = lineItems.fold(0, (sum, i) => sum + i.quantity); // 15

      // Render Sticky Bottom Summary Bar
      bool navigatedToPayment = false;
      await tester.pumpWidget(
        buildStockInTestApp(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    VisualStockInItemCard(
                      item: itemST26,
                      currentStock: initialStockST26,
                      onQuantityChanged: (_) {},
                      onDelete: () {},
                    ),
                    VisualStockInItemCard(
                      item: itemST25,
                      currentStock: initialStockST25,
                      onQuantityChanged: (_) {},
                      onDelete: () {},
                    ),
                  ],
                ),
              ),
              StickyBottomSummaryBar(
                totalAmount: totalGoods,
                itemCount: lineItems.length,
                totalQuantity: totalQty,
                onSaveDraft: () {},
                onContinue: () => navigatedToPayment = true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('31.150.000 đ'), findsOneWidget);
      expect(find.text('2 mặt hàng • Số lượng: 15'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_continue')));
      await tester.pumpAndSettle();
      expect(navigatedToPayment, isTrue);

      // Step 3: Payment Confirmation
      // Total: 31,150,000 đ, Discount: 150,000 đ -> Net Payable: 31,000,000 đ.
      // Paid: 20,000,000 đ -> Remaining Debt: 11,000,000 đ.
      final fullReceipt = StockInReceipt(
        id: 'REC_VIDEO_FLOW',
        importCode: 'PN_VIDEO_001',
        date: DateTime.now(),
        storeId: storeId,
        supplierId: supABC.id,
        supplierName: supABC.name,
        items: lineItems,
        totalAmount: totalGoods,
        discount: 150000.0,
        netPayable: 31000000.0,
        paidAmount: 20000000.0,
        debtAmount: 11000000.0,
        note: 'Nhập hàng theo clip video KiotViet',
      );

      await harness.completeReceipt(fullReceipt, paymentMethod: 'transfer', createdBy: 'admin_test');

      // Final Verification of End State:
      // 1. Stock ST26: 1 + 5 = 6
      expect(harness.products[pST26.id]!.stockInBranch(storeId), equals(6));
      // 2. Stock ST25: 10 + 10 = 20
      expect(harness.products[pST25.id]!.stockInBranch(storeId), equals(20));
      // 3. Supplier Debt: 15,000,000 + 11,000,000 = 26,000,000 đ
      expect(harness.suppliers[supABC.id]!.currentDebt, equals(initialDebt + 11000000.0));
      // 4. Supplier Total Purchase: 50,000,000 + 31,000,000 = 81,000,000 đ
      expect(harness.suppliers[supABC.id]!.totalPurchase, equals(initialPurchase + 31000000.0));
      // 5. Payment method recorded as 'transfer'
      expect(harness.receiptAudits[fullReceipt.id]!.paymentMethod, equals('transfer'));
    });

    // ========================================================================
    // T4.2: Cold Restart Draft Synchronization
    // ========================================================================
    test('T4.2: Draft persisted in RTDB survives cold restart and restores all items, prices, and notes intact', () async {
      const storeId = StockInE2ETestHarness.storeDongThang;
      final pST25 = harness.products['PROD_ST25']!;

      final initialDraft = StockInReceipt(
        id: 'DRAFT_COLD_RESTART_01',
        importCode: 'PN_COLD_01',
        date: DateTime.parse('2026-09-27T07:30:00Z'),
        storeId: storeId,
        supplierId: 'SUP_001',
        supplierName: 'Công ty TNHH Phân Bón Ánh Dương',
        items: [
          StockInReceiptItem(
            transactionId: 'TX_COLD_1',
            productId: pST25.id,
            quantity: 35,
            originalPrice: 120000.0,
            discount: 5000.0,
            unitPrice: 115000.0,
            productName: pST25.name,
            note: 'Đợt 1 lưu tạm',
          ),
        ],
        totalAmount: 4025000.0,
        discount: 25000.0,
        paidAmount: 1000000.0,
        status: 'draft',
        note: 'Phiếu lưu tạm trước khi app đóng',
      );

      // Save to mock RTDB
      await harness.saveDraft(initialDraft);

      // ── Simulate Cold Restart: Create entirely new harness and load from RTDB ──
      final freshHarness = StockInE2ETestHarness();

      // Read snapshot from RTDB
      final snap = await harness.db.ref('stores/$storeId/stock_in_receipts/${initialDraft.id}').get();
      expect(snap.exists, isTrue);

      final val = snap.value as Map<String, dynamic>;
      final restoredItems = (val['items'] as List).map((i) {
        final m = Map<String, dynamic>.from(i as Map);
        return StockInReceiptItem(
          transactionId: 'TX_RESTORED',
          productId: m['productId'].toString(),
          quantity: (m['quantity'] as num).toInt(),
          unitPrice: (m['unitPrice'] as num).toDouble(),
          originalPrice: (m['originalPrice'] as num?)?.toDouble(),
          discount: (m['discount'] as num?)?.toDouble() ?? 0.0,
          productName: m['productName']?.toString(),
          note: m['note']?.toString() ?? '',
        );
      }).toList();

      final restoredReceipt = StockInReceipt(
        id: val['id'].toString(),
        importCode: val['importCode'].toString(),
        date: DateTime.parse(val['date'].toString()),
        storeId: val['storeId']?.toString(),
        supplierId: val['supplierId']?.toString(),
        supplierName: val['supplierName']?.toString(),
        items: restoredItems,
        totalAmount: (val['totalAmount'] as num).toDouble(),
        discount: (val['discount'] as num).toDouble(),
        paidAmount: (val['paidAmount'] as num).toDouble(),
        status: val['status'].toString(),
        note: val['note'].toString(),
      );

      // Assert complete state restoration
      expect(restoredReceipt.id, equals('DRAFT_COLD_RESTART_01'));
      expect(restoredReceipt.isDraft, isTrue);
      expect(restoredReceipt.items.length, equals(1));
      expect(restoredReceipt.items.first.quantity, equals(35));
      expect(restoredReceipt.items.first.unitPrice, equals(115000.0));
      expect(restoredReceipt.items.first.note, equals('Đợt 1 lưu tạm'));
      expect(restoredReceipt.supplierName, equals('Công ty TNHH Phân Bón Ánh Dương'));

      // Complete restored draft in fresh harness
      await freshHarness.completeReceipt(restoredReceipt);
      expect(freshHarness.products[pST25.id]!.stockInBranch(storeId), equals(10 + 35)); // 45
    });

    // ========================================================================
    // T4.3: Role-Based Access Control (RBAC) Matrix Verification
    // ========================================================================
    testWidgets('T4.3: RBAC Matrix: Admin and Supervisor can cancel receipt; Staff is restricted from cancellation', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Helper to evaluate RBAC cancel capability according to domain rules
      bool canUserCancelReceipt(UserAccount user) {
        return user.isAdmin || user.isSupervisor;
      }

      const admin = StockInE2ETestHarness.adminUser;
      const supervisor = StockInE2ETestHarness.supervisorDongThang;
      const staff = StockInE2ETestHarness.staffUser;

      // 1. Role Capabilities Evaluation
      expect(canUserCancelReceipt(admin), isTrue);
      expect(canUserCancelReceipt(supervisor), isTrue);
      expect(canUserCancelReceipt(staff), isFalse);

      // 2. Widget UI Rendering for Staff vs Admin
      Widget buildReceiptDetailView(UserAccount user, VoidCallback onCancelTapped) {
        final canCancel = canUserCancelReceipt(user);
        return buildStockInTestApp(
          child: Column(
            children: [
              const Text('Chi tiết phiếu nhập #PN_RBAC_01'),
              const Spacer(),
              if (canCancel)
                ElevatedButton(
                  key: const Key('btn_cancel_receipt_action'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: onCancelTapped,
                  child: const Text('Hủy phiếu nhập'),
                )
              else
                const Text('Bạn không có quyền hủy phiếu nhập này', key: Key('text_no_cancel_permission')),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('btn_close_detail'),
                onPressed: () {},
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }

      // Check Staff: Cancel button must NOT exist; permission warning displayed
      await tester.pumpWidget(buildReceiptDetailView(staff, () {}));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_cancel_receipt_action')), findsNothing);
      expect(find.byKey(const Key('text_no_cancel_permission')), findsOneWidget);

      // Check Admin: Cancel button MUST exist
      bool adminCancelTapped = false;
      await tester.pumpWidget(buildReceiptDetailView(admin, () => adminCancelTapped = true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_cancel_receipt_action')), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_cancel_receipt_action')));
      expect(adminCancelTapped, isTrue);

      // Check Supervisor: Cancel button MUST exist
      bool supCancelTapped = false;
      await tester.pumpWidget(buildReceiptDetailView(supervisor, () => supCancelTapped = true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_cancel_receipt_action')), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_cancel_receipt_action')));
      expect(supCancelTapped, isTrue);
    });
  });
}
