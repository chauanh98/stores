import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/product_unit.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';

class _FakeProductRepository extends Fake implements ProductRepository {
  Product? lastUpsertedProduct;
  final List<Product> upsertHistory = [];

  @override
  Future<void> upsert(Product product) async {
    lastUpsertedProduct = product;
    upsertHistory.add(product);
  }
}

class _FakeInventoryRepository extends Fake implements InventoryRepository {
  final List<InventoryTransaction> recordedTransactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async {
    recordedTransactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(recordedTransactions);
}

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

final _defaultBranches = [
  const Branch('store_001', 'Chi nhánh Đông Thắng'),
  const Branch('store_002', 'Chi nhánh Thới Bình'),
];

Widget _buildChallengerM2App({
  required Widget child,
  required String storeId,
  List<Branch>? branches,
  Map<String, String>? availableStores,
  UserAccount? user,
  ProductRepository? productRepo,
  InventoryRepository? inventoryRepo,
  List<Product>? products,
  List<InventoryTransaction>? transactions,
}) {
  final testUser = user ??
      const UserAccount(
        username: 'supervisor_adv',
        displayName: 'Giám Sát Viên Adversarial',
        role: 'supervisor',
        storeId: 'store_001',
      );

  final repoProduct = productRepo ?? _FakeProductRepository();
  final repoInventory = inventoryRepo ?? _FakeInventoryRepository();

  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
      currentStoreIdProvider.overrideWithValue(storeId),
      branchesProvider.overrideWithValue(branches ?? _defaultBranches),
      availableStoresProvider.overrideWith((ref) async =>
          availableStores ??
          {
            'store_001': 'Chi nhánh Đông Thắng',
            'store_002': 'Chi nhánh Thới Bình',
          }),
      productRepositoryProvider.overrideWithValue(repoProduct),
      inventoryRepositoryProvider.overrideWithValue(repoInventory),
      if (products != null)
        productListProvider.overrideWith((ref) => Stream.value(products)),
      if (transactions != null)
        transactionsByProductProvider(
                products != null && products.isNotEmpty ? products.first.id : '')
            .overrideWith((ref) => Stream.value(transactions)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleProduct = Product(
    id: 'prod_adv_m2_01',
    name: 'Bia Tiger Crystal 330ml',
    code: 'TIG01',
    barcode: '893482222001',
    brand: 'Heineken',
    price: 18000,
    costPrice: 13500,
    branchStocks: {'store_001': 50, 'store_002': 30},
    category: 'Đồ uống',
    category3Levels: 'Bách hóa >> Đồ uống >> Bia',
    unit: 'Lon',
    description: 'Bia Tiger Crystal lon 330ml',
    minStock: 10,
    maxStock: 200,
    noteTemplate: 'Hàng dễ vỡ',
    components: 'Không có',
    units: [
      ProductUnit(
        id: 'unit_loc6',
        unitName: 'Lốc (6 lon)',
        conversionRate: 6,
        price: 105000,
        costPrice: 80000,
        isDirectSale: true,
      ),
    ],
  );

  group('Challenger 1 Adversarial Suite: Store-Scoped Stock Mutation & Pre-fill (M2)', () {
    // =========================================================================
    // SECTION 1: Rapid Edit -> Change Store -> Edit Again (Pre-fill Synchronization)
    // =========================================================================
    group('1. Rapid Edit -> Change Store -> Edit Again Pre-fill Synchronization', () {
      testWidgets(
          '1.1: Rapid edit without saving -> cancel -> change store context -> edit again reflects new store pre-fill without leaking dirty text',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeProductRepo = _FakeProductRepository();
        final fakeInventoryRepo = _FakeInventoryRepository();

        // Step 1: Render in store_001 context
        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: [sampleProduct],
            child: const ProductDetailPage(product: sampleProduct),
          ),
        );
        await tester.pumpAndSettle();

        // Enter edit mode under store_001
        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Verify pre-fill is 50 for store_001
        final stockFieldStore1 = find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.labelText?.contains('Số lượng tồn kho') == true);
        expect(stockFieldStore1, findsOneWidget);
        expect(tester.widget<TextField>(stockFieldStore1).controller?.text, equals('50'));

        // Rapidly enter dirty text '999' without saving
        await tester.enterText(stockFieldStore1, '999');
        await tester.pumpAndSettle();

        // Cancel edit mode
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Verify we returned to detail view
        expect(find.text('Thông tin cơ bản'), findsNothing);

        // Step 2: Switch context to store_002
        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_002',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: [sampleProduct],
            child: const ProductDetailPage(product: sampleProduct),
          ),
        );
        await tester.pumpAndSettle();

        // Enter edit mode under store_002
        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Verify pre-fill is exactly 30 for store_002 (NOT 50, and NOT dirty 999)
        final stockFieldStore2 = find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.labelText?.contains('Số lượng tồn kho') == true);
        expect(stockFieldStore2, findsOneWidget);
        expect(tester.widget<TextField>(stockFieldStore2).controller?.text, equals('30'));

        // Enter new dirty text '777' under store_002
        await tester.enterText(stockFieldStore2, '777');
        await tester.pumpAndSettle();

        // Cancel edit again
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Step 3: Switch back to store_001
        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: [sampleProduct],
            child: const ProductDetailPage(product: sampleProduct),
          ),
        );
        await tester.pumpAndSettle();

        // Enter edit mode under store_001 once more
        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Must cleanly show original 50
        final stockFieldStore1Again = find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.labelText?.contains('Số lượng tồn kho') == true);
        expect(tester.widget<TextField>(stockFieldStore1Again).controller?.text, equals('50'));

        // No repo saves or audit transactions should have occurred
        expect(fakeProductRepo.upsertHistory, isEmpty);
        expect(fakeInventoryRepo.recordedTransactions, isEmpty);
      });

      testWidgets(
          '1.2: Alternating rapid edit-saves across store_001 and store_002 persist independently with isolated audit ledger records',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeProductRepo = _FakeProductRepository();
        final fakeInventoryRepo = _FakeInventoryRepository();

        // --- Cycle 1: Edit & Save under store_001 (50 -> 75, +25) ---
        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: [sampleProduct],
            child: const ProductDetailPage(product: sampleProduct),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField1 = find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.labelText?.contains('Số lượng tồn kho') == true);
        await tester.enterText(stockField1, '75');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        expect(fakeProductRepo.lastUpsertedProduct, isNotNull);
        final productAfterCycle1 = fakeProductRepo.lastUpsertedProduct!;
        expect(productAfterCycle1.branchStocks['store_001'], equals(75));
        expect(productAfterCycle1.branchStocks['store_002'], equals(30)); // preserved
        expect(productAfterCycle1.stock, equals(105)); // 75 + 30

        expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
        final tx1 = fakeInventoryRepo.recordedTransactions.first;
        expect(tx1.storeId, equals('store_001'));
        expect(tx1.quantity, equals(25));
        expect(tx1.auditDifference, equals(25));
        expect(tx1.isAuditNegative, equals(false));

        // --- Cycle 2: Edit & Save under store_002 with updated product (30 -> 10, -20) ---
        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_002',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: [productAfterCycle1],
            child: ProductDetailPage(product: productAfterCycle1),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Pre-fill must be 30 for store_002
        final stockField2 = find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.labelText?.contains('Số lượng tồn kho') == true);
        expect(stockField2, findsOneWidget);
        expect(tester.widget<TextField>(stockField2).controller?.text, equals('30'));

        await tester.enterText(stockField2, '10');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        final productAfterCycle2 = fakeProductRepo.lastUpsertedProduct!;
        expect(productAfterCycle2.branchStocks['store_001'], equals(75)); // preserved from cycle 1
        expect(productAfterCycle2.branchStocks['store_002'], equals(10)); // updated
        expect(productAfterCycle2.stock, equals(85)); // 75 + 10

        expect(fakeInventoryRepo.recordedTransactions.length, equals(2));
        final tx2 = fakeInventoryRepo.recordedTransactions[1];
        expect(tx2.storeId, equals('store_002'));
        expect(tx2.quantity, equals(20));
        expect(tx2.auditDifference, equals(-20));
        expect(tx2.isAuditNegative, equals(true));
      });

      testWidgets(
          '1.3: Dynamic field label strictly reflects active store name upon entering edit mode',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // Under store_001
        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_001',
            child: const ProductDetailPage(product: sampleProduct),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        expect(
            find.text('Số lượng tồn kho (Chi nhánh Đông Thắng)'), findsOneWidget);
        expect(
            find.text('Số lượng tồn kho (Chi nhánh Thới Bình)'), findsNothing);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Under store_002
        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_002',
            child: const ProductDetailPage(product: sampleProduct),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        expect(
            find.text('Số lượng tồn kho (Chi nhánh Thới Bình)'), findsOneWidget);
        expect(
            find.text('Số lượng tồn kho (Chi nhánh Đông Thắng)'), findsNothing);
      });
    });

    // =========================================================================
    // SECTION 2: Asymmetric Branch Stocks (e.g. store_001: 999999, store_002: 0)
    // =========================================================================
    group('2. Asymmetric Branch Stocks (Extreme Disparity & Boundary Testing)', () {
      const asymmetricProduct = Product(
        id: 'prod_asym_01',
        name: 'Gạo ST25 Ông Cua 5kg',
        code: 'GAO-ST25',
        barcode: '893600000001',
        brand: 'Ông Cua',
        price: 195000,
        costPrice: 155000,
        branchStocks: {
          'store_001': 999999,
          'store_002': 0,
        },
        category: 'Lương thực',
      );

      testWidgets(
          '2.1: View mode correctly formats asymmetric stock counts and aggregate total',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_001',
            products: const [asymmetricProduct],
            child: const ProductDetailPage(product: asymmetricProduct),
          ),
        );
        await tester.pumpAndSettle();

        // Header status badge shows aggregate stock 999999
        expect(find.text('Còn hàng (999999)'), findsOneWidget);

        // Branch Allocation Table shows Đông Thắng: 999999 and Thới Bình: 0
        expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
        expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
        expect(find.text('Tổng: 999999'), findsOneWidget);
        expect(find.text('999999'), findsNWidgets(2)); // Row 1 + Total row
      });

      testWidgets(
          '2.2: Scoped mutation on empty store_002 (0 -> 500) preserves high volume store_001 (999999)',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeProductRepo = _FakeProductRepository();
        final fakeInventoryRepo = _FakeInventoryRepository();

        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_002',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: const [asymmetricProduct],
            child: const ProductDetailPage(product: asymmetricProduct),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Find stock TextField by dynamic label
        final stockField = find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.labelText?.contains('Số lượng tồn kho') == true);
        expect(stockField, findsOneWidget);
        expect(tester.widget<TextField>(stockField).controller?.text, equals('0'));

        await tester.enterText(stockField, '500');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        final updated = fakeProductRepo.lastUpsertedProduct!;
        expect(updated.branchStocks['store_002'], equals(500));
        expect(updated.branchStocks['store_001'], equals(999999));
        expect(updated.stock, equals(1000499)); // 999999 + 500

        expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
        final tx = fakeInventoryRepo.recordedTransactions.first;
        expect(tx.storeId, equals('store_002'));
        expect(tx.quantity, equals(500));
        expect(tx.auditDifference, equals(500));
        expect(tx.isAuditNegative, equals(false));
        expect(tx.note, contains('Tồn cũ: 0 -> Tồn mới: 500, chênh lệch: +500'));
      });

      testWidgets(
          '2.3: Scoped mutation depleting high volume store_001 (999999 -> 0) records massive negative audit and updates total to 0',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeProductRepo = _FakeProductRepository();
        final fakeInventoryRepo = _FakeInventoryRepository();

        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: const [asymmetricProduct],
            child: const ProductDetailPage(product: asymmetricProduct),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.labelText?.contains('Số lượng tồn kho') == true);
        expect(stockField, findsOneWidget);
        expect(tester.widget<TextField>(stockField).controller?.text, equals('999999'));

        await tester.enterText(stockField, '0');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        final updated = fakeProductRepo.lastUpsertedProduct!;
        expect(updated.branchStocks['store_001'], equals(0));
        expect(updated.branchStocks['store_002'], equals(0));
        expect(updated.stock, equals(0));

        expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
        final tx = fakeInventoryRepo.recordedTransactions.first;
        expect(tx.storeId, equals('store_001'));
        expect(tx.quantity, equals(999999));
        expect(tx.auditDifference, equals(-999999));
        expect(tx.isAuditNegative, equals(true));
        expect(tx.note, contains('Tồn cũ: 999999 -> Tồn mới: 0, chênh lệch: -999999'));
      });
    });

    // =========================================================================
    // SECTION 3: Legacy Key Input Maps (branch_1, branch_2) & Canonical Migration
    // =========================================================================
    group('3. Legacy Key Input Maps and Canonical Migration on Save', () {
      const legacyProduct = Product(
        id: 'prod_legacy_adv',
        name: 'Dầu Gội Head & Shoulders 850ml',
        code: 'HNS01',
        barcode: '893500000002',
        brand: 'P&G',
        price: 165000,
        costPrice: 125000,
        branchStocks: {
          'branch_1': 15,
          'branch_2': 25,
        },
        category: 'Hóa mỹ phẩm',
      );

      testWidgets(
          '3.1: Pre-fills legacy branch_1 (15) under store_001, mutates to 30, and serializes to canonical store_001 via ProductModel',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeProductRepo = _FakeProductRepository();
        final fakeInventoryRepo = _FakeInventoryRepository();

        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: const [legacyProduct],
            child: const ProductDetailPage(product: legacyProduct),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Pre-fill resolves branch_1 -> 15
        final stockField = find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.labelText?.contains('Số lượng tồn kho') == true);
        expect(stockField, findsOneWidget);
        expect(tester.widget<TextField>(stockField).controller?.text, equals('15'));

        await tester.enterText(stockField, '30');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        final updated = fakeProductRepo.lastUpsertedProduct!;
        expect(updated.stockInBranch('store_001'), equals(30));
        expect(updated.stockInBranch('store_002'), equals(25));
        expect(updated.stock, equals(55));

        // Audit transaction has storeId: 'store_001'
        expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
        final tx = fakeInventoryRepo.recordedTransactions.first;
        expect(tx.storeId, equals('store_001'));
        expect(tx.quantity, equals(15));
        expect(tx.auditDifference, equals(15));
        expect(tx.isAuditNegative, equals(false));

        // When converted to Map and parsed through ProductModel.fromMap, keys are canonical
        final model = ProductModel.fromMap(ProductModel.fromEntity(updated).toMap());
        expect(model.branchStocks['store_001'], equals(30));
        expect(model.branchStocks['store_002'], equals(25));
      });

      testWidgets(
          '3.2: Pre-fills legacy branch_2 (25) under store_002, mutates to 10, and serializes to canonical store_002 via ProductModel',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeProductRepo = _FakeProductRepository();
        final fakeInventoryRepo = _FakeInventoryRepository();

        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_002',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: const [legacyProduct],
            child: const ProductDetailPage(product: legacyProduct),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Pre-fill resolves branch_2 -> 25
        final stockField = find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.labelText?.contains('Số lượng tồn kho') == true);
        expect(stockField, findsOneWidget);
        expect(tester.widget<TextField>(stockField).controller?.text, equals('25'));

        await tester.enterText(stockField, '10');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        final updated = fakeProductRepo.lastUpsertedProduct!;
        expect(updated.stockInBranch('store_001'), equals(15));
        expect(updated.stockInBranch('store_002'), equals(10));
        expect(updated.stock, equals(25));

        // Audit transaction has storeId: 'store_002'
        expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
        final tx = fakeInventoryRepo.recordedTransactions.first;
        expect(tx.storeId, equals('store_002'));
        expect(tx.quantity, equals(15));
        expect(tx.auditDifference, equals(-15));
        expect(tx.isAuditNegative, equals(true));

        final model = ProductModel.fromMap(ProductModel.fromEntity(updated).toMap());
        expect(model.branchStocks['store_001'], equals(15));
        expect(model.branchStocks['store_002'], equals(10));
      });
    });

    // =========================================================================
    // SECTION 4: Cancel Edit Dirty State Leakage Prevention (All Controllers)
    // =========================================================================
    group('4. Cancel Edit Resets All Controllers Without Dirty State Leakage', () {
      testWidgets(
          '4.1: Dirtying every text field (Name, Code, Barcode, Price, Cost, Stock, Description, Limits) and cancelling fully restores original values',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeProductRepo = _FakeProductRepository();
        final fakeInventoryRepo = _FakeInventoryRepository();

        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: const [sampleProduct],
            child: const ProductDetailPage(product: sampleProduct),
          ),
        );
        await tester.pumpAndSettle();

        // Enter edit mode
        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Dirty main form fields
        await tester.enterText(find.widgetWithText(TextField, 'Bia Tiger Crystal 330ml'), 'DIRTY_NAME');
        await tester.enterText(find.widgetWithText(TextField, 'TIG01'), 'DIRTY_CODE');
        await tester.enterText(find.widgetWithText(TextField, '893482222001'), '999999999999');
        await tester.enterText(find.widgetWithText(TextField, '18000'), '88888');
        await tester.enterText(find.widgetWithText(TextField, '13500'), '66666');

        final stockField = find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.labelText?.contains('Số lượng tồn kho') == true);
        await tester.enterText(stockField, '777');

        // Scroll down
        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
        await tester.pumpAndSettle();

        // Expand Description and dirty it
        await tester.tap(find.text('Nhập mô tả'));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.widgetWithText(TextField, 'Bia Tiger Crystal lon 330ml'),
            'DIRTY_DESC');
        await tester.pumpAndSettle();

        // Expand Stock Limits and dirty them
        await tester.tap(find.text('Sửa định mức tồn kho'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextFormField, '10'), '55');
        await tester.enterText(find.widgetWithText(TextFormField, '200'), '888');
        await tester.pumpAndSettle();

        // Tap cancel (close icon)
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Detail view must show original unpolluted values
        expect(find.text('Bia Tiger Crystal 330ml'), findsWidgets);
        expect(find.text('DIRTY_NAME'), findsNothing);
        expect(find.text('TIG01'), findsWidgets);
        expect(find.text('DIRTY_CODE'), findsNothing);
        expect(find.text('18.000 đ'), findsOneWidget);
        expect(find.text('88.888 đ'), findsNothing);

        // Re-enter edit mode
        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Verify main controllers are reset to original values
        expect(find.widgetWithText(TextField, 'Bia Tiger Crystal 330ml'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'TIG01'), findsOneWidget);
        expect(find.widgetWithText(TextField, '893482222001'), findsOneWidget);
        expect(find.widgetWithText(TextField, '18000'), findsOneWidget);
        expect(find.widgetWithText(TextField, '13500'), findsOneWidget);

        final stockFieldReopened = find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.labelText?.contains('Số lượng tồn kho') == true);
        expect(tester.widget<TextField>(stockFieldReopened).controller?.text, equals('50'));

        // Scroll to verify collapsible fields
        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
        await tester.pumpAndSettle();

        // Ensure Description field is expanded and checked
        if (find.widgetWithText(TextFormField, 'Bia Tiger Crystal lon 330ml').evaluate().isEmpty) {
          await tester.tap(find.text('Nhập mô tả'));
          await tester.pumpAndSettle();
        }
        expect(find.widgetWithText(TextFormField, 'Bia Tiger Crystal lon 330ml'), findsOneWidget);

        // Ensure Stock Limits fields are expanded and checked
        if (find.widgetWithText(TextFormField, '10').evaluate().isEmpty) {
          await tester.tap(find.text('Sửa định mức tồn kho'));
          await tester.pumpAndSettle();
        }
        expect(find.widgetWithText(TextFormField, '10'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, '200'), findsOneWidget);

        // Zero dirty strings remain
        expect(find.textContaining('DIRTY'), findsNothing);

        // Verify zero repo calls
        expect(fakeProductRepo.upsertHistory, isEmpty);
        expect(fakeInventoryRepo.recordedTransactions, isEmpty);
      });
    });

    // =========================================================================
    // SECTION 5: Zero Diff Saving Produces Zero Audit Transactions
    // =========================================================================
    group('5. Zero Diff Saving Produces 0 Audit Transactions', () {
      testWidgets(
          '5.1: Editing non-stock attributes (Name, Price, Brand) while leaving stock unchanged produces 0 audit transactions',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeProductRepo = _FakeProductRepository();
        final fakeInventoryRepo = _FakeInventoryRepository();

        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: const [sampleProduct],
            child: const ProductDetailPage(product: sampleProduct),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // Change Name & Price, keep stock field untouched at 50
        await tester.enterText(
            find.widgetWithText(TextField, 'Bia Tiger Crystal 330ml'),
            'Bia Tiger Crystal Premium 330ml');
        await tester.enterText(find.widgetWithText(TextField, '18000'), '19500');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        // Product is successfully updated
        expect(fakeProductRepo.lastUpsertedProduct, isNotNull);
        final updated = fakeProductRepo.lastUpsertedProduct!;
        expect(updated.name, equals('Bia Tiger Crystal Premium 330ml'));
        expect(updated.price, equals(19500));
        expect(updated.stockInBranch('store_001'), equals(50));
        expect(updated.stock, equals(80));

        // ZERO audit transactions emitted
        expect(fakeInventoryRepo.recordedTransactions, isEmpty);
      });

      testWidgets(
          '5.2: Focusing stock field and re-typing identical stock value produces 0 audit transactions',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeProductRepo = _FakeProductRepository();
        final fakeInventoryRepo = _FakeInventoryRepository();

        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: const [sampleProduct],
            child: const ProductDetailPage(product: sampleProduct),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        final stockField = find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.labelText?.contains('Số lượng tồn kho') == true);
        await tester.enterText(stockField, '50'); // Re-type identical value
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        expect(fakeProductRepo.lastUpsertedProduct, isNotNull);
        expect(fakeInventoryRepo.recordedTransactions, isEmpty);
      });

      testWidgets(
          '5.3: Combo product edits never generate inventory audit transactions',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const comboProduct = Product(
          id: 'prod_combo_m2',
          name: 'Combo Tiệc Vui Cuối Tuần',
          code: 'CB-TIEK01',
          price: 99000,
          costPrice: 75000,
          branchStocks: {'store_001': 10, 'store_002': 5},
          category: 'Combo',
          unit: 'Gói',
          isCombo: true,
          comboComponents: [
            ComboComponent(
              productId: 'prod_adv_m2_01',
              productCode: 'TIG01',
              productName: 'Bia Tiger Crystal 330ml',
              quantity: 4,
              costPrice: 13500,
            ),
          ],
        );

        final fakeProductRepo = _FakeProductRepository();
        final fakeInventoryRepo = _FakeInventoryRepository();

        await tester.pumpWidget(
          _buildChallengerM2App(
            storeId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: const [comboProduct],
            child: const ProductDetailPage(product: comboProduct),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        // For combo, stock edit input is hidden and combo notice is shown
        expect(find.text('Tồn kho của Combo được tự động tính theo số lượng linh kiện thành phần.'),
            findsOneWidget);

        // Edit price and save
        await tester.enterText(find.widgetWithText(TextField, '99000'), '109000');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        expect(fakeProductRepo.lastUpsertedProduct, isNotNull);
        expect(fakeProductRepo.lastUpsertedProduct!.price, equals(109000));
        expect(fakeInventoryRepo.recordedTransactions, isEmpty);
      });
    });
  });
}
