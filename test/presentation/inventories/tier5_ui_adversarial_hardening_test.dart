import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/pages/stock_in_receipts_page.dart';
import 'package:stores/presentation/inventories/widgets/accounting_numpad.dart';
import 'package:stores/presentation/inventories/widgets/cancel_stock_in_receipt_dialog.dart';
import 'package:stores/presentation/inventories/widgets/sticky_bottom_summary_bar.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_exit_dialog.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_item_card.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_payment_confirmation_view.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_product_edit_sheet.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_receipt_detail_bottom_sheet.dart';

// ============================================================================
// TEST HARNESS & MOCK DEFINITIONS
// ============================================================================

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
  final List<Map<String, dynamic>> cancelledCalls = [];

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
  Future<void> deleteDraft({
    required String storeId,
    required String receiptId,
  }) async {
    savedDrafts.removeWhere((r) => r.id == receiptId);
  }

  @override
  Future<void> cancelReceipt({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {
    cancelledCalls.add({
      'storeId': storeId,
      'receipt': receipt,
      'reason': reason,
      'cancelledBy': cancelledBy,
    });
  }

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    completedReceipts.add(receipt);
  }

  @override
  Future<void> deleteReceipt({
    required String storeId,
    required String receiptId,
  }) async {
    completedReceipts.removeWhere((r) => r.id == receiptId);
    savedDrafts.removeWhere((r) => r.id == receiptId);
  }

  @override
  Future<List<StockInReceipt>> fetchReceipts(String storeId) async {
    return [...savedDrafts, ...completedReceipts];
  }

  @override
  Future<StockInReceipt?> getReceiptById({
    required String storeId,
    required String receiptId,
  }) async {
    return [...savedDrafts, ...completedReceipts]
        .where((r) => r.id == receiptId)
        .firstOrNull;
  }

  @override
  Stream<List<StockInReceipt>> watchReceipts(String storeId) {
    return Stream.value([...savedDrafts, ...completedReceipts]);
  }

  @override
  Future<double?> getLatestImportPrice({
    required String storeId,
    required String productId,
  }) async {
    return 150000.0;
  }
}

class _MockCancelStockInReceiptUseCase implements CancelStockInReceiptUseCase {
  int executeCallCount = 0;
  final Duration delay;

  _MockCancelStockInReceiptUseCase({this.delay = Duration.zero});

  @override
  Future<void> execute({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {
    executeCallCount++;
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockSaveStockInDraftUseCase implements SaveStockInDraftUseCase {
  int executeCallCount = 0;
  final List<StockInReceipt> saved = [];

  @override
  Future<String> execute(StockInReceipt receipt) async {
    executeCallCount++;
    saved.add(receipt);
    return receipt.id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockCompleteStockInReceiptUseCase
    implements CompleteStockInReceiptUseCase {
  int executeCallCount = 0;
  final List<StockInReceipt> executed = [];

  @override
  Future<StockInReceipt> execute(StockInReceipt receipt) async {
    executeCallCount++;
    final completed = receipt.copyWith(status: 'completed');
    executed.add(completed);
    return completed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildHarness({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: child,
    ),
  );
}

Widget _buildNavHarness({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('btn_open_harness_page'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => child),
                );
              },
              child: const Text('Open Page'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const sampleSupplier = Supplier(
    id: 'sup_001',
    name: 'Tổng Công Ty Dược Liệu Quốc Gia Việt Nam Chi Nhánh Cà Mau',
    code: 'DUOC_TW3',
    phone: '02838383838',
    currentDebt: 5000000.0,
  );

  const sampleProduct1 = Product(
    id: 'prod_001',
    name: 'Thuốc Kháng Sinh Amoxicillin Trihydrate 500mg Hộp 100 Viên Chuẩn GMP',
    code: 'SKU-AMOX-500MG-VN-2026-LONG',
    price: 220000,
    costPrice: 150000,
    branchStocks: {'store_001': 25, 'store_002': 10},
    category: 'Kháng sinh',
    unit: 'Hộp',
  );

  const sampleProduct2 = Product(
    id: 'prod_002',
    name: 'Paracetamol 500mg Hộp 20 Vỉ',
    code: 'PARA-500',
    price: 65000,
    costPrice: 45000,
    branchStocks: {'store_001': 50, 'store_002': 30},
    category: 'Giảm đau',
    unit: 'Hộp',
  );

  final sampleItem1 = StockInReceiptItem(
    transactionId: 'TX_001',
    productId: sampleProduct1.id,
    productName: sampleProduct1.name,
    productCode: sampleProduct1.code,
    quantity: 2,
    unitPrice: 150000,
    originalPrice: 150000,
    discount: 0,
    unit: 'Hộp',
  );

  final sampleItem2 = StockInReceiptItem(
    transactionId: 'TX_002',
    productId: sampleProduct2.id,
    productName: sampleProduct2.name,
    productCode: sampleProduct2.code,
    quantity: 5,
    unitPrice: 45000,
    originalPrice: 45000,
    discount: 0,
    unit: 'Hộp',
  );

  final completedReceipt = StockInReceipt(
    id: 'rec_completed_001',
    importCode: 'PN_20260927_001',
    date: DateTime(2026, 9, 27, 9, 30),
    storeId: 'store_001',
    supplierId: sampleSupplier.id,
    supplierName: sampleSupplier.name,
    supplierPhone: sampleSupplier.phone,
    createdBy: adminUser.username,
    createdByName: adminUser.displayName,
    items: [sampleItem1, sampleItem2],
    discount: 25000,
    paidAmount: 300000,
    status: 'completed',
    paymentMethod: 'cash',
    note: 'Nhập kho chi nhánh sáng 27/09',
    createdAt: DateTime(2026, 9, 27, 9, 30),
    updatedAt: DateTime(2026, 9, 27, 9, 30),
  );

  // ============================================================================
  // SUITE 1: NARROW VIEWPORTS & ZERO RENDERFLEX OVERFLOW HARDENING
  // ============================================================================
  group('Suite 1: Narrow Viewports & Zero RenderFlex Overflow Hardening', () {
    testWidgets(
      '1.1 StickyBottomSummaryBar on 320px & 280px with billions amount: ZERO overflow',
      (tester) async {
        // Test on 320x568 (iPhone SE 1st gen)
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        bool draftPressed = false;
        bool continuePressed = false;

        await tester.pumpWidget(
          _buildHarness(
            child: Scaffold(
              bottomNavigationBar: StickyBottomSummaryBar(
                totalAmount: 999999999999.0, // Billions VND
                itemCount: 999,
                totalQuantity: 99999,
                onSaveDraft: () => draftPressed = true,
                onContinue: () => continuePressed = true,
                isEnabled: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('sticky_bottom_summary_bar')), findsOneWidget);
        expect(find.byKey(const Key('btn_save_draft')), findsOneWidget);
        expect(find.byKey(const Key('btn_continue')), findsOneWidget);

        // Tap buttons to ensure they remain fully interactive
        await tester.tap(find.byKey(const Key('btn_save_draft')));
        await tester.pumpAndSettle();
        expect(draftPressed, isTrue);

        await tester.tap(find.byKey(const Key('btn_continue')));
        await tester.pumpAndSettle();
        expect(continuePressed, isTrue);

        // Stress further with ultra-narrow viewport: 280px width
        tester.view.physicalSize = const Size(280, 500);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '1.2 StockInItemCard on 320px with long product name, SKU & 100M VND: ZERO overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const extremeItem = StockInReceiptItem(
          transactionId: 'TX_EXTREME',
          productId: 'prod_extreme',
          productName:
              'Thuốc Đặc Trị Kháng Sinh Phổ Rộng Hộp 100 Vỉ 10 Viên Chuẩn Dược Điển Châu Âu EU-GMP',
          productCode: 'SKU-EXTRA-LONG-CODE-2026-SPECIAL-EDITION',
          quantity: 9999,
          unitPrice: 150000000.0,
          originalPrice: 150000000.0,
          discount: 0,
        );

        int updatedQty = 0;
        await tester.pumpWidget(
          _buildHarness(
            child: Scaffold(
              body: ListView(
                children: [
                  StockInItemCard(
                    item: extremeItem,
                    currentStock: 99999,
                    onQuantityChanged: (q) => updatedQty = q,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final element in find.byType(Row).evaluate()) {
          final ro = element.renderObject;
          if (ro is RenderFlex && ro.toString().contains('OVERFLOWING')) {
            // ignore: avoid_print
            print('OVERFLOWING ROW: ${ro.debugCreator}');
          }
        }
        for (final element in find.byType(Column).evaluate()) {
          final ro = element.renderObject;
          if (ro is RenderFlex && ro.toString().contains('OVERFLOWING')) {
            // ignore: avoid_print
            print('OVERFLOWING COLUMN: ${ro.debugCreator}');
          }
        }
        final exception = tester.takeException();
        expect(exception, isNull);
        expect(find.byKey(Key('item_card_${extremeItem.productId}')), findsOneWidget);
        expect(find.byKey(Key('stepper_inc_${extremeItem.productId}')), findsOneWidget);

        await tester.tap(find.byKey(Key('stepper_inc_${extremeItem.productId}')));
        await tester.pumpAndSettle();
        expect(updatedQty, 10000);
      },
    );

    testWidgets(
      '1.3 AccountingNumpad on 320px & 280px: ZERO overflow across all keys',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final List<String> tappedKeys = [];
        await tester.pumpWidget(
          _buildHarness(
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: AccountingNumpad(
                  onDigit: (k) => tappedKeys.add(k),
                  onDelete: () => tappedKeys.add('del'),
                  onClear: () => tappedKeys.add('clr'),
                  onDone: () => tappedKeys.add('done'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('accounting_numpad')), findsOneWidget);

        // Tap numpad keys on narrow screen
        await tester.tap(find.byKey(const Key('numpad_1')));
        await tester.tap(find.byKey(const Key('numpad_000')));
        await tester.tap(find.byKey(const Key('numpad_backspace')));
        await tester.tap(find.byKey(const Key('numpad_clear')));
        await tester.tap(find.byKey(const Key('numpad_enter')));
        await tester.pumpAndSettle();

        expect(tappedKeys, ['1', '000', 'del', 'clr', 'done']);

        // Ultra-narrow viewport: 280px
        tester.view.physicalSize = const Size(280, 500);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '1.4 StockInProductEditSheet on 320px: ZERO overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockRepo = _MockStockInReceiptRepository();

        await tester.pumpWidget(
          _buildHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
            ],
            child: const Scaffold(
              body: StockInProductEditSheet(
                product: sampleProduct1,
                branchStock: 5000,
                storeId: 'store_001',
                preFilledPrice: 85000000.0,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final exception = tester.takeException();
        expect(exception, isNull);
        expect(find.byKey(const Key('product_edit_sheet')), findsOneWidget);
        expect(find.byKey(const Key('btn_sheet_done')), findsOneWidget);
        expect(find.byKey(const Key('accounting_numpad')), findsOneWidget);
      },
    );

    testWidgets(
      '1.5 StockInPaymentConfirmationView on 320px with long supplier: ZERO overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildHarness(
            child: StockInPaymentConfirmationView(
              receipt: completedReceipt,
              suppliers: const [sampleSupplier],
              onComplete: ({
                required supplierId,
                required discount,
                required paidAmount,
                required paymentMethod,
                required note,
              }) {},
              onSaveDraft: () {},
              onViewItems: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('btn_payment_complete')), findsOneWidget);
        expect(find.byKey(const Key('btn_payment_save_draft')), findsOneWidget);
        expect(find.byKey(const Key('text_net_payable')), findsOneWidget);
      },
    );

    testWidgets(
      '1.6 StockInExitDialog & CancelStockInReceiptDialog on 320px: ZERO overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Test StockInExitDialog
        await tester.pumpWidget(
          _buildHarness(
            child: const Scaffold(
              body: StockInExitDialog(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('exit_receipt_dialog')), findsOneWidget);
        expect(find.byKey(const Key('dialog_choice_stay')), findsOneWidget);
        expect(find.byKey(const Key('dialog_choice_exit')), findsOneWidget);
        expect(find.byKey(const Key('dialog_choice_draft')), findsOneWidget);

        // Test CancelStockInReceiptDialog
        await tester.pumpWidget(
          _buildHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            ],
            child: Scaffold(
              body: CancelStockInReceiptDialog(
                receipt: completedReceipt,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('cancel_receipt_dialog')), findsOneWidget);
        expect(find.byKey(const Key('btn_cancel_dialog_close')), findsOneWidget);
        expect(find.byKey(const Key('btn_confirm_cancel')), findsOneWidget);
      },
    );

    testWidgets(
      '1.7 StockInReceiptDetailBottomSheet on 320px: ZERO overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              canViewCostPriceProvider.overrideWith((ref) => true),
              supplierListNotifierProvider.overrideWith(
                () => _TestSupplierListNotifier([sampleSupplier]),
              ),
            ],
            child: Scaffold(
              body: StockInReceiptDetailBottomSheet(
                receipt: completedReceipt,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('btn_cancel_receipt')), findsOneWidget);
        expect(find.byKey(const Key('btn_close_detail')), findsOneWidget);
      },
    );

    testWidgets(
      '1.8 Full StockInReceiptsPage on 320px: ZERO overflow across filter chips & list',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                    'store_002': 'Chi nhánh Thới Bình',
                  }),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              productListProvider.overrideWith(
                (ref) => Stream.value([sampleProduct1, sampleProduct2]),
              ),
              rawImportTransactionsStreamProvider
                  .overrideWith((ref) => Stream.value(<InventoryTransaction>[])),
              allSupplierDebtTransactionsProvider.overrideWith(
                  (ref) => Stream.value(<SupplierDebtTransaction>[])),
              supplierListNotifierProvider.overrideWith(
                () => _TestSupplierListNotifier([sampleSupplier]),
              ),
              filteredStockInReceiptsAsyncProvider.overrideWith(
                (ref) => AsyncValue.data([completedReceipt]),
              ),
            ],
            child: const StockInReceiptsPage(),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('filter_all')), findsOneWidget);
        expect(find.byKey(const Key('filter_completed')), findsOneWidget);
        expect(find.byKey(const Key('filter_draft')), findsOneWidget);
        expect(find.byKey(const Key('filter_cancelled')), findsOneWidget);
      },
    );
  });

  // ============================================================================
  // SUITE 2: RAPID MULTI-TAP & CONCURRENCY SAFETY (DEBOUNCE & LOADING GUARDS)
  // ============================================================================
  group('Suite 2: Rapid Multi-Tap & Concurrency Safety', () {
    testWidgets(
      '2.1 StockInProductEditSheet: 5 rapid taps on "Xong" invokes callback ONCE without double-pop crash',
      (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int doneCount = 0;
        int itemUpdatedCount = 0;

        await tester.pumpWidget(
          _buildNavHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            ],
            child: Builder(
              builder: (ctx) => ElevatedButton(
                key: const Key('btn_open_edit_sheet'),
                onPressed: () {
                  StockInProductEditSheet.show(
                    context: ctx,
                    product: sampleProduct2,
                    branchStock: 10,
                    preFilledPrice: 150000,
                    onDone: (qty, price, discount, note) => doneCount++,
                    onItemUpdated: (item) => itemUpdatedCount++,
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_open_harness_page')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_open_edit_sheet')));
        await tester.pumpAndSettle();

        final doneBtn = find.byKey(const Key('btn_sheet_done'));
        await tester.tap(doneBtn);
        await tester.tap(doneBtn, warnIfMissed: false);
        await tester.tap(doneBtn, warnIfMissed: false);
        await tester.tap(doneBtn, warnIfMissed: false);
        await tester.tap(doneBtn, warnIfMissed: false);

        await tester.pumpAndSettle();

        expect(doneCount, 1);
        expect(itemUpdatedCount, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '2.2 StockInProductEditSheet: 5 rapid taps on Numpad "Nhập" submits ONCE',
      (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int doneCount = 0;

        await tester.pumpWidget(
          _buildNavHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            ],
            child: Builder(
              builder: (ctx) => ElevatedButton(
                key: const Key('btn_open_edit_sheet'),
                onPressed: () {
                  StockInProductEditSheet.show(
                    context: ctx,
                    product: sampleProduct2,
                    branchStock: 10,
                    preFilledPrice: 150000,
                    onDone: (qty, price, discount, note) => doneCount++,
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_open_harness_page')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_open_edit_sheet')));
        await tester.pumpAndSettle();

        final enterBtn = find.byKey(const Key('numpad_enter'));
        await tester.tap(enterBtn);
        await tester.tap(enterBtn, warnIfMissed: false);
        await tester.tap(enterBtn, warnIfMissed: false);
        await tester.tap(enterBtn, warnIfMissed: false);
        await tester.tap(enterBtn, warnIfMissed: false);

        await tester.pumpAndSettle();

        expect(doneCount, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '2.3 ImportInventoryPage: Rapid tapping "Lưu tạm" in StickyBottomSummaryBar safely saves draft',
      (tester) async {
        final mockSaveDraftUseCase = _MockSaveStockInDraftUseCase();

        await tester.pumpWidget(
          _buildHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                  }),
              productListProvider.overrideWith((ref) => Stream.value([sampleProduct1])),
              supplierListNotifierProvider.overrideWith(
                () => _TestSupplierListNotifier([sampleSupplier]),
              ),
              saveStockInDraftUseCaseProvider
                  .overrideWithValue(mockSaveDraftUseCase),
            ],
            child: ImportInventoryPage(
              initialReceipt: StockInReceipt(
                id: 'draft_rapid',
                importCode: 'PN_RAPID',
                date: DateTime.now(),
                storeId: 'store_001',
                items: [sampleItem1],
                status: 'draft',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final draftBtn = find.byKey(const Key('btn_save_draft'));
        await tester.tap(draftBtn);
        await tester.tap(draftBtn, warnIfMissed: false);
        await tester.tap(draftBtn, warnIfMissed: false);

        await tester.pumpAndSettle();

        expect(mockSaveDraftUseCase.executeCallCount, greaterThanOrEqualTo(1));
        expect(tester.takeException(), isNull);
        expect(find.text('Đã lưu phiếu tạm'), findsOneWidget);
      },
    );

    testWidgets(
      '2.4 StockInPaymentConfirmationView: 5 rapid taps on "Hoàn thành" executes safely',
      (tester) async {
        int completeCount = 0;

        await tester.pumpWidget(
          _buildHarness(
            child: StockInPaymentConfirmationView(
              receipt: completedReceipt,
              suppliers: const [sampleSupplier],
              onComplete: ({
                required supplierId,
                required discount,
                required paidAmount,
                required paymentMethod,
                required note,
              }) {
                completeCount++;
              },
              onSaveDraft: () {},
              onViewItems: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final completeBtn = find.byKey(const Key('btn_payment_complete'));
        await tester.ensureVisible(completeBtn);
        await tester.pumpAndSettle();
        await tester.tap(completeBtn);
        await tester.tap(completeBtn, warnIfMissed: false);
        await tester.tap(completeBtn, warnIfMissed: false);
        await tester.tap(completeBtn, warnIfMissed: false);
        await tester.tap(completeBtn, warnIfMissed: false);

        await tester.pumpAndSettle();

        expect(completeCount, greaterThanOrEqualTo(1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '2.5 CancelStockInReceiptDialog: 5 rapid taps on "Xác nhận hủy" invokes usecase ONCE',
      (tester) async {
        final mockCancelUseCase = _MockCancelStockInReceiptUseCase(
          delay: const Duration(milliseconds: 300),
        );

        await tester.pumpWidget(
          _buildNavHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              cancelStockInReceiptUseCaseProvider
                  .overrideWithValue(mockCancelUseCase),
            ],
            child: Builder(
              builder: (ctx) => ElevatedButton(
                key: const Key('btn_open_cancel_dialog'),
                onPressed: () {
                  showDialog(
                    context: ctx,
                    builder: (_) => CancelStockInReceiptDialog(
                      receipt: completedReceipt,
                    ),
                  );
                },
                child: const Text('Open Cancel Dialog'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_open_harness_page')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_open_cancel_dialog')));
        await tester.pumpAndSettle();

        // Enter required cancellation reason
        await tester.enterText(
          find.byKey(const Key('input_cancel_reason')),
          'Khách đổi ý trả lại hàng lỗi',
        );
        await tester.pump();

        // Rapid multi-tap: 5 taps in immediate succession
        final confirmBtn = find.byKey(const Key('btn_confirm_cancel'));
        await tester.tap(confirmBtn);
        await tester.tap(confirmBtn, warnIfMissed: false);
        await tester.tap(confirmBtn, warnIfMissed: false);
        await tester.tap(confirmBtn, warnIfMissed: false);
        await tester.tap(confirmBtn, warnIfMissed: false);

        // Advance timer past async delay
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        dynamic firstException = tester.takeException();
        while (tester.takeException() != null) {}

        // Reset widget tree to prevent Navigator assertion leakage into subsequent tests
        await tester.pumpWidget(const SizedBox());
        while (tester.takeException() != null) {}

        expect(firstException, isNull, reason: 'Rapid taps caused Navigator exception: $firstException');
        expect(mockCancelUseCase.executeCallCount, 1, reason: 'Cancel usecase should be debounced to execute exactly once');
      },
    );
  });

  // ============================================================================
  // SUITE 3: STEPPER BOUNDARY CONDITIONS & INTEGRITY
  // ============================================================================
  group('Suite 3: Stepper Boundary Conditions & Integrity', () {
    testWidgets(
      '3.1 StockInItemCard: Decrement at quantity = 1 prompts confirmation dialog; Cancel preserves item',
      (tester) async {
        final itemQty1 = sampleItem1.copyWith(quantity: 1);
        bool deleted = false;
        int changedQty = 0;

        await tester.pumpWidget(
          _buildHarness(
            child: Scaffold(
              body: StockInItemCard(
                item: itemQty1,
                onDelete: () => deleted = true,
                onQuantityChanged: (q) => changedQty = q,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap decrement [-] when quantity is 1
        await tester.tap(find.byKey(Key('stepper_dec_${itemQty1.productId}')));
        await tester.pumpAndSettle();

        // Confirmation dialog appears
        expect(find.byKey(const Key('delete_confirmation_dialog')), findsOneWidget);
        expect(find.text('Xác nhận xóa'), findsOneWidget);

        // Tap "Hủy"
        await tester.tap(find.byKey(const Key('btn_cancel_delete')));
        await tester.pumpAndSettle();

        // Verify dialog dismissed, item was NOT deleted, quantity was NOT changed
        expect(find.byKey(const Key('delete_confirmation_dialog')), findsNothing);
        expect(deleted, isFalse);
        expect(changedQty, 0);

        // Tap decrement [-] again and confirm deletion
        await tester.tap(find.byKey(Key('stepper_dec_${itemQty1.productId}')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_confirm_delete')));
        await tester.pumpAndSettle();

        expect(deleted, isTrue);
      },
    );

    testWidgets(
      '3.2 StockInItemCard: Decrement at quantity = 2 decrements to 1 directly without dialog',
      (tester) async {
        final itemQty2 = sampleItem1.copyWith(quantity: 2);
        int changedQty = 0;

        await tester.pumpWidget(
          _buildHarness(
            child: Scaffold(
              body: StockInItemCard(
                item: itemQty2,
                onQuantityChanged: (q) => changedQty = q,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(Key('stepper_dec_${itemQty2.productId}')));
        await tester.pumpAndSettle();

        // No confirmation dialog shown
        expect(find.byKey(const Key('delete_confirmation_dialog')), findsNothing);
        expect(changedQty, 1);
      },
    );

    testWidgets(
      '3.3 StockInItemCard: Increment to large quantities updates stepper safely',
      (tester) async {
        final largeItem = sampleItem1.copyWith(quantity: 99999);
        int changedQty = 0;

        await tester.pumpWidget(
          _buildHarness(
            child: Scaffold(
              body: StockInItemCard(
                item: largeItem,
                onQuantityChanged: (q) => changedQty = q,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(Key('stepper_inc_${largeItem.productId}')));
        await tester.pumpAndSettle();

        expect(changedQty, 100000);
      },
    );

    testWidgets(
      '3.4 StockInProductEditSheet: Decrement button is disabled at quantity = 1; increment updates reactively',
      (tester) async {
        await tester.pumpWidget(
          _buildHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            ],
            child: Scaffold(
              body: StockInProductEditSheet(
                product: sampleProduct1,
                branchStock: 10,
                existingItem: sampleItem1.copyWith(quantity: 1, unitPrice: 100000),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Stepper dec is disabled (onPressed == null)
        final decFinder = find.byKey(const Key('sheet_stepper_dec'));
        final IconButton decButton = tester.widget(decFinder);
        expect(decButton.onPressed, isNull);

        // Tap increment [+]
        await tester.tap(find.byKey(const Key('sheet_stepper_inc')));
        await tester.pumpAndSettle();

        // Quantity becomes 2
        expect(find.text('2'), findsWidgets);

        // Stepper dec becomes enabled
        final IconButton decButtonAfter = tester.widget(decFinder);
        expect(decButtonAfter.onPressed, isNotNull);
      },
    );
  });

  // ============================================================================
  // SUITE 4: ACCOUNTING NUMPAD EDGE CASES & STRING PARSER HARDENING
  // ============================================================================
  group('Suite 4: Accounting Numpad Edge Cases & String Parser Hardening', () {
    testWidgets(
      '4.1 Multiple decimal points defense: Only a single decimal point is accepted',
      (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            ],
            child: const Scaffold(
              body: StockInProductEditSheet(
                product: sampleProduct2,
                branchStock: 10,
                preFilledPrice: 0,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Select unit price field
        await tester.tap(find.byKey(const Key('sheet_input_price')));
        await tester.pumpAndSettle();

        // Clear price first
        await tester.tap(find.byKey(const Key('numpad_clear')));
        await tester.pump();

        // Type: 1 . . . 5 . 0
        await tester.tap(find.byKey(const Key('numpad_1')));
        await tester.tap(find.byKey(const Key('numpad_.')));
        await tester.tap(find.byKey(const Key('numpad_.')));
        await tester.tap(find.byKey(const Key('numpad_.')));
        await tester.tap(find.byKey(const Key('numpad_5')));
        await tester.tap(find.byKey(const Key('numpad_.')));
        await tester.tap(find.byKey(const Key('numpad_0')));
        await tester.pumpAndSettle();

        final priceField = tester.widget<TextFormField>(
          find.byKey(const Key('sheet_input_price')),
        );
        final priceText = priceField.controller?.text ?? '';

        // Must NOT contain multiple dots
        expect('.'.allMatches(priceText).length, lessThanOrEqualTo(1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '4.2 Repeated zeros and 000 handling on fresh field: No leading zero pileup',
      (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            ],
            child: const Scaffold(
              body: StockInProductEditSheet(
                product: sampleProduct2,
                branchStock: 10,
                preFilledPrice: 0,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Clear price
        await tester.tap(find.byKey(const Key('numpad_clear')));
        await tester.pump();

        // Type: 000 then 5 then 000
        await tester.tap(find.byKey(const Key('numpad_000')));
        await tester.tap(find.byKey(const Key('numpad_5')));
        await tester.tap(find.byKey(const Key('numpad_000')));
        await tester.pumpAndSettle();

        final priceField = tester.widget<TextFormField>(
          find.byKey(const Key('sheet_input_price')),
        );
        final priceText = priceField.controller?.text ?? '';

        // Formatted properly to 5,000 without 000005000
        expect(priceText.replaceAll('.', '').replaceAll(',', ''), '5000');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '4.3 Backspace on empty/single character: Does not crash with RangeError',
      (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            ],
            child: const Scaffold(
              body: StockInProductEditSheet(
                product: sampleProduct2,
                branchStock: 10,
                preFilledPrice: 0,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Repeatedly tap backspace 6 times on already 0 value
        for (int i = 0; i < 6; i++) {
          await tester.tap(find.byKey(const Key('numpad_backspace')));
          await tester.pump();
        }

        expect(tester.takeException(), isNull);

        // Switch to quantity and tap backspace repeatedly
        await tester.tap(find.text('Số lượng nhập'));
        await tester.pump();

        for (int i = 0; i < 6; i++) {
          await tester.tap(find.byKey(const Key('numpad_backspace')));
          await tester.pump();
        }

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '4.4 Clear button ("C") resets active field to 0/1 properly',
      (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            ],
            child: const Scaffold(
              body: StockInProductEditSheet(
                product: sampleProduct2,
                branchStock: 10,
                preFilledPrice: 500000,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Clear
        await tester.tap(find.byKey(const Key('numpad_clear')));
        await tester.pumpAndSettle();

        final priceField = tester.widget<TextFormField>(
          find.byKey(const Key('sheet_input_price')),
        );
        expect(priceField.controller?.text, '0');
        expect(find.byKey(const Key('sheet_calculated_net_price')), findsOneWidget);
        expect(find.text('0 đ'), findsWidgets);
      },
    );

    testWidgets(
      '4.5 Switching active fields dynamically recalculates net price and subtotal instantly',
      (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            ],
            child: const Scaffold(
              body: StockInProductEditSheet(
                product: sampleProduct2,
                branchStock: 10,
                preFilledPrice: 0,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Focus Quantity -> set to 3
        await tester.tap(find.text('Số lượng nhập'));
        await tester.pump();
        await tester.tap(find.byKey(const Key('numpad_3')));
        await tester.pump();

        // 2. Focus Unit Price -> set to 20,000
        await tester.tap(find.byKey(const Key('sheet_input_price')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('numpad_2')));
        await tester.tap(find.byKey(const Key('numpad_0')));
        await tester.tap(find.byKey(const Key('numpad_000')));
        await tester.pump();

        // 3. Focus Discount -> set to 5,000
        await tester.tap(find.byKey(const Key('sheet_input_discount')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('numpad_5')));
        await tester.tap(find.byKey(const Key('numpad_000')));
        await tester.pumpAndSettle();

        // Verification:
        // Net Price = 20,000 - 5,000 = 15,000 đ
        // Subtotal = 15,000 * 3 = 45,000 đ
        final currencyFormat = NumberFormat('#,###', 'vi_VN');
        final expectedNetPrice = '${currencyFormat.format(15000)} đ';
        final expectedTotal = '${currencyFormat.format(45000)} đ';

        expect(find.text(expectedNetPrice), findsOneWidget);
        expect(find.text(expectedTotal), findsOneWidget);
      },
    );
  });

  // ============================================================================
  // SUITE 5: POPSCOPE NAVIGATION & EXIT DIALOG HANDLING
  // ============================================================================
  group('Suite 5: PopScope Navigation & Exit Dialog Handling', () {
    testWidgets(
      '5.1 Empty cart: Tapping Close (X) exits immediately without showing exit dialog',
      (tester) async {
        await tester.pumpWidget(
          _buildNavHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                  }),
              productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
              supplierListNotifierProvider.overrideWith(
                () => _TestSupplierListNotifier([]),
              ),
            ],
            child: const ImportInventoryPage(),
          ),
        );
        await tester.pumpAndSettle();

        // Open import page
        await tester.tap(find.byKey(const Key('btn_open_harness_page')));
        await tester.pumpAndSettle();

        expect(find.byType(ImportInventoryPage), findsOneWidget);

        // Tap Close (X)
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Exited immediately without showing dialog
        expect(find.byKey(const Key('exit_receipt_dialog')), findsNothing);
        expect(find.byType(ImportInventoryPage), findsNothing);
      },
    );

    testWidgets(
      '5.2 Non-empty cart: Tapping Close (X) shows dialog; "Ở lại" preserves page state',
      (tester) async {
        await tester.pumpWidget(
          _buildNavHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                  }),
              productListProvider.overrideWith((ref) => Stream.value([sampleProduct1])),
              supplierListNotifierProvider.overrideWith(
                () => _TestSupplierListNotifier([]),
              ),
            ],
            child: ImportInventoryPage(
              initialReceipt: StockInReceipt(
                id: 'draft_001',
                importCode: 'PN_001',
                date: DateTime.now(),
                storeId: 'store_001',
                items: [sampleItem1],
                status: 'draft',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open page
        await tester.tap(find.byKey(const Key('btn_open_harness_page')));
        await tester.pumpAndSettle();

        // Tap Close (X)
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Dialog appears
        expect(find.byKey(const Key('exit_receipt_dialog')), findsOneWidget);

        // Tap "Ở lại"
        await tester.tap(find.byKey(const Key('dialog_choice_stay')));
        await tester.pumpAndSettle();

        // Dialog dismissed, page remains open with item intact
        expect(find.byKey(const Key('exit_receipt_dialog')), findsNothing);
        expect(find.byType(ImportInventoryPage), findsOneWidget);
        expect(find.byKey(Key('item_card_${sampleItem1.productId}')), findsOneWidget);
      },
    );

    testWidgets(
      '5.3 Non-empty cart: Tapping "Rời khỏi" pops page without saving draft',
      (tester) async {
        final mockSaveDraftUseCase = _MockSaveStockInDraftUseCase();

        await tester.pumpWidget(
          _buildNavHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                  }),
              productListProvider.overrideWith((ref) => Stream.value([sampleProduct1])),
              supplierListNotifierProvider.overrideWith(
                () => _TestSupplierListNotifier([]),
              ),
              saveStockInDraftUseCaseProvider
                  .overrideWithValue(mockSaveDraftUseCase),
            ],
            child: ImportInventoryPage(
              initialReceipt: StockInReceipt(
                id: 'draft_001',
                importCode: 'PN_001',
                date: DateTime.now(),
                storeId: 'store_001',
                items: [sampleItem1],
                status: 'draft',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_open_harness_page')));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Tap "Rời khỏi"
        await tester.tap(find.byKey(const Key('dialog_choice_exit')));
        await tester.pumpAndSettle();

        // Page popped, NO saveDraft call
        expect(find.byType(ImportInventoryPage), findsNothing);
        expect(mockSaveDraftUseCase.executeCallCount, 0);
      },
    );

    testWidgets(
      '5.4 Non-empty cart: Tapping "Lưu tạm" saves draft to repository and pops',
      (tester) async {
        final mockSaveDraftUseCase = _MockSaveStockInDraftUseCase();

        await tester.pumpWidget(
          _buildNavHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                  }),
              productListProvider.overrideWith((ref) => Stream.value([sampleProduct1])),
              supplierListNotifierProvider.overrideWith(
                () => _TestSupplierListNotifier([]),
              ),
              saveStockInDraftUseCaseProvider
                  .overrideWithValue(mockSaveDraftUseCase),
            ],
            child: ImportInventoryPage(
              initialReceipt: StockInReceipt(
                id: 'draft_001',
                importCode: 'PN_001',
                date: DateTime.now(),
                storeId: 'store_001',
                items: [sampleItem1],
                status: 'draft',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_open_harness_page')));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Tap "Lưu tạm" in exit dialog
        await tester.tap(find.byKey(const Key('dialog_choice_draft')));
        await tester.pumpAndSettle();

        // Draft was saved and page popped
        expect(mockSaveDraftUseCase.executeCallCount, 1);
        expect(find.byType(ImportInventoryPage), findsNothing);
      },
    );

    testWidgets(
      '5.5 PopScope invocation in Step 2 triggers exit interception',
      (tester) async {
        await tester.pumpWidget(
          _buildNavHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                  }),
              productListProvider.overrideWith((ref) => Stream.value([sampleProduct1])),
              supplierListNotifierProvider.overrideWith(
                () => _TestSupplierListNotifier([sampleSupplier]),
              ),
            ],
            child: ImportInventoryPage(
              initialReceipt: StockInReceipt(
                id: 'draft_001',
                importCode: 'PN_001',
                date: DateTime.now(),
                storeId: 'store_001',
                items: [sampleItem1],
                status: 'draft',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_open_harness_page')));
        await tester.pumpAndSettle();

        // Transition to Step 2
        await tester.tap(find.byKey(const Key('btn_continue')));
        await tester.pumpAndSettle();

        // Simulate hardware back button via PopScope
        final popScopeFinder = find.byWidgetPredicate((w) => w is PopScope);
        expect(popScopeFinder, findsWidgets);
        final popScope = tester.widget<PopScope>(popScopeFinder.first);
        popScope.onPopInvokedWithResult?.call(false, null);
        await tester.pumpAndSettle();

        // Exit dialog is triggered
        expect(find.byKey(const Key('exit_receipt_dialog')), findsOneWidget);

        // Tap "Ở lại" to stay
        await tester.tap(find.byKey(const Key('dialog_choice_stay')));
        await tester.pumpAndSettle();

        expect(find.byType(StockInPaymentConfirmationView), findsOneWidget);
      },
    );
  });

  // ============================================================================
  // SUITE 6: RESUMING COMPLEX DRAFTS & STEP 1 <-> STEP 2 BI-DIRECTIONAL FIDELITY
  // ============================================================================
  group('Suite 6: Resuming Complex Drafts & Bi-directional State Fidelity', () {
    testWidgets(
      '6.1 Resuming draft with custom prices, supplier, discount, note and transitioning Step 1 <-> Step 2 preserves ALL mutations without loss',
      (tester) async {
        final mockCompleteUseCase = _MockCompleteStockInReceiptUseCase();

        final initialDraft = StockInReceipt(
          id: 'draft_complex_001',
          importCode: 'PN_COMPLEX_001',
          date: DateTime(2026, 9, 27, 8, 0),
          storeId: 'store_001',
          supplierId: sampleSupplier.id,
          supplierName: sampleSupplier.name,
          supplierPhone: sampleSupplier.phone,
          items: [sampleItem1, sampleItem2],
          discount: 20000.0,
          paidAmount: 200000.0,
          paymentMethod: 'cash',
          note: 'Giao buổi sáng trước 10h',
          status: 'draft',
        );

        await tester.pumpWidget(
          _buildNavHarness(
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
              currentStoreIdProvider.overrideWith((ref) => 'store_001'),
              availableStoresProvider.overrideWith((ref) async => {
                    'store_001': 'Chi nhánh Đông Thắng',
                  }),
              productListProvider.overrideWith(
                (ref) => Stream.value([sampleProduct1, sampleProduct2]),
              ),
              supplierListNotifierProvider.overrideWith(
                () => _TestSupplierListNotifier([sampleSupplier]),
              ),
              completeStockInReceiptUseCaseProvider
                  .overrideWithValue(mockCompleteUseCase),
            ],
            child: ImportInventoryPage(initialReceipt: initialDraft),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Open ImportInventoryPage
        await tester.tap(find.byKey(const Key('btn_open_harness_page')));
        await tester.pumpAndSettle();

        // Verify Step 1 correctly rendered with both items
        expect(find.byKey(Key('item_card_${sampleItem1.productId}')), findsOneWidget);
        expect(find.byKey(Key('item_card_${sampleItem2.productId}')), findsOneWidget);
        expect(find.text(sampleSupplier.name), findsOneWidget);

        // 2. Transition forward to Step 2
        await tester.tap(find.byKey(const Key('btn_continue')));
        await tester.pumpAndSettle();

        expect(find.byType(StockInPaymentConfirmationView), findsOneWidget);

        // Verify initial note and discount in Step 2
        expect(find.text('Giao buổi sáng trước 10h'), findsOneWidget);

        final noteInput = find.byKey(const Key('input_receipt_note'));
        await tester.ensureVisible(noteInput);
        await tester.pumpAndSettle();
        await tester.enterText(
          noteInput,
          'Cần hóa đơn đỏ và giao buổi chiều',
        );
        await tester.pump();

        final transferChip = find.byKey(const Key('payment_transfer'));
        await tester.ensureVisible(transferChip);
        await tester.pumpAndSettle();
        await tester.tap(transferChip);
        await tester.pumpAndSettle();

        // 4. Navigate back to Step 1 via "Xem hàng trong phiếu >"
        final viewItemsBtn = find.byKey(const Key('btn_view_receipt_items'));
        await tester.ensureVisible(viewItemsBtn);
        await tester.pumpAndSettle();
        await tester.tap(viewItemsBtn);
        await tester.pumpAndSettle();

        // Now back on Step 1
        expect(find.byType(StockInPaymentConfirmationView), findsNothing);
        expect(find.byKey(Key('item_card_${sampleItem1.productId}')), findsOneWidget);

        // Modify quantity of Item 1 on Step 1: tap [+]
        await tester.tap(find.byKey(Key('stepper_inc_${sampleItem1.productId}')));
        await tester.pumpAndSettle();

        // 5. Navigate forward to Step 2 again
        await tester.tap(find.byKey(const Key('btn_continue')));
        await tester.pumpAndSettle();

        expect(find.byType(StockInPaymentConfirmationView), findsOneWidget);

        // Assert: Edited note and payment method from earlier are STILL INTACT!
        expect(
          find.text('Cần hóa đơn đỏ và giao buổi chiều'),
          findsOneWidget,
        );

        // 6. Complete receipt from Step 2
        final completeBtn = find.byKey(const Key('btn_payment_complete'));
        await tester.ensureVisible(completeBtn);
        await tester.pumpAndSettle();
        await tester.tap(completeBtn);
        await tester.pumpAndSettle();

        // Assert: CompleteStockInReceiptUseCase was called with all preserved edits
        expect(mockCompleteUseCase.executeCallCount, 1);
        final completed = mockCompleteUseCase.executed.first;
        expect(completed.note, 'Cần hóa đơn đỏ và giao buổi chiều');
        expect(completed.paymentMethod, 'transfer');
        expect(completed.items.firstWhere((i) => i.productId == sampleItem1.productId).quantity, 3);
        expect(completed.status, 'completed');
      },
    );
  });
}
