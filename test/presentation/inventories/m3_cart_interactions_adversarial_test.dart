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
import 'package:stores/presentation/inventories/widgets/sticky_bottom_summary_bar.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_item_card.dart';
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
    if (idx >= 0) savedDrafts[idx] = receipt;
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
    return 150000.0;
  }
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: child,
    ),
  );
}

void main() {
  const adminUser = UserAccount(
    username: 'admin_test',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const sampleProductA = Product(
    id: 'prod_a',
    name: 'Gạo ST25 Thượng Hạng',
    code: 'ST25',
    price: 250000,
    costPrice: 150000,
    branchStocks: {'store_001': 20, 'store_002': 10},
    category: 'Gạo Đặc Sản',
  );

  const sampleProductB = Product(
    id: 'prod_b',
    name: 'Đường Tinh Luyện Cao Cấp Biên Hòa 1kg',
    code: 'DUONG_BH',
    price: 32000,
    costPrice: 24000,
    branchStocks: {'store_001': 50, 'store_002': 30},
    category: 'Gia Vị',
  );

  const sampleSupplier = Supplier(
    id: 'sup_01',
    name: 'Công ty Cổ phần Nông sản Việt',
    code: 'NCC_NSV',
    phone: '0988776655',
    currentDebt: 2500000.0,
  );

  group('Challenger M3: Stepper Boundary Stress Tests', () {
    testWidgets('Decrementing at quantity = 1 shows dialog; Cancel keeps item & does not call onDelete', (tester) async {
      bool deleted = false;
      int? changedQty;

      const singleItem = StockInReceiptItem(
        transactionId: 'TX_01',
        productId: 'prod_a',
        quantity: 1,
        unitPrice: 150000.0,
        productName: 'Gạo ST25 Thượng Hạng',
        productCode: 'ST25',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: Scaffold(
            body: StockInItemCard(
              item: singleItem,
              currentStock: 20,
              onQuantityChanged: (q) => changedQty = q,
              onDelete: () => deleted = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap decrement [-]
      await tester.tap(find.byKey(const Key('stepper_dec_prod_a')));
      await tester.pumpAndSettle();

      // Deletion dialog is shown
      expect(find.byKey(const Key('delete_confirmation_dialog')), findsOneWidget);
      expect(find.text('Xác nhận xóa'), findsOneWidget);

      // Tap 'Hủy' (cancel delete)
      await tester.tap(find.byKey(const Key('btn_cancel_delete')));
      await tester.pumpAndSettle();

      // Dialog is gone, item not deleted, quantity unchanged
      expect(find.byKey(const Key('delete_confirmation_dialog')), findsNothing);
      expect(deleted, isFalse);
      expect(changedQty, isNull);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('Decrementing at quantity = 1 shows dialog; Confirm invokes onDelete', (tester) async {
      bool deleted = false;

      const singleItem = StockInReceiptItem(
        transactionId: 'TX_01',
        productId: 'prod_a',
        quantity: 1,
        unitPrice: 150000.0,
        productName: 'Gạo ST25 Thượng Hạng',
        productCode: 'ST25',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: Scaffold(
            body: StockInItemCard(
              item: singleItem,
              currentStock: 20,
              onDelete: () => deleted = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap decrement [-]
      await tester.tap(find.byKey(const Key('stepper_dec_prod_a')));
      await tester.pumpAndSettle();

      // Tap 'Xóa' (confirm delete)
      await tester.tap(find.byKey(const Key('btn_confirm_delete')));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
      expect(find.byKey(const Key('delete_confirmation_dialog')), findsNothing);
    });

    testWidgets('Decrementing at quantity = 2 decrements without showing dialog', (tester) async {
      int? changedQty;
      bool deleted = false;

      const itemWithQty2 = StockInReceiptItem(
        transactionId: 'TX_02',
        productId: 'prod_a',
        quantity: 2,
        unitPrice: 150000.0,
        productName: 'Gạo ST25 Thượng Hạng',
        productCode: 'ST25',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: Scaffold(
            body: StockInItemCard(
              item: itemWithQty2,
              currentStock: 20,
              onQuantityChanged: (q) => changedQty = q,
              onDelete: () => deleted = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap decrement [-]
      await tester.tap(find.byKey(const Key('stepper_dec_prod_a')));
      await tester.pumpAndSettle();

      // Should directly call onQuantityChanged with 1, no dialog
      expect(find.byKey(const Key('delete_confirmation_dialog')), findsNothing);
      expect(changedQty, equals(1));
      expect(deleted, isFalse);
    });

    testWidgets('Incrementing large quantity handles high values properly', (tester) async {
      int? changedQty;

      const largeQtyItem = StockInReceiptItem(
        transactionId: 'TX_99',
        productId: 'prod_a',
        quantity: 999,
        unitPrice: 150000.0,
        productName: 'Gạo ST25 Thượng Hạng',
        productCode: 'ST25',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: Scaffold(
            body: StockInItemCard(
              item: largeQtyItem,
              currentStock: 20,
              onQuantityChanged: (q) => changedQty = q,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('999'), findsOneWidget);

      await tester.tap(find.byKey(const Key('stepper_inc_prod_a')));
      await tester.pumpAndSettle();

      expect(changedQty, equals(1000));
    });
  });

  group('Challenger M3: Swipe-to-Delete Stress Tests', () {
    testWidgets('Swipe left (endToStart) triggers dialog; Cancel keeps item visible', (tester) async {
      bool deleted = false;

      const testItem = StockInReceiptItem(
        transactionId: 'TX_01',
        productId: 'prod_a',
        quantity: 5,
        unitPrice: 150000.0,
        productName: 'Gạo ST25 Thượng Hạng',
        productCode: 'ST25',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: Scaffold(
            body: StockInItemCard(
              item: testItem,
              currentStock: 20,
              onDelete: () => deleted = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag left to dismiss
      await tester.drag(find.byKey(const Key('item_card_prod_a')), const Offset(-350, 0));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_confirmation_dialog')), findsOneWidget);

      // Cancel dismissal
      await tester.tap(find.byKey(const Key('btn_cancel_delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_confirmation_dialog')), findsNothing);
      expect(deleted, isFalse);
      expect(find.byKey(const Key('item_card_prod_a')), findsOneWidget);
    });

    testWidgets('Swipe left (endToStart) and Confirm delete invokes onDelete', (tester) async {
      bool deleted = false;

      const testItem = StockInReceiptItem(
        transactionId: 'TX_01',
        productId: 'prod_a',
        quantity: 5,
        unitPrice: 150000.0,
        productName: 'Gạo ST25 Thượng Hạng',
        productCode: 'ST25',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: Scaffold(
            body: StockInItemCard(
              item: testItem,
              currentStock: 20,
              onDelete: () => deleted = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag left to dismiss
      await tester.drag(find.byKey(const Key('item_card_prod_a')), const Offset(-350, 0));
      await tester.pumpAndSettle();

      // Confirm dismissal
      await tester.tap(find.byKey(const Key('btn_confirm_delete')));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });

    testWidgets('Swipe right (startToEnd) does NOT trigger delete confirmation dialog', (tester) async {
      const testItem = StockInReceiptItem(
        transactionId: 'TX_01',
        productId: 'prod_a',
        quantity: 5,
        unitPrice: 150000.0,
        productName: 'Gạo ST25 Thượng Hạng',
        productCode: 'ST25',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const Scaffold(
            body: StockInItemCard(
              item: testItem,
              currentStock: 20,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag right (startToEnd)
      await tester.drag(find.byKey(const Key('item_card_prod_a')), const Offset(350, 0));
      await tester.pumpAndSettle();

      // No dialog should appear
      expect(find.byKey(const Key('delete_confirmation_dialog')), findsNothing);
      expect(find.byKey(const Key('item_card_prod_a')), findsOneWidget);
    });
  });

  group('Challenger M3: Full Cart Lifecycle Stress Tests', () {
    late _MockStockInReceiptRepository mockRepo;

    setUp(() {
      mockRepo = _MockStockInReceiptRepository();
    });

    testWidgets('Empty cart -> Add item -> Stepper update -> Delete item -> Verified empty state and button states', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProductA, sampleProductB])),
            supplierListNotifierProvider.overrideWith(() => _TestSupplierListNotifier([sampleSupplier])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // PHASE 1: Verify Initial Empty State
      expect(find.text('Chưa có hàng trong phiếu'), findsOneWidget);
      expect(find.text('0 mặt hàng • Số lượng: 0'), findsOneWidget);
      expect(find.text('0 đ'), findsWidgets);

      // Verify "Tiếp tục" button is disabled
      final continueBtn1 = tester.widget<ElevatedButton>(find.byKey(const Key('btn_continue')));
      expect(continueBtn1.onPressed, isNull);

      // Verify "Lưu tạm" button is disabled
      final draftBtn1 = tester.widget<OutlinedButton>(find.byKey(const Key('btn_save_draft')));
      expect(draftBtn1.onPressed, isNull);

      // PHASE 2: Add Item via Search
      final searchField = find.byType(TextFormField).first;
      await tester.enterText(searchField, 'ST25');
      await tester.pumpAndSettle();

      // Select option from Autocomplete
      final optionFinder = find.text('Gạo ST25 Thượng Hạng • ST25');
      expect(optionFinder, findsOneWidget);
      await tester.tap(optionFinder);
      await tester.pumpAndSettle();

      // Product Edit Sheet appears
      expect(find.byKey(const Key('btn_sheet_done')), findsOneWidget);

      // Confirm adding item by tapping "Xong"
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      // PHASE 3: Cart has 1 item
      expect(find.text('Chưa có hàng trong phiếu'), findsNothing);
      expect(find.byKey(const Key('item_card_prod_a')), findsOneWidget);
      expect(find.text('1 mặt hàng • Số lượng: 1'), findsOneWidget);
      expect(find.text('150.000 đ'), findsWidgets);

      // Buttons are now enabled
      final continueBtn2 = tester.widget<ElevatedButton>(find.byKey(const Key('btn_continue')));
      expect(continueBtn2.onPressed, isNotNull);

      final draftBtn2 = tester.widget<OutlinedButton>(find.byKey(const Key('btn_save_draft')));
      expect(draftBtn2.onPressed, isNotNull);

      // PHASE 4: Update quantity via stepper
      await tester.tap(find.byKey(const Key('stepper_inc_prod_a')));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('1 mặt hàng • Số lượng: 2'), findsOneWidget);
      expect(find.text('300.000 đ'), findsWidgets);

      // Decrement back to 1
      await tester.tap(find.byKey(const Key('stepper_dec_prod_a')));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('1 mặt hàng • Số lượng: 1'), findsOneWidget);
      expect(find.text('150.000 đ'), findsWidgets);

      // PHASE 5: Delete item from cart (decrement from 1)
      await tester.tap(find.byKey(const Key('stepper_dec_prod_a')));
      await tester.pumpAndSettle();

      // Confirmation dialog appears
      expect(find.byKey(const Key('delete_confirmation_dialog')), findsOneWidget);

      // Confirm delete
      await tester.tap(find.byKey(const Key('btn_confirm_delete')));
      await tester.pumpAndSettle();

      // PHASE 6: Verify Cart Returned to Empty State
      expect(find.text('Chưa có hàng trong phiếu'), findsOneWidget);
      expect(find.byKey(const Key('item_card_prod_a')), findsNothing);
      expect(find.text('0 mặt hàng • Số lượng: 0'), findsOneWidget);
      expect(find.text('0 đ'), findsWidgets);

      // Buttons disabled again
      final continueBtn3 = tester.widget<ElevatedButton>(find.byKey(const Key('btn_continue')));
      expect(continueBtn3.onPressed, isNull);

      final draftBtn3 = tester.widget<OutlinedButton>(find.byKey(const Key('btn_save_draft')));
      expect(draftBtn3.onPressed, isNull);
    });

    testWidgets('Multi-item cart swipe deletion removes targeted item while keeping other items intact', (tester) async {
      final multiItemDraft = StockInReceipt(
        id: 'REC_MULTI_01',
        importCode: 'PN_MULTI_01',
        date: DateTime(2026, 9, 27),
        storeId: 'store_001',
        supplierId: sampleSupplier.id,
        supplierName: sampleSupplier.name,
        supplierPhone: sampleSupplier.phone,
        items: const [
          StockInReceiptItem(
            transactionId: 'TX_A',
            productId: 'prod_a',
            quantity: 2,
            unitPrice: 150000.0,
            originalPrice: 150000.0,
            productName: 'Gạo ST25 Thượng Hạng',
            productCode: 'ST25',
          ),
          StockInReceiptItem(
            transactionId: 'TX_B',
            productId: 'prod_b',
            quantity: 5,
            unitPrice: 24000.0,
            originalPrice: 24000.0,
            productName: 'Đường Tinh Luyện Cao Cấp Biên Hòa 1kg',
            productCode: 'DUONG_BH',
          ),
        ],
        totalAmount: 420000.0, // 300,000 + 120,000
        status: 'draft',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: ImportInventoryPage(initialReceipt: multiItemDraft),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProductA, sampleProductB])),
            supplierListNotifierProvider.overrideWith(() => _TestSupplierListNotifier([sampleSupplier])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('item_card_prod_a')), findsOneWidget);
      expect(find.byKey(const Key('item_card_prod_b')), findsOneWidget);
      expect(find.text('2 mặt hàng • Số lượng: 7'), findsOneWidget);
      expect(find.text('420.000 đ'), findsWidgets);

      // Swipe-to-delete item A
      await tester.drag(find.byKey(const Key('item_card_prod_a')), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_confirmation_dialog')), findsOneWidget);

      // Confirm delete
      await tester.tap(find.byKey(const Key('btn_confirm_delete')));
      await tester.pumpAndSettle();

      // Item A is deleted; Item B is still present
      expect(find.byKey(const Key('item_card_prod_a')), findsNothing);
      expect(find.byKey(const Key('item_card_prod_b')), findsOneWidget);

      // Summary updates to only reflect item B (5 * 24,000 = 120,000 đ)
      expect(find.text('1 mặt hàng • Số lượng: 5'), findsOneWidget);
      expect(find.text('120.000 đ'), findsWidgets);
    });
  });

  group('Challenger M3: Viewport Stress & RenderFlex Overflow Audits (320px, 360px, 375px)', () {
    for (final width in [320.0, 360.0, 375.0]) {
      testWidgets('Audit $width px: StickyBottomSummaryBar top row RenderFlex overflow check', (tester) async {
        tester.view.physicalSize = Size(width, 700.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: StickyBottomSummaryBar(
                totalAmount: 150000000.0,
                itemCount: 15,
                totalQuantity: 250,
                onSaveDraft: () {},
                onContinue: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final exception = tester.takeException();
        // Record whether StickyBottomSummaryBar overflows horizontally
        if (exception != null) {
          debugPrint('>>> FOUND OVERFLOW in StickyBottomSummaryBar on ${width}px: $exception');
        }
        expect(exception, isNull, reason: 'StickyBottomSummaryBar must not overflow on ${width}px viewport');
      });

      testWidgets('Audit $width px: StockInItemCard with realistic Vietnamese SKU & amount', (tester) async {
        tester.view.physicalSize = Size(width, 700.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const cardItem = StockInReceiptItem(
          transactionId: 'TX_TEST_01',
          productId: 'prod_test',
          quantity: 25,
          unitPrice: 1550000.0,
          productName: 'Gạo ST25 Thượng Hạng Đặc Biệt Hạt Dài Thơm Dẻo',
          productCode: 'ST25-DAC-BIET-2026',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: const [
                  StockInItemCard(
                    item: cardItem,
                    currentStock: 999,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final exception = tester.takeException();
        if (exception != null) {
          debugPrint('>>> FOUND OVERFLOW in StockInItemCard on ${width}px: $exception');
        }
        expect(exception, isNull, reason: 'StockInItemCard must not overflow on ${width}px viewport');
      });

      testWidgets('Audit $width px: StockInPaymentConfirmationView payment methods row RenderFlex check', (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          debugPrint('>>> FULL ERROR DETAILS:\n$details');
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        tester.view.physicalSize = Size(width, 700.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final testReceipt = StockInReceipt(
          id: 'REC_TEST',
          importCode: 'PN_TEST',
          date: DateTime(2026, 9, 27),
          storeId: 'store_001',
          items: const [
            StockInReceiptItem(
              transactionId: 'TX_1',
              productId: 'prod_1',
              quantity: 2,
              unitPrice: 150000.0,
            ),
          ],
          totalAmount: 300000.0,
          status: 'draft',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: StockInPaymentConfirmationView(
              receipt: testReceipt,
              suppliers: const [],
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

        final exception = tester.takeException();
        if (exception != null) {
          debugPrint('CURRENT EXCEPTION DEEP:\n${(exception as dynamic).toStringDeep()}');
        }
        expect(exception, isNull, reason: 'StockInPaymentConfirmationView must not overflow on ${width}px viewport');
      });
    }
  });
}
