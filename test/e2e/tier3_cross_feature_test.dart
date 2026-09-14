import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/data/models/inventory_transaction_model.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

// --- Test Utilities, Fakes & Mocks ---

final _transparentPixelPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
];

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _transparentPixelPng.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(_transparentPixelPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProductRepository implements ProductRepository {
  final List<Product> products;
  Product? lastUpsertedProduct;
  String? lastDeletedId;

  FakeProductRepository([List<Product>? initial])
      : products = initial != null ? List<Product>.from(initial) : [];

  @override
  Stream<List<Product>> watchAll() => Stream.value(products);

  @override
  Future<List<Product>> fetchAll() async => products;

  @override
  Future<Product?> fetchById(String id) async {
    try {
      return products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> upsert(Product product) async {
    lastUpsertedProduct = product;
    final index = products.indexWhere((p) => p.id == product.id);
    if (index >= 0) {
      products[index] = product;
    } else {
      products.add(product);
    }
  }

  @override
  Future<void> delete(String id) async {
    lastDeletedId = id;
    products.removeWhere((p) => p.id == id);
  }

  @override
  Future<void> updateStock(String id, int newStock) async {
    final index = products.indexWhere((p) => p.id == id);
    if (index >= 0) {
      products[index] = products[index].copyWith(
        branchStocks: {'store_001': newStock, 'store_002': 0},
      );
    }
  }
}

class FakeInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  Stream<List<InventoryTransaction>> watchAll() => Stream.value(transactions);

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(transactions.where((t) => t.productId == productId).toList());

  @override
  Future<void> record(InventoryTransaction transaction) async {
    transactions.add(transaction);
  }

  Future<List<InventoryTransaction>> fetchByProduct(String productId) async =>
      transactions.where((t) => t.productId == productId).toList();

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
      DateTime startDate, DateTime endDate) {
    return Stream.value(transactions
        .where((t) =>
            t.date.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
            t.date.isBefore(endDate.add(const Duration(seconds: 1))))
        .toList());
  }
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

Widget _wrapWithApp({
  required Widget child,
  required UserAccount user,
  required String currentStoreId,
  FakeProductRepository? productRepo,
  FakeInventoryRepository? inventoryRepo,
  List<Category>? categories,
  List<Branch>? branches,
  Map<String, String>? availableStores,
}) {
  final pRepo = productRepo ?? FakeProductRepository();
  final iRepo = inventoryRepo ?? FakeInventoryRepository();
  final cats = categories ??
      [
        const Category(id: 'cat_01', name: 'Đồ uống'),
        const Category(id: 'cat_02', name: 'Bánh kẹo'),
        const Category(id: 'cat_03', name: 'Gia dụng'),
      ];
  final brs = branches ??
      const [
        Branch('store_001', 'Chi nhánh Đông Thắng'),
        Branch('store_002', 'Chi nhánh Thới Bình'),
      ];
  final stores = availableStores ??
      {
        'store_001': 'Chi nhánh Đông Thắng',
        'store_002': 'Chi nhánh Thới Bình',
      };

  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
      currentStoreIdProvider.overrideWithValue(currentStoreId),
      productRepositoryProvider.overrideWithValue(pRepo),
      productListProvider.overrideWith((ref) => Stream.value(pRepo.products)),
      categoryListProvider.overrideWith((ref) => Stream.value(cats)),
      branchesProvider.overrideWithValue(brs),
      availableStoresProvider.overrideWith((ref) => Future.value(stores)),
      inventoryRepositoryProvider.overrideWithValue(iRepo),
      transactionsByProductProvider.overrideWith((ref, id) =>
          Stream.value(iRepo.transactions.where((t) => t.productId == id).toList())),
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
  HttpOverrides.global = _MockHttpOverrides();

  const adminUser = UserAccount(
    username: 'admin_test',
    displayName: 'Quản Lý Hệ Thống',
    role: 'supervisor',
    storeId: 'store_001',
  );

  group('Tier 3: Pairwise & Cross-Feature Interaction Tests', () {
    // =========================================================================
    // Test 1: F1 + F3: Canonical normalization with UI badges and detail tables
    // =========================================================================
    testWidgets(
        'T3-01 [F1+F3]: Canonical and legacy branch stocks render accurate UI badges and detail tables with 100% parity',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Canonical product
      const canonicalProduct = Product(
        id: 'p_canonical_01',
        name: 'Nước Ngọt Coca Cola 330ml',
        code: 'COCA01',
        price: 10000,
        costPrice: 7000,
        branchStocks: {'store_001': 25, 'store_002': 35}, // Total = 60
        category: 'Đồ uống',
      );

      // Legacy product
      const legacyProduct = Product(
        id: 'p_legacy_01',
        name: 'Bia Saigon Special 330ml',
        code: 'BSG01',
        price: 15000,
        costPrice: 11000,
        branchStocks: {'branch_1': 40, 'branch_2': 10}, // Total = 50
        category: 'Đồ uống',
      );

      // 1. Verify ProductTile for canonical product
      await tester.pumpWidget(_wrapWithApp(
        child: const Scaffold(body: ProductTile(product: canonicalProduct)),
        user: adminUser,
        currentStoreId: 'store_001',
      ));
      await tester.pumpAndSettle();

      expect(find.text('ĐT: 25 | TB: 35'), findsOneWidget);
      expect(find.text('Tồn: 60'), findsOneWidget);

      // 2. Verify ProductDetailPage for canonical product
      await tester.pumpWidget(_wrapWithApp(
        child: const ProductDetailPage(product: canonicalProduct),
        user: adminUser,
        currentStoreId: 'store_001',
      ));
      await tester.pumpAndSettle();

      expect(find.text('Phân bổ tồn kho theo chi nhánh'), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.text('35'), findsOneWidget);
      expect(find.text('Tổng: 60'), findsOneWidget);

      // 3. Verify ProductTile for legacy product
      await tester.pumpWidget(_wrapWithApp(
        child: const Scaffold(body: ProductTile(product: legacyProduct)),
        user: adminUser,
        currentStoreId: 'store_001',
      ));
      await tester.pumpAndSettle();

      expect(find.text('ĐT: 40 | TB: 10'), findsOneWidget);
      expect(find.text('Tồn: 50'), findsOneWidget);

      // 4. Verify ProductDetailPage for legacy product
      await tester.pumpWidget(_wrapWithApp(
        child: const ProductDetailPage(product: legacyProduct),
        user: adminUser,
        currentStoreId: 'store_001',
      ));
      await tester.pumpAndSettle();

      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('Tổng: 50'), findsOneWidget);
    });

    // =========================================================================
    // Test 2 & 3: F2 + F4 + F5: Branch provider with active store pre-fill
    // =========================================================================
    testWidgets(
        'T3-02 [F2+F4+F5]: In store_001, edit form pre-fills with store_001 stock and respects canonical branch list',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const product = Product(
        id: 'p_scope_01',
        name: 'Sữa Tươi Tiệt Trùng Vinamilk 1L',
        code: 'VNM01',
        price: 32000,
        costPrice: 24000,
        branchStocks: {'store_001': 50, 'store_002': 18}, // Total = 68
        category: 'Đồ uống',
      );

      final repo = FakeProductRepository([product]);

      await tester.pumpWidget(_wrapWithApp(
        child: const ProductDetailPage(product: product),
        user: adminUser,
        currentStoreId: 'store_001',
        productRepo: repo,
      ));
      await tester.pumpAndSettle();

      // Enter edit mode
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      // Assert pre-filled value is 50 (store_001 stock, NOT 68 total)
      final stockInput = find.widgetWithText(TextFormField, '50');
      expect(stockInput, findsOneWidget);
    });

    testWidgets(
        'T3-03 [F2+F4+F5]: In store_002, edit form pre-fills with store_002 stock without store ID inversion',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const product = Product(
        id: 'p_scope_02',
        name: 'Nước Mắm Nam Ngư 500ml',
        code: 'NN01',
        price: 28000,
        costPrice: 20000,
        branchStocks: {'store_001': 100, 'store_002': 28},
        category: 'Gia vị',
      );

      final repo = FakeProductRepository([product]);

      await tester.pumpWidget(_wrapWithApp(
        child: const ProductDetailPage(product: product),
        user: adminUser,
        currentStoreId: 'store_002',
        productRepo: repo,
      ));
      await tester.pumpAndSettle();

      // Enter edit mode
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      // Assert pre-filled value is 28 (store_002 stock, NOT 128 total)
      final stockInput = find.widgetWithText(TextFormField, '28');
      expect(stockInput, findsOneWidget);
    });

    // =========================================================================
    // Test 4 & 5: F4 + F6 + F7: Form pre-fill + scoped mutation + structured audit
    // =========================================================================
    testWidgets(
        'T3-04 [F4+F6+F7]: Positive stock edit (+8) in store_001 updates branchStocks, recalibrates stock, and records positive audit transaction',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const initialProduct = Product(
        id: 'p_audit_pos_01',
        name: 'Hạt Nêm Knorr Nấm Hương 400g',
        code: 'KNR01',
        price: 35000,
        costPrice: 25000,
        branchStocks: {'store_001': 20, 'store_002': 15}, // Total = 35
        category: 'Gia vị',
      );

      final pRepo = FakeProductRepository([initialProduct]);
      final iRepo = FakeInventoryRepository();

      await tester.pumpWidget(_wrapWithApp(
        child: const ProductDetailPage(product: initialProduct),
        user: adminUser,
        currentStoreId: 'store_001',
        productRepo: pRepo,
        inventoryRepo: iRepo,
      ));
      await tester.pumpAndSettle();

      // Tap Edit
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      // Modify stock from 20 -> 28 (+8)
      final stockField = find.widgetWithText(TextFormField, '20');
      expect(stockField, findsOneWidget);
      await tester.enterText(stockField, '28');
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      // 1. Verify Product update
      final updated = pRepo.lastUpsertedProduct!;
      expect(updated.branchStocks['store_001'], equals(28));
      expect(updated.branchStocks['store_002'], equals(15)); // Unchanged
      expect(updated.stock, equals(43)); // 28 + 15 = 43

      // 2. Verify Structured Audit Transaction
      expect(iRepo.transactions.length, equals(1));
      final auditTx = iRepo.transactions.first;
      expect(auditTx.productId, equals(initialProduct.id));
      expect(auditTx.type, equals(TransactionType.inventoryAudit));
      expect(auditTx.quantity, equals(8));
      expect(auditTx.importPrice, equals(initialProduct.costPrice));
      expect(auditTx.note, contains('Tồn cũ: 20 -> Tồn mới: 28, chênh lệch: +8'));
    });

    testWidgets(
        'T3-05 [F4+F6+F7]: Negative stock edit (-8) in store_002 updates branchStocks, recalibrates stock, and records negative audit transaction',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const initialProduct = Product(
        id: 'p_audit_neg_01',
        name: 'Mì Tôm Hảo Hảo Tôm Chua Cay',
        code: 'HH01',
        price: 4500,
        costPrice: 3200,
        branchStocks: {'store_001': 50, 'store_002': 30}, // Total = 80
        category: 'Bánh kẹo',
      );

      final pRepo = FakeProductRepository([initialProduct]);
      final iRepo = FakeInventoryRepository();

      await tester.pumpWidget(_wrapWithApp(
        child: const ProductDetailPage(product: initialProduct),
        user: adminUser,
        currentStoreId: 'store_002',
        productRepo: pRepo,
        inventoryRepo: iRepo,
      ));
      await tester.pumpAndSettle();

      // Tap Edit
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      // Modify stock from 30 -> 22 (-8)
      final stockField = find.widgetWithText(TextFormField, '30');
      expect(stockField, findsOneWidget);
      await tester.enterText(stockField, '22');
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      // 1. Verify Product update
      final updated = pRepo.lastUpsertedProduct!;
      expect(updated.branchStocks['store_002'], equals(22));
      expect(updated.branchStocks['store_001'], equals(50)); // Unchanged
      expect(updated.stock, equals(72)); // 50 + 22 = 72

      // 2. Verify Structured Audit Transaction
      expect(iRepo.transactions.length, equals(1));
      final auditTx = iRepo.transactions.first;
      expect(auditTx.productId, equals(initialProduct.id));
      expect(auditTx.type, equals(TransactionType.inventoryAudit));
      expect(auditTx.quantity, equals(8));
      expect(auditTx.note, contains('Tồn cũ: 30 -> Tồn mới: 22, chênh lệch: -8'));
    });

    // =========================================================================
    // Test 6: F6 + F8 + F9: Direct stock adjustment (+ and -) reflecting into FIFO
    // =========================================================================
    test(
        'T3-06 [F6+F8+F9]: Positive audit creates new FIFO lot, while negative audit sequentially drains oldest lots before POS sale',
        () {
      final now = DateTime(2024, 6, 1);
      final txs = [
        // 1. Initial import: 10 units @ 10,000 VND
        InventoryTransaction(
          id: 'tx_imp_1',
          productId: 'prod_fifo_audit',
          type: TransactionType.import,
          quantity: 10,
          date: now,
          note: 'Nhập hàng đợt 1',
          importPrice: 10000,
        ),
        // 2. Direct stock adjustment increase (+5 units @ 12,000 VND)
        InventoryTransaction(
          id: 'tx_audit_pos',
          productId: 'prod_fifo_audit',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: now.add(const Duration(days: 1)),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 15, chênh lệch: +5)',
          importPrice: 12000,
        ),
        // 3. Direct stock adjustment decrease (-3 units)
        InventoryTransaction(
          id: 'tx_audit_neg',
          productId: 'prod_fifo_audit',
          type: TransactionType.inventoryAudit,
          quantity: 3,
          date: now.add(const Duration(days: 2)),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 15 -> Tồn mới: 12, chênh lệch: -3)',
          importPrice: 10000,
        ),
      ];

      final calculator = FifoCalculator(txs);
      final lots = calculator.getInventoryLots('prod_fifo_audit');

      expect(lots.length, equals(2));
      // Lot 1: 10 - 3 (negative audit drain) = 7 units @ 10k
      expect(lots[0].remainingQuantity, equals(7));
      expect(lots[0].importPrice, equals(10000));
      // Lot 2: 5 units @ 12k
      expect(lots[1].remainingQuantity, equals(5));
      expect(lots[1].importPrice, equals(12000));

      // POS Sale: Sell 10 units
      // Should consume 7 units @ 10,000 + 3 units @ 12,000 = 70,000 + 36,000 = 106,000 VND
      final saleCost = calculator.calculateCostForSale(
        productId: 'prod_fifo_audit',
        quantity: 10,
        saleDate: now.add(const Duration(days: 3)),
      );

      expect(saleCost, equals(106000));
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(2));
    });

    // =========================================================================
    // Test 7: F8 + F9 Case 3 + F1: Store-partitioned transfer with unit cost preservation
    // =========================================================================
    test(
        'T3-07 [F8+F9+F1]: Inter-store transfer deducts source FIFO lot and propagates exact unit cost to target store queue',
        () {
      final now = DateTime(2024, 7, 1);

      // Source Store (store_001) transactions:
      final store1Import = InventoryTransaction(
        id: 'tx_s1_imp',
        productId: 'prod_transfer',
        type: TransactionType.import,
        quantity: 20,
        date: now,
        note: 'Nhập kho chi nhánh Đông Thắng',
        importPrice: 15000,
      );

      // Target Store (store_002) transactions:
      // Transfer of 8 units from store_001 with preserved cost 15,000 VND
      final store2ImportTransfer = InventoryTransaction(
        id: 'tx_s2_transfer_imp',
        productId: 'prod_transfer',
        type: TransactionType.import,
        quantity: 8,
        date: now.add(const Duration(hours: 4)),
        note: 'Nhận chuyển kho từ Chi nhánh Đông Thắng',
        importPrice: 15000, // Preserved cost basis!
      );

      final trackerStore1 = FifoCalculator([store1Import]);
      final trackerStore2 = FifoCalculator([store2ImportTransfer]);

      // Deduct 8 units from source tracker
      final store1ExportCost = trackerStore1.calculateCostForSale(
        productId: 'prod_transfer',
        quantity: 8,
        saleDate: now.add(const Duration(hours: 2)),
      );
      expect(store1ExportCost, equals(120000)); // 8 * 15k
      expect(trackerStore1.getInventoryLots('prod_transfer')[0].remainingQuantity, equals(12));

      // In target store (store_002): sell 5 units
      final store2SaleCost = trackerStore2.calculateCostForSale(
        productId: 'prod_transfer',
        quantity: 5,
        saleDate: now.add(const Duration(hours: 6)),
      );
      expect(store2SaleCost, equals(75000)); // 5 * 15k
      expect(trackerStore2.getInventoryLots('prod_transfer')[0].remainingQuantity, equals(3));

      // In source store (store_001): sell 5 units from remaining 12
      final store1SubsequentSaleCost = trackerStore1.calculateCostForSale(
        productId: 'prod_transfer',
        quantity: 5,
        saleDate: now.add(const Duration(hours: 7)),
      );
      expect(store1SubsequentSaleCost, equals(75000));
      expect(trackerStore1.getInventoryLots('prod_transfer')[0].remainingQuantity, equals(7));
    });

    // =========================================================================
    // Test 8: F8 + F9 Case 6 + F3: Sales return prepending at index 0 & UI stock parity
    // =========================================================================
    testWidgets(
        'T3-08 [F8+F9+F3]: Sales return prepends lot to head of queue, prioritizes it on resale, and reflects in UI badges',
        (tester) async {
      final now = DateTime(2024, 8, 1);

      // Existing store queue with 10 units @ 20,000 VND
      final initialTx = InventoryTransaction(
        id: 'tx_init',
        productId: 'prod_return_ui',
        type: TransactionType.import,
        quantity: 10,
        date: now,
        note: 'Lô nhập ban đầu',
        importPrice: 20000,
      );

      final fifo = FifoCalculator([initialTx]);

      // Customer returns 3 units with original acquisition cost 14,000 VND
      // Case 6: Prepend to head of queue (index 0)
      final lots = fifo.getInventoryLots('prod_return_ui');
      lots.insert(
        0,
        InventoryLot(
          transactionId: 'tx_return_01',
          importDate: now.add(const Duration(days: 1)),
          importPrice: 14000,
          remainingQuantity: 3,
        ),
      );

      expect(lots.length, equals(2));
      expect(lots[0].importPrice, equals(14000)); // Returned lot at HEAD
      expect(lots[0].remainingQuantity, equals(3));
      expect(lots[1].importPrice, equals(20000)); // Original lot
      expect(lots[1].remainingQuantity, equals(10));

      // Subsequent sale of 5 units: consumes 3 @ 14,000 + 2 @ 20,000 = 42,000 + 40,000 = 82,000 VND
      final cost = fifo.calculateCostForSale(
        productId: 'prod_return_ui',
        quantity: 5,
        saleDate: now.add(const Duration(days: 2)),
      );
      expect(cost, equals(82000));
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(8));

      // Now verify UI stock parity
      // Total remaining stock in store_002 is 8, store_001 has 12
      const updatedProduct = Product(
        id: 'prod_return_ui',
        name: 'Khăn Ướt Bobby 100 Tờ',
        code: 'BOB01',
        price: 35000,
        costPrice: 20000,
        branchStocks: {'store_001': 12, 'store_002': 8},
        category: 'Gia dụng',
      );

      await tester.pumpWidget(_wrapWithApp(
        child: const Scaffold(body: ProductTile(product: updatedProduct)),
        user: adminUser,
        currentStoreId: 'store_002',
      ));
      await tester.pumpAndSettle();

      expect(find.text('ĐT: 12 | TB: 8'), findsOneWidget);
      expect(find.text('Tồn: 20'), findsOneWidget);
    });

    // =========================================================================
    // Test 9: F1 + F7 + F8 + F9: Full multi-store transaction history playback
    // =========================================================================
    test(
        'T3-09 [F1+F7+F8+F9]: Full multi-store transaction history playback confirms complete FIFO state isolation and accurate COGS',
        () {
      final baseDate = DateTime(2024, 9, 1);

      // Interleaved multi-store transactions
      final allTransactions = [
        // Store 1 Import
        InventoryTransaction(
          id: 's1_t1',
          productId: 'prod_playback',
          type: TransactionType.import,
          quantity: 30,
          date: baseDate,
          note: 'Store 1 Import Lot A',
          importPrice: 10000,
        ),
        // Store 2 Import
        InventoryTransaction(
          id: 's2_t1',
          productId: 'prod_playback',
          type: TransactionType.import,
          quantity: 20,
          date: baseDate.add(const Duration(hours: 1)),
          note: 'Store 2 Import Lot X',
          importPrice: 18000,
        ),
        // Store 1 Positive Audit
        InventoryTransaction(
          id: 's1_t2',
          productId: 'prod_playback',
          type: TransactionType.inventoryAudit,
          quantity: 10,
          date: baseDate.add(const Duration(hours: 2)),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 30 -> Tồn mới: 40, chênh lệch: +10)',
          importPrice: 12000,
        ),
        // Store 2 Negative Audit
        InventoryTransaction(
          id: 's2_t2',
          productId: 'prod_playback',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: baseDate.add(const Duration(hours: 3)),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 20 -> Tồn mới: 15, chênh lệch: -5)',
          importPrice: 18000,
        ),
      ];

      // Partition transactions strictly by store
      final s1Txs = allTransactions.where((t) => t.id.startsWith('s1')).toList();
      final s2Txs = allTransactions.where((t) => t.id.startsWith('s2')).toList();

      final trackerS1 = FifoCalculator(s1Txs);
      final trackerS2 = FifoCalculator(s2Txs);

      // Verify Store 1 state: Lot 1 (30 @ 10k), Lot 2 (10 @ 12k) -> Total = 40
      final lotsS1 = trackerS1.getInventoryLots('prod_playback');
      expect(lotsS1.length, equals(2));
      expect(lotsS1[0].remainingQuantity, equals(30));
      expect(lotsS1[1].remainingQuantity, equals(10));

      // Verify Store 2 state: Lot 1 (20 - 5 = 15 @ 18k) -> Total = 15
      final lotsS2 = trackerS2.getInventoryLots('prod_playback');
      expect(lotsS2.length, equals(1));
      expect(lotsS2[0].remainingQuantity, equals(15));
      expect(lotsS2[0].importPrice, equals(18000));

      // Store 1 Sale: 35 units -> 30 @ 10k + 5 @ 12k = 360,000 VND
      final costS1 = trackerS1.calculateCostForSale(
        productId: 'prod_playback',
        quantity: 35,
        saleDate: baseDate.add(const Duration(days: 1)),
      );
      expect(costS1, equals(360000));
      expect(lotsS1[0].remainingQuantity, equals(0));
      expect(lotsS1[1].remainingQuantity, equals(5));

      // Store 2 Sale: 10 units -> 10 @ 18k = 180,000 VND
      final costS2 = trackerS2.calculateCostForSale(
        productId: 'prod_playback',
        quantity: 10,
        saleDate: baseDate.add(const Duration(days: 1, hours: 2)),
      );
      expect(costS2, equals(180000));
      expect(lotsS2[0].remainingQuantity, equals(5));

      // Zero cross-contamination
      expect(lotsS1[1].remainingQuantity, equals(5));
      expect(lotsS2[0].remainingQuantity, equals(5));
    });

    // =========================================================================
    // Test 10: F2 + F3 + F4 + F6: Store switcher sequential edit cycles
    // =========================================================================
    testWidgets(
        'T3-10 [F2+F3+F4+F6]: Sequential edit cycles in store_001 then store_002 maintain perfect cross-store isolation and UI synchronization',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const initialProduct = Product(
        id: 'p_switch_cycle',
        name: 'Dầu Gội Sunsilk 650g',
        code: 'SUN01',
        price: 130000,
        costPrice: 95000,
        branchStocks: {'store_001': 30, 'store_002': 20}, // Total = 50
        category: 'Hóa mỹ phẩm',
      );

      final repo = FakeProductRepository([initialProduct]);

      // --- Cycle 1: Edit in store_001 (30 -> 35) ---
      await tester.pumpWidget(_wrapWithApp(
        child: const ProductDetailPage(product: initialProduct),
        user: adminUser,
        currentStoreId: 'store_001',
        productRepo: repo,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, '30'), '35');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      final prodAfterS1 = repo.lastUpsertedProduct!;
      expect(prodAfterS1.branchStocks['store_001'], equals(35));
      expect(prodAfterS1.branchStocks['store_002'], equals(20)); // Untouched
      expect(prodAfterS1.stock, equals(55));

      // --- Cycle 2: Edit in store_002 (20 -> 15) ---
      await tester.pumpWidget(_wrapWithApp(
        child: ProductDetailPage(product: prodAfterS1),
        user: adminUser,
        currentStoreId: 'store_002',
        productRepo: repo,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, '20'), '15');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      final prodAfterS2 = repo.lastUpsertedProduct!;
      expect(prodAfterS2.branchStocks['store_001'], equals(35)); // Preserved
      expect(prodAfterS2.branchStocks['store_002'], equals(15)); // Updated
      expect(prodAfterS2.stock, equals(50));

      // Verify ProductTile renders final state
      await tester.pumpWidget(_wrapWithApp(
        child: Scaffold(body: ProductTile(product: prodAfterS2)),
        user: adminUser,
        currentStoreId: 'store_001',
      ));
      await tester.pumpAndSettle();

      expect(find.text('ĐT: 35 | TB: 15'), findsOneWidget);
      expect(find.text('Tồn: 50'), findsOneWidget);
    });

    // =========================================================================
    // Test 11: F8 + F9 Case 2 + F9 Case 6: POS sale -> Customer return -> Resale
    // =========================================================================
    test(
        'T3-11 [F8+F9]: POS sale followed by customer return and subsequent resale accurately consumes returned lot at original cost before higher cost lots',
        () {
      final now = DateTime(2024, 10, 1);

      // Initial lots: Lot 1 (10 @ 10,000 VND), Lot 2 (10 @ 25,000 VND)
      final txs = [
        InventoryTransaction(
          id: 'tx_imp_1',
          productId: 'prod_lifecycle',
          type: TransactionType.import,
          quantity: 10,
          date: now,
          note: 'Lô nhập 1 (giá rẻ)',
          importPrice: 10000,
        ),
        InventoryTransaction(
          id: 'tx_imp_2',
          productId: 'prod_lifecycle',
          type: TransactionType.import,
          quantity: 10,
          date: now.add(const Duration(days: 1)),
          note: 'Lô nhập 2 (giá cao)',
          importPrice: 25000,
        ),
      ];

      final fifo = FifoCalculator(txs);

      // Step 1: Sale of 5 units (from Lot 1)
      final sale1Cost = fifo.calculateCostForSale(
        productId: 'prod_lifecycle',
        quantity: 5,
        saleDate: now.add(const Duration(days: 2)),
      );
      expect(sale1Cost, equals(50000)); // 5 * 10k

      // Step 2: Customer returns 2 units (cost 10,000 VND)
      final lots = fifo.getInventoryLots('prod_lifecycle');
      lots.insert(
        0,
        InventoryLot(
          transactionId: 'tx_return',
          importDate: now.add(const Duration(days: 3)),
          importPrice: 10000,
          remainingQuantity: 2,
        ),
      );

      // Queue state: [2 @ 10k, 5 @ 10k, 10 @ 25k]
      expect(lots.length, equals(3));
      expect(lots[0].remainingQuantity, equals(2));
      expect(lots[0].importPrice, equals(10000));
      expect(lots[1].remainingQuantity, equals(5));
      expect(lots[1].importPrice, equals(10000));
      expect(lots[2].remainingQuantity, equals(10));
      expect(lots[2].importPrice, equals(25000));

      // Step 3: Resale of 8 units
      // Consumes: 2 @ 10k (return) + 5 @ 10k (Lot 1 rem) + 1 @ 25k (Lot 2) = 20k + 50k + 25k = 95,000 VND
      final sale2Cost = fifo.calculateCostForSale(
        productId: 'prod_lifecycle',
        quantity: 8,
        saleDate: now.add(const Duration(days: 4)),
      );

      expect(sale2Cost, equals(95000));
      expect(lots[0].remainingQuantity, equals(0));
      expect(lots[1].remainingQuantity, equals(0));
      expect(lots[2].remainingQuantity, equals(9)); // 9 units @ 25k left
    });

    // =========================================================================
    // Test 12: F6 + F8 + F9 Case 4 + F9 Case 5: Repeated audit variance cycles
    // =========================================================================
    test(
        'T3-12 [F6+F8+F9]: Repeated positive and negative audit variance cycles correctly drain and append lots across multi-stage inventory reconciliations',
        () {
      final now = DateTime(2024, 11, 1);

      // Initial: 20 units @ 10,000 VND
      final txs = [
        InventoryTransaction(
          id: 'tx_init',
          productId: 'prod_multi_audit',
          type: TransactionType.import,
          quantity: 20,
          date: now,
          note: 'Lô ban đầu',
          importPrice: 10000,
        ),
        // Audit 1 (+10 @ 12,000 VND)
        InventoryTransaction(
          id: 'tx_audit_1',
          productId: 'prod_multi_audit',
          type: TransactionType.inventoryAudit,
          quantity: 10,
          date: now.add(const Duration(days: 1)),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 20 -> Tồn mới: 30, chênh lệch: +10)',
          importPrice: 12000,
        ),
        // Audit 2 (-5 units)
        InventoryTransaction(
          id: 'tx_audit_2',
          productId: 'prod_multi_audit',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: now.add(const Duration(days: 2)),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 30 -> Tồn mới: 25, chênh lệch: -5)',
          importPrice: 10000,
        ),
        // Audit 3 (+5 @ 15,000 VND)
        InventoryTransaction(
          id: 'tx_audit_3',
          productId: 'prod_multi_audit',
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: now.add(const Duration(days: 3)),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 25 -> Tồn mới: 30, chênh lệch: +5)',
          importPrice: 15000,
        ),
        // Audit 4 (-20 units)
        InventoryTransaction(
          id: 'tx_audit_4',
          productId: 'prod_multi_audit',
          type: TransactionType.inventoryAudit,
          quantity: 20,
          date: now.add(const Duration(days: 4)),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 30 -> Tồn mới: 10, chênh lệch: -20)',
          importPrice: 10000,
        ),
      ];

      final fifo = FifoCalculator(txs);
      final lots = fifo.getInventoryLots('prod_multi_audit');

      // Math verification:
      // Init: Lot 1 = 20 @ 10k
      // Audit 1: Lot 1 = 20 @ 10k, Lot 2 = 10 @ 12k
      // Audit 2 (-5): Lot 1 = 15 @ 10k, Lot 2 = 10 @ 12k
      // Audit 3 (+5): Lot 1 = 15 @ 10k, Lot 2 = 10 @ 12k, Lot 3 = 5 @ 15k
      // Audit 4 (-20): Drains 15 from Lot 1 (exhausted) + 5 from Lot 2 (5 left @ 12k)
      expect(lots[0].remainingQuantity, equals(0)); // Lot 1 exhausted
      expect(lots[1].remainingQuantity, equals(5)); // Lot 2 has 5 left @ 12k
      expect(lots[2].remainingQuantity, equals(5)); // Lot 3 has 5 left @ 15k

      // Sale of 7 units: 5 @ 12k + 2 @ 15k = 60,000 + 30,000 = 90,000 VND
      final saleCost = fifo.calculateCostForSale(
        productId: 'prod_multi_audit',
        quantity: 7,
        saleDate: now.add(const Duration(days: 5)),
      );
      expect(saleCost, equals(90000));
      expect(lots[1].remainingQuantity, equals(0));
      expect(lots[2].remainingQuantity, equals(3));
    });

    // =========================================================================
    // Test 13: F1 + F6: Combo product stock is dynamic and does not emit audit transactions
    // =========================================================================
    testWidgets(
        'T3-13 [F1+F6]: Combo product edit mode shows dynamic computation notice and does not render stock text field or emit audit transaction',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const comp1 = Product(
        id: 'comp_01',
        name: 'Bia Heineken 330ml',
        code: 'KEN01',
        price: 22000,
        costPrice: 16000,
        branchStocks: {'store_001': 20, 'store_002': 10},
        category: 'Đồ uống',
      );

      const comboProduct = Product(
        id: 'p_combo_test',
        name: 'Combo Tiệc Vui',
        code: 'CB01',
        price: 80000,
        costPrice: 60000,
        branchStocks: {'store_001': 0, 'store_002': 0},
        category: 'Combo',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'comp_01',
            productCode: 'KEN01',
            productName: 'Bia Heineken 330ml',
            quantity: 2,
            costPrice: 16000,
          ),
        ],
      );

      final pRepo = FakeProductRepository([comp1, comboProduct]);
      final iRepo = FakeInventoryRepository();

      await tester.pumpWidget(_wrapWithApp(
        child: const ProductDetailPage(product: comboProduct),
        user: adminUser,
        currentStoreId: 'store_001',
        productRepo: pRepo,
        inventoryRepo: iRepo,
      ));
      await tester.pumpAndSettle();

      // Enter edit mode
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      // Informational banner should be present
      expect(
          find.text(
              'Tồn kho của Combo được tự động tính theo số lượng linh kiện thành phần.'),
          findsOneWidget);

      // Stock field should NOT be rendered
      expect(find.widgetWithText(TextFormField, 'Tồn kho'), findsNothing);

      // Save changes
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      // No inventory audit transaction emitted for combo
      expect(iRepo.transactions.isEmpty, isTrue);
    });

    // =========================================================================
    // Test 14: F1 + F7: InventoryTransactionModel roundtrip with structured audit fields
    // =========================================================================
    test(
        'T3-14 [F1+F7]: InventoryTransactionModel serialization and deserialization preserves all structured audit and store partition fields',
        () {
      final now = DateTime(2024, 12, 1, 10, 30);
      final model = InventoryTransactionModel(
        id: 'tx_audit_struct_01',
        productId: 'prod_struct_01',
        type: 'INVENTORY_AUDIT',
        quantity: 12,
        date: now,
        note: 'Cân bằng kho trực tiếp (Tồn cũ: 20 -> Tồn mới: 8, chênh lệch: -12)',
        importPrice: 45000,
        createdBy: 'admin_01',
        createdByName: 'Admin Supervisor',
      );

      final map = model.toMap();
      expect(map['id'], equals('tx_audit_struct_01'));
      expect(map['productId'], equals('prod_struct_01'));
      expect(map['type'], equals('INVENTORY_AUDIT'));
      expect(map['quantity'], equals(12));
      expect(map['importPrice'], equals(45000));
      expect(map['createdBy'], equals('admin_01'));

      final restored = InventoryTransactionModel.fromMap(map);
      expect(restored.id, equals(model.id));
      expect(restored.productId, equals(model.productId));
      expect(restored.toTransactionType(), equals(TransactionType.inventoryAudit));
      expect(restored.quantity, equals(12));
      expect(restored.importPrice, equals(45000));
    });

    // =========================================================================
    // Test 15: F1 + F2 + F3: 3-branch enterprise network maintains exact badge formatting and table parity
    // =========================================================================
    testWidgets(
        'T3-15 [F1+F2+F3]: 3-branch retail network displays dynamic short badges and full breakdown table matching all branches',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const enterpriseProduct = Product(
        id: 'p_ent_01',
        name: 'Thùng Bia Tiger Crystal 24 Lon',
        code: 'TIG24',
        price: 395000,
        costPrice: 320000,
        branchStocks: {
          'store_001': 25,
          'store_002': 15,
          'store_003': 10,
        },
        category: 'Đồ uống',
      );

      final branches = [
        const Branch('store_001', 'Chi nhánh Đông Thắng'),
        const Branch('store_002', 'Chi nhánh Thới Bình'),
        const Branch('store_003', 'Chi nhánh Cần Thơ'),
      ];

      // 1. ProductTile Badge Formatting
      await tester.pumpWidget(_wrapWithApp(
        child: const Scaffold(body: ProductTile(product: enterpriseProduct)),
        user: adminUser,
        currentStoreId: 'store_001',
        branches: branches,
      ));
      await tester.pumpAndSettle();

      expect(find.text('ĐT: 25 | TB: 15 | CN3: 10'), findsOneWidget);
      expect(find.text('Tồn: 50'), findsOneWidget);

      // 2. ProductDetailPage Table Parity
      await tester.pumpWidget(_wrapWithApp(
        child: const ProductDetailPage(product: enterpriseProduct),
        user: adminUser,
        currentStoreId: 'store_001',
        branches: branches,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('Chi nhánh Cần Thơ'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('Tổng: 50'), findsOneWidget);
    });
  });
}
