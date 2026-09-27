import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';
import 'package:stores/presentation/inventories/widgets/cancel_stock_in_receipt_dialog.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_receipt_detail_bottom_sheet.dart';

import '../support/firebase_test_harness.dart';

// ============================================================================
// IN-MEMORY FAKES FOR EMPIRICAL CHALLENGER TESTING
// ============================================================================

class _InMemoryProductRepo implements ProductRepository {
  final Map<String, Product> products = {};
  int upsertCalls = 0;

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Future<void> upsert(Product product) async {
    upsertCalls++;
    products[product.id] = product;
  }

  @override
  Future<void> delete(String id) async {
    products.remove(id);
  }

  @override
  Future<void> updateStock(String id, int newStock) async {
    final p = products[id];
    if (p != null) {
      products[id] = p.copyWith(branchStocks: {'store_001': newStock});
    }
  }

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InMemoryInventoryRepo implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];
  int recordCalls = 0;

  @override
  Future<void> record(InventoryTransaction tx) async {
    recordCalls++;
    transactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(transactions.where((t) => t.productId == productId).toList());

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(DateTime start, DateTime end) =>
      Stream.value(transactions.where((t) => t.type == TransactionType.import).toList());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InMemorySupplierRepo implements SupplierRepository {
  final Map<String, Supplier> suppliers = {};
  final List<SupplierDebtTransaction> debtTransactions = [];
  int upsertCalls = 0;
  int recordDebtCalls = 0;

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async => suppliers[id];

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    upsertCalls++;
    suppliers[supplier.id] = supplier;
  }

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction tx, {String? storeId}) async {
    recordDebtCalls++;
    debtTransactions.add(tx);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InMemoryStockInReceiptRepo implements StockInReceiptRepository {
  final Map<String, StockInReceipt> receipts = {};
  int cancelReceiptCalls = 0;

  @override
  Future<String> saveDraft(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
    return receipt.id;
  }

  @override
  Future<void> updateDraft(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
  }

  @override
  Future<void> deleteDraft({required String storeId, required String receiptId}) async {
    receipts.remove(receiptId);
  }

  @override
  Future<void> cancelReceipt({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {
    cancelReceiptCalls++;
    final now = DateTime.now();
    receipts[receipt.id] = receipt.copyWith(
      status: 'cancelled',
      cancelReason: reason,
      cancelledAt: now,
      cancelledBy: cancelledBy,
      updatedAt: now,
    );
  }

  @override
  Stream<List<StockInReceipt>> watchReceipts(String storeId) {
    return Stream.value(receipts.values.where((r) => r.storeId == storeId).toList());
  }

  @override
  Future<List<StockInReceipt>> fetchReceipts(String storeId) async {
    return receipts.values.where((r) => r.storeId == storeId).toList();
  }

  @override
  Future<StockInReceipt?> getReceiptById({required String storeId, required String receiptId}) async {
    return receipts[receiptId];
  }

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
  }

  @override
  Future<void> deleteReceipt({required String storeId, required String receiptId}) async {
    receipts.remove(receiptId);
  }

  @override
  Future<double?> getLatestImportPrice({required String storeId, required String productId}) async {
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _FakeSupplierListNotifier extends SupplierListNotifier {
  final List<Supplier> _suppliers;
  _FakeSupplierListNotifier([this._suppliers = const []]);

  @override
  Future<List<Supplier>> build() async => _suppliers;
}

// ============================================================================
// WIDGET TEST HARNESS BUILDER
// ============================================================================

Widget _buildTestApp({
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
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Test accounts across different roles
  const adminAccount = UserAccount(
    username: 'admin_boss',
    displayName: 'Chủ Cửa Hàng (Admin)',
    role: 'admin',
    storeId: 'store_001',
  );

  const ownerAccount = UserAccount(
    username: 'owner_user',
    displayName: 'Chủ Sở Hữu',
    role: 'owner',
    storeId: 'store_001',
  );

  const supervisorAccount = UserAccount(
    username: 'supervisor_lead',
    displayName: 'Cửa Hàng Trưởng',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const giamsatAccount = UserAccount(
    username: 'giamsat_user',
    displayName: 'Giám Sát Viên',
    role: 'giamsat',
    storeId: 'store_001',
  );

  const cuahangtruongAccount = UserAccount(
    username: 'cht_user',
    displayName: 'Cửa Hàng Trưởng Chi Nhánh',
    role: 'cuahangtruong',
    storeId: 'store_002',
  );

  const staffNhanvienAccount = UserAccount(
    username: 'staff_nv',
    displayName: 'Nhân Viên Bán Hàng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const staffWordAccount = UserAccount(
    username: 'staff_word',
    displayName: 'Nhân Viên Kho',
    role: 'staff',
    storeId: 'store_001',
  );

  const cashierAccount = UserAccount(
    username: 'cashier_user',
    displayName: 'Thu Ngân',
    role: 'cashier',
    storeId: 'store_001',
  );

  // Sample Completed Receipt
  final sampleCompletedReceipt = StockInReceipt(
    id: 'rec_m4_challenger_001',
    importCode: 'PN_CHALLENGER_001',
    status: 'completed',
    date: DateTime(2026, 9, 25, 9, 0),
    storeId: 'store_001',
    supplierId: 'sup_challenger_1',
    supplierName: 'Công Ty Dược Đông Á',
    createdBy: 'admin_boss',
    createdByName: 'Chủ Cửa Hàng (Admin)',
    note: 'Nhập lô hàng kháng sinh đợt 1',
    items: const [
      StockInReceiptItem(
        transactionId: 'tx_c_1',
        productId: 'prod_antibiotic_01',
        productName: 'Augmentin 1g',
        productCode: 'AUG1G',
        unit: 'Hộp',
        quantity: 20,
        importPrice: 150000,
      ),
      StockInReceiptItem(
        transactionId: 'tx_c_2',
        productId: 'prod_antibiotic_02',
        productName: 'Klamentin 500mg',
        productCode: 'KLAM500',
        unit: 'Hộp',
        quantity: 15,
        importPrice: 100000,
      ),
    ],
    totalAmount: 4500000,
    discount: 500000, // netPayable = 4,000,000
    paidAmount: 1500000,
    debtAmount: 2500000, // remainingDebt = 2,500,000
  );

  // Sample Draft Receipt
  final sampleDraftReceipt = StockInReceipt(
    id: 'rec_m4_draft_001',
    importCode: 'PN_DRAFT_001',
    status: 'draft',
    date: DateTime(2026, 9, 26, 14, 0),
    storeId: 'store_001',
    supplierId: 'sup_challenger_1',
    items: const [
      StockInReceiptItem(
        transactionId: 'tx_d_1',
        productId: 'prod_antibiotic_01',
        productName: 'Augmentin 1g',
        quantity: 5,
        importPrice: 150000,
      ),
    ],
    totalAmount: 750000,
    paidAmount: 0,
    debtAmount: 750000,
  );

  // Sample Cancelled Receipt
  final sampleCancelledReceipt = StockInReceipt(
    id: 'rec_m4_cancelled_001',
    importCode: 'PN_CANCELLED_001',
    status: 'cancelled',
    date: DateTime(2026, 9, 24, 10, 0),
    storeId: 'store_001',
    supplierId: 'sup_challenger_1',
    supplierName: 'Công Ty Dược Đông Á',
    cancelReason: 'Lô hàng bị rách bao bì và ẩm mốc trong quá trình vận chuyển',
    cancelledAt: DateTime(2026, 9, 24, 11, 30),
    cancelledBy: 'supervisor_lead',
    items: const [
      StockInReceiptItem(
        transactionId: 'tx_x_1',
        productId: 'prod_antibiotic_01',
        productName: 'Augmentin 1g',
        quantity: 10,
        importPrice: 150000,
      ),
    ],
    totalAmount: 1500000,
    paidAmount: 1500000,
    debtAmount: 0,
  );

  const sampleSupplier = Supplier(
    id: 'sup_challenger_1',
    name: 'Công Ty Dược Đông Á',
    phone: '0988776655',
    code: 'DONG_A_PHARMA',
    address: 'Hà Nội, Việt Nam',
    currentDebt: 5000000,
    totalPurchase: 20000000,
  );

  List<Override> buildOverrides({
    UserAccount? user,
    StockInReceiptRepository? receiptRepo,
    CancelStockInReceiptUseCase? cancelUseCase,
    SupplierRepository? supplierRepo,
  }) {
    return [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
      currentStoreIdProvider.overrideWith((ref) => user?.storeId ?? 'store_001'),
      canViewCostPriceProvider.overrideWith((ref) => user?.isAdmin == true || user?.isSupervisor == true),
      supplierListNotifierProvider.overrideWith(() => _FakeSupplierListNotifier([sampleSupplier])),
      if (receiptRepo != null) stockInReceiptRepositoryProvider.overrideWithValue(receiptRepo),
      if (cancelUseCase != null) cancelStockInReceiptUseCaseProvider.overrideWithValue(cancelUseCase),
      if (supplierRepo != null) supplierRepositoryProvider.overrideWithValue(supplierRepo),
    ];
  }

  // ============================================================================
  // TIER 1: RBAC PERMISSION STRESS TESTING
  // ============================================================================

  group('TIER 1: RBAC Permission Stress Testing (Cancel Button Visibility)', () {
    testWidgets('Staff users (nhanvien, staff, cashier) and guest CANNOT see or trigger cancellation button',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final unauthorizedUsers = [
        staffNhanvienAccount,
        staffWordAccount,
        cashierAccount,
        null, // Unauthenticated / Guest
      ];

      for (final user in unauthorizedUsers) {
        await tester.pumpWidget(
          _buildTestApp(
            overrides: buildOverrides(user: user),
            child: StockInReceiptDetailBottomSheet(receipt: sampleCompletedReceipt),
          ),
        );
        await tester.pumpAndSettle();

        // btn_cancel_receipt MUST NOT exist in widget tree
        expect(
          find.byKey(const Key('btn_cancel_receipt')),
          findsNothing,
          reason: 'User $user must not see cancellation button on completed receipt',
        );
        expect(find.text('Hủy phiếu nhập'), findsNothing);

        // Close button must still be available
        expect(find.byKey(const Key('btn_close_detail')), findsOneWidget);
      }
    });

    testWidgets('Admin & Supervisor users (admin, owner, supervisor, giamsat, cuahangtruong) CAN see cancellation button',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authorizedUsers = [
        adminAccount,
        ownerAccount,
        supervisorAccount,
        giamsatAccount,
        cuahangtruongAccount,
      ];

      for (final user in authorizedUsers) {
        await tester.pumpWidget(
          _buildTestApp(
            overrides: buildOverrides(user: user),
            child: StockInReceiptDetailBottomSheet(receipt: sampleCompletedReceipt),
          ),
        );
        await tester.pumpAndSettle();

        // btn_cancel_receipt MUST be visible
        expect(
          find.byKey(const Key('btn_cancel_receipt')),
          findsOneWidget,
          reason: 'Authorized user ${user.username} (${user.role}) must see cancellation button',
        );
        expect(find.text('Hủy phiếu nhập'), findsOneWidget);
      }
    });

    testWidgets('Draft and Cancelled receipts DO NOT show cancellation button, even for Admin and Supervisor',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final user in [adminAccount, supervisorAccount]) {
        // 1. Draft receipt -> No cancel button
        await tester.pumpWidget(
          _buildTestApp(
            overrides: buildOverrides(user: user),
            child: StockInReceiptDetailBottomSheet(receipt: sampleDraftReceipt),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('btn_cancel_receipt')), findsNothing);

        // 2. Cancelled receipt -> No cancel button
        await tester.pumpWidget(
          _buildTestApp(
            overrides: buildOverrides(user: user),
            child: StockInReceiptDetailBottomSheet(receipt: sampleCancelledReceipt),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('btn_cancel_receipt')), findsNothing);
      }
    });
  });

  // ============================================================================
  // TIER 2: CANCELLATION DIALOG VALIDATION & ADVERSARIAL INPUT STRESS TESTING
  // ============================================================================

  group('TIER 2: Cancellation Dialog Validation & Adversarial Inputs', () {
    testWidgets('Empty reason string "" triggers mandatory validation and blocks submission', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool executed = false;

      await tester.pumpWidget(
        _buildTestApp(
          overrides: buildOverrides(user: adminAccount),
          child: CancelStockInReceiptDialog(
            receipt: sampleCompletedReceipt,
            onConfirmCancel: (_) => executed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cancel_receipt_dialog')), findsOneWidget);

      // Confirm with empty text
      await tester.tap(find.byKey(const Key('btn_confirm_cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Vui lòng nhập lý do hủy'), findsOneWidget);
      expect(executed, isFalse, reason: 'Empty reason must block execution');
      expect(find.byKey(const Key('cancel_receipt_dialog')), findsOneWidget);
    });

    testWidgets('Whitespace-only reason ("   \\t\\n  \\r\\n  ") triggers validation and blocks submission',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool executed = false;

      await tester.pumpWidget(
        _buildTestApp(
          overrides: buildOverrides(user: adminAccount),
          child: CancelStockInReceiptDialog(
            receipt: sampleCompletedReceipt,
            onConfirmCancel: (_) => executed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter whitespace-only characters
      await tester.enterText(find.byKey(const Key('input_cancel_reason')), '   \t\n   \r\n   ');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_confirm_cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Vui lòng nhập lý do hủy'), findsOneWidget);
      expect(executed, isFalse, reason: 'Whitespace-only reason must block execution');
      expect(find.byKey(const Key('cancel_receipt_dialog')), findsOneWidget);
    });

    testWidgets('Special characters, emojis, HTML/SQL injection, and long texts PASS validation cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final adversarialReasons = [
        '<script>alert("XSS")</script> & DROP TABLE stock_in_receipts; --',
        'Lô hàng hỏng hóc 💥 📦 ❌ Cần trả gấp cho NCC Đông Á!',
        'Đơn giá sai lệch: 150.000đ -> 120.000đ (thực tế giảm 20%)',
        '   Lý do có khoảng trắng đầu và cuối dòng cần được trim tự động   ',
        'A' * 600, // Very long reason
      ];

      for (final adversarialReason in adversarialReasons) {
        String? submittedReason;

        await tester.pumpWidget(
          _buildTestApp(
            overrides: buildOverrides(user: adminAccount),
            child: CancelStockInReceiptDialog(
              receipt: sampleCompletedReceipt,
              onConfirmCancel: (r) => submittedReason = r,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('input_cancel_reason')), adversarialReason);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_confirm_cancel')));
        await tester.pumpAndSettle();

        expect(find.text('Vui lòng nhập lý do hủy'), findsNothing);
        expect(submittedReason, equals(adversarialReason.trim()));
      }
    });

    testWidgets('Dismissing dialog via "Đóng" button or barrier pop does NOT trigger cancellation', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool executed = false;

      // 1. Dismiss via "Đóng" button
      await tester.pumpWidget(
        _buildTestApp(
          overrides: buildOverrides(user: adminAccount),
          child: CancelStockInReceiptDialog(
            receipt: sampleCompletedReceipt,
            onConfirmCancel: (_) => executed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('input_cancel_reason')), 'Lý do nhập dở dang');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_cancel_dialog_close')));
      await tester.pumpAndSettle();

      expect(executed, isFalse, reason: 'Closing dialog must not confirm cancellation');
      expect(find.byType(CancelStockInReceiptDialog), findsNothing);
    });
  });

  // ============================================================================
  // TIER 3: CANCEL USE CASE & FULL ROLLBACK EMPIRICAL STRESS TESTING
  // ============================================================================

  group('TIER 3: Cancellation Execution & Full Rollback Stress Testing', () {
    late _InMemoryProductRepo productRepo;
    late _InMemoryInventoryRepo inventoryRepo;
    late _InMemorySupplierRepo supplierRepo;
    late _InMemoryStockInReceiptRepo receiptRepo;
    late MockFirebaseDatabase mockDb;
    late CancelStockInReceiptUseCase cancelUseCase;

    setUp(() {
      productRepo = _InMemoryProductRepo();
      inventoryRepo = _InMemoryInventoryRepo();
      supplierRepo = _InMemorySupplierRepo();
      receiptRepo = _InMemoryStockInReceiptRepo();
      mockDb = MockFirebaseDatabase();

      cancelUseCase = CancelStockInReceiptUseCase(
        db: mockDb,
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        supplierRepository: supplierRepo,
        receiptRepository: receiptRepo,
      );
    });

    test('Full stock & debt rollback: updates receipt to cancelled, logs audit fields, rolls back inventory and supplier debt',
        () async {
      // 1. Seed initial data
      const prod1 = Product(
        id: 'prod_antibiotic_01',
        name: 'Augmentin 1g',
        code: 'AUG1G',
        category: 'Kháng sinh',
        costPrice: 150000,
        price: 200000,
        unit: 'Hộp',
        branchStocks: {'store_001': 100, 'branch_1': 100, 'store_002': 20, 'branch_2': 20},
      );

      const prod2 = Product(
        id: 'prod_antibiotic_02',
        name: 'Klamentin 500mg',
        code: 'KLAM500',
        category: 'Kháng sinh',
        costPrice: 100000,
        price: 130000,
        unit: 'Hộp',
        branchStocks: {'store_001': 50, 'branch_1': 50, 'store_002': 10, 'branch_2': 10},
      );

      await productRepo.upsert(prod1);
      await productRepo.upsert(prod2);
      await supplierRepo.upsert(sampleSupplier);
      await receiptRepo.saveReceipt(sampleCompletedReceipt);

      // 2. Execute cancellation
      const cancelReason = 'Hàng không đạt chuẩn chất lượng GSP và bị ẩm vỏ hộp';
      const cancelledBy = 'supervisor_lead';

      await cancelUseCase.execute(
        storeId: 'store_001',
        receipt: sampleCompletedReceipt,
        reason: cancelReason,
        cancelledBy: cancelledBy,
      );

      // 3. Assert Receipt State & Audit Fields
      final updatedReceipt = await receiptRepo.getReceiptById(
        storeId: 'store_001',
        receiptId: sampleCompletedReceipt.id,
      );

      expect(updatedReceipt, isNotNull);
      expect(updatedReceipt!.status, equals('cancelled'));
      expect(updatedReceipt.isCancelled, isTrue);
      expect(updatedReceipt.cancelReason, equals(cancelReason));
      expect(updatedReceipt.cancelledBy, equals(cancelledBy));
      expect(updatedReceipt.cancelledAt, isNotNull);
      expect(
        DateTime.now().difference(updatedReceipt.cancelledAt!).inSeconds.abs(),
        lessThan(5),
      );

      // 4. Assert Product Stock Rollback (store_001 & branch_1 alias)
      final rolledBackProd1 = await productRepo.fetchById('prod_antibiotic_01');
      expect(rolledBackProd1, isNotNull);
      // aug1g had 100 in store_001, receipt had qty: 20 -> rolled back to 80
      expect(rolledBackProd1!.stockInBranch('store_001'), equals(80));
      expect(rolledBackProd1.stockInBranch('branch_1'), equals(80));
      expect(rolledBackProd1.stockInBranch('store_002'), equals(20), reason: 'Other branch must be untouched');

      final rolledBackProd2 = await productRepo.fetchById('prod_antibiotic_02');
      expect(rolledBackProd2, isNotNull);
      // klam500 had 50 in store_001, receipt had qty: 15 -> rolled back to 35
      expect(rolledBackProd2!.stockInBranch('store_001'), equals(35));
      expect(rolledBackProd2.stockInBranch('branch_1'), equals(35));
      expect(rolledBackProd2.stockInBranch('store_002'), equals(10), reason: 'Other branch must be untouched');

      // 5. Assert Reversal Inventory Transactions Recorded
      expect(inventoryRepo.transactions.length, equals(2));
      final revTx1 = inventoryRepo.transactions.firstWhere((t) => t.productId == 'prod_antibiotic_01');
      expect(revTx1.type, equals(TransactionType.export));
      expect(revTx1.quantity, equals(20));
      expect(revTx1.importPrice, equals(150000));
      expect(revTx1.note, contains(cancelReason));
      expect(revTx1.importCode, equals(sampleCompletedReceipt.importCode));

      final revTx2 = inventoryRepo.transactions.firstWhere((t) => t.productId == 'prod_antibiotic_02');
      expect(revTx2.type, equals(TransactionType.export));
      expect(revTx2.quantity, equals(15));
      expect(revTx2.importPrice, equals(100000));

      // 6. Assert Supplier Debt & Total Purchase Rollback
      final updatedSupplier = await supplierRepo.fetchById('sup_challenger_1');
      expect(updatedSupplier, isNotNull);
      // initial currentDebt: 5,000,000; receipt remainingDebt: 2,500,000 -> 2,500,000
      expect(updatedSupplier!.currentDebt, equals(2500000));
      // initial totalPurchase: 20,000,000; receipt effectiveNetPayable (4,500,000 - 500,000) = 4,000,000 -> 16,000,000
      expect(updatedSupplier.totalPurchase, equals(16000000));

      // 7. Assert Supplier Reversal Debt Transaction
      expect(supplierRepo.debtTransactions.length, equals(1));
      final debtTx = supplierRepo.debtTransactions.first;
      expect(debtTx.supplierId, equals('sup_challenger_1'));
      expect(debtTx.type, equals(SupplierDebtType.adjustment));
      expect(debtTx.amount, equals(-2500000));
      expect(debtTx.remainingDebt, equals(2500000));
      expect(debtTx.referenceCode, equals(sampleCompletedReceipt.importCode));
      expect(debtTx.note, contains(cancelReason));
      expect(debtTx.createdBy, equals(cancelledBy));

      // 8. Assert Multi-Path Atomic RTDB Updates
      expect(mockDb.recorder.hasCalled('update'), isTrue);
      final updateCalls = mockDb.recorder.calls.where((c) => c.method == 'update').toList();
      expect(updateCalls, isNotEmpty);
      final dynamic rawMap = updateCalls.first.value;
      expect(rawMap, isA<Map>());
      final Map updates = rawMap as Map;

      // Check receipt path
      expect(updates.containsKey('stores/store_001/stock_in_receipts/${sampleCompletedReceipt.id}'), isTrue);
      // Check branch stock paths
      expect(updates.containsKey('stores/store_001/products/prod_antibiotic_01/branchStocks'), isTrue);
      expect(updates.containsKey('stores/store_001/products/prod_antibiotic_02/branchStocks'), isTrue);
      // Check supplier debt paths
      expect(updates.containsKey('shared_suppliers/sup_challenger_1/currentDebt'), isTrue);
      expect(updates.containsKey('shared_suppliers/sup_challenger_1/totalPurchase'), isTrue);
    });

    test('Duplicate product items in single receipt are properly aggregated before stock rollback', () async {
      const prodA = Product(
        id: 'prod_multi_line',
        code: 'CON70',
        name: 'Cồn 70 độ 500ml',
        category: 'Y tế',
        costPrice: 20000,
        price: 25000,
        branchStocks: {'store_001': 60, 'branch_1': 60},
      );
      await productRepo.upsert(prodA);

      // Receipt contains prod_multi_line in 2 separate lines: 10 + 15 = 25
      final receiptWithDuplicates = StockInReceipt(
        id: 'rec_multi_001',
        importCode: 'PN_MULTI_001',
        status: 'completed',
        date: DateTime.now(),
        storeId: 'store_001',
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_m1',
            productId: 'prod_multi_line',
            quantity: 10,
            importPrice: 20000,
          ),
          StockInReceiptItem(
            transactionId: 'tx_m2',
            productId: 'prod_multi_line',
            quantity: 15,
            importPrice: 20000,
          ),
        ],
        totalAmount: 500000,
      );

      await cancelUseCase.execute(
        storeId: 'store_001',
        receipt: receiptWithDuplicates,
        reason: 'Hủy phiếu có dòng trùng',
        cancelledBy: 'admin',
      );

      final rolledBack = await productRepo.fetchById('prod_multi_line');
      expect(rolledBack, isNotNull);
      // 60 - (10 + 15) = 35
      expect(rolledBack!.stockInBranch('store_001'), equals(35));
      expect(rolledBack.stockInBranch('branch_1'), equals(35));
    });

    test('Clamping protections: stock and supplier debt never underflow below 0', () async {
      // Underflow scenario: stock in branch is only 5, but receipt has 20 (items sold out)
      const prodLowStock = Product(
        id: 'prod_underflow',
        code: 'N95',
        name: 'Khẩu trang N95',
        category: 'Vật tư',
        costPrice: 50000,
        price: 60000,
        branchStocks: {'store_001': 5, 'branch_1': 5},
      );
      await productRepo.upsert(prodLowStock);

      // Supplier with low debt
      const supLowDebt = Supplier(
        id: 'sup_low_debt',
        code: 'NCC_KT',
        name: 'NCC Khẩu Trang',
        currentDebt: 100000, // less than receipt remaining debt 500,000
        totalPurchase: 200000, // less than receipt net payable 600,000
      );
      await supplierRepo.upsert(supLowDebt);

      final receiptUnderflow = StockInReceipt(
        id: 'rec_underflow_001',
        importCode: 'PN_UNDERFLOW_001',
        status: 'completed',
        date: DateTime.now(),
        storeId: 'store_001',
        supplierId: 'sup_low_debt',
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_u1',
            productId: 'prod_underflow',
            quantity: 20,
            importPrice: 30000,
          ),
        ],
        totalAmount: 600000,
        paidAmount: 100000,
        debtAmount: 500000,
      );

      await cancelUseCase.execute(
        storeId: 'store_001',
        receipt: receiptUnderflow,
        reason: 'Hủy phiếu tồn kho âm',
        cancelledBy: 'admin',
      );

      final rolledBackProd = await productRepo.fetchById('prod_underflow');
      expect(rolledBackProd!.stockInBranch('store_001'), equals(0), reason: 'Stock must be clamped to 0');

      final rolledBackSup = await supplierRepo.fetchById('sup_low_debt');
      expect(rolledBackSup!.currentDebt, equals(0.0), reason: 'Debt must be clamped to 0.0');
      expect(rolledBackSup.totalPurchase, equals(0.0), reason: 'Total purchase must be clamped to 0.0');
    });

    test('Branch 2 (store_002) and branch_2 alias synchronization', () async {
      const prodStore2 = Product(
        id: 'prod_branch_2_item',
        code: 'SP_TB',
        name: 'Sản phẩm Thới Bình',
        category: 'Y tế',
        costPrice: 40000,
        price: 50000,
        branchStocks: {'store_002': 100, 'branch_2': 100, 'store_001': 50, 'branch_1': 50},
      );
      await productRepo.upsert(prodStore2);

      final receiptStore2 = StockInReceipt(
        id: 'rec_b2_001',
        importCode: 'PN_B2_001',
        status: 'completed',
        date: DateTime.now(),
        storeId: 'store_002',
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_b2',
            productId: 'prod_branch_2_item',
            quantity: 40,
            importPrice: 40000,
          ),
        ],
        totalAmount: 1600000,
      );

      await cancelUseCase.execute(
        storeId: 'store_002',
        receipt: receiptStore2,
        reason: 'Hủy phiếu chi nhánh Thới Bình',
        cancelledBy: 'cuahangtruong_02',
      );

      final rolledBack = await productRepo.fetchById('prod_branch_2_item');
      expect(rolledBack!.stockInBranch('store_002'), equals(60));
      expect(rolledBack.stockInBranch('branch_2'), equals(60));
      expect(rolledBack.stockInBranch('store_001'), equals(50), reason: 'Store 1 must remain untouched');
    });

    test('Rejection of invalid states: already cancelled, draft, or empty reason', () async {
      // 1. Empty reason throws ArgumentError
      expect(
        () => cancelUseCase.execute(
          storeId: 'store_001',
          receipt: sampleCompletedReceipt,
          reason: '   ',
          cancelledBy: 'admin',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // 2. Already cancelled receipt throws StateError
      expect(
        () => cancelUseCase.execute(
          storeId: 'store_001',
          receipt: sampleCancelledReceipt,
          reason: 'Hủy lại phiếu đã hủy',
          cancelledBy: 'admin',
        ),
        throwsA(isA<StateError>()),
      );

      // 3. Draft receipt throws StateError
      expect(
        () => cancelUseCase.execute(
          storeId: 'store_001',
          receipt: sampleDraftReceipt,
          reason: 'Hủy phiếu tạm',
          cancelledBy: 'admin',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ============================================================================
  // TIER 4: UI INTEGRATION & CANCELLATION FLOW IN DETAIL SHEET
  // ============================================================================

  group('TIER 4: UI End-to-End Cancellation Flow in Detail Sheet', () {
    testWidgets('Full flow: Admin cancels completed receipt via detail sheet and displays audit feedback',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeCancelUseCase = _FakeCancelStockInReceiptUseCase();

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...buildOverrides(user: adminAccount),
            cancelStockInReceiptUseCaseProvider.overrideWithValue(fakeCancelUseCase),
          ],
          child: StockInReceiptDetailBottomSheet(receipt: sampleCompletedReceipt),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify initial status badge
      expect(find.byKey(const Key('badge_completed')), findsOneWidget);
      expect(find.text('Đã hoàn thành'), findsOneWidget);

      // 2. Tap "Hủy phiếu nhập"
      expect(find.byKey(const Key('btn_cancel_receipt')), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_cancel_receipt')));
      await tester.pumpAndSettle();

      // 3. Modal dialog appears
      expect(find.byKey(const Key('cancel_receipt_dialog')), findsOneWidget);
      expect(find.text('Hủy phiếu nhập kho'), findsOneWidget);

      // 4. Fill in adversarial reason
      const reason = 'Hàng bị hư hỏng do vận chuyển đường bộ & vỡ 3 hộp';
      await tester.enterText(find.byKey(const Key('input_cancel_reason')), reason);
      await tester.pumpAndSettle();

      // 5. Confirm cancellation
      await tester.tap(find.byKey(const Key('btn_confirm_cancel')));
      await tester.pump(); // Pump frame for SnackBar

      // Assert use case executed
      expect(fakeCancelUseCase.executed, isTrue);
      expect(fakeCancelUseCase.cancelledReceiptId, equals(sampleCompletedReceipt.id));
      expect(fakeCancelUseCase.cancelReason, equals(reason));
      expect(fakeCancelUseCase.cancelledBy, equals('admin_boss'));

      // Check success SnackBar
      expect(find.text('Đã hủy phiếu nhập kho thành công'), findsOneWidget);
    });

    testWidgets('Cancelled receipt detail sheet displays audit card (reason, canceller, timestamp) and hides cancel button',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: buildOverrides(user: adminAccount),
          child: StockInReceiptDetailBottomSheet(receipt: sampleCancelledReceipt),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Badge must be "Đã hủy"
      expect(find.byKey(const Key('badge_cancelled')), findsOneWidget);
      expect(find.text('Đã hủy'), findsWidgets);

      // 2. Audit details must be rendered
      expect(find.text('Lý do hủy:'), findsOneWidget);
      expect(find.text(sampleCancelledReceipt.cancelReason!), findsOneWidget);
      expect(find.text('Người hủy:'), findsOneWidget);
      expect(find.text(sampleCancelledReceipt.cancelledBy!), findsOneWidget);
      expect(find.text('Thời gian hủy:'), findsOneWidget);
      final formattedTime = DateFormat('dd/MM/yyyy HH:mm').format(sampleCancelledReceipt.cancelledAt!);
      expect(find.text(formattedTime), findsOneWidget);

      // 3. Cancel button must NOT be present
      expect(find.byKey(const Key('btn_cancel_receipt')), findsNothing);
    });
  });
}

class _FakeCancelStockInReceiptUseCase extends CancelStockInReceiptUseCase {
  bool executed = false;
  String? cancelledStoreId;
  String? cancelledReceiptId;
  String? cancelReason;
  String? cancelledBy;

  _FakeCancelStockInReceiptUseCase()
      : super(
          productRepository: _InMemoryProductRepo(),
          inventoryRepository: _InMemoryInventoryRepo(),
          supplierRepository: _InMemorySupplierRepo(),
          receiptRepository: _InMemoryStockInReceiptRepo(),
        );

  @override
  Future<void> execute({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {
    executed = true;
    cancelledStoreId = storeId;
    cancelledReceiptId = receipt.id;
    cancelReason = reason;
    this.cancelledBy = cancelledBy;
  }
}
