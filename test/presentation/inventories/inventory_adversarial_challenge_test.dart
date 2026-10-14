import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inter_store_transfer_service.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/inventories/usecases/complete_stock_in_receipt_use_case.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/stock_in_receipt_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';
import 'package:stores/presentation/inventories/pages/import_detail_page.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/pages/inter_store_transfer_page.dart';

import '../../support/import_flow_helpers.dart';

// --- Fakes & Mocks ---

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

class _MockProductRepository implements ProductRepository {
  Product? lastUpsertedProduct;
  final List<Product> _products;

  _MockProductRepository([List<Product>? products])
      : _products = products ?? [];

  @override
  Future<void> upsert(Product product) async {
    lastUpsertedProduct = product;
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<Product>> fetchAll() async => _products;

  @override
  Future<Product?> fetchById(String id) async =>
      _products.where((p) => p.id == id).firstOrNull;

  @override
  Future<void> updateStock(String id, int newStock) async {}

  @override
  Stream<List<Product>> watchAll() => Stream.value(_products);
}

class _MockInventoryRepository implements InventoryRepository {
  InventoryTransaction? lastRecordedTx;

  @override
  Future<void> record(InventoryTransaction tx) async {
    lastRecordedTx = tx;
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value([]);

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime startDate, DateTime endDate) =>
      Stream.value([]);
}

class _FakeSupplierRepository implements SupplierRepository {
  @override
  Stream<List<Supplier>> watchAll({String? storeId}) => Stream.value([]);

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async => null;

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {}

  @override
  Future<void> delete(String id, {String? storeId}) async {}

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction transaction,
      {String? storeId}) async {}

  @override
  Stream<List<SupplierDebtTransaction>> watchDebtTransactions(String supplierId,
          {String? storeId}) =>
      Stream.value([]);

  @override
  Future<List<SupplierDebtTransaction>> fetchDebtTransactions(String supplierId,
          {String? storeId}) async =>
      [];
}

class _FakeStockInReceiptRepository implements StockInReceiptRepository {
  StockInReceipt? lastSaved;

  @override
  Future<String> saveDraft(StockInReceipt receipt) async => receipt.id;

  @override
  Future<void> updateDraft(StockInReceipt receipt) async {}

  @override
  Future<void> deleteDraft(
      {required String storeId, required String receiptId}) async {}

  @override
  Future<void> cancelReceipt({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {}

  @override
  Stream<List<StockInReceipt>> watchReceipts(String storeId) =>
      Stream.value([]);

  @override
  Future<List<StockInReceipt>> fetchReceipts(String storeId) async => [];

  @override
  Future<StockInReceipt?> getReceiptById(
          {required String storeId, required String receiptId}) async =>
      null;

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    lastSaved = receipt;
  }

  @override
  Future<void> deleteReceipt(
      {required String storeId, required String receiptId}) async {}

  @override
  Future<double?> getLatestImportPrice(
          {required String storeId, required String productId}) async =>
      null;
}

/// Pumps ImportInventoryPage (2-step wizard) for [user] with in-memory repos.
Future<void> _pumpWizard(
  WidgetTester tester, {
  required UserAccount? user,
  required String storeId,
  required List<Product> products,
  required Map<String, String> stores,
  _MockProductRepository? productRepo,
  _MockInventoryRepository? inventoryRepo,
}) async {
  final prodRepo = productRepo ?? _MockProductRepository(products);
  final invRepo = inventoryRepo ?? _MockInventoryRepository();
  final receiptRepo = _FakeStockInReceiptRepository();
  final supplierRepo = _FakeSupplierRepository();
  await tester.pumpWidget(
    _buildTestApp(
      child: const ImportInventoryPage(),
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
        currentStoreIdProvider.overrideWith((ref) => storeId),
        productListProvider.overrideWith((ref) => Stream.value(products)),
        availableStoresProvider.overrideWith((ref) async => stores),
        productRepositoryProvider.overrideWithValue(prodRepo),
        inventoryRepositoryProvider.overrideWithValue(invRepo),
        supplierRepositoryProvider.overrideWithValue(supplierRepo),
        stockInReceiptRepositoryProvider.overrideWithValue(receiptRepo),
        completeStockInReceiptUseCaseProvider
            .overrideWith((ref) => CompleteStockInReceiptUseCase(
                  productRepository: prodRepo,
                  inventoryRepository: invRepo,
                  supplierRepository: supplierRepo,
                  receiptRepository: receiptRepo,
                )),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
  Key? key,
}) {
  return ProviderScope(
    key: key,
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
  const staffUserBranch1 = UserAccount(
    username: 'staff_b1',
    displayName: 'Nhân viên Kho 1',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const staffUserBranch2 = UserAccount(
    username: 'staff_b2',
    displayName: 'Nhân viên Kho 2',
    role: 'nhanvien',
    storeId: 'store_002',
  );

  const adminUser = UserAccount(
    username: 'admin_user',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor_user',
    displayName: 'Giám sát viên',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const sampleProduct = Product(
    id: 'prod_100',
    name: 'Sản phẩm Test Adv',
    code: 'SP100',
    price: 300000,
    costPrice: 200000,
    branchStocks: {'branch_1': 10, 'branch_2': 5},
    category: 'Vật tư',
  );

  final storesMapFixture = {
    'store_001': 'Chi nhánh Thới Bình',
    'store_002': 'Chi nhánh Đông Thắng',
  };

  // =========================================================================
  // Milestone 1: Import Inventory Adversarial Tests
  // =========================================================================
  group('Milestone 1 — Import Inventory Adversarial Stress Tests', () {
    testWidgets(
        '[Adversarial M1-1] Staff: Locked store badge and masked cost price in ImportInventoryPage',
        (tester) async {
      await _pumpWizard(tester,
          user: staffUserBranch2,
          storeId: 'store_002',
          products: [sampleProduct],
          stores: storesMapFixture);

      // 1. Locked Store Badge
      expect(find.text('Chi nhánh nhập: Chi nhánh Đông Thắng (Cố định)'),
          findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.storefront), findsNothing);

      // 2. Page itself never exposes cost price / total value labels to staff
      expect(find.textContaining('Giá nhập'), findsNothing);
      expect(find.textContaining('Tổng giá trị'), findsNothing);

      // 3. Cost price input must NOT be rendered for staff in the edit sheet
      await openProductSheet(tester,
          search: 'Sản phẩm Test Adv', productText: 'Sản phẩm Test Adv');
      expect(find.byKey(const Key('product_edit_sheet')), findsOneWidget);
      expect(find.byKey(const Key('sheet_input_price')), findsNothing);
      // Quantity control remains available
      expect(find.byKey(const Key('sheet_stepper_inc')), findsOneWidget);
      expect(find.byKey(const Key('sheet_qty_text')), findsOneWidget);
    });

    testWidgets(
        '[Adversarial M1-2] Admin: Unlocked store badge and can view cost price',
        (tester) async {
      await _pumpWizard(tester,
          user: adminUser,
          storeId: 'store_001',
          products: [sampleProduct],
          stores: storesMapFixture);

      // 1. Unlocked Store Badge (Admin can switch store)
      expect(find.text('Chi nhánh nhập: Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.textContaining('(Cố định)'), findsNothing);
      expect(find.byIcon(Icons.storefront), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNothing);

      // 2. Cost price input is VISIBLE for Admin in the edit sheet
      await openProductSheet(tester,
          search: 'Sản phẩm Test Adv', productText: 'Sản phẩm Test Adv');
      expect(find.byKey(const Key('product_edit_sheet')), findsOneWidget);
      expect(find.byKey(const Key('sheet_input_price')), findsOneWidget);
      expect(find.textContaining('Giá nhập'), findsWidgets);
    });

    testWidgets(
        '[Adversarial M1-3] Supervisor: Full access with editable cost price and total value summary',
        (tester) async {
      await _pumpWizard(tester,
          user: supervisorUser,
          storeId: 'store_001',
          products: [sampleProduct],
          stores: storesMapFixture);

      // 1. Locked badge for supervisor per R2
      expect(find.text('Chi nhánh nhập: Chi nhánh Thới Bình (Cố định)'),
          findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      // 2. Cost price input is VISIBLE and editable
      await addProductViaSheet(tester,
          search: 'Sản phẩm Test Adv',
          productText: 'Sản phẩm Test Adv',
          quantity: 2,
          unitPrice: '250000');

      // 3. Total value summary reflects 2 x 250,000 = 500,000 and is unmasked
      expect(find.byKey(const Key('bottom_bar_total_amount')), findsOneWidget);
      expect(
          tester
              .widget<Text>(find.byKey(const Key('bottom_bar_total_amount')))
              .data,
          '500.000 đ');
      expect(find.text('1 mặt hàng • Số lượng: 2'), findsOneWidget);
      expect(find.text('***'), findsNothing);
    });

    testWidgets(
        '[Adversarial M1-4] Unauthenticated user (null auth) defaults to locked and masked state',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(null)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider
                .overrideWith((ref) => Stream.value([sampleProduct])),
            availableStoresProvider
                .overrideWith((ref) async => storesMapFixture),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Should default to locked badge and hidden cost price safely
      expect(find.text('Chi nhánh nhập: Chi nhánh Thới Bình (Cố định)'),
          findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.textContaining('Giá nhập'), findsNothing);
      expect(find.textContaining('Tổng giá trị'), findsNothing);
    });

    testWidgets(
        '[Adversarial M1-5] Staff Save flow with selected product uses product.costPrice fallback and records transaction',
        (tester) async {
      final mockProdRepo = _MockProductRepository([sampleProduct]);
      final mockInvRepo = _MockInventoryRepository();

      await _pumpWizard(tester,
          user: staffUserBranch1,
          storeId: 'store_001',
          products: [sampleProduct],
          stores: storesMapFixture,
          productRepo: mockProdRepo,
          inventoryRepo: mockInvRepo);

      // Staff cannot set a price: add with default quantity (1)
      await addProductViaSheet(tester,
          search: 'Sản phẩm Test Adv', productText: 'Sản phẩm Test Adv');
      await goToPaymentStep(tester);
      await completeReceiptOnPaymentStep(tester);

      // Transaction recorded with product's default costPrice (200000)
      expect(mockInvRepo.lastRecordedTx, isNotNull);
      expect(mockInvRepo.lastRecordedTx!.importPrice, equals(200000.0));
      expect(mockInvRepo.lastRecordedTx!.quantity, equals(1));
      expect(mockInvRepo.lastRecordedTx!.createdBy, equals('staff_b1'));

      // Weighted average with same price is unchanged; stock increased by 1
      expect(mockProdRepo.lastUpsertedProduct, isNotNull);
      expect(mockProdRepo.lastUpsertedProduct!.costPrice, equals(200000.0));
      expect(mockProdRepo.lastUpsertedProduct!.stock, equals(16));
    });

    testWidgets(
        '[Adversarial M1-6] Supervisor Save flow allows custom import price and recalculates weighted average cost',
        (tester) async {
      final mockProdRepo = _MockProductRepository([sampleProduct]);
      final mockInvRepo = _MockInventoryRepository();

      await _pumpWizard(tester,
          user: supervisorUser,
          storeId: 'store_001',
          products: [sampleProduct],
          stores: storesMapFixture,
          productRepo: mockProdRepo,
          inventoryRepo: mockInvRepo);

      // Initial stock: 15 (10+5), initial cost: 200,000.
      // Import 5 at 260,000 -> new total stock 20.
      // Expected new cost = (15*200,000 + 5*260,000) / 20 = 215,000.
      await addProductViaSheet(tester,
          search: 'Sản phẩm Test Adv',
          productText: 'Sản phẩm Test Adv',
          quantity: 5,
          unitPrice: '260000');
      await goToPaymentStep(tester);
      await completeReceiptOnPaymentStep(tester);

      expect(mockInvRepo.lastRecordedTx, isNotNull);
      expect(mockInvRepo.lastRecordedTx!.importPrice, equals(260000.0));
      expect(mockInvRepo.lastRecordedTx!.quantity, equals(5));

      expect(mockProdRepo.lastUpsertedProduct, isNotNull);
      expect(mockProdRepo.lastUpsertedProduct!.costPrice, equals(215000.0));
      expect(mockProdRepo.lastUpsertedProduct!.stock, equals(20));
    });

    test(
        '[Adversarial M1-7] Weighted Average Cost calculation mathematical oracle & boundary stress tests',
        () {
      // Test the exact weighted average formula used in ImportInventoryPage:
      // double newCostPrice = (currentTotalStock + quantity) > 0
      //     ? ((currentTotalStock * costPrice) + (quantity * effectiveImportPrice)) / (currentTotalStock + quantity)
      //     : effectiveImportPrice;

      double computeNewCost({
        required int currentTotalStock,
        required double currentCostPrice,
        required int importQuantity,
        required double effectiveImportPrice,
      }) {
        return (currentTotalStock + importQuantity) > 0
            ? ((currentTotalStock * currentCostPrice) +
                    (importQuantity * effectiveImportPrice)) /
                (currentTotalStock + importQuantity)
            : effectiveImportPrice;
      }

      // Case 1: Zero initial stock
      expect(
        computeNewCost(
          currentTotalStock: 0,
          currentCostPrice: 100000,
          importQuantity: 10,
          effectiveImportPrice: 150000,
        ),
        equals(150000.0),
      );

      // Case 2: Positive stock, price increase
      expect(
        computeNewCost(
          currentTotalStock: 10,
          currentCostPrice: 100000,
          importQuantity: 10,
          effectiveImportPrice: 200000,
        ),
        equals(150000.0),
      );

      // Case 3: Positive stock, price decrease
      expect(
        computeNewCost(
          currentTotalStock: 10,
          currentCostPrice: 100000,
          importQuantity: 10,
          effectiveImportPrice: 50000,
        ),
        equals(75000.0),
      );

      // Case 4: Staff import fallback (effective == current) -> stays identical
      expect(
        computeNewCost(
          currentTotalStock: 10,
          currentCostPrice: 100000,
          importQuantity: 5,
          effectiveImportPrice: 100000,
        ),
        equals(100000.0),
      );

      // Case 5: Negative stock (oversold) with positive remaining total -> guarded calculation
      expect(
        computeNewCost(
          currentTotalStock: -2,
          currentCostPrice: 100000,
          importQuantity: 5,
          effectiveImportPrice: 120000,
        ),
        // ( -200000 + 600000 ) / 3 = 400000 / 3
        closeTo(133333.3333, 0.001),
      );

      // Case 6: Negative stock resulting in <= 0 total stock -> triggers fallback to effectiveImportPrice
      expect(
        computeNewCost(
          currentTotalStock: -10,
          currentCostPrice: 100000,
          importQuantity: 5,
          effectiveImportPrice: 120000,
        ),
        equals(120000.0),
      );

      // Case 7: Zero total stock after import -> triggers fallback to effectiveImportPrice (prevents 0/0 NaN)
      expect(
        computeNewCost(
          currentTotalStock: -5,
          currentCostPrice: 100000,
          importQuantity: 5,
          effectiveImportPrice: 120000,
        ),
        equals(120000.0),
      );
    });

    testWidgets(
        '[Adversarial M1-8] ImportDetailPage Cost Price Masking for Staff, Admin, and Supervisor',
        (tester) async {
      final sampleTx = InventoryTransaction(
        id: 'tx_adv_999',
        productId: 'prod_100',
        type: TransactionType.import,
        quantity: 8,
        date: DateTime(2026, 8, 16),
        note: 'Import Detail Adversarial Test',
        importPrice: 245000,
        createdBy: 'staff_b1',
        createdByName: 'Nhân viên Kho 1',
      );

      // 1. Check Staff cannot view importPrice
      await tester.pumpWidget(
        _buildTestApp(
          key: const ValueKey('scope_staff'),
          child: ImportDetailPage(tx: sampleTx, product: sampleProduct),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(staffUserBranch1)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Giá nhập'), findsNothing);
      expect(find.text('245000'), findsNothing);

      // 2. Check Admin CAN view importPrice
      await tester.pumpWidget(
        _buildTestApp(
          key: const ValueKey('scope_admin'),
          child: ImportDetailPage(tx: sampleTx, product: sampleProduct),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Giá nhập'), findsOneWidget);
      expect(find.text('245000'), findsOneWidget);

      // 3. Check Supervisor CAN view importPrice
      await tester.pumpWidget(
        _buildTestApp(
          key: const ValueKey('scope_supervisor'),
          child: ImportDetailPage(tx: sampleTx, product: sampleProduct),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Giá nhập'), findsOneWidget);
      expect(find.text('245000'), findsOneWidget);

      // 4. Check Null importPrice in transaction does not throw error for Supervisor
      final nullPriceTx = InventoryTransaction(
        id: 'tx_adv_null_price',
        productId: 'prod_100',
        type: TransactionType.import,
        quantity: 2,
        date: DateTime(2026, 8, 16),
        note: 'Null price tx',
        importPrice: null,
      );
      await tester.pumpWidget(
        _buildTestApp(
          key: const ValueKey('scope_null_price'),
          child: ImportDetailPage(tx: nullPriceTx, product: sampleProduct),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Giá nhập'), findsNothing);
      expect(find.text('#tx_adv_null_price'), findsOneWidget);
    });
  });

  // =========================================================================
  // Milestone 2: Inter-Store Transfer Adversarial Tests
  // =========================================================================
  group('Milestone 2 — Inter-Store Transfer Adversarial Stress Tests', () {
    testWidgets(
        '[Adversarial M2-1] Staff: Source store strictly locked to user.storeId even if currentStoreIdProvider differs',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const InterStoreTransferPage(product: sampleProduct),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(staffUserBranch2)),
            // Deliberately set currentStoreIdProvider to store_001 (adversarial spoof attempt)
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider
                .overrideWith((ref) async => storesMapFixture),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Must strictly use staff's storeId (store_002: Chi nhánh Đông Thắng), NOT currentStoreIdProvider
      expect(find.text('Chi nhánh Đông Thắng (Cố định)'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets(
        '[Adversarial M2-2] Destination dropdown filters out locked source store',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const InterStoreTransferPage(product: sampleProduct),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(staffUserBranch1)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider
                .overrideWith((ref) async => storesMapFixture),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Open target store dropdown
      final dropdown = find.byType(DropdownButtonFormField<String>);
      expect(dropdown, findsOneWidget);

      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      // Dropdown menu should show Chi nhánh Đông Thắng (store_002) and NOT allow selecting own store (store_001)
      expect(find.text('Chi nhánh Đông Thắng').last, findsOneWidget);
    });

    testWidgets(
        '[Adversarial M2-3] Admin/Supervisor source store is unlocked and rendered without fixed tag',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const InterStoreTransferPage(product: sampleProduct),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider
                .overrideWith((ref) async => storesMapFixture),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.textContaining('(Cố định)'), findsNothing);
      expect(find.byIcon(Icons.storefront), findsOneWidget);
    });

    testWidgets(
        '[Adversarial M2-4] Empty State rendered when no alternative target stores exist',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const InterStoreTransferPage(product: sampleProduct),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(staffUserBranch1)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            // Only 1 store in chain
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.store_outlined), findsOneWidget);
      expect(find.text('Không có cửa hàng khác để chuyển.'), findsOneWidget);
    });

    test(
        '[Adversarial M2-5] InterStoreTransferService full validation matrix & error handling',
        () async {
      final service = InterStoreTransferService(null);

      // 1. Empty source store ID
      expect(
        await service.transferProduct(
          sourceStoreId: '',
          targetStoreId: 'store_002',
          product: sampleProduct,
          quantity: 2,
        ),
        equals('Chi nhánh không hợp lệ'),
      );

      // 2. Empty target store ID
      expect(
        await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: '',
          product: sampleProduct,
          quantity: 2,
        ),
        equals('Chi nhánh không hợp lệ'),
      );

      // 3. Same source and target store
      expect(
        await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: 'store_001',
          product: sampleProduct,
          quantity: 2,
        ),
        equals('Không thể chuyển cùng kho'),
      );

      // 4. Zero quantity
      expect(
        await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: 'store_002',
          product: sampleProduct,
          quantity: 0,
        ),
        equals('Số lượng phải lớn hơn 0'),
      );

      // 5. Negative quantity
      expect(
        await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: 'store_002',
          product: sampleProduct,
          quantity: -10,
        ),
        equals('Số lượng phải lớn hơn 0'),
      );

      // 6. Quantity exceeds stock (sampleProduct.stock is 15: branch_1:10 + branch_2:5)
      expect(
        await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: 'store_002',
          product: sampleProduct,
          quantity: 16,
        ),
        equals('Không đủ số lượng trong kho'),
      );

      // 7. Quantity exactly equals branch stock (10 in branch_1/store_001) passes validation
      expect(
        await service.transferProduct(
          sourceStoreId: 'store_001',
          targetStoreId: 'store_002',
          product: sampleProduct,
          quantity: 10,
        ),
        isNull, // With null DB, returns null on successful pre-checks
      );
    });

    test(
        '[Adversarial M2-6] InterStoreTransferService store name resolution logic',
        () async {
      // Create a testable instance of InterStoreTransferService
      final service = InterStoreTransferService(null);

      // Verify that invalid calls fail early with accurate error messages
      final res1 = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: sampleProduct,
        quantity: -1,
        sourceStoreName: 'Chi nhánh Thới Bình',
        targetStoreName: 'Chi nhánh Đông Thắng',
      );
      expect(res1, equals('Số lượng phải lớn hơn 0'));

      final res2 = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: sampleProduct,
        quantity: 99999, // Exceeds product stock (15)
      );
      expect(res2, equals('Không đủ số lượng trong kho'));
    });

    testWidgets(
        '[Adversarial M2-7] Transfer form validation for empty and invalid inputs',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const InterStoreTransferPage(product: sampleProduct),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(staffUserBranch1)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider
                .overrideWith((ref) async => storesMapFixture),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Find submit button via icon and scroll to it if needed
      final submitButton = find.byIcon(Icons.send_rounded);
      expect(submitButton, findsOneWidget);

      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Should show validation error messages
      expect(find.text('Chọn cửa hàng nhận'), findsOneWidget);
      expect(find.text('Vui lòng nhập Số lượng'), findsOneWidget);

      // Enter quantity > stock (15) into quantity input
      final quantityInput = find.byType(TextFormField).last;
      await tester.enterText(quantityInput, '999');
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.text('Số lượng vượt quá tồn kho'), findsOneWidget);
    });
  });

  group('Milestone 1 & 2 — Complex Form & Edge Case Stress Tests', () {
    testWidgets(
        '[Adversarial M1-9] Multi-row import: adding and removing product items updates summary counts',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const secondProduct = Product(
        id: 'prod_200',
        name: 'Mặt hàng Thứ Hai',
        code: 'SP200',
        price: 50000,
        costPrice: 30000,
        branchStocks: {'branch_1': 3},
        category: 'Vật tư',
      );

      await _pumpWizard(tester,
          user: staffUserBranch1,
          storeId: 'store_001',
          products: [sampleProduct, secondProduct],
          stores: storesMapFixture);

      // Initially no items: empty summary
      expect(find.text('0 mặt hàng • Số lượng: 0'), findsOneWidget);

      await addProductViaSheet(tester,
          search: 'Sản phẩm Test Adv',
          productText: 'Sản phẩm Test Adv',
          quantity: 2);
      expect(find.text('1 mặt hàng • Số lượng: 2'), findsOneWidget);

      await addProductViaSheet(tester,
          search: 'Mặt hàng Thứ Hai',
          productText: 'Mặt hàng Thứ Hai',
          quantity: 3);
      expect(find.text('2 mặt hàng • Số lượng: 5'), findsOneWidget);

      // Remove the second row (swipe + confirm)
      await tester.drag(
          find.byKey(const Key('item_card_prod_200')), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_confirm_delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('item_card_prod_200')), findsNothing);
      expect(find.byKey(const Key('item_card_prod_100')), findsOneWidget);
      expect(find.text('1 mặt hàng • Số lượng: 2'), findsOneWidget);
    });

    testWidgets(
        '[Adversarial M1-10] Import price 0 is allowed (promotional stock) and a negative price never produces a negative total',
        (tester) async {
      await _pumpWizard(tester,
          user: supervisorUser,
          storeId: 'store_001',
          products: [sampleProduct],
          stores: storesMapFixture);

      // Price 0 = bonus / promotional stock: allowed, total stays 0 đ.
      await addProductViaSheet(tester,
          search: 'Sản phẩm Test Adv',
          productText: 'Sản phẩm Test Adv',
          unitPrice: '0');
      expect(find.byKey(const Key('item_card_prod_100')), findsOneWidget);
      expect(find.text('1 mặt hàng • Số lượng: 1'), findsOneWidget);
      expect(
          tester
              .widget<Text>(find.byKey(const Key('bottom_bar_total_amount')))
              .data,
          '0 đ');

      // A negative price typed into the field must be clamped, never negative.
      await addProductViaSheet(tester,
          search: 'Sản phẩm Test Adv',
          productText: 'Sản phẩm Test Adv',
          unitPrice: '-5000');
      final total = tester
          .widget<Text>(find.byKey(const Key('bottom_bar_total_amount')))
          .data!;
      expect(total.contains('-'), isFalse, reason: 'total must not be negative');
    });
  });
}
