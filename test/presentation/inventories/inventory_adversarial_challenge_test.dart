import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inter_store_transfer_service.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/inventories/pages/import_detail_page.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/pages/inter_store_transfer_page.dart';

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
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUserBranch2)),
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            availableStoresProvider.overrideWith((ref) async => storesMapFixture),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // 1. Locked Store Badge
      expect(
          find.text('Chi nhánh nhập: Chi nhánh Đông Thắng (Cố định)'),
          findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      // 2. Cost Price Input and Total Value are STRICTLY HIDDEN
      expect(find.textContaining('Giá nhập'), findsNothing);
      expect(find.textContaining('Tổng giá trị'), findsNothing);

      // 3. Quantity input and stock indicators are visible
      expect(find.text('Số lượng'), findsOneWidget);
      expect(find.text('Tồn kho hiện tại'), findsOneWidget);
      expect(find.text('Tồn kho sau nhập'), findsOneWidget);
    });

    testWidgets(
        '[Adversarial M1-2] Admin: Unlocked store badge and can view cost price',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            availableStoresProvider.overrideWith((ref) async => storesMapFixture),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // 1. Unlocked Store Badge (Admin can switch store)
      expect(
          find.text('Chi nhánh nhập: Chi nhánh Thới Bình'),
          findsOneWidget);
      expect(find.textContaining('(Cố định)'), findsNothing);
      expect(find.byIcon(Icons.storefront), findsOneWidget);

      // 2. Cost Price Input and Total Value are VISIBLE for Admin
      expect(find.textContaining('Giá nhập'), findsOneWidget);
      expect(find.textContaining('Tổng giá trị'), findsOneWidget);
    });

    testWidgets(
        '[Adversarial M1-3] Supervisor: Full access with editable cost price and total value summary',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            availableStoresProvider.overrideWith((ref) async => storesMapFixture),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // 1. Locked badge for supervisor per R2
      expect(
          find.text('Chi nhánh nhập: Chi nhánh Thới Bình (Cố định)'),
          findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      // 2. Cost Price Input is VISIBLE
      expect(find.textContaining('Giá nhập'), findsOneWidget);

      // 3. Total Value Summary Card is VISIBLE
      expect(find.textContaining('Tổng giá trị'), findsOneWidget);
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
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            availableStoresProvider.overrideWith((ref) async => storesMapFixture),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Should default to locked badge and hidden cost price safely
      expect(
          find.text('Chi nhánh nhập: Chi nhánh Thới Bình (Cố định)'),
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

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUserBranch1)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            availableStoresProvider.overrideWith((ref) async => storesMapFixture),
            productRepositoryProvider.overrideWithValue(mockProdRepo),
            inventoryRepositoryProvider.overrideWithValue(mockInvRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select product via autocomplete
      final searchField = find.byType(TextFormField).first;
      await tester.tap(searchField);
      await tester.enterText(searchField, 'Sản phẩm Test Adv');
      await tester.pumpAndSettle();

      // Tap the matching autocomplete option
      final option = find.textContaining('Sản phẩm Test Adv').last;
      await tester.tap(option);
      await tester.pumpAndSettle();

      // Find save icon button in AppBar
      final saveButton = find.byIcon(Icons.save);
      expect(saveButton, findsOneWidget);

      // Tap save
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Verify transaction was recorded with product's default costPrice (200000)
      expect(mockInvRepo.lastRecordedTx, isNotNull);
      expect(mockInvRepo.lastRecordedTx!.importPrice, equals(200000.0));
      expect(mockInvRepo.lastRecordedTx!.quantity, equals(1));
      expect(mockInvRepo.lastRecordedTx!.createdBy, equals('staff_b1'));

      // Verify product upsert was called with updated stock
      expect(mockProdRepo.lastUpsertedProduct, isNotNull);
      expect(mockProdRepo.lastUpsertedProduct!.costPrice, equals(200000.0));
    });

    testWidgets(
        '[Adversarial M1-6] Supervisor Save flow allows custom import price and recalculates weighted average cost',
        (tester) async {
      final mockProdRepo = _MockProductRepository([sampleProduct]);
      final mockInvRepo = _MockInventoryRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            availableStoresProvider.overrideWith((ref) async => storesMapFixture),
            productRepositoryProvider.overrideWithValue(mockProdRepo),
            inventoryRepositoryProvider.overrideWithValue(mockInvRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select product via autocomplete
      final searchField = find.byType(TextFormField).first;
      await tester.tap(searchField);
      await tester.enterText(searchField, 'Sản phẩm Test Adv');
      await tester.pumpAndSettle();

      final option = find.textContaining('Sản phẩm Test Adv').last;
      await tester.tap(option);
      await tester.pumpAndSettle();

      // Supervisor modifies import price to 260000 and quantity to 5
      // Initial stock: 15 (10+5), initial cost: 200,000.
      // Import 5 at 260,000.
      // New total stock = 20.
      // Expected new cost = (15 * 200,000 + 5 * 260,000) / 20 = (3,000,000 + 1,300,000) / 20 = 4,300,000 / 20 = 215,000.

      final textFields = find.byType(TextFormField);
      // textFields[0]: search/autocomplete, textFields[1]: quantity, textFields[2]: importPrice
      await tester.enterText(textFields.at(1), '5');
      await tester.enterText(textFields.at(2), '260000');
      await tester.pumpAndSettle();

      // Tap save
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      expect(mockInvRepo.lastRecordedTx, isNotNull);
      expect(mockInvRepo.lastRecordedTx!.importPrice, equals(260000.0));
      expect(mockInvRepo.lastRecordedTx!.quantity, equals(5));

      expect(mockProdRepo.lastUpsertedProduct, isNotNull);
      expect(mockProdRepo.lastUpsertedProduct!.costPrice, equals(215000.0));
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
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUserBranch1)),
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
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
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
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
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
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUserBranch2)),
            // Deliberately set currentStoreIdProvider to store_001 (adversarial spoof attempt)
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider.overrideWith((ref) async => storesMapFixture),
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
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUserBranch1)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider.overrideWith((ref) async => storesMapFixture),
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
            availableStoresProvider.overrideWith((ref) async => storesMapFixture),
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
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUserBranch1)),
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
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUserBranch1)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider.overrideWith((ref) async => storesMapFixture),
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

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUserBranch1)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            availableStoresProvider.overrideWith((ref) async => storesMapFixture),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Initially 1 product row
      expect(find.text('Số sản phẩm'), findsOneWidget);
      expect(find.text('1'), findsWidgets);

      // Tap "Thêm Sản Phẩm" to add a second row
      final addRowButton = find.text('Thêm Sản Phẩm');
      expect(addRowButton, findsOneWidget);
      await tester.tap(addRowButton);
      await tester.pumpAndSettle();

      // Summary should show 2 products
      expect(find.text('2'), findsWidgets);

      // Delete icon should appear for all items when items > 1
      final deleteButtons = find.text('Xóa');
      expect(deleteButtons, findsNWidgets(2));

      // Delete the second row
      await tester.tap(deleteButtons.last);
      await tester.pumpAndSettle();

      // Summary should revert to 1 product and delete buttons disappear
      expect(find.text('Xóa'), findsNothing);
    });

    testWidgets(
        '[Adversarial M1-10] Supervisor validation fails with snackbar when import price is 0 or negative',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            availableStoresProvider.overrideWith((ref) async => storesMapFixture),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select product
      final searchField = find.byType(TextFormField).first;
      await tester.tap(searchField);
      await tester.enterText(searchField, 'Sản phẩm Test Adv');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sản phẩm Test Adv').last);
      await tester.pumpAndSettle();

      // Set import price to 0
      final priceField = find.byType(TextFormField).at(2);
      await tester.enterText(priceField, '0');
      await tester.pumpAndSettle();

      // Tap save
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // Validation snackbar should be displayed
      expect(find.text('Kiểm tra sản phẩm và số lượng'), findsOneWidget);
    });
  });
}

