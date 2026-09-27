import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_exit_dialog.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_payment_confirmation_view.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _TestSupplierListNotifier
    extends AutoDisposeAsyncNotifier<List<Supplier>>
    implements SupplierListNotifier {
  final List<Supplier> initialData;

  _TestSupplierListNotifier(this.initialData);

  @override
  Future<List<Supplier>> build() async => initialData;

  @override
  Future<void> refresh() async {
    state = AsyncData(initialData);
  }

  @override
  Future<void> upsertSupplier(Supplier supplier) async {}

  @override
  Future<void> deleteSupplier(String id) async {}

  @override
  Future<void> recordDebtPayment({
    required String supplierId,
    required double paymentAmount,
    String? referenceCode,
    String? note,
    String createdBy = 'Admin',
  }) async {}

  @override
  Future<void> recordDebtAdjustment({
    required String supplierId,
    required double newDebt,
    String? note,
    String createdBy = 'Admin',
  }) async {}

  @override
  Future<void> recordImportDebt({
    required String supplierId,
    required double totalAmount,
    required double paidAmount,
    String? importCode,
    String? note,
    String createdBy = 'Admin',
  }) async {}
}

class _MockStockInReceiptRepository implements StockInReceiptRepository {
  final List<StockInReceipt> savedDrafts = [];
  final List<StockInReceipt> completedReceipts = [];

  @override
  Future<String> saveDraft(StockInReceipt receipt) async {
    savedDrafts.add(receipt);
    return receipt.id;
  }

  @override
  Future<void> updateDraft(StockInReceipt receipt) async {
    final idx = savedDrafts.indexWhere((r) => r.id == receipt.id);
    if (idx >= 0) {
      savedDrafts[idx] = receipt;
    } else {
      savedDrafts.add(receipt);
    }
  }

  @override
  Future<void> deleteDraft({required String storeId, required String receiptId}) async {
    savedDrafts.removeWhere((r) => r.id == receiptId);
  }

  @override
  Future<void> cancelReceipt({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {}

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    completedReceipts.add(receipt);
  }

  @override
  Future<void> deleteReceipt({required String storeId, required String receiptId}) async {
    completedReceipts.removeWhere((r) => r.id == receiptId);
    savedDrafts.removeWhere((r) => r.id == receiptId);
  }

  @override
  Future<List<StockInReceipt>> fetchReceipts(String storeId) async {
    return [...savedDrafts, ...completedReceipts];
  }

  @override
  Future<StockInReceipt?> getReceiptById({required String storeId, required String receiptId}) async {
    return [...savedDrafts, ...completedReceipts].where((r) => r.id == receiptId).firstOrNull;
  }

  @override
  Stream<List<StockInReceipt>> watchReceipts(String storeId) {
    return Stream.value([...savedDrafts, ...completedReceipts]);
  }

  @override
  Future<double?> getLatestImportPrice({required String storeId, required String productId}) async {
    return 120000.0;
  }
}

Widget _buildHarness({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            key: const Key('btn_open_harness_page'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => child),
              );
            },
            child: const Text('Open Import Page'),
          ),
        ),
      ),
    ),
  );
}

class _MockCompleteStockInReceiptUseCase implements CompleteStockInReceiptUseCase {
  final List<StockInReceipt> executed = [];

  @override
  Future<StockInReceipt> execute(StockInReceipt receipt) async {
    final completed = receipt.copyWith(status: 'completed');
    executed.add(completed);
    return completed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const prod1 = Product(
    id: 'prod_01',
    name: 'Gạo ST25 Đặc Sản',
    code: 'ST25',
    price: 200000,
    costPrice: 150000,
    branchStocks: {'store_001': 10, 'store_002': 5},
    category: 'Gạo',
  );

  const prod2 = Product(
    id: 'prod_02',
    name: 'Nếp Cái Hoa Vàng',
    code: 'NEP_CHV',
    price: 45000,
    costPrice: 35000,
    branchStocks: {'store_001': 20, 'store_002': 15},
    category: 'Nếp',
  );

  const supplier = Supplier(
    id: 'sup_01',
    name: 'Công ty Cổ phần Nông nghiệp Ánh Dương',
    code: 'NCC_AD',
    phone: '0901234567',
    currentDebt: 5000000.0,
  );

  final sampleDraft = StockInReceipt(
    id: 'REC_DRAFT_STRESS',
    importCode: 'PN_DRAFT_STRESS',
    date: DateTime(2026, 9, 27),
    storeId: 'store_001',
    supplierId: supplier.id,
    supplierName: supplier.name,
    supplierPhone: supplier.phone,
    note: 'Đơn hàng nhập gấp trước 12h',
    discount: 20000.0,
    paidAmount: 900000.0,
    paymentMethod: 'transfer',
    status: 'draft',
    items: const [
      StockInReceiptItem(
        transactionId: 'TX_01',
        productId: 'prod_01',
        quantity: 4,
        unitPrice: 150000.0,
        originalPrice: 150000.0,
        productName: 'Gạo ST25 Đặc Sản',
        productCode: 'ST25',
      ),
      StockInReceiptItem(
        transactionId: 'TX_02',
        productId: 'prod_02',
        quantity: 10,
        unitPrice: 35000.0,
        originalPrice: 35000.0,
        productName: 'Nếp Cái Hoa Vàng',
        productCode: 'NEP_CHV',
      ),
    ],
  );

  group('Challenger M3_2: Baseline Contract Verification Suite', () {
    late _MockStockInReceiptRepository mockRepo;
    late _MockCompleteStockInReceiptUseCase mockCompleteUseCase;

    setUp(() {
      mockRepo = _MockStockInReceiptRepository();
      mockCompleteUseCase = _MockCompleteStockInReceiptUseCase();
    });

    List<Override> commonOverrides() => [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          productListProvider.overrideWith((ref) => Stream.value([prod1, prod2])),
          supplierListNotifierProvider.overrideWith(() => _TestSupplierListNotifier([supplier])),
          availableStoresProvider.overrideWith((ref) async => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
              }),
          stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          completeStockInReceiptUseCaseProvider.overrideWithValue(mockCompleteUseCase),
        ];

    // =========================================================================
    // 1. PopScope on empty cart (exits directly)
    // =========================================================================
    testWidgets('PopScope on empty cart: exits directly via Close (X) button without dialog', (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          child: const ImportInventoryPage(),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Open page
      await tester.tap(find.byKey(const Key('btn_open_harness_page')));
      await tester.pumpAndSettle();
      expect(find.byType(ImportInventoryPage), findsOneWidget);

      // Tap Close (X) button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Should exit directly
      expect(find.byType(StockInExitDialog), findsNothing);
      expect(find.byType(ImportInventoryPage), findsNothing);
      expect(find.byKey(const Key('btn_open_harness_page')), findsOneWidget);
      expect(mockRepo.savedDrafts, isEmpty);
    });

    testWidgets('PopScope on empty cart: exits directly via system back route without dialog', (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          child: const ImportInventoryPage(),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Open page
      await tester.tap(find.byKey(const Key('btn_open_harness_page')));
      await tester.pumpAndSettle();
      expect(find.byType(ImportInventoryPage), findsOneWidget);

      // Simulate system back button
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Should exit directly
      expect(find.byType(StockInExitDialog), findsNothing);
      expect(find.byType(ImportInventoryPage), findsNothing);
      expect(find.byKey(const Key('btn_open_harness_page')), findsOneWidget);
      expect(mockRepo.savedDrafts, isEmpty);
    });

    // =========================================================================
    // 2. PopScope on non-empty cart
    // =========================================================================
    testWidgets('PopScope on non-empty cart: "Lưu tạm" saves draft to RTDB with status "draft" and exits', (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_open_harness_page')));
      await tester.pumpAndSettle();
      expect(find.byType(ImportInventoryPage), findsOneWidget);

      // Tap Close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Exit dialog must appear
      expect(find.byType(StockInExitDialog), findsOneWidget);

      // Select "Lưu tạm"
      await tester.tap(find.byKey(const Key('dialog_choice_draft')));
      await tester.pumpAndSettle();

      // Verifications:
      // 1. Saved draft exists in repository with status 'draft'
      expect(mockRepo.savedDrafts.length, 1);
      final saved = mockRepo.savedDrafts.first;
      expect(saved.status, 'draft');
      expect(saved.id, sampleDraft.id);
      expect(saved.items.length, 2);
      expect(saved.totalAmount, 950000.0);

      // 2. Page has exited
      expect(find.byType(StockInExitDialog), findsNothing);
      expect(find.byType(ImportInventoryPage), findsNothing);
      expect(find.byKey(const Key('btn_open_harness_page')), findsOneWidget);
    });

    testWidgets('PopScope on non-empty cart: "Rời khỏi" discards changes and exits without saving', (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_open_harness_page')));
      await tester.pumpAndSettle();
      expect(find.byType(ImportInventoryPage), findsOneWidget);

      // Tap Close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Exit dialog must appear
      expect(find.byType(StockInExitDialog), findsOneWidget);

      // Select "Rời khỏi"
      await tester.tap(find.byKey(const Key('dialog_choice_exit')));
      await tester.pumpAndSettle();

      // Verifications:
      // 1. Page has exited
      expect(find.byType(StockInExitDialog), findsNothing);
      expect(find.byType(ImportInventoryPage), findsNothing);
      expect(find.byKey(const Key('btn_open_harness_page')), findsOneWidget);

      // 2. NO draft saved
      expect(mockRepo.savedDrafts, isEmpty);
    });

    testWidgets('PopScope on non-empty cart: "Ở lại" closes dialog and remains on import page', (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_open_harness_page')));
      await tester.pumpAndSettle();
      expect(find.byType(ImportInventoryPage), findsOneWidget);

      // Tap Close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Exit dialog must appear
      expect(find.byType(StockInExitDialog), findsOneWidget);

      // Select "Ở lại"
      await tester.tap(find.byKey(const Key('dialog_choice_stay')));
      await tester.pumpAndSettle();

      // Verifications:
      // 1. Dialog closes
      expect(find.byType(StockInExitDialog), findsNothing);

      // 2. User remains on import page
      expect(find.byType(ImportInventoryPage), findsOneWidget);
      expect(find.text('Phiếu PN_DRAFT_STRESS'), findsOneWidget);
      expect(find.text('2 mặt hàng • Số lượng: 14'), findsOneWidget);

      // 3. NO draft saved
      expect(mockRepo.savedDrafts, isEmpty);
    });

    // =========================================================================
    // 3. Draft resumption: initialReceipt restores items, quantities, prices, supplier, note
    // =========================================================================
    testWidgets('Draft resumption: correctly restores all items, quantities, prices, supplier, and note', (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_open_harness_page')));
      await tester.pumpAndSettle();

      // 1. Title shows draft code
      expect(find.text('Phiếu PN_DRAFT_STRESS'), findsOneWidget);

      // 2. Supplier card in Step 1 displays supplier name
      expect(find.text('Công ty Cổ phần Nông nghiệp Ánh Dương'), findsOneWidget);

      // 3. Item 1 restored
      expect(find.text('Gạo ST25 Đặc Sản'), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // qty
      expect(find.text('600.000 đ'), findsWidgets); // 150k * 4

      // 4. Item 2 restored
      expect(find.text('Nếp Cái Hoa Vàng'), findsOneWidget);
      expect(find.text('10'), findsOneWidget); // qty
      expect(find.text('350.000 đ'), findsWidgets); // 35k * 10

      // 5. Aggregates in StickyBottomSummaryBar: 600k + 350k = 950k, 14 units
      expect(find.text('2 mặt hàng • Số lượng: 14'), findsOneWidget);
      expect(find.text('950.000 đ'), findsWidgets);

      // 6. Transition to Step 2 to verify financial lines, supplier, and note
      await tester.tap(find.byKey(const Key('btn_continue')));
      await tester.pumpAndSettle();

      expect(find.byType(StockInPaymentConfirmationView), findsOneWidget);

      // Supplier dropdown matches
      expect(find.text('Công ty Cổ phần Nông nghiệp Ánh Dương (NCC_AD)'), findsOneWidget);

      // Financials: Total = 950.000, Discount = 20.000, Net = 930.000, Paid = 900.000, Debt = 30.000
      expect(find.text('950.000 đ'), findsWidgets);
      expect(find.text('20.000'), findsOneWidget); // Discount controller
      expect(find.text('930.000 đ'), findsOneWidget); // Net payable
      expect(find.text('900.000'), findsOneWidget); // Paid amount controller
      expect(find.text('30.000 đ'), findsOneWidget); // Remaining debt

      // Note input restored
      expect(find.text('Đơn hàng nhập gấp trước 12h'), findsOneWidget);

      // Payment method restored ('transfer')
      final transferChip = tester.widget<ChoiceChip>(find.byKey(const Key('payment_transfer')));
      expect(transferChip.selected, isTrue);
    });

    // =========================================================================
    // 4. 2-step transition: "Tiếp tục" -> Step 2 -> "Xem hàng trong phiếu >" -> back to Step 1
    // =========================================================================
    testWidgets('2-step transition: "Tiếp tục" -> Step 2 -> "Xem hàng trong phiếu >" -> back to Step 1', (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_open_harness_page')));
      await tester.pumpAndSettle();

      // Step 1 initial state
      expect(find.byType(StockInPaymentConfirmationView), findsNothing);
      expect(find.text('Gạo ST25 Đặc Sản'), findsOneWidget);
      expect(find.text('Nếp Cái Hoa Vàng'), findsOneWidget);

      // 1. Tap "Tiếp tục" -> Step 2
      await tester.tap(find.byKey(const Key('btn_continue')));
      await tester.pumpAndSettle();

      expect(find.byType(StockInPaymentConfirmationView), findsOneWidget);
      expect(find.text('Thanh toán & Nhà cung cấp'), findsOneWidget);
      expect(find.text('Xem hàng trong phiếu (2 mặt hàng)'), findsOneWidget);

      // 2. Tap "Xem hàng trong phiếu >" -> Back to Step 1
      await tester.tap(find.byKey(const Key('btn_view_receipt_items')));
      await tester.pumpAndSettle();

      // Step 2 unmounted, Step 1 restored
      expect(find.byType(StockInPaymentConfirmationView), findsNothing);
      expect(find.text('Phiếu PN_DRAFT_STRESS'), findsOneWidget);
      expect(find.text('Gạo ST25 Đặc Sản'), findsOneWidget);
      expect(find.text('Nếp Cái Hoa Vàng'), findsOneWidget);
      expect(find.text('2 mặt hàng • Số lượng: 14'), findsOneWidget);
      expect(find.text('950.000 đ'), findsWidgets);

      // 3. Increment an item in Step 1 and re-enter Step 2
      await tester.tap(find.byKey(const Key('stepper_inc_prod_01')));
      await tester.pumpAndSettle();

      // Qty becomes 5, total becomes 150k*5 + 35k*10 = 750k + 350k = 1,100,000 đ
      expect(find.text('5'), findsOneWidget);
      expect(find.text('2 mặt hàng • Số lượng: 15'), findsOneWidget);
      expect(find.text('1.100.000 đ'), findsWidgets);

      // Tap "Tiếp tục" -> Step 2 with updated subtotal
      await tester.tap(find.byKey(const Key('btn_continue')));
      await tester.pumpAndSettle();

      expect(find.byType(StockInPaymentConfirmationView), findsOneWidget);
      expect(find.text('Xem hàng trong phiếu (2 mặt hàng)'), findsOneWidget);
      expect(find.text('1.100.000 đ'), findsWidgets);
    });

    // =========================================================================
    // 5. Stress Testing: Emptying cart via stepper/swipe transitions PopScope to direct exit
    // =========================================================================
    testWidgets('Emptying cart dynamically reverts PopScope from dialog to direct exit', (tester) async {
      final singleItemDraft = sampleDraft.copyWith(
        items: [sampleDraft.items.first.copyWith(quantity: 1)],
      );

      await tester.pumpWidget(
        _buildHarness(
          child: ImportInventoryPage(initialReceipt: singleItemDraft),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_open_harness_page')));
      await tester.pumpAndSettle();
      expect(find.text('1 mặt hàng • Số lượng: 1'), findsOneWidget);

      // Decrement stepper at qty=1 triggers delete confirmation
      await tester.tap(find.byKey(const Key('stepper_dec_prod_01')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_confirmation_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_confirm_delete')));
      await tester.pumpAndSettle();

      // Cart is now completely empty
      expect(find.text('Chưa có hàng trong phiếu'), findsOneWidget);
      expect(find.text('0 mặt hàng • Số lượng: 0'), findsOneWidget);

      // Now pop the route: PopScope must exit directly without exit dialog
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(StockInExitDialog), findsNothing);
      expect(find.byType(ImportInventoryPage), findsNothing);
      expect(find.byKey(const Key('btn_open_harness_page')), findsOneWidget);
    });

    // =========================================================================
    // 6. Step 2 "Hoàn thành" saves completed receipt and pops
    // =========================================================================
    testWidgets('Step 2 "Hoàn thành" executes atomic completion use case and exits page', (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_open_harness_page')));
      await tester.pumpAndSettle();

      // Go to Step 2
      await tester.tap(find.byKey(const Key('btn_continue')));
      await tester.pumpAndSettle();

      // Ensure button is visible before tapping
      await tester.ensureVisible(find.byKey(const Key('btn_payment_complete')));
      await tester.pumpAndSettle();

      // Tap "Hoàn thành"
      await tester.tap(find.byKey(const Key('btn_payment_complete')));
      await tester.pumpAndSettle();

      // Assert completed receipt is saved
      expect(mockCompleteUseCase.executed.length, 1);
      final completed = mockCompleteUseCase.executed.first;
      expect(completed.status, 'completed');
      expect(completed.supplierId, 'sup_01');
      expect(completed.discount, 20000.0);
      // Assert page exited
      expect(find.byType(ImportInventoryPage), findsNothing);
      expect(find.byKey(const Key('btn_open_harness_page')), findsOneWidget);
    });
  });

  group('Empirical Challenger Bug Reproduction Suite', () {
    late _MockStockInReceiptRepository mockRepo;
    late _MockCompleteStockInReceiptUseCase mockCompleteUseCase;

    setUp(() {
      mockRepo = _MockStockInReceiptRepository();
      mockCompleteUseCase = _MockCompleteStockInReceiptUseCase();
    });

    List<Override> commonOverrides() => [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
          productListProvider.overrideWith((ref) => Stream.value([prod1, prod2])),
          supplierListNotifierProvider.overrideWith(() => _TestSupplierListNotifier([supplier])),
          availableStoresProvider.overrideWith((ref) async => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
              }),
          stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          completeStockInReceiptUseCaseProvider.overrideWithValue(mockCompleteUseCase),
        ];

    // =========================================================================
    // VERIFIED FIX 1: State synchronization between Step 2 inputs and "Lưu tạm"
    // =========================================================================
    testWidgets('VERIFIED FIX 1: Tapping "Lưu tạm" in Step 2 preserves user edits in draft', (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_open_harness_page')));
      await tester.pumpAndSettle();

      // Navigate to Step 2
      await tester.tap(find.byKey(const Key('btn_continue')));
      await tester.pumpAndSettle();

      // Modify note in Step 2
      await tester.enterText(find.byKey(const Key('input_receipt_note')), 'Ghi chú cập nhật tại Step 2');
      await tester.pumpAndSettle();

      // Modify discount in Step 2 to 50,000
      await tester.enterText(find.byKey(const Key('input_receipt_discount')), '50000');
      await tester.pumpAndSettle();

      // Tap "Lưu tạm" on Step 2 AppBar
      await tester.tap(find.byKey(const Key('btn_payment_save_draft')));
      await tester.pumpAndSettle();

      expect(mockRepo.savedDrafts.isNotEmpty, isTrue);
      final lastSavedDraft = mockRepo.savedDrafts.last;

      // VERIFIED FIX:
      // Step 2 edits are synchronized to parent state and preserved in saved draft!
      expect(lastSavedDraft.note, equals('Ghi chú cập nhật tại Step 2'),
          reason: 'Draft saved from Step 2 preserves the updated note entered by user');
      expect(lastSavedDraft.discount, equals(50000.0),
          reason: 'Draft saved from Step 2 preserves the updated discount entered by user');
    });

    // =========================================================================
    // VERIFIED FIX 2: State persistence when navigating Step 2 -> Step 1 -> Step 2
    // =========================================================================
    testWidgets('VERIFIED FIX 2: Navigating Step 2 -> Step 1 ("Xem hàng trong phiếu") -> Step 2 preserves user edits', (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_open_harness_page')));
      await tester.pumpAndSettle();

      // Navigate to Step 2
      await tester.tap(find.byKey(const Key('btn_continue')));
      await tester.pumpAndSettle();

      // Modify note in Step 2
      await tester.enterText(find.byKey(const Key('input_receipt_note')), 'Ghi chú quan trọng giữ nguyên');
      await tester.pumpAndSettle();

      // Modify discount in Step 2
      await tester.enterText(find.byKey(const Key('input_receipt_discount')), '50000');
      await tester.pumpAndSettle();

      // Tap "Xem hàng trong phiếu >" to go back to Step 1
      await tester.ensureVisible(find.byKey(const Key('btn_view_receipt_items')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_view_receipt_items')));
      await tester.pumpAndSettle();

      expect(find.byType(StockInPaymentConfirmationView), findsNothing);

      // Return to Step 2 via "Tiếp tục"
      await tester.tap(find.byKey(const Key('btn_continue')));
      await tester.pumpAndSettle();

      expect(find.byType(StockInPaymentConfirmationView), findsOneWidget);

      // VERIFIED FIX:
      // The user's entered note is preserved across Step 1 and Step 2 navigation
      expect(find.text('Ghi chú quan trọng giữ nguyên'), findsOneWidget,
          reason: 'User note was preserved upon returning from Step 1 to Step 2');
    });

    // =========================================================================
    // VERIFIED FIX 3: Draft resumption with paidAmount: 0 (100% debt) preserved
    // =========================================================================
    testWidgets('VERIFIED FIX 3: Draft resumption with paidAmount: 0.0 preserves 0 debt and does not force full payment', (tester) async {
      final zeroPaidDraft = sampleDraft.copyWith(
        paidAmount: 0.0,
      );

      await tester.pumpWidget(
        _buildHarness(
          child: ImportInventoryPage(initialReceipt: zeroPaidDraft),
          overrides: commonOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_open_harness_page')));
      await tester.pumpAndSettle();

      // Navigate to Step 2
      await tester.tap(find.byKey(const Key('btn_continue')));
      await tester.pumpAndSettle();

      // VERIFIED FIX:
      // A draft saved with paidAmount: 0 (buying on 100% credit) preserves paidAmount: 0.
      final paidField = tester.widget<TextFormField>(find.byKey(const Key('input_paid_amount')));
      expect(paidField.controller?.text, equals('0'),
          reason: 'paidAmount 0.0 is properly preserved when resuming a draft');
    });
  });
}
