import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/data/models/inventory_transaction_model.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';

// ---------------------------------------------------------------------------
// Test Fakes & Mock Helpers
// ---------------------------------------------------------------------------

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

final _canonicalBranches = [
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
        username: 'supervisor_adv_2',
        displayName: 'Giám Sát Viên Challenger 2',
        role: 'supervisor',
        storeId: 'store_001',
      );

  final repoProduct = productRepo ?? _FakeProductRepository();
  final repoInventory = inventoryRepo ?? _FakeInventoryRepository();

  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
      currentStoreIdProvider.overrideWithValue(storeId),
      branchesProvider.overrideWithValue(branches ?? _canonicalBranches),
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
          products?.firstOrNull?.id ?? 'prod_test',
        ).overrideWith((ref) => Stream.value(transactions)),
    ],
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

  group('Challenger 2 Adversarial Suite: Structured Audit Logging & Cross-Branch Isolation', () {
    // =========================================================================
    // SECTION 1: Exhaustive Serialization Round-Trip for InventoryTransactionModel
    // =========================================================================
    group('1. InventoryTransactionModel Serialization & Structured Audit Fields Round-Trip', () {
      test('Non-null structured audit fields serialization round-trip (Positive auditDifference)', () {
        final fixedDate = DateTime(2026, 8, 17, 14, 45, 0);
        final originalEntity = InventoryTransaction(
          id: 'tx_audit_pos_001',
          productId: 'prod_999',
          type: TransactionType.inventoryAudit,
          quantity: 25,
          date: fixedDate,
          note: 'Cân bằng kho tăng (+25)',
          importPrice: 48000.0,
          createdBy: 'admin_east',
          createdByName: 'Admin Đông Thắng',
          storeId: 'store_001',
          isAuditNegative: false,
          auditDifference: 25,
        );

        // Entity -> Model
        final model = InventoryTransactionModel.fromEntity(originalEntity);
        expect(model.id, equals('tx_audit_pos_001'));
        expect(model.productId, equals('prod_999'));
        expect(model.type, equals('INVENTORY_AUDIT'));
        expect(model.quantity, equals(25));
        expect(model.date, equals(fixedDate));
        expect(model.note, equals('Cân bằng kho tăng (+25)'));
        expect(model.importPrice, equals(48000.0));
        expect(model.createdBy, equals('admin_east'));
        expect(model.createdByName, equals('Admin Đông Thắng'));
        expect(model.storeId, equals('store_001'));
        expect(model.isAuditNegative, isFalse);
        expect(model.auditDifference, equals(25));

        // Model -> Map
        final map = model.toMap();
        expect(map['id'], equals('tx_audit_pos_001'));
        expect(map['productId'], equals('prod_999'));
        expect(map['type'], equals('INVENTORY_AUDIT'));
        expect(map['quantity'], equals(25));
        expect(map['date'], equals(fixedDate.toIso8601String()));
        expect(map['note'], equals('Cân bằng kho tăng (+25)'));
        expect(map['importPrice'], equals(48000.0));
        expect(map['createdBy'], equals('admin_east'));
        expect(map['createdByName'], equals('Admin Đông Thắng'));
        expect(map['storeId'], equals('store_001'));
        expect(map['isAuditNegative'], isFalse);
        expect(map['auditDifference'], equals(25));

        // Map -> Model
        final restoredModel = InventoryTransactionModel.fromMap(map);
        expect(restoredModel.id, equals(model.id));
        expect(restoredModel.productId, equals(model.productId));
        expect(restoredModel.type, equals('INVENTORY_AUDIT'));
        expect(restoredModel.toTransactionType(), equals(TransactionType.inventoryAudit));
        expect(restoredModel.quantity, equals(model.quantity));
        expect(restoredModel.date, equals(model.date));
        expect(restoredModel.note, equals(model.note));
        expect(restoredModel.importPrice, equals(model.importPrice));
        expect(restoredModel.createdBy, equals(model.createdBy));
        expect(restoredModel.createdByName, equals(model.createdByName));
        expect(restoredModel.storeId, equals('store_001'));
        expect(restoredModel.isAuditNegative, isFalse);
        expect(restoredModel.auditDifference, equals(25));

        // Restored Model -> Entity
        final restoredEntity = restoredModel.toEntity();
        expect(restoredEntity.id, equals(originalEntity.id));
        expect(restoredEntity.productId, equals(originalEntity.productId));
        expect(restoredEntity.type, equals(TransactionType.inventoryAudit));
        expect(restoredEntity.quantity, equals(25));
        expect(restoredEntity.storeId, equals('store_001'));
        expect(restoredEntity.isAuditNegative, isFalse);
        expect(restoredEntity.auditDifference, equals(25));
      });

      test('Non-null structured audit fields serialization round-trip (Negative auditDifference)', () {
        final fixedDate = DateTime(2026, 8, 17, 15, 30, 0);
        final originalEntity = InventoryTransaction(
          id: 'tx_audit_neg_002',
          productId: 'prod_888',
          type: TransactionType.inventoryAudit,
          quantity: 14,
          date: fixedDate,
          note: 'Cân bằng kho giảm (-14)',
          importPrice: 32000.0,
          createdBy: 'admin_west',
          createdByName: 'Admin Thới Bình',
          storeId: 'store_002',
          isAuditNegative: true,
          auditDifference: -14,
        );

        final model = InventoryTransactionModel.fromEntity(originalEntity);
        final map = model.toMap();

        expect(map['storeId'], equals('store_002'));
        expect(map['isAuditNegative'], isTrue);
        expect(map['auditDifference'], equals(-14));

        final restoredModel = InventoryTransactionModel.fromMap(map);
        expect(restoredModel.storeId, equals('store_002'));
        expect(restoredModel.isAuditNegative, isTrue);
        expect(restoredModel.auditDifference, equals(-14));

        final restoredEntity = restoredModel.toEntity();
        expect(restoredEntity.storeId, equals('store_002'));
        expect(restoredEntity.isAuditNegative, isTrue);
        expect(restoredEntity.auditDifference, equals(-14));
      });

      test('Null structured audit fields serialization round-trip (Standard Import / Export transactions)', () {
        final fixedDate = DateTime(2026, 8, 17, 16, 0, 0);
        final legacyEntity = InventoryTransaction(
          id: 'tx_import_legacy',
          productId: 'prod_777',
          type: TransactionType.import,
          quantity: 100,
          date: fixedDate,
          note: 'Nhập hàng thông thường',
          importPrice: 15000.0,
          createdBy: 'staff_01',
          createdByName: 'Nhân Viên Kho',
          storeId: null,
          isAuditNegative: null,
          auditDifference: null,
        );

        final model = InventoryTransactionModel.fromEntity(legacyEntity);
        final map = model.toMap();

        // Ensure keys are completely omitted when fields are null
        expect(map.containsKey('storeId'), isFalse);
        expect(map.containsKey('isAuditNegative'), isFalse);
        expect(map.containsKey('auditDifference'), isFalse);

        final restoredModel = InventoryTransactionModel.fromMap(map);
        expect(restoredModel.storeId, isNull);
        expect(restoredModel.isAuditNegative, isNull);
        expect(restoredModel.auditDifference, isNull);

        final restoredEntity = restoredModel.toEntity();
        expect(restoredEntity.storeId, isNull);
        expect(restoredEntity.isAuditNegative, isNull);
        expect(restoredEntity.auditDifference, isNull);
      });

      test('Robust dynamic map deserialization with String/num conversions for audit fields', () {
        final rawMap = <dynamic, dynamic>{
          'id': 'tx_dynamic_001',
          'productId': 'prod_dynamic',
          'type': 'audit',
          'quantity': 10.0, // double quantity
          'date': '2026-08-17T12:00:00.000',
          'note': 'Audit via dynamic raw map',
          'importPrice': 50000, // int importPrice
          'storeId': 'store_001',
          'isAuditNegative': 'true', // string boolean
          'auditDifference': -10.0, // double audit difference
        };

        final model = InventoryTransactionModel.fromMap(rawMap);
        expect(model.id, equals('tx_dynamic_001'));
        expect(model.quantity, equals(10));
        expect(model.toTransactionType(), equals(TransactionType.inventoryAudit));
        expect(model.importPrice, equals(50000.0));
        expect(model.storeId, equals('store_001'));
        expect(model.isAuditNegative, isTrue);
        expect(model.auditDifference, equals(-10));
      });

      test('Graceful fallback for completely empty or corrupted map', () {
        final emptyModel = InventoryTransactionModel.fromMap({});
        expect(emptyModel.id, equals(''));
        expect(emptyModel.productId, equals(''));
        expect(emptyModel.type, equals('import'));
        expect(emptyModel.quantity, equals(0));
        expect(emptyModel.note, equals(''));
        expect(emptyModel.storeId, isNull);
        expect(emptyModel.isAuditNegative, isNull);
        expect(emptyModel.auditDifference, isNull);
      });
    });

    // =========================================================================
    // SECTION 2: Sequential Stock Mutations Across Alternating Stores & Invariants
    // =========================================================================
    group('2. Cross-Branch Stock Isolation & Aggregate Sum Invariant Under Alternating Mutations', () {
      test('Sequential 6-step alternating mutations between store_001 and store_002', () {
        // Initial state: Store 1 = 100, Store 2 = 50, Total = 150
        var currentProduct = const Product(
          id: 'prod_isolation_01',
          name: 'Nước Tăng Lực RedBull 250ml',
          code: 'RB250',
          price: 12000,
          costPrice: 8000,
          branchStocks: {
            'store_001': 100,
            'store_002': 50,
          },
          category: 'Đồ uống',
        );

        expect(currentProduct.stockInBranch('store_001'), equals(100));
        expect(currentProduct.stockInBranch('store_002'), equals(50));
        expect(currentProduct.stock, equals(150));

        // Step 1: Mutate store_001 -> 125 (+25)
        final map1 = Map<String, int>.from(currentProduct.branchStocks);
        map1['store_001'] = 125;
        currentProduct = currentProduct.copyWith(branchStocks: map1);
        expect(currentProduct.stockInBranch('store_001'), equals(125));
        expect(currentProduct.stockInBranch('store_002'), equals(50), reason: 'store_002 must remain untouched');
        expect(currentProduct.stock, equals(175), reason: 'Total stock must equal 125 + 50 = 175');

        // Step 2: Mutate store_002 -> 30 (-20)
        final map2 = Map<String, int>.from(currentProduct.branchStocks);
        map2['store_002'] = 30;
        currentProduct = currentProduct.copyWith(branchStocks: map2);
        expect(currentProduct.stockInBranch('store_001'), equals(125), reason: 'store_001 must remain untouched');
        expect(currentProduct.stockInBranch('store_002'), equals(30));
        expect(currentProduct.stock, equals(155), reason: 'Total stock must equal 125 + 30 = 155');

        // Step 3: Mutate store_001 -> 0 (-125, zero stock boundary)
        final map3 = Map<String, int>.from(currentProduct.branchStocks);
        map3['store_001'] = 0;
        currentProduct = currentProduct.copyWith(branchStocks: map3);
        expect(currentProduct.stockInBranch('store_001'), equals(0));
        expect(currentProduct.stockInBranch('store_002'), equals(30), reason: 'store_002 must remain untouched');
        expect(currentProduct.stock, equals(30), reason: 'Total stock must equal 0 + 30 = 30');

        // Step 4: Mutate store_002 -> 80 (+50)
        final map4 = Map<String, int>.from(currentProduct.branchStocks);
        map4['store_002'] = 80;
        currentProduct = currentProduct.copyWith(branchStocks: map4);
        expect(currentProduct.stockInBranch('store_001'), equals(0), reason: 'store_001 must remain untouched');
        expect(currentProduct.stockInBranch('store_002'), equals(80));
        expect(currentProduct.stock, equals(80), reason: 'Total stock must equal 0 + 80 = 80');

        // Step 5: Mutate store_001 -> 500 (+500, bulk restock)
        final map5 = Map<String, int>.from(currentProduct.branchStocks);
        map5['store_001'] = 500;
        currentProduct = currentProduct.copyWith(branchStocks: map5);
        expect(currentProduct.stockInBranch('store_001'), equals(500));
        expect(currentProduct.stockInBranch('store_002'), equals(80), reason: 'store_002 must remain untouched');
        expect(currentProduct.stock, equals(580), reason: 'Total stock must equal 500 + 80 = 580');

        // Step 6: Zero mutation on store_001 (re-assign 500)
        final map6 = Map<String, int>.from(currentProduct.branchStocks);
        map6['store_001'] = 500;
        currentProduct = currentProduct.copyWith(branchStocks: map6);
        expect(currentProduct.stockInBranch('store_001'), equals(500));
        expect(currentProduct.stockInBranch('store_002'), equals(80));
        expect(currentProduct.stock, equals(580));
      });

      test('Stress test: 100 alternating rapid mutations between 2 stores preserving invariant', () {
        var product = const Product(
          id: 'prod_stress_01',
          name: 'Bánh Mì Sandwiches',
          code: 'BM01',
          price: 15000,
          costPrice: 9000,
          branchStocks: {
            'store_001': 50,
            'store_002': 50,
          },
          category: 'Thực phẩm',
        );

        for (int i = 1; i <= 100; i++) {
          final targetStore = (i % 2 == 1) ? 'store_001' : 'store_002';
          final untouchedStore = (i % 2 == 1) ? 'store_002' : 'store_001';
          final previousUntouchedStock = product.stockInBranch(untouchedStore);

          final newStock = (i * 7) % 250; // Dynamic pseudo-random stock value

          final updatedBranchStocks = Map<String, int>.from(product.branchStocks);
          updatedBranchStocks[targetStore] = newStock;
          product = product.copyWith(branchStocks: updatedBranchStocks);

          // Assert strict isolation
          expect(product.stockInBranch(untouchedStore), equals(previousUntouchedStock),
              reason: 'Mutation to $targetStore on iteration $i leaked to $untouchedStore');

          // Assert exact target stock update
          expect(product.stockInBranch(targetStore), equals(newStock));

          // Assert aggregate sum invariant
          final expectedTotal = product.branchStocks.values.fold(0, (a, b) => a + b);
          expect(product.stock, equals(expectedTotal),
              reason: 'Aggregate stock failed at iteration $i: expected $expectedTotal vs actual ${product.stock}');
        }
      });

      test('Multi-branch expansion (3 stores) isolation integrity', () {
        var product = const Product(
          id: 'prod_tri_store',
          name: 'Sữa Tươi Tiệt Trùng 1L',
          code: 'ST1L',
          price: 32000,
          costPrice: 24000,
          branchStocks: {
            'store_001': 100,
            'store_002': 60,
            'store_003': 40,
          },
          category: 'Sữa & Bơ',
        );

        expect(product.stock, equals(200));

        // Mutate store_002
        final m1 = Map<String, int>.from(product.branchStocks);
        m1['store_002'] = 90;
        product = product.copyWith(branchStocks: m1);
        expect(product.stockInBranch('store_001'), equals(100));
        expect(product.stockInBranch('store_002'), equals(90));
        expect(product.stockInBranch('store_003'), equals(40));
        expect(product.stock, equals(230));

        // Mutate store_003
        final m2 = Map<String, int>.from(product.branchStocks);
        m2['store_003'] = 10;
        product = product.copyWith(branchStocks: m2);
        expect(product.stockInBranch('store_001'), equals(100));
        expect(product.stockInBranch('store_002'), equals(90));
        expect(product.stockInBranch('store_003'), equals(10));
        expect(product.stock, equals(200));
      });
    });

    // =========================================================================
    // SECTION 3: Structured Audit History Generation & Signed Difference Verification
    // =========================================================================
    group('3. Structured Audit History Generation & Ledger Difference Verification', () {
      test('Audit Transaction accurately generated for Positive adjustment (+18)', () {
        const oldStock = 12;
        const newStock = 30;
        const stockDiff = newStock - oldStock; // +18
        final now = DateTime(2026, 8, 17, 17, 0, 0);

        final auditTx = InventoryTransaction(
          id: 'audit_${now.millisecondsSinceEpoch}_prod_test',
          productId: 'prod_test',
          type: TransactionType.inventoryAudit,
          quantity: stockDiff.abs(),
          date: now,
          note: 'Cân bằng kho trực tiếp (Tồn cũ: $oldStock -> Tồn mới: $newStock, chênh lệch: ${stockDiff > 0 ? "+$stockDiff" : "$stockDiff"})',
          importPrice: 20000.0,
          createdBy: 'admin_dt',
          createdByName: 'Admin Đông Thắng',
          storeId: 'store_001',
          isAuditNegative: stockDiff < 0,
          auditDifference: stockDiff,
        );

        expect(auditTx.type, equals(TransactionType.inventoryAudit));
        expect(auditTx.quantity, equals(18));
        expect(auditTx.auditDifference, equals(18));
        expect(auditTx.isAuditNegative, isFalse);
        expect(auditTx.storeId, equals('store_001'));
        expect(auditTx.note, contains('Tồn cũ: 12 -> Tồn mới: 30, chênh lệch: +18'));
      });

      test('Audit Transaction accurately generated for Negative adjustment (-22)', () {
        const oldStock = 50;
        const newStock = 28;
        const stockDiff = newStock - oldStock; // -22
        final now = DateTime(2026, 8, 17, 17, 15, 0);

        final auditTx = InventoryTransaction(
          id: 'audit_${now.millisecondsSinceEpoch}_prod_test',
          productId: 'prod_test',
          type: TransactionType.inventoryAudit,
          quantity: stockDiff.abs(),
          date: now,
          note: 'Cân bằng kho trực tiếp (Tồn cũ: $oldStock -> Tồn mới: $newStock, chênh lệch: ${stockDiff > 0 ? "+$stockDiff" : "$stockDiff"})',
          importPrice: 20000.0,
          createdBy: 'admin_tb',
          createdByName: 'Admin Thới Bình',
          storeId: 'store_002',
          isAuditNegative: stockDiff < 0,
          auditDifference: stockDiff,
        );

        expect(auditTx.type, equals(TransactionType.inventoryAudit));
        expect(auditTx.quantity, equals(22));
        expect(auditTx.auditDifference, equals(-22));
        expect(auditTx.isAuditNegative, isTrue);
        expect(auditTx.storeId, equals('store_002'));
        expect(auditTx.note, contains('Tồn cũ: 50 -> Tồn mới: 28, chênh lệch: -22'));
      });

      test('Multi-store ledger balance reconciliation matches independent store net delta', () {
        // Initial stocks: store_001 = 50, store_002 = 70
        const initialStore001 = 50;
        const initialStore002 = 70;

        final List<InventoryTransaction> ledger = [
          // Store 1 mutations: +20, -15, +35 => Net Store 1 = +40 (Final = 90)
          InventoryTransaction(
            id: 'tx_1',
            productId: 'prod_ledger',
            type: TransactionType.inventoryAudit,
            quantity: 20,
            date: DateTime(2026, 8, 17, 9, 0),
            note: '+20',
            storeId: 'store_001',
            isAuditNegative: false,
            auditDifference: 20,
          ),
          InventoryTransaction(
            id: 'tx_2',
            productId: 'prod_ledger',
            type: TransactionType.inventoryAudit,
            quantity: 15,
            date: DateTime(2026, 8, 17, 10, 0),
            note: '-15',
            storeId: 'store_001',
            isAuditNegative: true,
            auditDifference: -15,
          ),
          InventoryTransaction(
            id: 'tx_3',
            productId: 'prod_ledger',
            type: TransactionType.inventoryAudit,
            quantity: 35,
            date: DateTime(2026, 8, 17, 11, 0),
            note: '+35',
            storeId: 'store_001',
            isAuditNegative: false,
            auditDifference: 35,
          ),

          // Store 2 mutations: -30, +10 => Net Store 2 = -20 (Final = 50)
          InventoryTransaction(
            id: 'tx_4',
            productId: 'prod_ledger',
            type: TransactionType.inventoryAudit,
            quantity: 30,
            date: DateTime(2026, 8, 17, 12, 0),
            note: '-30',
            storeId: 'store_002',
            isAuditNegative: true,
            auditDifference: -30,
          ),
          InventoryTransaction(
            id: 'tx_5',
            productId: 'prod_ledger',
            type: TransactionType.inventoryAudit,
            quantity: 10,
            date: DateTime(2026, 8, 17, 13, 0),
            note: '+10',
            storeId: 'store_002',
            isAuditNegative: false,
            auditDifference: 10,
          ),
        ];

        // Reconcile Store 1
        final store1Txs = ledger.where((tx) => tx.storeId == 'store_001').toList();
        final store1NetDiff = store1Txs.fold<int>(0, (sum, tx) => sum + (tx.auditDifference ?? 0));
        expect(store1NetDiff, equals(40));
        expect(initialStore001 + store1NetDiff, equals(90));

        // Reconcile Store 2
        final store2Txs = ledger.where((tx) => tx.storeId == 'store_002').toList();
        final store2NetDiff = store2Txs.fold<int>(0, (sum, tx) => sum + (tx.auditDifference ?? 0));
        expect(store2NetDiff, equals(-20));
        expect(initialStore002 + store2NetDiff, equals(50));

        // Reconcile Total Ledger Aggregate
        final totalNetDiff = ledger.fold<int>(0, (sum, tx) => sum + (tx.auditDifference ?? 0));
        expect(totalNetDiff, equals(20)); // +40 + (-20) = +20
        expect((initialStore001 + initialStore002) + totalNetDiff, equals(90 + 50));
      });
    });

    // =========================================================================
    // SECTION 4: End-to-End Widget Alternating Store Mutations in ProductDetailPage
    // =========================================================================
    group('4. ProductDetailPage End-to-End Alternating Store Mutation Flow', () {
      const baseProduct = Product(
        id: 'prod_e2e_m2',
        name: 'Cà Phê Hòa Tan G7 3in1',
        code: 'G7-3IN1',
        barcode: '893500302001',
        price: 45000,
        costPrice: 32000,
        branchStocks: {'store_001': 50, 'store_002': 30}, // Total: 80
        category: 'Cà phê',
      );

      testWidgets(
          'Step-by-step alternating UI mutations: store_001 (+15) then store_002 (-15) then store_001 (+15)',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeProductRepo = _FakeProductRepository();
        final fakeInventoryRepo = _FakeInventoryRepository();

        // ---------------------------------------------------------------------
        // SUB-STEP 1: Active Store = store_001 (Edit 50 -> 65, +15)
        // ---------------------------------------------------------------------
        await tester.pumpWidget(
          _buildChallengerM2App(
            child: const ProductDetailPage(product: baseProduct),
            storeId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: [baseProduct],
          ),
        );
        await tester.pumpAndSettle();

        // Verify pre-fill for store_001
        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        expect(find.text('Số lượng tồn kho (Chi nhánh Đông Thắng)'), findsOneWidget);
        final stockField1 = find.widgetWithText(TextField, '50');
        expect(stockField1, findsOneWidget);

        await tester.enterText(stockField1, '65');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        // Verify product 1 state
        final productAfterStep1 = fakeProductRepo.lastUpsertedProduct!;
        expect(productAfterStep1.branchStocks['store_001'], equals(65));
        expect(productAfterStep1.branchStocks['store_002'], equals(30)); // isolated
        expect(productAfterStep1.stock, equals(95)); // 65 + 30 = 95

        // Verify audit 1
        expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
        final tx1 = fakeInventoryRepo.recordedTransactions[0];
        expect(tx1.storeId, equals('store_001'));
        expect(tx1.isAuditNegative, isFalse);
        expect(tx1.auditDifference, equals(15));
        expect(tx1.quantity, equals(15));

        // ---------------------------------------------------------------------
        // SUB-STEP 2: Active Store = store_002 (Edit 30 -> 15, -15)
        // ---------------------------------------------------------------------
        await tester.pumpWidget(
          _buildChallengerM2App(
            child: ProductDetailPage(product: productAfterStep1),
            storeId: 'store_002',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: [productAfterStep1],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        expect(find.text('Số lượng tồn kho (Chi nhánh Thới Bình)'), findsOneWidget);
        final stockField2 = find.widgetWithText(TextField, '30');
        expect(stockField2, findsOneWidget);

        await tester.enterText(stockField2, '15');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        // Verify product 2 state
        final productAfterStep2 = fakeProductRepo.lastUpsertedProduct!;
        expect(productAfterStep2.branchStocks['store_001'], equals(65)); // preserved from step 1
        expect(productAfterStep2.branchStocks['store_002'], equals(15));
        expect(productAfterStep2.stock, equals(80)); // 65 + 15 = 80

        // Verify audit 2
        expect(fakeInventoryRepo.recordedTransactions.length, equals(2));
        final tx2 = fakeInventoryRepo.recordedTransactions[1];
        expect(tx2.storeId, equals('store_002'));
        expect(tx2.isAuditNegative, isTrue);
        expect(tx2.auditDifference, equals(-15));
        expect(tx2.quantity, equals(15));

        // ---------------------------------------------------------------------
        // SUB-STEP 3: Active Store = store_001 (Edit 65 -> 80, +15)
        // ---------------------------------------------------------------------
        await tester.pumpWidget(
          _buildChallengerM2App(
            child: ProductDetailPage(product: productAfterStep2),
            storeId: 'store_001',
            productRepo: fakeProductRepo,
            inventoryRepo: fakeInventoryRepo,
            products: [productAfterStep2],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();

        expect(find.text('Số lượng tồn kho (Chi nhánh Đông Thắng)'), findsOneWidget);
        final stockField3 = find.widgetWithText(TextField, '65');
        expect(stockField3, findsOneWidget);

        await tester.enterText(stockField3, '80');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        // Verify final product state
        final productFinal = fakeProductRepo.lastUpsertedProduct!;
        expect(productFinal.branchStocks['store_001'], equals(80));
        expect(productFinal.branchStocks['store_002'], equals(15)); // preserved from step 2
        expect(productFinal.stock, equals(95)); // 80 + 15 = 95

        // Verify audit 3
        expect(fakeInventoryRepo.recordedTransactions.length, equals(3));
        final tx3 = fakeInventoryRepo.recordedTransactions[2];
        expect(tx3.storeId, equals('store_001'));
        expect(tx3.isAuditNegative, isFalse);
        expect(tx3.auditDifference, equals(15));
        expect(tx3.quantity, equals(15));

        // Final sanity check across the entire audit transaction log
        final store1AuditDiffTotal = fakeInventoryRepo.recordedTransactions
            .where((tx) => tx.storeId == 'store_001')
            .fold<int>(0, (acc, tx) => acc + (tx.auditDifference ?? 0));
        final store2AuditDiffTotal = fakeInventoryRepo.recordedTransactions
            .where((tx) => tx.storeId == 'store_002')
            .fold<int>(0, (acc, tx) => acc + (tx.auditDifference ?? 0));

        expect(store1AuditDiffTotal, equals(30)); // +15 + 15 = +30 (from 50 to 80)
        expect(store2AuditDiffTotal, equals(-15)); // -15 (from 30 to 15)
        expect(productFinal.branchStocks['store_001'], equals(50 + store1AuditDiffTotal));
        expect(productFinal.branchStocks['store_002'], equals(30 + store2AuditDiffTotal));
      });
    });
  });
}
