import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';

class _FakeProductRepository extends Fake implements ProductRepository {
  Product? lastUpsertedProduct;

  @override
  Future<void> upsert(Product product) async {
    lastUpsertedProduct = product;
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
  const Branch('store_003', 'Chi nhánh Cần Thơ'),
];

Widget _buildTestApp({
  required Widget child,
  String currentStoreId = 'store_001',
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      currentStoreIdProvider.overrideWith((ref) => currentStoreId),
      branchesProvider.overrideWithValue(_defaultBranches),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': 'Chi nhánh Đông Thắng',
            'store_002': 'Chi nhánh Thới Bình',
            'store_003': 'Chi nhánh Cần Thơ',
          }),
      ...overrides,
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

  const adminUser = UserAccount(
    username: 'admin_test',
    displayName: 'Quản trị viên Test',
    role: 'admin',
    storeId: 'store_001',
  );

  group('Empirical Challenger M4 Stress-Tests (Direct Stock Edit & FIFO Balance)', () {
    // -------------------------------------------------------------------------
    // 1. Editing stock with 0 change (old stock == entered stock)
    // -------------------------------------------------------------------------
    testWidgets(
        '1. Editing stock with 0 change produces NO spurious audit transaction',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeProductRepo = _FakeProductRepository();
      final fakeInventoryRepo = _FakeInventoryRepository();

      const product = Product(
        id: 'prod_zero_diff',
        name: 'Sữa tươi Tiệt trùng TH 1L',
        code: 'TH1L',
        category: 'Sữa & Bơ',
        price: 38000,
        costPrice: 30000,
        branchStocks: {'store_001': 24, 'store_002': 12},
        allowSale: true,
      );

      await tester.pumpWidget(
        _buildTestApp(
          currentStoreId: 'store_001',
          child: const ProductDetailPage(product: product),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            productRepositoryProvider.overrideWithValue(fakeProductRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
            productListProvider.overrideWith((ref) => Stream.value([product])),
            transactionsByProductProvider(product.id)
                .overrideWith((ref) => Stream.value([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Enter edit mode
      final editButton = find.widgetWithText(TextButton, 'Sửa');
      expect(editButton, findsOneWidget);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      // Change name only, leave stock at 24
      final nameField = find.widgetWithText(TextFormField, 'Sữa tươi Tiệt trùng TH 1L');
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'Sữa tươi Tiệt trùng TH 1L (Mới)');

      // Tap Save
      final saveButton = find.widgetWithText(TextButton, 'Lưu');
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Verify product was updated with new name and stock 24
      expect(fakeProductRepo.lastUpsertedProduct, isNotNull);
      expect(fakeProductRepo.lastUpsertedProduct!.name,
          equals('Sữa tươi Tiệt trùng TH 1L (Mới)'));
      expect(fakeProductRepo.lastUpsertedProduct!.branchStocks['store_001'],
          equals(24));

      // CRITICAL: NO audit transaction must be created!
      expect(fakeInventoryRepo.recordedTransactions, isEmpty);
    });

    // -------------------------------------------------------------------------
    // 2. Editing stock on multi-branch setup
    // -------------------------------------------------------------------------
    testWidgets(
        '2. Editing stock on multi-branch setup updates only active store and isolates stock counts',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeProductRepo = _FakeProductRepository();
      final fakeInventoryRepo = _FakeInventoryRepository();

      const product = Product(
        id: 'prod_multi_branch',
        name: 'Bia Heineken Sleek 330ml',
        code: 'HN330',
        category: 'Bia & Đồ uống có cồn',
        price: 22000,
        costPrice: 17000,
        branchStocks: {
          'store_001': 50,
          'store_002': 30,
          'store_003': 15,
        },
        allowSale: true,
      );

      // Active branch is store_002
      await tester.pumpWidget(
        _buildTestApp(
          currentStoreId: 'store_002',
          child: const ProductDetailPage(product: product),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            productRepositoryProvider.overrideWithValue(fakeProductRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
            productListProvider.overrideWith((ref) => Stream.value([product])),
            transactionsByProductProvider(product.id)
                .overrideWith((ref) => Stream.value([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Enter edit mode
      await tester.tap(find.widgetWithText(TextButton, 'Sửa'));
      await tester.pumpAndSettle();

      // The stock field should be initialized to store_002 stock (30)
      final stockField = find.widgetWithText(TextFormField, '30');
      expect(stockField, findsOneWidget);

      // Update stock of store_002 from 30 -> 45 (+15 diff)
      await tester.enterText(stockField, '45');
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
      await tester.pumpAndSettle();

      // Verify branch isolation: store_001 and store_003 unchanged, store_002 is 45
      final updated = fakeProductRepo.lastUpsertedProduct!;
      expect(updated.branchStocks['store_001'], equals(50));
      expect(updated.branchStocks['store_002'], equals(45));
      expect(updated.branchStocks['store_003'], equals(15));

      // Verify audit transaction was recorded with branch context
      expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
      final tx = fakeInventoryRepo.recordedTransactions.first;
      expect(tx.productId, equals('prod_multi_branch'));
      expect(tx.type, equals(TransactionType.inventoryAudit));
      expect(tx.quantity, equals(15));
      expect(tx.importPrice, equals(17000.0));
      expect(tx.createdBy, equals('admin_test'));
      expect(tx.note,
          equals('Cân bằng kho trực tiếp (Tồn cũ: 30 -> Tồn mới: 45, chênh lệch: +15)'));
    });

    testWidgets(
        '2b. Editing stock with legacy branch aliases (branch_1/branch_2) maps correctly to store_001',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeProductRepo = _FakeProductRepository();
      final fakeInventoryRepo = _FakeInventoryRepository();

      const product = Product(
        id: 'prod_legacy_branches',
        name: 'Dầu ăn Neptune 1L',
        code: 'NP1L',
        category: 'Gia vị & Dầu ăn',
        price: 52000,
        costPrice: 42000,
        branchStocks: {
          'branch_1': 10,
          'branch_2': 20,
        },
        allowSale: true,
      );

      // Active store is store_001 (which maps to branch_1)
      await tester.pumpWidget(
        _buildTestApp(
          currentStoreId: 'store_001',
          child: const ProductDetailPage(product: product),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            productRepositoryProvider.overrideWithValue(fakeProductRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
            productListProvider.overrideWith((ref) => Stream.value([product])),
            transactionsByProductProvider(product.id)
                .overrideWith((ref) => Stream.value([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Enter edit mode
      await tester.tap(find.widgetWithText(TextButton, 'Sửa'));
      await tester.pumpAndSettle();

      // Stock field should show 10 (from branch_1)
      final stockField = find.widgetWithText(TextFormField, '10');
      expect(stockField, findsOneWidget);

      // Update to 18 (+8)
      await tester.enterText(stockField, '18');
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
      await tester.pumpAndSettle();

      // Verify branch_1 updated, branch_2 intact
      final updated = fakeProductRepo.lastUpsertedProduct!;
      expect(updated.branchStocks['branch_1'], equals(18));
      expect(updated.branchStocks['branch_2'], equals(20));

      expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
      final tx = fakeInventoryRepo.recordedTransactions.first;
      expect(tx.quantity, equals(8));
      expect(tx.note,
          equals('Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 18, chênh lệch: +8)'));
    });

    // -------------------------------------------------------------------------
    // 3. Direct stock edit on Combo products
    // -------------------------------------------------------------------------
    testWidgets(
        '3. Combo products disallow direct stock editing and omit audit creation',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeProductRepo = _FakeProductRepository();
      final fakeInventoryRepo = _FakeInventoryRepository();

      const comboProduct = Product(
        id: 'combo_tet_2026',
        name: 'Combo Giỏ Quà Tết Sum Vầy',
        code: 'CB-TET01',
        category: 'Quà tặng & Combo',
        price: 350000,
        costPrice: 280000,
        branchStocks: {'store_001': 5},
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'p1',
            productCode: 'CAFE01',
            productName: 'Cà phê G7',
            quantity: 2,
          ),
          ComboComponent(
            productId: 'p2',
            productCode: 'BANH01',
            productName: 'Bánh Danisa',
            quantity: 1,
          ),
        ],
        allowSale: true,
      );

      await tester.pumpWidget(
        _buildTestApp(
          currentStoreId: 'store_001',
          child: const ProductDetailPage(product: comboProduct),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            productRepositoryProvider.overrideWithValue(fakeProductRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
            productListProvider
                .overrideWith((ref) => Stream.value([comboProduct])),
            transactionsByProductProvider(comboProduct.id)
                .overrideWith((ref) => Stream.value([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Enter edit mode
      await tester.tap(find.widgetWithText(TextButton, 'Sửa'));
      await tester.pumpAndSettle();

      // Verify NO stock text input field is rendered for combo
      // Info notice should be displayed instead
      expect(
          find.text(
              'Tồn kho của Combo được tự động tính theo số lượng linh kiện thành phần.'),
          findsOneWidget);

      // Save
      await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
      await tester.pumpAndSettle();

      // Verify NO audit transaction is created for combo
      expect(fakeInventoryRepo.recordedTransactions, isEmpty);
    });

    // -------------------------------------------------------------------------
    // 4. Negative diff / stock decrement & FIFO lot consumption
    // -------------------------------------------------------------------------
    testWidgets(
        '4. Negative diff decreases stock, generates negative audit note, and UI reflects red badge',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeProductRepo = _FakeProductRepository();
      final fakeInventoryRepo = _FakeInventoryRepository();

      const product = Product(
        id: 'prod_neg_diff',
        name: 'Trà Xanh Không Độ 500ml',
        code: 'TX500',
        category: 'Trà & Nước giải khát',
        price: 10000,
        costPrice: 7000,
        branchStocks: {'store_001': 20},
        allowSale: true,
      );

      await tester.pumpWidget(
        _buildTestApp(
          currentStoreId: 'store_001',
          child: const ProductDetailPage(product: product),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            productRepositoryProvider.overrideWithValue(fakeProductRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
            productListProvider.overrideWith((ref) => Stream.value([product])),
            transactionsByProductProvider(product.id)
                .overrideWith((ref) => Stream.value([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Enter edit mode
      await tester.tap(find.widgetWithText(TextButton, 'Sửa'));
      await tester.pumpAndSettle();

      final stockField = find.widgetWithText(TextFormField, '20');
      expect(stockField, findsOneWidget);

      // Decrement stock: 20 -> 13 (diff: -7)
      await tester.enterText(stockField, '13');
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
      await tester.pumpAndSettle();

      // Verify stock was updated to 13
      final updated = fakeProductRepo.lastUpsertedProduct!;
      expect(updated.branchStocks['store_001'], equals(13));

      // Verify transaction recorded
      expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
      final tx = fakeInventoryRepo.recordedTransactions.first;
      expect(tx.type, equals(TransactionType.inventoryAudit));
      expect(tx.quantity, equals(7)); // abs(13 - 20)
      expect(tx.importPrice, equals(7000.0));
      expect(tx.note,
          equals('Cân bằng kho trực tiếp (Tồn cũ: 20 -> Tồn mới: 13, chênh lệch: -7)'));
    });

    test('4b. FIFO Calculator seamlessly handles negative audit transactions', () {
      // Lot 1: 5 units @ 10,000 (imported Jan 1)
      // Lot 2: 15 units @ 14,000 (imported Jan 2)
      // Negative Audit Jan 3: -8 units
      //   -> FIFO consumes all 5 units of Lot 1 + 3 units of Lot 2 (Lot 2 remaining = 12)
      final txs = [
        InventoryTransaction(
          id: 'imp_1',
          productId: 'p_fifo_neg',
          type: TransactionType.import,
          quantity: 5,
          date: DateTime(2026, 1, 1),
          note: 'Nhập lô 1',
          importPrice: 10000,
        ),
        InventoryTransaction(
          id: 'imp_2',
          productId: 'p_fifo_neg',
          type: TransactionType.import,
          quantity: 15,
          date: DateTime(2026, 1, 2),
          note: 'Nhập lô 2',
          importPrice: 14000,
        ),
        InventoryTransaction(
          id: 'audit_neg',
          productId: 'p_fifo_neg',
          type: TransactionType.inventoryAudit,
          quantity: 8,
          date: DateTime(2026, 1, 3),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 20 -> Tồn mới: 12, chênh lệch: -8)',
          importPrice: 12000,
        ),
      ];

      final fifo = FifoCalculator(txs);
      final lots = fifo.getInventoryLots('p_fifo_neg');
      expect(lots.length, equals(2));
      expect(lots[0].remainingQuantity, equals(0)); // Lot 1 depleted
      expect(lots[1].remainingQuantity, equals(12)); // Lot 2 has 12 left

      // Sale of 4 units on Jan 4: must come from Lot 2 at 14,000 each = 56,000
      final cost = fifo.calculateCostForSale(
        productId: 'p_fifo_neg',
        quantity: 4,
        saleDate: DateTime(2026, 1, 4),
      );
      expect(cost, equals(56000.0));
      expect(lots[1].remainingQuantity, equals(8));
    });

    // -------------------------------------------------------------------------
    // 5. Stock Card History filter switching
    // -------------------------------------------------------------------------
    testWidgets(
        '5. Stock Card History filter switching isolates each transaction category cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const product = Product(
        id: 'prod_filter_test',
        name: 'Nước Tăng Lực RedBull 250ml',
        code: 'RB250',
        category: 'Nước tăng lực',
        price: 15000,
        costPrice: 11000,
        branchStocks: {'store_001': 50},
        allowSale: true,
      );

      final sampleTransactions = [
        InventoryTransaction(
          id: 'tx_imp',
          productId: 'prod_filter_test',
          type: TransactionType.import,
          quantity: 100,
          date: DateTime(2026, 8, 10),
          note: 'Nhập hàng từ nhà phân phối Phú Thái',
          importPrice: 11000,
        ),
        InventoryTransaction(
          id: 'tx_exp',
          productId: 'prod_filter_test',
          type: TransactionType.export,
          quantity: 20,
          date: DateTime(2026, 8, 12),
          note: 'HD-POS-0012',
        ),
        InventoryTransaction(
          id: 'tx_transfer',
          productId: 'prod_filter_test',
          type: TransactionType.export,
          quantity: 30,
          date: DateTime(2026, 8, 14),
          note: 'Chuyển kho sang Chi nhánh Thới Bình',
        ),
        InventoryTransaction(
          id: 'tx_audit_pos',
          productId: 'prod_filter_test',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: DateTime(2026, 8, 15),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 50 -> Tồn mới: 55, chênh lệch: +5)',
          importPrice: 11000,
        ),
        InventoryTransaction(
          id: 'tx_audit_neg',
          productId: 'prod_filter_test',
          type: TransactionType.inventoryAudit,
          quantity: 2,
          date: DateTime(2026, 8, 16),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 55 -> Tồn mới: 53, chênh lệch: -2)',
          importPrice: 11000,
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          currentStoreId: 'store_001',
          child: const ProductDetailPage(product: product),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            productListProvider.overrideWith((ref) => Stream.value([product])),
            transactionsByProductProvider(product.id)
                .overrideWith((ref) => Stream.value(sampleTransactions)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Verify all 5 tab segments exist
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Nhập hàng'), findsWidgets);
      expect(find.text('Bán hàng / Xuất'), findsWidgets);
      expect(find.text('Chuyển kho'), findsWidgets);
      expect(find.text('Cân bằng kho'), findsWidgets);

      // Initial tab: 'Tất cả' -> shows all 5
      expect(find.text('Nhập hàng từ nhà phân phối Phú Thái'), findsOneWidget);
      expect(find.text('Bán hàng (Mã đơn: HD-POS-0012)'), findsOneWidget);
      expect(find.text('Chuyển kho sang Chi nhánh Thới Bình'), findsOneWidget);
      expect(
          find.text('Cân bằng kho trực tiếp (Tồn cũ: 50 -> Tồn mới: 55, chênh lệch: +5)'),
          findsOneWidget);
      expect(
          find.text('Cân bằng kho trực tiếp (Tồn cũ: 55 -> Tồn mới: 53, chênh lệch: -2)'),
          findsOneWidget);

      // Tap 'Nhập hàng' (index 1)
      final importTab = find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('Nhập hàng'),
      );
      await tester.tap(importTab);
      await tester.pumpAndSettle();

      expect(find.text('Nhập hàng từ nhà phân phối Phú Thái'), findsOneWidget);
      expect(find.text('Bán hàng (Mã đơn: HD-POS-0012)'), findsNothing);
      expect(find.text('Chuyển kho sang Chi nhánh Thới Bình'), findsNothing);
      expect(
          find.text('Cân bằng kho trực tiếp (Tồn cũ: 50 -> Tồn mới: 55, chênh lệch: +5)'),
          findsNothing);
      expect(
          find.text('Cân bằng kho trực tiếp (Tồn cũ: 55 -> Tồn mới: 53, chênh lệch: -2)'),
          findsNothing);

      // Tap 'Bán hàng / Xuất' (index 2)
      final exportTab = find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('Bán hàng / Xuất'),
      );
      await tester.tap(exportTab);
      await tester.pumpAndSettle();

      expect(find.text('Bán hàng (Mã đơn: HD-POS-0012)'), findsOneWidget);
      expect(find.text('Nhập hàng từ nhà phân phối Phú Thái'), findsNothing);
      expect(find.text('Chuyển kho sang Chi nhánh Thới Bình'), findsNothing);
      expect(
          find.text('Cân bằng kho trực tiếp (Tồn cũ: 50 -> Tồn mới: 55, chênh lệch: +5)'),
          findsNothing);
      expect(
          find.text('Cân bằng kho trực tiếp (Tồn cũ: 55 -> Tồn mới: 53, chênh lệch: -2)'),
          findsNothing);

      // Tap 'Chuyển kho' (index 3)
      final transferTab = find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('Chuyển kho'),
      );
      await tester.tap(transferTab);
      await tester.pumpAndSettle();

      expect(find.text('Chuyển kho sang Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.text('Nhập hàng từ nhà phân phối Phú Thái'), findsNothing);
      expect(find.text('Bán hàng (Mã đơn: HD-POS-0012)'), findsNothing);
      expect(
          find.text('Cân bằng kho trực tiếp (Tồn cũ: 50 -> Tồn mới: 55, chênh lệch: +5)'),
          findsNothing);
      expect(
          find.text('Cân bằng kho trực tiếp (Tồn cũ: 55 -> Tồn mới: 53, chênh lệch: -2)'),
          findsNothing);

      // Tap 'Cân bằng kho' (index 4)
      final auditTab = find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('Cân bằng kho'),
      );
      await tester.tap(auditTab);
      await tester.pumpAndSettle();

      // ONLY the two inventoryAudit transactions must be visible!
      expect(
          find.text('Cân bằng kho trực tiếp (Tồn cũ: 50 -> Tồn mới: 55, chênh lệch: +5)'),
          findsOneWidget);
      expect(
          find.text('Cân bằng kho trực tiếp (Tồn cũ: 55 -> Tồn mới: 53, chênh lệch: -2)'),
          findsOneWidget);
      expect(find.text('+5'), findsOneWidget);
      expect(find.text('-2'), findsOneWidget);

      expect(find.text('Nhập hàng từ nhà phân phối Phú Thái'), findsNothing);
      expect(find.text('Bán hàng (Mã đơn: HD-POS-0012)'), findsNothing);
      expect(find.text('Chuyển kho sang Chi nhánh Thới Bình'), findsNothing);

      // Tap 'Tất cả' to return (index 0)
      final allTab = find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('Tất cả'),
      );
      await tester.tap(allTab);
      await tester.pumpAndSettle();

      expect(find.text('Nhập hàng từ nhà phân phối Phú Thái'), findsOneWidget);
      expect(find.text('Bán hàng (Mã đơn: HD-POS-0012)'), findsOneWidget);
      expect(find.text('Chuyển kho sang Chi nhánh Thới Bình'), findsOneWidget);
      expect(
          find.text('Cân bằng kho trực tiếp (Tồn cũ: 50 -> Tồn mới: 55, chênh lệch: +5)'),
          findsOneWidget);
      expect(
          find.text('Cân bằng kho trực tiếp (Tồn cũ: 55 -> Tồn mới: 53, chênh lệch: -2)'),
          findsOneWidget);
    });
  });
}
