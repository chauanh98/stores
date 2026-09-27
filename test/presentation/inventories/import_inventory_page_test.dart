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
    return 120000.0;
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
  const staffUser = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const sampleProduct = Product(
    id: 'prod_01',
    name: 'Gạo ST25 Đặc Sản',
    code: 'ST25',
    price: 200000,
    costPrice: 150000,
    branchStocks: {'store_001': 10, 'store_002': 5},
    category: 'Gạo',
  );

  const sampleSupplier = Supplier(
    id: 'sup_01',
    name: 'Công ty Cổ phần Nông nghiệp Ánh Dương',
    code: 'NCC_AD',
    phone: '0901234567',
    currentDebt: 5000000.0,
  );

  final sampleDraft = StockInReceipt(
    id: 'REC_DRAFT_99',
    importCode: 'PN_DRAFT_99',
    date: DateTime(2026, 9, 27),
    storeId: 'store_001',
    supplierId: sampleSupplier.id,
    supplierName: sampleSupplier.name,
    supplierPhone: sampleSupplier.phone,
    items: const [
      StockInReceiptItem(
        transactionId: 'TX_DRAFT_01',
        productId: 'prod_01',
        quantity: 3,
        unitPrice: 150000.0,
        originalPrice: 150000.0,
        productName: 'Gạo ST25 Đặc Sản',
        productCode: 'ST25',
      ),
    ],
    totalAmount: 450000.0,
    status: 'draft',
  );

  group('ImportInventoryPage Modern 2-Step Flow & Draft Tests (Milestone 3)', () {
    late _MockStockInReceiptRepository mockRepo;

    setUp(() {
      mockRepo = _MockStockInReceiptRepository();
    });

    testWidgets('Empty cart displays empty illustration and disables "Tiếp tục" button', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => _TestSupplierListNotifier([sampleSupplier])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Title & Empty state
      expect(find.text('Phiếu nhập hàng mới'), findsOneWidget);
      expect(find.text('Chưa có hàng trong phiếu'), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);

      // Bottom bar
      expect(find.text('0 mặt hàng • Số lượng: 0'), findsOneWidget);
      expect(find.text('0 đ'), findsOneWidget);

      // "Tiếp tục" is disabled when empty
      final continueBtn = tester.widget<ElevatedButton>(find.byKey(const Key('btn_continue')));
      expect(continueBtn.onPressed, isNull);
    });

    testWidgets('Resuming draft populates items, title, and allows 2-step navigation', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => _TestSupplierListNotifier([sampleSupplier])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Title indicates resumed draft code
      expect(find.text('Phiếu PN_DRAFT_99'), findsOneWidget);

      // Cart item rendered
      expect(find.text('Gạo ST25 Đặc Sản'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // quantity
      expect(find.text('450.000 đ'), findsWidgets); // 150,000 * 3
      expect(find.text('1 mặt hàng • Số lượng: 3'), findsOneWidget);

      // Tap "Tiếp tục" -> Navigates to Step 2
      await tester.tap(find.byKey(const Key('btn_continue')));
      await tester.pumpAndSettle();

      // Step 2: Payment & Supplier Confirmation View
      expect(find.byType(StockInPaymentConfirmationView), findsOneWidget);
      expect(find.text('Thanh toán & Nhà cung cấp'), findsOneWidget);
      expect(find.byKey(const Key('btn_view_receipt_items')), findsOneWidget);
      expect(find.byKey(const Key('btn_payment_complete')), findsOneWidget);

      // Tap "Xem hàng trong phiếu >" -> Navigates back to Step 1
      await tester.tap(find.byKey(const Key('btn_view_receipt_items')));
      await tester.pumpAndSettle();

      expect(find.byType(StockInPaymentConfirmationView), findsNothing);
      expect(find.text('Phiếu PN_DRAFT_99'), findsOneWidget);
    });

    testWidgets('Stepper increment dynamically updates totals in sticky bottom bar', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => _TestSupplierListNotifier([sampleSupplier])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('450.000 đ'), findsWidgets);
      expect(find.text('1 mặt hàng • Số lượng: 3'), findsOneWidget);

      // Increment stepper [+]
      await tester.tap(find.byKey(const Key('stepper_inc_prod_01')));
      await tester.pumpAndSettle();

      // Quantity becomes 4, total becomes 600,000 đ
      expect(find.text('4'), findsOneWidget);
      expect(find.text('600.000 đ'), findsWidgets);
      expect(find.text('1 mặt hàng • Số lượng: 4'), findsOneWidget);
    });

    testWidgets('Swipe to delete reveals confirmation dialog and removing item empties cart', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => _TestSupplierListNotifier([sampleSupplier])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Swipe left on the item card
      await tester.drag(find.byKey(const Key('item_card_prod_01')), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_confirmation_dialog')), findsOneWidget);

      // Confirm delete
      await tester.tap(find.byKey(const Key('btn_confirm_delete')));
      await tester.pumpAndSettle();

      // Cart is now empty
      expect(find.text('Chưa có hàng trong phiếu'), findsOneWidget);
      expect(find.text('0 mặt hàng • Số lượng: 0'), findsOneWidget);
    });

    testWidgets('Tapping "Lưu tạm" invokes SaveStockInDraftUseCase and displays snackbar', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => _TestSupplierListNotifier([sampleSupplier])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_save_draft')));
      await tester.pumpAndSettle();

      expect(mockRepo.savedDrafts.length, 1);
      expect(mockRepo.savedDrafts.first.status, 'draft');
      expect(find.text('Đã lưu phiếu tạm'), findsOneWidget);
    });

    testWidgets('Exit dialog choice "Ở lại" dismisses dialog and keeps user on page', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => _TestSupplierListNotifier([sampleSupplier])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap Close (X) button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('exit_receipt_dialog')), findsOneWidget);

      // Tap "Ở lại"
      await tester.tap(find.byKey(const Key('dialog_choice_stay')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('exit_receipt_dialog')), findsNothing);
      expect(find.text('Phiếu PN_DRAFT_99'), findsOneWidget);
    });

    testWidgets('Exit dialog choice "Lưu tạm" saves draft to repository and exits', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: ImportInventoryPage(initialReceipt: sampleDraft),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => _TestSupplierListNotifier([sampleSupplier])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap Close (X) button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Tap "Lưu tạm" in dialog
      await tester.tap(find.byKey(const Key('dialog_choice_draft')));
      await tester.pumpAndSettle();

      expect(mockRepo.savedDrafts.length, 1);
      expect(mockRepo.savedDrafts.first.status, 'draft');
    });

    testWidgets('Staff and Supervisor see locked store badge', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => _TestSupplierListNotifier([sampleSupplier])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chi nhánh nhập: Chi nhánh Đông Thắng (Cố định)'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('Admin sees unlocked store badge with storefront icon', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => _TestSupplierListNotifier([sampleSupplier])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
            stockInReceiptRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chi nhánh nhập: Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.textContaining('(Cố định)'), findsNothing);
      expect(find.byIcon(Icons.storefront), findsOneWidget);
    });
  });
}
